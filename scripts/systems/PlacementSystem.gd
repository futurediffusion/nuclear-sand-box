extends Node

## Autoload: PlacementSystem
## Gestiona el modo de colocación de objetos placeables en mundo.
## Para agregar un nuevo placeable: registrar item_id → scene_path en PlacementCatalog.

signal placement_completed(item_id: String, tile_pos: Vector2i)
signal placement_cancelled(item_id: String)

const TILE_SIZE: int = 32
const GHOST_SCENE: PackedScene = preload("res://scenes/placement_ghost.tscn")

## Compat temporal: mantener símbolos históricos para referencias externas.
const PLACEABLE_SCENES: Dictionary = PlacementCatalog.PLACEABLE_SCENES
const TILE_WALL_ITEMS: Dictionary = PlacementCatalog.TILE_WALL_ITEMS
const REPEAT_SCENE_ITEMS: Dictionary = PlacementCatalog.REPEAT_SCENE_ITEMS
const PLACEMENT_MODE_SCENE: String = PlacementCatalog.PLACEMENT_MODE_SCENE
const PLACEMENT_MODE_TILE_WALL: String = PlacementCatalog.PLACEMENT_MODE_TILE_WALL
const PLACEMENT_CLICK_COMBAT_BLOCK_MS: int = 120
const PLACEMENT_HOVER_SFX: Array[AudioStream] = [
	preload("res://art/Sounds/place1.ogg"),
	preload("res://art/Sounds/place2.ogg"),
	preload("res://art/Sounds/place3.ogg"),
	preload("res://art/Sounds/place4.ogg"),
]
const DEFAULT_PLACEMENT_HOVER_VOLUME_DB: float = 0.0
const DEFAULT_DOOR_PLACE_VOLUME_DB: float = 0.0
const WALLWOOD_PLACE_SFX: AudioStream = preload("res://art/Sounds/woodwallplace.ogg")
const WORKBENCH_PLACE_SFX: AudioStream = preload("res://art/Sounds/workbenchplace.ogg")
const CHEST_PLACE_SFX: AudioStream = preload("res://art/Sounds/chestplace.ogg")
const DOOR_PLACE_SFX: AudioStream = preload("res://art/Sounds/doorplace.ogg")
const FLOORWOOD_PLACE_SFX: AudioStream = preload("res://art/Sounds/placewoodfloor.ogg")
const DOORWOOD_ITEM_ID: String = BuildableCatalog.ID_DOORWOOD

var _active:       bool   = false
var _item_id:      String = ""
var _scene_path:   String = ""
var _placement_mode: String = ""
var _can_place:    bool   = false
var _ghost:        Node2D = null
var _ghost_sprite: Sprite2D = null
var _world_cache:  Node2D = null
var _check_shape:  RectangleShape2D = null  # cached — reutilizado cada frame
var _combat_block_pushed: bool = false
var _last_hover_tile: Vector2i = Vector2i.ZERO
var _has_last_hover_tile: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _drag_painting: bool = false
var _drag_last_tile: Vector2i = Vector2i.ZERO
var _has_drag_last_tile: bool = false
var _drag_painted_wall_tiles: Dictionary = {}

# Máscara de capas que bloquean colocación: WALLPROPS(16) + Resources(8) + Player(1)
const BLOCK_MASK: int = CollisionLayers.WORLD_WALL_LAYER_MASK \
					  | CollisionLayers.RESOURCES_LAYER_MASK \
					  | 1


# ── API pública ───────────────────────────────────────────────────────────────

func begin_placement(item_id: String, icon: Texture2D = null) -> void:
	if _active:
		cancel_placement()
	var scene_path := ""
	var placement_mode := PlacementCatalog.resolve_placement_mode(item_id)
	if placement_mode == PLACEMENT_MODE_TILE_WALL:
		# tile-wall no instancia escena world directamente.
		scene_path = ""
	else:
		scene_path = PlacementCatalog.resolve_scene_path(item_id)
		if scene_path == "":
			push_warning("[PlacementSystem] No hay escena registrada para item_id='%s'" % item_id)
			return
	_active     = true
	_item_id    = item_id
	_scene_path = scene_path
	_placement_mode = placement_mode
	_last_hover_tile = Vector2i.ZERO
	_has_last_hover_tile = false
	_drag_painted_wall_tiles.clear()
	_stop_drag_paint()
	_acquire_combat_block()
	_spawn_ghost(icon)


func cancel_placement() -> void:
	if not _active:
		return
	var id := _item_id
	_cleanup()
	placement_cancelled.emit(id)


func is_placing() -> bool:
	return _active


## Restaurar todas las entidades colocadas al cargar el mundo.
func restore_placed_entities(world_node: Node) -> void:
	var restored_door_tiles: Array[Vector2i] = []
	for entry in WorldSave.placed_entities:
		_spawn_placed_instance(entry, world_node)
		if PlacementCatalog.normalize_item_id(String(entry.get("item_id", ""))) != DOORWOOD_ITEM_ID:
			continue
		var door_tile := Vector2i(int(entry.get("tile_pos_x", -999999)), int(entry.get("tile_pos_y", -999999)))
		restored_door_tiles.append(door_tile)
	_refresh_all_door_pairings()
	_refresh_wall_collision_around_tiles(world_node, restored_door_tiles)


## Quitar una entidad colocada por UID (por ejemplo, si la destruyen).
func remove_placed_entity(uid: String) -> void:
	var removed_entry: Dictionary = _find_placed_entity_entry_by_uid(uid)
	WorldSave.remove_placed_entity(uid)
	if removed_entry.is_empty():
		return
	var removed_item_id: String = PlacementCatalog.normalize_item_id(String(removed_entry.get("item_id", "")))
	if removed_item_id != DOORWOOD_ITEM_ID:
		return
	var removed_tile := Vector2i(int(removed_entry.get("tile_pos_x", -999999)), int(removed_entry.get("tile_pos_y", -999999)))
	refresh_door_pairing_around_tile(removed_tile)
	var removed_tiles: Array[Vector2i] = [removed_tile]
	_refresh_wall_collision_around_tiles(_find_world_node(), removed_tiles)


# ── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _is_drag_paint_enabled_for_current_item():
					_drag_painting = true
					_drag_last_tile = _get_mouse_tile()
					_has_drag_last_tile = true
				else:
					_stop_drag_paint()
				UiManager.block_combat_for(PLACEMENT_CLICK_COMBAT_BLOCK_MS)
				if _can_place:
					_do_place()
			else:
				_stop_drag_paint()
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and (ke.physical_keycode == KEY_ESCAPE or ke.keycode == KEY_ESCAPE):
			cancel_placement()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _active and _ghost != null and is_instance_valid(_ghost):
		_update_ghost()
		_process_drag_tile_wall_paint()


func _process_drag_tile_wall_paint() -> void:
	if not _active:
		return
	if not _is_drag_paint_enabled_for_current_item():
		return
	if not _drag_painting:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_stop_drag_paint()
		return
	var current_tile: Vector2i = _get_mouse_tile()
	if not _has_drag_last_tile:
		_drag_last_tile = current_tile
		_has_drag_last_tile = true
		UiManager.block_combat_for(PLACEMENT_CLICK_COMBAT_BLOCK_MS)
		_do_place_at_tile(current_tile)
		return
	if current_tile == _drag_last_tile:
		return
	var segment_tiles: Array[Vector2i] = _build_drag_segment_tiles(_drag_last_tile, current_tile)
	for i in range(1, segment_tiles.size()):
		if not _active:
			return
		UiManager.block_combat_for(PLACEMENT_CLICK_COMBAT_BLOCK_MS)
		_do_place_at_tile(segment_tiles[i])
	_drag_last_tile = current_tile


func _is_drag_paint_enabled_for_current_item() -> bool:
	return PlacementCatalog.is_drag_paint_enabled_item(_item_id)


func _build_drag_segment_tiles(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0: int = from_tile.x
	var y0: int = from_tile.y
	var x1: int = to_tile.x
	var y1: int = to_tile.y
	var dx: int = absi(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -absi(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		out.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return out


func _ready() -> void:
	_rng.randomize()


# ── Validación ────────────────────────────────────────────────────────────────

func can_place_at(tile_pos: Vector2i) -> bool:
	var world := _find_world_node()
	if world == null:
		return false

	# ── 1. TileMap checks ────────────────────────────────────────────────────
	var walls_tm := world.get_node_or_null("StructureWallsMap") as TileMap
	if walls_tm != null and walls_tm.get_cell_source_id(0, tile_pos) != -1:
		return false

	var cliffs_tm := world.get_node_or_null("TileMap_Cliffs") as TileMap
	if cliffs_tm != null and cliffs_tm.get_cell_source_id(0, tile_pos) != -1:
		return false

	# ── 2. Placed entities registry ──────────────────────────────────────────
	for entry in WorldSave.placed_entities:
		var ex: int = int(entry.get("tile_pos_x", -99999))
		var ey: int = int(entry.get("tile_pos_y", -99999))
		if ex == tile_pos.x and ey == tile_pos.y:
			var existing_item_id := String(entry.get("item_id", ""))
			if _can_share_tile_with_existing(existing_item_id):
				continue
			return false

	# ── 3. Physics shape query ────────────────────────────────────────────────
	# Rectángulo 28×28: cubre la tile sin tocar colisiones de tiles adyacentes.
	# Detecta: paredes/placeables (16), árboles/piedras/recursos (8), player (1).
	var space_state := _get_space_state()
	if space_state != null:
		var tile_center_local := Vector2(
			tile_pos.x * TILE_SIZE + TILE_SIZE * 0.5,
			tile_pos.y * TILE_SIZE + TILE_SIZE * 0.5
		)
		var tile_center_global := world.to_global(tile_center_local)
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape               = _get_check_shape()
		params.transform           = Transform2D(0.0, tile_center_global)
		params.collision_mask      = BLOCK_MASK
		params.collide_with_bodies = true
		params.collide_with_areas  = false
		var hits := space_state.intersect_shape(params, 8)
		for hit in hits:
			var collider: Variant = hit.get("collider", null)
			if _is_physics_hit_blocking_for_item(collider):
				return false

	if _placement_mode == PLACEMENT_MODE_TILE_WALL:
		if world.has_method("can_place_player_wall_at_tile"):
			return bool(world.call("can_place_player_wall_at_tile", tile_pos))
		return false

	return true


func _get_check_shape() -> RectangleShape2D:
	if _check_shape == null:
		_check_shape = RectangleShape2D.new()
		_check_shape.size = Vector2(TILE_SIZE - 4, TILE_SIZE - 4)
	return _check_shape


# ── Internals ─────────────────────────────────────────────────────────────────

func _spawn_ghost(icon: Texture2D) -> void:
	_ghost        = GHOST_SCENE.instantiate() as Node2D
	_ghost_sprite = _ghost.get_node_or_null("Sprite2D") as Sprite2D
	if _ghost_sprite != null:
		# El ghost se posiciona por esquina de tile (x*32,y*32), así que
		# el sprite también debe renderizarse sin centrado para evitar offset 0.5 tile.
		_ghost_sprite.centered = false
		_ghost_sprite.offset = Vector2.ZERO
		_ghost_sprite.position = Vector2.ZERO
		_ghost_sprite.scale = Vector2.ONE
		_ghost_sprite.flip_h = false
		_ghost_sprite.flip_v = false
	if _ghost_sprite != null and icon != null:
		_ghost_sprite.texture = icon
	_apply_scene_visual_profile_to_ghost()
	var world := _find_world_node()
	var parent: Node = world if world != null else get_tree().current_scene
	parent.add_child(_ghost)
	_update_ghost()


func _apply_scene_visual_profile_to_ghost() -> void:
	if _ghost_sprite == null:
		return
	if _placement_mode != PLACEMENT_MODE_SCENE:
		return
	if _scene_path == "":
		return
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		return
	var preview_root := packed.instantiate()
	if preview_root == null:
		return
	var source_sprite := _find_first_sprite_2d(preview_root)
	if source_sprite == null:
		preview_root.free()
		return

	_ghost_sprite.centered = source_sprite.centered
	_ghost_sprite.offset = source_sprite.offset
	_ghost_sprite.flip_h = source_sprite.flip_h
	_ghost_sprite.flip_v = source_sprite.flip_v
	_ghost_sprite.hframes = source_sprite.hframes
	_ghost_sprite.vframes = source_sprite.vframes
	_ghost_sprite.frame = source_sprite.frame
	_ghost_sprite.region_enabled = source_sprite.region_enabled
	_ghost_sprite.region_rect = source_sprite.region_rect
	if _ghost_sprite.texture == null:
		_ghost_sprite.texture = source_sprite.texture

	if preview_root is Node2D:
		var root_2d := preview_root as Node2D
		var source_global := source_sprite.global_transform
		var relative: Transform2D = root_2d.global_transform.affine_inverse() * source_global
		_ghost_sprite.position = relative.origin
		_ghost_sprite.scale = Vector2(relative.x.length(), relative.y.length())
	else:
		_ghost_sprite.position = source_sprite.position
		_ghost_sprite.scale = source_sprite.scale

	preview_root.free()


func _find_first_sprite_2d(root: Node) -> Sprite2D:
	if root == null:
		return null
	if root is Sprite2D:
		return root as Sprite2D
	for child in root.get_children():
		if not (child is Node):
			continue
		var nested := _find_first_sprite_2d(child as Node)
		if nested != null:
			return nested
	return null


func _update_ghost() -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	var tile := _get_mouse_tile()
	if _has_last_hover_tile and tile != _last_hover_tile:
		_play_hover_tile_sfx()
	_last_hover_tile = tile
	_has_last_hover_tile = true
	_ghost.position = Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)
	_can_place      = can_place_at(tile)
	if _ghost_sprite != null:
		_ghost_sprite.modulate = Color(0.5, 1.0, 0.5, 0.7) if _can_place else Color(1.0, 0.35, 0.35, 0.5)


func _play_hover_tile_sfx() -> void:
	if PLACEMENT_HOVER_SFX.is_empty():
		return
	var stream := PLACEMENT_HOVER_SFX[_rng.randi_range(0, PLACEMENT_HOVER_SFX.size() - 1)]
	if stream == null:
		return
	var ghost_pos := _ghost.global_position if _ghost != null else Vector2.ZERO
	var sound_pos := ghost_pos + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	AudioSystem.play_2d(stream, sound_pos, null, &"SFX", _resolve_placement_hover_volume_db())


func _play_tile_wall_place_sfx(tile: Vector2i) -> void:
	if _item_id != "wallwood":
		return
	_play_placement_sfx_at_tile(WALLWOOD_PLACE_SFX, tile)


func _play_scene_place_sfx(item_id: String, tile: Vector2i) -> void:
	var stream: AudioStream = null
	var volume_db: float = 0.0
	match PlacementCatalog.normalize_item_id(item_id):
		"workbench":
			stream = WORKBENCH_PLACE_SFX
		"chest":
			stream = CHEST_PLACE_SFX
		"barrel":
			stream = CHEST_PLACE_SFX
		"stool":
			stream = CHEST_PLACE_SFX
		"doorwood":
			stream = _resolve_door_place_sfx()
			volume_db = _resolve_door_place_volume_db()
		"floorwood":
			stream = FLOORWOOD_PLACE_SFX
		_:
			return
	_play_placement_sfx_at_tile(stream, tile, volume_db)


func _play_placement_sfx_at_tile(stream: AudioStream, tile: Vector2i, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var world := _find_world_node()
	var sound_pos := Vector2(
		tile.x * TILE_SIZE + TILE_SIZE * 0.5,
		tile.y * TILE_SIZE + TILE_SIZE * 0.5
	)
	if world != null:
		sound_pos = world.to_global(sound_pos)
	AudioSystem.play_2d(stream, sound_pos, null, &"SFX", volume_db)


func _get_mouse_tile() -> Vector2i:
	var world := _find_world_node()
	if world == null:
		return Vector2i.ZERO
	var local_mouse := world.get_local_mouse_position()
	return Vector2i(floori(local_mouse.x / float(TILE_SIZE)), floori(local_mouse.y / float(TILE_SIZE)))


func _do_place() -> void:
	var tile := _get_mouse_tile()
	_do_place_at_tile(tile)


func _do_place_at_tile(tile: Vector2i) -> void:
	if not can_place_at(tile):
		return

	# Consumir item del inventario
	var inv := _get_player_inventory()
	if inv == null:
		return
	if not inv.has_method("remove_item"):
		return
	var removed := int(inv.call("remove_item", _item_id, 1))
	if removed < 1:
		if _placement_mode == PLACEMENT_MODE_TILE_WALL or PlacementCatalog.is_repeat_scene_item(_item_id):
			_cleanup()
		return

	if _placement_mode == PLACEMENT_MODE_TILE_WALL:
		var world := _find_world_node()
		var placed_wall := false
		if world != null and world.has_method("place_player_wall_at_tile"):
			placed_wall = bool(world.call("place_player_wall_at_tile", tile))
		if not placed_wall:
			if inv.has_method("add_item"):
				inv.call("add_item", _item_id, 1)
			return
		refresh_door_pairing_around_tile(tile)
		_play_tile_wall_place_sfx(tile)
		placement_completed.emit(_item_id, tile)
		if _drag_painting:
			_drag_painted_wall_tiles[tile] = true
		var remaining: int = 0
		if inv.has_method("get_total"):
			remaining = int(inv.call("get_total", _item_id))
		if remaining <= 0:
			_cleanup()
		else:
			_update_ghost()
		return

	# UID simple basado en tiempo + item_id
	var placed_id := PlacementCatalog.normalize_item_id(_item_id)
	var uid := "%s_%d" % [placed_id, Time.get_ticks_msec()]

	var entry: Dictionary = {
		"uid":       uid,
		"scene":     _scene_path,
		"tile_pos_x": tile.x,
		"tile_pos_y": tile.y,
		"tier":      1,
		"item_id":   placed_id,
	}
	WorldSave.add_placed_entity(entry)

	var world := _find_world_node()
	var parent: Node = world if world != null else get_tree().current_scene
	_spawn_placed_instance(entry, parent)
	if placed_id == DOORWOOD_ITEM_ID:
		refresh_door_pairing_around_tile(tile)
		var door_tiles: Array[Vector2i] = [tile]
		_refresh_wall_collision_around_tiles(world, door_tiles)

	_play_scene_place_sfx(placed_id, tile)
	placement_completed.emit(placed_id, tile)
	if PlacementCatalog.is_repeat_scene_item(placed_id):
		var remaining_scene: int = 0
		if inv.has_method("get_total"):
			remaining_scene = int(inv.call("get_total", _item_id))
			if placed_id != _item_id:
				remaining_scene += int(inv.call("get_total", placed_id))
		if remaining_scene <= 0:
			_cleanup()
		else:
			_update_ghost()
	else:
		_cleanup()


func _spawn_placed_instance(entry: Dictionary, parent: Node) -> void:
	var scene_path := String(entry.get("scene", ""))
	if scene_path == "":
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("[PlacementSystem] No se pudo cargar escena: %s" % scene_path)
		return
	var instance := packed.instantiate()
	# Asignar UID antes de add_child para que _ready() (ej: chest) cargue persistencia correcta.
	if "placed_uid" in instance:
		instance.placed_uid = String(entry.get("uid", ""))
	parent.add_child(instance)
	if instance is Node2D:
		var tx: int = int(entry.get("tile_pos_x", 0))
		var ty: int = int(entry.get("tile_pos_y", 0))
		(instance as Node2D).position = Vector2(tx * TILE_SIZE, ty * TILE_SIZE)
	if instance.has_method("load_persisted_data"):
		instance.call("load_persisted_data")


func refresh_door_pairing_around_tile(_tile_pos: Vector2i) -> void:
	_refresh_all_door_layouts()


func _refresh_all_door_pairings() -> void:
	_refresh_all_door_layouts()


func _refresh_all_door_layouts() -> void:
	var door_uid_by_tile := _collect_door_uid_by_tile()
	if door_uid_by_tile.is_empty():
		return

	var door_vertical_by_tile: Dictionary = {}
	for tile_key in door_uid_by_tile.keys():
		var tile := _tile_key_to_pos(String(tile_key))
		var is_vertical := _resolve_door_is_vertical(tile, door_uid_by_tile)
		door_vertical_by_tile[String(tile_key)] = is_vertical
		_set_door_vertical_layout_state(String(door_uid_by_tile[tile_key]), is_vertical)

	var visited_horizontal: Dictionary = {}
	for tile_key in door_uid_by_tile.keys():
		var key := String(tile_key)
		if visited_horizontal.has(key):
			continue
		if bool(door_vertical_by_tile.get(key, false)):
			visited_horizontal[key] = true
			_set_door_mirrored_state(String(door_uid_by_tile[key]), false)
			continue
		var tile := _tile_key_to_pos(key)
		var start_x := tile.x
		var end_x := tile.x
		while true:
			var left_key := _tile_pos_to_key(Vector2i(start_x - 1, tile.y))
			if not door_uid_by_tile.has(left_key):
				break
			if bool(door_vertical_by_tile.get(left_key, false)):
				break
			start_x -= 1
		while true:
			var right_key := _tile_pos_to_key(Vector2i(end_x + 1, tile.y))
			if not door_uid_by_tile.has(right_key):
				break
			if bool(door_vertical_by_tile.get(right_key, false)):
				break
			end_x += 1
		for x in range(start_x, end_x + 1):
			var span_key := _tile_pos_to_key(Vector2i(x, tile.y))
			visited_horizontal[span_key] = true
			var uid := String(door_uid_by_tile.get(span_key, ""))
			if uid == "":
				continue
			var mirrored := ((x - start_x) % 2) == 1
			_set_door_mirrored_state(uid, mirrored)


func _collect_door_uid_by_tile() -> Dictionary:
	var out: Dictionary = {}
	for entry in WorldSave.placed_entities:
		if PlacementCatalog.normalize_item_id(String(entry.get("item_id", ""))) != DOORWOOD_ITEM_ID:
			continue
		var tile := Vector2i(int(entry.get("tile_pos_x", -999999)), int(entry.get("tile_pos_y", -999999)))
		var uid := String(entry.get("uid", ""))
		if uid == "":
			continue
		out[_tile_pos_to_key(tile)] = uid
	return out


func _resolve_door_is_vertical(tile_pos: Vector2i, door_uid_by_tile: Dictionary) -> bool:
	var has_left := _is_door_or_wall_at_tile(tile_pos + Vector2i.LEFT, door_uid_by_tile)
	var has_right := _is_door_or_wall_at_tile(tile_pos + Vector2i.RIGHT, door_uid_by_tile)
	var has_up := _is_door_or_wall_at_tile(tile_pos + Vector2i.UP, door_uid_by_tile)
	var has_down := _is_door_or_wall_at_tile(tile_pos + Vector2i.DOWN, door_uid_by_tile)

	var horizontal_enclosed := has_left and has_right
	var vertical_enclosed := has_up and has_down

	if vertical_enclosed and not horizontal_enclosed:
		return true
	if horizontal_enclosed and not vertical_enclosed:
		return false
	if vertical_enclosed and horizontal_enclosed:
		var horizontal_wall_score := int(_is_wall_at_tile(tile_pos + Vector2i.LEFT)) + int(_is_wall_at_tile(tile_pos + Vector2i.RIGHT))
		var vertical_wall_score := int(_is_wall_at_tile(tile_pos + Vector2i.UP)) + int(_is_wall_at_tile(tile_pos + Vector2i.DOWN))
		if vertical_wall_score > horizontal_wall_score:
			return true
		if horizontal_wall_score > vertical_wall_score:
			return false
		return false

	var has_horizontal_support := has_left or has_right
	var has_vertical_support := has_up or has_down
	if has_vertical_support and not has_horizontal_support:
		return true
	if has_horizontal_support and not has_vertical_support:
		return false
	return false


func _is_door_or_wall_at_tile(tile_pos: Vector2i, door_uid_by_tile: Dictionary) -> bool:
	if _is_wall_at_tile(tile_pos):
		return true
	return door_uid_by_tile.has(_tile_pos_to_key(tile_pos))


func _is_wall_at_tile(tile_pos: Vector2i) -> bool:
	var world := _find_world_node()
	if world == null:
		return false
	var walls_tm := world.get_node_or_null("StructureWallsMap") as TileMap
	if walls_tm == null:
		return false
	return walls_tm.get_cell_source_id(0, tile_pos) != -1


func _tile_pos_to_key(tile_pos: Vector2i) -> String:
	return "%d,%d" % [tile_pos.x, tile_pos.y]


func _tile_key_to_pos(tile_key: String) -> Vector2i:
	var parts := tile_key.split(",")
	if parts.size() != 2:
		return Vector2i(-999999, -999999)
	return Vector2i(int(parts[0]), int(parts[1]))

func _find_placed_entity_entry_by_uid(uid: String) -> Dictionary:
	if uid == "":
		return {}
	for raw_entry in WorldSave.placed_entities:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		if String(entry.get("uid", "")) == uid:
			return entry.duplicate(true)
	return {}

func _refresh_wall_collision_around_tiles(world_node: Node, center_tiles: Array[Vector2i], radius: int = 1) -> void:
	if center_tiles.is_empty():
		return
	var world := world_node
	if world == null:
		world = _find_world_node()
	if world == null:
		return
	if not world.has_method("refresh_wall_collision_for_tiles"):
		return
	var neighborhood_tiles: Array[Vector2i] = _collect_tile_neighborhood(center_tiles, radius)
	if neighborhood_tiles.is_empty():
		return
	world.call("refresh_wall_collision_for_tiles", neighborhood_tiles)

func _collect_tile_neighborhood(center_tiles: Array[Vector2i], radius: int = 1) -> Array[Vector2i]:
	var unique_tiles: Dictionary = {}
	var clamped_radius: int = maxi(0, radius)
	for center in center_tiles:
		for oy in range(-clamped_radius, clamped_radius + 1):
			for ox in range(-clamped_radius, clamped_radius + 1):
				unique_tiles[center + Vector2i(ox, oy)] = true
	var out: Array[Vector2i] = []
	for raw_tile in unique_tiles.keys():
		if raw_tile is Vector2i:
			out.append(raw_tile as Vector2i)
	return out


func _set_door_mirrored_state(uid: String, mirrored: bool) -> void:
	if uid == "":
		return
	var persisted := WorldSave.get_placed_entity_data(uid)
	persisted["is_mirrored"] = mirrored
	WorldSave.set_placed_entity_data(uid, persisted)
	var door := _find_live_door_by_uid(uid)
	if door == null:
		return
	if door.has_method("set_mirrored"):
		door.call("set_mirrored", mirrored, false)
	elif "is_mirrored" in door:
		door.is_mirrored = mirrored


func _set_door_vertical_layout_state(uid: String, is_vertical: bool) -> void:
	if uid == "":
		return
	var persisted := WorldSave.get_placed_entity_data(uid)
	persisted["is_vertical_layout"] = is_vertical
	WorldSave.set_placed_entity_data(uid, persisted)
	var door := _find_live_door_by_uid(uid)
	if door == null:
		return
	if door.has_method("set_vertical_layout"):
		door.call("set_vertical_layout", is_vertical, false)
	elif "is_vertical_layout" in door:
		door.is_vertical_layout = is_vertical


func _find_live_door_by_uid(uid: String) -> Node:
	if uid == "":
		return null
	for candidate in get_tree().get_nodes_in_group("doorwood_placeable"):
		if not (candidate is Node):
			continue
		var node := candidate as Node
		if not is_instance_valid(node):
			continue
		if "placed_uid" in node and String(node.placed_uid) == uid:
			return node
	return null


func _cleanup() -> void:
	_active   = false
	_item_id  = ""
	_scene_path = ""
	_placement_mode = ""
	_can_place  = false
	_last_hover_tile = Vector2i.ZERO
	_has_last_hover_tile = false
	_stop_drag_paint()
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost        = null
	_ghost_sprite = null
	_release_combat_block()

func _exit_tree() -> void:
	_release_combat_block()


func _stop_drag_paint() -> void:
	_flush_drag_paint_wall_collision()
	_drag_painting = false
	_drag_last_tile = Vector2i.ZERO
	_has_drag_last_tile = false


func _flush_drag_paint_wall_collision() -> void:
	if _drag_painted_wall_tiles.is_empty():
		return
	var painted_tiles: Array[Vector2i] = []
	for raw_tile in _drag_painted_wall_tiles.keys():
		if raw_tile is Vector2i:
			painted_tiles.append(raw_tile as Vector2i)
	_drag_painted_wall_tiles.clear()
	if painted_tiles.is_empty():
		return
	# Rebuild final al terminar trazo para evitar estados intermedios
	# donde un segmento queda desincronizado hasta recargar.
	_refresh_wall_collision_around_tiles(_find_world_node(), painted_tiles, 2)


func _find_world_node() -> Node2D:
	if _world_cache != null and is_instance_valid(_world_cache):
		return _world_cache
	var nodes := get_tree().get_nodes_in_group("world")
	if nodes.size() > 0 and nodes[0] is Node2D:
		_world_cache = nodes[0] as Node2D
		return _world_cache
	return null


func _get_player_inventory() -> InventoryComponent:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0].get_node_or_null("InventoryComponent") as InventoryComponent


func _get_space_state() -> PhysicsDirectSpaceState2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var world2d: World2D = scene.get_world_2d()
	if world2d == null:
		return null
	return world2d.direct_space_state


func _get_scene_path(item_id: String) -> String:
	return PlacementCatalog.resolve_scene_path(item_id)

func _is_tile_wall_item(item_id: String) -> bool:
	return PlacementCatalog.is_tile_wall_item(item_id)


func _is_repeat_scene_item(item_id: String) -> bool:
	return PlacementCatalog.is_repeat_scene_item(item_id)


func _can_share_tile_with_existing(existing_item_id: String) -> bool:
	var placing_item_id := _item_id
	if placing_item_id == "" or existing_item_id == "":
		return false
	return PlacementCatalog.can_share_tile(placing_item_id, existing_item_id)


func _is_physics_hit_blocking_for_item(collider: Variant) -> bool:
	if PlacementCatalog.should_ignore_collision_for_item(_item_id, collider):
		return false
	return true


func _resolve_placement_hover_volume_db() -> float:
	var panel := _resolve_sound_panel()
	if panel != null:
		return panel.placement_hover_volume_db
	return DEFAULT_PLACEMENT_HOVER_VOLUME_DB


func _resolve_door_place_sfx() -> AudioStream:
	var panel := _resolve_sound_panel()
	if panel != null and panel.door_place_sfx != null:
		return panel.door_place_sfx
	return DOOR_PLACE_SFX


func _resolve_door_place_volume_db() -> float:
	var panel := _resolve_sound_panel()
	if panel != null:
		return panel.door_place_volume_db
	return DEFAULT_DOOR_PLACE_VOLUME_DB


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null

func _acquire_combat_block() -> void:
	if _combat_block_pushed:
		return
	UiManager.push_combat_block()
	_combat_block_pushed = true

func _release_combat_block() -> void:
	if not _combat_block_pushed:
		return
	UiManager.pop_combat_block()
	_combat_block_pushed = false
