extends RefCounted
class_name WallRefreshQueue

var _queue: Array[Vector2i] = []
var _enqueued: Dictionary = {}
var _activity_timestamps: Dictionary = {}

func clear() -> void:
	_queue.clear()
	_enqueued.clear()
	_activity_timestamps.clear()

func record_activity(chunk_pos: Vector2i) -> void:
	_activity_timestamps[chunk_pos] = Time.get_ticks_msec()

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

	# Prioritize chunks with recent activity
	var best_idx: int = 0
	var max_ts: int = -1

	for i in range(_queue.size()):
		var cpos = _queue[i]
		var ts = _activity_timestamps.get(cpos, 0)
		if ts > max_ts:
			max_ts = ts
			best_idx = i

	var chunk_pos: Vector2i = _queue[best_idx]
	_queue.remove_at(best_idx)
	_enqueued.erase(chunk_pos)
	_activity_timestamps.erase(chunk_pos)
	return chunk_pos
