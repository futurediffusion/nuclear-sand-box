extends Node
class_name WallOcclusionComponent

var player: Player = null
var tilemap: TileMap = null
var opened_wall_tiles: Dictionary = {}
var enabled: bool = true

@export var update_interval := 0.10
@export var move_threshold_px := 8.0
var _accum := 0.0
var _last_player_pos := Vector2.INF

func setup(p_player: Player) -> void:
	player = p_player
	_resolve_tilemap()
	if tilemap == null:
		push_warning("[WallOcclusion] setup without tilemap")

func tick(_delta: float) -> void:
	if player == null:
		return
	pass

func physics_tick(delta: float) -> void:
	if player == null:
		push_warning("[WallOcclusion] Player missing in physics_tick")
		return
	if not enabled:
		return
	if tilemap == null:
		push_warning("[WallOcclusion] TileMap missing, disabling component")
		enabled = false
		return
	if not player.is_in_group("player"):
		return

	_accum += delta
	if _accum < update_interval:
		return
	_accum = 0.0

	if _last_player_pos != Vector2.INF and player.global_position.distance_to(_last_player_pos) < move_threshold_px:
		return

	_last_player_pos = player.global_position
	_update_occlusion()

func set_enabled(value: bool) -> void:
	if player == null:
		return
	enabled = value
	if not enabled:
		_close_opened_walls()

func on_player_moved(_global_pos: Vector2) -> void:
	if player == null:
		return
	if not enabled or tilemap == null:
		return
	if not player.is_in_group("player"):
		return
	_update_occlusion()

func close() -> void:
	if player == null:
		return
	_close_opened_walls()

func _resolve_tilemap() -> void:
	if player == null:
		return
	if player.tilemap_path != NodePath():
		tilemap = player.get_node_or_null(player.tilemap_path) as TileMap
	if tilemap == null:
		tilemap = player.get_node_or_null("../World/WorldTileMap") as TileMap
	if tilemap == null:
		push_warning("[WALL_TOGGLE] No encuentro el TileMap. Asigna tilemap_path en el Inspector.")
	else:
		Debug.log("wall", "[WALL_TOGGLE] OK tilemap=%s" % tilemap.get_path())

func _update_occlusion() -> void:
	return  # DESACTIVADO: oclusión manejada por OcclusionController + shader
	var still_open: Dictionary = {}

	var base_tile: Vector2i = _probe_tile()
	var tpos: Vector2i = base_tile + player.probe_tile_offset
	var tpos_up: Vector2i = tpos + Vector2i(0, -1)

	var behind_mode: bool = false

	if _has_wall(tpos):
		_set_wall_alt(tpos, player.wall_alt_small)
		still_open[tpos] = true
		behind_mode = true
	if _has_wall(tpos_up):
		_set_wall_alt(tpos_up, player.wall_alt_small)
		still_open[tpos_up] = true
		behind_mode = true

	var main_is_h: bool = _is_horizontal_member(tpos) or _is_horizontal_member(tpos_up)
	if behind_mode and main_is_h and absf(player.velocity.x) > 0.1:
		var side: int = 1 if player.velocity.x > 0.0 else -1
		var lateral: Vector2i = tpos + Vector2i(side, 0)
		var lateral_up: Vector2i = tpos_up + Vector2i(side, 0)
		if _is_horizontal_interior(lateral) or _is_horizontal_end(lateral) or _is_top_corner(lateral):
			_set_wall_alt(lateral, player.wall_alt_small)
			still_open[lateral] = true
		if _is_horizontal_interior(lateral_up) or _is_horizontal_end(lateral_up) or _is_top_corner(lateral_up):
			_set_wall_alt(lateral_up, player.wall_alt_small)
			still_open[lateral_up] = true

	if absf(player.velocity.x) > 0.1:
		var side2: int = 1 if player.velocity.x > 0.0 else -1
		var approach: Vector2i = tpos + Vector2i(side2, 0)
		var approach_up: Vector2i = tpos_up + Vector2i(side2, 0)
		if _is_horizontal_end(approach) or _is_top_corner(approach):
			_set_wall_alt(approach, player.wall_alt_small)
			still_open[approach] = true
		if _is_horizontal_end(approach_up) or _is_top_corner(approach_up):
			_set_wall_alt(approach_up, player.wall_alt_small)
			still_open[approach_up] = true

	for old_tpos: Variant in opened_wall_tiles.keys():
		if not still_open.has(old_tpos):
			_set_wall_alt(old_tpos as Vector2i, player.wall_alt_full)

	if behind_mode and _has_wall(tpos_up):
		tilemap.set_layer_modulate(player.walls_layer, Color(1, 1, 1, 0.4))
	else:
		tilemap.set_layer_modulate(player.walls_layer, Color(1, 1, 1, 1.0))

	opened_wall_tiles = still_open

func _probe_tile() -> Vector2i:
	if tilemap == null or player == null:
		return Vector2i.ZERO
	var probe_world_pos: Vector2 = player.global_position + Vector2(0.0, player.wall_probe_px)
	return tilemap.local_to_map(tilemap.to_local(probe_world_pos))

func _has_wall(pos: Vector2i) -> bool:
	if tilemap == null or player == null:
		return false
	return tilemap.get_cell_source_id(player.walls_layer, pos) == player.walls_source_id

func _set_wall_alt(pos: Vector2i, alt: int) -> void:
	if tilemap == null or player == null:
		return
	var src: int = tilemap.get_cell_source_id(player.walls_layer, pos)
	if src == -1:
		return
	var atlas: Vector2i = tilemap.get_cell_atlas_coords(player.walls_layer, pos)
	var prev_alt: int = tilemap.get_cell_alternative_tile(player.walls_layer, pos)
	if prev_alt == alt:
		return
	tilemap.set_cell(player.walls_layer, pos, src, atlas, alt)
	var check_alt: int = tilemap.get_cell_alternative_tile(player.walls_layer, pos)
	if check_alt != alt:
		tilemap.set_cell(player.walls_layer, pos, src, atlas, prev_alt)

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
	var has_left: bool = _has_wall(pos + Vector2i(-1, 0))
	var has_right: bool = _has_wall(pos + Vector2i(1, 0))
	var has_above: bool = _has_wall(pos + Vector2i(0, -1))
	var has_below: bool = _has_wall(pos + Vector2i(0, 1))
	if has_above or has_below:
		return false
	return has_left != has_right

func _is_top_corner(pos: Vector2i) -> bool:
	if not _has_wall(pos):
		return false
	var has_left: bool = _has_wall(pos + Vector2i(-1, 0))
	var has_right: bool = _has_wall(pos + Vector2i(1, 0))
	var has_below: bool = _has_wall(pos + Vector2i(0, 1))
	return (has_left != has_right) and has_below

func _close_opened_walls() -> void:
	if player == null:
		return
	for tpos: Variant in opened_wall_tiles.keys():
		_set_wall_alt(tpos as Vector2i, player.wall_alt_full)
	opened_wall_tiles.clear()
	_last_player_pos = Vector2.INF
	_accum = 0.0
