extends RefCounted
class_name WorldProjectionRebuildCoordinator

## Owns explicit projection rebuild orchestration and reporting:
## - projection rebuild request publication
## - deterministic post-snapshot explicit rebuild ordering
## - snapshot rebuild summary generation/serialization
## - territory projection rebuild request bookkeeping

const SnapshotRebuildNotificationDtoScript := preload("res://scripts/domain/contracts/SnapshotRebuildNotificationDto.gd")

var _domain_event_dispatcher: SandboxDomainEventDispatcher
var _building_tilemap_projection: BuildingTilemapProjection
var _wall_collider_projection: WallColliderProjection
var _spatial_index_projection: SpatialIndexProjection
var _sandbox_structure_repository: SandboxStructureRepository
var _building_repository: BuildingRepository
var _loaded_chunks: Dictionary = {}

var _request_player_territory_rebuild_cb: Callable = Callable()
var _tick_player_territory_cb: Callable = Callable()

var _player_territory_rebuild_dirty: bool = false
var _last_snapshot_rebuild_report: Dictionary = _build_default_snapshot_report()

func setup(ctx: Dictionary) -> void:
	_domain_event_dispatcher = ctx.get("domain_event_dispatcher", null) as SandboxDomainEventDispatcher
	_building_tilemap_projection = ctx.get("building_tilemap_projection", null) as BuildingTilemapProjection
	_wall_collider_projection = ctx.get("wall_collider_projection", null) as WallColliderProjection
	_spatial_index_projection = ctx.get("spatial_index_projection", null) as SpatialIndexProjection
	_sandbox_structure_repository = ctx.get("sandbox_structure_repository", null) as SandboxStructureRepository
	_building_repository = ctx.get("building_repository", null) as BuildingRepository
	_loaded_chunks = ctx.get("loaded_chunks", {}) as Dictionary
	_request_player_territory_rebuild_cb = ctx.get("request_player_territory_rebuild_cb", Callable()) as Callable
	_tick_player_territory_cb = ctx.get("tick_player_territory_cb", Callable()) as Callable

func request_player_territory_rebuild(reason: String) -> void:
	_player_territory_rebuild_dirty = true
	_publish_projection_rebuild_requested("player_territory", reason)

func consume_player_territory_rebuild_request() -> bool:
	if not _player_territory_rebuild_dirty:
		return false
	_player_territory_rebuild_dirty = false
	return true

func rebuild_explicit_projections_after_snapshot_load() -> void:
	_publish_projection_rebuild_requested("snapshot_explicit", "snapshot_loaded")
	# Explicit deterministic rebuild order after canonical-state-first restore:
	# 1) tilemap projection, 2) wall collider projection,
	# 3) spatial index projection, 4) territory projection.
	var loaded_structure_snapshot: Array[Dictionary] = _collect_loaded_structure_snapshot()
	var warnings: Array[String] = []
	var tilemap_projection_applied: int = 0
	var collider_projection_rebuilt: int = 0
	var spatial_projection_rebuilt: int = 0

	if _building_tilemap_projection != null and not loaded_structure_snapshot.is_empty():
		_building_tilemap_projection.apply_snapshot(loaded_structure_snapshot)
		tilemap_projection_applied = 1
	elif _building_tilemap_projection == null:
		warnings.append("missing_building_tilemap_projection")

	if _wall_collider_projection != null and not loaded_structure_snapshot.is_empty():
		_wall_collider_projection.rebuild_from_state(loaded_structure_snapshot)
		collider_projection_rebuilt = 1
	elif _wall_collider_projection == null:
		warnings.append("missing_wall_collider_projection")

	if _spatial_index_projection != null:
		_spatial_index_projection.rebuild_from_source("snapshot_load")
		spatial_projection_rebuilt = 1
	else:
		warnings.append("missing_spatial_index_projection")

	if _request_player_territory_rebuild_cb.is_valid():
		_request_player_territory_rebuild_cb.call("snapshot_load")
	if _tick_player_territory_cb.is_valid():
		_tick_player_territory_cb.call()

	_last_snapshot_rebuild_report["calls"] = int(_last_snapshot_rebuild_report.get("calls", 0)) + 1
	_last_snapshot_rebuild_report["warnings"] = warnings.duplicate(true)
	_last_snapshot_rebuild_report["loaded_structure_count"] = loaded_structure_snapshot.size()
	_last_snapshot_rebuild_report["tilemap_projection_applied"] = tilemap_projection_applied
	_last_snapshot_rebuild_report["collider_projection_rebuilt"] = collider_projection_rebuilt
	_last_snapshot_rebuild_report["spatial_projection_rebuilt"] = spatial_projection_rebuilt
	_last_snapshot_rebuild_report["territory_rebuild_requests"] = 1

	if _domain_event_dispatcher != null:
		_domain_event_dispatcher.publish("projection_rebuild_completed", {
			"projection": "snapshot_explicit",
			"reason": "snapshot_loaded",
			"report": get_snapshot_rebuild_report(),
		})

func get_snapshot_rebuild_report() -> Dictionary:
	return SnapshotRebuildNotificationDtoScript.build(_last_snapshot_rebuild_report)

func _collect_loaded_structure_snapshot() -> Array[Dictionary]:
	var loaded_structure_snapshot: Array[Dictionary] = []
	for chunk_pos_raw in _loaded_chunks.keys():
		if not (chunk_pos_raw is Vector2i):
			continue
		var chunk_pos: Vector2i = chunk_pos_raw as Vector2i
		if _sandbox_structure_repository != null:
			loaded_structure_snapshot.append_array(_sandbox_structure_repository.list_structures_in_chunk(chunk_pos, false))
		elif _building_repository != null:
			loaded_structure_snapshot.append_array(_building_repository.load_structures_in_chunk(chunk_pos))
	return loaded_structure_snapshot

func _publish_projection_rebuild_requested(projection: String, reason: String) -> void:
	if _domain_event_dispatcher == null:
		return
	_domain_event_dispatcher.publish("projection_rebuild_requested", {
		"projection": projection,
		"reason": reason,
	})

static func _build_default_snapshot_report() -> Dictionary:
	return {
		"calls": 0,
		"warnings": [],
		"loaded_structure_count": 0,
		"tilemap_projection_applied": 0,
		"collider_projection_rebuilt": 0,
		"spatial_projection_rebuilt": 0,
		"territory_rebuild_requests": 0,
	}
