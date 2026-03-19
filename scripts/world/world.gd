extends Node2D

signal chunk_stage_completed(chunk_pos: Vector2i, stage: String)

@onready var tilemap: TileMap = $WorldTileMap
@onready var walls_tilemap: TileMap = $StructureWallsMap   # <-- paredes van aquí
@onready var ground_tilemap: TileMap = $GroundTileMap
@onready var cliffs_tilemap: TileMap = $TileMap_Cliffs
@onready var _vegetation_root: VegetationRoot = $VegetationRoot
@onready var prop_spawner := PropSpawner.new()
@onready var chunk_generator := ChunkGenerator.new()
@onready var _collision_builder := CollisionBuilder.new()
var _tile_painter := TilePainter.new()

@export var width: int = 64
@export var height: int = 64
@export var chunk_size: int = 32
@export var active_radius: int = 1
@export var chunk_check_interval: float = 0.3
@export var copper_ore_scene: PackedScene
@export var stone_ore_scene: PackedScene
@export var tree_scene: PackedScene
@export var grass_tuft_scene: PackedScene
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
@export var autosave_interval: float = 120.0

@export_group("Player Walls")
@export var player_wallwood_max_hp: int = 3
@export var player_wall_drop_enabled: bool = true
@export var player_wall_drop_item_id: String = "wallwood"
@export var player_wall_drop_amount: int = 1
@export var structural_wall_drop_enabled: bool = true
@export var structural_wall_drop_item_id: String = "wallwood"
@export var structural_wall_drop_amount: int = 1
@export var player_wall_hit_shake_duration: float = 0.08
@export var player_wall_hit_shake_px: float = 5.0
@export var player_wall_hit_shake_speed: float = 40.0
@export var player_wall_hit_flash_time: float = 0.06
@export var structural_wall_hit_shake_duration: float = 0.12
@export var structural_wall_hit_shake_px: float = 7.0
@export var structural_wall_hit_shake_speed: float = 46.0
@export var structural_wall_default_hp: int = 3
@export_group("")

@export_group("Spawn Density")
@export var copper_grass_min: int = 0
@export var copper_grass_max: int = 1
@export var copper_dirt_min: int = 2
@export var copper_dirt_max: int = 5
@export var stone_grass_min: int = 0
@export var stone_grass_max: int = 2
@export var stone_dirt_min: int = 4
@export var stone_dirt_max: int = 10
@export var tree_grass_min: int = 5
@export var tree_grass_max: int = 10
@export var tree_dirt_min: int = 1
@export var tree_dirt_max: int = 3
@export var grass_tuft_grass_min: int = 10
@export var grass_tuft_grass_max: int = 20
@export var grass_tuft_dirt_min: int = 2
@export var grass_tuft_dirt_max: int = 6
@export_group("")

@export_group("Cliff Generation")
@export var cliff_border_width: int = 4
@export var cliff_blob_count: int = 18
@export var cliff_radius_min: int = 4
@export var cliff_radius_max: int = 10
@export var cliff_warp_strength: float = 3.5
@export var cliff_clear_radius: int = 4
@export var cliff_spawn_safe_radius: int = 6
@export var cliff_collision_band: float = 0.3
@export_group("")

var _autosave_timer: float = 0.0
var _biome_seed: int = 0
var cliff_generator: CliffGenerator
var _cliff_seed: int = 0
var _cliff_screen_size: Vector2 = Vector2(1920, 1080)
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
var _entity_root: Node2D

var chunk_save: Dictionary = {}
var _spawn_queue: SpawnBudgetQueue
var _perf_monitor := ChunkPerfMonitor.new()
var _pending_tile_erases: Array[Vector2i] = []
var _settlement_intel: SettlementIntel
var _player_wall_system: PlayerWallSystem
var _wall_feedback: WallFeedback
var _wall_persistence: WallPersistence
var _structural_wall_persistence: StructuralWallPersistence
var _chunk_wall_collider_cache: ChunkWallColliderCache
var _wall_refresh_queue: WallRefreshQueue

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
const WALK_SURFACE_GRASS: StringName = &"grass"
const WALK_SURFACE_DIRT: StringName = &"dirt"
const WALK_SURFACE_WOOD: StringName = &"wood"
const FLOORWOOD_RUNTIME_ITEM_ID: String = "floorwood"
const FLOORWOOD_LEGACY_ITEM_ID: String = "woodfloor"
const FLOOR_SURFACE_BY_ATLAS := {
	FLOOR_WOOD: WALK_SURFACE_WOOD,
}
const DOORWOOD_ITEM_ID: String = BuildableCatalog.ID_DOORWOOD
const PLAYER_WALL_FALLBACK_ATLAS: Vector2i = Vector2i(0, 0)
const PLAYER_WALL_ISOLATED_ATLAS: Vector2i = Vector2i(0, 1)
const PLAYER_WALL_FALLBACK_ALT: int = 2
const PLAYER_WALL_HIT_TINT: Color = Color(0.86, 0.76, 0.6, 1.0)
const SettlementIntelScript := preload("res://scripts/world/SettlementIntel.gd")
const PlayerWallSystemScript := preload("res://scripts/world/PlayerWallSystem.gd")
const WallPersistenceScript := preload("res://scripts/world/WallPersistence.gd")
const StructuralWallPersistenceScript := preload("res://scripts/world/StructuralWallPersistence.gd")
const WallFeedbackScript := preload("res://scripts/world/WallFeedback.gd")
const ChunkWallColliderCacheScript := preload("res://scripts/world/ChunkWallColliderCache.gd")
const WallRefreshQueueScript := preload("res://scripts/world/WallRefreshQueue.gd")
const WALL_RECONNECT_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1),
]

# Biome IDs used by PropSpawner via get_spawn_biome()
const BIOME_ID_GRASSLAND: int = 1
const BIOME_ID_DENSE_GRASS: int = 2

func _ready() -> void:
	_wall_refresh_queue = WallRefreshQueueScript.new()
	_chunk_wall_collider_cache = ChunkWallColliderCacheScript.new()
	_chunk_wall_collider_cache.setup({
		"walls_tilemap": walls_tilemap,
		"collision_builder": _collision_builder,
		"chunk_size": chunk_size,
		"walls_map_layer": WALLS_MAP_LAYER,
		"src_walls": SRC_WALLS,
		"max_cached_chunk_colliders": max_cached_chunk_colliders,
		"debug_collision_cache": debug_collision_cache,
		"loaded_chunks": loaded_chunks,
		"current_player_chunk_getter": Callable(self, "_get_current_player_chunk"),
		"chunk_key": Callable(self, "_chunk_key"),
		"is_chunk_in_active_window": Callable(self, "_is_chunk_in_active_window"),
		"record_stage_time": Callable(self, "_record_chunk_stage_time"),
		"chunk_perf_stage_collider_build": CHUNK_PERF_STAGE_COLLIDER_BUILD,
		"extra_wall_support_lookup_provider": Callable(self, "_get_extra_wall_support_lookup_for_chunk"),
	})
	_chunk_wall_collider_cache.clear_all()
	add_to_group("world")
	get_tree().set_auto_accept_quit(false)
	_player_wall_system = PlayerWallSystemScript.new()
	_wall_persistence = WallPersistenceScript.new()
	_structural_wall_persistence = StructuralWallPersistenceScript.new()
	_structural_wall_persistence.setup({
		"chunk_save": chunk_save,
		"walls_map_layer": WALLS_MAP_LAYER,
		"structural_wall_source": -1,
		"structural_wall_default_hp": structural_wall_default_hp,
	})
	_wall_feedback = WallFeedbackScript.new()
	_wall_feedback.setup({
		"owner": self,
		"walls_tilemap": walls_tilemap,
		"walls_map_layer": WALLS_MAP_LAYER,
		"src_walls": SRC_WALLS,
		"tile_to_world": Callable(self, "_tile_to_world"),
		"player_wall_hit_shake_duration": player_wall_hit_shake_duration,
		"player_wall_hit_shake_px": player_wall_hit_shake_px,
		"player_wall_hit_shake_speed": player_wall_hit_shake_speed,
		"player_wall_hit_flash_time": player_wall_hit_flash_time,
		"structural_wall_hit_shake_duration": structural_wall_hit_shake_duration,
		"structural_wall_hit_shake_px": structural_wall_hit_shake_px,
		"structural_wall_hit_shake_speed": structural_wall_hit_shake_speed,
		"player_wall_hit_tint": PLAYER_WALL_HIT_TINT,
		"player_wall_fallback_atlas": PLAYER_WALL_FALLBACK_ATLAS,
		"player_wall_fallback_alt": PLAYER_WALL_FALLBACK_ALT,
	})
	# Nota de migración: world.gd no define audio de walls; PlayerWallSystem resuelve defaults/overrides internos.
	_player_wall_system.setup({
		"owner": self,
		"feedback": _wall_feedback,
		"sound_panel_getter": Callable(self, "_get_sound_panel_for_walls"),
		"wall_persistence": _wall_persistence,
		"structural_wall_persistence": _structural_wall_persistence,
		"walls_tilemap": walls_tilemap,
		"cliffs_tilemap": cliffs_tilemap,
		"chunk_save": chunk_save,
		"loaded_chunks": loaded_chunks,
		"width": width,
		"height": height,
		"chunk_size": chunk_size,
		"walls_map_layer": WALLS_MAP_LAYER,
		"wall_terrain_set": WALL_TERRAIN_SET,
		"wall_terrain": WALL_TERRAIN,
		"src_walls": SRC_WALLS,
		"world_to_tile": Callable(self, "_world_to_tile"),
		"tile_to_world": Callable(self, "_tile_to_world"),
		"tile_to_chunk": Callable(self, "_tile_to_chunk"),
		"mark_chunk_walls_dirty_and_refresh_for_tiles": Callable(self, "_mark_walls_dirty_and_refresh_for_tiles"),
		"player_wallwood_max_hp": player_wallwood_max_hp,
		"player_wall_drop_enabled": player_wall_drop_enabled,
		"player_wall_drop_item_id": player_wall_drop_item_id,
		"player_wall_drop_amount": player_wall_drop_amount,
		"structural_wall_drop_enabled": structural_wall_drop_enabled,
		"structural_wall_drop_item_id": structural_wall_drop_item_id,
		"structural_wall_drop_amount": structural_wall_drop_amount,
		"player_wall_hit_shake_duration": player_wall_hit_shake_duration,
		"player_wall_hit_shake_px": player_wall_hit_shake_px,
		"player_wall_hit_shake_speed": player_wall_hit_shake_speed,
		"player_wall_hit_flash_time": player_wall_hit_flash_time,
		"structural_wall_default_hp": structural_wall_default_hp,
		"player_wall_hit_tint": PLAYER_WALL_HIT_TINT,
		"player_wall_fallback_atlas": PLAYER_WALL_FALLBACK_ATLAS,
		"player_wall_isolated_atlas": PLAYER_WALL_ISOLATED_ATLAS,
		"player_wall_fallback_alt": PLAYER_WALL_FALLBACK_ALT,
		"wall_reconnect_offsets": WALL_RECONNECT_OFFSETS,
	})
	Debug.log("boot", "World._ready begin")
	ground_tilemap.z_index = -1
	cliffs_tilemap.z_index = 5
	var cliff_mat := ShaderMaterial.new()
	cliff_mat.shader = load("res://shaders/cliff_occlusion.gdshader")
	cliff_mat.set_shader_parameter("fade_radius", 96.0)
	cliff_mat.set_shader_parameter("alpha_hidden", 0.4)
	cliff_mat.set_shader_parameter("is_behind", false)
	cliff_mat.set_shader_parameter("screen_size", _cliff_screen_size)
	cliff_mat.set_shader_parameter("player_screen_pos", _cliff_screen_size * 0.5)
	cliffs_tilemap.material = cliff_mat
	call_deferred("_init_cliff_screen_size")
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

	WorldSave.chunk_size = chunk_size

	SaveManager.register_world(self)
	var _had_save := SaveManager.load_world_save()

	# Seeds derivados de run_seed — determinísticos y persistentes entre cargas
	_biome_seed = absi(hash(Seed.run_seed ^ 0x1A2B3C4D))
	_ground_painter.setup(absi(hash(Seed.run_seed ^ 0x5E6F7A8B)), width, height)

	player = get_node_or_null("../Player")

	var occ_ctrl := OcclusionController.new()
	occ_ctrl.name = "OcclusionController"
	add_child(occ_ctrl)

	tavern_chunk = _tile_to_chunk(Vector2i(width / 2, height / 2))
	spawn_tile = get_tavern_center_tile(tavern_chunk)

	var spawn_world: Vector2 = _tile_to_world(spawn_tile)
	if player:
		player.global_position = spawn_world

	if _had_save and player:
		var loaded_chunk := world_to_chunk(SaveManager._pending_player_pos)
		var max_chunk := Vector2i(width / chunk_size, height / chunk_size)
		var in_bounds := loaded_chunk.x >= 0 and loaded_chunk.x < max_chunk.x \
			and loaded_chunk.y >= 0 and loaded_chunk.y < max_chunk.y
		if in_bounds:
			player.global_position = SaveManager._pending_player_pos
			current_player_chunk = loaded_chunk
		else:
			push_warning("SaveManager: posición guardada fuera del mundo actual, usando spawn.")
			player.global_position = spawn_world
			current_player_chunk = world_to_chunk(spawn_world)
	else:
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
		"stone_ore_scene": stone_ore_scene,
		"tree_scene": tree_scene,
		"grass_tuft_scene": grass_tuft_scene,
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

	_cliff_seed = absi(hash(Seed.run_seed ^ 0x9C0D1E2F))
	cliff_generator = CliffGenerator.new()
	cliff_generator.name = "CliffGenerator"
	add_child(cliff_generator)

	_entity_root = Node2D.new()
	_entity_root.name = "EntitiesRoot"
	_entity_root.z_index = 10
	_entity_root.y_sort_enabled = true
	add_child(_entity_root)

	cliff_generator.setup({
		"x_min": 0, "x_max": width, "y_min": 0, "y_max": height,
		"chunk_size": chunk_size, "layer": LAYER_GROUND,
		"terrain_set_id": 0, "terrain_id": 2,
		"spawn_center": spawn_tile,
		"cliff_seed": _cliff_seed,
		"cliffs_tilemap": cliffs_tilemap,
		"border_width": cliff_border_width,
		"record_stage_time": Callable(self, "_record_chunk_stage_time"),
		"blob_count":         cliff_blob_count,
		"radius_min":         cliff_radius_min,
		"radius_max":         cliff_radius_max,
		"warp_strength":      cliff_warp_strength,
		"clear_radius":       cliff_clear_radius,
		"spawn_safe_radius":  cliff_spawn_safe_radius,
		"collision_band":     cliff_collision_band,
	})
	cliff_generator.global_phase()
	_paint_outer_ground_band()

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
		"cliff_generator": cliff_generator,
		"world_to_tile": Callable(self, "_world_to_tile"),
		"entity_root": _entity_root,
	})
	npc_simulator.current_player_chunk = current_player_chunk
	_vegetation_root.setup({
		"ground_tilemap": ground_tilemap,
		"chunk_size": chunk_size,
		"tile_size": 32,
		"grass_source_id": 3,   # source 3 = grassautotile.png en TileMap_Ground.tres
		"grass_terrain_id": 1,  # terrain_set_0/terrain_1 = "grass"
		"chunk_save": chunk_save,
	})

	if GameEvents != null and not GameEvents.entity_died.is_connected(_on_entity_died):
		GameEvents.entity_died.connect(_on_entity_died)
	if not chunk_stage_completed.is_connected(_on_chunk_stage_completed):
		chunk_stage_completed.connect(_on_chunk_stage_completed)

	if _player_wall_system != null:
		if not _player_wall_system.player_wall_hit.is_connected(_on_wall_hit_activity):
			_player_wall_system.player_wall_hit.connect(_on_wall_hit_activity)
		if not _player_wall_system.structural_wall_hit.is_connected(_on_wall_hit_activity):
			_player_wall_system.structural_wall_hit.connect(_on_wall_hit_activity)

	WorldSave.wall_tile_blocker_fn = _has_wall_tile_between

	_settlement_intel = SettlementIntelScript.new()
	_settlement_intel.setup({
		"world_to_tile":    Callable(self, "_world_to_tile"),
		"tile_to_world":    Callable(self, "_tile_to_world"),
		"player_pos_getter": Callable(self, "_get_player_world_pos"),
	})
	if _player_wall_system != null \
			and not _player_wall_system.player_wall_drop.is_connected(_on_wall_drop_for_intel):
		_player_wall_system.player_wall_drop.connect(_on_wall_drop_for_intel)

	await update_chunks(current_player_chunk)


func _on_chunk_stage_completed(chunk_pos: Vector2i, stage: String) -> void:
	if stage != "tiles":
		return
	if _player_wall_system != null:
		_player_wall_system.apply_saved_walls_for_chunk(chunk_pos)

func _clear_chunk_wall_runtime_cache() -> void:
	if _chunk_wall_collider_cache != null:
		_chunk_wall_collider_cache.clear_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveManager.save_world()
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_save_game"):
		SaveManager.save_world()
	elif event.is_action_pressed("ui_load_game"):
		if SaveManager.has_save():
			get_tree().reload_current_scene()
		else:
			Debug.log("save", "F6: no save found")
	elif event.is_action_pressed("ui_new_game"):
		SaveManager.new_game()
		get_tree().reload_current_scene()

func _process_tile_erase_queue() -> void:
	var budget := 2
	while budget > 0 and not _pending_tile_erases.is_empty():
		var cpos: Vector2i = _pending_tile_erases.pop_front()
		if loaded_chunks.has(cpos):
			continue  # el chunk volvió al rango antes de que borráramos — saltar
		unload_chunk(cpos)
		budget -= 1

func _process_wall_refresh_queue(max_rebuilds_per_frame: int = 1) -> void:
	if _wall_refresh_queue == null:
		return
	var rebuild_budget: int = maxi(0, max_rebuilds_per_frame)
	while rebuild_budget > 0:
		var result: Dictionary = _wall_refresh_queue.try_pop_next()
		if not result.ok:
			break

		var chunk_pos: Vector2i = result.chunk_pos
		if not loaded_chunks.has(chunk_pos):
			if _wall_refresh_queue != null:
				_wall_refresh_queue.purge_chunk(chunk_pos)
			continue

		_ensure_chunk_wall_collision(chunk_pos)
		_wall_refresh_queue.confirm_rebuild(chunk_pos, result.revision)
		rebuild_budget -= 1

func _process(delta: float) -> void:
	if _settlement_intel != null:
		_settlement_intel.process(delta)
	pipeline.process(delta)
	_process_wall_refresh_queue(1)
	_process_tile_erase_queue()
	if entity_coordinator != null and player:
		entity_coordinator.set_player_pos(player.global_position)
	_update_cliff_occlusion()
	_process_chunk_perf_debug(delta)
	_autosave_timer += delta
	if _autosave_timer >= autosave_interval:
		_autosave_timer = 0.0
		SaveManager.save_world()
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
			_vegetation_root.load_chunk(cpos, chunk_occupied_tiles.get(cpos, {}))

	for cpos in loaded_chunks.keys():
		if not needed.has(cpos):
			# Lógica inmediata: sacar del mapa activo y descargar entidades
			loaded_chunks.erase(cpos)
			entity_coordinator.unload_entities(cpos)
			pipeline.on_chunk_unloaded(cpos)
			# Erasure de tiles diferida: evita 4× erase_chunk_region por frame
			_ground_terrain_painted_chunks.erase(_chunk_key(cpos))
			_pending_tile_erases.append(cpos)

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
	if budgets.has("cliff_paint_chunks_per_tick"):
		pipeline.cliff_paint_chunks_per_tick = budgets["cliff_paint_chunks_per_tick"]

func unload_chunk(chunk_pos: Vector2i) -> void:
	if _wall_refresh_queue != null:
		_wall_refresh_queue.purge_chunk(chunk_pos)
	_vegetation_root.unload_chunk(chunk_pos)
	# Borrar suelo del WorldTileMap
	_tile_painter.erase_chunk_region(tilemap, chunk_pos, chunk_size, [LAYER_GROUND, LAYER_FLOOR])
	# Borrar paredes del StructureWallsMap
	_tile_painter.erase_chunk_region(walls_tilemap, chunk_pos, chunk_size, [WALLS_MAP_LAYER])
	# Borrar suelo del GroundTileMap
	_tile_painter.erase_chunk_region(ground_tilemap, chunk_pos, chunk_size, [0])
	_ground_terrain_painted_chunks.erase(_chunk_key(chunk_pos))
	# Liberar collider de cliffs y borrar tiles del TileMap_Cliffs
	cliff_generator.release_chunk_cliff_collisions(chunk_pos)
	_tile_painter.erase_chunk_region(cliffs_tilemap, chunk_pos, chunk_size, [LAYER_GROUND])

func get_spawn_biome(x: int, y: int) -> int:
	var terrain := _ground_painter.get_terrain(x, y)
	if terrain == 0:  # dirt patch → alta densidad de ores
		return BIOME_ID_DENSE_GRASS
	return BIOME_ID_GRASSLAND  # grass → baja densidad

func get_walk_surface_at_world_pos(world_pos: Vector2) -> StringName:
	var tile_pos: Vector2i = _world_to_tile(world_pos)
	return get_walk_surface_at_tile(tile_pos)

func get_walk_surface_at_tile(tile_pos: Vector2i) -> StringName:
	if not _is_valid_walk_surface_tile(tile_pos):
		return WALK_SURFACE_GRASS

	if _has_floorwood_placeable_at_tile(tile_pos):
		return WALK_SURFACE_WOOD

	var floor_surface: StringName = _resolve_floor_walk_surface(tile_pos)
	if floor_surface != StringName():
		return floor_surface

	var terrain: int = _ground_painter.get_terrain(tile_pos.x, tile_pos.y)
	if terrain == 0:
		return WALK_SURFACE_DIRT
	return WALK_SURFACE_GRASS

func _resolve_floor_walk_surface(tile_pos: Vector2i) -> StringName:
	if tilemap == null:
		return StringName()
	if tilemap.get_cell_source_id(LAYER_FLOOR, tile_pos) != SRC_FLOOR:
		return StringName()
	var atlas: Vector2i = tilemap.get_cell_atlas_coords(LAYER_FLOOR, tile_pos)
	if FLOOR_SURFACE_BY_ATLAS.has(atlas):
		var surface_id: StringName = FLOOR_SURFACE_BY_ATLAS[atlas]
		return surface_id
	return StringName()

func _is_valid_walk_surface_tile(tile_pos: Vector2i) -> bool:
	return tile_pos.x >= 0 and tile_pos.x < width and tile_pos.y >= 0 and tile_pos.y < height

func _has_floorwood_placeable_at_tile(tile_pos: Vector2i) -> bool:
	var cpos := _tile_to_chunk(tile_pos)
	var entry := WorldSave.get_placed_entity_at_tile(cpos.x, cpos.y, tile_pos)
	if entry.is_empty():
		return false
	var item_id: String = String(entry.get("item_id", "")).strip_edges()
	return item_id == FLOORWOOD_RUNTIME_ITEM_ID or item_id == FLOORWOOD_LEGACY_ITEM_ID

var chunk_occupied_tiles: Dictionary = {}

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
		"stone_ore_scene": stone_ore_scene,
		"tree_scene": tree_scene,
		"grass_tuft_scene": grass_tuft_scene,
		"bandit_camp_scene": bandit_camp_scene,
		"bandit_scene": bandit_scene,
		"cliff_generator": cliff_generator,
		"copper_grass_min": copper_grass_min,
		"copper_grass_max": copper_grass_max,
		"copper_dirt_min": copper_dirt_min,
		"copper_dirt_max": copper_dirt_max,
		"stone_grass_min": stone_grass_min,
		"stone_grass_max": stone_grass_max,
		"stone_dirt_min": stone_dirt_min,
		"stone_dirt_max": stone_dirt_max,
		"tree_grass_min": tree_grass_min,
		"tree_grass_max": tree_grass_max,
		"tree_dirt_min": tree_dirt_min,
		"tree_dirt_max": tree_dirt_max,
		"grass_tuft_grass_min": grass_tuft_grass_min,
		"grass_tuft_grass_max": grass_tuft_grass_max,
		"grass_tuft_dirt_min": grass_tuft_dirt_min,
		"grass_tuft_dirt_max": grass_tuft_dirt_max,
		"structural_wall_default_hp": structural_wall_default_hp,
	}

func _on_ground_fallback_debug(chunk_pos: Vector2i, total_cells: int, missing_cells: int, invalid_source_cells: int, mode: String = "legacy") -> void:
	_perf_monitor.record_fallback(chunk_pos, total_cells, missing_cells, invalid_source_cells, mode)

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return tilemap.local_to_map(tilemap.to_local(world_pos))

func _has_wall_tile_between(from_pos: Vector2, to_pos: Vector2) -> bool:
	if walls_tilemap == null:
		return false
	var from_tile := walls_tilemap.local_to_map(walls_tilemap.to_local(from_pos))
	var to_tile := walls_tilemap.local_to_map(walls_tilemap.to_local(to_pos))
	if from_tile == to_tile:
		return false
	return _tile_line_has_wall(from_tile, to_tile)

func _tile_line_has_wall(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var dx := absi(to_tile.x - from_tile.x)
	var dy := absi(to_tile.y - from_tile.y)
	var sx := 1 if to_tile.x > from_tile.x else -1
	var sy := 1 if to_tile.y > from_tile.y else -1
	var x := from_tile.x
	var y := from_tile.y
	var err := dx - dy
	while true:
		var cell := Vector2i(x, y)
		if cell != from_tile and cell != to_tile:
			if walls_tilemap.get_cell_source_id(WALLS_MAP_LAYER, cell) == SRC_WALLS:
				return true
		if x == to_tile.x and y == to_tile.y:
			break
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return false

func _tile_to_world(tile_pos: Vector2i) -> Vector2:
	return tilemap.to_global(tilemap.map_to_local(tile_pos))

func _tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	return Vector2i(int(floor(float(tile_pos.x) / float(chunk_size))), int(floor(float(tile_pos.y) / float(chunk_size))))

func _get_sound_panel_for_walls() -> Node:
	if AudioSystem != null and AudioSystem.has_method("get_sound_panel"):
		return AudioSystem.get_sound_panel()
	return null

func _debug_check_player_chunk(player_global: Vector2) -> void:
	if not DEBUG_SPAWN: return
	var player_tile: Vector2i = _world_to_tile(player_global)
	var chunk_key: Vector2i = _tile_to_chunk(player_tile)
	Debug.log("spawn", "CHUNK_CHECK player_tile=%s player_chunk=%s" % [str(player_tile), str(chunk_key)])

func unload_chunk_entities(chunk_pos: Vector2i) -> void:
	pipeline.on_chunk_unloaded(chunk_pos)
	entity_coordinator.unload_entities(chunk_pos)
	if _chunk_wall_collider_cache != null:
		_chunk_wall_collider_cache.on_chunk_unloaded(chunk_pos)

func _get_current_player_chunk() -> Vector2i:
	return current_player_chunk

func _chunk_key(chunk_pos: Vector2i) -> String:
	return "%d,%d" % [chunk_pos.x, chunk_pos.y]

func _chunk_from_key(chunk_key: String) -> Vector2i:
	var parts: PackedStringArray = chunk_key.split(",")
	if parts.size() != 2:
		return Vector2i(-99999, -99999)
	return Vector2i(int(parts[0]), int(parts[1]))

func _get_extra_wall_support_lookup_for_chunk(chunk_pos: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	# Miramos 3x3 chunks para cubrir el margen de 1 tile alrededor del chunk actual
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cx := chunk_pos.x + dx
			var cy := chunk_pos.y + dy
			var entries := WorldSave.get_placed_entities_in_chunk(cx, cy)
			for entry in entries:
				var item_id: String = BuildableCatalog.normalize_buildable_id(String(entry.get("item_id", "")))
				if item_id != DOORWOOD_ITEM_ID:
					continue
				var tx: int = int(entry.get("tile_pos_x", -999999))
				var ty: int = int(entry.get("tile_pos_y", -999999))
				out[Vector2i(tx, ty)] = true
	return out



# Frontera de módulos: world.gd conserva sólo API pública de fachada para gameplay/colocación;
# toda la lógica interna de ownership, reconciliación, drops, feedback y aplicación de paredes vive en PlayerWallSystem.
func can_place_player_wall_at_tile(tile_pos: Vector2i) -> bool:
	return _player_wall_system != null and _player_wall_system.can_place_player_wall_at_tile(tile_pos)

func place_player_wall_at_tile(tile_pos: Vector2i, hp_override: int = -1) -> bool:
	return _player_wall_system != null and _player_wall_system.place_player_wall_at_tile(tile_pos, hp_override)

func damage_player_wall_from_contact(hit_pos: Vector2, hit_normal: Vector2, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_from_contact(hit_pos, hit_normal, amount)

func damage_player_wall_near_world_pos(world_pos: Vector2, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_near_world_pos(world_pos, amount)

func damage_player_wall_at_world_pos(world_pos: Vector2, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_at_world_pos(world_pos, amount)

func damage_player_wall_in_circle(world_center: Vector2, world_radius: float, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_in_circle(world_center, world_radius, amount)

func hit_wall_at_world_pos(world_pos: Vector2, amount: int = 1, radius: float = 20.0, allow_structural_feedback: bool = true) -> bool:
	return _player_wall_system != null and _player_wall_system.hit_wall_at_world_pos(world_pos, amount, radius, allow_structural_feedback)

func damage_player_wall_at_tile(tile_pos: Vector2i, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_at_tile(tile_pos, amount)

func remove_player_wall_at_tile(tile_pos: Vector2i, drop_item: bool = true) -> bool:
	return _player_wall_system != null and _player_wall_system.remove_player_wall_at_tile(tile_pos, drop_item)

func refresh_wall_collision_for_tiles(tile_positions: Array[Vector2i]) -> void:
	if tile_positions.is_empty():
		return
	var valid_tiles: Array[Vector2i] = []
	for tile_pos in tile_positions:
		if tile_pos.x < 0 or tile_pos.x >= width or tile_pos.y < 0 or tile_pos.y >= height:
			continue
		valid_tiles.append(tile_pos)
	if valid_tiles.is_empty():
		return
	_mark_walls_dirty_and_refresh_for_tiles(valid_tiles)

func _mark_walls_dirty_and_refresh_for_tiles(tile_positions: Array[Vector2i]) -> void:
	var chunks_to_refresh: Dictionary = {}
	for tile_pos in tile_positions:
		var cpos: Vector2i = _tile_to_chunk(tile_pos)
		mark_chunk_walls_dirty(cpos.x, cpos.y)
		chunks_to_refresh[cpos] = true
	for cpos in chunks_to_refresh.keys():
		var chunk_pos: Vector2i = cpos as Vector2i
		if _wall_refresh_queue != null:
			_wall_refresh_queue.record_activity(chunk_pos)
			if loaded_chunks.has(chunk_pos):
				_wall_refresh_queue.enqueue(chunk_pos)
	if _settlement_intel != null and not tile_positions.is_empty():
		_settlement_intel.mark_base_scan_dirty_near(_tile_to_world(tile_positions[0]))

func mark_chunk_walls_dirty(cx: int, cy: int) -> void:
	if _chunk_wall_collider_cache != null:
		_chunk_wall_collider_cache.mark_dirty(cx, cy)

func _ensure_chunk_wall_collision(chunk_pos: Vector2i) -> void:
	if _chunk_wall_collider_cache != null:
		_chunk_wall_collider_cache.ensure_for_chunk(chunk_pos)

func _init_cliff_screen_size() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	_cliff_screen_size = Vector2(vp.get_visible_rect().size)
	if cliffs_tilemap.material != null:
		(cliffs_tilemap.material as ShaderMaterial).set_shader_parameter("screen_size", _cliff_screen_size)

func _update_cliff_occlusion() -> void:
	if player == null or cliffs_tilemap.material == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var mat := cliffs_tilemap.material as ShaderMaterial
	# Actualizar screen_size si cambió el viewport (igual que OcclusionController)
	var current_size := Vector2(vp.get_visible_rect().size)
	if not current_size.is_equal_approx(_cliff_screen_size):
		_cliff_screen_size = current_size
		mat.set_shader_parameter("screen_size", _cliff_screen_size)
	# is_behind: hay cliff en la tile del player o justo al sur (player al norte = detrás del cliff)
	var player_tile := _world_to_tile(player.global_position)
	var behind: bool = \
		cliffs_tilemap.get_cell_source_id(0, player_tile) != -1 or \
		cliffs_tilemap.get_cell_source_id(0, player_tile + Vector2i(0, 1)) != -1
	mat.set_shader_parameter("is_behind", behind)
	var screen_pos: Vector2 = vp.get_canvas_transform() * player.global_position
	mat.set_shader_parameter("player_screen_pos", screen_pos)

func get_spawn_world_pos() -> Vector2:
	return _tile_to_world(spawn_tile)

func teleport_to_spawn() -> void:
	if player == null:
		return
	var target: Vector2 = _tile_to_world(spawn_tile)
	player.global_position = target
	var new_chunk := world_to_chunk(target)
	if new_chunk != current_player_chunk:
		current_player_chunk = new_chunk
		await update_chunks(current_player_chunk)
	Debug.log("spawn", "/spawn → tile=%s world=%s" % [str(spawn_tile), str(target)])

func get_tavern_center_tile(chunk_pos: Vector2i) -> Vector2i:
	var x0: int = chunk_pos.x * chunk_size + 4
	var y0: int = chunk_pos.y * chunk_size + 3
	return Vector2i(x0 + 6, y0 + 4)


func _on_wall_hit_activity(tile_pos: Vector2i) -> void:
	if _wall_refresh_queue != null:
		var cpos: Vector2i = _tile_to_chunk(tile_pos)
		_wall_refresh_queue.record_activity(cpos)

func _get_player_world_pos() -> Vector2:
	if player == null:
		return Vector2.ZERO
	return player.global_position

func _on_wall_drop_for_intel(tile_pos: Vector2i, _item_id: String, _amount: int) -> void:
	if _settlement_intel != null:
		_settlement_intel.mark_base_scan_dirty_near(_tile_to_world(tile_pos))

func _on_entity_died(uid: String, kind: String, _pos: Vector2, _killer: Node) -> void:
	if kind != "enemy":
		return
	if uid == "":
		return
	npc_simulator.on_entity_died(uid)


# Pinta grass en GroundTileMap fuera del límite del mundo para cubrir el gris del viewport.
## SettlementIntel — interest marker facade
func record_interest_event(kind: String, world_pos: Vector2, metadata: Dictionary = {}) -> void:
	if _settlement_intel != null:
		_settlement_intel.record_interest_event(kind, world_pos, metadata)

func get_interest_markers_near(world_pos: Vector2, radius: float) -> Array[Dictionary]:
	if _settlement_intel == null:
		return []
	return _settlement_intel.get_interest_markers_near(world_pos, radius)

func rescan_workbench_markers() -> void:
	if _settlement_intel != null:
		_settlement_intel.rescan_workbench_markers()

func mark_interest_scan_dirty() -> void:
	if _settlement_intel != null:
		_settlement_intel.mark_interest_scan_dirty()

## SettlementIntel — base detection facade
func get_detected_bases_near(world_pos: Vector2, radius: float) -> Array[Dictionary]:
	if _settlement_intel == null:
		return []
	return _settlement_intel.get_detected_bases_near(world_pos, radius)

func has_detected_base_near(world_pos: Vector2, radius: float) -> bool:
	if _settlement_intel == null:
		return false
	return _settlement_intel.has_detected_base_near(world_pos, radius)


func _paint_outer_ground_band() -> void:
	var band: int = 10
	var cells: Array[Vector2i] = []
	for i in range(1, band + 1):
		for x in range(-band, width + band):
			cells.append(Vector2i(x, -i))
			cells.append(Vector2i(x, height + i - 1))
		for y in range(-band + 1, height + band - 1):
			cells.append(Vector2i(-i, y))
			cells.append(Vector2i(width + i - 1, y))
	if not cells.is_empty():
		ground_tilemap.set_cells_terrain_connect(0, cells, 0, 1, false)
