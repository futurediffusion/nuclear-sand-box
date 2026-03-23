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
## Incidentes emitidos:
##   trespass            — actor en interior por demasiado tiempo (enemy rápido, player lento)
##   loitering           — actor en zona de puerta sin moverse
##   suspicious_presence — bandit/enemy merodeando el perímetro exterior
##
## Anti-spam:
##   - Evalúa a cadencia de 0.4s (no cada frame)
##   - Cooldown de 25s entre emisiones del mismo actor
##   - Al emitir, resetea el timer del actor (re-evalúa desde cero)


# ── Thresholds ────────────────────────────────────────────────────────────────

## Segundos en interior antes de emitir trespass (enemy es rápido — ya no debería estar aquí)
const INTERIOR_ENEMY_SEC:  float = 2.5
## Segundos en interior para un player en zona restringida post-warning
const INTERIOR_PLAYER_SEC: float = 12.0
## Segundos en zona de puerta/grounds para enemy antes de loitering
const DOOR_ENEMY_SEC:      float = 5.0
## Segundos en zona de puerta para player (más tolerado — puede estar comprando)
const DOOR_PLAYER_SEC:     float = 15.0
## Segundos en perímetro exterior para enemy antes de suspicious_presence
const PERIMETER_ENEMY_SEC: float = 8.0
## Players en perímetro: espacio público — no se monitorean

## Cooldown mínimo entre reportes del mismo actor (segundos)
const EMIT_COOLDOWN_SEC:   float = 25.0

## Expansión del Rect2 de interior para definir la zona de puerta
const DOOR_GROW_PX:  float = 48.0
## Expansión adicional para el perímetro exterior corto
const PERIM_GROW_PX: float = 128.0


# ── Cadencia ──────────────────────────────────────────────────────────────────

const _EVAL_INTERVAL: float = 0.4
var _eval_accum: float = 0.0


# ── Callables (inyectados por world.gd en setup) ──────────────────────────────

## report_tavern_incident(type: String, payload: Dictionary)
var _incident_reporter: Callable = Callable()
## Devuelve Array[Node2D] de actores a monitorear (players + enemies)
var _get_candidates:    Callable = Callable()
## Devuelve Rect2 del interior de la taberna
var _interior_bounds:   Callable = Callable()


# ── Tracking (por actor_id) ───────────────────────────────────────────────────
#
# Cada entrada es un Dictionary:
#   "node"        : Node2D  — referencia al nodo (verificar is_instance_valid)
#   "zone"        : String  — última zona clasificada
#   "time_in_zone": float   — segundos acumulados en la zona actual
#   "last_emit"   : float   — timestamp de la última emisión
#   "emit_count"  : int     — número total de veces emitido para este actor
#   "is_enemy"    : bool
#   "is_player"   : bool

var _tracked: Dictionary = {}


# ── Pública ───────────────────────────────────────────────────────────────────

func setup(ctx: Dictionary) -> void:
	_incident_reporter = ctx.get("incident_reporter", Callable())
	_get_candidates    = ctx.get("get_candidates",    Callable())
	_interior_bounds   = ctx.get("interior_bounds",   Callable())


## Llamar desde world._process(delta).
## Evalúa a cadencia reducida para no saturar frame budget.
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
	var interior: Rect2   = _interior_bounds.call()  if _interior_bounds.is_valid()  else Rect2()
	var door_rect: Rect2  = interior.grow(DOOR_GROW_PX)
	var perim_rect: Rect2 = interior.grow(PERIM_GROW_PX)
	var now: float        = Time.get_ticks_msec() / 1000.0
	var candidates: Array = _get_candidates.call()
	var seen: Dictionary  = {}

	for actor: Variant in candidates:
		if actor == null or not is_instance_valid(actor) or not actor is Node2D:
			continue
		var actor_id: String = (actor as Node).name
		seen[actor_id] = true

		var pos: Vector2   = (actor as Node2D).global_position
		var zone: String   = _classify_zone(pos, interior, door_rect, perim_rect)

		# Fuera de todas las zonas — limpiar tracking
		if zone.is_empty():
			_tracked.erase(actor_id)
			continue

		# Obtener o crear entry
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
				"is_enemy":     (actor as Node).is_in_group("enemy"),
				"is_player":    (actor as Node).is_in_group("player"),
			}
			_tracked[actor_id] = entry

		# Cambio de zona: resetear acumulador (nueva zona, nuevo juicio)
		if entry["zone"] != zone:
			entry["zone"]         = zone
			entry["time_in_zone"] = 0.0

		entry["time_in_zone"] = (entry["time_in_zone"] as float) + dt
		entry["node"]         = actor  # mantener referencia fresca

		_maybe_emit(entry, now)

	# Limpiar entradas de actores que ya no están en ninguna zona
	for actor_id: String in _tracked.keys():
		if not seen.has(actor_id):
			_tracked.erase(actor_id)


## Clasifica la posición del actor en la zona más interior que la contenga.
## Retorna "" si está fuera de las tres zonas — se descarta del tracking.
func _classify_zone(
		pos: Vector2,
		interior: Rect2,
		door_rect: Rect2,
		perim_rect: Rect2,
) -> String:
	var C := LocalCivilAuthorityConstants
	# Comprobar de interior → exterior (la más restrictiva primero)
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

	var is_enemy:  bool  = entry["is_enemy"]
	var is_player: bool  = entry["is_player"]
	var zone:      String = entry["zone"]
	var time:      float = entry["time_in_zone"]

	# Anti-spam: respetar cooldown por actor
	var last_emit: float = entry["last_emit"]
	if last_emit > 0.0 and (now - last_emit) < EMIT_COOLDOWN_SEC:
		return

	var incident_type: String = ""
	var threshold:     float  = INF

	match zone:
		C.ZONE_TAVERN_INTERIOR:
			if is_enemy:
				# Enemy en interior: presencia ilegítima — respuesta rápida
				threshold     = INTERIOR_ENEMY_SEC
				incident_type = "trespass"
			elif is_player:
				# Player en interior: tolerado más tiempo (puede ser cliente)
				# El monitor solo avisa si se queda en zona restringida post-warning.
				threshold     = INTERIOR_PLAYER_SEC
				incident_type = "trespass"

		C.ZONE_TAVERN_GROUNDS:
			# Zona de puerta — acceso permitido pero no indefinido
			if is_enemy:
				threshold     = DOOR_ENEMY_SEC
				incident_type = "loitering"
			elif is_player:
				threshold     = DOOR_PLAYER_SEC
				incident_type = "loitering"

		C.ZONE_TAVERN_PERIMETER:
			# Perímetro exterior — espacio semi-público
			# Solo enemies/bandits generan presión social aquí
			if is_enemy:
				threshold     = PERIMETER_ENEMY_SEC
				incident_type = "suspicious_presence"
			# Players en perímetro: no reportar — espacio público

	if incident_type.is_empty() or time < threshold:
		return

	# Emitir
	entry["last_emit"]    = now
	entry["emit_count"]   = (entry["emit_count"] as int) + 1
	entry["time_in_zone"] = 0.0  # resetear para re-evaluar desde cero

	var actor_node: Node2D = entry.get("node") as Node2D
	var actor_pos: Vector2 = actor_node.global_position \
		if (actor_node != null and is_instance_valid(actor_node)) \
		else Vector2.ZERO

	_incident_reporter.call(incident_type, {
		"offender": actor_node,
		"pos":      actor_pos,
	})
