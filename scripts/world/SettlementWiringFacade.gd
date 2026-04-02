extends RefCounted
class_name SettlementWiringFacade

func setup(ctx: Dictionary) -> Dictionary:
	var settlement_intel := SettlementIntel.new()
	settlement_intel.setup({
		"cadence": ctx.get("cadence"),
		"world_to_tile": ctx.get("world_to_tile", Callable()),
		"tile_to_world": ctx.get("tile_to_world", Callable()),
		"player_pos_getter": ctx.get("player_pos_getter", Callable()),
		"world_spatial_index": ctx.get("world_spatial_index"),
	})
	var player_territory := PlayerTerritoryMap.new()
	return {
		"settlement_intel": settlement_intel,
		"player_territory": player_territory,
		"player_territory_dirty": true,
	}
