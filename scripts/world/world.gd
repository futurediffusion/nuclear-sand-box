extends Node2D

signal chunk_stage_completed(chunk_pos: Vector2i, stage: String)

@onready var tilemap: TileMap = $WorldTileMap
@onready var walls_tilemap: TileMap = $StructureWallsMap   # <-- paredes van aquí
@onready var ground_tilemap: TileMap = $GroundTileMap
@onready var cliffs_tilemap: TileMap = $TileMap_Cliffs
@onready var prop_spawner := PropSpawner.new()
@onready var chunk_generator := ChunkGenerator.new()
@onready var _collision_builder := CollisionBuilder.new()
var _tile_painter := TilePainter.new()

@export var width: int = 256
@export var height: int = 256
@export var chunk_size: int = 32
@export var active_radius: int = 1
@export var chunk_check_interval: float = 0.3
@export var copper_ore_scene: PackedScene
@export var bandit_camp_scene: PackedScene
@export var bandit_scene: PackedScene
@export var tavern_keeper_scene: PackedScene
@export_group("Chunk Perf Debug")
@export var debug_chunk_perf_enabled: bool = true
@export var debug_chunk_perf_window_size: int = 64
@export var debug_chunk_perf_auto_print: bool = false
@export var debug_chunk_perf_print_interval: float = 5.0
@export var debug_chunk_perf_auto_calibrate_runtime: bool = false
@export var debug_chunk_perf_ring0_alert_generate_ms: float = 4.0
@export var debug_chunk_perf_ring0_alert_ground_connect_ms: float = 4.0
@export var debug_chunk_perf_ring0_alert_wall_connect_ms: float = 4.0
@export var debug_chunk_perf_ring0_alert_collider_ms: float = 4.0
@export var debug_chunk_perf_ring0_alert_entities_ms: float = 4.0
@export var max_cached_chunk_colliders: int = 64
@export var debug_collision_cache: bool = false

var _biome_seed: int = 0
var cliff_generator: CliffGenerator
var _cliff_seed: int = 0
var _ground_painter := GroundPainter.new()
var _ground_terrain_painted_chunks: Dictionary = {}

var player: Node2D
var loaded_chunks: Dictionary = {}
var current_player_chunk := Vector2i(-999, -999)

var spawn_tile: Vector2i
var tavern_chunk: Vector2i
var _chunk_timer: float = 0.0
var npc_simulator: NpcSimulator
var entity_coordinator: EntitySpawnCoordinator
var pipeline: ChunkPipeline

var chunk_save: Dictionary = {}
var _spawn_queue: SpawnBudgetQueue
var _perf_monitor := ChunkPerfMonitor.new()

const CHUNK_PERF_STAGE_COLLIDER_BUILD: String = "collider build"

const LAYER_GROUND: int = 0
const LAYER_FLOOR: int = 1
const WALL_TERRAIN_SET: int = 0
const WALL_TERRAIN: int = 0

# StructureWallsMap usa siempre layer 0
const WALLS_MAP_LAYER: int = 0

const SRC_FLOOR: int = 1
const SRC_WALLS: int = 2

const FLOOR_WOOD: Vector2i = Vector2i(0, 0)

# Biome IDs used by PropSpawner via get_spawn_biome()
const BIOME_ID_GRASSLAND: int = 1
const BIOME_ID_DENSE_GRASS: int = 2

func _ready() -> void:
	_clear_chunk_wall_runtime_cache()
	add_to_group("world")
	Debug.log("boot", "World._ready begin")
	_biome_seed = randi()
	_ground_painter.setup(randi(), width, height)
	ground_tilemap.z_index = -1
	tilemap.set_layer_enabled(LAYER_GROUND, false)
	_perf_monitor.enabled = debug_chunk_perf_enabled
	_perf_monitor.window_size = debug_chunk_perf_window_size
	_perf_monitor.auto_print = debug_chunk_perf_auto_print
	_perf_monitor.print_interval = debug_chunk_perf_print_interval
	_perf_monitor.auto_calibrate = debug_chunk_perf_auto_calibrate_runtime
	_perf_monitor.alert_generate_ms = debug_chunk_perf_ring0_alert_generate_ms
	_perf_monitor.alert_ground_connect_ms = debug_chunk_perf_ring0_alert_ground_connect_ms
	_perf_monitor.alert_wall_connect_ms = debug_chunk_perf_ring0_alert_wall_connect_ms
	_perf_monitor.alert_collider_ms = debug_chunk_perf_ring0_alert_collider_ms
	_perf_monitor.alert_entities_ms = debug_chunk_perf_ring0_alert_entities_ms

	player = get_node_or_null("../Player")

	var occ_ctrl := OcclusionController.new()
	occ_ctrl.name = "OcclusionController"
	add_child(occ_ctrl)

	tavern_chunk = _tile_to_chunk(Vector2i(width / 2, height / 2))
	spawn_tile = get_tavern_center_tile(tavern_chunk)

	var spawn_world: Vector2 = _tile_to_world(spawn_tile)
	if player:
		player.global_position = spawn_world

	current_player_chunk = world_to_chunk(spawn_world)

	# Create subsystems before wiring them together
	npc_simulator = NpcSimulator.new()
	npc_simulator.name = "NpcSimulator"
	add_child(npc_simulator)

	entity_coordinator = EntitySpawnCoordinator.new()
	entity_coordinator.name = "EntitySpawnCoordinator"
	add_child(entity_coordinator)

	pipeline = ChunkPipeline.new()
	pipeline.name = "ChunkPipeline"
	add_child(pipeline)

	entity_coordinator.setup({
		"prop_spawner": prop_spawner,
		"npc_simulator": npc_simulator,
		"chunk_save": chunk_save,
		"loaded_chunks": loaded_chunks,
		"tilemap": tilemap,
		"copper_ore_scene": copper_ore_scene,
		"bandit_camp_scene": bandit_camp_scene,
		"bandit_scene": bandit_scene,
		"tavern_keeper_scene": tavern_keeper_scene,
		"make_spawn_ctx": Callable(self, "_make_spawn_ctx"),
		"tile_to_world": Callable(self, "_tile_to_world"),
		"chunk_key": Callable(self, "_chunk_key"),
		"chunk_from_key": Callable(self, "_chunk_from_key"),
		"enqueue_structure_tile_stage": Callable(pipeline, "enqueue_structure_tile_stage"),
		"record_stage_time": Callable(self, "_record_chunk_stage_time"),
	})
	entity_coordinator.current_player_chunk = current_player_chunk
	_spawn_queue = entity_coordinator.get_spawn_queue()

	_cliff_seed = randi()
	cliff_generator = CliffGenerator.new()
	cliff_generator.name = "CliffGenerator"
	add_child(cliff_generator)
	cliff_generator.setup({
		"x_min": 0, "x_max": width, "y_min": 0, "y_max": height,
		"chunk_size": chunk_size, "layer": LAYER_GROUND,
		"terrain_set_id": 0, "terrain_id": 2,
		"spawn_center": spawn_tile,
		"cliff_seed": _cliff_seed,
		"cliffs_tilemap": cliffs_tilemap,
	})
	cliff_generator.global_phase()

	pipeline.setup({
		"chunk_generator": chunk_generator,
		"prop_spawner": prop_spawner,
		"entity_coordinator": entity_coordinator,
		"tilemap": tilemap,
		"walls_tilemap": walls_tilemap,
		"ground_tilemap": ground_tilemap,
		"tile_painter": _tile_painter,
		"chunk_save": chunk_save,
		"loaded_chunks": loaded_chunks,
		"player": player,
		"active_radius": active_radius,
		"width": width,
		"height": height,
		"chunk_size": chunk_size,
		"layer_floor": LAYER_FLOOR,
		"src_floor": SRC_FLOOR,
		"floor_wood": FLOOR_WOOD,
		"walls_map_layer": WALLS_MAP_LAYER,
		"wall_terrain_set": WALL_TERRAIN_SET,
		"wall_terrain": WALL_TERRAIN,
		"chunk_key": Callable(self, "_chunk_key"),
		"world_to_tile": Callable(self, "_world_to_tile"),
		"tile_to_chunk": Callable(self, "_tile_to_chunk"),
		"record_stage_time": Callable(self, "_record_chunk_stage_time"),
		"emit_stage_completed": func(pos: Vector2i, stage: String) -> void: emit_signal("chunk_stage_completed", pos, stage),
		"ensure_chunk_wall_collision": Callable(self, "_ensure_chunk_wall_collision"),
		"make_spawn_ctx": Callable(self, "_make_spawn_ctx"),
		"on_ground_fallback_debug": Callable(self, "_on_ground_fallback_debug"),
		"get_terrain": Callable(_ground_painter, "get_terrain"),
		"cliff_generator": cliff_generator,
		"cliffs_tilemap": cliffs_tilemap,
	})
	pipeline.current_player_chunk = current_player_chunk

	npc_simulator.setup({
		"player": player,
		"bandit_scene": bandit_scene,
		"spawn_queue": _spawn_queue,
		"loaded_chunks": loaded_chunks,
		"chunk_save": chunk_save,
		"tile_to_world": Callable(self, "_tile_to_world"),
		"chunk_key": Callable(self, "_chunk_key"),
	})
	npc_simulator.current_player_chunk = current_player_chunk
	if GameEvents != null and not GameEvents.entity_died.is_connected(_on_entity_died):
		GameEvents.entity_died.connect(_on_entity_died)
	await update_chunks(current_player_chunk)

func _clear_chunk_wall_runtime_cache() -> void:
	for cpos in chunk_wall_body.keys():
		var body: StaticBody2D = chunk_wall_body[cpos]
		if body != null and is_instance_valid(body):
			body.queue_free()
	chunk_wall_body.clear()
	_chunk_wall_last_used.clear()
	_chunk_wall_use_counter = 0

func _process(delta: float) -> void:
	pipeline.process(delta)
	if entity_coordinator != null and player:
		entity_coordinator.set_player_pos(player.global_position)
	_process_chunk_perf_debug(delta)
	_chunk_timer += delta
	if _chunk_timer < chunk_check_interval:
		return
	_chunk_timer = 0.0
	if not player:
		return
	var pchunk := world_to_chunk(player.global_position)
	if pchunk != current_player_chunk:
		current_player_chunk = pchunk
		pipeline.current_player_chunk = pchunk
		if npc_simulator:
			npc_simulator.current_player_chunk = pchunk
		if entity_coordinator:
			entity_coordinator.current_player_chunk = pchunk
		update_chunks(pchunk)


func world_to_chunk(pos: Vector2) -> Vector2i:
	return _tile_to_chunk(_world_to_tile(pos))

func _is_chunk_in_active_window(chunk_pos: Vector2i, center: Vector2i) -> bool:
	return abs(chunk_pos.x - center.x) <= active_radius and abs(chunk_pos.y - center.y) <= active_radius

func update_chunks(center: Vector2i) -> void:
	if pipeline.is_updating:
		return
	Debug.log("boot", "ChunkManager load begin center=%s" % center)
	Debug.log("chunk", "CENTER moved -> (%d,%d)" % [center.x, center.y])
	if player:
		_debug_check_tile_alignment(player.global_position)
		_debug_check_player_chunk(player.global_position)

	var needed: Dictionary = {}
	var needed_chunks: Array[Vector2i] = []
	var max_chunk_x: int = int(floor(float(width - 1) / float(chunk_size)))
	var max_chunk_y: int = int(floor(float(height - 1) / float(chunk_size)))

	for cy in range(center.y - active_radius, center.y + active_radius + 1):
		for cx in range(center.x - active_radius, center.x + active_radius + 1):
			if cx < 0 or cx > max_chunk_x or cy < 0 or cy > max_chunk_y:
				continue
			var cpos := Vector2i(cx, cy)
			needed[cpos] = true
			needed_chunks.append(cpos)

	if pipeline.terrain_paint_ring_priority_enabled:
		needed_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var ring_a: int = max(abs(a.x - center.x), abs(a.y - center.y))
			var ring_b: int = max(abs(b.x - center.x), abs(b.y - center.y))
			if ring_a == ring_b:
				if a.y == b.y:
					return a.x < b.x
				return a.y < b.y
			return ring_a < ring_b
		)

	if pipeline.progressive_terrain_paint_enabled:
		pipeline.reset_terrain_paint_epoch()

	for cpos in needed_chunks:
		if not pipeline.generated_chunks.has(cpos) and not pipeline.generating_chunks.has(cpos):
			pipeline.generating_chunks[cpos] = true
			await pipeline.generate_chunk(cpos, true)
		if pipeline.generating_chunks.has(cpos):
			continue
		if not loaded_chunks.has(cpos):
			entity_coordinator.load_chunk(cpos)
			loaded_chunks[cpos] = true
		if pipeline.progressive_terrain_paint_enabled and _is_chunk_in_active_window(cpos, center):
			pipeline.enqueue_terrain_paint(cpos, center, pipeline.terrain_paint_epoch)

	# Pass 2: paint GroundTileMap for new chunks (batched so set_cells_terrain_connect sees neighbors)
	var ground_to_paint: Array[Vector2i] = []
	for cpos in needed_chunks:
		if not _ground_terrain_painted_chunks.has(_chunk_key(cpos)):
			ground_to_paint.append(cpos)
	if not ground_to_paint.is_empty():
		await chunk_generator.apply_ground_terrain_ctx(ground_to_paint, pipeline.make_ground_terrain_ctx())
		for cpos in ground_to_paint:
			_ground_terrain_painted_chunks[_chunk_key(cpos)] = true

	for cpos in loaded_chunks.keys():
		if not needed.has(cpos):
			unload_chunk(cpos)
			entity_coordinator.unload_entities(cpos)
			pipeline.on_chunk_unloaded(cpos)
			loaded_chunks.erase(cpos)

	if pipeline.progressive_terrain_paint_enabled and pipeline.terrain_paint_center_ring0_pending == 0:
		pipeline.is_updating = false
	Debug.log("boot", "ChunkManager load end center=%s" % center)


func _record_chunk_stage_time(stage: String, chunk_pos: Vector2i, elapsed_ms: float) -> void:
	_perf_monitor.record(stage, chunk_pos, current_player_chunk, elapsed_ms)

func debug_print_chunk_stage_percentiles() -> void:
	_perf_monitor.print_percentiles()
	_apply_calibrated_perf_budgets()

func _process_chunk_perf_debug(delta: float) -> void:
	if _perf_monitor.tick(delta):
		_apply_calibrated_perf_budgets()

func _apply_calibrated_perf_budgets() -> void:
	var budgets := _perf_monitor.get_calibrated_budgets()
	if budgets.has("terrain_paint_ms_budget"):
		pipeline.terrain_paint_ms_budget = budgets["terrain_paint_ms_budget"]
	if budgets.has("wall_collider_chunks_per_tick"):
		pipeline.wall_collider_chunks_per_tick = budgets["wall_collider_chunks_per_tick"]

func unload_chunk(chunk_pos: Vector2i) -> void:
	# Borrar suelo del WorldTileMap
	_tile_painter.erase_chunk_region(tilemap, chunk_pos, chunk_size, [LAYER_GROUND, LAYER_FLOOR])
	# Borrar paredes del StructureWallsMap
	_tile_painter.erase_chunk_region(walls_tilemap, chunk_pos, chunk_size, [WALLS_MAP_LAYER])
	# Borrar suelo del GroundTileMap
	_tile_painter.erase_chunk_region(ground_tilemap, chunk_pos, chunk_size, [0])
	_ground_terrain_painted_chunks.erase(_chunk_key(chunk_pos))

func get_spawn_biome(x: int, y: int) -> int:
	var terrain := _ground_painter.get_terrain(x, y)
	if terrain == 0:  # dirt patch → alta densidad de ores
		return BIOME_ID_DENSE_GRASS
	return BIOME_ID_GRASSLAND  # grass → baja densidad

var chunk_occupied_tiles: Dictionary = {}
var chunk_wall_body: Dictionary = {}
var _chunk_wall_last_used: Dictionary = {}
var _chunk_wall_use_counter: int = 0

const DEBUG_SPAWN: bool = true

func _debug_check_tile_alignment(player_global: Vector2) -> void:
	if not DEBUG_SPAWN: return
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
		"biome_seed": _biome_seed,
		"get_biome": Callable(self, "get_spawn_biome"),
		"chunk_save": chunk_save,
		"chunk_occupied_tiles": chunk_occupied_tiles,
		"entities_spawned_chunks": entity_coordinator.entities_spawned_chunks,
		"player_tile": player_tile,
		"player_chunk": current_player_chunk,
		"copper_ore_scene": copper_ore_scene,
		"bandit_camp_scene": bandit_camp_scene,
		"bandit_scene": bandit_scene,
	}

func _on_ground_fallback_debug(chunk_pos: Vector2i, total_cells: int, missing_cells: int, invalid_source_cells: int, mode: String = "legacy") -> void:
	_perf_monitor.record_fallback(chunk_pos, total_cells, missing_cells, invalid_source_cells, mode)

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return tilemap.local_to_map(tilemap.to_local(world_pos))

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return tilemap.to_global(tilemap.map_to_local(tile_pos))

func _tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	return Vector2i(int(floor(float(tile_pos.x) / float(chunk_size))), int(floor(float(tile_pos.y) / float(chunk_size))))

func _debug_check_player_chunk(player_global: Vector2) -> void:
	if not DEBUG_SPAWN: return
	var player_tile: Vector2i = _world_to_tile(player_global)
	var chunk_key: Vector2i = _tile_to_chunk(player_tile)
	Debug.log("spawn", "CHUNK_CHECK player_tile=%s player_chunk=%s" % [str(player_tile), str(chunk_key)])

func unload_chunk_entities(chunk_pos: Vector2i) -> void:
	pipeline.on_chunk_unloaded(chunk_pos)
	entity_coordinator.unload_entities(chunk_pos)

	if chunk_wall_body.has(chunk_pos):
		var body: StaticBody2D = chunk_wall_body[chunk_pos]
		if is_instance_valid(body):
			_collision_builder.set_chunk_collider_enabled(body, false)
			_touch_chunk_wall_usage(chunk_pos)
	_enforce_chunk_collider_cache_limit()

func _chunk_key(chunk_pos: Vector2i) -> String:
	return "%d,%d" % [chunk_pos.x, chunk_pos.y]

func _chunk_from_key(chunk_key: String) -> Vector2i:
	var parts: PackedStringArray = chunk_key.split(",")
	if parts.size() != 2:
		return Vector2i(-99999, -99999)
	return Vector2i(int(parts[0]), int(parts[1]))


func mark_chunk_walls_dirty(cx: int, cy: int) -> void:
	WorldSave.set_chunk_flag(cx, cy, "walls_dirty", true)

func _ensure_chunk_wall_collision(chunk_pos: Vector2i) -> void:
	var collider_start_us: int = Time.get_ticks_usec()
	var cx: int = chunk_pos.x
	var cy: int = chunk_pos.y
	var chunk_key: String = _chunk_key(chunk_pos)
	var current_hash: int = _compute_walls_hash(chunk_pos)
	var saved_hash = WorldSave.get_chunk_flag(cx, cy, "walls_hash")
	var dirty: bool = WorldSave.get_chunk_flag(cx, cy, "walls_dirty") == true
	var collider_exists: bool = _has_valid_chunk_wall_body(chunk_pos)

	var must_rebuild: bool = dirty or saved_hash == null or int(saved_hash) != current_hash or not collider_exists
	if must_rebuild:
		if collider_exists:
			var old_body: StaticBody2D = chunk_wall_body[chunk_pos]
			if is_instance_valid(old_body):
				old_body.queue_free()
		chunk_wall_body.erase(chunk_pos)
		_chunk_wall_last_used.erase(chunk_key)

		var body: StaticBody2D = _collision_builder.build_chunk_walls(
			walls_tilemap, chunk_pos, chunk_size, WALLS_MAP_LAYER, SRC_WALLS
		)
		if body != null:
			walls_tilemap.add_child(body)
			chunk_wall_body[chunk_pos] = body
			_collision_builder.set_chunk_collider_enabled(body, true)
			_touch_chunk_wall_usage(chunk_pos)

		WorldSave.set_chunk_flag(cx, cy, "walls_hash", current_hash)
		WorldSave.set_chunk_flag(cx, cy, "walls_dirty", false)
		if debug_collision_cache:
			var reason: String = ""
			if dirty:
				reason = "dirty"
			elif saved_hash == null:
				reason = "missing_hash"
			elif not collider_exists:
				reason = "missing_collider"
			else:
				reason = "hash_changed"
			Debug.log("chunk", "REBUILD walls collider chunk=%s reason=%s hash=%d" % [chunk_key, reason, current_hash])
		_record_chunk_stage_time(CHUNK_PERF_STAGE_COLLIDER_BUILD, chunk_pos, float(Time.get_ticks_usec() - collider_start_us) / 1000.0)
		return

	var cached_body: StaticBody2D = chunk_wall_body[chunk_pos]
	_collision_builder.set_chunk_collider_enabled(cached_body, true)
	_touch_chunk_wall_usage(chunk_pos)
	if debug_collision_cache:
		Debug.log("chunk", "REUSE walls collider chunk=%s hash=%d" % [chunk_key, current_hash])
	_record_chunk_stage_time(CHUNK_PERF_STAGE_COLLIDER_BUILD, chunk_pos, float(Time.get_ticks_usec() - collider_start_us) / 1000.0)

func _has_valid_chunk_wall_body(chunk_pos: Vector2i) -> bool:
	if not chunk_wall_body.has(chunk_pos):
		return false
	var body: StaticBody2D = chunk_wall_body[chunk_pos]
	if body == null or not is_instance_valid(body):
		chunk_wall_body.erase(chunk_pos)
		_chunk_wall_last_used.erase(_chunk_key(chunk_pos))
		return false
	return true

func _compute_walls_hash(chunk_pos: Vector2i) -> int:
	var start_x: int = chunk_pos.x * chunk_size
	var start_y: int = chunk_pos.y * chunk_size
	var end_x: int = start_x + chunk_size
	var end_y: int = start_y + chunk_size
	var h: int = 2166136261
	for y in range(start_y, end_y):
		for x in range(start_x, end_x):
			var cell := Vector2i(x, y)
			var source_id: int = walls_tilemap.get_cell_source_id(WALLS_MAP_LAYER, cell)
			if source_id == -1:
				continue
			var atlas: Vector2i = walls_tilemap.get_cell_atlas_coords(WALLS_MAP_LAYER, cell)
			var alt: int = walls_tilemap.get_cell_alternative_tile(WALLS_MAP_LAYER, cell)
			h = _fnv1a_mix_int(h, x)
			h = _fnv1a_mix_int(h, y)
			h = _fnv1a_mix_int(h, source_id)
			h = _fnv1a_mix_int(h, atlas.x)
			h = _fnv1a_mix_int(h, atlas.y)
			h = _fnv1a_mix_int(h, alt)
	return h

func _fnv1a_mix_int(h: int, value: int) -> int:
	var n: int = value
	h = int((h ^ n) * 16777619)
	return h

func _touch_chunk_wall_usage(chunk_pos: Vector2i) -> void:
	_chunk_wall_use_counter += 1
	_chunk_wall_last_used[_chunk_key(chunk_pos)] = _chunk_wall_use_counter

func _enforce_chunk_collider_cache_limit() -> void:
	if max_cached_chunk_colliders <= 0:
		return
	if chunk_wall_body.size() <= max_cached_chunk_colliders:
		return

	var candidates: Array[Dictionary] = []
	for cpos in chunk_wall_body.keys():
		if _is_chunk_in_active_window(cpos, current_player_chunk):
			continue
		if loaded_chunks.has(cpos):
			continue
		var key: String = _chunk_key(cpos)
		var used_at: int = int(_chunk_wall_last_used.get(key, -1))
		candidates.append({"chunk_pos": cpos, "used_at": used_at})

	if candidates.is_empty():
		return

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("used_at", -1)) < int(b.get("used_at", -1))
	)

	for candidate in candidates:
		if chunk_wall_body.size() <= max_cached_chunk_colliders:
			break
		var cpos: Vector2i = candidate["chunk_pos"]
		var key: String = _chunk_key(cpos)
		var body: StaticBody2D = chunk_wall_body.get(cpos, null)
		if body != null and is_instance_valid(body):
			body.queue_free()
		chunk_wall_body.erase(cpos)
		_chunk_wall_last_used.erase(key)

func get_tavern_center_tile(chunk_pos: Vector2i) -> Vector2i:
	var x0: int = chunk_pos.x * chunk_size + 4
	var y0: int = chunk_pos.y * chunk_size + 3
	return Vector2i(x0 + 6, y0 + 4)


func _on_entity_died(uid: String, kind: String, _pos: Vector2, _killer: Node) -> void:
	if kind != "enemy":
		return
	if uid == "":
		return
	npc_simulator.on_entity_died(uid)
