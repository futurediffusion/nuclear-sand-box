extends Node

const DEFAULT_CHUNK_SAVE := {
	"entities": {},
	"flags": {}
}

var chunks: Dictionary = {}  # chunk_key(String) -> ChunkSave(Dictionary)
var enemy_state_by_chunk: Dictionary = {}  # chunk_key(String) -> enemy_id(String) -> state(Dictionary)
var enemy_spawns_by_chunk: Dictionary = {}  # chunk_key(String) -> Array[Dictionary]
var global_flags: Dictionary = {}  # flags globales del mundo (ej: "global_camp_placed")
var player_walls_by_chunk: Dictionary = {}  # chunk_key(String) -> tile_key(String) -> {"hp": int}

func chunk_key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]

## Entidades colocadas manualmente por el player en mundo (mesas, etc.)
var placed_entities: Array[Dictionary] = []
var placed_entity_data_by_uid: Dictionary = {}  # uid(String) -> data(Dictionary)

const PLAYER_WALL_HP_KEY: String = "hp"

func add_placed_entity(entry: Dictionary) -> void:
	placed_entities.append(entry.duplicate(true))

func remove_placed_entity(uid: String) -> void:
	for i in range(placed_entities.size() - 1, -1, -1):
		if String(placed_entities[i].get("uid", "")) == uid:
			placed_entities.remove_at(i)
			erase_placed_entity_data(uid)
			return

func clear_placed_entities() -> void:
	placed_entities.clear()


func set_placed_entity_data(uid: String, data: Dictionary) -> void:
	if uid == "":
		return
	placed_entity_data_by_uid[uid] = data.duplicate(true)


func get_placed_entity_data(uid: String) -> Dictionary:
	if uid == "":
		return {}
	if not placed_entity_data_by_uid.has(uid):
		return {}
	var data = placed_entity_data_by_uid.get(uid, {})
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	return {}


func erase_placed_entity_data(uid: String) -> void:
	if uid == "":
		return
	placed_entity_data_by_uid.erase(uid)


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

func set_player_wall(cx: int, cy: int, tile_pos: Vector2i, hp: int) -> void:
	if hp <= 0:
		remove_player_wall(cx, cy, tile_pos)
		return
	var ckey := chunk_key(cx, cy)
	if not player_walls_by_chunk.has(ckey):
		player_walls_by_chunk[ckey] = {}
	var chunk_dict: Dictionary = player_walls_by_chunk[ckey]
	chunk_dict[_player_wall_tile_key(tile_pos)] = {PLAYER_WALL_HP_KEY: hp}
	player_walls_by_chunk[ckey] = chunk_dict

func has_player_wall(cx: int, cy: int, tile_pos: Vector2i) -> bool:
	var ckey := chunk_key(cx, cy)
	if not player_walls_by_chunk.has(ckey):
		return false
	var chunk_dict: Dictionary = player_walls_by_chunk[ckey]
	return chunk_dict.has(_player_wall_tile_key(tile_pos))

func get_player_wall(cx: int, cy: int, tile_pos: Vector2i) -> Dictionary:
	var ckey := chunk_key(cx, cy)
	if not player_walls_by_chunk.has(ckey):
		return {}
	var chunk_dict: Dictionary = player_walls_by_chunk[ckey]
	var key := _player_wall_tile_key(tile_pos)
	if not chunk_dict.has(key):
		return {}
	var raw: Variant = chunk_dict[key]
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}

func remove_player_wall(cx: int, cy: int, tile_pos: Vector2i) -> void:
	var ckey := chunk_key(cx, cy)
	if not player_walls_by_chunk.has(ckey):
		return
	var chunk_dict: Dictionary = player_walls_by_chunk[ckey]
	chunk_dict.erase(_player_wall_tile_key(tile_pos))
	if chunk_dict.is_empty():
		player_walls_by_chunk.erase(ckey)
	else:
		player_walls_by_chunk[ckey] = chunk_dict

func list_player_walls_in_chunk(cx: int, cy: int) -> Array[Dictionary]:
	var ckey := chunk_key(cx, cy)
	if not player_walls_by_chunk.has(ckey):
		return []
	var chunk_dict: Dictionary = player_walls_by_chunk[ckey]
	var keys: Array = chunk_dict.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for tile_key in keys:
		var parsed: Vector2i = _player_wall_tile_from_key(String(tile_key))
		if parsed.x <= -999999:
			continue
		var hp: int = 0
		var raw: Variant = chunk_dict[tile_key]
		if raw is Dictionary:
			hp = int((raw as Dictionary).get(PLAYER_WALL_HP_KEY, 0))
		if hp <= 0:
			continue
		out.append({
			"tile": parsed,
			"hp": hp,
		})
	return out

func clear_player_walls() -> void:
	player_walls_by_chunk.clear()

func _player_wall_tile_key(tile_pos: Vector2i) -> String:
	return "%d,%d" % [tile_pos.x, tile_pos.y]

func _player_wall_tile_from_key(tile_key: String) -> Vector2i:
	var parts: PackedStringArray = tile_key.split(",")
	if parts.size() != 2:
		return Vector2i(-999999, -999999)
	return Vector2i(int(parts[0]), int(parts[1]))

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
