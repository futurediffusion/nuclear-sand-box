extends Node
class_name BanditWorkCoordinator

## Low-level runtime coordinator for already-ticked bandits.
## Keeps concrete world interactions here and delegates carry logistics to CampStash.
##
## Resource-cycle ownership contract (decision here, execution in behavior):
## acquire resource -> hit -> drop candidate -> pickup -> cargo -> return -> deposit
## - Coordinator decides transition intent and validates guards.
## - Behavior keeps locomotion/state-machine execution.
## - CampStash executes concrete world pickup/deposit side effects.
##
## Stage contract (entry -> exit):
## 1) acquire_resource: state=RESOURCE_WATCH + valid _resource_node_id.
##    exits to hit_resource when pending_mine_id!=0.
## 2) hit_resource: pending_mine_id consumed and hit() attempted.
##    exits to drop_candidate (drop spawned in world) or acquire_resource retry.
## 3) drop_candidate: nearby sweep around resource center.
##    exits to pickup_intent when pending_collect_id!=0.
## 4) pickup_intent: sweep_collect_arrive resolves drop -> cargo_manifest/cargo_count.
##    exits to cargo_loaded (cargo_count>0) or acquire_resource retry.
## 5) cargo_loaded: cargo_count grows, coordinator requests RETURN_HOME intent.
##    exits to return_home via behavior.force_return_home().
## 6) return_home: behavior executes navigation to deposit/home.
##    exits to deposit when _just_arrived_home_with_cargo flag is consumed by stash.
## 7) deposit: stash handle_cargo_deposit empties manifest/counter.
##    exits to acquire_resource/patrol depending on behavior.

const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")

const RAID_ENGAGE_RADIUS_SQ: float = 260.0 * 260.0
const RAID_ATTACK_RANGE_SQ: float = 96.0 * 96.0
const RAID_LOOT_RANGE_SQ: float = 76.0 * 76.0
const RAID_TARGET_SEARCH_RADIUS: float = 180.0
const RAID_ATTACK_COOLDOWN: float = 0.45
const RAID_LOOT_COOLDOWN: float = 1.10
const RAID_ANCHOR_FALLBACK_HIT_RANGE_SQ: float = 112.0 * 112.0
const RAID_LOCAL_WALL_PROBE_RADIUS: float = 180.0
const RAID_LOCAL_WALL_STRIKE_RANGE_SQ: float = 164.0 * 164.0
const RESOURCE_HIT_RECENCY_TICKS: int = 10
const POST_HIT_CONTINUITY_WINDOW_TICKS: int = 3
const POST_HIT_PICKUP_RETRY_LIMIT: int = 3
const ENABLE_POST_DEPOSIT_RESUME_PHASE: bool = true
const DROP_SCAN_ENOUGH_THRESHOLD: int = 10
const DROP_SCAN_MAX_CANDIDATES_EVAL: int = 40
const drops_per_npc_per_tick_max: int = 2
const drops_global_per_pulse_max: int = 18
const RESERVATION_TIMEOUT_SECONDS: float = 6.0
const RESERVATION_HEARTBEAT_GRACE_SECONDS: float = 2.5
const DEPOSIT_SLOT_MODULO: int = 16

const INVALID_TARGET: Vector2 = Vector2(-1.0, -1.0)

var _stash: BanditCampStashSystem = null
var _world_node: Node = null
var _world_spatial_index: WorldSpatialIndex = null

var _raid_attack_next_at: Dictionary = {}  # member_id -> RunClock.now()
var _raid_loot_next_at: Dictionary = {}  # member_id -> RunClock.now()
var _state_lost_after_hit_count: int = 0
var _full_cycles_by_member: Dictionary = {}  # member_id -> completed_cycle_count
var _work_tick_seq: int = 0
var _active_work_cycle_by_member: Dictionary = {}  # member_id -> work_cycle_id
var _next_work_cycle_seq: int = 1
var _post_hit_continuity_until_tick_by_member: Dictionary = {}  # member_id -> tick deadline
var _post_hit_pickup_retry_by_member: Dictionary = {}  # member_id -> retry count
var _log_worker_event_cb: Callable = Callable()
var _is_worker_instrumentation_enabled_cb: Callable = Callable()
var _emit_group_event_cb: Callable = Callable()
var _instrumentation_enabled: bool = true
var _resource_reservations: Dictionary = {}  # resource_id -> {member_id, group_id, expires_at, last_heartbeat, target_id}
var _drop_reservations: Dictionary = {}  # drop_id -> {member_id, group_id, expires_at, last_heartbeat, target_id}
var _slot_reservations: Dictionary = {}  # slot_id -> {member_id, group_id, expires_at, last_heartbeat, target_id}
var _reservation_double_bookings_prevented: int = 0
var _reservation_expired_total: int = 0
var _reservation_reassignments_total: int = 0
var _last_leader_id_by_group: Dictionary = {}
var _last_group_mode_by_group: Dictionary = {}


func _fmt_pos(value: Vector2) -> String:
	return "%.2f,%.2f" % [value.x, value.y]


func _is_worker_event_logging_enabled() -> bool:
	if not _instrumentation_enabled:
		return false
	if _is_worker_instrumentation_enabled_cb.is_valid():
		return bool(_is_worker_instrumentation_enabled_cb.call())
	return Debug.is_enabled("bandit_pipeline")


func _current_work_cycle_id(beh: BanditWorldBehavior) -> String:
	if beh == null:
		return ""
	return String(_active_work_cycle_by_member.get(beh.member_id, ""))


func _ensure_work_cycle_id(beh: BanditWorldBehavior) -> String:
	if beh == null:
		return ""
	var member_id: String = beh.member_id
	var existing: String = String(_active_work_cycle_by_member.get(member_id, ""))
	if existing != "":
		return existing
	var cycle_id: String = "%s-%06d" % [member_id, _next_work_cycle_seq]
	_next_work_cycle_seq += 1
	_active_work_cycle_by_member[member_id] = cycle_id
	return cycle_id


func _complete_work_cycle(beh: BanditWorldBehavior) -> void:
	if beh == null:
		return
	_active_work_cycle_by_member.erase(beh.member_id)


func _emit_worker_event(event_name: String, beh: BanditWorldBehavior,
		used_pos: Vector2, target_id: String, extra := {}, ensure_cycle: bool = false) -> void:
	if not _is_worker_event_logging_enabled():
		return
	var work_cycle_id: String = _current_work_cycle_id(beh)
	if ensure_cycle:
		work_cycle_id = _ensure_work_cycle_id(beh)
	var payload := {
		"npc_id": beh.member_id if beh != null else "unknown",
		"group_id": beh.group_id if beh != null else "unknown",
		"camp_id": beh.group_id if beh != null else "unknown",
		"position_used": _fmt_pos(used_pos),
		"target_id": target_id,
		"state": str(int(beh.state)) if beh != null else "unknown",
		"tick": _work_tick_seq,
		"work_cycle_id": work_cycle_id,
	}
	for key in extra.keys():
		payload[key] = extra[key]
	if _log_worker_event_cb.is_valid():
		_log_worker_event_cb.call(event_name, payload)
		return
	var fallback := payload.duplicate()
	fallback["event"] = event_name
	Debug.log("bandit_pipeline", "[BWC_PIPE] %s" % JSON.stringify(fallback))


func setup(ctx: Dictionary) -> void:
	_stash = ctx.get("stash") as BanditCampStashSystem
	_world_node = ctx.get("world_node")
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex
	_log_worker_event_cb = ctx.get("log_worker_event_cb", Callable())
	_is_worker_instrumentation_enabled_cb = ctx.get("is_worker_instrumentation_enabled_cb", Callable())
	_emit_group_event_cb = ctx.get("emit_group_event_cb", Callable())
	_instrumentation_enabled = bool(ctx.get("worker_instrumentation_enabled", true))
	if _stash != null:
		_stash.set_work_context({
			"on_deposit_closed_cb": Callable(self, "notify_deposit_closed"),
		})




func _emit_group_event(event_name: String, beh: BanditWorldBehavior, payload: Dictionary = {}) -> void:
	if beh == null:
		return
	var normalized: Dictionary = payload.duplicate(true)
	normalized["event"] = event_name
	normalized["npc_id"] = String(normalized.get("npc_id", beh.member_id))
	normalized["group_id"] = String(normalized.get("group_id", beh.group_id))
	normalized["camp_id"] = String(normalized.get("camp_id", beh.group_id))
	if not normalized.has("target_id"):
		normalized["target_id"] = ""
	if _emit_group_event_cb.is_valid():
		_emit_group_event_cb.call(event_name, normalized)
	var used_pos: Vector2 = normalized.get("world_pos", beh.home_pos) as Vector2
	if used_pos == Vector2.ZERO and normalized.get("position", null) is Vector2:
		used_pos = normalized.get("position") as Vector2
	_emit_worker_event("group_event_" + event_name, beh, used_pos, String(normalized.get("target_id", "")), normalized)


func _sample_group_status_events(beh: BanditWorldBehavior) -> void:
	if beh == null or beh.group_id == "":
		return
	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	if g.is_empty():
		return
	var leader_id: String = String(g.get("leader_id", ""))
	var prev_leader: String = String(_last_leader_id_by_group.get(beh.group_id, ""))
	if prev_leader != "" and prev_leader != leader_id:
		_emit_group_event("leader_changed", beh, {
			"leader_id": leader_id,
			"previous_leader_id": prev_leader,
		})
	_last_leader_id_by_group[beh.group_id] = leader_id
	var mode: String = String(g.get("current_group_intent", "idle"))
	var prev_mode: String = String(_last_group_mode_by_group.get(beh.group_id, ""))
	if prev_mode != "" and prev_mode != mode:
		_emit_group_event("group_mode_changed", beh, {
			"group_mode": mode,
			"previous_group_mode": prev_mode,
		})
	_last_group_mode_by_group[beh.group_id] = mode

func get_work_tick_seq() -> int:
	return _work_tick_seq


func get_work_cycle_id_for_member(member_id: String) -> String:
	return String(_active_work_cycle_by_member.get(member_id, ""))


func has_recent_resource_hit(beh: BanditWorldBehavior) -> bool:
	if beh == null:
		return false
	if int(beh.last_resource_hit_tick) <= 0:
		return false
	return (_work_tick_seq - int(beh.last_resource_hit_tick)) <= RESOURCE_HIT_RECENCY_TICKS


func process_post_behavior(beh: BanditWorldBehavior, enemy_node: Node, pulse_drop_budget_ctx: Dictionary = {}) -> void:
	if beh == null:
		return
	_work_tick_seq += 1
	_expire_stale_reservations()
	if enemy_node == null or not is_instance_valid(enemy_node):
		_handle_missing_enemy(beh)
		return
	_refresh_member_reservations(beh, enemy_node)
	_sample_group_status_events(beh)

	_maybe_drop_carry_on_aggro(beh, enemy_node)
	_guard_resource_cycle_before_work(beh)
	_handle_mining(beh, enemy_node)
	_handle_structure_assault(beh, enemy_node)
	_handle_collection_and_deposit(beh, enemy_node, pulse_drop_budget_ctx)
	_guard_resource_cycle_after_work(beh)


func _handle_missing_enemy(beh: BanditWorldBehavior) -> void:
	if _stash != null and not beh._cargo_manifest.is_empty():
		_stash.drop_carry_on_aggro(beh, null)
	if beh.pending_mine_id != 0 and not is_instance_id_valid(beh.pending_mine_id):
		beh.pending_mine_id = 0
		beh._resource_node_id = 0
	if beh.pending_collect_id != 0 and not is_instance_id_valid(beh.pending_collect_id):
		beh.pending_collect_id = 0
	_raid_attack_next_at.erase(beh.member_id)
	_raid_loot_next_at.erase(beh.member_id)
	_active_work_cycle_by_member.erase(beh.member_id)
	_release_member_reservations(beh.member_id, "missing_enemy")
	_emit_group_event("member_died", beh, {"reason": "missing_enemy_runtime"})
	_clear_post_hit_continuity(beh)


func _refresh_member_reservations(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	if beh == null:
		return
	_release_member_reservations(beh.member_id, "heartbeat_refresh")
	var now: float = RunClock.now()
	var member_pos: Vector2 = _effective_work_position(enemy_node)
	if beh.pending_mine_id != 0:
		if not is_instance_id_valid(beh.pending_mine_id):
			beh.pending_mine_id = 0
			_request_replan(beh, member_pos, "resource_target_disappeared")
		else:
			_try_reserve_target(_resource_reservations, str(beh.pending_mine_id), beh, now, "resource")
	if beh.pending_collect_id != 0:
		if not is_instance_id_valid(beh.pending_collect_id):
			beh.pending_collect_id = 0
			_request_replan(beh, member_pos, "drop_target_disappeared")
		else:
			_try_reserve_target(_drop_reservations, str(beh.pending_collect_id), beh, now, "drop")
	var slot_id: String = _member_slot_key(beh)
	if slot_id != "":
		_try_reserve_target(_slot_reservations, slot_id, beh, now, "slot")


func _try_reserve_target(reservations: Dictionary, target_id: String, beh: BanditWorldBehavior,
		now: float, reservation_kind: String) -> bool:
	if target_id == "" or beh == null:
		return false
	var existing: Dictionary = reservations.get(target_id, {}) as Dictionary
	if not existing.is_empty():
		var holder_id: String = String(existing.get("member_id", ""))
		if holder_id != "" and holder_id != beh.member_id:
			var holder_heartbeat: float = float(existing.get("last_heartbeat", 0.0))
			var holder_expires_at: float = float(existing.get("expires_at", 0.0))
			if now <= holder_expires_at and (now - holder_heartbeat) <= RESERVATION_HEARTBEAT_GRACE_SECONDS:
				_reservation_double_bookings_prevented += 1
				_request_replan(beh, beh.home_pos, "%s_reserved_by_other" % reservation_kind)
				if reservation_kind == "resource":
					beh.pending_mine_id = 0
				elif reservation_kind == "drop":
					beh.pending_collect_id = 0
				return false
			_reservation_expired_total += 1
			_reservation_reassignments_total += 1
	reservations[target_id] = {
		"member_id": beh.member_id,
		"group_id": beh.group_id,
		"target_id": target_id,
		"last_heartbeat": now,
		"expires_at": now + RESERVATION_TIMEOUT_SECONDS,
	}
	return true


func _expire_stale_reservations() -> void:
	var now: float = RunClock.now()
	_expire_map_stale(_resource_reservations, now)
	_expire_map_stale(_drop_reservations, now)
	_expire_map_stale(_slot_reservations, now)


func _expire_map_stale(reservations: Dictionary, now: float) -> void:
	if reservations.is_empty():
		return
	var to_remove: Array = []
	for key in reservations.keys():
		var entry: Dictionary = reservations.get(key, {}) as Dictionary
		if entry.is_empty():
			to_remove.append(key)
			continue
		var expires_at: float = float(entry.get("expires_at", 0.0))
		var last_heartbeat: float = float(entry.get("last_heartbeat", 0.0))
		if now > expires_at or (now - last_heartbeat) > RESERVATION_HEARTBEAT_GRACE_SECONDS:
			to_remove.append(key)
	for key in to_remove:
		reservations.erase(key)
		_reservation_expired_total += 1


func _release_member_reservations(member_id: String, _reason: String = "") -> void:
	if member_id == "":
		return
	_release_member_from_map(_resource_reservations, member_id)
	_release_member_from_map(_drop_reservations, member_id)
	_release_member_from_map(_slot_reservations, member_id)


func _release_member_from_map(reservations: Dictionary, member_id: String) -> void:
	if reservations.is_empty():
		return
	var to_remove: Array = []
	for key in reservations.keys():
		var entry: Dictionary = reservations.get(key, {}) as Dictionary
		if String(entry.get("member_id", "")) == member_id:
			to_remove.append(key)
	for key in to_remove:
		reservations.erase(key)


func _request_replan(beh: BanditWorldBehavior, fallback_pos: Vector2, reason: String) -> void:
	if beh == null:
		return
	_reservation_reassignments_total += 1
	_emit_worker_event("assignment_replan", beh, fallback_pos, "", {
		"reason": reason,
		"state": int(beh.state),
	})
	_emit_group_event("target_invalidated", beh, {
		"reason": reason,
		"world_pos": fallback_pos,
	})
	if beh.state != NpcWorldBehavior.State.RETURN_HOME:
		beh._enter_patrol({})


func _member_slot_key(beh: BanditWorldBehavior) -> String:
	if beh == null or beh.group_id == "":
		return ""
	if beh.deposit_pos == Vector2.ZERO:
		return ""
	if beh.state != NpcWorldBehavior.State.RETURN_HOME and beh.state != NpcWorldBehavior.State.IDLE_AT_HOME:
		return ""
	var slot_idx: int = absi(int(hash(beh.member_id))) % DEPOSIT_SLOT_MODULO
	return "%s:%d" % [beh.group_id, slot_idx]


func get_reservation_owner_maps() -> Dictionary:
	return {
		"resource_id_to_member_id": _snapshot_owner_map(_resource_reservations),
		"drop_id_to_member_id": _snapshot_owner_map(_drop_reservations),
		"slot_id_to_member_id": _snapshot_owner_map(_slot_reservations),
	}


func consume_reservation_conflict_metrics() -> Dictionary:
	var snapshot: Dictionary = {
		"double_reservations_avoided": _reservation_double_bookings_prevented,
		"expired_reservations": _reservation_expired_total,
		"assignment_replans": _reservation_reassignments_total,
	}
	_reservation_double_bookings_prevented = 0
	_reservation_expired_total = 0
	_reservation_reassignments_total = 0
	return snapshot


func _snapshot_owner_map(reservations: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in reservations.keys():
		var entry: Dictionary = reservations.get(key, {}) as Dictionary
		var owner_id: String = String(entry.get("member_id", ""))
		if owner_id != "":
			out[key] = owner_id
	return out


func _maybe_drop_carry_on_aggro(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	if _stash == null or beh._cargo_manifest.is_empty():
		return
	var ai_comp := enemy_node.get_node_or_null("AIComponent")
	if ai_comp != null and ai_comp.get("target") != null:
		_emit_group_event("threat_seen", beh, {"threat_level": 1.0})
		_stash.drop_carry_on_aggro(beh, enemy_node)


func _handle_collection_and_deposit(beh: BanditWorldBehavior, enemy_node: Node,
		pulse_drop_budget_ctx: Dictionary = {}) -> void:
	if _stash == null:
		return

	var cargo_before_work: int = beh.cargo_count
	var member_pos: Vector2 = _effective_work_position(enemy_node)
	var npc_drop_budget_ctx: Dictionary = {
		"processed": 0,
		"max": drops_per_npc_per_tick_max,
	}
	var continuity_active: bool = _process_post_hit_continuity_window(
			beh, enemy_node, member_pos, pulse_drop_budget_ctx, npc_drop_budget_ctx)
	if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH and not continuity_active:
		var res_center := _resolve_resource_center(beh, enemy_node)
		_stash.sweep_collect_orbit(beh, enemy_node, res_center,
				_make_drop_query_ctx("drop_collect_orbit", pulse_drop_budget_ctx, npc_drop_budget_ctx))
	elif beh.pending_collect_id != 0:
		_stash.sweep_collect_arrive(beh, enemy_node, member_pos,
				_make_drop_query_ctx("drop_collect_arrive", pulse_drop_budget_ctx, npc_drop_budget_ctx))

	if beh.cargo_count > cargo_before_work:
		_emit_worker_event("cargo_updated", beh, member_pos, "", {
			"cargo_before": cargo_before_work,
			"cargo_after": beh.cargo_count,
		})
		_emit_group_event("drop_collected", beh, {
			"world_pos": member_pos,
			"amount": maxi(1, beh.cargo_count - cargo_before_work),
		})

	if beh.cargo_count > 0:
		var still_mining: bool = beh.state == NpcWorldBehavior.State.RESOURCE_WATCH \
				and beh._resource_node_id != 0 \
				and is_instance_id_valid(beh._resource_node_id)
		if not still_mining or beh.is_cargo_full():
			_request_return_home(beh, "cargo_loaded")

	_stash.handle_cargo_deposit(beh, enemy_node)


func _reactivate_resource_search(beh: BanditWorldBehavior, resume_pos: Vector2) -> void:
	if beh == null:
		return
	beh.pending_collect_id = 0
	beh.pending_mine_id = 0
	var resource_id: int = int(beh.last_valid_resource_node_id)
	if resource_id == 0:
		resource_id = int(beh._resource_node_id)
	if resource_id == 0 or not is_instance_id_valid(resource_id):
		_emit_worker_event("resource_reactivation_skipped", beh, resume_pos, "", {
			"reason": "missing_or_invalid_resource_id",
			"last_valid_resource_id": int(beh.last_valid_resource_node_id),
		})
		return
	beh.enter_resource_watch(_resolve_resource_center(beh, null), resource_id)
	_emit_worker_event("resource_reactivated", beh, resume_pos, str(resource_id), {
		"reason": "post_deposit_resume",
	})


func _resume_after_deposit_closed(beh: BanditWorldBehavior, deposit_pos: Vector2, had_cargo: bool) -> void:
	if beh == null or not had_cargo:
		return
	var current: int = int(_full_cycles_by_member.get(beh.member_id, 0))
	_full_cycles_by_member[beh.member_id] = current + 1
	_emit_worker_event("work_cycle_resumed", beh, deposit_pos, "", {
		"cycle_count": current + 1,
		"source": "deposit_closed",
	})
	if ENABLE_POST_DEPOSIT_RESUME_PHASE:
		_reactivate_resource_search(beh, deposit_pos)
	else:
		_emit_worker_event("work_cycle_resume_rollback", beh, deposit_pos, "", {
			"reason": "post_deposit_resume_phase_disabled",
		})
	_complete_work_cycle(beh)


func notify_deposit_closed(beh: BanditWorldBehavior, deposit_pos: Vector2,
		outcome: String, had_cargo: bool) -> void:
	if beh == null:
		return
	_emit_worker_event("deposit_closed_ack", beh, deposit_pos, "", {
		"outcome": outcome,
		"had_cargo": had_cargo,
	})
	_resume_after_deposit_closed(beh, deposit_pos, had_cargo)


func _resolve_resource_center(beh: BanditWorldBehavior, enemy_node: Node) -> Vector2:
	var fallback := _effective_work_position(enemy_node)
	var resource_id: int = beh._resource_node_id
	var used_sticky_resource_id: bool = false
	if resource_id == 0:
		resource_id = int(beh.last_valid_resource_node_id)
		used_sticky_resource_id = resource_id != 0
	if resource_id == 0 or not is_instance_id_valid(resource_id):
		if beh._resource_node_id != 0:
			beh._resource_node_id = 0
		_emit_worker_event("resource_index_missing", beh, fallback, "", {
			"stage": "resolve_resource_center",
		})
		return fallback
	var res: Node2D = null
	if _world_spatial_index != null and BanditTuningScript.enable_worker_resource_fallback():
		res = _world_spatial_index.resolve_runtime_node_with_fallback(
			WorldSpatialIndex.KIND_WORLD_RESOURCE,
			resource_id,
			{"expected_group": "world_resource"}
		)
	if res == null:
		res = instance_from_id(resource_id) as Node2D
	if res == null or not is_instance_valid(res) or res.is_queued_for_deletion():
		beh._resource_node_id = 0
		if beh.last_valid_resource_node_id == resource_id:
			beh.last_valid_resource_node_id = 0
		_emit_worker_event("resource_index_missing", beh, fallback, "", {
			"stage": "resolve_resource_center_invalid",
		})
		return fallback
	beh._resource_node_id = resource_id
	beh.last_valid_resource_node_id = resource_id
	if used_sticky_resource_id:
		_emit_worker_event("resource_fallback_applied", beh, fallback, str(resource_id), {
			"stage": "resolve_resource_center_sticky_id",
		})
	return res.global_position


func _handle_mining(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	var mine_id: int = beh.pending_mine_id
	if mine_id == 0:
		return
	_emit_worker_event("resource_acquired", beh, _effective_work_position(enemy_node), str(mine_id), {
		"stage": "mining_pending",
	}, true)
	_emit_group_event("resource_discovered", beh, {
		"target_id": str(mine_id),
		"world_pos": _effective_work_position(enemy_node),
	})
	beh.pending_mine_id = 0
	if not is_instance_id_valid(mine_id):
		beh._resource_node_id = 0
		_emit_worker_event("resource_index_missing", beh, _effective_work_position(enemy_node), str(mine_id), {
			"stage": "pending_mine_invalid",
		})
		_emit_group_event("resource_depleted", beh, {"target_id": str(mine_id), "reason": "pending_mine_invalid"})
		return

	var res_node: Node = instance_from_id(mine_id) as Node
	if res_node == null or not is_instance_valid(res_node) or res_node.is_queued_for_deletion():
		beh._resource_node_id = 0
		_emit_worker_event("resource_index_missing", beh, _effective_work_position(enemy_node), str(mine_id), {
			"stage": "resource_node_missing",
		})
		_emit_group_event("resource_depleted", beh, {"target_id": str(mine_id), "reason": "resource_node_missing"})
		return

	var enemy_pos: Vector2 = _effective_work_position(enemy_node)
	var res_pos: Vector2 = (res_node as Node2D).global_position
	if enemy_pos.distance_squared_to(res_pos) > BanditTuningScript.mine_range_sq():
		_restore_mine_intent_if_still_watching(beh, mine_id)
		return
	_emit_worker_event("resource_in_range", beh, enemy_pos, str(mine_id), {
		"resource_pos": _fmt_pos(res_pos),
	})

	var wc: WeaponComponent = enemy_node.get_node_or_null("WeaponComponent") as WeaponComponent
	if wc != null and wc.current_weapon_id != "ironpipe":
		wc.equip_weapon_id("ironpipe")
		if wc.current_weapon_id != "ironpipe":
			_restore_mine_intent_if_still_watching(beh, mine_id)
			return
		beh.pending_mine_id = mine_id
		return

	res_node.hit(enemy_node)
	_emit_worker_event("resource_hit", beh, enemy_pos, str(mine_id), {
		"resource_pos": _fmt_pos(res_pos),
	})
	_emit_group_event("drop_spawned", beh, {
		"target_id": str(mine_id),
		"position": res_pos,
		"amount": 1,
	})
	beh.last_valid_resource_node_id = mine_id
	beh.last_resource_hit_tick = _work_tick_seq
	_open_post_hit_continuity_window(beh)
	_preserve_cycle_after_hit(beh, mine_id)
	if enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", res_pos)


func _handle_structure_assault(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	if _stash == null:
		return
	if _world_node == null or not is_instance_valid(_world_node):
		return
	if beh.group_id == "":
		return

	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	if g.is_empty():
		return
	var intent: String = String(g.get("current_group_intent", ""))
	var assault_active: bool = BanditGroupMemory.is_structure_assault_active(beh.group_id)
	var has_raid_context: bool = assault_active \
			or intent == "raiding" \
			or BanditGroupMemory.has_placement_react_lock(beh.group_id)

	var group_anchor: Vector2 = _resolve_assault_anchor(beh.group_id, g)
	var member_anchor: Vector2 = _resolve_member_assault_anchor(beh, group_anchor)
	var attack_anchor: Vector2 = member_anchor if _is_valid_target(member_anchor) else group_anchor

	var enemy_pos: Vector2 = _effective_work_position(enemy_node)
	if not _is_valid_target(attack_anchor):
		attack_anchor = enemy_pos
	elif has_raid_context:
		var engaged_by_group: bool = _is_valid_target(group_anchor) \
				and enemy_pos.distance_squared_to(group_anchor) <= RAID_ENGAGE_RADIUS_SQ
		var engaged_by_member: bool = _is_valid_target(member_anchor) \
				and enemy_pos.distance_squared_to(member_anchor) <= RAID_ENGAGE_RADIUS_SQ
		if not engaged_by_group and not engaged_by_member:
			return
	else:
		var local_leash_sq: float = RAID_TARGET_SEARCH_RADIUS * RAID_TARGET_SEARCH_RADIUS
		if enemy_pos.distance_squared_to(attack_anchor) > local_leash_sq:
			return

	var now: float = RunClock.now()
	var member_id: String = beh.member_id

	if now >= float(_raid_loot_next_at.get(member_id, 0.0)):
		var looted: bool = _try_loot_nearby_container(beh, enemy_node, attack_anchor, enemy_pos)
		if looted:
			_raid_loot_next_at[member_id] = now + RAID_LOOT_COOLDOWN
			_raid_attack_next_at[member_id] = now + RAID_ATTACK_COOLDOWN
			return

	if now < float(_raid_attack_next_at.get(member_id, 0.0)):
		return

	var target: Dictionary = _resolve_structure_attack_target(attack_anchor, enemy_pos)
	if target.is_empty():
		_emit_group_event("target_invalidated", beh, {"reason": "assault_target_empty", "world_pos": attack_anchor})
		# Fallback: si estamos pegados al ancla de asalto y no hay target resoluble,
		# intentar daño directo de pared cerca del ancla para evitar quedarse trabado.
		var fallback_hit: bool = false
		var fallback_positions: Array[Vector2] = [enemy_pos]
		if _is_valid_target(attack_anchor) and enemy_pos.distance_squared_to(attack_anchor) > 1.0:
			fallback_positions.append(attack_anchor)
		if _is_valid_target(group_anchor) and enemy_pos.distance_squared_to(group_anchor) > 1.0:
			fallback_positions.append(group_anchor)
		for fallback_pos in fallback_positions:
			if fallback_pos != enemy_pos and enemy_pos.distance_squared_to(fallback_pos) > RAID_ANCHOR_FALLBACK_HIT_RANGE_SQ:
				continue
			if not _damage_player_wall_at(fallback_pos, beh):
				continue
			if enemy_node.has_method("queue_ai_attack_press"):
				enemy_node.call("queue_ai_attack_press", fallback_pos)
			_raid_attack_next_at[member_id] = now + RAID_ATTACK_COOLDOWN
			fallback_hit = true
			Debug.log("raid", "[BWC] structure fallback wall hit npc=%s group=%s pos=%s" % [
				beh.member_id, beh.group_id, str(fallback_pos)
			])
			break
		# Si ya no quedan paredes/placeables para este asalto y el NPC trae cargo,
		# priorizar retorno al barril para depositar en vez de quedarse reteniendo el ítem.
		if not fallback_hit and beh.cargo_count > 0:
			_request_return_home(beh, "structure_no_target_with_cargo")
			Debug.log("raid", "[BWC] structure no-target → return home with cargo npc=%s group=%s cargo=%d" % [
				beh.member_id, beh.group_id, beh.cargo_count
			])
		return
	var target_pos: Vector2 = target.get("pos", INVALID_TARGET) as Vector2
	if not _is_valid_target(target_pos):
		return
	if enemy_pos.distance_squared_to(target_pos) > RAID_ATTACK_RANGE_SQ:
		_try_local_wall_strike(
			beh,
			enemy_node,
			enemy_pos,
			attack_anchor,
			group_anchor,
			now,
			member_id
		)
		return

	var attacked: bool = false
	var target_kind: String = String(target.get("kind", ""))
	if target_kind == "placeable":
		var node: Node = target.get("node") as Node
		if node != null and is_instance_valid(node) and not node.is_queued_for_deletion() \
				and node.has_method("hit"):
			node.call("hit", enemy_node)
			attacked = true
	elif target_kind == "wall":
		attacked = _damage_player_wall_at(target_pos, beh)

	if not attacked:
		if target_kind == "wall":
			_try_local_wall_strike(
				beh,
				enemy_node,
				enemy_pos,
				attack_anchor,
				group_anchor,
				now,
				member_id
			)
		return

	_trigger_wall_melee_animation(enemy_node, target_pos)
	_raid_attack_next_at[member_id] = now + RAID_ATTACK_COOLDOWN
	Debug.log("raid", "[BWC] structure hit npc=%s group=%s kind=%s pos=%s" % [
		beh.member_id, beh.group_id, target_kind, str(target_pos)
	])


func _resolve_assault_anchor(group_id: String, g: Dictionary) -> Vector2:
	var anchor: Vector2 = g.get("last_interest_pos", INVALID_TARGET) as Vector2
	if _is_valid_target(anchor):
		return anchor
	var pending: Vector2 = BanditGroupMemory.get_assault_target(group_id)
	return pending if _is_valid_target(pending) else INVALID_TARGET


func _effective_work_position(enemy_node: Node) -> Vector2:
	# Single helper to keep work/pickup queries consistent: member position is
	# the authoritative actor-space for local loot collection and mining loops.
	# Group/leader/camp anchors remain valid only for raid target selection.
	var node2d := enemy_node as Node2D
	return node2d.global_position if node2d != null else Vector2.ZERO


func _resolve_member_assault_anchor(beh: BanditWorldBehavior, group_anchor: Vector2) -> Vector2:
	if beh != null and beh.has_method("get_structure_assault_focus_target"):
		var focus_raw: Variant = beh.call("get_structure_assault_focus_target")
		if focus_raw is Vector2:
			var focus: Vector2 = focus_raw as Vector2
			if _is_valid_target(focus):
				return focus
	return group_anchor if _is_valid_target(group_anchor) else INVALID_TARGET


func _resolve_structure_attack_target(assault_anchor: Vector2, enemy_pos: Vector2) -> Dictionary:
	var query_ctx: Dictionary = {
		"intent": "raiding",
		"stage": "assault_member_target",
		"enough_threshold": 1,
		"max_candidates_eval": 32,
	}
	var search_centers: Array[Vector2] = [assault_anchor]
	if enemy_pos.distance_squared_to(assault_anchor) > 1.0:
		search_centers.append(enemy_pos)

	var placeable_node: Node2D = null
	for center in search_centers:
		if not _is_valid_target(center):
			continue
		placeable_node = _find_nearest_player_structure_node(enemy_pos, center)
		if placeable_node != null:
			break
	var placeable_pos: Vector2 = placeable_node.global_position if placeable_node != null else INVALID_TARGET
	if not _is_valid_target(placeable_pos) and _world_node.has_method("find_nearest_player_placeable_world_pos"):
		for center in search_centers:
			if not _is_valid_target(center):
				continue
			placeable_pos = _world_node.call("find_nearest_player_placeable_world_pos", center, RAID_TARGET_SEARCH_RADIUS, query_ctx) as Vector2
			if _is_valid_target(placeable_pos):
				break

	var wall_pos: Vector2 = INVALID_TARGET
	if _world_node.has_method("find_nearest_player_wall_world_pos"):
		for center in search_centers:
			if not _is_valid_target(center):
				continue
			wall_pos = _world_node.call("find_nearest_player_wall_world_pos", center, RAID_TARGET_SEARCH_RADIUS) as Vector2
			if _is_valid_target(wall_pos):
				break

	var has_placeable_node: bool = placeable_node != null \
			and is_instance_valid(placeable_node) \
			and not placeable_node.is_queued_for_deletion()
	var has_placeable: bool = _is_valid_target(placeable_pos) and has_placeable_node
	var has_wall: bool = _is_valid_target(wall_pos)
	if not has_placeable and not has_wall:
		return {}

	if has_placeable and not has_wall:
		return {"kind": "placeable", "pos": placeable_pos, "node": placeable_node}
	if has_wall and not has_placeable:
		return {"kind": "wall", "pos": wall_pos}

	var d_placeable: float = enemy_pos.distance_squared_to(placeable_pos)
	var d_wall: float = enemy_pos.distance_squared_to(wall_pos)
	if d_placeable <= d_wall:
		return {"kind": "placeable", "pos": placeable_pos, "node": placeable_node}
	return {"kind": "wall", "pos": wall_pos}


func _try_loot_nearby_container(beh: BanditWorldBehavior, enemy_node: Node,
		assault_anchor: Vector2, enemy_pos: Vector2) -> bool:
	if beh.is_cargo_full():
		return false

	var container: ContainerPlaceable = _find_nearest_raidable_container(enemy_pos, assault_anchor)
	if container == null:
		return false

	var chest_pos: Vector2 = container.global_position
	if enemy_pos.distance_squared_to(chest_pos) > RAID_LOOT_RANGE_SQ:
		return false

	var capacity_left: int = maxi(0, beh.cargo_capacity - beh.cargo_count)
	if capacity_left <= 0:
		return false

	var extracted: Array[Dictionary] = container.extract_items_for_raid(capacity_left)
	if extracted.is_empty():
		return false

	var cargo_result: Dictionary = _stash.append_manifest_entries(beh, extracted)
	var added: int = int(cargo_result.get("added", 0))
	var leftovers: Array = cargo_result.get("leftovers", []) as Array
	if not leftovers.is_empty():
		for raw_left in leftovers:
			if not (raw_left is Dictionary):
				continue
			var left: Dictionary = raw_left as Dictionary
			container.try_insert_item(String(left.get("item_id", "")), int(left.get("amount", 0)))

	if added <= 0:
		for raw_entry in extracted:
			if not (raw_entry is Dictionary):
				continue
			var entry: Dictionary = raw_entry as Dictionary
			container.try_insert_item(String(entry.get("item_id", "")), int(entry.get("amount", 0)))
		return false

	_request_return_home(beh, "raid_chest_loot")
	Debug.log("raid", "[BWC] chest looted npc=%s group=%s chest_uid=%s +%d cargo=%d/%d items=%s" % [
		beh.member_id,
		beh.group_id,
		container.placed_uid,
		added,
		beh.cargo_count,
		beh.cargo_capacity,
		_format_loot_entries(cargo_result.get("taken", []) as Array),
	])
	return true


func _return_home_block_reason(beh: BanditWorldBehavior) -> String:
	if beh == null:
		return "missing_behavior"
	match beh.state:
		NpcWorldBehavior.State.RETURN_HOME:
			return "already_returning_home"
		NpcWorldBehavior.State.HOLD_POSITION:
			if beh.cargo_count > 0:
				return "holding_position_with_cargo"
			return "holding_position_no_cargo"
		_:
			return ""


func _request_return_home(beh: BanditWorldBehavior, reason: String) -> bool:
	if beh == null:
		return false
	var block_reason: String = _return_home_block_reason(beh)
	if block_reason != "":
		Debug.log("bandit_ai", "[BWC] return_home_blocked npc=%s reason=%s block=%s cargo=%d state=%s tick=%d" % [
			beh.member_id,
			reason,
			block_reason,
			beh.cargo_count,
			str(int(beh.state)),
			_work_tick_seq,
		])
		# Priority rule: carrying cargo should preempt HOLD_POSITION unless another
		# stronger block exists.
		if block_reason != "holding_position_with_cargo":
			_emit_worker_event("cargo_not_returning", beh, beh.home_pos, "", {
				"reason": reason,
				"block": block_reason,
			})
			return false
		block_reason = ""

	if block_reason != "":
		return false
	beh.force_return_home()
	_emit_worker_event("return_home_triggered", beh, beh.home_pos, "", {
		"reason": reason,
		"cargo": beh.cargo_count,
	})
	if beh.state != NpcWorldBehavior.State.RETURN_HOME:
		_emit_worker_event("cargo_not_returning", beh, beh.home_pos, "", {
			"reason": reason,
			"post_state": str(int(beh.state)),
		})
	return true


func _restore_mine_intent_if_still_watching(beh: BanditWorldBehavior, mine_id: int) -> void:
	if beh == null:
		return
	if beh.state != NpcWorldBehavior.State.RESOURCE_WATCH:
		return
	if beh._resource_node_id != mine_id:
		return
	if beh.pending_collect_id != 0:
		return
	beh.pending_mine_id = mine_id


func _preserve_cycle_after_hit(beh: BanditWorldBehavior, mine_id: int) -> void:
	if beh == null:
		return
	if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH:
		return
	_state_lost_after_hit_count += 1
	if beh.pending_collect_id != 0:
		return
	if beh._resource_node_id != mine_id:
		return
	# Guard: if state was lost right after hit, re-enter resource watch explicitly.
	beh.enter_resource_watch(_resolve_resource_center(beh, null), mine_id)
	Debug.log("bandit_ai", "[BWC] state_lost_after_hit guard npc=%s mine_id=%d count=%d" % [
		beh.member_id, mine_id, _state_lost_after_hit_count
	])
	_emit_worker_event("state_lost_after_hit", beh, _resolve_resource_center(beh, null), str(mine_id), {
		"count": _state_lost_after_hit_count,
	})


func _open_post_hit_continuity_window(beh: BanditWorldBehavior) -> void:
	if beh == null:
		return
	var member_id: String = beh.member_id
	_post_hit_continuity_until_tick_by_member[member_id] = _work_tick_seq + POST_HIT_CONTINUITY_WINDOW_TICKS
	_post_hit_pickup_retry_by_member[member_id] = 0
	_emit_worker_event("post_hit_continuity_window_opened", beh, beh.home_pos, str(beh._resource_node_id), {
		"until_tick": int(_post_hit_continuity_until_tick_by_member.get(member_id, _work_tick_seq)),
		"window_ticks": POST_HIT_CONTINUITY_WINDOW_TICKS,
	})


func _clear_post_hit_continuity(beh: BanditWorldBehavior) -> void:
	if beh == null:
		return
	_post_hit_continuity_until_tick_by_member.erase(beh.member_id)
	_post_hit_pickup_retry_by_member.erase(beh.member_id)


func _is_post_hit_window_active(beh: BanditWorldBehavior) -> bool:
	if beh == null:
		return false
	var until_tick: int = int(_post_hit_continuity_until_tick_by_member.get(beh.member_id, 0))
	return until_tick > 0 and _work_tick_seq <= until_tick


func _has_worker_continuity(beh: BanditWorldBehavior) -> bool:
	if beh == null:
		return false
	return _is_post_hit_window_active(beh) \
			or beh.pending_collect_id != 0 \
			or beh.pending_mine_id != 0 \
			or beh.cargo_count > 0


func _emit_cycle_abandon_reason(beh: BanditWorldBehavior, reason: String) -> void:
	if beh == null:
		return
	_emit_worker_event("work_cycle_abandoned", beh, beh.home_pos, "", {
		"reason": reason,
		"pending_collect_id": beh.pending_collect_id,
		"pending_mine_id": beh.pending_mine_id,
		"cargo": beh.cargo_count,
	})


func _make_drop_query_ctx(stage: String, pulse_drop_budget_ctx: Dictionary = {},
		npc_drop_budget_ctx: Dictionary = {}) -> Dictionary:
	return {
		"intent": "idle",
		"stage": stage,
		"enough_threshold": DROP_SCAN_ENOUGH_THRESHOLD,
		"max_candidates_eval": DROP_SCAN_MAX_CANDIDATES_EVAL,
		"drops_per_npc_per_tick_max": drops_per_npc_per_tick_max,
		"drops_global_per_pulse_max": drops_global_per_pulse_max,
		"drops_global_counter_ctx": pulse_drop_budget_ctx,
		"drops_npc_counter_ctx": npc_drop_budget_ctx,
	}


func _process_post_hit_continuity_window(beh: BanditWorldBehavior, enemy_node: Node,
		member_pos: Vector2, pulse_drop_budget_ctx: Dictionary = {},
		npc_drop_budget_ctx: Dictionary = {}) -> bool:
	if beh == null or _stash == null:
		return false
	if not _is_post_hit_window_active(beh):
		return false
	if beh.is_cargo_full():
		_emit_group_event("deposit_full", beh, {"reason": "post_hit_window_cargo_full", "cargo": beh.cargo_count})
		_request_return_home(beh, "post_hit_window_cargo_full")
		return true

	var cargo_before: int = beh.cargo_count
	var had_pending_before: bool = beh.pending_collect_id != 0
	if had_pending_before:
		_stash.sweep_collect_arrive(beh, enemy_node, member_pos,
				_make_drop_query_ctx("post_hit_collect_arrive", pulse_drop_budget_ctx, npc_drop_budget_ctx))
		if beh.cargo_count > cargo_before:
			_clear_post_hit_continuity(beh)
			return true

	var still_without_pending: bool = beh.pending_collect_id == 0 and beh.cargo_count == cargo_before
	if still_without_pending:
		var res_center := _resolve_resource_center(beh, enemy_node)
		_stash.sweep_collect_orbit(beh, enemy_node, res_center,
				_make_drop_query_ctx("post_hit_collect_orbit_resource", pulse_drop_budget_ctx, npc_drop_budget_ctx))
		if beh.pending_collect_id == 0 and beh.cargo_count == cargo_before:
			_stash.sweep_collect_orbit(beh, enemy_node, member_pos,
					_make_drop_query_ctx("post_hit_collect_orbit_member", pulse_drop_budget_ctx, npc_drop_budget_ctx))
		if beh.cargo_count > cargo_before:
			_clear_post_hit_continuity(beh)
			return true
		if beh.pending_collect_id == 0:
			var retries: int = int(_post_hit_pickup_retry_by_member.get(beh.member_id, 0)) + 1
			_post_hit_pickup_retry_by_member[beh.member_id] = retries
			if retries >= POST_HIT_PICKUP_RETRY_LIMIT:
				_emit_cycle_abandon_reason(beh, "pickup_candidates_empty")
				_clear_post_hit_continuity(beh)
			else:
				_emit_worker_event("drop_pickup_retry_scheduled", beh, member_pos, "", {
					"retry": retries,
					"retry_limit": POST_HIT_PICKUP_RETRY_LIMIT,
				})
	return true


func _guard_resource_cycle_before_work(beh: BanditWorldBehavior) -> void:
	if beh == null:
		return
	# Empty transition guard: no mining target + no pickup target while in watcher state.
	if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH \
			and beh.pending_mine_id == 0 \
			and beh.pending_collect_id == 0 \
			and beh._resource_node_id == 0:
		if BanditTuningScript.enable_worker_resource_fallback() \
				and beh.last_valid_resource_node_id != 0 \
				and has_recent_resource_hit(beh):
			beh._resource_node_id = beh.last_valid_resource_node_id
			beh.pending_mine_id = beh._resource_node_id
			_emit_worker_event("resource_fallback_applied", beh, beh.home_pos, str(beh._resource_node_id), {
				"stage": "guard_before_work_recent_hit",
			}, true)
			return
		if beh.cargo_count > 0:
			_request_return_home(beh, "empty_resource_watch_with_cargo")


func _guard_resource_cycle_after_work(beh: BanditWorldBehavior) -> void:
	if beh == null:
		return
	if beh.state == NpcWorldBehavior.State.IDLE_AT_HOME or beh.state == NpcWorldBehavior.State.PATROL:
		if _has_worker_continuity(beh):
			if beh.cargo_count > 0:
				_request_return_home(beh, "continuity_guard_with_cargo")
				return
			if beh._resource_node_id != 0:
				beh.enter_resource_watch(_resolve_resource_center(beh, null), beh._resource_node_id)
				_emit_worker_event("state_lost_after_hit", beh, _resolve_resource_center(beh, null), str(beh._resource_node_id), {
					"reason": "continuity_guard_blocked_idle_patrol",
				})
			else:
				_emit_cycle_abandon_reason(beh, "state_lost_after_hit")
				_clear_post_hit_continuity(beh)
				beh.pending_collect_id = 0
				beh.pending_mine_id = 0
			return
	if beh.pending_collect_id != 0 and beh.cargo_count >= beh.cargo_capacity:
		# Transition cannot stay unresolved when capacity is full.
		beh.pending_collect_id = 0
		_emit_group_event("deposit_full", beh, {"reason": "collect_intent_while_full", "cargo": beh.cargo_count})
		_request_return_home(beh, "collect_intent_while_full")


func get_cycle_debug_stats() -> Dictionary:
	return {
		"state_lost_after_hit": _state_lost_after_hit_count,
		"full_cycles_by_member": _full_cycles_by_member.duplicate(true),
	}


func _find_nearest_raidable_container(enemy_pos: Vector2, assault_anchor: Vector2) -> ContainerPlaceable:
	var best: ContainerPlaceable = null
	var best_dsq: float = INF
	var search_centers: Array[Vector2] = [assault_anchor]
	if enemy_pos.distance_squared_to(assault_anchor) > 1.0:
		search_centers.append(enemy_pos)

	var runtime_nodes: Array = []
	var query_ctx: Dictionary = {
		"intent": "raiding",
		"stage": "assault_member_target",
		"enough_threshold": 3,
		"max_candidates_eval": 36,
	}
	if _world_spatial_index != null:
		for center in search_centers:
			if not _is_valid_target(center):
				continue
			runtime_nodes.append_array(_world_spatial_index.get_runtime_nodes_near(
				WorldSpatialIndex.KIND_STORAGE,
				center,
				RAID_TARGET_SEARCH_RADIUS,
				query_ctx
			))
	for raw_node in runtime_nodes:
		var container := raw_node as ContainerPlaceable
		if container == null:
			continue
		if not _is_valid_raid_container(container):
			continue
		var dsq: float = enemy_pos.distance_squared_to(container.global_position)
		if dsq < best_dsq:
			best_dsq = dsq
			best = container

	if best != null:
		return best

	for raw_node in get_tree().get_nodes_in_group("interactable"):
		var container := raw_node as ContainerPlaceable
		if container == null:
			continue
		if not _is_valid_raid_container(container):
			continue
		var near_any_center: bool = false
		for center in search_centers:
			if not _is_valid_target(center):
				continue
			if container.global_position.distance_squared_to(center) <= RAID_TARGET_SEARCH_RADIUS * RAID_TARGET_SEARCH_RADIUS:
				near_any_center = true
				break
		if not near_any_center:
			continue
		var dsq: float = enemy_pos.distance_squared_to(container.global_position)
		if dsq < best_dsq:
			best_dsq = dsq
			best = container
	return best


func _is_valid_raid_container(container: ContainerPlaceable) -> bool:
	if container == null or not is_instance_valid(container) or container.is_queued_for_deletion():
		return false
	if not container.is_raid_lootable():
		return false
	if container.get_raid_loot_total_units() <= 0:
		return false
	return true


func _find_nearest_player_structure_node(enemy_pos: Vector2, assault_anchor: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dsq: float = INF
	var max_search_sq: float = RAID_TARGET_SEARCH_RADIUS * RAID_TARGET_SEARCH_RADIUS

	var runtime_nodes: Array = []
	var query_ctx: Dictionary = {
		"intent": "raiding",
		"stage": "assault_member_target",
		"enough_threshold": 4,
		"max_candidates_eval": 40,
	}
	if _world_spatial_index != null:
		runtime_nodes.append_array(_world_spatial_index.get_runtime_nodes_near(
			WorldSpatialIndex.KIND_STORAGE, assault_anchor, RAID_TARGET_SEARCH_RADIUS, query_ctx))
		runtime_nodes.append_array(_world_spatial_index.get_runtime_nodes_near(
			WorldSpatialIndex.KIND_WORKBENCH, assault_anchor, RAID_TARGET_SEARCH_RADIUS, query_ctx))

	for raw_node in runtime_nodes:
		var node2d := raw_node as Node2D
		if node2d == null:
			continue
		if not _is_player_structure_node(node2d):
			continue
		var dsq: float = enemy_pos.distance_squared_to(node2d.global_position)
		if dsq < best_dsq:
			best_dsq = dsq
			best = node2d

	for raw_node in get_tree().get_nodes_in_group("interactable"):
		var node2d := raw_node as Node2D
		if node2d == null:
			continue
		if not _is_player_structure_node(node2d):
			continue
		if node2d.global_position.distance_squared_to(assault_anchor) > max_search_sq:
			continue
		var dsq: float = enemy_pos.distance_squared_to(node2d.global_position)
		if dsq < best_dsq:
			best_dsq = dsq
			best = node2d
	return best


func _is_player_structure_node(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if not node.has_method("hit"):
		return false
	if not ("placed_uid" in node):
		return false
	var placed_uid: String = String(node.get("placed_uid"))
	if placed_uid == "":
		return false
	if "faction_owner_id" in node and String(node.get("faction_owner_id")) != "":
		return false
	if "group_id" in node and String(node.get("group_id")) != "":
		return false
	return true


func _damage_player_wall_at(world_pos: Vector2, beh: BanditWorldBehavior = null) -> bool:
	if _world_node == null:
		return false
	var hit_ok: bool = false
	if _world_node.has_method("hit_wall_at_world_pos"):
		hit_ok = bool(_world_node.call("hit_wall_at_world_pos", world_pos, 1, 24.0, true))
	elif _world_node.has_method("damage_player_wall_at_world_pos"):
		hit_ok = bool(_world_node.call("damage_player_wall_at_world_pos", world_pos, 1))
	if hit_ok and beh != null:
		_emit_group_event("wall_breached", beh, {"world_pos": world_pos, "threat_level": 2.0})
	return hit_ok


func _is_valid_target(pos: Vector2) -> bool:
	return pos.is_finite() and not pos.is_equal_approx(INVALID_TARGET)


func _try_local_wall_strike(beh: BanditWorldBehavior, enemy_node: Node, enemy_pos: Vector2,
		primary_anchor: Vector2, secondary_anchor: Vector2, now: float, member_id: String) -> bool:
	if _world_node == null:
		return false
	if not _world_node.has_method("find_nearest_player_wall_world_pos"):
		return false

	var probes: Array[Vector2] = [enemy_pos]
	if _is_valid_target(primary_anchor) and enemy_pos.distance_squared_to(primary_anchor) > 1.0:
		probes.append(primary_anchor)
	if _is_valid_target(secondary_anchor) and enemy_pos.distance_squared_to(secondary_anchor) > 1.0:
		probes.append(secondary_anchor)

	var best_wall: Vector2 = INVALID_TARGET
	var best_dsq: float = INF
	for probe in probes:
		var wall_pos: Vector2 = _world_node.call(
			"find_nearest_player_wall_world_pos",
			probe,
			RAID_LOCAL_WALL_PROBE_RADIUS
		) as Vector2
		if not _is_valid_target(wall_pos):
			continue
		var dsq: float = enemy_pos.distance_squared_to(wall_pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best_wall = wall_pos

	if not _is_valid_target(best_wall):
		return false
	if best_dsq > RAID_LOCAL_WALL_STRIKE_RANGE_SQ:
		return false
	if not _damage_player_wall_at(best_wall, beh):
		return false

	_trigger_wall_melee_animation(enemy_node, best_wall)
	_raid_attack_next_at[member_id] = now + RAID_ATTACK_COOLDOWN
	Debug.log("raid", "[BWC] local wall strike npc=%s group=%s wall=%s" % [
		beh.member_id, beh.group_id, str(best_wall)
	])
	return true


## Fuerza ironpipe y dispara animación de slash visible al atacar una wall.
## Usa begin_scripted_melee_action para que el weapon controller tickee incluso
## cuando el enemy está fuera del rango normal de AI activa.
func _trigger_wall_melee_animation(enemy_node: Node, wall_pos: Vector2) -> void:
	if enemy_node == null or not is_instance_valid(enemy_node):
		return
	# Asegurar que tenga ironpipe equipado — no atacar walls con el arco
	var wc = enemy_node.get_node_or_null("WeaponComponent")
	if wc != null and wc.has_method("equip_weapon_id"):
		wc.equip_weapon_id("ironpipe")
		if enemy_node.has_method("_on_weapon_equipped_apply_visuals"):
			enemy_node.call("_on_weapon_equipped_apply_visuals", "ironpipe")
	# Usar begin_scripted_melee_action para activar _pending_scripted_melee_action
	# y que el weapon controller corra aunque la IA esté en lite/sleep mode
	if enemy_node.has_method("begin_scripted_melee_action"):
		enemy_node.call("begin_scripted_melee_action", wall_pos, RAID_ATTACK_COOLDOWN * 0.8)
	elif enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", wall_pos)


func _format_loot_entries(entries: Array) -> String:
	if entries.is_empty():
		return "[]"
	var parts: Array[String] = []
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw as Dictionary
		parts.append("%s×%d" % [String(e.get("item_id", "")), int(e.get("amount", 0))])
	return "[" + ", ".join(parts) + "]"
