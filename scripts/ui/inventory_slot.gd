extends Control
class_name InventorySlot

signal slot_clicked(slot_index: int, button: int)
signal drag_started(slot_index: int, mouse_position: Vector2)
signal drag_finished(slot_index: int, mouse_position: Vector2)

@export var slot_index: int = -1
const DRAG_THRESHOLD := 8.0

@onready var icon: TextureRect = $Icon
@onready var count: Label = $Count
@onready var _icon_node: CanvasItem = $Icon as CanvasItem

var pressed: bool = false
var dragging: bool = false
var press_pos: Vector2 = Vector2.ZERO
var _inventory_component: InventoryComponent = null
var _inventory_ui: Node = null

func _ready() -> void:
	set_empty()

func set_empty() -> void:
	icon.texture = null
	icon.visible = false
	set_blocked(false)
	count.text = ""
	count.visible = false

func set_item(amount: int, tex: Texture2D) -> void:
	icon.texture = tex
	icon.visible = tex != null
	if tex == null:
		set_blocked(false)

	count.text = str(amount)
	count.visible = amount > 1

func set_blocked(is_blocked: bool) -> void:
	if _icon_node == null:
		return
	if is_blocked:
		_icon_node.modulate = Color(1.0, 0.7, 0.7, 1.0)
	else:
		_icon_node.modulate = Color(1, 1, 1, 1)


func bind_inventory_component(inv: InventoryComponent) -> void:
	_inventory_component = inv


func bind_inventory_ui(inventory_ui: Node) -> void:
	_inventory_ui = inventory_ui


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pressed = true
			dragging = false
			press_pos = event.position
		else:
			if pressed:
				pressed = false
				if dragging:
					_finish_drag()
				else:
					_click_use()
				accept_event()
	elif event is InputEventMouseMotion:
		if pressed and not dragging:
			if press_pos.distance_to(event.position) >= DRAG_THRESHOLD:
				if _can_drag_current_slot():
					dragging = true
					_start_drag()
					accept_event()


func _click_use() -> void:
	if slot_index < 0:
		return
	var inv := _find_inventory_component()
	if inv != null:
		inv.request_use_item.emit(slot_index)
		return
	slot_clicked.emit(slot_index, MOUSE_BUTTON_LEFT)


func _start_drag() -> void:
	if slot_index < 0 or not _can_drag_current_slot():
		return
	var mouse_position := get_global_mouse_position()
	var menu := _find_inventory_menu()
	if menu != null and menu.has_method("begin_drag"):
		menu.begin_drag(slot_index, mouse_position)
	drag_started.emit(slot_index, mouse_position)


func _finish_drag() -> void:
	if slot_index < 0 or not _can_drag_current_slot():
		return
	var mouse_position := get_global_mouse_position()
	var menu := _find_inventory_menu()
	if menu != null and menu.has_method("end_drag"):
		menu.end_drag(slot_index, mouse_position)
	drag_finished.emit(slot_index, mouse_position)


func _find_inventory_component() -> InventoryComponent:
	if _inventory_component != null and not is_instance_valid(_inventory_component):
		_inventory_component = null
	if _inventory_component != null:
		return _inventory_component
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0].get_node_or_null("InventoryComponent") as InventoryComponent
	return null


func _find_inventory_menu() -> Node:
	if _inventory_ui != null and not is_instance_valid(_inventory_ui):
		_inventory_ui = null
	if _inventory_ui != null:
		return _inventory_ui
	var nodes := get_tree().get_nodes_in_group("inventory_ui")
	if nodes.size() > 0:
		return nodes[0]
	return null


func _can_drag_current_slot() -> bool:
	if slot_index < 0:
		return false

	var menu := _find_inventory_menu()
	if menu != null and menu.has_method("can_drag_slot"):
		return bool(menu.call("can_drag_slot", slot_index))

	var inv := _find_inventory_component()
	if inv == null:
		return false
	if slot_index >= inv.max_slots:
		return false

	var data = inv.slots[slot_index]
	if data == null:
		return false

	var item_id := String(data.get("id", ""))
	var amount := int(data.get("count", 0))
	return item_id != "" and amount > 0
