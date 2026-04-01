class_name WorldSpatialIndex
extends Node

# Spatial interface boundary: "where/query".
# Small, pragmatic helper for common world queries and retrieval.
# Runtime world entities (drops/resources/loaded workbenches/storage) are indexed
# by chunk with live node references.
# Persistent placeables still live canonically in WorldSave. This class only
# offers query helpers plus small derived views over that persistence data.

const KIND_ITEM_DROP: StringName = &"item_drop"
const KIND_WORLD_RESOURCE: StringName = &"world_resource"
const KIND_WORKBENCH: StringName = &"workbench"
const KIND_STORAGE: StringName = &"storage"
const PLACEABLE_CACHE_CONSISTENCY_INTERVAL_SEC: float = 10.0

var _world_to_tile_cb: Callable
var _tile_to_world_cb: Callable
var _chunk_size: int = 32

# kind -> chunk_key -> {instance_id: Node}
var _runtime_nodes_by_kind: Dictionary = {}
# instance_id -> {"kind": StringName, "chunk_key": String, "node": Node}
var _runtime_meta_by_id: Dictionary = {}
# Derived persistent view: item_id -> chunk_key -> Array[Dictionary].
# This is rebuilt from WorldSave when its structural revision changes.
var _placeables_cache_revision: int = -1
var _placeables_by_item_id_and_chunk: Dictionary = {}

var _queries_total: int = 0
var _queries_with_hits: int = 0
var _consistency_checks_total: int = 0
var _consistency_checks_failed: int = 0
var _last_consistency_issue: String = ""
var _last_consistency_check_msec: int = 0


func setup(ctx: Dictionary) -> void:
	_world_to_tile_cb = ctx.get("world_to_tile", Callable())
	_tile_to_world_cb = ctx.get("tile_to_world", Callable())
	_chunk_size = maxi(int(ctx.get("chunk_size", 32)), 1)
	_last_consistency_check_msec = Time.get_ticks_msec()
	add_to_group("world_spatial_index")
	set_process(true)


func _process(_delta: float) -> void:
	var now_msec: int = Time.get_ticks_msec()
	var elapsed_sec: float = float(now_msec - _last_consistency_check_msec) / 1000.0
	if elapsed_sec < PLACEABLE_CACHE_CONSISTENCY_INTERVAL_SEC:
		return
	_last_consistency_check_msec = now_msec
	_run_placeables_consistency_check()


func register_runtime_node(kind: StringName, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var node2d := node as Node2D
	if node2d == null:
		return
	var iid: int = node.get_instance_id()
	_unregister_runtime_id(iid)
	var chunk_key := _world_to_chunk_key(node2d.global_position)
	var by_chunk: Dictionary = _ensure_runtime_kind(kind)
	if not by_chunk.has(chunk_key):
		by_chunk[chunk_key] = {}
	var chunk_bucket: Dictionary = by_chunk[chunk_key]
	chunk_bucket[iid] = node
	_runtime_meta_by_id[iid] = {
		"kind": kind,
		"chunk_key": chunk_key,
		"node": node,
	}


func unregister_runtime_node(node: Node) -> void:
	if node == null:
		return
	_unregister_runtime_id(node.get_instance_id())


func update_runtime_node(kind: StringName, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var iid: int = node.get_instance_id()
	var node2d := node as Node2D
	if node2d == null:
		return
	var next_chunk_key := _world_to_chunk_key(node2d.global_position)
	var meta: Dictionary = _runtime_meta_by_id.get(iid, {})
	if meta.is_empty():
		register_runtime_node(kind, node)
		return
	if StringName(meta.get("kind", &"")) != kind or String(meta.get("chunk_key", "")) != next_chunk_key:
		register_runtime_node(kind, node)


func get_runtime_nodes_near(kind: StringName, world_pos: Vector2, radius: float) -> Array:
	_queries_total += 1
	var result: Array = []
	var r2: float = radius * radius
	for chunk_key in _get_chunk_keys_for_radius(world_pos, radius):
		var bucket: Dictionary = _get_runtime_bucket(kind, chunk_key)
		if bucket.is_empty():
			continue
		var stale_ids: Array[int] = []
		for iid in bucket.keys():
			var node: Node = bucket[iid]
			var node2d := node as Node2D
			if node == null or not is_instance_valid(node) or node2d == null or node.is_queued_for_deletion():
				stale_ids.append(int(iid))
				continue
			var actual_chunk_key := _world_to_chunk_key(node2d.global_position)
			if actual_chunk_key != chunk_key:
				register_runtime_node(kind, node)
				continue
			if node2d.global_position.distance_squared_to(world_pos) <= r2:
				result.append(node)
		for stale_id in stale_ids:
			_unregister_runtime_id(stale_id)
	if result.size() > 0:
		_queries_with_hits += 1
	return result



func get_all_runtime_nodes(kind: StringName) -> Array:
	var result: Array = []
	var by_chunk: Dictionary = _runtime_nodes_by_kind.get(kind, {})
	for chunk_key in by_chunk.keys():
		var bucket: Dictionary = by_chunk[chunk_key]
		var stale_ids: Array[int] = []
		for iid in bucket.keys():
			var node: Node = bucket[iid]
			if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
				stale_ids.append(int(iid))
				continue
			result.append(node)
		for stale_id in stale_ids:
			_unregister_runtime_id(stale_id)
	return result


func get_placeables_by_item_ids_near(world_pos: Vector2, radius: float, item_ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var filter: Dictionary = _array_to_string_set(item_ids)
	var r2: float = radius * radius
	for chunk_key in _get_chunk_keys_for_radius(world_pos, radius):
		var entries: Array[Dictionary] = get_placeables_in_chunk_key(chunk_key, item_ids)
		for entry in entries:
			var item_id := String(entry.get("item_id", "")).strip_edges()
			if not filter.is_empty() and not filter.has(item_id):
				continue
			var wpos := _entry_world_pos(entry)
			if wpos.distance_squared_to(world_pos) <= r2:
				result.append(entry)
	return result


func get_placeables_in_chunk_key(chunk_key: String, item_ids: Array[String] = []) -> Array[Dictionary]:
	var parts := chunk_key.split(",")
	if parts.size() != 2:
		return []
	return get_placeables_in_chunk(int(parts[0]), int(parts[1]), item_ids)


func get_placeables_in_chunk(cx: int, cy: int, item_ids: Array[String] = []) -> Array[Dictionary]:
	if item_ids.is_empty():
		return WorldSave.get_placed_entities_in_chunk(cx, cy)
	_ensure_placeables_cache()
	var filter: Dictionary = _array_to_string_set(item_ids)
	var result: Array[Dictionary] = []
	for item_id in filter.keys():
		var chunk_entries: Array = _get_cached_placeables_for_item_in_chunk(String(item_id), WorldSave.chunk_key(cx, cy))
		for entry in chunk_entries:
			result.append((entry as Dictionary).duplicate(true))
	return result


## Derived cache maintenance API.
## Only canonical truth changes in WorldSave may alter cache contents.
func invalidate_placeables_cache(reason: String = "manual") -> void:
	_placeables_cache_revision = -1
	_placeables_by_item_id_and_chunk.clear()
	if reason.strip_edges() != "":
		print_debug("WorldSpatialIndex.invalidate_placeables_cache reason=%s" % reason)


func rebuild_placeables_cache_from_truth(reason: String = "manual") -> void:
	invalidate_placeables_cache(reason)
	_ensure_placeables_cache()


## Explicitly block domain writes into derived cache.
func try_write_placeables_cache(_item_id: String, _chunk_key: String, _entries: Array[Dictionary]) -> int:
	push_warning("WorldSpatialIndex blocks semantic writes to derived placeables cache. Update WorldSave canonical truth instead.")
	return ERR_UNAUTHORIZED


## Persistent query helper only.
## Reads a derived WorldSave view; does not turn placeables into live runtime nodes.
func get_all_placeables_by_item_id(item_id: String) -> Array[Dictionary]:
	var key := item_id.strip_edges()
	if key == "":
		return []
	_ensure_placeables_cache()
	var result: Array[Dictionary] = []
	var by_chunk: Dictionary = _placeables_by_item_id_and_chunk.get(key, {})
	for chunk_entries in by_chunk.values():
		for entry in chunk_entries:
			result.append((entry as Dictionary).duplicate(true))
	return result


func get_placeables_in_tile_rect(min_x: int, min_y: int, w: int, h: int, item_ids: Array[String] = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var max_x: int = min_x + w - 1
	var max_y: int = min_y + h - 1
	var min_cx: int = int(floor(float(min_x) / float(_chunk_size)))
	var max_cx: int = int(floor(float(max_x) / float(_chunk_size)))
	var min_cy: int = int(floor(float(min_y) / float(_chunk_size)))
	var max_cy: int = int(floor(float(max_y) / float(_chunk_size)))
	var filter: Dictionary = _array_to_string_set(item_ids)
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			for entry in WorldSave.get_placed_entities_in_chunk(cx, cy):
				var tx: int = int(entry.get("tile_pos_x", 0))
				var ty: int = int(entry.get("tile_pos_y", 0))
				if tx < min_x or tx > max_x or ty < min_y or ty > max_y:
					continue
				var item_id := String(entry.get("item_id", "")).strip_edges()
				if not filter.is_empty() and not filter.has(item_id):
					continue
				result.append(entry)
	return result


func find_nearest_runtime_node(kind: StringName, world_pos: Vector2, radius: float) -> Node2D:
	var best: Node2D = null
	var best_dsq: float = radius * radius
	for raw_node in get_runtime_nodes_near(kind, world_pos, radius):
		var node := raw_node as Node2D
		if node == null:
			continue
		var dsq := node.global_position.distance_squared_to(world_pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best = node
	return best


func _ensure_runtime_kind(kind: StringName) -> Dictionary:
	if not _runtime_nodes_by_kind.has(kind):
		_runtime_nodes_by_kind[kind] = {}
	return _runtime_nodes_by_kind[kind]


func _get_runtime_bucket(kind: StringName, chunk_key: String) -> Dictionary:
	var by_chunk: Dictionary = _runtime_nodes_by_kind.get(kind, {})
	return by_chunk.get(chunk_key, {})


func _unregister_runtime_id(iid: int) -> void:
	var meta: Dictionary = _runtime_meta_by_id.get(iid, {})
	if meta.is_empty():
		return
	var kind: StringName = meta.get("kind", &"")
	var chunk_key: String = String(meta.get("chunk_key", ""))
	var by_chunk: Dictionary = _runtime_nodes_by_kind.get(kind, {})
	if by_chunk.has(chunk_key):
		var bucket: Dictionary = by_chunk[chunk_key]
		bucket.erase(iid)
		if bucket.is_empty():
			by_chunk.erase(chunk_key)
	_runtime_meta_by_id.erase(iid)


func _get_chunk_keys_for_radius(world_pos: Vector2, radius: float) -> Array[String]:
	var min_world := world_pos - Vector2(radius, radius)
	var max_world := world_pos + Vector2(radius, radius)
	var min_chunk := _world_to_chunk(_world_to_tile(min_world))
	var max_chunk := _world_to_chunk(_world_to_tile(max_world))
	var result: Array[String] = []
	for cy in range(min_chunk.y, max_chunk.y + 1):
		for cx in range(min_chunk.x, max_chunk.x + 1):
			result.append("%d,%d" % [cx, cy])
	return result


func _world_to_chunk_key(world_pos: Vector2) -> String:
	var tile := _world_to_tile(world_pos)
	var chunk := _world_to_chunk(tile)
	return "%d,%d" % [chunk.x, chunk.y]


func _world_to_chunk(tile_pos: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(tile_pos.x) / float(_chunk_size))),
		int(floor(float(tile_pos.y) / float(_chunk_size)))
	)


func _world_to_tile(world_pos: Vector2) -> Vector2i:
	if _world_to_tile_cb.is_valid():
		return _world_to_tile_cb.call(world_pos)
	return Vector2i(
		int(floor(world_pos.x / 32.0)),
		int(floor(world_pos.y / 32.0))
	)


func _entry_world_pos(entry: Dictionary) -> Vector2:
	var tile := Vector2i(int(entry.get("tile_pos_x", 0)), int(entry.get("tile_pos_y", 0)))
	if _tile_to_world_cb.is_valid():
		return _tile_to_world_cb.call(tile)
	return Vector2(tile.x * 32, tile.y * 32)


func _array_to_string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		var key := String(value).strip_edges()
		if key != "":
			result[key] = true
	return result


func _ensure_placeables_cache() -> void:
	var revision: int = int(WorldSave.placed_entities_revision)
	if revision == _placeables_cache_revision:
		return
	_placeables_cache_revision = revision
	_placeables_by_item_id_and_chunk.clear()
	for chunk_key in WorldSave.placed_entities_by_chunk.keys():
		var chunk_dict: Dictionary = WorldSave.placed_entities_by_chunk[chunk_key]
		for uid in chunk_dict.keys():
			var entry: Dictionary = chunk_dict[uid]
			var item_id := String(entry.get("item_id", "")).strip_edges()
			if item_id == "":
				continue
			if not _placeables_by_item_id_and_chunk.has(item_id):
				_placeables_by_item_id_and_chunk[item_id] = {}
			var by_chunk: Dictionary = _placeables_by_item_id_and_chunk[item_id]
			if not by_chunk.has(chunk_key):
				by_chunk[chunk_key] = []
			var bucket: Array = by_chunk[chunk_key]
			bucket.append(entry.duplicate(true))


func _run_placeables_consistency_check() -> void:
	_consistency_checks_total += 1
	_ensure_placeables_cache()
	var truth_total: int = 0
	for chunk_dict in WorldSave.placed_entities_by_chunk.values():
		truth_total += (chunk_dict as Dictionary).size()
	var cache_total: int = 0
	for by_chunk in _placeables_by_item_id_and_chunk.values():
		for bucket in (by_chunk as Dictionary).values():
			cache_total += (bucket as Array).size()
	if truth_total != cache_total:
		_consistency_checks_failed += 1
		_last_consistency_issue = "placeables cache drift detected truth=%d cache=%d revision=%d" % [truth_total, cache_total, _placeables_cache_revision]
		push_warning(_last_consistency_issue)
		rebuild_placeables_cache_from_truth("consistency_drift")
		return
	_last_consistency_issue = ""


func _get_cached_placeables_for_item_in_chunk(item_id: String, chunk_key: String) -> Array:
	var by_chunk: Dictionary = _placeables_by_item_id_and_chunk.get(item_id, {})
	return by_chunk.get(chunk_key, [])


func get_debug_snapshot() -> Dictionary:
	var runtime_counts := {
		"item_drop": get_all_runtime_nodes(KIND_ITEM_DROP).size(),
		"world_resource": get_all_runtime_nodes(KIND_WORLD_RESOURCE).size(),
		"workbench": get_all_runtime_nodes(KIND_WORKBENCH).size(),
		"storage": get_all_runtime_nodes(KIND_STORAGE).size(),
	}
	_ensure_placeables_cache()
	var persistent_counts: Dictionary = {}
	for item_id in ["workbench", "doorwood", "chest", "barrel"]:
		persistent_counts[item_id] = get_all_placeables_by_item_id(item_id).size()
	var total_runtime: int = 0
	for count in runtime_counts.values():
		total_runtime += int(count)
	return {
		"alive": total_runtime > 0 or not _placeables_by_item_id_and_chunk.is_empty(),
		"runtime_counts": runtime_counts,
		"persistent_cache_revision": _placeables_cache_revision,
		"persistent_item_counts": persistent_counts,
		"persistent_cache_item_ids": _placeables_by_item_id_and_chunk.size(),
		"persistent_cache_consistency": {
			"interval_sec": PLACEABLE_CACHE_CONSISTENCY_INTERVAL_SEC,
			"checks_total": _consistency_checks_total,
			"checks_failed": _consistency_checks_failed,
			"last_issue": _last_consistency_issue,
		},
		"query_total": _queries_total,
		"query_hit_rate": float(_queries_with_hits) / float(maxi(_queries_total, 1)),
	}
