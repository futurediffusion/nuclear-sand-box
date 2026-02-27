extends CanvasLayer
class_name InventoryUI

@export var grid_path: NodePath
@export var slot_scene: PackedScene
@export var columns: int = 5
@export var rows: int = 3
@export var copper_icon: Texture2D
@export var owner_actor_path: NodePath
@export var inventory_path: NodePath

var _grid: GridContainer
var _slots: Array[InventorySlot] = []
var inventory_ref: InventoryComponent = null
var owner_actor: Node = null
@onready var _events := get_node_or_null("/root/GameEvents")
@onready var panel: InventoryPanel = $Root/InventoryPanel
func _ready() -> void:
	visible = false
	Debug.log("boot", "InventoryUI ready begin")
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

	owner_actor = get_node_or_null(owner_actor_path)
	inventory_ref = get_node_or_null(inventory_path) as InventoryComponent
	if owner_actor == null:
		push_warning("[InventoryUI] owner_actor_path no apunta a un actor válido")
	if inventory_ref == null:
		push_warning("[InventoryUI] inventory_path no apunta a InventoryComponent")
	elif owner_actor == null:
		owner_actor = inventory_ref.get_parent()

	_grid.columns = columns

	_build_slots()
	print("[InventoryUI] total slots=", _slots.size(), " grid children=", _grid.get_child_count())

	if _events != null and _events.has_signal("item_picked"):
		if not _events.item_picked.is_connected(_on_item_picked):
			_events.item_picked.connect(_on_item_picked)
	else:
		push_warning("[InventoryUI] GameEvents no existe en /root o no tiene signal item_picked")

	_connect_inventory_signal(inventory_ref)

	visible = false
	Debug.log("boot", "InventoryUI ready end")

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

func set_inventory(inv: InventoryComponent, owner: Node = null) -> void:
	if inventory_ref != null and inventory_ref != inv and inventory_ref.inventory_changed.is_connected(refresh):
		inventory_ref.inventory_changed.disconnect(refresh)

	inventory_ref = inv
	if owner != null:
		owner_actor = owner
	elif inventory_ref != null and owner_actor == null:
		owner_actor = inventory_ref.get_parent()

	if inventory_ref != null:
		print("[InventoryUI] set_inventory inv_id=", inventory_ref.get_instance_id())
	_connect_inventory_signal(inventory_ref)

	refresh()

func refresh() -> void:
	if inventory_ref == null:
		return
	if not ("slots" in inventory_ref):
		return

	for s in _slots:
		s.set_empty()

	for i in range(min(_slots.size(), inventory_ref.slots.size())):
		var data = inventory_ref.slots[i]
		if data == null:
			continue

		var item_id: String = String(data["id"])
		var amount: int = int(data["count"])

		var tex: Texture2D = _resolve_icon(item_id)
		_slots[i].set_item(amount, tex)


func _on_item_picked(_item_id: String, amount: int, picker: Node) -> void:
	if amount <= 0:
		return
	if owner_actor != null and picker != owner_actor:
		return

	refresh()

func _connect_inventory_signal(inv: InventoryComponent) -> void:
	if inv == null:
		return
	if not inv.inventory_changed.is_connected(refresh):
		inv.inventory_changed.connect(refresh)


func _resolve_icon(item_id: String) -> Texture2D:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db != null and item_db.has_method("get_item"):
		var data: ItemData = item_db.get_item(item_id)
		if data != null and data.icon != null:
			return data.icon
	return copper_icon if item_id == "copper" else null
