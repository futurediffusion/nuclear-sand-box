class_name PlacementPerfTelemetry
extends RefCounted

const _WINDOW_MSEC: int = 1000
const _LOG_CATEGORY: String = "perf_telemetry"

static var _window_start_msec: int = 0
static var _window_event_count: int = 0
static var _stage_totals_usec: Dictionary = {}
static var _stage_counts: Dictionary = {}
static var _lane_totals_usec: Dictionary = {
	"collider": 0,
	"ia": 0,
	"other": 0,
}
static var _counter_totals: Dictionary = {
	"tiles_affected": 0,
	"chunks_enqueued": 0,
	"rebuilds_executed": 0,
}


static func record_stage(stage: String, duration_usec: int, metrics: Dictionary = {}, lane: String = "other") -> void:
	var now_msec: int = Time.get_ticks_msec()
	_ensure_window_initialized(now_msec)
	_roll_window_if_needed(now_msec)

	var stage_key: String = stage.strip_edges()
	if stage_key == "":
		stage_key = "unknown_stage"
	var safe_duration: int = maxi(duration_usec, 0)
	_stage_totals_usec[stage_key] = int(_stage_totals_usec.get(stage_key, 0)) + safe_duration
	_stage_counts[stage_key] = int(_stage_counts.get(stage_key, 0)) + 1
	_window_event_count += 1

	var lane_key: String = lane.strip_edges()
	if not _lane_totals_usec.has(lane_key):
		_lane_totals_usec[lane_key] = 0
	_lane_totals_usec[lane_key] = int(_lane_totals_usec.get(lane_key, 0)) + safe_duration

	_counter_totals["tiles_affected"] = int(_counter_totals.get("tiles_affected", 0)) + int(metrics.get("tiles_affected", 0))
	_counter_totals["chunks_enqueued"] = int(_counter_totals.get("chunks_enqueued", 0)) + int(metrics.get("chunks_enqueued", 0))
	_counter_totals["rebuilds_executed"] = int(_counter_totals.get("rebuilds_executed", 0)) + int(metrics.get("rebuilds_executed", 0))


static func _ensure_window_initialized(now_msec: int) -> void:
	if _window_start_msec <= 0:
		_window_start_msec = now_msec


static func _roll_window_if_needed(now_msec: int) -> void:
	if now_msec - _window_start_msec < _WINDOW_MSEC:
		return
	_flush_window(now_msec)
	_reset_window(now_msec)


static func _flush_window(now_msec: int) -> void:
	if _window_event_count <= 0:
		return
	var elapsed_msec: int = maxi(now_msec - _window_start_msec, 1)
	var elapsed_sec: float = float(elapsed_msec) / 1000.0
	var collider_ms: float = float(_lane_totals_usec.get("collider", 0)) / 1000.0
	var ia_ms: float = float(_lane_totals_usec.get("ia", 0)) / 1000.0
	var dominant: String = "collider_rebuild" if collider_ms >= ia_ms else "ia"
	var stage_ms_total: Dictionary = {}
	for stage_name in _stage_totals_usec.keys():
		stage_ms_total[stage_name] = float(_stage_totals_usec.get(stage_name, 0)) / 1000.0
	var payload: Dictionary = {
		"window_sec": elapsed_sec,
		"events": _window_event_count,
		"counters": {
			"tiles_affected": int(_counter_totals.get("tiles_affected", 0)),
			"chunks_enqueued": int(_counter_totals.get("chunks_enqueued", 0)),
			"rebuilds_executed": int(_counter_totals.get("rebuilds_executed", 0)),
		},
		"time_ms": {
			"collider": collider_ms,
			"ia": ia_ms,
			"other": float(_lane_totals_usec.get("other", 0)) / 1000.0,
			"per_stage": stage_ms_total,
		},
		"dominant_bottleneck": dominant,
	}
	Debug.log(_LOG_CATEGORY, "[PlacementPerf][1s] %s" % JSON.stringify(payload))


static func _reset_window(now_msec: int) -> void:
	_window_start_msec = now_msec
	_window_event_count = 0
	_stage_totals_usec.clear()
	_stage_counts.clear()
	_lane_totals_usec = {
		"collider": 0,
		"ia": 0,
		"other": 0,
	}
	_counter_totals = {
		"tiles_affected": 0,
		"chunks_enqueued": 0,
		"rebuilds_executed": 0,
	}
