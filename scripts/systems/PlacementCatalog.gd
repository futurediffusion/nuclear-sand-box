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
	"table": "res://scenes/placeables/table_world.tscn",
	"stool": "res://scenes/placeables/stool_world.tscn",
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
	"table": {FLOORWOOD_ITEM_ID: true},
	"stool": {FLOORWOOD_ITEM_ID: true},
	"workbench": {FLOORWOOD_ITEM_ID: true},
	"wallwood": {FLOORWOOD_ITEM_ID: true},
}

const LEGACY_IGNORE_COLLISION_GROUPS: Dictionary = {
	FLOORWOOD_ITEM_ID: ["doorwood_placeable"],
	LEGACY_WOODFLOOR_ITEM_ID: ["doorwood_placeable"],
}


static func resolve_scene_path(item_id: String) -> String:
	return String(get_placement_profile(item_id).get("scene_path", ""))


static func resolve_placement_mode(item_id: String) -> String:
	return String(get_placement_profile(item_id).get("placement_mode", PLACEMENT_MODE_SCENE))


static func is_tile_wall_item(item_id: String) -> bool:
	return resolve_placement_mode(item_id) == PLACEMENT_MODE_TILE_WALL


static func is_repeat_scene_item(item_id: String) -> bool:
	return bool(get_placement_profile(item_id).get("repeat_place", false))


static func is_drag_paint_enabled_item(item_id: String) -> bool:
	return bool(get_placement_profile(item_id).get("drag_paintable", false))


static func is_floorwood_item(item_id: String) -> bool:
	return normalize_item_id(item_id) == FLOORWOOD_ITEM_ID


static func can_share_tile(placing_item_id: String, existing_item_id: String) -> bool:
	var placing_id := normalize_item_id(placing_item_id)
	var existing_id := normalize_item_id(existing_item_id)
	if placing_id == "" or existing_id == "":
		return false
	if placing_id == existing_id:
		return false
	var raw_share_set: Variant = get_placement_profile(placing_id).get("can_share_set", {})
	if raw_share_set is Dictionary:
		return (raw_share_set as Dictionary).has(existing_id)
	return false


static func get_ignore_collision_groups(item_id: String) -> Array[String]:
	var raw_groups: Variant = get_placement_profile(item_id).get("ignore_collision_groups_when_placing", [])
	return _normalize_string_array(raw_groups)


static func should_ignore_collision_for_item(item_id: String, collider: Variant) -> bool:
	if not (collider is Node):
		return false
	var node := collider as Node
	for group_name in get_ignore_collision_groups(item_id):
		if group_name != "" and node.is_in_group(group_name):
			return true
	return false


static func get_placement_profile(item_id: String) -> Dictionary:
	var normalized_id := normalize_item_id(item_id)
	var profile := _legacy_profile(normalized_id, item_id)
	var metadata := _get_itemdb_placement_data(normalized_id)
	if not bool(metadata.get("has_explicit_placement", false)):
		return profile
	var mode := String(metadata.get("placement_mode", "")).strip_edges()
	if mode == PLACEMENT_MODE_SCENE or mode == PLACEMENT_MODE_TILE_WALL:
		profile["placement_mode"] = mode
	var scene_path := String(metadata.get("placement_scene_path", "")).strip_edges()
	if scene_path != "":
		profile["scene_path"] = scene_path
	if metadata.has("repeat_place"):
		profile["repeat_place"] = bool(metadata["repeat_place"])
	if metadata.has("drag_paintable"):
		profile["drag_paintable"] = bool(metadata["drag_paintable"])
	var metadata_share := _normalize_item_id_array(metadata.get("can_share_tile_with", []))
	if not metadata_share.is_empty():
		profile["can_share_tile_with"] = metadata_share
		profile["can_share_set"] = _build_bool_set(metadata_share)
	var ignore_groups := _normalize_string_array(metadata.get("ignore_collision_groups_when_placing", []))
	if not ignore_groups.is_empty():
		profile["ignore_collision_groups_when_placing"] = ignore_groups
	return profile


static func normalize_item_id(item_id: String) -> String:
	var normalized := item_id.strip_edges()
	if normalized == LEGACY_WOODFLOOR_ITEM_ID:
		return FLOORWOOD_ITEM_ID
	return normalized


static func _legacy_profile(normalized_id: String, raw_item_id: String) -> Dictionary:
	var scene_path := String(PLACEABLE_SCENES.get(normalized_id, String(PLACEABLE_SCENES.get(raw_item_id, ""))))
	var placement_mode := PLACEMENT_MODE_TILE_WALL if TILE_WALL_ITEMS.has(normalized_id) else PLACEMENT_MODE_SCENE
	var repeat_place := REPEAT_SCENE_ITEMS.has(normalized_id)
	var drag_paintable := placement_mode == PLACEMENT_MODE_TILE_WALL or normalized_id == FLOORWOOD_ITEM_ID
	var legacy_share: Array[String] = []
	var compat: Variant = SHARED_TILE_COMPATIBILITY.get(normalized_id, null)
	if compat is Dictionary:
		for raw_id in (compat as Dictionary).keys():
			var candidate := normalize_item_id(String(raw_id))
			if candidate == "":
				continue
			legacy_share.append(candidate)
	var ignore_groups := _normalize_string_array(LEGACY_IGNORE_COLLISION_GROUPS.get(normalized_id, []))
	return {
		"item_id": normalized_id,
		"placement_mode": placement_mode,
		"scene_path": scene_path,
		"repeat_place": repeat_place,
		"drag_paintable": drag_paintable,
		"can_share_tile_with": legacy_share,
		"can_share_set": _build_bool_set(legacy_share),
		"ignore_collision_groups_when_placing": ignore_groups,
	}


static func _get_itemdb_placement_data(normalized_id: String) -> Dictionary:
	if normalized_id == "":
		return {}
	if ItemDB == null or not ItemDB.has_method("get_placement_data"):
		return {}
	var raw: Variant = ItemDB.get_placement_data(normalized_id)
	if raw is Dictionary:
		return raw as Dictionary
	return {}


static func _normalize_item_id_array(raw: Variant) -> Array[String]:
	var normalized := _normalize_string_array(raw)
	for i in range(normalized.size()):
		normalized[i] = normalize_item_id(normalized[i])
	return normalized


static func _normalize_string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for value in raw:
		var item := String(value).strip_edges()
		if item == "":
			continue
		out.append(item)
	return out


static func _build_bool_set(items: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for item in items:
		var normalized := normalize_item_id(item)
		if normalized == "":
			continue
		out[normalized] = true
	return out
