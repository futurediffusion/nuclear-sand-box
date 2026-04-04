extends SceneTree

const ScavengerControllerScript := preload("res://scripts/world/ScavengerController.gd")
const FORBIDDEN_ORDER := "demolish_structure_target"


func run() -> void:
	var controller: ScavengerController = ScavengerControllerScript.new()
	_test_default_build_order_is_not_forbidden(controller)
	_test_forbidden_demolition_order_is_blocked(controller)
	print("[SCAVENGER_REGRESSION] PASS: scavenger never returns demolition/sabotage/assault structure orders")
	quit(0)


func _test_default_build_order_is_not_forbidden(controller: ScavengerController) -> void:
	var order: Dictionary = controller.build_order({
		"macro_state": "working",
		"prioritized_resources": [
			{"id": 101, "pos": Vector2(32, 16)},
		],
		"group_id": "test_group",
		"member_id": "test_scavenger",
	})
	assert(not controller._is_forbidden_scavenger_order(order), "build_order should never emit forbidden scavenger orders")


func _test_forbidden_demolition_order_is_blocked(controller: ScavengerController) -> void:
	var fallback: Dictionary = controller._resolve_scavenger_order({
		"order": FORBIDDEN_ORDER,
		"target_pos": Vector2(999, 999),
	}, {
		"macro_state": "idle",
		"cargo_count": 0,
		"group_id": "test_group",
		"member_id": "test_scavenger",
	}, [], [])
	var fallback_type: String = String(fallback.get("order", ""))
	assert(fallback_type != FORBIDDEN_ORDER, "forbidden demolition order must be blocked")
	assert(fallback_type == "mine_target" or fallback_type == "pickup_target" or fallback_type == "return_home",
		"fallback must be economic (mine_target/pickup_target/return_home)")


func _init() -> void:
	run()
