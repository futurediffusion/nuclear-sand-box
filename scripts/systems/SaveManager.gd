extends Node

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 2


# Persistence ownership boundary:
# - canonical truth lives in snapshot/canonical owners, not runtime projections.
# - see docs/architecture/ownership/persistence.md
var _world: Node = null
var _pending_player_pos: Vector2 = Vector2.ZERO
var _pending_player_inv: Array = []
var _pending_player_gold: int = -1
var _last_save_pipeline_snapshot: Dictionary = {}
var _last_load_pipeline_snapshot: Dictionary = {}

func register_world(world: Node) -> void:
	_world = world

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_world() -> void:
	if _world == null:
		push_warning("SaveManager: no world registered")
		return

	# Snapshot active entities into WorldSave before serializing
	var ec = _world.get("entity_coordinator")
	if ec != null and ec.has_method("snapshot_entities_to_world_save"):
		ec.snapshot_entities_to_world_save()

	var player = _world.get("player")
	var player_pos := Vector2.ZERO
	var player_inv := []
	var player_gold := 0
	if player != null:
		player_pos = player.global_position
		var inv = player.get("inventory_component")
		if inv != null:
			player_inv = inv.get("slots")
			player_gold = inv.get("gold")

	var canonical_state: Dictionary = _build_canonical_save_state(player_pos, player_inv, player_gold)
	var world_snapshot = WorldSaveAdapter.build_world_snapshot(canonical_state)
	world_snapshot.persistence_meta = {
		"snapshot_contract": "canonical_world_snapshot_v2",
		"canonical_snapshot_path": true,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
	}
	_last_save_pipeline_snapshot = _summarize_world_snapshot(world_snapshot)
	_last_save_pipeline_snapshot["source"] = "save_world"
	_last_save_pipeline_snapshot["canonical_snapshot_path_used"] = true
	_last_save_pipeline_snapshot["legacy_migration_used"] = false
	var data: Dictionary = WorldSnapshotSerializer.serialize(world_snapshot)
	data["version"] = SAVE_VERSION

	var json_str: String = JSON.stringify(data)
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to open save file for writing: %s" % SAVE_PATH)
		return
	file.store_string(json_str)
	file.close()
	Debug.log("save", "World saved to %s" % SAVE_PATH)

func load_world_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: failed to open save file for reading")
		return false
	var json_str: String = file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_str)
	if data == null or not data is Dictionary:
		push_error("SaveManager: invalid save file JSON")
		return false

	var version: int = int(data.get("version", 0))
	if version > SAVE_VERSION or version <= 0:
		push_warning("SaveManager: unsupported save version %d (current %d)" % [version, SAVE_VERSION])
		return false

	# Restore seed value (chunk_seed() is deterministic from run_seed; no global seed() reset needed)
	Seed.run_seed = int(data.get("seed", 0))

	# Restore player position (applied by world.gd after _ready setup)
	var pp = _des(data.get("player_pos", {"__v2": [0.0, 0.0]}))
	if pp is Vector2:
		_pending_player_pos = pp

	_pending_player_inv = _des(data.get("player_inv", []))
	_pending_player_gold = int(data.get("player_gold", -1))

	# Restore WorldSave state through snapshot adapter first.
	var deserialized_payload: Dictionary = {}
	for key_raw in (data as Dictionary).keys():
		deserialized_payload[String(key_raw)] = _des((data as Dictionary).get(key_raw))

	var world_snapshot: WorldSnapshot = null
	var used_legacy_migration: bool = false
	var restore_path: String = "canonical_snapshot"
	var snapshot_loaded_version: int = 0
	var snapshot_migration_path: Array = []
	var snapshot_migration_warnings: Array = []
	if deserialized_payload.has("snapshot_version"):
		var deserialize_report: Dictionary = WorldSnapshotSerializer.deserialize_with_report(deserialized_payload)
		if not bool(deserialize_report.get("ok", false)):
			push_warning("SaveManager: unsupported snapshot version %s" % str(deserialize_report.get("loaded_snapshot_version", 0)))
			return false
		var snapshot_raw: Variant = deserialize_report.get("snapshot", null)
		if snapshot_raw is WorldSnapshot:
			world_snapshot = snapshot_raw as WorldSnapshot
		snapshot_loaded_version = int(deserialize_report.get("loaded_snapshot_version", 0))
		snapshot_migration_path = (deserialize_report.get("migration_path", []) as Array).duplicate(true)
		snapshot_migration_warnings = (deserialize_report.get("warnings", []) as Array).duplicate(true)
		if not snapshot_migration_path.is_empty():
			restore_path = "snapshot_migration"
	else:
		# Explicitly opt into the legacy migration bridge in this one bounded
		# load path so debug assertions can still fail on unexpected callers.
		deserialized_payload[WorldSaveAdapter.LEGACY_MIGRATION_ALLOW_KEY] = true
		var migration_result: Dictionary = WorldSaveAdapter.migrate_legacy_payload_to_world_snapshot(deserialized_payload)
		var snapshot_raw: Variant = migration_result.get("snapshot", null)
		if snapshot_raw is WorldSnapshot:
			world_snapshot = snapshot_raw as WorldSnapshot
		used_legacy_migration = bool(migration_result.get("legacy_migration_used", false))
		restore_path = String(migration_result.get("legacy_source", "legacy_migration"))
		snapshot_loaded_version = int(migration_result.get("loaded_snapshot_version", 1))
		snapshot_migration_path = (migration_result.get("migration_path", []) as Array).duplicate(true)
		snapshot_migration_warnings = (migration_result.get("warnings", []) as Array).duplicate(true)

	if world_snapshot == null:
		push_error("SaveManager: failed to obtain a world snapshot for load")
		return false

	if not WorldSaveAdapter.apply_world_snapshot(world_snapshot):
		push_error("SaveManager: failed to apply world snapshot")
		return false

	_last_load_pipeline_snapshot = _summarize_world_snapshot(world_snapshot)
	_last_load_pipeline_snapshot["source"] = restore_path
	_last_load_pipeline_snapshot["loaded_save_file_version"] = version
	_last_load_pipeline_snapshot["loaded_snapshot_version"] = snapshot_loaded_version
	_last_load_pipeline_snapshot["snapshot_target_version"] = int(world_snapshot.snapshot_version)
	_last_load_pipeline_snapshot["snapshot_migration_path"] = snapshot_migration_path.duplicate(true)
	_last_load_pipeline_snapshot["snapshot_migration_warnings"] = snapshot_migration_warnings.duplicate(true)
	_last_load_pipeline_snapshot["canonical_snapshot_path_used"] = true
	_last_load_pipeline_snapshot["legacy_migration_used"] = used_legacy_migration
	Debug.log("save", "Load telemetry: save_version=%d snapshot_version=%d migration_path=%s canonical_snapshot_path_used=true legacy_migration_used=%s source=%s" % [
		version,
		snapshot_loaded_version,
		JSON.stringify(snapshot_migration_path),
		str(used_legacy_migration),
		restore_path,
	])

	# Restore Faction / Site / NpcProfile systems (backward-compatible: get with empty default)
	var fs = data.get("faction_system", {})
	if fs is Dictionary:
		FactionSystem.deserialize(fs)
	var ss = data.get("site_system", {})
	if ss is Dictionary:
		SiteSystem.deserialize(ss)
	var nps = data.get("npc_profile_system", {})
	if nps is Dictionary:
		NpcProfileSystem.deserialize(nps)

	var bgm = data.get("bandit_group_memory", {})
	if bgm is Dictionary:
		BanditGroupMemory.deserialize(bgm)

	var eq = data.get("extortion_queue")
	if eq is Dictionary or eq is Array:
		ExtortionQueue.deserialize(eq)

	var rc = data.get("run_clock", {})
	if rc is Dictionary:
		RunClock.load_save_data(rc)

	var wt = data.get("world_time", {})
	if wt is Dictionary:
		WorldTime.load_save_data(wt)

	var fh = data.get("faction_hostility", {})
	if fh is Dictionary:
		FactionHostilityManager.deserialize(fh)

	Debug.log("save", "World loaded from %s" % SAVE_PATH)
	return true

func delete_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)

func new_game() -> void:
	delete_save()
	_pending_player_pos = Vector2.ZERO
	_pending_player_inv = []
	_pending_player_gold = -1
	WorldSave.chunks.clear()
	WorldSave.enemy_state_by_chunk.clear()
	WorldSave.enemy_spawns_by_chunk.clear()
	WorldSave.global_flags.clear()
	WorldSave.player_walls_by_chunk.clear()
	WorldSave.clear_placed_entities()
	WorldSave.placed_entity_data_by_uid.clear()
	PlacementSystem.clear_runtime_instances()
	FactionSystem.reset()
	SiteSystem.reset()
	NpcProfileSystem.reset()
	BanditGroupMemory.reset()
	ExtortionQueue.reset()
	RunClock.reset()
	WorldTime.load_save_data({})
	FactionHostilityManager.reset()

	# Generar semilla aleatoria real, ignorando debug_seed
	var new_seed := int(Time.get_unix_time_from_system()) % 2147483647
	if new_seed <= 0:
		new_seed = 1
	Seed.run_seed = new_seed
	seed(new_seed)
	Debug.log("save", "New game — save cleared, new seed=%d" % Seed.run_seed)

# ---------------------------------------------------------------------------
# Serialization helpers
# ---------------------------------------------------------------------------

func _ser(val: Variant) -> Variant:
	if val is Vector2i:
		return {"__v2i": [val.x, val.y]}
	if val is Vector2:
		return {"__v2": [float(val.x), float(val.y)]}
	if val is Dictionary:
		var out: Dictionary = {}
		for k in val.keys():
			var sk: String
			if k is Vector2i:
				sk = "__k2i:%d,%d" % [k.x, k.y]
			else:
				sk = str(k)
			out[sk] = _ser(val[k])
		return out
	if val is Array:
		var out: Array = []
		for item in val:
			out.append(_ser(item))
		return out
	return val

func _des(val: Variant) -> Variant:
	if val is Dictionary:
		if val.has("__v2i"):
			var arr = val["__v2i"]
			return Vector2i(int(arr[0]), int(arr[1]))
		if val.has("__v2"):
			var arr = val["__v2"]
			return Vector2(float(arr[0]), float(arr[1]))
		var out: Dictionary = {}
		for k in val.keys():
			var dk: Variant = k
			if typeof(k) == TYPE_STRING and (k as String).begins_with("__k2i:"):
				var parts: PackedStringArray = (k as String).substr(6).split(",")
				dk = Vector2i(int(parts[0]), int(parts[1]))
			out[dk] = _des(val[k])
		return out
	if val is Array:
		var out: Array = []
		for item in val:
			out.append(_des(item))
		return out
	return val

func _build_canonical_save_state(player_pos: Vector2, player_inv: Array, player_gold: int) -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"seed": Seed.run_seed,
		"player_pos": player_pos,
		"player_inv": player_inv,
		"player_gold": player_gold,
		"faction_system": FactionSystem.serialize(),
		"site_system": SiteSystem.serialize(),
		"npc_profile_system": NpcProfileSystem.serialize(),
		"bandit_group_memory": BanditGroupMemory.serialize(),
		"extortion_queue": ExtortionQueue.serialize(),
		"run_clock": RunClock.get_save_data(),
		"world_time": WorldTime.get_save_data(),
		"faction_hostility": FactionHostilityManager.serialize(),
	}

func get_last_save_pipeline_snapshot() -> Dictionary:
	return _last_save_pipeline_snapshot.duplicate(true)

func get_last_load_pipeline_snapshot() -> Dictionary:
	return _last_load_pipeline_snapshot.duplicate(true)

func _summarize_world_snapshot(world_snapshot: WorldSnapshot) -> Dictionary:
	if world_snapshot == null:
		return {}
	var structure_count: int = 0
	var placed_entity_count: int = 0
	for chunk_snapshot in world_snapshot.chunks:
		if chunk_snapshot == null:
			continue
		structure_count += (chunk_snapshot.structures as Array).size()
		placed_entity_count += (chunk_snapshot.placed_entities as Array).size()
	return {
		"snapshot_version": int(world_snapshot.snapshot_version),
		"save_version": int(world_snapshot.save_version),
		"chunk_count": int(world_snapshot.chunks.size()),
		"structure_count": structure_count,
		"placed_entity_count": placed_entity_count,
		"persistence_meta": world_snapshot.persistence_meta.duplicate(true),
	}
