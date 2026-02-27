extends Control
class_name InventoryPanel

signal slot_clicked(slot_index: int, button: int)

@export var grid_path: NodePath
@export var slot_scene: PackedScene

@export var columns: int = 5
@export var rows: int = 3

# Opcional: tamaño visual del tile, por si quieres 32x32 aquí.
@export var tile_size: Vector2 = Vector2(32, 32)

@onready var _grid: GridContainer = get_node(grid_path) as GridContainer

var _inv: InventoryComponent = null
var _slots_nodes: Array[Node] = []
var _visible_slots: int = 0

func _ready() -> void:
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)
	_rebuild_grid()

func configure_view(new_cols: int, new_rows: int) -> void:
	columns = new_cols
	rows = new_rows
	_grid.columns = columns
	_rebuild_grid()
	_refresh()

func set_inventory(inv: InventoryComponent) -> void:
	# desconecta anterior
	if _inv != null and _inv.inventory_changed.is_connected(_refresh):
		_inv.inventory_changed.disconnect(_refresh)

	_inv = inv

	if _inv != null:
		_inv.inventory_changed.connect(_refresh)

	_refresh()

func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()

	_slots_nodes.clear()
	_visible_slots = columns * rows

	for i in range(_visible_slots):
		var slot = slot_scene.instantiate()
		_grid.add_child(slot)
		_slots_nodes.append(slot)

		# fuerza tamaño visual (clave si el slot viene con offsets raros)
		if slot is Control:
			(slot as Control).custom_minimum_size = tile_size
			# evita que se estire raro en algunos layouts
			(slot as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			(slot as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# click hook (compra/venta)
		if slot is Control:
			(slot as Control).gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed:
					emit_signal("slot_clicked", i, ev.button_index)
			)

func _refresh() -> void:
	if _inv == null:
		_set_all_empty()
		return

	var inv_slots_count: int = _inv.max_slots
	# OJO: panel puede mostrar más que max_slots, esos van vacíos.
	for i in range(_visible_slots):
		var ui_slot = _slots_nodes[i]

		if i >= inv_slots_count:
			_set_slot_empty(ui_slot)
			continue

		var data = _inv.slots[i] # null o {"id","count"}
		if data == null:
			_set_slot_empty(ui_slot)
			continue

		var item_id: String = String(data["id"])
		var count: int = int(data["count"])
		var icon: Texture2D = _get_item_icon(item_id)

		_set_slot_item(ui_slot, icon, count)

func _set_all_empty() -> void:
	for s in _slots_nodes:
		_set_slot_empty(s)

func _set_slot_empty(slot: Node) -> void:
	if slot.has_method("set_empty"):
		slot.call("set_empty")
	elif slot.has_method("set_item"):
		# fallback: meter "nada"
		slot.call("set_item", 0, null)
	else:
		# último recurso: intentar encontrar hijos típicos
		var icon_node := slot.get_node_or_null("Icon")
		if icon_node and icon_node is TextureRect:
			(icon_node as TextureRect).texture = null
		var label_node := slot.get_node_or_null("Count")
		if label_node and label_node is Label:
			(label_node as Label).text = ""

func _set_slot_item(slot: Node, icon: Texture2D, count: int) -> void:
	if slot.has_method("set_item"):
		# Tu slot actual usa set_item(count, icon) o set_item(amount, texture)
		slot.call("set_item", count, icon)
		return

	# fallback manual (si algún slot no tiene set_item)
	var icon_node := slot.get_node_or_null("Icon")
	if icon_node and icon_node is TextureRect:
		(icon_node as TextureRect).texture = icon

	var label_node := slot.get_node_or_null("Count")
	if label_node and label_node is Label:
		(label_node as Label).text = str(count) if count > 1 else ""

func _get_item_icon(item_id: String) -> Texture2D:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return null

	# Intentos por si tu ItemDB tiene nombres distintos
	if item_db.has_method("get_icon"):
		return item_db.call("get_icon", item_id)
	if item_db.has_method("get_item_icon"):
		return item_db.call("get_item_icon", item_id)
	if item_db.has_method("get_texture"):
		return item_db.call("get_texture", item_id)
	if item_db.has_method("get_item_texture"):
		return item_db.call("get_item_texture", item_id)

	return null
