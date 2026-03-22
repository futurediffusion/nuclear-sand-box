class_name WorldCadenceCoordinator
extends RefCounted

const DEFAULT_MAX_CATCHUP: int = 2

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
		while _time >= float(lane.get("next_at", interval)):
			due = mini(max_catchup, due + 1)
			lane["next_at"] = float(lane.get("next_at", interval)) + interval
		lane["due"] = due
		_lanes[lane_name] = lane

func consume_lane(name: StringName) -> int:
	if not _lanes.has(name):
		return 0
	var lane: Dictionary = _lanes[name]
	var due: int = int(lane.get("due", 0))
	lane["due"] = 0
	_lanes[name] = lane
	return due

func lane_due(name: StringName) -> int:
	if not _lanes.has(name):
		return 0
	return int(_lanes[name].get("due", 0))
