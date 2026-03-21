class_name BanditTerritoryQuery
extends RefCounted

# ── BanditTerritoryQuery ──────────────────────────────────────────────────────
# Módulo estático de consulta de territorio bandido.
# Define el radio de influencia de cada grupo basado en el nivel de hostilidad
# de su facción. Usado para detectar intrusiones del jugador en tiempo real.
#
# Radio de territorio por nivel:
#   nivel 0-2:  500 px  (~15 tiles)  — banda débil, zona de camping
#   nivel 3-5:  700 px  (~22 tiles)  — presencia establecida
#   nivel 6-8:  900 px  (~28 tiles)  — facción dominante
#   nivel 9-10: 1100 px (~34 tiles)  — control regional total

const TERRITORY_RADIUS_BY_LEVEL: Array[float] = [
	500.0,   # nivel 0
	500.0,   # nivel 1
	500.0,   # nivel 2
	700.0,   # nivel 3
	700.0,   # nivel 4
	700.0,   # nivel 5
	900.0,   # nivel 6
	900.0,   # nivel 7
	900.0,   # nivel 8
	1100.0,  # nivel 9
	1100.0,  # nivel 10
]


## Radio de territorio para una facción según su nivel de hostilidad actual.
static func radius_for_faction(faction_id: String) -> float:
	var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
	var level: int = clampi(profile.hostility_level, 0, TERRITORY_RADIUS_BY_LEVEL.size() - 1)
	return TERRITORY_RADIUS_BY_LEVEL[level]


## Devuelve todos los grupos bandidos cuyo territorio contiene world_pos.
## Resultado: Array de { faction_id, group_id, home_pos, dist, radius }
## ordenado de más cercano a más lejano.
static func groups_at(world_pos: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for gid in BanditGroupMemory.get_all_group_ids():
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		if g.is_empty():
			continue
		# Solo grupos con líder vivo — grupos fantasma no reclaman territorio
		var leader_id: String = String(g.get("leader_id", ""))
		if leader_id == "":
			continue
		var faction_id: String = String(g.get("faction_id", "bandits"))
		var home_pos: Vector2  = g.get("home_world_pos", Vector2.ZERO) as Vector2
		var radius: float      = radius_for_faction(faction_id)
		var dist: float        = world_pos.distance_to(home_pos)
		if dist <= radius:
			result.append({
				"faction_id": faction_id,
				"group_id":   gid,
				"leader_id":  leader_id,
				"home_pos":   home_pos,
				"dist":       dist,
				"radius":     radius,
			})
	# Orden: el grupo más cercano primero (más probable que reaccione primero)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("dist", INF)) < float(b.get("dist", INF)))
	return result


## True si world_pos está dentro del territorio de al menos un grupo bandido.
static func is_in_territory(world_pos: Vector2) -> bool:
	for gid in BanditGroupMemory.get_all_group_ids():
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		if g.is_empty():
			continue
		var leader_id: String = String(g.get("leader_id", ""))
		if leader_id == "":
			continue
		var faction_id: String = String(g.get("faction_id", "bandits"))
		var home_pos: Vector2  = g.get("home_world_pos", Vector2.ZERO) as Vector2
		var radius: float      = radius_for_faction(faction_id)
		if world_pos.distance_to(home_pos) <= radius:
			return true
	return false
