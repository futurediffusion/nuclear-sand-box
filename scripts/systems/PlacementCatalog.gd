extends RefCounted
class_name PlacementCatalog

## Catalogo central para placement: mappings de item -> escena,
## modos de colocacion y reglas de compatibilidad entre placeables.

const FLOORWOOD_ITEM_ID: String = "floorwood"
const LEGACY_WOODFLOOR_ITEM_ID: String = "woodfloor"

const PLACEABLE_SCENES: Dictionary = {
	"workbench": "res://scenes/placeables/workbench_world.tscn",
	"chest": "res://scenes/placeables/chest_world.tscn",
	"barrel": "res://scenes/placeables/barrel_world.tscn",
	"doorwood": "res://scenes/placeables/door_world.tscn",
	FLOORWOOD_ITEM_ID: "res://scenes/placeables/woodfloor_world.tscn",
	LEGACY_WOODFLOOR_ITEM_ID: "res://scenes/placeables/woodfloor_world.tscn",
}

const TILE_WALL_ITEMS: Dictionary = {
	"wallwood": true,
}

const REPEAT_SCENE_ITEMS: Dictionary = {
	FLOORWOOD_ITEM_ID: true,
	LEGACY_WOODFLOOR_ITEM_ID: true,
}

const PLACEMENT_MODE_SCENE: String = "scene"
const PLACEMENT_MODE_TILE_WALL: String = "tile_wall"

const SHARED_TILE_COMPATIBILITY: Dictionary = {
	"doorwood": {FLOORWOOD_ITEM_ID: true},
	FLOORWOOD_ITEM_ID: {"doorwood": true},
	"chest": {FLOORWOOD_ITEM_ID: true},
	"barrel": {FLOORWOOD_ITEM_ID: true},
	"workbench": {FLOORWOOD_ITEM_ID: true},
	"wallwood": {FLOORWOOD_ITEM_ID: true},
}


static func resolve_scene_path(item_id: String) -> String:
	var normalized := normalize_item_id(item_id)
	return String(PLACEABLE_SCENES.get(normalized, String(PLACEABLE_SCENES.get(item_id, ""))))


static func resolve_placement_mode(item_id: String) -> String:
	if is_tile_wall_item(item_id):
		return PLACEMENT_MODE_TILE_WALL
	return PLACEMENT_MODE_SCENE


static func is_tile_wall_item(item_id: String) -> bool:
	return TILE_WALL_ITEMS.has(normalize_item_id(item_id))


static func is_repeat_scene_item(item_id: String) -> bool:
	return REPEAT_SCENE_ITEMS.has(normalize_item_id(item_id))


static func is_floorwood_item(item_id: String) -> bool:
	return normalize_item_id(item_id) == FLOORWOOD_ITEM_ID


static func can_share_tile(placing_item_id: String, existing_item_id: String) -> bool:
	var placing_id := normalize_item_id(placing_item_id)
	var existing_id := normalize_item_id(existing_item_id)
	if placing_id == "" or existing_id == "":
		return false
	if placing_id == existing_id:
		return false
	var compat: Variant = SHARED_TILE_COMPATIBILITY.get(placing_id, null)
	if compat is Dictionary:
		return (compat as Dictionary).has(existing_id)
	return false


static func normalize_item_id(item_id: String) -> String:
	var normalized := item_id.strip_edges()
	if normalized == LEGACY_WOODFLOOR_ITEM_ID:
		return FLOORWOOD_ITEM_ID
	return normalized
