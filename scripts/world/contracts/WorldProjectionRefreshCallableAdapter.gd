extends WorldProjectionRefreshContract
class_name WorldProjectionRefreshCallableAdapter

# Transitional adapter backed by legacy refresh/projection callback.

var _refresh_for_tiles_cb: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_refresh_for_tiles_cb = ctx.get("mark_chunk_walls_dirty_and_refresh_for_tiles", Callable())


func refresh_for_tiles(tile_positions: Array[Vector2i]) -> void:
	if not _refresh_for_tiles_cb.is_valid():
		return
	_refresh_for_tiles_cb.call(tile_positions)
