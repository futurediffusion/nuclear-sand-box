extends Node

const DEFAULT_CHUNK_SAVE := {
	"entities": {},
	"flags": {}
}

var chunks: Dictionary = {}  # chunk_key(String) -> ChunkSave(Dictionary)
var enemy_state_by_chunk: Dictionary = {}  # chunk_key(String) -> enemy_id(String) -> state(Dictionary)
var enemy_spawns_by_chunk: Dictionary = {}  # chunk_key(String) -> Array[Dictionary]
var global_flags: Dictionary = {}  # flags globales del mundo
var player_walls_by_chunk: Dictionary = {}  # chunk_key(String) -> tile_key(String) -> {"hp": int}

var chunk_size: int = 32
const INVALID_CHUNK_POS: Vector2i = Vector2i(-999999, -999999)
var _chunk_key_serialize_calls: int = 0
var _chunk_key_deserialize_calls: int = 0

func chunk_key(cx: int, cy: int) -> String:
	return chunk_key_from_pos(Vector2i(cx, cy))

func chunk_key_from_pos(chunk_pos: Vector2i) -> String:
	return serialize_chunk_pos(chunk_pos)

func chunk_pos_from_key(chunk_key_value: String) -> Vector2i:
	return deserialize_chunk_key(chunk_key_value)

func serialize_chunk_pos(chunk_pos: Vector2i) -> String:
	_chunk_key_serialize_calls += 1
	return "%d,%d" % [chunk_pos.x, chunk_pos.y]

func deserialize_chunk_key(chunk_key_value: String) -> Vector2i:
	_chunk_key_deserialize_calls += 1
	var parts: PackedStringArray = chunk_key_value.split(",")
	if parts.size() != 2:
		return INVALID_CHUNK_POS
	return Vector2i(int(parts[0]), int(parts[1]))

func get_chunk_key_codec_metrics() -> Dictionary:
	return {
		"serialize_calls": _chunk_key_serialize_calls,
		"deserialize_calls": _chunk_key_deserialize_calls,
	}

func get_chunk_key_for_tile(tx: int, ty: int) -> String:
	return chunk_key_from_pos(chunk_pos_for_tile(tx, ty))

func chunk_pos_for_tile(tx: int, ty: int) -> Vector2i:
	return Vector2i(
		int(floor(float(tx) / float(chunk_size))),
		int(floor(float(ty) / float(chunk_size)))
	)

## Entidades colocadas manualmente por el player en mundo (mesas, etc.)
## Almacenamiento canónico por chunk: chunk_key -> { uid -> entry }
var placed_entities_by_chunk: Dictionary = {}
## Índice auxiliar para O(1) removal y lookup: uid -> chunk_key
var placed_entity_chunk_by_uid: Dictionary = {}
## Datos persistentes por UID (inventarios, etc.): uid -> data
var placed_entity_data_by_uid: Dictionary = {}
## Revisión estructural de placeables persistentes.
## Sube solo cuando cambia el set canónico (alta/baja/movimiento), no cuando cambia data por UID.
var placed_entities_revision: int = 0
## Serial monotónico de cambios estructurales de placeables (delta-friendly).
var placed_entities_change_serial: int = 0
const PLACED_ENTITIES_CHANGE_LOG_MAX: int = 256
var _placed_entities_change_log: Array[Dictionary] = []

const PLAYER_WALL_HP_KEY: String = "hp"

## Callable registrado por world.gd para verificar si hay una pared de tilemap entre dos posiciones.
## Signature: func(from_pos: Vector2, to_pos: Vector2) -> bool
var wall_tile_blocker_fn: Callable = Callable()
## Callable registrado por world.gd para chequear ocupación de pared en un punto.
## Signature: func(world_pos: Vector2) -> bool
## Compat: los sistemas de combate usan este contrato primero para evitar tratar colliders
## como fuente canónica de existencia de muros.
var wall_tile_occupancy_fn: Callable = Callable()

func add_placed_entity(entry: Dictionary) -> void:
	var uid := String(entry.get("uid", ""))
	if uid == "":
		return
	var previous_entry: Dictionary = {}
	if placed_entity_chunk_by_uid.has(uid):
		var prev_ckey := String(placed_entity_chunk_by_uid[uid])
		if placed_entities_by_chunk.has(prev_ckey):
			var prev_chunk_dict: Dictionary = placed_entities_by_chunk[prev_ckey]
			if prev_chunk_dict.has(uid):
				previous_entry = (prev_chunk_dict[uid] as Dictionary).duplicate(true)

	var tx := int(entry.get("tile_pos_x", 0))
	var ty := int(entry.get("tile_pos_y", 0))
	var ckey := String(entry.get("chunk_key", ""))
	if ckey == "":
		ckey = get_chunk_key_for_tile(tx, ty)

	# Si ya existía en otro chunk, borrar la entrada vieja para evitar duplicados.
	if placed_entity_chunk_by_uid.has(uid):
		var old_ckey := String(placed_entity_chunk_by_uid[uid])
		if old_ckey != ckey and placed_entities_by_chunk.has(old_ckey):
			placed_entities_by_chunk[old_ckey].erase(uid)
			if placed_entities_by_chunk[old_ckey].is_empty():
				placed_entities_by_chunk.erase(old_ckey)

	var final_entry := entry.duplicate(true)
	final_entry["chunk_key"] = ckey

	if not placed_entities_by_chunk.has(ckey):
		placed_entities_by_chunk[ckey] = {}

	placed_entities_by_chunk[ckey][uid] = final_entry
	placed_entity_chunk_by_uid[uid] = ckey
	placed_entities_revision += 1
	_record_placed_entities_change({
		"op": "upsert",
		"uid": uid,
		"prev_entry": previous_entry,
		"entry": final_entry.duplicate(true),
	})

func remove_placed_entity(uid: String) -> void:
	if not placed_entity_chunk_by_uid.has(uid):
		# Intento de remoción por UID que no existe en el índice.
		# Podría ser porque no se cargó el índice o el UID es inválido.
		return

	var ckey := String(placed_entity_chunk_by_uid[uid])
	var previous_entry: Dictionary = {}
	if placed_entities_by_chunk.has(ckey):
		var chunk_dict: Dictionary = placed_entities_by_chunk[ckey]
		if chunk_dict.has(uid):
			previous_entry = (chunk_dict[uid] as Dictionary).duplicate(true)
		placed_entities_by_chunk[ckey].erase(uid)
		if placed_entities_by_chunk[ckey].is_empty():
			placed_entities_by_chunk.erase(ckey)

	placed_entity_chunk_by_uid.erase(uid)
	erase_placed_entity_data(uid)
	placed_entities_revision += 1
	_record_placed_entities_change({
		"op": "remove",
		"uid": uid,
		"prev_entry": previous_entry,
	})

func clear_placed_entities() -> void:
	var had_entries: bool = not placed_entity_chunk_by_uid.is_empty()
	placed_entities_by_chunk.clear()
	placed_entity_chunk_by_uid.clear()
	placed_entities_revision += 1
	if had_entries:
		_record_placed_entities_change({"op": "clear"})

func get_placed_entities_in_chunk(cx: int, cy: int) -> Array[Dictionary]:
	var ckey := chunk_key(cx, cy)
	if not placed_entities_by_chunk.has(ckey):
		return []
	var dict: Dictionary = placed_entities_by_chunk[ckey]
	var out: Array[Dictionary] = []
	for uid in dict:
		out.append((dict[uid] as Dictionary).duplicate(true))
	return out

func get_placed_entity_at_tile(cx: int, cy: int, tile_pos: Vector2i) -> Dictionary:
	var ckey := chunk_key(cx, cy)
	if not placed_entities_by_chunk.has(ckey):
		return {}
	var dict: Dictionary = placed_entities_by_chunk[ckey]
	for uid in dict:
		var entry: Dictionary = dict[uid]
		if int(entry.get("tile_pos_x", -999999)) == tile_pos.x and \
		   int(entry.get("tile_pos_y", -999999)) == tile_pos.y:
			return entry.duplicate(true)
	return {}

func has_placed_entity_at_tile(cx: int, cy: int, tile_pos: Vector2i) -> bool:
	return not get_placed_entity_at_tile(cx, cy, tile_pos).is_empty()

func find_placed_entity(uid: String) -> Dictionary:
	if not placed_entity_chunk_by_uid.has(uid):
		return {}
	var ckey := String(placed_entity_chunk_by_uid[uid])
	if not placed_entities_by_chunk.has(ckey):
		return {}
	var dict: Dictionary = placed_entities_by_chunk[ckey]
	if not dict.has(uid):
		return {}
	return (dict[uid] as Dictionary).duplicate(true)


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


func get_placed_entities_changes_since(serial: int) -> Dictionary:
	var since: int = maxi(serial, 0)
	var latest: int = placed_entities_change_serial
	if _placed_entities_change_log.is_empty():
		return {
			"latest_serial": latest,
			"overflow": false,
			"changes": [],
		}
	var first_serial: int = int(_placed_entities_change_log[0].get("serial", 1))
	if since < first_serial - 1:
		return {
			"latest_serial": latest,
			"overflow": true,
			"changes": [],
		}
	var changes: Array[Dictionary] = []
	for change in _placed_entities_change_log:
		var change_serial: int = int((change as Dictionary).get("serial", 0))
		if change_serial <= since:
			continue
		changes.append((change as Dictionary).duplicate(true))
	return {
		"latest_serial": latest,
		"overflow": false,
		"changes": changes,
	}


func _record_placed_entities_change(change: Dictionary) -> void:
	placed_entities_change_serial += 1
	var payload: Dictionary = change.duplicate(true)
	payload["serial"] = placed_entities_change_serial
	_placed_entities_change_log.append(payload)
	if _placed_entities_change_log.size() > PLACED_ENTITIES_CHANGE_LOG_MAX:
		_placed_entities_change_log.pop_front()

func _player_wall_tile_key(tile_pos: Vector2i) -> String:
	return "%d,%d" % [tile_pos.x, tile_pos.y]

func _player_wall_tile_from_key(tile_key: String) -> Vector2i:
	var parts: PackedStringArray = tile_key.split(",")
	if parts.size() != 2:
		return Vector2i(-999999, -999999)
	return Vector2i(int(parts[0]), int(parts[1]))

func get_enemy_state(ck: String, enemy_id: String):
	if ck == "" or enemy_id == "":
		return null
	if not enemy_state_by_chunk.has(ck):
		return null
	return enemy_state_by_chunk[ck].get(enemy_id, null)

func get_enemy_state_at_chunk_pos(chunk_pos: Vector2i, enemy_id: String):
	return get_enemy_state(chunk_key_from_pos(chunk_pos), enemy_id)

func set_enemy_state(ck: String, enemy_id: String, state: Dictionary) -> void:
	if ck == "" or enemy_id == "":
		return
	if not enemy_state_by_chunk.has(ck):
		enemy_state_by_chunk[ck] = {}
	var copy: Dictionary = state.duplicate(true)
	copy["id"] = enemy_id
	copy["chunk_key"] = ck
	if not copy.has("version"):
		copy["version"] = 1
	enemy_state_by_chunk[ck][enemy_id] = copy

func set_enemy_state_at_chunk_pos(chunk_pos: Vector2i, enemy_id: String, state: Dictionary) -> void:
	set_enemy_state(chunk_key_from_pos(chunk_pos), enemy_id, state)

func has_enemy_state(ck: String, enemy_id: String) -> bool:
	if ck == "" or enemy_id == "":
		return false
	return enemy_state_by_chunk.has(ck) and enemy_state_by_chunk[ck].has(enemy_id)

func has_enemy_state_at_chunk_pos(chunk_pos: Vector2i, enemy_id: String) -> bool:
	return has_enemy_state(chunk_key_from_pos(chunk_pos), enemy_id)

func remove_enemy_state(ck: String, enemy_id: String) -> void:
	if not enemy_state_by_chunk.has(ck):
		return
	enemy_state_by_chunk[ck].erase(enemy_id)
	if enemy_state_by_chunk[ck].is_empty():
		enemy_state_by_chunk.erase(ck)

func remove_enemy_state_at_chunk_pos(chunk_pos: Vector2i, enemy_id: String) -> void:
	remove_enemy_state(chunk_key_from_pos(chunk_pos), enemy_id)

func iter_enemy_ids_in_chunk(ck: String) -> Array[String]:
	if not enemy_state_by_chunk.has(ck):
		return []
	var ids: Array[String] = []
	for enemy_id in enemy_state_by_chunk[ck].keys():
		ids.append(String(enemy_id))
	ids.sort()
	return ids

func iter_enemy_ids_in_chunk_pos(chunk_pos: Vector2i) -> Array[String]:
	return iter_enemy_ids_in_chunk(chunk_key_from_pos(chunk_pos))

func mark_enemy_dead(ck: String, enemy_id: String) -> void:
	var state = get_enemy_state(ck, enemy_id)
	if state == null:
		return
	var copy: Dictionary = (state as Dictionary).duplicate(true)
	copy["is_dead"] = true
	copy["is_downed"] = false
	copy["last_active_time"] = RunClock.now()
	set_enemy_state(ck, enemy_id, copy)

func mark_enemy_dead_at_chunk_pos(chunk_pos: Vector2i, enemy_id: String) -> void:
	mark_enemy_dead(chunk_key_from_pos(chunk_pos), enemy_id)

func mark_enemy_downed(ck: String, enemy_id: String, resolve_at: float, entered_at: float = -1.0) -> void:
	var state = get_enemy_state(ck, enemy_id)
	if state == null:
		return
	var copy: Dictionary = (state as Dictionary).duplicate(true)
	copy["is_dead"] = false
	copy["is_downed"] = true
	copy["downed_resolve_at"] = resolve_at
	copy["downed_at"] = RunClock.now() if entered_at < 0.0 else entered_at
	copy["last_active_time"] = RunClock.now()
	set_enemy_state(ck, enemy_id, copy)

func mark_enemy_downed_at_chunk_pos(chunk_pos: Vector2i, enemy_id: String, resolve_at: float, entered_at: float = -1.0) -> void:
	mark_enemy_downed(chunk_key_from_pos(chunk_pos), enemy_id, resolve_at, entered_at)

func get_or_create_enemy_state(ck: String, enemy_id: String, default_state: Dictionary) -> Dictionary:
	var existing = get_enemy_state(ck, enemy_id)
	if existing != null:
		return (existing as Dictionary).duplicate(true)
	var created: Dictionary = default_state.duplicate(true)
	created["id"] = enemy_id
	created["chunk_key"] = ck
	if not created.has("version"):
		created["version"] = 1
	set_enemy_state(ck, enemy_id, created)
	return created.duplicate(true)

func get_or_create_enemy_state_at_chunk_pos(chunk_pos: Vector2i, enemy_id: String, default_state: Dictionary) -> Dictionary:
	return get_or_create_enemy_state(chunk_key_from_pos(chunk_pos), enemy_id, default_state)

func get_enemy_count_in_chunk(ck: String) -> int:
	if not enemy_state_by_chunk.has(ck):
		return 0
	return enemy_state_by_chunk[ck].size()

func get_enemy_count_in_chunk_pos(chunk_pos: Vector2i) -> int:
	return get_enemy_count_in_chunk(chunk_key_from_pos(chunk_pos))

func ensure_chunk_enemy_spawns(ck: String, records: Array) -> void:
	if ck == "":
		return
	if enemy_spawns_by_chunk.has(ck):
		return
	var stable_records: Array = records.duplicate(true)
	stable_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("spawn_index", 0)) < int(b.get("spawn_index", 0))
	)
	enemy_spawns_by_chunk[ck] = stable_records

func ensure_chunk_enemy_spawns_at_chunk_pos(chunk_pos: Vector2i, records: Array) -> void:
	ensure_chunk_enemy_spawns(chunk_key_from_pos(chunk_pos), records)

func get_chunk_enemy_spawns(ck: String) -> Array:
	if not enemy_spawns_by_chunk.has(ck):
		return []
	return (enemy_spawns_by_chunk[ck] as Array).duplicate(true)

func get_chunk_enemy_spawns_at_chunk_pos(chunk_pos: Vector2i) -> Array:
	return get_chunk_enemy_spawns(chunk_key_from_pos(chunk_pos))

func clear_chunk_enemy_spawns(ck: String) -> void:
	enemy_spawns_by_chunk.erase(ck)
	enemy_state_by_chunk.erase(ck)

func clear_chunk_enemy_spawns_at_chunk_pos(chunk_pos: Vector2i) -> void:
	clear_chunk_enemy_spawns(chunk_key_from_pos(chunk_pos))

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
