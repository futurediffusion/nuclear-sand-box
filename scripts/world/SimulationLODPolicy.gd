extends RefCounted
class_name SimulationLODPolicy

# Small temporal-priority layer on top of cadence.
# It does not schedule systems globally; it only tells callers how often to
# reevaluate non-critical thinking based on current relevance.
#
# Strong signals:
# - direct combat / active target pressure
# - recently engaged
# - high-pressure group intent (raiding/extorting/hunting)
#
# Medium signals:
# - distance to player
# - on-screen visibility
# - carrying cargo / explicit travel states
#
# Soft/context heuristics:
# - base/player settlement signal presence
# - leader/role bias
# - sleeping / idle slowdown bias

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
const ACTIVE_WORK_LOOP_MAX_INTERVAL: float = 0.35
const WORKER_PRIORITY_TICK_INTERVAL: float = 0.25
const MODE_CONTEXTUAL: StringName = &"contextual"
const MODE_EXPLORATION_NORMAL: StringName = &"exploration_normal"
const MODE_COMBAT_CLOSE: StringName = &"combat_close"
const MODE_RAID_ACTIVE: StringName = &"raid_active"
const MODE_INTERVAL_PRESETS: Dictionary = {
	MODE_EXPLORATION_NORMAL: {"group": 1.15, "npc": 1.10},
	MODE_COMBAT_CLOSE: {"group": 0.72, "npc": 0.68},
	MODE_RAID_ACTIVE: {"group": 0.58, "npc": 0.62},
}
static var _worker_priority_enabled: bool = true


static func set_worker_priority_enabled(enabled: bool) -> void:
	_worker_priority_enabled = enabled


static func is_worker_priority_enabled() -> bool:
	return _worker_priority_enabled

static func get_bandit_group_scan_interval(ctx: Dictionary) -> float:
	return float(get_bandit_group_scan_debug(ctx).get("interval", BanditTuning.group_scan_interval()))


static func get_bandit_group_scan_debug(ctx: Dictionary) -> Dictionary:
	var base_interval: float = maxf(float(ctx.get("base_interval", BanditTuning.group_scan_interval())), 0.1)
	var distance_to_player: float = maxf(float(ctx.get("distance_to_player", INF)), 0.0)
	var intent: String = String(ctx.get("intent", "idle"))
	var is_visible: bool = bool(ctx.get("is_visible", false))
	var in_combat: bool = bool(ctx.get("in_combat", false))
	var recently_engaged: bool = bool(ctx.get("recently_engaged", false))
	var has_player_signal: bool = bool(ctx.get("has_player_signal", false))
	var has_base_signal: bool = bool(ctx.get("has_base_signal", false))

	var multiplier: float = 1.0
	var reasons: Array[String] = []
	match intent:
		"raiding":
			multiplier = 0.25
			reasons.append("intent_raiding")
		"extorting":
			multiplier = 0.4
			reasons.append("intent_extorting")
		"hunting":
			multiplier = 0.5
			reasons.append("intent_hunting")
		"alerted":
			multiplier = 0.7
			reasons.append("intent_alerted")
		_:
			multiplier = 1.0

	if in_combat:
		multiplier = minf(multiplier, 0.3)
		reasons.push_front("direct_combat")
	elif recently_engaged:
		multiplier = minf(multiplier, 0.5)
		reasons.push_front("recently_engaged")

	if distance_to_player <= GROUP_NEAR_DISTANCE:
		multiplier *= 0.55
		reasons.append("player_near")
	elif distance_to_player <= GROUP_MID_DISTANCE:
		multiplier *= 0.85
		reasons.append("player_mid")
	elif distance_to_player >= GROUP_FAR_DISTANCE:
		multiplier *= 1.6
		reasons.append("player_far")
	else:
		multiplier *= 1.15
		reasons.append("player_outer_mid")

	if is_visible:
		multiplier *= 0.8
		reasons.append("visible")
	if has_player_signal:
		multiplier *= 0.8
		reasons.append("player_signal")
	if has_base_signal:
		multiplier *= 0.85
		reasons.append("base_signal")

	if intent == "idle" and distance_to_player >= GROUP_FAR_DISTANCE and not has_player_signal and not has_base_signal and not recently_engaged:
		multiplier *= 1.25
		reasons.append("idle_far_bias")

	var mode: StringName = resolve_interval_mode(ctx)
	var mode_multiplier: float = _get_mode_multiplier(mode, "group")
	var interval: float = clampf(base_interval * multiplier * mode_multiplier, MIN_GROUP_SCAN_INTERVAL, MAX_GROUP_SCAN_INTERVAL)
	if mode != MODE_CONTEXTUAL:
		reasons.push_front("mode_%s" % String(mode))
	return {
		"interval": interval,
		"multiplier": multiplier,
		"mode_multiplier": mode_multiplier,
		"mode": String(mode),
		"dominant_reason": reasons[0] if not reasons.is_empty() else "baseline",
		"reasons": reasons,
		"bucket": _classify_bucket(interval, base_interval),
	}


static func get_behavior_tick_interval(ctx: Dictionary) -> float:
	return float(get_behavior_tick_debug(ctx).get("interval", BanditTuning.behavior_tick_interval()))


static func get_behavior_tick_debug(ctx: Dictionary) -> Dictionary:
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
	var is_worker_cycle_active: bool = bool(ctx.get("is_worker_cycle_active", false))

	var multiplier: float = 1.0
	var reasons: Array[String] = []
	if is_worker_cycle_active and _worker_priority_enabled:
		var worker_interval: float = clampf(WORKER_PRIORITY_TICK_INTERVAL, MIN_BEHAVIOR_TICK_INTERVAL, ACTIVE_WORK_LOOP_MAX_INTERVAL)
		reasons.append("worker_priority")
		return {
			"interval": worker_interval,
			"multiplier": 1.0,
			"mode_multiplier": 1.0,
			"mode": String(resolve_interval_mode(ctx)),
			"dominant_reason": "worker_priority",
			"reasons": reasons,
			"bucket": _classify_bucket(worker_interval, base_interval),
			"is_worker_cycle_active": true,
			"worker_priority_enabled": true,
		}
	if is_worker_cycle_active and not _worker_priority_enabled:
		reasons.append("worker_priority_disabled")
	match intent:
		"raiding":
			multiplier = 0.5
			reasons.append("intent_raiding")
		"extorting":
			multiplier = 0.6
			reasons.append("intent_extorting")
		"hunting":
			multiplier = 0.7
			reasons.append("intent_hunting")
		"alerted":
			multiplier = 0.85
			reasons.append("intent_alerted")
		_:
			multiplier = 1.0

	if in_combat:
		multiplier = minf(multiplier, 0.5)
		reasons.push_front("direct_combat")
	elif recently_engaged:
		multiplier = minf(multiplier, 0.7)
		reasons.push_front("recently_engaged")

	if state_name == "RETURN_HOME" or state_name == "LOOT_APPROACH" or state_name == "APPROACH_INTEREST" or state_name == "RESOURCE_WATCH":
		multiplier *= 0.8
		reasons.append("active_world_task")
	elif state_name == "IDLE_AT_HOME" and is_sleeping:
		multiplier *= 1.15
		reasons.append("idle_sleep_bias")

	if has_cargo:
		multiplier *= 0.8
		reasons.append("has_cargo")
	if role == "leader":
		multiplier *= 0.9
		reasons.append("leader_bias")

	if distance_to_player <= ACTOR_NEAR_DISTANCE:
		multiplier *= 0.65
		reasons.append("player_near")
	elif distance_to_player <= ACTOR_MID_DISTANCE:
		multiplier *= 0.9
		reasons.append("player_mid")
	elif distance_to_player >= ACTOR_FAR_DISTANCE:
		multiplier *= 1.5
		reasons.append("player_far")
	else:
		multiplier *= 1.15
		reasons.append("player_outer_mid")

	if is_visible:
		multiplier *= 0.85
		reasons.append("visible")
	if intent == "idle" and distance_to_player >= ACTOR_FAR_DISTANCE and is_sleeping and not has_cargo and not recently_engaged:
		multiplier *= 1.15
		reasons.append("idle_far_sleep_bias")

	var mode: StringName = resolve_interval_mode(ctx)
	var mode_multiplier: float = _get_mode_multiplier(mode, "npc")
	var interval: float = clampf(base_interval * multiplier * mode_multiplier, MIN_BEHAVIOR_TICK_INTERVAL, MAX_BEHAVIOR_TICK_INTERVAL)
	# Floor de distancia: un NPC a >FAR no puede tickear más rápido que slow,
	# sin importar intent ni estado de combate — a esa distancia no hay combate real posible.
	if distance_to_player >= ACTOR_FAR_DISTANCE:
		interval = maxf(interval, base_interval * 1.6)
		reasons.push_front("distance_floor")
	if mode != MODE_CONTEXTUAL:
		reasons.push_front("mode_%s" % String(mode))
	# Work-loop continuity guard:
	# mining/pickup/return/deposit must not drift into slow LOD buckets even when
	# far from player; we cap only active logistics states to keep responsiveness.
	var is_active_work_loop: bool = state_name == "RESOURCE_WATCH" \
			or state_name == "LOOT_APPROACH" \
			or state_name == "RETURN_HOME" \
			or has_cargo
	if is_active_work_loop:
		interval = minf(interval, ACTIVE_WORK_LOOP_MAX_INTERVAL)
		reasons.push_front("work_loop_cap")
	return {
		"interval": interval,
		"multiplier": multiplier,
		"mode_multiplier": mode_multiplier,
		"mode": String(mode),
		"dominant_reason": reasons[0] if not reasons.is_empty() else "baseline",
		"reasons": reasons,
		"bucket": _classify_bucket(interval, base_interval),
		"is_worker_cycle_active": is_worker_cycle_active,
		"worker_priority_enabled": _worker_priority_enabled,
	}


static func was_recently_engaged(last_engaged_time: float, now: float = RunClock.now()) -> bool:
	if last_engaged_time <= 0.0:
		return false
	return now - last_engaged_time <= RECENT_COMBAT_WINDOW


static func _classify_bucket(interval: float, base_interval: float) -> String:
	if interval <= base_interval * 0.75:
		return "fast"
	if interval <= base_interval * 1.15:
		return "medium"
	return "slow"


static func resolve_interval_mode(ctx: Dictionary) -> StringName:
	var mode_signals: Dictionary = ctx.get("mode_signals", {})
	if bool(mode_signals.get(MODE_RAID_ACTIVE, false)) or bool(mode_signals.get(String(MODE_RAID_ACTIVE), false)):
		return MODE_RAID_ACTIVE
	if bool(mode_signals.get(MODE_COMBAT_CLOSE, false)) or bool(mode_signals.get(String(MODE_COMBAT_CLOSE), false)):
		return MODE_COMBAT_CLOSE
	if bool(mode_signals.get(MODE_EXPLORATION_NORMAL, false)) or bool(mode_signals.get(String(MODE_EXPLORATION_NORMAL), false)):
		return MODE_EXPLORATION_NORMAL
	return MODE_CONTEXTUAL


static func _get_mode_multiplier(mode: StringName, lane: String) -> float:
	var preset: Dictionary = MODE_INTERVAL_PRESETS.get(mode, {})
	return maxf(float(preset.get(lane, 1.0)), 0.2)
