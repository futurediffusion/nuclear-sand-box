extends RefCounted
class_name ChunkGenerator

const LAYER_GROUND: int = 0

func apply_ground(chunk_pos: Vector2i, ctx: Dictionary) -> void:
	var tilemap: TileMap = ctx["tilemap"]
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	var chunk_size: int = ctx["chunk_size"]
	var pick_tile: Callable = ctx["pick_tile"]
	var tree: SceneTree = ctx["tree"]
	var generating_yield_stride: int = ctx.get("generating_yield_stride", 8)
	var terrain_set: int = ctx.get("ground_terrain_set", 0)
	var ground_source_id: int = int(ctx.get("ground_source_id", 0))
	var ground_fallback_atlas_by_terrain: Dictionary = ctx.get("ground_fallback_atlas_by_terrain", {
		0: Vector2i(0, 0),
		1: Vector2i(0, 1),
	})
	var terrain_connect_batch_size: int = max(1, int(ctx.get("terrain_connect_batch_size", 256)))
	var allow_legacy_fallback: bool = bool(ctx.get("allow_legacy_fallback", true))
	var ground_mapping_mode: String = String(ctx.get("ground_mapping_mode", "legacy"))
	var terrain_connect_yield_each_batches: int = max(1, int(ctx.get("terrain_connect_yield_each_batches", 1)))
	var perf_hook: Callable = ctx.get("perf_stage_hook", Callable())
	var fallback_debug_hook: Callable = ctx.get("ground_fallback_debug_hook", Callable())

	var start_x := chunk_pos.x * chunk_size
	var start_y := chunk_pos.y * chunk_size

	var terrain_buckets: Dictionary = {}
	for y in range(start_y, start_y + chunk_size):
		for x in range(start_x, start_x + chunk_size):
			if x < 0 or x >= width or y < 0 or y >= height:
				continue
			var tile_data_variant: Variant = pick_tile.call(x, y)
			var tile_data: Dictionary = {}
			if typeof(tile_data_variant) == TYPE_DICTIONARY:
				tile_data = tile_data_variant
			elif typeof(tile_data_variant) == TYPE_VECTOR2I:
				tile_data = {
					"atlas_coords": tile_data_variant,
					"ground_terrain_id": clampi(tile_data_variant.y, 0, 1),
				}

			var terrain: int = clampi(int(tile_data.get("ground_terrain_id", 0)), 0, 1)
			if not terrain_buckets.has(terrain):
				terrain_buckets[terrain] = []
			terrain_buckets[terrain].append(Vector2i(x, y))

		if y % generating_yield_stride == 0:
			await tree.process_frame

	await apply_ground_terrain_batched(
		tilemap,
		tree,
		terrain_set,
		terrain_buckets,
		ground_source_id,
		ground_fallback_atlas_by_terrain,
		terrain_connect_batch_size,
		terrain_connect_yield_each_batches,
		chunk_pos,
		perf_hook,
		fallback_debug_hook,
		allow_legacy_fallback,
		ground_mapping_mode
	)

func apply_ground_terrain_batched(
	tilemap: TileMap,
	tree: SceneTree,
	terrain_set: int,
	terrain_buckets: Dictionary,
	ground_source_id: int,
	ground_fallback_atlas_by_terrain: Dictionary,
	terrain_connect_batch_size: int,
	terrain_connect_yield_each_batches: int,
	chunk_pos: Vector2i,
	perf_hook: Callable,
	fallback_debug_hook: Callable,
	allow_legacy_fallback: bool,
	ground_mapping_mode: String
) -> void:
	var start_us: int = Time.get_ticks_usec()
	var batch_counter: int = 0
	var fallback_missing_cells: int = 0
	var fallback_invalid_source_cells: int = 0
	for terrain_key in terrain_buckets.keys():
		var terrain: int = int(terrain_key)
		var fallback_atlas: Vector2i = Vector2i(0, terrain)
		if ground_fallback_atlas_by_terrain.has(terrain):
			fallback_atlas = Vector2i(ground_fallback_atlas_by_terrain[terrain])
		var cells_variant: Array = terrain_buckets[terrain]
		var cells: Array[Vector2i] = []
		cells.assign(cells_variant)
		if cells.is_empty():
			continue

		var start_idx: int = 0
		while start_idx < cells.size():
			var end_idx: int = min(start_idx + terrain_connect_batch_size, cells.size())
			var sub_batch: Array[Vector2i] = []
			sub_batch.assign(cells.slice(start_idx, end_idx))

			tilemap.set_cells_terrain_connect(LAYER_GROUND, sub_batch, terrain_set, terrain, true)
			for cell in sub_batch:
				var source_id: int = tilemap.get_cell_source_id(LAYER_GROUND, cell)
				if source_id == -1:
					fallback_missing_cells += 1
					tilemap.set_cell(LAYER_GROUND, cell, ground_source_id, fallback_atlas)
				elif source_id != ground_source_id:
					fallback_invalid_source_cells += 1
					if allow_legacy_fallback or ground_mapping_mode != "legacy":
						tilemap.set_cell(LAYER_GROUND, cell, ground_source_id, fallback_atlas)

			batch_counter += 1
			if batch_counter % terrain_connect_yield_each_batches == 0:
				await tree.process_frame

			start_idx = end_idx

	if perf_hook.is_valid():
		var elapsed_ms: float = float(Time.get_ticks_usec() - start_us) / 1000.0
		perf_hook.call("ground terrain connect", chunk_pos, elapsed_ms)

	var fallback_total_cells: int = fallback_missing_cells + fallback_invalid_source_cells
	if fallback_total_cells > 0 and fallback_debug_hook.is_valid():
		fallback_debug_hook.call(chunk_pos, fallback_total_cells, fallback_missing_cells, fallback_invalid_source_cells, ground_mapping_mode)
