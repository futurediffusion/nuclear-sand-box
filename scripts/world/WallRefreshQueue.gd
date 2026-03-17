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

# Revision System for merging changes
var _requested_revisions: Dictionary = {} # chunk_pos -> int
var _rebuilt_revisions: Dictionary = {}   # chunk_pos -> int

func clear() -> void:
	_hot_queue.clear()
	_normal_queue.clear()
	_enqueued_status.clear()
	_activity_timestamps.clear()
	_last_rebuild_timestamps.clear()
	_requested_revisions.clear()
	_rebuilt_revisions.clear()

func record_activity(chunk_pos: Vector2i) -> void:
	var now := Time.get_ticks_msec()
	_activity_timestamps[chunk_pos] = now

	var status = _enqueued_status.get(chunk_pos, 0)
	if status == 1: # was normal, promote
		_promote_to_hot(chunk_pos)
	elif status == 2: # already hot, move to front (Most Recent First)
		_hot_queue.erase(chunk_pos)
		_hot_queue.push_front(chunk_pos)

func enqueue(chunk_pos: Vector2i) -> void:
	# Revision merge: every enqueue increments the requested revision
	_requested_revisions[chunk_pos] = _requested_revisions.get(chunk_pos, 0) + 1

	if _enqueued_status.has(chunk_pos):
		# If it's already hot, calling enqueue again also refreshes its priority
		if _enqueued_status[chunk_pos] == 2:
			_hot_queue.erase(chunk_pos)
			_hot_queue.push_front(chunk_pos)
		return

	if _is_hot(chunk_pos):
		_hot_queue.push_front(chunk_pos) # Most Recent First
		_enqueued_status[chunk_pos] = 2
	else:
		_normal_queue.append(chunk_pos)
		_enqueued_status[chunk_pos] = 1

func has_pending() -> bool:
	return not _hot_queue.is_empty() or not _normal_queue.is_empty()

## Selection Contract (Option A): Tries to pop the next ready chunk.
## Returns { "ok": bool, "chunk_pos": Vector2i, "revision": int, "next_ready_in_ms": int }
func try_pop_next() -> Dictionary:
	var now := Time.get_ticks_msec()

	# 1. Maintenance: Demote "cold" chunks from Hot to Normal queue
	_demote_cold_chunks(now)

	# 2. Try Hot Queue first
	var hot_result = _try_pop_from_queue(_hot_queue, now)
	if hot_result.ok:
		return hot_result

	# 3. Try Normal Queue
	var normal_result = _try_pop_from_queue(_normal_queue, now)
	if normal_result.ok:
		return normal_result

	# 4. Nothing ready this frame
	var next_wait = -1
	if hot_result.next_ready_in_ms != -1:
		next_wait = hot_result.next_ready_in_ms
	if normal_result.next_ready_in_ms != -1:
		if next_wait == -1 or normal_result.next_ready_in_ms < next_wait:
			next_wait = normal_result.next_ready_in_ms

	return {
		"ok": false,
		"chunk_pos": Vector2i(-999999, -999999),
		"revision": -1,
		"next_ready_in_ms": next_wait
	}

func confirm_rebuild(chunk_pos: Vector2i, revision: int) -> void:
	_rebuilt_revisions[chunk_pos] = revision
	_last_rebuild_timestamps[chunk_pos] = Time.get_ticks_msec()

func purge_chunk(chunk_pos: Vector2i) -> void:
	_hot_queue.erase(chunk_pos)
	_normal_queue.erase(chunk_pos)
	_enqueued_status.erase(chunk_pos)
	_activity_timestamps.erase(chunk_pos)
	_last_rebuild_timestamps.erase(chunk_pos)
	_requested_revisions.erase(chunk_pos)
	_rebuilt_revisions.erase(chunk_pos)

func _is_hot(chunk_pos: Vector2i) -> bool:
	var ts = _activity_timestamps.get(chunk_pos, 0)
	if ts == 0: return false
	return (Time.get_ticks_msec() - ts) < HOT_THRESHOLD_MS

func _promote_to_hot(chunk_pos: Vector2i) -> void:
	_normal_queue.erase(chunk_pos)
	_hot_queue.push_front(chunk_pos) # Most Recent First
	_enqueued_status[chunk_pos] = 2

func _demote_cold_chunks(now: int) -> void:
	var i := 0
	while i < _hot_queue.size():
		var chunk_pos = _hot_queue[i]
		# Use a local check with passed 'now' for consistency during this frame
		var ts = _activity_timestamps.get(chunk_pos, 0)
		if (now - ts) >= HOT_THRESHOLD_MS:
			_hot_queue.remove_at(i)
			_normal_queue.append(chunk_pos)
			_enqueued_status[chunk_pos] = 1
		else:
			i += 1

func _try_pop_from_queue(queue: Array[Vector2i], now: int) -> Dictionary:
	var min_wait = -1

	for i in range(queue.size()):
		var chunk_pos = queue[i]

		# Check cooldown
		var last_rebuild = _last_rebuild_timestamps.get(chunk_pos, 0)
		var elapsed = now - last_rebuild
		if elapsed < REFRESH_COOLDOWN_MS:
			var wait = REFRESH_COOLDOWN_MS - elapsed
			if min_wait == -1 or wait < min_wait:
				min_wait = wait
			continue # Skip this chunk for now, it's in cooldown

		queue.remove_at(i)
		_enqueued_status.erase(chunk_pos)

		# Cleanup activity timestamp if it's old
		if not _is_hot(chunk_pos):
			_activity_timestamps.erase(chunk_pos)

		return {
			"ok": true,
			"chunk_pos": chunk_pos,
			"revision": _requested_revisions.get(chunk_pos, 0),
			"next_ready_in_ms": 0
		}

	return {
		"ok": false,
		"chunk_pos": Vector2i(-999999, -999999),
		"revision": -1,
		"next_ready_in_ms": min_wait
	}
