extends RefCounted
class_name SimulationLODPolicy

# Small temporal-priority layer on top of cadence.
# It does not schedule systems globally; it only tells callers how often to
# reevaluate non-critical thinking based on current relevance.

const GROUP_NEAR_DISTANCE: float = 320.0
const GROUP_MID_DISTANCE: float = 768.0
const GROUP_FAR_DISTANCE: float = 1600.0

const ACTOR_NEAR_DISTANCE: float = 260.0
const ACTOR_MID_DISTANCE: float = 620.0
const ACTOR_FAR_DISTANCE: float = 1200.0

const RECENT_COMBAT_WINDOW: float = 10.0
const MIN_GROUP_SCAN_INTERVAL: float = 2.0
const MAX_GROUP_SCAN_INTERVAL: float = 16.0
const MIN_BEHAVIOR_TICK_INTERVAL: float = 0.25
const MAX_BEHAVIOR_TICK_INTERVAL: float = 1.5

static func get_bandit_group_scan_interval(ctx: Dictionary) -> float:
	var base_interval: float = maxf(float(ctx.get("base_interval", BanditTuning.group_scan_interval())), 0.1)
	var distance_to_player: float = maxf(float(ctx.get("distance_to_player", INF)), 0.0)
	var intent: String = String(ctx.get("intent", "idle"))
	var is_visible: bool = bool(ctx.get("is_visible", false))
	var in_combat: bool = bool(ctx.get("in_combat", false))
	var recently_engaged: bool = bool(ctx.get("recently_engaged", false))
	var has_player_signal: bool = bool(ctx.get("has_player_signal", false))
	var has_base_signal: bool = bool(ctx.get("has_base_signal", false))

	var multiplier: float = 1.0
	match intent:
		"raiding":
			multiplier = 0.25
		"extorting":
			multiplier = 0.4
		"hunting":
			multiplier = 0.5
		"alerted":
			multiplier = 0.7
		_:
			multiplier = 1.0

	if in_combat:
		multiplier = minf(multiplier, 0.3)
	elif recently_engaged:
		multiplier = minf(multiplier, 0.5)

	if distance_to_player <= GROUP_NEAR_DISTANCE:
		multiplier *= 0.55
	elif distance_to_player <= GROUP_MID_DISTANCE:
		multiplier *= 0.85
	elif distance_to_player >= GROUP_FAR_DISTANCE:
		multiplier *= 1.6
	else:
		multiplier *= 1.15

	if is_visible:
		multiplier *= 0.8
	if has_player_signal:
		multiplier *= 0.8
	if has_base_signal:
		multiplier *= 0.85

	if intent == "idle" and distance_to_player >= GROUP_FAR_DISTANCE and not has_player_signal and not has_base_signal and not recently_engaged:
		multiplier *= 1.25

	return clampf(base_interval * multiplier, MIN_GROUP_SCAN_INTERVAL, MAX_GROUP_SCAN_INTERVAL)


static func get_behavior_tick_interval(ctx: Dictionary) -> float:
	var base_interval: float = maxf(float(ctx.get("base_interval", BanditTuning.behavior_tick_interval())), 0.05)
	var distance_to_player: float = maxf(float(ctx.get("distance_to_player", INF)), 0.0)
	var intent: String = String(ctx.get("intent", "idle"))
	var role: String = String(ctx.get("role", "scavenger"))
	var state_name: String = String(ctx.get("state_name", ""))
	var has_cargo: bool = bool(ctx.get("has_cargo", false))
	var is_visible: bool = bool(ctx.get("is_visible", false))
	var is_sleeping: bool = bool(ctx.get("is_sleeping", false))
	var in_combat: bool = bool(ctx.get("in_combat", false))
	var recently_engaged: bool = bool(ctx.get("recently_engaged", false))

	var multiplier: float = 1.0
	match intent:
		"raiding":
			multiplier = 0.5
		"extorting":
			multiplier = 0.6
		"hunting":
			multiplier = 0.7
		"alerted":
			multiplier = 0.85
		_:
			multiplier = 1.0

	if in_combat:
		multiplier = minf(multiplier, 0.5)
	elif recently_engaged:
		multiplier = minf(multiplier, 0.7)

	if state_name == "RETURN_HOME" or state_name == "LOOT_APPROACH" or state_name == "APPROACH_INTEREST" or state_name == "RESOURCE_WATCH":
		multiplier *= 0.8
	elif state_name == "IDLE_AT_HOME" and is_sleeping:
		multiplier *= 1.15

	if has_cargo:
		multiplier *= 0.8
	if role == "leader":
		multiplier *= 0.9

	if distance_to_player <= ACTOR_NEAR_DISTANCE:
		multiplier *= 0.65
	elif distance_to_player <= ACTOR_MID_DISTANCE:
		multiplier *= 0.9
	elif distance_to_player >= ACTOR_FAR_DISTANCE:
		multiplier *= 1.5
	else:
		multiplier *= 1.15

	if is_visible:
		multiplier *= 0.85
	if intent == "idle" and distance_to_player >= ACTOR_FAR_DISTANCE and is_sleeping and not has_cargo and not recently_engaged:
		multiplier *= 1.15

	return clampf(base_interval * multiplier, MIN_BEHAVIOR_TICK_INTERVAL, MAX_BEHAVIOR_TICK_INTERVAL)


static func was_recently_engaged(last_engaged_time: float, now: float = RunClock.now()) -> bool:
	if last_engaged_time <= 0.0:
		return false
	return now - last_engaged_time <= RECENT_COMBAT_WINDOW
