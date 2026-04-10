extends Node2D

# Responsibility boundary:
# world.gd is the top-level orchestrator/facade for world subsystems. It wires
# systems together and exposes public gameplay hooks, but social policy and
# other subsystem internals should live in dedicated services instead of here.
# Ownership constitution reference: docs/architecture/ownership/world-bootstrap-orchestration.md

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

@export_group("Camp Config")
@export var camp_members_per_camp: int = 10

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
var _settlement_intel: SettlementIntel
var _player_territory: TerritoryProjection
var _bandit_behavior_layer: BanditBehaviorLayer
var _world_spatial_index: WorldSpatialIndex
var _spatial_index_projection: SpatialIndexProjection
var _world_territory_policy: WorldTerritoryPolicy
var _local_social_ports: LocalSocialAuthorityPorts
var _tavern_security_runtime: TavernSecurityRuntime
var _resource_repopulator: ResourceRepopulator
var _occlusion_controller: OcclusionController
var _day_night_controller
var _speech_bubble_manager: WorldSpeechBubbleManager
var _player_wall_system: PlayerWallSystem
var _building_repository: BuildingRepository
var _building_system: BuildingSystem
var _building_tilemap_projection: BuildingTilemapProjection
var _wall_collider_projection: WallColliderProjection
var _threat_assessment_system: ThreatAssessmentSystem
var _group_intent_system: BanditIntentSystem
var _placement_reaction_system: PlacementReactionSystem
var _wall_feedback: WallFeedback
var _structural_wall_persistence: StructuralWallPersistence
var _sandbox_structure_repository: SandboxStructureRepository
var _chunk_wall_collider_cache: ChunkWallColliderCache
var _wall_refresh_queue: WallRefreshQueue
var _cadence: WorldCadenceCoordinator
var _chunk_lifecycle_coordinator: WorldChunkLifecycleCoordinator
var _drop_pressure_service: WorldDropPressureService
var _drop_compaction_service: WorldDropCompactionService
var _world_sim_telemetry: WorldSimTelemetry
var _sandbox_diagnostics: SandboxDiagnostics
var _projection_rebuild_coordinator: WorldProjectionRebuildCoordinator
var _maintenance_pulse_runtime: WorldMaintenancePulseRuntime
var _gameplay_command_dispatcher: GameplayCommandDispatcher
var _domain_event_dispatcher: SandboxDomainEventDispatcher
var _save_count: int = 0
var _last_save_time_msec: int = -1
var _wall_coordinate_transform_port: WorldCoordinateTransformContract
var _wall_chunk_dirty_notifier_port: WorldChunkDirtyNotifierContract
var _wall_projection_refresh_port: WorldProjectionRefreshContract

# Placement reaction tuning/config lives in PlacementReactionRuntimeConfig.
# world.gd only composes and forwards the config payload to PlacementReactionSystem.
## Empty filter = query all player placeables from WorldSpatialIndex persistent cache.
const _PLAYER_RAID_PLACEABLE_ITEM_IDS: Array[String] = []
@export_group("Placement Reaction")
@export var placement_reaction_config: PlacementReactionRuntimeConfig
@export_group("")

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
const BuildingSystemScript := preload("res://scripts/domain/building/BuildingSystem.gd")
const WorldSaveBuildingRepositoryScript := preload("res://scripts/persistence/save/WorldSaveBuildingRepository.gd")
const BuildingTilemapProjectionScript := preload("res://scripts/projections/tilemap/BuildingTilemapProjection.gd")
const WallColliderProjectionScript := preload("res://scripts/projections/collision/WallColliderProjection.gd")
const SpatialIndexProjectionScript := preload("res://scripts/projections/index/SpatialIndexProjection.gd")
const TerritoryProjectionScript := preload("res://scripts/projections/territory/TerritoryProjection.gd")
const ThreatAssessmentSystemScript := preload("res://scripts/domain/factions/ThreatAssessmentSystem.gd")
const BanditIntentSystemScript := preload("res://scripts/domain/factions/BanditIntentSystem.gd")
const PlacementReactionSystemScript := preload("res://scripts/domain/factions/PlacementReactionSystem.gd")
const BuildingEventDtoScript := preload("res://scripts/domain/contracts/BuildingEventDto.gd")
const SnapshotRebuildNotificationDtoScript := preload("res://scripts/domain/contracts/SnapshotRebuildNotificationDto.gd")
const StructuralWallPersistenceScript := preload("res://scripts/world/StructuralWallPersistence.gd")
const SandboxStructureRepositoryScript := preload("res://scripts/world/SandboxStructureRepository.gd")
const WallFeedbackScript := preload("res://scripts/world/WallFeedback.gd")
const ChunkWallColliderCacheScript := preload("res://scripts/world/ChunkWallColliderCache.gd")
const WallRefreshQueueScript := preload("res://scripts/world/WallRefreshQueue.gd")
const WorldCadenceCoordinatorScript := preload("res://scripts/world/WorldCadenceCoordinator.gd")
const WorldSimTelemetryScript := preload("res://scripts/world/WorldSimTelemetry.gd")
const SandboxDiagnosticsScript := preload("res://scripts/world/SandboxDiagnostics.gd")
const PlacementPerfTelemetryScript := preload("res://scripts/world/PlacementPerfTelemetry.gd")
const DayNightControllerScript := preload("res://scripts/world/DayNightController.gd")
const GameplayCommandDispatcherScript := preload("res://scripts/runtime/world/GameplayCommandDispatcher.gd")
const TavernSecurityRuntimeScript := preload("res://scripts/runtime/world/TavernSecurityRuntime.gd")
const SandboxDomainEventDispatcherScript := preload("res://scripts/runtime/world/SandboxDomainEventDispatcher.gd")
const WorldChunkLifecycleCoordinatorScript := preload("res://scripts/runtime/world/WorldChunkLifecycleCoordinator.gd")
const WorldDropPressureServiceScript := preload("res://scripts/runtime/world/WorldDropPressureService.gd")
const WorldDropCompactionServiceScript := preload("res://scripts/runtime/world/WorldDropCompactionService.gd")
const WorldProjectionRebuildCoordinatorScript := preload("res://scripts/runtime/world/WorldProjectionRebuildCoordinator.gd")
const WorldMaintenancePulseRuntimeScript := preload("res://scripts/runtime/world/WorldMaintenancePulseRuntime.gd")
const PlacementReactionRuntimeConfigScript := preload("res://scripts/world/PlacementReactionRuntimeConfig.gd")
const WorldCoordinateTransformCallableAdapterScript := preload("res://scripts/world/contracts/WorldCoordinateTransformCallableAdapter.gd")
const WorldChunkDirtyNotifierCallableAdapterScript := preload("res://scripts/world/contracts/WorldChunkDirtyNotifierCallableAdapter.gd")
const WorldProjectionRefreshCallableAdapterScript := preload("res://scripts/world/contracts/WorldProjectionRefreshCallableAdapter.gd")
const LANE_SHORT_PULSE: StringName = &"short_pulse"
const LANE_MEDIUM_PULSE: StringName = &"medium_pulse"
const LANE_DIRECTOR_PULSE: StringName = &"director_pulse"
const LANE_CHUNK_PULSE: StringName = &"chunk_pulse"
const LANE_AUTOSAVE: StringName = &"autosave"
const LANE_SETTLEMENT_BASE_SCAN: StringName = &"settlement_base_scan"
const LANE_SETTLEMENT_WORKBENCH_SCAN: StringName = &"settlement_workbench_scan"
const LANE_OCCLUSION_PULSE: StringName = &"occlusion_pulse"
const LANE_RESOURCE_REPOP_PULSE: StringName = &"resource_repop_pulse"
const LANE_BANDIT_WORK_LOOP: StringName = &"bandit_work_loop"
const LANE_DROP_COMPACT_PULSE: StringName = &"drop_compact_pulse"
const TICK_DOMAIN_SIMULATION: StringName = &"simulation_tick"
const TICK_DOMAIN_AI_DECISION: StringName = &"ai_decision_tick"
const TICK_DOMAIN_EXECUTION_RUNTIME: StringName = &"execution_runtime_tick"
const TICK_DOMAIN_PROJECTION_REBUILD: StringName = &"projection_rebuild_tick"
const TICK_DOMAIN_PERSISTENCE: StringName = &"persistence_tick"
const TICK_DOMAIN_MAINTENANCE: StringName = &"maintenance_tick"
const OCCLUSION_INTERVAL_SEC: float = 0.10
const RESOURCE_REPOP_INTERVAL_SEC: float = 0.50
const BANDIT_WORK_LOOP_INTERVAL_SEC: float = 0.25
const DROP_COMPACT_INTERVAL_SEC: float = 0.40
const SHORT_PULSE_PHASE: float = 0.15
const MEDIUM_PULSE_PHASE: float = 0.42
const DIRECTOR_PULSE_PHASE: float = 0.67
const CHUNK_PULSE_PHASE: float = 0.68
const AUTOSAVE_PHASE: float = 0.31
const OCCLUSION_PHASE: float = 0.07
const RESOURCE_REPOP_PHASE: float = 0.53
const BANDIT_WORK_LOOP_PHASE: float = 0.24
const DROP_COMPACT_PHASE: float = 0.59
const BUDGET_WALL_REFRESH_PER_PULSE: int = 1
const BUDGET_TILE_ERASE_PER_PULSE: int = 2
const BUDGET_OCCLUSION_MATERIALS_PER_PULSE: int = 8
const BUDGET_RESOURCE_REPOP_OPS_PER_PULSE: int = 8
const BUDGET_BANDIT_WORK_TICKS_PER_PULSE: int = 24
const BUDGET_DROP_COMPACT_PULSES_PER_FRAME: int = 1
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

@export_group("Drop Compaction")
@export var drop_compaction_enabled: bool = true
@export var drop_compaction_radius_px: float = 44.0
@export var drop_compaction_max_nodes_inspected: int = 96
@export var drop_compaction_max_merges_per_exec: int = 16
@export var drop_compaction_hotspot_ttl_sec: float = 12.0
@export var drop_compaction_hotspot_radius_px: float = 220.0
@export var drop_compaction_min_cluster_size: int = 3
@export_group("Drop Pressure")
@export var drop_pressure_high_item_drop_count: int = 140
@export var drop_pressure_critical_item_drop_count: int = 240
@export var drop_pressure_high_merge_radius_mult: float = 1.55
@export var drop_pressure_high_nodes_mult: float = 1.55
@export var drop_pressure_high_merges_mult: float = 1.80
@export var drop_pressure_critical_merge_radius_mult: float = 2.25
@export var drop_pressure_critical_nodes_mult: float = 2.00
@export var drop_pressure_critical_merges_mult: float = 2.40
@export var drop_pressure_high_orphan_ttl_sec: float = 25.0
@export_group("")

func _configure_world_cadence_lanes() -> void:
	if _cadence == null:
		return
	_cadence.configure_lane(LANE_SHORT_PULSE, 0.12, SHORT_PULSE_PHASE, WorldCadenceCoordinator.DEFAULT_MAX_CATCHUP, BUDGET_WALL_REFRESH_PER_PULSE + BUDGET_TILE_ERASE_PER_PULSE, TICK_DOMAIN_MAINTENANCE)
	_cadence.configure_lane(LANE_MEDIUM_PULSE, 0.50, MEDIUM_PULSE_PHASE, WorldCadenceCoordinator.DEFAULT_MAX_CATCHUP, -1, TICK_DOMAIN_PROJECTION_REBUILD)
	_cadence.configure_lane(LANE_DIRECTOR_PULSE, 0.12, DIRECTOR_PULSE_PHASE, WorldCadenceCoordinator.DEFAULT_MAX_CATCHUP, -1, TICK_DOMAIN_AI_DECISION)
	_cadence.configure_lane(LANE_CHUNK_PULSE, chunk_check_interval, CHUNK_PULSE_PHASE, WorldCadenceCoordinator.DEFAULT_MAX_CATCHUP, -1, TICK_DOMAIN_SIMULATION)
	_cadence.configure_lane(LANE_AUTOSAVE, autosave_interval, AUTOSAVE_PHASE, 1, -1, TICK_DOMAIN_PERSISTENCE)
	_cadence.configure_lane(LANE_SETTLEMENT_BASE_SCAN, SettlementIntel.BASE_RESCAN_INTERVAL, SettlementIntel.BASE_SCAN_PHASE_RATIO, 1, -1, TICK_DOMAIN_AI_DECISION)
	_cadence.configure_lane(LANE_SETTLEMENT_WORKBENCH_SCAN, SettlementIntel.WORKBENCH_RESCAN_INTERVAL, SettlementIntel.WORKBENCH_SCAN_PHASE_RATIO, 1, -1, TICK_DOMAIN_AI_DECISION)
	_cadence.configure_lane(LANE_OCCLUSION_PULSE, OCCLUSION_INTERVAL_SEC, OCCLUSION_PHASE, 1, BUDGET_OCCLUSION_MATERIALS_PER_PULSE, TICK_DOMAIN_EXECUTION_RUNTIME)
	_cadence.configure_lane(LANE_RESOURCE_REPOP_PULSE, RESOURCE_REPOP_INTERVAL_SEC, RESOURCE_REPOP_PHASE, 1, BUDGET_RESOURCE_REPOP_OPS_PER_PULSE, TICK_DOMAIN_SIMULATION)
	# Bandit work loop cadence:
	# - 0.25s keeps mining/pickup/return/deposit transitions perceptibly continuous.
	# - Budget counts behavior ticks per pulse (not physics ops).
	# - Heavy scan/pathfinding remains LOD-gated inside BanditBehaviorLayer.
	_cadence.configure_lane(LANE_BANDIT_WORK_LOOP, BANDIT_WORK_LOOP_INTERVAL_SEC, BANDIT_WORK_LOOP_PHASE, 1, BUDGET_BANDIT_WORK_TICKS_PER_PULSE, TICK_DOMAIN_AI_DECISION)
	_cadence.configure_lane(LANE_DROP_COMPACT_PULSE, DROP_COMPACT_INTERVAL_SEC, DROP_COMPACT_PHASE, 1, BUDGET_DROP_COMPACT_PULSES_PER_FRAME, TICK_DOMAIN_MAINTENANCE)

func _ensure_placement_reaction_config() -> PlacementReactionRuntimeConfig:
	if placement_reaction_config == null:
		placement_reaction_config = PlacementReactionRuntimeConfigScript.new()
	return placement_reaction_config

func _setup_building_module() -> void:
	_building_repository = WorldSaveBuildingRepositoryScript.new()
	_building_system = BuildingSystemScript.new()
	_building_tilemap_projection = BuildingTilemapProjectionScript.new()
	_threat_assessment_system = ThreatAssessmentSystemScript.new()
	_group_intent_system = BanditIntentSystemScript.new()
	_group_intent_system.setup({
		"group_memory": BanditGroupMemory,
		"now_provider": Callable(RunClock, "now"),
	})
	_placement_reaction_system = PlacementReactionSystemScript.new()
	var placement_config: PlacementReactionRuntimeConfig = _ensure_placement_reaction_config()
	var placement_setup_payload: Dictionary = placement_config.build_setup_payload(
		_threat_assessment_system,
		_group_intent_system,
		Callable(self, "_get_enemy_node_for_react"),
		_world_spatial_index,
		Callable(self, "_tile_to_world"),
		Callable(self, "find_nearest_player_workbench_world_pos"),
		Callable(self, "_get_drop_compaction_hotspots")
	)
	placement_setup_payload["domain_event_dispatcher"] = _domain_event_dispatcher
	_placement_reaction_system.setup(placement_setup_payload)
	_building_tilemap_projection.setup({
		"walls_tilemap": walls_tilemap,
		"walls_map_layer": WALLS_MAP_LAYER,
		"wall_terrain_set": WALL_TERRAIN_SET,
		"wall_terrain": WALL_TERRAIN,
		"src_walls": SRC_WALLS,
		"wall_reconnect_offsets": WALL_RECONNECT_OFFSETS,
		"player_wall_fallback_atlas": PLAYER_WALL_FALLBACK_ATLAS,
		"player_wall_isolated_atlas": PLAYER_WALL_ISOLATED_ATLAS,
		"player_wall_fallback_alt": PLAYER_WALL_FALLBACK_ALT,
		"is_valid_world_tile": Callable(self, "_is_valid_world_tile"),
		"has_player_wall_state": Callable(self, "_has_player_wall_state"),
		"has_structural_wall_state": Callable(self, "_has_structural_wall_state"),
	})
	_wall_collider_projection = WallColliderProjectionScript.new()
	_wall_collider_projection.setup({
		"is_valid_world_tile": Callable(self, "_is_valid_world_tile"),
		"tile_to_chunk": Callable(self, "_tile_to_chunk"),
		"tile_to_world": Callable(self, "_tile_to_world"),
		"wall_reconnect_offsets": WALL_RECONNECT_OFFSETS,
		"projection_refresh_port": _wall_projection_refresh_port,
		"chunk_dirty_notifier_port": _wall_chunk_dirty_notifier_port,
		"wall_refresh_queue": _wall_refresh_queue,
		"loaded_chunks": loaded_chunks,
		"mark_base_scan_dirty_near": Callable(self, "_mark_settlement_base_scan_dirty_from_projection"),
		"mark_player_territory_dirty": Callable(self, "_mark_player_territory_dirty_from_projection"),
	})

func _ready() -> void:
	_wall_refresh_queue = WallRefreshQueueScript.new()
	_cadence = WorldCadenceCoordinatorScript.new()
	# WorldCadenceCoordinator governs shared world pulses only: cross-system
	# maintenance, chunk/autosave work, and directors that coordinate multiple
	# systems. Specialized inner loops can still keep local clocks when their
	# timing is inherently private/incremental.
	_configure_world_cadence_lanes()
	_update_drop_pressure_snapshot()
	_domain_event_dispatcher = SandboxDomainEventDispatcherScript.new()
	_domain_event_dispatcher.setup({"trace_limit": 192})
	_register_domain_event_consumers()
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
	_structural_wall_persistence = StructuralWallPersistenceScript.new()
	_structural_wall_persistence.setup({
		"chunk_save": chunk_save,
		"walls_map_layer": WALLS_MAP_LAYER,
		"structural_wall_source": -1,
		"structural_wall_default_hp": structural_wall_default_hp,
	})
	_sandbox_structure_repository = SandboxStructureRepositoryScript.new()
	_sandbox_structure_repository.setup({
		"structural_wall_persistence": _structural_wall_persistence,
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
	_wall_coordinate_transform_port = WorldCoordinateTransformCallableAdapterScript.new()
	_wall_coordinate_transform_port.setup({
		"world_to_tile": Callable(self, "_world_to_tile"),
		"tile_to_world": Callable(self, "_tile_to_world"),
		"tile_to_chunk": Callable(self, "_tile_to_chunk"),
	})
	_wall_chunk_dirty_notifier_port = WorldChunkDirtyNotifierCallableAdapterScript.new()
	_wall_chunk_dirty_notifier_port.setup({
		"mark_chunk_walls_dirty": Callable(self, "mark_chunk_walls_dirty"),
	})
	_wall_projection_refresh_port = WorldProjectionRefreshCallableAdapterScript.new()
	_wall_projection_refresh_port.setup({
		"mark_chunk_walls_dirty_and_refresh_for_tiles": Callable(self, "_mark_walls_dirty_and_refresh_for_tiles"),
	})
	_setup_building_module()
	# Nota de migración: world.gd no define audio de walls; PlayerWallSystem resuelve defaults/overrides internos.
	_player_wall_system.setup({
		"owner": self,
		"feedback": _wall_feedback,
		"sound_panel_getter": Callable(self, "_get_sound_panel_for_walls"),
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
		"coordinate_transform_port": _wall_coordinate_transform_port,
		"chunk_dirty_notifier_port": _wall_chunk_dirty_notifier_port,
		"projection_refresh_port": _wall_projection_refresh_port,
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
		"building_repository": _building_repository,
		"building_system": _building_system,
		"building_tilemap_projection": _building_tilemap_projection,
		"wall_collider_projection": _wall_collider_projection,
		"building_collider_refresh_projection": _wall_collider_projection,
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

	_occlusion_controller = OcclusionController.new()
	_occlusion_controller.name = "OcclusionController"
	add_child(_occlusion_controller)
	if _occlusion_controller != null:
		_occlusion_controller.configure_cadence(_cadence != null)

	_day_night_controller = DayNightControllerScript.new()
	_day_night_controller.name = "DayNightController"
	add_child(_day_night_controller)
	if _day_night_controller != null:
		_day_night_controller.add_to_group("global_subsystem")
		_day_night_controller.add_to_group("day_night_controller")
		_day_night_controller.initialize_overlay()
		# SaveManager.load_world_save() ya pudo restaurar WorldTime.elapsed; sincronizar
		# aquí evita un frame inicial con look diurno incorrecto al cargar de noche.
		_day_night_controller.sync_to_time_in_day(WorldTime.get_time_in_day())

	@warning_ignore("integer_division")
	tavern_chunk = _tile_to_chunk(Vector2i(width / 2, height / 2))
	spawn_tile = get_tavern_center_tile(tavern_chunk)

	var spawn_world: Vector2 = _tile_to_world(spawn_tile)
	# Siempre spawnear en el centro de la taberna al iniciar.
	# El save restaura chunks/inventario/mundo pero no la posición del jugador,
	# ya que la posición guardada puede ser exterior al anillo de cliffs o en
	# un área peligrosa. El jugador siempre parte desde la taberna.
	if player:
		player.global_position = spawn_world
	current_player_chunk = world_to_chunk(spawn_world)

	# Create subsystems before wiring them together
	npc_simulator = NpcSimulator.new()
	npc_simulator.name = "NpcSimulator"
	npc_simulator.camp_members_per_camp = camp_members_per_camp
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
	_chunk_lifecycle_coordinator = WorldChunkLifecycleCoordinatorScript.new()
	_chunk_lifecycle_coordinator.setup({
		"pipeline": pipeline,
		"entity_coordinator": entity_coordinator,
		"chunk_generator": chunk_generator,
		"vegetation_root": _vegetation_root,
		"loaded_chunks": loaded_chunks,
		"ground_terrain_painted_chunks": _ground_terrain_painted_chunks,
		"chunk_occupied_tiles": chunk_occupied_tiles,
		"chunk_size": chunk_size,
		"active_radius": active_radius,
		"width": width,
		"height": height,
		"debug_log": func(channel: String, msg: String) -> void: Debug.log(channel, msg),
		"debug_check_tile_alignment": Callable(self, "_debug_check_tile_alignment"),
		"debug_check_player_chunk": Callable(self, "_debug_check_player_chunk"),
		"is_chunk_in_active_window": Callable(self, "_is_chunk_in_active_window"),
		"on_unload_chunk": Callable(self, "unload_chunk"),
	})

	_maintenance_pulse_runtime = WorldMaintenancePulseRuntimeScript.new()
	_maintenance_pulse_runtime.setup({
		"chunk_lifecycle_coordinator": _chunk_lifecycle_coordinator,
		"wall_refresh_queue": _wall_refresh_queue,
		"loaded_chunks": loaded_chunks,
		"ensure_chunk_wall_collision": Callable(self, "_ensure_chunk_wall_collision"),
		"cadence": _cadence,
		"lane_short_pulse": LANE_SHORT_PULSE,
		"wall_refresh_budget_per_pulse": BUDGET_WALL_REFRESH_PER_PULSE,
		"tile_erase_budget_per_pulse": BUDGET_TILE_ERASE_PER_PULSE,
	})

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
	_spatial_index_projection = SpatialIndexProjectionScript.new()
	_spatial_index_projection.setup({
		"chunk_size": chunk_size,
	})
	_projection_rebuild_coordinator = WorldProjectionRebuildCoordinatorScript.new()
	_projection_rebuild_coordinator.setup({
		"domain_event_dispatcher": _domain_event_dispatcher,
		"building_tilemap_projection": _building_tilemap_projection,
		"wall_collider_projection": _wall_collider_projection,
		"spatial_index_projection": _spatial_index_projection,
		"sandbox_structure_repository": _sandbox_structure_repository,
		"building_repository": _building_repository,
		"loaded_chunks": loaded_chunks,
		"request_player_territory_rebuild_cb": Callable(self, "_request_player_territory_rebuild_internal"),
		"tick_player_territory_cb": Callable(self, "_tick_player_territory"),
	})
	_world_spatial_index.setup({
		"world_to_tile": Callable(self, "_world_to_tile"),
		"tile_to_world": Callable(self, "_tile_to_world"),
		"chunk_size": chunk_size,
		"placeables_projection": _spatial_index_projection,
	})
	_drop_pressure_service = WorldDropPressureServiceScript.new()
	_drop_pressure_service.setup({
		"world_spatial_index": _world_spatial_index,
		"loot_system": LootSystem,
		"high_item_drop_count": drop_pressure_high_item_drop_count,
		"critical_item_drop_count": drop_pressure_critical_item_drop_count,
		"high_orphan_ttl_sec": drop_pressure_high_orphan_ttl_sec,
		"now_msec_provider": Callable(Time, "get_ticks_msec"),
	})
	_drop_compaction_service = WorldDropCompactionServiceScript.new()
	_drop_compaction_service.setup({
		"world_spatial_index": _world_spatial_index,
		"drop_pressure_service": _drop_pressure_service,
		"world_to_tile": Callable(self, "_world_to_tile"),
		"tile_to_world": Callable(self, "_tile_to_world"),
		"chunk_size": chunk_size,
		"drop_compaction_enabled": drop_compaction_enabled,
		"drop_compaction_radius_px": drop_compaction_radius_px,
		"drop_compaction_max_nodes_inspected": drop_compaction_max_nodes_inspected,
		"drop_compaction_max_merges_per_exec": drop_compaction_max_merges_per_exec,
		"drop_compaction_hotspot_ttl_sec": drop_compaction_hotspot_ttl_sec,
		"drop_compaction_hotspot_radius_px": drop_compaction_hotspot_radius_px,
		"drop_compaction_min_cluster_size": drop_compaction_min_cluster_size,
		"drop_pressure_high_merge_radius_mult": drop_pressure_high_merge_radius_mult,
		"drop_pressure_high_nodes_mult": drop_pressure_high_nodes_mult,
		"drop_pressure_high_merges_mult": drop_pressure_high_merges_mult,
		"drop_pressure_critical_merge_radius_mult": drop_pressure_critical_merge_radius_mult,
		"drop_pressure_critical_nodes_mult": drop_pressure_critical_nodes_mult,
		"drop_pressure_critical_merges_mult": drop_pressure_critical_merges_mult,
		"now_msec_provider": Callable(Time, "get_ticks_msec"),
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
	_resource_repopulator.configure_cadence(RESOURCE_REPOP_INTERVAL_SEC)

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
		if not _player_wall_system.building_events_emitted.is_connected(_on_building_events_emitted):
			_player_wall_system.building_events_emitted.connect(_on_building_events_emitted)

	WorldSave.wall_tile_blocker_fn = _has_wall_tile_between
	WorldSave.wall_tile_occupancy_fn = _has_wall_tile_at_world_pos

	_settlement_intel = SettlementIntelScript.new()
	_settlement_intel.setup({
		"cadence": _cadence,
		"world_to_tile":    Callable(self, "_world_to_tile"),
		"tile_to_world":    Callable(self, "_tile_to_world"),
		"player_pos_getter": Callable(self, "_get_player_world_pos"),
		"world_spatial_index": _world_spatial_index,
	})
	_player_territory = TerritoryProjectionScript.new()
	_request_player_territory_rebuild("startup")
	_tavern_security_runtime = TavernSecurityRuntimeScript.new()
	_tavern_security_runtime.setup({
		"world_node": self,
		"entity_root": _entity_root,
		"sentinel_scene": sentinel_scene,
		"tavern_chunk": tavern_chunk,
		"chunk_size": chunk_size,
		"tile_to_world": Callable(self, "_tile_to_world"),
		"get_tavern_exit_world_pos": Callable(self, "get_tavern_exit_world_pos"),
		"get_tavern_inner_bounds_world": Callable(self, "get_tavern_inner_bounds_world"),
		"report_tavern_incident": Callable(self, "report_tavern_incident"),
	})
	var tavern_memory: TavernLocalMemory = _tavern_security_runtime.get_tavern_memory()
	var tavern_policy: TavernAuthorityPolicy = _tavern_security_runtime.get_tavern_policy()
	var tavern_director: TavernSanctionDirector = _tavern_security_runtime.get_tavern_director()
	_local_social_ports = LocalSocialAuthorityPortsScript.new()
	_local_social_ports.setup({
		"local_authority_policy":  Callable(tavern_policy,  "evaluate"),
		"local_memory_source":     Callable(tavern_memory,  "get_snapshot"),
		"local_sanction_director": Callable(tavern_director, "dispatch"),
	})
	_world_territory_policy = WorldTerritoryPolicy.new()
	_world_territory_policy.setup({
		"tile_to_world": Callable(self, "_tile_to_world"),
		"get_tavern_center_tile": Callable(self, "get_tavern_center_tile"),
		"react_to_bandit_territory_intrusion": Callable(self, "_on_bandit_territory_intrusion"),
		"local_social_ports": _local_social_ports,
	})

	_gameplay_command_dispatcher = GameplayCommandDispatcherScript.new()
	_gameplay_command_dispatcher.setup({
		"player_wall_system": _player_wall_system,
		"settlement_intel": _settlement_intel,
		"world_territory_policy": _world_territory_policy,
		"tavern_memory": tavern_memory,
		"tavern_policy": tavern_policy,
		"tavern_director": tavern_director,
		"register_drop_compaction_hotspot": Callable(self, "_register_drop_compaction_hotspot"),
		"mark_player_territory_dirty": func() -> void: _request_player_territory_rebuild("gameplay_dispatcher"),
		"find_nearest_player": Callable(self, "_find_nearest_player"),
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
	_sandbox_diagnostics = SandboxDiagnosticsScript.new()
	_sandbox_diagnostics.setup({
		"world": self,
		"save_manager": SaveManager,
		"sandbox_structure_repository": _sandbox_structure_repository,
		"bandit_behavior_layer": _bandit_behavior_layer,
		"player_wall_system": _player_wall_system,
		"wall_collider_projection": _wall_collider_projection,
		"territory_projection": _player_territory,
		"spatial_index_projection": _spatial_index_projection,
		"settlement_intel": _settlement_intel,
		"snapshot_rebuild_report_cb": Callable(self, "get_snapshot_rebuild_report"),
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

	# Eager projection rebuild from WorldSave data before async chunk generation starts.
	# Without this, the player sees the tavern with no floor/walls until the full
	# chunk pipeline completes (several frames). Reads directly from WorldSave.chunks
	# to avoid depending on loaded_chunks (populated only after chunk generation).
	if _had_save and _building_tilemap_projection != null and _wall_collider_projection != null \
			and _sandbox_structure_repository != null:
		var eager_snapshot: Array[Dictionary] = []
		for key_raw in WorldSave.chunks.keys():
			var cp: Vector2i = WorldSave.chunk_pos_from_key(String(key_raw))
			if cp == WorldSave.INVALID_CHUNK_POS:
				continue
			eager_snapshot.append_array(_sandbox_structure_repository.list_structures_in_chunk(cp, false))
		if not eager_snapshot.is_empty():
			_building_tilemap_projection.apply_snapshot(eager_snapshot)
			_wall_collider_projection.rebuild_from_state(eager_snapshot)

	await update_chunks(current_player_chunk)
	if _had_save:
		_domain_event_dispatcher.publish("snapshot_loaded", {
			"source": "save_manager",
			"world_has_save": true,
			"load_report": SaveManager.get_last_load_pipeline_snapshot(),
		})

func _register_domain_event_consumers() -> void:
	if _domain_event_dispatcher == null:
		return
	_domain_event_dispatcher.subscribe("structure_placed", "placement_reaction", Callable(self, "_on_structure_domain_event"))
	_domain_event_dispatcher.subscribe("structure_damaged", "placement_reaction", Callable(self, "_on_structure_domain_event"))
	_domain_event_dispatcher.subscribe("structure_removed", "placement_reaction", Callable(self, "_on_structure_domain_event"))
	_domain_event_dispatcher.subscribe("placement_completed", "placement_reaction", Callable(self, "_on_structure_domain_event"))
	_domain_event_dispatcher.subscribe("snapshot_loaded", "world_projection_rebuild", Callable(self, "_on_snapshot_loaded_domain_event"))
	_domain_event_dispatcher.subscribe("projection_rebuild_requested", "domain_event_trace", Callable(self, "_on_projection_rebuild_requested_domain_event"))
	_domain_event_dispatcher.subscribe("projection_rebuild_completed", "domain_event_trace", Callable(self, "_on_generic_domain_event_trace"))
	_domain_event_dispatcher.subscribe("threat_assessed", "domain_event_trace", Callable(self, "_on_generic_domain_event_trace"))
	_domain_event_dispatcher.subscribe("intent_published", "domain_event_trace", Callable(self, "_on_generic_domain_event_trace"))

func _on_structure_domain_event(event_record: Dictionary) -> void:
	if _placement_reaction_system == null:
		return
	var payload: Dictionary = event_record.get("payload", {}) as Dictionary
	if payload.is_empty():
		return
	_placement_reaction_system.handle_building_event(payload)

func _on_snapshot_loaded_domain_event(_event_record: Dictionary) -> void:
	if _projection_rebuild_coordinator == null:
		return
	_projection_rebuild_coordinator.rebuild_explicit_projections_after_snapshot_load()

func _on_projection_rebuild_requested_domain_event(event_record: Dictionary) -> void:
	var payload: Dictionary = event_record.get("payload", {}) as Dictionary
	var projection: String = String(payload.get("projection", ""))
	if projection.is_empty():
		return
	Debug.log("world", "domain_event projection_rebuild_requested projection=%s reason=%s" % [
		projection,
		String(payload.get("reason", "")),
	])

func _on_generic_domain_event_trace(event_record: Dictionary) -> void:
	Debug.log("world", "domain_event type=%s seq=%s" % [
		String(event_record.get("type", "")),
		str(event_record.get("seq", -1)),
	])


func _on_chunk_stage_completed(chunk_pos: Vector2i, stage: String) -> void:
	if stage == "tiles":
		if _player_wall_system != null:
			_player_wall_system.apply_saved_walls_for_chunk(chunk_pos)
	elif _tavern_security_runtime != null:
		_tavern_security_runtime.on_chunk_stage_completed(chunk_pos, stage)


## Engancha el keeper al sistema institucional en cuanto su job es completado.
## El keeper se instancia después de entities_enqueued, así que no puede cablearse antes.
func _on_spawn_job_completed(job: Dictionary, node: Node) -> void:
	if _tavern_security_runtime != null:
		_tavern_security_runtime.on_spawn_job_completed(job, node)

func get_snapshot_rebuild_report() -> Dictionary:
	if _projection_rebuild_coordinator == null:
		return SnapshotRebuildNotificationDtoScript.build({})
	return _projection_rebuild_coordinator.get_snapshot_rebuild_report()

func get_domain_event_trace(limit: int = 64) -> Array[Dictionary]:
	if _domain_event_dispatcher == null:
		return []
	return _domain_event_dispatcher.get_recent_events(limit)

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

func _register_drop_compaction_hotspot(world_pos: Vector2, score: int = 1) -> void:
	if _drop_compaction_service == null:
		return
	_drop_compaction_service.register_hotspot(world_pos, score)


func _update_drop_pressure_snapshot() -> void:
	if _drop_pressure_service == null:
		return
	_drop_pressure_service.update_snapshot()


func _compact_item_drops_once() -> int:
	if _drop_compaction_service == null:
		return 0
	return _drop_compaction_service.execute_compaction_pass()

func _process(delta: float) -> void:
	_process_frame_domains(delta)
	_dispatch_runtime_pulses()
	pipeline.process(delta)
	if entity_coordinator != null and player:
		entity_coordinator.set_player_pos(player.global_position)
	if _day_night_controller != null and WorldTime != null:
		_day_night_controller.update_for_time_in_day(WorldTime.get_time_in_day(), delta)
	_update_cliff_occlusion()
	_process_chunk_perf_debug(delta)
	if _world_sim_telemetry != null:
		_world_sim_telemetry.tick(delta)
	if _cadence != null and _cadence.consume_lane(LANE_AUTOSAVE) > 0:
		_perform_world_save("autosave")
	if _cadence != null and _cadence.consume_lane(LANE_CHUNK_PULSE) <= 0:
		return
	if not player:
		return
	_maybe_update_player_chunk_from_position(player.global_position)

func _process_frame_domains(delta: float) -> void:
	if _cadence != null:
		_cadence.advance(delta)
	if _settlement_intel != null:
		_settlement_intel.process(delta)
	if _tavern_security_runtime != null:
		_tavern_security_runtime.tick(delta)

func _dispatch_runtime_pulses() -> void:
	_dispatch_medium_pulse()
	_dispatch_short_pulse()
	_dispatch_lane_occlusion_pulse()
	_dispatch_lane_resource_repop_pulse()
	_dispatch_lane_drop_compact_pulse()

func _dispatch_medium_pulse() -> void:
	var pulses: int = _consume_lane_or_default(LANE_MEDIUM_PULSE, 1)
	for _pulse in pulses:
		_update_drop_pressure_snapshot()
		_tick_player_territory()

func _dispatch_short_pulse() -> void:
	if _maintenance_pulse_runtime == null:
		return
	_maintenance_pulse_runtime.execute_short_pulse(_consume_lane_or_default(LANE_SHORT_PULSE, 1))

func _dispatch_lane_occlusion_pulse() -> void:
	if _occlusion_controller == null:
		return
	var pulses: int = _consume_lane_or_default(LANE_OCCLUSION_PULSE, 0)
	if pulses <= 0:
		return
	var updates: int = _occlusion_controller.tick_from_cadence(pulses, BUDGET_OCCLUSION_MATERIALS_PER_PULSE)
	_report_lane_work(LANE_OCCLUSION_PULSE, updates, BUDGET_OCCLUSION_MATERIALS_PER_PULSE * pulses)

func _dispatch_lane_resource_repop_pulse() -> void:
	if _resource_repopulator == null:
		return
	var pulses: int = _consume_lane_or_default(LANE_RESOURCE_REPOP_PULSE, 1)
	if pulses <= 0:
		return
	var ops: int = _resource_repopulator.tick_from_cadence(pulses)
	_report_lane_work(LANE_RESOURCE_REPOP_PULSE, ops, BUDGET_RESOURCE_REPOP_OPS_PER_PULSE * pulses)

func _dispatch_lane_drop_compact_pulse() -> void:
	var pulses: int = _consume_lane_or_default(LANE_DROP_COMPACT_PULSE, 0)
	if pulses <= 0:
		return
	var compact_ops: int = 0
	for _pulse in pulses:
		compact_ops += _compact_item_drops_once()
	_report_lane_work(LANE_DROP_COMPACT_PULSE, compact_ops, BUDGET_DROP_COMPACT_PULSES_PER_FRAME * pulses)

func _consume_lane_or_default(lane: StringName, fallback: int) -> int:
	if _cadence == null:
		return fallback
	return _cadence.consume_lane(lane)

func _report_lane_work(lane: StringName, work_units: int, budget_units: int) -> void:
	if _cadence != null:
		_cadence.report_lane_work(lane, work_units, budget_units)

func _maybe_update_player_chunk_from_position(player_world_pos: Vector2) -> void:
	var pchunk := world_to_chunk(player_world_pos)
	if pchunk == current_player_chunk:
		return
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
	if _chunk_lifecycle_coordinator == null:
		return
	var player_pos: Vector2 = player.global_position if player != null else Vector2.INF
	await _chunk_lifecycle_coordinator.update_chunks(center, player_pos)


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
	_ground_terrain_painted_chunks.erase(chunk_pos)
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

func _has_wall_tile_at_world_pos(world_pos: Vector2) -> bool:
	if walls_tilemap == null:
		return false
	var tile_pos: Vector2i = walls_tilemap.local_to_map(walls_tilemap.to_local(world_pos))
	return walls_tilemap.get_cell_source_id(WALLS_MAP_LAYER, tile_pos) == SRC_WALLS

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
func _has_player_wall_state(tile_pos: Vector2i) -> bool:
	return _player_wall_system != null and _player_wall_system.has_player_wall_state(tile_pos)

func _has_structural_wall_state(tile_pos: Vector2i) -> bool:
	return _player_wall_system != null and _player_wall_system.has_structural_wall_state(tile_pos)

## Legacy façade-only API: external callers may still use world.has_method()/world.call() for wall commands.
func can_place_player_wall_at_tile(tile_pos: Vector2i) -> bool:
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.can_place_player_wall_at_tile(tile_pos)

func place_player_wall_at_tile(tile_pos: Vector2i, hp_override: int = -1) -> bool:
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.place_player_wall_at_tile(tile_pos, hp_override)

func damage_player_wall_from_contact(hit_pos: Vector2, hit_normal: Vector2, amount: int = 1) -> bool:
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.damage_player_wall_from_contact(hit_pos, hit_normal, amount)

func damage_player_wall_near_world_pos(world_pos: Vector2, amount: int = 1) -> bool:
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.damage_player_wall_near_world_pos(world_pos, amount)

func damage_player_wall_at_world_pos(world_pos: Vector2, amount: int = 1) -> bool:
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.damage_player_wall_at_world_pos(world_pos, amount)

func damage_player_wall_in_circle(world_center: Vector2, world_radius: float, amount: int = 1) -> bool:
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.damage_player_wall_in_circle(world_center, world_radius, amount)

func find_nearest_player_wall_world_pos(world_pos: Vector2, radius: float) -> Vector2:
	if _player_wall_system == null:
		return Vector2(-1.0, -1.0)
	return _player_wall_system.find_nearest_player_wall_world_pos(world_pos, radius)


func find_nearest_player_wall_world_pos_global(world_pos: Vector2, max_radius: float = -1.0) -> Vector2:
	if _player_wall_system == null:
		return Vector2(-1.0, -1.0)
	return _player_wall_system.find_nearest_player_wall_world_pos_global(world_pos, max_radius)


func find_player_wall_samples_world_pos(world_pos: Vector2, radius: float, max_points: int = 12,
		min_separation: float = 48.0) -> Array[Vector2]:
	if _player_wall_system == null:
		return []
	return _player_wall_system.find_player_wall_samples_world_pos(world_pos, radius, max_points, min_separation)

func find_nearest_player_workbench_world_pos(world_pos: Vector2, radius: float, query_ctx: Dictionary = {}) -> Vector2:
	return _find_nearest_player_placeable_world_pos_by_items(world_pos, radius, [BuildableCatalog.ID_WORKBENCH], query_ctx)

func find_nearest_player_storage_world_pos(world_pos: Vector2, radius: float, query_ctx: Dictionary = {}) -> Vector2:
	return _find_nearest_player_placeable_world_pos_by_items(world_pos, radius, [
		BuildableCatalog.ID_CHEST,
		BuildableCatalog.ID_BARREL,
	], query_ctx)


func find_nearest_player_placeable_world_pos(world_pos: Vector2, radius: float, query_ctx: Dictionary = {}) -> Vector2:
	return _find_nearest_player_placeable_world_pos_by_items(world_pos, radius, _PLAYER_RAID_PLACEABLE_ITEM_IDS, query_ctx)


func _find_nearest_player_placeable_world_pos_by_items(world_pos: Vector2, radius: float,
		item_ids: Array[String], query_ctx: Dictionary = {}) -> Vector2:
	if _world_spatial_index == null:
		return Vector2(-1.0, -1.0)
	var best_pos: Vector2 = Vector2(-1.0, -1.0)
	var best_dsq: float = radius * radius
	var entries: Array[Dictionary] = _world_spatial_index.get_placeables_by_item_ids_near(world_pos, radius, item_ids, query_ctx)
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
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.hit_wall_at_world_pos(world_pos, amount, radius, allow_structural_feedback)

func damage_player_wall_at_tile(tile_pos: Vector2i, amount: int = 1) -> bool:
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.damage_player_wall_at_tile(tile_pos, amount)

func remove_player_wall_at_tile(tile_pos: Vector2i, drop_item: bool = true) -> bool:
	return _gameplay_command_dispatcher != null and _gameplay_command_dispatcher.remove_player_wall_at_tile(tile_pos, drop_item)

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
	var t0_usec: int = Time.get_ticks_usec()
	var chunks_to_refresh: Dictionary = {}
	for tile_pos in tile_positions:
		var cpos: Vector2i = _tile_to_chunk(tile_pos)
		mark_chunk_walls_dirty(cpos.x, cpos.y)
		chunks_to_refresh[cpos] = true
	var chunks_enqueued: int = 0
	for cpos in chunks_to_refresh.keys():
		var chunk_pos: Vector2i = cpos as Vector2i
		if _wall_refresh_queue != null:
			_wall_refresh_queue.record_activity(chunk_pos)
			if loaded_chunks.has(chunk_pos):
				_wall_refresh_queue.enqueue(chunk_pos)
				chunks_enqueued += 1
	if _settlement_intel != null and not tile_positions.is_empty():
		_settlement_intel.mark_base_scan_dirty_near(_tile_to_world(tile_positions[0]))
	_request_player_territory_rebuild("legacy_wall_refresh")
	PlacementPerfTelemetryScript.record_stage(
		"world_mark_walls_dirty_and_refresh_for_tiles",
		Time.get_ticks_usec() - t0_usec,
		{
			"tiles_affected": tile_positions.size(),
			"chunks_touched": chunks_to_refresh.size(),
			"chunks_enqueued": chunks_enqueued,
		},
		"collider"
	)

func _mark_settlement_base_scan_dirty_from_projection(world_pos: Vector2) -> void:
	if _settlement_intel != null:
		_settlement_intel.mark_base_scan_dirty_near(world_pos)

func _mark_player_territory_dirty_from_projection() -> void:
	_request_player_territory_rebuild("wall_collider_projection")

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
		@warning_ignore("integer_division")
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
		var inner_min_world := _tile_to_world(inner_min)
		var inner_max_world := _tile_to_world(inner_max + Vector2i(1, 1))
		return Rect2(inner_min_world, inner_max_world - inner_min_world)
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
	if _tavern_security_runtime != null:
		_tavern_security_runtime.ensure_tavern_sentinels_spawned()

func _find_nearest_player(world_pos: Vector2) -> CharacterBody2D:
	# Runtime hot-path:
	# - Single-player sandbox keeps the local `player` reference as authority.
	# - Group scan is kept only as legacy/setup fallback when `player` is missing.
	if player != null and is_instance_valid(player):
		return player as CharacterBody2D
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
	_register_drop_compaction_hotspot(_tile_to_world(tile_pos), 2)
	if _tavern_security_runtime != null:
		_tavern_security_runtime.on_wall_hit_activity(tile_pos, _get_player_world_pos())

func _get_player_world_pos() -> Vector2:
	if player == null:
		return Vector2.ZERO
	return player.global_position

func _on_wall_drop_for_intel(tile_pos: Vector2i, _item_id: String, _amount: int) -> void:
	if _settlement_intel != null:
		_settlement_intel.mark_base_scan_dirty_near(_tile_to_world(tile_pos))
	_register_drop_compaction_hotspot(_tile_to_world(tile_pos), maxi(1, _amount))
	_request_player_territory_rebuild("wall_drop")

func _on_placement_completed(_item_id: String, tile_pos: Vector2i) -> void:
	var world_pos: Vector2 = _tile_to_world(tile_pos)
	Debug.log("placement_react", "placement_completed item=%s tile=%s world=%s" % [
		_item_id, str(tile_pos), str(world_pos)])
	if _domain_event_dispatcher != null:
		_domain_event_dispatcher.publish("placement_completed",
			BuildingEventDtoScript.placement_completed(_item_id, tile_pos, world_pos, "placement_system"))

func _on_building_events_emitted(events: Array[Dictionary]) -> void:
	if _domain_event_dispatcher == null:
		return
	for event_data in events:
		if not (event_data is Dictionary):
			continue
		var event_payload: Dictionary = event_data as Dictionary
		var event_type: String = String(event_payload.get("type", event_payload.get("event_type", "")))
		if event_type.is_empty():
			continue
		_domain_event_dispatcher.publish(event_type, event_payload)


func reset_placement_react_debug_metrics() -> void:
	if _placement_reaction_system != null:
		_placement_reaction_system.reset_debug_metrics()


func get_placement_react_debug_snapshot() -> Dictionary:
	if _placement_reaction_system != null:
		return _placement_reaction_system.get_debug_snapshot()
	return {}


func _get_enemy_node_for_react(enemy_id: String) -> Node:
	if npc_simulator == null:
		return null
	return npc_simulator.get_enemy_node(enemy_id)


func _get_drop_compaction_hotspots() -> Array[Dictionary]:
	if _drop_compaction_service == null:
		return []
	return _drop_compaction_service.get_hotspots()


func _on_entity_died(uid: String, kind: String, _pos: Vector2, _killer: Node) -> void:
	if kind == "enemy" and uid != "":
		npc_simulator.on_entity_died(uid)
	if _tavern_security_runtime != null:
		_tavern_security_runtime.on_entity_died(_pos, _killer)


# Pinta grass en GroundTileMap fuera del límite del mundo para cubrir el gris del viewport.
## TerritoryProjection — territorio del jugador (derived read-model)
func _tick_player_territory() -> void:
	if _player_territory == null or _settlement_intel == null:
		return
	if _projection_rebuild_coordinator == null:
		return
	if not _projection_rebuild_coordinator.consume_player_territory_rebuild_request():
		return
	_player_territory.apply_inputs(_collect_player_territory_projection_inputs())

func _collect_player_territory_projection_inputs() -> Dictionary:
	var wb_anchors: Array = _collect_player_workbench_projection_anchors()
	var bases: Array[Dictionary] = _settlement_intel.get_detected_bases_snapshot()
	return {
		"workbench_anchors": wb_anchors,
		"detected_bases": bases,
		"source": "world_tick_player_territory_explicit_sources",
	}

func _collect_player_workbench_projection_anchors() -> Array:
	# Domain-first input: canonical placeables snapshot (via derived index cache).
	if _world_spatial_index != null:
		return _world_spatial_index.get_all_placeables_by_item_id("workbench")
	# Compatibility bridge (persistence-safe): if runtime index cache is unavailable,
	# read directly from canonical WorldSave placeable entries instead of scene nodes.
	# This avoids promoting live scene groups as persistence truth.
	var anchors: Array = []
	for chunk_raw in WorldSave.placed_entities_by_chunk.values():
		if not (chunk_raw is Dictionary):
			continue
		for entry_raw in (chunk_raw as Dictionary).values():
			if not (entry_raw is Dictionary):
				continue
			var entry: Dictionary = entry_raw as Dictionary
			if String(entry.get("item_id", "")).strip_edges() != "workbench":
				continue
			anchors.append(entry.duplicate(true))
	return anchors

func _request_player_territory_rebuild(_reason: String) -> void:
	_request_player_territory_rebuild_internal(_reason)

func _request_player_territory_rebuild_internal(reason: String) -> void:
	if _projection_rebuild_coordinator == null:
		return
	_projection_rebuild_coordinator.request_player_territory_rebuild(reason)

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
## Legacy façade-only API: preserve compatibility while GameplayCommandDispatcher owns behavior.
func record_interest_event(kind: String, world_pos: Vector2, metadata: Dictionary = {}) -> void:
	if _gameplay_command_dispatcher == null:
		return
	_gameplay_command_dispatcher.record_interest_event(kind, world_pos, metadata)

func report_tavern_incident(incident_type: String, payload: Dictionary = {}) -> void:
	if _gameplay_command_dispatcher == null:
		return
	_gameplay_command_dispatcher.report_tavern_incident(incident_type, payload)

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
	if _gameplay_command_dispatcher == null:
		return
	_gameplay_command_dispatcher.rescan_workbench_markers()

func mark_interest_scan_dirty() -> void:
	if _gameplay_command_dispatcher == null:
		return
	_gameplay_command_dispatcher.mark_interest_scan_dirty()

## SettlementIntel — base detection facade
## Legacy façade-only API: read-only forwarding to SettlementIntel for existing integration points.
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
	var snapshot: Dictionary = _world_sim_telemetry.get_debug_snapshot()
	snapshot["day_night_cycle"] = _day_night_controller.get_debug_snapshot() if _day_night_controller != null else {}
	snapshot["snapshot_rebuild_report"] = get_snapshot_rebuild_report()
	snapshot["sandbox_diagnostics"] = get_world_diagnostics_snapshot()
	return snapshot


func get_world_diagnostics_snapshot() -> Dictionary:
	if _sandbox_diagnostics == null:
		return {}
	return _sandbox_diagnostics.get_world_health_snapshot()


func get_drop_pressure_snapshot() -> Dictionary:
	if _drop_pressure_service == null:
		return {}
	return _drop_pressure_service.get_snapshot()


func dump_debug_summary() -> String:
	if _world_sim_telemetry == null:
		return "WORLD SIM\n- telemetry: unavailable"
	var summary: String = _world_sim_telemetry.dump_debug_summary()
	if _day_night_controller != null and _day_night_controller.has_method("get_debug_snapshot"):
		var cycle_snapshot: Dictionary = _day_night_controller.get_debug_snapshot()
		var cycle_phase: String = String(cycle_snapshot.get("cycle_phase", "unknown"))
		var time_in_day: float = float(cycle_snapshot.get("time_in_day", -1.0))
		var target_night: float = float(cycle_snapshot.get("target_night_amount", 0.0))
		var current_night: float = float(cycle_snapshot.get("current_night_amount", 0.0))
		summary += "\n- cycle: phase=%s t=%.3f target_night=%.3f current_night=%.3f" % [
			cycle_phase,
			time_in_day,
			target_night,
			current_night,
		]
	return summary


func build_overlay_lines() -> PackedStringArray:
	if _world_sim_telemetry == null:
		return PackedStringArray()
	var lines: PackedStringArray = _world_sim_telemetry.build_overlay_lines()
	if _day_night_controller != null and _day_night_controller.has_method("get_debug_snapshot"):
		var cycle_snapshot: Dictionary = _day_night_controller.get_debug_snapshot()
		var cycle_phase: String = String(cycle_snapshot.get("cycle_phase", "unknown"))
		var time_in_day: float = float(cycle_snapshot.get("time_in_day", -1.0))
		var target_night: float = float(cycle_snapshot.get("target_night_amount", 0.0))
		var current_night: float = float(cycle_snapshot.get("current_night_amount", 0.0))
		lines.append("Cycle %s t=%.3f n=%.3f->%.3f" % [
			cycle_phase,
			time_in_day,
			current_night,
			target_night,
		])
	return lines


func _perform_world_save(_reason: String = "manual") -> void:
	SaveManager.save_world()
	_last_save_time_msec = Time.get_ticks_msec()
	_save_count += 1


func _get_world_maintenance_debug_snapshot() -> Dictionary:
	var loaded_count: int = loaded_chunks.size()
	var generated_count: int = pipeline.generated_chunks.size() if pipeline != null else 0
	var terrain_pending: int = pipeline.terrain_paint_center_ring0_pending if pipeline != null else 0
	var autosave_due: int = _cadence.lane_due(LANE_AUTOSAVE) if _cadence != null else 0
	var last_save_age: float = -1.0
	var drop_compaction_metrics: Dictionary = _drop_compaction_service.get_metrics_snapshot() if _drop_compaction_service != null else {}
	var maintenance_snapshot: Dictionary = _maintenance_pulse_runtime.get_debug_snapshot() if _maintenance_pulse_runtime != null else {}
	if _last_save_time_msec >= 0:
		last_save_age = float(Time.get_ticks_msec() - _last_save_time_msec) / 1000.0
	return {
		"pending_tile_erases": int(maintenance_snapshot.get("pending_tile_erases", 0)),
		"loaded_chunks": loaded_count,
		"generated_chunks": generated_count,
		"terrain_paint_ring0_pending": terrain_pending,
		"day_night_cycle": _day_night_controller.get_debug_snapshot() if _day_night_controller != null else {},
		"spawn_queue": _spawn_queue.debug_dump() if _spawn_queue != null else {},
		"wall_refresh": maintenance_snapshot.get("wall_refresh", {}) as Dictionary,
		"autosave": {
			"interval": autosave_interval,
			"due": autosave_due,
			"save_count": _save_count,
			"last_save_age": snappedf(last_save_age, 0.01) if last_save_age >= 0.0 else -1.0,
		},
		"drop_compaction": {
			"enabled": drop_compaction_enabled,
			"merged_drop_events": int(drop_compaction_metrics.get("merged_drop_events", 0)),
			"spawn_metrics": LootSystem.get_drop_spawn_metrics() if LootSystem != null and LootSystem.has_method("get_drop_spawn_metrics") else {},
			"hotspots": int(drop_compaction_metrics.get("hotspots", 0)),
			"radius_px": float(drop_compaction_metrics.get("radius_px", drop_compaction_radius_px)),
			"max_nodes_inspected": int(drop_compaction_metrics.get("max_nodes_inspected", drop_compaction_max_nodes_inspected)),
			"max_merges_per_exec": int(drop_compaction_metrics.get("max_merges_per_exec", drop_compaction_max_merges_per_exec)),
			"pressure": get_drop_pressure_snapshot(),
		},
		"lane_inventory": {
			"occlusion_controller": {"script": "scripts/world/OcclusionController.gd", "lane": String(LANE_OCCLUSION_PULSE), "domain": String(TICK_DOMAIN_EXECUTION_RUNTIME), "interval": OCCLUSION_INTERVAL_SEC, "budget": BUDGET_OCCLUSION_MATERIALS_PER_PULSE},
			"resource_repopulator": {"script": "scripts/world/ResourceRepopulator.gd", "lane": String(LANE_RESOURCE_REPOP_PULSE), "domain": String(TICK_DOMAIN_SIMULATION), "interval": RESOURCE_REPOP_INTERVAL_SEC, "budget": BUDGET_RESOURCE_REPOP_OPS_PER_PULSE},
			"bandit_work_loop": {"script": "scripts/world/BanditBehaviorLayer.gd::_process", "lane": String(LANE_BANDIT_WORK_LOOP), "domain": String(TICK_DOMAIN_AI_DECISION), "interval": BANDIT_WORK_LOOP_INTERVAL_SEC, "budget": BUDGET_BANDIT_WORK_TICKS_PER_PULSE},
			"maintenance_short_pulse": {"script": "scripts/runtime/world/WorldMaintenancePulseRuntime.gd::execute_short_pulse", "lane": String(LANE_SHORT_PULSE), "domain": String(TICK_DOMAIN_MAINTENANCE), "interval": 0.12, "budget": BUDGET_WALL_REFRESH_PER_PULSE + BUDGET_TILE_ERASE_PER_PULSE},
			"drop_compaction": {"script": "scripts/runtime/world/WorldDropCompactionService.gd::execute_compaction_pass", "lane": String(LANE_DROP_COMPACT_PULSE), "domain": String(TICK_DOMAIN_MAINTENANCE), "interval": DROP_COMPACT_INTERVAL_SEC, "budget": BUDGET_DROP_COMPACT_PULSES_PER_FRAME},
		},
	}
