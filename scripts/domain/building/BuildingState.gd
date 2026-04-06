extends RefCounted
class_name BuildingState

## Building domain state container.
##
## Scope (scaffolding):
## - Keep building/structure data in a state-first shape.
## - Stay independent from scene nodes and world orchestration.
## - Provide tiny helpers so command processors can read/write consistently.

const KEY_VERSION := "version"
const KEY_STRUCTURES_BY_TILE := "structures_by_tile"

const STRUCTURE_KEY_ID := "structure_id"
const STRUCTURE_KEY_TILE_POS := "tile_pos"
const STRUCTURE_KEY_HP := "hp"
const STRUCTURE_KEY_MAX_HP := "max_hp"
const STRUCTURE_KEY_METADATA := "metadata"

static func create_empty() -> Dictionary:
	return {
		KEY_VERSION: 1,
		KEY_STRUCTURES_BY_TILE: {},
	}

static func create_structure_record(
		structure_id: String,
		tile_pos: Vector2i,
		hp: int,
		max_hp: int,
		metadata: Dictionary = {}
	) -> Dictionary:
	return {
		STRUCTURE_KEY_ID: structure_id,
		STRUCTURE_KEY_TILE_POS: tile_pos,
		STRUCTURE_KEY_HP: maxi(0, hp),
		STRUCTURE_KEY_MAX_HP: maxi(1, max_hp),
		STRUCTURE_KEY_METADATA: metadata.duplicate(true),
	}

static func get_structures_map(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	return state.get(KEY_STRUCTURES_BY_TILE, {}) as Dictionary

static func has_structure_at_tile(state: Dictionary, tile_pos: Vector2i) -> bool:
	return get_structures_map(state).has(tile_pos)

static func get_structure_at_tile(state: Dictionary, tile_pos: Vector2i) -> Dictionary:
	return get_structures_map(state).get(tile_pos, {}) as Dictionary
