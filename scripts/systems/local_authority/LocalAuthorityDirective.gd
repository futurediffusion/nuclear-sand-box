extends RefCounted
class_name LocalAuthorityDirective

# ── LocalAuthorityDirective ───────────────────────────────────────────────────
# Resultado de traducir un LocalCivilIncident a una decisión institucional abstracta.
# Producido por LocalAuthorityEventFeed; consumido por sistemas futuros.
#
# POSICIÓN EN LA CADENA:
#
#   [Hecho]          LocalCivilIncident
#       ↓
#   [Decisión]       LocalAuthorityDirective   ← estás aquí
#       ↓
#   [Ejecución]      TavernSanctionDirector (futuro)
#                    → TavernKeeper reacciona
#                    → Sentinel actúa
#                    → Servicio denegado
#
# POR QUÉ EXISTE ANTES QUE TavernSanctionDirector:
#   El directive separa "qué decidió la institución" de "cómo lo ejecuta".
#   Sin este contrato explícito, TavernKeeper y los sentinels acabarían
#   leyendo directamente el incidente y replicando la lógica de decisión
#   cada uno por su cuenta — acoplamiento fatal.
#
# QUÉ NO HACE:
#   - No ejecuta ninguna acción
#   - No emite señales
#   - No referencia nodos vivos
#   - No sabe quién producirá el incidente ni quién ejecutará la respuesta
#
# QUÉ SÍ PREPARA:
#   - TavernLocalMemory puede almacenar directives junto a incidentes
#   - TavernAuthorityPolicy puede producir directives enriquecidos con historial
#   - TavernSanctionDirector recibe este contrato y decide ejecución


# ── Identidad y trazabilidad ──────────────────────────────────────────────────

## Autoridad local que emitió esta directiva.
var local_authority_id: String = ""

## ID del incidente origen. Permite trazar directive → incident sin guardar el objeto.
var incident_id: String = ""

## Actor sobre quien recae la directiva. Puede estar vacío si el ofensor es desconocido.
var offender_actor_id: String = ""

## Zona donde aplica la directiva.
var zone_id: String = LocalCivilAuthorityConstants.ZONE_UNKNOWN


# ── Decisión principal ────────────────────────────────────────────────────────

## Tipo de respuesta institucional. Usar LocalAuthorityResponse.Response.*.
## Es la decisión principal — una sola. Los matices van en los flags auxiliares.
## LOCKDOWN nunca aparece aquí como response_type — se comunica vía suggests_zone_lockdown.
var response_type: String = LocalAuthorityResponse.Response.RECORD_ONLY

## Banda de severidad del incidente original (LocalAuthorityResponse.SeverityBand.*).
## Permite que sanction/policy hagan switch ordinal sin comparar floats.
var severity_band: int = LocalAuthorityResponse.SeverityBand.LOW


# ── Flags auxiliares ──────────────────────────────────────────────────────────
# Los flags comunican intención de acción secundaria sin añadir más response_types.
# El SanctionDirector los lee para decidir qué poner en marcha.

## Si true, la institución considera que un actor físico (sentinel/responder) debe
## intervenir activamente. No significa que ya existe un sentinel — eso lo decide
## SanctionDirector según disponibilidad.
var requires_responder: bool = false

## Si true, este directive debe persistirse en TavernLocalMemory (futuro).
## Algunos warns de baja severidad pueden descartarse sin registro.
var should_record: bool = true

## Si true, el evento es suficientemente grave como para considerar restringir
## la actividad civil en la zona (cerrar comercio, bloquear entrada, etc.).
## No implementa el lockdown — solo lo sugiere al SanctionDirector.
## Casos típicos: murder, weapon_threat crítico, ataque masivo.
var suggests_zone_lockdown: bool = false


# ── Debug / trazabilidad ──────────────────────────────────────────────────────

## Razón legible de por qué se eligió esta respuesta. Útil para tuning y debug.
## No es una descripción de UI — es una nota interna del feed/policy.
var notes: String = ""

## Extensión libre para que policy/sanction puedan adjuntar datos sin cambiar el contrato.
var metadata: Dictionary = {}


# ── Serialización ─────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"local_authority_id":   local_authority_id,
		"incident_id":          incident_id,
		"offender_actor_id":    offender_actor_id,
		"zone_id":              zone_id,
		"response_type":        response_type,
		"severity_band":        severity_band,
		"requires_responder":   requires_responder,
		"should_record":        should_record,
		"suggests_zone_lockdown": suggests_zone_lockdown,
		"notes":                notes,
		"metadata":             metadata.duplicate(),
	}


static func from_dict(d: Dictionary) -> LocalAuthorityDirective:
	var dir := LocalAuthorityDirective.new()
	dir.local_authority_id    = str(d.get("local_authority_id",   ""))
	dir.incident_id           = str(d.get("incident_id",          ""))
	dir.offender_actor_id     = str(d.get("offender_actor_id",    ""))
	dir.zone_id               = str(d.get("zone_id",
		LocalCivilAuthorityConstants.ZONE_UNKNOWN))
	dir.response_type         = str(d.get("response_type",
		LocalAuthorityResponse.Response.RECORD_ONLY))
	dir.severity_band         = int(d.get("severity_band",
		LocalAuthorityResponse.SeverityBand.LOW))
	dir.requires_responder    = bool(d.get("requires_responder",    false))
	dir.should_record         = bool(d.get("should_record",         true))
	dir.suggests_zone_lockdown = bool(d.get("suggests_zone_lockdown", false))
	dir.notes                 = str(d.get("notes",                  ""))
	var raw_meta: Variant     = d.get("metadata", null)
	if raw_meta is Dictionary:
		dir.metadata = raw_meta.duplicate()
	return dir


# ── Inspección ────────────────────────────────────────────────────────────────

## Resumen legible para logs de debug.
func describe() -> String:
	var band_name: String = LocalAuthorityResponse.SeverityBand.name_of(severity_band)
	var flags: PackedStringArray = PackedStringArray()
	if requires_responder:    flags.append("NEEDS_RESPONDER")
	if suggests_zone_lockdown: flags.append("SUGGESTS_LOCKDOWN")
	if not should_record:     flags.append("NO_RECORD")
	var flags_str: String = " [%s]" % ", ".join(flags) if not flags.is_empty() else ""
	return "[%s] %s ← %s (band:%s, zone:%s)%s | %s" % [
		local_authority_id, response_type, incident_id,
		band_name, zone_id, flags_str, notes
	]
