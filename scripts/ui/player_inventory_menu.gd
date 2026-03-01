extends CanvasLayer
class_name PlayerInventoryMenu

@onready var panel: InventoryPanel = $Root/InventoryPanel

var _inv: InventoryComponent = null

func _ready() -> void:
	visible = false
	if panel != null and not panel.slot_clicked.is_connected(_on_slot_clicked):
		panel.slot_clicked.connect(_on_slot_clicked)

func toggle() -> void:
	visible = not visible
	print("[MENU] toggle visible=", visible)

	if visible:
		UiManager.open_ui("inventory")
		call_deferred("_bind_player_inventory")
	else:
		UiManager.close_ui("inventory")

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

func _on_slot_clicked(slot_index: int, _button: int) -> void:
	if _inv == null:
		return
	_inv.request_use_item.emit(slot_index)
