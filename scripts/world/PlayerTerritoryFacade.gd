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
	var get_workbench_nodes: Callable = ctx.get("get_workbench_nodes", Callable())
	var wb_nodes: Array = get_workbench_nodes.call() if get_workbench_nodes.is_valid() else []
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
