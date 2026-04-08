extends RefCounted
class_name WorldSaveAdapter

const ChunkSnapshotSerializer := preload("res://scripts/persistence/save/ChunkSnapshotSerializer.gd")
const ChunkSnapshot := preload("res://scripts/core/ChunkSnapshot.gd")

const SNAPSHOT_STATE_VERSION: int = 1
const SNAPSHOT_STATE_KEY: String = "world_snapshot_state"

## Infrastructure adapter between canonical chunk snapshots and current
## WorldSave-backed storage payload sections.
##
## Canonical side:
## - chunk snapshots (ChunkSnapshot)
## - world snapshot state envelope ({snapshot_version, global_flags, chunks})
##
## Storage side (compat):
## - legacy worldsave_* sections in save payload
##
## This adapter intentionally does not own or infer gameplay/domain truth.

static func save_chunk_snapshot(snapshot: ChunkSnapshot) -> void:
	if snapshot == null:
		return
	ChunkSnapshotSerializer.apply_snapshot_to_worldsave(snapshot)

static func load_chunk_snapshot(chunk_key: String) -> ChunkSnapshot:
	return ChunkSnapshotSerializer.serialize_chunk_from_worldsave(chunk_key)

static func capture_world_snapshot_state() -> Dictionary:
	var chunk_dicts: Array[Dictionary] = []
	for snapshot in _collect_chunk_snapshots():
		if snapshot == null:
			continue
		chunk_dicts.append((snapshot as ChunkSnapshot).to_dict())
	return {
		"snapshot_version": SNAPSHOT_STATE_VERSION,
		"global_flags": WorldSave.global_flags.duplicate(true),
		"chunks": chunk_dicts,
	}

static func persist_world_snapshot_state(payload: Dictionary) -> void:
	payload[SNAPSHOT_STATE_KEY] = capture_world_snapshot_state()

static func restore_world_snapshot_state(payload: Dictionary) -> bool:
	var raw_state: Variant = payload.get(SNAPSHOT_STATE_KEY, null)
	if not (raw_state is Dictionary):
		return false
	var state: Dictionary = raw_state as Dictionary
	var chunks_raw: Variant = state.get("chunks", [])
	if not (chunks_raw is Array):
		return false

	_clear_worldsave_chunk_state()
	_apply_chunk_snapshots(chunks_raw as Array)

	var global_flags_raw: Variant = state.get("global_flags", {})
	if global_flags_raw is Dictionary:
		WorldSave.global_flags = (global_flags_raw as Dictionary).duplicate(true)
	else:
		WorldSave.global_flags = {}
	return true

static func export_legacy_worldsave_payload() -> Dictionary:
	return {
		"worldsave_chunks": WorldSave.chunks.duplicate(true),
		"worldsave_enemy_state": WorldSave.enemy_state_by_chunk.duplicate(true),
		"worldsave_enemy_spawns": WorldSave.enemy_spawns_by_chunk.duplicate(true),
		"worldsave_global_flags": WorldSave.global_flags.duplicate(true),
		"worldsave_player_walls": WorldSave.player_walls_by_chunk.duplicate(true),
	}

static func restore_legacy_worldsave_payload(payload: Dictionary) -> void:
	_clear_worldsave_chunk_state()

	var ws_chunks: Variant = payload.get("worldsave_chunks", {})
	if ws_chunks is Dictionary:
		WorldSave.chunks = (ws_chunks as Dictionary).duplicate(true)

	var ws_enemy_state: Variant = payload.get("worldsave_enemy_state", {})
	if ws_enemy_state is Dictionary:
		WorldSave.enemy_state_by_chunk = (ws_enemy_state as Dictionary).duplicate(true)

	var ws_enemy_spawns: Variant = payload.get("worldsave_enemy_spawns", {})
	if ws_enemy_spawns is Dictionary:
		WorldSave.enemy_spawns_by_chunk = (ws_enemy_spawns as Dictionary).duplicate(true)

	var ws_global_flags: Variant = payload.get("worldsave_global_flags", {})
	if ws_global_flags is Dictionary:
		WorldSave.global_flags = (ws_global_flags as Dictionary).duplicate(true)

	var ws_player_walls: Variant = payload.get("worldsave_player_walls", {})
	if ws_player_walls is Dictionary:
		WorldSave.player_walls_by_chunk = (ws_player_walls as Dictionary).duplicate(true)

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

static func _clear_worldsave_chunk_state() -> void:
	WorldSave.chunks.clear()
	WorldSave.enemy_state_by_chunk.clear()
	WorldSave.enemy_spawns_by_chunk.clear()
	WorldSave.player_walls_by_chunk.clear()
	WorldSave.clear_placed_entities()
	WorldSave.placed_entity_data_by_uid.clear()
