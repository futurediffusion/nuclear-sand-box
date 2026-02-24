extends Control
class_name InventorySlot

@onready var icon: TextureRect = $Icon
@onready var count: Label = $Count

func _ready() -> void:
	set_empty()

func set_empty() -> void:
	icon.texture = null
	icon.visible = false
	count.text = ""
	count.visible = false

func set_item(amount: int, tex: Texture2D) -> void:
	icon.texture = tex
	icon.visible = tex != null

	count.text = str(amount)
	count.visible = amount > 1
