extends Node2D

# Responsibility boundary:
# world.gd is the top-level orchestrator/facade for world subsystems. It wires
# systems together and exposes public gameplay hooks, but social policy and
# other subsystem internals should live in dedicated services instead of here.

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
@export_range(0.0, 1.0, 0.01) var camp_spawn_chance: float = 1.0
@export var tavern_keeper_scene: PackedScene
@export var sentinel_scene: PackedScene
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
@export var debug_world_sim_telemetry_enabled: bool = true

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
var npc_simulator: NpcSimulator
var entity_coordinator: EntitySpawnCoordinator
var pipeline: ChunkPipeline
var _entity_root: Node2D

var chunk_save: Dictionary = {}
var _spawn_queue: SpawnBudgetQueue
var _perf_monitor := ChunkPerfMonitor.new()
var _pending_tile_erases: Array[Vector2i] = []
var _settlement_intel: SettlementIntel
var _player_territory: PlayerTerritoryMap
var _player_territory_dirty: bool = false
var _bandit_behavior_layer: BanditBehaviorLayer
var _world_spatial_index: WorldSpatialIndex
var _world_territory_policy: WorldTerritoryPolicy
var _local_social_ports: LocalSocialAuthorityPorts
var _tavern_memory:            TavernLocalMemory
var _tavern_policy:            TavernAuthorityPolicy
var _tavern_director:          TavernSanctionDirector
var _tavern_presence_monitor:  TavernPresenceMonitor
var _tavern_garrison_monitor:  TavernGarrisonMonitor
var _tavern_brawl:             TavernPerimeterBrawl

## Postura defensiva del recinto. Evaluada cada _POSTURE_EVAL_INTERVAL segundos.
const _POSTURE_EVAL_INTERVAL: float = 10.0
var _posture_eval_accum: float       = 0.0
var _current_posture:    int         = TavernDefensePosture.NORMAL
## patrol_points originales de perimeter guards, cacheados en spawn.
## Clave: Sentinel node (object reference). Valor: PackedVector2Array.
## Permite restaurar patrullas al salir de FORTIFIED.
var _perimeter_patrol_cache: Dictionary = {}
var _resource_repopulator: ResourceRepopulator
var _speech_bubble_manager: WorldSpeechBubbleManager
var _player_wall_system: PlayerWallSystem
var _wall_feedback: WallFeedback
var _wall_persistence: WallPersistence
var _structural_wall_persistence: StructuralWallPersistence
var _chunk_wall_collider_cache: ChunkWallColliderCache
var _wall_refresh_queue: WallRefreshQueue
var _cadence: WorldCadenceCoordinator
var _world_sim_telemetry: WorldSimTelemetry
var _save_count: int = 0
var _last_save_time_msec: int = -1
var _tavern_sentinels_spawned: bool = false

# Placement reaction
## Every hostile eligible group receives structure-assault targeting on player placement.
## No fixed 3-unit cap: dispatch uses ALL members by default (configurable via squad value).
## RaidQueue receives per-group structure_assault intents so behavior keeps consuming targets.
const _PLACEMENT_REACT_INTENT_LOCK_SECONDS: float = 90.0
const _PLACEMENT_REACT_STRUCT_ASSAULT_SQUAD: int = -1  # -1 = all available members
const _PLACEMENT_REACT_EVENT_MIN_INTERVAL: float = 0.20
## Empty filter = query all player placeables from WorldSpatialIndex persistent cache.
const _PLAYER_RAID_PLACEABLE_ITEM_IDS: Array[String] = []
var _placement_react_last_event_at: float = -9999.0

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
const BanditBehaviorLayerScript        := preload("res://scripts/world/BanditBehaviorLayer.gd")
const WorldSpatialIndexScript          := preload("res://scripts/world/WorldSpatialIndex.gd")
const LocalSocialAuthorityPortsScript  := preload("res://scripts/world/LocalSocialAuthorityPorts.gd")
const ResourceRepopulatorScript        := preload("res://scripts/world/ResourceRepopulator.gd")
const WorldSpeechBubbleManagerScript   := preload("res://scripts/ui/WorldSpeechBubbleManager.gd")
const PlayerWallSystemScript := preload("res://scripts/world/PlayerWallSystem.gd")
const WallPersistenceScript := preload("res://scripts/world/WallPersistence.gd")
const StructuralWallPersistenceScript := preload("res://scripts/world/StructuralWallPersistence.gd")
const WallFeedbackScript := preload("res://scripts/world/WallFeedback.gd")
const ChunkWallColliderCacheScript := preload("res://scripts/world/ChunkWallColliderCache.gd")
const WallRefreshQueueScript := preload("res://scripts/world/WallRefreshQueue.gd")
const WorldCadenceCoordinatorScript := preload("res://scripts/world/WorldCadenceCoordinator.gd")
const WorldSimTelemetryScript := preload("res://scripts/world/WorldSimTelemetry.gd")
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
	_cadence = WorldCadenceCoordinatorScript.new()
	# WorldCadenceCoordinator governs shared world pulses only: cross-system
	# maintenance, chunk/autosave work, and directors that coordinate multiple
	# systems. Specialized inner loops can still keep local clocks when their
	# timing is inherently private/incremental.
	_cadence.configure_lane(&"short_pulse", 0.12, 0.15)
	_cadence.configure_lane(&"medium_pulse", 0.50, 0.42)
	_cadence.configure_lane(&"director_pulse", 0.12, 0.67)
	_cadence.configure_lane(&"chunk_pulse", chunk_check_interval, 0.68)
	_cadence.configure_lane(&"autosave", autosave_interval, 0.31, 1)
	_cadence.configure_lane(&"settlement_base_scan", SettlementIntel.BASE_RESCAN_INTERVAL, SettlementIntel.BASE_SCAN_PHASE_RATIO, 1)
	_cadence.configure_lane(&"settlement_workbench_scan", SettlementIntel.WORKBENCH_RESCAN_INTERVAL, SettlementIntel.WORKBENCH_SCAN_PHASE_RATIO, 1)
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
	_spawn_queue.job_spawned.connect(_on_spawn_job_completed)

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
		"width": width,
		"height": height,
	})
	npc_simulator.current_player_chunk = current_player_chunk

	_speech_bubble_manager = WorldSpeechBubbleManagerScript.new()
	_speech_bubble_manager.name = "WorldSpeechBubbleManager"
	add_child(_speech_bubble_manager)

	_world_spatial_index = WorldSpatialIndexScript.new()
	_world_spatial_index.name = "WorldSpatialIndex"
	add_child(_world_spatial_index)
	_world_spatial_index.setup({
		"world_to_tile": Callable(self, "_world_to_tile"),
		"tile_to_world": Callable(self, "_tile_to_world"),
		"chunk_size": chunk_size,
	})

	_bandit_behavior_layer = BanditBehaviorLayerScript.new()
	_bandit_behavior_layer.name = "BanditBehaviorLayer"
	add_child(_bandit_behavior_layer)
	_bandit_behavior_layer.setup({
		"cadence":               _cadence,
		"npc_simulator":         npc_simulator,
		"player":                player,
		"speech_bubble_manager": _speech_bubble_manager,
		"world_spatial_index": _world_spatial_index,
		"world_node": self,
	})  # Setup del sistema de extorsión

	_resource_repopulator = ResourceRepopulatorScript.new()
	_resource_repopulator.name = "ResourceRepopulator"
	add_child(_resource_repopulator)
	_resource_repopulator.setup(stone_ore_scene, copper_ore_scene, tilemap)

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
	if not PlacementSystem.placement_completed.is_connected(_on_placement_completed):
		PlacementSystem.placement_completed.connect(_on_placement_completed)
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
		"cadence": _cadence,
		"world_to_tile":    Callable(self, "_world_to_tile"),
		"tile_to_world":    Callable(self, "_tile_to_world"),
		"player_pos_getter": Callable(self, "_get_player_world_pos"),
		"world_spatial_index": _world_spatial_index,
	})
	_player_territory = PlayerTerritoryMap.new()
	_player_territory_dirty = true
	_tavern_memory   = TavernLocalMemory.new()
	_tavern_policy   = TavernAuthorityPolicy.new()
	_tavern_policy.setup({"memory": _tavern_memory})
	_tavern_director = TavernSanctionDirector.new()
	_tavern_director.setup({
		"get_keeper":          Callable(self, "_get_tavern_keeper_node"),
		"get_sentinels":       func() -> Array: return get_tree().get_nodes_in_group("tavern_sentinel"),
		"memory_deny_service": Callable(_tavern_memory, "deny_service_for"),
		"tavern_site_id":      "tavern_main",
	})
	_tavern_presence_monitor = TavernPresenceMonitor.new()
	_tavern_presence_monitor.setup({
		"incident_reporter": Callable(self, "report_tavern_incident"),
		"get_candidates": func() -> Array:
			var r: Array = []
			r.append_array(get_tree().get_nodes_in_group("player"))
			r.append_array(get_tree().get_nodes_in_group("enemy"))
			r.append_array(get_tree().get_nodes_in_group("npc"))
			return r,
		"interior_bounds": Callable(self, "get_tavern_inner_bounds_world"),
	})
	_tavern_garrison_monitor = TavernGarrisonMonitor.new()
	_tavern_garrison_monitor.setup({
		"get_sentinels":  func() -> Array: return get_tree().get_nodes_in_group("tavern_sentinel"),
		"tavern_site_id": "tavern_main",
	})
	_tavern_brawl = TavernPerimeterBrawl.new()
	_tavern_brawl.setup({
		"get_sentinels":     func() -> Array: return get_tree().get_nodes_in_group("tavern_sentinel"),
		"get_nearby_enemies": func(pos: Vector2, radius: float) -> Array:
			var result: Array = []
			for e in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(e) and (e as Node2D).global_position.distance_to(pos) <= radius:
					result.append(e)
			return result,
		"get_tavern_center": func() -> Vector2:
			var b: Rect2 = get_tavern_inner_bounds_world()
			return b.get_center() if b.size != Vector2.ZERO else Vector2.ZERO,
	})
	_local_social_ports = LocalSocialAuthorityPortsScript.new()
	_local_social_ports.setup({
		"local_authority_policy":  Callable(_tavern_policy,  "evaluate"),
		"local_memory_source":     Callable(_tavern_memory,  "get_snapshot"),
		"local_sanction_director": Callable(_tavern_director, "dispatch"),
	})
	_world_territory_policy = WorldTerritoryPolicy.new()
	_world_territory_policy.setup({
		"tile_to_world": Callable(self, "_tile_to_world"),
		"get_tavern_center_tile": Callable(self, "get_tavern_center_tile"),
		"react_to_bandit_territory_intrusion": Callable(self, "_on_bandit_territory_intrusion"),
		"local_social_ports": _local_social_ports,
	})
	PlacementSystem.register_placement_validator(Callable(self, "_validate_placement_restrictions"))

	NpcPathService.setup({
		"cliffs_tilemap":  cliffs_tilemap,
		"walls_tilemap":   walls_tilemap,
		"world_to_tile":   Callable(self, "_world_to_tile"),
		"tile_to_world":   Callable(self, "_tile_to_world"),
		"world_tile_rect": Rect2i(0, 0, width, height),
		"world_spatial_index": _world_spatial_index,
	})
	if _player_wall_system != null \
			and not _player_wall_system.player_wall_drop.is_connected(_on_wall_drop_for_intel):
		_player_wall_system.player_wall_drop.connect(_on_wall_drop_for_intel)

	_world_sim_telemetry = WorldSimTelemetryScript.new()
	_world_sim_telemetry.setup({
		"enabled": debug_world_sim_telemetry_enabled,
		"world": self,
		"cadence": _cadence,
		"bandit_behavior_layer": _bandit_behavior_layer,
		"settlement_intel": _settlement_intel,
		"world_spatial_index": _world_spatial_index,
		"maintenance_snapshot_cb": Callable(self, "_get_world_maintenance_debug_snapshot"),
		"npc_sim": npc_simulator,
		"perf_monitor": _perf_monitor,
	})

	# Wire SettlementIntel into BanditGroupIntel (must be after _settlement_intel is ready)
	if _bandit_behavior_layer != null:
		_bandit_behavior_layer.setup_group_intel({
			"get_interest_markers_near": Callable(self, "get_interest_markers_near"),
			"get_detected_bases_near": Callable(self, "get_detected_bases_near"),
			"find_nearest_player_wall_world_pos": Callable(self, "find_nearest_player_wall_world_pos"),
			"find_player_wall_samples_world_pos": Callable(self, "find_player_wall_samples_world_pos"),
			"find_nearest_player_workbench_world_pos": Callable(self, "find_nearest_player_workbench_world_pos"),
			"find_nearest_player_storage_world_pos": Callable(self, "find_nearest_player_storage_world_pos"),
			"find_nearest_player_placeable_world_pos": Callable(self, "find_nearest_player_placeable_world_pos"),
		})

	await update_chunks(current_player_chunk)


func _on_chunk_stage_completed(chunk_pos: Vector2i, stage: String) -> void:
	if stage == "tiles":
		if _player_wall_system != null:
			_player_wall_system.apply_saved_walls_for_chunk(chunk_pos)
	elif stage == "entities_enqueued" and chunk_pos == tavern_chunk:
		# Los jobs de entidades ya están en cola — spawnear sentinels.
		# El keeper aún puede no estar en árbol; usamos fallback por tile geometry.
		# El cableado del keeper ocurre en _on_spawn_job_completed cuando llega "npc_keeper".
		ensure_tavern_sentinels_spawned()


## Engancha el keeper al sistema institucional en cuanto su job es completado.
## El keeper se instancia después de entities_enqueued, así que no puede cablearse antes.
func _on_spawn_job_completed(job: Dictionary, node: Node) -> void:
	if String(job.get("kind", "")) == "npc_keeper":
		_wire_keeper_incident_reporter()  # incluye _register_tavern_containers()

func _clear_chunk_wall_runtime_cache() -> void:
	if _chunk_wall_collider_cache != null:
		_chunk_wall_collider_cache.clear_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_perform_world_save("window_close")
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_save_game"):
		_perform_world_save("manual")
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
	if _cadence != null:
		_cadence.advance(delta)
	if _settlement_intel != null:
		_settlement_intel.process(delta)
	if _tavern_presence_monitor != null:
		_tavern_presence_monitor.tick(delta)
	if _tavern_garrison_monitor != null:
		_tavern_garrison_monitor.tick(delta)
	if _tavern_brawl != null:
		_tavern_brawl.tick(delta)
	_tick_defense_posture(delta)
	var medium_pulses: int = _cadence.consume_lane(&"medium_pulse") if _cadence != null else 1
	for _pulse in medium_pulses:
		_tick_player_territory()
	pipeline.process(delta)
	var short_pulses: int = _cadence.consume_lane(&"short_pulse") if _cadence != null else 1
	for _pulse in short_pulses:
		_process_wall_refresh_queue(1)
		_process_tile_erase_queue()
	if entity_coordinator != null and player:
		entity_coordinator.set_player_pos(player.global_position)
	_update_cliff_occlusion()
	_process_chunk_perf_debug(delta)
	if _world_sim_telemetry != null:
		_world_sim_telemetry.tick(delta)
	if _cadence != null and _cadence.consume_lane(&"autosave") > 0:
		_perform_world_save("autosave")
	if _cadence != null and _cadence.consume_lane(&"chunk_pulse") <= 0:
		return
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
		"tavern_exclusion_rect": PropSpawner.compute_tavern_exclusion_rect(tavern_chunk, chunk_size),
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
		"camp_spawn_chance": camp_spawn_chance,
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
	return WorldSave.chunk_key_from_pos(chunk_pos)

func _chunk_from_key(chunk_key: String) -> Vector2i:
	return WorldSave.chunk_pos_from_key(chunk_key)

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

func find_nearest_player_wall_world_pos(world_pos: Vector2, radius: float) -> Vector2:
	if _player_wall_system == null:
		return Vector2(-1.0, -1.0)
	return _player_wall_system.find_nearest_player_wall_world_pos(world_pos, radius)


func find_player_wall_samples_world_pos(world_pos: Vector2, radius: float, max_points: int = 12,
		min_separation: float = 48.0) -> Array[Vector2]:
	if _player_wall_system == null:
		return []
	return _player_wall_system.find_player_wall_samples_world_pos(world_pos, radius, max_points, min_separation)

func find_nearest_player_workbench_world_pos(world_pos: Vector2, radius: float) -> Vector2:
	return _find_nearest_player_placeable_world_pos_by_items(world_pos, radius, [BuildableCatalog.ID_WORKBENCH])

func find_nearest_player_storage_world_pos(world_pos: Vector2, radius: float) -> Vector2:
	return _find_nearest_player_placeable_world_pos_by_items(world_pos, radius, [
		BuildableCatalog.ID_CHEST,
		BuildableCatalog.ID_BARREL,
	])


func find_nearest_player_placeable_world_pos(world_pos: Vector2, radius: float) -> Vector2:
	return _find_nearest_player_placeable_world_pos_by_items(world_pos, radius, _PLAYER_RAID_PLACEABLE_ITEM_IDS)


func _find_nearest_player_placeable_world_pos_by_items(world_pos: Vector2, radius: float,
		item_ids: Array[String]) -> Vector2:
	if _world_spatial_index == null:
		return Vector2(-1.0, -1.0)
	var best_pos: Vector2 = Vector2(-1.0, -1.0)
	var best_dsq: float = radius * radius
	var entries: Array[Dictionary] = _world_spatial_index.get_placeables_by_item_ids_near(world_pos, radius, item_ids)
	for entry in entries:
		var tile_pos := Vector2i(int(entry.get("tile_pos_x", -999999)), int(entry.get("tile_pos_y", -999999)))
		if tile_pos.x <= -999999 or tile_pos.y <= -999999:
			continue
		var placeable_pos: Vector2 = _tile_to_world(tile_pos)
		var dsq: float = world_pos.distance_squared_to(placeable_pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best_pos = placeable_pos
	return best_pos

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
	_player_territory_dirty = true

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


## Posición world del tile exterior a la puerta de la taberna.
## La puerta es la ausencia de pared en el tile inferior central (x0+6, y0+7).
## Este método devuelve el tile justo afuera: (door_x, inner_max.y + 2).
func get_tavern_exit_world_pos() -> Vector2:
	var keepers := get_tree().get_nodes_in_group("tavern_keeper")
	if not keepers.is_empty():
		var keeper := keepers[0]
		var inner_min: Vector2i = keeper.get("tavern_inner_min")
		var inner_max: Vector2i = keeper.get("tavern_inner_max")
		var door_x: int = (inner_min.x + inner_max.x + 1) / 2
		return _tile_to_world(Vector2i(door_x, inner_max.y + 2))
	# Fallback por geometría fija desde tavern_chunk
	var x0: int = tavern_chunk.x * chunk_size + 4
	var y0: int = tavern_chunk.y * chunk_size + 3
	return _tile_to_world(Vector2i(x0 + 6, y0 + 8))


## Rect2 en world-space del interior de la taberna (sin incluir las paredes).
func get_tavern_inner_bounds_world() -> Rect2:
	var keepers := get_tree().get_nodes_in_group("tavern_keeper")
	if not keepers.is_empty():
		var keeper := keepers[0]
		var inner_min: Vector2i = keeper.get("tavern_inner_min")
		var inner_max: Vector2i = keeper.get("tavern_inner_max")
		var min_world := _tile_to_world(inner_min)
		var max_world := _tile_to_world(inner_max + Vector2i(1, 1))
		return Rect2(min_world, max_world - min_world)
	# Fallback
	var x0: int = tavern_chunk.x * chunk_size + 4
	var y0: int = tavern_chunk.y * chunk_size + 3
	var min_world := _tile_to_world(Vector2i(x0 + 1, y0 + 1))
	var max_world := _tile_to_world(Vector2i(x0 + 11, y0 + 7))
	return Rect2(min_world, max_world - min_world)


## ── Tavern Sentinel Garrison (Fase 6) ────────────────────────────────────────
##
## Guarnición completa de 11 sentinels:
##   interior_guard (×2) — flanquean al keeper; presencia visible del espacio interior
##   door_guard     (×1) — borde exterior de la puerta; control de acceso; ronda corta
##   perimeter_guard(×8) — dos por lateral (norte/sur/este/oeste); offset ±56px
##
## Anti-doble-spawn: _tavern_sentinels_spawned + comprobación de grupo.
## TODO(multi-taberna): filtrar por tavern_site_id cuando haya más de una taberna.
##
## Activadores de incidente configurados:
##   wall_damaged          → VANDALISM MODERATE en interior+walls (ZONE_INTERIOR)
##   wall_damaged_exterior → VANDALISM SERIOUS en perímetro (ZONE_PERIMETER) → perimeter_guard responde
##   barrel_opened/barrel_destroyed, assault_keeper/sentinel, murder_in_tavern,
##   armed_intruder, trespass, bandit_attack, disturbance, suspicious_presence, loitering


func ensure_tavern_sentinels_spawned() -> void:
	if _tavern_sentinels_spawned:
		return
	# Segunda guarda: si por alguna razón ya hay sentinels de taberna en escena
	if not get_tree().get_nodes_in_group("tavern_sentinel").is_empty():
		_tavern_sentinels_spawned = true
		return
	if sentinel_scene == null:
		Debug.log("world", "ensure_tavern_sentinels_spawned: sentinel_scene no asignada en Inspector")
		return
	if _entity_root == null:
		Debug.log("world", "ensure_tavern_sentinels_spawned: _entity_root no disponible")
		return

	_tavern_sentinels_spawned = true

	var keeper_pos: Vector2 = _get_tavern_keeper_pos()
	var exit_pos:   Vector2 = get_tavern_exit_world_pos()
	var bounds:     Rect2   = get_tavern_inner_bounds_world()
	var cx: float = bounds.position.x + bounds.size.x * 0.5
	var cy: float = bounds.position.y + bounds.size.y * 0.5

	# Interior guards — flanquean al keeper (izquierda / derecha)
	_spawn_single_tavern_sentinel("interior_guard", keeper_pos + Vector2(-28.0, 16.0))
	_spawn_single_tavern_sentinel("interior_guard", keeper_pos + Vector2( 28.0, 16.0))

	# Door guard — 2 tiles al sur de la salida; patrulla suelta alrededor de la entrada
	var dg := _spawn_single_tavern_sentinel("door_guard", exit_pos + Vector2(0.0, 32.0))
	if dg != null:
		# 5 puntos irregulares frente a la puerta (no cuadrados, asimétricos)
		dg.patrol_points = PackedVector2Array([
			exit_pos + Vector2(-52.0,  28.0),
			exit_pos + Vector2(  0.0,  20.0),
			exit_pos + Vector2( 44.0,  36.0),
			exit_pos + Vector2( 16.0,  52.0),
			exit_pos + Vector2(-32.0,  44.0),
		])

	# Perimeter guards — 128px fuera del inner bounds (4 tiles; clearance segura
	# para paredes de hasta 3 tiles/96px de espesor). Valor reducido desde 192px
	# porque a mayor distancia el nav mesh puede no tener cobertura y el pathfinding falla.
	# Dos guards por lado (8 total) — offset lateral de 56px para cobertura doblada.
	const _PM: float = 128.0
	const _PO: float = 56.0   # offset lateral entre los dos guards de cada lado

	# Norte (×2)
	_spawn_single_tavern_sentinel("perimeter_guard",
		Vector2(cx - _PO, bounds.position.y - _PM), "north")
	_spawn_single_tavern_sentinel("perimeter_guard",
		Vector2(cx + _PO, bounds.position.y - _PM), "north")
	# Sur (×2)
	_spawn_single_tavern_sentinel("perimeter_guard",
		Vector2(cx - _PO, bounds.position.y + bounds.size.y + _PM), "south")
	_spawn_single_tavern_sentinel("perimeter_guard",
		Vector2(cx + _PO, bounds.position.y + bounds.size.y + _PM), "south")
	# Este (×2)
	_spawn_single_tavern_sentinel("perimeter_guard",
		Vector2(bounds.position.x + bounds.size.x + _PM, cy - _PO), "east")
	_spawn_single_tavern_sentinel("perimeter_guard",
		Vector2(bounds.position.x + bounds.size.x + _PM, cy + _PO), "east")
	# Oeste (×2)
	_spawn_single_tavern_sentinel("perimeter_guard",
		Vector2(bounds.position.x - _PM, cy - _PO), "west")
	_spawn_single_tavern_sentinel("perimeter_guard",
		Vector2(bounds.position.x - _PM, cy + _PO), "west")

	Debug.log("world", "[TavernSentinels] 11 desplegados — keeper=%s exit=%s bounds=%s" % [
		str(keeper_pos), str(exit_pos), str(bounds)
	])


## side — solo para perimeter_guard: "north" | "south" | "east" | "west"
func _spawn_single_tavern_sentinel(role: String, pos: Vector2, side: String = "") -> Sentinel:
	var s := sentinel_scene.instantiate() as Sentinel
	# Nombre descriptivo antes de add_child para que sea estable en logs y árbol.
	match role:
		"door_guard":
			s.name = "door_guard"
		"perimeter_guard":
			s.name = "perimeter_guard_" + side if not side.is_empty() else "perimeter_guard"
		"interior_guard":
			s.name = "interior_guard"  # auto-renombrado a interior_guard2 si ya existe
	_entity_root.add_child(s)
	s.global_position  = pos
	s.home_pos         = pos
	s.sentinel_role    = role
	s.tavern_site_id   = "tavern_main"
	s.add_to_group("tavern_sentinel")
	s.set_incident_reporter(Callable(self, "report_tavern_incident"))
	match role:
		"door_guard":
			pass  # patrol_points asignados por el callsite después del spawn
		"interior_guard":
			s.patrol_points = _get_interior_patrol_points()
		"perimeter_guard":
			if not side.is_empty():
				var pts := _get_perimeter_patrol_points(side, pos)
				s.patrol_points = pts
				# Cache para poder restaurar patrullas al salir de postura FORTIFIED.
				_perimeter_patrol_cache[s] = pts.duplicate()
	return s


## Patrol points para interior guards — 8 puntos que mezclan esquinas con puntos
## hacia el centro, de modo que al recorrerse en orden aleatorio el movimiento
## no sea un simple rectángulo sino un vagabundeo dentro del espacio interior.
func _get_interior_patrol_points() -> PackedVector2Array:
	var b: Rect2 = get_tavern_inner_bounds_world()
	var inset: float = 28.0
	var bi: Rect2   = b.grow(-inset)
	var cx: float   = bi.position.x + bi.size.x * 0.5
	var cy: float   = bi.position.y + bi.size.y * 0.5
	var hw: float   = bi.size.x * 0.5
	var hh: float   = bi.size.y * 0.5
	# 4 esquinas + 4 puntos interiores (≈45 % del camino al centro).
	# Al elegirse al azar, los guardias cruzan el interior en diagonal en lugar
	# de seguir siempre el perímetro.
	return PackedVector2Array([
		bi.position,                                   # NW
		bi.position + Vector2(bi.size.x, 0.0),         # NE
		bi.position + bi.size,                         # SE
		bi.position + Vector2(0.0, bi.size.y),         # SW
		Vector2(cx, cy - hh * 0.45),                  # interior norte
		Vector2(cx + hw * 0.40, cy),                  # interior este
		Vector2(cx, cy + hh * 0.45),                  # interior sur
		Vector2(cx - hw * 0.40, cy),                  # interior oeste
	])


## Patrol points para perimeter guards — 5 puntos con variación de profundidad
## que crean una trayectoria ondulada a lo largo del lateral, nunca una línea recta.
##
## "toward" = dirección que acerca al muro (e.g. +y para norte, -y para sur).
## d1/d2 se randomizan por instancia para que dos guards del mismo lado
## tengan rutas ligeramente distintas y no caminen sincronizados.
func _get_perimeter_patrol_points(side: String, home: Vector2) -> PackedVector2Array:
	var b: Rect2  = get_tavern_inner_bounds_world()
	const M: float = 128.0
	var d1: float  = randf_range(20.0, 32.0)   # profundidad variante: más cerca del muro
	var d2: float  = randf_range(16.0, 26.0)   # profundidad variante: más lejos del muro
	match side:
		"north", "south":
			# toward: +1 = acercarse al muro (norte sube y), -1 (sur baja y)
			var toward: float = 1.0 if side == "north" else -1.0
			return PackedVector2Array([
				Vector2(b.position.x - M,                 home.y + toward * d1),
				Vector2(b.position.x + b.size.x * 0.25,  home.y - toward * d2),
				Vector2(b.position.x + b.size.x * 0.5,   home.y),
				Vector2(b.position.x + b.size.x * 0.75,  home.y - toward * d2),
				Vector2(b.position.x + b.size.x + M,     home.y + toward * d1),
			])
		"east", "west":
			# toward: -1 = acercarse al muro (este baja x), +1 (oeste sube x)
			var toward: float = -1.0 if side == "east" else 1.0
			return PackedVector2Array([
				Vector2(home.x + toward * d1,   b.position.y - M),
				Vector2(home.x - toward * d2,   b.position.y + b.size.y * 0.25),
				Vector2(home.x,                  b.position.y + b.size.y * 0.5),
				Vector2(home.x - toward * d2,   b.position.y + b.size.y * 0.75),
				Vector2(home.x + toward * d1,   b.position.y + b.size.y + M),
			])
	return PackedVector2Array()


## ── Postura defensiva del recinto ────────────────────────────────────────────
##
## Evaluada cada _POSTURE_EVAL_INTERVAL segundos. Cuando la postura cambia,
## se propaga a tres subsistemas:
##   TavernPresenceMonitor — ajusta multiplier de thresholds
##   TavernAuthorityPolicy — activa/desactiva Regla 5 (exterior escalada)
##   Perimeter sentinels   — FORTIFIED: post fijo; NORMAL/GUARDED: patrulla corta
##
## La evaluación usa TavernDefensePosture.compute() que es puro y determinista.

func _tick_defense_posture(delta: float) -> void:
	if _tavern_memory == null:
		return
	_posture_eval_accum += delta
	if _posture_eval_accum < _POSTURE_EVAL_INTERVAL:
		return
	_posture_eval_accum = 0.0

	var bounds: Rect2 = get_tavern_inner_bounds_world()
	var tavern_center: Vector2 = bounds.get_center() if bounds.size != Vector2.ZERO else Vector2.ZERO
	var new_posture: int = TavernDefensePosture.compute(_tavern_memory, tavern_center, RunClock.now())

	if new_posture == _current_posture:
		return

	var old_posture: int = _current_posture
	_current_posture = new_posture
	_apply_defense_posture(new_posture, old_posture)
	Debug.log("authority", "[POSTURE] %s → %s" % [
		TavernDefensePosture.name_of(old_posture),
		TavernDefensePosture.name_of(new_posture),
	])


func _apply_defense_posture(posture: int, old_posture: int) -> void:
	# Propagar a monitor de presencia (thresholds dinámicos)
	if _tavern_presence_monitor != null:
		_tavern_presence_monitor.set_defense_posture(posture)
	# Propagar a policy (Regla 5 — exterior escalada en FORTIFIED)
	if _tavern_policy != null:
		_tavern_policy.set_defense_posture(posture)
	# Adaptar patrullas de perimeter guards
	_adapt_perimeter_patrols(posture, old_posture)


## Ajusta las patrullas de perimeter guards según postura.
##
## FORTIFIED → post fijo (patrol_points vacío) — máxima vigilancia, sin ronda.
##             El guardia mantiene posición cerca de la pared y no se distrae.
## NORMAL/GUARDED → restaura las patrullas originales cacheadas en spawn.
##
## Los interior_guard y door_guard no se tocan — solo perimeter.
func _adapt_perimeter_patrols(posture: int, old_posture: int) -> void:
	var sentinels: Array = get_tree().get_nodes_in_group("tavern_sentinel")
	for node: Variant in sentinels:
		if not (node is Sentinel and is_instance_valid(node)):
			continue
		var s := node as Sentinel
		if s.sentinel_role != "perimeter_guard":
			continue

		if posture == TavernDefensePosture.FORTIFIED:
			# Asegurar cache antes de limpiar (puede ser la primera vez que llega a FORTIFIED).
			if not _perimeter_patrol_cache.has(s) and not s.patrol_points.is_empty():
				_perimeter_patrol_cache[s] = s.patrol_points.duplicate()
			s.patrol_points = PackedVector2Array()
		elif old_posture == TavernDefensePosture.FORTIFIED:
			# Restaurar al salir de FORTIFIED.
			if _perimeter_patrol_cache.has(s):
				s.patrol_points = _perimeter_patrol_cache[s] as PackedVector2Array


## Resolver la posición world del TavernKeeper en runtime.
## Si el keeper todavía no está en escena, usa geometría fija del chunk.
func _get_tavern_keeper_pos() -> Vector2:
	var keepers := get_tree().get_nodes_in_group("tavern_keeper")
	if not keepers.is_empty():
		return (keepers[0] as Node2D).global_position
	# Fallback: tile del counter desde geometría del chunk
	var x0 := tavern_chunk.x * chunk_size + 4
	var y0 := tavern_chunk.y * chunk_size + 3
	return _tile_to_world(Vector2i(x0 + 6, y0 + 2))


## ── Entry point institucional para incidentes civiles de taberna ─────────────
## Este método es el punto de entrada del INCIDENTE, no del sanction.
## La ruta conceptual correcta es: incident → memory → policy → sanction.
## Hoy no hay director, así que el incidente se loguea y queda registrado
## para observabilidad. NO se llama direct_local_sanction() porque semánticamente
## eso salta memory y policy, que todavía no existen.
##
## En Paso 2: conectar TavernLocalMemory aquí primero, luego policy, luego director.
## _local_social_ports tiene los puertos listos para cuando lleguen esas piezas.
##
## Llamar desde: hurtbox del keeper, barrel interaction, wall damage callbacks,
##   BanditBehaviorLayer, futuros civiles, etc.
## Offenders: player, bandit/enemy, cualquier Node2D agente.
func report_tavern_incident(incident_type: String, payload: Dictionary = {}) -> void:
	var incident := _build_tavern_incident(incident_type, payload)
	if incident == null:
		Debug.log("authority", "[TAVERN] incident_type='%s' sin mapping — ignorado" % incident_type)
		return

	# La policy evalúa ANTES de registrar — así ve solo el historial previo,
	# no el incidente actual. El orden es relevante para escalaciones correctas.
	var directive: LocalAuthorityDirective = _tavern_policy.evaluate(incident)
	_tavern_memory.record(incident)
	Debug.log("authority", "[TAVERN] %s" % directive.describe())

	if directive.response_type == LocalAuthorityResponse.Response.RECORD_ONLY:
		return

	var offender_node: CharacterBody2D = payload.get("offender", null) as CharacterBody2D
	if offender_node == null or not is_instance_valid(offender_node):
		# Fallback solo cuando el ofensor era desconocido desde el principio (no enemy explícito).
		# Para incidentes de bandit/enemy el nodo ya viene en payload — si no llegó, no forzar player.
		var is_enemy_incident := incident_type in ["armed_intruder", "bandit_attack", "murder_in_tavern"]
		if not is_enemy_incident:
			var incident_pos: Vector2 = payload.get("pos", Vector2.ZERO)
			offender_node = _find_nearest_player(incident_pos)

	_tavern_director.dispatch(directive, offender_node)


## Construye un LocalCivilIncident a partir del tipo de incidente semántico
## y el payload del activador. Devuelve null si el tipo no tiene mapping.
func _build_tavern_incident(incident_type: String, payload: Dictionary) -> LocalCivilIncident:
	var C  := LocalCivilAuthorityConstants
	var offense: String   = ""
	var severity: float   = 0.0
	var victim_kind: String = C.VictimKind.CIVILIAN
	var zone: String      = C.ZONE_TAVERN_INTERIOR

	match incident_type:
		"assault_keeper":
			offense     = C.Offense.ASSAULT
			severity    = C.SEVERITY_SERIOUS
			victim_kind = C.VictimKind.AUTHORITY_MEMBER
		"assault_sentinel":
			offense     = C.Offense.ASSAULT
			severity    = C.SEVERITY_SERIOUS
			victim_kind = C.VictimKind.AUTHORITY_MEMBER
		"murder_in_tavern":
			offense     = C.Offense.MURDER
			severity    = C.SEVERITY_CRITICAL
		"wall_damaged":
			offense     = C.Offense.VANDALISM
			severity    = C.SEVERITY_MODERATE
			victim_kind = C.VictimKind.TAVERN_PROPERTY
		"wall_damaged_exterior":
			# Daño estructural desde el perímetro — ataque externo a la taberna.
			# Más grave que interior (agresión directa desde fuera).
			# zone=PERIMETER → director asigna perimeter_guard. Policy puede escalar a CALL_BACKUP.
			offense     = C.Offense.VANDALISM
			severity    = C.SEVERITY_SERIOUS
			victim_kind = C.VictimKind.TAVERN_PROPERTY
			zone        = C.ZONE_TAVERN_PERIMETER
		"barrel_opened":
			offense     = C.Offense.TRESPASS
			severity    = C.SEVERITY_MINOR
			victim_kind = C.VictimKind.TAVERN_PROPERTY
		"barrel_destroyed":
			offense     = C.Offense.VANDALISM
			severity    = C.SEVERITY_MODERATE
			victim_kind = C.VictimKind.TAVERN_PROPERTY
		"armed_intruder":
			offense     = C.Offense.WEAPON_THREAT
			severity    = C.SEVERITY_SERIOUS
		"trespass":
			offense     = C.Offense.TRESPASS
			severity    = C.SEVERITY_MINOR
			victim_kind = C.VictimKind.TAVERN_PROPERTY
			zone        = C.ZONE_TAVERN_GROUNDS
		"bandit_attack":
			offense     = C.Offense.ASSAULT
			severity    = C.SEVERITY_SERIOUS
		"disturbance":
			offense     = C.Offense.DISTURBANCE
			severity    = C.SEVERITY_MINOR
			zone        = C.ZONE_TAVERN_INTERIOR
		"suspicious_presence":
			# Bandit/enemy en el perímetro exterior por tiempo prolongado.
			# Emitido por TavernPresenceMonitor. Respuesta base: WARN.
			# Policy escala si el actor tiene historial previo en la taberna.
			offense     = C.Offense.DISTURBANCE
			severity    = C.SEVERITY_MINOR
			zone        = C.ZONE_TAVERN_PERIMETER
		"loitering":
			# Actor rondando la zona de puerta/acceso más de lo aceptable.
			# Emitido por TavernPresenceMonitor. Respuesta base: WARN.
			offense     = C.Offense.TRESPASS
			severity    = C.SEVERITY_MINOR
			zone        = C.ZONE_TAVERN_GROUNDS
		_:
			return null

	var offender_node: Node2D = payload.get("offender", null) as Node2D
	var offender_id: String   = ""
	var offender_pos: Vector2 = payload.get("pos", Vector2.ZERO)

	if offender_node != null and is_instance_valid(offender_node):
		offender_id = offender_node.name
		if offender_pos == Vector2.ZERO:
			offender_pos = offender_node.global_position

	return LocalCivilIncidentFactory.create(
		"tavern_main",
		offense,
		severity,
		offender_pos,
		offender_id,
		victim_kind,
		zone,
		[],            # witnesses — Fase 3
		incident_type, # source_tag
		{}
	)


## Devuelve el nodo TavernKeeper activo, o null si no está en escena.
func _get_tavern_keeper_node() -> TavernKeeper:
	var keepers := get_tree().get_nodes_in_group("tavern_keeper")
	if not keepers.is_empty() and keepers[0] is TavernKeeper:
		return keepers[0] as TavernKeeper
	return null


## Cablea el reporter de incidentes y el service_check de memoria en el keeper activo.
## También registra contenedores en zona de taberna para activadores barrel_*.
func _wire_keeper_incident_reporter() -> void:
	var keeper := _get_tavern_keeper_node()
	if keeper != null:
		keeper.set_incident_reporter(Callable(self, "report_tavern_incident"))
		keeper.set_service_check(Callable(_tavern_memory, "is_service_denied"))
	_register_tavern_containers()


## Encuentra contenedores (barriles, cofres) dentro de los bounds de la taberna
## y les registra el reporter de incidentes civiles.
## Solo registra los que existan en este momento (post-spawn del chunk de taberna).
## TODO(Paso 4): registrar también contenedores colocados por el player después del spawn.
func _register_tavern_containers() -> void:
	var bounds: Rect2 = get_tavern_inner_bounds_world()
	if bounds.size == Vector2.ZERO:
		return
	var search_bounds := bounds.grow(32.0)
	var reporter := Callable(self, "report_tavern_incident")
	var registered: int = 0
	for group_name in ["chest", "interactable"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or not (node is Node2D):
				continue
			if not (node as Node2D).global_position.is_zero_approx() \
					and not search_bounds.has_point((node as Node2D).global_position):
				continue
			if node.has_method("set_civil_incident_reporter"):
				node.call("set_civil_incident_reporter", reporter)
				registered += 1
	Debug.log("authority", "[TAVERN] containers registrados con reporter: %d" % registered)


## Encuentra el jugador más cercano a una posición world. Devuelve null si no hay.
func _find_nearest_player(world_pos: Vector2) -> CharacterBody2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	if world_pos == Vector2.ZERO or players.size() == 1:
		return players[0] as CharacterBody2D
	var nearest: CharacterBody2D = null
	var nearest_dist: float = INF
	for p in players:
		if p == null or not (p is Node2D):
			continue
		var d: float = (p as Node2D).global_position.distance_to(world_pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p as CharacterBody2D
	return nearest


func _on_wall_hit_activity(tile_pos: Vector2i) -> void:
	if _wall_refresh_queue != null:
		var cpos: Vector2i = _tile_to_chunk(tile_pos)
		_wall_refresh_queue.record_activity(cpos)
	# Comparar en coordenadas de tile (enteras) para evitar ambigüedad de float.
	# has_point en world-space fallaba en tiles exactamente en el borde del bounds
	# (norte/este dependiendo del offset de map_to_local).
	var keepers := get_tree().get_nodes_in_group("tavern_keeper")
	if keepers.is_empty():
		return
	var keeper := keepers[0]
	var inner_min: Vector2i = keeper.get("tavern_inner_min")
	var inner_max: Vector2i = keeper.get("tavern_inner_max")
	var world_pos: Vector2 = _tile_to_world(tile_pos)
	# Determinar si el golpe viene desde adentro o afuera usando la posición del
	# player, NO el tile de la pared. Las paredes están exactamente en los bordes
	# de inner_min/inner_max, así que clasificar por tile da resultados inconsistentes
	# (el tile de la pared queda excluido por las condiciones estrictas).
	var player_tile: Vector2i = _world_to_tile(_get_player_world_pos())
	var player_inside: bool = player_tile.x >= inner_min.x and player_tile.x <= inner_max.x \
						  and player_tile.y >= inner_min.y and player_tile.y <= inner_max.y
	if player_inside:
		report_tavern_incident("wall_damaged", {"pos": world_pos})
	else:
		# Perímetro: 10 tiles (320px) de margen en todas las direcciones
		const PERIM: int = 10
		var in_perim: bool = tile_pos.x >= inner_min.x - PERIM \
						 and tile_pos.x <= inner_max.x + PERIM \
						 and tile_pos.y >= inner_min.y - PERIM \
						 and tile_pos.y <= inner_max.y + PERIM
		if in_perim:
			report_tavern_incident("wall_damaged_exterior", {"pos": world_pos})

func _get_player_world_pos() -> Vector2:
	if player == null:
		return Vector2.ZERO
	return player.global_position

func _on_wall_drop_for_intel(tile_pos: Vector2i, _item_id: String, _amount: int) -> void:
	if _settlement_intel != null:
		_settlement_intel.mark_base_scan_dirty_near(_tile_to_world(tile_pos))
	_player_territory_dirty = true

func _on_placement_completed(_item_id: String, tile_pos: Vector2i) -> void:
	var world_pos: Vector2 = _tile_to_world(tile_pos)
	Debug.log("placement_react", "placement_completed item=%s tile=%s world=%s" % [
		_item_id, str(tile_pos), str(world_pos)])
	# Throttle mínimo para evitar duplicados por input/drag en el mismo frame.
	var now: float = RunClock.now()
	if now - _placement_react_last_event_at < _PLACEMENT_REACT_EVENT_MIN_INTERVAL:
		return
	_placement_react_last_event_at = now
	_trigger_placement_react(world_pos)


func _trigger_placement_react(target_pos: Vector2) -> void:
	var all_ids: Array = BanditGroupMemory.get_all_group_ids()
	Debug.log("placement_react", "--- placement react target=%s groups_total=%d ---" % [
		str(target_pos), all_ids.size()])
	if all_ids.is_empty():
		Debug.log("placement_react", "  SKIP: no hay grupos registrados en BanditGroupMemory")
		return
	var queued: int = 0
	var dispatched_groups: int = 0
	var pending_groups: int = 0
	var total_redirected: int = 0
	for gid in all_ids:
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		var faction_id: String = String(g.get("faction_id", ""))
		var eradicated: bool = bool(g.get("eradicated", false))
		var members: Array = g.get("member_ids", []) as Array
		if eradicated:
			continue
		if members.is_empty():
			continue
		if not _is_group_hostile_for_structure_assault(g):
			Debug.log("placement_react", "  group=%s faction=%s skipped (not hostile for structures)" % [
				gid, faction_id])
			continue
		var leader_id: String = String(g.get("leader_id", ""))
		if leader_id == "" and not members.is_empty():
			leader_id = String(members[0])
		if leader_id == "":
			continue
		BanditGroupMemory.record_interest(gid, target_pos, "structure_placed")
		BanditGroupMemory.set_placement_react_lock(gid, _PLACEMENT_REACT_INTENT_LOCK_SECONDS)
		BanditGroupMemory.update_intent(gid, "raiding")
		var enqueued_now: bool = false
		if not RaidQueue.has_structure_assault_for_group(gid):
			RaidQueue.enqueue_structure_assault(
				faction_id,
				gid,
				leader_id,
				target_pos,
				"placed_structure",
				_PLACEMENT_REACT_STRUCT_ASSAULT_SQUAD
			)
			queued += 1
			enqueued_now = true
		var redirected: int = 0
		if _bandit_behavior_layer != null:
			redirected = _bandit_behavior_layer.dispatch_group_to_target(
				gid,
				target_pos,
				_PLACEMENT_REACT_STRUCT_ASSAULT_SQUAD
			)
		if redirected > 0:
			dispatched_groups += 1
			total_redirected += redirected
		else:
			pending_groups += 1
		Debug.log("placement_react", "  group=%s faction=%s redirected=%d queued_now=%s" % [
			gid, faction_id, redirected, str(enqueued_now)])
	Debug.log("placement_react", "  SUMMARY queued=%d dispatched_groups=%d pending_groups=%d redirected_total=%d" % [
		queued, dispatched_groups, pending_groups, total_redirected])


func _is_group_hostile_for_structure_assault(group_data: Dictionary) -> bool:
	var faction_id: String = String(group_data.get("faction_id", ""))
	if faction_id == "":
		return false
	if _is_faction_baseline_hostile_to_player(faction_id):
		return true
	var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
	return profile.can_attack_punitively \
		or profile.can_probe_walls \
		or profile.can_damage_workbenches \
		or profile.can_damage_storage \
		or profile.can_damage_walls \
		or profile.can_raid_base


func _is_faction_baseline_hostile_to_player(faction_id: String) -> bool:
	var fid: String = faction_id.strip_edges().to_lower()
	if fid == "":
		return false
	var aliases: Array[String] = [fid]
	if fid.ends_with("s"):
		var singular: String = fid.substr(0, fid.length() - 1)
		if singular != "":
			aliases.append(singular)
	else:
		aliases.append(fid + "s")
	for raw_alias in aliases:
		var alias: String = String(raw_alias)
		var faction_data: Dictionary = FactionSystem.get_faction(alias)
		if faction_data.is_empty():
			continue
		if float(faction_data.get("hostility_to_player", 0.0)) > 0.0:
			return true
	# Fallback defensivo para facciones hostiles no registradas aún en FactionSystem.
	return fid.find("bandit") >= 0 or fid.find("goblin") >= 0 or fid.find("raider") >= 0


func _on_entity_died(uid: String, kind: String, _pos: Vector2, _killer: Node) -> void:
	if kind == "enemy" and uid != "":
		npc_simulator.on_entity_died(uid)
	# Incidente institucional: muerte dentro de la taberna.
	# Aplica sea quien sea el muerto (player, keeper, NPC, enemy) y el killer (player, bandit, null).
	var tavern_bounds: Rect2 = get_tavern_inner_bounds_world()
	if tavern_bounds.size != Vector2.ZERO and tavern_bounds.grow(16.0).has_point(_pos):
		var killer_node: CharacterBody2D = _killer as CharacterBody2D
		report_tavern_incident("murder_in_tavern", {"offender": killer_node, "pos": _pos})


# Pinta grass en GroundTileMap fuera del límite del mundo para cubrir el gris del viewport.
## PlayerTerritoryMap — territorio del jugador
func _tick_player_territory() -> void:
	if not _player_territory_dirty or _player_territory == null or _settlement_intel == null:
		return
	_player_territory_dirty = false
	var wb_nodes: Array = _world_spatial_index.get_all_runtime_nodes(WorldSpatialIndex.KIND_WORKBENCH) if _world_spatial_index != null else get_tree().get_nodes_in_group("workbench")
	var bases: Array[Dictionary] = _settlement_intel.get_detected_bases_near(Vector2.ZERO, 999999.0)
	_player_territory.rebuild(wb_nodes, bases)

func is_in_player_territory(world_pos: Vector2) -> bool:
	if _player_territory == null:
		return false
	return _player_territory.is_in_player_territory(world_pos)

func get_player_territory_zones() -> Array[Dictionary]:
	if _player_territory == null:
		return []
	return _player_territory.get_zones()


# ---------------------------------------------------------------------------
# Build restrictions — validador registrado en PlacementSystem
# ---------------------------------------------------------------------------
# La política concreta vive en WorldTerritoryPolicy; world.gd solo registra el
# validator y delega la decisión.
#
# Integración futura:
# _local_social_ports es el punto de composición para TavernLocalMemory /
# TavernAuthorityPolicy / TavernResponseDirector. world.gd seguirá cableando
# módulos, no convirtiéndose en fuente de verdad social.
func _validate_placement_restrictions(tile_pos: Vector2i) -> bool:
	if _world_territory_policy == null:
		return true
	return _world_territory_policy.validate_placement(tile_pos, tavern_chunk)


## SettlementIntel — interest marker facade
func record_interest_event(kind: String, world_pos: Vector2, metadata: Dictionary = {}) -> void:
	if _settlement_intel != null:
		_settlement_intel.record_interest_event(kind, world_pos, metadata)
	if _world_territory_policy != null:
		_world_territory_policy.record_interest_event(kind, world_pos)
	# Estructura colocada o workbench → reconstruir mapa de territorio del jugador
	if kind == "workbench" or kind == "structure_placed":
		_player_territory_dirty = true

func _on_bandit_territory_intrusion(group_entry: Dictionary, world_pos: Vector2, kind: String) -> void:
	if _bandit_behavior_layer == null:
		return
	_bandit_behavior_layer.notify_territory_reaction(
		String(group_entry.get("faction_id", "")),
		String(group_entry.get("group_id", "")),
		world_pos,
		kind)

func get_interest_markers_near(world_pos: Vector2, radius: float) -> Array[Dictionary]:
	if _settlement_intel == null:
		return []
	return _settlement_intel.get_interest_markers_near(world_pos, radius)

func rescan_workbench_markers() -> void:
	if _settlement_intel != null:
		_settlement_intel.rescan_workbench_markers()
	_player_territory_dirty = true

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


func get_debug_snapshot() -> Dictionary:
	if _world_sim_telemetry == null:
		return {"enabled": false}
	return _world_sim_telemetry.get_debug_snapshot()


func dump_debug_summary() -> String:
	if _world_sim_telemetry == null:
		return "WORLD SIM\n- telemetry: unavailable"
	return _world_sim_telemetry.dump_debug_summary()


func build_overlay_lines() -> PackedStringArray:
	if _world_sim_telemetry == null:
		return PackedStringArray()
	return _world_sim_telemetry.build_overlay_lines()


func _perform_world_save(_reason: String = "manual") -> void:
	SaveManager.save_world()
	_last_save_time_msec = Time.get_ticks_msec()
	_save_count += 1


func _get_world_maintenance_debug_snapshot() -> Dictionary:
	var loaded_count: int = loaded_chunks.size()
	var generated_count: int = pipeline.generated_chunks.size() if pipeline != null else 0
	var terrain_pending: int = pipeline.terrain_paint_center_ring0_pending if pipeline != null else 0
	var autosave_due: int = _cadence.lane_due(&"autosave") if _cadence != null else 0
	var last_save_age: float = -1.0
	if _last_save_time_msec >= 0:
		last_save_age = float(Time.get_ticks_msec() - _last_save_time_msec) / 1000.0
	return {
		"pending_tile_erases": _pending_tile_erases.size(),
		"loaded_chunks": loaded_count,
		"generated_chunks": generated_count,
		"terrain_paint_ring0_pending": terrain_pending,
		"spawn_queue": _spawn_queue.debug_dump() if _spawn_queue != null else {},
		"wall_refresh": _wall_refresh_queue.get_debug_snapshot() if _wall_refresh_queue != null else {},
		"autosave": {
			"interval": autosave_interval,
			"due": autosave_due,
			"save_count": _save_count,
			"last_save_age": snappedf(last_save_age, 0.01) if last_save_age >= 0.0 else -1.0,
		},
	}
