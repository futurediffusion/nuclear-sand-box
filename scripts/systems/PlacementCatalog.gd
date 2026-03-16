extends RefCounted
class_name PlacementCatalog

## Catálogo central para placement: mappings de item → escena,
## modos de colocación y reglas de compatibilidad entre placeables.

const PLACEABLE_SCENES: Dictionary = {
	"workbench": "res://scenes/placeables/workbench_world.tscn",
	"chest": "res://scenes/placeables/chest_world.tscn",
	"barrel": "res://scenes/placeables/barrel_world.tscn",
	"doorwood": "res://scenes/placeables/door_world.tscn",
	"woodfloor": "res://scenes/placeables/woodfloor_world.tscn",
}

const TILE_WALL_ITEMS: Dictionary = {
	"wallwood": true,
}

const REPEAT_SCENE_ITEMS: Dictionary = {
	"woodfloor": true,
}

const PLACEMENT_MODE_SCENE: String = "scene"
const PLACEMENT_MODE_TILE_WALL: String = "tile_wall"

const SHARED_TILE_COMPATIBILITY: Dictionary = {
	"doorwood": {"woodfloor": true},
	"woodfloor": {"doorwood": true},
	"chest": {"woodfloor": true},
	"barrel": {"woodfloor": true},
	"workbench": {"woodfloor": true},
	"wallwood": {"woodfloor": true},
}


static func resolve_scene_path(item_id: String) -> String:
	return String(PLACEABLE_SCENES.get(item_id, ""))


static func resolve_placement_mode(item_id: String) -> String:
	if is_tile_wall_item(item_id):
		return PLACEMENT_MODE_TILE_WALL
	return PLACEMENT_MODE_SCENE


static func is_tile_wall_item(item_id: String) -> bool:
	return TILE_WALL_ITEMS.has(item_id)


static func is_repeat_scene_item(item_id: String) -> bool:
	return REPEAT_SCENE_ITEMS.has(item_id)


static func can_share_tile(placing_item_id: String, existing_item_id: String) -> bool:
	if placing_item_id == "" or existing_item_id == "":
		return false
	if placing_item_id == existing_item_id:
		return false
	var compat: Variant = SHARED_TILE_COMPATIBILITY.get(placing_item_id, null)
	if compat is Dictionary:
		return (compat as Dictionary).has(existing_item_id)
	return false
