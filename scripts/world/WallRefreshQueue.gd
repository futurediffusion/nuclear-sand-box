extends RefCounted
class_name WallRefreshQueue

# Period after activity where a chunk is considered "Hot"
const HOT_THRESHOLD_MS: int = 2000
# Minimum time between rebuilds for the same chunk to avoid "rebuild spam"
const REBUILD_COOLDOWN_MS: int = 200

var _hot_queue: Array[Vector2i] = []
var _normal_queue: Array[Vector2i] = []
var _enqueued: Dictionary = {} # chunk_pos -> bool

var _activity_timestamps: Dictionary = {}
var _last_rebuild_timestamps: Dictionary = {}

func clear() -> void:
	_hot_queue.clear()
	_normal_queue.clear()
	_enqueued.clear()
	_activity_timestamps.clear()
	_last_rebuild_timestamps.clear()

func record_activity(chunk_pos: Vector2i) -> void:
	var now = Time.get_ticks_msec()
	_activity_timestamps[chunk_pos] = now

	# If it was in normal queue, promote it to hot
	if _enqueued.get(chunk_pos, false):
		if _normal_queue.has(chunk_pos):
			_normal_queue.erase(chunk_pos)
			_hot_queue.append(chunk_pos)

func enqueue(chunk_pos: Vector2i) -> void:
	if _enqueued.has(chunk_pos):
		return

	var now = Time.get_ticks_msec()
	var last_activity = _activity_timestamps.get(chunk_pos, 0)

	if now - last_activity < HOT_THRESHOLD_MS:
		_hot_queue.append(chunk_pos)
	else:
		_normal_queue.append(chunk_pos)

	_enqueued[chunk_pos] = true

func on_chunk_unloaded(chunk_pos: Vector2i) -> void:
	_hot_queue.erase(chunk_pos)
	_normal_queue.erase(chunk_pos)
	_enqueued.erase(chunk_pos)
	_activity_timestamps.erase(chunk_pos)
	_last_rebuild_timestamps.erase(chunk_pos)

func has_pending() -> bool:
	return not _hot_queue.is_empty() or not _normal_queue.is_empty()

func pop_next() -> Vector2i:
	var now = Time.get_ticks_msec()

	# 1. Try Hot Queue
	var result = _pop_from_queue_respecting_cooldown(_hot_queue, now)
	if result != Vector2i(-999999, -999999):
		return result

	# 2. Try Normal Queue
	result = _pop_from_queue_respecting_cooldown(_normal_queue, now)
	return result

func _pop_from_queue_respecting_cooldown(queue: Array[Vector2i], now: int) -> Vector2i:
	for i in range(queue.size()):
		var cpos = queue[i]
		var last_rebuild = _last_rebuild_timestamps.get(cpos, 0)

		if now - last_rebuild >= REBUILD_COOLDOWN_MS:
			queue.remove_at(i)
			_enqueued.erase(cpos)
			_last_rebuild_timestamps[cpos] = now
			return cpos

	return Vector2i(-999999, -999999)

# Periodic cleanup of old timestamps to prevent memory growth
# Can be called occasionally from world.gd
func prune_old_activity(max_age_ms: int = 30000) -> void:
	var now = Time.get_ticks_msec()
	var to_remove = []

	for cpos in _activity_timestamps:
		if now - _activity_timestamps[cpos] > max_age_ms:
			# Only remove if NOT enqueued
			if not _enqueued.has(cpos):
				to_remove.append(cpos)

	for cpos in to_remove:
		_activity_timestamps.erase(cpos)

	# Also prune last rebuild timestamps for chunks not in sight
	to_remove = []
	for cpos in _last_rebuild_timestamps:
		if now - _last_rebuild_timestamps[cpos] > max_age_ms:
			if not _enqueued.has(cpos):
				to_remove.append(cpos)
	for cpos in to_remove:
		_last_rebuild_timestamps.erase(cpos)
