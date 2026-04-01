extends RefCounted
class_name StructuralWallPersistence

const WALL_HP_KEY: String = "hp"
const WALL_TILE_KEY: String = "tile"
const WALL_LAYER_KEY: String = "layer"
const WALL_SOURCE_KEY: String = "source"
const WALL_ATLAS_KEY: String = "atlas"
const WALL_KIND_KEY: String = "kind"
const WALL_TYPE_KEY: String = "wall_type"

var chunk_save: Dictionary = {}
var walls_map_layer: int = 1
var structural_wall_source: int = -1
var structural_wall_default_hp: int = 1

func setup(ctx: Dictionary) -> void:
	chunk_save = ctx.get("chunk_save", {})
	walls_map_layer = int(ctx.get("walls_map_layer", walls_map_layer))
	structural_wall_source = int(ctx.get("structural_wall_source", structural_wall_source))
	structural_wall_default_hp = maxi(1, int(ctx.get("structural_wall_default_hp", structural_wall_default_hp)))

func has_wall(chunk_pos: Vector2i, tile_pos: Vector2i) -> bool:
	return not get_wall(chunk_pos, tile_pos).is_empty()

func get_wall(chunk_pos: Vector2i, tile_pos: Vector2i) -> Dictionary:
	var placed_tiles: Array = _get_chunk_placed_tiles(chunk_pos)
	for raw_tile in placed_tiles:
		if typeof(raw_tile) != TYPE_DICTIONARY:
			continue
		var tile_data: Dictionary = raw_tile as Dictionary
		if not _is_structural_entry(tile_data):
			continue
		var saved_tile: Variant = tile_data.get(WALL_TILE_KEY, Vector2i(-1, -1))
		if not (saved_tile is Vector2i):
			continue
		if (saved_tile as Vector2i) != tile_pos:
			continue
		return deserialize_wall_data(tile_data)
	return {}

func save_wall(chunk_pos: Vector2i, tile_pos: Vector2i, wall_data: Dictionary) -> void:
	var normalized: Dictionary = serialize_wall_data(tile_pos, wall_data)
	if normalized.is_empty():
		push_warning("StructuralWallPersistence.save_wall: rejected payload for chunk=%s tile=%s" % [str(chunk_pos), str(tile_pos)])
		return
	_ensure_chunk_entry(chunk_pos)
	var placed_tiles: Array = _get_chunk_placed_tiles(chunk_pos)
	for i in range(placed_tiles.size()):
		if typeof(placed_tiles[i]) != TYPE_DICTIONARY:
			continue
		var tile_data: Dictionary = placed_tiles[i] as Dictionary
		if not _is_structural_entry(tile_data):
			continue
		var saved_tile: Variant = tile_data.get(WALL_TILE_KEY, Vector2i(-1, -1))
		if not (saved_tile is Vector2i):
			continue
		if (saved_tile as Vector2i) != tile_pos:
			continue
		placed_tiles[i] = normalized
		chunk_save[chunk_pos]["placed_tiles"] = placed_tiles
		return
	placed_tiles.append(normalized)
	chunk_save[chunk_pos]["placed_tiles"] = placed_tiles

func remove_wall(chunk_pos: Vector2i, tile_pos: Vector2i) -> void:
	var placed_tiles: Array = _get_chunk_placed_tiles(chunk_pos)
	if placed_tiles.is_empty():
		return
	var next_tiles: Array = []
	for raw_tile in placed_tiles:
		if typeof(raw_tile) != TYPE_DICTIONARY:
			next_tiles.append(raw_tile)
			continue
		var tile_data: Dictionary = raw_tile as Dictionary
		if not _is_structural_entry(tile_data):
			next_tiles.append(tile_data)
			continue
		var saved_tile: Variant = tile_data.get(WALL_TILE_KEY, Vector2i(-1, -1))
		if not (saved_tile is Vector2i) or (saved_tile as Vector2i) != tile_pos:
			next_tiles.append(tile_data)
	chunk_save[chunk_pos]["placed_tiles"] = next_tiles

func load_chunk_walls(chunk_pos: Vector2i) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for raw_tile in _get_chunk_placed_tiles(chunk_pos):
		if typeof(raw_tile) != TYPE_DICTIONARY:
			continue
		var tile_data: Dictionary = raw_tile as Dictionary
		if not _is_structural_entry(tile_data):
			continue
		var deserialized: Dictionary = deserialize_wall_data(tile_data)
		if deserialized.is_empty():
			continue
		entries.append(deserialized)
	return entries

func list_walls_in_chunk(chunk_pos: Vector2i) -> Array[Dictionary]:
	return load_chunk_walls(chunk_pos)

func serialize_wall_data(tile_pos: Vector2i, wall_data: Dictionary) -> Dictionary:
	if not wall_data.has(WALL_HP_KEY):
		return {}
	var hp: int = int(wall_data.get(WALL_HP_KEY, 0))
	if hp <= 0:
		return {}
	var serialized: Dictionary = {
		WALL_LAYER_KEY: walls_map_layer,
		WALL_TILE_KEY: tile_pos,
		WALL_SOURCE_KEY: structural_wall_source,
		WALL_ATLAS_KEY: Vector2i(-1, -1),
		WALL_HP_KEY: hp,
	}
	if wall_data.has(WALL_KIND_KEY):
		serialized[WALL_KIND_KEY] = wall_data.get(WALL_KIND_KEY)
	if wall_data.has(WALL_TYPE_KEY):
		serialized[WALL_TYPE_KEY] = wall_data.get(WALL_TYPE_KEY)
	return serialized

func deserialize_wall_data(raw_data: Dictionary) -> Dictionary:
	if not _is_structural_entry(raw_data):
		return {}
	var tile_raw: Variant = raw_data.get(WALL_TILE_KEY, Vector2i(-1, -1))
	if not (tile_raw is Vector2i):
		return {}
	var hp: int = int(raw_data.get(WALL_HP_KEY, structural_wall_default_hp))
	if hp <= 0:
		return {}
	var out: Dictionary = {
		WALL_TILE_KEY: tile_raw,
		WALL_HP_KEY: hp,
		WALL_LAYER_KEY: walls_map_layer,
		WALL_SOURCE_KEY: structural_wall_source,
		WALL_ATLAS_KEY: raw_data.get(WALL_ATLAS_KEY, Vector2i(-1, -1)),
	}
	if raw_data.has(WALL_KIND_KEY):
		out[WALL_KIND_KEY] = raw_data.get(WALL_KIND_KEY)
	if raw_data.has(WALL_TYPE_KEY):
		out[WALL_TYPE_KEY] = raw_data.get(WALL_TYPE_KEY)
	return out

func _is_structural_entry(tile_data: Dictionary) -> bool:
	var layer: int = int(tile_data.get(WALL_LAYER_KEY, -9999))
	if layer != walls_map_layer:
		return false
	var source_id: int = int(tile_data.get(WALL_SOURCE_KEY, 0))
	return source_id == structural_wall_source

func _ensure_chunk_entry(chunk_pos: Vector2i) -> void:
	if not chunk_save.has(chunk_pos) or typeof(chunk_save[chunk_pos]) != TYPE_DICTIONARY:
		chunk_save[chunk_pos] = {}
	if not (chunk_save[chunk_pos] as Dictionary).has("placed_tiles"):
		chunk_save[chunk_pos]["placed_tiles"] = []

func _get_chunk_placed_tiles(chunk_pos: Vector2i) -> Array:
	if not chunk_save.has(chunk_pos):
		return []
	var chunk_data: Variant = chunk_save[chunk_pos]
	if typeof(chunk_data) != TYPE_DICTIONARY:
		return []
	return (chunk_data as Dictionary).get("placed_tiles", [])
