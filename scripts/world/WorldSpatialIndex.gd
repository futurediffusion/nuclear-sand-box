class_name WorldSpatialIndex
extends Node

# Small, pragmatic spatial helper for common world queries.
# Runtime world entities (drops/resources/loaded workbenches/storage) are indexed
# by chunk with live node references.
# Persistent placeables still live canonically in WorldSave. This class only
# offers query helpers plus small derived views over that persistence data.

const KIND_ITEM_DROP: StringName = &"item_drop"
const KIND_WORLD_RESOURCE: StringName = &"world_resource"
const KIND_WORKBENCH: StringName = &"workbench"
const KIND_STORAGE: StringName = &"storage"

const STORAGE_ITEM_IDS: Dictionary = {
	"chest": true,
	"barrel": true,
}

const BLOCKING_EXCLUDED_ITEM_IDS: Dictionary = {
	"floorwood": true,
	"woodfloor": true,
}

var _world_to_tile_cb: Callable
var _tile_to_world_cb: Callable
var _chunk_size: int = 32

# kind -> chunk_pos(Vector2i) -> {instance_id: Node}
var _runtime_nodes_by_kind: Dictionary = {}
# instance_id -> {"kind": StringName, "chunk_pos": Vector2i, "node": Node}
var _runtime_meta_by_id: Dictionary = {}
# Derived persistent view: item_id -> chunk_pos(Vector2i) -> Array[Dictionary].
# This is rebuilt from WorldSave when its structural revision changes.
var _placeables_cache_revision: int = -1
var _placeables_by_item_id_and_chunk: Dictionary = {}

var _queries_total: int = 0
var _queries_with_hits: int = 0
var _chunk_query_time_usec_total: int = 0
var _chunk_query_calls: int = 0
var _nearest_query_calls: int = 0
var _nearest_candidates_evaluated_total: int = 0


func setup(ctx: Dictionary) -> void:
	_world_to_tile_cb = ctx.get("world_to_tile", Callable())
	_tile_to_world_cb = ctx.get("tile_to_world", Callable())
	_chunk_size = maxi(int(ctx.get("chunk_size", 32)), 1)
	add_to_group("world_spatial_index")


func register_runtime_node(kind: StringName, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var node2d := node as Node2D
	if node2d == null:
		return
	var iid: int = node.get_instance_id()
	_unregister_runtime_id(iid)
	var chunk_pos := _world_to_chunk_pos(node2d.global_position)
	var by_chunk: Dictionary = _ensure_runtime_kind(kind)
	if not by_chunk.has(chunk_pos):
		by_chunk[chunk_pos] = {}
	var chunk_bucket: Dictionary = by_chunk[chunk_pos]
	chunk_bucket[iid] = node
	_runtime_meta_by_id[iid] = {
		"kind": kind,
		"chunk_pos": chunk_pos,
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
	var next_chunk_pos := _world_to_chunk_pos(node2d.global_position)
	var meta: Dictionary = _runtime_meta_by_id.get(iid, {})
	if meta.is_empty():
		register_runtime_node(kind, node)
		return
	if StringName(meta.get("kind", &"")) != kind or Vector2i(meta.get("chunk_pos", Vector2i(-999999, -999999))) != next_chunk_pos:
		register_runtime_node(kind, node)


func get_runtime_nodes_near(kind: StringName, world_pos: Vector2, radius: float, query_ctx: Dictionary = {}) -> Array:
	_queries_total += 1
	var result: Array = []
	var effective_radius: float = _resolve_contextual_radius(radius, kind, query_ctx)
	var r2: float = effective_radius * effective_radius
	var enough_threshold: int = maxi(int(query_ctx.get("enough_threshold", 0)), 0)
	var max_candidates_eval: int = maxi(int(query_ctx.get("max_candidates_eval", 0)), 0)
	var candidates_evaluated: int = 0
	for chunk_pos in _get_chunk_positions_for_radius_ring_ordered(world_pos, effective_radius):
		var bucket: Dictionary = _get_runtime_bucket(kind, chunk_pos)
		if bucket.is_empty():
			continue
		var stale_ids: Array[int] = []
		for iid in bucket.keys():
			var node: Node = bucket[iid]
			var node2d := node as Node2D
			if node == null or not is_instance_valid(node) or node2d == null or node.is_queued_for_deletion():
				stale_ids.append(int(iid))
				continue
			var actual_chunk_pos := _world_to_chunk_pos(node2d.global_position)
			if actual_chunk_pos != chunk_pos:
				register_runtime_node(kind, node)
				continue
			candidates_evaluated += 1
			if node2d.global_position.distance_squared_to(world_pos) <= r2:
				result.append(node)
				if enough_threshold > 0 and result.size() >= enough_threshold:
					break
			if max_candidates_eval > 0 and candidates_evaluated >= max_candidates_eval:
				break
		for stale_id in stale_ids:
			_unregister_runtime_id(stale_id)
		if (enough_threshold > 0 and result.size() >= enough_threshold) \
				or (max_candidates_eval > 0 and candidates_evaluated >= max_candidates_eval):
			break
	if result.size() > 0:
		_queries_with_hits += 1
	_nearest_query_calls += 1
	_nearest_candidates_evaluated_total += candidates_evaluated
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


func get_placeables_by_item_ids_near(world_pos: Vector2, radius: float, item_ids: Array[String], query_ctx: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var filter: Dictionary = _array_to_string_set(item_ids)
	var effective_radius: float = _resolve_contextual_radius(radius, &"placeable", query_ctx)
	var r2: float = effective_radius * effective_radius
	var enough_threshold: int = maxi(int(query_ctx.get("enough_threshold", 0)), 0)
	var max_candidates_eval: int = maxi(int(query_ctx.get("max_candidates_eval", 0)), 0)
	var candidates_evaluated: int = 0
	for chunk_pos in _get_chunk_positions_for_radius_ring_ordered(world_pos, effective_radius):
		var entries: Array[Dictionary] = get_placeables_in_chunk(chunk_pos.x, chunk_pos.y, item_ids)
		for entry in entries:
			var item_id := String(entry.get("item_id", "")).strip_edges()
			if not filter.is_empty() and not filter.has(item_id):
				continue
			candidates_evaluated += 1
			var wpos := _entry_world_pos(entry)
			if wpos.distance_squared_to(world_pos) <= r2:
				result.append(entry)
				if enough_threshold > 0 and result.size() >= enough_threshold:
					break
			if max_candidates_eval > 0 and candidates_evaluated >= max_candidates_eval:
				break
		if (enough_threshold > 0 and result.size() >= enough_threshold) \
				or (max_candidates_eval > 0 and candidates_evaluated >= max_candidates_eval):
			break
	_nearest_query_calls += 1
	_nearest_candidates_evaluated_total += candidates_evaluated
	return result


func get_placeables_in_chunk_key(chunk_key: String, item_ids: Array[String] = []) -> Array[Dictionary]:
	var chunk_pos: Vector2i = WorldSave.chunk_pos_from_key(chunk_key)
	if chunk_pos.x <= -999999:
		return []
	return get_placeables_in_chunk(chunk_pos.x, chunk_pos.y, item_ids)


func get_placeables_in_chunk(cx: int, cy: int, item_ids: Array[String] = []) -> Array[Dictionary]:
	var t0: int = Time.get_ticks_usec()
	if item_ids.is_empty():
		var direct: Array[Dictionary] = WorldSave.get_placed_entities_in_chunk(cx, cy)
		_chunk_query_time_usec_total += Time.get_ticks_usec() - t0
		_chunk_query_calls += 1
		return direct
	_ensure_placeables_cache()
	var filter: Dictionary = _array_to_string_set(item_ids)
	var result: Array[Dictionary] = []
	var chunk_pos := Vector2i(cx, cy)
	for item_id in filter.keys():
		var chunk_entries: Array = _get_cached_placeables_for_item_in_chunk_pos(String(item_id), chunk_pos)
		for entry in chunk_entries:
			result.append((entry as Dictionary).duplicate(true))
	_chunk_query_time_usec_total += Time.get_ticks_usec() - t0
	_chunk_query_calls += 1
	return result


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


func get_blocker_tiles_in_rect(min_x: int, min_y: int, w: int, h: int) -> Dictionary:
	var blockers: Dictionary = {}
	for entry in get_placeables_in_tile_rect(min_x, min_y, w, h):
		var item_id := String(entry.get("item_id", "")).strip_edges()
		var uid := String(entry.get("uid", ""))
		if not placeable_blocks_movement(item_id, uid):
			continue
		blockers[Vector2i(int(entry.get("tile_pos_x", 0)), int(entry.get("tile_pos_y", 0)))] = true
	return blockers


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


func placeable_blocks_movement(item_id: String, uid: String = "") -> bool:
	if item_id == "":
		return false
	if BLOCKING_EXCLUDED_ITEM_IDS.has(item_id):
		return false
	if item_id == "doorwood":
		var data: Dictionary = WorldSave.get_placed_entity_data(uid)
		return not bool(data.get("is_open", false))
	return true


func is_storage_item_id(item_id: String) -> bool:
	return STORAGE_ITEM_IDS.has(item_id)


func _ensure_runtime_kind(kind: StringName) -> Dictionary:
	if not _runtime_nodes_by_kind.has(kind):
		_runtime_nodes_by_kind[kind] = {}
	return _runtime_nodes_by_kind[kind]


func _get_runtime_bucket(kind: StringName, chunk_pos: Vector2i) -> Dictionary:
	var by_chunk: Dictionary = _runtime_nodes_by_kind.get(kind, {})
	return by_chunk.get(chunk_pos, {})


func _unregister_runtime_id(iid: int) -> void:
	var meta: Dictionary = _runtime_meta_by_id.get(iid, {})
	if meta.is_empty():
		return
	var kind: StringName = meta.get("kind", &"")
	var chunk_pos: Vector2i = Vector2i(meta.get("chunk_pos", Vector2i(-999999, -999999)))
	var by_chunk: Dictionary = _runtime_nodes_by_kind.get(kind, {})
	if by_chunk.has(chunk_pos):
		var bucket: Dictionary = by_chunk[chunk_pos]
		bucket.erase(iid)
		if bucket.is_empty():
			by_chunk.erase(chunk_pos)
	_runtime_meta_by_id.erase(iid)


func _get_chunk_positions_for_radius(world_pos: Vector2, radius: float) -> Array[Vector2i]:
	var min_world := world_pos - Vector2(radius, radius)
	var max_world := world_pos + Vector2(radius, radius)
	var min_chunk := _world_to_chunk(_world_to_tile(min_world))
	var max_chunk := _world_to_chunk(_world_to_tile(max_world))
	var result: Array[Vector2i] = []
	for cy in range(min_chunk.y, max_chunk.y + 1):
		for cx in range(min_chunk.x, max_chunk.x + 1):
			result.append(Vector2i(cx, cy))
	return result


func _get_chunk_positions_for_radius_ring_ordered(world_pos: Vector2, radius: float) -> Array[Vector2i]:
	var center_chunk: Vector2i = _world_to_chunk_pos(world_pos)
	var chunks: Array[Vector2i] = _get_chunk_positions_for_radius(world_pos, radius)
	chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var adx: int = absi(a.x - center_chunk.x)
		var ady: int = absi(a.y - center_chunk.y)
		var bdx: int = absi(b.x - center_chunk.x)
		var bdy: int = absi(b.y - center_chunk.y)
		var aring: int = maxi(adx, ady)
		var bring: int = maxi(bdx, bdy)
		if aring != bring:
			return aring < bring
		var adsq: int = adx * adx + ady * ady
		var bdsq: int = bdx * bdx + bdy * bdy
		if adsq != bdsq:
			return adsq < bdsq
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return chunks


func _resolve_contextual_radius(radius: float, kind: Variant, query_ctx: Dictionary) -> float:
	var base: float = maxf(radius, 0.0)
	if query_ctx.is_empty():
		return base
	var intent: String = String(query_ctx.get("intent", ""))
	var stage: String = String(query_ctx.get("stage", ""))
	var scale: float = 1.0
	if stage == "assault_member_target":
		scale *= 0.75
	elif stage == "assault_confirm":
		scale *= 0.85
	if intent == "raiding":
		scale *= 0.82
	elif intent == "hunting":
		scale *= 0.90
	if String(kind) == "world_resource" and (intent == "idle" or intent == ""):
		scale *= 0.70
	return maxf(1.0, base * clampf(scale, 0.45, 1.0))


func _world_to_chunk_pos(world_pos: Vector2) -> Vector2i:
	var tile := _world_to_tile(world_pos)
	return _world_to_chunk(tile)


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
		var chunk_pos: Vector2i = WorldSave.chunk_pos_from_key(String(chunk_key))
		if chunk_pos.x <= -999999:
			continue
		var chunk_dict: Dictionary = WorldSave.placed_entities_by_chunk[chunk_key]
		for uid in chunk_dict.keys():
			var entry: Dictionary = chunk_dict[uid]
			var item_id := String(entry.get("item_id", "")).strip_edges()
			if item_id == "":
				continue
			if not _placeables_by_item_id_and_chunk.has(item_id):
				_placeables_by_item_id_and_chunk[item_id] = {}
			var by_chunk: Dictionary = _placeables_by_item_id_and_chunk[item_id]
			if not by_chunk.has(chunk_pos):
				by_chunk[chunk_pos] = []
			var bucket: Array = by_chunk[chunk_pos]
			bucket.append(entry.duplicate(true))


func _get_cached_placeables_for_item_in_chunk_pos(item_id: String, chunk_pos: Vector2i) -> Array:
	var by_chunk: Dictionary = _placeables_by_item_id_and_chunk.get(item_id, {})
	return by_chunk.get(chunk_pos, [])


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
		"query_total": _queries_total,
		"query_hit_rate": float(_queries_with_hits) / float(maxi(_queries_total, 1)),
		"chunk_query_calls": _chunk_query_calls,
		"chunk_query_avg_usec": float(_chunk_query_time_usec_total) / float(maxi(_chunk_query_calls, 1)),
		"nearest_query_calls": _nearest_query_calls,
		"nearest_candidates_avg": float(_nearest_candidates_evaluated_total) / float(maxi(_nearest_query_calls, 1)),
		"worldsave_chunk_key_codec": WorldSave.get_chunk_key_codec_metrics(),
	}
