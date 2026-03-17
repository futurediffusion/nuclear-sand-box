extends RefCounted
class_name BuildableCatalog

## Taxonomía común de buildables (fase 4).
## Mantiene compatibilidad con ids runtime existentes.

const ID_WALLWOOD: String = "wallwood"
const ID_DOORWOOD: String = "doorwood"
const ID_WOODFLOOR: String = "woodfloor"
const ID_CHEST: String = "chest"
const ID_BARREL: String = "barrel"
const ID_TABLE: String = "table"
const ID_STOOL: String = "stool"
const ID_WORKBENCH: String = "workbench"

const CATEGORY_TILE_WALL_PLAYER: String = "tile_wall_player"
const CATEGORY_TILE_WALL_STRUCTURAL: String = "tile_wall_structural"
const CATEGORY_ENTITY_PLACEABLE: String = "entity_placeable"

const _BUILDABLE_CATEGORY_BY_ID: Dictionary = {
	ID_WALLWOOD: CATEGORY_TILE_WALL_PLAYER,
	ID_DOORWOOD: CATEGORY_ENTITY_PLACEABLE,
	ID_WOODFLOOR: CATEGORY_ENTITY_PLACEABLE,
	ID_CHEST: CATEGORY_ENTITY_PLACEABLE,
	ID_BARREL: CATEGORY_ENTITY_PLACEABLE,
	ID_TABLE: CATEGORY_ENTITY_PLACEABLE,
	ID_STOOL: CATEGORY_ENTITY_PLACEABLE,
	ID_WORKBENCH: CATEGORY_ENTITY_PLACEABLE,
}

const _ID_ALIASES: Dictionary = {
	"floorwood": ID_WOODFLOOR,
}

const _RUNTIME_ITEM_BY_BUILDABLE_ID: Dictionary = {
	ID_WOODFLOOR: "floorwood",
}

static func normalize_buildable_id(raw_id: String) -> String:
	var normalized := raw_id.strip_edges()
	if normalized == "":
		return ""
	if _ID_ALIASES.has(normalized):
		return String(_ID_ALIASES[normalized])
	return normalized

static func has_buildable(raw_id: String) -> bool:
	return _BUILDABLE_CATEGORY_BY_ID.has(normalize_buildable_id(raw_id))

static func category_for_item_id(raw_id: String) -> String:
	return String(_BUILDABLE_CATEGORY_BY_ID.get(normalize_buildable_id(raw_id), ""))

static func is_category(raw_id: String, category: String) -> bool:
	return category_for_item_id(raw_id) == category

static func resolve_runtime_item_id(raw_id: String) -> String:
	var buildable_id := normalize_buildable_id(raw_id)
	if buildable_id == "":
		return ""
	return String(_RUNTIME_ITEM_BY_BUILDABLE_ID.get(buildable_id, buildable_id))

static func resolve_drop_item_id(requested_item_id: String, fallback_buildable_id: String) -> String:
	var requested := requested_item_id.strip_edges()
	if requested != "":
		return requested
	return resolve_runtime_item_id(fallback_buildable_id)

static func classify_wall_tile(is_player_wall: bool, is_structural_wall: bool) -> String:
	if is_player_wall:
		return CATEGORY_TILE_WALL_PLAYER
	if is_structural_wall:
		return CATEGORY_TILE_WALL_STRUCTURAL
	return ""
