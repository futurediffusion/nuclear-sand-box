extends Control
class_name InventorySlot

@onready var icon: TextureRect = $Icon
@onready var count: Label = $Count
@onready var _icon_node: CanvasItem = $Icon as CanvasItem

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
