extends WorldChunkDirtyNotifierContract
class_name WorldChunkDirtyNotifierCallableAdapter

# Transitional adapter backed by legacy chunk-dirty callback.

var _mark_chunk_dirty_cb: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_mark_chunk_dirty_cb = ctx.get("mark_chunk_walls_dirty", Callable())


func mark_chunk_dirty(chunk_pos: Vector2i) -> void:
	if not _mark_chunk_dirty_cb.is_valid():
		return
	_mark_chunk_dirty_cb.call(chunk_pos.x, chunk_pos.y)
