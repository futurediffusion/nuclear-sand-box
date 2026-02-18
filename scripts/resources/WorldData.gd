class_name WorldData
extends Resource

@export var map_size: Vector2i = Vector2i.ZERO
@export var tavern_position: Vector2i = Vector2i.ZERO
@export var tile_ids: Dictionary = {}
@export var resource_nodes: Dictionary = {}

func setup(initial_map_size: Vector2i, initial_tavern_position: Vector2i) -> void:
	map_size = initial_map_size
	tavern_position = initial_tavern_position

func set_tile(cell: Vector2i, tile_id: int) -> void:
	tile_ids[cell] = tile_id

func get_tile(cell: Vector2i) -> int:
	if not tile_ids.has(cell):
		return -1
	return tile_ids[cell]

func set_resource_amount(cell: Vector2i, amount: int) -> void:
	if amount <= 0:
		resource_nodes.erase(cell)
		return
	resource_nodes[cell] = amount

func get_resource_amount(cell: Vector2i) -> int:
	if not resource_nodes.has(cell):
		return 0
	return resource_nodes[cell]
