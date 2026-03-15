extends Control
class_name InventoryPanel

signal slot_clicked(slot_index: int, button: int)
signal placeable_requested(item_id: String)

@export var slot_scene: PackedScene

@export var columns: int = 5
@export var rows: int = 3

# tamaño visual del tile
@export var tile_size: Vector2 = Vector2(32, 32)


@onready var _grid: GridContainer = $Grid

var _inv: InventoryComponent = null
var _slots_nodes: Array[Node] = []
var _visible_slots: int = 0
var _price_resolver: Callable = Callable()
var _slot_meta: Array[Dictionary] = []
var _shop_vendor: VendorComponent = null
var _shop_player_inv: InventoryComponent = null
var _shop_mode: String = ""
var dragging: bool = false
var drag_from_slot: int = -1
var drag_item_id: String = ""
var drag_amount: int = 0
var drag_from_count_snapshot: int = 0
var drag_ghost: Control = null
var drag_offset: Vector2 = Vector2(16, 16)
var _default_drop_scene: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
var _external_drop_handler: Callable = Callable()
var _external_quick_transfer_handler: Callable = Callable()


func _process(_delta: float) -> void:
	if not dragging:
		return
	if drag_ghost == null or not is_instance_valid(drag_ghost):
		return
	drag_ghost.global_position = get_viewport().get_mouse_position() - drag_offset

func _ready() -> void:
	if _grid == null:
		push_error("[InventoryPanel] No existe nodo requerido $Grid (GridContainer). Revisa inventory_panel.tscn.")
		return

	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)

	_rebuild_grid()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree() and dragging:
			cancel_drag()
	elif what == NOTIFICATION_EXIT_TREE:
		if dragging:
			cancel_drag()

func configure_view(new_cols: int, new_rows: int) -> void:
	columns = new_cols
	rows = new_rows

	if _grid != null:
		_grid.columns = columns

	_rebuild_grid()
	_refresh()

func set_inventory(inv: InventoryComponent) -> void:
	# desconecta anterior
	if _inv != null and _inv.inventory_changed.is_connected(_refresh):
		_inv.inventory_changed.disconnect(_refresh)
	if _inv != null and _inv.slot_changed.is_connected(_on_inventory_slot_changed):
		_inv.slot_changed.disconnect(_on_inventory_slot_changed)

	_inv = inv

	# conecta nuevo
	if _inv != null and not _inv.inventory_changed.is_connected(_refresh):
		_inv.inventory_changed.connect(_refresh)
	if _inv != null and not _inv.slot_changed.is_connected(_on_inventory_slot_changed):
		_inv.slot_changed.connect(_on_inventory_slot_changed)

	for slot in _slots_nodes:
		if slot.has_method("bind_inventory_component"):
			slot.call("bind_inventory_component", _inv)

	_refresh()

func set_price_resolver(resolver: Callable) -> void:
	_price_resolver = resolver
	_refresh()

func set_shop_context(vendor: VendorComponent, player_inv: InventoryComponent, mode: String) -> void:
	_shop_vendor = vendor
	_shop_player_inv = player_inv
	_shop_mode = mode
	_refresh()


func set_external_drop_handler(handler: Callable) -> void:
	_external_drop_handler = handler


func set_external_quick_transfer_handler(handler: Callable) -> void:
	_external_quick_transfer_handler = handler

func _rebuild_grid() -> void:
	if _grid == null:
		return

	for c in _grid.get_children():
		c.queue_free()

	_slots_nodes.clear()
	_slot_meta.clear()
	_visible_slots = columns * rows

	for i in range(_visible_slots):
		var slot = slot_scene.instantiate()
		_grid.add_child(slot)
		_slots_nodes.append(slot)
		_slot_meta.append({})

		# fuerza tamaño visual
		if slot is Control:
			var cslot := slot as Control
			cslot.custom_minimum_size = tile_size
			# estos flags evitan que el container te lo estire raro
			cslot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cslot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cslot.mouse_filter = Control.MOUSE_FILTER_STOP

			if slot.has_method("bind_inventory_component"):
				slot.call("bind_inventory_component", _inv)
			if slot.has_method("bind_inventory_ui"):
				slot.call("bind_inventory_ui", self)
			if slot is InventorySlot:
				(slot as InventorySlot).slot_index = i
			if slot.has_signal("slot_clicked") and not slot.slot_clicked.is_connected(_on_slot_clicked):
				slot.slot_clicked.connect(_on_slot_clicked)

func _refresh() -> void:
	if _grid == null:
		return

	if _inv == null:
		clear_slot_meta()
		_set_all_empty()
		return

	var inv_slots_count: int = _inv.max_slots
	var existing_meta: Array[Dictionary] = []
	if _is_shop_buy_mode():
		existing_meta = _slot_meta.duplicate(true)
		if OS.is_debug_build():
			print("[SHOP] mapped_slots=%d" % existing_meta.size())
	clear_slot_meta()

	for i in range(_visible_slots):
		var ui_slot: Node = _slots_nodes[i]

		# si el panel muestra más que el inventario real, lo dejas vacío
		if i >= inv_slots_count:
			_set_slot_empty(ui_slot)
			_set_slot_blocked(ui_slot, false)
			_set_slot_tooltip(ui_slot, "")
			continue

		var data = _inv.slots[i] # null o {"id","count"}
		if _is_shop_buy_mode() and i < existing_meta.size() and not existing_meta[i].is_empty():
			var mapped_item_id := String(existing_meta[i].get("item_id", ""))
			if mapped_item_id != "":
				data = {"id": mapped_item_id, "count": 1}
				set_slot_meta(i, existing_meta[i])
		if data == null:
			_set_slot_empty(ui_slot)
			_set_slot_blocked(ui_slot, false)
			_set_slot_tooltip(ui_slot, "")
			continue

		var item_id: String = String(data.get("id", ""))
		var count: int = int(data.get("count", 0))

		if item_id == "" or count <= 0:
			_set_slot_empty(ui_slot)
			_set_slot_blocked(ui_slot, false)
			_set_slot_tooltip(ui_slot, "")
			continue

		if _is_shop_buy_mode() and i < existing_meta.size() and not existing_meta[i].is_empty():
			set_slot_meta(i, existing_meta[i])
		else:
			set_slot_meta(i, {"item_id": item_id, "source": "INV"})

		var item_db := get_node_or_null("/root/ItemDB")
		var icon: Texture2D = null

		if item_db != null:
			var item_data: ItemData = item_db.get_item(item_id)
			if OS.is_debug_build() and _is_shop_buy_mode():
				print("[SHOP] resolve id=%s data=%s icon=%s" % [item_id, str(item_data != null), item_data.icon if item_data else null])
			if item_data != null and item_data.icon != null:
				icon = item_data.icon

		if OS.is_debug_build() and _is_shop_buy_mode():
			var icon_path: String = icon.resource_path if icon != null else "null"
			print("[SHOP] paint slot=%d offer_index=%s id=%s icon_path=%s" % [i, str(get_slot_meta(i).get("offer_index", -1)), item_id, icon_path])
		_set_slot_item(ui_slot, icon, count)
		if OS.is_debug_build() and _is_shop_buy_mode():
			print("[SHOP] paint slot=%d id=%s count=%s" % [i, item_id, str(count)])
		_set_slot_blocked(ui_slot, _is_slot_blocked(i, item_id))
		_set_slot_tooltip(ui_slot, _build_tooltip(item_id, count))



func _on_inventory_slot_changed(slot_index: int) -> void:
	_refresh_slot(slot_index)


func _refresh_slot(slot_index: int) -> void:
	if _grid == null:
		return
	if slot_index < 0 or slot_index >= _visible_slots:
		return

	var ui_slot: Node = _slots_nodes[slot_index]
	if _inv == null:
		_set_slot_empty(ui_slot)
		_set_slot_blocked(ui_slot, false)
		_set_slot_tooltip(ui_slot, "")
		return

	var inv_slots_count: int = _inv.max_slots
	if slot_index >= inv_slots_count:
		_set_slot_empty(ui_slot)
		_set_slot_blocked(ui_slot, false)
		_set_slot_tooltip(ui_slot, "")
		return

	var data = _inv.slots[slot_index]
	if _is_shop_buy_mode() and slot_index < _slot_meta.size() and not _slot_meta[slot_index].is_empty():
		var mapped_item_id := String(_slot_meta[slot_index].get("item_id", ""))
		if mapped_item_id != "":
			data = {"id": mapped_item_id, "count": 1}
	if data == null:
		_set_slot_empty(ui_slot)
		_set_slot_blocked(ui_slot, false)
		_set_slot_tooltip(ui_slot, "")
		set_slot_meta(slot_index, {})
		return

	var item_id: String = String(data.get("id", ""))
	var count: int = int(data.get("count", 0))
	if item_id == "" or count <= 0:
		_set_slot_empty(ui_slot)
		_set_slot_blocked(ui_slot, false)
		_set_slot_tooltip(ui_slot, "")
		set_slot_meta(slot_index, {})
		return

	var existing_slot_meta := get_slot_meta(slot_index)
	if _is_shop_buy_mode() and not existing_slot_meta.is_empty():
		set_slot_meta(slot_index, existing_slot_meta)
	else:
		set_slot_meta(slot_index, {"item_id": item_id, "source": "INV"})

	var item_db := get_node_or_null("/root/ItemDB")
	var icon: Texture2D = null
	if item_db != null:
		var item_data: ItemData = item_db.get_item(item_id)
		if OS.is_debug_build() and _is_shop_buy_mode():
			print("[SHOP] resolve id=%s data=%s icon=%s" % [item_id, str(item_data != null), item_data.icon if item_data else null])
		if item_data != null and item_data.icon != null:
			icon = item_data.icon

	if OS.is_debug_build() and _is_shop_buy_mode():
		var icon_path: String = icon.resource_path if icon != null else "null"
		print("[SHOP] paint slot=%d offer_index=%s id=%s icon_path=%s" % [slot_index, str(get_slot_meta(slot_index).get("offer_index", -1)), item_id, icon_path])
	_set_slot_item(ui_slot, icon, count)
	if OS.is_debug_build() and _is_shop_buy_mode():
		print("[SHOP] paint slot=%d id=%s count=%s" % [slot_index, item_id, str(count)])
	_set_slot_blocked(ui_slot, _is_slot_blocked(slot_index, item_id))
	_set_slot_tooltip(ui_slot, _build_tooltip(item_id, count))

func _is_slot_blocked(slot_index: int, item_id: String) -> bool:
	if _shop_vendor == null or _shop_player_inv == null:
		return false

	var slot_meta := get_slot_meta(slot_index)
	match _shop_mode:
		"BUY":
			var buy_check := ShopService.can_buy_from_meta(_shop_vendor, _shop_player_inv, slot_meta, 1)
			if OS.is_debug_build():
				var price := int(_price_resolver.call(item_id)) if _price_resolver.is_valid() else 0
				print("[SHOP] can_buy slot=%d id=%s price=%d money=%d has_space=%s offer_index=%s" % [
					slot_index,
					item_id,
					price,
					_shop_player_inv.gold,
					str(_shop_player_inv.can_add(item_id, 1)),
					str(slot_meta.get("offer_index", -1)),
				])
			return not bool(buy_check.get("ok", false))
		"SELL":
			var sell_check := ShopService.can_sell(_shop_vendor, _shop_player_inv, item_id, 1)
			return not bool(sell_check.get("ok", false))
		_:
			return false

func clear_slot_meta() -> void:
	for i in range(_slot_meta.size()):
		_slot_meta[i] = {}

func set_slot_meta(slot_index: int, meta: Dictionary) -> void:
	if slot_index < 0 or slot_index >= _slot_meta.size():
		return
	_slot_meta[slot_index] = meta.duplicate(true)

func get_slot_meta(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _slot_meta.size():
		return {}
	return _slot_meta[slot_index]

func _set_all_empty() -> void:
	for s in _slots_nodes:
		_set_slot_empty(s)

func _set_slot_empty(slot: Node) -> void:
	if slot.has_method("set_empty"):
		slot.call("set_empty")
		return

	# fallback: si solo existe set_item(count, tex)
	if slot.has_method("set_item"):
		slot.call("set_item", 0, null)
		return

	# último recurso: buscar hijos típicos
	var icon_node := slot.get_node_or_null("Icon")
	if icon_node is TextureRect:
		(icon_node as TextureRect).texture = null
		(icon_node as TextureRect).visible = false

	var label_node := slot.get_node_or_null("Count")
	if label_node is Label:
		(label_node as Label).text = ""
		(label_node as Label).visible = false

func _set_slot_blocked(slot: Node, is_blocked: bool) -> void:
	if slot.has_method("set_blocked"):
		slot.call("set_blocked", is_blocked)

func _set_slot_item(slot: Node, icon: Texture2D, count: int) -> void:
	if slot.has_method("set_item"):
		# tu InventorySlot es set_item(amount, tex)
		slot.call("set_item", count, icon)
		return

	# fallback manual
	var icon_node := slot.get_node_or_null("Icon")
	if icon_node is TextureRect:
		(icon_node as TextureRect).texture = icon
		(icon_node as TextureRect).visible = icon != null

	var label_node := slot.get_node_or_null("Count")
	if label_node is Label:
		(label_node as Label).text = str(count) if count > 1 else ""
		(label_node as Label).visible = count > 1

func _build_tooltip(item_id: String, count: int) -> String:
	var txt := "%s x%d" % [item_id, count]
	if _price_resolver.is_valid():
		var price := int(_price_resolver.call(item_id))
		txt += "\nPrice: %d" % price
	return txt

func _set_slot_tooltip(slot: Node, tip: String) -> void:
	if slot is Control:
		(slot as Control).tooltip_text = tip


func begin_drag(slot_index: int, mouse_position: Vector2, button_index: int, shift: bool) -> void:
	if not can_drag_slot(slot_index):
		return

	var stack = _inv.slots[slot_index]
	if stack == null:
		return

	var item_id := String(stack.get("id", ""))
	var count := int(stack.get("count", 0))
	if item_id == "" or count <= 0:
		return

	var amount := count
	if button_index == MOUSE_BUTTON_RIGHT:
		if shift:
			amount = int(floor(count / 2.0))
			amount = max(amount, 1)
		else:
			amount = 1
	else:
		amount = count

	var icon: Texture2D = null
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db != null:
		var item_data: ItemData = item_db.get_item(item_id)
		if item_data != null:
			icon = item_data.icon

	_clear_drag_visual()

	var ghost := Control.new()
	ghost.name = "DragGhost"
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
	ghost_icon.modulate = Color(1, 1, 1, 0.9)
	ghost.add_child(ghost_icon)

	if amount > 1:
		var ghost_count := Label.new()
		ghost_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost_count.text = str(amount)
		ghost_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ghost_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		ghost_count.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		ghost_count.add_theme_constant_override("outline_size", 2)
		ghost_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		ghost_count.size = tile_size
		ghost.add_child(ghost_count)

	add_child(ghost)
	drag_ghost = ghost
	dragging = true
	drag_from_slot = slot_index
	drag_item_id = item_id
	drag_amount = amount
	drag_from_count_snapshot = count
	drag_ghost.global_position = mouse_position - drag_offset

	print("[InventoryPanel] begin_drag VISUAL slot=%d id=%s amount=%d (from_count=%d) btn=%s shift=%s" % [slot_index, item_id, amount, count, _button_to_log(button_index), str(shift)])


func end_drag(_slot_index: int, _mouse_position: Vector2) -> void:
	var from_slot := drag_from_slot
	var amount := drag_amount
	if not dragging or from_slot < 0:
		_clear_drag_visual()
		return

	var mouse := get_viewport().get_mouse_position()
	var target := _get_slot_at_global_pos(mouse)
	print("[InventoryPanel] end_drag TARGET from=%d target=%d mouse=%s" % [from_slot, target, str(mouse)])

	if target == -1:
		if _external_drop_handler.is_valid():
			var handled := bool(_external_drop_handler.call(from_slot, amount, mouse))
			if handled:
				_clear_drag_visual()
				return

		if _is_shop_click_context():
			_clear_drag_visual()
			return

		if _inv == null:
			_clear_drag_visual()
			return

		var data := _inv.extract_amount_for_drop(from_slot, amount)
		if data.is_empty():
			_clear_drag_visual()
			return

		var item_id := String(data.get("id", ""))
		var drop_amount := int(data.get("amount", 0))
		if item_id != "" and drop_amount > 0:
			var world_pos := _resolve_world_drop_position()
			var item_data: ItemData = null
			var item_db := get_node_or_null("/root/ItemDB")
			if item_db != null and item_db.has_method("get_item"):
				item_data = item_db.get_item(item_id)

			var overrides := {
				"drop_scene": _default_drop_scene,
			}
			LootSystem.spawn_drop(item_data, item_id, drop_amount, world_pos, _resolve_world_drop_parent(), overrides)
			print("[InventoryPanel] drop OUTSIDE from=%d id=%s amount=%d world_pos=%s" % [from_slot, item_id, drop_amount, str(world_pos)])

		_clear_drag_visual()
		return

	if _inv != null and target != -1 and target != from_slot:
		_inv.drag_transfer_amount(from_slot, target, amount)

	_clear_drag_visual()


func _resolve_world_drop_position() -> Vector2:
	var player := _find_player_node()
	if player != null:
		if player.has_method("get_world_mouse_pos"):
			return player.call("get_world_mouse_pos") as Vector2
		return player.global_position + Vector2(0, 16)

	if get_tree() != null and get_tree().current_scene != null:
		var scene := get_tree().current_scene
		if scene is Node2D:
			return (scene as Node2D).global_position

	return Vector2.ZERO


func _resolve_world_drop_parent() -> Node:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		return current_scene
	return get_tree().root


func _find_player_node() -> Node2D:
	if get_tree() == null:
		return null

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		return players[0] as Node2D

	return null


func _get_slot_at_global_pos(mouse_global: Vector2) -> int:
	for slot in _slots_nodes:
		if slot == null:
			continue
		if not is_instance_valid(slot):
			continue
		if not (slot is InventorySlot):
			continue

		var inventory_slot := slot as InventorySlot
		if not inventory_slot.is_visible_in_tree():
			continue
		if inventory_slot.get_global_rect().has_point(mouse_global):
			return inventory_slot.slot_index

	return -1


func cancel_drag() -> void:
	if not dragging:
		return
	_clear_drag_visual()


func _clear_drag_visual() -> void:
	if drag_ghost != null and is_instance_valid(drag_ghost):
		drag_ghost.queue_free()

	drag_ghost = null
	dragging = false
	drag_from_slot = -1
	drag_item_id = ""
	drag_amount = 0
	drag_from_count_snapshot = 0


func _button_to_log(button_index: int) -> String:
	if button_index == MOUSE_BUTTON_RIGHT:
		return "R"
	return "L"


func can_drag_slot(slot_index: int) -> bool:
	if _is_shop_buy_mode():
		return false
	if _inv == null:
		return false
	if slot_index < 0 or slot_index >= _inv.max_slots:
		return false

	var data = _inv.slots[slot_index]
	if data == null:
		return false

	var item_id := String(data.get("id", ""))
	var amount := int(data.get("count", 0))
	return item_id != "" and amount > 0


func _is_shop_buy_mode() -> bool:
	return _shop_mode == "BUY"




func on_slot_primary_action(slot_index: int, shift_pressed: bool = false) -> bool:
	if slot_index < 0:
		return false

	if _is_shop_click_context():
		slot_clicked.emit(slot_index, MOUSE_BUTTON_LEFT)
		return true

	if _inv == null:
		return false

	if shift_pressed and _external_quick_transfer_handler.is_valid():
		return bool(_external_quick_transfer_handler.call(slot_index))

	# Placeable items entran en placement mode en vez de "usar"
	var slot_data = _inv.slots[slot_index]
	if slot_data != null:
		var item_id := String(slot_data.get("id", ""))
		if item_id != "" and _is_placeable_item(item_id):
			placeable_requested.emit(item_id)
			return true

	return _inv.use_slot(slot_index)


func _is_placeable_item(item_id: String) -> bool:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return false
	var item_data: ItemData = item_db.get_item(item_id)
	if item_data == null:
		return false
	return "placeable" in item_data.tags


func should_show_not_usable_feedback(slot_index: int) -> bool:
	if _is_shop_click_context():
		return false
	return _slot_has_item(slot_index)


func _is_shop_click_context() -> bool:
	if _shop_mode == "SELL" or _shop_mode == "BUY":
		return true
	return _shop_vendor != null and _shop_player_inv != null


func _slot_has_item(slot_index: int) -> bool:
	if _inv == null:
		return false
	if slot_index < 0 or slot_index >= _inv.max_slots:
		return false

	var data = _inv.slots[slot_index]
	if data == null:
		return false

	var item_id := String(data.get("id", ""))
	var amount := int(data.get("count", 0))
	return item_id != "" and amount > 0

func _on_slot_clicked(slot_index: int, button: int) -> void:
	slot_clicked.emit(slot_index, button)
