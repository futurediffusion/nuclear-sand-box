extends RefCounted
class_name BodyguardController

const MACRO_DEFENDING_CAMP := "defending_camp"
const MACRO_ALERTED := "alerted"
const MACRO_HUNTING := "hunting"
const MACRO_RAIDING := "raiding"
const MACRO_RETREATING := "retreating"


func build_order(ctx: Dictionary) -> Dictionary:
	var group_blackboard: Dictionary = ctx.get("group_blackboard", {})
	var status: Dictionary = group_blackboard.get("status", {})
	var macro_state: String = String(ctx.get("macro_state", "idle"))
	if macro_state == "idle":
		macro_state = String((status.get("group_mode", {}) as Dictionary).get("value", macro_state))
	var leader_pos: Vector2 = ctx.get("leader_pos", Vector2.ZERO)
	var home_pos: Vector2 = ctx.get("home_pos", leader_pos)
	var assigned_slot: String = String(ctx.get("assigned_slot", ""))
	var interest_pos: Vector2 = ctx.get("interest_pos", Vector2.ZERO)
	var structure_assault_active: bool = bool(ctx.get("structure_assault_active", false))
	var existing_assignment: Dictionary = ctx.get("existing_assignment", {}) as Dictionary
	var assigned_assault_target: Vector2 = existing_assignment.get("target_pos", Vector2.ZERO) as Vector2

	if structure_assault_active:
		if String(existing_assignment.get("order", "")) == "assault_structure_target" and assigned_assault_target != Vector2.ZERO:
			Debug.log("bandit_group", "[BGC][structure_assault_target_preserved] group=%s member=%s role=bodyguard target=%s" % [
				String(ctx.get("group_id", "")),
				String(ctx.get("member_id", "")),
				str(assigned_assault_target),
			])
			return {"order": "assault_structure_target", "target_pos": assigned_assault_target}
		if interest_pos != Vector2.ZERO:
			return {"order": "assault_structure_target", "target_pos": interest_pos}

	if macro_state == MACRO_RETREATING:
		return {
			"order": "return_home",
			"home_pos": home_pos,
		}

	if macro_state == MACRO_RAIDING or macro_state == MACRO_HUNTING:
		return {
			"order": "attack_target",
			"target_pos": interest_pos if interest_pos != Vector2.ZERO else leader_pos,
		}

	if macro_state == MACRO_ALERTED:
		return {
			"order": "move_to_target",
			"target_pos": interest_pos if interest_pos != Vector2.ZERO else leader_pos,
		}

	if assigned_slot != "":
		return {
			"order": "follow_slot",
			"slot_name": assigned_slot,
		}

	if macro_state == MACRO_DEFENDING_CAMP:
		return {
			"order": "follow_slot",
			"slot_name": "frontal",
		}

	return {
		"order": "follow_slot",
		"slot_name": "lateral_left",
	}
