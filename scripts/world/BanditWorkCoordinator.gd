extends Node
class_name BanditWorkCoordinator

## Flow director for post-behavior raid execution.
## Domain decisions stay in BanditRaidRuntimePolicy/BanditWallAssaultPolicy.
## This coordinator only orchestrates state transitions and delegates runtime effects.

const CombatStateServiceScript := preload("res://scripts/world/CombatStateService.gd")
const BWCAssaultStagesScript := preload("res://scripts/world/bandit_work_coordinator/BWCAssaultStages.gd")
const BWCCooldownsScript := preload("res://scripts/world/bandit_work_coordinator/BWCCooldowns.gd")
const RaidStageFlowScript := preload("res://scripts/world/bandit_work_coordinator/RaidStageFlow.gd")
const LootExecutionScript := preload("res://scripts/world/bandit_work_coordinator/LootExecution.gd")
const WallDamageExecutionScript := preload("res://scripts/world/bandit_work_coordinator/WallDamageExecution.gd")
const RetreatExecutionScript := preload("res://scripts/world/bandit_work_coordinator/RetreatExecution.gd")
const CargoDepositExecutionScript := preload("res://scripts/world/bandit_work_coordinator/CargoDepositExecution.gd")
const MiningExecutionScript := preload("res://scripts/world/bandit_work_coordinator/MiningExecution.gd")

const RAID_ATTACK_RANGE_SQ: float = 96.0 * 96.0
const INVALID_TARGET: Vector2 = Vector2(-1.0, -1.0)

var _stash: BanditCampStashSystem = null
var _world_node: Node = null
var _world_spatial_index: WorldSpatialIndex = null

var _cooldowns: BWCCooldowns = BWCCooldownsScript.new()
var _stages: BWCAssaultStages = BWCAssaultStagesScript.new()
var _raid_stage_flow: RaidStageFlow = RaidStageFlowScript.new()
var _loot_execution: LootExecution = LootExecutionScript.new()
var _wall_damage_execution: WallDamageExecution = WallDamageExecutionScript.new()
var _retreat_execution: RetreatExecution = RetreatExecutionScript.new()
var _cargo_deposit_execution: CargoDepositExecution = CargoDepositExecutionScript.new()
var _mining_execution: MiningExecution = MiningExecutionScript.new()


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
	_cargo_deposit_execution.execute(_stash, beh, enemy_node, drops_cache)


func _execute_behavior_command(beh: BanditWorldBehavior, enemy_node: Node, command: Dictionary) -> void:
	if command.is_empty():
		return
	var intent: String = String(command.get("intent", BanditWorldBehavior.EXEC_INTENT_NONE))
	match intent:
		BanditWorldBehavior.EXEC_INTENT_MINE_RESOURCE:
			_mining_execution.execute(beh, enemy_node, command)
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


func _handle_structure_assault_command(beh: BanditWorldBehavior, enemy_node: Node, command: Dictionary) -> Dictionary:
	var validation: Dictionary = _validate_structure_assault_context(beh)
	if not validation.is_empty():
		return validation

	var has_raid_context: bool = bool(command.get("has_raid_context", false))
	var group_anchor: Vector2 = command.get("group_anchor", INVALID_TARGET) as Vector2
	var member_anchor: Vector2 = command.get("member_anchor", INVALID_TARGET) as Vector2
	var canonical_target: Vector2 = command.get("canonical_target", INVALID_TARGET) as Vector2
	var consume_canonical_only: bool = bool(command.get("consume_canonical_only", false))
	var attack_anchor: Vector2 = member_anchor if _is_valid_target(member_anchor) else group_anchor
	var enemy_pos: Vector2 = command.get("node_pos", (enemy_node as Node2D).global_position) as Vector2
	var now: float = float(command.get("now", RunClock.now()))
	var member_id: String = beh.member_id

	_raid_stage_flow.ensure_run(_stages, member_id)
	var stage: String = _raid_stage_flow.stage_of(_stages, member_id)
	if _raid_stage_flow.is_closed(stage):
		return {
			"allow": false,
			"reason": "stage_closed",
			"stage": BWCAssaultStages.RAID_STAGE_CLOSED,
			"result": _raid_stage_flow.result_of(_stages, member_id, BWCAssaultStages.RAID_RESULT_ABORT),
		}
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
		if _retreat_execution.should_retreat_on_attack_deny(deny_reason):
			return _enter_raid_retreat(beh, member_id, now, deny_reason)
		directive["stage"] = BWCAssaultStages.RAID_STAGE_BREACH
		return directive

	var assault_effect: Dictionary = _execute_structure_assault_effect(beh, enemy_node, directive)
	if not bool(assault_effect.get("attacked", false)):
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "attack_failed", now)

	var target_pos: Vector2 = assault_effect.get("target_pos", INVALID_TARGET) as Vector2
	var target_kind: String = String(assault_effect.get("target_kind", ""))
	_cooldowns.set_attack_next_at(member_id, float(directive.get("next_attack_at", now + BanditWallAssaultPolicy.STRUCTURE_ATTACK_COOLDOWN)))
	_cooldowns.set_breach_resolved_at(member_id, now)
	if not _raid_stage_flow.transition(_stages, member_id, BWCAssaultStages.RAID_STAGE_BREACH, BWCAssaultStages.RAID_STAGE_LOOT):
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


func _validate_structure_assault_context(beh: BanditWorldBehavior) -> Dictionary:
	if _stash == null:
		return {"allow": false, "reason": "stash_unavailable"}
	if _world_node == null or not is_instance_valid(_world_node):
		return {"allow": false, "reason": "world_unavailable"}
	if beh.group_id == "":
		return {"allow": false, "reason": "missing_group_id"}
	var g: Dictionary = BanditGroupMemory.get_group(beh.group_id)
	if g.is_empty():
		return {"allow": false, "reason": "group_missing"}
	return {}


func _execute_structure_assault_effect(beh: BanditWorldBehavior, enemy_node: Node, directive: Dictionary) -> Dictionary:
	var target_pos: Vector2 = directive.get("pos", INVALID_TARGET) as Vector2
	if not _is_valid_target(target_pos):
		return {"attacked": false}
	var attacked: bool = false
	var target_kind: String = String(directive.get("kind", ""))
	if target_kind == "placeable":
		var node: Node = directive.get("node") as Node
		if node != null and is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("hit"):
			if enemy_node.has_method("queue_ai_attack_press"):
				enemy_node.call("queue_ai_attack_press", target_pos)
			node.call("hit", enemy_node)
			attacked = true
	elif target_kind == "wall":
		attacked = _wall_damage_execution.try_wall_slash_strike(enemy_node, _world_node, target_pos)

	if target_kind != "wall" and attacked and enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", target_pos)
	return {
		"attacked": attacked,
		"target_kind": target_kind,
		"target_pos": target_pos,
	}


func _execute_raid_stage(beh: BanditWorldBehavior, enemy_node: Node, member_id: String,
		stage: String, now: float, attack_anchor: Vector2, enemy_pos: Vector2) -> Dictionary:
	match stage:
		BWCAssaultStages.RAID_STAGE_ENGAGE:
			if not _raid_stage_flow.transition(_stages, member_id, BWCAssaultStages.RAID_STAGE_ENGAGE, BWCAssaultStages.RAID_STAGE_BREACH):
				return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "invalid_transition_engage", now)
			return {"allow": false, "reason": "engage_confirmed", "stage": BWCAssaultStages.RAID_STAGE_BREACH}
		BWCAssaultStages.RAID_STAGE_LOOT:
			var loot_result: Dictionary = _loot_execution.execute_raid_loot_stage({
				"stash": _stash,
				"beh": beh,
				"member_id": member_id,
				"now": now,
				"enemy_pos": enemy_pos,
				"attack_anchor": attack_anchor,
				"world_spatial_index": _world_spatial_index,
				"scene_tree": get_tree(),
				"breach_resolved_at": _cooldowns.breach_resolved_at(member_id),
				"loot_next_at": _cooldowns.loot_next_at(member_id),
			})
			if not bool(loot_result.get("allow", false)):
				var deny_reason: String = String(loot_result.get("reason", "loot_blocked"))
				if _retreat_execution.should_retreat_on_loot_deny(deny_reason):
					return _enter_raid_retreat(beh, member_id, now, deny_reason)
				return loot_result
			_cooldowns.set_loot_next_at(member_id, float(loot_result.get("loot_next_at", now + BanditWallAssaultPolicy.STRUCTURE_LOOT_COOLDOWN)))
			_cooldowns.set_attack_next_at(member_id, float(loot_result.get("attack_next_at", now + BanditWallAssaultPolicy.STRUCTURE_ATTACK_COOLDOWN)))
			_raid_stage_flow.set_result(_stages, member_id, BWCAssaultStages.RAID_RESULT_SUCCESS)
			if not _raid_stage_flow.transition(_stages, member_id, BWCAssaultStages.RAID_STAGE_LOOT, BWCAssaultStages.RAID_STAGE_RETREAT):
				return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "invalid_transition_loot", now)
			return loot_result
		BWCAssaultStages.RAID_STAGE_RETREAT:
			_retreat_execution.execute(beh)
			var result: String = _raid_stage_flow.result_of(_stages, member_id, BWCAssaultStages.RAID_RESULT_RETREAT)
			if result == "":
				result = BWCAssaultStages.RAID_RESULT_RETREAT
			return _close_raid_run(member_id, result, "return_home", now)
		_:
			return {}


func _enter_raid_retreat(beh: BanditWorldBehavior, member_id: String, now: float, reason: String) -> Dictionary:
	var stage: String = _raid_stage_flow.stage_of(_stages, member_id)
	if stage == BWCAssaultStages.RAID_STAGE_CLOSED:
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, reason, now)
	if stage == BWCAssaultStages.RAID_STAGE_RETREAT:
		_retreat_execution.execute(beh)
		return _execute_raid_stage(beh, null, member_id, BWCAssaultStages.RAID_STAGE_RETREAT, now, INVALID_TARGET, INVALID_TARGET)
	_raid_stage_flow.set_result(_stages, member_id, BWCAssaultStages.RAID_RESULT_RETREAT)
	if not _raid_stage_flow.transition(_stages, member_id, stage, BWCAssaultStages.RAID_STAGE_RETREAT):
		return _close_raid_run(member_id, BWCAssaultStages.RAID_RESULT_ABORT, "invalid_transition_retreat", now)
	return _execute_raid_stage(beh, null, member_id, BWCAssaultStages.RAID_STAGE_RETREAT, now, INVALID_TARGET, INVALID_TARGET)


func _close_raid_run(member_id: String, result: String, reason: String, now: float) -> Dictionary:
	_raid_stage_flow.close(_stages, member_id, result)
	_cooldowns.set_attack_next_at(member_id, now + BanditWallAssaultPolicy.STRUCTURE_ATTACK_COOLDOWN)
	return _raid_stage_flow.close_payload(result, reason, BWCAssaultStages.RAID_STAGE_CLOSED)


func _is_valid_target(pos: Vector2) -> bool:
	return pos.is_finite() and not pos.is_equal_approx(INVALID_TARGET)
