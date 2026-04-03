class_name WorldSimTelemetry
extends RefCounted

var enabled: bool = true
var print_interval: float = 5.0

var _world: Node = null
var _cadence: WorldCadenceCoordinator = null
var _bandit_behavior_layer: BanditBehaviorLayer = null
var _settlement_intel: SettlementIntel = null
var _world_spatial_index: WorldSpatialIndex = null
var _maintenance_snapshot_cb: Callable = Callable()
var _npc_sim: NpcSimulator = null
var _perf_monitor: ChunkPerfMonitor = null
var _print_timer: float = 0.0


func setup(ctx: Dictionary) -> void:
	enabled = bool(ctx.get("enabled", true))
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
	var timers: Dictionary = settlement.get("timers", {})
	var npc_ms: float = _npc_sim.process_ms_avg if _npc_sim != null else -1.0
	var gen_p50: float = _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_GENERATE) if _perf_monitor != null else -1.0
	var ent_p50: float = _perf_monitor.get_stage_p50(ChunkPerfMonitor.STAGE_ENTITIES) if _perf_monitor != null else -1.0
	var q_total: int = int(spatial.get("query_total", 0))
	var hit_pct: int = int(spatial.get("query_hit_rate", 0.0) * 100.0)
	var g_counts: Dictionary = _nested_dict(bandit, ["group_scan", "group_counts"])
	var npc_counts: Dictionary = bandit.get("npc_counts", {})
	var npc_reasons: Dictionary = bandit.get("npc_dominant_reasons", {})
	var npc_mode_perf: Dictionary = bandit.get("mode_perf", {})
	var group_mode_perf: Dictionary = _nested_dict(bandit, ["group_scan", "mode_perf"], {})
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
		+ "bandits g[%s] npc[%s] top=%s | "
		+ "lod-mode npc[%s] group[%s] | "
		+ "settlement wb=%.1f/30s base=%.1f/10s bases=%d | "
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
		_format_mode_perf_summary(npc_mode_perf),
		_format_mode_perf_summary(group_mode_perf),
		float(timers.get("workbench_rescan_timer", 0.0)),
		float(timers.get("base_rescan_timer", 0.0)),
		int(settlement.get("bases_detected", 0)),
		hit_pct, q_total,
	])


func get_debug_snapshot() -> Dictionary:
	if not enabled:
		return {
			"enabled": false,
		}
	var cadence_snapshot: Dictionary = _cadence.get_debug_snapshot() if _cadence != null else {}
	var bandit_snapshot: Dictionary = _bandit_behavior_layer.get_lod_debug_snapshot() if _bandit_behavior_layer != null else {}
	var spatial_snapshot: Dictionary = _world_spatial_index.get_debug_snapshot() if _world_spatial_index != null else {}
	var maintenance_snapshot: Dictionary = _maintenance_snapshot_cb.call() if _maintenance_snapshot_cb.is_valid() else {}
	if not cadence_snapshot.is_empty():
		cadence_snapshot["activity_summary"] = _summarize_lane_activity(cadence_snapshot.get("lanes", {}))
	if not bandit_snapshot.is_empty():
		bandit_snapshot["npc_dominant_reasons"] = _count_dominant_reasons(bandit_snapshot.get("npc_intervals", {}))
		var group_scan: Dictionary = bandit_snapshot.get("group_scan", {})
		group_scan["group_dominant_reasons"] = _count_dominant_reasons(group_scan.get("group_intervals", {}))
		bandit_snapshot["group_scan"] = group_scan
	var drop_metrics: Dictionary = _build_drop_metrics_snapshot(spatial_snapshot, bandit_snapshot, maintenance_snapshot)
	return {
		"enabled": true,
		"cadence": cadence_snapshot,
		"bandit_lod": bandit_snapshot,
		"settlement": _settlement_intel.get_debug_snapshot() if _settlement_intel != null else {},
		"spatial_index": spatial_snapshot,
		"world_maintenance": maintenance_snapshot,
		"drop_metrics": drop_metrics,
	}


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
	var drop_metrics: Dictionary = snapshot.get("drop_metrics", {})
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
		"- drops: mode=%s q/pulse=%d avgCand=%.1f budgetHits=%d compactHits=%d merged=%d" % [
			String(drop_metrics.get("drop_pressure_mode", "normal")),
			int(drop_metrics.get("pickup_queries_per_pulse", 0)),
			float(drop_metrics.get("average_drop_candidates_per_query", 0.0)),
			int(drop_metrics.get("drop_processing_budget_hits", 0)),
			int(drop_metrics.get("deposit_compact_path_hits", 0)),
			int(drop_metrics.get("merged_drop_events", 0)),
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
	var drop_metrics: Dictionary = snapshot.get("drop_metrics", {})
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
	lines.append("drops n=%d q=%d avg=%.1f b=%d c=%d m=%d mode=%s" % [
		int(drop_metrics.get("item_drop_count", 0)),
		int(drop_metrics.get("pickup_queries_per_pulse", 0)),
		float(drop_metrics.get("average_drop_candidates_per_query", 0.0)),
		int(drop_metrics.get("drop_processing_budget_hits", 0)),
		int(drop_metrics.get("deposit_compact_path_hits", 0)),
		int(drop_metrics.get("merged_drop_events", 0)),
		String(drop_metrics.get("drop_pressure_mode", "normal")),
	])
	return lines


func _build_drop_metrics_snapshot(spatial: Dictionary, bandit: Dictionary, maintenance: Dictionary) -> Dictionary:
	var runtime_counts: Dictionary = spatial.get("runtime_counts", {})
	var spatial_drop_queries: Dictionary = spatial.get("drop_queries", {})
	var bandit_drop_metrics: Dictionary = bandit.get("drop_metrics", {})
	var drop_compaction: Dictionary = maintenance.get("drop_compaction", {})
	var pressure: Dictionary = drop_compaction.get("pressure", {})
	var item_drop_count: int = int(runtime_counts.get("item_drop", pressure.get("item_drop_count", 0)))
	var pickup_queries_per_pulse: int = int(bandit_drop_metrics.get(
		"pickup_queries_per_pulse",
		spatial_drop_queries.get("pickup_queries_per_pulse", 0)
	))
	var avg_drop_candidates: float = float(bandit_drop_metrics.get(
		"average_drop_candidates_per_query",
		spatial_drop_queries.get("average_drop_candidates_per_query", 0.0)
	))
	return {
		"item_drop_count": item_drop_count,
		"pickup_queries_per_pulse": pickup_queries_per_pulse,
		"average_drop_candidates_per_query": avg_drop_candidates,
		"merged_drop_events": int(drop_compaction.get("merged_drop_events", 0)),
		"deposit_compact_path_hits": int(bandit_drop_metrics.get("deposit_compact_path_hits", 0)),
		"drop_pressure_mode": String(bandit_drop_metrics.get("drop_pressure_mode", pressure.get("level", "normal"))),
		"drop_processing_budget_hits": int(bandit_drop_metrics.get("drop_processing_budget_hits", 0)),
	}


func _format_cadence_line(lanes: Dictionary) -> String:
	var parts: Array[String] = []
	for lane_name in ["short_pulse", "medium_pulse", "director_pulse", "chunk_pulse", "autosave", "settlement_base_scan", "settlement_workbench_scan", "occlusion_pulse", "resource_repop_pulse", "bandit_work_loop"]:
		if lanes.has(lane_name):
			var lane: Dictionary = lanes[lane_name]
			var utilization: float = float(lane.get("last_utilization", -1.0))
			var utilization_suffix: String = ""
			if utilization >= 0.0:
				utilization_suffix = " util=%d%%" % int(round(utilization * 100.0))
			parts.append("%s=%s/%.2f work=%d%s%s" % [
				lane_name,
				str(lane.get("recent_consumed", 0.0)),
				float(lane.get("interval", 0.0)),
				int(lane.get("last_work", 0)),
				utilization_suffix,
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


func _format_mode_perf_summary(mode_perf: Dictionary) -> String:
	var ordered_modes: Array[String] = ["contextual", "exploration_normal", "combat_close", "raid_active"]
	var parts: Array[String] = []
	for mode in ordered_modes:
		if not mode_perf.has(mode):
			continue
		var entry: Dictionary = mode_perf.get(mode, {})
		var frame_ms: float = float(entry.get("frame_time_avg_ms", entry.get("scan_time_avg_ms", -1.0)))
		var react_ms: float = float(entry.get("reaction_latency_avg_s", 0.0)) * 1000.0
		var samples: int = int(entry.get("reaction_samples", 0))
		parts.append("%s %.2fms/%.1fms n=%d" % [mode, frame_ms, react_ms, samples])
	return "n/a" if parts.is_empty() else ", ".join(parts)
