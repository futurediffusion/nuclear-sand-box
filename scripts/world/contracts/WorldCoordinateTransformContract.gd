extends RefCounted
class_name WorldCoordinateTransformContract

# Typed contract for world/tile/chunk coordinate transforms.
# Transitional goal (Phase 1): remove ad-hoc callable wiring from setup(ctx).

func world_to_tile(_world_pos: Vector2) -> Vector2i:
	return Vector2i.ZERO


func tile_to_world(_tile_pos: Vector2i) -> Vector2:
	return Vector2.ZERO


func tile_to_chunk(tile_pos: Vector2i, chunk_size: int = 32) -> Vector2i:
	return Vector2i(int(floor(float(tile_pos.x) / float(chunk_size))), int(floor(float(tile_pos.y) / float(chunk_size))))
