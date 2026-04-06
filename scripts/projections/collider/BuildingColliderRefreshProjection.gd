extends RefCounted
class_name BuildingColliderRefreshProjection

const BuildingEventsScript := preload("res://scripts/domain/building/BuildingEvents.gd")
const BuildingStateScript := preload("res://scripts/domain/building/BuildingState.gd")

const CHANGE_KEY_ACTION := "action"
const CHANGE_KEY_BEFORE := "before"
const CHANGE_KEY_AFTER := "after"

var wall_reconnect_offsets: Array[Vector2i] = []
var is_valid_world_tile_cb: Callable
var tile_to_chunk_cb: Callable
var projection_refresh_port: WorldProjectionRefreshContract
var chunk_dirty_notifier_port: WorldChunkDirtyNotifierContract

func setup(ctx: Dictionary) -> void:
	is_valid_world_tile_cb = ctx.get("is_valid_world_tile", Callable())
	tile_to_chunk_cb = ctx.get("tile_to_chunk", Callable())
	projection_refresh_port = ctx.get("projection_refresh_port", null) as WorldProjectionRefreshContract
	chunk_dirty_notifier_port = ctx.get("chunk_dirty_notifier_port", null) as WorldChunkDirtyNotifierContract

	wall_reconnect_offsets = []
	for offset in ctx.get("wall_reconnect_offsets", []):
		if offset is Vector2i:
			wall_reconnect_offsets.append(offset as Vector2i)
	if wall_reconnect_offsets.is_empty():
		wall_reconnect_offsets = [Vector2i.ZERO]

func apply_events(events: Array[Dictionary]) -> void:
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

func _apply_tiles(base_tiles: Array[Vector2i]) -> void:
	if base_tiles.is_empty():
		return
	var scope_tiles: Array[Vector2i] = _collect_scope_for_cells(base_tiles)
	if scope_tiles.is_empty():
		return
	if projection_refresh_port != null:
		projection_refresh_port.refresh_for_tiles(scope_tiles)
		return
	if chunk_dirty_notifier_port == null:
		return
	var chunks_seen: Dictionary = {}
	for tile_pos in scope_tiles:
		var cpos: Vector2i = _tile_to_chunk(tile_pos)
		if chunks_seen.has(cpos):
			continue
		chunks_seen[cpos] = true
		chunk_dirty_notifier_port.mark_chunk_dirty(cpos)

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

func _add_if_valid_tile(out: Dictionary, tile_pos: Vector2i) -> void:
	if not _is_valid_world_tile(tile_pos):
		return
	out[tile_pos] = true
