extends RefCounted
class_name WorldChunkMaintenanceCoordinator

var _wall_refresh_queue: WallRefreshQueue
var _loaded_chunks: Dictionary
var _pending_tile_erases: Array[Vector2i] = []
var _ensure_chunk_wall_collision: Callable
var _unload_chunk: Callable

func setup(ctx: Dictionary) -> void:
	_wall_refresh_queue = ctx.get("wall_refresh_queue")
	_loaded_chunks = ctx.get("loaded_chunks", {})
	_pending_tile_erases = ctx.get("pending_tile_erases", [])
	_ensure_chunk_wall_collision = ctx.get("ensure_chunk_wall_collision", Callable())
	_unload_chunk = ctx.get("unload_chunk", Callable())

func process_queues(max_rebuilds_per_frame: int = 1, max_tile_erases_per_frame: int = 2) -> void:
	_process_wall_refresh_queue(max_rebuilds_per_frame)
	_process_tile_erase_queue(max_tile_erases_per_frame)

func enqueue_tile_erase(chunk_pos: Vector2i) -> void:
	_pending_tile_erases.append(chunk_pos)

func record_wall_activity_and_enqueue(chunk_pos: Vector2i, should_enqueue: bool) -> void:
	if _wall_refresh_queue == null:
		return
	_wall_refresh_queue.record_activity(chunk_pos)
	if should_enqueue:
		_wall_refresh_queue.enqueue(chunk_pos)

func purge_wall_refresh_for_chunk(chunk_pos: Vector2i) -> void:
	if _wall_refresh_queue != null:
		_wall_refresh_queue.purge_chunk(chunk_pos)

func get_wall_refresh_debug_snapshot() -> Dictionary:
	if _wall_refresh_queue == null:
		return {}
	return _wall_refresh_queue.get_debug_snapshot()

func get_pending_tile_erases_count() -> int:
	return _pending_tile_erases.size()

func _process_tile_erase_queue(max_tile_erases_per_frame: int) -> void:
	var budget := maxi(0, max_tile_erases_per_frame)
	while budget > 0 and not _pending_tile_erases.is_empty():
		var cpos: Vector2i = _pending_tile_erases.pop_front()
		if _loaded_chunks.has(cpos):
			continue
		if _unload_chunk.is_valid():
			_unload_chunk.call(cpos)
		budget -= 1

func _process_wall_refresh_queue(max_rebuilds_per_frame: int = 1) -> void:
	if _wall_refresh_queue == null:
		return
	var rebuild_budget: int = maxi(0, max_rebuilds_per_frame)
	while rebuild_budget > 0:
		var result: Dictionary = _wall_refresh_queue.try_pop_next()
		if not result.ok:
			break
		var chunk_pos: Vector2i = result.chunk_pos
		if not _loaded_chunks.has(chunk_pos):
			_wall_refresh_queue.purge_chunk(chunk_pos)
			continue
		if _ensure_chunk_wall_collision.is_valid():
			_ensure_chunk_wall_collision.call(chunk_pos)
		_wall_refresh_queue.confirm_rebuild(chunk_pos, result.revision)
		rebuild_budget -= 1
