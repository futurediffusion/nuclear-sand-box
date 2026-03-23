extends RefCounted
class_name TavernPresenceMonitor

## Observa actores cercanos a la taberna y emite incidentes de presencia/loitering
## via report_tavern_incident() cuando el tiempo en zona supera los thresholds.
##
## Responsabilidad ÚNICA: detectar presión social/territorial antes de violencia.
## No toma decisiones institucionales — eso es de TavernAuthorityPolicy.
## No mueve sentinels — eso es de TavernSanctionDirector.
##
## Zonas (concéntricas, basadas en get_tavern_inner_bounds_world):
##   INTERIOR  — dentro de la taberna
##   GROUNDS   — anillo de ~48px alrededor del interior (zona de puerta)
##   PERIMETER — anillo de ~128px (perímetro exterior corto)
##
## Clasificación de actor (Fase 5):
##   player   — en grupo "player"
##   bandit   — en grupo "enemy"
##   civilian — en grupo "npc" o "civilian" (preparado para Fase 6+)
##   unknown  — ninguno de los anteriores
##
## Presión exterior dinámica (Fase 5):
##   BanditTerritoryQuery.is_in_territory(tavern_center) → _pressure_mult
##   Si hay campamento bandit cercano: thresholds reducidos → respuesta más rápida
##
## Anti-spam:
##   - Evalúa a cadencia de 0.4s
##   - Cooldown de 25s entre emisiones del mismo actor
##   - Al emitir, resetea el timer del actor


# ── Thresholds base ───────────────────────────────────────────────────────────

## Segundos en interior antes de trespass (enemy/bandit — debería no estar aquí)
const INTERIOR_BANDIT_SEC:   float = 2.5
## Segundos en interior para player en zona restringida post-warning
const INTERIOR_PLAYER_SEC:   float = 12.0
## Civilians más tolerados que player (pueden ser NPCs que visitan)
const INTERIOR_CIVILIAN_SEC: float = 20.0

## Segundos en zona de puerta para bandit antes de loitering
const DOOR_BANDIT_SEC:       float = 5.0
## Segundos en zona de puerta para player/civilian
const DOOR_PLAYER_SEC:       float = 15.0

## Segundos en perímetro para bandit antes de suspicious_presence
const PERIMETER_BANDIT_SEC:  float = 8.0
## Players y civilians en perímetro: espacio público — no se reportan

## Cooldown mínimo entre reportes del mismo actor
const EMIT_COOLDOWN_SEC:     float = 25.0

## Expansión del interior Rect2 para definir la zona de puerta
const DOOR_GROW_PX:   float = 48.0
## Expansión adicional para el perímetro exterior corto
const PERIM_GROW_PX:  float = 128.0

## Factor de presión aplicado a thresholds según postura defensiva / presencia bandit.
##
## NORM     (1.00) — sin presión; thresholds base
## HIGH     (0.65) — campamento cercano o postura GUARDED; 35% más estrictos
## FORTIFIED(0.45) — postura FORTIFIED; 55% más estrictos; respuesta muy rápida
const PRESSURE_MULT_FORTIFIED: float = 0.45
const PRESSURE_MULT_HIGH:      float = 0.65
const PRESSURE_MULT_NORM:      float = 1.0


# ── Cadencia ──────────────────────────────────────────────────────────────────

const _EVAL_INTERVAL: float = 0.4
var _eval_accum: float = 0.0


# ── Callables ────────────────────────────────────────────────────────────────

## report_tavern_incident(type: String, payload: Dictionary)
var _incident_reporter: Callable = Callable()
## Devuelve Array[Node2D] de actores a monitorear
var _get_candidates:    Callable = Callable()
## Devuelve Rect2 del interior de la taberna
var _interior_bounds:   Callable = Callable()


# ── Estado interno ────────────────────────────────────────────────────────────

## Tracking por actor_id.
## Cada entrada: {
##   "node"        : Node2D,
##   "zone"        : String,
##   "time_in_zone": float,
##   "last_emit"   : float,
##   "emit_count"  : int,
##   "actor_kind"  : String — "player" | "bandit" | "civilian" | "unknown"
## }
var _tracked: Dictionary = {}

## Multiplicador de thresholds según presión exterior actual.
## Actualizado cada ciclo de evaluación via BanditTerritoryQuery.
var _pressure_mult: float = PRESSURE_MULT_NORM

## Postura defensiva actual del recinto. Propagada por world.gd cada ~10s.
## Sobreescribe el efecto de BanditTerritoryQuery cuando está en GUARDED/FORTIFIED.
var _defense_posture: int = TavernDefensePosture.NORMAL


# ── Pública ───────────────────────────────────────────────────────────────────

func setup(ctx: Dictionary) -> void:
	_incident_reporter = ctx.get("incident_reporter", Callable())
	_get_candidates    = ctx.get("get_candidates",    Callable())
	_interior_bounds   = ctx.get("interior_bounds",   Callable())


## Propagado desde world.gd cada ~10s al cambiar la postura del recinto.
func set_defense_posture(posture: int) -> void:
	_defense_posture = posture


## Llamar desde world._process(delta). Evalúa a cadencia reducida.
func tick(delta: float) -> void:
	if not _incident_reporter.is_valid() or not _get_candidates.is_valid():
		return
	_eval_accum += delta
	if _eval_accum < _EVAL_INTERVAL:
		return
	var real_dt: float = _eval_accum
	_eval_accum = 0.0
	_evaluate(real_dt)


# ── Evaluación ────────────────────────────────────────────────────────────────

func _evaluate(dt: float) -> void:
	var interior: Rect2   = _interior_bounds.call()  if _interior_bounds.is_valid() else Rect2()
	var door_rect: Rect2  = interior.grow(DOOR_GROW_PX)
	var perim_rect: Rect2 = interior.grow(PERIM_GROW_PX)
	var now: float        = Time.get_ticks_msec() / 1000.0
	var candidates: Array = _get_candidates.call()
	var seen: Dictionary  = {}

	# Actualizar presión exterior una vez por ciclo
	_update_pressure(interior)

	for actor: Variant in candidates:
		if actor == null or not is_instance_valid(actor) or not actor is Node2D:
			continue
		var actor_id: String = (actor as Node).name
		seen[actor_id] = true

		var pos: Vector2 = (actor as Node2D).global_position
		var zone: String = _classify_zone(pos, interior, door_rect, perim_rect)

		if zone.is_empty():
			_tracked.erase(actor_id)
			continue

		var entry: Dictionary
		if _tracked.has(actor_id):
			entry = _tracked[actor_id]
		else:
			entry = {
				"node":         actor,
				"zone":         zone,
				"time_in_zone": 0.0,
				"last_emit":    0.0,
				"emit_count":   0,
				"actor_kind":   _classify_actor_kind(actor as Node),
			}
			_tracked[actor_id] = entry

		if entry["zone"] != zone:
			entry["zone"]         = zone
			entry["time_in_zone"] = 0.0

		entry["time_in_zone"] = (entry["time_in_zone"] as float) + dt
		entry["node"]         = actor

		_maybe_emit(entry, now)

	for actor_id: String in _tracked.keys():
		if not seen.has(actor_id):
			_tracked.erase(actor_id)


## Determina el tipo de actor para aplicar thresholds diferenciados.
##
## Fase 5: player / bandit / civilian / unknown.
## Fase 6+: expandir "civilian" con distinción de NPCs específicos
##          (visitante, mercader, residente) cuando haya IA civil real.
func _classify_actor_kind(actor: Node) -> String:
	if actor.is_in_group("player"):
		return "player"
	if actor.is_in_group("enemy"):
		return "bandit"
	# Preparado para civiles NPC — grupos reconocidos como no hostiles
	if actor.is_in_group("npc") or actor.is_in_group("civilian"):
		return "civilian"
	return "unknown"


## Actualiza _pressure_mult según postura defensiva y presencia territorial bandit.
##
## La postura (propagada por world.gd) tiene prioridad sobre BanditTerritoryQuery:
##   FORTIFIED → mult mínimo (0.45) — recinto bajo ataque sostenido
##   GUARDED   → mult alto (0.65) — presencia hostil detectada
##   NORMAL    → depende de BanditTerritoryQuery (0.65 si hay camp, 1.0 si no)
func _update_pressure(interior: Rect2) -> void:
	if interior.size == Vector2.ZERO:
		_pressure_mult = PRESSURE_MULT_NORM
		return
	match _defense_posture:
		TavernDefensePosture.FORTIFIED:
			_pressure_mult = PRESSURE_MULT_FORTIFIED
		TavernDefensePosture.GUARDED:
			_pressure_mult = PRESSURE_MULT_HIGH
		_:  # NORMAL — usar BanditTerritoryQuery como antes
			var tavern_center: Vector2 = interior.get_center()
			var has_nearby_camp: bool = BanditTerritoryQuery.is_in_territory(tavern_center)
			_pressure_mult = PRESSURE_MULT_HIGH if has_nearby_camp else PRESSURE_MULT_NORM


## Clasifica la posición en la zona más interior que la contenga.
func _classify_zone(
		pos: Vector2,
		interior: Rect2,
		door_rect: Rect2,
		perim_rect: Rect2,
) -> String:
	var C := LocalCivilAuthorityConstants
	if interior.size != Vector2.ZERO and interior.has_point(pos):
		return C.ZONE_TAVERN_INTERIOR
	if door_rect.size != Vector2.ZERO and door_rect.has_point(pos):
		return C.ZONE_TAVERN_GROUNDS
	if perim_rect.size != Vector2.ZERO and perim_rect.has_point(pos):
		return C.ZONE_TAVERN_PERIMETER
	return ""


## Evalúa si la entrada merece emitir un incidente ahora.
func _maybe_emit(entry: Dictionary, now: float) -> void:
	var C := LocalCivilAuthorityConstants

	var actor_kind: String = entry["actor_kind"]
	var zone:       String = entry["zone"]
	var time:       float  = entry["time_in_zone"]

	var last_emit: float = entry["last_emit"]
	if last_emit > 0.0 and (now - last_emit) < EMIT_COOLDOWN_SEC:
		return

	var incident_type: String = ""
	var threshold:     float  = INF

	match zone:
		C.ZONE_TAVERN_INTERIOR:
			match actor_kind:
				"bandit":
					# Bandit en interior: presencia ilegítima — respuesta rápida.
					# _pressure_mult reduce el threshold si hay campo cercano.
					threshold     = INTERIOR_BANDIT_SEC * _pressure_mult
					incident_type = "trespass"
				"player":
					threshold     = INTERIOR_PLAYER_SEC
					incident_type = "trespass"
				"civilian":
					# Civiles: más margen (pueden ser visitantes legítimos).
					# TODO(Fase 6): distinguir entre civiles de confianza y desconocidos.
					threshold     = INTERIOR_CIVILIAN_SEC
					incident_type = "trespass"
				# "unknown": no reportar (evitar falsos positivos con props animados, etc.)

		C.ZONE_TAVERN_GROUNDS:
			match actor_kind:
				"bandit":
					threshold     = DOOR_BANDIT_SEC * _pressure_mult
					incident_type = "loitering"
				"player", "civilian":
					threshold     = DOOR_PLAYER_SEC
					incident_type = "loitering"
				# "unknown": no reportar

		C.ZONE_TAVERN_PERIMETER:
			match actor_kind:
				"bandit":
					# Presión exterior alta → threshold más bajo (reacciona antes).
					threshold     = PERIMETER_BANDIT_SEC * _pressure_mult
					incident_type = "suspicious_presence"
				# Players, civilians, unknown: perímetro es espacio público — no reportar.

	if incident_type.is_empty() or time < threshold:
		return

	entry["last_emit"]    = now
	entry["emit_count"]   = (entry["emit_count"] as int) + 1
	entry["time_in_zone"] = 0.0

	var actor_node: Node2D = entry.get("node") as Node2D
	var actor_pos: Vector2 = actor_node.global_position \
		if (actor_node != null and is_instance_valid(actor_node)) \
		else Vector2.ZERO

	_incident_reporter.call(incident_type, {
		"offender": actor_node,
		"pos":      actor_pos,
	})
