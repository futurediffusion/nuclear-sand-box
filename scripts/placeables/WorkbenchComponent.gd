extends StaticBody2D
class_name WorkbenchWorld

const MAX_HITS: int = 4
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")

# Shake params — same feel as stone_ore
const SHAKE_DURATION: float = 0.08
const SHAKE_PX: float       = 6.0
const SHAKE_SPEED: float    = 40.0
const HIT_FLASH_TIME: float = 0.06

@onready var area: Area2D            = $Area2D
@onready var sprite: Sprite2D        = $Sprite2D
@onready var interact_icon: Sprite2D = $Sprite2D2

var _player_inside: bool  = false
var _hit_count: int       = 0
var _shake_t: float       = 0.0
var _flash_t: float       = 0.0
var _base_sprite_pos: Vector2

## UID asignado cuando se coloca via PlacementSystem (para WorldSave).
var placed_uid: String = ""


func _ready() -> void:
	add_to_group("workbench")
	add_to_group("interactable")
	interact_icon.visible = false
	_base_sprite_pos = sprite.position

	# StaticBody2D en WALLPROPS + Resources: igual que árboles/piedras,
	# para que shape_overlaps_wall lo trate como destructible y no bloquee el slash.
	collision_layer = CollisionLayers.WORLD_WALL_LAYER_MASK | CollisionLayers.RESOURCES_LAYER_MASK
	collision_mask  = 0

	# Area2D: layer Resources (8) para que el hitbox del slash lo detecte,
	# mask Player (1) para body_entered/body_exited del jugador.
	area.collision_layer = CollisionLayers.RESOURCES_LAYER_MASK
	area.collision_mask  = 1

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	# Shake
	if _shake_t > 0.0:
		_shake_t -= delta
		var off: float = sin((SHAKE_DURATION - _shake_t) * SHAKE_SPEED) * SHAKE_PX
		sprite.position = _base_sprite_pos + Vector2(off, 0.0)
		if _shake_t <= 0.0:
			sprite.position = _base_sprite_pos

	# Flash reset
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			sprite.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if not _player_inside:
		return
	if UiManager.is_interact_blocked():
		return
	if not event.is_action_pressed("interact"):
		return

	var menu := _get_workbench_menu()
	if menu == null:
		return

	if menu.is_open():
		menu.close_menu()
	else:
		menu.open_menu()

	UiManager.block_interact_for(150)
	get_viewport().set_input_as_handled()


## Llamado por slash.gd cuando el hitbox golpea esta Area2D.
func hit(_by: Node) -> void:
	_hit_count += 1
	_play_hit_feedback()
	if _hit_count >= MAX_HITS:
		_destroy()


func _play_hit_feedback() -> void:
	_shake_t = SHAKE_DURATION
	_flash_t = HIT_FLASH_TIME
	sprite.modulate = Color(0.8, 0.8, 0.8, 1.0)


func _destroy() -> void:
	# Cerrar menú si está abierto
	var menu := _get_workbench_menu()
	if menu != null and menu.is_open():
		menu.close_menu()

	# Dropear el item workbench en la posición del nodo
	var world_node := get_parent()
	if world_node == null:
		world_node = get_tree().current_scene

	var overrides := {"drop_scene": ITEM_DROP_SCENE}
	var drop_item_id := BuildableCatalog.resolve_drop_item_id("", BuildableCatalog.ID_WORKBENCH)
	var spawned := LootSystem.spawn_drop(null, drop_item_id, 1, global_position, world_node, overrides)

	if OS.is_debug_build():
		Debug.log("workbench", "destroy uid=%s parent_ok=%s drop_spawned=%s" % [placed_uid, str(world_node != null), str(spawned != null)])

	# Remover del registro de placed_entities
	if placed_uid != "":
		PlacementSystem.remove_placed_entity(placed_uid)

	queue_free()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	interact_icon.visible = true


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false
	interact_icon.visible = false
	var menu := _get_workbench_menu()
	if menu != null and menu.is_open():
		menu.close_menu()


func _get_workbench_menu() -> WorkbenchMenuUi:
	var scene := get_tree().current_scene
	if scene != null:
		var by_path := scene.get_node_or_null("UI/WorkbenchMenuUi") as WorkbenchMenuUi
		if by_path != null:
			return by_path
	for node in get_tree().get_nodes_in_group("workbench_menu_ui"):
		if node is WorkbenchMenuUi:
			return node as WorkbenchMenuUi
	return null
