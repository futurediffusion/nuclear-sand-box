extends RefCounted
class_name WallRefreshQueue

var _queue: Array[Vector2i] = []
var _enqueued: Dictionary = {}

func clear() -> void:
	_queue.clear()
	_enqueued.clear()

func enqueue(chunk_pos: Vector2i) -> void:
	if _enqueued.has(chunk_pos):
		return
	_queue.append(chunk_pos)
	_enqueued[chunk_pos] = true

func has_pending() -> bool:
	return not _queue.is_empty()

func pop_next() -> Vector2i:
	if _queue.is_empty():
		return Vector2i(-999999, -999999)
	var chunk_pos: Vector2i = _queue.pop_front()
	_enqueued.erase(chunk_pos)
	return chunk_pos
