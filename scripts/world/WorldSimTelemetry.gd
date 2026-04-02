class_name WorldSimTelemetry
extends RefCounted

var enabled: bool = true
var print_interval: float = 5.0
var snapshot_detail_level: String = "normal"
var snapshot_profiling_enabled: bool = false
var deep_snapshot_sample_interval: float = 0.75

var _world: Node = null
var _cadence: WorldCadenceCoordinator = null
var _bandit_behavior_layer: BanditBehaviorLayer = null
var _settlement_intel: SettlementIntel = null
var _world_spatial_index: WorldSpatialIndex = null
var _maintenance_snapshot_cb: Callable = Callable()
var _npc_sim: NpcSimulator = null
var _perf_monitor: ChunkPerfMonitor = null
var _print_timer: float = 0.0
var _deep_snapshot_cache: Dictionary = {}
var _deep_snapshot_last_at: float = -INF


func setup(ctx: Dictionary) -> void:
	enabled = bool(ctx.get("enabled", true))
	snapshot_detail_level = _normalize_snapshot_detail_level(String(ctx.get("snapshot_detail_level", "normal")))
	snapshot_profiling_enabled = bool(ctx.get("snapshot_profiling_enabled", false))
	deep_snapshot_sample_interval = maxf(0.0, float(ctx.get("deep_snapshot_sample_interval", 0.75)))
	_world = ctx.get("world")
	_cadence = ctx.get("cadence") as WorldCadenceCoordinator
	_bandit_behavior_layer = ctx.get("bandit_behavior_layer") as BanditBehaviorLayer
	_settlement_intel = ctx.get("settlement_intel") as SettlementIntel
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex
	_maintenance_snapshot_cb = ctx.get("maintenance_snapshot_cb", Callable())
	_npc_sim = ctx.get("npc_sim") as NpcSimulator
	_perf_monitor = ctx.get("perf_monitor") as ChunkPerfMonitor


func tick(delta: float) -> void:
	if not enabled:
		return
	_print_timer += delta
	if _print_timer < print_interval:
		return
	_print_timer = 0.0
	_print_perf_to_console()


func _print_perf_to_console() -> void:
	var snapshot := get_debug_snapshot()
	var bandit: Dictionary = snapshot.get("bandit_lod", {})
	var settlement: Dictionary = snapshot.get("settlement", {})
	var spatial: Dictionary = snapshot.get("spatial_index", {})
	var npc_ms: float = _npc_sim.process_ms_avg if _npc_sim != null else -1.0
	var gen_p50: float = _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_GENERATE) if _perf_monitor != null else -1.0
	var ent_p50: float = _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_ENTITIES) if _perf_monitor != null else -1.0
	var q_total: int = int(spatial.get("query_total", 0))
	var hit_pct: int = int(spatial.get("query_hit_rate", 0.0) * 100.0)
	var g_counts: Dictionary = _nested_dict(bandit, ["group_scan", "group_counts"])
	var npc_counts: Dictionary = bandit.get("npc_counts", {})
	var npc_reasons: Dictionary = bandit.get("npc_dominant_reasons", {})
	var tick_perf: Dictionary = bandit.get("tick_perf", {})
	var dist_stats: Dictionary = _npc_sim.get_active_distance_stats() if _npc_sim != null else {}
	var dist_str: String = "n/a"
	if int(dist_stats.get("count", 0)) > 0:
		dist_str = "min=%.0f avg=%.0f max=%.0f" % [
			float(dist_stats.get("min", 0.0)),
			float(dist_stats.get("avg", 0.0)),
			float(dist_stats.get("max", 0.0)),
		]
	var top_reason: String = ""
	var top_count: int = 0
	for r in npc_reasons.keys():
		if int(npc_reasons[r]) > top_count:
			top_count = int(npc_reasons[r])
			top_reason = String(r)
	Debug.log("perf_telemetry", (
		"chunk gen=%.2fms ent=%.2fms | npc sim=%.2fms (active=%d data=%d) dist[%s] | "
		+ "bandits g[%s] npc[%s] top=%s tick=%.2fms q/tick=%.2f | "
		+ "settlement dirty[wb=%s base=%s] bases=%d | "
		+ "spatial hit=%d%% (%d q)"
	) % [
		gen_p50, ent_p50,
		npc_ms,
		_npc_sim.active_enemies.size() if _npc_sim != null else 0,
		_npc_sim._data_behaviors.size() if _npc_sim != null else 0,
		dist_str,
		_format_bucket_counts(g_counts),
		_format_bucket_counts(npc_counts),
		top_reason,
		float(tick_perf.get("avg_ms", -1.0)),
		float(tick_perf.get("avg_query_delta", -1.0)),
		str(bool(settlement.get("interest_scan_dirty", false))),
		str(bool(settlement.get("base_scan_dirty", false))),
		int(settlement.get("bases_detected", 0)),
		hit_pct, q_total,
	])


func get_debug_snapshot(detail_level: String = "", force_export: bool = false) -> Dictionary:
	if not enabled:
		return {
			"enabled": false,
		}
	var resolved_level: String = snapshot_detail_level if detail_level == "" else _normalize_snapshot_detail_level(detail_level)
	var include_deep: bool = resolved_level == "full" or force_export or snapshot_profiling_enabled
	var cadence_snapshot: Dictionary = _cadence.get_debug_snapshot() if _cadence != null else {}
	var bandit_snapshot: Dictionary = _bandit_behavior_layer.get_lod_debug_snapshot(
		resolved_level,
		force_export,
		snapshot_profiling_enabled
	) if _bandit_behavior_layer != null else {}
	var settlement_snapshot: Dictionary = _settlement_intel.get_debug_snapshot() if _settlement_intel != null else {}
	var spatial_snapshot: Dictionary = _world_spatial_index.get_debug_snapshot() if _world_spatial_index != null else {}
	var maintenance_snapshot: Dictionary = _maintenance_snapshot_cb.call() if _maintenance_snapshot_cb.is_valid() else {}
	var snapshot: Dictionary = {
		"enabled": true,
		"detail_level": resolved_level,
		"profiling_enabled": snapshot_profiling_enabled,
		"cadence": cadence_snapshot,
		"bandit_lod": bandit_snapshot,
		"settlement": settlement_snapshot,
		"spatial_index": spatial_snapshot,
		"world_maintenance": maintenance_snapshot,
	}
	if not include_deep:
		return snapshot
	if not force_export and resolved_level != "full" and not _should_refresh_deep_snapshot():
		if not _deep_snapshot_cache.is_empty():
			return _deep_snapshot_cache
	if not cadence_snapshot.is_empty():
		cadence_snapshot["activity_summary"] = _summarize_lane_activity(cadence_snapshot.get("lanes", {}))
	if not bandit_snapshot.is_empty():
		bandit_snapshot["npc_dominant_reasons"] = _count_dominant_reasons(bandit_snapshot.get("npc_intervals", {}))
		var group_scan: Dictionary = bandit_snapshot.get("group_scan", {})
		group_scan["group_dominant_reasons"] = _count_dominant_reasons(group_scan.get("group_intervals", {}))
		bandit_snapshot["group_scan"] = group_scan
	snapshot["kpis"] = _build_explicit_kpi_snapshot(cadence_snapshot, bandit_snapshot, settlement_snapshot)
	if not force_export:
		_deep_snapshot_cache = snapshot
		_deep_snapshot_last_at = RunClock.now()
	return snapshot


func dump_debug_summary() -> String:
	var snapshot := get_debug_snapshot()
	if not bool(snapshot.get("enabled", false)):
		return "WORLD SIM\n- telemetry: disabled"
	var cadence: Dictionary = snapshot.get("cadence", {})
	var lanes: Dictionary = cadence.get("lanes", {})
	var bandit: Dictionary = snapshot.get("bandit_lod", {})
	var settlement: Dictionary = snapshot.get("settlement", {})
	var spatial: Dictionary = snapshot.get("spatial_index", {})
	var maintenance: Dictionary = snapshot.get("world_maintenance", {})
	var base_progress: Dictionary = settlement.get("base_scan_progress", {})
	var runtime_counts: Dictionary = spatial.get("runtime_counts", {})
	var wall_refresh: Dictionary = maintenance.get("wall_refresh", {})
	var autosave: Dictionary = maintenance.get("autosave", {})
	var lines := PackedStringArray([
		"WORLD SIM",
		"- cadence: %s" % _format_cadence_line(lanes),
		"- bandit groups: %s" % _format_bucket_counts(_nested_dict(bandit, ["group_scan", "group_counts"])),
		"- bandit npcs: %s" % _format_bucket_counts(bandit.get("npc_counts", {})),
		"- settlement: base_scan=%s(%d/%d), workbench_markers=%d, bases=%d" % [
			"running" if bool(settlement.get("base_scan_running", false)) else "idle",
			int(base_progress.get("processed", 0)),
			int(base_progress.get("total", 0)),
			int(settlement.get("workbench_markers", 0)),
			int(settlement.get("bases_detected", 0)),
		],
		"- spatial: drops=%d, resources=%d, benches=%d, storage=%d" % [
			int(runtime_counts.get("item_drop", 0)),
			int(runtime_counts.get("world_resource", 0)),
			int(runtime_counts.get("workbench", 0)),
			int(runtime_counts.get("storage", 0)),
		],
		"- maintenance: tile_erase=%d, wall_refresh=%d(hot=%d), autosave=%s" % [
			int(maintenance.get("pending_tile_erases", 0)),
			int(wall_refresh.get("hot_size", 0)) + int(wall_refresh.get("normal_size", 0)),
			int(wall_refresh.get("hot_size", 0)),
			_format_autosave_line(autosave),
		],
	])
	return "\n".join(lines)


func build_overlay_lines() -> PackedStringArray:
	var snapshot := get_debug_snapshot()
	if not bool(snapshot.get("enabled", false)):
		return PackedStringArray(["WORLD SIM: telemetry disabled"])
	var settlement: Dictionary = snapshot.get("settlement", {})
	var maintenance: Dictionary = snapshot.get("world_maintenance", {})
	var lines := PackedStringArray()
	lines.append("WORLD SIM")
	lines.append("cadence %s" % _format_cadence_line(snapshot.get("cadence", {}).get("lanes", {})))
	lines.append("bandits g[%s] npc[%s]" % [
		_format_bucket_counts(_nested_dict(snapshot.get("bandit_lod", {}), ["group_scan", "group_counts"])),
		_format_bucket_counts(snapshot.get("bandit_lod", {}).get("npc_counts", {})),
	])
	lines.append("settlement base=%s workbench=%d" % [
		"running" if bool(settlement.get("base_scan_running", false)) else "idle",
		int(settlement.get("workbench_markers", 0)),
	])
	lines.append("maintenance erase=%d wall=%d" % [
		int(maintenance.get("pending_tile_erases", 0)),
		int(_nested_dict(maintenance, ["wall_refresh", "hot_size"], 0)) + int(_nested_dict(maintenance, ["wall_refresh", "normal_size"], 0)),
	])
	return lines


func _format_cadence_line(lanes: Dictionary) -> String:
	var parts: Array[String] = []
	for lane_name in ["short_pulse", "medium_pulse", "director_pulse", "chunk_pulse", "autosave", "settlement_base_scan", "settlement_workbench_scan"]:
		if lanes.has(lane_name):
			var lane: Dictionary = lanes[lane_name]
			parts.append("%s=%s/%.2f%s" % [
				lane_name,
				str(lane.get("recent_consumed", 0.0)),
				float(lane.get("interval", 0.0)),
				" catchup" if float(lane.get("recent_catchup", 0.0)) > 0.0 else "",
			])
	return ", ".join(parts)


func _format_bucket_counts(raw_counts: Dictionary) -> String:
	return "fast=%d, medium=%d, slow=%d" % [
		int(raw_counts.get("fast", 0)),
		int(raw_counts.get("medium", 0)),
		int(raw_counts.get("slow", 0)),
	]


func _format_autosave_line(autosave: Dictionary) -> String:
	return "count=%d last=%.2fs due=%d" % [
		int(autosave.get("save_count", 0)),
		float(autosave.get("last_save_age", -1.0)),
		int(autosave.get("due", 0)),
	]


func _nested_dict(source: Dictionary, path: Array, fallback: Variant = {}) -> Variant:
	var current: Variant = source
	for key in path:
		if not (current is Dictionary) or not current.has(key):
			return fallback
		current = current[key]
	return current


func _count_dominant_reasons(intervals: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for entry in intervals.values():
		var reason: String = String((entry as Dictionary).get("dominant_reason", "unknown"))
		counts[reason] = int(counts.get(reason, 0)) + 1
	return counts


func _summarize_lane_activity(lanes: Dictionary) -> Dictionary:
	var almost_inactive: Array[String] = []
	var very_active: Array[String] = []
	for lane_name in lanes.keys():
		var lane: Dictionary = lanes[lane_name]
		match String(lane.get("activity", "warm")):
			"inactive":
				almost_inactive.append(String(lane_name))
			"hot":
				very_active.append(String(lane_name))
	return {
		"almost_inactive": almost_inactive,
		"very_active": very_active,
	}


func _build_explicit_kpi_snapshot(cadence_snapshot: Dictionary, bandit_snapshot: Dictionary, settlement_snapshot: Dictionary) -> Dictionary:
	var bandit_lane_perf: Dictionary = bandit_snapshot.get("lane_perf", {})
	var settlement_lane_perf: Dictionary = _nested_dict(settlement_snapshot, ["telemetry_perf", "lane_ms"], {})
	var loop_detection: Array[Dictionary] = _detect_unbudgeted_loops(cadence_snapshot)
	var live_tree_calls: int = int(_nested_dict(bandit_snapshot, ["live_tree_scans", "calls"], 0))
	var live_tree_avg_nodes: float = float(_nested_dict(bandit_snapshot, ["live_tree_scans", "avg_node_count"], 0.0))
	var bandit_alloc_est: float = float(_nested_dict(bandit_snapshot, ["temp_alloc_estimate_per_tick", "avg_objects"], 0.0))
	var settlement_alloc_est: float = float(_nested_dict(settlement_snapshot, ["telemetry_perf", "temp_alloc_estimate_per_tick", "avg_objects"], 0.0))
	var chunk_lane_est_ms: float = maxf(0.0, _safe_chunk_stage_p50_sum())
	return {
		"scan_live_tree_hot_paths": {
			"status": "measured",
			"calls": live_tree_calls,
			"avg_nodes_per_scan": snappedf(live_tree_avg_nodes, 0.01),
			"source": "BanditBehaviorLayer fallback item_drop/world_resource scans",
		},
		"temp_allocations_estimated_per_tick": {
			"status": "estimated",
			"objects_per_tick_estimate": snappedf(bandit_alloc_est + settlement_alloc_est, 0.01),
			"components": {
				"bandit_behavior_layer": snappedf(bandit_alloc_est, 0.01),
				"settlement_intel": snappedf(settlement_alloc_est, 0.01),
			},
		},
		"lane_times_ms": {
			"director": _measured_kpi_entry(_nested_dict(bandit_lane_perf, ["director_pulse", "avg_ms"], -1.0)),
			"behavior": _measured_kpi_entry(_nested_dict(bandit_lane_perf, ["bandit_behavior_tick", "avg_ms"], -1.0)),
			"settlement": _measured_kpi_entry(_nested_dict(settlement_lane_perf, ["settlement_base_scan", "avg_ms"], -1.0)),
			"chunk": {
				"status": "estimated",
				"avg_ms": snappedf(chunk_lane_est_ms, 0.001),
				"notes": "estimated from chunk stage p50 aggregate",
			},
		},
		"unbudgeted_loops_detected": {
			"status": "pending_benchmark" if loop_detection.is_empty() else "measured",
			"count": loop_detection.size(),
			"loops": loop_detection,
		},
	}


func _safe_chunk_stage_p50_sum() -> float:
	if _perf_monitor == null:
		return -1.0
	return _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_GENERATE) \
		+ _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_ENTITIES) \
		+ _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_GROUND_CONNECT) \
		+ _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_WALL_CONNECT) \
		+ _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_COLLIDER_BUILD)


func _measured_kpi_entry(avg_ms: Variant) -> Dictionary:
	var val: float = float(avg_ms)
	if val < 0.0:
		return {
			"status": "pending_benchmark",
			"avg_ms": -1.0,
		}
	return {
		"status": "measured",
		"avg_ms": snappedf(val, 0.001),
	}


func _detect_unbudgeted_loops(cadence_snapshot: Dictionary) -> Array[Dictionary]:
	var loops: Array[Dictionary] = []
	var lanes: Dictionary = cadence_snapshot.get("lanes", {})
	var high_due_lanes: Array[String] = ["director_pulse", "bandit_behavior_tick", "chunk_pulse", "settlement_base_scan", "settlement_workbench_scan"]
	for lane_name in high_due_lanes:
		var due: int = int(_nested_dict(lanes, [lane_name, "due"], 0))
		var generated_due: int = int(_nested_dict(lanes, [lane_name, "last_generated_due"], 0))
		if due > 1 or generated_due > 2:
			loops.append({
				"id": lane_name,
				"kind": "cadence_backlog",
				"detail": "lane generated/queued more than expected per tick",
				"due": due,
				"generated_due": generated_due,
			})
	return loops


func _normalize_snapshot_detail_level(detail_level: String) -> String:
	match String(detail_level).to_lower():
		"minimal":
			return "minimal"
		"full":
			return "full"
		_:
			return "normal"


func _should_refresh_deep_snapshot() -> bool:
	if _deep_snapshot_cache.is_empty():
		return true
	if deep_snapshot_sample_interval <= 0.0:
		return true
	return (RunClock.now() - _deep_snapshot_last_at) >= deep_snapshot_sample_interval
