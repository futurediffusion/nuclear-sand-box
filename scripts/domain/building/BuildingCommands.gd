extends RefCounted
class_name BuildingCommands

## Building domain command payload constructors.
##
## Commands are explicit dictionaries to keep the boundary contract clear
## while this module is still lightweight/scaffolding.

const TYPE_PLACE_STRUCTURE := "place_structure"
const TYPE_DAMAGE_STRUCTURE := "damage_structure"
const TYPE_REMOVE_STRUCTURE := "remove_structure"

static func place_structure(
		structure_id: String,
		tile_pos: Vector2i,
		max_hp: int,
		metadata: Dictionary = {}
	) -> Dictionary:
	return {
		"type": TYPE_PLACE_STRUCTURE,
		"structure_id": structure_id,
		"tile_pos": tile_pos,
		"max_hp": maxi(1, max_hp),
		"metadata": metadata.duplicate(true),
	}

static func damage_structure(
		tile_pos: Vector2i,
		amount: int,
		source_id: String = ""
	) -> Dictionary:
	return {
		"type": TYPE_DAMAGE_STRUCTURE,
		"tile_pos": tile_pos,
		"amount": maxi(0, amount),
		"source_id": source_id,
	}

static func remove_structure(
		tile_pos: Vector2i,
		reason: String = "",
		drop_items: bool = true
	) -> Dictionary:
	return {
		"type": TYPE_REMOVE_STRUCTURE,
		"tile_pos": tile_pos,
		"reason": reason,
		"drop_items": drop_items,
	}
