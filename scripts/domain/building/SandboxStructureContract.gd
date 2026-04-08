extends RefCounted
class_name SandboxStructureContract

## Canonical contract for sandbox-owned structure-like objects.
##
## Goal (incremental): provide one shared record language for player walls,
## structural walls, and placeable/buildable entities while keeping current
## persistence stores unchanged.

const KIND_PLAYER_WALL: String = "player_wall"
const KIND_STRUCTURAL_WALL: String = "structural_wall"
const KIND_PLACEABLE: String = "placeable"

const OWNER_PLAYER: String = "player"
const OWNER_SANDBOX: String = "sandbox"

const KEY_STRUCTURE_ID: String = "structure_id"
const KEY_KIND: String = "kind"
const KEY_OWNER: String = "owner"
const KEY_CHUNK_POS: String = "chunk_pos"
const KEY_TILE_POS: String = "tile_pos"
const KEY_HP: String = "hp"
const KEY_MAX_HP: String = "max_hp"
const KEY_METADATA: String = "metadata"
const KEY_PERSISTENCE_BUCKET: String = "persistence_bucket"

const BUCKET_PLAYER_WALLS: String = "player_walls_by_chunk"
const BUCKET_STRUCTURAL_TILES: String = "chunk_save.placed_tiles"
const BUCKET_PLACED_ENTITIES: String = "placed_entities_by_chunk"

const METADATA_KEY_UID: String = "uid"
const METADATA_KEY_ITEM_ID: String = "item_id"
const METADATA_KEY_WALL_SOURCE: String = "wall_source"
const METADATA_KEY_BREAKABLE: String = "breakable"

static func build_structure_id(kind: String, chunk_pos: Vector2i, tile_pos: Vector2i) -> String:
	var normalized_kind: String = kind.strip_edges()
	if normalized_kind == "":
		normalized_kind = "unknown"
	return "%s:%d:%d:%d:%d" % [normalized_kind, chunk_pos.x, chunk_pos.y, tile_pos.x, tile_pos.y]

static func create_record(kind: String,
		owner: String,
		chunk_pos: Vector2i,
		tile_pos: Vector2i,
		hp: int,
		max_hp: int,
		metadata: Dictionary = {},
		persistence_bucket: String = "",
		structure_id: String = "") -> Dictionary:
	var normalized_max_hp: int = maxi(1, max_hp)
	var normalized_hp: int = clampi(hp, 0, normalized_max_hp)
	var resolved_id: String = structure_id.strip_edges()
	if resolved_id == "":
		resolved_id = build_structure_id(kind, chunk_pos, tile_pos)
	return {
		KEY_STRUCTURE_ID: resolved_id,
		KEY_KIND: kind.strip_edges(),
		KEY_OWNER: owner.strip_edges(),
		KEY_CHUNK_POS: chunk_pos,
		KEY_TILE_POS: tile_pos,
		KEY_HP: normalized_hp,
		KEY_MAX_HP: normalized_max_hp,
		KEY_METADATA: metadata.duplicate(true),
		KEY_PERSISTENCE_BUCKET: persistence_bucket.strip_edges(),
	}

static func create_player_wall_record(chunk_pos: Vector2i, tile_pos: Vector2i, hp: int,
		metadata: Dictionary = {}, max_hp: int = -1) -> Dictionary:
	var resolved_max_hp: int = hp if max_hp <= 0 else max_hp
	return create_record(
		KIND_PLAYER_WALL,
		OWNER_PLAYER,
		chunk_pos,
		tile_pos,
		hp,
		resolved_max_hp,
		metadata,
		BUCKET_PLAYER_WALLS
	)

static func create_structural_wall_record(chunk_pos: Vector2i, tile_pos: Vector2i, hp: int,
		wall_source: int,
		metadata: Dictionary = {},
		max_hp: int = -1) -> Dictionary:
	var next_metadata: Dictionary = metadata.duplicate(true)
	next_metadata[METADATA_KEY_WALL_SOURCE] = wall_source
	var resolved_max_hp: int = hp if max_hp <= 0 else max_hp
	return create_record(
		KIND_STRUCTURAL_WALL,
		OWNER_SANDBOX,
		chunk_pos,
		tile_pos,
		hp,
		resolved_max_hp,
		next_metadata,
		BUCKET_STRUCTURAL_TILES
	)

static func create_placeable_record(chunk_pos: Vector2i, tile_pos: Vector2i, uid: String,
		item_id: String, hp: int = 1, max_hp: int = 1, metadata: Dictionary = {}) -> Dictionary:
	var next_metadata: Dictionary = metadata.duplicate(true)
	next_metadata[METADATA_KEY_UID] = uid.strip_edges()
	next_metadata[METADATA_KEY_ITEM_ID] = item_id.strip_edges()
	if not next_metadata.has(METADATA_KEY_BREAKABLE):
		next_metadata[METADATA_KEY_BREAKABLE] = true
	return create_record(
		KIND_PLACEABLE,
		OWNER_PLAYER,
		chunk_pos,
		tile_pos,
		hp,
		max_hp,
		next_metadata,
		BUCKET_PLACED_ENTITIES,
		uid.strip_edges()
	)

static func to_legacy_player_wall_payload(structure: Dictionary) -> Dictionary:
	var hp: int = int(structure.get(KEY_HP, 0))
	if hp <= 0:
		return {}
	return {"hp": hp}
