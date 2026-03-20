extends RefCounted
class_name BanditTuning

# Centralized runtime tuning for bandit world orchestration.
# Keep group/faction-specific lookups behind helpers so we can branch later
# without hunting hardcoded literals across behavior/director code.

const DEFAULT_FACTION: String = "default"

const FRICTION_COMPENSATION: float = 25.0
const ALERTED_SCOUT_CHASE_SPEED: float = 55.0

const TAUNT_RANGE_SQ: float = 300.0 * 300.0
const COLLECT_RANGE_SQ: float = 160.0 * 160.0
const ABORT_PLAYER_DISTANCE_SQ: float = 6000.0 * 6000.0
const EXTORT_PAY_AMOUNT: int = 10
const EXTORT_TAUNT_BUBBLE_DURATION: float = 3.5
const EXTORT_WARN_MELEE_LOCK_DURATION: float = 7.0
const EXTORT_AI_REENABLE_DELAY: float = 12.0
const EXTORT_WARN_APPROACH_SPEED: float = 75.0
const EXTORT_GROUP_APPROACH_SPEED: float = 55.0
const EXTORT_WARN_STRIKE_RANGE: float = 76.0
const EXTORT_WARN_STRIKE_RANGE_BONUS: float = 8.0

static func faction_for_group(_group_id: String) -> String:
	return DEFAULT_FACTION

static func friction_compensation() -> float:
	return FRICTION_COMPENSATION

static func alerted_scout_chase_speed(_group_id: String = "") -> float:
	return ALERTED_SCOUT_CHASE_SPEED

static func extort_taunt_range_sq(_group_id: String = "") -> float:
	return TAUNT_RANGE_SQ

static func extort_collect_range_sq(_group_id: String = "") -> float:
	return COLLECT_RANGE_SQ

static func extort_abort_distance_sq(_group_id: String = "") -> float:
	return ABORT_PLAYER_DISTANCE_SQ

static func extort_pay_amount(_group_id: String = "") -> int:
	return EXTORT_PAY_AMOUNT

static func extort_taunt_bubble_duration(_group_id: String = "") -> float:
	return EXTORT_TAUNT_BUBBLE_DURATION

static func extort_warn_melee_lock_duration(_group_id: String = "") -> float:
	return EXTORT_WARN_MELEE_LOCK_DURATION

static func extort_ai_reenable_delay(_group_id: String = "") -> float:
	return EXTORT_AI_REENABLE_DELAY

static func extort_warn_approach_speed(_group_id: String = "") -> float:
	return EXTORT_WARN_APPROACH_SPEED

static func extort_group_approach_speed(_group_id: String = "") -> float:
	return EXTORT_GROUP_APPROACH_SPEED

static func extort_warn_strike_range(_group_id: String = "") -> float:
	return EXTORT_WARN_STRIKE_RANGE

static func extort_warn_strike_range_bonus(_group_id: String = "") -> float:
	return EXTORT_WARN_STRIKE_RANGE_BONUS
