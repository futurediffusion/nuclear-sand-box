extends Node2D

@onready var tilemap: TileMap = $WorldTileMap

@export var width: int = 256
@export var height: int = 256
@export var chunk_size: int = 32
@export var active_radius: int = 1  # chunks activos alrededor del player
@export var copper_ore_scene: PackedScene
@export var chunk_check_interval: float = 0.3

# Noise para bioma dominante
var biome_noise := FastNoiseLite.new()
# Noise para variación dentro del bioma
var detail_noise := FastNoiseLite.new()

var player: Node2D  # asigna tu player
var loaded_chunks: Dictionary = {}  # {Vector2i chunk_pos -> bool}
var current_player_chunk := Vector2i(-999, -999)

var spawn_tile: Vector2i
var tavern_chunk: Vector2i
const COPPER_MIN_DIST_TILES := 10
var _chunk_timer: float = 0.0
var _pick_rng := RandomNumberGenerator.new()

@export var bandit_camp_scene: PackedScene
@export var bandit_scene: PackedScene
var generated_chunks: Dictionary = {}   # {Vector2i: true} — tiles ya pintados Y entidades ya spawneadas
var generating_chunks: Dictionary = {}  # {Vector2i: true} — generación de tiles en curso (async)
var entities_spawned_chunks: Dictionary = {}  # {Vector2i: true} — spawn_entities ya corrió para este chunk
var chunk_save: Dictionary = {}         # {Vector2i: { "ores":[], "camps":[], "placed_tiles":[], "placements":[] } }

#tabern keeper
@export var tavern_keeper_scene: PackedScene


# Layers
const LAYER_GROUND: int = 0
const LAYER_FLOOR: int = 1
const LAYER_WALLS: int = 2

# Sources
const SRC_FLOOR: int = 1
const SRC_WALLS: int = 2

# Floor
const FLOOR_WOOD: Vector2i = Vector2i(0, 0)

# --- ROOF (fila superior y=0)
const ROOF_VERTICAL: Vector2i = Vector2i(0, 0)
const ROOF_CONT_LEFT: Vector2i = Vector2i(1, 0)
const ROOF_CONT_RIGHT: Vector2i = Vector2i(2, 0)
const ROOF_BOTH: Vector2i = Vector2i(3, 0)

# --- WALL (fila inferior y=1)
const WALL_SINGLE: Vector2i = Vector2i(0, 1)
const WALL_END_RIGHT: Vector2i = Vector2i(1, 1)
const WALL_END_LEFT: Vector2i = Vector2i(2, 1)
const WALL_MID: Vector2i = Vector2i(3, 1)

const BIOME_TILES = {
	0: [
		{"col_range": [0,2], "rows": [1], "w": 70},
		{"col_range": [0,2], "rows": [2], "w": 15},
		{"col_range": [0,2], "rows": [0], "w": 15},
	],
	1: [
		{"col_range": [0,2], "rows": [0], "w": 70},
		{"col_range": [0,2], "rows": [2], "w": 20},
		{"col_range": [0,2], "rows": [1], "w": 10},
	],
	2: [
		{"col_range": [0,2], "rows": [2], "w": 70},
		{"col_range": [0,2], "rows": [1], "w": 20},
		{"col_range": [0,2], "rows": [0], "w": 10},
	],
}

func _ready() -> void:
	Debug.log("boot", "World._ready begin")
	biome_noise.seed = randi()
	biome_noise.frequency = 0.015
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	detail_noise.seed = randi()
	detail_noise.frequency = 0.08
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	player = get_node_or_null("../Player")

	tavern_chunk = _tile_to_chunk(Vector2i(width / 2, height / 2))
	spawn_tile = get_tavern_center_tile(tavern_chunk)

	var spawn_world: Vector2 = _tile_to_world(spawn_tile)
	if player:
		player.global_position = spawn_world

	current_player_chunk = world_to_chunk(spawn_world)
	update_chunks(current_player_chunk)

func _process(delta: float) -> void:
	_chunk_timer += delta
	if _chunk_timer < chunk_check_interval:
		return
	_chunk_timer = 0.0

	if not player:
		return
	var pchunk := world_to_chunk(player.global_position)
	if pchunk != current_player_chunk:
		current_player_chunk = pchunk
		update_chunks(pchunk)

# ─── Chunk logic ────────────────────────────────────────────────

func world_to_chunk(pos: Vector2) -> Vector2i:
	var tile_pos: Vector2i = _world_to_tile(pos)
	return _tile_to_chunk(tile_pos)

func _is_chunk_in_active_window(chunk_pos: Vector2i, center: Vector2i) -> bool:
	if abs(chunk_pos.x - center.x) > active_radius:
		return false
	if abs(chunk_pos.y - center.y) > active_radius:
		return false
	return true

func update_chunks(center: Vector2i) -> void:
	Debug.log("boot", "ChunkManager load begin center=%s" % center)
	Debug.log("chunk", "CENTER moved -> (%d,%d)" % [center.x, center.y])
	if player:
		_debug_check_tile_alignment(player.global_position)
		_debug_check_player_chunk(player.global_position)

	var needed: Dictionary = {}
	var min_chunk_x: int = 0
	var min_chunk_y: int = 0
	var max_chunk_x: int = int(floor(float(width - 1) / float(chunk_size)))
	var max_chunk_y: int = int(floor(float(height - 1) / float(chunk_size)))

	for cy in range(center.y - active_radius, center.y + active_radius + 1):
		for cx in range(center.x - active_radius, center.x + active_radius + 1):
			if cx < min_chunk_x or cx > max_chunk_x or cy < min_chunk_y or cy > max_chunk_y:
				continue

			var cpos := Vector2i(cx, cy)
			needed[cpos] = true

			if not generated_chunks.has(cpos) and not generating_chunks.has(cpos):
				generating_chunks[cpos] = true
				generate_chunk(cpos)

			if generating_chunks.has(cpos):
				continue

			if not loaded_chunks.has(cpos):
				load_chunk_entities(cpos)
				loaded_chunks[cpos] = true

	for cpos in loaded_chunks.keys():
		if not needed.has(cpos):
			unload_chunk(cpos)
			unload_chunk_entities(cpos)
			loaded_chunks.erase(cpos)
	Debug.log("boot", "ChunkManager load end center=%s" % center)

func generate_chunk(chunk_pos: Vector2i) -> void:
	Debug.log("chunk", "GENERATE chunk=(%d,%d) run_seed=%d chunk_seed=%d" % [chunk_pos.x, chunk_pos.y, Seed.run_seed, Seed.chunk_seed(chunk_pos.x, chunk_pos.y)])
	# Spawn de entidades PRIMERO (síncrono, antes del await)
	spawn_entities_in_chunk(chunk_pos)

	var start_x := chunk_pos.x * chunk_size
	var start_y := chunk_pos.y * chunk_size

	for y in range(start_y, start_y + chunk_size):
		for x in range(start_x, start_x + chunk_size):
			if x < 0 or x >= width or y < 0 or y >= height:
				continue
			var tile_atlas := pick_tile(x, y)
			tile_atlas.y = clampi(tile_atlas.y, 0, 2)
			tilemap.set_cell(0, Vector2i(x, y), 0, tile_atlas)

		if y % 8 == 0:
			await get_tree().process_frame

	generated_chunks[chunk_pos] = true
	generating_chunks.erase(chunk_pos)

	if _is_chunk_in_active_window(chunk_pos, current_player_chunk):
		if not loaded_chunks.has(chunk_pos):
			load_chunk_entities(chunk_pos)
			loaded_chunks[chunk_pos] = true

func unload_chunk(chunk_pos: Vector2i) -> void:
	var start_x := chunk_pos.x * chunk_size
	var start_y := chunk_pos.y * chunk_size
	for y in range(start_y, start_y + chunk_size):
		for x in range(start_x, start_x + chunk_size):
			tilemap.erase_cell(LAYER_GROUND, Vector2i(x, y))
			tilemap.erase_cell(LAYER_FLOOR, Vector2i(x, y))
			tilemap.erase_cell(LAYER_WALLS, Vector2i(x, y))

# ─── Tile picking ────────────────────────────────────────────────

func get_biome(x: int, y: int) -> int:
	var v := (biome_noise.get_noise_2d(x, y) + 1.0) * 0.5
	if v < 0.38:
		return 0
	elif v > 0.62:
		return 2
	else:
		return 1

func pick_tile(x: int, y: int) -> Vector2i:
	var biome := get_biome(x, y)
	var tiles: Array = BIOME_TILES[biome]

	var total_weight: int = 0
	for t in tiles:
		total_weight += int(t["w"])

	_pick_rng.seed = hash(Vector2i(x, y))

	var roll: int = _pick_rng.randi_range(0, total_weight - 1)
	var acc: int = 0
	var winner: Dictionary = {}
	for t in tiles:
		acc += int(t["w"])
		if roll < acc:
			winner = t
			break

	var col: int = _pick_rng.randi_range(int(winner["col_range"][0]), int(winner["col_range"][1]))
	var rows: Array = winner["rows"]
	var row: int = rows[_pick_rng.randi_range(0, rows.size() - 1)]
	return Vector2i(col, row)

# ─── Spawner ────────────────────────────────────────────────────

var chunk_entities: Dictionary = {}
var chunk_saveables: Dictionary = {}
var chunk_occupied_tiles: Dictionary = {}

const INVALID_SPAWN_TILE := Vector2i(999999, 999999)
const SAFE_PLAYER_SPAWN_RADIUS_TILES := 3
const TAVERN_SAFE_MARGIN_TILES := 4
const SPAWN_MAX_TRIES := 30
const COPPER_FOOTPRINT_RADIUS_TILES := 0
const CAMP_FOOTPRINT_RADIUS_TILES := 2
const DEBUG_SPAWN: bool = true
const DEBUG_SAVE: bool = true

func _debug_spawn_report(chunk_key: Vector2i, player_tile: Vector2i, chosen_tile: Vector2i, reason: String) -> void:
	if not DEBUG_SPAWN:
		return
	Debug.log("spawn", "chunk=%s player_tile=%s chosen=%s -> %s" % [str(chunk_key), str(player_tile), str(chosen_tile), reason])

func _debug_check_tile_alignment(player_global: Vector2) -> void:
	if not DEBUG_SPAWN:
		return
	var local_pos: Vector2 = tilemap.to_local(player_global)
	var tile_pos: Vector2i = tilemap.local_to_map(local_pos)
	Debug.log("spawn", "ALIGN player_global=%s local=%s tile=%s" % [str(player_global), str(local_pos), str(tile_pos)])

func spawn_entities_in_chunk(chunk_pos: Vector2i) -> void:
	# Guardia con flag dedicado — nunca depender de chunk_save.has() ni generated_chunks
	# porque chunk_save puede existir antes (vía _ensure_chunk_save_key desde furniture)
	# y generated_chunks se setea DESPUÉS del await en generate_chunk.
	if entities_spawned_chunks.has(chunk_pos):
		return
	entities_spawned_chunks[chunk_pos] = true

	# Garantizar chunk_save con todas las claves, sin borrar lo que ya haya
	if not chunk_save.has(chunk_pos):
		chunk_save[chunk_pos] = {
			"ores": [],
			"camps": [],
			"placed_tiles": [],
			"placements": []
		}
	else:
		if not chunk_save[chunk_pos].has("ores"):        chunk_save[chunk_pos]["ores"] = []
		if not chunk_save[chunk_pos].has("camps"):       chunk_save[chunk_pos]["camps"] = []
		if not chunk_save[chunk_pos].has("placed_tiles"):chunk_save[chunk_pos]["placed_tiles"] = []
		if not chunk_save[chunk_pos].has("placements"):  chunk_save[chunk_pos]["placements"] = []

	if not chunk_occupied_tiles.has(chunk_pos):
		chunk_occupied_tiles[chunk_pos] = {}

	# Taberna — siempre antes del cobre para que su footprint ocupe tiles primero
	if chunk_pos == tavern_chunk:
		generate_tavern_in_chunk(chunk_pos)

	# ─── COBRE ───────────────────────────────────────────────────
	if copper_ore_scene == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_pos) ^ biome_noise.seed

	var copper_positions: Array[Vector2i] = []

	var cx := chunk_pos.x * chunk_size + chunk_size / 2
	var cy := chunk_pos.y * chunk_size + chunk_size / 2
	var biome := get_biome(cx, cy)

	var attempts := 0
	match biome:
		2: attempts = rng.randi_range(6, 16)
		0: attempts = rng.randi_range(3, 7)
		1: attempts = rng.randi_range(0, 3)

	var chunk_center_tile := Vector2i(cx, cy)
	if _tile_distance_to_spawn(chunk_center_tile) <= 15:
		attempts = max(attempts, 1)

	var player_tile: Vector2i = spawn_tile
	if player:
		player_tile = _world_to_tile(player.global_position)

	var copper_spawn_failed_logged := false

	for i in range(attempts):
		var tpos: Vector2i = _find_valid_spawn_tile(
			chunk_pos, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES,
			SPAWN_MAX_TRIES, rng, COPPER_FOOTPRINT_RADIUS_TILES
		)

		if tpos == INVALID_SPAWN_TILE:
			if not copper_spawn_failed_logged:
				_debug_spawn_report(chunk_pos, player_tile, INVALID_SPAWN_TILE, "CANCEL: no valid tile after tries")
				copper_spawn_failed_logged = true
			continue

		var dist := _tile_distance_to_spawn(tpos)
		var allow_close := rng.randf() < 0.15
		if not allow_close and dist < COPPER_MIN_DIST_TILES:
			continue

		var tile_biome := get_biome(tpos.x, tpos.y)
		match tile_biome:
			2:
				if rng.randf() > 0.60: continue
			1:
				if rng.randf() > 0.30: continue
			0:
				if rng.randf() > 0.20: continue

		chunk_save[chunk_pos]["ores"].append({"tile": tpos, "remaining": -1})
		_mark_footprint_occupied(chunk_pos, tpos, COPPER_FOOTPRINT_RADIUS_TILES)
		copper_positions.append(tpos)

	# ─── CAMPAMENTOS ─────────────────────────────────────────────
	if bandit_camp_scene == null or bandit_scene == null:
		return

	var guarded_count := int(floor(copper_positions.size() * 0.40))
	guarded_count = clampi(guarded_count, 0, 3)

	for g in range(guarded_count):
		if copper_positions.is_empty():
			break
		var idx := rng.randi_range(0, copper_positions.size() - 1)
		var copper_tile := copper_positions[idx]

		var camp_tile := _find_nearby_tile(rng, copper_tile, 6, 14)
		if camp_tile == INVALID_SPAWN_TILE:
			continue
		if not _is_spawn_tile_valid(chunk_pos, camp_tile, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES, CAMP_FOOTPRINT_RADIUS_TILES):
			continue

		chunk_save[chunk_pos]["camps"].append({"tile": camp_tile})
		_mark_footprint_occupied(chunk_pos, camp_tile, CAMP_FOOTPRINT_RADIUS_TILES)

	var random_camps := rng.randi_range(0, 2)
	var camp_spawn_failed_logged := false

	for r in range(random_camps):
		var try_tile: Vector2i = INVALID_SPAWN_TILE

		for i in range(SPAWN_MAX_TRIES):
			var candidate: Vector2i = _find_valid_spawn_tile(
				chunk_pos, player_tile, SAFE_PLAYER_SPAWN_RADIUS_TILES,
				SPAWN_MAX_TRIES, rng, CAMP_FOOTPRINT_RADIUS_TILES
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
		_mark_footprint_occupied(chunk_pos, try_tile, CAMP_FOOTPRINT_RADIUS_TILES)

func load_chunk_entities(chunk_pos: Vector2i) -> void:
	chunk_entities[chunk_pos] = []
	chunk_saveables[chunk_pos] = []
	_rebuild_chunk_occupied_tiles(chunk_pos)

	if not chunk_save.has(chunk_pos):
		return

	var placements_count: int = chunk_save[chunk_pos].get("placements", []).size()
	var ores_count: int = chunk_save[chunk_pos]["ores"].size()
	var camps_count: int = chunk_save[chunk_pos]["camps"].size()
	Debug.log("chunk", "LOAD_ENTITIES chunk=(%d,%d) placements=%d ores=%d camps=%d" % [chunk_pos.x, chunk_pos.y, placements_count, ores_count, camps_count])

	var cx: int = chunk_pos.x
	var cy: int = chunk_pos.y
	WorldSave.get_chunk_save(cx, cy)

	# 1) ORES
	for d in chunk_save[chunk_pos]["ores"]:
		var tpos: Vector2i = d["tile"]
		var ore := copper_ore_scene.instantiate()
		ore.position = tilemap.map_to_local(tpos)
		tilemap.add_child(ore)
		chunk_entities[chunk_pos].append(ore)

		var ore_uid: String = UID.make_uid("ore_copper", "", tpos)
		ore.entity_uid = ore_uid
		var ore_state = WorldSave.get_entity_state(cx, cy, ore_uid)
		if ore_state != null:
			ore.apply_save_state(ore_state)
			if DEBUG_SAVE:
				Debug.log("save", "apply state uid=%s remaining=%d" % [ore_uid, int(ore.get("remaining"))])
		elif d.has("remaining") and d["remaining"] != -1:
			ore.set("remaining", int(d["remaining"]))
			WorldSave.set_entity_state(cx, cy, ore_uid, ore.get_save_state())
		else:
			WorldSave.set_entity_state(cx, cy, ore_uid, ore.get_save_state())
		chunk_saveables[chunk_pos].append(ore)

	# 2) TILES PERSISTENTES (taberna piso/paredes)
	for t in chunk_save[chunk_pos]["placed_tiles"]:
		tilemap.set_cell(t["layer"], t["tile"], t["source"], t["atlas"])

	# 3) CAMPS
	for c in chunk_save[chunk_pos]["camps"]:
		var ct: Vector2i = c["tile"]
		var camp := bandit_camp_scene.instantiate()
		camp.position = tilemap.map_to_local(ct)
		tilemap.add_child(camp)
		chunk_entities[chunk_pos].append(camp)
		camp.set("bandit_scene", bandit_scene)

	# 4) PLACEMENTS (props + npc_keeper)
	var spawned_count: int = 0
	var spawned_npc_count: int = 0
	var spawned_keeper_uids: Dictionary = {}
	if chunk_save[chunk_pos].has("placements"):
		for p in chunk_save[chunk_pos]["placements"]:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = p
			var kind: String = String(d.get("kind", ""))

			if kind == "prop":
				var prop_id: String = String(d.get("prop_id", ""))
				var path: String = PropDB.scene_path(prop_id)
				if path == "":
					Debug.log("chunk", "PROPS unknown prop_id=%s" % prop_id)
					continue
				var ps: PackedScene = load(path) as PackedScene
				if ps == null:
					Debug.log("chunk", "PROPS failed load path=%s" % path)
					continue
				var inst: Node2D = ps.instantiate() as Node2D
				var ccell: Array = d.get("cell", [0, 0])
				var cell: Vector2i = Vector2i(int(ccell[0]), int(ccell[1]))
				inst.position = tilemap.map_to_local(cell)
				inst.z_index = tilemap.z_index + 5
				tilemap.add_child(inst)
				chunk_entities[chunk_pos].append(inst)
				spawned_count += 1

			elif kind == "npc_keeper":
				if tavern_keeper_scene == null:
					Debug.log("chunk", "NPC tavern_keeper_scene missing in inspector")
					continue

				var site_id: String = String(d.get("site_id", ""))
				var keeper_uid: String = UID.make_uid("npc_keeper", site_id)
				if spawned_keeper_uids.has(keeper_uid):
					continue
				spawned_keeper_uids[keeper_uid] = true

				var keeper_state = WorldSave.get_entity_state(cx, cy, keeper_uid)
				if keeper_state == null:
					WorldSave.set_entity_state(cx, cy, keeper_uid, {"spawned": true})
					if DEBUG_SAVE:
						Debug.log("save", "seed keeper uid=%s" % keeper_uid)

				var keeper := tavern_keeper_scene.instantiate() as TavernKeeper
				var ccell: Array = d.get("cell", [0, 0])
				var counter_cell: Vector2i = Vector2i(int(ccell[0]), int(ccell[1]))
				var imin: Array = d.get("inner_min", [0, 0])
				var imax: Array = d.get("inner_max", [0, 0])
				var inner_min: Vector2i = Vector2i(int(imin[0]), int(imin[1]))
				var inner_max: Vector2i = Vector2i(int(imax[0]), int(imax[1]))
				keeper.entity_uid = keeper_uid
				keeper.set("_tilemap", tilemap)
				keeper.set("tavern_inner_min", inner_min)
				keeper.set("tavern_inner_max", inner_max)
				keeper.set("counter_tile", counter_cell)
				if keeper_state != null:
					keeper.apply_save_state(keeper_state)
				keeper.position = tilemap.map_to_local(counter_cell)
				tilemap.add_child(keeper)
				chunk_entities[chunk_pos].append(keeper)
				chunk_saveables[chunk_pos].append(keeper)
				spawned_npc_count += 1
				spawned_count += 1

	Debug.log("chunk", "SPAWNED chunk=(%d,%d) props=%d npcs=%d ores=%d camps=%d saveables=%d" % [chunk_pos.x, chunk_pos.y, spawned_count - spawned_npc_count, spawned_npc_count, chunk_save[chunk_pos]["ores"].size(), chunk_save[chunk_pos]["camps"].size(), chunk_saveables[chunk_pos].size()])

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return tilemap.local_to_map(tilemap.to_local(world_pos))

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return tilemap.to_global(tilemap.map_to_local(tile_pos))

func _tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	var cx: int = int(floor(float(tile_pos.x) / float(chunk_size)))
	var cy: int = int(floor(float(tile_pos.y) / float(chunk_size)))
	return Vector2i(cx, cy)

func _debug_check_player_chunk(player_global: Vector2) -> void:
	if not DEBUG_SPAWN:
		return
	var player_tile: Vector2i = _world_to_tile(player_global)
	var chunk_key: Vector2i = _tile_to_chunk(player_tile)
	Debug.log("spawn", "CHUNK_CHECK player_tile=%s player_chunk=%s" % [str(player_tile), str(chunk_key)])

func _get_random_tile_in_chunk(chunk_key: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var tx: int = rng.randi_range(chunk_key.x * chunk_size, chunk_key.x * chunk_size + chunk_size - 1)
	var ty: int = rng.randi_range(chunk_key.y * chunk_size, chunk_key.y * chunk_size + chunk_size - 1)
	return Vector2i(tx, ty)

func _is_spawn_tile_valid(chunk_key: Vector2i, tile_pos: Vector2i, player_tile: Vector2i, safe_radius_tiles: int, footprint_radius_tiles: int = 0) -> bool:
	if tile_pos == INVALID_SPAWN_TILE:
		return false
	if tile_pos.x < 0 or tile_pos.x >= width or tile_pos.y < 0 or tile_pos.y >= height:
		return false

	for oy in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
		for ox in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
			var probe := tile_pos + Vector2i(ox, oy)
			if probe.x < 0 or probe.x >= width or probe.y < 0 or probe.y >= height:
				return false
			if probe.distance_to(player_tile) <= float(safe_radius_tiles):
				return false
			var occ: Dictionary = chunk_occupied_tiles.get(chunk_key, {})
			if occ.has(probe):
				return false
	return true

func _find_valid_spawn_tile(chunk_key: Vector2i, player_tile: Vector2i, safe_radius_tiles: int, max_tries: int, rng: RandomNumberGenerator, footprint_radius_tiles: int = 0) -> Vector2i:
	var tries: int = 0
	var reject_prints: int = 0
	while tries < max_tries:
		var candidate: Vector2i = _get_random_tile_in_chunk(chunk_key, rng)
		if _is_spawn_tile_valid(chunk_key, candidate, player_tile, safe_radius_tiles, footprint_radius_tiles):
			return candidate

		if DEBUG_SPAWN and reject_prints < 3:
			var occ: Dictionary = chunk_occupied_tiles.get(chunk_key, {})
			Debug.log("spawn", "REJECT chunk=%s cand=%s dist=%s occupied=%s reason=%s" % [str(chunk_key), str(candidate), str(candidate.distance_to(player_tile)), str(occ.has(candidate)), _get_spawn_reject_reason(chunk_key, candidate, player_tile, safe_radius_tiles, footprint_radius_tiles)])
			reject_prints += 1
		tries += 1
	return INVALID_SPAWN_TILE

func _get_spawn_reject_reason(chunk_key: Vector2i, tile_pos: Vector2i, player_tile: Vector2i, safe_radius_tiles: int, footprint_radius_tiles: int = 0) -> String:
	if tile_pos == INVALID_SPAWN_TILE:
		return "invalid_spawn_tile"
	if tile_pos.x < 0 or tile_pos.x >= width or tile_pos.y < 0 or tile_pos.y >= height:
		return "out_of_world_bounds"

	var occ: Dictionary = chunk_occupied_tiles.get(chunk_key, {})
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

func _mark_tile_occupied(chunk_key: Vector2i, tile_pos: Vector2i) -> void:
	if tile_pos == INVALID_SPAWN_TILE:
		return
	if not chunk_occupied_tiles.has(chunk_key):
		chunk_occupied_tiles[chunk_key] = {}
	chunk_occupied_tiles[chunk_key][tile_pos] = true

func _mark_footprint_occupied(chunk_key: Vector2i, tile_pos: Vector2i, footprint_radius_tiles: int) -> void:
	if tile_pos == INVALID_SPAWN_TILE:
		return
	for oy in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
		for ox in range(-footprint_radius_tiles, footprint_radius_tiles + 1):
			_mark_tile_occupied(chunk_key, tile_pos + Vector2i(ox, oy))

func _rebuild_chunk_occupied_tiles(chunk_key: Vector2i) -> void:
	chunk_occupied_tiles[chunk_key] = {}
	if not chunk_save.has(chunk_key):
		return
	for d in chunk_save[chunk_key]["ores"]:
		_mark_footprint_occupied(chunk_key, d["tile"], COPPER_FOOTPRINT_RADIUS_TILES)
	for c in chunk_save[chunk_key]["camps"]:
		_mark_footprint_occupied(chunk_key, c["tile"], CAMP_FOOTPRINT_RADIUS_TILES)

func unload_chunk_entities(chunk_pos: Vector2i) -> void:
	if not chunk_entities.has(chunk_pos):
		return

	var saveables_count: int = chunk_saveables.get(chunk_pos, []).size()
	var entities_count: int = chunk_entities.get(chunk_pos, []).size()
	Debug.log("chunk", "UNLOAD chunk=(%d,%d) entities=%d saveables=%d" % [chunk_pos.x, chunk_pos.y, entities_count, saveables_count])

	var cx: int = chunk_pos.x
	var cy: int = chunk_pos.y
	if chunk_saveables.has(chunk_pos):
		for entity in chunk_saveables[chunk_pos]:
			if not is_instance_valid(entity):
				continue
			if not entity.has_method("get_save_state"):
				continue
			var uid_value = entity.get("entity_uid")
			if uid_value == null:
				continue
			var uid: String = String(uid_value)
			if uid == "":
				continue
			var state: Dictionary = entity.get_save_state()
			WorldSave.set_entity_state(cx, cy, uid, state)
			if DEBUG_SAVE and state.has("remaining"):
				Debug.log("save", "store state uid=%s remaining=%d" % [uid, int(state["remaining"])])

	if chunk_save.has(chunk_pos):
		var ore_list = chunk_save[chunk_pos]["ores"]
		for e in chunk_entities[chunk_pos]:
			if is_instance_valid(e) and e is CopperOre:
				var tile := _world_to_tile(e.global_position)
				for d in ore_list:
					if d["tile"] == tile:
						d["remaining"] = int(e.get("remaining"))
						break

	for e in chunk_entities[chunk_pos]:
		if is_instance_valid(e):
			e.queue_free()
	chunk_entities.erase(chunk_pos)
	chunk_saveables.erase(chunk_pos)

func despawn_entities_in_chunk(chunk_pos: Vector2i) -> void:
	if not chunk_entities.has(chunk_pos):
		return
	for e in chunk_entities[chunk_pos]:
		if is_instance_valid(e):
			e.queue_free()
	chunk_entities.erase(chunk_pos)
	chunk_saveables.erase(chunk_pos)
	Debug.log("chunk", "SPAWN_SUMMARY chunk=(%d,%d) ores=%d camps=%d" % [chunk_pos.x, chunk_pos.y, chunk_save[chunk_pos]["ores"].size(), chunk_save[chunk_pos]["camps"].size()])

func _tile_distance_to_spawn(t: Vector2i) -> float:
	return spawn_tile.distance_to(t)

func _spawn_camp_at(chunk_pos: Vector2i, tile_pos: Vector2i) -> void:
	var camp := bandit_camp_scene.instantiate()
	camp.global_position = tilemap.map_to_local(tile_pos)
	add_child(camp)
	chunk_entities[chunk_pos].append(camp)
	if camp.has_method("set"):
		camp.set("bandit_scene", bandit_scene)

func _find_nearby_tile(rng: RandomNumberGenerator, origin: Vector2i, min_r: int, max_r: int) -> Vector2i:
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

func _place_tile_persistent(chunk_pos: Vector2i, layer: int, tile_pos: Vector2i, source: int, atlas: Vector2i) -> void:
	tilemap.set_cell(layer, tile_pos, source, atlas)
	chunk_save[chunk_pos]["placed_tiles"].append({
		"layer": layer,
		"tile": tile_pos,
		"source": source,
		"atlas": atlas
	})

func generate_tavern_in_chunk(chunk_pos: Vector2i) -> void:
	if not chunk_save.has(chunk_pos):
		return
	if not chunk_save[chunk_pos].has("placed_tiles"):
		chunk_save[chunk_pos]["placed_tiles"] = []

	var w: int = 12
	var h: int = 8
	var x0: int = chunk_pos.x * chunk_size + 4
	var y0: int = chunk_pos.y * chunk_size + 3
	var x1: int = x0 + w - 1
	var y1: int = y0 + h - 1
	var door_x: int = x0 + w / 2

	# 1) PISO INTERIOR
	for x in range(x0 + 1, x1):
		for y in range(y0 + 1, y1):
			_place_tile_persistent(chunk_pos, LAYER_FLOOR, Vector2i(x, y), SRC_FLOOR, FLOOR_WOOD)

	# 2) PARED SUPERIOR
	_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x0, y0 + 1), SRC_WALLS, ROOF_CONT_RIGHT)
	_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x1, y0 + 1), SRC_WALLS, ROOF_CONT_LEFT)
	for x in range(x0 + 1, x1):
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x, y0 + 1), SRC_WALLS, WALL_MID)

	# 3) PARED INFERIOR con puerta
	for x in range(x0, x1 + 1):
		if x == door_x:
			continue
		var atlas_b: Vector2i
		if x == x0:                atlas_b = WALL_END_LEFT
		elif x == x1:              atlas_b = WALL_END_RIGHT
		elif x == door_x - 1:     atlas_b = WALL_END_RIGHT
		elif x == door_x + 1:     atlas_b = WALL_END_LEFT
		else:                      atlas_b = WALL_MID
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x, y1), SRC_WALLS, atlas_b)

	# 4) PAREDES LATERALES
	for y in range(y0 + 2, y1):
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x0, y), SRC_WALLS, ROOF_VERTICAL)
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x1, y), SRC_WALLS, ROOF_VERTICAL)

	# Reservar huella de la taberna
	for y in range(y0 - TAVERN_SAFE_MARGIN_TILES, y1 + TAVERN_SAFE_MARGIN_TILES + 1):
		for x in range(x0 - TAVERN_SAFE_MARGIN_TILES, x1 + TAVERN_SAFE_MARGIN_TILES + 1):
			_mark_tile_occupied(chunk_pos, Vector2i(x, y))

	var inner_min: Vector2i = Vector2i(x0 + 1, y0 + 1)
	var inner_max: Vector2i = Vector2i(x1 - 1, y1 - 1)
	var door_cell: Vector2i = Vector2i(door_x, y1)

	generate_tavern_furniture_simple(chunk_pos, inner_min, inner_max, door_cell)
	Debug.log("chunk", "TAVERN chunk=(%d,%d) placements=%d" % [chunk_pos.x, chunk_pos.y, chunk_save[chunk_pos].get("placements", []).size()])

func get_tavern_center_tile(chunk_pos: Vector2i) -> Vector2i:
	var w: int = 12
	var h: int = 8
	var x0: int = chunk_pos.x * chunk_size + 4
	var y0: int = chunk_pos.y * chunk_size + 3
	return Vector2i(x0 + (w / 2), y0 + (h / 2))

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

func _ensure_chunk_save_key(chunk_key: Vector2i) -> void:
	if not chunk_save.has(chunk_key):
		chunk_save[chunk_key] = {
			"ores": [],
			"camps": [],
			"placed_tiles": [],
			"placements": []
		}
	if not chunk_save[chunk_key].has("placements"):
		chunk_save[chunk_key]["placements"] = []

func add_prop_placement(chunk_key: Vector2i, prop_id: String, site_id: String, cell: Vector2i) -> void:
	_ensure_chunk_save_key(chunk_key)

	for p in chunk_save[chunk_key]["placements"]:
		if typeof(p) == TYPE_DICTIONARY and String((p as Dictionary).get("site_id", "")) == site_id:
			return

	chunk_save[chunk_key]["placements"].append({
		"kind": "prop",
		"prop_id": prop_id,
		"site_id": site_id,
		"cell": [cell.x, cell.y]
	})

func generate_tavern_furniture_simple(chunk_key: Vector2i, inner_min: Vector2i, inner_max: Vector2i, door_cell: Vector2i) -> void:
	var occupied: Dictionary = {}

	# Reservar corredor de la puerta
	for i: int in range(4):
		for w: int in range(2):
			occupied[Vector2i(door_cell.x + w, door_cell.y - i)] = true

	# COUNTER
	var counter_size: Vector2i = Vector2i(3, 1)
	var counter_pos: Vector2i = Vector2i(door_cell.x, inner_min.y + 2)
	var counter_cell: Vector2i = counter_pos  # tile donde para el keeper
	if _rect_fits_and_free(occupied, counter_pos, counter_size, inner_min, inner_max):
		_mark_rect(occupied, counter_pos, counter_size)
		add_prop_placement(chunk_key, "counter", "tavern_counter_01", counter_pos)
		var behind: Vector2i = Vector2i(counter_pos.x, counter_pos.y - 1)
		if behind.y >= inner_min.y:
			_mark_rect(occupied, behind, Vector2i(counter_size.x, 1))
		# El keeper se para justo detrás del centro del counter
		counter_cell = Vector2i(counter_pos.x + 1, counter_pos.y - 1)

	# MESAS
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
			add_prop_placement(chunk_key, "table", "tavern_table_%02d" % placed_tables, pos)

	# BARRILES en esquinas
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
			add_prop_placement(chunk_key, "barrel", "tavern_barrel_%02d" % barrel_count, c)

	# NPC KEEPER — guardar placement con bounds para que load_chunk_entities lo instancie
	_ensure_chunk_save_key(chunk_key)
	for p in chunk_save[chunk_key]["placements"]:
		if typeof(p) == TYPE_DICTIONARY and String((p as Dictionary).get("site_id", "")) == "tavern_keeper_01":
			return
	chunk_save[chunk_key]["placements"].append({
		"kind":      "npc_keeper",
		"site_id":   "tavern_keeper_01",
		"cell":      [counter_cell.x, counter_cell.y],
		"inner_min": [inner_min.x, inner_min.y],
		"inner_max": [inner_max.x, inner_max.y]
	})
