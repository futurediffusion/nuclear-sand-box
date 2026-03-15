extends Node

## Autoload: PlacementSystem
## Gestiona el modo de colocación de objetos placeables en mundo.
## Para agregar un nuevo placeable: registrar item_id → scene_path en PLACEABLE_SCENES.

signal placement_completed(item_id: String, tile_pos: Vector2i)
signal placement_cancelled(item_id: String)

const TILE_SIZE: int = 32
const GHOST_SCENE: PackedScene = preload("res://scenes/placement_ghost.tscn")

## Registry: item_id -> scene_path del objeto a instanciar en mundo.
const PLACEABLE_SCENES: Dictionary = {
	"workbench": "res://scenes/placeables/workbench_world.tscn",
	"chest": "res://scenes/placeables/chest_world.tscn",
	"barrel": "res://scenes/placeables/barrel_world.tscn",
}

var _active:       bool   = false
var _item_id:      String = ""
var _scene_path:   String = ""
var _can_place:    bool   = false
var _ghost:        Node2D = null
var _ghost_sprite: Sprite2D = null
var _world_cache:  Node2D = null
var _check_shape:  RectangleShape2D = null  # cached — reutilizado cada frame

# Máscara de capas que bloquean colocación: WALLPROPS(16) + Resources(8) + Player(1)
const BLOCK_MASK: int = CollisionLayers.WORLD_WALL_LAYER_MASK \
					  | CollisionLayers.RESOURCES_LAYER_MASK \
					  | 1


# ── API pública ───────────────────────────────────────────────────────────────

func begin_placement(item_id: String, icon: Texture2D = null) -> void:
	if _active:
		cancel_placement()
	var scene_path := _get_scene_path(item_id)
	if scene_path == "":
		push_warning("[PlacementSystem] No hay escena registrada para item_id='%s'" % item_id)
		return
	_active     = true
	_item_id    = item_id
	_scene_path = scene_path
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
		var hits := space_state.intersect_shape(params, 1)
		if hits.size() > 0:
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
	_ghost.position = Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)
	_can_place      = can_place_at(tile)
	if _ghost_sprite != null:
		_ghost_sprite.modulate = Color(0.5, 1.0, 0.5, 0.7) if _can_place else Color(1.0, 0.35, 0.35, 0.5)


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
		return

	# UID simple basado en tiempo + item_id
	var uid := "%s_%d" % [_item_id, Time.get_ticks_msec()]

	var entry: Dictionary = {
		"uid":       uid,
		"scene":     _scene_path,
		"tile_pos_x": tile.x,
		"tile_pos_y": tile.y,
		"tier":      1,
		"item_id":   _item_id,
	}
	WorldSave.add_placed_entity(entry)

	var world := _find_world_node()
	var parent: Node = world if world != null else get_tree().current_scene
	_spawn_placed_instance(entry, parent)

	var placed_id := _item_id
	_cleanup()
	placement_completed.emit(placed_id, tile)


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
	_can_place  = false
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost        = null
	_ghost_sprite = null


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
	return String(PLACEABLE_SCENES.get(item_id, ""))
