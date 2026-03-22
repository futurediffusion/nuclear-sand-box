extends RefCounted
class_name LocalAuthorityEventFeed

# ── LocalAuthorityEventFeed ───────────────────────────────────────────────────
# Traductor sin estado: LocalCivilIncident → LocalAuthorityDirective.
#
# SEPARACIÓN DE RESPONSABILIDADES — LEER ANTES DE MODIFICAR:
#
#   DETECCIÓN  → quien construye el LocalCivilIncident
#                (player_attack_handler, trap_trigger, door_script, etc.)
#
#   DECISIÓN   → este archivo   ← estás aquí
#                Traduce el hecho a una respuesta institucional abstracta.
#                No ejecuta nada. No conoce sentinels. No conoce TavernKeeper.
#
#   EJECUCIÓN  → TavernSanctionDirector (futuro)
#                Lee el directive, decide cómo y quién lo ejecuta.
#
# POR QUÉ EXISTE ANTES QUE TavernAuthorityPolicy COMPLETA:
#   TavernAuthorityPolicy necesitará historial (TavernLocalMemory) y contexto
#   acumulado para tomar decisiones ricas. Ese contexto no existe todavía.
#   Este feed es el traductor inicial — deliberadamente simple y sin estado —
#   que ya permite usar el contrato de directive sin bloquear el resto de la
#   cadena. Cuando Policy exista, este feed puede ser reemplazado o llamado
#   por ella para casos básicos.
#
# POR QUÉ NO ESTÁ DENTRO DE TavernKeeper:
#   Si la lógica de decisión vive en TavernKeeper, cada nueva autoridad
#   local (village_elder, caravan_master) replica la misma sopa de ifs.
#   El feed es la capa institucional reutilizable; TavernKeeper solo orquesta.
#
# QUÉ NO RESUELVE TODAVÍA:
#   - No considera historial de incidentes previos del mismo actor
#   - No pondera número de testigos para escalar/desescalar
#   - No tiene cooldowns ni deduplicación
#   - No conoce la disponibilidad de responders
#   Esos comportamientos pertenecen a TavernAuthorityPolicy + TavernLocalMemory.
#
# USO:
#   var directive := LocalAuthorityEventFeed.evaluate(incident)
#   if directive.requires_responder:
#       # poner en cola para SanctionDirector (futuro)
#   if directive.should_record:
#       # TavernLocalMemory.record(directive)  (futuro)
#   Debug.log("civil_feed", directive.describe())


## Traduce un LocalCivilIncident a un LocalAuthorityDirective.
## Nunca devuelve null — en caso de incidente inválido devuelve RECORD_ONLY con notas.
static func evaluate(incident: LocalCivilIncident) -> LocalAuthorityDirective:
	# Validación estructural: si el incidente no es procesable, registrar y salir.
	if not incident.is_valid():
		return _make_directive(incident,
			LocalAuthorityResponse.Response.RECORD_ONLY,
			false, false, false,
			"incidente inválido: %s" % ", ".join(incident.validation_errors())
		)

	var response: String      = _compute_response(incident)
	var band: int             = LocalAuthorityResponse.SeverityBand.from_float(incident.severity)
	var needs_responder: bool = LocalAuthorityResponse.Response.is_active_response(response)
	var record: bool          = _should_record(incident, response)
	var lockdown: bool        = _suggests_lockdown(incident, response)

	return _make_directive(incident, response, needs_responder, record, lockdown,
		_build_notes(incident, response)
	)


# ── Tabla de mapping incidente → respuesta ────────────────────────────────────
#
# Lógica de decisión en dos pasos — responsabilidades separadas:
#
#   _base_response()    → respuesta pura según offense_type + severity.
#                         Sin conocer victim_kind. Fácil de leer como tabla.
#
#   _compute_response() → aplica escalada graduada por victim_kind encima del base.
#                         La escalada es proporcional al severity, no plana.
#
# EDITAR AQUÍ para ajustar la tabla institucional base.
# Cuando TavernAuthorityPolicy exista con contexto histórico, puede llamar
# a _base_response() para obtener la respuesta "naive" y enriquecerla con historial.

static func _compute_response(inc: LocalCivilIncident) -> String:
	var R  := LocalAuthorityResponse.Response
	var C  := LocalCivilAuthorityConstants
	var sv := inc.severity

	# Ofensor desconocido + baja severidad + sin testigos = no hay a quién actuar.
	# Registrar el hecho es todo lo que se puede hacer.
	if inc.offender_actor_id.is_empty() \
			and sv < C.SEVERITY_MODERATE \
			and inc.witnesses.is_empty():
		return R.RECORD_ONLY

	var base: String    = _base_response(inc)
	var escalated: bool = (inc.victim_kind == C.VictimKind.AUTHORITY_MEMBER)

	if not escalated:
		return base

	# ── Escalada graduada por AUTHORITY_MEMBER ────────────────────────────────
	# La escalada es proporcional — no convierte un disturbio leve en una expulsión.
	# Principio: la institución reacciona más fuerte cuando sus miembros son afectados,
	# pero la severidad del incidente sigue determinando cuánto más fuerte.
	#
	# Un disturbio leve contra autoridad: sanción económica (deny_service), no física.
	# Un robo moderado contra autoridad: expulsión (eject), no solo deny_service.
	# Una agresión grave contra autoridad: refuerzo (call_backup), como cualquier grave.
	# Assault/arrest_or_subdue: ya son respuestas serias — la escalada no añade nada.
	match base:
		R.RECORD_ONLY:
			# Hay ofensor conocido o testigos — algo se puede hacer mínimamente.
			return R.WARN
		R.WARN:
			# Baja severity + autoridad afectada: depende de la naturaleza del incidente.
			#
			# Ofensas de PRESENCIA FÍSICA (trespass, refusal_to_leave): deny_service es
			# incoherente — no había interacción comercial. La respuesta correcta es eject.
			# Ejemplo: alguien entra sin permiso al interior y la afectada es la encargada.
			#          "No te vendemos nada" no tiene sentido; "sal de aquí" sí.
			#
			# Ofensas con DIMENSIÓN COMERCIAL O SOCIAL (theft, disturbance, vandalism):
			# deny_service es apropiado para baja severity — consecuencia sin intervención física.
			if sv < C.SEVERITY_MODERATE:
				if _is_presence_offense(inc.offense_type):
					return R.EJECT
				return R.DENY_SERVICE
			return R.EJECT
		R.DENY_SERVICE:
			# Ya se contemplaba consecuencia económica; con autoridad afectada, física.
			return R.EJECT
		_:
			# EJECT, CALL_BACKUP, ARREST_OR_SUBDUE: respuestas ya serias.
			# La escalada por victim_kind no añade más — severity ya lo determina.
			return base


static func _base_response(inc: LocalCivilIncident) -> String:
	var R  := LocalAuthorityResponse.Response
	var C  := LocalCivilAuthorityConstants
	var sv := inc.severity

	match inc.offense_type:

		C.Offense.THEFT:
			# Robo leve: advertencia (primer paso institucional).
			# Robo moderado: sanción económica (denegar servicio).
			# Robo grave: expulsión física.
			if sv >= C.SEVERITY_SERIOUS:
				return R.EJECT
			if sv >= C.SEVERITY_MODERATE:
				return R.DENY_SERVICE
			return R.WARN

		C.Offense.ASSAULT:
			# Agresión siempre merece al menos expulsión.
			# Grave: pedir refuerzo — la institución no puede contenerlo sola.
			if sv >= C.SEVERITY_SERIOUS:
				return R.CALL_BACKUP
			return R.EJECT

		C.Offense.MURDER:
			# Asesinato: respuesta de fuerza siempre, sin gradaciones.
			# suggests_zone_lockdown se activa en _suggests_lockdown().
			return R.ARREST_OR_SUBDUE

		C.Offense.VANDALISM:
			# Vandalismo menor: advertencia (daño reparable, sin víctima personal).
			# Vandalismo serio: expulsión.
			if sv >= C.SEVERITY_MODERATE:
				return R.EJECT
			return R.WARN

		C.Offense.TRESPASS:
			# Interior de taberna: expulsión directa — zona privada.
			# Perímetro/grounds leve: advertencia.
			if inc.zone_id == C.ZONE_TAVERN_INTERIOR or sv >= C.SEVERITY_MODERATE:
				return R.EJECT
			return R.WARN

		C.Offense.DISTURBANCE:
			# Disturbio puntual/leve: advertencia.
			# Disturbio sostenido o serio: expulsión.
			if sv >= C.SEVERITY_MODERATE:
				return R.EJECT
			return R.WARN

		C.Offense.WEAPON_THREAT:
			# Amenaza con arma: siempre requiere refuerzo externo mínimo.
			# Amenaza grave: intento de sometimiento.
			if sv >= C.SEVERITY_SERIOUS:
				return R.ARREST_OR_SUBDUE
			return R.CALL_BACKUP

		C.Offense.REFUSAL_TO_LEAVE:
			# Negativa a salir: expulsión.
			# Persistente o peligrosa: pedir refuerzo.
			if sv >= C.SEVERITY_SERIOUS:
				return R.CALL_BACKUP
			return R.EJECT

		_:
			# Tipo desconocido — registrar sin actuar. Policy futura puede enriquecer.
			return R.RECORD_ONLY


# ── Flags auxiliares ──────────────────────────────────────────────────────────

## Ofensas cuyo núcleo es la presencia física del actor, no un intercambio comercial.
## Para estas, deny_service como escalada de AUTHORITY_MEMBER es narrativamente incoherente.
static func _is_presence_offense(offense: String) -> bool:
	var C := LocalCivilAuthorityConstants
	return offense in [C.Offense.TRESPASS, C.Offense.REFUSAL_TO_LEAVE]


static func _should_record(inc: LocalCivilIncident, response: String) -> bool:
	var R := LocalAuthorityResponse.Response
	# WARN de baja severidad sin testigos: no merece entrar en el historial.
	# Todo lo demás se registra — la memoria futura lo usará.
	if response == R.WARN \
			and inc.severity < LocalCivilAuthorityConstants.SEVERITY_MODERATE \
			and inc.witnesses.is_empty():
		return false
	return true


static func _suggests_lockdown(inc: LocalCivilIncident, response: String) -> bool:
	var C := LocalCivilAuthorityConstants
	var R := LocalAuthorityResponse.Response
	# Lockdown se sugiere solo en los casos más graves:
	# - Asesinato dentro de jurisdicción
	# - Amenaza con arma de severidad crítica
	# - Respuesta de arrest + víctima es miembro de autoridad
	if inc.offense_type == C.Offense.MURDER:
		return true
	if inc.offense_type == C.Offense.WEAPON_THREAT \
			and inc.severity >= C.SEVERITY_CRITICAL:
		return true
	if response == R.ARREST_OR_SUBDUE \
			and inc.victim_kind == C.VictimKind.AUTHORITY_MEMBER:
		return true
	return false


# ── Builder interno ───────────────────────────────────────────────────────────

static func _make_directive(
	inc: LocalCivilIncident,
	response: String,
	requires_responder: bool,
	should_record: bool,
	suggests_lockdown: bool,
	notes: String,
) -> LocalAuthorityDirective:
	var d := LocalAuthorityDirective.new()
	d.local_authority_id    = inc.local_authority_id
	d.incident_id           = inc.incident_id
	d.offender_actor_id     = inc.offender_actor_id
	d.zone_id               = inc.zone_id
	d.response_type         = response
	d.severity_band         = LocalAuthorityResponse.SeverityBand.from_float(inc.severity)
	d.requires_responder    = requires_responder
	d.should_record         = should_record
	d.suggests_zone_lockdown = suggests_lockdown
	d.notes                 = notes
	return d


static func _build_notes(inc: LocalCivilIncident, response: String) -> String:
	var C   := LocalCivilAuthorityConstants
	var R   := LocalAuthorityResponse.Response
	var sv  := LocalAuthorityResponse.SeverityBand.name_of(
		LocalAuthorityResponse.SeverityBand.from_float(inc.severity)
	)

	# RECORD_ONLY merece una nota específica que explique POR QUÉ no se actúa.
	# Sin esto, el pipeline absorbe casos ambiguos sin trazabilidad.
	if response == R.RECORD_ONLY:
		if not C.Offense.is_known(inc.offense_type):
			return "RECORD_ONLY: offense_type '%s' fuera del vocabulario — sin mapping" \
				% inc.offense_type
		var reason: PackedStringArray = PackedStringArray()
		if inc.offender_actor_id.is_empty():
			reason.append("ofensor desconocido")
		if inc.witnesses.is_empty():
			reason.append("sin testigos")
		if inc.severity < C.SEVERITY_MODERATE:
			reason.append("sv:%s" % sv)
		return "RECORD_ONLY: sin contexto accionable (%s)" % ", ".join(reason)

	var victim_note: String = ""
	if inc.victim_kind == C.VictimKind.AUTHORITY_MEMBER:
		victim_note = " [AUTHORITY_MEMBER escalation]"
	var offender_note: String = ""
	if inc.offender_actor_id.is_empty():
		offender_note = " [offender unknown]"
	return "%s/%s(sv:%s)→%s%s%s" % [
		inc.offense_type, inc.zone_id, sv, response, victim_note, offender_note
	]


# ── Smoke test / ejemplo de integración (documentado, no activo) ──────────────
#
# Cómo verificar el contrato sin UI ni escena nueva:
#
#   static func _debug_smoke_test() -> void:
#       var C  := LocalCivilAuthorityConstants
#       var R  := LocalAuthorityResponse.Response
#
#       # Caso 1: robo moderado por actor conocido → deny_service
#       var inc1 := LocalCivilIncidentFactory.create(
#           "tavern_main", C.Offense.THEFT, C.SEVERITY_MODERATE,
#           Vector2(100, 200), offender_actor_id: "player",
#           victim_kind: C.VictimKind.VENDOR,
#           zone_id: C.ZONE_TAVERN_INTERIOR,
#       )
#       var dir1 := LocalAuthorityEventFeed.evaluate(inc1)
#       assert(dir1.response_type == R.DENY_SERVICE)
#       assert(dir1.should_record == true)
#       assert(dir1.requires_responder == false)
#       Debug.log("civil_feed", dir1.describe())
#
#       # Caso 2: asesinato → arrest_or_subdue + lockdown sugerido
#       var inc2 := LocalCivilIncidentFactory.create(
#           "tavern_main", C.Offense.MURDER, C.SEVERITY_CRITICAL,
#           Vector2(120, 180), offender_actor_id: "player",
#           victim_kind: C.VictimKind.CIVILIAN,
#           zone_id: C.ZONE_TAVERN_INTERIOR,
#       )
#       var dir2 := LocalAuthorityEventFeed.evaluate(inc2)
#       assert(dir2.response_type == R.ARREST_OR_SUBDUE)
#       assert(dir2.requires_responder == true)
#       assert(dir2.suggests_zone_lockdown == true)
#       Debug.log("civil_feed", dir2.describe())
#
#       # Caso 3: daño a propiedad sin ofensor conocido + baja severity → record_only
#       var inc3 := LocalCivilIncidentFactory.create_simple(
#           "tavern_main", C.Offense.VANDALISM, C.SEVERITY_MINOR, Vector2(80, 160),
#       )
#       var dir3 := LocalAuthorityEventFeed.evaluate(inc3)
#       assert(dir3.response_type == R.RECORD_ONLY)
#       assert(dir3.requires_responder == false)
#       Debug.log("civil_feed", dir3.describe())
#
#       # Caso 4: amenaza con arma a miembro de autoridad → arrest_or_subdue + lockdown
#       var inc4 := LocalCivilIncidentFactory.create(
#           "tavern_main", C.Offense.WEAPON_THREAT, C.SEVERITY_SERIOUS,
#           Vector2(100, 190), offender_actor_id: "player",
#           victim_kind: C.VictimKind.AUTHORITY_MEMBER,
#           zone_id: C.ZONE_TAVERN_INTERIOR,
#       )
#       var dir4 := LocalAuthorityEventFeed.evaluate(inc4)
#       assert(dir4.response_type == R.ARREST_OR_SUBDUE)
#       assert(dir4.suggests_zone_lockdown == true)
#       Debug.log("civil_feed", dir4.describe())
#
#       Debug.log("civil_feed", "smoke test OK: 4 casos evaluados")
