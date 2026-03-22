extends RefCounted
class_name LocalCivilIncident

# ── LocalCivilIncident ────────────────────────────────────────────────────────
# Registro de un único evento civil/institucional dentro de la jurisdicción
# de una autoridad local.
#
# INTENCIÓN DE DISEÑO — LEER ANTES DE MODIFICAR:
#
#   Este es un REGISTRO DE DATOS PURO. No tiene señales, no tiene side effects,
#   no referencia nodos ni managers. Puede crearse, pasarse, serializarse y
#   almacenarse sin tocar ningún sistema vivo.
#
# POR QUÉ NO ES FactionHostilityData:
#   FactionHostilityData rastrea heat/puntos acumulados de una facción enemiga
#   contra el jugador a lo largo del tiempo — es un marcador de reputación.
#   LocalCivilIncident es un reporte de evento único — más parecido a un acta
#   policial que a un nivel de hostilidad. TavernLocalMemory (futuro) agregará
#   incidentes; este registro es lo que agregará.
#
# CONEXIONES FUTURAS (no implementadas aquí):
#   TavernLocalMemory     → almacena lista de LocalCivilIncidents por actor
#   TavernAuthorityPolicy → lee incidentes para decidir severidad de respuesta
#   TavernSanctionDirector→ lee la decisión de policy, emite sanciones concretas
#   Sentinels/Responders  → reciben acciones sancionadas y las ejecutan en mundo
#
# QUÉ NO RESUELVE TODAVÍA:
#   - No persiste por sí solo (eso es trabajo de TavernLocalMemory)
#   - No dispara ninguna reacción al crearse
#   - No tiene cooldowns ni deduplicación por actor
#   - No conoce a los sentinels ni a la policy

# ── Campos requeridos ─────────────────────────────────────────────────────────

## Identifica qué autoridad local posee este incidente.
## e.g. "tavern_main", "village_north". String estable, no ref de nodo.
## DEBE ser no vacío; incidentes sin autoridad no tienen jurisdicción.
var local_authority_id: String = ""

## Actor que cometió la ofensa. Puede ser el jugador o cualquier NPC.
## El string vacío está permitido si el infractor es desconocido
## (p.ej. propiedad dañada sin testigos). La policy debe manejar
## explícitamente el caso unknown_offender.
var offender_actor_id: String = ""

## Tipo de ofensa. Usar LocalCivilAuthorityConstants.Offense.*.
## No usar strings literales directamente en los llamadores.
var offense_type: String = ""

## Severidad normalizada [0.0, 1.0]. Usar constantes de severidad como referencia.
## Se fuerza al rango válido en la factory; validar si viene de save.
var severity: float = 0.0

## Posición mundo donde ocurrió el incidente.
var position: Vector2 = Vector2.ZERO

## Día de juego (WorldTime.get_current_day()) en el momento del incidente.
## Permite a memoria y policy razonar sobre "hace cuánto" sin drift de reloj real.
var day: int = 0

## IDs de actores que observaron el incidente. Array de strings de actor_id.
## Array vacío = sin testigos. Los testigos pueden afectar el peso de la respuesta.
var witnesses: Array[String] = []

## Categoría de quién fue dañado. Usar LocalCivilAuthorityConstants.VictimKind.*.
var victim_kind: String = LocalCivilAuthorityConstants.VictimKind.UNKNOWN

## Sub-zona dentro del territorio de la autoridad.
## Default "unknown" es válido si el llamador no rastrea zonas todavía.
var zone_id: String = LocalCivilAuthorityConstants.ZONE_UNKNOWN

# ── Campos auto-generados ─────────────────────────────────────────────────────

## ID único para este incidente. Generado por la factory; estable en serialización.
var incident_id: String = ""

## Segundos de RunClock.now() en el momento de creación.
## Útil para deduplicación dentro de una sesión u ordenar incidentes del mismo día.
var created_at_run_time: float = 0.0

## Tag que identifica el sistema/nodo que emitió este incidente.
## Para debug y trazabilidad sin acoplamiento directo.
## e.g. "player_combat_handler", "trap_trigger", "tavern_door_script"
var source_tag: String = ""

## Slot de extensión libre. Mantener pequeño.
## Si un campo aparece en todos los incidentes, promoverlo a campo nombrado.
var metadata: Dictionary = {}


# ── Validación ────────────────────────────────────────────────────────────────

## Devuelve true si el incidente tiene los campos mínimos para ser accionable.
## No valida que offense_type sea un tipo conocido — eso es trabajo de la policy.
func is_valid() -> bool:
	return not local_authority_id.is_empty() and not offense_type.is_empty()


## Lista de errores de validación legibles. Útil para logs de debug.
func validation_errors() -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if local_authority_id.is_empty():
		errs.append("local_authority_id vacío — incidente sin jurisdicción")
	if offense_type.is_empty():
		errs.append("offense_type vacío — tipo de ofensa indefinido")
	if severity < 0.0 or severity > 1.0:
		errs.append("severity %.2f fuera de rango [0.0, 1.0]" % severity)
	if incident_id.is_empty():
		errs.append("incident_id vacío — incidente sin identificador")
	return errs


# ── Serialización ─────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"incident_id":          incident_id,
		"local_authority_id":   local_authority_id,
		"offender_actor_id":    offender_actor_id,
		"offense_type":         offense_type,
		"severity":             severity,
		"position":             { "x": position.x, "y": position.y },
		"day":                  day,
		"witnesses":            witnesses.duplicate(),
		"victim_kind":          victim_kind,
		"zone_id":              zone_id,
		"created_at_run_time":  created_at_run_time,
		"source_tag":           source_tag,
		"metadata":             metadata.duplicate(),
	}


static func from_dict(d: Dictionary) -> LocalCivilIncident:
	var inc := LocalCivilIncident.new()
	inc.incident_id         = str(d.get("incident_id",        ""))
	inc.local_authority_id  = str(d.get("local_authority_id", ""))
	inc.offender_actor_id   = str(d.get("offender_actor_id",  ""))
	inc.offense_type        = str(d.get("offense_type",       ""))
	inc.severity            = clampf(float(d.get("severity",  0.0)), 0.0, 1.0)
	var raw_pos: Variant    = d.get("position", null)
	if raw_pos is Dictionary:
		inc.position = Vector2(float(raw_pos.get("x", 0.0)), float(raw_pos.get("y", 0.0)))
	inc.day                 = int(d.get("day",               0))
	inc.victim_kind         = str(d.get("victim_kind",
		LocalCivilAuthorityConstants.VictimKind.UNKNOWN))
	inc.zone_id             = str(d.get("zone_id",
		LocalCivilAuthorityConstants.ZONE_UNKNOWN))
	inc.created_at_run_time = float(d.get("created_at_run_time", 0.0))
	inc.source_tag          = str(d.get("source_tag",        ""))
	var raw_witnesses: Variant = d.get("witnesses", null)
	if raw_witnesses is Array:
		for w: Variant in raw_witnesses:
			inc.witnesses.append(str(w))
	var raw_meta: Variant = d.get("metadata", null)
	if raw_meta is Dictionary:
		inc.metadata = raw_meta.duplicate()
	return inc
