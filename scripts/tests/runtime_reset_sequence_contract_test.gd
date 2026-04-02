extends SceneTree

const RuntimeResetCoordinatorScript := preload("res://scripts/world/RuntimeResetCoordinator.gd")

const EXPECTED_SEQUENCE := [
	"placement.clear_runtime_instances",
	"registries.faction.reset",
	"registries.site.reset",
	"registries.npc_profile.reset",
	"tactical.bandit_group_memory.reset",
	"tactical.extortion_queue.reset",
	"tactical.raid_queue.reset",
	"tactical.enemy_registry.reset",
	"time.run_clock.reset",
	"time.world_time.load_save_data",
	"hostility.faction_hostility_manager.reset",
]

func _init() -> void:
	run()


func run() -> void:
	print("Running RuntimeResetCoordinator sequence contract validation...")

	var coordinator: RuntimeResetCoordinator = RuntimeResetCoordinatorScript.new()
	var observed_sequence: Array[String] = []
	var spies: Dictionary = {}

	for operation in EXPECTED_SEQUENCE:
		var op_name := operation
		spies[op_name] = func() -> void:
			observed_sequence.append(op_name)

	coordinator.configure_validation_spies(spies)
	coordinator.reset_new_game()

	if observed_sequence != EXPECTED_SEQUENCE:
		print("FAIL: Runtime reset sequence contract violated.")
		print("Expected: ", EXPECTED_SEQUENCE)
		print("Observed: ", observed_sequence)
		quit(1)
		return

	print("PASS: Runtime reset sequence is stable and side-effect free under spies.")
	quit(0)
