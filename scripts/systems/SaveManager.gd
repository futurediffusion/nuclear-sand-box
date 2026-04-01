extends Node

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 1

var _world: Node = null
var _pending_player_pos: Vector2 = Vector2.ZERO
var _pending_player_inv: Array = []
var _pending_player_gold: int = -1
var _runtime_ports: Dictionary = {}

func register_world(world: Node) -> void:
	_world = world

func register_runtime_ports(ports: Dictionary = {}) -> void:
	_runtime_ports = ports.duplicate(true)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_world() -> void:
	if _world == null:
		push_warning("SaveManager: no world registered")
		return

	# Snapshot activo delegado a Coordination (world), no a Persistence.
	_call_runtime_port("snapshot_before_save")

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

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"seed": Seed.run_seed,
		"player_pos": _ser(player_pos),
		"player_inv": _ser(player_inv),
		"player_gold": player_gold,
		"chunk_save": _ser(_world.chunk_save),
	}
	data.merge(_ser(WorldSave.to_save_snapshot()), true)
	data.merge({
		"faction_system":       FactionSystem.serialize(),
		"site_system":          SiteSystem.serialize(),
		"npc_profile_system":   NpcProfileSystem.serialize(),
		"bandit_group_memory":  BanditGroupMemory.serialize(),
		"extortion_queue":      ExtortionQueue.serialize(),
		"raid_run_summary":     RaidQueue.get_run_summary_save_data(),
		"run_clock":            RunClock.get_save_data(),
		"world_time":           WorldTime.get_save_data(),
		"faction_hostility":    FactionHostilityManager.serialize(),
	}, true)

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
	if version != SAVE_VERSION:
		push_warning("SaveManager: save version mismatch (got %d, expected %d)" % [version, SAVE_VERSION])
		return false

	# Restore seed value (chunk_seed() is deterministic from run_seed; no global seed() reset needed)
	Seed.run_seed = int(data.get("seed", 0))

	# Restore player position (applied by world.gd after _ready setup)
	var pp = _des(data.get("player_pos", {"__v2": [0.0, 0.0]}))
	if pp is Vector2:
		_pending_player_pos = pp

	_pending_player_inv = _des(data.get("player_inv", []))
	_pending_player_gold = int(data.get("player_gold", -1))

	_restore_world_save_snapshot(data)

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

	var raid_summary = data.get("raid_run_summary", {})
	if raid_summary is Dictionary:
		RaidQueue.load_run_summary_save_data(raid_summary)

	var rc = data.get("run_clock", {})
	if rc is Dictionary:
		RunClock.load_save_data(rc)

	var wt = data.get("world_time", {})
	if wt is Dictionary:
		WorldTime.load_save_data(wt)

	var fh = data.get("faction_hostility", {})
	if fh is Dictionary:
		FactionHostilityManager.deserialize(fh)

	# Restore chunk_save into world's existing dict (mutate in-place so references stay valid)
	if _world != null:
		var cs = _des(data.get("chunk_save", {}))
		if cs is Dictionary:
			_world.chunk_save.clear()
			for k in cs.keys():
				_world.chunk_save[k] = cs[k]

	Debug.log("save", "World loaded from %s" % SAVE_PATH)
	return true

func _restore_world_save_snapshot(data: Dictionary) -> void:
	var snapshot: Dictionary = _des(data)

	# Backward-compatible migration: old saves used flat `placed_entities`.
	if not snapshot.has(WorldSave.SAVE_KEY_PLACED_ENTITIES_BY_CHUNK):
		var legacy_placed: Variant = _des(data.get("placed_entities", []))
		if legacy_placed is Array:
			var migrated: Dictionary = {}
			for entry in legacy_placed:
				if not (entry is Dictionary):
					continue
				var d: Dictionary = entry as Dictionary
				var uid := String(d.get("uid", ""))
				if uid == "":
					continue
				var tx := int(d.get("tile_pos_x", 0))
				var ty := int(d.get("tile_pos_y", 0))
				var ckey := String(d.get("chunk_key", WorldSave.get_chunk_key_for_tile(tx, ty)))
				if not migrated.has(ckey):
					migrated[ckey] = {}
				(migrated[ckey] as Dictionary)[uid] = d.duplicate(true)
			snapshot[WorldSave.SAVE_KEY_PLACED_ENTITIES_BY_CHUNK] = migrated
			Debug.log("save", "Migration: Converted %d legacy placed entities to chunk-based storage." % legacy_placed.size())

	var integrity_errors := WorldSave.apply_save_snapshot(snapshot)
	if not integrity_errors.is_empty():
		for err in integrity_errors:
			push_warning("SaveManager integrity warning: %s" % err)

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
	_call_runtime_port("reset_runtime_for_new_game")

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

func _call_runtime_port(name: String, args: Array = []) -> Variant:
	var cb: Callable = _runtime_ports.get(name, Callable())
	if cb.is_valid():
		return cb.callv(args)
	return null
