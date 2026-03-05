extends CanvasLayer
class_name PlayerInventoryMenu

@onready var panel: InventoryPanel = $Root/InventoryPanel

var _inv: InventoryComponent = null

func _ready() -> void:
	visible = false

func toggle() -> void:
	var next_visible := not visible
	if not next_visible and panel != null:
		panel.cancel_drag()

	visible = next_visible
	print("[MENU] toggle visible=", visible)

	if visible:
		_close_keeper_menu_if_open()
		UiManager.open_ui("inventory")
		UiManager.push_combat_block()
		call_deferred("_bind_player_inventory")
	else:
		UiManager.close_ui("inventory")
		UiManager.pop_combat_block()


func _close_keeper_menu_if_open() -> void:
	var keeper_menu := _get_keeper_menu_ui()
	if keeper_menu != null and keeper_menu.is_shop_open():
		keeper_menu.close_shop()


func _get_keeper_menu_ui() -> KeeperMenuUi:
	var scene := get_tree().current_scene
	if scene != null:
		var by_path := scene.get_node_or_null("UI/KeeperMenuUi") as KeeperMenuUi
		if by_path != null:
			return by_path
	for node in get_tree().get_nodes_in_group("keeper_menu_ui"):
		if node is KeeperMenuUi:
			return node as KeeperMenuUi
	return null

func _on_root_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mouse_ev := ev as InputEventMouseButton
		if mouse_ev.pressed:
			get_viewport().set_input_as_handled()

func _on_texture_rect_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mouse_ev := ev as InputEventMouseButton
		if mouse_ev.pressed:
			get_viewport().set_input_as_handled()

func _bind_player_inventory() -> void:
	var player := get_tree().current_scene.get_node_or_null("Player")
	if player == null:
		var arr := get_tree().get_nodes_in_group("player")
		if arr.size() > 0:
			player = arr[0]

	if player == null:
		return

	var inv := player.get_node_or_null("InventoryComponent") as InventoryComponent
	if inv == null:
		return

	_inv = inv
	panel.set_inventory(inv)
