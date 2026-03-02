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
var press_button_index: int = MOUSE_BUTTON_LEFT
var press_shift: bool = false
var _inventory_component: InventoryComponent = null
var _inventory_ui: Node = null
var _feedback_label: Label = null
var _feedback_tween: Tween = null

func _ready() -> void:
	set_empty()
	_ensure_feedback_label()

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
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.pressed:
			pressed = true
			dragging = false
			press_pos = event.position
			press_button_index = event.button_index
			press_shift = event.shift_pressed
		else:
			if pressed:
				pressed = false
				if dragging:
					_finish_drag()
				elif press_button_index == MOUSE_BUTTON_LEFT:
					_click_action()
				accept_event()
	elif event is InputEventMouseMotion:
		if pressed and not dragging:
			if press_pos.distance_to(event.position) >= DRAG_THRESHOLD:
				if _can_drag_current_slot():
					dragging = true
					_start_drag()
					accept_event()


func _click_action() -> void:
	if slot_index < 0:
		return
	if _inventory_ui != null and is_instance_valid(_inventory_ui) and _inventory_ui.has_method("on_slot_primary_action"):
		var handled := bool(_inventory_ui.call("on_slot_primary_action", slot_index))
		if not handled and _inventory_ui.has_method("should_show_not_usable_feedback"):
			var show_feedback := bool(_inventory_ui.call("should_show_not_usable_feedback", slot_index))
			if show_feedback:
				_show_not_usable_feedback(_find_inventory_component())
		return
	slot_clicked.emit(slot_index, MOUSE_BUTTON_LEFT)


func _show_not_usable_feedback(inv: InventoryComponent) -> void:
	if inv == null:
		return
	if slot_index < 0 or slot_index >= inv.max_slots:
		return

	var stack = inv.slots[slot_index]
	if stack == null:
		return

	var item_id := String(stack.get("id", ""))
	var amount := int(stack.get("count", 0))
	if item_id == "" or amount <= 0:
		return

	var feedback_text := "No usable"
	if _is_heal_item_at_full_hp(item_id, inv):
		feedback_text = "Full HP"

	_ensure_feedback_label()
	if _feedback_label == null:
		return

	_feedback_label.text = feedback_text
	_feedback_label.modulate = Color(1.0, 0.9, 0.7, 1.0)
	_feedback_label.position = Vector2((size.x - _feedback_label.size.x) * 0.5, -16.0)
	_feedback_label.visible = true

	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()

	_feedback_tween = create_tween()
	_feedback_tween.set_parallel(true)
	_feedback_tween.tween_property(_feedback_label, "position:y", -24.0, 0.45)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.45)
	_feedback_tween.set_parallel(false)
	_feedback_tween.tween_callback(func() -> void:
		if _feedback_label == null:
			return
		_feedback_label.visible = false
		_feedback_label.modulate = Color(1.0, 0.9, 0.7, 1.0)
	)


func _is_heal_item_at_full_hp(item_id: String, inv: InventoryComponent) -> bool:
	if item_id == "" or inv == null:
		return false

	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return false

	var item_data: ItemData = item_db.get_item(item_id)
	if item_data == null or not item_data.consumable or item_data.heal_hp <= 0:
		return false

	var owner_node := inv.get_parent()
	if owner_node == null:
		return false

	var health := owner_node.get_node_or_null("HealthComponent")
	if health == null:
		return false

	return int(health.hp) >= int(health.max_hp)


func _ensure_feedback_label() -> void:
	if _feedback_label != null and is_instance_valid(_feedback_label):
		return
	_feedback_label = Label.new()
	_feedback_label.text = ""
	_feedback_label.visible = false
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_font_size_override("font_size", 11)
	_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7, 1.0))
	_feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback_label.position = Vector2(0, -16)
	_feedback_label.size = Vector2(size.x, 16)
	add_child(_feedback_label)


func _start_drag() -> void:
	if slot_index < 0 or not _can_drag_current_slot():
		return
	var mouse_position := get_global_mouse_position()
	var menu := _find_inventory_menu()
	if menu != null and menu.has_method("begin_drag"):
		menu.begin_drag(slot_index, mouse_position, press_button_index, press_shift)
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
