extends SceneTree

const BuildingSystemScript := preload("res://scripts/domain/building/BuildingSystem.gd")
const BuildingCommandsScript := preload("res://scripts/domain/building/BuildingCommands.gd")
const BuildingStateScript := preload("res://scripts/domain/building/BuildingState.gd")
const BuildingColliderRefreshProjectionScript := preload("res://scripts/projections/collider/BuildingColliderRefreshProjection.gd")
const WorldProjectionRefreshContractScript := preload("res://scripts/world/contracts/WorldProjectionRefreshContract.gd")

class FakeProjectionRefreshPort extends WorldProjectionRefreshContractScript:
	var calls: Array[Array] = []

	func refresh_for_tiles(tile_positions: Array[Vector2i]) -> void:
		calls.append(tile_positions.duplicate())


func run() -> void:
	print("[BUILDING_PHASE2] Running building vertical slice regression harness...")
	var system: BuildingSystem = BuildingSystemScript.new()
	system.setup(BuildingStateScript.create_empty())

	var projection_port := FakeProjectionRefreshPort.new()
	var projection: BuildingColliderRefreshProjection = BuildingColliderRefreshProjectionScript.new()
	projection.setup({
		"projection_refresh_port": projection_port,
		"is_valid_world_tile": func(_tile: Vector2i) -> bool: return true,
		"wall_reconnect_offsets": [Vector2i.ZERO, Vector2i.RIGHT],
	})

	var tile := Vector2i(10, 10)
	var chunk := Vector2i(0, 0)
	var metadata := BuildingStateScript.create_player_wall_metadata(true, "wallwood", 1)

	_test_place_structure(system, projection, projection_port, tile, chunk, metadata)
	_test_damage_structure(system, tile)
	_test_remove_structure(system, projection, projection_port, metadata)
	_test_rebuild_and_apply_projection(system, projection, projection_port, chunk)

	print("[BUILDING_PHASE2] PASS: place/damage/remove/projection regressions are stable")
	quit(0)


func _test_place_structure(
		system: BuildingSystem,
		projection: BuildingColliderRefreshProjection,
		port: FakeProjectionRefreshPort,
		tile: Vector2i,
		chunk: Vector2i,
		metadata: Dictionary
	) -> void:
	var place_cmd: Dictionary = BuildingCommandsScript.place_structure("", tile, 8, metadata)
	place_cmd["hp"] = 8
	place_cmd["chunk_pos"] = chunk
	place_cmd["kind"] = "player_wall"

	var placed_result: Dictionary = system.process(place_cmd)
	assert(bool(placed_result.get(BuildingSystem.RESULT_KEY_SUCCESS, false)), "place_structure should succeed")
	assert(BuildingStateScript.has_structure_at_tile(system.get_state(), tile), "placed tile should be indexed")
	assert((placed_result.get(BuildingSystem.RESULT_KEY_EVENTS, []) as Array).size() == 1,
		"place_structure should emit structure_placed event")

	projection.apply_change_set(placed_result.get(BuildingSystem.RESULT_KEY_CHANGED_STRUCTURES, []))
	assert(port.calls.size() == 1, "projection refresh should be triggered by placement change-set")
	assert(_scope_has_tile(port.calls[0], tile), "projection scope should include placed tile")
	assert(_scope_has_tile(port.calls[0], tile + Vector2i.RIGHT), "projection scope should include reconnect neighbor")


func _test_damage_structure(system: BuildingSystem, tile: Vector2i) -> void:
	var damage_partial: Dictionary = system.process(BuildingCommandsScript.damage_structure(tile, 3))
	assert(bool(damage_partial.get(BuildingSystem.RESULT_KEY_SUCCESS, false)), "non-lethal damage should succeed")
	var structure_after_partial: Dictionary = BuildingStateScript.get_structure_at_tile(system.get_state(), tile)
	assert(int(structure_after_partial.get(BuildingStateScript.STRUCTURE_KEY_HP, -1)) == 5,
		"non-lethal damage should reduce hp deterministically")

	var damage_lethal: Dictionary = system.process(BuildingCommandsScript.damage_structure(tile, 5))
	assert(bool(damage_lethal.get(BuildingSystem.RESULT_KEY_SUCCESS, false)), "lethal damage should succeed")
	assert(not BuildingStateScript.has_structure_at_tile(system.get_state(), tile),
		"lethal damage should remove structure from state")
	var lethal_events: Array = damage_lethal.get(BuildingSystem.RESULT_KEY_EVENTS, [])
	assert(lethal_events.size() == 2, "lethal damage should emit damaged+removed events")


func _test_remove_structure(
		system: BuildingSystem,
		projection: BuildingColliderRefreshProjection,
		port: FakeProjectionRefreshPort,
		metadata: Dictionary
	) -> void:
	var tile := Vector2i(12, 7)
	var place_cmd: Dictionary = BuildingCommandsScript.place_structure("manual_remove", tile, 4, metadata)
	place_cmd["chunk_pos"] = Vector2i(0, 0)
	place_cmd["kind"] = "player_wall"
	var place_result: Dictionary = system.process(place_cmd)
	assert(bool(place_result.get(BuildingSystem.RESULT_KEY_SUCCESS, false)), "setup place for remove should succeed")

	var remove_result: Dictionary = system.process(BuildingCommandsScript.remove_structure(tile, "cleanup"))
	assert(bool(remove_result.get(BuildingSystem.RESULT_KEY_SUCCESS, false)), "remove_structure should succeed")
	assert(not BuildingStateScript.has_structure_at_tile(system.get_state(), tile), "removed structure should be absent")
	projection.apply_events(remove_result.get(BuildingSystem.RESULT_KEY_EVENTS, []))
	assert(port.calls.size() >= 2, "projection refresh should be triggered by remove events")


func _test_rebuild_and_apply_projection(
		system: BuildingSystem,
		projection: BuildingColliderRefreshProjection,
		port: FakeProjectionRefreshPort,
		chunk: Vector2i
	) -> void:
	var tile := Vector2i(15, 15)
	var place_cmd: Dictionary = BuildingCommandsScript.place_structure(
		"rebuild_case",
		tile,
		6,
		BuildingStateScript.create_player_wall_metadata(true, "wallwood", 1)
	)
	place_cmd["chunk_pos"] = chunk
	place_cmd["kind"] = "player_wall"
	var place_result: Dictionary = system.process(place_cmd)
	assert(bool(place_result.get(BuildingSystem.RESULT_KEY_SUCCESS, false)), "rebuild case placement should succeed")

	var rebuilt_state: Dictionary = BuildingStateScript.create_empty()
	for structure in BuildingStateScript.get_structures_by_id(system.get_state()).values():
		if typeof(structure) != TYPE_DICTIONARY:
			continue
		BuildingStateScript.upsert_structure(rebuilt_state, structure as Dictionary)

	var structures_in_chunk: Array[Dictionary] = BuildingStateScript.get_structures_in_chunk(rebuilt_state, chunk)
	assert(structures_in_chunk.size() > 0, "rebuilt state should contain structures for the target chunk")

	var projection_change_set: Array[Dictionary] = []
	for structure in structures_in_chunk:
		projection_change_set.append({
			"action": "placed",
			"before": {},
			"after": structure,
		})
	projection.apply_change_set(projection_change_set)
	assert(port.calls.size() >= 3, "projection should accept rebuilt-state change-set")
	assert(_scope_has_tile(port.calls[port.calls.size() - 1], tile), "rebuilt projection scope should include rebuilt tile")


func _scope_has_tile(scope_tiles: Array, needle: Vector2i) -> bool:
	for cell in scope_tiles:
		if cell is Vector2i and (cell as Vector2i) == needle:
			return true
	return false


func _init() -> void:
	run()
