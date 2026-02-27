extends CanvasLayer

@export var slot_scene: PackedScene
@export var copper_icon: Texture2D
@export var columns: int = 10
@export var rows: int = 3

@onready var shop_grid: GridContainer = $Root/Panel/ContentArea/ShopGrid

func _ready() -> void:
	visible = false

	shop_grid.columns = columns
	shop_grid.add_theme_constant_override("h_separation", 0)
	shop_grid.add_theme_constant_override("v_separation", 0)

func open_with_copper(stock: int) -> void:
	visible = true
	_fill_with_copper(stock)

func close() -> void:
	visible = false

func toggle_with_copper(stock: int) -> void:
	if visible:
		close()
	else:
		open_with_copper(stock)

func _fill_with_copper(stock: int) -> void:
	for c in shop_grid.get_children():
		c.queue_free()

	var total_slots: int = columns * rows
	var fill_count: int = mini(stock, total_slots)

	for i in range(total_slots):
		var slot = slot_scene.instantiate()
		shop_grid.add_child(slot)

		if slot is Control:
			(slot as Control).custom_minimum_size = Vector2(32, 32)

		if i < fill_count:
			if slot.has_method("set_item"):
				slot.call("set_item", 1, copper_icon)
		else:
			if slot.has_method("set_empty"):
				slot.call("set_empty")
