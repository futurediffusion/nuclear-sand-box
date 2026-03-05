extends Node

var _enemies: Array[WeakRef] = []
var _enemy_chunks: Dictionary = {} # instance_id -> Vector2i
var buckets: Dictionary = {} # Vector2i -> Array[Node2D]
var _enemy_bucket_indices: Dictionary = {} # instance_id -> index within bucket array
var _cleanup_timer: float = 0.0
var _index_cleanup_timer: float = 0.0
var _bucket_cleanup_cursor: int = 0
const CLEANUP_INTERVAL: float = 3.0
const CLEANUP_BUCKETS_PER_TICK: int = 6
const INDEX_CLEANUP_INTERVAL: float = 20.0
var _warned_missing_world: bool = false
var _cached_world: Node = null


func register_enemy(e: Node2D) -> void:
	if e == null:
		return

	for w: WeakRef in _enemies:
		var obj: Object = w.get_ref()
		if obj == e:
			return

	_enemies.append(weakref(e))
	update_enemy_chunk(e)


func unregister_enemy(e: Node2D) -> void:
	if e == null:
		return

	for i: int in range(_enemies.size() - 1, -1, -1):
		var obj: Object = _enemies[i].get_ref()
		if obj == null or obj == e:
			_enemies.remove_at(i)

	_remove_enemy_from_bucket(e)


func update_enemy_chunk(e: Node2D) -> void:
	if e == null:
		return
	var new_chunk_opt: Variant = world_to_chunk(e.global_position)
	if new_chunk_opt == null:
		return
	var new_chunk: Vector2i = new_chunk_opt
	var id := e.get_instance_id()
	if _enemy_chunks.has(id) and _enemy_chunks[id] == new_chunk:
		return

	_remove_enemy_from_bucket(e)
	_enemy_chunks[id] = new_chunk

	if not buckets.has(new_chunk):
		buckets[new_chunk] = []
	var bucket: Array = buckets[new_chunk]
	_enemy_bucket_indices[id] = bucket.size()
	bucket.append(e)
	buckets[new_chunk] = bucket


func get_live_enemies() -> Array[Node2D]:
	var out: Array[Node2D] = []

	for i: int in range(_enemies.size() - 1, -1, -1):
		var obj: Object = _enemies[i].get_ref()
		if obj == null:
			_enemies.remove_at(i)
			continue

		var enemy: Node2D = obj as Node2D
		if enemy != null:
			out.append(enemy)

	return out


func get_bucket_neighborhood(chunk_coord: Vector2i) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for y: int in range(chunk_coord.y - 1, chunk_coord.y + 2):
		for x: int in range(chunk_coord.x - 1, chunk_coord.x + 2):
			var c := Vector2i(x, y)
			if not buckets.has(c):
				continue
			var bucket: Array = buckets[c]
			for i: int in range(bucket.size() - 1, -1, -1):
				var enemy := bucket[i] as Node2D
				if enemy == null or not is_instance_valid(enemy):
					var removed_id := enemy.get_instance_id() if enemy != null and is_instance_valid(enemy) else -1
					_swap_remove_bucket_at(bucket, i)
					if removed_id != -1:
						_enemy_chunks.erase(removed_id)
						_enemy_bucket_indices.erase(removed_id)
					continue
				out.append(enemy)
			if bucket.is_empty():
				buckets.erase(c)
			else:
				buckets[c] = bucket
	return out


func world_to_chunk(pos: Vector2) -> Variant:
	var world: Node = _find_world_node()
	if world != null and world.has_method("world_to_chunk"):
		_warned_missing_world = false
		return world.world_to_chunk(pos)
	if not _warned_missing_world:
		_warned_missing_world = true
		push_warning("[EnemyRegistry] World not ready: skipping chunk assignment until world_to_chunk is available.")
	return null


func count() -> int:
	return get_live_enemies().size()


func _process(delta: float) -> void:
	_cleanup_timer += delta
	_index_cleanup_timer += delta
	if _cleanup_timer >= CLEANUP_INTERVAL:
		_cleanup_timer = 0.0
		_cleanup_invalid_buckets(CLEANUP_BUCKETS_PER_TICK)

	if _index_cleanup_timer >= INDEX_CLEANUP_INTERVAL:
		_index_cleanup_timer = 0.0
		_cleanup_orphan_indices()


func _cleanup_invalid_buckets(max_buckets: int) -> void:
	get_live_enemies() # fuerza limpieza de refs muertas
	if buckets.is_empty():
		_bucket_cleanup_cursor = 0
		return

	var keys: Array = buckets.keys()
	if _bucket_cleanup_cursor >= keys.size():
		_bucket_cleanup_cursor = 0

	var processed: int = 0
	while processed < max_buckets and not keys.is_empty():
		if _bucket_cleanup_cursor >= keys.size():
			_bucket_cleanup_cursor = 0
		var chunk_key: Variant = keys[_bucket_cleanup_cursor]
		_bucket_cleanup_cursor += 1
		processed += 1

		var bucket: Array = buckets[chunk_key]
		for i: int in range(bucket.size() - 1, -1, -1):
			var enemy := bucket[i] as Node2D
			if enemy == null or not is_instance_valid(enemy):
				var removed_id := enemy.get_instance_id() if enemy != null and is_instance_valid(enemy) else -1
				_swap_remove_bucket_at(bucket, i)
				if removed_id != -1:
					_enemy_chunks.erase(removed_id)
					_enemy_bucket_indices.erase(removed_id)
		if bucket.is_empty():
			buckets.erase(chunk_key)
			keys.remove_at(_bucket_cleanup_cursor - 1)
			_bucket_cleanup_cursor -= 1
		else:
			buckets[chunk_key] = bucket


func _cleanup_orphan_indices() -> void:
	var live_ids: Dictionary = {}
	for enemy in get_live_enemies():
		live_ids[enemy.get_instance_id()] = true

	for id in _enemy_chunks.keys():
		if not live_ids.has(id):
			_enemy_chunks.erase(id)
			_enemy_bucket_indices.erase(id)


func _remove_enemy_from_bucket(e: Node2D) -> void:
	var id := e.get_instance_id()
	if not _enemy_chunks.has(id):
		return

	var old_chunk: Vector2i = _enemy_chunks[id]
	if buckets.has(old_chunk):
		var old_bucket: Array = buckets[old_chunk]
		if _enemy_bucket_indices.has(id):
			var idx: int = _enemy_bucket_indices[id]
			if idx >= 0 and idx < old_bucket.size() and old_bucket[idx] == e:
				_swap_remove_bucket_at(old_bucket, idx)
			else:
				for i: int in range(old_bucket.size() - 1, -1, -1):
					if old_bucket[i] == e:
						_swap_remove_bucket_at(old_bucket, i)
						break
		else:
			for i: int in range(old_bucket.size() - 1, -1, -1):
				if old_bucket[i] == e:
					_swap_remove_bucket_at(old_bucket, i)
					break
		if old_bucket.is_empty():
			buckets.erase(old_chunk)
		else:
			buckets[old_chunk] = old_bucket
	_enemy_chunks.erase(id)
	_enemy_bucket_indices.erase(id)


func _swap_remove_bucket_at(bucket: Array, idx: int) -> void:
	var last_idx: int = bucket.size() - 1
	if idx < 0 or idx > last_idx:
		return
	if idx != last_idx:
		var swapped: Node2D = bucket[last_idx] as Node2D
		bucket[idx] = swapped
		if swapped != null and is_instance_valid(swapped):
			_enemy_bucket_indices[swapped.get_instance_id()] = idx
	bucket.remove_at(last_idx)



func _find_world_node() -> Node:
	if _cached_world != null and is_instance_valid(_cached_world):
		return _cached_world

	var tree := get_tree()
	if tree == null:
		return null

	var world_group: Array[Node] = tree.get_nodes_in_group("world")
	if not world_group.is_empty():
		_cached_world = world_group[0]
		return _cached_world

	_cached_world = tree.current_scene.get_node_or_null("World") if tree.current_scene != null else null
	return _cached_world
