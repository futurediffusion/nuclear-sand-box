extends RefCounted
class_name BanditIntentSystem

## Canonical bandit intent-decision layer.
## Converts perception + current state/context into traceable intent records.
## This service only publishes intent records/state; it never executes movement/combat.

const INTENT_KIND_PLACEMENT_REACTION := "placement_reaction_assault_target"
const DECISION_CONTINUE_WORK := "continue_current_work"
const DECISION_REACT_THREAT := "react_to_threat"
const DECISION_PURSUE_TARGET := "pursue_target"
const DECISION_RETURN_HOME := "return_home"
const DECISION_STRUCTURE_ASSAULT := "structure_assault_focus"
const DECISION_LOOT_RESOURCE := "loot_resource_interest"

const PRIORITY_VALUE_BY_LABEL := {
	"none": 0,
	"low": 1,
	"medium": 2,
	"high": 3,
	"critical": 4,
}

var _group_memory: Object
var _now_provider: Callable = Callable(RunClock, "now")


func setup(config: Dictionary = {}) -> void:
	_group_memory = config.get("group_memory", BanditGroupMemory) as Object
	var maybe_now: Variant = config.get("now_provider", Callable())
	if maybe_now is Callable and (maybe_now as Callable).is_valid():
		_now_provider = maybe_now as Callable


func decide_group_intent(perception: Dictionary, current_state: Dictionary, context: Dictionary = {}) -> Dictionary:
	var now: float = _read_now()
	var current_mode: String = String(current_state.get("current_group_intent", "idle"))
	var recommended_mode: String = String(context.get("policy_next_intent", current_mode))
	if recommended_mode.is_empty():
		recommended_mode = current_mode
	var placement_lock: bool = bool(current_state.get("has_placement_react_lock", false))
	if placement_lock and recommended_mode == "idle":
		recommended_mode = current_mode

	var threat_signals: Dictionary = perception.get("threat_signals", {}) as Dictionary
	var threat_detected: bool = bool(threat_signals.get("threat_detected", false))
	var has_assault_target: bool = bool(perception.get("has_assault_target", false))
	var loot_count: int = int(perception.get("nearby_loot_count", 0))
	var resource_count: int = int(perception.get("nearby_resource_count", 0))
	var should_return_home: bool = bool(context.get("should_return_home", false))

	var decision_type: String = DECISION_CONTINUE_WORK
	match recommended_mode:
		"raiding":
			decision_type = DECISION_STRUCTURE_ASSAULT if has_assault_target else DECISION_PURSUE_TARGET
		"hunting", "extorting":
			decision_type = DECISION_PURSUE_TARGET
		"alerted":
			decision_type = DECISION_REACT_THREAT
		"idle":
			if should_return_home:
				decision_type = DECISION_RETURN_HOME
			elif loot_count > 0 or resource_count > 0:
				decision_type = DECISION_LOOT_RESOURCE
			else:
				decision_type = DECISION_CONTINUE_WORK
		_:
			decision_type = DECISION_REACT_THREAT if threat_detected else DECISION_CONTINUE_WORK

	return {
		"kind": "group_intent_decision",
		"group_mode": recommended_mode,
		"decision_type": decision_type,
		"reason": String(context.get("reason", "policy_driven")),
		"source": String(context.get("source", "bandit_group_intel")),
		"trace": {
			"at": now,
			"current_mode": current_mode,
			"recommended_mode": recommended_mode,
			"threat_detected": threat_detected,
			"placement_lock": placement_lock,
			"has_assault_target": has_assault_target,
			"nearby_loot_count": loot_count,
			"nearby_resource_count": resource_count,
		},
	}


func apply_group_intent_record(group_id: String, intent_record: Dictionary, options: Dictionary = {}) -> Dictionary:
	if _group_memory == null or group_id.is_empty() or intent_record.is_empty():
		return {"applied": false, "group_id": group_id, "reason": "invalid_input"}
	var group_mode: String = String(intent_record.get("group_mode", "idle"))
	var source: String = String(options.get("source", "bandit_intent_system"))
	_group_memory.call("bb_write_group_mode", group_id, group_mode, source)
	_group_memory.call("update_intent", group_id, group_mode)
	_group_memory.call(
		"bb_set_status",
		group_id,
		"canonical_intent_record",
		intent_record.duplicate(true),
		BanditGroupMemory.BLACKBOARD_STATUS_TTL,
		source
	)
	return {
		"applied": true,
		"group_id": group_id,
		"group_mode": group_mode,
		"decision_type": String(intent_record.get("decision_type", DECISION_CONTINUE_WORK)),
	}


func publish_placement_reaction_intent(assessment: Dictionary, candidate: Dictionary,
		options: Dictionary = {}) -> Dictionary:
	var gid: String = String(candidate.get("group_id", candidate.get("gid", "")))
	var target_pos: Vector2 = assessment.get("target_position", Vector2.ZERO) as Vector2
	var anchor_pos: Vector2 = candidate.get("anchor_position", target_pos) as Vector2
	if gid.is_empty() or not target_pos.is_finite():
		return {
			"status": "invalid",
			"published": false,
			"group_id": gid,
			"intent": {},
		}
	if not anchor_pos.is_finite():
		anchor_pos = target_pos

	var score: float = clampf(float(candidate.get("score", 0.0)), 0.0, 1.0)
	var anchor_distance: float = maxf(0.0, float(candidate.get("anchor_distance", INF)))
	var lock_min_relevance_delta: float = maxf(0.0, float(options.get("lock_min_relevance_delta", 0.0)))
	var lock_min_distance_delta: float = maxf(0.0, float(options.get("lock_min_distance_delta_px", 0.0)))
	var lock_seconds: float = maxf(0.0, float(options.get("lock_seconds", 90.0)))
	var squad_size: int = maxi(1, int(options.get("squad_size", 1)))
	var ttl_seconds: float = maxf(0.0, float(options.get("ttl_seconds", 90.0)))
	var reason_source: String = String(options.get("reason_source", "placement_reaction"))
	var reason: String = "%s:squad=%d" % [reason_source, squad_size]
	var source: String = String(options.get(
		"source",
		BanditGroupMemory.ASSAULT_INTENT_SOURCE_PLACEMENT_REACT
	))
	var now: float = _read_now()
	var priority_label: String = String(assessment.get("priority", "none"))
	var priority_value: int = int(PRIORITY_VALUE_BY_LABEL.get(priority_label, 0))
	var lifecycle: Dictionary = {
		"created_at": now,
		"ttl_seconds": ttl_seconds,
		"expires_at": now + ttl_seconds,
	}
	var canonical_intent: Dictionary = {
		"kind": INTENT_KIND_PLACEMENT_REACTION,
		"group_id": gid,
		"target_position": target_pos,
		"anchor_position": anchor_pos,
		"priority": {
			"label": priority_label,
			"value": priority_value,
			"score": score,
		},
		"reason": reason,
		"source": source,
		"lifecycle": lifecycle,
		"origin_event_ref": _build_origin_event_ref(assessment, options),
		"assessment": {
			"severity": float(assessment.get("severity", 0.0)),
			"debug": assessment.get("debug", {}).duplicate(true),
		},
		"publication": {
			"path": "BanditGroupMemory.publish_assault_target_intent",
			"publisher": "BanditIntentSystem.publish_placement_reaction_intent",
		},
	}

	if _group_memory == null:
		return {
			"status": "missing_group_memory",
			"published": false,
			"group_id": gid,
			"intent": canonical_intent,
		}

	var lock_active: bool = _group_memory.call("has_placement_react_lock", gid)
	if lock_active:
		var last_attempt: Dictionary = _group_memory.call("get_placement_react_attempt", gid) as Dictionary
		var last_score: float = float(last_attempt.get("score", -1.0))
		var last_dist: float = float(last_attempt.get("anchor_distance", INF))
		var score_delta: float = score - last_score
		var dist_delta: float = last_dist - anchor_distance
		var improves_relevance: bool = score_delta >= lock_min_relevance_delta
		var improves_distance: bool = dist_delta >= lock_min_distance_delta
		if not improves_relevance and not improves_distance:
			return {
				"status": "ignored_by_lock",
				"published": false,
				"group_id": gid,
				"lock_active": true,
				"anchor_kind": String(candidate.get("anchor_kind", "unknown")),
				"score": score,
				"previous_score": last_score,
				"score_delta": score_delta,
				"anchor_distance": anchor_distance,
				"previous_anchor_distance": last_dist,
				"anchor_distance_delta": dist_delta,
				"intent": canonical_intent,
			}

	_group_memory.call("record_interest", gid, target_pos, "structure_placed")
	_group_memory.call("set_placement_react_lock", gid, lock_seconds)
	_group_memory.call("set_placement_react_attempt", gid, target_pos, score, anchor_distance)
	_group_memory.call("update_intent", gid, "raiding")
	var published: bool = bool(_group_memory.call(
		"publish_assault_target_intent",
		gid,
		anchor_pos,
		target_pos,
		reason,
		ttl_seconds,
		source
	))
	canonical_intent["publication_result"] = {
		"published": published,
		"published_at": _read_now(),
	}

	return {
		"status": "published" if published else "suppressed",
		"published": published,
		"group_id": gid,
		"anchor_kind": String(candidate.get("anchor_kind", "unknown")),
		"score": score,
		"intent": canonical_intent,
	}


func _read_now() -> float:
	if _now_provider.is_valid():
		return float(_now_provider.call())
	return RunClock.now()


func _build_origin_event_ref(assessment: Dictionary, options: Dictionary) -> Dictionary:
	var source_event: Dictionary = assessment.get("source_event", {}) as Dictionary
	var provided_ref: Dictionary = options.get("origin_event_ref", {}) as Dictionary
	return {
		"event_type": String(source_event.get("event_type", provided_ref.get("event_type", "placement_completed"))),
		"item_id": String(source_event.get("item_id", provided_ref.get("item_id", ""))),
		"tile_pos": source_event.get("tile_pos", provided_ref.get("tile_pos", Vector2i.ZERO)),
		"world_pos": source_event.get("world_pos", provided_ref.get("world_pos", assessment.get("target_position", Vector2.ZERO))),
		"metadata": source_event.get("metadata", provided_ref.get("metadata", {})),
	}
