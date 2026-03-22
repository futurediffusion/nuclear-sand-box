extends RefCounted
class_name LocalCivilIncidentFactory

# ── LocalCivilIncidentFactory ─────────────────────────────────────────────────
# Crea instancias de LocalCivilIncident con defaults sanos y campos auto-rellenados.
#
# POR QUÉ UNA FACTORY:
#   Sin esto, cada llamador debe recordar setear day, created_at_run_time, clampear
#   severity, normalizar arrays vacíos y generar un incident_id. Un campo omitido
#   degrada silenciosamente la precisión futura de memoria y policy.
#   La factory es el único lugar donde se garantizan esos invariantes.
#
# HOOK FUTURO — cómo se usará cuando TavernLocalMemory exista:
#
#   var inc := LocalCivilIncidentFactory.create(
#       "tavern_main",
#       LocalCivilAuthorityConstants.Offense.THEFT,
#       LocalCivilAuthorityConstants.SEVERITY_MODERATE,
#       player.global_position,
#       offender_id: player.actor_id,
#       victim_kind: LocalCivilAuthorityConstants.VictimKind.VENDOR,
#       zone_id: LocalCivilAuthorityConstants.ZONE_TAVERN_INTERIOR,
#       witnesses: ["npc_barmaid_01"],
#       source_tag: "player_pickpocket_handler",
#   )
#   TavernLocalMemory.record(inc)   # <-- futuro; la factory no lo llama
#
# NOTA: la factory NO conoce a TavernLocalMemory ni a ninguna policy.
# El coordinador (world.gd, TavernKeeper, o un futuro LocalAuthorityBus)
# es quien conecta factory → memoria → policy → sanción.


## Crea un incidente con todos los campos. Parametros obligatorios mínimos:
##   local_authority_id, offense_type, severity, position.
## El resto tiene defaults razonables.
static func create(
	local_authority_id: String,
	offense_type: String,
	severity: float,
	position: Vector2,
	offender_actor_id: String = "",
	victim_kind: String = LocalCivilAuthorityConstants.VictimKind.UNKNOWN,
	zone_id: String = LocalCivilAuthorityConstants.ZONE_UNKNOWN,
	witnesses: Array[String] = [],
	source_tag: String = "",
	metadata: Dictionary = {},
) -> LocalCivilIncident:
	var inc := LocalCivilIncident.new()

	# Campos de identidad
	inc.incident_id        = _generate_id(local_authority_id, offense_type)
	inc.local_authority_id = local_authority_id
	inc.offender_actor_id  = offender_actor_id
	inc.offense_type       = offense_type

	# Severity clampeado aquí para no depender de que los llamadores sean perfectos
	inc.severity           = clampf(severity, 0.0, 1.0)
	inc.position           = position

	# Tiempo auto-rellenado desde autoloads. Defensivo: usa 0 si el autoload no existe.
	inc.day                = WorldTime.get_current_day() if WorldTime != null else 0
	inc.created_at_run_time = RunClock.now() if RunClock != null else 0.0

	# Normalización de strings vacíos: si llega vacío, usar default semántico
	inc.victim_kind = victim_kind if not victim_kind.is_empty() \
	                  else LocalCivilAuthorityConstants.VictimKind.UNKNOWN
	inc.zone_id     = zone_id if not zone_id.is_empty() \
	                  else LocalCivilAuthorityConstants.ZONE_UNKNOWN

	# Witnesses: copiar y deduplicar. Un testigo duplicado es ruido para la policy.
	for w: String in witnesses:
		if not w.is_empty() and not inc.witnesses.has(w):
			inc.witnesses.append(w)
	inc.source_tag = source_tag
	inc.metadata   = metadata.duplicate()

	return inc


## Sobrecarga rápida para incidentes simples sin testigos ni metadata.
## Útil en sistemas que no rastrean zona ni víctima todavía.
static func create_simple(
	local_authority_id: String,
	offense_type: String,
	severity: float,
	position: Vector2,
) -> LocalCivilIncident:
	return create(local_authority_id, offense_type, severity, position)


# ── Interno ───────────────────────────────────────────────────────────────────

static func _generate_id(authority_id: String, offense_type: String) -> String:
	# Combina authority, tipo, tiempo unix y un entero aleatorio para minimizar
	# colisiones incluso si se crean múltiples incidentes en el mismo frame.
	var t: float = Time.get_unix_time_from_system()
	var h: int   = hash(authority_id + offense_type + str(t) + str(randi()))
	return "ci_%d" % absi(h)


# ── Smoke test / ejemplo de uso (llamar desde consola de debug o DevHelper) ────
#
# Para verificar que el contrato funciona sin UI ni escena nueva:
#
#   static func _debug_smoke_test() -> void:
#       var C := LocalCivilAuthorityConstants
#
#       var inc1 := LocalCivilIncidentFactory.create(
#           "tavern_main",
#           C.Offense.THEFT,
#           C.SEVERITY_MODERATE,
#           Vector2(128.0, 200.0),
#           offender_actor_id = "player",
#           victim_kind       = C.VictimKind.VENDOR,
#           zone_id           = C.ZONE_TAVERN_INTERIOR,
#           witnesses         = ["npc_barmaid_01", "npc_merchant_02"],
#           source_tag        = "smoke_test",
#       )
#       assert(inc1.is_valid(), "inc1 debe ser válido")
#       assert(inc1.witnesses.size() == 2, "inc1 debe tener 2 testigos")
#
#       # Roundtrip serialización
#       var dict1  := inc1.to_dict()
#       var inc1b  := LocalCivilIncident.from_dict(dict1)
#       assert(inc1b.incident_id      == inc1.incident_id,      "incident_id roundtrip")
#       assert(inc1b.offense_type     == inc1.offense_type,     "offense_type roundtrip")
#       assert(inc1b.witnesses.size() == inc1.witnesses.size(),  "witnesses roundtrip")
#
#       var inc2 := LocalCivilIncidentFactory.create_simple(
#           "tavern_main",
#           C.Offense.DISTURBANCE,
#           C.SEVERITY_MINOR,
#           Vector2(64.0, 128.0),
#       )
#       assert(inc2.is_valid(),  "inc2 debe ser válido")
#       assert(inc2.offender_actor_id == "", "inc2 offender desconocido")
#
#       # Incidente inválido — sin authority_id
#       var inc_bad := LocalCivilIncidentFactory.create_simple("", C.Offense.ASSAULT, 0.8, Vector2.ZERO)
#       assert(!inc_bad.is_valid(), "inc_bad no debe ser válido")
#       assert(inc_bad.validation_errors().size() > 0, "inc_bad debe tener errores")
#
#       Debug.log("civil_authority", "smoke test OK: %d incidentes creados" % 3)
