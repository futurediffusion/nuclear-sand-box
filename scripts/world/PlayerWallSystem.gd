extends RefCounted
class_name PlayerWallSystem

const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const TileHitFeedbackScript := preload("res://scripts/systems/TileHitFeedback.gd")
const WallTileResolverScript := preload("res://scripts/world/WallTileResolver.gd")
const DEFAULT_PLAYER_WALL_HIT_SOUNDS: Array[AudioStream] = [
	preload("res://art/Sounds/wood1.ogg"),
	preload("res://art/Sounds/wood2.ogg"),
]
const DEFAULT_PLAYER_WALL_HIT_VOLUME_DB: float = 0.0

var walls_tilemap: TileMap
var cliffs_tilemap: TileMap
var chunk_save: Dictionary
var loaded_chunks: Dictionary

var width: int = 0
var height: int = 0
var chunk_size: int = 32

var wall_terrain_set: int = 0
var wall_terrain: int = 0
var walls_map_layer: int = 0
var src_walls: int = 2

var player_wallwood_max_hp: int = 3
var player_wall_drop_enabled: bool = true
var player_wall_drop_item_id: String = "wallwood"
var player_wall_drop_amount: int = 1

var player_wall_hit_shake_duration: float = 0.08
var player_wall_hit_shake_px: float = 5.0
var player_wall_hit_shake_speed: float = 40.0
var player_wall_hit_flash_time: float = 0.06
var player_wall_hit_tint: Color = Color(0.86, 0.76, 0.6, 1.0)

var player_wall_fallback_atlas: Vector2i = Vector2i(0, 0)
var player_wall_fallback_alt: int = 2

var player_wall_hit_sounds: Array[AudioStream] = _to_valid_sound_pool(DEFAULT_PLAYER_WALL_HIT_SOUNDS)
var player_wall_hit_volume_db: float = DEFAULT_PLAYER_WALL_HIT_VOLUME_DB

var wall_reconnect_offsets: Array[Vector2i] = []

var world_to_tile_cb: Callable
var tile_to_world_cb: Callable
var tile_to_chunk_cb: Callable
var mark_chunk_walls_dirty_and_refresh_for_tiles_cb: Callable

var owner: Node

func setup(ctx: Dictionary) -> void:
	walls_tilemap = ctx.get("walls_tilemap")
	cliffs_tilemap = ctx.get("cliffs_tilemap")
	chunk_save = ctx.get("chunk_save", {})
	loaded_chunks = ctx.get("loaded_chunks", {})

	width = int(ctx.get("width", width))
	height = int(ctx.get("height", height))
	chunk_size = int(ctx.get("chunk_size", chunk_size))

	wall_terrain_set = int(ctx.get("wall_terrain_set", wall_terrain_set))
	wall_terrain = int(ctx.get("wall_terrain", wall_terrain))
	walls_map_layer = int(ctx.get("walls_map_layer", walls_map_layer))
	src_walls = int(ctx.get("src_walls", src_walls))

	player_wallwood_max_hp = int(ctx.get("player_wallwood_max_hp", player_wallwood_max_hp))
	player_wall_drop_enabled = bool(ctx.get("player_wall_drop_enabled", player_wall_drop_enabled))
	player_wall_drop_item_id = String(ctx.get("player_wall_drop_item_id", player_wall_drop_item_id)).strip_edges()
	player_wall_drop_amount = maxi(0, int(ctx.get("player_wall_drop_amount", player_wall_drop_amount)))
	player_wall_hit_shake_duration = float(ctx.get("player_wall_hit_shake_duration", player_wall_hit_shake_duration))
	player_wall_hit_shake_px = float(ctx.get("player_wall_hit_shake_px", player_wall_hit_shake_px))
	player_wall_hit_shake_speed = float(ctx.get("player_wall_hit_shake_speed", player_wall_hit_shake_speed))
	player_wall_hit_flash_time = float(ctx.get("player_wall_hit_flash_time", player_wall_hit_flash_time))
	player_wallwood_max_hp = maxi(1, player_wallwood_max_hp)
	player_wall_hit_tint = Color(ctx.get("player_wall_hit_tint", player_wall_hit_tint))

	player_wall_fallback_atlas = Vector2i(ctx.get("player_wall_fallback_atlas", player_wall_fallback_atlas))
	player_wall_fallback_alt = int(ctx.get("player_wall_fallback_alt", player_wall_fallback_alt))

	wall_reconnect_offsets = []
	for offset in ctx.get("wall_reconnect_offsets", []):
		if offset is Vector2i:
			wall_reconnect_offsets.append(offset as Vector2i)

	world_to_tile_cb = ctx.get("world_to_tile", Callable())
	tile_to_world_cb = ctx.get("tile_to_world", Callable())
	tile_to_chunk_cb = ctx.get("tile_to_chunk", Callable())
	mark_chunk_walls_dirty_and_refresh_for_tiles_cb = ctx.get("mark_chunk_walls_dirty_and_refresh_for_tiles", Callable())
	owner = ctx.get("owner")

	var legacy_audio_config: Dictionary = {}
	if ctx.has("player_wall_hit_sounds"):
		legacy_audio_config["player_wall_hit_sounds"] = ctx.get("player_wall_hit_sounds")
	if ctx.has("player_wall_hit_volume_db"):
		legacy_audio_config["player_wall_hit_volume_db"] = ctx.get("player_wall_hit_volume_db")
	configure_audio(legacy_audio_config)

func configure_audio(config: Dictionary = {}) -> void:
	var resolved_sounds: Array[AudioStream] = _to_valid_sound_pool(DEFAULT_PLAYER_WALL_HIT_SOUNDS)
	var resolved_volume_db: float = DEFAULT_PLAYER_WALL_HIT_VOLUME_DB

	if config.has("player_wall_hit_sounds"):
		var explicit_sounds: Array[AudioStream] = _to_valid_sound_pool(config.get("player_wall_hit_sounds", []))
		if not explicit_sounds.is_empty():
			resolved_sounds = explicit_sounds
	if config.has("player_wall_hit_volume_db"):
		resolved_volume_db = float(config.get("player_wall_hit_volume_db", resolved_volume_db))

	var panel: Node = AudioSystem.get_sound_panel()
	if panel is SoundPanel:
		var sound_panel := panel as SoundPanel
		var panel_sounds: Array[AudioStream] = _to_valid_sound_pool(sound_panel.get_player_wall_hit_sfx_pool())
		if not panel_sounds.is_empty():
			resolved_sounds = panel_sounds
		resolved_volume_db = sound_panel.player_wall_hit_volume_db

	player_wall_hit_sounds = resolved_sounds
	player_wall_hit_volume_db = resolved_volume_db

func can_place_player_wall_at_tile(tile_pos: Vector2i) -> bool:
	if not _is_valid_world_tile(tile_pos):
		return false
	var cpos := _tile_to_chunk(tile_pos)
	if WorldSave.has_player_wall(cpos.x, cpos.y, tile_pos):
		return false
	if walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos) != -1:
		return false
	if cliffs_tilemap.get_cell_source_id(0, tile_pos) != -1:
		return false
	for entry in WorldSave.placed_entities:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var placed_entry := entry as Dictionary
		var tx: int = int(placed_entry.get("tile_pos_x", -99999))
		var ty: int = int(placed_entry.get("tile_pos_y", -99999))
		if tx != tile_pos.x or ty != tile_pos.y:
			continue
		var existing_item_id := String(placed_entry.get("item_id", ""))
		if PlacementCatalog.can_share_tile("wallwood", existing_item_id):
			continue
		return false
	return true

func place_player_wall_at_tile(tile_pos: Vector2i, hp_override: int = -1) -> bool:
	if not can_place_player_wall_at_tile(tile_pos):
		return false
	var placement_tiles: Array[Vector2i] = [tile_pos]
	if not _apply_player_wall_tiles_strict(placement_tiles):
		return false
	if walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos) != src_walls:
		return false
	var configured_max_hp: int = maxi(1, player_wallwood_max_hp)
	var final_hp := hp_override if hp_override > 0 else configured_max_hp
	final_hp = clampi(final_hp, 1, configured_max_hp)
	var cpos := _tile_to_chunk(tile_pos)
	WorldSave.set_player_wall(cpos.x, cpos.y, tile_pos, final_hp)
	var reconnect_scope := _collect_reconnect_neighborhood(tile_pos)
	_reconcile_wall_ownership_in_scope(reconnect_scope)
	_mark_walls_dirty_and_refresh_for_tiles(reconnect_scope)
	return true

func damage_player_wall_from_contact(hit_pos: Vector2, hit_normal: Vector2, amount: int = 1) -> bool:
	if amount <= 0:
		amount = 1
	var resolved_tile: Vector2i = WallTileResolverScript.resolve_player_wall_tile_from_contact(hit_pos, hit_normal, Callable(self, "_world_to_tile"), Callable(self, "_is_valid_world_tile"), Callable(self, "_is_player_wall_tile"), Callable(self, "_tile_to_world"), _get_wall_tile_size_vec(), 1)
	if resolved_tile.x < 0 or resolved_tile.y < 0:
		return false
	return damage_player_wall_at_tile(resolved_tile, amount)

func damage_player_wall_near_world_pos(world_pos: Vector2, amount: int = 1) -> bool:
	if amount <= 0:
		amount = 1
	var center_tile: Vector2i = _world_to_tile(world_pos)
	var resolved_tile: Vector2i = WallTileResolverScript.find_nearest_player_wall_tile_in_neighborhood(world_pos, center_tile, Callable(self, "_world_to_tile"), Callable(self, "_is_valid_world_tile"), Callable(self, "_is_player_wall_tile"), Callable(self, "_tile_to_world"), _get_wall_tile_size_vec(), 1)
	if resolved_tile.x < 0 or resolved_tile.y < 0:
		return false
	return damage_player_wall_at_tile(resolved_tile, amount)

func damage_player_wall_at_world_pos(world_pos: Vector2, amount: int = 1) -> bool:
	var tile_pos := _world_to_tile(world_pos)
	if damage_player_wall_at_tile(tile_pos, amount):
		return true
	var best_tile := Vector2i.ZERO
	var found := false
	var best_dist := 1.0e30
	var search_radius: int = 2
	for oy in range(-search_radius, search_radius + 1):
		for ox in range(-search_radius, search_radius + 1):
			var candidate: Vector2i = tile_pos + Vector2i(ox, oy)
			if not _is_valid_world_tile(candidate):
				continue
			var chunk_pos := _tile_to_chunk(candidate)
			if not WorldSave.has_player_wall(chunk_pos.x, chunk_pos.y, candidate):
				continue
			var center := _tile_to_world(candidate)
			var dist := center.distance_squared_to(world_pos)
			if not found or dist < best_dist:
				best_dist = dist
				best_tile = candidate
				found = true
	if not found:
		return false
	return damage_player_wall_at_tile(best_tile, amount)

func damage_player_wall_in_circle(world_center: Vector2, world_radius: float, amount: int = 1) -> bool:
	if amount <= 0:
		amount = 1
	var radius: float = maxf(world_radius, 0.0)
	var center_tile: Vector2i = _world_to_tile(world_center)
	var tile_size: float = 32.0
	var tile_radius: int = maxi(1, int(ceili(radius / tile_size)) + 1)
	var best_tile: Vector2i = Vector2i.ZERO
	var found: bool = false
	var best_dist_sq: float = 1.0e30

	for oy in range(-tile_radius, tile_radius + 1):
		for ox in range(-tile_radius, tile_radius + 1):
			var candidate: Vector2i = center_tile + Vector2i(ox, oy)
			if not _is_valid_world_tile(candidate):
				continue
			var chunk_pos: Vector2i = _tile_to_chunk(candidate)
			if not WorldSave.has_player_wall(chunk_pos.x, chunk_pos.y, candidate):
				continue

			var tile_center: Vector2 = _tile_to_world(candidate)
			var half_ext: float = tile_size * 0.5
			var min_p: Vector2 = tile_center - Vector2(half_ext, half_ext)
			var max_p: Vector2 = tile_center + Vector2(half_ext, half_ext)
			var closest: Vector2 = Vector2(
				clampf(world_center.x, min_p.x, max_p.x),
				clampf(world_center.y, min_p.y, max_p.y)
			)
			var dist_sq: float = world_center.distance_squared_to(closest)
			if dist_sq > radius * radius:
				continue
			if not found or dist_sq < best_dist_sq:
				found = true
				best_dist_sq = dist_sq
				best_tile = candidate

	if not found:
		return false
	return damage_player_wall_at_tile(best_tile, amount)

func hit_wall_at_world_pos(world_pos: Vector2, amount: int = 1, radius: float = 20.0, allow_structural_feedback: bool = true) -> bool:
	var hit_amount: int = maxi(1, amount)
	var hit_radius: float = maxf(radius, 0.0)
	var hit_player_wall: bool = false

	if hit_radius > 0.0:
		hit_player_wall = damage_player_wall_in_circle(world_pos, hit_radius, hit_amount)
	if not hit_player_wall:
		hit_player_wall = damage_player_wall_at_world_pos(world_pos, hit_amount)
	if hit_player_wall:
		return true
	if not allow_structural_feedback:
		return false

	var structural_tile: Vector2i = WallTileResolverScript.find_nearest_structural_wall_tile(world_pos, hit_radius, Callable(self, "_world_to_tile"), Callable(self, "_is_valid_world_tile"), Callable(self, "_is_structural_wall_tile"), Callable(self, "_tile_to_world"), _get_wall_tile_size_vec())
	if structural_tile.x < 0 or structural_tile.y < 0:
		return false
	_play_structural_wall_hit_feedback(structural_tile)
	return true

func damage_player_wall_at_tile(tile_pos: Vector2i, amount: int = 1) -> bool:
	if amount <= 0:
		amount = 1
	var cpos := _tile_to_chunk(tile_pos)
	var data := WorldSave.get_player_wall(cpos.x, cpos.y, tile_pos)
	if data.is_empty():
		return false
	_play_player_wall_hit_feedback(tile_pos)
	var configured_max_hp: int = maxi(1, player_wallwood_max_hp)
	var current_hp := int(data.get(WorldSave.PLAYER_WALL_HP_KEY, configured_max_hp))
	var normalized_hp: int = clampi(current_hp, 1, configured_max_hp)
	if normalized_hp != current_hp:
		WorldSave.set_player_wall(cpos.x, cpos.y, tile_pos, normalized_hp)
	current_hp = normalized_hp
	var new_hp := current_hp - amount
	if new_hp > 0:
		WorldSave.set_player_wall(cpos.x, cpos.y, tile_pos, new_hp)
		return true
	return remove_player_wall_at_tile(tile_pos, player_wall_drop_enabled)

func remove_player_wall_at_tile(tile_pos: Vector2i, drop_item: bool = true) -> bool:
	var cpos := _tile_to_chunk(tile_pos)
	if not WorldSave.has_player_wall(cpos.x, cpos.y, tile_pos):
		return false
	walls_tilemap.erase_cell(walls_map_layer, tile_pos)
	WorldSave.remove_player_wall(cpos.x, cpos.y, tile_pos)
	var reconnect_neighbors := _collect_existing_wall_neighbors(tile_pos)
	_apply_wall_terrain_connect(reconnect_neighbors)
	var reconnect_scope := _collect_reconnect_neighborhood(tile_pos)
	_reconcile_wall_ownership_in_scope(reconnect_scope)
	if _enforce_removed_wall_tile_cleared(tile_pos):
		reconnect_neighbors = _collect_existing_wall_neighbors(tile_pos)
		_apply_wall_terrain_connect(reconnect_neighbors)
		_enforce_removed_wall_tile_cleared(tile_pos)
	_mark_walls_dirty_and_refresh_for_tiles(reconnect_scope)
	if drop_item and player_wall_drop_enabled and player_wall_drop_amount > 0:
		_spawn_player_wall_drop(tile_pos)
	return true

func apply_saved_walls_for_chunk(chunk_pos: Vector2i) -> void:
	if not loaded_chunks.has(chunk_pos):
		return
	var entries: Array[Dictionary] = WorldSave.list_player_walls_in_chunk(chunk_pos.x, chunk_pos.y)
	if entries.is_empty():
		return
	var player_tiles_dict: Dictionary = {}
	for entry in entries:
		var tile_raw: Variant = entry.get("tile", Vector2i(-1, -1))
		if not (tile_raw is Vector2i):
			continue
		var tile_pos: Vector2i = tile_raw as Vector2i
		if not _is_valid_world_tile(tile_pos):
			continue
		player_tiles_dict[tile_pos] = true
	var player_tiles: Array[Vector2i] = _dict_keys_to_vector2i_array(player_tiles_dict)
	_apply_player_wall_tiles_strict(player_tiles)

func _get_wall_tile_size_vec() -> Vector2:
	var tile_size_vec: Vector2 = Vector2(32.0, 32.0)
	if walls_tilemap != null and walls_tilemap.tile_set != null:
		tile_size_vec = Vector2(walls_tilemap.tile_set.tile_size)
	return tile_size_vec

func _enforce_removed_wall_tile_cleared(tile_pos: Vector2i) -> bool:
	if not _is_valid_world_tile(tile_pos):
		return false
	if _is_player_wall_tile(tile_pos):
		return false
	if _is_structural_wall_tile(tile_pos):
		return false
	if walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos) == -1:
		return false
	walls_tilemap.erase_cell(walls_map_layer, tile_pos)
	return true

func _play_player_wall_hit_feedback(tile_pos: Vector2i) -> void:
	_play_player_wall_hit_sfx(tile_pos)
	_spawn_player_wall_hit_shake(tile_pos)

func _play_structural_wall_hit_feedback(tile_pos: Vector2i) -> void:
	_play_player_wall_hit_sfx(tile_pos)

func _play_player_wall_hit_sfx(tile_pos: Vector2i) -> void:
	var sfx := _pick_player_wall_hit_sound()
	if sfx == null:
		return
	AudioSystem.play_2d(sfx, _tile_to_world(tile_pos), owner, &"SFX", player_wall_hit_volume_db)

func _pick_player_wall_hit_sound() -> AudioStream:
	if player_wall_hit_sounds.is_empty():
		return null
	return player_wall_hit_sounds[randi() % player_wall_hit_sounds.size()]

func _to_valid_sound_pool(pool: Array) -> Array[AudioStream]:
	var valid: Array[AudioStream] = []
	for stream in pool:
		if stream is AudioStream and stream != null:
			valid.append(stream as AudioStream)
	return valid

func _spawn_player_wall_hit_shake(tile_pos: Vector2i) -> void:
	var source_id: int = walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos)
	var atlas_coords: Vector2i = walls_tilemap.get_cell_atlas_coords(walls_map_layer, tile_pos)
	if atlas_coords.x < 0 or atlas_coords.y < 0:
		atlas_coords = player_wall_fallback_atlas
	var alternative_tile: int = walls_tilemap.get_cell_alternative_tile(walls_map_layer, tile_pos)
	var feedback_result: Dictionary = TileHitFeedbackScript.spawn_tile_hit_feedback(
		owner,
		walls_tilemap,
		walls_map_layer,
		tile_pos,
		{
			"source_id": source_id,
			"fallback_source_id": src_walls,
			"atlas_coords": atlas_coords,
			"alternative_tile": alternative_tile,
			"fallback_atlas": player_wall_fallback_atlas,
			"fallback_alternative_tile": player_wall_fallback_alt,
			"shake_duration": player_wall_hit_shake_duration,
			"shake_speed": player_wall_hit_shake_speed,
			"shake_px": player_wall_hit_shake_px,
			"flash_time": player_wall_hit_flash_time,
			"tint": player_wall_hit_tint,
			"z_index": max(walls_tilemap.z_index + 2, 7),
		}
	)
	if bool(feedback_result.get("ok", false)):
		return
	if Debug.is_enabled("wall"):
		var reason: String = String(feedback_result.get("reason", "unknown"))
		Debug.log("wall", "wallwood shake skipped at %s reason=%s" % [str(tile_pos), reason])

func _spawn_player_wall_drop(tile_pos: Vector2i) -> void:
	if player_wall_drop_item_id == "":
		return
	var origin := _tile_to_world(tile_pos) + Vector2(0.0, -10.0)
	var overrides := {"drop_scene": ITEM_DROP_SCENE}
	LootSystem.spawn_drop(null, player_wall_drop_item_id, player_wall_drop_amount, origin, owner, overrides)

func _collect_wall_connect_cells_for_placement(tile_pos: Vector2i) -> Array[Vector2i]:
	var out: Dictionary = {}
	out[tile_pos] = true
	for offset_raw in wall_reconnect_offsets:
		var offset: Vector2i = offset_raw
		var probe: Vector2i = tile_pos + offset
		if not _is_valid_world_tile(probe):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, probe) == src_walls:
			out[probe] = true
	return _dict_keys_to_vector2i_array(out)

func _collect_existing_wall_neighbors(tile_pos: Vector2i) -> Array[Vector2i]:
	var out: Dictionary = {}
	for offset_raw in wall_reconnect_offsets:
		var offset: Vector2i = offset_raw
		if offset == Vector2i.ZERO:
			continue
		var probe: Vector2i = tile_pos + offset
		if not _is_valid_world_tile(probe):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, probe) == src_walls:
			out[probe] = true
	return _dict_keys_to_vector2i_array(out)

func _collect_reconnect_neighborhood(tile_pos: Vector2i) -> Array[Vector2i]:
	var out: Dictionary = {}
	for offset_raw in wall_reconnect_offsets:
		var offset: Vector2i = offset_raw
		var probe: Vector2i = tile_pos + offset
		if not _is_valid_world_tile(probe):
			continue
		out[probe] = true
	return _dict_keys_to_vector2i_array(out)

func _collect_scope_for_cells(base_cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Dictionary = {}
	for base_cell in base_cells:
		if not _is_valid_world_tile(base_cell):
			continue
		for offset_raw in wall_reconnect_offsets:
			var offset: Vector2i = offset_raw
			var probe: Vector2i = base_cell + offset
			if _is_valid_world_tile(probe):
				out[probe] = true
	return _dict_keys_to_vector2i_array(out)

func _capture_existing_player_walls_in_cells(cells: Array[Vector2i]) -> Dictionary:
	var out: Dictionary = {}
	for cell in cells:
		if not _is_valid_world_tile(cell):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, cell) != src_walls:
			continue
		if _is_player_wall_tile(cell):
			out[cell] = true
	return out

func _capture_existing_structural_walls_in_cells(cells: Array[Vector2i]) -> Dictionary:
	var out: Dictionary = {}
	for cell in cells:
		if not _is_valid_world_tile(cell):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, cell) != src_walls:
			continue
		if _is_structural_wall_tile(cell):
			out[cell] = true
	return out

func _sanitize_unexpected_walls(scope_cells: Array[Vector2i], allowed_cells: Dictionary, keep_structural: bool = false) -> bool:
	var removed_any := false
	for cell in scope_cells:
		if not _is_valid_world_tile(cell):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, cell) != src_walls:
			continue
		if allowed_cells.has(cell):
			continue
		if keep_structural and _is_structural_wall_tile(cell):
			continue
		walls_tilemap.erase_cell(walls_map_layer, cell)
		removed_any = true
	return removed_any

func _apply_player_wall_tiles_strict(player_tiles: Array[Vector2i]) -> bool:
	if player_tiles.is_empty():
		return true
	var valid_tiles_dict: Dictionary = {}
	for tile_pos in player_tiles:
		if _is_valid_world_tile(tile_pos):
			valid_tiles_dict[tile_pos] = true
	var valid_tiles: Array[Vector2i] = _dict_keys_to_vector2i_array(valid_tiles_dict)
	if valid_tiles.is_empty():
		return false
	var scope_cells: Array[Vector2i] = _collect_scope_for_cells(valid_tiles)
	var existing_player_walls: Dictionary = _capture_existing_player_walls_in_cells(scope_cells)
	var protected_structural_cells: Dictionary = _capture_existing_structural_walls_in_cells(scope_cells)
	var player_connect_cells: Dictionary = existing_player_walls.duplicate(true)
	for tile_pos in valid_tiles:
		player_connect_cells[tile_pos] = true
	var player_connect_list: Array[Vector2i] = _dict_keys_to_vector2i_array(player_connect_cells)
	var allowed_cells: Dictionary = player_connect_cells.duplicate(true)
	for structural_cell in protected_structural_cells.keys():
		if structural_cell is Vector2i:
			allowed_cells[structural_cell] = true

	if player_connect_list.size() <= 1:
		if not _ensure_wall_cells_exist(valid_tiles):
			return false
		_reconcile_wall_ownership_in_scope(scope_cells, valid_tiles_dict)
		return true

	_apply_wall_terrain_connect(player_connect_list)
	if not _ensure_wall_cells_exist(player_connect_list):
		return false

	if _sanitize_unexpected_walls(scope_cells, allowed_cells, true):
		_apply_wall_terrain_connect(player_connect_list)
		_sanitize_unexpected_walls(scope_cells, allowed_cells, true)
		if not _ensure_wall_cells_exist(player_connect_list):
			return false

	_reconcile_wall_ownership_in_scope(scope_cells, valid_tiles_dict)

	for tile_pos in valid_tiles:
		if walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos) != src_walls:
			return false
	return true

func _is_player_wall_tile(tile_pos: Vector2i) -> bool:
	var cpos := _tile_to_chunk(tile_pos)
	return WorldSave.has_player_wall(cpos.x, cpos.y, tile_pos)

func _is_structural_wall_tile(tile_pos: Vector2i) -> bool:
	var cpos := _tile_to_chunk(tile_pos)
	if not chunk_save.has(cpos):
		return false
	var chunk_data: Variant = chunk_save[cpos]
	if typeof(chunk_data) != TYPE_DICTIONARY:
		return false
	var placed_tiles: Array = (chunk_data as Dictionary).get("placed_tiles", [])
	for raw_tile in placed_tiles:
		if typeof(raw_tile) != TYPE_DICTIONARY:
			continue
		var tile_data: Dictionary = raw_tile as Dictionary
		var source_id: int = int(tile_data.get("source", 0))
		if source_id != -1 and source_id != src_walls:
			continue
		var saved_tile: Variant = tile_data.get("tile", Vector2i(-1, -1))
		if saved_tile is Vector2i and (saved_tile as Vector2i) == tile_pos:
			return true
	return false

func _reconcile_wall_ownership_in_scope(scope_cells: Array[Vector2i], keep_tiles: Dictionary = {}) -> bool:
	var removed_any: bool = _erase_unowned_walls_in_scope(scope_cells, keep_tiles)
	if not removed_any:
		return false

	var survivor_cells: Array[Vector2i] = _collect_scope_wall_cells(scope_cells)
	if survivor_cells.is_empty():
		return true
	_apply_wall_terrain_connect(survivor_cells)

	var removed_after_connect: bool = _erase_unowned_walls_in_scope(scope_cells, keep_tiles)
	if removed_after_connect:
		survivor_cells = _collect_scope_wall_cells(scope_cells)
		if not survivor_cells.is_empty():
			_apply_wall_terrain_connect(survivor_cells)
	return true

func _erase_unowned_walls_in_scope(scope_cells: Array[Vector2i], keep_tiles: Dictionary = {}) -> bool:
	var removed_any: bool = false
	for cell in scope_cells:
		if not _is_valid_world_tile(cell):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, cell) != src_walls:
			continue
		if keep_tiles.has(cell):
			continue
		if _is_player_wall_tile(cell):
			continue
		if _is_structural_wall_tile(cell):
			continue
		walls_tilemap.erase_cell(walls_map_layer, cell)
		removed_any = true
	return removed_any

func _collect_scope_wall_cells(scope_cells: Array[Vector2i]) -> Array[Vector2i]:
	var survivor_cells_dict: Dictionary = {}
	for cell in scope_cells:
		if not _is_valid_world_tile(cell):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, cell) == src_walls:
			survivor_cells_dict[cell] = true
	return _dict_keys_to_vector2i_array(survivor_cells_dict)

func _ensure_wall_cells_exist(cells: Array[Vector2i]) -> bool:
	for tile_pos in cells:
		if not _is_valid_world_tile(tile_pos):
			continue
		if walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos) == src_walls:
			continue
		if not _force_place_player_wall_tile(tile_pos):
			return false
	return true

func _dict_keys_to_vector2i_array(dict: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in dict.keys():
		if key is Vector2i:
			out.append(key as Vector2i)
	return out

func _apply_wall_terrain_connect(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	walls_tilemap.set_cells_terrain_connect(walls_map_layer, cells, wall_terrain_set, wall_terrain, true)

func _force_place_player_wall_tile(tile_pos: Vector2i) -> bool:
	if not _is_valid_world_tile(tile_pos):
		return false
	walls_tilemap.set_cell(
		walls_map_layer,
		tile_pos,
		src_walls,
		player_wall_fallback_atlas,
		player_wall_fallback_alt
	)
	return walls_tilemap.get_cell_source_id(walls_map_layer, tile_pos) == src_walls

func _mark_walls_dirty_and_refresh_for_tiles(tile_positions: Array[Vector2i]) -> void:
	if mark_chunk_walls_dirty_and_refresh_for_tiles_cb.is_valid():
		mark_chunk_walls_dirty_and_refresh_for_tiles_cb.call(tile_positions)

func _is_valid_world_tile(tile_pos: Vector2i) -> bool:
	return tile_pos.x >= 0 and tile_pos.x < width and tile_pos.y >= 0 and tile_pos.y < height

func _tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	if tile_to_chunk_cb.is_valid():
		return tile_to_chunk_cb.call(tile_pos)
	return Vector2i(int(floor(float(tile_pos.x) / float(chunk_size))), int(floor(float(tile_pos.y) / float(chunk_size))))

func _world_to_tile(pos: Vector2) -> Vector2i:
	if world_to_tile_cb.is_valid():
		return world_to_tile_cb.call(pos)
	return Vector2i.ZERO

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	if tile_to_world_cb.is_valid():
		return tile_to_world_cb.call(tile_pos)
	return Vector2.ZERO
