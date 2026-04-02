extends Node
class_name BanditWorkCoordinator

## Low-level runtime coordinator for already-ticked bandits.
## Keeps concrete world interactions here and delegates carry logistics to CampStash.

const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")
const CombatStateServiceScript := preload("res://scripts/world/CombatStateService.gd")
const BWCAssaultStagesScript := preload("res://scripts/world/bandit_work_coordinator/BWCAssaultStages.gd")
const BWCCooldownsScript := preload("res://scripts/world/bandit_work_coordinator/BWCCooldowns.gd")
const BWCLootRuntimeScript := preload("res://scripts/world/bandit_work_coordinator/BWCLootRuntime.gd")
const BWCWallDamageScript := preload("res://scripts/world/bandit_work_coordinator/BWCWallDamage.gd")
const BWCRetreatRuntimeScript := preload("res://scripts/world/bandit_work_coordinator/BWCRetreatRuntime.gd")

const RAID_ATTACK_RANGE_SQ: float = 96.0 * 96.0
const INVALID_TARGET: Vector2 = Vector2(-1.0, -1.0)

var _stash: BanditCampStashSystem = null
var _world_node: Node = null
var _world_spatial_index: WorldSpatialIndex = null

var _cooldowns: BWCCooldowns = BWCCooldownsScript.new()
var _stages: BWCAssaultStages = BWCAssaultStagesScript.new()
var _loot_runtime: BWCLootRuntime = BWCLootRuntimeScript.new()
var _wall_damage: BWCWallDamage = BWCWallDamageScript.new()
var _retreat_runtime: BWCRetreatRuntime = BWCRetreatRuntimeScript.new()


func setup(ctx: Dictionary) -> void:
	_stash = ctx.get("stash") as BanditCampStashSystem
	_world_node = ctx.get("world_node")
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex


func process_post_behavior(beh: BanditWorldBehavior, enemy_node: Node, drops_cache: Array, execution_command: Dictionary = {}, combat_state: Dictionary = {}) -> void:
	if beh == null:
		return
	if enemy_node == null or not is_instance_valid(enemy_node):
		_handle_missing_enemy(beh)
		return

	_maybe_drop_carry_on_aggro(beh, enemy_node, combat_state)
	_execute_behavior_command(beh, enemy_node, execution_command)
	_handle_collection_and_deposit(beh, enemy_node, drops_cache)


func _execute_behavior_command(beh: BanditWorldBehavior, enemy_node: Node, command: Dictionary) -> void:
	if command.is_empty():
		return
	var intent: String = String(command.get("intent", BanditWorldBehavior.EXEC_INTENT_NONE))
	match intent:
		BanditWorldBehavior.EXEC_INTENT_MINE_RESOURCE:
			_handle_mining_command(beh, enemy_node, command)
		BanditWorldBehavior.EXEC_INTENT_STRUCTURE_ASSAULT:
			var result: Dictionary = _handle_structure_assault_command(beh, enemy_node, command)
			beh.apply_execution_feedback(command, result)
		_:
			pass


func _handle_missing_enemy(beh: BanditWorldBehavior) -> void:
	if _stash != null and not beh._cargo_manifest.is_empty():
		_stash.drop_carry_on_aggro(beh, null)
	if beh.pending_mine_id != 0 and not is_instance_id_valid(beh.pending_mine_id):
		beh.pending_mine_id = 0
		beh._resource_node_id = 0
	if beh.pending_collect_id != 0 and not is_instance_id_valid(beh.pending_collect_id):
		beh.pending_collect_id = 0
	_cooldowns.clear_member(beh.member_id)
	_stages.clear_member(beh.member_id)


func _maybe_drop_carry_on_aggro(beh: BanditWorldBehavior, enemy_node: Node, combat_state: Dictionary) -> void:
	if _stash == null or beh._cargo_manifest.is_empty():
		return
	var canonical: Dictionary = combat_state
	if canonical.is_empty():
		canonical = CombatStateServiceScript.read_actor_state(enemy_node)
	var events: Array = canonical.get("events", []) as Array
	if events.has(CombatStateServiceScript.EVENT_COMBAT_STARTED):
		_stash.drop_carry_on_aggro(beh, enemy_node)


func _handle_collection_and_deposit(beh: BanditWorldBehavior, enemy_node: Node,
		drops_cache: Array) -> void:
	if _stash == null:
		return

	if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH:
		var res_center := _resolve_resource_center(beh, enemy_node)
		_stash.sweep_collect_orbit(beh, enemy_node, res_center, drops_cache)
	elif beh.pending_collect_id != 0:
		_stash.sweep_collect_arrive(beh, enemy_node,
			(enemy_node as Node2D).global_position, drops_cache)

	_stash.handle_cargo_deposit(beh, enemy_node)


func _resolve_resource_center(beh: BanditWorldBehavior, enemy_node: Node) -> Vector2:
	var fallback := (enemy_node as Node2D).global_position
	if beh._resource_node_id == 0 or not is_instance_id_valid(beh._resource_node_id):
		if beh._resource_node_id != 0:
			beh._resource_node_id = 0
		return fallback
	var res := instance_from_id(beh._resource_node_id) as Node2D
	if res == null or not is_instance_valid(res) or res.is_queued_for_deletion():
		beh._resource_node_id = 0
		return fallback
	return res.global_position


func _handle_mining_command(beh: BanditWorldBehavior, enemy_node: Node, command: Dictionary) -> void:
	var mine_id: int = int(command.get("mine_id", 0))
	if mine_id == 0:
		return
	if not is_instance_id_valid(mine_id):
		beh._resource_node_id = 0
		return

	var res_node: Node = instance_from_id(mine_id) as Node
	if res_node == null or not is_instance_valid(res_node) or res_node.is_queued_for_deletion():
		beh._resource_node_id = 0
		return

	var enemy_pos: Vector2 = (enemy_node as Node2D).global_position
	var res_pos: Vector2 = (res_node as Node2D).global_position
	if enemy_pos.distance_squared_to(res_pos) > BanditTuningScript.mine_range_sq():
		return

	var wc: WeaponComponent = enemy_node.get_node_or_null("WeaponComponent") as WeaponComponent
	if wc != null and wc.current_weapon_id != "ironpipe":
		wc.equip_weapon_id("ironpipe")
		if wc.current_weapon_id != "ironpipe":
			return
		beh.pending_mine_id = mine_id
		return

	res_node.hit(enemy_node)
	if enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", res_pos)


func _handle_structure_assault_command(beh: BanditWorldBehavior, enemy_node: Node, command: Dictionary) -> Dictionary:
	if _stash == null:
		return {"allow": false, "reason": "stash_unavailable"}
	if _world_node == null or not is_instance_valid(_world_node):
		return {"allow": false, "reason": "world_unavailable"}
	if beh.group_id == "":
		return {"allow": false, "reason": "missing_group_id"}

	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	if g.is_empty():
		return {"allow": false, "reason": "group_missing"}
	var has_raid_context: bool = bool(command.get("has_raid_context", false))
	var group_anchor: Vector2 = command.get("group_anchor", INVALID_TARGET) as Vector2
	var member_anchor: Vector2 = command.get("member_anchor", INVALID_TARGET) as Vector2
	var canonical_target: Vector2 = command.get("canonical_target", INVALID_TARGET) as Vector2
	var consume_canonical_only: bool = bool(command.get("consume_canonical_only", false))
	var attack_anchor: Vector2 = member_anchor if _is_valid_target(member_anchor) else group_anchor

	var enemy_pos: Vector2 = command.get("node_pos", (enemy_node as Node2D).global_position) as Vector2

	var now: float = float(command.get("now", RunClock.now()))
	var member_id: String = beh.member_id
	_stages.ensure_run(member_id)
	var stage: String = _stages.stage_of(member_id)

	if stage == BWCAssaultStages.RAID_STAGE_CLOSED:
		return {"allow": false, "reason": "stage_closed", "stage": BWCAssaultStages.RAID_STAGE_CLOSED, "result": _stages.result_of(member_id, BWCAssaultStages.RAID_RESULT_ABORT)}
	if not has_raid_context:
		return _enter_raid_retreat(beh, member_id, now, "raid_context_lost")

	var stage_result: Dictionary = _execute_raid_stage(beh, enemy_node, member_id, stage, now, attack_anchor, enemy_pos)
	if not stage_result.is_empty():
		return stage_result

	var directive: Dictionary = BanditWallAssaultPolicy.evaluate_structure_directive({
		"world_node": _world_node,
		"has_raid_context": has_raid_context,
		"now": now,
		"attack_next_at": _cooldowns.attack_next_at(member_id),
		"enemy_pos": enemy_pos,
		"group_anchor": group_anchor,
		"member_anchor": member_anchor,
		"canonical_target": canonical_target,
		"consume_canonical_only": consume_canonical_only,
		"attack_range_sq": RAID_ATTACK_RANGE_SQ,
	})
	if not bool(directive.get("allow", false)):
		var deny_reason: String = String(directive.get("reason", "attack_blocked"))
		if _retreat_runtime.should_retreat_on_attack_deny(deny_reason):
			return _enter_raid_retreat(beh, member_id, now, deny_reason)
		directive["stage"] = BWCAssaultStages.RAID_STAGE_BREACH
		return directive

	var target: Dictionary = directive
	var target_pos: Vector2 = target.get("pos", INVALID_TARGET) as Vector2
	if not _is_valid_target(target_pos):
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "invalid_target", now)
	var attacked: bool = false
	var target_kind: String = String(target.get("kind", ""))
	if target_kind == "placeable":
		var node: Node = target.get("node") as Node
		if node != null and is_instance_valid(node) and not node.is_queued_for_deletion() \
				and node.has_method("hit"):
			if enemy_node.has_method("queue_ai_attack_press"):
				enemy_node.call("queue_ai_attack_press", target_pos)
			node.call("hit", enemy_node)
			attacked = true
	elif target_kind == "wall":
		attacked = _wall_damage.try_wall_slash_strike(enemy_node, _world_node, target_pos)

	if not attacked:
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "attack_failed", now)

	if target_kind != "wall":
		if enemy_node.has_method("queue_ai_attack_press"):
			enemy_node.call("queue_ai_attack_press", target_pos)
	_cooldowns.set_attack_next_at(member_id, float(target.get("next_attack_at", now + BanditWallAssaultPolicy.STRUCTURE_ATTACK_COOLDOWN)))
	_cooldowns.set_breach_resolved_at(member_id, now)
	if not _transition_raid_stage(member_id, BWCAssaultStages.RAID_STAGE_BREACH, BWCAssaultStages.RAID_STAGE_LOOT):
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "invalid_transition_breach", now)
	Debug.log("raid", "[BWC] structure hit npc=%s group=%s kind=%s pos=%s" % [
		beh.member_id, beh.group_id, target_kind, str(target_pos)
	])
	return {
		"allow": true,
		"reason": "attacked",
		"target_kind": target_kind,
		"target_pos": target_pos,
		"stage": BWCAssaultStages.RAID_STAGE_LOOT,
	}


func _handle_raid_loot_stage(beh: BanditWorldBehavior, enemy_node: Node, member_id: String,
		now: float, attack_anchor: Vector2, enemy_pos: Vector2) -> Dictionary:
	var loot_gate: Dictionary = BanditWallAssaultPolicy.can_transition_breach_to_loot({
		"has_raid_context": true,
		"now": now,
		"breach_resolved_at": _cooldowns.breach_resolved_at(member_id),
		"loot_next_at": _cooldowns.loot_next_at(member_id),
		"enemy_pos": enemy_pos,
		"loot_anchor": attack_anchor,
		"loot_range_sq": BWCLootRuntime.RAID_LOOT_RANGE_SQ,
	})
	if not bool(loot_gate.get("allow", false)):
		var deny_reason: String = String(loot_gate.get("reason", "loot_blocked"))
		if _retreat_runtime.should_retreat_on_loot_deny(deny_reason):
			return _enter_raid_retreat(beh, member_id, now, deny_reason)
		return {
			"allow": false,
			"reason": deny_reason,
			"stage": BWCAssaultStages.RAID_STAGE_LOOT,
		}

	var loot_result: Dictionary = _loot_runtime.try_loot_nearby_container(_stash, beh, enemy_pos, attack_anchor, _world_spatial_index, get_tree())
	var looted: bool = bool(loot_result.get("looted", false))
	_cooldowns.set_loot_next_at(member_id, now + BanditWallAssaultPolicy.STRUCTURE_LOOT_COOLDOWN)
	_cooldowns.set_attack_next_at(member_id, now + BanditWallAssaultPolicy.STRUCTURE_ATTACK_COOLDOWN)
	_stages.set_result(member_id, BWCAssaultStages.RAID_RESULT_SUCCESS)
	if not _transition_raid_stage(member_id, BWCAssaultStages.RAID_STAGE_LOOT, BWCAssaultStages.RAID_STAGE_RETREAT):
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "invalid_transition_loot", now)
	if looted:
		var container: ContainerPlaceable = loot_result.get("container") as ContainerPlaceable
		Debug.log("raid", "[BWC] chest looted npc=%s group=%s chest_uid=%s +%d cargo=%d/%d items=%s" % [
			beh.member_id,
			beh.group_id,
			container.placed_uid if container != null else "",
			int(loot_result.get("added", 0)),
			beh.cargo_count,
			beh.cargo_capacity,
			_loot_runtime.format_loot_entries(loot_result.get("taken", []) as Array),
		])
		return {
			"allow": true,
			"reason": "container_looted",
			"stage": BWCAssaultStages.RAID_STAGE_RETREAT,
			"result": BWCAssaultStages.RAID_RESULT_SUCCESS,
		}
	return {
		"allow": true,
		"reason": "loot_empty_or_unavailable",
		"stage": BWCAssaultStages.RAID_STAGE_RETREAT,
		"result": BWCAssaultStages.RAID_RESULT_SUCCESS,
	}


func _handle_raid_retreat_stage(beh: BanditWorldBehavior, member_id: String, now: float) -> Dictionary:
	_retreat_runtime.execute_retreat_effect(beh)
	var result: String = _stages.result_of(member_id, BWCAssaultStages.RAID_RESULT_RETREAT)
	if result == "":
		result = BWCAssaultStages.RAID_RESULT_RETREAT
	return _close_raid_run(member_id, result, "return_home", now)


func _execute_raid_stage(beh: BanditWorldBehavior, enemy_node: Node, member_id: String,
		stage: String, now: float, attack_anchor: Vector2, enemy_pos: Vector2) -> Dictionary:
	match stage:
		BWCAssaultStages.RAID_STAGE_ENGAGE:
			if not _transition_raid_stage(member_id, BWCAssaultStages.RAID_STAGE_ENGAGE, BWCAssaultStages.RAID_STAGE_BREACH):
				return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "invalid_transition_engage", now)
			return {"allow": false, "reason": "engage_confirmed", "stage": BWCAssaultStages.RAID_STAGE_BREACH}
		BWCAssaultStages.RAID_STAGE_LOOT:
			return _handle_raid_loot_stage(beh, enemy_node, member_id, now, attack_anchor, enemy_pos)
		BWCAssaultStages.RAID_STAGE_RETREAT:
			return _handle_raid_retreat_stage(beh, member_id, now)
		_:
			return {}


func _enter_raid_retreat(beh: BanditWorldBehavior, member_id: String, now: float, reason: String) -> Dictionary:
	var stage: String = _stages.stage_of(member_id)
	if stage == BWCAssaultStages.RAID_STAGE_CLOSED:
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, reason, now)
	if stage == BWCAssaultStages.RAID_STAGE_RETREAT:
		return _handle_raid_retreat_stage(beh, member_id, now)
	_stages.set_result(member_id, BWCAssaultStages.RAID_RESULT_RETREAT)
	if not _transition_raid_stage(member_id, stage, BWCAssaultStages.RAID_STAGE_RETREAT):
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "invalid_transition_retreat", now)
	return _handle_raid_retreat_stage(beh, member_id, now)


func _transition_raid_stage(member_id: String, from_stage: String, to_stage: String) -> bool:
	return _stages.transition(member_id, from_stage, to_stage)


func _close_raid_run(member_id: String, result: String, reason: String, now: float) -> Dictionary:
	_stages.close(member_id, result)
	_cooldowns.set_attack_next_at(member_id, now + BanditWallAssaultPolicy.STRUCTURE_ATTACK_COOLDOWN)
	return {
		"allow": result != BWCAssaultStages.RAID_RESULT_ABORT,
		"reason": reason,
		"stage": BWCAssaultStages.RAID_STAGE_CLOSED,
		"stage_closed": true,
		"result": result,
	}


func _is_valid_target(pos: Vector2) -> bool:
	return pos.is_finite() and not pos.is_equal_approx(INVALID_TARGET)
