extends RefCounted
class_name TavernAuthorityPolicy

## Política institucional de la taberna — traduce incidente + historial → directiva.
##
## La policy recibe:
##   1. El incidente actual  (qué pasó, quién, cuánto)
##   2. El historial previo del ofensor (TavernLocalMemory)
##
## Flujo de evaluación en dos pasos:
##   a) base_directive  = LocalAuthorityEventFeed.evaluate(incident)
##                        (respuesta naïve basada solo en este incidente)
##   b) escalated       = _apply_memory_escalation(base, profile)
##                        (endurecimiento progresivo por historial)
##
## Reglas de escalación (en orden de prioridad):
##   1. Agresión previa a autoridad → siempre ARREST_OR_SUBDUE
##   2. Violencia reiterada (≥2 incidentes) → mínimo CALL_BACKUP
##   3. Reincidencia general (≥3 incidentes) → escalar un nivel
##   Sin historial previo → devuelve base_directive sin cambios.
##
## IMPORTANTE: la policy evalúa el historial ANTES de que el incidente actual
## sea registrado en memoria (responsabilidad del coordinador — world.gd).

var _memory: TavernLocalMemory = null


func setup(ctx: Dictionary) -> void:
	_memory = ctx.get("memory", null)


## Evalúa el incidente con contexto histórico. Nunca devuelve null.
func evaluate(incident: LocalCivilIncident) -> LocalAuthorityDirective:
	var base := LocalAuthorityEventFeed.evaluate(incident)

	if _memory == null or incident.offender_actor_id.is_empty():
		return base

	var rec := _memory.get_offender_record(incident.offender_actor_id)
	if rec == null:
		# Primera vez — sin historial, la respuesta base es correcta.
		return base

	return _apply_memory_escalation(base, incident, rec)


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
	# La institución no negocia con quien ya agredió a sus representantes.
	if rec.authority_assault_count > 0:
		if current in [R.WARN, R.DENY_SERVICE, R.EJECT, R.CALL_BACKUP]:
			target = R.ARREST_OR_SUBDUE

	# Regla 2 — Violencia reiterada (≥2 incidentes violentos previos).
	# Alguien que repite violencia no recibe solo advertencias.
	elif rec.violence_count >= 2:
		if current in [R.WARN, R.DENY_SERVICE]:
			target = R.EJECT
		elif current == R.EJECT:
			target = R.CALL_BACKUP

	# Regla 3 — Reincidencia general (≥3 incidentes de cualquier tipo).
	# La acumulación de infracciones menores merece endurecimiento progresivo.
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


## Sube un nivel en la escala de respuestas.
func _escalate_one(response: String) -> String:
	var R := LocalAuthorityResponse.Response
	match response:
		R.RECORD_ONLY:  return R.WARN
		R.WARN:         return R.EJECT
		R.DENY_SERVICE: return R.EJECT
		R.EJECT:        return R.CALL_BACKUP
		R.CALL_BACKUP:  return R.ARREST_OR_SUBDUE
		_:              return response  # ARREST_OR_SUBDUE: techo, no escala más


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
