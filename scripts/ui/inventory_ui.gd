extends CanvasLayer
class_name InventoryUI

@export var owner_actor_path: NodePath
@export var inventory_path: NodePath

@onready var panel: InventoryPanel = $Root/InventoryUI

var inventory_ref: InventoryComponent = null
var owner_actor: Node = null

func _ready() -> void:
	visible = false

	owner_actor = get_node_or_null(owner_actor_path)
	inventory_ref = get_node_or_null(inventory_path) as InventoryComponent

	if inventory_ref == null:
		push_warning("[InventoryUI] inventory_path no apunta a InventoryComponent")
		return

	panel.set_inventory(inventory_ref)

func toggle() -> void:
	visible = not visible

func set_inventory(inv: InventoryComponent) -> void:
	inventory_ref = inv
	if panel != null:
		panel.set_inventory(inventory_ref)
