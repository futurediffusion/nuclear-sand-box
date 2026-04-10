extends RefCounted
class_name ChunkSnapshotSerializer


const PLAYER_WALL_KIND: String = "player_wall"
const PLAYER_WALL_HP_KEY: String = "hp"

## Converts canonical chunk/domain dictionaries into a ChunkSnapshot DTO.
## Input keys (all optional except chunk identity):
## - chunk_key: String
## - chunk_pos: Vector2i
## - entities: Dictionary
## - flags: Dictionary
## - enemy_state: Dictionary
## - enemy_spawns: Array[Dictionary]
## - structures: Array[Dictionary|StructureSnapshot]
## - placed_entities: Array[Dictionary]
## - placed_entity_data_by_uid: Dictionary (uid -> Dictionary)
static func serialize_canonical_chunk(canonical_chunk: Dictionary) -> ChunkSnapshot:
	var snapshot := ChunkSnapshot.new()
	snapshot.chunk_key = String(canonical_chunk.get("chunk_key", "")).strip_edges()
	var chunk_pos_raw: Variant = canonical_chunk.get("chunk_pos", null)
	if chunk_pos_raw is Vector2i:
		snapshot.chunk_pos = chunk_pos_raw as Vector2i
	elif not snapshot.chunk_key.is_empty():
		snapshot.chunk_pos = WorldSave.chunk_pos_from_key(snapshot.chunk_key)

	if snapshot.chunk_key.is_empty() and snapshot.chunk_pos != WorldSave.INVALID_CHUNK_POS:
		snapshot.chunk_key = WorldSave.chunk_key_from_pos(snapshot.chunk_pos)

	snapshot.entities = _dict_dup(canonical_chunk.get("entities", {}))
	snapshot.flags = _dict_dup(canonical_chunk.get("flags", {}))
	snapshot.enemy_state = _dict_dup(canonical_chunk.get("enemy_state", {}))
	snapshot.enemy_spawns = _dict_array_dup(canonical_chunk.get("enemy_spawns", []))
	snapshot.structures = _deserialize_structures(canonical_chunk.get("structures", []))
	snapshot.placed_entities = _dict_array_dup(canonical_chunk.get("placed_entities", []))
	snapshot.placed_entity_data_by_uid = _dict_dict_dup(canonical_chunk.get("placed_entity_data_by_uid", {}))
	return snapshot

## Reads canonical chunk-owned state directly from WorldSave stores (not from
## runtime tilemaps/colliders/indices) and produces a canonical snapshot DTO.
static func serialize_chunk_from_worldsave(chunk_key: String) -> ChunkSnapshot:
	var key: String = String(chunk_key).strip_edges()
	var chunk_pos: Vector2i = WorldSave.chunk_pos_from_key(key)
	if chunk_pos == WorldSave.INVALID_CHUNK_POS:
		return ChunkSnapshot.new()

	var chunk_save: Dictionary = WorldSave.get_chunk_save(chunk_pos.x, chunk_pos.y)
	var structures: Array[StructureSnapshot] = _structures_from_player_walls(key, chunk_pos)

	var placed_entities: Array[Dictionary] = []
	if WorldSave.placed_entities_by_chunk.has(key):
		var chunk_entities_raw: Variant = WorldSave.placed_entities_by_chunk.get(key, {})
		if chunk_entities_raw is Dictionary:
			for uid in (chunk_entities_raw as Dictionary).keys():
				var entry_raw: Variant = (chunk_entities_raw as Dictionary).get(uid, {})
				if entry_raw is Dictionary:
					placed_entities.append((entry_raw as Dictionary).duplicate(true))

	var placed_data_by_uid: Dictionary = {}
	for entry in placed_entities:
		var uid: String = String(entry.get("uid", "")).strip_edges()
		if uid.is_empty():
			continue
		if not WorldSave.placed_entity_data_by_uid.has(uid):
			continue
		var payload_raw: Variant = WorldSave.placed_entity_data_by_uid.get(uid, {})
		if payload_raw is Dictionary:
			placed_data_by_uid[uid] = (payload_raw as Dictionary).duplicate(true)

	return serialize_canonical_chunk({
		"chunk_key": key,
		"chunk_pos": chunk_pos,
		"entities": _dict_dup(chunk_save.get("entities", {})),
		"flags": _dict_dup(chunk_save.get("flags", {})),
		"enemy_state": _dict_dup(WorldSave.enemy_state_by_chunk.get(key, {})),
		"enemy_spawns": _dict_array_dup(WorldSave.enemy_spawns_by_chunk.get(key, [])),
		"structures": structures,
		"placed_entities": placed_entities,
		"placed_entity_data_by_uid": placed_data_by_uid,
	})

## Converts a ChunkSnapshot back into canonical chunk-domain dictionaries.
## Returned format matches serialize_canonical_chunk input.
static func deserialize_chunk_snapshot(snapshot: ChunkSnapshot) -> Dictionary:
	if snapshot == null:
		return {}

	var chunk_key: String = String(snapshot.chunk_key).strip_edges()
	var chunk_pos: Vector2i = snapshot.chunk_pos
	if chunk_key.is_empty() and chunk_pos != WorldSave.INVALID_CHUNK_POS:
		chunk_key = WorldSave.chunk_key_from_pos(chunk_pos)
	if chunk_pos == WorldSave.INVALID_CHUNK_POS and not chunk_key.is_empty():
		chunk_pos = WorldSave.chunk_pos_from_key(chunk_key)

	return {
		"chunk_key": chunk_key,
		"chunk_pos": chunk_pos,
		"entities": snapshot.entities.duplicate(true),
		"flags": snapshot.flags.duplicate(true),
		"enemy_state": snapshot.enemy_state.duplicate(true),
		"enemy_spawns": _dict_array_dup(snapshot.enemy_spawns),
		"structures": _serialize_structures(snapshot.structures),
		"placed_entities": _dict_array_dup(snapshot.placed_entities),
		"placed_entity_data_by_uid": _dict_dict_dup(snapshot.placed_entity_data_by_uid),
	}

## Applies snapshot data to the canonical WorldSave chunk stores only.
## This does not rebuild any projection/runtime scene state.
static func apply_snapshot_to_worldsave(snapshot: ChunkSnapshot) -> void:
	var canonical: Dictionary = deserialize_chunk_snapshot(snapshot)
	var key: String = String(canonical.get("chunk_key", "")).strip_edges()
	var chunk_pos_raw: Variant = canonical.get("chunk_pos", WorldSave.INVALID_CHUNK_POS)
	if key.is_empty() or not (chunk_pos_raw is Vector2i):
		return
	var chunk_pos: Vector2i = chunk_pos_raw as Vector2i
	if chunk_pos == WorldSave.INVALID_CHUNK_POS:
		return

	WorldSave.chunks[key] = {
		"entities": _dict_dup(canonical.get("entities", {})),
		"flags": _dict_dup(canonical.get("flags", {})),
	}
	WorldSave.enemy_state_by_chunk[key] = _dict_dup(canonical.get("enemy_state", {}))
	WorldSave.enemy_spawns_by_chunk[key] = _dict_array_dup(canonical.get("enemy_spawns", []))

	_apply_snapshot_structures(key, chunk_pos, canonical.get("structures", []))
	_apply_snapshot_placed_entities(key, canonical.get("placed_entities", []), canonical.get("placed_entity_data_by_uid", {}))

static func _deserialize_structures(raw_value: Variant) -> Array[StructureSnapshot]:
	var out: Array[StructureSnapshot] = []
	if raw_value is Array:
		for entry in raw_value:
			if entry is StructureSnapshot:
				out.append(entry as StructureSnapshot)
			elif entry is Dictionary:
				out.append(StructureSnapshot.from_dict(entry as Dictionary))
	return out

static func _serialize_structures(structures: Array[StructureSnapshot]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for structure in structures:
		if structure == null:
			continue
		out.append((structure as StructureSnapshot).to_dict())
	return out

static func _structures_from_player_walls(chunk_key: String, chunk_pos: Vector2i) -> Array[StructureSnapshot]:
	var out: Array[StructureSnapshot] = []
	var raw_chunk: Variant = WorldSave.player_walls_by_chunk.get(chunk_key, {})
	if not (raw_chunk is Dictionary):
		return out
	for tile_key_raw in (raw_chunk as Dictionary).keys():
		var tile_pos: Vector2i = _tile_pos_from_key(String(tile_key_raw))
		if tile_pos.x <= -999999:
			continue
		var wall_raw: Variant = (raw_chunk as Dictionary).get(tile_key_raw, {})
		if not (wall_raw is Dictionary):
			continue
		var hp: int = int((wall_raw as Dictionary).get(PLAYER_WALL_HP_KEY, 0))
		if hp <= 0:
			continue
		var structure := StructureSnapshot.new()
		structure.kind = PLAYER_WALL_KIND
		structure.chunk_pos = chunk_pos
		structure.tile_pos = tile_pos
		structure.hp = hp
		structure.max_hp = hp
		structure.metadata = {
			"blocks_movement": true,
			"tile_source": "wallwood",
			"tile_atlas": 1,
		}
		structure.structure_id = "%s:%d:%d:%d:%d" % [
			PLAYER_WALL_KIND,
			chunk_pos.x,
			chunk_pos.y,
			tile_pos.x,
			tile_pos.y,
		]
		out.append(structure)
	return out

static func _apply_snapshot_structures(chunk_key: String, chunk_pos: Vector2i, structures_raw: Variant) -> void:
	var next_chunk_walls: Dictionary = {}
	var structures: Array[StructureSnapshot] = _deserialize_structures(structures_raw)
	for structure in structures:
		if structure == null:
			continue
		if String(structure.kind) != PLAYER_WALL_KIND:
			continue
		if structure.chunk_pos != chunk_pos:
			continue
		if structure.hp <= 0:
			continue
		next_chunk_walls[_tile_key_from_pos(structure.tile_pos)] = {PLAYER_WALL_HP_KEY: int(structure.hp)}
	if next_chunk_walls.is_empty():
		WorldSave.player_walls_by_chunk.erase(chunk_key)
	else:
		WorldSave.player_walls_by_chunk[chunk_key] = next_chunk_walls

static func _apply_snapshot_placed_entities(chunk_key: String, placed_entities_raw: Variant, placed_data_raw: Variant) -> void:
	if WorldSave.placed_entities_by_chunk.has(chunk_key):
		var prev_chunk_raw: Variant = WorldSave.placed_entities_by_chunk[chunk_key]
		if prev_chunk_raw is Dictionary:
			for uid in (prev_chunk_raw as Dictionary).keys():
				WorldSave.placed_entity_chunk_by_uid.erase(String(uid))

	var next_chunk_entities: Dictionary = {}
	if placed_entities_raw is Array:
		for entry in placed_entities_raw:
			if not (entry is Dictionary):
				continue
			var copied: Dictionary = (entry as Dictionary).duplicate(true)
			copied["chunk_key"] = chunk_key
			var uid: String = String(copied.get("uid", "")).strip_edges()
			if uid.is_empty():
				continue
			next_chunk_entities[uid] = copied
			WorldSave.placed_entity_chunk_by_uid[uid] = chunk_key

	if next_chunk_entities.is_empty():
		WorldSave.placed_entities_by_chunk.erase(chunk_key)
	else:
		WorldSave.placed_entities_by_chunk[chunk_key] = next_chunk_entities

	if placed_data_raw is Dictionary:
		for uid_raw in (placed_data_raw as Dictionary).keys():
			var uid: String = String(uid_raw).strip_edges()
			if uid.is_empty():
				continue
			if not next_chunk_entities.has(uid):
				continue
			var payload_raw: Variant = (placed_data_raw as Dictionary).get(uid_raw, {})
			if payload_raw is Dictionary:
				WorldSave.placed_entity_data_by_uid[uid] = (payload_raw as Dictionary).duplicate(true)

static func _dict_dup(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

static func _dict_dict_dup(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for key_raw in (value as Dictionary).keys():
		var payload_raw: Variant = (value as Dictionary).get(key_raw, {})
		if payload_raw is Dictionary:
			out[String(key_raw)] = (payload_raw as Dictionary).duplicate(true)
	return out

static func _dict_array_dup(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array):
		return out
	for entry in value:
		if entry is Dictionary:
			out.append((entry as Dictionary).duplicate(true))
	return out

static func _tile_key_from_pos(tile_pos: Vector2i) -> String:
	return "%d,%d" % [tile_pos.x, tile_pos.y]

static func _tile_pos_from_key(tile_key: String) -> Vector2i:
	var parts: PackedStringArray = tile_key.split(",")
	if parts.size() != 2:
		return Vector2i(-999999, -999999)
	return Vector2i(int(parts[0]), int(parts[1]))
