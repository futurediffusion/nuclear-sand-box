extends RefCounted
class_name WallPersistence

const HP_KEY: String = WorldSave.PLAYER_WALL_HP_KEY
const INVALID_CHUNK: Vector2i = Vector2i(-999999, -999999)
const INVALID_TILE: Vector2i = Vector2i(-999999, -999999)

func save_wall(chunk_id: Vector2i, tile: Vector2i, wall_data: Dictionary) -> bool:
	var chunk_pos: Vector2i = _normalize_chunk_id(chunk_id)
	if chunk_pos == INVALID_CHUNK:
		return false
	var tile_pos: Vector2i = _normalize_tile(tile)
	if tile_pos == INVALID_TILE:
		return false
	var serialized: Dictionary = _serialize_wall_data(wall_data)
	var hp: int = int(serialized.get(HP_KEY, 0))
	if hp <= 0:
		WorldSave.remove_player_wall(chunk_pos.x, chunk_pos.y, tile_pos)
		return true
	WorldSave.set_player_wall(chunk_pos.x, chunk_pos.y, tile_pos, hp)
	return true

func remove_wall(chunk_id: Vector2i, tile: Vector2i) -> bool:
	var chunk_pos: Vector2i = _normalize_chunk_id(chunk_id)
	if chunk_pos == INVALID_CHUNK:
		return false
	var tile_pos: Vector2i = _normalize_tile(tile)
	if tile_pos == INVALID_TILE:
		return false
	var exists: bool = has_wall(chunk_pos, tile_pos)
	if not exists:
		return false
	WorldSave.remove_player_wall(chunk_pos.x, chunk_pos.y, tile_pos)
	return true

func load_chunk_walls(chunk_id: Vector2i) -> Array[Dictionary]:
	var chunk_pos: Vector2i = _normalize_chunk_id(chunk_id)
	if chunk_pos == INVALID_CHUNK:
		return []
	var raw_entries: Array[Dictionary] = WorldSave.list_player_walls_in_chunk(chunk_pos.x, chunk_pos.y)
	var out: Array[Dictionary] = []
	for raw_entry in raw_entries:
		var tile_raw: Variant = raw_entry.get("tile", INVALID_TILE)
		if not (tile_raw is Vector2i):
			continue
		var tile_pos: Vector2i = tile_raw as Vector2i
		var wall_data: Dictionary = _deserialize_wall_data(raw_entry)
		if wall_data.is_empty():
			continue
		out.append({
			"tile": tile_pos,
			"wall_data": wall_data,
		})
	return out

func list_player_walls(player_id: String = "") -> Array[Dictionary]:
	var ignored_player_id: String = player_id
	if ignored_player_id != "":
		# Schema actual: walls no distinguen owner por player. El parámetro queda reservado.
		pass
	var chunk_keys: Array = WorldSave.player_walls_by_chunk.keys()
	chunk_keys.sort()
	var out: Array[Dictionary] = []
	for chunk_key in chunk_keys:
		var chunk_pos: Vector2i = _chunk_from_world_save_key(String(chunk_key))
		if chunk_pos == INVALID_CHUNK:
			continue
		var chunk_entries: Array[Dictionary] = load_chunk_walls(chunk_pos)
		for entry in chunk_entries:
			out.append({
				"chunk_id": chunk_pos,
				"tile": entry.get("tile", INVALID_TILE),
				"wall_data": entry.get("wall_data", {}),
			})
	return out

func has_wall(chunk_id: Vector2i, tile: Vector2i) -> bool:
	return not get_wall(chunk_id, tile).is_empty()

func get_wall(chunk_id: Vector2i, tile: Vector2i) -> Dictionary:
	var chunk_pos: Vector2i = _normalize_chunk_id(chunk_id)
	if chunk_pos == INVALID_CHUNK:
		return {}
	var tile_pos: Vector2i = _normalize_tile(tile)
	if tile_pos == INVALID_TILE:
		return {}
	var chunk_walls: Array[Dictionary] = load_chunk_walls(chunk_pos)
	for entry in chunk_walls:
		var entry_tile: Variant = entry.get("tile", INVALID_TILE)
		if entry_tile is Vector2i and (entry_tile as Vector2i) == tile_pos:
			var wall_data: Variant = entry.get("wall_data", {})
			if wall_data is Dictionary:
				return (wall_data as Dictionary).duplicate(true)
	return {}

func _serialize_wall_data(wall_data: Dictionary) -> Dictionary:
	var hp: int = int(wall_data.get(HP_KEY, wall_data.get("hp", 0)))
	return {
		HP_KEY: hp,
	}

func _deserialize_wall_data(raw_wall_data: Dictionary) -> Dictionary:
	var hp: int = int(raw_wall_data.get(HP_KEY, raw_wall_data.get("hp", 0)))
	if hp <= 0:
		return {}
	return {
		HP_KEY: hp,
	}

func _normalize_chunk_id(chunk_id: Variant) -> Vector2i:
	if chunk_id is Vector2i:
		return chunk_id as Vector2i
	return INVALID_CHUNK

func _normalize_tile(tile: Variant) -> Vector2i:
	if tile is Vector2i:
		return tile as Vector2i
	return INVALID_TILE

func _chunk_from_world_save_key(chunk_key: String) -> Vector2i:
	var parts: PackedStringArray = chunk_key.split(",")
	if parts.size() != 2:
		return INVALID_CHUNK
	return Vector2i(int(parts[0]), int(parts[1]))
