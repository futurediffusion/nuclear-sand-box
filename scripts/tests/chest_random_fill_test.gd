extends Node2D

@export var chest_scene: PackedScene = preload("res://scenes/placeables/chest_world.tscn")
@export var chest_slots_to_fill: int = 15
@export var max_chest_distance_px: float = 28.0

@onready var player: Node2D = $Player


func _ready() -> void:
	randomize()
	_spawn_test_chest()


func _spawn_test_chest() -> void:
	if chest_scene == null:
		push_warning("[ChestRandomFillTest] chest_scene no asignada")
		return

	var chest := chest_scene.instantiate() as ChestWorld
	if chest == null:
		push_warning("[ChestRandomFillTest] no se pudo instanciar ChestWorld")
		return

	chest.position = player.position + Vector2(max_chest_distance_px, 0.0)
	chest.stored_slots = _build_random_slots(chest_slots_to_fill)
	add_child(chest)


func _build_random_slots(slot_count: int) -> Array:
	var result: Array = []
	if slot_count <= 0:
		return result

	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		push_warning("[ChestRandomFillTest] ItemDB no disponible")
		return result

	var ids: Array = item_db.items.keys()
	if ids.is_empty():
		push_warning("[ChestRandomFillTest] ItemDB sin items")
		return result

	for i in range(slot_count):
		var item_id := String(ids[randi() % ids.size()])
		var max_stack := 10
		if item_db.has_method("get_max_stack"):
			max_stack = maxi(1, int(item_db.get_max_stack(item_id, 10)))
		var amount := randi_range(1, max_stack)
		result.append({"id": item_id, "count": amount})

	return result
