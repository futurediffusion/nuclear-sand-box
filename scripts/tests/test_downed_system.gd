extends SceneTree

# Mocking parts of the engine/project as needed
# Since we cannot run a full Godot scene tree easily,
# we will test the logic in isolation by instantiating the components.

func run():
	print("--- Running Downed System Tests ---")

	test_transitions()
	test_persistence()

	print("--- All Downed System Tests Passed! ---")
	quit(0)

func test_transitions():
	print("Testing Downed Transitions...")

	# Mock Character
	var char = CharacterBody2D.new()
	var health = preload("res://scripts/components/HealthComponent.gd").new()
	health.name = "HealthComponent"
	char.add_child(health)

	var downed = preload("res://scripts/components/DownedComponent.gd").new()
	downed.name = "DownedComponent"
	downed.downed_duration_seconds = 1.0 # Short for testing
	char.add_child(downed)

	# CharacterBase logic usually connects these, let's do it manually for the test
	health.died.connect(func(): downed.enter_downed())

	# 1. Alive -> Downed
	assert(not downed.is_downed, "Should start alive")
	health.take_damage(health.max_hp)
	assert(downed.is_downed, "Should be downed after lethal damage")
	assert(health.hp <= 0, "HP should be 0 or less")

	# 2. Downed -> Revived
	downed.revive()
	assert(not downed.is_downed, "Should not be downed after revive")
	# Simulate CharacterBase._on_revived logic
	health.heal(1)
	assert(health.hp == 1, "Should have 1 HP after revive")
	assert(not health.is_dead(), "Health should report not dead")

	# 3. Alive -> Downed again (verifying fix for _dead_emitted)
	health.take_damage(1)
	assert(downed.is_downed, "Should be downed again after lethal damage")

	# 4. Downed -> Dead (finishing blow)
	downed.die_final()
	assert(not downed.is_downed, "Should not be downed after final death")

	# 5. Downed -> Reset (respawn)
	health.take_damage(health.max_hp)
	assert(downed.is_downed, "Should be downed again")
	downed.reset()
	assert(not downed.is_downed, "Should not be downed after reset")
	assert(downed.downed_at == 0.0, "downed_at should be reset")

	print("SUCCESS: Downed Transitions")

func test_persistence():
	print("Testing Downed Persistence...")

	WorldSave.clear_chunk_enemy_spawns("0,0")

	var enemy_id = "test_enemy"
	var chunk_key = "0,0"
	var resolve_at = RunClock.time + 100.0

	# Setup base state so mark_enemy_downed actually has something to modify
	WorldSave.get_or_create_enemy_state(chunk_key, enemy_id, {})

	# Simulate marking as downed in WorldSave
	WorldSave.mark_enemy_downed(chunk_key, enemy_id, resolve_at)

	var state = WorldSave.get_enemy_state(chunk_key, enemy_id)
	assert(state["is_downed"] == true, "State should be marked as downed")
	assert(state["downed_resolve_at"] == resolve_at, "Resolution timestamp should match")

	# Simulate NpcSimulator reloading
	var downed_comp = preload("res://scripts/components/DownedComponent.gd").new()
	downed_comp.load_save_data(state)

	assert(downed_comp.is_downed, "Component should restore downed state")
	assert(downed_comp.downed_resolve_at == resolve_at, "Component should restore resolution timestamp")

	print("SUCCESS: Downed Persistence")

func _init():
	run()
