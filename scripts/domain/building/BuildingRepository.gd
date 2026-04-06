extends RefCounted
class_name BuildingRepository

## Building persistence boundary contract.
##
## Building domain modules should depend on this repository abstraction instead
## of calling WorldSave directly. Concrete adapters (WorldSave, tests, future
## disk-backed stores) implement this contract.
##
## Record contract (Dictionary) expected by this interface:
## - structure_id: String
## - chunk_pos: Vector2i
## - tile_pos: Vector2i
## - kind: String
## - hp: int
## - max_hp: int
## - metadata: Dictionary

func save_structure(_structure: Dictionary) -> Dictionary:
	push_error("BuildingRepository.save_structure must be implemented by an adapter")
	return {}

func remove_structure(_chunk_pos: Vector2i, _tile_pos: Vector2i) -> bool:
	push_error("BuildingRepository.remove_structure must be implemented by an adapter")
	return false

func load_structures_in_chunk(_chunk_pos: Vector2i) -> Array[Dictionary]:
	push_error("BuildingRepository.load_structures_in_chunk must be implemented by an adapter")
	return []

func get_structure_by_tile(_chunk_pos: Vector2i, _tile_pos: Vector2i) -> Dictionary:
	push_error("BuildingRepository.get_structure_by_tile must be implemented by an adapter")
	return {}

func get_structure_by_key(_structure_id: String) -> Dictionary:
	push_error("BuildingRepository.get_structure_by_key must be implemented by an adapter")
	return {}

func list_structures() -> Array[Dictionary]:
	push_error("BuildingRepository.list_structures must be implemented by an adapter")
	return []
