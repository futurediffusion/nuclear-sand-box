extends RefCounted
class_name WorldPathingFacade

func setup(ctx: Dictionary) -> void:
	NpcPathService.setup({
		"cliffs_tilemap": ctx.get("cliffs_tilemap"),
		"walls_tilemap": ctx.get("walls_tilemap"),
		"world_to_tile": ctx.get("world_to_tile", Callable()),
		"tile_to_world": ctx.get("tile_to_world", Callable()),
		"world_tile_rect": ctx.get("world_tile_rect", Rect2i()),
		"world_spatial_index": ctx.get("world_spatial_index"),
	})
