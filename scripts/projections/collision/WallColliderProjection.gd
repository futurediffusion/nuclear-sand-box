extends RefCounted
class_name WallColliderProjection

const BuildingEventsScript := preload("res://scripts/domain/building/BuildingEvents.gd")
const BuildingStateScript := preload("res://scripts/domain/building/BuildingState.gd")

const CHANGE_KEY_ACTION := "action"
const CHANGE_KEY_BEFORE := "before"
const CHANGE_KEY_AFTER := "after"

var wall_reconnect_offsets: Array[Vector2i] = []
var is_valid_world_tile_cb: Callable
var tile_to_chunk_cb: Callable
var tile_to_world_cb: Callable
var mark_base_scan_dirty_near_cb: Callable
var mark_player_territory_dirty_cb: Callable

var projection_refresh_port: WorldProjectionRefreshContract
var chunk_dirty_notifier_port: WorldChunkDirtyNotifierContract
var wall_refresh_queue: WallRefreshQueue
var loaded_chunks: Dictionary = {}
var _apply_calls: int = 0
var _last_apply_source: String = "startup"
var _last_scope_tile_count: int = 0
var _last_dirty_chunk_count: int = 0
var _legacy_chunk_dirty_fallback_uses: int = 0

func setup(ctx: Dictionary) -> void:
	is_valid_world_tile_cb = ctx.get("is_valid_world_tile", Callable())
	tile_to_chunk_cb = ctx.get("tile_to_chunk", Callable())
	tile_to_world_cb = ctx.get("tile_to_world", Callable())
	mark_base_scan_dirty_near_cb = ctx.get("mark_base_scan_dirty_near", Callable())
	mark_player_territory_dirty_cb = ctx.get("mark_player_territory_dirty", Callable())
	projection_refresh_port = ctx.get("projection_refresh_port", null) as WorldProjectionRefreshContract
	chunk_dirty_notifier_port = ctx.get("chunk_dirty_notifier_port", null) as WorldChunkDirtyNotifierContract
	wall_refresh_queue = ctx.get("wall_refresh_queue", null) as WallRefreshQueue
	loaded_chunks = ctx.get("loaded_chunks", {}) as Dictionary

	wall_reconnect_offsets = []
	for offset in ctx.get("wall_reconnect_offsets", []):
		if offset is Vector2i:
			wall_reconnect_offsets.append(offset as Vector2i)
	if wall_reconnect_offsets.is_empty():
		wall_reconnect_offsets = [Vector2i.ZERO]

func apply_events(events: Array[Dictionary]) -> void:
	_apply_calls += 1
	_last_apply_source = "events"
	apply_input({
		"source": "building_events",
		"events": events,
	})

func apply_input(input: Dictionary) -> void:
	var events: Array[Dictionary] = input.get("events", []) as Array[Dictionary]
	var changed_structures: Array[Dictionary] = input.get("changed_structures", []) as Array[Dictionary]
	var structures: Array[Dictionary] = input.get("structures", []) as Array[Dictionary]
	var base_tiles: Array[Vector2i] = input.get("base_tiles", []) as Array[Vector2i]
	if not events.is_empty():
		_apply_events_internal(events)
		return
	if not changed_structures.is_empty():
		apply_change_set(changed_structures)
		return
	if not structures.is_empty():
		apply_snapshot(structures)
		return
	if not base_tiles.is_empty():
		_apply_tiles(base_tiles)

func _apply_events_internal(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	var touched_tiles: Dictionary = {}
	for raw_event in events:
		if typeof(raw_event) != TYPE_DICTIONARY:
			continue
		var event := raw_event as Dictionary
		var event_type: String = String(event.get("type", "")).strip_edges()
		if event_type == BuildingEventsScript.TYPE_STRUCTURE_PLACED:
			var structure: Dictionary = event.get("structure", {}) as Dictionary
			if not _is_wall_structure(structure):
				continue
			_add_if_valid_tile(touched_tiles, _extract_tile_pos(structure))
		elif event_type == BuildingEventsScript.TYPE_STRUCTURE_REMOVED:
			_add_if_valid_tile(touched_tiles, _extract_tile_pos(event))
		elif event_type == BuildingEventsScript.TYPE_STRUCTURE_DAMAGED and bool(event.get("was_destroyed", false)):
			_add_if_valid_tile(touched_tiles, _extract_tile_pos(event))
	_apply_tiles(_dict_keys_to_vector2i_array(touched_tiles))

func apply_change_set(changed_structures: Array[Dictionary]) -> void:
	_apply_calls += 1
	_last_apply_source = "change_set"
	if changed_structures.is_empty():
		return
	var touched_tiles: Dictionary = {}
	for raw_change in changed_structures:
		if typeof(raw_change) != TYPE_DICTIONARY:
			continue
		var change := raw_change as Dictionary
		var before: Dictionary = change.get(CHANGE_KEY_BEFORE, {}) as Dictionary
		var after: Dictionary = change.get(CHANGE_KEY_AFTER, {}) as Dictionary
		var action: String = String(change.get(CHANGE_KEY_ACTION, "")).strip_edges()
		if action == "placed" or action == "damaged":
			if _is_wall_structure(after):
				_add_if_valid_tile(touched_tiles, _extract_tile_pos(after))
		elif action == "removed":
			if _is_wall_structure(before):
				_add_if_valid_tile(touched_tiles, _extract_tile_pos(before))
	_apply_tiles(_dict_keys_to_vector2i_array(touched_tiles))

func apply_snapshot(structures: Array[Dictionary]) -> void:
	_apply_calls += 1
	_last_apply_source = "snapshot"
	if structures.is_empty():
		return
	var touched_tiles: Dictionary = {}
	for raw_structure in structures:
		if typeof(raw_structure) != TYPE_DICTIONARY:
			continue
		var structure := raw_structure as Dictionary
		if not _is_wall_structure(structure):
			continue
		_add_if_valid_tile(touched_tiles, _extract_tile_pos(structure))
	_apply_tiles(_dict_keys_to_vector2i_array(touched_tiles))

func rebuild_from_state(structures: Array[Dictionary]) -> void:
	apply_snapshot(structures)

func _apply_tiles(base_tiles: Array[Vector2i]) -> void:
	if base_tiles.is_empty():
		return
	var scope_tiles: Array[Vector2i] = _collect_scope_for_cells(base_tiles)
	_last_scope_tile_count = scope_tiles.size()
	if scope_tiles.is_empty():
		return
	if projection_refresh_port != null:
		projection_refresh_port.refresh_for_tiles(scope_tiles)
	else:
		_register_legacy_bridge_usage(
			"wall_collider.chunk_dirty_fallback",
			"Missing `projection_refresh_port`; using deprecated chunk-dirty fallback path."
		)
		_mark_scope_chunks_dirty(scope_tiles)
	_mark_runtime_side_effects(scope_tiles)

func _mark_scope_chunks_dirty(scope_tiles: Array[Vector2i]) -> void:
	if chunk_dirty_notifier_port == null:
		_last_dirty_chunk_count = 0
		return
	var chunks_seen: Dictionary = {}
	for tile_pos in scope_tiles:
		var cpos: Vector2i = _tile_to_chunk(tile_pos)
		if chunks_seen.has(cpos):
			continue
		chunks_seen[cpos] = true
		chunk_dirty_notifier_port.mark_chunk_dirty(cpos)
		if wall_refresh_queue != null:
			wall_refresh_queue.record_activity(cpos)
			if loaded_chunks.has(cpos):
				wall_refresh_queue.enqueue(cpos)
	_last_dirty_chunk_count = chunks_seen.size()

func get_debug_snapshot() -> Dictionary:
	return {
		"apply_calls": _apply_calls,
		"last_apply_source": _last_apply_source,
		"last_scope_tile_count": _last_scope_tile_count,
		"last_dirty_chunk_count": _last_dirty_chunk_count,
		"legacy_chunk_dirty_fallback_uses": _legacy_chunk_dirty_fallback_uses,
		"uses_projection_refresh_port": projection_refresh_port != null,
		"uses_chunk_dirty_notifier_port": chunk_dirty_notifier_port != null,
	}

func _register_legacy_bridge_usage(bridge_id: String, details: String) -> void:
	_legacy_chunk_dirty_fallback_uses += 1
	Debug.log("compat", "[DEPRECATED_BRIDGE][%s] %s count=%d" % [
		bridge_id,
		details,
		_legacy_chunk_dirty_fallback_uses,
	])
	push_warning("[WallColliderProjection] Deprecated compatibility bridge used: %s" % bridge_id)
	if OS.is_debug_build():
		assert(false, "[WallColliderProjection] Deprecated compatibility bridge used: %s — %s" % [bridge_id, details])

func _mark_runtime_side_effects(scope_tiles: Array[Vector2i]) -> void:
	if mark_player_territory_dirty_cb.is_valid():
		mark_player_territory_dirty_cb.call()
	if mark_base_scan_dirty_near_cb.is_valid() and not scope_tiles.is_empty():
		mark_base_scan_dirty_near_cb.call(_tile_to_world(scope_tiles[0]))

func _collect_scope_for_cells(base_cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Dictionary = {}
	for base_cell in base_cells:
		if not _is_valid_world_tile(base_cell):
			continue
		for offset in wall_reconnect_offsets:
			var probe: Vector2i = base_cell + offset
			if _is_valid_world_tile(probe):
				out[probe] = true
	return _dict_keys_to_vector2i_array(out)

func _dict_keys_to_vector2i_array(dict: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in dict.keys():
		if key is Vector2i:
			out.append(key as Vector2i)
	return out

func _extract_tile_pos(payload: Dictionary) -> Vector2i:
	var tile_raw: Variant = payload.get(BuildingStateScript.STRUCTURE_KEY_TILE_POS, payload.get("tile_pos", payload.get("tile", Vector2i(-1, -1))))
	if tile_raw is Vector2i:
		return tile_raw as Vector2i
	return Vector2i(-1, -1)

func _is_wall_structure(structure: Dictionary) -> bool:
	if structure.is_empty():
		return false
	var metadata: Dictionary = structure.get(BuildingStateScript.STRUCTURE_KEY_METADATA, {}) as Dictionary
	if bool(metadata.get(BuildingStateScript.METADATA_KEY_IS_PLAYER_WALL, false)):
		return true
	var kind: String = String(structure.get(BuildingStateScript.STRUCTURE_KEY_KIND, "")).strip_edges()
	return kind == "player_wall" or kind == "wall"

func _is_valid_world_tile(tile_pos: Vector2i) -> bool:
	if is_valid_world_tile_cb.is_valid():
		return bool(is_valid_world_tile_cb.call(tile_pos))
	return true

func _tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	if tile_to_chunk_cb.is_valid():
		var converted: Variant = tile_to_chunk_cb.call(tile_pos)
		if converted is Vector2i:
			return converted as Vector2i
	return Vector2i.ZERO

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	if tile_to_world_cb.is_valid():
		var converted: Variant = tile_to_world_cb.call(tile_pos)
		if converted is Vector2:
			return converted as Vector2
	return Vector2(tile_pos)

func _add_if_valid_tile(out: Dictionary, tile_pos: Vector2i) -> void:
	if not _is_valid_world_tile(tile_pos):
		return
	out[tile_pos] = true
