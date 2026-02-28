extends CanvasLayer
class_name PlayerInventoryMenu

@onready var panel: InventoryPanel = $Root/InventoryPanel

func _ready() -> void:
	visible = false

func toggle() -> void:
	visible = not visible
	print("[MENU] toggle visible=", visible)
	var cursor2d := get_tree().current_scene.get_node_or_null("Cursor2D")
	if visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if cursor2d != null:
			cursor2d.visible = false
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if cursor2d != null:
			cursor2d.visible = true
	print("[MOUSE] after toggle mode=", Input.get_mouse_mode(), " cursor2d_visible=", cursor2d.visible if cursor2d != null else "<missing>")
	print("[UI][PlayerInventoryMenu] visible=", visible, " mode=", Input.get_mouse_mode(), " cursor2d_exists=", cursor2d != null, " cursor2d_visible=", cursor2d.visible if cursor2d != null else "<missing>")

func _on_root_gui_input(ev: InputEvent) -> void:
	print("[UI][Root] ", ev)

func _on_texture_rect_gui_input(ev: InputEvent) -> void:
	print("[UI][BG] ", ev)

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

	panel.set_inventory(inv)
