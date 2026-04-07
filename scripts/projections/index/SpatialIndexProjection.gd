extends RefCounted
class_name SpatialIndexProjection

# Projection-only derived read model for placeable spatial queries.
# This class MUST NOT own domain truth; canonical placeables remain in WorldSave.
# It incrementally mirrors domain changes to serve runtime spatial lookups.

var _chunk_size: int = 32

var _placeables_cache_revision: int = -1
var _placeables_by_item_id_and_chunk: Dictionary = {}
var _placeables_cache_meta_by_uid: Dictionary = {}
var _last_applied_placeables_change_serial: int = 0
var _placeables_incremental_apply_calls: int = 0
var _placeables_incremental_apply_usec_total: int = 0
var _placeables_full_rebuild_calls: int = 0
var _placeables_full_rebuild_usec_total: int = 0
var _placeables_sanity_interval_msec: int = 90000
var _next_placeables_sanity_check_msec: int = 0
var _placeables_revision_poll_interval_msec: int = 1500
var _next_placeables_revision_poll_msec: int = 0
var _placeables_sync_pending: bool = true
var _pending_placeables_changed_chunks: Dictionary = {}
var _pending_placeables_changed_item_ids: Dictionary = {}
var _event_driven_invalidation_hits: int = 0
var _revision_poll_invalidations: int = 0
var _last_sync_reason: String = "startup"

func setup(ctx: Dictionary) -> void:
	_chunk_size = maxi(int(ctx.get("chunk_size", 32)), 1)
	_placeables_sanity_interval_msec = maxi(int(ctx.get("placeables_sanity_interval_msec", _placeables_sanity_interval_msec)), 1000)
	_placeables_revision_poll_interval_msec = maxi(int(ctx.get("placeables_revision_poll_interval_msec", _placeables_revision_poll_interval_msec)), 250)

func ensure_synced() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec >= _next_placeables_revision_poll_msec:
		_next_placeables_revision_poll_msec = now_msec + _placeables_revision_poll_interval_msec
		if int(WorldSave.placed_entities_revision) != _placeables_cache_revision:
			_placeables_sync_pending = true
			_revision_poll_invalidations += 1
			_last_sync_reason = "revision_poll"
	if not _placeables_sync_pending and _placeables_cache_revision >= 0:
		if now_msec >= _next_placeables_sanity_check_msec:
			_run_placeables_sanity_check()
			_schedule_next_placeables_sanity(now_msec)
		return
	var revision: int = int(WorldSave.placed_entities_revision)
	if _placeables_cache_revision < 0:
		_rebuild_placeables_cache_full("initial_snapshot")
		_placeables_sync_pending = false
		_schedule_next_placeables_sanity(now_msec)
		return
	if revision != _placeables_cache_revision:
		var t0: int = Time.get_ticks_usec()
		var delta: Dictionary = WorldSave.get_placed_entities_changes_since(_last_applied_placeables_change_serial)
		var overflow: bool = bool(delta.get("overflow", true))
		var changes: Array = delta.get("changes", [])
		if overflow or changes.is_empty():
			_rebuild_placeables_cache_full("delta_overflow")
		else:
			for raw_change in changes:
				_apply_placeables_cache_change(raw_change as Dictionary)
			_placeables_cache_revision = revision
			_last_sync_reason = "incremental_events"
		_last_applied_placeables_change_serial = int(delta.get("latest_serial", _last_applied_placeables_change_serial))
		_placeables_incremental_apply_calls += 1
		_placeables_incremental_apply_usec_total += Time.get_ticks_usec() - t0
	_placeables_sync_pending = false
	_pending_placeables_changed_chunks.clear()
	_pending_placeables_changed_item_ids.clear()
	if now_msec >= _next_placeables_sanity_check_msec:
		_run_placeables_sanity_check()
		_schedule_next_placeables_sanity(now_msec)

func rebuild_from_source(reason: String = "manual_rebuild") -> void:
	_rebuild_placeables_cache_full(reason)

func notify_placeables_changed(item_id: String, tile_pos: Vector2i) -> void:
	_placeables_sync_pending = true
	var item_key: String = item_id.strip_edges()
	if item_key != "":
		_pending_placeables_changed_item_ids[item_key] = true
	var chunk_pos := Vector2i(
		int(floor(float(tile_pos.x) / float(_chunk_size))),
		int(floor(float(tile_pos.y) / float(_chunk_size)))
	)
	_pending_placeables_changed_chunks[chunk_pos] = true
	_event_driven_invalidation_hits += 1
	_last_sync_reason = "event_invalidation"

func get_placeables_in_chunk(cx: int, cy: int, item_ids: Array[String] = []) -> Array[Dictionary]:
	if item_ids.is_empty():
		return WorldSave.get_placed_entities_in_chunk(cx, cy)
	ensure_synced()
	var filter: Dictionary = _array_to_string_set(item_ids)
	var result: Array[Dictionary] = []
	var chunk_pos := Vector2i(cx, cy)
	for item_id in filter.keys():
		var chunk_entries: Array = _get_cached_placeables_for_item_in_chunk_pos(String(item_id), chunk_pos)
		for entry in chunk_entries:
			result.append((entry as Dictionary).duplicate(true))
	return result

func get_all_placeables_by_item_id(item_id: String) -> Array[Dictionary]:
	var key := item_id.strip_edges()
	if key == "":
		return []
	ensure_synced()
	var result: Array[Dictionary] = []
	var by_chunk: Dictionary = _placeables_by_item_id_and_chunk.get(key, {})
	for chunk_entries in by_chunk.values():
		for entry in chunk_entries:
			result.append((entry as Dictionary).duplicate(true))
	return result

func get_debug_snapshot() -> Dictionary:
	return {
		"persistent_cache_revision": _placeables_cache_revision,
		"persistent_change_serial": _last_applied_placeables_change_serial,
		"persistent_cache_item_ids": _placeables_by_item_id_and_chunk.size(),
		"persistent_cache_uid_count": _placeables_cache_meta_by_uid.size(),
		"persistent_incremental_apply_calls": _placeables_incremental_apply_calls,
		"persistent_incremental_apply_avg_usec": float(_placeables_incremental_apply_usec_total) / float(maxi(_placeables_incremental_apply_calls, 1)),
		"persistent_full_rebuild_calls": _placeables_full_rebuild_calls,
		"persistent_full_rebuild_avg_usec": float(_placeables_full_rebuild_usec_total) / float(maxi(_placeables_full_rebuild_calls, 1)),
		"persistent_sync_pending": _placeables_sync_pending,
		"pending_changed_chunks": _pending_placeables_changed_chunks.size(),
		"pending_changed_item_ids": _pending_placeables_changed_item_ids.size(),
		"event_driven_invalidation_hits": _event_driven_invalidation_hits,
		"revision_poll_invalidations": _revision_poll_invalidations,
		"last_sync_reason": _last_sync_reason,
	}

func _schedule_next_placeables_sanity(now_msec: int) -> void:
	_next_placeables_sanity_check_msec = now_msec + _placeables_sanity_interval_msec

func _rebuild_placeables_cache_full(reason: String) -> void:
	var t0: int = Time.get_ticks_usec()
	_placeables_cache_revision = int(WorldSave.placed_entities_revision)
	_placeables_by_item_id_and_chunk.clear()
	_placeables_cache_meta_by_uid.clear()
	for chunk_key in WorldSave.placed_entities_by_chunk.keys():
		var chunk_pos: Vector2i = WorldSave.chunk_pos_from_key(String(chunk_key))
		if chunk_pos.x <= -999999:
			continue
		var chunk_dict: Dictionary = WorldSave.placed_entities_by_chunk[chunk_key]
		for entry_key in chunk_dict.keys():
			var entry: Dictionary = chunk_dict[entry_key]
			var item_id := String(entry.get("item_id", "")).strip_edges()
			if item_id == "":
				continue
			if not _placeables_by_item_id_and_chunk.has(item_id):
				_placeables_by_item_id_and_chunk[item_id] = {}
			var by_chunk: Dictionary = _placeables_by_item_id_and_chunk[item_id]
			if not by_chunk.has(chunk_pos):
				by_chunk[chunk_pos] = []
			var bucket: Array = by_chunk[chunk_pos]
			var entry_copy: Dictionary = entry.duplicate(true)
			bucket.append(entry_copy)
			var uid: String = String(entry_copy.get("uid", "")).strip_edges()
			if uid != "":
				_placeables_cache_meta_by_uid[uid] = {
					"item_id": item_id,
					"chunk_pos": chunk_pos,
				}
	_last_applied_placeables_change_serial = int(WorldSave.placed_entities_change_serial)
	_placeables_full_rebuild_calls += 1
	_placeables_full_rebuild_usec_total += Time.get_ticks_usec() - t0
	_placeables_sync_pending = false
	_pending_placeables_changed_chunks.clear()
	_pending_placeables_changed_item_ids.clear()
	_last_sync_reason = reason

func _apply_placeables_cache_change(change: Dictionary) -> void:
	var op: String = String(change.get("op", "")).strip_edges()
	if op == "clear":
		_placeables_by_item_id_and_chunk.clear()
		_placeables_cache_meta_by_uid.clear()
		return
	var prev_entry: Dictionary = change.get("prev_entry", {})
	if not prev_entry.is_empty():
		_cache_remove_placeable_entry(prev_entry)
	if op == "remove":
		return
	var entry: Dictionary = change.get("entry", {})
	if not entry.is_empty():
		_cache_add_placeable_entry(entry)

func _cache_add_placeable_entry(entry: Dictionary) -> void:
	var uid: String = String(entry.get("uid", "")).strip_edges()
	var item_id: String = String(entry.get("item_id", "")).strip_edges()
	if uid == "" or item_id == "":
		return
	var chunk_pos := Vector2i(
		int(floor(float(int(entry.get("tile_pos_x", 0))) / float(_chunk_size))),
		int(floor(float(int(entry.get("tile_pos_y", 0))) / float(_chunk_size)))
	)
	if not _placeables_by_item_id_and_chunk.has(item_id):
		_placeables_by_item_id_and_chunk[item_id] = {}
	var by_chunk: Dictionary = _placeables_by_item_id_and_chunk[item_id]
	if not by_chunk.has(chunk_pos):
		by_chunk[chunk_pos] = []
	var bucket: Array = by_chunk[chunk_pos]
	bucket.append(entry.duplicate(true))
	_placeables_cache_meta_by_uid[uid] = {
		"item_id": item_id,
		"chunk_pos": chunk_pos,
	}

func _cache_remove_placeable_entry(entry: Dictionary) -> void:
	var uid: String = String(entry.get("uid", "")).strip_edges()
	if uid == "":
		return
	var meta: Dictionary = _placeables_cache_meta_by_uid.get(uid, {})
	var item_id: String = String(meta.get("item_id", String(entry.get("item_id", "")).strip_edges()))
	var chunk_pos: Vector2i = Vector2i(meta.get("chunk_pos", Vector2i(-999999, -999999)))
	if chunk_pos.x <= -999999:
		chunk_pos = Vector2i(
			int(floor(float(int(entry.get("tile_pos_x", 0))) / float(_chunk_size))),
			int(floor(float(int(entry.get("tile_pos_y", 0))) / float(_chunk_size)))
		)
	var by_chunk: Dictionary = _placeables_by_item_id_and_chunk.get(item_id, {})
	if by_chunk.has(chunk_pos):
		var bucket: Array = by_chunk[chunk_pos]
		for i in range(bucket.size() - 1, -1, -1):
			var bucket_entry: Dictionary = bucket[i]
			if String(bucket_entry.get("uid", "")).strip_edges() == uid:
				bucket.remove_at(i)
				break
		if bucket.is_empty():
			by_chunk.erase(chunk_pos)
		if by_chunk.is_empty():
			_placeables_by_item_id_and_chunk.erase(item_id)
	_placeables_cache_meta_by_uid.erase(uid)

func _run_placeables_sanity_check() -> void:
	var canonical_total: int = int(WorldSave.placed_entity_chunk_by_uid.size())
	var cache_total: int = int(_placeables_cache_meta_by_uid.size())
	if canonical_total != cache_total or _placeables_cache_revision != int(WorldSave.placed_entities_revision):
		_rebuild_placeables_cache_full("sanity_resync")

func _get_cached_placeables_for_item_in_chunk_pos(item_id: String, chunk_pos: Vector2i) -> Array:
	var by_chunk: Dictionary = _placeables_by_item_id_and_chunk.get(item_id, {})
	return by_chunk.get(chunk_pos, [])

func _array_to_string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		var key := String(value).strip_edges()
		if key != "":
			result[key] = true
	return result
