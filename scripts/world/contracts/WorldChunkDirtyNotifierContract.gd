extends RefCounted
class_name WorldChunkDirtyNotifierContract

# Typed contract for chunk invalidation notifications.

func mark_chunk_dirty(_chunk_pos: Vector2i) -> void:
	pass
