extends Node
class_name WallOcclusionComponent

var owner: Node = null
var tilemap: TileMap = null
var opened_wall_tiles: Dictionary = {}
var enabled: bool = true

func setup(p_owner: Node) -> void:
	owner = p_owner
	_resolve_tilemap()

func tick(_delta: float) -> void:
	pass

func physics_tick(_delta: float) -> void:
	pass

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_close_opened_walls()

func on_player_moved(_global_pos: Vector2) -> void:
	if not enabled or owner == null or tilemap == null:
		return

	var still_open: Dictionary = {}
	var base_tile := _probe_tile()
	var tpos := base_tile + owner.probe_tile_offset
	var tpos_up := tpos + Vector2i(0, -1)
	var behind_mode := false

	if _has_wall(tpos):
		_set_wall_alt(tpos, owner.wall_alt_small)
		still_open[tpos] = true
		behind_mode = true
	if _has_wall(tpos_up):
		_set_wall_alt(tpos_up, owner.wall_alt_small)
		still_open[tpos_up] = true
		behind_mode = true

	var main_is_h := _is_horizontal_member(tpos) or _is_horizontal_member(tpos_up)
	if behind_mode and main_is_h and absf(owner.velocity.x) > 0.1:
		var side := 1 if owner.velocity.x > 0.0 else -1
		var lateral := tpos + Vector2i(side, 0)
		var lateral_up := tpos_up + Vector2i(side, 0)
		if _is_horizontal_interior(lateral) or _is_horizontal_end(lateral) or _is_top_corner(lateral):
			_set_wall_alt(lateral, owner.wall_alt_small)
			still_open[lateral] = true
		if _is_horizontal_interior(lateral_up) or _is_horizontal_end(lateral_up) or _is_top_corner(lateral_up):
			_set_wall_alt(lateral_up, owner.wall_alt_small)
			still_open[lateral_up] = true

	if absf(owner.velocity.x) > 0.1:
		var side2 := 1 if owner.velocity.x > 0.0 else -1
		var approach := tpos + Vector2i(side2, 0)
		var approach_up := tpos_up + Vector2i(side2, 0)
		if _is_horizontal_end(approach) or _is_top_corner(approach):
			_set_wall_alt(approach, owner.wall_alt_small)
			still_open[approach] = true
		if _is_horizontal_end(approach_up) or _is_top_corner(approach_up):
			_set_wall_alt(approach_up, owner.wall_alt_small)
			still_open[approach_up] = true

	for old_tpos in opened_wall_tiles.keys():
		if not still_open.has(old_tpos):
			_set_wall_alt(old_tpos, owner.wall_alt_full)

	if behind_mode and _has_wall(tpos_up):
		tilemap.set_layer_modulate(owner.walls_layer, Color(1, 1, 1, 0.4))
	else:
		tilemap.set_layer_modulate(owner.walls_layer, Color(1, 1, 1, 1.0))

	opened_wall_tiles = still_open

func close() -> void:
	_close_opened_walls()

func _resolve_tilemap() -> void:
	if owner == null:
		return
	if owner.tilemap_path != NodePath():
		tilemap = owner.get_node_or_null(owner.tilemap_path) as TileMap
	if tilemap == null:
		tilemap = owner.get_node_or_null("../World/WorldTileMap") as TileMap
	if tilemap == null:
		push_warning("[WALL_TOGGLE] No encuentro el TileMap. Asigna tilemap_path en el Inspector.")
	else:
		owner.player_debug("[WALL_TOGGLE] OK tilemap=%s" % tilemap.get_path())

func _probe_tile() -> Vector2i:
	if tilemap == null or owner == null:
		return Vector2i.ZERO
	var probe_world_pos := owner.global_position + Vector2(0.0, owner.wall_probe_px)
	return tilemap.local_to_map(tilemap.to_local(probe_world_pos))

func _has_wall(pos: Vector2i) -> bool:
	if tilemap == null or owner == null:
		return false
	return tilemap.get_cell_source_id(owner.walls_layer, pos) == owner.walls_source_id

func _set_wall_alt(pos: Vector2i, alt: int) -> void:
	if tilemap == null or owner == null:
		return
	var src := tilemap.get_cell_source_id(owner.walls_layer, pos)
	if src == -1:
		return
	var atlas := tilemap.get_cell_atlas_coords(owner.walls_layer, pos)
	var prev_alt := tilemap.get_cell_alternative_tile(owner.walls_layer, pos)
	if prev_alt == alt:
		return
	tilemap.set_cell(owner.walls_layer, pos, src, atlas, alt)
	var check_alt := tilemap.get_cell_alternative_tile(owner.walls_layer, pos)
	if check_alt != alt:
		tilemap.set_cell(owner.walls_layer, pos, src, atlas, prev_alt)

func _is_horizontal_member(pos: Vector2i) -> bool:
	if not _has_wall(pos):
		return false
	return _has_wall(pos + Vector2i(-1, 0)) or _has_wall(pos + Vector2i(1, 0))

func _is_horizontal_interior(pos: Vector2i) -> bool:
	if not _has_wall(pos):
		return false
	return _has_wall(pos + Vector2i(-1, 0)) and _has_wall(pos + Vector2i(1, 0))

func _is_horizontal_end(pos: Vector2i) -> bool:
	if not _has_wall(pos):
		return false
	var has_left := _has_wall(pos + Vector2i(-1, 0))
	var has_right := _has_wall(pos + Vector2i(1, 0))
	var has_above := _has_wall(pos + Vector2i(0, -1))
	var has_below := _has_wall(pos + Vector2i(0, 1))
	if has_above or has_below:
		return false
	return has_left != has_right

func _is_top_corner(pos: Vector2i) -> bool:
	if not _has_wall(pos):
		return false
	var has_left := _has_wall(pos + Vector2i(-1, 0))
	var has_right := _has_wall(pos + Vector2i(1, 0))
	var has_below := _has_wall(pos + Vector2i(0, 1))
	return (has_left != has_right) and has_below

func _close_opened_walls() -> void:
	if owner == null:
		return
	for tpos in opened_wall_tiles.keys():
		_set_wall_alt(tpos, owner.wall_alt_full)
	opened_wall_tiles.clear()
