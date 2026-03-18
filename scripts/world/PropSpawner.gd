extends RefCounted
class_name PropSpawner

const INVALID_SPAWN_TILE := Vector2i(999999, 999999)
const SAFE_PLAYER_SPAWN_RADIUS_TILES := 3
const TAVERN_SAFE_MARGIN_TILES := 4
const SPAWN_MAX_TRIES := 30
const COPPER_FOOTPRINT_RADIUS_TILES := 0
const CAMP_FOOTPRINT_RADIUS_TILES := 2
const COPPER_MIN_DIST_TILES := 10
const STONE_FOOTPRINT_RADIUS_TILES := 0
const STONE_MIN_DIST_TILES := 6
const TREE_FOOTPRINT_RADIUS_TILES := 1
const TREE_MIN_DIST_TILES := 3
const GRASS_FOOTPRINT_RADIUS_TILES := 0
const GRASS_MIN_DIST_TILES := 1
const DEBUG_SPAWN: bool = true
const USE_WALL_TERRAIN: bool = true
const TAVERN_BARREL_SEED_FLAG: String = "tavern_barrels_seeded_v1"
const TAVERN_BARREL_SCENE_PATH: String = "res://scenes/placeables/barrel_world.tscn"
const TAVERN_BARREL_ITEM_ID: String = "barrel"
const TAVERN_TABLE_SEED_FLAG: String = "tavern_tables_seeded_v1"
const TAVERN_TABLE_SCENE_PATH: String = "res://scenes/placeables/table_world.tscn"
const TAVERN_TABLE_ITEM_ID: String = "table"
const TAVERN_STOOL_SEED_FLAG: String = "tavern_stools_seeded_v1"
const TAVERN_TILES_SEED_FLAG: String = "tavern_tiles_seeded_v1"
const TAVERN_STOOL_SCENE_PATH: String = "res://scenes/placeables/stool_world.tscn"
const TAVERN_STOOL_ITEM_ID: String = "stool"

const LAYER_FLOOR: int = 1
const LAYER_WALLS: int = 0
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
			"stones": [],
			"trees": [],
			"grasses": [],
			"camps": [],
			"placed_tiles": [],
			"placements": []
		}
	else:
		if not chunk_save[chunk_pos].has("ores"): chunk_save[chunk_pos]["ores"] = []
		if not chunk_save[chunk_pos].has("stones"): chunk_save[chunk_pos]["stones"] = []
		if not chunk_save[chunk_pos].has("trees"): chunk_save[chunk_pos]["trees"] = []
		if not chunk_save[chunk_pos].has("grasses"): chunk_save[chunk_pos]["grasses"] = []
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
		2: attempts = rng.randi_range(ctx.get("copper_dirt_min", 2), ctx.get("copper_dirt_max", 5))
		0: attempts = rng.randi_range(3, 7)
		1: attempts = rng.randi_range(ctx.get("copper_grass_min", 0), ctx.get("copper_grass_max", 1))

	if _is_test_density_chunk(chunk_pos, ctx):
		attempts += max(0, int(Debug.test_density_extra_copper_per_chunk_load))

	var chunk_center_tile := Vector2i(cx, cy)
	if _tile_distance_to_spawn(chunk_center_tile, ctx) <= 15.0:
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
		if not allow_close and dist < float(COPPER_MIN_DIST_TILES):
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

	# --- STONES (2× copper density) ---
	if ctx.get("stone_ore_scene") != null:
		var stone_attempts := 0
		match biome:
			2: stone_attempts = rng.randi_range(ctx.get("stone_dirt_min", 4), ctx.get("stone_dirt_max", 10))
			0: stone_attempts = rng.randi_range(0, 1)
			1: stone_attempts = rng.randi_range(ctx.get("stone_grass_min", 0), ctx.get("stone_grass_max", 2))

		for _si in range(stone_attempts):
			var stpos: Vector2i = _find_valid_spawn_tile(
				chunk_pos, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES,
				SPAWN_MAX_TRIES, rng, STONE_FOOTPRINT_RADIUS_TILES, ctx
			)
			if stpos == INVALID_SPAWN_TILE:
				continue

			var sdist := _tile_distance_to_spawn(stpos, ctx)
			var sallow_close := rng.randf() < 0.15
			if not sallow_close and sdist < float(STONE_MIN_DIST_TILES):
				continue

			var stile_biome: int = int(get_biome.call(stpos.x, stpos.y))
			match stile_biome:
				2:
					if rng.randf() > 0.70: continue
				1:
					if rng.randf() > 0.50: continue
				0:
					if rng.randf() > 0.30: continue

			chunk_save[chunk_pos]["stones"].append({"tile": stpos, "remaining": -1})
			_mark_footprint_occupied(chunk_pos, stpos, STONE_FOOTPRINT_RADIUS_TILES, ctx)

	# --- TREES ---
	if ctx.get("tree_scene") != null:
		var tree_attempts := 0
		match biome:
			1: tree_attempts = rng.randi_range(ctx.get("tree_grass_min", 5), ctx.get("tree_grass_max", 10))
			2: tree_attempts = rng.randi_range(ctx.get("tree_dirt_min", 1), ctx.get("tree_dirt_max", 3))
			0: tree_attempts = 0

		for _ti in range(tree_attempts):
			var ttpos: Vector2i = _find_valid_spawn_tile(
				chunk_pos, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES,
				SPAWN_MAX_TRIES, rng, TREE_FOOTPRINT_RADIUS_TILES, ctx
			)
			if ttpos == INVALID_SPAWN_TILE:
				continue

			var tdist := _tile_distance_to_spawn(ttpos, ctx)
			var tallow_close := rng.randf() < 0.15
			if not tallow_close and tdist < float(TREE_MIN_DIST_TILES):
				continue

			chunk_save[chunk_pos]["trees"].append({"tile": ttpos})
			_mark_footprint_occupied(chunk_pos, ttpos, TREE_FOOTPRINT_RADIUS_TILES, ctx)

	# --- GRASS TUFTS ---
	if ctx.get("grass_tuft_scene") != null:
		var grass_attempts := 0
		match biome:
			1: grass_attempts = rng.randi_range(ctx.get("grass_tuft_grass_min", 10), ctx.get("grass_tuft_grass_max", 20))
			2: grass_attempts = rng.randi_range(ctx.get("grass_tuft_dirt_min", 2), ctx.get("grass_tuft_dirt_max", 6))
			0: grass_attempts = 0

		for _gi in range(grass_attempts):
			var gpos: Vector2i = _find_valid_spawn_tile(
				chunk_pos, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES,
				SPAWN_MAX_TRIES, rng, GRASS_FOOTPRINT_RADIUS_TILES, ctx
			)
			if gpos == INVALID_SPAWN_TILE:
				continue

			var gdist := _tile_distance_to_spawn(gpos, ctx)
			if gdist < float(GRASS_MIN_DIST_TILES):
				continue

			chunk_save[chunk_pos]["grasses"].append({"tile": gpos})
			_mark_footprint_occupied(chunk_pos, gpos, GRASS_FOOTPRINT_RADIUS_TILES, ctx)

	if ctx["bandit_camp_scene"] == null or ctx["bandit_scene"] == null:
		return

	# Solo existe 1 campamento en todo el mundo
	if WorldSave.global_flags.get("global_camp_placed", false):
		return

	var camp_tile: Vector2i = INVALID_SPAWN_TILE
	for cp in copper_positions:
		var candidate := _find_nearby_tile(rng, cp, 6, 14, ctx)
		if candidate == INVALID_SPAWN_TILE:
			continue
		if _is_spawn_tile_valid(chunk_pos, candidate, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES, CAMP_FOOTPRINT_RADIUS_TILES, ctx):
			camp_tile = candidate
			break
	if camp_tile == INVALID_SPAWN_TILE:
		camp_tile = _find_valid_spawn_tile(
			chunk_pos, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES,
			SPAWN_MAX_TRIES, rng, CAMP_FOOTPRINT_RADIUS_TILES, ctx
		)
	if camp_tile == INVALID_SPAWN_TILE:
		_debug_spawn_report(chunk_pos, player_tile, INVALID_SPAWN_TILE, "CANCEL: no valid tile for global camp")
		return

	chunk_save[chunk_pos]["camps"].append({"tile": camp_tile})
	_mark_footprint_occupied(chunk_pos, camp_tile, CAMP_FOOTPRINT_RADIUS_TILES, ctx)
	WorldSave.global_flags["global_camp_placed"] = true


func _is_test_density_chunk(chunk_pos: Vector2i, ctx: Dictionary) -> bool:
	if not Debug.test_density_enabled:
		return false
	if not ctx.has("player_chunk"):
		return false
	var player_chunk: Vector2i = ctx["player_chunk"]
	return abs(chunk_pos.x - player_chunk.x) <= 1 and abs(chunk_pos.y - player_chunk.y) <= 1

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
	var cg = ctx.get("cliff_generator")
	for oy in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
		for ox in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
			var probe := tile_pos + Vector2i(ox, oy)
			if probe.x < 0 or probe.x >= width or probe.y < 0 or probe.y >= height:
				return false
			if probe.distance_to(player_tile) <= float(safe_radius_tiles):
				return false
			if occ.has(probe):
				return false
			if cg != null and cg.is_cliff_tile(probe):
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
	for d in chunk_save[chunk_key].get("stones", []):
		_mark_footprint_occupied(chunk_key, d["tile"], STONE_FOOTPRINT_RADIUS_TILES, ctx)
	for d in chunk_save[chunk_key].get("trees", []):
		_mark_footprint_occupied(chunk_key, d["tile"], TREE_FOOTPRINT_RADIUS_TILES, ctx)
	for d in chunk_save[chunk_key].get("grasses", []):
		_mark_footprint_occupied(chunk_key, d["tile"], GRASS_FOOTPRINT_RADIUS_TILES, ctx)
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
	_ensure_chunk_save_key(chunk_pos, ctx)
	var chunk_save: Dictionary = ctx["chunk_save"]
	if not chunk_save[chunk_pos].has("placed_tiles"):
		chunk_save[chunk_pos]["placed_tiles"] = []
	if not chunk_save[chunk_pos].has("placements"):
		chunk_save[chunk_pos]["placements"] = []

	var data := _structure_gen.generate_tavern(chunk_pos, int(ctx["chunk_size"]))
	_align_existing_tavern_barrels_to_structure(data.placements)
	_align_existing_tavern_tables_to_structure(data.placements)
	_align_existing_tavern_stools_to_structure(data.placements)
	_seed_tavern_barrels_as_placeables(data.placements)
	_seed_tavern_tables_as_placeables(data.placements)
	_seed_tavern_stools_as_placeables(data.placements)
	_remove_legacy_tavern_barrel_props(chunk_pos, ctx)
	_remove_legacy_tavern_table_props(chunk_pos, ctx)
	_remove_legacy_tavern_stool_props(chunk_pos, ctx)
	var bounds: Rect2i = data.bounds
	var x0: int = bounds.position.x
	var y0: int = bounds.position.y
	var x1: int = x0 + bounds.size.x - 1
	var y1: int = y0 + bounds.size.y - 1
	var door_x: int = x0 + bounds.size.x / 2
	var structural_wall_default_hp: int = maxi(1, int(ctx.get("structural_wall_default_hp", 1)))

	# Only write floor/wall tiles the first time. On subsequent loads the saved
	# placed_tiles array already reflects the player's destruction state — re-writing
	# here would restore destroyed tiles with full HP.
	if not bool(WorldSave.global_flags.get(TAVERN_TILES_SEED_FLAG, false)):
		for cell in data.floor_cells:
			_place_tile_persistent(chunk_pos, LAYER_FLOOR, cell, SRC_FLOOR, FLOOR_WOOD, ctx)

		for cell in data.wall_cells:
			if USE_WALL_TERRAIN:
				chunk_save[chunk_pos]["placed_tiles"].append({
					"layer": LAYER_WALLS,
					"tile": cell,
					"source": -1,
					"atlas": Vector2i(-1, -1),
					"hp": structural_wall_default_hp,
				})
			else:
				var atlas: Vector2i = WALL_MID
				if cell.y == y0 + 1:
					if cell.x == x0:
						atlas = ROOF_CONT_RIGHT
					elif cell.x == x1:
						atlas = ROOF_CONT_LEFT
					else:
						atlas = WALL_MID
				elif cell.y == y1:
					if cell.x == x0:
						atlas = WALL_END_LEFT
					elif cell.x == x1:
						atlas = WALL_END_RIGHT
					elif cell.x == door_x - 1:
						atlas = WALL_END_RIGHT
					elif cell.x == door_x + 1:
						atlas = WALL_END_LEFT
					else:
						atlas = WALL_MID
				else:
					atlas = ROOF_VERTICAL
				_place_tile_persistent(chunk_pos, LAYER_WALLS, cell, SRC_WALLS, atlas, ctx)

		WorldSave.global_flags[TAVERN_TILES_SEED_FLAG] = true

	for p in data.placements:
		if _is_tavern_barrel_placement(p) or _is_tavern_table_placement(p) or _is_tavern_stool_placement(p):
			continue
		var exists := false
		var site_id := String(p.get("site_id", ""))
		if site_id != "":
			for existing in chunk_save[chunk_pos]["placements"]:
				if typeof(existing) == TYPE_DICTIONARY and String((existing as Dictionary).get("site_id", "")) == site_id:
					exists = true
					break
		if not exists:
			chunk_save[chunk_pos]["placements"].append(p)

	var tavern_safe_margin: int = TAVERN_SAFE_MARGIN_TILES
	for y in range(y0 - tavern_safe_margin, y1 + tavern_safe_margin + 1):
		for x in range(x0 - tavern_safe_margin, x1 + tavern_safe_margin + 1):
			_mark_tile_occupied(chunk_pos, Vector2i(x, y), ctx)

	Debug.log("chunk", "TAVERN generated (StructureGen) chunk=(%d,%d) floor=%d walls=%d placements=%d" % [
		chunk_pos.x,
		chunk_pos.y,
		data.floor_cells.size(),
		data.wall_cells.size(),
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

func _is_tavern_barrel_placement(raw: Variant) -> bool:
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var p := raw as Dictionary
	return String(p.get("kind", "")) == "prop" and String(p.get("prop_id", "")) == "barrel"

func _is_tavern_table_placement(raw: Variant) -> bool:
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var p := raw as Dictionary
	return String(p.get("kind", "")) == "prop" and String(p.get("prop_id", "")) == "table"

func _is_tavern_stool_placement(raw: Variant) -> bool:
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var p := raw as Dictionary
	return String(p.get("kind", "")) == "prop" and String(p.get("prop_id", "")) == "stool"

func _remove_legacy_tavern_barrel_props(chunk_key: Vector2i, ctx: Dictionary) -> void:
	var chunk_save: Dictionary = ctx["chunk_save"]
	if not chunk_save.has(chunk_key):
		return
	var placements_raw: Variant = chunk_save[chunk_key].get("placements", null)
	if not (placements_raw is Array):
		return
	var placements: Array = placements_raw
	var filtered: Array = []
	for raw in placements:
		if _is_tavern_barrel_placement(raw):
			continue
		filtered.append(raw)
	chunk_save[chunk_key]["placements"] = filtered

func _remove_legacy_tavern_table_props(chunk_key: Vector2i, ctx: Dictionary) -> void:
	var chunk_save: Dictionary = ctx["chunk_save"]
	if not chunk_save.has(chunk_key):
		return
	var placements_raw: Variant = chunk_save[chunk_key].get("placements", null)
	if not (placements_raw is Array):
		return
	var placements: Array = placements_raw
	var filtered: Array = []
	for raw in placements:
		if _is_tavern_table_placement(raw):
			continue
		filtered.append(raw)
	chunk_save[chunk_key]["placements"] = filtered

func _remove_legacy_tavern_stool_props(chunk_key: Vector2i, ctx: Dictionary) -> void:
	var chunk_save: Dictionary = ctx["chunk_save"]
	if not chunk_save.has(chunk_key):
		return
	var placements_raw: Variant = chunk_save[chunk_key].get("placements", null)
	if not (placements_raw is Array):
		return
	var placements: Array = placements_raw
	var filtered: Array = []
	for raw in placements:
		if _is_tavern_stool_placement(raw):
			continue
		filtered.append(raw)
	chunk_save[chunk_key]["placements"] = filtered

func _seed_tavern_barrels_as_placeables(placements: Array[Dictionary]) -> void:
	if bool(WorldSave.global_flags.get(TAVERN_BARREL_SEED_FLAG, false)):
		return

	for p in placements:
		if not _is_tavern_barrel_placement(p):
			continue
		var cell_raw: Array = p.get("cell", []) as Array
		if cell_raw.size() < 2:
			continue
		var cell := Vector2i(int(cell_raw[0]), int(cell_raw[1]))
		var site_id := String(p.get("site_id", ""))
		var uid := UID.make_uid("placed_barrel", site_id, cell if site_id == "" else Vector2i(-1, -1))
		if _placed_entity_uid_exists(uid):
			continue
		WorldSave.add_placed_entity({
			"uid": uid,
			"scene": TAVERN_BARREL_SCENE_PATH,
			"tile_pos_x": cell.x,
			"tile_pos_y": cell.y,
			"tier": 1,
			"item_id": TAVERN_BARREL_ITEM_ID,
		})

	WorldSave.global_flags[TAVERN_BARREL_SEED_FLAG] = true

func _seed_tavern_tables_as_placeables(placements: Array[Dictionary]) -> void:
	if bool(WorldSave.global_flags.get(TAVERN_TABLE_SEED_FLAG, false)):
		return

	for p in placements:
		if not _is_tavern_table_placement(p):
			continue
		var cell_raw: Array = p.get("cell", []) as Array
		if cell_raw.size() < 2:
			continue
		var cell := Vector2i(int(cell_raw[0]), int(cell_raw[1]))
		var site_id := String(p.get("site_id", ""))
		var uid := UID.make_uid("placed_table", site_id, cell if site_id == "" else Vector2i(-1, -1))
		if _placed_entity_uid_exists(uid):
			continue
		WorldSave.add_placed_entity({
			"uid": uid,
			"scene": TAVERN_TABLE_SCENE_PATH,
			"tile_pos_x": cell.x,
			"tile_pos_y": cell.y,
			"tier": 1,
			"item_id": TAVERN_TABLE_ITEM_ID,
		})

	WorldSave.global_flags[TAVERN_TABLE_SEED_FLAG] = true

func _seed_tavern_stools_as_placeables(placements: Array[Dictionary]) -> void:
	if bool(WorldSave.global_flags.get(TAVERN_STOOL_SEED_FLAG, false)):
		return

	for p in placements:
		if not _is_tavern_stool_placement(p):
			continue
		var cell_raw: Array = p.get("cell", []) as Array
		if cell_raw.size() < 2:
			continue
		var cell := Vector2i(int(cell_raw[0]), int(cell_raw[1]))
		var site_id := String(p.get("site_id", ""))
		var uid := UID.make_uid("placed_stool", site_id, cell if site_id == "" else Vector2i(-1, -1))
		if _placed_entity_uid_exists(uid):
			continue
		WorldSave.add_placed_entity({
			"uid": uid,
			"scene": TAVERN_STOOL_SCENE_PATH,
			"tile_pos_x": cell.x,
			"tile_pos_y": cell.y,
			"tier": 1,
			"item_id": TAVERN_STOOL_ITEM_ID,
		})

	WorldSave.global_flags[TAVERN_STOOL_SEED_FLAG] = true

func _align_existing_tavern_barrels_to_structure(placements: Array[Dictionary]) -> void:
	for p in placements:
		if not _is_tavern_barrel_placement(p):
			continue
		var cell_raw: Array = p.get("cell", []) as Array
		if cell_raw.size() < 2:
			continue
		var cell := Vector2i(int(cell_raw[0]), int(cell_raw[1]))
		var site_id := String(p.get("site_id", ""))
		var uid := UID.make_uid("placed_barrel", site_id, cell if site_id == "" else Vector2i(-1, -1))

		var entry := WorldSave.find_placed_entity(uid)
		if entry.is_empty():
			continue

		var tx: int = int(entry.get("tile_pos_x", 0))
		var ty: int = int(entry.get("tile_pos_y", 0))
		if tx == cell.x and ty == cell.y:
			continue

		entry["tile_pos_x"] = cell.x
		entry["tile_pos_y"] = cell.y
		# Al re-añadirlo con la nueva posición, se actualizará el chunk si es necesario.
		WorldSave.add_placed_entity(entry)

func _align_existing_tavern_tables_to_structure(placements: Array[Dictionary]) -> void:
	for p in placements:
		if not _is_tavern_table_placement(p):
			continue
		var cell_raw: Array = p.get("cell", []) as Array
		if cell_raw.size() < 2:
			continue
		var cell := Vector2i(int(cell_raw[0]), int(cell_raw[1]))
		var site_id := String(p.get("site_id", ""))
		var uid := UID.make_uid("placed_table", site_id, cell if site_id == "" else Vector2i(-1, -1))

		var entry := WorldSave.find_placed_entity(uid)
		if entry.is_empty():
			continue

		var tx: int = int(entry.get("tile_pos_x", 0))
		var ty: int = int(entry.get("tile_pos_y", 0))
		if tx == cell.x and ty == cell.y:
			continue

		entry["tile_pos_x"] = cell.x
		entry["tile_pos_y"] = cell.y
		WorldSave.add_placed_entity(entry)

func _align_existing_tavern_stools_to_structure(placements: Array[Dictionary]) -> void:
	for p in placements:
		if not _is_tavern_stool_placement(p):
			continue
		var cell_raw: Array = p.get("cell", []) as Array
		if cell_raw.size() < 2:
			continue
		var cell := Vector2i(int(cell_raw[0]), int(cell_raw[1]))
		var site_id := String(p.get("site_id", ""))
		var uid := UID.make_uid("placed_stool", site_id, cell if site_id == "" else Vector2i(-1, -1))

		var entry := WorldSave.find_placed_entity(uid)
		if entry.is_empty():
			continue

		var tx: int = int(entry.get("tile_pos_x", 0))
		var ty: int = int(entry.get("tile_pos_y", 0))
		if tx == cell.x and ty == cell.y:
			continue

		entry["tile_pos_x"] = cell.x
		entry["tile_pos_y"] = cell.y
		WorldSave.add_placed_entity(entry)

func _placed_entity_uid_exists(uid: String) -> bool:
	return WorldSave.placed_entity_chunk_by_uid.has(uid)

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
	var table_seed_placements: Array[Dictionary] = []
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
			table_seed_placements.append({
				"kind": "prop",
				"prop_id": "table",
				"site_id": "tavern_table_%02d" % placed_tables,
				"cell": [pos.x, pos.y],
			})
	if not table_seed_placements.is_empty():
		_seed_tavern_tables_as_placeables(table_seed_placements)

	var left_x: int = mini(inner_min.x + 1, inner_max.x)
	var right_x: int = maxi(inner_max.x - 1, inner_min.x)
	var top_y: int = mini(inner_min.y + 1, inner_max.y)
	var bottom_y: int = maxi(inner_max.y - 1, inner_min.y)
	var corners: Array[Vector2i] = [
		Vector2i(left_x, top_y),
		Vector2i(right_x, top_y),
		Vector2i(left_x, bottom_y),
		Vector2i(right_x, bottom_y),
	]
	var barrel_seed_placements: Array[Dictionary] = []
	var barrel_count: int = 0
	for c in corners:
		if barrel_count >= 4:
			break
		if _is_free(occupied, c):
			occupied[c] = true
			barrel_count += 1
			barrel_seed_placements.append({
				"kind": "prop",
				"prop_id": "barrel",
				"site_id": "tavern_barrel_%02d" % barrel_count,
				"cell": [c.x, c.y],
			})
	if not barrel_seed_placements.is_empty():
		_seed_tavern_barrels_as_placeables(barrel_seed_placements)

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
