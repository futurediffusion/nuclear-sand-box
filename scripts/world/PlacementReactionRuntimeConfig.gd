extends Resource
class_name PlacementReactionRuntimeConfig

const DEFAULT_INTENT_LOCK_SECONDS: float = 90.0
const DEFAULT_STRUCT_ASSAULT_SQUAD_SIZE: int = 3
const DEFAULT_EVENT_MIN_INTERVAL: float = 0.20
const DEFAULT_DEBUG_MAX_EVENTS: int = 96

@export var default_radius: float = 640.0
@export var radius_by_item_id: Dictionary = {}
@export var max_groups_per_event: int = 3
@export var min_score: float = 0.40
@export var high_priority_score: float = 0.72
@export var struct_assault_squad_size: int = DEFAULT_STRUCT_ASSAULT_SQUAD_SIZE
@export var high_priority_squad_size_override: int = 4
@export var blocking_checks_budget: int = 4
@export var lock_min_relevance_delta: float = 0.12
@export var lock_min_distance_delta_px: float = 96.0
@export var wall_assault_global_mode: bool = true
@export var wall_assault_radius: float = 12000.0
@export var wall_assault_min_score: float = 0.18
@export var event_min_interval: float = DEFAULT_EVENT_MIN_INTERVAL
@export var intent_lock_seconds: float = DEFAULT_INTENT_LOCK_SECONDS
@export var debug_max_events: int = DEFAULT_DEBUG_MAX_EVENTS

func build_setup_payload(
	threat_assessment_system: ThreatAssessmentSystem,
	group_intent_system: BanditIntentSystem,
	enemy_node_provider: Callable,
	world_spatial_index: WorldSpatialIndex,
	tile_to_world: Callable,
	nearest_workbench_world_pos: Callable,
	drop_hotspots_provider: Callable
) -> Dictionary:
	return {
		"threat_assessment_system": threat_assessment_system,
		"group_intent_system": group_intent_system,
		"enemy_node_provider": enemy_node_provider,
		"world_spatial_index": world_spatial_index,
		"tile_to_world": tile_to_world,
		"nearest_workbench_world_pos": nearest_workbench_world_pos,
		"drop_hotspots_provider": drop_hotspots_provider,
		"default_radius": default_radius,
		"radius_by_item_id": radius_by_item_id.duplicate(true),
		"max_groups_per_event": max_groups_per_event,
		"min_score": min_score,
		"high_priority_score": high_priority_score,
		"struct_assault_squad_size": struct_assault_squad_size,
		"high_priority_squad_size_override": high_priority_squad_size_override,
		"blocking_checks_budget": blocking_checks_budget,
		"lock_min_relevance_delta": lock_min_relevance_delta,
		"lock_min_distance_delta_px": lock_min_distance_delta_px,
		"wall_assault_global_mode": wall_assault_global_mode,
		"wall_assault_radius": wall_assault_radius,
		"wall_assault_min_score": wall_assault_min_score,
		"event_min_interval": event_min_interval,
		"intent_lock_seconds": intent_lock_seconds,
		"debug_max_events": debug_max_events,
	}
