extends RefCounted
class_name BanditGroupBrain

const BodyguardControllerScript := preload("res://scripts/world/BodyguardController.gd")
const ScavengerControllerScript := preload("res://scripts/world/ScavengerController.gd")

const MACRO_STATES: Array[String] = [
	"idle",
	"patrol",
	"alerted",
	"hunting",
	"raiding",
	"working",
	"retreating",
	"depositing",
	"defending_camp",
]

var _bodyguard_controller: BodyguardController = BodyguardControllerScript.new()
var _scavenger_controller: ScavengerController = ScavengerControllerScript.new()

const GROUP_ORDER_CACHE_TTL_SECONDS: float = 0.9
const GROUP_RECOMPUTE_SAFETY_TTL_TICKS: int = 12
const POLLING_REVIEW_INTERVAL_SECONDS: float = 20.0

var _dirty_groups: Dictionary = {}
var _cached_orders_by_group: Dictionary = {}
var _cached_orders_expires_at: Dictionary = {}
var _last_signature_by_group: Dictionary = {}
var _last_signature_parts_by_group: Dictionary = {}
var _last_recompute_tick_by_group: Dictionary = {}
var _group_tick_counter_by_group: Dictionary = {}
var _group_recompute_total: int = 0
var _group_recompute_reason_breakdown: Dictionary = {}
var _cache_hit_count: int = 0
var _cache_query_count: int = 0
var _last_polling_review_at: float = 0.0


func setup(_ctx: Dictionary = {}) -> void:
	_dirty_groups.clear()
	_cached_orders_by_group.clear()
	_cached_orders_expires_at.clear()
	_last_signature_by_group.clear()
	_last_signature_parts_by_group.clear()
	_last_recompute_tick_by_group.clear()
	_group_tick_counter_by_group.clear()
	_group_recompute_total = 0
	_group_recompute_reason_breakdown = {
		"target_changed": 0,
		"cargo_changed": 0,
		"role_reassigned": 0,
		"phase_changed": 0,
		"ttl_expired": 0,
	}
	_cache_hit_count = 0
	_cache_query_count = 0
	_last_polling_review_at = 0.0


func ingest_work_event(event_name: String, payload: Dictionary = {}) -> void:
	var group_id: String = String(payload.get("group_id", payload.get("camp_id", "")))
	if group_id == "":
		return
	var member_id: String = String(payload.get("npc_id", ""))
	var now: float = RunClock.now()
	var pos: Vector2 = payload.get("world_pos", Vector2.ZERO) as Vector2
	if pos == Vector2.ZERO:
		var pos_raw: Variant = payload.get("position", null)
		if pos_raw is Vector2:
			pos = pos_raw as Vector2
	match event_name:
		"resource_discovered":
			if pos != Vector2.ZERO:
				BanditGroupMemory.bb_write_known_resources(group_id, [{"id": int(payload.get("target_id", 0)), "pos": pos}], 45.0, "event_resource_discovered")
		"resource_depleted":
			BanditGroupMemory.bb_set_status(group_id, "last_resource_depleted_at", now, 30.0, "event_resource_depleted")
		"drop_spawned":
			if pos != Vector2.ZERO:
				BanditGroupMemory.bb_write_known_drops(group_id, [{"id": int(payload.get("target_id", 0)), "pos": pos, "amount": int(payload.get("amount", 1))}], 20.0, "event_drop_spawned")
		"drop_collected":
			BanditGroupMemory.bb_set_status(group_id, "last_drop_collected_at", now, 20.0, "event_drop_collected")
		"member_died":
			if member_id != "":
				BanditGroupMemory.bb_clear_assignment(group_id, member_id)
		"target_invalidated":
			if member_id != "":
				BanditGroupMemory.bb_clear_assignment(group_id, member_id)
		"threat_seen":
			BanditGroupMemory.bb_write_threat_level(group_id, maxf(1.0, float(payload.get("threat_level", 1.0))), "event_threat_seen")
			BanditGroupMemory.bb_write_group_mode(group_id, "alerted", "event_threat_seen")
		"deposit_full":
			BanditGroupMemory.bb_write_group_mode(group_id, "depositing", "event_deposit_full")
		"wall_breached":
			BanditGroupMemory.bb_write_group_mode(group_id, "raiding", "event_wall_breached")
			BanditGroupMemory.bb_write_threat_level(group_id, maxf(2.0, float(payload.get("threat_level", 2.0))), "event_wall_breached")
		"leader_changed":
			BanditGroupMemory.bb_set_status(group_id, "leader_id", String(payload.get("leader_id", "")), 90.0, "event_leader_changed")
		"group_mode_changed":
			BanditGroupMemory.bb_write_group_mode(group_id, String(payload.get("group_mode", "idle")), "event_group_mode_changed")
		_:
			pass
	_dirty_groups[group_id] = true
	Debug.log("bandit_group", "[BGB][event] group=%s event=%s member=%s" % [group_id, event_name, member_id])


func assign_group_orders(group_id: String, members: Array, group_ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if group_id == "" or members.is_empty():
		return out
	var now: float = RunClock.now()
	_cache_query_count += 1
	var signature_data: Dictionary = _build_group_state_signature(members, group_ctx)
	var signature: String = String(signature_data.get("fingerprint", ""))
	var current_parts: Dictionary = signature_data.get("parts", {}) as Dictionary
	var previous_parts: Dictionary = _last_signature_parts_by_group.get(group_id, {}) as Dictionary
	var group_tick: int = int(_group_tick_counter_by_group.get(group_id, 0)) + 1
	_group_tick_counter_by_group[group_id] = group_tick
	var ticks_since_recompute: int = group_tick - int(_last_recompute_tick_by_group.get(group_id, 0))
	var ttl_expired: bool = ticks_since_recompute >= GROUP_RECOMPUTE_SAFETY_TTL_TICKS
	var reason: String = _resolve_recompute_reason(previous_parts, current_parts, ttl_expired)
	var force_recompute: bool = reason != ""
	var use_group_cache: bool = BanditTuning.rollout_opt_task_5_group_order_cache()
	if use_group_cache and not force_recompute and now < float(_cached_orders_expires_at.get(group_id, 0.0)) and _cached_orders_by_group.has(group_id):
		_cache_hit_count += 1
		Debug.log("bandit_group", "[BGB][cache_hit] group=%s signature=%s" % [group_id, signature])
		_maybe_log_polling_review(now)
		return (_cached_orders_by_group[group_id] as Dictionary).duplicate(true)
	if not use_group_cache:
		reason = "ttl_expired"
	elif reason == "":
		reason = "ttl_expired"
	_group_recompute_total += 1
	_group_recompute_reason_breakdown[reason] = int(_group_recompute_reason_breakdown.get(reason, 0)) + 1
	Debug.log("bandit_group", "[BGB][recompute] group=%s cache_invalidated_reason=%s sig_changed=%s ttl_ticks=%d/%d" % [
		group_id,
		reason,
		str(_last_signature_by_group.get(group_id, "") != signature),
		ticks_since_recompute,
		GROUP_RECOMPUTE_SAFETY_TTL_TICKS,
	])
	var macro_state: String = _resolve_macro_state(group_ctx)
	BanditGroupMemory.bb_write_group_mode(group_id, macro_state, "group_brain")
	for item in members:
		if not (item is Dictionary):
			continue
		var member: Dictionary = item as Dictionary
		var member_id: String = String(member.get("member_id", ""))
		if member_id == "":
			continue
		var role: String = String(member.get("role", "scavenger"))
		var member_ctx: Dictionary = member.duplicate(true)
		var memory_assignment: Dictionary = BanditGroupMemory.bb_get_assignment(group_id, member_id)
		if memory_assignment.is_empty():
			memory_assignment = member_ctx.get("current_assignment", {}) as Dictionary
		member_ctx["existing_assignment"] = memory_assignment
		var order: Dictionary = _build_order_for_member(role, group_ctx, member_ctx)
		order["macro_state"] = macro_state
		out[member_id] = order
		BanditGroupMemory.bb_set_assignment(group_id, member_id, order, 8.0, "group_brain")
	_cached_orders_by_group[group_id] = out.duplicate(true)
	_cached_orders_expires_at[group_id] = now + GROUP_ORDER_CACHE_TTL_SECONDS
	_last_signature_by_group[group_id] = signature
	_last_signature_parts_by_group[group_id] = current_parts.duplicate(true)
	_last_recompute_tick_by_group[group_id] = group_tick
	_dirty_groups[group_id] = false
	_maybe_log_polling_review(now)
	return out


func _build_group_state_signature(members: Array, group_ctx: Dictionary) -> Dictionary:
	var ids: Array[String] = []
	var member_role_tokens: Array[String] = []
	var member_cargo_tokens: Array[String] = []
	for raw in members:
		if raw is Dictionary:
			var member: Dictionary = raw as Dictionary
			var member_id: String = String(member.get("member_id", ""))
			ids.append(member_id)
			member_role_tokens.append("%s:%s" % [member_id, String(member.get("role", "scavenger"))])
			member_cargo_tokens.append("%s:%d/%d" % [
				member_id,
				int(member.get("cargo_count", 0)),
				int(member.get("cargo_capacity", 0)),
			])
	ids.sort()
	member_role_tokens.sort()
	member_cargo_tokens.sort()
	var phase: String = _resolve_group_phase(members, group_ctx)
	var interest_pos: Vector2 = group_ctx.get("interest_pos", Vector2.ZERO) as Vector2
	var prioritized_resource_ids: Array[String] = _extract_target_ids(group_ctx.get("prioritized_resources", []))
	var prioritized_drop_ids: Array[String] = _extract_target_ids(group_ctx.get("prioritized_drops", []))
	var target_signature: String = "%s|res=%s|drops=%s" % [
		str(interest_pos),
		",".join(prioritized_resource_ids),
		",".join(prioritized_drop_ids),
	]
	var role_signature: String = "%s|roles=%s" % [",".join(ids), ",".join(member_role_tokens)]
	var cargo_signature: String = ",".join(member_cargo_tokens)
	var phase_signature: String = phase
	var fingerprint: String = "target=%s|cargo=%s|roles=%s|phase=%s" % [
		target_signature,
		cargo_signature,
		role_signature,
		phase_signature,
	]
	return {
		"fingerprint": fingerprint,
		"parts": {
			"target": target_signature,
			"cargo": cargo_signature,
			"role": role_signature,
			"phase": phase_signature,
		},
	}


func _extract_target_ids(raw_list: Variant) -> Array[String]:
	var out: Array[String] = []
	var values: Array = raw_list as Array
	for raw in values:
		var entry: Dictionary = raw as Dictionary
		out.append(str(int(entry.get("id", 0))))
	out.sort()
	return out


func _resolve_group_phase(members: Array, group_ctx: Dictionary) -> String:
	if bool(group_ctx.get("structure_assault_active", false)):
		return "assault"
	var mode: String = _resolve_macro_state(group_ctx)
	if mode == "retreating" or mode == "depositing":
		return "egress"
	if _has_active_scavenger_resource_work(members):
		return "loot"
	return "loot" if _has_pending_loot_targets(group_ctx) else "egress"


func _resolve_recompute_reason(previous_parts: Dictionary, current_parts: Dictionary, ttl_expired: bool) -> String:
	if previous_parts.is_empty():
		return "target_changed"
	if String(previous_parts.get("target", "")) != String(current_parts.get("target", "")):
		return "target_changed"
	if String(previous_parts.get("cargo", "")) != String(current_parts.get("cargo", "")):
		return "cargo_changed"
	if String(previous_parts.get("role", "")) != String(current_parts.get("role", "")):
		return "role_reassigned"
	if String(previous_parts.get("phase", "")) != String(current_parts.get("phase", "")):
		return "phase_changed"
	if ttl_expired:
		return "ttl_expired"
	return ""


func _has_active_scavenger_resource_work(members: Array) -> bool:
	for raw in members:
		if not (raw is Dictionary):
			continue
		var member: Dictionary = raw as Dictionary
		if String(member.get("role", "")) != "scavenger":
			continue
		var current_resource_id: int = int(member.get("current_resource_id", 0))
		var pending_mine_id: int = int(member.get("pending_mine_id", 0))
		if bool(member.get("has_active_task", false)) and (current_resource_id != 0 or pending_mine_id != 0):
			return true
	return false


func _has_pending_loot_targets(group_ctx: Dictionary) -> bool:
	return not (group_ctx.get("prioritized_resources", []) as Array).is_empty() \
			or not (group_ctx.get("prioritized_drops", []) as Array).is_empty()


func get_cache_stats() -> Dictionary:
	var ratio: float = 0.0
	if _cache_query_count > 0:
		ratio = float(_cache_hit_count) / float(_cache_query_count)
	return {
		"group_recompute_total": _group_recompute_total,
		"group_recompute_reason_breakdown": _group_recompute_reason_breakdown.duplicate(true),
		"group_cache_hit_ratio": ratio,
		"rollout_optimization_flags": {
			"task_5_group_order_cache": BanditTuning.rollout_opt_task_5_group_order_cache(),
		},
	}


func _maybe_log_polling_review(now: float) -> void:
	if now - _last_polling_review_at < POLLING_REVIEW_INTERVAL_SECONDS:
		return
	_last_polling_review_at = now
	var ratio: float = 0.0
	if _cache_query_count > 0:
		ratio = float(_cache_hit_count) / float(_cache_query_count)
	Debug.log("bandit_group", "[BGB][polling_review] cache_hit=%d cache_query=%d group_recompute_total=%d group_cache_hit_ratio=%.2f breakdown=%s" % [
		_cache_hit_count,
		_cache_query_count,
		_group_recompute_total,
		ratio,
		str(_group_recompute_reason_breakdown),
	])


func _resolve_macro_state(group_ctx: Dictionary) -> String:
	var requested: String = String(group_ctx.get("group_mode", "idle"))
	if requested in MACRO_STATES:
		return requested
	match requested:
		"extorting":
			return "raiding"
		"returning", "hold":
			return "retreating"
		_:
			return "idle"


func _build_order_for_member(role: String, group_ctx: Dictionary, member_ctx: Dictionary) -> Dictionary:
	var merged: Dictionary = group_ctx.duplicate(true)
	merged["macro_state"] = _resolve_macro_state(group_ctx)
	for key in member_ctx.keys():
		merged[key] = member_ctx[key]
	match role:
		"leader":
			return _build_leader_order(merged)
		"bodyguard":
			return _bodyguard_controller.build_order(merged)
		_:
			return _scavenger_controller.build_order(merged)


func _build_leader_order(ctx: Dictionary) -> Dictionary:
	var macro_state: String = String(ctx.get("macro_state", _resolve_macro_state(ctx)))
	var interest_pos: Vector2 = ctx.get("interest_pos", Vector2.ZERO)
	var structure_assault_active: bool = bool(ctx.get("structure_assault_active", false))
	if structure_assault_active:
		var existing_assignment: Dictionary = ctx.get("existing_assignment", {}) as Dictionary
		var assigned_target: Vector2 = existing_assignment.get("target_pos", Vector2.ZERO) as Vector2
		if String(existing_assignment.get("order", "")) == "assault_structure_target" and assigned_target != Vector2.ZERO:
			Debug.log("bandit_group", "[BGB][structure_assault_target_preserved] group=%s member=%s role=leader target=%s" % [
				String(ctx.get("group_id", "")),
				String(ctx.get("member_id", "")),
				str(assigned_target),
			])
			return {"order": "assault_structure_target", "target_pos": assigned_target}
		if interest_pos != Vector2.ZERO:
			return {"order": "assault_structure_target", "target_pos": interest_pos}
	match macro_state:
		"retreating", "depositing":
			return {"order": "return_home"}
		"working":
			return {"order": "move_to_target", "target_pos": interest_pos if interest_pos != Vector2.ZERO else ctx.get("home_pos", Vector2.ZERO)}
		"hunting", "raiding", "alerted":
			return {"order": "attack_target", "target_pos": interest_pos}
		_:
			# Never relax while someone in the group is under attack.
			if bool(ctx.get("any_member_threatened", false)):
				return {"order": "follow_slot", "slot_name": "frontal"}
			# Relax at home while any scavenger is actively working.
			# Wake up and lead formation again once everyone is idle.
			if bool(ctx.get("any_scavenger_busy", false)):
				return {"order": "relax_at_home"}
			return {"order": "follow_slot", "slot_name": "frontal"}
