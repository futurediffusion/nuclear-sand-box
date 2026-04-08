extends RefCounted
class_name BuildingEvents

const BuildingEventDtoScript := preload("res://scripts/domain/contracts/BuildingEventDto.gd")

## Building domain event payload constructors.
##
## Events represent immutable facts emitted by BuildingSystem
## when commands are eventually applied.

const TYPE_STRUCTURE_PLACED := "structure_placed"
const TYPE_STRUCTURE_DAMAGED := "structure_damaged"
const TYPE_STRUCTURE_REMOVED := "structure_removed"

static func structure_placed(structure: Dictionary) -> Dictionary:
	return BuildingEventDtoScript.structure_placed(structure)

static func structure_damaged(
		structure_id: String,
		tile_pos: Vector2i,
		damage_amount: int,
		remaining_hp: int,
		was_destroyed: bool
	) -> Dictionary:
	return BuildingEventDtoScript.structure_damaged(
		structure_id,
		tile_pos,
		damage_amount,
		remaining_hp,
		was_destroyed
	)

static func structure_removed(
		structure_id: String,
		tile_pos: Vector2i,
		reason: String = ""
	) -> Dictionary:
	return BuildingEventDtoScript.structure_removed(structure_id, tile_pos, reason)
