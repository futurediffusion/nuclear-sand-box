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
	var deposit_lock_active: bool = bool(ctx.get("deposit_lock_active", false))
	var group_blackboard: Dictionary = ctx.get("group_blackboard", {})
	var perception: Dictionary = group_blackboard.get("perception", {})
	var drops: Array = ctx.get("prioritized_drops", [])
	var resources: Array = ctx.get("prioritized_resources", [])
	if drops.is_empty():
		drops = (perception.get("prioritized_drops", {}) as Dictionary).get("value", [])
	if resources.is_empty():
		resources = (perception.get("prioritized_resources", {}) as Dictionary).get("value", [])
	var interest_pos: Vector2 = ctx.get("interest_pos", Vector2.ZERO)
	var member_id: String = String(ctx.get("member_id", ""))
	var group_id: String = String(ctx.get("group_id", ""))
	var current_state: String = String(ctx.get("current_state", ""))
	var current_resource_id: int = int(ctx.get("current_resource_id", 0))
	var pending_mine_id: int = int(ctx.get("pending_mine_id", 0))
	var last_valid_resource_node_id: int = int(ctx.get("last_valid_resource_node_id", 0))
	var has_active_task: bool = bool(ctx.get("has_active_task", false))
	var existing_assignment: Dictionary = ctx.get("existing_assignment", {}) as Dictionary
	var force_replan_resource: bool = bool(ctx.get("force_replan_resource", false))
	var reservation_conflict: bool = bool(ctx.get("reservation_conflict", false))
	var combat_interruption: bool = bool(ctx.get("in_combat", false)) or macro_state == MACRO_HUNTING or macro_state == MACRO_RAIDING

	if macro_state == MACRO_RETREATING:
		return {"order": "return_home"}

	if (carry_count > 0 and deposit_lock_active) or carry_count >= capacity or macro_state == MACRO_DEPOSITING:
		return {"order": "return_home"}

	if combat_interruption:
		if interest_pos != Vector2.ZERO:
			return {"order": "attack_target", "target_pos": interest_pos}
		return {"order": "follow_slot", "slot_name": "escort_left"}

	var can_preserve_resource: bool = not force_replan_resource \
			and not reservation_conflict \
			and not combat_interruption
	if can_preserve_resource:
		var preserved: Dictionary = _resolve_preserved_resource_order(
				existing_assignment,
				current_state,
				current_resource_id,
				pending_mine_id,
				last_valid_resource_node_id,
				resources)
		if not preserved.is_empty():
			Debug.log("bandit_group", "[SCV][mine_target_preserved] group=%s member=%s target=%s state=%s active=%s" % [
				group_id,
				member_id,
				str(preserved.get("target_id", 0)),
				current_state,
				str(has_active_task),
			])
			return preserved
		elif current_resource_id != 0 or pending_mine_id != 0:
			Debug.log("bandit_group", "[SCV][mine_target_changed] group=%s member=%s reason=invalid_or_missing old_current=%d old_pending=%d" % [
				group_id,
				member_id,
				current_resource_id,
				pending_mine_id,
			])

	# Mining is the primary job — commit to the resource before chasing drops.
	# Drops near the resource get auto-swept by sweep_collect_orbit during RESOURCE_WATCH.
	if not resources.is_empty() and (macro_state == MACRO_WORKING or macro_state == "patrol" or macro_state == "idle"):
		var first_resource: Dictionary = resources[0] as Dictionary
		var order := {
			"order": "mine_target",
			"target_id": int(first_resource.get("id", 0)),
			"target_pos": first_resource.get("pos", Vector2.ZERO),
		}
		Debug.log("bandit_group", "[SCV][mine_target_assigned] group=%s member=%s target=%d reason=new_assignment" % [
			group_id,
			member_id,
			int(order.get("target_id", 0)),
		])
		return order

	if not drops.is_empty():
		var first_drop: Dictionary = drops[0] as Dictionary
		return {
			"order": "pickup_target",
			"target_id": int(first_drop.get("id", 0)),
			"target_pos": first_drop.get("pos", Vector2.ZERO),
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


func _resolve_preserved_resource_order(existing_assignment: Dictionary,
		current_state: String,
		current_resource_id: int,
		pending_mine_id: int,
		last_valid_resource_node_id: int,
		resources: Array) -> Dictionary:
	var assignment_target_id: int = int(existing_assignment.get("target_id", 0))
	var assignment_target_pos: Vector2 = existing_assignment.get("target_pos", Vector2.ZERO) as Vector2
	if String(existing_assignment.get("order", "")) == "mine_target" and assignment_target_id != 0:
		var from_list: Dictionary = _find_resource_by_id(resources, assignment_target_id)
		if not from_list.is_empty():
			return _mine_order_from_resource(from_list)
		if assignment_target_pos != Vector2.ZERO:
			return {"order": "mine_target", "target_id": assignment_target_id, "target_pos": assignment_target_pos}
	var preferred_ids: Array[int] = []
	if current_state == "RESOURCE_WATCH" and current_resource_id != 0:
		preferred_ids.append(current_resource_id)
	if current_resource_id != 0 and not preferred_ids.has(current_resource_id):
		preferred_ids.append(current_resource_id)
	if pending_mine_id != 0 and not preferred_ids.has(pending_mine_id):
		preferred_ids.append(pending_mine_id)
	if last_valid_resource_node_id != 0 and not preferred_ids.has(last_valid_resource_node_id):
		preferred_ids.append(last_valid_resource_node_id)
	for target_id in preferred_ids:
		var resource: Dictionary = _find_resource_by_id(resources, target_id)
		if not resource.is_empty():
			return _mine_order_from_resource(resource)
	return {}


func _find_resource_by_id(resources: Array, target_id: int) -> Dictionary:
	if target_id == 0:
		return {}
	for raw in resources:
		var resource: Dictionary = raw as Dictionary
		if int(resource.get("id", 0)) == target_id:
			return resource
	return {}


func _mine_order_from_resource(resource: Dictionary) -> Dictionary:
	return {
		"order": "mine_target",
		"target_id": int(resource.get("id", 0)),
		"target_pos": resource.get("pos", Vector2.ZERO),
	}
