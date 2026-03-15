extends StaticBody2D
class_name WorkbenchWorld

@onready var area: Area2D            = $Area2D
@onready var interact_icon: Sprite2D = $Sprite2D2

var _player_inside: bool = false


func _ready() -> void:
	add_to_group("workbench")
	add_to_group("interactable")
	interact_icon.visible = false

	# StaticBody2D en capa de props de pared
	collision_layer = CollisionLayers.WORLD_WALL_LAYER_MASK
	collision_mask  = 0

	# Area2D debe monitorear la capa del player (layer 1 = valor 1)
	# Sin esto body_entered/body_exited nunca disparan
	area.collision_layer = 0
	area.collision_mask  = 1

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


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
