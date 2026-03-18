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

	# 1. Alive -> Downed (Overkill test A)
	assert(not downed.is_downed, "Should start alive")
	health.take_damage(health.max_hp + 10)
	assert(downed.is_downed, "Should be downed after lethal damage")
	assert(health.hp == 0, "HP should be exactly 0, not negative")

	# 2. Downed -> Revived (Revive valid test B)
	downed.revive()
	assert(not downed.is_downed, "Should not be downed after revive")
	# Simulate CharacterBase._on_revived logic with set_hp_clamped
	health.set_hp_clamped(maxi(1, downed.downed_revive_hp))
	assert(health.hp >= 1, "Should have at least 1 HP after revive")
	assert(not health.is_dead(), "Health should report not dead")

	# 3. Alive -> Downed again (Damage after revive test C)
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

	RunClock.reset(100.0)
	WorldSave.clear_chunk_enemy_spawns("0,0")

	var enemy_id = "test_enemy"
	var chunk_key = "0,0"
	var downed_at = RunClock.now()
	var resolve_at = downed_at + 100.0

	# Setup base state so mark_enemy_downed actually has something to modify
	WorldSave.get_or_create_enemy_state(chunk_key, enemy_id, {
		"id": enemy_id,
		"chunk_key": chunk_key,
		"pos": Vector2.ZERO,
		"hp": 0,
		"is_dead": false,
		"is_downed": false,
		"version": 1
	})

	# Simulate marking as downed in WorldSave
	WorldSave.mark_enemy_downed(chunk_key, enemy_id, resolve_at, downed_at)

	var state = WorldSave.get_enemy_state(chunk_key, enemy_id)
	assert(state["is_downed"] == true, "State should be marked as downed (Test D)")
	assert(state["is_dead"] == false, "State should NOT be marked as dead when downed (Test D)")
	assert(is_equal_approx(float(state["downed_at"]), downed_at), "downed_at should match")
	assert(is_equal_approx(float(state["downed_resolve_at"]), resolve_at), "Resolution timestamp should match")

	# Simulate NpcSimulator reloading
	var downed_comp = preload("res://scripts/components/DownedComponent.gd").new()
	downed_comp.load_save_data(state)

	assert(downed_comp.is_downed, "Component should restore downed state")
	assert(is_equal_approx(downed_comp.downed_at, downed_at), "Component should restore downed_at")
	assert(is_equal_approx(downed_comp.downed_resolve_at, resolve_at), "Component should restore resolution timestamp")

	# Simulate marking as dead in WorldSave (Test E)
	WorldSave.mark_enemy_dead(chunk_key, enemy_id)
	var dead_state = WorldSave.get_enemy_state(chunk_key, enemy_id)
	assert(dead_state["is_dead"] == true, "State should be marked as dead (Test E)")
	assert(dead_state["is_downed"] == false, "State should NOT be marked as downed when dead (Test E)")

	print("SUCCESS: Downed Persistence")

func _init():
	run()
