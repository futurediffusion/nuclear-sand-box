extends RefCounted
class_name WallRefreshQueue

# Chunks with activity in the last 2000ms are considered Hot
const HOT_THRESHOLD_MS: int = 2000
# Cooldown between rebuilds for the same chunk to prevent "rebuild serrucho"
const REFRESH_COOLDOWN_MS: int = 200

# Tiered queues for O(1) prioritization
var _hot_queue: Array[Vector2i] = []
var _normal_queue: Array[Vector2i] = []

# State tracking
var _enqueued_status: Dictionary = {} # chunk_pos -> int (0: none, 1: normal, 2: hot)
var _activity_timestamps: Dictionary = {} # chunk_pos -> int (last activity)
var _last_rebuild_timestamps: Dictionary = {} # chunk_pos -> int (last successful pop)

func clear() -> void:
	_hot_queue.clear()
	_normal_queue.clear()
	_enqueued_status.clear()
	_activity_timestamps.clear()
	_last_rebuild_timestamps.clear()

func record_activity(chunk_pos: Vector2i) -> void:
	var now := Time.get_ticks_msec()
	_activity_timestamps[chunk_pos] = now

	# If it was in the normal queue, promote it to hot
	if _enqueued_status.get(chunk_pos, 0) == 1:
		_promote_to_hot(chunk_pos)

func enqueue(chunk_pos: Vector2i) -> void:
	if _enqueued_status.has(chunk_pos):
		return

	if _is_hot(chunk_pos):
		_hot_queue.append(chunk_pos)
		_enqueued_status[chunk_pos] = 2
	else:
		_normal_queue.append(chunk_pos)
		_enqueued_status[chunk_pos] = 1

func has_pending() -> bool:
	return not _hot_queue.is_empty() or not _normal_queue.is_empty()

func pop_next() -> Vector2i:
	var now := Time.get_ticks_msec()

	# 1. Try Hot Queue first
	var hot_chunk = _pop_from_queue(_hot_queue, now)
	if hot_chunk != Vector2i(-999999, -999999):
		return hot_chunk

	# 2. Try Normal Queue
	return _pop_from_queue(_normal_queue, now)

func purge_chunk(chunk_pos: Vector2i) -> void:
	_hot_queue.erase(chunk_pos)
	_normal_queue.erase(chunk_pos)
	_enqueued_status.erase(chunk_pos)
	_activity_timestamps.erase(chunk_pos)
	_last_rebuild_timestamps.erase(chunk_pos)

func _is_hot(chunk_pos: Vector2i) -> bool:
	var ts = _activity_timestamps.get(chunk_pos, 0)
	return (Time.get_ticks_msec() - ts) < HOT_THRESHOLD_MS

func _promote_to_hot(chunk_pos: Vector2i) -> void:
	_normal_queue.erase(chunk_pos)
	_hot_queue.append(chunk_pos)
	_enqueued_status[chunk_pos] = 2

func _pop_from_queue(queue: Array[Vector2i], now: int) -> Vector2i:
	for i in range(queue.size()):
		var chunk_pos = queue[i]

		# Check cooldown
		var last_rebuild = _last_rebuild_timestamps.get(chunk_pos, 0)
		if (now - last_rebuild) < REFRESH_COOLDOWN_MS:
			continue # Skip this chunk for now, it's in cooldown

		queue.remove_at(i)
		_enqueued_status.erase(chunk_pos)
		_last_rebuild_timestamps[chunk_pos] = now

		# Cleanup activity timestamp if it's old (optional, but keeps memory clean)
		if not _is_hot(chunk_pos):
			_activity_timestamps.erase(chunk_pos)

		return chunk_pos

	return Vector2i(-999999, -999999)
