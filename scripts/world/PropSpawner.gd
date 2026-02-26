extends RefCounted
class_name PropSpawner

const INVALID_SPAWN_TILE := Vector2i(999999, 999999)
const SAFE_PLAYER_SPAWN_RADIUS_TILES := 3
const TAVERN_SAFE_MARGIN_TILES := 4
const SPAWN_MAX_TRIES := 30
const COPPER_FOOTPRINT_RADIUS_TILES := 0
const CAMP_FOOTPRINT_RADIUS_TILES := 2
const COPPER_MIN_DIST_TILES := 10
const DEBUG_SPAWN: bool = true

const LAYER_FLOOR: int = 1
const LAYER_WALLS: int = 2
const SRC_FLOOR: int = 1
const SRC_WALLS: int = 2
const FLOOR_WOOD: Vector2i = Vector2i(0, 0)
const ROOF_VERTICAL: Vector2i = Vector2i(0, 0)
const ROOF_CONT_LEFT: Vector2i = Vector2i(1, 0)
const ROOF_CONT_RIGHT: Vector2i = Vector2i(2, 0)
const WALL_END_RIGHT: Vector2i = Vector2i(1, 1)
const WALL_END_LEFT: Vector2i = Vector2i(2, 1)
const WALL_MID: Vector2i = Vector2i(3, 1)

var _structure_gen := StructureGenerator.new()

func generate_chunk_spawns(chunk_pos: Vector2i, ctx: Dictionary) -> void:
	var entities_spawned_chunks: Dictionary = ctx["entities_spawned_chunks"]
	if entities_spawned_chunks.has(chunk_pos):
		return
	entities_spawned_chunks[chunk_pos] = true

	var chunk_save: Dictionary = ctx["chunk_save"]
	if not chunk_save.has(chunk_pos):
		chunk_save[chunk_pos] = {
			"ores": [],
			"camps": [],
			"placed_tiles": [],
			"placements": []
		}
	else:
		if not chunk_save[chunk_pos].has("ores"): chunk_save[chunk_pos]["ores"] = []
		if not chunk_save[chunk_pos].has("camps"): chunk_save[chunk_pos]["camps"] = []
		if not chunk_save[chunk_pos].has("placed_tiles"): chunk_save[chunk_pos]["placed_tiles"] = []
		if not chunk_save[chunk_pos].has("placements"): chunk_save[chunk_pos]["placements"] = []

	var chunk_occupied_tiles: Dictionary = ctx["chunk_occupied_tiles"]
	if not chunk_occupied_tiles.has(chunk_pos):
		chunk_occupied_tiles[chunk_pos] = {}

	if chunk_pos == ctx["tavern_chunk"]:
		generate_tavern_in_chunk(chunk_pos, ctx)

	if ctx["copper_ore_scene"] == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_pos) ^ int(ctx["biome_seed"])

	var copper_positions: Array[Vector2i] = []
	var chunk_size: int = ctx["chunk_size"]
	var cx := chunk_pos.x * chunk_size + chunk_size / 2
	var cy := chunk_pos.y * chunk_size + chunk_size / 2
	var get_biome: Callable = ctx["get_biome"]
	var biome: int = int(get_biome.call(cx, cy))

	var attempts := 0
	match biome:
		2: attempts = rng.randi_range(6, 16)
		0: attempts = rng.randi_range(3, 7)
		1: attempts = rng.randi_range(0, 3)

	var chunk_center_tile := Vector2i(cx, cy)
	if _tile_distance_to_spawn(chunk_center_tile, ctx) <= 15:
		attempts = max(attempts, 1)

	var player_tile: Vector2i = ctx["player_tile"]
	var copper_spawn_failed_logged := false

	for i in range(attempts):
		var tpos: Vector2i = _find_valid_spawn_tile(
			chunk_pos, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES,
			SPAWN_MAX_TRIES, rng, COPPER_FOOTPRINT_RADIUS_TILES, ctx
		)

		if tpos == INVALID_SPAWN_TILE:
			if not copper_spawn_failed_logged:
				_debug_spawn_report(chunk_pos, player_tile, INVALID_SPAWN_TILE, "CANCEL: no valid tile after tries")
				copper_spawn_failed_logged = true
			continue

		var dist := _tile_distance_to_spawn(tpos, ctx)
		var allow_close := rng.randf() < 0.15
		if not allow_close and dist < COPPER_MIN_DIST_TILES:
			continue

		var tile_biome: int = int(get_biome.call(tpos.x, tpos.y))
		match tile_biome:
			2:
				if rng.randf() > 0.60: continue
			1:
				if rng.randf() > 0.30: continue
			0:
				if rng.randf() > 0.20: continue

		chunk_save[chunk_pos]["ores"].append({"tile": tpos, "remaining": -1})
		_mark_footprint_occupied(chunk_pos, tpos, COPPER_FOOTPRINT_RADIUS_TILES, ctx)
		copper_positions.append(tpos)

	if ctx["bandit_camp_scene"] == null or ctx["bandit_scene"] == null:
		return

	var guarded_count := int(floor(copper_positions.size() * 0.40))
	guarded_count = clampi(guarded_count, 0, 3)

	for g in range(guarded_count):
		if copper_positions.is_empty():
			break
		var idx := rng.randi_range(0, copper_positions.size() - 1)
		var copper_tile := copper_positions[idx]

		var camp_tile := _find_nearby_tile(rng, copper_tile, 6, 14, ctx)
		if camp_tile == INVALID_SPAWN_TILE:
			continue
		if not _is_spawn_tile_valid(chunk_pos, camp_tile, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES, CAMP_FOOTPRINT_RADIUS_TILES, ctx):
			continue

		chunk_save[chunk_pos]["camps"].append({"tile": camp_tile})
		_mark_footprint_occupied(chunk_pos, camp_tile, CAMP_FOOTPRINT_RADIUS_TILES, ctx)

	var random_camps := rng.randi_range(0, 2)
	var camp_spawn_failed_logged := false

	for r in range(random_camps):
		var try_tile: Vector2i = INVALID_SPAWN_TILE

		for i in range(SPAWN_MAX_TRIES):
			var candidate: Vector2i = _find_valid_spawn_tile(
				chunk_pos, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES,
				SPAWN_MAX_TRIES, rng, CAMP_FOOTPRINT_RADIUS_TILES, ctx
			)
			if candidate == INVALID_SPAWN_TILE:
				break
			if not _is_close_to_any(candidate, copper_positions, 10):
				try_tile = candidate
				break

		if try_tile == INVALID_SPAWN_TILE:
			if not camp_spawn_failed_logged:
				_debug_spawn_report(chunk_pos, player_tile, INVALID_SPAWN_TILE, "CANCEL: no valid tile after tries")
				camp_spawn_failed_logged = true
			continue

		chunk_save[chunk_pos]["camps"].append({"tile": try_tile})
		_mark_footprint_occupied(chunk_pos, try_tile, CAMP_FOOTPRINT_RADIUS_TILES, ctx)

func rebuild_chunk_occupied_tiles(chunk_key: Vector2i, ctx: Dictionary) -> void:
	_rebuild_chunk_occupied_tiles(chunk_key, ctx)

func _debug_spawn_report(chunk_key: Vector2i, player_tile: Vector2i, chosen_tile: Vector2i, reason: String) -> void:
	if not DEBUG_SPAWN:
		return
	Debug.log("spawn", "chunk=%s player_tile=%s chosen=%s -> %s" % [str(chunk_key), str(player_tile), str(chosen_tile), reason])

func _get_random_tile_in_chunk(chunk_key: Vector2i, rng: RandomNumberGenerator, ctx: Dictionary) -> Vector2i:
	var chunk_size: int = ctx["chunk_size"]
	var tx: int = rng.randi_range(chunk_key.x * chunk_size, chunk_key.x * chunk_size + chunk_size - 1)
	var ty: int = rng.randi_range(chunk_key.y * chunk_size, chunk_key.y * chunk_size + chunk_size - 1)
	return Vector2i(tx, ty)

func _is_spawn_tile_valid(chunk_key: Vector2i, tile_pos: Vector2i, player_tile: Vector2i, safe_radius_tiles: int, footprint_radius_tiles: int, ctx: Dictionary) -> bool:
	if tile_pos == INVALID_SPAWN_TILE:
		return false
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	if tile_pos.x < 0 or tile_pos.x >= width or tile_pos.y < 0 or tile_pos.y >= height:
		return false

	var occ: Dictionary = ctx["chunk_occupied_tiles"].get(chunk_key, {})
	for oy in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
		for ox in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
			var probe := tile_pos + Vector2i(ox, oy)
			if probe.x < 0 or probe.x >= width or probe.y < 0 or probe.y >= height:
				return false
			if probe.distance_to(player_tile) <= float(safe_radius_tiles):
				return false
			if occ.has(probe):
				return false
	return true

func _find_valid_spawn_tile(chunk_key: Vector2i, player_tile: Vector2i, safe_radius_tiles: int, max_tries: int, rng: RandomNumberGenerator, footprint_radius_tiles: int, ctx: Dictionary) -> Vector2i:
	var tries: int = 0
	var reject_prints: int = 0
	while tries < max_tries:
		var candidate: Vector2i = _get_random_tile_in_chunk(chunk_key, rng, ctx)
		if _is_spawn_tile_valid(chunk_key, candidate, player_tile, safe_radius_tiles, footprint_radius_tiles, ctx):
			return candidate

		if DEBUG_SPAWN and reject_prints < 3:
			var occ: Dictionary = ctx["chunk_occupied_tiles"].get(chunk_key, {})
			Debug.log("spawn", "REJECT chunk=%s cand=%s dist=%s occupied=%s reason=%s" % [str(chunk_key), str(candidate), str(candidate.distance_to(player_tile)), str(occ.has(candidate)), _get_spawn_reject_reason(chunk_key, candidate, player_tile, safe_radius_tiles, footprint_radius_tiles, ctx)])
			reject_prints += 1
		tries += 1
	return INVALID_SPAWN_TILE

func _get_spawn_reject_reason(chunk_key: Vector2i, tile_pos: Vector2i, player_tile: Vector2i, safe_radius_tiles: int, footprint_radius_tiles: int, ctx: Dictionary) -> String:
	if tile_pos == INVALID_SPAWN_TILE:
		return "invalid_spawn_tile"
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	if tile_pos.x < 0 or tile_pos.x >= width or tile_pos.y < 0 or tile_pos.y >= height:
		return "out_of_world_bounds"

	var occ: Dictionary = ctx["chunk_occupied_tiles"].get(chunk_key, {})
	for oy in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
		for ox in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
			var probe := tile_pos + Vector2i(ox, oy)
			if probe.x < 0 or probe.x >= width or probe.y < 0 or probe.y >= height:
				return "footprint_out_of_world_bounds"
			if probe.distance_to(player_tile) <= float(safe_radius_tiles):
				return "inside_safe_radius"
			if occ.has(probe):
				return "occupied"
	return "unknown"

func _mark_tile_occupied(chunk_key: Vector2i, tile_pos: Vector2i, ctx: Dictionary) -> void:
	if tile_pos == INVALID_SPAWN_TILE:
		return
	var chunk_occupied_tiles: Dictionary = ctx["chunk_occupied_tiles"]
	if not chunk_occupied_tiles.has(chunk_key):
		chunk_occupied_tiles[chunk_key] = {}
	chunk_occupied_tiles[chunk_key][tile_pos] = true

func _mark_footprint_occupied(chunk_key: Vector2i, tile_pos: Vector2i, footprint_radius_tiles: int, ctx: Dictionary) -> void:
	if tile_pos == INVALID_SPAWN_TILE:
		return
	for oy in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
		for ox in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
			_mark_tile_occupied(chunk_key, tile_pos + Vector2i(ox, oy), ctx)

func _rebuild_chunk_occupied_tiles(chunk_key: Vector2i, ctx: Dictionary) -> void:
	var chunk_occupied_tiles: Dictionary = ctx["chunk_occupied_tiles"]
	var chunk_save: Dictionary = ctx["chunk_save"]
	chunk_occupied_tiles[chunk_key] = {}
	if not chunk_save.has(chunk_key):
		return
	for d in chunk_save[chunk_key]["ores"]:
		_mark_footprint_occupied(chunk_key, d["tile"], COPPER_FOOTPRINT_RADIUS_TILES, ctx)
	for c in chunk_save[chunk_key]["camps"]:
		_mark_footprint_occupied(chunk_key, c["tile"], CAMP_FOOTPRINT_RADIUS_TILES, ctx)

func _tile_distance_to_spawn(t: Vector2i, ctx: Dictionary) -> float:
	return (ctx["spawn_tile"] as Vector2i).distance_to(t)

func _find_nearby_tile(rng: RandomNumberGenerator, origin: Vector2i, min_r: int, max_r: int, ctx: Dictionary) -> Vector2i:
	var width: int = ctx["width"]
	var height: int = ctx["height"]
	for i in range(12):
		var dx := rng.randi_range(-max_r, max_r)
		var dy := rng.randi_range(-max_r, max_r)
		var t := origin + Vector2i(dx, dy)
		if t.x < 0 or t.x >= width or t.y < 0 or t.y >= height:
			continue
		var d := origin.distance_to(t)
		if d < float(min_r) or d > float(max_r):
			continue
		return t
	return INVALID_SPAWN_TILE

func _is_close_to_any(p: Vector2i, points: Array[Vector2i], max_dist: int) -> bool:
	for q in points:
		if p.distance_to(q) <= float(max_dist):
			return true
	return false

func _place_tile_persistent(chunk_pos: Vector2i, layer: int, tile_pos: Vector2i, source: int, atlas: Vector2i, ctx: Dictionary) -> void:
	var tilemap: TileMap = ctx["tilemap"]
	var chunk_save: Dictionary = ctx["chunk_save"]
	tilemap.set_cell(layer, tile_pos, source, atlas)
	chunk_save[chunk_pos]["placed_tiles"].append({
		"layer": layer,
		"tile": tile_pos,
		"source": source,
		"atlas": atlas
	})

func generate_tavern_in_chunk(chunk_pos: Vector2i, ctx: Dictionary) -> void:
	var chunk_save: Dictionary = ctx["chunk_save"]
	if not chunk_save.has(chunk_pos):
		return
	if not chunk_save[chunk_pos].has("placed_tiles"):
		chunk_save[chunk_pos]["placed_tiles"] = []

	var chunk_size: int = ctx["chunk_size"]
	var w: int = 12
	var h: int = 8
	var x0: int = chunk_pos.x * chunk_size + 4
	var y0: int = chunk_pos.y * chunk_size + 3
	var x1: int = x0 + w - 1
	var y1: int = y0 + h - 1
	var door_x: int = x0 + w / 2

	for x in range(x0 + 1, x1):
		for y in range(y0 + 1, y1):
			_place_tile_persistent(chunk_pos, LAYER_FLOOR, Vector2i(x, y), SRC_FLOOR, FLOOR_WOOD, ctx)

	_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x0, y0 + 1), SRC_WALLS, ROOF_CONT_RIGHT, ctx)
	_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x1, y0 + 1), SRC_WALLS, ROOF_CONT_LEFT, ctx)
	for x in range(x0 + 1, x1):
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x, y0 + 1), SRC_WALLS, WALL_MID, ctx)

	for x in range(x0, x1 + 1):
		if x == door_x:
			continue
		var atlas_b: Vector2i
		if x == x0: atlas_b = WALL_END_LEFT
		elif x == x1: atlas_b = WALL_END_RIGHT
		elif x == door_x - 1: atlas_b = WALL_END_RIGHT
		elif x == door_x + 1: atlas_b = WALL_END_LEFT
		else: atlas_b = WALL_MID
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x, y1), SRC_WALLS, atlas_b, ctx)

	for y in range(y0 + 2, y1):
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x0, y), SRC_WALLS, ROOF_VERTICAL, ctx)
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x1, y), SRC_WALLS, ROOF_VERTICAL, ctx)

	for y in range(y0 - TAVERN_SAFE_MARGIN_TILES, y1 + TAVERN_SAFE_MARGIN_TILES + 1):
		for x in range(x0 - TAVERN_SAFE_MARGIN_TILES, x1 + TAVERN_SAFE_MARGIN_TILES + 1):
			_mark_tile_occupied(chunk_pos, Vector2i(x, y), ctx)

	var inner_min: Vector2i = Vector2i(x0 + 1, y0 + 1)
	var inner_max: Vector2i = Vector2i(x1 - 1, y1 - 1)
	var door_cell: Vector2i = Vector2i(door_x, y1)

	generate_tavern_furniture_simple(chunk_pos, inner_min, inner_max, door_cell, ctx)
	Debug.log("chunk", "TAVERN chunk=(%d,%d) placements=%d" % [chunk_pos.x, chunk_pos.y, chunk_save[chunk_pos].get("placements", []).size()])

	var data := _structure_gen.generate_tavern(chunk_pos, chunk_size)
	Debug.log("chunk", "STRUCT (compare) floor=%d walls=%d doors=%d placements=%d" % [
		data.floor_cells.size(),
		data.wall_cells.size(),
		data.door_cells.size(),
		data.placements.size()
	])

func _is_free(occupied: Dictionary, cell: Vector2i) -> bool:
	return not occupied.has(cell)

func _mark_rect(occupied: Dictionary, pos: Vector2i, size: Vector2i) -> void:
	for y: int in range(size.y):
		for x: int in range(size.x):
			occupied[Vector2i(pos.x + x, pos.y + y)] = true

func _rect_fits_and_free(occupied: Dictionary, pos: Vector2i, size: Vector2i, inner_min: Vector2i, inner_max: Vector2i) -> bool:
	for y: int in range(size.y):
		for x: int in range(size.x):
			var c: Vector2i = Vector2i(pos.x + x, pos.y + y)
			if c.x < inner_min.x or c.y < inner_min.y or c.x > inner_max.x or c.y > inner_max.y:
				return false
			if occupied.has(c):
				return false
	return true

func _ensure_chunk_save_key(chunk_key: Vector2i, ctx: Dictionary) -> void:
	var chunk_save: Dictionary = ctx["chunk_save"]
	if not chunk_save.has(chunk_key):
		chunk_save[chunk_key] = {
			"ores": [],
			"camps": [],
			"placed_tiles": [],
			"placements": []
		}
	if not chunk_save[chunk_key].has("placements"):
		chunk_save[chunk_key]["placements"] = []

func add_prop_placement(chunk_key: Vector2i, prop_id: String, site_id: String, cell: Vector2i, ctx: Dictionary) -> void:
	var chunk_save: Dictionary = ctx["chunk_save"]
	_ensure_chunk_save_key(chunk_key, ctx)

	for p in chunk_save[chunk_key]["placements"]:
		if typeof(p) == TYPE_DICTIONARY and String((p as Dictionary).get("site_id", "")) == site_id:
			return

	chunk_save[chunk_key]["placements"].append({
		"kind": "prop",
		"prop_id": prop_id,
		"site_id": site_id,
		"cell": [cell.x, cell.y]
	})

func generate_tavern_furniture_simple(chunk_key: Vector2i, inner_min: Vector2i, inner_max: Vector2i, door_cell: Vector2i, ctx: Dictionary) -> void:
	var chunk_save: Dictionary = ctx["chunk_save"]
	var occupied: Dictionary = {}

	for i: int in range(4):
		for w: int in range(2):
			occupied[Vector2i(door_cell.x + w, door_cell.y - i)] = true

	var counter_size: Vector2i = Vector2i(3, 1)
	var counter_pos: Vector2i = Vector2i(door_cell.x, inner_min.y + 2)
	var counter_cell: Vector2i = counter_pos
	if _rect_fits_and_free(occupied, counter_pos, counter_size, inner_min, inner_max):
		_mark_rect(occupied, counter_pos, counter_size)
		add_prop_placement(chunk_key, "counter", "tavern_counter_01", counter_pos, ctx)
		var behind: Vector2i = Vector2i(counter_pos.x, counter_pos.y - 1)
		if behind.y >= inner_min.y:
			_mark_rect(occupied, behind, Vector2i(counter_size.x, 1))
		counter_cell = Vector2i(counter_pos.x + 1, counter_pos.y - 1)

	var table_size: Vector2i = Vector2i(2, 2)
	var placed_tables: int = 0
	var candidates: Array[Vector2i] = [
		Vector2i(inner_min.x + 2, inner_max.y - 1),
		Vector2i(inner_max.x - 2, inner_max.y - 1),
	]
	for pos in candidates:
		if placed_tables >= 2:
			break
		if _rect_fits_and_free(occupied, pos, table_size, inner_min, inner_max):
			_mark_rect(occupied, pos, table_size)
			placed_tables += 1
			add_prop_placement(chunk_key, "table", "tavern_table_%02d" % placed_tables, pos, ctx)

	var corners: Array[Vector2i] = [
		Vector2i(inner_min.x, inner_min.y + 1),
		Vector2i(inner_max.x, inner_min.y + 1),
		Vector2i(inner_min.x, inner_max.y),
		Vector2i(inner_max.x, inner_max.y),
	]
	var barrel_count: int = 0
	for c in corners:
		if barrel_count >= 4:
			break
		if _is_free(occupied, c):
			occupied[c] = true
			barrel_count += 1
			add_prop_placement(chunk_key, "barrel", "tavern_barrel_%02d" % barrel_count, c, ctx)

	_ensure_chunk_save_key(chunk_key, ctx)
	for p in chunk_save[chunk_key]["placements"]:
		if typeof(p) == TYPE_DICTIONARY and String((p as Dictionary).get("site_id", "")) == "tavern_keeper_01":
			return
	chunk_save[chunk_key]["placements"].append({
		"kind": "npc_keeper",
		"site_id": "tavern_keeper_01",
		"cell": [counter_cell.x, counter_cell.y],
		"inner_min": [inner_min.x, inner_min.y],
		"inner_max": [inner_max.x, inner_max.y]
	})
