extends RefCounted
class_name TavernLocalMemory

## Memoria institucional de la taberna.
##
## Mantiene un OffenderRecord por actor_id con métricas finas:
##   - tipo de ofensas vistas, violencia, daño a autoridad, daño a propiedad
##   - gravedad máxima, reincidencia, última ofensa (día + tiempo de sesión)
##   - estado de deny_service (fuente de verdad para el keeper)
##
## La policy DEBE consultar esta memoria ANTES de que se registre el incidente
## actual (para ver solo el historial previo).
##
## Fase 2: sesión únicamente. Fase 3: serializar en WorldSave.

const MAX_ENTRIES: int = 128


## Perfil institucional acumulado por actor.
class OffenderRecord extends RefCounted:
	var actor_id: String = ""

	## Número total de incidentes registrados.
	var incident_count: int = 0
	## Incidentes violentos (ASSAULT, MURDER).
	var violence_count: int = 0
	## Incidentes cuya víctima era miembro de la autoridad (keeper, sentinel).
	var authority_assault_count: int = 0
	## Incidentes de daño a propiedad (VANDALISM, TRESPASS).
	var property_damage_count: int = 0
	## Gravedad máxima registrada (0.0–1.0).
	var max_severity_seen: float = 0.0
	## Gravedad del incidente más reciente.
	var last_severity: float = 0.0
	## Día de juego de la última ofensa.
	var last_offense_day: int = 0
	## Tiempo de sesión (RunClock) de la última ofensa.
	var last_offense_run_time: float = 0.0
	## Tipos de ofensa observados (sin duplicados).
	var offense_types_seen: PackedStringArray = PackedStringArray()
	## true si el actor ha sido baneado del servicio.
	var service_denied: bool = false

	func to_dict() -> Dictionary:
		return {
			"actor_id":                actor_id,
			"incident_count":          incident_count,
			"violence_count":          violence_count,
			"authority_assault_count": authority_assault_count,
			"property_damage_count":   property_damage_count,
			"max_severity_seen":       max_severity_seen,
			"last_severity":           last_severity,
			"last_offense_day":        last_offense_day,
			"last_offense_run_time":   last_offense_run_time,
			"offense_types_seen":      Array(offense_types_seen),
			"service_denied":          service_denied,
		}


## Registro cronológico (como dicts, para serialización futura).
var _entries: Array[Dictionary] = []
## Perfiles por actor_id.
var _offender_records: Dictionary = {}  # String → OffenderRecord


## Registra el incidente y actualiza el perfil del ofensor.
## Llamar DESPUÉS de que TavernAuthorityPolicy haya evaluado (para que policy
## vea solo el historial previo y no el incidente actual).
func record(incident: LocalCivilIncident) -> void:
	_entries.append(incident.to_dict())
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()

	if incident.offender_actor_id.is_empty():
		return

	var C   := LocalCivilAuthorityConstants
	var rec := _get_or_create(incident.offender_actor_id)

	rec.incident_count   += 1
	rec.last_severity     = incident.severity
	rec.max_severity_seen = maxf(rec.max_severity_seen, incident.severity)
	rec.last_offense_day      = incident.day
	rec.last_offense_run_time = incident.created_at_run_time

	if not rec.offense_types_seen.has(incident.offense_type):
		rec.offense_types_seen.append(incident.offense_type)

	if incident.offense_type in [C.Offense.ASSAULT, C.Offense.MURDER]:
		rec.violence_count += 1

	if incident.victim_kind == C.VictimKind.AUTHORITY_MEMBER:
		rec.authority_assault_count += 1

	if incident.offense_type in [C.Offense.VANDALISM, C.Offense.TRESPASS]:
		rec.property_damage_count += 1


## Devuelve el perfil previo al actor (null si es primera vez).
func get_offender_record(actor_id: String) -> OffenderRecord:
	return _offender_records.get(actor_id, null) as OffenderRecord


## Número de incidentes registrados para un actor.
func get_offender_count(actor_id: String) -> int:
	var rec: OffenderRecord = _offender_records.get(actor_id, null)
	return rec.incident_count if rec != null else 0


## Marca al actor como baneado del servicio.
## Fuente de verdad — el keeper consulta aquí en lugar de mantener su propio set.
func deny_service_for(actor_id: String) -> void:
	if actor_id.is_empty():
		return
	_get_or_create(actor_id).service_denied = true
	Debug.log("authority", "[MEMORY] deny_service registrado actor_id=%s" % actor_id)


## true si el actor fue baneado del servicio en esta sesión.
func is_service_denied(actor_id: String) -> bool:
	var rec: OffenderRecord = _offender_records.get(actor_id, null)
	return rec != null and rec.service_denied


## Nivel de tensión institucional basado en incidentes recientes.
##
## Devuelve un float 0.0 – 3.0:
##   0.0 – 1.0  calma    (pocos o ningún incidente reciente)
##   1.0 – 2.0  tensa    (presencia sospechosa/loitering acumulado)
##   2.0 – 3.0  caliente (violencia o daño reciente)
##   > 2.5      crítica  (murder, agresión a autoridad, acumulación violenta)
##
## window_sec: ventana temporal de evaluación (default 180s = 3 min de juego).
## now:        RunClock.now() — tiempo de sesión actual en segundos.
func get_tension_level(now: float, window_sec: float = 180.0) -> float:
	var C := LocalCivilAuthorityConstants
	var score: float = 0.0
	var cutoff: float = now - window_sec
	for entry: Dictionary in _entries:
		var t: float = float(entry.get("created_at_run_time", -INF))
		if t < cutoff:
			continue
		var offense: String = String(entry.get("offense_type", ""))
		var sev:     float  = float(entry.get("severity", 0.0))
		match offense:
			C.Offense.MURDER:        score += 3.0
			C.Offense.ASSAULT:       score += 1.5 * sev
			C.Offense.WEAPON_THREAT: score += 2.0 * sev
			C.Offense.VANDALISM:     score += 1.0 * sev
			C.Offense.TRESPASS:      score += 0.3
			C.Offense.DISTURBANCE:   score += 0.2
	return clampf(score, 0.0, 3.0)


## Snapshot estructurado para el port callable de LocalSocialAuthorityPorts.
func get_snapshot(scope_id: String, _payload: Dictionary = {}) -> Dictionary:
	var offender_dicts: Dictionary = {}
	for actor_id: String in _offender_records:
		offender_dicts[actor_id] = (_offender_records[actor_id] as OffenderRecord).to_dict()
	return {
		"scope_id":      scope_id,
		"entry_count":   _entries.size(),
		"offenders":     offender_dicts,
	}


func _get_or_create(actor_id: String) -> OffenderRecord:
	if not _offender_records.has(actor_id):
		var rec := OffenderRecord.new()
		rec.actor_id = actor_id
		_offender_records[actor_id] = rec
	return _offender_records[actor_id] as OffenderRecord
