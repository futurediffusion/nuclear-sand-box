extends Node
class_name SpawnBudgetQueue

signal job_spawned(job: Dictionary, node: Node)
signal job_skipped(job: Dictionary, reason: String)

@export var max_spawns_per_frame: int = 6
@export var max_ms_per_frame: float = 2.0
@export var enable_time_budget: bool = true
@export var enable_count_budget: bool = true
@export var debug_spawn_queue: bool = false
@export var sort_interval_frames: int = 6
@export var reorder_player_distance_threshold: float = 96.0

var spawn_parent: Node
var chunk_active_checker: Callable

var _queue: Array[Dictionary] = []
var _by_key: Dictionary = {}
var _chunk_index: Dictionary = {}
var _player_pos: Vector2 = Vector2.ZERO
var _frame_counter: int = 0
var _queue_dirty: bool = false
var _last_sort_player_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func enqueue(job: Dictionary) -> void:
	if job.is_empty():
		return
	var normalized: Dictionary = _normalize_job(job)
	if normalized.is_empty():
		return
	var dedupe_key: String = String(normalized["dedupe_key"])
	if _by_key.has(dedupe_key):
		return
	_queue.append(normalized)
	_by_key[dedupe_key] = true
	_queue_dirty = true
	var chunk_key: String = String(normalized["chunk_key"])
	if not _chunk_index.has(chunk_key):
		_chunk_index[chunk_key] = []
	_chunk_index[chunk_key].append(dedupe_key)

func enqueue_many(jobs: Array[Dictionary]) -> void:
	for job in jobs:
		enqueue(job)

func process_queue(_delta: float) -> void:
	if get_tree() == null or get_tree().paused:
		return
	if _queue.is_empty():
		return
	_frame_counter += 1
	if _frame_counter % max(1, sort_interval_frames) == 0 and _should_reorder_queue():
		_queue.sort_custom(_job_less)
		_queue_dirty = false
		_last_sort_player_pos = _player_pos

	var t0: int = Time.get_ticks_usec()
	var spawned: int = 0

	while not _queue.is_empty():
		if enable_count_budget and spawned >= max_spawns_per_frame:
			break
		if enable_time_budget:
			var elapsed_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
			if elapsed_ms >= max_ms_per_frame:
				break

		var job: Dictionary = _queue.pop_front()
		var dedupe_key: String = String(job.get("dedupe_key", ""))
		# Always free dedupe tracking before any skip path so skipped jobs never lock keys.
		_by_key.erase(dedupe_key)
		_remove_from_chunk_index(String(job.get("chunk_key", "")), dedupe_key)

		if not _is_chunk_active(String(job.get("chunk_key", ""))):
			job_skipped.emit(job, "chunk_inactive")
			continue

		var spawned_node := _spawn_job(job)
		if spawned_node == null:
			job_skipped.emit(job, "spawn_failed")
			continue

		spawned += 1
		job_spawned.emit(job, spawned_node)

func cancel_chunk(chunk_key: String) -> void:
	if not _chunk_index.has(chunk_key):
		return
	var keys: Array = _chunk_index.get(chunk_key, [])
	if keys.is_empty():
		_chunk_index.erase(chunk_key)
		return
	var key_set: Dictionary = {}
	for key in keys:
		key_set[String(key)] = true
	for i in range(_queue.size() - 1, -1, -1):
		var dedupe_key: String = String(_queue[i].get("dedupe_key", ""))
		if key_set.has(dedupe_key):
			_queue.remove_at(i)
			_queue_dirty = true
	for key in keys:
		_by_key.erase(String(key))
	_chunk_index.erase(chunk_key)

func set_player_world_pos(pos: Vector2) -> void:
	_player_pos = pos

func get_pending_count() -> int:
	return _queue.size()

func debug_dump() -> Dictionary:
	return {
		"pending": _queue.size(),
		"keys": _by_key.size(),
		"chunks": _chunk_index.size(),
	}

func _normalize_job(job: Dictionary) -> Dictionary:
	var chunk_key: String = String(job.get("chunk_key", ""))
	if chunk_key == "":
		return {}

	var scene: PackedScene = job.get("scene", null) as PackedScene
	if scene == null and job.has("scene_path"):
		var path: String = String(job.get("scene_path", ""))
		if path != "":
			scene = load(path) as PackedScene
	if scene == null:
		return {}

	var normalized: Dictionary = job.duplicate(true)
	normalized["scene"] = scene
	if not normalized.has("global_position"):
		normalized["global_position"] = Vector2.ZERO
	if not normalized.has("kind"):
		normalized["kind"] = "unknown"
	if not normalized.has("init_data"):
		normalized["init_data"] = {}
	if not normalized.has("priority"):
		normalized["priority"] = int(job.get("chunk_distance_ring", 999))
	normalized["dedupe_key"] = _compute_dedupe_key(normalized)
	return normalized

func _compute_dedupe_key(job: Dictionary) -> String:
	var chunk_key: String = String(job.get("chunk_key", ""))
	var uid: String = String(job.get("uid", ""))
	if uid != "":
		return "%s:%s" % [chunk_key, uid]
	return "%s:%s:%s" % [chunk_key, String(job.get("kind", "unknown")), str(job.get("global_position", Vector2.ZERO))]

func _job_less(a: Dictionary, b: Dictionary) -> bool:
	var ap: int = int(a.get("priority", 999999))
	var bp: int = int(b.get("priority", 999999))
	if ap == bp:
		var ad: float = (_player_pos - Vector2(a.get("global_position", Vector2.ZERO))).length_squared()
		var bd: float = (_player_pos - Vector2(b.get("global_position", Vector2.ZERO))).length_squared()
		return ad < bd
	return ap < bp

func _should_reorder_queue() -> bool:
	if _queue.size() <= 1:
		return false
	if _queue_dirty:
		return true
	var threshold: float = max(0.0, reorder_player_distance_threshold)
	if threshold <= 0.0:
		return true
	var moved_sq: float = (_player_pos - _last_sort_player_pos).length_squared()
	return moved_sq >= threshold * threshold

func _spawn_job(job: Dictionary) -> Node:
	var scene: PackedScene = job.get("scene", null) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	if node == null:
		return null

	var target_parent: Node = spawn_parent
	if target_parent == null:
		if get_tree() != null and get_tree().current_scene != null:
			target_parent = get_tree().current_scene
		elif get_tree() != null:
			target_parent = get_tree().root
	if target_parent == null:
		node.queue_free()
		return null

	target_parent.add_child(node)
	if node is Node2D:
		(node as Node2D).global_position = Vector2(job.get("global_position", Vector2.ZERO))

	_apply_init_data(node, Dictionary(job.get("init_data", {})))
	return node

func _apply_init_data(node: Node, init_data: Dictionary) -> void:
	if init_data.is_empty():
		return
	if node.has_method("apply_spawn_data"):
		node.call("apply_spawn_data", init_data)

	if init_data.has("properties"):
		var props: Dictionary = init_data["properties"]
		for key in props.keys():
			node.set(String(key), props[key])

	if init_data.has("save_state") and node.has_method("apply_save_state"):
		var save_state: Variant = init_data["save_state"]
		if save_state is Dictionary:
			node.call("apply_save_state", save_state)

	if init_data.has("setup_args") and node.has_method("setup"):
		var args: Variant = init_data["setup_args"]
		if args is Array:
			node.callv("setup", args)

func _remove_from_chunk_index(chunk_key: String, dedupe_key: String) -> void:
	if not _chunk_index.has(chunk_key):
		return
	var keys: Array = _chunk_index[chunk_key]
	for i in range(keys.size() - 1, -1, -1):
		if String(keys[i]) == dedupe_key:
			keys.remove_at(i)
	if keys.is_empty():
		_chunk_index.erase(chunk_key)
	else:
		_chunk_index[chunk_key] = keys

func _is_chunk_active(chunk_key: String) -> bool:
	if chunk_active_checker.is_valid():
		return bool(chunk_active_checker.call(chunk_key))
	return true
