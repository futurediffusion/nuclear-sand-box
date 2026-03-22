class_name WorldSimTelemetry
extends RefCounted

var enabled: bool = true

var _world: Node = null
var _cadence: WorldCadenceCoordinator = null
var _bandit_behavior_layer: BanditBehaviorLayer = null
var _settlement_intel: SettlementIntel = null
var _world_spatial_index: WorldSpatialIndex = null
var _maintenance_snapshot_cb: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	enabled = bool(ctx.get("enabled", true))
	_world = ctx.get("world")
	_cadence = ctx.get("cadence") as WorldCadenceCoordinator
	_bandit_behavior_layer = ctx.get("bandit_behavior_layer") as BanditBehaviorLayer
	_settlement_intel = ctx.get("settlement_intel") as SettlementIntel
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex
	_maintenance_snapshot_cb = ctx.get("maintenance_snapshot_cb", Callable())


func get_debug_snapshot() -> Dictionary:
	if not enabled:
		return {
			"enabled": false,
		}
	var cadence_snapshot: Dictionary = _cadence.get_debug_snapshot() if _cadence != null else {}
	var bandit_snapshot: Dictionary = _bandit_behavior_layer.get_lod_debug_snapshot() if _bandit_behavior_layer != null else {}
	if not cadence_snapshot.is_empty():
		cadence_snapshot["activity_summary"] = _summarize_lane_activity(cadence_snapshot.get("lanes", {}))
	if not bandit_snapshot.is_empty():
		bandit_snapshot["npc_dominant_reasons"] = _count_dominant_reasons(bandit_snapshot.get("npc_intervals", {}))
		var group_scan: Dictionary = bandit_snapshot.get("group_scan", {})
		group_scan["group_dominant_reasons"] = _count_dominant_reasons(group_scan.get("group_intervals", {}))
		bandit_snapshot["group_scan"] = group_scan
	return {
		"enabled": true,
		"cadence": cadence_snapshot,
		"bandit_lod": bandit_snapshot,
		"settlement": _settlement_intel.get_debug_snapshot() if _settlement_intel != null else {},
		"spatial_index": _world_spatial_index.get_debug_snapshot() if _world_spatial_index != null else {},
		"world_maintenance": _maintenance_snapshot_cb.call() if _maintenance_snapshot_cb.is_valid() else {},
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
