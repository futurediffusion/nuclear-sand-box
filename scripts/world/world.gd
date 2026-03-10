extends Node2D

@onready var tilemap: TileMap = $WorldTileMap
@onready var walls_tilemap: TileMap = $StructureWallsMap   # <-- paredes van aquí
@onready var prop_spawner := PropSpawner.new()
@onready var chunk_generator := ChunkGenerator.new()
@onready var _collision_builder := CollisionBuilder.new()
var _tile_painter := TilePainter.new()

@export var width: int = 256
@export var height: int = 256
@export var chunk_size: int = 32
@export var active_radius: int = 1
@export var biome_module_size: int = 6
@export var biome_module_bias: float = 0.22
@export var copper_ore_scene: PackedScene
@export var chunk_check_interval: float = 0.3
@export var npc_lite_enabled: bool = true
@export var npc_lite_radius: float = 420.0
@export var npc_lite_hysteresis: float = 60.0
@export var npc_lite_check_interval: float = 0.25
@export var npc_lite_debug: bool = false
@export_group("NPC Data-Only")
@export var npc_data_only_enabled: bool = true
@export var npc_sim_radius: float = 520.0
@export var npc_sim_hysteresis: float = 80.0
@export var npc_sim_check_interval: float = 0.25
@export var npc_despawn_grace_seconds: float = 1.0
@export var npc_debug_counts: bool = false
@export var prefetch_enabled: bool = true
@export var prefetch_border_tiles: int = 6
@export var prefetch_ring_radius: int = 1
@export var prefetch_budget_chunks_per_tick: int = 1
@export var prefetch_check_interval: float = 0.15
@export var prefetch_enqueue_entities: bool = false
@export var prefetch_entity_priority_offset: int = 5
@export var max_cached_chunk_colliders: int = 64
@export var debug_collision_cache: bool = false

var biome_noise := FastNoiseLite.new()

var player: Node2D
var loaded_chunks: Dictionary = {}
var current_player_chunk := Vector2i(-999, -999)

var spawn_tile: Vector2i
var tavern_chunk: Vector2i
var _chunk_timer: float = 0.0
var _npc_lite_timer: float = 0.0
var _npc_sim_timer: float = 0.0
var _pick_rng := RandomNumberGenerator.new()

@export var bandit_camp_scene: PackedScene
@export var bandit_scene: PackedScene
var generated_chunks: Dictionary = {}
var generating_chunks: Dictionary = {}
var entities_spawned_chunks: Dictionary = {}
var chunk_save: Dictionary = {}
var queued_entity_chunks: Dictionary = {}
var _spawn_queue: SpawnBudgetQueue
var prefetched_chunks: Dictionary = {}
var prefetching_chunks: Dictionary = {}
var _prefetch_queue: Array[Vector2i] = []
var _prefetch_timer: float = 0.0
var _last_prefetch_center_chunk_key: String = ""

const PREFETCH_QUEUE_MAX: int = 64

@export var tavern_keeper_scene: PackedScene

const LAYER_GROUND: int = 0
const LAYER_FLOOR: int = 1
const LAYER_WALLS: int = 2        # layer dentro de WorldTileMap (ya no se usa para paredes)
const WALL_TERRAIN_SET: int = 0
const WALL_TERRAIN: int = 0

# StructureWallsMap usa siempre layer 0
const WALLS_MAP_LAYER: int = 0

const SRC_FLOOR: int = 1
const SRC_WALLS: int = 2

const FLOOR_WOOD: Vector2i = Vector2i(0, 0)
const ROOF_VERTICAL: Vector2i = Vector2i(0, 0)
const ROOF_CONT_LEFT: Vector2i = Vector2i(1, 0)
const ROOF_CONT_RIGHT: Vector2i = Vector2i(2, 0)
const ROOF_BOTH: Vector2i = Vector2i(3, 0)
const WALL_SINGLE: Vector2i = Vector2i(0, 1)
const WALL_END_RIGHT: Vector2i = Vector2i(1, 1)
const WALL_END_LEFT: Vector2i = Vector2i(2, 1)
const WALL_MID: Vector2i = Vector2i(3, 1)

const BIOME_TILES = {
	0: [
		{"col_range": [0,2], "rows": [1], "w": 1},
	],
	1: [
		{"col_range": [0,2], "rows": [0], "w": 1},
	],
	2: [
		{"col_range": [0,2], "rows": [2], "w": 1},
	],
}

func _ready() -> void:
	_clear_chunk_wall_runtime_cache()
	add_to_group("world")
	Debug.log("boot", "World._ready begin")
	biome_noise.seed = randi()
	biome_noise.frequency = 0.015
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

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
	_spawn_queue = SpawnBudgetQueue.new()
	_spawn_queue.name = "SpawnBudgetQueue"
	_spawn_queue.spawn_parent = tilemap
	_spawn_queue.chunk_active_checker = Callable(self, "_is_chunk_key_loaded")
	_spawn_queue.job_spawned.connect(_on_spawn_queue_job_spawned)
	_spawn_queue.job_skipped.connect(_on_spawn_queue_job_skipped)
	_spawn_queue.chunk_drained.connect(_on_spawn_queue_chunk_drained)
	add_child(_spawn_queue)
	if GameEvents != null and not GameEvents.entity_died.is_connected(_on_entity_died):
		GameEvents.entity_died.connect(_on_entity_died)
	update_chunks(current_player_chunk)

func _clear_chunk_wall_runtime_cache() -> void:
	for cpos in chunk_wall_body.keys():
		var body: StaticBody2D = chunk_wall_body[cpos]
		if body != null and is_instance_valid(body):
			body.queue_free()
	chunk_wall_body.clear()
	_chunk_wall_last_used.clear()
	_chunk_wall_use_counter = 0

func _process(delta: float) -> void:
	if _spawn_queue != null:
		if player:
			_spawn_queue.set_player_world_pos(player.global_position)
		_spawn_queue.process_queue(delta)
	_process_prefetch(delta)
	_process_npc_lite_mode(delta)
	_process_npc_data_only(delta)
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

func _process_npc_lite_mode(delta: float) -> void:
	if get_tree().paused:
		return
	_npc_lite_timer += delta
	if _npc_lite_timer < maxf(npc_lite_check_interval, 0.05):
		return
	_npc_lite_timer = 0.0
	if not npc_lite_enabled:
		return
	if player == null or not is_instance_valid(player):
		return

	var player_pos := player.global_position
	var enter_radius := npc_lite_radius + npc_lite_hysteresis
	var exit_radius := maxf(npc_lite_radius - npc_lite_hysteresis, 0.0)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.is_queued_for_deletion():
			continue
		if not enemy.has_method("enter_lite_mode") or not enemy.has_method("exit_lite_mode"):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		var dist: float = enemy.global_position.distance_to(player_pos)
		if npc_data_only_enabled and dist > (npc_sim_radius + npc_sim_hysteresis):
			continue
		if dist > enter_radius:
			enemy.enter_lite_mode()
			if npc_lite_debug:
				Debug.log("npc_lite", "enemy=%s -> enter dist=%.2f" % [String(enemy.name), dist])
		elif dist < exit_radius:
			enemy.exit_lite_mode()
			if npc_lite_debug:
				Debug.log("npc_lite", "enemy=%s -> exit dist=%.2f" % [String(enemy.name), dist])

func _process_npc_data_only(delta: float) -> void:
	if get_tree().paused:
		return
	if not npc_data_only_enabled:
		return
	_npc_sim_timer += delta
	if _npc_sim_timer < maxf(npc_sim_check_interval, 0.05):
		return
	_npc_sim_timer = 0.0
	if player == null or not is_instance_valid(player):
		return

	var spawn_radius: float = maxf(npc_sim_radius - npc_sim_hysteresis, 0.0)
	var despawn_radius: float = npc_sim_radius + npc_sim_hysteresis
	var player_pos: Vector2 = player.global_position
	for cpos in loaded_chunks.keys():
		var chunk_pos: Vector2i = cpos
		_ensure_enemy_spawn_records_for_chunk(chunk_pos)
		var chunk_key: String = _chunk_key(chunk_pos)
		for enemy_id in WorldSave.iter_enemy_ids_in_chunk(chunk_key):
			var state_v = WorldSave.get_enemy_state(chunk_key, enemy_id)
			if state_v == null:
				continue
			var state: Dictionary = state_v
			var enemy_pos: Vector2 = Vector2(state.get("pos", Vector2.ZERO))
			var dist: float = enemy_pos.distance_to(player_pos)
			var is_dead: bool = bool(state.get("is_dead", false))
			if dist < spawn_radius and not is_dead and not active_enemies.has(enemy_id) and not spawning_enemy_ids.has(enemy_id):
				_enqueue_enemy_spawn(chunk_pos, enemy_id, state)
			elif dist > despawn_radius and active_enemies.has(enemy_id):
				var node: Node = active_enemies[enemy_id]
				if _can_despawn_enemy(node, state):
					_despawn_enemy(enemy_id)
	if npc_debug_counts:
		Debug.log("npc_data", "active=%d queued=%d" % [active_enemies.size(), spawning_enemy_ids.size()])

func _ensure_enemy_spawn_records_for_chunk(chunk_pos: Vector2i) -> void:
	var chunk_key: String = _chunk_key(chunk_pos)
	if not WorldSave.get_chunk_enemy_spawns(chunk_key).is_empty():
		return
	if not chunk_save.has(chunk_pos):
		return
	var records: Array[Dictionary] = []
	var spawn_index: int = 0
	for camp in chunk_save[chunk_pos].get("camps", []):
		if typeof(camp) != TYPE_DICTIONARY:
			continue
		var camp_tile: Vector2i = camp.get("tile", Vector2i.ZERO)
		var camp_world: Vector2 = _tile_to_world(camp_tile)
		var offsets: Array[Vector2] = [Vector2(-28, -18), Vector2(32, -10), Vector2(-20, 30), Vector2(28, 24)]
		for offset in offsets:
			var enemy_id: String = "e:%s:%03d" % [chunk_key, spawn_index]
			var enemy_pos: Vector2 = camp_world + offset
			var record: Dictionary = {
				"spawn_index": spawn_index,
				"enemy_id": enemy_id,
				"chunk_key": chunk_key,
				"pos": enemy_pos,
				"seed": Seed.chunk_seed(chunk_pos.x, chunk_pos.y) ^ spawn_index,
				"hp": 3,
				"loadout": {"weapon_ids": ["ironpipe", "bow"], "equipped_weapon_id": "ironpipe"},
			}
			records.append(record)
			var default_state: Dictionary = {
				"id": enemy_id,
				"chunk_key": chunk_key,
				"pos": enemy_pos,
				"hp": 3,
				"is_dead": false,
				"seed": int(record["seed"]),
				"weapon_ids": ["ironpipe", "bow"],
				"equipped_weapon_id": "ironpipe",
				"alert": 0.0,
				"last_seen_player_pos": Vector2.ZERO,
				"last_active_time": 0.0,
				"version": 1,
			}
			WorldSave.get_or_create_enemy_state(chunk_key, enemy_id, default_state)
			spawn_index += 1
	WorldSave.ensure_chunk_enemy_spawns(chunk_key, records)

func _enqueue_enemy_spawn(chunk_pos: Vector2i, enemy_id: String, state: Dictionary) -> void:
	if _spawn_queue == null:
		return
	var chunk_key: String = _chunk_key(chunk_pos)
	spawning_enemy_ids[enemy_id] = true
	var init_data: Dictionary = {
		"properties": {
			"entity_uid": enemy_id,
			"enemy_chunk_key": chunk_key,
		},
		"save_state": state,
	}
	var ring: int = max(abs(chunk_pos.x - current_player_chunk.x), abs(chunk_pos.y - current_player_chunk.y))
	_spawn_queue.enqueue({
		"chunk_key": chunk_key,
		"kind": "enemy",
		"scene": bandit_scene,
		"global_position": Vector2(state.get("pos", Vector2.ZERO)),
		"init_data": init_data,
		"priority": ring,
		"uid": enemy_id,
	})

func _can_despawn_enemy(node: Node, state: Dictionary) -> bool:
	if node == null or not is_instance_valid(node):
		return true
	if node.has_method("is_attacking") and bool(node.call("is_attacking")):
		return false
	var now: float = Time.get_unix_time_from_system()
	var last_active_time: float = float(state.get("last_active_time", 0.0))
	if node.has_method("capture_save_state"):
		var runtime_state: Dictionary = node.call("capture_save_state")
		last_active_time = maxf(last_active_time, float(runtime_state.get("last_active_time", 0.0)))
	if now - last_active_time < maxf(npc_despawn_grace_seconds, 0.0):
		return false
	return true

func _despawn_enemy(enemy_id: String) -> void:
	if not active_enemies.has(enemy_id):
		return
	var node: Node = active_enemies[enemy_id]
	var chunk_key: String = String(active_enemy_chunk.get(enemy_id, ""))
	if node != null and is_instance_valid(node):
		if node.has_method("capture_save_state"):
			var state: Dictionary = node.call("capture_save_state")
			WorldSave.set_enemy_state(chunk_key, enemy_id, state)
		if node.has_node("AIComponent"):
			var ai := node.get_node_or_null("AIComponent")
			if ai != null and ai.has_method("on_owner_exit_tree"):
				ai.call("on_owner_exit_tree")
		if node.has_node("AIWeaponController"):
			var ctrl := node.get_node_or_null("AIWeaponController")
			if ctrl != null and ctrl.has_method("clear_transient_input"):
				ctrl.call("clear_transient_input")
		EnemyRegistry.unregister_enemy(node)
		node.queue_free()
	active_enemies.erase(enemy_id)
	active_enemy_chunk.erase(enemy_id)
	spawning_enemy_ids.erase(enemy_id)


func world_to_chunk(pos: Vector2) -> Vector2i:
	return _tile_to_chunk(_world_to_tile(pos))

func _is_chunk_in_active_window(chunk_pos: Vector2i, center: Vector2i) -> bool:
	return abs(chunk_pos.x - center.x) <= active_radius and abs(chunk_pos.y - center.y) <= active_radius

func update_chunks(center: Vector2i) -> void:
	Debug.log("boot", "ChunkManager load begin center=%s" % center)
	Debug.log("chunk", "CENTER moved -> (%d,%d)" % [center.x, center.y])
	if player:
		_debug_check_tile_alignment(player.global_position)
		_debug_check_player_chunk(player.global_position)

	var needed: Dictionary = {}
	var max_chunk_x: int = int(floor(float(width - 1) / float(chunk_size)))
	var max_chunk_y: int = int(floor(float(height - 1) / float(chunk_size)))

	for cy in range(center.y - active_radius, center.y + active_radius + 1):
		for cx in range(center.x - active_radius, center.x + active_radius + 1):
			if cx < 0 or cx > max_chunk_x or cy < 0 or cy > max_chunk_y:
				continue
			var cpos := Vector2i(cx, cy)
			needed[cpos] = true
			if not generated_chunks.has(cpos) and not generating_chunks.has(cpos):
				generating_chunks[cpos] = true
				generate_chunk(cpos, true)
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

func generate_chunk(chunk_pos: Vector2i, spawn_entities: bool = true) -> void:
	Debug.log("chunk", "GENERATE chunk=(%d,%d) run_seed=%d chunk_seed=%d" % [chunk_pos.x, chunk_pos.y, Seed.run_seed, Seed.chunk_seed(chunk_pos.x, chunk_pos.y)])
	prop_spawner.generate_chunk_spawns(chunk_pos, _make_spawn_ctx())
	await chunk_generator.apply_ground(chunk_pos, _make_ground_ctx())
	generated_chunks[chunk_pos] = true
	generating_chunks.erase(chunk_pos)
	if spawn_entities and _is_chunk_in_active_window(chunk_pos, current_player_chunk):
		if not loaded_chunks.has(chunk_pos):
			load_chunk_entities(chunk_pos)
			loaded_chunks[chunk_pos] = true

func _process_prefetch(delta: float) -> void:
	if not prefetch_enabled or player == null:
		return
	_prefetch_timer += delta
	if _prefetch_timer < prefetch_check_interval:
		return
	_prefetch_timer = 0.0

	var player_tile: Vector2i = _world_to_tile(player.global_position)
	var player_chunk: Vector2i = _tile_to_chunk(player_tile)
	_reprioritize_prefetch_queue(player_chunk)
	var local_in_chunk := Vector2i(posmod(player_tile.x, chunk_size), posmod(player_tile.y, chunk_size))
	if _should_trigger_prefetch(local_in_chunk):
		var center_key: String = _chunk_key(player_chunk)
		if _last_prefetch_center_chunk_key != center_key:
			_enqueue_prefetch_ring(player_chunk)
			_last_prefetch_center_chunk_key = center_key

	if _has_critical_generation_in_active_window(player_chunk):
		return

	var budget: int = max(0, prefetch_budget_chunks_per_tick)
	for _i in range(budget):
		if _prefetch_queue.is_empty():
			break
		var cpos: Vector2i = _prefetch_queue.pop_front()
		var key: String = _chunk_key(cpos)
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
				var key: String = _chunk_key(target)
				if generated_chunks.has(target) or prefetched_chunks.has(key) or prefetching_chunks.has(key):
					continue
				if _prefetch_queue.has(target):
					continue
				_prefetch_queue.append(target)
	_enforce_prefetch_queue_limit(center_chunk)

func _reprioritize_prefetch_queue(center_chunk: Vector2i) -> void:
	if _prefetch_queue.is_empty():
		return
	var filtered_queue: Array[Vector2i] = []
	for cpos in _prefetch_queue:
		var ring_distance: int = max(abs(cpos.x - center_chunk.x), abs(cpos.y - center_chunk.y))
		if ring_distance <= (prefetch_ring_radius + active_radius + 1):
			filtered_queue.append(cpos)
	_prefetch_queue = filtered_queue
	_enforce_prefetch_queue_limit(center_chunk)

func _enforce_prefetch_queue_limit(center_chunk: Vector2i) -> void:
	if _prefetch_queue.size() <= PREFETCH_QUEUE_MAX:
		return
	_prefetch_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = max(abs(a.x - center_chunk.x), abs(a.y - center_chunk.y))
		var db: int = max(abs(b.x - center_chunk.x), abs(b.y - center_chunk.y))
		if da == db:
			return a.distance_squared_to(center_chunk) < b.distance_squared_to(center_chunk)
		return da < db
	)
	_prefetch_queue.resize(PREFETCH_QUEUE_MAX)

func _has_critical_generation_in_active_window(center_chunk: Vector2i) -> bool:
	for key in generating_chunks.keys():
		var cpos: Vector2i = key
		if _is_chunk_in_active_window(cpos, center_chunk):
			return true
	return false

func _prefetch_chunk(chunk_pos: Vector2i) -> void:
	var key: String = _chunk_key(chunk_pos)
	if generated_chunks.has(chunk_pos):
		prefetching_chunks.erase(key)
		prefetched_chunks[key] = true
		return
	if generating_chunks.has(chunk_pos):
		prefetching_chunks.erase(key)
		return

	generating_chunks[chunk_pos] = true
	await generate_chunk(chunk_pos, false)
	prefetching_chunks.erase(key)
	prefetched_chunks[key] = true
	if prefetch_enqueue_entities:
		_enqueue_prefetched_entity_jobs(chunk_pos)

func _enqueue_prefetched_entity_jobs(chunk_pos: Vector2i) -> void:
	if _spawn_queue == null:
		return
	if not chunk_save.has(chunk_pos):
		return
	var jobs: Array[Dictionary] = []
	var chunk_key: String = _chunk_key(chunk_pos)
	var chunk_ring: int = max(abs(chunk_pos.x - current_player_chunk.x), abs(chunk_pos.y - current_player_chunk.y))
	var priority: int = chunk_ring + prefetch_entity_priority_offset
	for d in chunk_save[chunk_pos].get("ores", []):
		var tpos: Vector2i = d["tile"]
		jobs.append({
			"chunk_key": chunk_key,
			"kind": "ore",
			"scene": copper_ore_scene,
			"tile": tpos,
			"global_position": _tile_to_world(tpos),
			"priority": priority,
			"uid": UID.make_uid("ore_copper", "", tpos),
		})
	for p in chunk_save[chunk_pos].get("placements", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var kind: String = String(p.get("kind", ""))
		if kind != "prop":
			continue
		var prop_id: String = String(p.get("prop_id", ""))
		var path: String = PropDB.scene_path(prop_id)
		if path == "":
			continue
		var ps: PackedScene = load(path) as PackedScene
		if ps == null:
			continue
		var ccell: Array = p.get("cell", [0, 0])
		var cell: Vector2i = Vector2i(int(ccell[0]), int(ccell[1]))
		jobs.append({
			"chunk_key": chunk_key,
			"kind": "prop",
			"scene": ps,
			"tile": cell,
			"global_position": _tile_to_world(cell),
			"priority": priority,
			"uid": UID.make_uid("prop_%s" % prop_id, "", cell),
		})
	if not jobs.is_empty():
		_spawn_queue.enqueue_many(jobs)

func unload_chunk(chunk_pos: Vector2i) -> void:
	# Borrar suelo del WorldTileMap
	_tile_painter.erase_chunk_region(tilemap, chunk_pos, chunk_size, [LAYER_GROUND, LAYER_FLOOR])
	# Borrar paredes del StructureWallsMap
	_tile_painter.erase_chunk_region(walls_tilemap, chunk_pos, chunk_size, [WALLS_MAP_LAYER])

func get_biome(x: int, y: int) -> int:
	var noise_v := (biome_noise.get_noise_2d(x, y) + 1.0) * 0.5
	var module_v := _module_pattern_value(x, y)
	var v := clampf(noise_v + (module_v * biome_module_bias), 0.0, 1.0)
	if v < 0.46:
		return 0
	elif v > 0.72:
		return 2
	return 1

func _module_pattern_value(x: int, y: int) -> float:
	var module_size: int = max(1, biome_module_size)
	var module_x: int = int(floor(float(x) / float(module_size)))
	var module_y: int = int(floor(float(y) / float(module_size)))
	var module_pos := Vector2i(module_x, module_y)

	var gate_roll := abs(hash(module_pos)) % 100
	var path_roll := abs(hash(module_pos + Vector2i(31, 17))) % 100
	if gate_roll < 18:
		return -1.0
	if path_roll < 28:
		return -0.65

	var block_roll := abs(hash(module_pos + Vector2i(97, -53))) % 100
	if block_roll < 36:
		return 0.20
	if block_roll > 84:
		return 0.75
	return -0.15

func pick_tile(x: int, y: int) -> Vector2i:
	var biome := get_biome(x, y)
	var tiles: Array = BIOME_TILES[biome]
	var total_weight: int = 0
	for t in tiles: total_weight += int(t["w"])
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

var chunk_entities: Dictionary = {}
var active_enemies: Dictionary = {}  # enemy_id -> EnemyAI node
var active_enemy_chunk: Dictionary = {}  # enemy_id -> chunk_key
var spawning_enemy_ids: Dictionary = {}  # enemy_id -> true while queued
var chunk_saveables: Dictionary = {}
var chunk_occupied_tiles: Dictionary = {}
var chunk_wall_body: Dictionary = {}
var _chunk_wall_last_used: Dictionary = {}
var _chunk_wall_use_counter: int = 0

const DEBUG_SPAWN: bool = true
const DEBUG_SAVE: bool = true

func _debug_spawn_report(chunk_key: Vector2i, player_tile: Vector2i, chosen_tile: Vector2i, reason: String) -> void:
	if not DEBUG_SPAWN: return
	Debug.log("spawn", "chunk=%s player_tile=%s chosen=%s -> %s" % [str(chunk_key), str(player_tile), str(chosen_tile), reason])

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
		"biome_seed": biome_noise.seed,
		"get_biome": Callable(self, "get_biome"),
		"chunk_save": chunk_save,
		"chunk_occupied_tiles": chunk_occupied_tiles,
		"entities_spawned_chunks": entities_spawned_chunks,
		"player_tile": player_tile,
		"player_chunk": current_player_chunk,
		"copper_ore_scene": copper_ore_scene,
		"bandit_camp_scene": bandit_camp_scene,
		"bandit_scene": bandit_scene,
	}

func _make_ground_ctx() -> Dictionary:
	return {
		"tilemap": tilemap,
		"width": width,
		"height": height,
		"chunk_size": chunk_size,
		"pick_tile": Callable(self, "pick_tile"),
		"tree": get_tree(),
		"generating_yield_stride": 8,
	}

func load_chunk_entities(chunk_pos: Vector2i) -> void:
	chunk_entities[chunk_pos] = []
	chunk_saveables[chunk_pos] = []
	if queued_entity_chunks.has(chunk_pos):
		return
	queued_entity_chunks[chunk_pos] = true
	prop_spawner.rebuild_chunk_occupied_tiles(chunk_pos, _make_spawn_ctx())

	if not chunk_save.has(chunk_pos):
		queued_entity_chunks.erase(chunk_pos)
		entities_spawned_chunks[chunk_pos] = true
		return

	var placements_count: int = chunk_save[chunk_pos].get("placements", []).size()
	var ores_count: int = chunk_save[chunk_pos]["ores"].size()
	var camps_count: int = chunk_save[chunk_pos]["camps"].size()
	Debug.log("chunk", "LOAD_ENTITIES chunk=(%d,%d) placements=%d ores=%d camps=%d" % [chunk_pos.x, chunk_pos.y, placements_count, ores_count, camps_count])

	var cx: int = chunk_pos.x
	var cy: int = chunk_pos.y
	WorldSave.get_chunk_save(cx, cy)

	var chunk_key: String = _chunk_key(chunk_pos)
	var chunk_ring: int = max(abs(chunk_pos.x - current_player_chunk.x), abs(chunk_pos.y - current_player_chunk.y))
	var jobs: Array[Dictionary] = []

	# 1) ORES
	for d in chunk_save[chunk_pos]["ores"]:
		var tpos: Vector2i = d["tile"]
		var ore_uid: String = UID.make_uid("ore_copper", "", tpos)
		var ore_state = WorldSave.get_entity_state(cx, cy, ore_uid)
		var ore_init: Dictionary = {
			"properties": {"entity_uid": ore_uid},
			"worldsave": {
				"cx": cx,
				"cy": cy,
				"uid": ore_uid,
				"init_if_missing": ore_state == null,
			}
		}
		if ore_state != null:
			ore_init["save_state"] = ore_state
		elif d.has("remaining") and d["remaining"] != -1:
			ore_init["save_state"] = {"remaining": int(d["remaining"])}
		jobs.append({
			"chunk_key": chunk_key,
			"kind": "ore",
			"scene": copper_ore_scene,
			"tile": tpos,
			"global_position": _tile_to_world(tpos),
			"init_data": ore_init,
			"priority": chunk_ring,
			"uid": ore_uid,
		})

	# 2) TILES PERSISTENTES — suelo en WorldTileMap, paredes en StructureWallsMap
	var floor_cells: Array[Vector2i] = []
	var wall_terrain_cells: Array[Vector2i] = []
	var manual_tiles: Array[Dictionary] = []

	for t in chunk_save[chunk_pos]["placed_tiles"]:
		var source_id: int = int(t.get("source", 0))
		if source_id == -1:
			# Paredes via terrain connect → van a StructureWallsMap layer 0
			wall_terrain_cells.append(t["tile"])
		elif int(t.get("layer", -1)) == LAYER_FLOOR and source_id == SRC_FLOOR and t.get("atlas", Vector2i(-1, -1)) == FLOOR_WOOD:
			floor_cells.append(t["tile"])
		else:
			manual_tiles.append(t)

	if floor_cells.size() > 0:
		_tile_painter.apply_floor(tilemap, LAYER_FLOOR, SRC_FLOOR, FLOOR_WOOD, floor_cells)

	if manual_tiles.size() > 0:
		_tile_painter.apply_manual_tiles(tilemap, manual_tiles)

	if wall_terrain_cells.size() > 0:
		Debug.log("chunk", "WALL_TERRAIN_PAINT chunk=(%d,%d) cells=%d -> StructureWallsMap" % [chunk_pos.x, chunk_pos.y, wall_terrain_cells.size()])
		# *** CLAVE: pintar paredes en StructureWallsMap (layer 0), no en WorldTileMap ***
		_tile_painter.apply_walls_terrain_connect(walls_tilemap, WALLS_MAP_LAYER, WALL_TERRAIN_SET, WALL_TERRAIN, wall_terrain_cells)

	# Colisiones de paredes con hash/dirty-cache por chunk.
	_ensure_chunk_wall_collision(chunk_pos)

	# 3) CAMPS (solo prop visual; enemies pasan a data-only records)
	for c in chunk_save[chunk_pos]["camps"]:
		var ct: Vector2i = c["tile"]
		jobs.append({
			"chunk_key": chunk_key,
			"kind": "camp",
			"scene": bandit_camp_scene,
			"tile": ct,
			"global_position": _tile_to_world(ct),
			"init_data": {
				"properties": {"bandit_scene": bandit_scene, "max_bandits_alive": 0},
			},
			"priority": chunk_ring,
			"uid": UID.make_uid("camp_bandit", "", ct),
		})
	_ensure_enemy_spawn_records_for_chunk(chunk_pos)

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
				if path == "": continue
				var ps: PackedScene = load(path) as PackedScene
				if ps == null: continue
				var ccell: Array = d.get("cell", [0, 0])
				var cell: Vector2i = Vector2i(int(ccell[0]), int(ccell[1]))
				jobs.append({
					"chunk_key": chunk_key,
					"kind": "prop",
					"scene": ps,
					"tile": cell,
					"global_position": _tile_to_world(cell),
					"init_data": {
						"properties": {"z_index": tilemap.z_index + 5},
					},
					"priority": chunk_ring,
					"uid": UID.make_uid("prop_%s" % prop_id, "", cell),
				})
				spawned_count += 1

			elif kind == "npc_keeper":
				if tavern_keeper_scene == null: continue
				var site_id: String = String(d.get("site_id", ""))
				var keeper_uid: String = UID.make_uid("npc_keeper", site_id)
				if spawned_keeper_uids.has(keeper_uid): continue
				spawned_keeper_uids[keeper_uid] = true
				var keeper_state = WorldSave.get_entity_state(cx, cy, keeper_uid)
				if keeper_state == null:
					WorldSave.set_entity_state(cx, cy, keeper_uid, {"spawned": true})
				var ccell: Array = d.get("cell", [0, 0])
				var counter_cell: Vector2i = Vector2i(int(ccell[0]), int(ccell[1]))
				var imin: Array = d.get("inner_min", [0, 0])
				var imax: Array = d.get("inner_max", [0, 0])
				jobs.append({
					"chunk_key": chunk_key,
					"kind": "npc_keeper",
					"scene": tavern_keeper_scene,
					"tile": counter_cell,
					"global_position": _tile_to_world(counter_cell),
					"init_data": {
						"properties": {
							"entity_uid": keeper_uid,
							"_tilemap": tilemap,
							"tavern_inner_min": Vector2i(int(imin[0]), int(imin[1])),
							"tavern_inner_max": Vector2i(int(imax[0]), int(imax[1])),
							"counter_tile": counter_cell,
						},
						"save_state": keeper_state,
					},
					"priority": chunk_ring,
					"uid": keeper_uid,
				})
				spawned_npc_count += 1
				spawned_count += 1

	if _spawn_queue != null and not jobs.is_empty():
		_spawn_queue.enqueue_many(jobs)
	else:
		queued_entity_chunks.erase(chunk_pos)
		entities_spawned_chunks[chunk_pos] = true

	Debug.log("chunk", "SPAWNED chunk=(%d,%d) props=%d npcs=%d ores=%d camps=%d" % [chunk_pos.x, chunk_pos.y, spawned_count - spawned_npc_count, spawned_npc_count, ores_count, camps_count])

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
	var chunk_key: String = _chunk_key(chunk_pos)
	if _spawn_queue != null:
		_spawn_queue.cancel_chunk(chunk_key)
	for enemy_id in active_enemy_chunk.keys():
		if String(active_enemy_chunk[enemy_id]) == chunk_key:
			_despawn_enemy(String(enemy_id))
	for enemy_id in spawning_enemy_ids.keys():
		if String(enemy_id).begins_with("e:%s:" % chunk_key):
			spawning_enemy_ids.erase(enemy_id)
	queued_entity_chunks.erase(chunk_pos)
	prefetching_chunks.erase(chunk_key)

	if chunk_wall_body.has(chunk_pos):
		var body: StaticBody2D = chunk_wall_body[chunk_pos]
		if is_instance_valid(body):
			_collision_builder.set_chunk_collider_enabled(body, false)
			_touch_chunk_wall_usage(chunk_pos)
	_enforce_chunk_collider_cache_limit()

	if not chunk_entities.has(chunk_pos):
		return

	var cx: int = chunk_pos.x
	var cy: int = chunk_pos.y
	if chunk_saveables.has(chunk_pos):
		for entity in chunk_saveables[chunk_pos]:
			if not is_instance_valid(entity): continue
			if not entity.has_method("get_save_state"): continue
			var uid_value = entity.get("entity_uid")
			if uid_value == null: continue
			var uid: String = String(uid_value)
			if uid == "": continue
			WorldSave.set_entity_state(cx, cy, uid, entity.get_save_state())

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
		if not is_instance_valid(e):
			continue
		if e.has_method("enter_lite_mode"):
			e.enter_lite_mode()
		if e.has_node("AIComponent"):
			var ai: Node = e.get_node_or_null("AIComponent")
			if ai != null and ai.has_method("on_owner_exit_tree"):
				ai.on_owner_exit_tree()
		e.queue_free()
	chunk_entities.erase(chunk_pos)
	chunk_saveables.erase(chunk_pos)

func _chunk_key(chunk_pos: Vector2i) -> String:
	return "%d,%d" % [chunk_pos.x, chunk_pos.y]

func _chunk_from_key(chunk_key: String) -> Vector2i:
	var parts: PackedStringArray = chunk_key.split(",")
	if parts.size() != 2:
		return Vector2i(-99999, -99999)
	return Vector2i(int(parts[0]), int(parts[1]))

func _is_chunk_key_loaded(chunk_key: String) -> bool:
	var cpos: Vector2i = _chunk_from_key(chunk_key)
	return loaded_chunks.has(cpos)

func _on_spawn_queue_job_spawned(job: Dictionary, node: Node) -> void:
	var chunk_pos: Vector2i = _chunk_from_key(String(job.get("chunk_key", "")))
	if chunk_pos.x == -99999:
		return
	if not chunk_entities.has(chunk_pos):
		chunk_entities[chunk_pos] = []
	if not chunk_saveables.has(chunk_pos):
		chunk_saveables[chunk_pos] = []

	chunk_entities[chunk_pos].append(node)
	var kind: String = String(job.get("kind", ""))
	if kind == "ore" or kind == "npc_keeper":
		chunk_saveables[chunk_pos].append(node)
	elif kind == "enemy":
		var enemy_id: String = String(job.get("uid", ""))
		spawning_enemy_ids.erase(enemy_id)
		active_enemies[enemy_id] = node
		active_enemy_chunk[enemy_id] = String(job.get("chunk_key", ""))
		if node.has_method("exit_lite_mode"):
			node.call("exit_lite_mode")
		EnemyRegistry.register_enemy(node)

	if kind == "ore":
		var init_data: Dictionary = job.get("init_data", {})
		var ws: Dictionary = init_data.get("worldsave", {})
		if bool(ws.get("init_if_missing", false)) and node.has_method("get_save_state"):
			WorldSave.set_entity_state(int(ws.get("cx", chunk_pos.x)), int(ws.get("cy", chunk_pos.y)), String(ws.get("uid", "")), node.call("get_save_state"))

func _on_spawn_queue_job_skipped(job: Dictionary, reason: String) -> void:
	var kind: String = String(job.get("kind", ""))
	if kind == "enemy":
		spawning_enemy_ids.erase(String(job.get("uid", "")))
	if reason != "chunk_inactive":
		return
	var chunk_pos: Vector2i = _chunk_from_key(String(job.get("chunk_key", "")))
	if chunk_pos.x == -99999:
		return
	# Si el job se saltó por inactividad, nunca dejamos el chunk "ocupado".
	# Esto evita que un skip transitorio deje bloqueado el re-encolado de entidades.
	queued_entity_chunks.erase(chunk_pos)
	if loaded_chunks.has(chunk_pos):
		call_deferred("load_chunk_entities", chunk_pos)

func _on_spawn_queue_chunk_drained(chunk_key: String) -> void:
	var chunk_pos: Vector2i = _chunk_from_key(chunk_key)
	if chunk_pos.x == -99999:
		return
	queued_entity_chunks.erase(chunk_pos)
	entities_spawned_chunks[chunk_pos] = true

func mark_chunk_walls_dirty(cx: int, cy: int) -> void:
	WorldSave.set_chunk_flag(cx, cy, "walls_dirty", true)

func _ensure_chunk_wall_collision(chunk_pos: Vector2i) -> void:
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
		return

	var cached_body: StaticBody2D = chunk_wall_body[chunk_pos]
	_collision_builder.set_chunk_collider_enabled(cached_body, true)
	_touch_chunk_wall_usage(chunk_pos)
	if debug_collision_cache:
		Debug.log("chunk", "REUSE walls collider chunk=%s hash=%d" % [chunk_key, current_hash])

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
	if active_enemy_chunk.has(uid):
		WorldSave.mark_enemy_dead(String(active_enemy_chunk[uid]), uid)
		active_enemies.erase(uid)
		active_enemy_chunk.erase(uid)
	spawning_enemy_ids.erase(uid)
