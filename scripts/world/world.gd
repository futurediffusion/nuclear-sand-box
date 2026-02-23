extends Node2D

@onready var tilemap: TileMap = $WorldTileMap

@export var width: int = 256
@export var height: int = 256
@export var chunk_size: int = 32
@export var active_radius: int = 1  # chunks activos alrededor del player
@export var copper_ore_scene: PackedScene
@export var chunk_check_interval: float = 0.3
@export_range(0.1, 4.0, 0.1) var copper_spawn_multiplier: float = 1.6
@export_range(0.1, 4.0, 0.1) var camp_spawn_multiplier: float = 1.8

# Noise para bioma dominante
var biome_noise := FastNoiseLite.new()
# Noise para variación dentro del bioma
var detail_noise := FastNoiseLite.new()

var player: Node2D  # asigna tu player
var loaded_chunks: Dictionary = {}  # {Vector2i chunk_pos -> bool}
var current_player_chunk := Vector2i(-999, -999)

var spawn_tile: Vector2i
const COPPER_MIN_DIST_TILES := 10
var _chunk_timer: float = 0.0
var _pick_rng := RandomNumberGenerator.new()

@export var bandit_camp_scene: PackedScene
@export var bandit_scene: PackedScene  # tu Enemy (bandido)
var generated_chunks: Dictionary = {} # {Vector2i: true}
var generating_chunks: Dictionary = {} # {Vector2i: true}
var chunk_save: Dictionary = {}       # {Vector2i: { "ores":[], "camps":[] } }

# Tabla de tiles por bioma
# Formato: [atlas_coords, peso_relativo]
# Bioma: 0=arena, 1=pasto, 2=piedra
# Layers
const LAYER_GROUND: int = 0
const LAYER_FLOOR: int = 1
const LAYER_WALLS: int = 2

# Sources
const SRC_FLOOR: int = 1
const SRC_WALLS: int = 2

# Floor
const FLOOR_WOOD: Vector2i = Vector2i(0, 0)

# -----------------------------
# WALL TILESET (4x2)
# Fila 0 = ROOF
# Fila 1 = WALL
# -----------------------------

# --- ROOF (fila superior y=0)
const ROOF_VERTICAL: Vector2i = Vector2i(0, 0)   # techo completo (columna vertical)
const ROOF_CONT_LEFT: Vector2i = Vector2i(1, 0)  # continuidad hacia izquierda
const ROOF_CONT_RIGHT: Vector2i = Vector2i(2, 0) # continuidad hacia derecha
const ROOF_BOTH: Vector2i = Vector2i(3, 0)       # continuidad L/R (tramo horizontal)

# --- WALL (fila inferior y=1)
const WALL_SINGLE: Vector2i = Vector2i(0, 1)     # pared sola / poste vertical
const WALL_END_RIGHT: Vector2i = Vector2i(1, 1)  # termina derecha / marco izquierdo puerta
const WALL_END_LEFT: Vector2i = Vector2i(2, 1)   # termina izquierda / marco derecho puerta
const WALL_MID: Vector2i = Vector2i(3, 1)        # tramo horizontal

const BIOME_TILES = {
	0: [  # Arena dominante
		{"col_range": [0,2], "rows": [1], "w": 70},  # arena
		{"col_range": [0,2], "rows": [2], "w": 15},  # invasión piedra
		{"col_range": [0,2], "rows": [0], "w": 15},  # invasión pasto
	],
	1: [  # Pasto dominante
		{"col_range": [0,2], "rows": [0], "w": 70},  # pasto
		{"col_range": [0,2], "rows": [2], "w": 20},  # piedra
		{"col_range": [0,2], "rows": [1], "w": 10},  # arena
	],
	2: [  # Piedra dominante
		{"col_range": [0,2], "rows": [2], "w": 70},  # piedra
		{"col_range": [0,2], "rows": [1], "w": 20},  # arena
		{"col_range": [0,2], "rows": [0], "w": 10},  # pasto
	],
}

func _ready() -> void:
	biome_noise.seed = randi()
	biome_noise.frequency = 0.015       # frecuencia baja = biomas grandes
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	detail_noise.seed = randi()
	detail_noise.frequency = 0.08       # frecuencia alta = variación fina
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	player = get_node_or_null("../Player")

	# Spawn inicial: ubicar al jugador en el centro de la taberna del chunk inicial.
	var initial_spawn_tile := Vector2i(width / 2, height / 2)
	var spawn_chunk: Vector2i = _tile_to_chunk(initial_spawn_tile)
	spawn_tile = _get_tavern_center_tile_for_chunk(spawn_chunk)

	# mover player al centro REAL en el mundo
	if player:
		player.global_position = tilemap.to_global(tilemap.map_to_local(spawn_tile))

	current_player_chunk = world_to_chunk(tilemap.to_global(tilemap.map_to_local(spawn_tile)))
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

func update_chunks(center: Vector2i) -> void:
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
	
	# Descargar chunks lejanos
	for cpos in loaded_chunks.keys():
		if not needed.has(cpos):
			unload_chunk(cpos)

			# OJO: NO borrar generated_chunks.
			# Si lo borras, el chunk se regenera al volver y rompe la coherencia del mundo.
			# generated_chunks.erase(cpos)
			# generating_chunks.erase(cpos)

			unload_chunk_entities(cpos)
			loaded_chunks.erase(cpos)

func generate_chunk(chunk_pos: Vector2i) -> void:
	spawn_entities_in_chunk(chunk_pos)

	var start_x := chunk_pos.x * chunk_size
	var start_y := chunk_pos.y * chunk_size
	
	for y in range(start_y, start_y + chunk_size):
		for x in range(start_x, start_x + chunk_size):
			# Límites del mapa finito
			if x < 0 or x >= width or y < 0 or y >= height:
				continue
			
			var tile_atlas := pick_tile(x, y)
			tile_atlas.y = clampi(tile_atlas.y, 0, 2)
			tilemap.set_cell(0, Vector2i(x, y), 0, tile_atlas)

		if y % 8 == 0:
			await get_tree().process_frame
	
	generated_chunks[chunk_pos] = true
	generating_chunks.erase(chunk_pos)

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
		return 0  # Arena
	elif v > 0.62:
		return 2  # Piedra
	else:
		return 1  # Pasto

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

var chunk_entities: Dictionary = {}  # {Vector2i -> Array[Node]}
var chunk_occupied_tiles: Dictionary = {}  # {Vector2i -> {Vector2i: true}}

const INVALID_SPAWN_TILE := Vector2i(999999, 999999)
const SAFE_PLAYER_SPAWN_RADIUS_TILES := 3
const TAVERN_SAFE_RADIUS_TILES: int = 20
const SPAWN_MAX_TRIES := 30
const COPPER_FOOTPRINT_RADIUS_TILES := 0
const CAMP_FOOTPRINT_RADIUS_TILES := 2
const DEBUG_SPAWN: bool = true

var tavern_tile: Vector2i = Vector2i(0, 0)
var has_tavern: bool = false

func _debug_spawn_report(chunk_key: Vector2i, player_tile: Vector2i, chosen_tile: Vector2i, reason: String) -> void:
	if not DEBUG_SPAWN:
		return
	print("[SPAWN][chunk=", chunk_key, "] player_tile=", player_tile, " chosen=", chosen_tile, " -> ", reason)

func _debug_check_tile_alignment(player_global: Vector2) -> void:
	if not DEBUG_SPAWN:
		return

	var local_pos: Vector2 = tilemap.to_local(player_global)
	var tile_pos: Vector2i = tilemap.local_to_map(local_pos)
	print("[ALIGN] player_global=", player_global, " local=", local_pos, " tile=", tile_pos)

func spawn_entities_in_chunk(chunk_pos: Vector2i) -> void:
	if not chunk_save.has(chunk_pos):
		chunk_save[chunk_pos] = {
			"ores": [],
			"camps": [],
			"placed_tiles": []
		}
		# --- TABERNA: SOLO 1 VEZ (BUGFIX) ---
		# Solo generar taberna en el chunk del spawn (chunk del jugador al inicio).
		var spawn_chunk: Vector2i = _tile_to_chunk(spawn_tile)
		if chunk_pos == spawn_chunk and not has_tavern:
			generate_tavern_in_chunk(chunk_pos)
		chunk_occupied_tiles[chunk_pos] = {}
	else:
		return

	if copper_ore_scene == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_pos) ^ biome_noise.seed

	# -----------------------------
	# 1) SPAWN COBRE
	# -----------------------------
	var copper_positions: Array[Vector2i] = []

	# Bioma del centro del chunk (para “densidad” general)
	var cx := chunk_pos.x * chunk_size + chunk_size / 2
	var cy := chunk_pos.y * chunk_size + chunk_size / 2
	var biome := get_biome(cx, cy)

	var attempts := 0
	match biome:
		2: attempts = rng.randi_range(8, 18)  # piedra: bastante
		0: attempts = rng.randi_range(4, 9)   # arena: medio
		1: attempts = rng.randi_range(1, 5)   # pasto: poco

	attempts = maxi(1, int(round(float(attempts) * copper_spawn_multiplier)))

	# Cerca del spawn: mínimo 1 intento
	var chunk_center_tile := Vector2i(cx, cy)
	if _tile_distance_to_spawn(chunk_center_tile) <= 15:
		attempts = max(attempts, 1)

	var player_tile: Vector2i = spawn_tile
	if player:
		player_tile = _world_to_tile(player.global_position)

	var copper_spawn_failed_logged := false

	for i in range(attempts):
		var tpos: Vector2i = _find_valid_spawn_tile(chunk_pos, player_tile, TAVERN_SAFE_RADIUS_TILES, SPAWN_MAX_TRIES, rng, COPPER_FOOTPRINT_RADIUS_TILES)
		if tpos == INVALID_SPAWN_TILE:
			if not copper_spawn_failed_logged:
				_debug_spawn_report(chunk_pos, player_tile, INVALID_SPAWN_TILE, "CANCEL: no valid tile after tries")
				copper_spawn_failed_logged = true
			continue

		# regla distancia (la mayoría lejos)
		var dist := _tile_distance_to_spawn(tpos)
		var allow_close := rng.randf() < 0.15
		if not allow_close and dist < COPPER_MIN_DIST_TILES:
			continue

		# regla por BIOMA del tile: 60% piedra / 30% pasto / 20% arena
		var tile_biome := get_biome(tpos.x, tpos.y)
		match tile_biome:
			2:
				if rng.randf() > 0.60:
					continue
			1:
				if rng.randf() > 0.30:
					continue
			0:
				if rng.randf() > 0.20:
					continue

		chunk_save[chunk_pos]["ores"].append({
			"tile": tpos,
			"remaining": -1
		})
		_mark_footprint_occupied(chunk_pos, tpos, COPPER_FOOTPRINT_RADIUS_TILES)
		copper_positions.append(tpos)

	# -----------------------------
	# 2) SPAWN CAMPAMENTOS (BANDIDOS)
	# -----------------------------
	if bandit_camp_scene == null or bandit_scene == null:
		return

	# (A) Algunos cobres custodiados (no todos)
	var guarded_count := int(floor(copper_positions.size() * 0.45))
	guarded_count = clampi(int(round(float(guarded_count) * camp_spawn_multiplier)), 0, 5)

	for g in range(guarded_count):
		var idx := rng.randi_range(0, copper_positions.size() - 1)
		var copper_tile := copper_positions[idx]

		var camp_tile := _find_nearby_tile(rng, copper_tile, 6, 14) # cerca (6-14 tiles)
		if camp_tile == INVALID_SPAWN_TILE:
			continue
		if not _is_spawn_tile_valid(chunk_pos, camp_tile, player_tile, TAVERN_SAFE_RADIUS_TILES, CAMP_FOOTPRINT_RADIUS_TILES):
			continue

		chunk_save[chunk_pos]["camps"].append({
			"tile": camp_tile
		})
		_mark_footprint_occupied(chunk_pos, camp_tile, CAMP_FOOTPRINT_RADIUS_TILES)

	# (B) Algunos campamentos random (NO cerca del cobre)
	var random_camps := int(round(float(rng.randi_range(1, 3)) * camp_spawn_multiplier))
	random_camps = clampi(random_camps, 1, 6)
	var camp_spawn_failed_logged := false
	for r in range(random_camps):
		var try_tile: Vector2i = INVALID_SPAWN_TILE
		for i in range(SPAWN_MAX_TRIES):
			var candidate: Vector2i = _find_valid_spawn_tile(chunk_pos, player_tile, TAVERN_SAFE_RADIUS_TILES, SPAWN_MAX_TRIES, rng, CAMP_FOOTPRINT_RADIUS_TILES)
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

		# evitar spawn muy cerca del cobre
		chunk_save[chunk_pos]["camps"].append({
			"tile": try_tile
		})
		_mark_footprint_occupied(chunk_pos, try_tile, CAMP_FOOTPRINT_RADIUS_TILES)

func load_chunk_entities(chunk_pos: Vector2i) -> void:
	chunk_entities[chunk_pos] = []
	_rebuild_chunk_occupied_tiles(chunk_pos)

	if not chunk_save.has(chunk_pos):
		return

	for d in chunk_save[chunk_pos]["ores"]:
		var tpos: Vector2i = d["tile"]
		var ore := copper_ore_scene.instantiate()
		ore.global_position = tilemap.to_global(tilemap.map_to_local(tpos))

		if d.has("remaining") and d["remaining"] != -1:
			ore.set("remaining", int(d["remaining"]))

		add_child(ore)
		chunk_entities[chunk_pos].append(ore)
	if chunk_save.has(chunk_pos):
		for t in chunk_save[chunk_pos]["placed_tiles"]:
			tilemap.set_cell(t["layer"], t["tile"], t["source"], t["atlas"])

	for c in chunk_save[chunk_pos]["camps"]:
		var ct: Vector2i = c["tile"]
		var camp := bandit_camp_scene.instantiate()
		camp.global_position = tilemap.to_global(tilemap.map_to_local(ct))
		add_child(camp)
		chunk_entities[chunk_pos].append(camp)

		camp.set("bandit_scene", bandit_scene)

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return tilemap.local_to_map(tilemap.to_local(world_pos))

func _tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	var cx: int = int(floor(float(tile_pos.x) / float(chunk_size)))
	var cy: int = int(floor(float(tile_pos.y) / float(chunk_size)))
	return Vector2i(cx, cy)

func _debug_check_player_chunk(player_global: Vector2) -> void:
	if not DEBUG_SPAWN:
		return

	var player_tile: Vector2i = _world_to_tile(player_global)
	var chunk_key: Vector2i = _tile_to_chunk(player_tile)
	print("[CHUNK_CHECK] player_tile=", player_tile, " player_chunk=", chunk_key)

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

			if has_tavern and safe_radius_tiles > 0:
				var dist_to_tavern: int = probe.distance_to(tavern_tile)
				if dist_to_tavern <= safe_radius_tiles:
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
			print(
				"[REJECT] chunk=", chunk_key,
				" cand=", candidate,
				" dist=", candidate.distance_to(player_tile),
				" occupied=", occ.has(candidate),
				" reason=", _get_spawn_reject_reason(chunk_key, candidate, player_tile, safe_radius_tiles, footprint_radius_tiles)
			)
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

			if has_tavern and safe_radius_tiles > 0:
				var dist_to_tavern: int = probe.distance_to(tavern_tile)
				if dist_to_tavern <= safe_radius_tiles:
					return "inside_tavern_safe_radius"

			if occ.has(probe):
				return "occupied"

	return "unknown"

func _mark_tile_occupied(chunk_key: Vector2i, tile_pos: Vector2i) -> void:
	if tile_pos == INVALID_SPAWN_TILE:
		return

	if not chunk_occupied_tiles.has(chunk_key):
		chunk_occupied_tiles[chunk_key] = {}
	var occ: Dictionary = chunk_occupied_tiles[chunk_key]
	occ[tile_pos] = true

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

func despawn_entities_in_chunk(chunk_pos: Vector2i) -> void:
	if not chunk_entities.has(chunk_pos):
		return
	for e in chunk_entities[chunk_pos]:
		if is_instance_valid(e):
			e.queue_free()
	chunk_entities.erase(chunk_pos)
	print("[SPAWN_SUMMARY] chunk=", chunk_pos,
	" ores=", chunk_save[chunk_pos]["ores"].size(),
	" camps=", chunk_save[chunk_pos]["camps"].size())
func _tile_distance_to_spawn(t: Vector2i) -> float:
	return spawn_tile.distance_to(t)
	
func _spawn_camp_at(chunk_pos: Vector2i, tile_pos: Vector2i) -> void:
	var camp := bandit_camp_scene.instantiate()
	camp.global_position = tilemap.to_global(tilemap.map_to_local(tile_pos))
	add_child(camp)
	chunk_entities[chunk_pos].append(camp)

	# pasarle la escena de bandido al campamento (si tiene la variable)
	if camp.has_method("set"):
		camp.set("bandit_scene", bandit_scene)

func _find_nearby_tile(rng: RandomNumberGenerator, origin: Vector2i, min_r: int, max_r: int) -> Vector2i:
	for i in range(12): # intentos
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

	# 2) PARED SUPERIOR + ESQUINAS ROOF
	# Esquinas superiores
	_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x0, y0 + 1), SRC_WALLS, ROOF_CONT_RIGHT)
	_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x1, y0 + 1), SRC_WALLS, ROOF_CONT_LEFT)
	# Pared horizontal (sin tocar x0 ni x1)
	for x in range(x0 + 1, x1):
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x, y0 + 1), SRC_WALLS, WALL_MID)

	# 3) PARED INFERIOR con puerta
	for x in range(x0, x1 + 1):
		if x == door_x:
			continue
		var atlas_b: Vector2i
		if x == x0:
			atlas_b = WALL_END_LEFT
		elif x == x1:
			atlas_b = WALL_END_RIGHT
		elif x == door_x - 1:
			atlas_b = WALL_END_RIGHT
		elif x == door_x + 1:
			atlas_b = WALL_END_LEFT
		else:
			atlas_b = WALL_MID
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x, y1), SRC_WALLS, atlas_b)

	# 4) PAREDES LATERALES VERTICALES
	for y in range(y0 + 2, y1):
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x0, y), SRC_WALLS, ROOF_VERTICAL)
		_place_tile_persistent(chunk_pos, LAYER_WALLS, Vector2i(x1, y), SRC_WALLS, ROOF_VERTICAL)

	# Guardamos el "centro" de la taberna para usarlo como zona segura.
	tavern_tile = _get_tavern_center_tile_for_chunk(chunk_pos)
	has_tavern = true

func _get_tavern_center_tile_for_chunk(chunk_pos: Vector2i) -> Vector2i:
	var tavern_width: int = 12
	var x0: int = chunk_pos.x * chunk_size + 4
	var y0: int = chunk_pos.y * chunk_size + 3
	return Vector2i(x0 + tavern_width / 2, y0 + 8 / 2)
