extends RefCounted
class_name LocalAuthorityResponse

# ── LocalAuthorityResponse ────────────────────────────────────────────────────
# Vocabulario de respuestas institucionales para el dominio de autoridad civil local.
#
# POR QUÉ ESTO EXISTE SEPARADO DE LocalCivilAuthorityConstants:
#   LocalCivilAuthorityConstants describe el HECHO (qué pasó, quién, dónde).
#   LocalAuthorityResponse describe la DECISIÓN INSTITUCIONAL (qué hacer al respecto).
#   Son dominios distintos. Un incidente puede generar distintas respuestas según
#   contexto histórico, número de ofensas previas, etc. Mantener vocabularios
#   separados permite que policy y memory evolucionen sin tocar las definiciones
#   de ofensa, y viceversa.
#
# QUÉ NO ES:
#   - No es una orden de ejecución. "call_backup" significa
#     "la institución decide que se necesitan responders" — no invoca nada todavía.
#   - No está acoplado a TavernKeeper, sentinels ni ningún nodo vivo.
#   - No tiene side effects.
#
# CÓMO LO USARÁN LOS SISTEMAS FUTUROS:
#   TavernSanctionDirector lee response_type del directive y decide la ejecución:
#     - WARN          → TavernKeeper emite advertencia verbal
#     - DENY_SERVICE  → TavernKeeper no comercia con el actor
#     - EJECT         → responder intenta expulsar del zone_id
#     - CALL_BACKUP   → invoca sentinel/responder disponible
#     - ARREST_OR_SUBDUE → responder de fuerza, intento de incapacitar
#     - LOCKDOWN      → cierra actividad civil de la zona (reservado para eventos masivos)
#     - RECORD_ONLY   → solo memoria, sin acción; usado cuando no hay ofensor conocido
#                       o cuando severity es demasiado baja para actuar


# ── Tipos de respuesta ────────────────────────────────────────────────────────
# Usa Response.WARN, Response.EJECT, etc. — nunca strings literales en llamadores.
#
# Orden conceptual de escalada (de menor a mayor intervención):
#   RECORD_ONLY → WARN → DENY_SERVICE → EJECT → CALL_BACKUP → ARREST_OR_SUBDUE
#
# LOCKDOWN existe como constante pero NO es un response_type que LocalAuthorityEventFeed
# produzca nunca. Vive aquí para que TavernSanctionDirector lo use como acción
# coordinada de zona — de ahí el flag suggests_zone_lockdown en el directive.
# Si LOCKDOWN estuviera en all(), cada sistema que haga switch en response_type
# debería saber qué hacer con él, cuando en realidad solo SanctionDirector lo coordina.
class Response:
	const WARN              := "warn"
	const DENY_SERVICE      := "deny_service"
	const EJECT             := "eject"
	const CALL_BACKUP       := "call_backup"
	const ARREST_OR_SUBDUE  := "arrest_or_subdue"
	## Reservado para TavernSanctionDirector. EventFeed nunca lo asigna como response_type.
	## Usar suggests_zone_lockdown en el directive para comunicar la necesidad de lockdown.
	const LOCKDOWN          := "lockdown"
	## Sin acción activa. Se registra en memoria pero no se actúa sobre el ofensor.
	## Casos válidos: ofensor desconocido + baja severity + sin testigos.
	## Si se promueve a "warn" sin saber a quién advertir, la acción es incoherente.
	const RECORD_ONLY       := "record_only"

	## Tipos válidos como response_type de un directive producido por EventFeed.
	## LOCKDOWN intencionalmente excluido — es coordinación de zona, no respuesta individual.
	static func all() -> PackedStringArray:
		return PackedStringArray([
			WARN, DENY_SERVICE, EJECT, CALL_BACKUP,
			ARREST_OR_SUBDUE, RECORD_ONLY,
		])

	static func is_known(r: String) -> bool:
		return all().has(r)

	## Devuelve true si esta respuesta requiere que algún actor físico intervenga.
	## LOCKDOWN excluido: el lockdown lo coordina SanctionDirector vía suggests_zone_lockdown.
	static func is_active_response(r: String) -> bool:
		return r in [EJECT, CALL_BACKUP, ARREST_OR_SUBDUE]


# ── Banda de severidad ────────────────────────────────────────────────────────
# Convierte el float continuo de severity en una categoría ordinal para el directive.
# Permite que policy y sanction hagan switch/match en vez de comparar floats.
#
# Umbrales alineados con LocalCivilAuthorityConstants severity thresholds:
#   [0.00, 0.20) → LOW      (por debajo de SEVERITY_MINOR)
#   [0.20, 0.50) → MEDIUM   (SEVERITY_MINOR a SEVERITY_MODERATE)
#   [0.50, 0.75) → HIGH     (SEVERITY_MODERATE a SEVERITY_SERIOUS)
#   [0.75, 1.00] → CRITICAL (SEVERITY_SERIOUS a SEVERITY_CRITICAL)
class SeverityBand:
	const LOW      := 0
	const MEDIUM   := 1
	const HIGH     := 2
	const CRITICAL := 3

	## Clasifica un float [0,1] en una banda ordinal.
	static func from_float(severity: float) -> int:
		var C := LocalCivilAuthorityConstants
		if severity >= C.SEVERITY_SERIOUS:
			return CRITICAL
		if severity >= C.SEVERITY_MODERATE:
			return HIGH
		if severity >= C.SEVERITY_MINOR:
			return MEDIUM
		return LOW

	## Nombre legible para debug/logs.
	static func name_of(band: int) -> String:
		match band:
			LOW:      return "LOW"
			MEDIUM:   return "MEDIUM"
			HIGH:     return "HIGH"
			CRITICAL: return "CRITICAL"
		return "UNKNOWN(%d)" % band
