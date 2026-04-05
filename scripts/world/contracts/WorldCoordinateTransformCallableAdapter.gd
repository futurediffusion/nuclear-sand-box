extends WorldCoordinateTransformContract
class_name WorldCoordinateTransformCallableAdapter

# Transitional adapter backed by legacy callables.

var _world_to_tile_cb: Callable = Callable()
var _tile_to_world_cb: Callable = Callable()
var _tile_to_chunk_cb: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_world_to_tile_cb = ctx.get("world_to_tile", Callable())
	_tile_to_world_cb = ctx.get("tile_to_world", Callable())
	_tile_to_chunk_cb = ctx.get("tile_to_chunk", Callable())


func world_to_tile(world_pos: Vector2) -> Vector2i:
	if _world_to_tile_cb.is_valid():
		return _world_to_tile_cb.call(world_pos)
	return Vector2i.ZERO


func tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _tile_to_world_cb.is_valid():
		return _tile_to_world_cb.call(tile_pos)
	return Vector2.ZERO


func tile_to_chunk(tile_pos: Vector2i, chunk_size: int = 32) -> Vector2i:
	if _tile_to_chunk_cb.is_valid():
		return _tile_to_chunk_cb.call(tile_pos)
	return super.tile_to_chunk(tile_pos, chunk_size)
