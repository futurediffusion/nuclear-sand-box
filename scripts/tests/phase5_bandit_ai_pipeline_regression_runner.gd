extends SceneTree

const BanditPerceptionSystemScript := preload("res://scripts/domain/factions/BanditPerceptionSystem.gd")
const BanditIntentSystemScript := preload("res://scripts/domain/factions/BanditIntentSystem.gd")
const BanditTaskPlannerScript := preload("res://scripts/domain/factions/BanditTaskPlanner.gd")
const BanditBehaviorLayerScript := preload("res://scripts/world/BanditBehaviorLayer.gd")


class FakeBanditBehavior extends RefCounted:
	var member_id: String = "npc-test"
	var group_id: String = "group-test"
	var role: String = "bodyguard"
	var state: int = 0
	var delivery_lock_active: bool = false
	var cargo_count: int = 0
	var pending_collect_id: int = 0
	var pending_mine_id: int = 0
	var _loot_target_id: int = 0
	var _resource_node_id: int = 0
	var last_valid_resource_node_id: int = 0
	var wall_assault_calls: int = 0
	var last_wall_assault_target: Vector2 = Vector2.ZERO

	func enter_wall_assault(target: Vector2) -> void:
		wall_assault_calls += 1
		last_wall_assault_target = target

	func enter_extort_approach(_target: Vector2) -> void:
		pass

	func enter_resource_watch(_target: Vector2, _target_id: int) -> void:
		pass

	func enter_loot_approach(_target_id: int) -> void:
		pass

	func force_return_home() -> void:
		pass


func _init() -> void:
	run()


func run() -> void:
	print("[PHASE5] Running bandit AI pipeline regression harness...")
	_test_perception_output_generation()
	_test_canonical_intent_output_generation()
	_test_task_planning_output_generation()
	_test_execution_consumes_task_for_migrated_slice()
	_test_duplicate_decision_path_prevention()
	print("[PHASE5] PASS: perception/intent/task/execution slice remains stable")
	quit(0)


func _test_perception_output_generation() -> void:
	var perception_system: BanditPerceptionSystem = BanditPerceptionSystemScript.new()
	var out: Dictionary = perception_system.build_group_intent_perception({
		"group_id": "g-alpha",
		"members": [
			{"member_id": "m1", "in_combat": true, "recently_engaged": false},
			{"member_id": "m2", "in_combat": false, "recently_engaged": true},
		],
		"prioritized_drops": [{"id": 1, "pos": Vector2(10, 10)}],
		"prioritized_resources": [{"id": 2, "pos": Vector2(20, 20)}],
		"structure_assault_active": true,
	})
	assert(String(out.get("stage", "")) == "perception", "perception output must declare stage=perception")
	assert(String(out.get("group_id", "")) == "g-alpha", "perception output should preserve group_id")
	assert(bool((out.get("threat_signals", {}) as Dictionary).get("threat_detected", false)),
		"perception should detect threat when members are in combat/recently engaged")
	assert(int(out.get("nearby_loot_count", 0)) == 1 and int(out.get("nearby_resource_count", 0)) == 1,
		"perception should report nearby loot/resource counts")


func _test_canonical_intent_output_generation() -> void:
	var intent_system: BanditIntentSystem = BanditIntentSystemScript.new()
	intent_system.setup()
	var intent: Dictionary = intent_system.decide_group_intent(
		{
			"threat_signals": {"threat_detected": false},
			"has_assault_target": true,
			"nearby_loot_count": 0,
			"nearby_resource_count": 0,
		},
		{"current_group_intent": "idle", "has_placement_react_lock": false},
		{"policy_next_intent": "raiding", "reason": "phase5_regression", "source": "test"}
	)
	assert(String(intent.get("kind", "")) == "group_intent_decision", "intent output should be canonical decision record")
	assert(String(intent.get("group_mode", "")) == "raiding", "intent should preserve policy-selected group mode")
	assert(String(intent.get("decision_type", "")) == BanditIntentSystemScript.DECISION_STRUCTURE_ASSAULT,
		"intent should emit structure assault decision when raiding+assault target")


func _test_task_planning_output_generation() -> void:
	var planner: BanditTaskPlanner = BanditTaskPlannerScript.new()
	var planned: Dictionary = planner.plan_member_task(
		{
			"kind": "group_intent_decision",
			"group_mode": "raiding",
			"decision_type": BanditIntentSystemScript.DECISION_STRUCTURE_ASSAULT,
		},
		{
			"role": "bodyguard",
			"interest_pos": Vector2(128, 64),
			"home_pos": Vector2(0, 0),
			"macro_state": "raiding",
		},
		{"order": "attack_target", "target_pos": Vector2(8, 8)}
	)
	assert(String(planned.get("order", "")) == BanditTaskPlanner.ORDER_ASSAULT_STRUCTURE_TARGET,
		"task planner should canonicalize bodyguard raiding to assault_structure_target")
	var task: Dictionary = planned.get("task", {}) as Dictionary
	assert(String(task.get("kind", "")) == BanditTaskPlanner.ORDER_ASSAULT_STRUCTURE_TARGET,
		"task payload kind should match canonical task order")


func _test_execution_consumes_task_for_migrated_slice() -> void:
	var behavior_layer: BanditBehaviorLayer = BanditBehaviorLayerScript.new()
	behavior_layer.set_worker_instrumentation_enabled(false)
	var fake_beh := FakeBanditBehavior.new()
	var ctx: Dictionary = {
		"node_pos": Vector2(32, 32),
		"in_combat": false,
		"recently_engaged": false,
	}
	var order := {
		"order": "assault_structure_target",
		"target_pos": Vector2(96, 96),
		"task": {
			"kind": "assault_structure_target",
			"macro_state": "raiding",
			"intent": {"decision_type": BanditIntentSystemScript.DECISION_STRUCTURE_ASSAULT},
		},
	}
	behavior_layer.call("_apply_member_order", fake_beh, ctx, order)
	assert(fake_beh.wall_assault_calls == 1,
		"execution layer should consume migrated task and route to wall assault behavior")
	assert(fake_beh.last_wall_assault_target == Vector2(96, 96),
		"execution layer should consume task target position for wall assault")


func _test_duplicate_decision_path_prevention() -> void:
	var behavior_layer: BanditBehaviorLayer = BanditBehaviorLayerScript.new()
	behavior_layer.set_worker_instrumentation_enabled(false)
	var fake_beh := FakeBanditBehavior.new()
	var ctx: Dictionary = {
		"node_pos": Vector2(32, 32),
		"in_combat": false,
		"recently_engaged": false,
	}
	var mismatched_order := {
		"order": "attack_target",
		"target_pos": Vector2(80, 80),
		"task": {
			"kind": "assault_structure_target",
			"macro_state": "raiding",
			"intent": {"decision_type": BanditIntentSystemScript.DECISION_STRUCTURE_ASSAULT},
		},
	}
	behavior_layer.call("_apply_member_order", fake_beh, ctx, mismatched_order)
	assert(fake_beh.wall_assault_calls == 0,
		"execution layer should block mismatched order/task to avoid duplicate decision paths")
