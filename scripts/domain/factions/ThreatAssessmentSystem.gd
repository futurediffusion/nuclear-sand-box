extends RefCounted
class_name ThreatAssessmentSystem

## Domain service that evaluates building/placement events and returns
## hostility assessment candidates. It NEVER dispatches runtime AI actions.

const PRIORITY_NONE := "none"
const PRIORITY_LOW := "low"
const PRIORITY_MEDIUM := "medium"
const PRIORITY_HIGH := "high"
const PRIORITY_CRITICAL := "critical"

const EVENT_TYPE_STRUCTURE_PLACED := "structure_placed"
const EVENT_TYPE_STRUCTURE_DAMAGED := "structure_damaged"
const EVENT_TYPE_STRUCTURE_REMOVED := "structure_removed"
const EVENT_TYPE_PLACEMENT_COMPLETED := "placement_completed"

const DEFAULT_ITEM_THREAT_WEIGHTS := {
	"wallwood": 0.72,
	"doorwood": 0.58,
	"workbench": 0.67,
	"chest": 0.52,
	"barrel": 0.45,
	"table": 0.34,
	"stool": 0.20,
}

func assess_building_event(event_data: Dictionary, context: Dictionary = {}) -> Dictionary:
	var normalized_event: Dictionary = _normalize_event(event_data)
	if not bool(normalized_event.get("is_valid", false)):
		return _empty_assessment(normalized_event, "invalid_event")

	var item_id: String = String(normalized_event.get("item_id", ""))
	var event_type: String = String(normalized_event.get("event_type", ""))
	var target_pos: Vector2 = normalized_event.get("target_position", Vector2.ZERO) as Vector2
	var metadata: Dictionary = normalized_event.get("metadata", {}) as Dictionary

	var base_threat: float = _resolve_base_event_threat(event_type, item_id, context)
	var event_threat_boost: float = clampf(float(metadata.get("threat_boost", 0.0)), -1.0, 1.0)
	var normalized_event_severity: float = clampf(base_threat + event_threat_boost, 0.0, 1.0)

	var raw_candidates: Array = context.get("group_candidates", []) as Array
	var min_group_score: float = clampf(float(context.get("min_group_score", 0.40)), 0.0, 1.0)
	var max_groups: int = maxi(0, int(context.get("max_groups", 0)))
	var candidate_scope: Array[Dictionary] = []
	var strongest_group_score: float = 0.0

	for raw_entry in raw_candidates:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		var score_pack: Dictionary = entry.get("score_pack", {}) as Dictionary
		var group_score: float = clampf(float(score_pack.get("score", 0.0)), 0.0, 1.0)
		if group_score < min_group_score:
			continue
		strongest_group_score = maxf(strongest_group_score, group_score)
		candidate_scope.append({
			"group_id": String(entry.get("gid", "")),
			"faction_id": String(entry.get("faction_id", "")),
			"anchor_kind": String(entry.get("anchor_kind", "unknown")),
			"anchor_distance": sqrt(float(entry.get("dist_sq", INF))),
			"score": group_score,
			"score_pack": score_pack.duplicate(true),
		})

	candidate_scope.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score: float = float(a.get("score", 0.0))
		var b_score: float = float(b.get("score", 0.0))
		if is_equal_approx(a_score, b_score):
			return float(a.get("anchor_distance", INF)) < float(b.get("anchor_distance", INF))
		return a_score > b_score
	)
	if max_groups > 0 and candidate_scope.size() > max_groups:
		candidate_scope.resize(max_groups)

	var has_candidates: bool = not candidate_scope.is_empty()
	var severity: float = clampf(normalized_event_severity * 0.55 + strongest_group_score * 0.45, 0.0, 1.0)
	var priority: String = _priority_from_severity(severity)
	var is_relevant: bool = has_candidates and severity > 0.0

	return {
		"is_relevant": is_relevant,
		"priority": priority,
		"severity": severity,
		"target_position": target_pos,
		"source_event": {
			"event_type": event_type,
			"item_id": item_id,
			"tile_pos": normalized_event.get("tile_pos", Vector2i.ZERO),
			"world_pos": target_pos,
			"metadata": metadata.duplicate(true),
		},
		"candidate_group_scope": {
			"has_candidates": has_candidates,
			"candidates": candidate_scope,
			"min_group_score": min_group_score,
			"max_groups": max_groups,
		},
		"debug": {
			"base_event_threat": base_threat,
			"event_threat_boost": event_threat_boost,
			"normalized_event_severity": normalized_event_severity,
			"strongest_group_score": strongest_group_score,
			"source": "threat_assessment_system",
		},
	}

func _normalize_event(event_data: Dictionary) -> Dictionary:
	if event_data.is_empty():
		return {"is_valid": false, "reason": "empty_event"}

	var event_type: String = String(event_data.get("type", event_data.get("event_type", ""))).strip_edges()
	if event_type.is_empty():
		return {"is_valid": false, "reason": "missing_event_type"}

	var item_id: String = String(event_data.get("item_id", "")).strip_edges()
	var tile_pos_variant: Variant = event_data.get("tile_pos", Vector2i.ZERO)
	var tile_pos: Vector2i = tile_pos_variant if tile_pos_variant is Vector2i else Vector2i.ZERO

	var target_pos: Vector2 = Vector2.ZERO
	var target_variant: Variant = event_data.get("world_pos", event_data.get("target_position", Vector2.ZERO))
	if target_variant is Vector2:
		target_pos = target_variant as Vector2

	var metadata: Dictionary = event_data.get("metadata", {}) as Dictionary

	return {
		"is_valid": true,
		"event_type": event_type,
		"item_id": item_id,
		"tile_pos": tile_pos,
		"target_position": target_pos,
		"metadata": metadata,
	}

func _resolve_base_event_threat(event_type: String, item_id: String, context: Dictionary) -> float:
	var event_weight: float = 0.35
	match event_type:
		EVENT_TYPE_STRUCTURE_DAMAGED:
			event_weight = 0.80
		EVENT_TYPE_STRUCTURE_REMOVED:
			event_weight = 0.64
		EVENT_TYPE_STRUCTURE_PLACED, EVENT_TYPE_PLACEMENT_COMPLETED:
			event_weight = 0.45
		_:
			event_weight = 0.30

	var weights: Dictionary = DEFAULT_ITEM_THREAT_WEIGHTS
	var override_weights: Variant = context.get("item_threat_weights", {})
	if override_weights is Dictionary and not (override_weights as Dictionary).is_empty():
		weights = override_weights as Dictionary
	var item_weight: float = clampf(float(weights.get(item_id, 0.25)), 0.0, 1.0)
	return clampf(event_weight * 0.55 + item_weight * 0.45, 0.0, 1.0)

func _priority_from_severity(severity: float) -> String:
	if severity >= 0.85:
		return PRIORITY_CRITICAL
	if severity >= 0.65:
		return PRIORITY_HIGH
	if severity >= 0.45:
		return PRIORITY_MEDIUM
	if severity > 0.0:
		return PRIORITY_LOW
	return PRIORITY_NONE

func _empty_assessment(normalized_event: Dictionary, reason: String) -> Dictionary:
	var world_pos: Vector2 = normalized_event.get("target_position", Vector2.ZERO) as Vector2
	return {
		"is_relevant": false,
		"priority": PRIORITY_NONE,
		"severity": 0.0,
		"target_position": world_pos,
		"source_event": {
			"event_type": String(normalized_event.get("event_type", "")),
			"item_id": String(normalized_event.get("item_id", "")),
			"tile_pos": normalized_event.get("tile_pos", Vector2i.ZERO),
			"world_pos": world_pos,
			"metadata": normalized_event.get("metadata", {}),
		},
		"candidate_group_scope": {
			"has_candidates": false,
			"candidates": [],
			"min_group_score": 0.0,
			"max_groups": 0,
		},
		"debug": {
			"source": "threat_assessment_system",
			"reason": reason,
		},
	}
