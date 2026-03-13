extends Node

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 1

var _world: Node = null
var _pending_player_pos: Vector2 = Vector2.ZERO

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
	if player != null:
		player_pos = player.global_position

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"seed": Seed.run_seed,
		"player_pos": _ser(player_pos),
		"chunk_save": _ser(_world.chunk_save),
		"worldsave_chunks": _ser(WorldSave.chunks),
		"worldsave_enemy_state": _ser(WorldSave.enemy_state_by_chunk),
		"worldsave_enemy_spawns": _ser(WorldSave.enemy_spawns_by_chunk),
		"worldsave_global_flags": _ser(WorldSave.global_flags),
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
	WorldSave.chunks.clear()
	WorldSave.enemy_state_by_chunk.clear()
	WorldSave.enemy_spawns_by_chunk.clear()
	WorldSave.global_flags.clear()
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
