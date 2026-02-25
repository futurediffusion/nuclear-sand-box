extends RefCounted
class_name ChunkGenerator

const LAYER_GROUND: int = 0
const GROUND_SOURCE: int = 0

func apply_ground(chunk_pos: Vector2i, ctx: Dictionary) -> void:
	var tilemap: TileMap = ctx["tilemap"]
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	var chunk_size: int = ctx["chunk_size"]
	var pick_tile: Callable = ctx["pick_tile"]
	var tree: SceneTree = ctx["tree"]
	var generating_yield_stride: int = ctx.get("generating_yield_stride", 8)

	var start_x := chunk_pos.x * chunk_size
	var start_y := chunk_pos.y * chunk_size

	for y in range(start_y, start_y + chunk_size):
		for x in range(start_x, start_x + chunk_size):
			if x < 0 or x >= width or y < 0 or y >= height:
				continue
			var tile_atlas: Vector2i = pick_tile.call(x, y)
			tile_atlas.y = clampi(tile_atlas.y, 0, 2)
			tilemap.set_cell(LAYER_GROUND, Vector2i(x, y), GROUND_SOURCE, tile_atlas)

		if y % generating_yield_stride == 0:
			await tree.process_frame
