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
var _legacy_input_hint_uses: int = 0


func plan_member_task(canonical_intent: Dictionary, member_ctx: Dictionary, legacy_input_hints: Dictionary) -> Dictionary:
	var intent_record: Dictionary = _normalize_canonical_intent(canonical_intent, member_ctx)
	var planning_trace: Dictionary = {}
	var resolved_order: Dictionary = _resolve_order_from_intent(intent_record, member_ctx, legacy_input_hints, planning_trace)
	var sanitized_order: Dictionary = _sanitize_order(resolved_order, member_ctx)
	var task_payload: Dictionary = _build_task_payload(sanitized_order, intent_record, member_ctx, planning_trace)
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


func _resolve_order_from_intent(intent_record: Dictionary, member_ctx: Dictionary, legacy_input_hints: Dictionary,
		planning_trace: Dictionary) -> Dictionary:
	var decision_type: String = String(intent_record.get("decision_type", BanditIntentSystemScript.DECISION_CONTINUE_WORK))
	var role: String = String(member_ctx.get("role", "scavenger"))
	planning_trace["decision_type"] = decision_type
	planning_trace["authority"] = "canonical_pipeline"
	planning_trace["flow"] = "continue_current_work"
	planning_trace["legacy_input_used"] = false
	planning_trace["legacy_input_source"] = ""
	match decision_type:
		BanditIntentSystemScript.DECISION_RETURN_HOME:
			planning_trace["flow"] = "return_home"
			return {"order": ORDER_RETURN_HOME}
		BanditIntentSystemScript.DECISION_STRUCTURE_ASSAULT:
			planning_trace["flow"] = "structure_assault_focus"
			var assault_target: Vector2 = _resolve_target_pos(member_ctx, {})
			if assault_target == Vector2.ZERO:
				assault_target = _read_legacy_target_hint(legacy_input_hints, planning_trace, "structure_assault_target")
			if (role == "leader" or role == "bodyguard") and assault_target != Vector2.ZERO:
				return {"order": ORDER_ASSAULT_STRUCTURE_TARGET, "target_pos": assault_target}
			return {"order": ORDER_FOLLOW_SLOT, "slot_name": "frontal"}
		BanditIntentSystemScript.DECISION_PURSUE_TARGET, BanditIntentSystemScript.DECISION_REACT_THREAT:
			planning_trace["flow"] = "threat_response"
			var threat_target: Vector2 = _resolve_target_pos(member_ctx, {})
			if threat_target == Vector2.ZERO:
				threat_target = _read_legacy_target_hint(legacy_input_hints, planning_trace, "threat_target")
			if threat_target != Vector2.ZERO:
				return {"order": ORDER_ATTACK_TARGET, "target_pos": threat_target}
			return {"order": ORDER_FOLLOW_SLOT, "slot_name": "frontal"}
		BanditIntentSystemScript.DECISION_LOOT_RESOURCE:
			planning_trace["flow"] = "loot_resource_interest"
			return _plan_canonical_loot_order(member_ctx, role)
		BanditIntentSystemScript.DECISION_CONTINUE_WORK:
			planning_trace["flow"] = "continue_current_work"
			return _plan_continue_work_order(member_ctx, role, legacy_input_hints, planning_trace)
		_:
			planning_trace["flow"] = "unknown_decision_type_defaulted_to_continue_work"
			return _plan_continue_work_order(member_ctx, role, legacy_input_hints, planning_trace)


func _plan_canonical_loot_order(member_ctx: Dictionary, role: String) -> Dictionary:
	if role != "scavenger":
		return {"order": ORDER_FOLLOW_SLOT, "slot_name": "escort_left"}
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


func _plan_continue_work_order(member_ctx: Dictionary, role: String, legacy_input_hints: Dictionary,
		planning_trace: Dictionary) -> Dictionary:
	var macro_state: String = String(member_ctx.get("macro_state", "idle"))
	var carry_count: int = int(member_ctx.get("cargo_count", 0))
	var delivery_lock_active: bool = bool(member_ctx.get("delivery_lock_active", false))
	if macro_state == "retreating" or macro_state == "depositing" or delivery_lock_active or carry_count > 0:
		return {"order": ORDER_RETURN_HOME}
	if role == "scavenger":
		var preserved_resource_order: Dictionary = _resolve_preserved_resource_order(member_ctx)
		if not preserved_resource_order.is_empty():
			return preserved_resource_order
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
	var assigned_slot: String = String(member_ctx.get("assigned_slot", ""))
	if assigned_slot != "":
		return {"order": ORDER_FOLLOW_SLOT, "slot_name": assigned_slot}
	var legacy_slot: String = String(legacy_input_hints.get("slot_name", ""))
	if legacy_slot != "":
		_register_legacy_input_hint_usage(
			"bandit_task_planner.legacy_slot_hint",
			"continue_current_work used legacy slot_name as input hint."
		)
		planning_trace["legacy_input_used"] = true
		planning_trace["legacy_input_source"] = "slot_hint"
		return {"order": ORDER_FOLLOW_SLOT, "slot_name": legacy_slot}
	return {"order": ORDER_FOLLOW_SLOT, "slot_name": "frontal" if role == "leader" else "lateral_left"}


func _resolve_preserved_resource_order(member_ctx: Dictionary) -> Dictionary:
	var resources: Array = member_ctx.get("prioritized_resources", []) as Array
	var preferred_ids: Array[int] = []
	var existing_assignment: Dictionary = member_ctx.get("existing_assignment", {}) as Dictionary
	var assignment_target_id: int = int(existing_assignment.get("target_id", 0))
	if assignment_target_id != 0:
		preferred_ids.append(assignment_target_id)
	var current_resource_id: int = int(member_ctx.get("current_resource_id", 0))
	var pending_mine_id: int = int(member_ctx.get("pending_mine_id", 0))
	var last_valid_resource_node_id: int = int(member_ctx.get("last_valid_resource_node_id", 0))
	for candidate in [current_resource_id, pending_mine_id, last_valid_resource_node_id]:
		if candidate != 0 and not preferred_ids.has(candidate):
			preferred_ids.append(candidate)
	for target_id in preferred_ids:
		for raw in resources:
			var resource: Dictionary = raw as Dictionary
			if int(resource.get("id", 0)) == target_id:
				return {
					"order": ORDER_MINE_TARGET,
					"target_id": target_id,
					"target_pos": resource.get("pos", Vector2.ZERO),
				}
	return {}


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


func _build_task_payload(order_data: Dictionary, intent_record: Dictionary, member_ctx: Dictionary,
		planning_trace: Dictionary = {}) -> Dictionary:
	var order_type: String = String(order_data.get("order", ORDER_RETURN_HOME))
	var payload: Dictionary = {
		"kind": order_type,
		"macro_state": String(member_ctx.get("macro_state", "idle")),
		"intent": {
			"kind": String(intent_record.get("kind", "group_intent_decision")),
			"group_mode": String(intent_record.get("group_mode", member_ctx.get("group_mode", "idle"))),
			"decision_type": String(intent_record.get("decision_type", BanditIntentSystemScript.DECISION_CONTINUE_WORK)),
		},
		"planning_trace": {
			"authority": String(planning_trace.get("authority", "canonical_pipeline")),
			"flow": String(planning_trace.get("flow", "continue_current_work")),
			"legacy_input_used": bool(planning_trace.get("legacy_input_used", false)),
			"legacy_input_source": String(planning_trace.get("legacy_input_source", "")),
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


func _read_legacy_target_hint(legacy_input_hints: Dictionary, planning_trace: Dictionary, hint_name: String) -> Vector2:
	var target: Variant = legacy_input_hints.get("target_pos", null)
	if target is Vector2 and (target as Vector2) != Vector2.ZERO:
		_register_legacy_input_hint_usage(
			"bandit_task_planner.legacy_target_hint",
			"%s resolved target_pos from legacy proposed_order hint." % hint_name
		)
		planning_trace["legacy_input_used"] = true
		planning_trace["legacy_input_source"] = hint_name
		return target as Vector2
	return Vector2.ZERO


func _is_order_allowed(order_data: Dictionary) -> bool:
	var order_type: String = String(order_data.get("order", ""))
	return ORDER_KIND_ALLOWLIST.has(order_type)

func get_debug_snapshot() -> Dictionary:
	return {
		"legacy_input_hint_uses": _legacy_input_hint_uses,
	}


func _register_legacy_input_hint_usage(bridge_id: String, details: String) -> void:
	_legacy_input_hint_uses += 1
	Debug.log("compat", "[LEGACY_INPUT_HINT][%s] %s count=%d" % [
		bridge_id,
		details,
		_legacy_input_hint_uses,
	])
