extends CanvasLayer
class_name KeeperMenuUi

@onready var player_panel: InventoryPanel = $Root/Panel/ContentArea/Layout/Playerbox/PlayerInventoryPanel
@onready var keeper_panel: InventoryPanel = $Root/Panel/ContentArea/Layout/KeeperBox/KeeperInventoryPanel

var _player_inv: InventoryComponent = null
var _keeper_inv: InventoryComponent = null


func _ready() -> void:
	visible = false
	player_panel.slot_clicked.connect(_on_player_slot_clicked)
	keeper_panel.slot_clicked.connect(_on_keeper_slot_clicked)


func toggle() -> void:
	visible = not visible
	print("[MENU] toggle visible=", visible)
	var cursor2d := get_tree().current_scene.get_node_or_null("Cursor2D")
	if visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if cursor2d != null:
			cursor2d.visible = false
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		if cursor2d != null:
			cursor2d.visible = true
	print("[MOUSE] after toggle mode=", Input.get_mouse_mode(), " cursor2d_visible=", cursor2d.visible if cursor2d != null else "<missing>")


func set_player_inventory(inv: InventoryComponent) -> void:
	_player_inv = inv
	player_panel.set_inventory(inv)


func set_keeper_inventory(inv: InventoryComponent) -> void:
	_keeper_inv = inv
	keeper_panel.set_inventory(inv)


func _refresh_binds() -> void:
	if _player_inv != null:
		player_panel.set_inventory(_player_inv)
	if _keeper_inv != null:
		keeper_panel.set_inventory(_keeper_inv)


func _on_player_slot_clicked(slot_index: int, _button: int) -> void:
	_transfer_one(_player_inv, _keeper_inv, slot_index)


func _on_keeper_slot_clicked(slot_index: int, _button: int) -> void:
	_transfer_one(_keeper_inv, _player_inv, slot_index)


func _transfer_one(from_inv: InventoryComponent, to_inv: InventoryComponent, slot_index: int) -> void:
	if from_inv == null or to_inv == null:
		return
	if slot_index < 0 or slot_index >= from_inv.max_slots:
		return

	var data = from_inv.slots[slot_index]
	if data == null:
		return

	var item_id := String(data.get("id", ""))
	if item_id == "":
		return

	if not from_inv.has_method("remove_item"):
		print("[KeeperMenuUi] InventoryComponent no tiene remove_item(item_id, amount).")
		return
	if not to_inv.has_method("add_item"):
		print("[KeeperMenuUi] InventoryComponent no tiene add_item(item_id, amount).")
		return

	var removed: int = from_inv.remove_item(item_id, 1)
	if removed <= 0:
		return

	var added: int = to_inv.add_item(item_id, 1)
	if added <= 0:
		# rollback por seguridad si destino no pudo recibir
		from_inv.add_item(item_id, removed)
