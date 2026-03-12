extends Node
class_name ChunkPipeline

const WorldTerrainConfig = preload("res://scripts/world/WorldTerrainConfig.gd")

# ── Stage name constants ───────────────────────────────────────────────────────
const CHUNK_PERF_STAGE_GENERATE: String = "generate"
const CHUNK_PERF_STAGE_GROUND_CONNECT: String = "ground terrain connect"
const CHUNK_PERF_STAGE_WALL_CONNECT: String = "wall terrain connect"
const CHUNK_PERF_STAGE_COLLIDER_BUILD: String = "collider build"
const CHUNK_PERF_STAGE_ENTITIES: String = "enqueue/spawn entities"

const PREFETCH_QUEUE_MAX: int = 64

# ── Exported settings ─────────────────────────────────────────────────────────
@export var prefetch_enabled: bool = true
@export var prefetch_border_tiles: int = 6
@export var prefetch_ring_radius: int = 1
@export var prefetch_budget_chunks_per_tick: int = 1
@export var prefetch_check_interval: float = 0.15
@export var prefetch_enqueue_entities: bool = false
@export var prefetch_entity_priority_offset: int = 5
@export var prefetch_prepare_ground_enabled: bool = true
@export var prefetch_prepare_walls_enabled: bool = true
@export var prefetch_frame_pressure_fps_threshold: float = 52.0
@export var prefetch_frame_pressure_budget_floor: int = 0
@export var progressive_terrain_paint_enabled: bool = true

@export_group("Ground Mapping")
@export var corrected_ground_mapping_enabled: bool = true
@export var corrected_ground_mapping_ring0_only: bool = true
@export var legacy_ground_mapping_allow_fallback: bool = true

@export_group("Paint Budgets")
@export var terrain_paint_chunks_per_tick: int = 2
@export var terrain_paint_ms_budget: float = 1.5
@export var terrain_paint_ring_priority_enabled: bool = true
@export var structure_tile_chunks_per_tick: int = 2
@export var wall_collider_chunks_per_tick: int = 2

# ── Pipeline state ────────────────────────────────────────────────────────────
var generated_chunks: Dictionary = {}
var generating_chunks: Dictionary = {}
var prefetched_chunks: Dictionary = {}
var prefetched_visual_chunks: Dictionary = {}
var prefetching_chunks: Dictionary = {}
var _prefetch_queue: Array[Vector2i] = []
var _prefetch_timer: float = 0.0
var _last_prefetch_center_chunk_key: String = ""

var _terrain_paint_queue: Array[Dictionary] = []
var _terrain_paint_enqueued: Dictionary = {}
var _terrain_painted_chunks: Dictionary = {}
var terrain_paint_epoch: int = 0
var terrain_paint_center_ring0_pending: int = 0

var _structure_tile_queue: Array[Vector2i] = []
var _structure_tile_enqueued: Dictionary = {}
var _collider_queue: Array[Vector2i] = []
var _collider_enqueued: Dictionary = {}

var is_updating: bool = false

# ── Injected references ───────────────────────────────────────────────────────
var chunk_generator  # ChunkGenerator
var prop_spawner     # PropSpawner
var entity_coordinator: EntitySpawnCoordinator
var tilemap: TileMap
var walls_tilemap: TileMap
var ground_tilemap: TileMap
var _cliff_generator: CliffGenerator
var _cliffs_tilemap: TileMap
var _tile_painter    # TilePainter
var chunk_save: Dictionary
var loaded_chunks: Dictionary
var player: Node2D
var current_player_chunk: Vector2i = Vector2i(-999, -999)

var active_radius: int = 1
var width: int = 256
var height: int = 256
var chunk_size: int = 32

# Tile layer values (injected from world constants)
var _layer_floor: int = 1
var _src_floor: int = 1
var _floor_wood: Vector2i = Vector2i(0, 0)
var _walls_map_layer: int = 0
var _wall_terrain_set: int = 0
var _wall_terrain: int = 0

# ── Injected callables ────────────────────────────────────────────────────────
var _chunk_key: Callable
var _world_to_tile: Callable
var _tile_to_chunk: Callable
var _record_stage_time: Callable
var _emit_stage_completed: Callable
var _ensure_chunk_wall_collision: Callable
var _make_spawn_ctx: Callable
var _on_ground_fallback_debug: Callable
var _get_terrain: Callable  # from GroundPainter


func setup(ctx: Dictionary) -> void:
	chunk_generator = ctx["chunk_generator"]
	prop_spawner = ctx["prop_spawner"]
	entity_coordinator = ctx["entity_coordinator"]
	tilemap = ctx["tilemap"]
	walls_tilemap = ctx["walls_tilemap"]
	ground_tilemap = ctx["ground_tilemap"]
	_tile_painter = ctx["tile_painter"]
	chunk_save = ctx["chunk_save"]
	loaded_chunks = ctx["loaded_chunks"]
	player = ctx.get("player")
	active_radius = ctx.get("active_radius", 1)
	width = ctx.get("width", 256)
	height = ctx.get("height", 256)
	chunk_size = ctx.get("chunk_size", 32)
	_layer_floor = ctx.get("layer_floor", 1)
	_src_floor = ctx.get("src_floor", 1)
	_floor_wood = ctx.get("floor_wood", Vector2i(0, 0))
	_walls_map_layer = ctx.get("walls_map_layer", 0)
	_wall_terrain_set = ctx.get("wall_terrain_set", 0)
	_wall_terrain = ctx.get("wall_terrain", 0)
	_chunk_key = ctx["chunk_key"]
	_world_to_tile = ctx["world_to_tile"]
	_tile_to_chunk = ctx["tile_to_chunk"]
	_record_stage_time = ctx["record_stage_time"]
	_emit_stage_completed = ctx["emit_stage_completed"]
	_ensure_chunk_wall_collision = ctx["ensure_chunk_wall_collision"]
	_make_spawn_ctx = ctx["make_spawn_ctx"]
	_on_ground_fallback_debug = ctx["on_ground_fallback_debug"]
	_get_terrain = ctx["get_terrain"]
	_cliff_generator = ctx.get("cliff_generator")
	_cliffs_tilemap = ctx.get("cliffs_tilemap")


# Called every frame from world._process(delta)
func process(delta: float) -> void:
	_process_chunk_stage_queues()
	_process_prefetch(delta)
	_process_terrain_paint_scheduler()


# Called by world.update_chunks before iterating needed_chunks
func reset_terrain_paint_epoch() -> void:
	terrain_paint_epoch += 1
	_terrain_paint_queue.clear()
	_terrain_paint_enqueued.clear()
	terrain_paint_center_ring0_pending = 0
	is_updating = true


# Called by world when a chunk is removed from loaded_chunks
func on_chunk_unloaded(chunk_pos: Vector2i) -> void:
	_structure_tile_enqueued.erase(chunk_pos)
	_collider_enqueued.erase(chunk_pos)
	var key: String = _chunk_key.call(chunk_pos)
	prefetching_chunks.erase(key)
	_terrain_painted_chunks.erase(key)


func enqueue_terrain_paint(chunk_pos: Vector2i, center: Vector2i, epoch: int) -> void:
	_enqueue_terrain_paint_chunk(chunk_pos, center, epoch)


func make_ground_terrain_ctx() -> Dictionary:
	return _make_ground_terrain_ctx()


# ── Core generation ───────────────────────────────────────────────────────────

func generate_chunk(chunk_pos: Vector2i, spawn_entities: bool = true) -> void:
	Debug.log("chunk", "GENERATE chunk=(%d,%d) run_seed=%d chunk_seed=%d" % [
		chunk_pos.x, chunk_pos.y, Seed.run_seed, Seed.chunk_seed(chunk_pos.x, chunk_pos.y)
	])
	var generate_start_us: int = Time.get_ticks_usec()
	prop_spawner.generate_chunk_spawns(chunk_pos, _make_spawn_ctx.call())
	_record_stage_time.call(
		CHUNK_PERF_STAGE_GENERATE, chunk_pos,
		float(Time.get_ticks_usec() - generate_start_us) / 1000.0
	)
	generated_chunks[chunk_pos] = true
	generating_chunks.erase(chunk_pos)
	if spawn_entities and _is_chunk_in_active_window(chunk_pos, current_player_chunk):
		if not loaded_chunks.has(chunk_pos):
			entity_coordinator.load_chunk(chunk_pos)
			loaded_chunks[chunk_pos] = true


# ── Stage queues ──────────────────────────────────────────────────────────────

func _process_chunk_stage_queues() -> void:
	var tiles_budget: int = max(0, structure_tile_chunks_per_tick)
	while tiles_budget > 0 and not _structure_tile_queue.is_empty():
		var chunk_pos: Vector2i = _structure_tile_queue.pop_front()
		_structure_tile_enqueued.erase(chunk_pos)
		if not loaded_chunks.has(chunk_pos):
			continue
		prepare_chunk_tiles(chunk_pos)
		_emit_stage_completed.call(chunk_pos, "tiles")
		_enqueue_collider_stage(chunk_pos)
		tiles_budget -= 1

	var collider_budget: int = max(0, wall_collider_chunks_per_tick)
	while collider_budget > 0 and not _collider_queue.is_empty():
		var chunk_pos: Vector2i = _collider_queue.pop_front()
		_collider_enqueued.erase(chunk_pos)
		if not loaded_chunks.has(chunk_pos):
			continue
		prepare_chunk_colliders(chunk_pos)
		_emit_stage_completed.call(chunk_pos, "collision")
		entity_coordinator.enqueue_entities(chunk_pos)
		_emit_stage_completed.call(chunk_pos, "entities_enqueued")
		collider_budget -= 1


func enqueue_structure_tile_stage(chunk_pos: Vector2i) -> void:
	if _structure_tile_enqueued.has(chunk_pos):
		return
	_structure_tile_queue.append(chunk_pos)
	_structure_tile_enqueued[chunk_pos] = true


func _enqueue_collider_stage(chunk_pos: Vector2i) -> void:
	if _collider_enqueued.has(chunk_pos):
		return
	_collider_queue.append(chunk_pos)
	_collider_enqueued[chunk_pos] = true


func prepare_chunk_tiles(chunk_pos: Vector2i) -> void:
	if not chunk_save.has(chunk_pos):
		return
	_apply_chunk_persistent_tiles(chunk_pos)
	if _cliff_generator != null:
		_cliff_generator.paint_chunk_cliffs(chunk_pos)
	var key: String = _chunk_key.call(chunk_pos)
	_terrain_painted_chunks[key] = true
	_terrain_paint_enqueued.erase(key)


func prepare_chunk_colliders(chunk_pos: Vector2i) -> void:
	if not chunk_save.has(chunk_pos):
		return
	_ensure_chunk_wall_collision.call(chunk_pos)
	if _cliff_generator != null:
		_cliff_generator.build_chunk_cliff_collisions(chunk_pos)


# ── Persistent tile application ───────────────────────────────────────────────

func _apply_chunk_persistent_tiles(chunk_pos: Vector2i, include_ground: bool = true, include_walls: bool = true) -> void:
	if not chunk_save.has(chunk_pos):
		return
	var floor_cells: Array[Vector2i] = []
	var wall_terrain_cells: Array[Vector2i] = []
	var manual_tiles: Array[Dictionary] = []

	for t in chunk_save[chunk_pos].get("placed_tiles", []):
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var source_id: int = int(t.get("source", 0))
		if source_id == -1:
			wall_terrain_cells.append(t["tile"])
		elif int(t.get("layer", -1)) == _layer_floor and source_id == _src_floor and t.get("atlas", Vector2i(-1, -1)) == _floor_wood:
			floor_cells.append(t["tile"])
		else:
			manual_tiles.append(t)

	if include_ground and floor_cells.size() > 0:
		_tile_painter.apply_floor(tilemap, _layer_floor, _src_floor, _floor_wood, floor_cells)
	if include_ground and manual_tiles.size() > 0:
		_tile_painter.apply_manual_tiles(tilemap, manual_tiles)
	if include_walls and wall_terrain_cells.size() > 0:
		Debug.log("chunk", "WALL_TERRAIN_PAINT chunk=(%d,%d) cells=%d -> StructureWallsMap" % [chunk_pos.x, chunk_pos.y, wall_terrain_cells.size()])
		var wall_start_us: int = Time.get_ticks_usec()
		_tile_painter.apply_walls_terrain_connect(walls_tilemap, _walls_map_layer, _wall_terrain_set, _wall_terrain, wall_terrain_cells)
		_record_stage_time.call(CHUNK_PERF_STAGE_WALL_CONNECT, chunk_pos, float(Time.get_ticks_usec() - wall_start_us) / 1000.0)


# ── Terrain paint scheduler ───────────────────────────────────────────────────

func _enqueue_terrain_paint_chunk(chunk_pos: Vector2i, center: Vector2i, epoch: int) -> void:
	var key: String = _chunk_key.call(chunk_pos)
	if _terrain_painted_chunks.has(key) or _terrain_paint_enqueued.has(key):
		return
	var ring: int = max(abs(chunk_pos.x - center.x), abs(chunk_pos.y - center.y))
	_terrain_paint_queue.append({"chunk": chunk_pos, "ring": ring, "epoch": epoch})
	_terrain_paint_enqueued[key] = true
	if ring == 0:
		terrain_paint_center_ring0_pending += 1


func _process_terrain_paint_scheduler() -> void:
	if not progressive_terrain_paint_enabled:
		return
	if _terrain_paint_queue.is_empty():
		if terrain_paint_center_ring0_pending == 0:
			is_updating = false
		return

	var chunks_budget: int = max(1, terrain_paint_chunks_per_tick)
	var ms_budget: float = maxf(0.0, terrain_paint_ms_budget)
	var start_ms: int = Time.get_ticks_msec()
	var processed: int = 0
	while processed < chunks_budget and not _terrain_paint_queue.is_empty():
		if ms_budget > 0.0 and float(Time.get_ticks_msec() - start_ms) >= ms_budget:
			break
		var job: Dictionary = _terrain_paint_queue.pop_front()
		if int(job.get("epoch", -1)) != terrain_paint_epoch:
			continue
		var cpos: Vector2i = job.get("chunk", Vector2i.ZERO)
		var ring: int = int(job.get("ring", 0))
		var key: String = _chunk_key.call(cpos)
		_terrain_paint_enqueued.erase(key)
		if not loaded_chunks.has(cpos):
			continue
		_apply_chunk_persistent_tiles(cpos)
		_terrain_painted_chunks[key] = true
		processed += 1
		if ring == 0:
			terrain_paint_center_ring0_pending = max(0, terrain_paint_center_ring0_pending - 1)

	if terrain_paint_center_ring0_pending == 0:
		is_updating = false


# ── Prefetch ──────────────────────────────────────────────────────────────────

func _process_prefetch(delta: float) -> void:
	if not prefetch_enabled or player == null:
		return
	_prefetch_timer += delta
	if _prefetch_timer < prefetch_check_interval:
		return
	_prefetch_timer = 0.0

	var player_tile: Vector2i = _world_to_tile.call(player.global_position)
	var player_chunk: Vector2i = _tile_to_chunk.call(player_tile)
	_reprioritize_prefetch_queue(player_chunk)
	var local_in_chunk := Vector2i(posmod(player_tile.x, chunk_size), posmod(player_tile.y, chunk_size))
	if _should_trigger_prefetch(local_in_chunk):
		var center_key: String = _chunk_key.call(player_chunk)
		if _last_prefetch_center_chunk_key != center_key:
			_enqueue_prefetch_ring(player_chunk)
			_last_prefetch_center_chunk_key = center_key

	if _has_critical_generation_in_active_window(player_chunk):
		return

	var budget: int = _runtime_prefetch_budget()
	for _i in range(budget):
		if _prefetch_queue.is_empty():
			break
		var cpos: Vector2i = _prefetch_queue.pop_front()
		var key: String = _chunk_key.call(cpos)
		if generated_chunks.has(cpos) or prefetching_chunks.has(key):
			continue
		prefetching_chunks[key] = true
		call_deferred("_prefetch_chunk", cpos)


func _should_trigger_prefetch(local_in_chunk: Vector2i) -> bool:
	if chunk_size <= 0:
		return false
	var border: int = clamp(prefetch_border_tiles, 0, max(0, chunk_size - 1))
	var max_idx: int = chunk_size - 1
	return (
		local_in_chunk.x <= border
		or local_in_chunk.x >= (max_idx - border)
		or local_in_chunk.y <= border
		or local_in_chunk.y >= (max_idx - border)
	)


func _enqueue_prefetch_ring(center_chunk: Vector2i) -> void:
	var world_max_chunk_x: int = int(floor(float(width - 1) / float(chunk_size)))
	var world_max_chunk_y: int = int(floor(float(height - 1) / float(chunk_size)))
	var ring_radius: int = max(0, prefetch_ring_radius)
	for ring in range(1, ring_radius + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if max(abs(dx), abs(dy)) != ring:
					continue
				var target := Vector2i(center_chunk.x + dx, center_chunk.y + dy)
				if target.x < 0 or target.y < 0 or target.x > world_max_chunk_x or target.y > world_max_chunk_y:
					continue
				var key: String = _chunk_key.call(target)
				if generated_chunks.has(target) or prefetched_chunks.has(key) or prefetching_chunks.has(key):
					continue
				if _prefetch_queue.has(target):
					continue
				_prefetch_queue.append(target)
	_enforce_prefetch_queue_limit(center_chunk)


func _reprioritize_prefetch_queue(center_chunk: Vector2i) -> void:
	if _prefetch_queue.is_empty():
		return
	var player_dir: Vector2 = _get_prefetch_direction()
	var has_player_dir: bool = player_dir.length_squared() > 0.0
	var filtered_queue: Array[Vector2i] = []
	for cpos in _prefetch_queue:
		var ring_distance: int = max(abs(cpos.x - center_chunk.x), abs(cpos.y - center_chunk.y))
		if ring_distance <= (prefetch_ring_radius + active_radius + 1):
			filtered_queue.append(cpos)
	filtered_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _is_prefetch_chunk_higher_priority(a, b, center_chunk, player_dir, has_player_dir)
	)
	_prefetch_queue = filtered_queue
	_enforce_prefetch_queue_limit(center_chunk)


func _enforce_prefetch_queue_limit(center_chunk: Vector2i) -> void:
	if _prefetch_queue.size() <= PREFETCH_QUEUE_MAX:
		return
	var player_dir: Vector2 = _get_prefetch_direction()
	var has_player_dir: bool = player_dir.length_squared() > 0.0
	_prefetch_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _is_prefetch_chunk_higher_priority(a, b, center_chunk, player_dir, has_player_dir)
	)
	_prefetch_queue.resize(PREFETCH_QUEUE_MAX)


func _is_prefetch_chunk_higher_priority(a: Vector2i, b: Vector2i, center_chunk: Vector2i, player_dir: Vector2, has_player_dir: bool) -> bool:
	var ring_a: int = max(abs(a.x - center_chunk.x), abs(a.y - center_chunk.y))
	var ring_b: int = max(abs(b.x - center_chunk.x), abs(b.y - center_chunk.y))
	if has_player_dir:
		var forward_a: float = _chunk_forward_score(a, center_chunk, player_dir)
		var forward_b: float = _chunk_forward_score(b, center_chunk, player_dir)
		if !is_equal_approx(forward_a, forward_b):
			return forward_a > forward_b
	if ring_a != ring_b:
		return ring_a < ring_b
	var dist_a: int = a.distance_squared_to(center_chunk)
	var dist_b: int = b.distance_squared_to(center_chunk)
	if dist_a != dist_b:
		return dist_a < dist_b
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y


func _chunk_forward_score(chunk_pos: Vector2i, center_chunk: Vector2i, player_dir: Vector2) -> float:
	var offset := Vector2(chunk_pos - center_chunk)
	if offset.length_squared() <= 0.0:
		return -1.0
	return player_dir.dot(offset.normalized())


func _get_prefetch_direction() -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	var vel_v = player.get("velocity")
	if typeof(vel_v) == TYPE_VECTOR2:
		var vel: Vector2 = vel_v
		if vel.length_squared() > 16.0:
			return vel.normalized()
	var last_dir_v = player.get("last_direction")
	if typeof(last_dir_v) == TYPE_VECTOR2:
		var last_dir: Vector2 = last_dir_v
		if last_dir.length_squared() > 0.0:
			return last_dir.normalized()
	return Vector2.ZERO


func _runtime_prefetch_budget() -> int:
	var base_budget: int = max(0, prefetch_budget_chunks_per_tick)
	if base_budget == 0:
		return 0
	var floor_budget: int = clamp(prefetch_frame_pressure_budget_floor, 0, base_budget)
	var budget: int = base_budget
	if is_updating:
		budget = max(floor_budget, budget - 1)
	if prefetch_frame_pressure_fps_threshold > 0.0:
		var fps: float = Engine.get_frames_per_second()
		if fps > 0.0 and fps < prefetch_frame_pressure_fps_threshold:
			budget = max(floor_budget, budget - 1)
	return budget


func _has_critical_generation_in_active_window(center_chunk: Vector2i) -> bool:
	for key in generating_chunks.keys():
		var cpos: Vector2i = key
		if _is_chunk_in_active_window(cpos, center_chunk):
			return true
	return false


func _prefetch_chunk(chunk_pos: Vector2i) -> void:
	var key: String = _chunk_key.call(chunk_pos)
	if generated_chunks.has(chunk_pos):
		prefetching_chunks.erase(key)
		prefetched_chunks[key] = true
		return
	if generating_chunks.has(chunk_pos):
		prefetching_chunks.erase(key)
		return
	if _has_critical_generation_in_active_window(current_player_chunk):
		prefetching_chunks.erase(key)
		if not _prefetch_queue.has(chunk_pos):
			_prefetch_queue.push_front(chunk_pos)
		return

	generating_chunks[chunk_pos] = true
	await generate_chunk(chunk_pos, false)
	prefetching_chunks.erase(key)
	prefetched_chunks[key] = true
	if not prefetched_visual_chunks.has(key):
		_prefetch_prepare_chunk_visuals(chunk_pos)
		prefetched_visual_chunks[key] = true
	if prefetch_enqueue_entities:
		entity_coordinator.enqueue_prefetched_jobs(chunk_pos, prefetch_entity_priority_offset)


func _prefetch_prepare_chunk_visuals(chunk_pos: Vector2i) -> void:
	if not prefetch_prepare_ground_enabled and not prefetch_prepare_walls_enabled:
		return
	_apply_chunk_persistent_tiles(chunk_pos, prefetch_prepare_ground_enabled, prefetch_prepare_walls_enabled)


# ── Ground mapping / terrain ctx ──────────────────────────────────────────────

func _chunk_ring_from_center(chunk_pos: Vector2i, center: Vector2i) -> int:
	return max(abs(chunk_pos.x - center.x), abs(chunk_pos.y - center.y))


func _use_corrected_ground_mapping_for_chunk(chunk_pos: Vector2i) -> bool:
	if not corrected_ground_mapping_enabled:
		return false
	if not corrected_ground_mapping_ring0_only:
		return true
	return _chunk_ring_from_center(chunk_pos, current_player_chunk) == 0


func _ground_mapping_profile_for_chunk(chunk_pos: Vector2i) -> Dictionary:
	if _use_corrected_ground_mapping_for_chunk(chunk_pos):
		return {
			"mode": "dirt_grass",
			"ground_source_id": WorldTerrainConfig.DIRT_GRASS_GROUND_SOURCE_ID,
			"ground_fallback_atlas_by_terrain": WorldTerrainConfig.DIRT_GRASS_FALLBACK_ATLAS_BY_TERRAIN,
			"allow_legacy_fallback": false,
		}
	return {
		"mode": "legacy",
		"ground_source_id": WorldTerrainConfig.LEGACY_GROUND_SOURCE_ID,
		"ground_fallback_atlas_by_terrain": WorldTerrainConfig.LEGACY_FALLBACK_ATLAS_BY_TERRAIN,
		"allow_legacy_fallback": legacy_ground_mapping_allow_fallback,
	}


func _make_ground_terrain_ctx() -> Dictionary:
	return {
		"tilemap": ground_tilemap,
		"width": width,
		"height": height,
		"chunk_size": chunk_size,
		"get_terrain": _get_terrain,
		"terrain_set": 0,
		"tree": get_tree(),
	}


# ── Internal helpers ──────────────────────────────────────────────────────────

func _is_chunk_in_active_window(chunk_pos: Vector2i, center: Vector2i) -> bool:
	return abs(chunk_pos.x - center.x) <= active_radius and abs(chunk_pos.y - center.y) <= active_radius
