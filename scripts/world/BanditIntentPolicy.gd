extends RefCounted
class_name BanditIntentPolicy

# Responsibility boundary:
# BanditIntentPolicy owns social intent policy for bandit groups.
# It translates scan score + persistent faction state into effective thresholds,
# next intent, and social-action eligibility. It does not scan the world, mutate
# BanditGroupMemory, enqueue flows, or persist hostility outside FactionHostilityManager.

const EXTORT_SCORE_THRESHOLD: float = 3.0

static func evaluate(base_score: float,
		profile: FactionBehaviorProfile,
		wealth_tier: int,
		current_intent: String,
		intent_time: float = 0.0,
		internal_cooldown: float = 0.0) -> Dictionary:
	var effective_score: float = base_score * (1.0 + profile.heat_modifier * 0.6)
	var effective_alerted_threshold: float = maxf(
		BanditTuning.alerted_threshold() - FactionHostilityManager.WEALTH_TERRITORIAL_BONUS[wealth_tier],
		BanditTuning.minimum_alerted_threshold())
	var effective_hunting_threshold: float = maxf(
		BanditTuning.hunting_threshold() - float(profile.hostility_level) * 0.4,
		BanditTuning.minimum_hunting_threshold())

	if profile.hostility_level >= 10:
		effective_score = maxf(effective_score, effective_hunting_threshold + 1.0)
	elif profile.hostility_level >= 9 and base_score > 0.0:
		effective_score = maxf(effective_score, effective_hunting_threshold + 0.1)

	var next_intent: String = _pick_next_intent(
		effective_score,
		effective_alerted_threshold,
		effective_hunting_threshold,
		profile,
		base_score,
		current_intent,
		intent_time)
	var hyst_floor: float = BanditTuning.alerted_release_threshold()
	if current_intent == "alerted" and next_intent == "idle" and effective_score >= hyst_floor:
		next_intent = "alerted"

	var can_extort_now: bool = profile.can_extort and not profile.can_knockout 		and base_score >= EXTORT_SCORE_THRESHOLD and internal_cooldown <= 0.0
	var can_full_raid_now: bool = profile.can_raid_base and internal_cooldown <= 0.0
	var can_light_raid_now: bool = profile.can_damage_workbenches and not can_full_raid_now 		and internal_cooldown <= 0.0

	return {
		"effective_score": effective_score,
		"next_intent": next_intent,
		"effective_alerted_threshold": effective_alerted_threshold,
		"effective_hunting_threshold": effective_hunting_threshold,
		"can_extort_now": can_extort_now,
		"can_light_raid_now": can_light_raid_now,
		"can_full_raid_now": can_full_raid_now,
	}


static func _pick_next_intent(effective_score: float,
		effective_alerted_threshold: float,
		effective_hunting_threshold: float,
		profile: FactionBehaviorProfile,
		base_score: float,
		current_intent: String,
		intent_time: float) -> String:
	var next_intent: String = "idle"
	if effective_score >= effective_hunting_threshold:
		next_intent = "hunting"
	elif effective_score >= effective_alerted_threshold:
		next_intent = "alerted"

	if profile.hostility_level >= 7 and next_intent == "idle" and base_score > 0.0:
		next_intent = "alerted"

	if current_intent == "hunting" and next_intent == "alerted" 		and effective_score >= BanditTuning.hunting_release_threshold() and intent_time < BanditTuning.intent_hysteresis_grace():
		return "hunting"
	if current_intent == "alerted" and next_intent == "idle" 		and effective_score >= BanditTuning.alerted_release_threshold() and intent_time < BanditTuning.intent_hysteresis_grace():
		return "alerted"
	return next_intent
