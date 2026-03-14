extends Node

const DEFAULT_CHUNK_SAVE := {
	"entities": {},
	"flags": {}
}

var chunks: Dictionary = {}  # chunk_key(String) -> ChunkSave(Dictionary)
var enemy_state_by_chunk: Dictionary = {}  # chunk_key(String) -> enemy_id(String) -> state(Dictionary)
var enemy_spawns_by_chunk: Dictionary = {}  # chunk_key(String) -> Array[Dictionary]
var global_flags: Dictionary = {}  # flags globales del mundo (ej: "global_camp_placed")

func chunk_key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]

func get_chunk_save(cx: int, cy: int) -> Dictionary:
	var k := chunk_key(cx, cy)
	if not chunks.has(k):
		chunks[k] = {
			"entities": {},
			"flags": {}
		}
	return chunks[k]

func get_entity_state(cx: int, cy: int, uid: String):
	var cs: Dictionary = get_chunk_save(cx, cy)
	return cs["entities"].get(uid, null)

func set_entity_state(cx: int, cy: int, uid: String, state: Dictionary) -> void:
	get_chunk_save(cx, cy)["entities"][uid] = state.duplicate(true)

func erase_entity_state(cx: int, cy: int, uid: String) -> void:
	get_chunk_save(cx, cy)["entities"].erase(uid)

# --- Generic scaffolding for future chunk facts (props moved/broken, chests looted, NPC KO/dead, etc.) ---
func get_chunk_flag(cx: int, cy: int, flag_key: String):
	return get_chunk_save(cx, cy)["flags"].get(flag_key, null)

func set_chunk_flag(cx: int, cy: int, flag_key: String, value) -> void:
	get_chunk_save(cx, cy)["flags"][flag_key] = value

func get_enemy_state(chunk_key: String, enemy_id: String):
	if chunk_key == "" or enemy_id == "":
		return null
	if not enemy_state_by_chunk.has(chunk_key):
		return null
	return enemy_state_by_chunk[chunk_key].get(enemy_id, null)

func set_enemy_state(chunk_key: String, enemy_id: String, state: Dictionary) -> void:
	if chunk_key == "" or enemy_id == "":
		return
	if not enemy_state_by_chunk.has(chunk_key):
		enemy_state_by_chunk[chunk_key] = {}
	var copy: Dictionary = state.duplicate(true)
	copy["id"] = enemy_id
	copy["chunk_key"] = chunk_key
	if not copy.has("version"):
		copy["version"] = 1
	enemy_state_by_chunk[chunk_key][enemy_id] = copy

func has_enemy_state(chunk_key: String, enemy_id: String) -> bool:
	if chunk_key == "" or enemy_id == "":
		return false
	return enemy_state_by_chunk.has(chunk_key) and enemy_state_by_chunk[chunk_key].has(enemy_id)

func remove_enemy_state(chunk_key: String, enemy_id: String) -> void:
	if not enemy_state_by_chunk.has(chunk_key):
		return
	enemy_state_by_chunk[chunk_key].erase(enemy_id)
	if enemy_state_by_chunk[chunk_key].is_empty():
		enemy_state_by_chunk.erase(chunk_key)

func iter_enemy_ids_in_chunk(chunk_key: String) -> Array[String]:
	if not enemy_state_by_chunk.has(chunk_key):
		return []
	var ids: Array[String] = []
	for enemy_id in enemy_state_by_chunk[chunk_key].keys():
		ids.append(String(enemy_id))
	ids.sort()
	return ids

func mark_enemy_dead(chunk_key: String, enemy_id: String) -> void:
	var state = get_enemy_state(chunk_key, enemy_id)
	if state == null:
		return
	var copy: Dictionary = (state as Dictionary).duplicate(true)
	copy["is_dead"] = true
	copy["last_active_time"] = Time.get_unix_time_from_system()
	set_enemy_state(chunk_key, enemy_id, copy)

func get_or_create_enemy_state(chunk_key: String, enemy_id: String, default_state: Dictionary) -> Dictionary:
	var existing = get_enemy_state(chunk_key, enemy_id)
	if existing != null:
		return (existing as Dictionary).duplicate(true)
	var created: Dictionary = default_state.duplicate(true)
	created["id"] = enemy_id
	created["chunk_key"] = chunk_key
	if not created.has("version"):
		created["version"] = 1
	set_enemy_state(chunk_key, enemy_id, created)
	return created.duplicate(true)

func get_enemy_count_in_chunk(chunk_key: String) -> int:
	if not enemy_state_by_chunk.has(chunk_key):
		return 0
	return enemy_state_by_chunk[chunk_key].size()

func ensure_chunk_enemy_spawns(chunk_key: String, records: Array) -> void:
	if chunk_key == "":
		return
	if enemy_spawns_by_chunk.has(chunk_key):
		return
	var stable_records: Array = records.duplicate(true)
	stable_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("spawn_index", 0)) < int(b.get("spawn_index", 0))
	)
	enemy_spawns_by_chunk[chunk_key] = stable_records

func get_chunk_enemy_spawns(chunk_key: String) -> Array:
	if not enemy_spawns_by_chunk.has(chunk_key):
		return []
	return (enemy_spawns_by_chunk[chunk_key] as Array).duplicate(true)

func clear_chunk_enemy_spawns(chunk_key: String) -> void:
	enemy_spawns_by_chunk.erase(chunk_key)
	enemy_state_by_chunk.erase(chunk_key)

# --- Flower data ---
var _flower_data: Dictionary = {}  # Vector2i -> Array

func set_flower_data(chunk: Vector2i, data: Array) -> void:
	_flower_data[chunk] = data

func get_flower_data(chunk: Vector2i) -> Array:
	return _flower_data.get(chunk, []) as Array

# --- Fungus data ---
var _fungus_data: Dictionary = {}  # Vector2i -> Array

func set_fungus_data(chunk: Vector2i, data: Array) -> void:
	_fungus_data[chunk] = data

func get_fungus_data(chunk: Vector2i) -> Array:
	return _fungus_data.get(chunk, []) as Array

# --- Sticks data ---
var _sticks_data: Dictionary = {}  # Vector2i -> Array

func set_sticks_data(chunk: Vector2i, data: Array) -> void:
	_sticks_data[chunk] = data

func get_sticks_data(chunk: Vector2i) -> Array:
	return _sticks_data.get(chunk, []) as Array

# --- Tiny stones data ---
var _tiny_stones_data: Dictionary = {}  # Vector2i -> Array

func set_tiny_stones_data(chunk: Vector2i, data: Array) -> void:
	_tiny_stones_data[chunk] = data

func get_tiny_stones_data(chunk: Vector2i) -> Array:
	return _tiny_stones_data.get(chunk, []) as Array
