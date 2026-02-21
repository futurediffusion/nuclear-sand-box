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
const COPPER_MIN_DIST_TILES := 20
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
const BIOME_TILES = {
	0: [  # Arena
		{"col_range": [0,2], "row": 1, "w": 70},  # los 3 tiles de arena
		{"col_range": [0,2], "row": 2, "w": 15},  # los 3 tiles de piedra (invasión)
		{"col_range": [0,2], "row": 0, "w": 15},  # los 3 tiles de pasto (invasión)
	],
	1: [  # Pasto
		{"col_range": [0,2], "row": 0, "w": 70},  # los 3 tiles de pasto
		{"col_range": [0,2], "row": 2, "w": 20},  # los 3 tiles de piedra
		{"col_range": [0,2], "row": 1, "w": 10},  # los 3 tiles de arena
	],
	2: [  # Piedra
		{"col_range": [0,2], "row": 2, "w": 70},  # los 3 tiles de piedra
		{"col_range": [0,2], "row": 1, "w": 20},  # los 3 tiles de arena
		{"col_range": [0,2], "row": 0, "w": 10},  # los 3 tiles de pasto
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

	# Spawn del mundo en el centro del mapa (en tiles)
	spawn_tile = Vector2i(width / 2, height / 2)

	# mover player al centro REAL en el mundo
	if player:
		player.global_position = tilemap.map_to_local(spawn_tile)

	current_player_chunk = world_to_chunk(tilemap.map_to_local(spawn_tile))
	update_chunks(current_player_chunk)

func _process(delta: float) -> void:
	_chunk_timer += delta
	if _chunk_timer < chunk_check_interval:
		return
	_chunk_timer = 0.0

	if not player:
		return
	var pchunk := world_to_chunk(player.position)
	if pchunk != current_player_chunk:
		current_player_chunk = pchunk
		update_chunks(pchunk)

# ─── Chunk logic ────────────────────────────────────────────────

func world_to_chunk(pos: Vector2) -> Vector2i:
	var tile_pos = tilemap.local_to_map(pos)
	return Vector2i(tile_pos.x / chunk_size, tile_pos.y / chunk_size)

func update_chunks(center: Vector2i) -> void:
	var needed: Dictionary = {}
	for cy in range(center.y - active_radius, center.y + active_radius + 1):
		for cx in range(center.x - active_radius, center.x + active_radius + 1):
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
			generated_chunks.erase(cpos)
			generating_chunks.erase(cpos)
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
			tilemap.erase_cell(0, Vector2i(x, y))
	

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

	var total_weight := 0
	for t in tiles:
		total_weight += t["w"]

	_pick_rng.seed = hash(Vector2i(x, y))

	# 1) elegir qué grupo de tile gana (por peso)
	var roll := _pick_rng.randi_range(0, total_weight - 1)
	var acc := 0
	var winner: Dictionary
	for t in tiles:
		acc += t["w"]
		if roll < acc:
			winner = t
			break

	# 2) dentro del grupo ganador, elegir la columna aleatoria (los 3 cuadros)
	var col := _pick_rng.randi_range(winner["col_range"][0], winner["col_range"][1])
	return Vector2i(col, winner["row"])

# ─── Spawner ────────────────────────────────────────────────────

var chunk_entities: Dictionary = {}  # {Vector2i -> Array[Node]}

func spawn_entities_in_chunk(chunk_pos: Vector2i) -> void:
	if not chunk_save.has(chunk_pos):
		chunk_save[chunk_pos] = {"ores": [], "camps": []}
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
		2: attempts = rng.randi_range(6, 16)  # piedra: bastante
		0: attempts = rng.randi_range(3, 7)   # arena: medio
		1: attempts = rng.randi_range(0, 3)   # pasto: poco

	# Cerca del spawn: mínimo 1 intento
	var chunk_center_tile := Vector2i(cx, cy)
	if _tile_distance_to_spawn(chunk_center_tile) <= 30:
		attempts = max(attempts, 1)

	for i in range(attempts):
		var tx := rng.randi_range(chunk_pos.x * chunk_size, chunk_pos.x * chunk_size + chunk_size - 1)
		var ty := rng.randi_range(chunk_pos.y * chunk_size, chunk_pos.y * chunk_size + chunk_size - 1)

		if tx < 0 or tx >= width or ty < 0 or ty >= height:
			continue

		var tpos := Vector2i(tx, ty)

		# regla distancia (la mayoría lejos)
		var dist := _tile_distance_to_spawn(tpos)
		var allow_close := rng.randf() < 0.15
		if not allow_close and dist < COPPER_MIN_DIST_TILES:
			continue

		# regla por BIOMA del tile: 60% piedra / 30% pasto / 20% arena
		var tile_biome := get_biome(tx, ty)
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
		copper_positions.append(tpos)

	# -----------------------------
	# 2) SPAWN CAMPAMENTOS (BANDIDOS)
	# -----------------------------
	if bandit_camp_scene == null or bandit_scene == null:
		return

	# (A) Algunos cobres custodiados (no todos)
	var guarded_count := int(floor(copper_positions.size() * 0.40)) # 25% custodiados
	guarded_count = clampi(guarded_count, 0, 3) # por chunk, máximo 3

	for g in range(guarded_count):
		var idx := rng.randi_range(0, copper_positions.size() - 1)
		var copper_tile := copper_positions[idx]

		var camp_tile := _find_nearby_tile(rng, copper_tile, 6, 14) # cerca (6-14 tiles)
		if camp_tile == Vector2i(-999, -999):
			continue

		chunk_save[chunk_pos]["camps"].append({
			"tile": camp_tile
		})

	# (B) Algunos campamentos random (NO cerca del cobre)
	var random_camps := rng.randi_range(0, 2) # 0-1 campamentos extra por chunk
	for r in range(random_camps):
		var try_tile := Vector2i(
			rng.randi_range(chunk_pos.x * chunk_size, chunk_pos.x * chunk_size + chunk_size - 1),
			rng.randi_range(chunk_pos.y * chunk_size, chunk_pos.y * chunk_size + chunk_size - 1)
		)

		# evitar spawn muy cerca del cobre
		if _is_close_to_any(try_tile, copper_positions, 10):
			continue

		chunk_save[chunk_pos]["camps"].append({
			"tile": try_tile
		})

func load_chunk_entities(chunk_pos: Vector2i) -> void:
	chunk_entities[chunk_pos] = []

	if not chunk_save.has(chunk_pos):
		return

	for d in chunk_save[chunk_pos]["ores"]:
		var tpos: Vector2i = d["tile"]
		var ore := copper_ore_scene.instantiate()
		ore.global_position = tilemap.map_to_local(tpos)

		if d.has("remaining") and d["remaining"] != -1:
			ore.set("remaining", int(d["remaining"]))

		add_child(ore)
		chunk_entities[chunk_pos].append(ore)

	for c in chunk_save[chunk_pos]["camps"]:
		var ct: Vector2i = c["tile"]
		var camp := bandit_camp_scene.instantiate()
		camp.global_position = tilemap.map_to_local(ct)
		add_child(camp)
		chunk_entities[chunk_pos].append(camp)

		camp.set("bandit_scene", bandit_scene)

func unload_chunk_entities(chunk_pos: Vector2i) -> void:
	if not chunk_entities.has(chunk_pos):
		return

	if chunk_save.has(chunk_pos):
		var ore_list = chunk_save[chunk_pos]["ores"]

		for e in chunk_entities[chunk_pos]:
			if is_instance_valid(e) and e is CopperOre:
				var tile := tilemap.local_to_map(e.global_position)
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
func _tile_distance_to_spawn(t: Vector2i) -> float:
	return spawn_tile.distance_to(t)
	
func _spawn_camp_at(chunk_pos: Vector2i, tile_pos: Vector2i) -> void:
	var camp := bandit_camp_scene.instantiate()
	camp.global_position = tilemap.map_to_local(tile_pos)
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

	return Vector2i(-999, -999)

func _is_close_to_any(p: Vector2i, points: Array[Vector2i], max_dist: int) -> bool:
	for q in points:
		if p.distance_to(q) <= float(max_dist):
			return true
	return false
	
