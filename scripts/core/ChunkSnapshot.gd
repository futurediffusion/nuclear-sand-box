extends RefCounted
class_name ChunkSnapshot


## Canonical chunk-scoped save payload.
##
## Canonical chunk state in current architecture:
## - WorldSave chunk entity/flag state
## - WorldSave enemy state + enemy spawn definitions
## - Building/structure state (player walls normalized as structures)
## - Chunk-owned placed entities + their per-uid persisted data
##
## Derived / non-canonical and intentionally excluded:
## - chunk streaming queues/caches/perf windows
## - tilemap paint buffers and terrain-connect cache
## - collider cache/index/projection runtime artifacts

var chunk_key: String = ""
var chunk_pos: Vector2i = Vector2i.ZERO

var entities: Dictionary = {}
var flags: Dictionary = {}
var enemy_state: Dictionary = {}
var enemy_spawns: Array[Dictionary] = []

var structures: Array[StructureSnapshot] = []
var placed_entities: Array[Dictionary] = []
var placed_entity_data_by_uid: Dictionary = {}

static func from_dict(data: Dictionary) -> ChunkSnapshot:
	var snapshot := ChunkSnapshot.new()
	snapshot.chunk_key = String(data.get("chunk_key", ""))
	var chunk_pos_raw: Variant = data.get("chunk_pos", Vector2i.ZERO)
	if chunk_pos_raw is Vector2i:
		snapshot.chunk_pos = chunk_pos_raw
	elif chunk_pos_raw is String:
		var parsed: Variant = str_to_var(chunk_pos_raw)
		snapshot.chunk_pos = parsed if parsed is Vector2i else Vector2i.ZERO
	else:
		snapshot.chunk_pos = Vector2i.ZERO

	var entities_raw: Variant = data.get("entities", {})
	if entities_raw is Dictionary:
		snapshot.entities = (entities_raw as Dictionary).duplicate(true)

	var flags_raw: Variant = data.get("flags", {})
	if flags_raw is Dictionary:
		snapshot.flags = (flags_raw as Dictionary).duplicate(true)

	var enemy_state_raw: Variant = data.get("enemy_state", {})
	if enemy_state_raw is Dictionary:
		snapshot.enemy_state = (enemy_state_raw as Dictionary).duplicate(true)

	var enemy_spawns_raw: Variant = data.get("enemy_spawns", [])
	if enemy_spawns_raw is Array:
		for spawn in enemy_spawns_raw:
			if spawn is Dictionary:
				snapshot.enemy_spawns.append((spawn as Dictionary).duplicate(true))

	var structures_raw: Variant = data.get("structures", [])
	if structures_raw is Array:
		for entry in structures_raw:
			if entry is Dictionary:
				snapshot.structures.append(StructureSnapshot.from_dict(entry as Dictionary))

	var placed_entities_raw: Variant = data.get("placed_entities", [])
	if placed_entities_raw is Array:
		for entry in placed_entities_raw:
			if entry is Dictionary:
				snapshot.placed_entities.append((entry as Dictionary).duplicate(true))

	var placed_data_raw: Variant = data.get("placed_entity_data_by_uid", {})
	if placed_data_raw is Dictionary:
		for uid_raw in (placed_data_raw as Dictionary).keys():
			var uid: String = String(uid_raw)
			var value: Variant = placed_data_raw[uid_raw]
			if value is Dictionary:
				snapshot.placed_entity_data_by_uid[uid] = (value as Dictionary).duplicate(true)

	return snapshot

func to_dict() -> Dictionary:
	var serialized_structures: Array[Dictionary] = []
	for entry: StructureSnapshot in structures:
		if entry == null:
			continue
		serialized_structures.append(entry.to_dict())

	var serialized_enemy_spawns: Array[Dictionary] = []
	for spawn: Dictionary in enemy_spawns:
		serialized_enemy_spawns.append(spawn.duplicate(true))

	var serialized_placed_entities: Array[Dictionary] = []
	for entry: Dictionary in placed_entities:
		serialized_placed_entities.append(entry.duplicate(true))

	var serialized_placed_data: Dictionary = {}
	for uid: String in placed_entity_data_by_uid.keys():
		var payload: Variant = placed_entity_data_by_uid[uid]
		if payload is Dictionary:
			serialized_placed_data[uid] = (payload as Dictionary).duplicate(true)

	return {
		"chunk_key": chunk_key,
		"chunk_pos": chunk_pos,
		"entities": entities.duplicate(true),
		"flags": flags.duplicate(true),
		"enemy_state": enemy_state.duplicate(true),
		"enemy_spawns": serialized_enemy_spawns,
		"structures": serialized_structures,
		"placed_entities": serialized_placed_entities,
		"placed_entity_data_by_uid": serialized_placed_data,
	}
