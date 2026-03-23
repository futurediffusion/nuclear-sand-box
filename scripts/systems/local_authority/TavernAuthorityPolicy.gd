extends RefCounted
class_name TavernAuthorityPolicy

## Política institucional de la taberna — traduce incidente + historial → directiva.
##
## La policy recibe:
##   1. El incidente actual  (qué pasó, quién, cuánto)
##   2. El historial previo del ofensor (TavernLocalMemory)
##   3. El nivel de tensión institucional actual (TavernLocalMemory.get_tension_level)
##
## Flujo de evaluación:
##   a) base_directive = LocalAuthorityEventFeed.evaluate(incident)
##   b) escalated      = _apply_memory_escalation(base, rec)
##   c) contextualized = _apply_tension_modifier(escalated, incident, rec, tension)
##
## Reglas de escalación por historial (prioridad decreciente):
##   1. Agresión previa a autoridad → siempre ARREST_OR_SUBDUE
##   2. Violencia reiterada (≥2 incidentes) → mínimo CALL_BACKUP
##   3. Reincidencia general (≥3 incidentes) → escalar un nivel
##
## Regla 4 — Tensión institucional (contextual, Fase 5):
##   LOW  (<1.0): incidente de presencia no violento, primera visita → RECORD_ONLY
##               (la taberna tolera en paz — paz tensa favorable)
##   HIGH (≥2.0): actor con historial hostil → escalar un nivel adicional
##               (institución en alerta máxima — paz tensa rota)
##
## IMPORTANTE: la policy evalúa el historial ANTES de que el incidente actual
## sea registrado en memoria (responsabilidad del coordinador — world.gd).

var _memory: TavernLocalMemory = null


func setup(ctx: Dictionary) -> void:
	_memory = ctx.get("memory", null)


## Evalúa el incidente con contexto histórico y tensión. Nunca devuelve null.
func evaluate(incident: LocalCivilIncident) -> LocalAuthorityDirective:
	var base := LocalAuthorityEventFeed.evaluate(incident)

	if _memory == null or incident.offender_actor_id.is_empty():
		return base

	var rec := _memory.get_offender_record(incident.offender_actor_id)

	# Primer incidente: sin historial, solo aplicar modificador de tensión.
	if rec == null:
		var tension: float = _memory.get_tension_level(RunClock.now())
		if tension < 1.0:
			return base  # calma institucional — respetar respuesta base
		# Tensión >1.0 incluso sin historial personal → no suavizar
		return base

	# Reglas 1-3 por historial
	var escalated := _apply_memory_escalation(base, incident, rec)

	# Regla 4: modificador de tensión (afina el resultado)
	var tension: float = _memory.get_tension_level(RunClock.now())
	var final_response := _apply_tension_modifier(
		escalated.response_type, incident, rec, tension
	)

	if final_response == escalated.response_type:
		return escalated

	return _reclone(escalated, final_response,
		" [tensión: %.1f→%s]" % [tension, final_response]
	)


# ── Escalación por historial ───────────────────────────────────────────────────

func _apply_memory_escalation(
		base: LocalAuthorityDirective,
		_incident: LocalCivilIncident,
		rec: TavernLocalMemory.OffenderRecord,
) -> LocalAuthorityDirective:
	var R       := LocalAuthorityResponse.Response
	var current := base.response_type
	var target  := current

	# Regla 1 — Agresión previa a miembro de autoridad.
	if rec.authority_assault_count > 0:
		if current in [R.WARN, R.DENY_SERVICE, R.EJECT, R.CALL_BACKUP]:
			target = R.ARREST_OR_SUBDUE

	# Regla 2 — Violencia reiterada (≥2 incidentes violentos previos).
	elif rec.violence_count >= 2:
		if current in [R.WARN, R.DENY_SERVICE]:
			target = R.EJECT
		elif current == R.EJECT:
			target = R.CALL_BACKUP

	# Regla 3 — Reincidencia general (≥3 incidentes de cualquier tipo).
	elif rec.incident_count >= 3:
		target = _escalate_one(current)

	if target == current:
		return base

	return _reclone(base, target,
		" [historial: %s→%s viols=%d auth=%d n=%d]" % [
			current, target,
			rec.violence_count,
			rec.authority_assault_count,
			rec.incident_count,
		]
	)


# ── Regla 4: Tensión institucional ────────────────────────────────────────────

## Modifica la respuesta según el clima institucional reciente.
##
## PAZ TENSA FAVORABLE (tension < 1.0):
##   Un actor sin historial violento que hace un incidente menor de presencia
##   (trespass/disturbance) en un momento de calma → solo registrar, no actuar.
##   La taberna tolera la presencia incierta cuando no hay tensión acumulada.
##
## CLIMA CALIENTE (tension ≥ 2.0):
##   Actor con historial hostil (violencia o weapon_threat previos) → escalar un nivel.
##   La institución ya no da margen cuando el ambiente está deteriorado.
func _apply_tension_modifier(
		current: String,
		incident: LocalCivilIncident,
		rec: TavernLocalMemory.OffenderRecord,
		tension: float,
) -> String:
	var R := LocalAuthorityResponse.Response
	var C := LocalCivilAuthorityConstants

	# Calma institucional: primer incidente de presencia no violento → reducir a RECORD_ONLY
	if tension < 1.0 and current == R.WARN:
		var is_presence_incident: bool = incident.offense_type in [
			C.Offense.DISTURBANCE, C.Offense.TRESPASS
		]
		var has_no_violence: bool = rec.violence_count == 0 and rec.authority_assault_count == 0
		if is_presence_incident and has_no_violence and rec.incident_count <= 1:
			return R.RECORD_ONLY

	# Clima caliente: actor con historial hostil → un nivel extra de escalación
	if tension >= 2.0 and current in [R.WARN, R.EJECT]:
		var is_likely_hostile: bool = (
			rec.violence_count > 0
			or C.Offense.WEAPON_THREAT in Array(rec.offense_types_seen)
		)
		if is_likely_hostile:
			return _escalate_one(current)

	return current


# ── Helpers ───────────────────────────────────────────────────────────────────

## Sube un nivel en la escala de respuestas.
func _escalate_one(response: String) -> String:
	var R := LocalAuthorityResponse.Response
	match response:
		R.RECORD_ONLY:  return R.WARN
		R.WARN:         return R.EJECT
		R.DENY_SERVICE: return R.EJECT
		R.EJECT:        return R.CALL_BACKUP
		R.CALL_BACKUP:  return R.ARREST_OR_SUBDUE
		_:              return response  # ARREST_OR_SUBDUE: techo


## Construye una nueva directiva idéntica a base pero con response_type diferente.
func _reclone(
		base: LocalAuthorityDirective,
		new_response: String,
		note_suffix: String,
) -> LocalAuthorityDirective:
	var d := LocalAuthorityDirective.new()
	d.local_authority_id      = base.local_authority_id
	d.incident_id             = base.incident_id
	d.offender_actor_id       = base.offender_actor_id
	d.zone_id                 = base.zone_id
	d.response_type           = new_response
	d.severity_band           = base.severity_band
	d.requires_responder      = LocalAuthorityResponse.Response.is_active_response(new_response)
	d.should_record           = true
	d.suggests_zone_lockdown  = base.suggests_zone_lockdown
	d.notes                   = base.notes + note_suffix
	return d
