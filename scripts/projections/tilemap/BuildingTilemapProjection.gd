extends RefCounted
class_name BuildingTilemapProjection

const BuildingEventsScript := preload("res://scripts/domain/building/BuildingEvents.gd")
const BuildingStateScript := preload("res://scripts/domain/building/BuildingState.gd")

var walls_tilemap: TileMap
var walls_map_layer: int = 0
var wall_terrain_set: int = 0
var wall_terrain: int = 0
var src_walls: int = 2

var wall_reconnect_offsets: Array[Vector2i] = []
var player_wall_fallback_atlas: Vector2i = Vector2i(0, 0)
var player_wall_isolated_atlas: Vector2i = Vector2i(0, 1)
var player_wall_fallback_alt: int = 2

var is_valid_world_tile_cb: Callable
var has_player_wall_state_cb: Callable
var has_structural_wall_state_cb: Callable

func setup(ctx: Dictionary) -> void:
	walls_tilemap = ctx.get("walls_tilemap", null) as TileMap
	walls_map_layer = int(ctx.get("walls_map_layer", walls_map_layer))
	wall_terrain_set = int(ctx.get("wall_terrain_set", wall_terrain_set))
	wall_terrain = int(ctx.get("wall_terrain", wall_terrain))
	src_walls = int(ctx.get("src_walls", src_walls))
	player_wall_fallback_atlas = Vector2i(ctx.get("player_wall_fallback_atlas", player_wall_fallback_atlas))
	player_wall_isolated_atlas = Vector2i(ctx.get("player_wall_isolated_atlas", player_wall_isolated_atlas))
	player_wall_fallback_alt = int(ctx.get("player_wall_fallback_alt", player_wall_fallback_alt))
	is_valid_world_tile_cb = ctx.get("is_valid_world_tile", Callable())
	has_player_wall_state_cb = ctx.get("has_player_wall_state", Callable())
	has_structural_wall_state_cb = ctx.get("has_structural_wall_state", Callable())

	wall_reconnect_offsets = []
	for offset in ctx.get("wall_reconnect_offsets", []):
		if offset is Vector2i:
			wall_reconnect_offsets.append(offset as Vector2i)

func apply_events(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	var touched: Dictionary = {}
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var event_type: String = String((event as Dictionary).get("type", "")).strip_edges()
		if event_type == BuildingEventsScript.TYPE_STRUCTURE_PLACED:
			var structure: Dictionary = (event as Dictionary).get("structure", {}) as Dictionary
			if not _is_player_wall_structure(structure):
				continue
			var tile_pos := _extract_tile_pos(structure)
			if tile_pos.x < 0 or tile_pos.y < 0:
				continue
			touched[tile_pos] = true
		elif event_type == BuildingEventsScript.TYPE_STRUCTURE_REMOVED:
			var tile_raw: Variant = (event as Dictionary).get("tile_pos", Vector2i(-1, -1))
			if tile_raw is Vector2i:
				touched[tile_raw as Vector2i] = true
		elif event_type == BuildingEventsScript.TYPE_STRUCTURE_DAMAGED:
			if bool((event as Dictionary).get("was_destroyed", false)):
				var destroyed_tile_raw: Variant = (event as Dictionary).get("tile_pos", Vector2i(-1, -1))
				if destroyed_tile_raw is Vector2i:
					touched[destroyed_tile_raw as Vector2i] = true
	if touched.is_empty():
		return
	var touched_tiles: Array[Vector2i] = _dict_keys_to_vector2i_array(touched)
	var expanded_scope: Array[Vector2i] = _collect_scope_for_cells(_collect_scope_for_cells(touched_tiles))
	_refresh_scope(expanded_scope)

func apply_snapshot(structures: Array[Dictionary]) -> void:
	var tiles: Dictionary = {}
	for raw in structures:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var structure: Dictionary = raw as Dictionary
		if not _is_player_wall_structure(structure):
			continue
		var tile_pos := _extract_tile_pos(structure)
		if tile_pos.x < 0 or tile_pos.y < 0:
			continue
		tiles[tile_pos] = true
	if tiles.is_empty():
		return
	var base_cells: Array[Vector2i] = _dict_keys_to_vector2i_array(tiles)
	var scope_cells: Array[Vector2i] = _collect_scope_for_cells(_collect_scope_for_cells(base_cells))
	_refresh_scope(scope_cells)

func _refresh_scope(scope_cells: Array[Vector2i]) -> void:
	if walls_tilemap == null or scope_cells.is_empty():
		return
	var player_tiles: Dictionary = {}
	var structural_tiles: Dictionary = {}
	for cell in scope_cells:
		if not _is_valid_world_tile(cell):
			continue
		if _has_player_wall_state(cell):
			player_tiles[cell] = true
		if _has_structural_wall_state(cell):
			structural_tiles[cell] = true

	for cell in scope_cells:
		if not _is_valid_world_tile(cell):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, cell) != src_walls:
			continue
		if player_tiles.has(cell):
			continue
		if structural_tiles.has(cell):
			continue
		walls_tilemap.erase_cell(walls_map_layer, cell)

	var player_tile_list: Array[Vector2i] = _dict_keys_to_vector2i_array(player_tiles)
	if not player_tile_list.is_empty():
		_apply_wall_terrain_connect(player_tile_list)
		_ensure_wall_cells_exist(player_tile_list)

	for cell in scope_cells:
		if not _is_valid_world_tile(cell):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, cell) != src_walls:
			continue
		if player_tiles.has(cell):
			continue
		if structural_tiles.has(cell):
			continue
		walls_tilemap.erase_cell(walls_map_layer, cell)

	var survivors: Array[Vector2i] = _collect_survivor_wall_cells(scope_cells)
	if not survivors.is_empty():
		_apply_wall_terrain_connect(survivors)

func _collect_scope_for_cells(base_cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Dictionary = {}
	for base_cell in base_cells:
		if not _is_valid_world_tile(base_cell):
			continue
		for offset in wall_reconnect_offsets:
			var probe := base_cell + offset
			if _is_valid_world_tile(probe):
				out[probe] = true
	return _dict_keys_to_vector2i_array(out)

func _collect_survivor_wall_cells(scope_cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Dictionary = {}
	for cell in scope_cells:
		if not _is_valid_world_tile(cell):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, cell) == src_walls:
			out[cell] = true
	return _dict_keys_to_vector2i_array(out)

func _ensure_wall_cells_exist(cells: Array[Vector2i]) -> void:
	var expected_cells: Dictionary = {}
	for cell in cells:
		if _is_valid_world_tile(cell):
			expected_cells[cell] = true
	for tile_pos in cells:
		if not _is_valid_world_tile(tile_pos):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos) == src_walls:
			continue
		walls_tilemap.set_cell(
			walls_map_layer,
			tile_pos,
			src_walls,
			_resolve_fallback_atlas_for_tile(tile_pos, expected_cells),
			player_wall_fallback_alt
		)

func _apply_wall_terrain_connect(cells: Array[Vector2i]) -> void:
	if cells.is_empty() or walls_tilemap == null:
		return
	walls_tilemap.set_cells_terrain_connect(walls_map_layer, cells, wall_terrain_set, wall_terrain, true)

func _resolve_fallback_atlas_for_tile(tile_pos: Vector2i, expected_cells: Dictionary = {}) -> Vector2i:
	if _has_expected_wall_neighbor(tile_pos, expected_cells):
		return player_wall_fallback_atlas
	return player_wall_isolated_atlas

func _has_expected_wall_neighbor(tile_pos: Vector2i, expected_cells: Dictionary = {}) -> bool:
	var side_offsets: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for offset in side_offsets:
		var probe := tile_pos + offset
		if not _is_valid_world_tile(probe):
			continue
		if expected_cells.has(probe):
			return true
		if walls_tilemap != null and walls_tilemap.get_cell_source_id(walls_map_layer, probe) == src_walls:
			return true
	return false

func _extract_tile_pos(structure: Dictionary) -> Vector2i:
	var tile_raw: Variant = structure.get(BuildingStateScript.STRUCTURE_KEY_TILE_POS, structure.get("tile", Vector2i(-1, -1)))
	if tile_raw is Vector2i:
		return tile_raw as Vector2i
	return Vector2i(-1, -1)

func _is_player_wall_structure(structure: Dictionary) -> bool:
	var metadata: Dictionary = structure.get(BuildingStateScript.STRUCTURE_KEY_METADATA, {}) as Dictionary
	if bool(metadata.get(BuildingStateScript.METADATA_KEY_IS_PLAYER_WALL, false)):
		return true
	var kind: String = String(structure.get(BuildingStateScript.STRUCTURE_KEY_KIND, "")).strip_edges()
	return kind == "player_wall" or kind == "wall"

func _has_player_wall_state(tile_pos: Vector2i) -> bool:
	if has_player_wall_state_cb.is_valid():
		return bool(has_player_wall_state_cb.call(tile_pos))
	return false

func _has_structural_wall_state(tile_pos: Vector2i) -> bool:
	if has_structural_wall_state_cb.is_valid():
		return bool(has_structural_wall_state_cb.call(tile_pos))
	return false

func _is_valid_world_tile(tile_pos: Vector2i) -> bool:
	if is_valid_world_tile_cb.is_valid():
		return bool(is_valid_world_tile_cb.call(tile_pos))
	return true

func _dict_keys_to_vector2i_array(dict: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in dict.keys():
		if key is Vector2i:
			out.append(key as Vector2i)
	return out
