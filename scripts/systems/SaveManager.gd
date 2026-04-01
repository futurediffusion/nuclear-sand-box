extends Node

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 1

var _world: Node = null
var _pending_player_pos: Vector2 = Vector2.ZERO
var _pending_player_inv: Array = []
var _pending_player_gold: int = -1

const WORLD_SAVE_KEYS: Array[String] = [
	"worldsave_chunks",
	"worldsave_enemy_state",
	"worldsave_enemy_spawns",
	"worldsave_global_flags",
	"worldsave_player_walls",
	"placed_entities_by_chunk",
	"placed_entity_data_by_uid",
]

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

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"seed": Seed.run_seed,
		"player_pos": _ser(player_pos),
		"player_inv": _ser(player_inv),
		"player_gold": player_gold,
		"chunk_save": _ser(_world.chunk_save),
	}
	data.merge(_capture_world_save_payload(), true)
	data.merge({
		"faction_system":       FactionSystem.serialize(),
		"site_system":          SiteSystem.serialize(),
		"npc_profile_system":   NpcProfileSystem.serialize(),
		"bandit_group_memory":  BanditGroupMemory.serialize(),
		"extortion_queue":      ExtortionQueue.serialize(),
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

	_restore_world_save_payload(data)

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

	# Restore chunk_save into world's existing dict (mutate in-place so references stay valid)
	if _world != null:
		var cs = _des(data.get("chunk_save", {}))
		if cs is Dictionary:
			_world.chunk_save.clear()
			for k in cs.keys():
				_world.chunk_save[k] = cs[k]

	Debug.log("save", "World loaded from %s" % SAVE_PATH)
	return true

func _capture_world_save_payload() -> Dictionary:
	var payload: Dictionary = {}
	payload["worldsave_chunks"] = _ser(WorldSave.chunks)
	payload["worldsave_enemy_state"] = _ser(WorldSave.enemy_state_by_chunk)
	payload["worldsave_enemy_spawns"] = _ser(WorldSave.enemy_spawns_by_chunk)
	payload["worldsave_global_flags"] = _ser(WorldSave.global_flags)
	payload["worldsave_player_walls"] = _ser(WorldSave.player_walls_by_chunk)
	payload["placed_entities_by_chunk"] = _ser(WorldSave.placed_entities_by_chunk)
	payload["placed_entity_data_by_uid"] = _ser(WorldSave.placed_entity_data_by_uid)
	return payload

func _restore_world_save_payload(data: Dictionary) -> void:
	var restore_payload: Dictionary = {}
	for key in WORLD_SAVE_KEYS:
		restore_payload[key] = _des(data.get(key, {}))
	var legacy_placed = _des(data.get("placed_entities", []))
	if legacy_placed is Array:
		restore_payload["placed_entities_legacy"] = legacy_placed

	var integrity_errors: PackedStringArray = _validate_world_save_payload(restore_payload)
	if not integrity_errors.is_empty():
		for err in integrity_errors:
			push_warning("SaveManager integrity warning: %s" % err)

	WorldSave.chunks = restore_payload.get("worldsave_chunks", {})
	WorldSave.enemy_state_by_chunk = restore_payload.get("worldsave_enemy_state", {})
	WorldSave.enemy_spawns_by_chunk = restore_payload.get("worldsave_enemy_spawns", {})
	WorldSave.global_flags = restore_payload.get("worldsave_global_flags", {})
	WorldSave.player_walls_by_chunk = restore_payload.get("worldsave_player_walls", {})

	WorldSave.clear_placed_entities()
	var placed_chunk_raw: Dictionary = restore_payload.get("placed_entities_by_chunk", {})
	if not placed_chunk_raw.is_empty():
		WorldSave.placed_entities_by_chunk = placed_chunk_raw
		WorldSave.placed_entity_chunk_by_uid.clear()
		for ckey in WorldSave.placed_entities_by_chunk:
			var dict: Dictionary = WorldSave.placed_entities_by_chunk[ckey]
			for uid in dict:
				WorldSave.placed_entity_chunk_by_uid[String(uid)] = String(ckey)
	else:
		var placed_legacy: Array = restore_payload.get("placed_entities_legacy", [])
		for entry in placed_legacy:
			if entry is Dictionary:
				WorldSave.add_placed_entity(entry as Dictionary)
		if not placed_legacy.is_empty():
			Debug.log("save", "Migration: Converted %d legacy placed entities to chunk-based storage." % placed_legacy.size())

	WorldSave.placed_entity_data_by_uid.clear()
	var placed_data_raw: Dictionary = restore_payload.get("placed_entity_data_by_uid", {})
	for uid in placed_data_raw.keys():
		var entity_data = placed_data_raw[uid]
		WorldSave.placed_entity_data_by_uid[String(uid)] = (entity_data as Dictionary).duplicate(true)

func _validate_world_save_payload(payload: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	var dict_fields: Dictionary = {
		"worldsave_chunks": "WorldSave.chunks",
		"worldsave_enemy_state": "WorldSave.enemy_state_by_chunk",
		"worldsave_enemy_spawns": "WorldSave.enemy_spawns_by_chunk",
		"worldsave_global_flags": "WorldSave.global_flags",
		"worldsave_player_walls": "WorldSave.player_walls_by_chunk",
		"placed_entities_by_chunk": "WorldSave.placed_entities_by_chunk",
		"placed_entity_data_by_uid": "WorldSave.placed_entity_data_by_uid",
	}
	for key in dict_fields.keys():
		if not (payload.get(key, {}) is Dictionary):
			errors.append("%s expected Dictionary in '%s'" % [dict_fields[key], key])
			payload[key] = {}

	var placed_legacy: Variant = payload.get("placed_entities_legacy", [])
	if not (placed_legacy is Array):
		errors.append("Legacy placed_entities expected Array")
		payload["placed_entities_legacy"] = []

	var placed_chunk: Dictionary = payload.get("placed_entities_by_chunk", {})
	for ckey in placed_chunk.keys():
		var entries: Variant = placed_chunk[ckey]
		if not (entries is Dictionary):
			errors.append("placed_entities_by_chunk[%s] must be Dictionary" % String(ckey))
			placed_chunk[ckey] = {}
			continue
		var sanitized_entries: Dictionary = {}
		for uid in (entries as Dictionary).keys():
			var raw_entry: Variant = (entries as Dictionary)[uid]
			if raw_entry is Dictionary:
				sanitized_entries[String(uid)] = (raw_entry as Dictionary).duplicate(true)
			else:
				errors.append("placed entity '%s' in chunk '%s' is not Dictionary" % [String(uid), String(ckey)])
		placed_chunk[ckey] = sanitized_entries
	payload["placed_entities_by_chunk"] = placed_chunk

	var placed_data: Dictionary = payload.get("placed_entity_data_by_uid", {})
	for uid in placed_data.keys():
		if not (placed_data[uid] is Dictionary):
			errors.append("placed_entity_data_by_uid['%s'] must be Dictionary" % String(uid))
			placed_data[uid] = {}
	payload["placed_entity_data_by_uid"] = placed_data
	return errors

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
