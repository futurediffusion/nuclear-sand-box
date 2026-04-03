extends RefCounted
class_name ScavengerController

const MACRO_WORKING := "working"
const MACRO_DEPOSITING := "depositing"
const MACRO_RETREATING := "retreating"
const MACRO_RAIDING := "raiding"
const MACRO_HUNTING := "hunting"


func build_order(ctx: Dictionary) -> Dictionary:
	var macro_state: String = String(ctx.get("macro_state", "idle"))
	var carry_count: int = int(ctx.get("cargo_count", 0))
	var capacity: int = max(1, int(ctx.get("cargo_capacity", 1)))
	var group_blackboard: Dictionary = ctx.get("group_blackboard", {})
	var perception: Dictionary = group_blackboard.get("perception", {})
	var drops: Array = ctx.get("prioritized_drops", [])
	var resources: Array = ctx.get("prioritized_resources", [])
	if drops.is_empty():
		drops = (perception.get("prioritized_drops", {}) as Dictionary).get("value", [])
	if resources.is_empty():
		resources = (perception.get("prioritized_resources", {}) as Dictionary).get("value", [])
	var interest_pos: Vector2 = ctx.get("interest_pos", Vector2.ZERO)

	if macro_state == MACRO_RETREATING:
		return {"order": "return_home"}

	if carry_count >= capacity or macro_state == MACRO_DEPOSITING:
		return {"order": "return_home"}

	if not drops.is_empty():
		var first_drop: Dictionary = drops[0] as Dictionary
		return {
			"order": "pickup_target",
			"target_id": int(first_drop.get("id", 0)),
			"target_pos": first_drop.get("pos", Vector2.ZERO),
		}

	if not resources.is_empty() and (macro_state == MACRO_WORKING or macro_state == "patrol" or macro_state == "idle"):
		var first_resource: Dictionary = resources[0] as Dictionary
		return {
			"order": "mine_target",
			"target_id": int(first_resource.get("id", 0)),
			"target_pos": first_resource.get("pos", Vector2.ZERO),
		}

	if macro_state == MACRO_RAIDING or macro_state == MACRO_HUNTING:
		return {
			"order": "attack_target",
			"target_pos": interest_pos,
		}

	if interest_pos != Vector2.ZERO:
		return {
			"order": "move_to_target",
			"target_pos": interest_pos,
		}

	return {"order": "follow_slot", "slot_name": "escort_left"}
