extends RefCounted
class_name WorldChunkLifecycleCoordinator

## Owns runtime chunk lifecycle orchestration:
## - active window computation and diffing
## - generation/load sequencing
## - deferred unload + tile erase draining
## - progressive paint scheduling bookkeeping

var _pipeline: ChunkPipeline
var _entity_coordinator: EntitySpawnCoordinator
var _chunk_generator: ChunkGenerator
var _vegetation_root: VegetationRoot

var _loaded_chunks: Dictionary = {}
var _ground_terrain_painted_chunks: Dictionary = {}
var _chunk_occupied_tiles: Dictionary = {}
var _pending_tile_erases: Array[Vector2i] = []

var _chunk_size: int = 32
var _active_radius: int = 1
var _width: int = 0
var _height: int = 0

var _debug_log: Callable = Callable()
var _debug_check_tile_alignment: Callable = Callable()
var _debug_check_player_chunk: Callable = Callable()
var _is_chunk_in_active_window: Callable = Callable()
var _on_unload_chunk: Callable = Callable()

func setup(ctx: Dictionary) -> void:
	_pipeline = ctx.get("pipeline", null) as ChunkPipeline
	_entity_coordinator = ctx.get("entity_coordinator", null) as EntitySpawnCoordinator
	_chunk_generator = ctx.get("chunk_generator", null) as ChunkGenerator
	_vegetation_root = ctx.get("vegetation_root", null) as VegetationRoot
	_loaded_chunks = ctx.get("loaded_chunks", {}) as Dictionary
	_ground_terrain_painted_chunks = ctx.get("ground_terrain_painted_chunks", {}) as Dictionary
	_chunk_occupied_tiles = ctx.get("chunk_occupied_tiles", {}) as Dictionary
	_chunk_size = int(ctx.get("chunk_size", 32))
	_active_radius = int(ctx.get("active_radius", 1))
	_width = int(ctx.get("width", 0))
	_height = int(ctx.get("height", 0))
	_debug_log = ctx.get("debug_log", Callable()) as Callable
	_debug_check_tile_alignment = ctx.get("debug_check_tile_alignment", Callable()) as Callable
	_debug_check_player_chunk = ctx.get("debug_check_player_chunk", Callable()) as Callable
	_is_chunk_in_active_window = ctx.get("is_chunk_in_active_window", Callable()) as Callable
	_on_unload_chunk = ctx.get("on_unload_chunk", Callable()) as Callable

func update_chunks(center: Vector2i, player_global_position: Vector2 = Vector2.INF) -> void:
	if _pipeline == null or _entity_coordinator == null or _chunk_generator == null:
		return
	if _pipeline.is_updating:
		return
	_log("boot", "ChunkManager load begin center=%s" % center)
	_log("chunk", "CENTER moved -> (%d,%d)" % [center.x, center.y])
	if player_global_position != Vector2.INF:
		if _debug_check_tile_alignment.is_valid():
			_debug_check_tile_alignment.call(player_global_position)
		if _debug_check_player_chunk.is_valid():
			_debug_check_player_chunk.call(player_global_position)

	var needed_data: Dictionary = _compute_needed_chunks(center)
	var needed: Dictionary = needed_data.get("needed", {}) as Dictionary
	var needed_chunks: Array[Vector2i] = needed_data.get("needed_chunks", []) as Array[Vector2i]

	if _pipeline.terrain_paint_ring_priority_enabled:
		needed_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var ring_a: int = max(abs(a.x - center.x), abs(a.y - center.y))
			var ring_b: int = max(abs(b.x - center.x), abs(b.y - center.y))
			if ring_a == ring_b:
				if a.y == b.y:
					return a.x < b.x
				return a.y < b.y
			return ring_a < ring_b
		)

	if _pipeline.progressive_terrain_paint_enabled:
		_pipeline.reset_terrain_paint_epoch()

	for cpos in needed_chunks:
		if not _pipeline.generated_chunks.has(cpos) and not _pipeline.generating_chunks.has(cpos):
			_pipeline.generating_chunks[cpos] = true
			_pipeline.generate_chunk(cpos, true)
		if _pipeline.generating_chunks.has(cpos):
			continue
		if not _loaded_chunks.has(cpos):
			_entity_coordinator.load_chunk(cpos)
			_loaded_chunks[cpos] = true
		if _pipeline.progressive_terrain_paint_enabled and _is_active_window_chunk(cpos, center):
			_pipeline.enqueue_terrain_paint(cpos, center, _pipeline.terrain_paint_epoch)

	var ground_to_paint: Array[Vector2i] = []
	for cpos in needed_chunks:
		if not _ground_terrain_painted_chunks.has(cpos):
			ground_to_paint.append(cpos)
	if not ground_to_paint.is_empty():
		await _chunk_generator.apply_ground_terrain_ctx(ground_to_paint, _pipeline.make_ground_terrain_ctx())
		for cpos in ground_to_paint:
			_ground_terrain_painted_chunks[cpos] = true
			if _vegetation_root != null:
				_vegetation_root.load_chunk(cpos, _chunk_occupied_tiles.get(cpos, {}))

	for cpos in _loaded_chunks.keys():
		if not needed.has(cpos):
			_loaded_chunks.erase(cpos)
			_entity_coordinator.unload_entities(cpos)
			_pipeline.on_chunk_unloaded(cpos)
			_ground_terrain_painted_chunks.erase(cpos)
			_pending_tile_erases.append(cpos)

	if _pipeline.progressive_terrain_paint_enabled and _pipeline.terrain_paint_center_ring0_pending == 0:
		_pipeline.is_updating = false
	_log("boot", "ChunkManager load end center=%s" % center)

func process_tile_erase_queue(max_erases_per_pulse: int) -> void:
	var budget: int = maxi(0, max_erases_per_pulse)
	while budget > 0 and not _pending_tile_erases.is_empty():
		var cpos: Vector2i = _pending_tile_erases.pop_front()
		if _loaded_chunks.has(cpos):
			continue
		if _on_unload_chunk.is_valid():
			_on_unload_chunk.call(cpos)
		budget -= 1

func pending_tile_erase_count() -> int:
	return _pending_tile_erases.size()

func _compute_needed_chunks(center: Vector2i) -> Dictionary:
	var needed: Dictionary = {}
	var needed_chunks: Array[Vector2i] = []
	var max_chunk_x: int = int(floor(float(_width - 1) / float(_chunk_size)))
	var max_chunk_y: int = int(floor(float(_height - 1) / float(_chunk_size)))
	for cy in range(center.y - _active_radius, center.y + _active_radius + 1):
		for cx in range(center.x - _active_radius, center.x + _active_radius + 1):
			if cx < 0 or cx > max_chunk_x or cy < 0 or cy > max_chunk_y:
				continue
			var cpos := Vector2i(cx, cy)
			needed[cpos] = true
			needed_chunks.append(cpos)
	return {
		"needed": needed,
		"needed_chunks": needed_chunks,
	}

func _is_active_window_chunk(chunk_pos: Vector2i, center: Vector2i) -> bool:
	if _is_chunk_in_active_window.is_valid():
		return bool(_is_chunk_in_active_window.call(chunk_pos, center))
	return abs(chunk_pos.x - center.x) <= _active_radius and abs(chunk_pos.y - center.y) <= _active_radius

func _log(channel: String, msg: String) -> void:
	if _debug_log.is_valid():
		_debug_log.call(channel, msg)
