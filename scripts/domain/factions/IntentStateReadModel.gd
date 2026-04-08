extends RefCounted
class_name IntentStateReadModel

## Transition read-model adapter over group blackboard status branch.
## Exposes canonical intent state as read-only context.

func from_blackboard(blackboard: Dictionary) -> Dictionary:
	var status: Dictionary = blackboard.get("status", {}) as Dictionary
	var canonical_intent_entry: Dictionary = status.get("canonical_intent_record", {}) as Dictionary
	var canonical_intent: Dictionary = canonical_intent_entry.get("value", {}) as Dictionary
	return {
		"canonical_intent": canonical_intent,
		"has_canonical_intent": _has_canonical_intent(canonical_intent),
	}


func _has_canonical_intent(canonical_intent: Dictionary) -> bool:
	if canonical_intent.is_empty():
		return false
	if String(canonical_intent.get("kind", "")).is_empty():
		return false
	return not String(canonical_intent.get("decision_type", "")).is_empty()
