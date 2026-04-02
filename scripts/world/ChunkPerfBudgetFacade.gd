extends RefCounted
class_name ChunkPerfBudgetFacade

var _perf_monitor: ChunkPerfMonitor
var _pipeline: ChunkPipeline

func setup(ctx: Dictionary) -> void:
	_perf_monitor = ctx.get("perf_monitor")
	_pipeline = ctx.get("pipeline")

func configure(settings: Dictionary) -> void:
	if _perf_monitor == null:
		return
	_perf_monitor.enabled = settings.get("enabled", _perf_monitor.enabled)
	_perf_monitor.window_size = settings.get("window_size", _perf_monitor.window_size)
	_perf_monitor.auto_print = settings.get("auto_print", _perf_monitor.auto_print)
	_perf_monitor.print_interval = settings.get("print_interval", _perf_monitor.print_interval)
	_perf_monitor.auto_calibrate = settings.get("auto_calibrate", _perf_monitor.auto_calibrate)
	_perf_monitor.alert_generate_ms = settings.get("alert_generate_ms", _perf_monitor.alert_generate_ms)
	_perf_monitor.alert_ground_connect_ms = settings.get("alert_ground_connect_ms", _perf_monitor.alert_ground_connect_ms)
	_perf_monitor.alert_wall_connect_ms = settings.get("alert_wall_connect_ms", _perf_monitor.alert_wall_connect_ms)
	_perf_monitor.alert_collider_ms = settings.get("alert_collider_ms", _perf_monitor.alert_collider_ms)
	_perf_monitor.alert_entities_ms = settings.get("alert_entities_ms", _perf_monitor.alert_entities_ms)

func process(delta: float) -> void:
	if _perf_monitor != null and _perf_monitor.tick(delta):
		_apply_calibrated_perf_budgets()

func record(stage: String, chunk_pos: Vector2i, center_chunk: Vector2i, elapsed_ms: float) -> void:
	if _perf_monitor != null:
		_perf_monitor.record(stage, chunk_pos, center_chunk, elapsed_ms)

func debug_print_percentiles() -> void:
	if _perf_monitor == null:
		return
	_perf_monitor.print_percentiles()
	_apply_calibrated_perf_budgets()

func _apply_calibrated_perf_budgets() -> void:
	if _perf_monitor == null or _pipeline == null:
		return
	var budgets := _perf_monitor.get_calibrated_budgets()
	if budgets.has("terrain_paint_ms_budget"):
		_pipeline.terrain_paint_ms_budget = budgets["terrain_paint_ms_budget"]
	if budgets.has("wall_collider_chunks_per_tick"):
		_pipeline.wall_collider_chunks_per_tick = budgets["wall_collider_chunks_per_tick"]
	if budgets.has("cliff_paint_chunks_per_tick"):
		_pipeline.cliff_paint_chunks_per_tick = budgets["cliff_paint_chunks_per_tick"]
