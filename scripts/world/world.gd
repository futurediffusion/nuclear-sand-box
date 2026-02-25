extends Node2D

@onready var tilemap: TileMap = $WorldTileMap
@onready var prop_spawner := PropSpawner.new()

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
	prop_spawner.generate_chunk_spawns(chunk_pos, _make_spawn_ctx())

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


func _make_spawn_ctx() -> Dictionary:
	var player_tile: Vector2i = spawn_tile
	if player:
		player_tile = _world_to_tile(player.global_position)
	return {
		"tilemap": tilemap,
		"width": width,
		"height": height,
		"chunk_size": chunk_size,
		"tavern_chunk": tavern_chunk,
		"spawn_tile": spawn_tile,
		"biome_seed": biome_noise.seed,
		"get_biome": Callable(self, "get_biome"),
		"chunk_save": chunk_save,
		"chunk_occupied_tiles": chunk_occupied_tiles,
		"entities_spawned_chunks": entities_spawned_chunks,
		"player_tile": player_tile,
		"copper_ore_scene": copper_ore_scene,
		"bandit_camp_scene": bandit_camp_scene,
		"bandit_scene": bandit_scene,
	}

func load_chunk_entities(chunk_pos: Vector2i) -> void:
	chunk_entities[chunk_pos] = []
	chunk_saveables[chunk_pos] = []
	prop_spawner.rebuild_chunk_occupied_tiles(chunk_pos, _make_spawn_ctx())

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

func get_tavern_center_tile(chunk_pos: Vector2i) -> Vector2i:
	var w: int = 12
	var h: int = 8
	var x0: int = chunk_pos.x * chunk_size + 4
	var y0: int = chunk_pos.y * chunk_size + 3
	return Vector2i(x0 + (w / 2), y0 + (h / 2))
