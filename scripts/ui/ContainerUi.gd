extends CanvasLayer
class_name ContainerUi

const UI_REASON_CHEST_COMPAT: String = "chest"

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/inventory_slot.tscn")
const DEFAULT_CHEST_OPEN_SFX: AudioStream = preload("res://art/Sounds/chestopen.ogg")
const DEFAULT_CHEST_CLOSE_SFX: AudioStream = preload("res://art/Sounds/chestclose.ogg")
const DEFAULT_INVENTORY_ITEM_SELECT_SFX: AudioStream = preload("res://art/Sounds/inventoryitemgrab.ogg")
const DEFAULT_SHIFT_TRANSFER_SFX: AudioStream = preload("res://art/Sounds/inventoryshifttransfer.ogg")
const DEFAULT_UI_SLOT_PLACE_SFX_POOL: Array[AudioStream] = [
	preload("res://art/Sounds/place1.ogg"),
	preload("res://art/Sounds/place2.ogg"),
	preload("res://art/Sounds/place3.ogg"),
	preload("res://art/Sounds/place4.ogg"),
]
const DEFAULT_CHEST_OPEN_VOLUME_DB: float = 0.0
const DEFAULT_CHEST_CLOSE_VOLUME_DB: float = 0.0
const DEFAULT_INVENTORY_ITEM_SELECT_VOLUME_DB: float = 0.0
const DEFAULT_SHIFT_TRANSFER_VOLUME_DB: float = 0.0
const DEFAULT_UI_SLOT_PLACE_VOLUME_DB: float = 0.0
const TRANSFER_DOWN_SEMITONE_OFFSET: float = -2.0

@export var chest_columns: int = 5
@export var chest_rows: int = 3
@export var tile_size: Vector2 = Vector2(32, 32)
@export var chest_max_slots: int = 15
@export var chest_max_stack: int = 10

@onready var chest_grid: GridContainer = $Root/Chest/Chestgrid
@onready var player_panel: InventoryPanel = $Root/Playerbox/PlayerInventoryPanel

var _container_component: ContainerPlaceable = null
var _player_inv: InventoryComponent = null
var _chest_inv: Dictionary = {}
var _slot_nodes: Array[InventorySlot] = []

var dragging: bool = false
var drag_from_slot: int = -1
var drag_item_id: String = ""
var drag_amount: int = 0
var drag_ghost: Control = null
var drag_offset: Vector2 = Vector2(16, 16)


func _ready() -> void:
	visible = false
	add_to_group("chest_ui")
	add_to_group("container_ui")
	if has_signal("visibility_changed"):
		visibility_changed.connect(_on_visibility_changed)
	if chest_grid == null:
		push_error("[ContainerUi] Missing node Root/Chest/Chestgrid")
		return
	chest_grid.columns = chest_columns
	_rebuild_chest_grid()


func _process(_delta: float) -> void:
	if not dragging:
		return
	if drag_ghost == null or not is_instance_valid(drag_ghost):
		return
	drag_ghost.global_position = get_viewport().get_mouse_position() - drag_offset


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		close_menu()
		UiManager.block_interact_for(150)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if dragging:
			_clear_drag_visual()


func _on_visibility_changed() -> void:
	if not visible and dragging:
		_clear_drag_visual()


func open_for_container(container_component: ContainerPlaceable) -> void:
	if container_component == null:
		return

	if _container_component != null and _container_component != container_component:
		_handoff_current_chest()

	_close_inventory_if_open()
	_container_component = container_component
	_player_inv = _get_player_inventory()
	player_panel.set_inventory(_player_inv)
	player_panel.set_external_drop_handler(Callable(self, "_on_player_panel_drop_outside"))
	player_panel.set_external_quick_transfer_handler(Callable(self, "_on_player_panel_quick_transfer"), true)

	_rebuild_chest_inventory_model()
	_load_chest_slots_from_component()
	_refresh_both_sides()

	visible = true
	UiManager.open_ui(UI_REASON_CHEST_COMPAT)
	UiManager.push_combat_block()
	_play_chest_open_sfx()


func open_menu(container_component: ContainerPlaceable) -> void:
	open_for_container(container_component)

func open_for_chest(chest_component: Node) -> void:
	if chest_component is ContainerPlaceable:
		open_for_container(chest_component as ContainerPlaceable)


func close_menu() -> void:
	var was_visible := visible
	_clear_drag_visual()
	if player_panel != null:
		if player_panel.has_method("cancel_drag"):
			player_panel.cancel_drag()
		player_panel.set_external_drop_handler(Callable())
		player_panel.set_external_quick_transfer_handler(Callable(), false)

	if _container_component != null and _container_component.has_method("on_ui_closed_from_ui_layer"):
		_container_component.on_ui_closed_from_ui_layer()

	_persist_chest_data()
	_container_component = null
	if was_visible:
		visible = false
		UiManager.close_ui(UI_REASON_CHEST_COMPAT)
		UiManager.pop_combat_block()
		_play_chest_close_sfx()


func _handoff_current_chest() -> void:
	if _container_component == null:
		return
	_clear_drag_visual()
	if player_panel != null:
		if player_panel.has_method("cancel_drag"):
			player_panel.cancel_drag()
		player_panel.set_external_drop_handler(Callable())
		player_panel.set_external_quick_transfer_handler(Callable(), false)
	_persist_chest_data()
	if _container_component.has_method("on_ui_closed_from_ui_layer"):
		_container_component.on_ui_closed_from_ui_layer()

func is_open() -> bool:
	return visible


func can_drag_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= int(_chest_inv.get("max_slots", 0)):
		return false
	var data = _chest_get_slot(slot_index)
	if data == null:
		return false
	var item_id := String(data.get("id", ""))
	var amount := int(data.get("count", 0))
	return item_id != "" and amount > 0


func on_slot_primary_action(slot_index: int, _shift_pressed: bool = false) -> bool:
	if slot_index < 0 or slot_index >= int(_chest_inv.get("max_slots", 0)):
		return false
	if _player_inv == null:
		return false

	var moved_any := false
	while true:
		var source_stack = _normalize_slot(_chest_get_slot(slot_index))
		var remaining := _slot_count(source_stack)
		if remaining <= 0:
			break
		var source_item_id := _slot_id(source_stack)
		if source_item_id == "":
			break
		var moved_this_pass := false
		for i in range(_player_inv.max_slots):
			if not _can_auto_transfer_to_inventory_slot(source_item_id, i):
				continue
			if _transfer_chest_to_player_slot(slot_index, i, remaining):
				moved_this_pass = true
				moved_any = true
				break
		if not moved_this_pass:
			break

	if moved_any:
		_play_shift_transfer_down_sfx()
	return true


func should_show_not_usable_feedback(_slot_index: int) -> bool:
	return false


func begin_drag(slot_index: int, mouse_position: Vector2, button_index: int, shift: bool) -> void:
	if not can_drag_slot(slot_index):
		return

	var stack = _chest_get_slot(slot_index)
	var item_id := String(stack.get("id", ""))
	var count := int(stack.get("count", 0))
	if item_id == "" or count <= 0:
		return

	var amount := count
	if button_index == MOUSE_BUTTON_RIGHT:
		if shift:
			amount = max(1, int(floor(count / 2.0)))
		else:
			amount = 1

	var icon := _get_item_icon(item_id)
	_clear_drag_visual()

	var ghost := Control.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 1000
	ghost.size = tile_size

	var ghost_icon := TextureRect.new()
	ghost_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_icon.texture = icon
	ghost_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost_icon.custom_minimum_size = tile_size
	ghost_icon.size = tile_size
	ghost.add_child(ghost_icon)

	if amount > 1:
		var ghost_count := Label.new()
		ghost_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost_count.text = str(amount)
		ghost_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ghost_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		ghost_count.size = tile_size
		ghost.add_child(ghost_count)

	add_child(ghost)
	drag_ghost = ghost
	dragging = true
	drag_from_slot = slot_index
	drag_item_id = item_id
	drag_amount = amount
	drag_ghost.global_position = mouse_position - drag_offset
	_play_inventory_item_select_sfx()


func end_drag(_slot_index: int, _mouse_position: Vector2) -> void:
	if not dragging or drag_from_slot < 0:
		_clear_drag_visual()
		return

	var mouse := get_viewport().get_mouse_position()
	var chest_target := _get_chest_slot_at_global_pos(mouse)
	if chest_target != -1:
		_move_inside_chest(drag_from_slot, chest_target, drag_amount)
		_play_slot_place_sfx()
		_clear_drag_visual()
		return

	var player_target := _get_player_slot_at_global_pos(mouse)
	if player_target != -1:
		_transfer_chest_to_player_slot(drag_from_slot, player_target, drag_amount)
		_play_slot_place_sfx()

	_clear_drag_visual()


func _rebuild_chest_grid() -> void:
	for child in chest_grid.get_children():
		child.queue_free()
	_slot_nodes.clear()

	var total := chest_columns * chest_rows
	for i in range(total):
		var slot := SLOT_SCENE.instantiate() as InventorySlot
		if slot == null:
			continue
		slot.slot_index = i
		slot.custom_minimum_size = tile_size
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.bind_inventory_ui(self)
		if not slot.slot_clicked.is_connected(_on_chest_slot_clicked):
			slot.slot_clicked.connect(_on_chest_slot_clicked)
		chest_grid.add_child(slot)
		_slot_nodes.append(slot)


func _rebuild_chest_inventory_model() -> void:
	var computed_slots := _resolve_container_max_slots()
	var resolved_max_stack := _resolve_container_max_stack()
	_chest_inv = {
		"max_slots": maxi(1, computed_slots),
		"max_stack": maxi(1, resolved_max_stack),
		"slots": [],
	}
	(_chest_inv["slots"] as Array).resize(int(_chest_inv["max_slots"]))
	for i in range(int(_chest_inv["max_slots"])):
		(_chest_inv["slots"] as Array)[i] = null

func _resolve_container_max_slots() -> int:
	if _container_component != null and _container_component.has_method("get_container_max_slots"):
		return maxi(1, int(_container_component.call("get_container_max_slots")))
	if chest_max_slots > 0:
		return chest_max_slots
	return maxi(1, chest_columns * chest_rows)


func _resolve_container_max_stack() -> int:
	if _container_component != null and _container_component.has_method("get_container_max_stack"):
		return maxi(1, int(_container_component.call("get_container_max_stack")))
	return maxi(1, chest_max_stack)


func _load_chest_slots_from_component() -> void:
	if _container_component == null:
		return

	var source: Array = _container_component.stored_slots
	var slots_array := _chest_inv.get("slots", []) as Array
	for i in range(mini(source.size(), slots_array.size())):
		var normalized: Variant = _normalize_slot(source[i])
		slots_array[i] = normalized
	_chest_inv["slots"] = slots_array


func _persist_chest_data() -> void:
	if _container_component == null:
		return

	var slots_copy := (_chest_inv.get("slots", []) as Array).duplicate(true)
	_container_component.stored_slots = slots_copy
	if _container_component.has_method("sync_persistence_data"):
		_container_component.sync_persistence_data()
	return


func _refresh_both_sides() -> void:
	_refresh_chest_slots()


func _refresh_chest_slots() -> void:
	for i in range(_slot_nodes.size()):
		_refresh_chest_slot(i)


func _refresh_chest_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_nodes.size():
		return
	var slot := _slot_nodes[slot_index]
	var data = _chest_get_slot(slot_index)
	if data == null:
		slot.set_empty()
		return
	var item_id := String(data.get("id", ""))
	var count := int(data.get("count", 0))
	if item_id == "" or count <= 0:
		slot.set_empty()
		return
	slot.set_item(count, _get_item_icon(item_id))


func _move_inside_chest(from_slot: int, to_slot: int, amount: int) -> bool:
	var moved := _move_between_containers(_chest_inv, from_slot, _chest_inv, to_slot, amount)
	if moved:
		_persist_chest_data()
		_refresh_both_sides()
	return moved


func _transfer_chest_to_player_slot(from_slot: int, to_player_slot: int, amount: int) -> bool:
	if _player_inv == null:
		return false
	var player_container := _as_container(_player_inv)
	var moved := _move_between_containers(_chest_inv, from_slot, player_container, to_player_slot, amount)
	if moved:
		_write_back_inventory_container(_player_inv, player_container)
		_persist_chest_data()
		_refresh_both_sides()
	return moved


func _transfer_player_to_chest_slot(from_player_slot: int, to_chest_slot: int, amount: int) -> bool:
	if _player_inv == null:
		return false
	var player_container := _as_container(_player_inv)
	var moved := _move_between_containers(player_container, from_player_slot, _chest_inv, to_chest_slot, amount)
	if moved:
		_write_back_inventory_container(_player_inv, player_container)
		_persist_chest_data()
		_refresh_both_sides()
	return moved


func _move_between_containers(from_container: Dictionary, from_slot: int, to_container: Dictionary, to_slot: int, amount: int) -> bool:
	if not _is_valid_slot(from_container, from_slot):
		return false
	if not _is_valid_slot(to_container, to_slot):
		return false
	if amount <= 0:
		return false
	if from_container == to_container and from_slot == to_slot:
		return false

	var from_slots := from_container.get("slots", []) as Array
	var to_slots := to_container.get("slots", []) as Array
	var from_stack = _normalize_slot(from_slots[from_slot])
	if from_stack == null:
		return false

	var from_id := _slot_id(from_stack)
	var from_count := _slot_count(from_stack)
	if from_id == "" or from_count <= 0:
		return false

	var requested := mini(amount, from_count)
	var to_stack = _normalize_slot(to_slots[to_slot])

	if to_stack == null:
		to_slots[to_slot] = {"id": from_id, "count": requested}
		from_count -= requested
		if from_count <= 0:
			from_slots[from_slot] = null
		else:
			from_slots[from_slot] = {"id": from_id, "count": from_count}
		from_container["slots"] = from_slots
		to_container["slots"] = to_slots
		return true

	var to_id := _slot_id(to_stack)
	var to_count := _slot_count(to_stack)
	if to_id == "" or to_count <= 0:
		to_slots[to_slot] = {"id": from_id, "count": requested}
		from_count -= requested
		if from_count <= 0:
			from_slots[from_slot] = null
		else:
			from_slots[from_slot] = {"id": from_id, "count": from_count}
		from_container["slots"] = from_slots
		to_container["slots"] = to_slots
		return true

	if to_id == from_id:
		var stack_limit := _get_stack_limit(from_id, to_container)
		var space := stack_limit - to_count
		var moved := mini(space, requested)
		if moved <= 0:
			return false
		to_slots[to_slot] = {"id": to_id, "count": to_count + moved}
		from_count -= moved
		if from_count <= 0:
			from_slots[from_slot] = null
		else:
			from_slots[from_slot] = {"id": from_id, "count": from_count}
		from_container["slots"] = from_slots
		to_container["slots"] = to_slots
		return true

	if requested < from_count:
		return false

	from_slots[from_slot] = {"id": to_id, "count": to_count}
	to_slots[to_slot] = {"id": from_id, "count": from_count}
	from_container["slots"] = from_slots
	to_container["slots"] = to_slots
	return true


func _as_container(inv: InventoryComponent) -> Dictionary:
	return {
		"max_slots": inv.max_slots,
		"max_stack": inv.max_stack,
		"slots": inv.slots.duplicate(true),
	}


func _write_back_inventory_container(inv: InventoryComponent, container: Dictionary) -> void:
	inv.slots = (container.get("slots", []) as Array).duplicate(true)
	inv.inventory_changed.emit()
	for i in range(inv.max_slots):
		inv.slot_changed.emit(i)


func _on_player_panel_drop_outside(from_slot: int, amount: int, mouse_global: Vector2) -> bool:
	var chest_target := _get_chest_slot_at_global_pos(mouse_global)
	if chest_target == -1:
		return false
	return _transfer_player_to_chest_slot(from_slot, chest_target, amount)


func _on_player_panel_quick_transfer(from_player_slot: int) -> bool:
	if _player_inv == null:
		return false
	if from_player_slot < 0 or from_player_slot >= _player_inv.max_slots:
		return false

	var moved_any := false
	while true:
		var source_stack = _normalize_slot(_player_inv.slots[from_player_slot])
		if source_stack == null:
			break
		var item_id := _slot_id(source_stack)
		var remaining := _slot_count(source_stack)
		if item_id == "" or remaining <= 0:
			break

		var moved_this_pass := false
		for chest_slot in range(int(_chest_inv.get("max_slots", 0))):
			if not _can_auto_transfer_to_chest_slot(item_id, chest_slot):
				continue
			if _transfer_player_to_chest_slot(from_player_slot, chest_slot, remaining):
				moved_this_pass = true
				moved_any = true
				break
		if not moved_this_pass:
			break

	if moved_any:
		_play_shift_transfer_sfx()

	var final_stack = _player_inv.slots[from_player_slot]
	if final_stack == null:
		return true
	var final_count := int((final_stack as Dictionary).get("count", 0))
	return final_count <= 0


func _can_auto_transfer_to_inventory_slot(item_id: String, target_slot: int) -> bool:
	if _player_inv == null:
		return false
	if target_slot < 0 or target_slot >= _player_inv.max_slots:
		return false
	var target_stack = _normalize_slot(_player_inv.slots[target_slot])
	if target_stack == null:
		return true
	if _slot_id(target_stack) != item_id:
		return false
	var stack_limit := _get_stack_limit(item_id, _as_container(_player_inv))
	return _slot_count(target_stack) < stack_limit


func _can_auto_transfer_to_chest_slot(item_id: String, target_slot: int) -> bool:
	if target_slot < 0 or target_slot >= int(_chest_inv.get("max_slots", 0)):
		return false
	var target_stack = _normalize_slot(_chest_get_slot(target_slot))
	if target_stack == null:
		return true
	if _slot_id(target_stack) != item_id:
		return false
	var stack_limit := _get_stack_limit(item_id, _chest_inv)
	return _slot_count(target_stack) < stack_limit


func _normalize_slot(raw: Variant) -> Variant:
	if raw == null:
		return null
	if not (raw is Dictionary):
		return null
	var item_id := String(raw.get("id", ""))
	var count := int(raw.get("count", 0))
	if item_id == "":
		item_id = String(raw.get("item_id", ""))
		count = int(raw.get("amount", 0))
	if item_id == "" or count <= 0:
		return null
	return {"id": item_id, "count": count}


func _slot_id(slot: Variant) -> String:
	if slot == null:
		return ""
	return String((slot as Dictionary).get("id", ""))


func _slot_count(slot: Variant) -> int:
	if slot == null:
		return 0
	return int((slot as Dictionary).get("count", 0))


func _is_valid_slot(container: Dictionary, slot_index: int) -> bool:
	var max_slots := int(container.get("max_slots", 0))
	return slot_index >= 0 and slot_index < max_slots


func _chest_get_slot(slot_index: int) -> Variant:
	var slots_array := _chest_inv.get("slots", []) as Array
	if slot_index < 0 or slot_index >= slots_array.size():
		return null
	return _normalize_slot(slots_array[slot_index])


func _get_item_icon(item_id: String) -> Texture2D:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return null
	if item_db.has_method("get_icon"):
		return item_db.get_icon(item_id) as Texture2D
	return null


func _get_stack_limit(item_id: String, container: Dictionary) -> int:
	var fallback := maxi(1, int(container.get("max_stack", _resolve_container_max_stack())))
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return fallback
	if item_db.has_method("get_max_stack"):
		return maxi(1, int(item_db.get_max_stack(item_id, fallback)))
	return fallback


func _get_chest_slot_at_global_pos(mouse_global: Vector2) -> int:
	for slot in _slot_nodes:
		if slot == null or not is_instance_valid(slot):
			continue
		if not slot.is_visible_in_tree():
			continue
		if slot.get_global_rect().has_point(mouse_global):
			return slot.slot_index
	return -1


func _get_player_slot_at_global_pos(mouse_global: Vector2) -> int:
	if player_panel == null:
		return -1
	for child in player_panel.find_children("*", "InventorySlot", true, false):
		var slot := child as InventorySlot
		if slot == null or not slot.is_visible_in_tree():
			continue
		if slot.get_global_rect().has_point(mouse_global):
			return slot.slot_index
	return -1


func _clear_drag_visual() -> void:
	if drag_ghost != null and is_instance_valid(drag_ghost):
		drag_ghost.queue_free()
	drag_ghost = null
	dragging = false
	drag_from_slot = -1
	drag_item_id = ""
	drag_amount = 0


func _get_player_inventory() -> InventoryComponent:
	var scene := get_tree().current_scene
	var player: Node = null
	if scene != null:
		player = scene.get_node_or_null("Player")
	if player == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
	if player == null:
		return null
	return player.get_node_or_null("InventoryComponent") as InventoryComponent


func _close_inventory_if_open() -> void:
	var inventory_menu := _get_player_inventory_menu()
	if inventory_menu != null and inventory_menu.visible:
		inventory_menu.close()


func _get_player_inventory_menu() -> PlayerInventoryMenu:
	var scene := get_tree().current_scene
	if scene != null:
		var by_path := scene.get_node_or_null("UI/PlayerInventoryMenu") as PlayerInventoryMenu
		if by_path != null:
			return by_path
	for node in get_tree().get_nodes_in_group("inventory_ui"):
		if node is PlayerInventoryMenu:
			return node as PlayerInventoryMenu
	return null


func _on_chest_slot_clicked(slot_index: int, _button: int) -> void:
	on_slot_primary_action(slot_index)


func _play_chest_open_sfx() -> void:
	var panel := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_CHEST_OPEN_SFX
	var volume_db: float = DEFAULT_CHEST_OPEN_VOLUME_DB
	if panel != null:
		if panel.chest_open_sfx != null:
			stream = panel.chest_open_sfx
		volume_db = panel.chest_open_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _play_chest_close_sfx() -> void:
	var panel := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_CHEST_CLOSE_SFX
	var volume_db: float = DEFAULT_CHEST_CLOSE_VOLUME_DB
	if panel != null:
		if panel.chest_close_sfx != null:
			stream = panel.chest_close_sfx
		volume_db = panel.chest_close_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _play_shift_transfer_sfx() -> void:
	_play_shift_transfer_sfx_with_semitone_offset(0.0)


func _play_shift_transfer_down_sfx() -> void:
	_play_shift_transfer_sfx_with_semitone_offset(TRANSFER_DOWN_SEMITONE_OFFSET)


func _play_shift_transfer_sfx_with_semitone_offset(semitone_offset: float) -> void:
	var panel := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_SHIFT_TRANSFER_SFX
	var volume_db: float = DEFAULT_SHIFT_TRANSFER_VOLUME_DB
	if panel != null:
		if panel.inventory_shift_transfer_sfx != null:
			stream = panel.inventory_shift_transfer_sfx
		volume_db = panel.inventory_shift_transfer_volume_db
	if stream != null:
		var pitch_scale := pow(2.0, semitone_offset / 12.0)
		AudioSystem.play_1d(stream, null, &"SFX", volume_db, pitch_scale)


func _play_inventory_item_select_sfx() -> void:
	var panel := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_INVENTORY_ITEM_SELECT_SFX
	var volume_db: float = DEFAULT_INVENTORY_ITEM_SELECT_VOLUME_DB
	if panel != null:
		if panel.inventory_item_select_sfx != null:
			stream = panel.inventory_item_select_sfx
		volume_db = panel.inventory_item_select_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _play_slot_place_sfx() -> void:
	var panel := _resolve_sound_panel()
	var pool: Array[AudioStream] = DEFAULT_UI_SLOT_PLACE_SFX_POOL
	var volume_db: float = DEFAULT_UI_SLOT_PLACE_VOLUME_DB
	if panel != null:
		var panel_pool: Array[AudioStream] = panel.get_ui_slot_place_sfx_pool()
		if not panel_pool.is_empty():
			pool = panel_pool
		volume_db = panel.ui_slot_place_volume_db
	if pool.is_empty():
		return
	var stream: AudioStream = pool[randi() % pool.size()]
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null
