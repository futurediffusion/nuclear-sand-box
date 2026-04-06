extends BuildingRepository
class_name WorldSaveBuildingRepository

## WorldSave-backed building repository adapter.
##
## This is the persistence boundary implementation for the building module.
## It keeps compatibility with the existing player wall save schema in
## WorldSave.player_walls_by_chunk (tile_key -> {"hp": int}) and only adapts
## data into the BuildingState record shape required by the domain.

const PLAYER_WALL_KIND: String = "player_wall"

func save_structure(structure: Dictionary) -> Dictionary:
	var normalized: Dictionary = _normalize_structure(structure)
	if normalized.is_empty():
		return {}
	var chunk_pos: Vector2i = normalized.get(BuildingState.STRUCTURE_KEY_CHUNK_POS, Vector2i.ZERO)
	var tile_pos: Vector2i = normalized.get(BuildingState.STRUCTURE_KEY_TILE_POS, Vector2i.ZERO)
	var hp: int = int(normalized.get(BuildingState.STRUCTURE_KEY_HP, 0))
	if hp <= 0:
		remove_structure(chunk_pos, tile_pos)
		return {}
	WorldSave.set_player_wall(chunk_pos.x, chunk_pos.y, tile_pos, hp)
	return normalized

func remove_structure(chunk_pos: Vector2i, tile_pos: Vector2i) -> bool:
	var existed: bool = WorldSave.has_player_wall(chunk_pos.x, chunk_pos.y, tile_pos)
	WorldSave.remove_player_wall(chunk_pos.x, chunk_pos.y, tile_pos)
	return existed

func load_structures_in_chunk(chunk_pos: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw_entry in WorldSave.list_player_walls_in_chunk(chunk_pos.x, chunk_pos.y):
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var tile_raw: Variant = entry.get("tile", Vector2i(-1, -1))
		if not (tile_raw is Vector2i):
			continue
		var structure: Dictionary = _normalize_structure({
			BuildingState.STRUCTURE_KEY_CHUNK_POS: chunk_pos,
			BuildingState.STRUCTURE_KEY_TILE_POS: tile_raw,
			BuildingState.STRUCTURE_KEY_HP: int(entry.get("hp", 0)),
			BuildingState.STRUCTURE_KEY_MAX_HP: int(entry.get("hp", 0)),
			BuildingState.STRUCTURE_KEY_KIND: PLAYER_WALL_KIND,
			BuildingState.STRUCTURE_KEY_METADATA: BuildingState.create_player_wall_metadata(true, "wallwood", 1),
		})
		if structure.is_empty():
			continue
		out.append(structure)
	return out

func get_structure_by_tile(chunk_pos: Vector2i, tile_pos: Vector2i) -> Dictionary:
	var raw: Dictionary = WorldSave.get_player_wall(chunk_pos.x, chunk_pos.y, tile_pos)
	if raw.is_empty():
		return {}
	return _normalize_structure({
		BuildingState.STRUCTURE_KEY_CHUNK_POS: chunk_pos,
		BuildingState.STRUCTURE_KEY_TILE_POS: tile_pos,
		BuildingState.STRUCTURE_KEY_HP: int(raw.get("hp", 0)),
		BuildingState.STRUCTURE_KEY_MAX_HP: int(raw.get("hp", 0)),
		BuildingState.STRUCTURE_KEY_KIND: PLAYER_WALL_KIND,
		BuildingState.STRUCTURE_KEY_METADATA: BuildingState.create_player_wall_metadata(true, "wallwood", 1),
	})

func get_structure_by_key(structure_id: String) -> Dictionary:
	var parsed: Dictionary = _parse_structure_key(structure_id)
	if parsed.is_empty():
		return {}
	var chunk_pos_raw: Variant = parsed.get(BuildingState.STRUCTURE_KEY_CHUNK_POS, Vector2i.ZERO)
	var tile_pos_raw: Variant = parsed.get(BuildingState.STRUCTURE_KEY_TILE_POS, Vector2i.ZERO)
	if not (chunk_pos_raw is Vector2i) or not (tile_pos_raw is Vector2i):
		return {}
	var structure := get_structure_by_tile(chunk_pos_raw as Vector2i, tile_pos_raw as Vector2i)
	if structure.is_empty():
		return {}
	if String(structure.get(BuildingState.STRUCTURE_KEY_ID, "")) != structure_id:
		return {}
	return structure

func list_structures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for chunk_key_raw in WorldSave.player_walls_by_chunk.keys():
		var chunk_pos: Vector2i = WorldSave.chunk_pos_from_key(String(chunk_key_raw))
		if chunk_pos == WorldSave.INVALID_CHUNK_POS:
			continue
		out.append_array(load_structures_in_chunk(chunk_pos))
	return out

func _normalize_structure(structure: Dictionary) -> Dictionary:
	var chunk_pos_raw: Variant = structure.get(BuildingState.STRUCTURE_KEY_CHUNK_POS, Vector2i.ZERO)
	var tile_pos_raw: Variant = structure.get(BuildingState.STRUCTURE_KEY_TILE_POS, Vector2i.ZERO)
	if not (chunk_pos_raw is Vector2i) or not (tile_pos_raw is Vector2i):
		return {}
	var chunk_pos: Vector2i = chunk_pos_raw as Vector2i
	var tile_pos: Vector2i = tile_pos_raw as Vector2i
	var kind: String = String(structure.get(BuildingState.STRUCTURE_KEY_KIND, PLAYER_WALL_KIND)).strip_edges()
	if kind.is_empty():
		kind = PLAYER_WALL_KIND
	var hp: int = int(structure.get(BuildingState.STRUCTURE_KEY_HP, 0))
	if hp <= 0:
		return {}
	var max_hp: int = int(structure.get(BuildingState.STRUCTURE_KEY_MAX_HP, hp))
	if max_hp <= 0:
		max_hp = hp
	var metadata: Dictionary = structure.get(BuildingState.STRUCTURE_KEY_METADATA, {}) as Dictionary
	if metadata.is_empty():
		metadata = BuildingState.create_player_wall_metadata(true, "wallwood", 1)
	var structure_id: String = String(structure.get(BuildingState.STRUCTURE_KEY_ID, "")).strip_edges()
	if structure_id.is_empty():
		structure_id = BuildingState.build_structure_key(kind, chunk_pos, tile_pos)
	return BuildingState.create_structure_record(
		structure_id,
		chunk_pos,
		tile_pos,
		kind,
		hp,
		max_hp,
		metadata
	)

func _parse_structure_key(structure_id: String) -> Dictionary:
	var parts: PackedStringArray = structure_id.split(":")
	if parts.size() != 5:
		return {}
	var kind: String = String(parts[0]).strip_edges()
	if kind.is_empty():
		return {}
	return {
		BuildingState.STRUCTURE_KEY_KIND: kind,
		BuildingState.STRUCTURE_KEY_CHUNK_POS: Vector2i(int(parts[1]), int(parts[2])),
		BuildingState.STRUCTURE_KEY_TILE_POS: Vector2i(int(parts[3]), int(parts[4])),
	}
