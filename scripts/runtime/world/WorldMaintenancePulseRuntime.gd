extends RefCounted
class_name WorldMaintenancePulseRuntime

const PlacementPerfTelemetryScript := preload("res://scripts/world/PlacementPerfTelemetry.gd")

var _chunk_lifecycle_coordinator: WorldChunkLifecycleCoordinator
var _wall_refresh_queue: WallRefreshQueue
var _loaded_chunks: Dictionary = {}
var _ensure_chunk_wall_collision: Callable = Callable()
var _cadence: WorldCadenceCoordinator
var _lane_short_pulse: StringName = &"short_pulse"

var _wall_refresh_budget_per_pulse: int = 1
var _tile_erase_budget_per_pulse: int = 2

func setup(ctx: Dictionary) -> void:
	_chunk_lifecycle_coordinator = ctx.get("chunk_lifecycle_coordinator", null) as WorldChunkLifecycleCoordinator
	_wall_refresh_queue = ctx.get("wall_refresh_queue", null) as WallRefreshQueue
	_loaded_chunks = ctx.get("loaded_chunks", {}) as Dictionary
	_ensure_chunk_wall_collision = ctx.get("ensure_chunk_wall_collision", Callable()) as Callable
	_cadence = ctx.get("cadence", null) as WorldCadenceCoordinator
	_lane_short_pulse = ctx.get("lane_short_pulse", _lane_short_pulse) as StringName
	_wall_refresh_budget_per_pulse = int(ctx.get("wall_refresh_budget_per_pulse", _wall_refresh_budget_per_pulse))
	_tile_erase_budget_per_pulse = int(ctx.get("tile_erase_budget_per_pulse", _tile_erase_budget_per_pulse))

func execute_short_pulse(pulse_count: int) -> void:
	var pulses: int = maxi(0, pulse_count)
	if pulses <= 0:
		return
	for _pulse in pulses:
		_process_wall_refresh_queue(_wall_refresh_budget_per_pulse)
		_process_tile_erase_queue(_tile_erase_budget_per_pulse)
	if _cadence != null:
		var budget_per_pulse: int = _wall_refresh_budget_per_pulse + _tile_erase_budget_per_pulse
		var executed_ops: int = budget_per_pulse * pulses
		_cadence.report_lane_work(_lane_short_pulse, executed_ops, budget_per_pulse)

func get_debug_snapshot() -> Dictionary:
	return {
		"pending_tile_erases": _chunk_lifecycle_coordinator.pending_tile_erase_count() if _chunk_lifecycle_coordinator != null else 0,
		"wall_refresh": _wall_refresh_queue.get_debug_snapshot() if _wall_refresh_queue != null else {},
	}

func _process_tile_erase_queue(max_erases_per_pulse: int) -> void:
	if _chunk_lifecycle_coordinator == null:
		return
	_chunk_lifecycle_coordinator.process_tile_erase_queue(max_erases_per_pulse)

func _process_wall_refresh_queue(max_rebuilds_per_pulse: int) -> void:
	var t0_usec: int = Time.get_ticks_usec()
	if _wall_refresh_queue == null:
		return
	var rebuild_budget: int = maxi(0, max_rebuilds_per_pulse)
	var rebuilds_executed: int = 0
	while rebuild_budget > 0:
		var result: Dictionary = _wall_refresh_queue.try_pop_next()
		if not result.ok:
			break

		var chunk_pos: Vector2i = result.chunk_pos
		if not _loaded_chunks.has(chunk_pos):
			_wall_refresh_queue.purge_chunk(chunk_pos)
			continue

		if _ensure_chunk_wall_collision.is_valid():
			_ensure_chunk_wall_collision.call(chunk_pos)
		_wall_refresh_queue.confirm_rebuild(chunk_pos, result.revision)
		rebuilds_executed += 1
		rebuild_budget -= 1
	PlacementPerfTelemetryScript.record_stage(
		"world_process_wall_refresh_queue",
		Time.get_ticks_usec() - t0_usec,
		{
			"rebuild_budget": maxi(0, max_rebuilds_per_pulse),
			"rebuilds_executed": rebuilds_executed,
		},
		"collider"
	)
