extends RefCounted
class_name WallPersistence

const WALL_HP_KEY: String = "hp"

func save_wall(chunk_id: Vector2i, tile: Vector2i, wall_data: Dictionary) -> void:
	var serialized: Dictionary = serialize_wall_data(wall_data)
	var hp: int = int(serialized.get(WALL_HP_KEY, 0))
	if hp <= 0:
		remove_wall(chunk_id, tile)
		return
	WorldSave.set_player_wall(chunk_id.x, chunk_id.y, tile, hp)

func remove_wall(chunk_id: Vector2i, tile: Vector2i) -> void:
	WorldSave.remove_player_wall(chunk_id.x, chunk_id.y, tile)

func load_chunk_walls(chunk_id: Vector2i) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for raw_entry in WorldSave.list_player_walls_in_chunk(chunk_id.x, chunk_id.y):
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var tile_raw: Variant = entry.get("tile", Vector2i(-1, -1))
		if not (tile_raw is Vector2i):
			continue
		var deserialized: Dictionary = deserialize_wall_data(entry)
		if deserialized.is_empty():
			continue
		entries.append({
			"tile": tile_raw,
			"wall_data": deserialized,
		})
	return entries

func list_player_walls(_player_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for chunk_key_raw in WorldSave.player_walls_by_chunk.keys():
		var chunk_id: Vector2i = _parse_chunk_key(String(chunk_key_raw))
		if chunk_id.x <= -999999:
			continue
		for entry in load_chunk_walls(chunk_id):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = entry as Dictionary
			row["chunk_id"] = chunk_id
			out.append(row)
	return out

func has_wall(chunk_id: Vector2i, tile: Vector2i) -> bool:
	var data: Dictionary = get_wall(chunk_id, tile)
	return not data.is_empty()

func get_wall(chunk_id: Vector2i, tile: Vector2i) -> Dictionary:
	var raw: Dictionary = WorldSave.get_player_wall(chunk_id.x, chunk_id.y, tile)
	if raw.is_empty():
		return {}
	return deserialize_wall_data(raw)

func serialize_wall_data(wall_data: Dictionary) -> Dictionary:
	var hp: int = int(wall_data.get(WALL_HP_KEY, 0))
	if hp <= 0:
		return {}
	return {WALL_HP_KEY: hp}

func deserialize_wall_data(raw_data: Dictionary) -> Dictionary:
	var hp: int = int(raw_data.get(WALL_HP_KEY, 0))
	if hp <= 0:
		return {}
	return {WALL_HP_KEY: hp}

func _parse_chunk_key(chunk_key: String) -> Vector2i:
	var parts: PackedStringArray = chunk_key.split(",")
	if parts.size() != 2:
		return Vector2i(-999999, -999999)
	return Vector2i(int(parts[0]), int(parts[1]))
