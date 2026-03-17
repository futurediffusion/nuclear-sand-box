extends Node

func _ready() -> void:
	print("--- Running Downed System Tests ---")
	await test_alive_to_downed()
	await test_downed_to_dead_finishing_blow()
	await test_downed_to_alive_recovery()
	await test_persistence()
	print("--- Downed System Tests Completed ---")
	get_tree().quit()

func test_alive_to_downed():
	print("Test: alive -> downed")
	var character = CharacterBase.new()
	character.name = "TestCharacter"
	add_child(character)
	character._setup_health_component()

	assert(not character.is_downed(), "Should not be downed initially")

	character.take_damage(character.max_hp + 1)

	assert(character.is_downed(), "Should be downed after taking lethal damage")
	assert(character.hp <= 0, "HP should be 0 or less")
	print("  Passed")
	character.queue_free()

func test_downed_to_dead_finishing_blow():
	print("Test: downed -> dead (finishing blow)")
	var character = CharacterBase.new()
	character.name = "TestCharacter"
	add_child(character)
	character._setup_health_component()

	character.take_damage(character.max_hp + 1)
	assert(character.is_downed(), "Should be downed")

	var died_signal_called = false
	character.health_component.died.connect(func(): died_signal_called = true)

	character.take_damage(1)
	assert(character.dying, "Should be dying after finishing blow")
	assert(not character.is_downed(), "Should no longer be marked as downed")
	print("  Passed")
	character.queue_free()

func test_downed_to_alive_recovery():
	print("Test: downed -> alive (recovery)")
	var character = CharacterBase.new()
	character.name = "TestCharacter"
	add_child(character)
	character._setup_health_component()

	character.enter_downed()
	assert(character.is_downed(), "Should be downed")

	character.recover_from_downed()
	assert(not character.is_downed(), "Should no longer be downed")
	assert(character.hp > 0, "Should have HP after recovery")
	print("  Passed")
	character.queue_free()

func test_persistence():
	print("Test: Persistence (Save/Load mock)")
	# Since we can't easily run the whole world, we test the state capturing
	var enemy = EnemyAI.new()
	enemy.name = "TestEnemy"
	enemy.entity_uid = "test_uid"
	add_child(enemy)
	# Need to mock some things because EnemyAI expects them in _ready
	enemy._setup_done = true
	enemy._setup_inventory_component()
	enemy._setup_weapon_component()
	enemy._setup_health_component()

	enemy.enter_downed()
	var state = enemy.capture_save_state()

	assert(state["is_downed"] == true, "Save state should have is_downed = true")
	assert(state["downed_resolve_at"] > 0, "Save state should have resolution timestamp")

	var new_enemy = EnemyAI.new()
	new_enemy.name = "TestEnemy2"
	add_child(new_enemy)
	new_enemy._setup_done = true
	new_enemy._setup_inventory_component()
	new_enemy._setup_weapon_component()
	new_enemy._setup_health_component()

	new_enemy.apply_save_state(state)
	# apply_save_state calls enter_downed if is_downed is true
	assert(new_enemy.is_downed(), "New enemy should be downed after applying save state")

	print("  Passed")
	enemy.queue_free()
	new_enemy.queue_free()
