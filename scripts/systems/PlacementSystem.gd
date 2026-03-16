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
	for entry in WorldSave.placed_entities:
		_spawn_placed_instance(entry, world_node)


## Quitar una entidad colocada por UID (por ejemplo, si la destruyen).
func remove_placed_entity(uid: String) -> void:
	WorldSave.remove_placed_entity(uid)


# ── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			UiManager.block_combat_for(PLACEMENT_CLICK_COMBAT_BLOCK_MS)
			if _can_place:
				_do_place()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
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
	if _ghost_sprite != null and icon != null:
		_ghost_sprite.texture = icon
	var world := _find_world_node()
	var parent: Node = world if world != null else get_tree().current_scene
	parent.add_child(_ghost)
	_update_ghost()


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
		_play_tile_wall_place_sfx(tile)
		placement_completed.emit(_item_id, tile)
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


func _cleanup() -> void:
	_active   = false
	_item_id  = ""
	_scene_path = ""
	_placement_mode = ""
	_can_place  = false
	_last_hover_tile = Vector2i.ZERO
	_has_last_hover_tile = false
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost        = null
	_ghost_sprite = null
	_release_combat_block()

func _exit_tree() -> void:
	_release_combat_block()


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
	if not PlacementCatalog.is_floorwood_item(_item_id):
		return true
	if collider is Node:
		var node := collider as Node
		if node.is_in_group("doorwood_placeable"):
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
