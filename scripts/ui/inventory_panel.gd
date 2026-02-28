extends Control
class_name InventoryPanel

signal slot_clicked(slot_index: int, button: int)


@export var slot_scene: PackedScene

@export var columns: int = 5
@export var rows: int = 3

# tamaño visual del tile
@export var tile_size: Vector2 = Vector2(32, 32)


@onready var _grid: GridContainer = $Grid

var _inv: InventoryComponent = null
var _slots_nodes: Array[Node] = []
var _visible_slots: int = 0

func _ready() -> void:
	if _grid == null:
		push_error("[InventoryPanel] No existe nodo $Grid (GridContainer). Revisa inventory_panel.tscn.")
		return

	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)

	_rebuild_grid()
	_refresh()

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

	_inv = inv

	# conecta nuevo
	if _inv != null and not _inv.inventory_changed.is_connected(_refresh):
		_inv.inventory_changed.connect(_refresh)

	_refresh()

func _rebuild_grid() -> void:
	if _grid == null:
		return

	for c in _grid.get_children():
		c.queue_free()

	_slots_nodes.clear()
	_visible_slots = columns * rows

	for i in range(_visible_slots):
		var slot = slot_scene.instantiate()
		_grid.add_child(slot)
		_slots_nodes.append(slot)

		# fuerza tamaño visual
		if slot is Control:
			var cslot := slot as Control
			cslot.custom_minimum_size = tile_size
			# estos flags evitan que el container te lo estire raro
			cslot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cslot.size_flags_vertical = Control.SIZE_SHRINK_CENTER

			# click hook (compra/venta)
			var idx := i # IMPORTANTÍSIMO: evita bug de captura del loop
			cslot.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed:
					slot_clicked.emit(idx, ev.button_index)
			)

func _refresh() -> void:
	if _grid == null:
		return

	if _inv == null:
		_set_all_empty()
		return

	var inv_slots_count: int = _inv.max_slots

	for i in range(_visible_slots):
		var ui_slot: Node = _slots_nodes[i]

		# si el panel muestra más que el inventario real, lo dejas vacío
		if i >= inv_slots_count:
			_set_slot_empty(ui_slot)
			continue

		var data = _inv.slots[i] # null o {"id","count"}
		if data == null:
			_set_slot_empty(ui_slot)
			continue

		var item_id: String = String(data.get("id", ""))
		var count: int = int(data.get("count", 0))

		if item_id == "" or count <= 0:
			_set_slot_empty(ui_slot)
			continue

		var item_db := get_node_or_null("/root/ItemDB")
		var icon: Texture2D = null

		if item_db != null:
			var item_data: ItemData = item_db.get_item(item_id)
			if item_data != null and item_data.icon != null:
				icon = item_data.icon

		_set_slot_item(ui_slot, icon, count)

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
