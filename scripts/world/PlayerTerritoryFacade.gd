extends RefCounted
class_name PlayerTerritoryFacade

func setup(ctx: Dictionary) -> Dictionary:
	return {"player_territory_dirty": bool(ctx.get("player_territory_dirty", true))}

func tick(ctx: Dictionary) -> bool:
	if not bool(ctx.get("player_territory_dirty", false)):
		return false
	var player_territory: PlayerTerritoryMap = ctx.get("player_territory")
	var settlement_intel: SettlementIntel = ctx.get("settlement_intel")
	if player_territory == null or settlement_intel == null:
		return true
	var world_spatial_index: WorldSpatialIndex = ctx.get("world_spatial_index")
	var wb_nodes: Array = []
	if world_spatial_index != null:
		wb_nodes = world_spatial_index.get_all_runtime_nodes(WorldSpatialIndex.KIND_WORKBENCH)
	else:
		var tree: SceneTree = ctx.get("tree")
		if tree != null:
			wb_nodes = tree.get_nodes_in_group("workbench")
	var bases: Array[Dictionary] = settlement_intel.get_detected_bases_near(Vector2.ZERO, 999999.0)
	player_territory.rebuild(wb_nodes, bases)
	return false

func is_in_player_territory(player_territory: PlayerTerritoryMap, world_pos: Vector2) -> bool:
	if player_territory == null:
		return false
	return player_territory.is_in_player_territory(world_pos)

func get_player_territory_zones(player_territory: PlayerTerritoryMap) -> Array[Dictionary]:
	if player_territory == null:
		return []
	return player_territory.get_zones()
