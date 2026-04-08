extends RefCounted
class_name PerceptionReadModel

## Transition read-model adapter over group blackboard perception branch.
## Exposes normalized facts (data/memory), not tactical directives.

func from_blackboard(blackboard: Dictionary) -> Dictionary:
	var perception: Dictionary = blackboard.get("perception", {}) as Dictionary
	var prioritized_drops_entry: Dictionary = perception.get("prioritized_drops", {}) as Dictionary
	var prioritized_resources_entry: Dictionary = perception.get("prioritized_resources", {}) as Dictionary
	return {
		"prioritized_drops": prioritized_drops_entry.get("value", []),
		"prioritized_resources": prioritized_resources_entry.get("value", []),
		"nearby_loot_count": int((prioritized_drops_entry.get("value", []) as Array).size()),
		"nearby_resource_count": int((prioritized_resources_entry.get("value", []) as Array).size()),
	}
