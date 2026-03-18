extends Node

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 1

var _world: Node = null
var _pending_player_pos: Vector2 = Vector2.ZERO
var _pending_player_inv: Array = []
var _pending_player_gold: int = -1

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
		"worldsave_chunks": _ser(WorldSave.chunks),
		"worldsave_enemy_state": _ser(WorldSave.enemy_state_by_chunk),
		"worldsave_enemy_spawns": _ser(WorldSave.enemy_spawns_by_chunk),
		"worldsave_global_flags": _ser(WorldSave.global_flags),
		"worldsave_player_walls": _ser(WorldSave.player_walls_by_chunk),
		"placed_entities_by_chunk": _ser(WorldSave.placed_entities_by_chunk),
		"placed_entity_data_by_uid": _ser(WorldSave.placed_entity_data_by_uid),
		"faction_system":     FactionSystem.serialize(),
		"site_system":        SiteSystem.serialize(),
		"npc_profile_system": NpcProfileSystem.serialize(),
		"run_clock":          RunClock.get_save_data(),
	}

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

	# Restore WorldSave state
	var ws_chunks = _des(data.get("worldsave_chunks", {}))
	if ws_chunks is Dictionary:
		WorldSave.chunks = ws_chunks

	var ws_enemy_state = _des(data.get("worldsave_enemy_state", {}))
	if ws_enemy_state is Dictionary:
		WorldSave.enemy_state_by_chunk = ws_enemy_state

	var ws_enemy_spawns = _des(data.get("worldsave_enemy_spawns", {}))
	if ws_enemy_spawns is Dictionary:
		WorldSave.enemy_spawns_by_chunk = ws_enemy_spawns

	var ws_global_flags = _des(data.get("worldsave_global_flags", {}))
	if ws_global_flags is Dictionary:
		WorldSave.global_flags = ws_global_flags

	var ws_player_walls = _des(data.get("worldsave_player_walls", {}))
	if ws_player_walls is Dictionary:
		WorldSave.player_walls_by_chunk = ws_player_walls

	# --- Migration / Loading of placed entities ---
	WorldSave.clear_placed_entities()

	# Try loading the new chunk-based format first
	var placed_chunk_raw = _des(data.get("placed_entities_by_chunk", {}))
	if placed_chunk_raw is Dictionary and not placed_chunk_raw.is_empty():
		WorldSave.placed_entities_by_chunk = placed_chunk_raw
		# Rebuild index UID -> Chunk
		WorldSave.placed_entity_chunk_by_uid.clear()
		for ckey in WorldSave.placed_entities_by_chunk:
			var dict: Dictionary = WorldSave.placed_entities_by_chunk[ckey]
			for uid in dict:
				WorldSave.placed_entity_chunk_by_uid[uid] = ckey
	else:
		# FALLBACK / MIGRATION: detect legacy 'placed_entities' array
		var placed_legacy = _des(data.get("placed_entities", []))
		if placed_legacy is Array:
			for entry in placed_legacy:
				if entry is Dictionary:
					# add_placed_entity will automatically resolve chunk_key and update indices
					WorldSave.add_placed_entity(entry)
			if not placed_legacy.is_empty():
				Debug.log("save", "Migration: Converted %d legacy placed entities to chunk-based storage." % placed_legacy.size())

	# Restore placed entity data by uid (backward-compatible: defaults to empty dictionary)
	var placed_data_raw = _des(data.get("placed_entity_data_by_uid", {}))
	WorldSave.placed_entity_data_by_uid.clear()
	if placed_data_raw is Dictionary:
		for uid in placed_data_raw.keys():
			var uid_str := String(uid)
			var entity_data = placed_data_raw[uid]
			if entity_data is Dictionary:
				WorldSave.placed_entity_data_by_uid[uid_str] = (entity_data as Dictionary).duplicate(true)

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

	var rc = data.get("run_clock", {})
	if rc is Dictionary:
		RunClock.load_save_data(rc)

	# Restore chunk_save into world's existing dict (mutate in-place so references stay valid)
	if _world != null:
		var cs = _des(data.get("chunk_save", {}))
		if cs is Dictionary:
			_world.chunk_save.clear()
			for k in cs.keys():
				_world.chunk_save[k] = cs[k]

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
	RunClock.reset()

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
