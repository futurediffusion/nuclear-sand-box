extends RefCounted
class_name LocalCivilAuthorityConstants

# ── LocalCivilAuthorityConstants ──────────────────────────────────────────────
# Vocabulario del dominio de autoridad civil local.
#
# POR QUÉ EXISTE ESTE ARCHIVO ANTES QUE TavernAuthorityPolicy / SanctionDirector:
#   Los strings literales dispersos por múltiples sistemas crean acoplamiento
#   invisible y bugs silenciosos. Centralizar el vocabulario aquí garantiza que
#   memoria, policy, sanción y sentinels hablen el mismo idioma sin dependencias
#   circulares.
#
# QUÉ NO ES:
#   - No es un sistema de hostilidad/heat. La autoridad civil habla de
#     "incidentes", "jurisdicción", "testigos" — no de "aggro" ni "decay rates".
#   - No es específico de la taberna. Puede compartirse con autoridad de aldea,
#     caravana u otro asentamiento civil que se añada en el futuro.
#
# EXTENSIÓN FUTURA:
#   Cuando existan más autoridades locales (village_elder, caravan_master...),
#   añadir sus zone_ids aquí. No crear un archivo de constantes por autoridad.

# ── Tipos de ofensa ───────────────────────────────────────────────────────────
# Usa Offense.THEFT, Offense.ASSAULT, etc. en lugar de strings literales.
# Si offense_type llega desde save, valida contra Offense.all().
class Offense:
	const THEFT            := "theft"
	const ASSAULT          := "assault"
	const MURDER           := "murder"
	const VANDALISM        := "vandalism"
	const TRESPASS         := "trespass"
	const DISTURBANCE      := "disturbance"
	const WEAPON_THREAT    := "weapon_threat"
	const REFUSAL_TO_LEAVE := "refusal_to_leave"

	## Todos los tipos conocidos — útil para validar valores deserializados.
	static func all() -> PackedStringArray:
		return PackedStringArray([
			THEFT, ASSAULT, MURDER, VANDALISM,
			TRESPASS, DISTURBANCE, WEAPON_THREAT, REFUSAL_TO_LEAVE,
		])

	## Devuelve true si el tipo es conocido. Policy puede decidir si acepta desconocidos.
	static func is_known(offense: String) -> bool:
		return all().has(offense)


# ── Tipos de víctima ──────────────────────────────────────────────────────────
# Quién fue dañado. Afecta cómo la policy responde (dañar a una figura de
# autoridad es más grave que dañar propiedad, por ejemplo).
class VictimKind:
	const CIVILIAN         := "civilian"
	const VENDOR           := "vendor"
	const TAVERN_PROPERTY  := "tavern_property"
	const AUTHORITY_MEMBER := "authority_member"
	const UNKNOWN          := "unknown"

	static func all() -> PackedStringArray:
		return PackedStringArray([
			CIVILIAN, VENDOR, TAVERN_PROPERTY, AUTHORITY_MEMBER, UNKNOWN,
		])

	static func is_known(kind: String) -> bool:
		return all().has(kind)


# ── Severidad ─────────────────────────────────────────────────────────────────
# Severity es un float normalizado [0.0, 1.0]. Estos niveles son orientativos
# para los emisores de incidentes; la policy decide cómo los interpreta.
#
# Un robo de objeto barato: SEVERITY_MINOR
# Un asalto sin arma: SEVERITY_MODERATE
# Un asalto con arma: SEVERITY_SERIOUS
# Un asesinato o ataque a autoridad: SEVERITY_CRITICAL
const SEVERITY_MIN:      float = 0.0
const SEVERITY_MINOR:    float = 0.2
const SEVERITY_MODERATE: float = 0.5
const SEVERITY_SERIOUS:  float = 0.75
const SEVERITY_CRITICAL: float = 1.0
const SEVERITY_MAX:      float = 1.0


# ── Identificadores de zona ───────────────────────────────────────────────────
# Un zone_id estrecha la jurisdicción dentro del territorio de una autoridad.
# "unknown" es válido cuando el llamador no rastrea zonas todavía.
#
# EXTENSIÓN FUTURA: añadir zonas de aldea, mercado, carretera real, etc.
const ZONE_UNKNOWN:          String = "unknown"
const ZONE_TAVERN_INTERIOR:  String = "tavern_interior"
const ZONE_TAVERN_GROUNDS:   String = "tavern_grounds"
const ZONE_TAVERN_PERIMETER: String = "tavern_perimeter"
