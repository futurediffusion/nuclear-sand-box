extends RefCounted
class_name BuildingState

## Building domain state container.
##
## This module intentionally stores structure/wall state in plain Dictionaries so
## it can stay independent from nodes/tilemaps. The same canonical record shape
## is used for player walls and future structure types.
##
## Indexing strategy (minimal but efficient for current needs):
## - by id/key: O(1)
## - by tile position: O(1)
## - by chunk: O(k) where k = structures in chunk

const KEY_VERSION := "version"
const KEY_STRUCTURES_BY_ID := "structures_by_id"
const KEY_STRUCTURE_ID_BY_TILE := "structure_id_by_tile"
const KEY_STRUCTURE_IDS_BY_CHUNK := "structure_ids_by_chunk"

const STRUCTURE_KEY_ID := "structure_id"
const STRUCTURE_KEY_CHUNK_POS := "chunk_pos"
const STRUCTURE_KEY_TILE_POS := "tile_pos"
const STRUCTURE_KEY_KIND := "kind"
const STRUCTURE_KEY_HP := "hp"
const STRUCTURE_KEY_MAX_HP := "max_hp"
const STRUCTURE_KEY_METADATA := "metadata"

## Metadata keys used by current player wall behavior and migration tasks.
const METADATA_KEY_IS_PLAYER_WALL := "is_player_wall"
const METADATA_KEY_DROP_ENABLED := "drop_enabled"
const METADATA_KEY_DROP_ITEM_ID := "drop_item_id"
const METADATA_KEY_DROP_AMOUNT := "drop_amount"
const METADATA_KEY_SOURCE := "source"

static func create_empty() -> Dictionary:
	return {
		KEY_VERSION: 2,
		KEY_STRUCTURES_BY_ID: {},
		KEY_STRUCTURE_ID_BY_TILE: {},
		KEY_STRUCTURE_IDS_BY_CHUNK: {},
	}

static func create_player_wall_metadata(
		drop_enabled: bool,
		drop_item_id: String,
		drop_amount: int,
		source: String = "player"
	) -> Dictionary:
	return {
		METADATA_KEY_IS_PLAYER_WALL: true,
		METADATA_KEY_DROP_ENABLED: drop_enabled,
		METADATA_KEY_DROP_ITEM_ID: drop_item_id,
		METADATA_KEY_DROP_AMOUNT: maxi(0, drop_amount),
		METADATA_KEY_SOURCE: source,
	}

static func build_structure_key(kind: String, chunk_pos: Vector2i, tile_pos: Vector2i) -> String:
	## Deterministic fallback key when a caller does not have an external uid.
	return "%s:%d:%d:%d:%d" % [kind, chunk_pos.x, chunk_pos.y, tile_pos.x, tile_pos.y]

static func create_structure_record(
		structure_id: String,
		chunk_pos: Vector2i,
		tile_pos: Vector2i,
		kind: String,
		hp: int,
		max_hp: int,
		metadata: Dictionary = {}
	) -> Dictionary:
	var normalized_kind := kind.strip_edges()
	if normalized_kind.is_empty():
		normalized_kind = "unknown"
	var normalized_id := structure_id.strip_edges()
	if normalized_id.is_empty():
		normalized_id = build_structure_key(normalized_kind, chunk_pos, tile_pos)
	var resolved_max_hp := maxi(1, max_hp)
	return {
		STRUCTURE_KEY_ID: normalized_id,
		STRUCTURE_KEY_CHUNK_POS: chunk_pos,
		STRUCTURE_KEY_TILE_POS: tile_pos,
		STRUCTURE_KEY_KIND: normalized_kind,
		STRUCTURE_KEY_HP: clampi(hp, 0, resolved_max_hp),
		STRUCTURE_KEY_MAX_HP: resolved_max_hp,
		STRUCTURE_KEY_METADATA: metadata.duplicate(true),
	}

static func has_structure(state: Dictionary, structure_id: String) -> bool:
	return get_structures_by_id(state).has(structure_id)

static func get_structure(state: Dictionary, structure_id: String) -> Dictionary:
	return get_structures_by_id(state).get(structure_id, {}) as Dictionary

static func has_structure_at_tile(state: Dictionary, tile_pos: Vector2i) -> bool:
	return get_structure_id_by_tile(state).has(tile_pos)

static func get_structure_id_at_tile(state: Dictionary, tile_pos: Vector2i) -> String:
	return String(get_structure_id_by_tile(state).get(tile_pos, ""))

static func get_structure_at_tile(state: Dictionary, tile_pos: Vector2i) -> Dictionary:
	var structure_id := get_structure_id_at_tile(state, tile_pos)
	if structure_id.is_empty():
		return {}
	return get_structure(state, structure_id)

static func has_structures_in_chunk(state: Dictionary, chunk_pos: Vector2i) -> bool:
	return get_structure_ids_by_chunk(state).has(chunk_pos)

static func get_structure_ids_in_chunk(state: Dictionary, chunk_pos: Vector2i) -> Array[String]:
	var ids_bucket: Dictionary = get_structure_ids_by_chunk(state).get(chunk_pos, {}) as Dictionary
	var ids: Array[String] = []
	for key in ids_bucket.keys():
		ids.append(String(key))
	return ids

static func get_structures_in_chunk(state: Dictionary, chunk_pos: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for structure_id in get_structure_ids_in_chunk(state, chunk_pos):
		var structure := get_structure(state, structure_id)
		if not structure.is_empty():
			out.append(structure)
	return out

static func upsert_structure(state: Dictionary, structure: Dictionary) -> Dictionary:
	## Remove the previous indexed location when replacing an existing record.
	var structure_id := String(structure.get(STRUCTURE_KEY_ID, ""))
	if structure_id.is_empty():
		return {}
	if has_structure(state, structure_id):
		var previous := get_structure(state, structure_id)
		_unindex_structure(state, previous)

	var structures_by_id := get_structures_by_id(state)
	structures_by_id[structure_id] = structure.duplicate(true)
	_index_structure(state, structure)
	return get_structure(state, structure_id)

static func remove_structure(state: Dictionary, structure_id: String) -> Dictionary:
	if not has_structure(state, structure_id):
		return {}
	var removed := get_structure(state, structure_id)
	_unindex_structure(state, removed)
	get_structures_by_id(state).erase(structure_id)
	return removed

static func remove_structure_at_tile(state: Dictionary, tile_pos: Vector2i) -> Dictionary:
	var structure_id := get_structure_id_at_tile(state, tile_pos)
	if structure_id.is_empty():
		return {}
	return remove_structure(state, structure_id)

static func apply_damage_by_id(state: Dictionary, structure_id: String, amount: int) -> Dictionary:
	if amount <= 0:
		return {}
	var structure := get_structure(state, structure_id)
	if structure.is_empty():
		return {}
	structure[STRUCTURE_KEY_HP] = maxi(0, int(structure.get(STRUCTURE_KEY_HP, 0)) - amount)
	return upsert_structure(state, structure)

static func apply_damage_at_tile(state: Dictionary, tile_pos: Vector2i, amount: int) -> Dictionary:
	var structure_id := get_structure_id_at_tile(state, tile_pos)
	if structure_id.is_empty():
		return {}
	return apply_damage_by_id(state, structure_id, amount)

static func get_structures_by_id(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	if not state.has(KEY_STRUCTURES_BY_ID):
		state[KEY_STRUCTURES_BY_ID] = {}
	return state.get(KEY_STRUCTURES_BY_ID, {}) as Dictionary

static func get_structure_id_by_tile(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	if not state.has(KEY_STRUCTURE_ID_BY_TILE):
		state[KEY_STRUCTURE_ID_BY_TILE] = {}
	return state.get(KEY_STRUCTURE_ID_BY_TILE, {}) as Dictionary

static func get_structure_ids_by_chunk(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	if not state.has(KEY_STRUCTURE_IDS_BY_CHUNK):
		state[KEY_STRUCTURE_IDS_BY_CHUNK] = {}
	return state.get(KEY_STRUCTURE_IDS_BY_CHUNK, {}) as Dictionary

static func _index_structure(state: Dictionary, structure: Dictionary) -> void:
	var structure_id := String(structure.get(STRUCTURE_KEY_ID, ""))
	var tile_pos: Vector2i = structure.get(STRUCTURE_KEY_TILE_POS, Vector2i.ZERO)
	var chunk_pos: Vector2i = structure.get(STRUCTURE_KEY_CHUNK_POS, Vector2i.ZERO)
	if structure_id.is_empty() or not (tile_pos is Vector2i) or not (chunk_pos is Vector2i):
		return
	get_structure_id_by_tile(state)[tile_pos] = structure_id
	var per_chunk := get_structure_ids_by_chunk(state)
	if not per_chunk.has(chunk_pos):
		per_chunk[chunk_pos] = {}
	(per_chunk[chunk_pos] as Dictionary)[structure_id] = true

static func _unindex_structure(state: Dictionary, structure: Dictionary) -> void:
	var structure_id := String(structure.get(STRUCTURE_KEY_ID, ""))
	var tile_pos: Vector2i = structure.get(STRUCTURE_KEY_TILE_POS, Vector2i.ZERO)
	var chunk_pos: Vector2i = structure.get(STRUCTURE_KEY_CHUNK_POS, Vector2i.ZERO)
	if structure_id.is_empty():
		return
	if tile_pos is Vector2i:
		get_structure_id_by_tile(state).erase(tile_pos)
	if chunk_pos is Vector2i:
		var per_chunk := get_structure_ids_by_chunk(state)
		if per_chunk.has(chunk_pos):
			var bucket := per_chunk[chunk_pos] as Dictionary
			bucket.erase(structure_id)
			if bucket.is_empty():
				per_chunk.erase(chunk_pos)
