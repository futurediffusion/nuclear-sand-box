extends CanvasLayer
class_name InventoryUI

@export var grid_path: NodePath
@export var slot_scene: PackedScene
@export var columns: int = 5
@export var rows: int = 3
@export var copper_icon: Texture2D

var _grid: GridContainer
var _slots: Array[InventorySlot] = []
var _inventory: Node = null

func _ready() -> void:
	print("[InventoryUI] _ready() OK. node=", name)

	_grid = get_node_or_null(grid_path) as GridContainer
	print("[InventoryUI] grid_path=", grid_path, " grid=", _grid)

	print("[InventoryUI] slot_scene=", slot_scene)
	print("[InventoryUI] columns=", columns, " rows=", rows)

	if _grid == null:
		push_error("[InventoryUI] ERROR: grid_path no apunta a un GridContainer")
		return

	if slot_scene == null:
		push_error("[InventoryUI] ERROR: slot_scene NO asignado en el Inspector (en la instancia de Main)")
		return

	_grid.columns = columns

	_build_slots()
	print("[InventoryUI] total slots=", _slots.size(), " grid children=", _grid.get_child_count())

	visible = false

func toggle() -> void:
	print("[InventoryUI] toggle() visible antes=", visible, " slots=", _slots.size())
	visible = not visible
	if visible:
		refresh()

func _build_slots() -> void:
	var total: int = columns * rows
	for i in range(total):
		var s := slot_scene.instantiate() as InventorySlot
		_grid.add_child(s)
		_slots.append(s)

func set_inventory(inv: Node) -> void:
	_inventory = inv
	print("[InventoryUI] set_inventory inv_id=", _inventory.get_instance_id())

	# ✅ conectar señal del inventario
	if _inventory.has_signal("inventory_changed"):
		if not _inventory.inventory_changed.is_connected(refresh):
			_inventory.inventory_changed.connect(refresh)

	refresh()

func refresh() -> void:
	if _inventory == null:
		return
	if not ("slots" in _inventory):
		return

	for s in _slots:
		s.set_empty()

	for i in range(min(_slots.size(), _inventory.slots.size())):
		var data = _inventory.slots[i]
		if data == null:
			continue

		var item_id: String = String(data["id"])
		var amount: int = int(data["count"])

		var tex: Texture2D = _resolve_icon(item_id)
		_slots[i].set_item(amount, tex)


func _resolve_icon(item_id: String) -> Texture2D:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db != null and item_db.has_method("get_item"):
		var data: ItemData = item_db.get_item(item_id)
		if data != null and data.icon != null:
			return data.icon
	return copper_icon if item_id == "copper" else null
