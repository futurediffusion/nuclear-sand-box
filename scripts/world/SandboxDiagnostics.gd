extends RefCounted
class_name SandboxDiagnostics

## Unified read-only diagnostics aggregation for sandbox world health.
## This layer composes existing telemetry snapshots without becoming an
## authoritative owner of gameplay state.

const SandboxDomainLanguageScript := preload("res://scripts/core/SandboxDomainLanguage.gd")

var _world: Node = null
var _save_manager: Node = null
var _sandbox_structure_repository: SandboxStructureRepository = null
var _bandit_behavior_layer: BanditBehaviorLayer = null
var _player_wall_system: PlayerWallSystem = null
var _wall_collider_projection: WallColliderProjection = null
var _territory_projection: TerritoryProjection = null
var _spatial_index_projection: SpatialIndexProjection = null
var _settlement_intel: SettlementIntel = null
var _snapshot_rebuild_report_cb: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_world = ctx.get("world")
	_save_manager = ctx.get("save_manager")
	_sandbox_structure_repository = ctx.get("sandbox_structure_repository") as SandboxStructureRepository
	_bandit_behavior_layer = ctx.get("bandit_behavior_layer") as BanditBehaviorLayer
	_player_wall_system = ctx.get("player_wall_system") as PlayerWallSystem
	_wall_collider_projection = ctx.get("wall_collider_projection") as WallColliderProjection
	_territory_projection = ctx.get("territory_projection") as TerritoryProjection
	_spatial_index_projection = ctx.get("spatial_index_projection") as SpatialIndexProjection
	_settlement_intel = ctx.get("settlement_intel") as SettlementIntel
	_snapshot_rebuild_report_cb = ctx.get("snapshot_rebuild_report_cb", Callable()) as Callable


func get_world_health_snapshot() -> Dictionary:
	var loaded_chunks: Dictionary = _read_loaded_chunks()
	var structure_counts: Dictionary = _count_structures_for_loaded_chunks(loaded_chunks)
	var structure_record_counts: Dictionary = structure_counts.duplicate(true)
	return {
		"domain_language": SandboxDomainLanguageScript.get_snapshot(),
		"persistence": _build_persistence_snapshot(),
		"projections": _build_projection_snapshot(),
		"bandit_pipeline": _build_bandit_pipeline_snapshot(),
		"compatibility_bridges": _build_compatibility_snapshot(),
		"world_runtime": {
			"loaded_chunk_count": loaded_chunks.size(),
			"structure_record_counts": structure_record_counts,
			# Legacy alias retained while diagnostics consumers migrate.
			"structure_counts": structure_counts,
			"detected_base_count": _read_detected_base_count(),
		},
	}


func _build_persistence_snapshot() -> Dictionary:
	var save_snapshot: Dictionary = {}
	var load_snapshot: Dictionary = {}
	if _save_manager != null:
		if _save_manager.has_method("get_last_save_pipeline_snapshot"):
			save_snapshot = _save_manager.call("get_last_save_pipeline_snapshot") as Dictionary
		if _save_manager.has_method("get_last_load_pipeline_snapshot"):
			load_snapshot = _save_manager.call("get_last_load_pipeline_snapshot") as Dictionary
	return {
		"save_path": String(_save_manager.get("SAVE_PATH") if _save_manager != null else ""),
		"last_save": save_snapshot,
		"last_load": load_snapshot,
		"last_load_source_path": String(load_snapshot.get("source", "")),
		"canonical_snapshot_path_used": bool(load_snapshot.get("canonical_snapshot_path_used", false)),
		"loaded_snapshot_version": int(load_snapshot.get("loaded_snapshot_version", 0)),
		"snapshot_target_version": int(load_snapshot.get("snapshot_target_version", 0)),
		"snapshot_migration_path": (load_snapshot.get("snapshot_migration_path", []) as Array).duplicate(true),
	}


func _build_projection_snapshot() -> Dictionary:
	var snapshot_rebuild_report: Dictionary = _snapshot_rebuild_report_cb.call() if _snapshot_rebuild_report_cb.is_valid() else {}
	var wall_collider_debug: Dictionary = _wall_collider_projection.get_debug_snapshot() if _wall_collider_projection != null else {}
	var territory_debug: Dictionary = _territory_projection.get_debug_snapshot() if _territory_projection != null else {}
	var spatial_debug: Dictionary = _spatial_index_projection.get_debug_snapshot() if _spatial_index_projection != null else {}
	return {
		"snapshot_rebuild_report": snapshot_rebuild_report,
		"rebuild_counts": {
			"snapshot_explicit_calls": int(snapshot_rebuild_report.get("calls", 0)),
			"wall_collider_apply_calls": int(wall_collider_debug.get("apply_calls", 0)),
			"territory_rebuild_calls": int(territory_debug.get("rebuild_calls", 0)),
			"spatial_full_rebuild_calls": int(spatial_debug.get("persistent_full_rebuild_calls", 0)),
		},
		"wall_collider": wall_collider_debug,
		"territory": territory_debug,
		"spatial": spatial_debug,
	}


func _build_bandit_pipeline_snapshot() -> Dictionary:
	if _bandit_behavior_layer == null or not _bandit_behavior_layer.has_method("get_pipeline_diagnostics_snapshot"):
		return {}
	return _bandit_behavior_layer.call("get_pipeline_diagnostics_snapshot") as Dictionary


func _build_compatibility_snapshot() -> Dictionary:
	var wall_projection_debug: Dictionary = _wall_collider_projection.get_debug_snapshot() if _wall_collider_projection != null else {}
	var territory_debug: Dictionary = _territory_projection.get_debug_snapshot() if _territory_projection != null else {}
	var player_wall_compat: Dictionary = _player_wall_system.get_compat_bridge_snapshot() if _player_wall_system != null else {}
	var bandit_pipeline: Dictionary = _build_bandit_pipeline_snapshot()
	var perception_debug: Dictionary = bandit_pipeline.get("perception", {}) as Dictionary
	var task_planner_debug: Dictionary = (bandit_pipeline.get("group_brain", {}) as Dictionary).get("task_planner", {}) as Dictionary
	return {
		"player_wall_system": player_wall_compat,
		"wall_collider_projection": {
			"legacy_chunk_dirty_fallback_uses": int(wall_projection_debug.get("legacy_chunk_dirty_fallback_uses", 0)),
		},
		"territory_projection": {
			"legacy_runtime_anchor_reads": int(territory_debug.get("legacy_runtime_anchor_reads", 0)),
			"legacy_runtime_api_attempts": int(territory_debug.get("legacy_runtime_api_attempts", 0)),
		},
		"bandit_perception": perception_debug,
		"bandit_task_plan": task_planner_debug,
		# Legacy alias retained while downstream dashboards migrate.
		"bandit_task_planner": task_planner_debug,
	}


func _read_loaded_chunks() -> Dictionary:
	if _world == null:
		return {}
	var chunks_raw: Variant = _world.get("loaded_chunks")
	if chunks_raw is Dictionary:
		return (chunks_raw as Dictionary).duplicate(true)
	return {}


func _count_structures_for_loaded_chunks(loaded_chunks: Dictionary) -> Dictionary:
	var player_walls: int = 0
	var structural_walls: int = 0
	var placeables: int = 0
	if _sandbox_structure_repository == null:
		return {
			"total": 0,
			"player_walls": 0,
			"structural_walls": 0,
			"placeables": 0,
		}
	for chunk_pos_raw in loaded_chunks.keys():
		if not (chunk_pos_raw is Vector2i):
			continue
		var rows: Array[Dictionary] = _sandbox_structure_repository.list_structures_in_chunk(chunk_pos_raw as Vector2i, true)
		for raw in rows:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = raw as Dictionary
			match String(row.get("kind", "")):
				"player_wall":
					player_walls += 1
				"structural_wall":
					structural_walls += 1
				"placeable":
					placeables += 1
	return {
		"total": player_walls + structural_walls + placeables,
		"player_walls": player_walls,
		"structural_walls": structural_walls,
		"placeables": placeables,
	}


func _read_detected_base_count() -> int:
	if _settlement_intel == null:
		return 0
	if _settlement_intel.has_method("get_detected_bases_snapshot"):
		return (_settlement_intel.call("get_detected_bases_snapshot") as Array).size()
	return 0
