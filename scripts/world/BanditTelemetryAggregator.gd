extends RefCounted
class_name BanditTelemetryAggregator

const DEFAULT_METRICS_WINDOW_SECONDS: float = 5.0
const PERF_WINDOW_LOG_SAMPLE_EVERY_N_WINDOWS: int = 3

var _metrics_window_seconds: float = DEFAULT_METRICS_WINDOW_SECONDS
var _perf_window_elapsed_s: float = 0.0
var _perf_window_accum: Dictionary = {}
var _perf_baseline_snapshots: Dictionary = {}
var _lod_mode_perf: Dictionary = {}


func configure(window_seconds: float) -> void:
	_metrics_window_seconds = maxf(window_seconds, 0.1)


func advance_window(delta: float) -> void:
	_perf_window_elapsed_s += maxf(delta, 0.0)


func reset_perf_window_metrics() -> void:
	_perf_window_elapsed_s = 0.0
	_perf_window_accum = {
		"physics_process_calls": 0,
		"physics_process_total_ms": 0.0,
		"ally_separation_total_ms": 0.0,
		"behavior_tick_calls": 0,
		"behavior_tick_total_ms": 0.0,
		"work_units": 0,
		"scan_total": 0,
		"separation_group_scans": 0,
		"separation_npc_scans": 0,
		"separation_neighbor_checks_total": 0,
		"crowd_mode_active_groups": 0,
		"crowd_mode_groups_total": 0,
		"assignment_conflicts_total": 0,
		"double_reservations_avoided": 0,
		"expired_reservations": 0,
		"assignment_replans": 0,
		"assault_context_build_ms": 0.0,
		"assault_context_hits": 0,
		"assault_per_npc_before_total_ms": 0.0,
		"assault_per_npc_before_calls": 0,
		"assault_per_npc_after_total_ms": 0.0,
		"assault_per_npc_after_calls": 0,
		"worker_active_count_samples": 0,
		"worker_active_count_frames": 0,
		"followers_without_task_samples": 0,
		"followers_without_task_frames": 0,
		"profile_full_count": 0,
		"profile_obedient_count": 0,
		"profile_decorative_count": 0,
		"profile_switches_total": 0,
		"profile_budget_downgrades": 0,
		"profile_event_reactivations": 0,
		"scan_by_group": {},
		"scan_by_npc": {},
	}


func record_mode_frame_time(mode: StringName, elapsed_ms: float) -> void:
	var entry: Dictionary = _ensure_mode_perf_entry(mode)
	entry["frame_samples"] = int(entry.get("frame_samples", 0)) + 1
	entry["frame_time_total_ms"] = float(entry.get("frame_time_total_ms", 0.0)) + maxf(elapsed_ms, 0.0)
	entry["frame_time_avg_ms"] = float(entry.get("frame_time_total_ms", 0.0)) / float(maxi(int(entry.get("frame_samples", 0)), 1))
	_lod_mode_perf[String(mode)] = entry


func record_mode_reaction_latency(mode: StringName, latency_s: float) -> void:
	var entry: Dictionary = _ensure_mode_perf_entry(mode)
	entry["reaction_samples"] = int(entry.get("reaction_samples", 0)) + 1
	entry["reaction_latency_total_s"] = float(entry.get("reaction_latency_total_s", 0.0)) + maxf(latency_s, 0.0)
	entry["reaction_latency_avg_s"] = float(entry.get("reaction_latency_total_s", 0.0)) / float(maxi(int(entry.get("reaction_samples", 0)), 1))
	_lod_mode_perf[String(mode)] = entry


func snapshot_mode_perf() -> Dictionary:
	return _lod_mode_perf.duplicate(true)


func accumulate_perf_window(delta: Dictionary) -> void:
	for key_var in delta.keys():
		var key: String = str(key_var)
		var value = delta[key_var]
		if value is int:
			_perf_window_accum[key] = int(_perf_window_accum.get(key, 0)) + int(value)
		elif value is float:
			_perf_window_accum[key] = float(_perf_window_accum.get(key, 0.0)) + float(value)
		else:
			_perf_window_accum[key] = value


func merge_nested_counter(key: String, source: Dictionary) -> void:
	var target: Dictionary = _perf_window_accum.get(key, {})
	for item in source.keys():
		var name: String = str(item)
		target[name] = int(target.get(name, 0)) + int(source[item])
	_perf_window_accum[key] = target


func flush_perf_window_if_needed() -> void:
	if _perf_window_elapsed_s < _metrics_window_seconds:
		return
	if _should_emit_sampled_perf_window_log():
		var snapshot: Dictionary = get_perf_window_snapshot()
		Debug.log("perf_telemetry", "[BanditBehaviorMetrics][window] %s" % JSON.stringify(snapshot))
	reset_perf_window_metrics()


func dict_int_sum(src: Dictionary) -> int:
	var total: int = 0
	for k in src.keys():
		total += int(src[k])
	return total


func count_assignment_conflicts(claims: Dictionary) -> int:
	var conflicts: int = 0
	for k in claims.keys():
		var claim_count: int = int(claims[k])
		if claim_count > 1:
			conflicts += claim_count - 1
	return conflicts


func get_perf_window_snapshot() -> Dictionary:
	var elapsed: float = maxf(_perf_window_elapsed_s, 0.0001)
	var physics_calls: int = int(_perf_window_accum.get("physics_process_calls", 0))
	var behavior_calls: int = int(_perf_window_accum.get("behavior_tick_calls", 0))
	var workers_frames: int = maxi(int(_perf_window_accum.get("worker_active_count_frames", 0)), 1)
	var followers_frames: int = maxi(int(_perf_window_accum.get("followers_without_task_frames", 0)), 1)
	var profile_samples: int = maxi(
			int(_perf_window_accum.get("profile_full_count", 0))
			+ int(_perf_window_accum.get("profile_obedient_count", 0))
			+ int(_perf_window_accum.get("profile_decorative_count", 0)),
			1)
	var scan_by_group: Dictionary = _perf_window_accum.get("scan_by_group", {})
	var scan_by_npc: Dictionary = _perf_window_accum.get("scan_by_npc", {})
	var physics_avg: float = float(_perf_window_accum.get("physics_process_total_ms", 0.0)) / float(maxi(physics_calls, 1))
	var behavior_avg: float = float(_perf_window_accum.get("behavior_tick_total_ms", 0.0)) / float(maxi(behavior_calls, 1))
	var crowd_mode_groups_total: int = int(_perf_window_accum.get("crowd_mode_groups_total", 0))
	var crowd_mode_active_ratio: float = float(_perf_window_accum.get("crowd_mode_active_groups", 0)) / float(maxi(crowd_mode_groups_total, 1))
	var phase1_reduction: Dictionary = _build_phase1_physics_reduction_snapshot(physics_avg)
	return {
		"window_seconds": elapsed,
		"cost_ms": {
			"physics_process_total": float(_perf_window_accum.get("physics_process_total_ms", 0.0)),
			"ally_separation_total": float(_perf_window_accum.get("ally_separation_total_ms", 0.0)),
			"ally_separation_total_ms": float(_perf_window_accum.get("ally_separation_total_ms", 0.0)),
			"behavior_tick_total": float(_perf_window_accum.get("behavior_tick_total_ms", 0.0)),
		},
		"cost_ms_avg": {
			"physics_process_avg": physics_avg,
			"behavior_tick_avg": behavior_avg,
		},
		"counters": {
			"work_units": int(_perf_window_accum.get("work_units", 0)),
			"scan_total": int(_perf_window_accum.get("scan_total", 0)),
			"separation_group_scans": int(_perf_window_accum.get("separation_group_scans", 0)),
			"separation_npc_scans": int(_perf_window_accum.get("separation_npc_scans", 0)),
			"separation_neighbor_checks_total": int(_perf_window_accum.get("separation_neighbor_checks_total", 0)),
			"workers_active_avg": float(_perf_window_accum.get("worker_active_count_samples", 0)) / float(workers_frames),
			"followers_without_task_avg": float(_perf_window_accum.get("followers_without_task_samples", 0)) / float(followers_frames),
			"assignment_conflicts_total": int(_perf_window_accum.get("assignment_conflicts_total", 0)),
			"double_reservations_avoided": int(_perf_window_accum.get("double_reservations_avoided", 0)),
			"expired_reservations": int(_perf_window_accum.get("expired_reservations", 0)),
			"assignment_replans": int(_perf_window_accum.get("assignment_replans", 0)),
			"assault_context_build_ms": float(_perf_window_accum.get("assault_context_build_ms", 0.0)),
			"assault_context_hits": int(_perf_window_accum.get("assault_context_hits", 0)),
			"assault_per_npc_ms_before_after": {
				"before_total_ms": float(_perf_window_accum.get("assault_per_npc_before_total_ms", 0.0)),
				"before_calls": int(_perf_window_accum.get("assault_per_npc_before_calls", 0)),
				"before_avg_ms": float(_perf_window_accum.get("assault_per_npc_before_total_ms", 0.0)) / float(maxi(int(_perf_window_accum.get("assault_per_npc_before_calls", 0)), 1)),
				"after_total_ms": float(_perf_window_accum.get("assault_per_npc_after_total_ms", 0.0)),
				"after_calls": int(_perf_window_accum.get("assault_per_npc_after_calls", 0)),
				"after_avg_ms": float(_perf_window_accum.get("assault_per_npc_after_total_ms", 0.0)) / float(maxi(int(_perf_window_accum.get("assault_per_npc_after_calls", 0)), 1)),
			},
			"profile_full_ratio": float(_perf_window_accum.get("profile_full_count", 0)) / float(profile_samples),
			"profile_obedient_ratio": float(_perf_window_accum.get("profile_obedient_count", 0)) / float(profile_samples),
			"profile_decorative_ratio": float(_perf_window_accum.get("profile_decorative_count", 0)) / float(profile_samples),
			"profile_switches_total": int(_perf_window_accum.get("profile_switches_total", 0)),
			"profile_budget_downgrades": int(_perf_window_accum.get("profile_budget_downgrades", 0)),
			"profile_event_reactivations": int(_perf_window_accum.get("profile_event_reactivations", 0)),
		},
		"comparative_metrics": {
			"ally_separation_total_ms": float(_perf_window_accum.get("ally_separation_total_ms", 0.0)),
			"separation_neighbor_checks_total": int(_perf_window_accum.get("separation_neighbor_checks_total", 0)),
			"crowd_mode_active_ratio": crowd_mode_active_ratio,
		},
		"scan_by_group": scan_by_group.duplicate(true),
		"scan_by_npc": scan_by_npc.duplicate(true),
		"baseline_compare": {
			"phase1_physics_reduction": phase1_reduction,
		},
	}


func save_perf_baseline_snapshot(label: String) -> Dictionary:
	var normalized_label: String = label.strip_edges().to_lower()
	if normalized_label == "":
		normalized_label = "custom"
	var snapshot: Dictionary = {
		"saved_at_unix": Time.get_unix_time_from_system(),
		"window": get_perf_window_snapshot(),
	}
	_perf_baseline_snapshots[normalized_label] = snapshot
	Debug.log("perf_telemetry", "[BanditBehaviorMetrics][baseline_saved] label=%s payload=%s" % [
		normalized_label,
		JSON.stringify(snapshot),
	])
	return snapshot


func get_perf_baseline_snapshots() -> Dictionary:
	return _perf_baseline_snapshots.duplicate(true)


func _ensure_mode_perf_entry(mode: StringName) -> Dictionary:
	var mode_key: String = String(mode)
	if not _lod_mode_perf.has(mode_key):
		_lod_mode_perf[mode_key] = {
			"frame_samples": 0,
			"frame_time_total_ms": 0.0,
			"frame_time_avg_ms": 0.0,
			"reaction_samples": 0,
			"reaction_latency_total_s": 0.0,
			"reaction_latency_avg_s": 0.0,
		}
	return _lod_mode_perf[mode_key]


func _build_phase1_physics_reduction_snapshot(current_physics_avg: float) -> Dictionary:
	var baseline_keys: Array[String] = ["phase_1", "phase1", "fase_1", "fase1", "small"]
	var selected_key: String = ""
	var selected: Dictionary = {}
	for key in baseline_keys:
		if _perf_baseline_snapshots.has(key):
			selected_key = key
			selected = _perf_baseline_snapshots[key] as Dictionary
			break
	if selected.is_empty():
		return {"available": false}
	var window: Dictionary = selected.get("window", {})
	var cost_avg: Dictionary = window.get("cost_ms_avg", {})
	var baseline_physics_avg: float = float(cost_avg.get("physics_process_avg", 0.0))
	if baseline_physics_avg <= 0.0001:
		return {
			"available": false,
			"baseline_label": selected_key,
		}
	var reduction_abs: float = baseline_physics_avg - current_physics_avg
	var reduction_pct: float = (reduction_abs / baseline_physics_avg) * 100.0
	return {
		"available": true,
		"baseline_label": selected_key,
		"baseline_physics_avg_ms": baseline_physics_avg,
		"current_physics_avg_ms": current_physics_avg,
		"reduction_ms": reduction_abs,
		"reduction_pct": reduction_pct,
	}


func _should_emit_sampled_perf_window_log() -> bool:
	return Debug.should_sample("perf_telemetry", "bandit_behavior_perf_window", PERF_WINDOW_LOG_SAMPLE_EVERY_N_WINDOWS)
