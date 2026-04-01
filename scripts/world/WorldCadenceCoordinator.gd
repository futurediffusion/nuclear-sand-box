class_name WorldCadenceCoordinator
extends RefCounted

const DEFAULT_MAX_CATCHUP: int = 2
const RECENT_ACTIVITY_DECAY_WINDOW: float = 5.0

var _lanes: Dictionary = {}
var _time: float = 0.0

func configure_lane(name: StringName, interval: float, phase_ratio: float = 0.0, max_catchup: int = DEFAULT_MAX_CATCHUP) -> void:
	if interval <= 0.0:
		push_warning("WorldCadenceCoordinator lane %s needs interval > 0" % String(name))
		return
	var normalized_phase: float = wrapf(phase_ratio, 0.0, 1.0)
	_lanes[name] = {
		"interval": interval,
		"next_at": interval * normalized_phase,
		"due": 0,
		"max_catchup": maxi(1, max_catchup),
		"recent_consumed": 0.0,
		"recent_catchup": 0.0,
		"last_consumed": 0,
		"total_consumed": 0,
		"last_generated_due": 0,
		"last_catchup_generated": 0,
		"last_tick_time": 0.0,
		"last_consume_time": -1.0,
	}

func reset_time(seed_time: float = 0.0) -> void:
	_time = maxf(0.0, seed_time)
	for lane_name in _lanes.keys():
		var lane: Dictionary = _lanes[lane_name]
		lane["due"] = 0
		var interval: float = float(lane.get("interval", 0.0))
		var phase_ratio: float = 0.0
		if interval > 0.0:
			phase_ratio = fposmod(float(lane.get("next_at", 0.0)), interval) / interval
		lane["next_at"] = _time + interval * phase_ratio
		_lanes[lane_name] = lane

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_time += delta
	for lane_name in _lanes.keys():
		var lane: Dictionary = _lanes[lane_name]
		var interval: float = float(lane.get("interval", 0.0))
		if interval <= 0.0:
			continue
		var due: int = int(lane.get("due", 0))
		var max_catchup: int = int(lane.get("max_catchup", DEFAULT_MAX_CATCHUP))
		var generated_due: int = 0
		while _time >= float(lane.get("next_at", interval)):
			due = mini(max_catchup, due + 1)
			generated_due += 1
			lane["next_at"] = float(lane.get("next_at", interval)) + interval
		if RECENT_ACTIVITY_DECAY_WINDOW > 0.0:
			var decay := clampf(1.0 - (delta / RECENT_ACTIVITY_DECAY_WINDOW), 0.0, 1.0)
			lane["recent_consumed"] = float(lane.get("recent_consumed", 0.0)) * decay
			lane["recent_catchup"] = float(lane.get("recent_catchup", 0.0)) * decay
		lane["due"] = due
		lane["last_generated_due"] = generated_due
		lane["last_catchup_generated"] = maxi(0, generated_due - 1)
		lane["last_tick_time"] = _time
		_lanes[lane_name] = lane

func consume_lane(name: StringName) -> int:
	if not _lanes.has(name):
		return 0
	var lane: Dictionary = _lanes[name]
	var due: int = int(lane.get("due", 0))
	lane["due"] = 0
	lane["last_consumed"] = due
	lane["total_consumed"] = int(lane.get("total_consumed", 0)) + due
	lane["recent_consumed"] = float(lane.get("recent_consumed", 0.0)) + float(due)
	if due > 1:
		lane["recent_catchup"] = float(lane.get("recent_catchup", 0.0)) + float(due - 1)
	lane["last_consume_time"] = _time
	_lanes[name] = lane
	return due

## Cadence interface boundary: "when to run".
## Returns how many pulses should run now for this lane and consumes them.
func when_to_run(name: StringName) -> int:
	return consume_lane(name)


func lane_due(name: StringName) -> int:
	if not _lanes.has(name):
		return 0
	return int(_lanes[name].get("due", 0))


## Cadence interface boundary: "when to run".
## Non-consuming peek for due pulses in the lane.
func when_due(name: StringName) -> int:
	return lane_due(name)


func get_debug_snapshot() -> Dictionary:
	var lanes: Dictionary = {}
	for lane_name in _lanes.keys():
		var lane: Dictionary = _lanes[lane_name]
		var next_at: float = float(lane.get("next_at", _time))
		var recent_consumed: float = float(lane.get("recent_consumed", 0.0))
		var activity: String = "warm"
		if recent_consumed <= 0.25:
			activity = "inactive"
		elif recent_consumed >= 3.0:
			activity = "hot"
		lanes[String(lane_name)] = {
			"interval": float(lane.get("interval", 0.0)),
			"due": int(lane.get("due", 0)),
			"next_in": maxf(next_at - _time, 0.0),
			"recent_consumed": snappedf(recent_consumed, 0.01),
			"recent_catchup": snappedf(float(lane.get("recent_catchup", 0.0)), 0.01),
			"last_consumed": int(lane.get("last_consumed", 0)),
			"last_generated_due": int(lane.get("last_generated_due", 0)),
			"last_catchup_generated": int(lane.get("last_catchup_generated", 0)),
			"total_consumed": int(lane.get("total_consumed", 0)),
			"activity": activity,
		}
	return {
		"time": _time,
		"lane_count": _lanes.size(),
		"lanes": lanes,
	}
