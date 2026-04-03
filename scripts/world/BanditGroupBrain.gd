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
const POLLING_REVIEW_INTERVAL_SECONDS: float = 20.0

var _dirty_groups: Dictionary = {}
var _cached_orders_by_group: Dictionary = {}
var _cached_orders_expires_at: Dictionary = {}
var _last_signature_by_group: Dictionary = {}
var _event_recompute_count: int = 0
var _periodic_recompute_count: int = 0
var _cache_hit_count: int = 0
var _last_polling_review_at: float = 0.0


func setup(_ctx: Dictionary = {}) -> void:
	_dirty_groups.clear()
	_cached_orders_by_group.clear()
	_cached_orders_expires_at.clear()
	_last_signature_by_group.clear()
	_event_recompute_count = 0
	_periodic_recompute_count = 0
	_cache_hit_count = 0
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
	var signature: String = _build_group_signature(members, group_ctx)
	var has_active_scavenger_resource_work: bool = _has_active_scavenger_resource_work(members)
	var force_recompute: bool = bool(_dirty_groups.get(group_id, false)) \
			or _last_signature_by_group.get(group_id, "") != signature \
			or has_active_scavenger_resource_work
	if not force_recompute and now < float(_cached_orders_expires_at.get(group_id, 0.0)) and _cached_orders_by_group.has(group_id):
		_cache_hit_count += 1
		Debug.log("bandit_group", "[BGB][cache_hit] group=%s signature=%s" % [group_id, signature])
		_maybe_log_polling_review(now)
		return (_cached_orders_by_group[group_id] as Dictionary).duplicate(true)
	if force_recompute:
		_event_recompute_count += 1
	else:
		_periodic_recompute_count += 1
	Debug.log("bandit_group", "[BGB][recompute] group=%s dirty=%s sig_changed=%s disable_cache_for_active_scavenger=%s" % [
		group_id,
		str(bool(_dirty_groups.get(group_id, false))),
		str(_last_signature_by_group.get(group_id, "") != signature),
		str(has_active_scavenger_resource_work),
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
	if not has_active_scavenger_resource_work:
		_cached_orders_by_group[group_id] = out.duplicate(true)
		_cached_orders_expires_at[group_id] = now + GROUP_ORDER_CACHE_TTL_SECONDS
	else:
		_cached_orders_by_group.erase(group_id)
		_cached_orders_expires_at.erase(group_id)
	_last_signature_by_group[group_id] = signature
	_dirty_groups[group_id] = false
	_maybe_log_polling_review(now)
	return out


func _build_group_signature(members: Array, group_ctx: Dictionary) -> String:
	var ids: Array[String] = []
	var member_cargo_tokens: Array[String] = []
	var member_active_tokens: Array[String] = []
	var member_resource_tokens: Array[String] = []
	for raw in members:
		if raw is Dictionary:
			var member: Dictionary = raw as Dictionary
			var member_id: String = String(member.get("member_id", ""))
			ids.append(member_id)
			member_cargo_tokens.append("%s:%d" % [member_id, int(member.get("cargo_count", 0))])
			member_active_tokens.append("%s:%s" % [member_id, str(bool(member.get("has_active_task", false)))])
			member_resource_tokens.append("%s:%d:%d" % [
				member_id,
				int(member.get("current_resource_id", 0)),
				int(member.get("pending_mine_id", 0)),
			])
	ids.sort()
	member_cargo_tokens.sort()
	member_active_tokens.sort()
	member_resource_tokens.sort()
	var mode: String = String(group_ctx.get("group_mode", "idle"))
	var interest_pos: Vector2 = group_ctx.get("interest_pos", Vector2.ZERO) as Vector2
	var prioritized_resource_ids: Array[String] = _extract_target_ids(group_ctx.get("prioritized_resources", []))
	var prioritized_drop_ids: Array[String] = _extract_target_ids(group_ctx.get("prioritized_drops", []))
	var any_scavenger_busy: bool = bool(group_ctx.get("any_scavenger_busy", false))
	var any_member_threatened: bool = bool(group_ctx.get("any_member_threatened", false))
	return "%s|%s|members=%s|res=%s|drops=%s|cargo=%s|active=%s|mine=%s|busy=%s|threat=%s" % [
		mode,
		str(interest_pos),
		",".join(ids),
		",".join(prioritized_resource_ids),
		",".join(prioritized_drop_ids),
		",".join(member_cargo_tokens),
		",".join(member_active_tokens),
		",".join(member_resource_tokens),
		str(any_scavenger_busy),
		str(any_member_threatened),
	]


func _extract_target_ids(raw_list: Variant) -> Array[String]:
	var out: Array[String] = []
	var values: Array = raw_list as Array
	for raw in values:
		var entry: Dictionary = raw as Dictionary
		out.append(str(int(entry.get("id", 0))))
	out.sort()
	return out


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


func _maybe_log_polling_review(now: float) -> void:
	if now - _last_polling_review_at < POLLING_REVIEW_INTERVAL_SECONDS:
		return
	_last_polling_review_at = now
	Debug.log("bandit_group", "[BGB][polling_review] cache_hit=%d event_recompute=%d periodic_recompute=%d" % [
		_cache_hit_count,
		_event_recompute_count,
		_periodic_recompute_count,
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
