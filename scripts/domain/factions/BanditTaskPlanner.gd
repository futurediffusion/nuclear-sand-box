extends RefCounted
class_name BanditTaskPlanner

## Canonical task planning layer between intent and execution.
## Consumes canonical intent outputs and emits concrete order/task payloads.
## This planner never executes movement/combat side effects.

const BanditIntentSystemScript := preload("res://scripts/domain/factions/BanditIntentSystem.gd")

const ORDER_FOLLOW_SLOT := "follow_slot"
const ORDER_MOVE_TO_TARGET := "move_to_target"
const ORDER_MINE_TARGET := "mine_target"
const ORDER_PICKUP_TARGET := "pickup_target"
const ORDER_RETURN_HOME := "return_home"
const ORDER_ASSAULT_STRUCTURE_TARGET := "assault_structure_target"
const ORDER_ATTACK_TARGET := "attack_target"

const ORDER_KIND_ALLOWLIST := {
	ORDER_FOLLOW_SLOT: true,
	ORDER_MOVE_TO_TARGET: true,
	ORDER_MINE_TARGET: true,
	ORDER_PICKUP_TARGET: true,
	ORDER_RETURN_HOME: true,
	ORDER_ASSAULT_STRUCTURE_TARGET: true,
	ORDER_ATTACK_TARGET: true,
}


func plan_member_task(canonical_intent: Dictionary, member_ctx: Dictionary, proposed_order: Dictionary) -> Dictionary:
	var intent_record: Dictionary = _normalize_canonical_intent(canonical_intent, member_ctx)
	var resolved_order: Dictionary = _resolve_order_from_intent(intent_record, member_ctx, proposed_order)
	var sanitized_order: Dictionary = _sanitize_order(resolved_order, member_ctx)
	var task_payload: Dictionary = _build_task_payload(sanitized_order, intent_record, member_ctx)
	var out: Dictionary = sanitized_order.duplicate(true)
	out["task"] = task_payload
	return out


func _normalize_canonical_intent(canonical_intent: Dictionary, member_ctx: Dictionary) -> Dictionary:
	var out: Dictionary = canonical_intent.duplicate(true)
	if String(out.get("kind", "")).is_empty():
		out["kind"] = "group_intent_decision"
	if String(out.get("group_mode", "")).is_empty():
		out["group_mode"] = String(member_ctx.get("group_mode", "idle"))
	if String(out.get("decision_type", "")).is_empty():
		out["decision_type"] = BanditIntentSystemScript.DECISION_CONTINUE_WORK
	return out


func _resolve_order_from_intent(intent_record: Dictionary, member_ctx: Dictionary, proposed_order: Dictionary) -> Dictionary:
	var decision_type: String = String(intent_record.get("decision_type", BanditIntentSystemScript.DECISION_CONTINUE_WORK))
	var role: String = String(member_ctx.get("role", "scavenger"))
	match decision_type:
		BanditIntentSystemScript.DECISION_RETURN_HOME:
			return {"order": ORDER_RETURN_HOME}
		BanditIntentSystemScript.DECISION_STRUCTURE_ASSAULT:
			var assault_target: Vector2 = _resolve_target_pos(member_ctx, proposed_order)
			if (role == "leader" or role == "bodyguard") and assault_target != Vector2.ZERO:
				return {"order": ORDER_ASSAULT_STRUCTURE_TARGET, "target_pos": assault_target}
			return proposed_order
		BanditIntentSystemScript.DECISION_PURSUE_TARGET, BanditIntentSystemScript.DECISION_REACT_THREAT:
			if _is_order_allowed(proposed_order):
				return proposed_order
			var threat_target: Vector2 = _resolve_target_pos(member_ctx, proposed_order)
			if threat_target != Vector2.ZERO:
				return {"order": ORDER_ATTACK_TARGET, "target_pos": threat_target}
			return {"order": ORDER_FOLLOW_SLOT, "slot_name": "frontal"}
		BanditIntentSystemScript.DECISION_LOOT_RESOURCE:
			if _is_economic_order(proposed_order):
				return proposed_order
			return _fallback_economic_order(member_ctx)
		_:
			return proposed_order


func _fallback_economic_order(member_ctx: Dictionary) -> Dictionary:
	var resources: Array = member_ctx.get("prioritized_resources", []) as Array
	if not resources.is_empty():
		var first_resource: Dictionary = resources[0] as Dictionary
		return {
			"order": ORDER_MINE_TARGET,
			"target_id": int(first_resource.get("id", 0)),
			"target_pos": first_resource.get("pos", Vector2.ZERO),
		}
	var drops: Array = member_ctx.get("prioritized_drops", []) as Array
	if not drops.is_empty():
		var first_drop: Dictionary = drops[0] as Dictionary
		return {
			"order": ORDER_PICKUP_TARGET,
			"target_id": int(first_drop.get("id", 0)),
			"target_pos": first_drop.get("pos", Vector2.ZERO),
		}
	var interest_pos: Vector2 = member_ctx.get("interest_pos", Vector2.ZERO) as Vector2
	if interest_pos != Vector2.ZERO:
		return {"order": ORDER_MOVE_TO_TARGET, "target_pos": interest_pos}
	return {"order": ORDER_FOLLOW_SLOT, "slot_name": "escort_left"}


func _sanitize_order(order_data: Dictionary, member_ctx: Dictionary) -> Dictionary:
	var out: Dictionary = order_data.duplicate(true)
	if not _is_order_allowed(out):
		return {"order": ORDER_RETURN_HOME}
	var order_type: String = String(out.get("order", ""))
	match order_type:
		ORDER_FOLLOW_SLOT:
			if String(out.get("slot_name", "")).is_empty():
				out["slot_name"] = "frontal"
		ORDER_MOVE_TO_TARGET, ORDER_ATTACK_TARGET, ORDER_ASSAULT_STRUCTURE_TARGET:
			var target_pos: Vector2 = _resolve_target_pos(member_ctx, out)
			if target_pos != Vector2.ZERO:
				out["target_pos"] = target_pos
		ORDER_MINE_TARGET, ORDER_PICKUP_TARGET:
			var target_pos_for_io: Vector2 = _resolve_target_pos(member_ctx, out)
			if target_pos_for_io != Vector2.ZERO:
				out["target_pos"] = target_pos_for_io
	return out


func _build_task_payload(order_data: Dictionary, intent_record: Dictionary, member_ctx: Dictionary) -> Dictionary:
	var order_type: String = String(order_data.get("order", ORDER_RETURN_HOME))
	var payload: Dictionary = {
		"kind": order_type,
		"macro_state": String(member_ctx.get("macro_state", "idle")),
		"intent": {
			"kind": String(intent_record.get("kind", "group_intent_decision")),
			"group_mode": String(intent_record.get("group_mode", member_ctx.get("group_mode", "idle"))),
			"decision_type": String(intent_record.get("decision_type", BanditIntentSystemScript.DECISION_CONTINUE_WORK)),
		},
	}
	match order_type:
		ORDER_FOLLOW_SLOT:
			payload["slot_name"] = String(order_data.get("slot_name", "frontal"))
		ORDER_MOVE_TO_TARGET, ORDER_ATTACK_TARGET, ORDER_ASSAULT_STRUCTURE_TARGET:
			payload["target_pos"] = order_data.get("target_pos", Vector2.ZERO)
		ORDER_MINE_TARGET, ORDER_PICKUP_TARGET:
			payload["target_id"] = int(order_data.get("target_id", 0))
			payload["target_pos"] = order_data.get("target_pos", Vector2.ZERO)
		ORDER_RETURN_HOME:
			payload["home_pos"] = member_ctx.get("home_pos", Vector2.ZERO)
	return payload


func _resolve_target_pos(member_ctx: Dictionary, order_data: Dictionary) -> Vector2:
	var order_target: Variant = order_data.get("target_pos", null)
	if order_target is Vector2 and (order_target as Vector2) != Vector2.ZERO:
		return order_target as Vector2
	var interest_pos: Vector2 = member_ctx.get("interest_pos", Vector2.ZERO) as Vector2
	if interest_pos != Vector2.ZERO:
		return interest_pos
	return member_ctx.get("leader_pos", Vector2.ZERO) as Vector2


func _is_order_allowed(order_data: Dictionary) -> bool:
	var order_type: String = String(order_data.get("order", ""))
	return ORDER_KIND_ALLOWLIST.has(order_type)


func _is_economic_order(order_data: Dictionary) -> bool:
	var order_type: String = String(order_data.get("order", ""))
	return order_type == ORDER_MINE_TARGET \
			or order_type == ORDER_PICKUP_TARGET \
			or order_type == ORDER_MOVE_TO_TARGET \
			or order_type == ORDER_RETURN_HOME
