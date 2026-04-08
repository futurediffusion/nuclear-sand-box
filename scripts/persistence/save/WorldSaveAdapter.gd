extends RefCounted
class_name WorldSaveAdapter

const ChunkSnapshotSerializer := preload("res://scripts/persistence/save/ChunkSnapshotSerializer.gd")
const ChunkSnapshot := preload("res://scripts/core/ChunkSnapshot.gd")
const WorldSnapshot := preload("res://scripts/core/WorldSnapshot.gd")

const LEGACY_SNAPSHOT_STATE_KEY: String = "world_snapshot_state"

## Infrastructure adapter between canonical chunk snapshots and WorldSave.
##
## Canonical side:
## - chunk snapshots (ChunkSnapshot)
## - world snapshot root (WorldSnapshot)
##
## This adapter intentionally does not own or infer gameplay/domain truth.

static func save_chunk_snapshot(snapshot: ChunkSnapshot) -> void:
	if snapshot == null:
		return
	ChunkSnapshotSerializer.apply_snapshot_to_worldsave(snapshot)

static func load_chunk_snapshot(chunk_key: String) -> ChunkSnapshot:
	return ChunkSnapshotSerializer.serialize_chunk_from_worldsave(chunk_key)


static func load_canonical_chunk_state(chunk_pos: Vector2i) -> Dictionary:
	if chunk_pos == WorldSave.INVALID_CHUNK_POS:
		return {}
	var chunk_key: String = WorldSave.chunk_key_from_pos(chunk_pos)
	if chunk_key.is_empty():
		return {}
	var snapshot: ChunkSnapshot = load_chunk_snapshot(chunk_key)
	if snapshot == null:
		return {}
	return ChunkSnapshotSerializer.deserialize_chunk_snapshot(snapshot)

static func build_world_snapshot(canonical_state: Dictionary) -> WorldSnapshot:
	var snapshot := WorldSnapshot.new()
	snapshot.save_version = int(canonical_state.get("save_version", 1))
	snapshot.seed = int(canonical_state.get("seed", 0))
	snapshot.player_pos = canonical_state.get("player_pos", Vector2.ZERO)

	var player_inv_raw: Variant = canonical_state.get("player_inv", [])
	if player_inv_raw is Array:
		snapshot.player_inv = (player_inv_raw as Array).duplicate(true)
	else:
		snapshot.player_inv = []

	snapshot.player_gold = int(canonical_state.get("player_gold", 0))
	var run_clock_raw: Variant = canonical_state.get("run_clock", {})
	if run_clock_raw is Dictionary:
		snapshot.run_clock = (run_clock_raw as Dictionary).duplicate(true)
	var world_time_raw: Variant = canonical_state.get("world_time", {})
	if world_time_raw is Dictionary:
		snapshot.world_time = (world_time_raw as Dictionary).duplicate(true)

	snapshot.faction_system = _dict_copy(canonical_state.get("faction_system", {}))
	snapshot.site_system = _dict_copy(canonical_state.get("site_system", {}))
	snapshot.npc_profile_system = _dict_copy(canonical_state.get("npc_profile_system", {}))
	snapshot.bandit_group_memory = _dict_copy(canonical_state.get("bandit_group_memory", {}))
	snapshot.extortion_queue = canonical_state.get("extortion_queue", {})
	snapshot.faction_hostility = _dict_copy(canonical_state.get("faction_hostility", {}))

	for chunk_snapshot in _collect_chunk_snapshots():
		snapshot.chunks.append(chunk_snapshot)
	snapshot.global_flags = WorldSave.global_flags.duplicate(true)
	return snapshot

static func apply_world_snapshot(snapshot: WorldSnapshot) -> bool:
	if snapshot == null:
		return false
	_clear_worldsave_chunk_state()
	for chunk_snapshot in snapshot.chunks:
		if chunk_snapshot == null:
			continue
		save_chunk_snapshot(chunk_snapshot)
	WorldSave.global_flags = snapshot.global_flags.duplicate(true)
	return true

## One-way migration adapter from legacy payload sections to canonical snapshot.
## Returned keys:
## - "snapshot": WorldSnapshot (always non-null)
## - "legacy_migration_used": bool
## - "legacy_source": String
static func migrate_legacy_payload_to_world_snapshot(payload: Dictionary) -> Dictionary:
	var canonical_state: Dictionary = {
		"save_version": int(payload.get("version", payload.get("save_version", 1))),
		"seed": int(payload.get("seed", 0)),
		"player_pos": payload.get("player_pos", Vector2.ZERO),
		"player_inv": payload.get("player_inv", []),
		"player_gold": int(payload.get("player_gold", 0)),
		"faction_system": _dict_copy(payload.get("faction_system", {})),
		"site_system": _dict_copy(payload.get("site_system", {})),
		"npc_profile_system": _dict_copy(payload.get("npc_profile_system", {})),
		"bandit_group_memory": _dict_copy(payload.get("bandit_group_memory", {})),
		"extortion_queue": payload.get("extortion_queue", {}),
		"run_clock": _dict_copy(payload.get("run_clock", {})),
		"world_time": _dict_copy(payload.get("world_time", {})),
		"faction_hostility": _dict_copy(payload.get("faction_hostility", {})),
	}

	var legacy_source: String = "none"
	_clear_worldsave_chunk_state()

	var snapshot_state_raw: Variant = payload.get(LEGACY_SNAPSHOT_STATE_KEY, null)
	if snapshot_state_raw is Dictionary:
		var state := snapshot_state_raw as Dictionary
		var chunks_raw: Variant = state.get("chunks", [])
		if chunks_raw is Array:
			_apply_chunk_snapshots(chunks_raw as Array)
			legacy_source = "world_snapshot_state"
		var global_flags_raw: Variant = state.get("global_flags", {})
		if global_flags_raw is Dictionary:
			WorldSave.global_flags = (global_flags_raw as Dictionary).duplicate(true)

	var ws_chunks: Variant = payload.get("worldsave_chunks", null)
	if ws_chunks is Dictionary:
		WorldSave.chunks = (ws_chunks as Dictionary).duplicate(true)
		legacy_source = "worldsave_payload"
	var ws_enemy_state: Variant = payload.get("worldsave_enemy_state", null)
	if ws_enemy_state is Dictionary:
		WorldSave.enemy_state_by_chunk = (ws_enemy_state as Dictionary).duplicate(true)
		legacy_source = "worldsave_payload"
	var ws_enemy_spawns: Variant = payload.get("worldsave_enemy_spawns", null)
	if ws_enemy_spawns is Dictionary:
		WorldSave.enemy_spawns_by_chunk = (ws_enemy_spawns as Dictionary).duplicate(true)
		legacy_source = "worldsave_payload"
	var ws_global_flags: Variant = payload.get("worldsave_global_flags", null)
	if ws_global_flags is Dictionary:
		WorldSave.global_flags = (ws_global_flags as Dictionary).duplicate(true)
		legacy_source = "worldsave_payload"
	var ws_player_walls: Variant = payload.get("worldsave_player_walls", null)
	if ws_player_walls is Dictionary:
		WorldSave.player_walls_by_chunk = (ws_player_walls as Dictionary).duplicate(true)
		legacy_source = "worldsave_payload"

	var placed_chunk_raw: Variant = payload.get("placed_entities_by_chunk", null)
	if placed_chunk_raw is Dictionary and not (placed_chunk_raw as Dictionary).is_empty():
		_apply_legacy_placed_entities_by_chunk(placed_chunk_raw as Dictionary)
		if legacy_source == "none":
			legacy_source = "placed_entities_by_chunk"
	else:
		var placed_legacy_raw: Variant = payload.get("placed_entities", null)
		if placed_legacy_raw is Array and not (placed_legacy_raw as Array).is_empty():
			for entry in (placed_legacy_raw as Array):
				if entry is Dictionary:
					WorldSave.add_placed_entity((entry as Dictionary).duplicate(true))
			if legacy_source == "none":
				legacy_source = "placed_entities_array"

	var placed_data_raw: Variant = payload.get("placed_entity_data_by_uid", null)
	if placed_data_raw is Dictionary:
		for uid_raw in (placed_data_raw as Dictionary).keys():
			var uid: String = String(uid_raw).strip_edges()
			if uid.is_empty():
				continue
			var value_raw: Variant = (placed_data_raw as Dictionary).get(uid_raw, {})
			if value_raw is Dictionary:
				WorldSave.placed_entity_data_by_uid[uid] = (value_raw as Dictionary).duplicate(true)

	var snapshot: WorldSnapshot = build_world_snapshot(canonical_state)
	return {
		"snapshot": snapshot,
		"legacy_migration_used": legacy_source != "none",
		"legacy_source": legacy_source,
	}

static func _collect_chunk_snapshots() -> Array[ChunkSnapshot]:
	var out: Array[ChunkSnapshot] = []
	var seen: Dictionary = {}
	for chunk_key in _collect_worldsave_chunk_keys():
		var key: String = String(chunk_key).strip_edges()
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		var snapshot: ChunkSnapshot = ChunkSnapshotSerializer.serialize_chunk_from_worldsave(key)
		if snapshot == null:
			continue
		if String(snapshot.chunk_key).strip_edges().is_empty():
			continue
		out.append(snapshot)
	out.sort_custom(func(a: ChunkSnapshot, b: ChunkSnapshot) -> bool:
		return String(a.chunk_key) < String(b.chunk_key)
	)
	return out

static func _collect_worldsave_chunk_keys() -> Array[String]:
	var keys: Array[String] = []
	_append_dict_keys(keys, WorldSave.chunks)
	_append_dict_keys(keys, WorldSave.enemy_state_by_chunk)
	_append_dict_keys(keys, WorldSave.enemy_spawns_by_chunk)
	_append_dict_keys(keys, WorldSave.player_walls_by_chunk)
	_append_dict_keys(keys, WorldSave.placed_entities_by_chunk)
	return keys

static func _append_dict_keys(out: Array[String], dict: Dictionary) -> void:
	for key_raw in dict.keys():
		out.append(String(key_raw))

static func _apply_chunk_snapshots(raw_chunks: Array) -> void:
	for entry in raw_chunks:
		if entry is ChunkSnapshot:
			save_chunk_snapshot(entry as ChunkSnapshot)
		elif entry is Dictionary:
			save_chunk_snapshot(ChunkSnapshot.from_dict(entry as Dictionary))

static func _apply_legacy_placed_entities_by_chunk(raw_chunks: Dictionary) -> void:
	for chunk_key_raw in raw_chunks.keys():
		var chunk_key: String = String(chunk_key_raw).strip_edges()
		if chunk_key.is_empty():
			continue
		var chunk_dict_raw: Variant = raw_chunks.get(chunk_key_raw, {})
		if not (chunk_dict_raw is Dictionary):
			continue
		var chunk_dict: Dictionary = chunk_dict_raw as Dictionary
		var next_chunk_entities: Dictionary = {}
		for uid_raw in chunk_dict.keys():
			var uid: String = String(uid_raw).strip_edges()
			if uid.is_empty():
				continue
			var entry_raw: Variant = chunk_dict.get(uid_raw, {})
			if not (entry_raw is Dictionary):
				continue
			var copied: Dictionary = (entry_raw as Dictionary).duplicate(true)
			copied["uid"] = uid
			copied["chunk_key"] = chunk_key
			next_chunk_entities[uid] = copied
			WorldSave.placed_entity_chunk_by_uid[uid] = chunk_key
		if not next_chunk_entities.is_empty():
			WorldSave.placed_entities_by_chunk[chunk_key] = next_chunk_entities

static func _clear_worldsave_chunk_state() -> void:
	WorldSave.chunks.clear()
	WorldSave.enemy_state_by_chunk.clear()
	WorldSave.enemy_spawns_by_chunk.clear()
	WorldSave.player_walls_by_chunk.clear()
	WorldSave.clear_placed_entities()
	WorldSave.placed_entity_data_by_uid.clear()

static func _dict_copy(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
