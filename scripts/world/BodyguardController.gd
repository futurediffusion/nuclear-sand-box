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
