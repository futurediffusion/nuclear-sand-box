extends RefCounted
class_name RuntimeSandboxScenarioFramework

const WorldSaveAdapter := preload("res://scripts/persistence/save/WorldSaveAdapter.gd")
const WorldSnapshotSerializer := preload("res://scripts/persistence/save/WorldSnapshotSerializer.gd")
const SpatialIndexProjectionScript := preload("res://scripts/projections/index/SpatialIndexProjection.gd")


class ScenarioContext extends RefCounted:
	var scenario_id: String = ""
	var _default_canonical_state: Dictionary = {
		"save_version": 2,
		"seed": 4242,
		"player_pos": Vector2(16.0, 16.0),
		"player_inv": [],
		"player_gold": 0,
		"run_clock": {"seconds": 0},
		"world_time": {"minutes": 0},
		"faction_system": {},
		"site_system": {},
		"npc_profile_system": {},
		"bandit_group_memory": {},
		"extortion_queue": [],
		"faction_hostility": {},
	}

	func reset_world_state() -> void:
		WorldSave.chunks.clear()
		WorldSave.enemy_state_by_chunk.clear()
		WorldSave.enemy_spawns_by_chunk.clear()
		WorldSave.global_flags.clear()
		WorldSave.player_walls_by_chunk.clear()
		WorldSave.clear_placed_entities()
		WorldSave.placed_entity_data_by_uid.clear()

	func save_load_roundtrip(overrides: Dictionary = {}) -> Dictionary:
		var canonical_state: Dictionary = _default_canonical_state.duplicate(true)
		for key in overrides.keys():
			canonical_state[key] = overrides[key]
		var snapshot = WorldSaveAdapter.build_world_snapshot(canonical_state)
		var payload: Dictionary = WorldSnapshotSerializer.serialize(snapshot)
		var restored = WorldSnapshotSerializer.deserialize(payload)
		reset_world_state()
		var applied: bool = WorldSaveAdapter.apply_world_snapshot(restored)
		assert(applied, "scenario %s should apply restored snapshot" % scenario_id)
		return {
			"canonical_state": canonical_state,
			"snapshot": snapshot,
			"payload": payload,
			"restored": restored,
		}

	func rebuild_projection(reason: String, chunk_size: int = 32) -> SpatialIndexProjection:
		var projection: SpatialIndexProjection = SpatialIndexProjectionScript.new()
		projection.setup({"chunk_size": chunk_size})
		projection.rebuild_from_source("%s:%s" % [scenario_id, reason])
		return projection

	func upsert_chunk(cx: int, cy: int, entities: Dictionary = {}, flags: Dictionary = {}) -> String:
		var key: String = WorldSave.chunk_key(cx, cy)
		WorldSave.chunks[key] = {
			"entities": entities.duplicate(true),
			"flags": flags.duplicate(true),
		}
		return key

	func upsert_player_wall(cx: int, cy: int, tile_pos: Vector2i, hp: int) -> void:
		WorldSave.set_player_wall(cx, cy, tile_pos, hp)

	func apply_wall_damage(cx: int, cy: int, tile_pos: Vector2i, damage: int) -> int:
		var wall: Dictionary = WorldSave.get_player_wall(cx, cy, tile_pos)
		var hp_before: int = int(wall.get("hp", 0))
		var hp_after: int = maxi(hp_before - damage, 0)
		WorldSave.set_player_wall(cx, cy, tile_pos, hp_after)
		return hp_after

	func upsert_placeable(uid: String, item_id: String, tile_pos: Vector2i, chunk_key: String = "") -> void:
		var resolved_chunk_key: String = chunk_key
		if resolved_chunk_key.is_empty():
			resolved_chunk_key = WorldSave.get_chunk_key_for_tile(tile_pos.x, tile_pos.y)
		WorldSave.add_placed_entity({
			"uid": uid,
			"item_id": item_id,
			"tile_pos_x": tile_pos.x,
			"tile_pos_y": tile_pos.y,
			"chunk_key": resolved_chunk_key,
		})


var _scenarios: Array[Dictionary] = []


func add_scenario(id: String, description: String, run_fn: Callable) -> void:
	assert(not id.is_empty(), "scenario id cannot be empty")
	assert(run_fn.is_valid(), "scenario runner callable should be valid")
	_scenarios.append({
		"id": id,
		"description": description,
		"run": run_fn,
	})


func run_all() -> Dictionary:
	assert(not _scenarios.is_empty(), "runtime scenario framework requires at least one scenario")
	var executed_ids: Array[String] = []
	for scenario in _scenarios:
		var id: String = String(scenario.get("id", ""))
		var description: String = String(scenario.get("description", ""))
		var run_fn: Callable = scenario.get("run", Callable()) as Callable
		assert(run_fn.is_valid(), "scenario %s is missing executable callback" % id)
		var ctx := ScenarioContext.new()
		ctx.scenario_id = id
		ctx.reset_world_state()
		print("[SCENARIO] START id=%s desc=%s" % [id, description])
		run_fn.call(ctx)
		executed_ids.append(id)
		print("[SCENARIO] PASS id=%s" % id)
	ctx.reset_world_state()
	return {
		"scenario_count": executed_ids.size(),
		"scenario_ids": executed_ids,
	}
