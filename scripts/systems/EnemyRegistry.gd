extends Node

var _enemies: Array[WeakRef] = []
var _enemy_chunks: Dictionary = {} # instance_id -> Vector2i
var buckets: Dictionary = {} # Vector2i -> Array[Node2D]
var _cleanup_timer: float = 0.0
const CLEANUP_INTERVAL: float = 5.0


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
	var new_chunk := world_to_chunk(e.global_position)
	var id := e.get_instance_id()
	if _enemy_chunks.has(id) and _enemy_chunks[id] == new_chunk:
		return

	_remove_enemy_from_bucket(e)
	_enemy_chunks[id] = new_chunk

	if not buckets.has(new_chunk):
		buckets[new_chunk] = []
	var bucket: Array = buckets[new_chunk]
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
					bucket.remove_at(i)
					continue
				out.append(enemy)
			if bucket.is_empty():
				buckets.erase(c)
			else:
				buckets[c] = bucket
	return out


func world_to_chunk(pos: Vector2) -> Vector2i:
	var world: Node = _find_world_node()
	if world != null and world.has_method("world_to_chunk"):
		return world.world_to_chunk(pos)
	return Vector2i(int(floor(pos.x / 512.0)), int(floor(pos.y / 512.0)))


func count() -> int:
	return get_live_enemies().size()


func _process(delta: float) -> void:
	_cleanup_timer += delta
	if _cleanup_timer >= CLEANUP_INTERVAL:
		_cleanup_timer = 0.0
		_cleanup_invalid_entries()


func _cleanup_invalid_entries() -> void:
	get_live_enemies() # fuerza limpieza de refs muertas

	for chunk_key in buckets.keys():
		var bucket: Array = buckets[chunk_key]
		for i: int in range(bucket.size() - 1, -1, -1):
			var enemy := bucket[i] as Node2D
			if enemy == null or not is_instance_valid(enemy):
				bucket.remove_at(i)
		if bucket.is_empty():
			buckets.erase(chunk_key)
		else:
			buckets[chunk_key] = bucket

	for id in _enemy_chunks.keys():
		if not _has_enemy_with_id(id):
			_enemy_chunks.erase(id)


func _remove_enemy_from_bucket(e: Node2D) -> void:
	var id := e.get_instance_id()
	if not _enemy_chunks.has(id):
		return

	var old_chunk: Vector2i = _enemy_chunks[id]
	if buckets.has(old_chunk):
		var old_bucket: Array = buckets[old_chunk]
		for i: int in range(old_bucket.size() - 1, -1, -1):
			if old_bucket[i] == e:
				old_bucket.remove_at(i)
		if old_bucket.is_empty():
			buckets.erase(old_chunk)
		else:
			buckets[old_chunk] = old_bucket
	_enemy_chunks.erase(id)


func _has_enemy_with_id(id: int) -> bool:
	for w: WeakRef in _enemies:
		var obj: Object = w.get_ref()
		if obj != null and obj is Node and (obj as Node).get_instance_id() == id:
			return true
	return false


func _find_world_node() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var world_group: Array[Node] = tree.get_nodes_in_group("world")
	if not world_group.is_empty():
		return world_group[0]
	return tree.current_scene.get_node_or_null("World") if tree.current_scene != null else null
