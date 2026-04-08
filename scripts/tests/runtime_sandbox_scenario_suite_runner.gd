extends SceneTree

const RuntimeSandboxScenarioFrameworkScript := preload("res://scripts/tests/runtime_sandbox_scenario_framework.gd")
const BanditIntentSystemScript := preload("res://scripts/domain/factions/BanditIntentSystem.gd")
const WorldSnapshot := preload("res://scripts/core/WorldSnapshot.gd")


func _init() -> void:
	run()


func run() -> void:
	print("[SANDBOX_SCENARIOS] Running unified runtime sandbox scenario suite...")
	var framework: RuntimeSandboxScenarioFramework = RuntimeSandboxScenarioFrameworkScript.new()
	framework.add_scenario(
		"build_damage_destroy_save_load_projection_rebuild",
		"Build structures/placeables, damage and destroy, then verify save/load + projection rebuild respects canonical destruction",
		Callable(self, "_scenario_build_damage_destroy_save_load_projection_rebuild")
	)
	framework.add_scenario(
		"raid_assault_active_save_load_resume",
		"Persist active raid/assault canonical state through save/load and validate canonical intent behavior resumes",
		Callable(self, "_scenario_raid_assault_active_save_load_resume")
	)
	framework.add_scenario(
		"chunk_window_shift_with_structures_placeables",
		"Shift chunk windows across neighboring chunks while structures/placeables persist through save/load",
		Callable(self, "_scenario_chunk_window_shift_with_structures_placeables")
	)
	framework.add_scenario(
		"long_session_repeated_save_load_cycles",
		"Run a deterministic long-session loop with repeated save/load cycles and cumulative canonical state",
		Callable(self, "_scenario_long_session_repeated_save_load_cycles")
	)
	framework.add_scenario(
		"projection_rebuild_consistency_after_snapshot_restore",
		"Rebuild projection repeatedly after canonical snapshot restoration and verify deterministic consistency",
		Callable(self, "_scenario_projection_rebuild_consistency_after_snapshot_restore")
	)
	var report: Dictionary = framework.run_all()
	print("[SANDBOX_SCENARIOS] PASS count=%d ids=%s" % [
		int(report.get("scenario_count", 0)),
		String(report.get("scenario_ids", [])),
	])
	quit(0)


func _scenario_build_damage_destroy_save_load_projection_rebuild(ctx: RuntimeSandboxScenarioFramework.ScenarioContext) -> void:
	ctx.upsert_chunk(0, 0, {}, {"scenario": "build_damage_destroy"})
	ctx.upsert_player_wall(0, 0, Vector2i(4, 4), 90)
	ctx.upsert_placeable("scenario:build:workbench", "workbench", Vector2i(5, 4))
	ctx.upsert_placeable("scenario:build:barrel", "barrel", Vector2i(6, 4))

	var hp_after_damage: int = ctx.apply_wall_damage(0, 0, Vector2i(4, 4), 35)
	assert(hp_after_damage == 55, "wall damage should reduce hp deterministically before destroy")
	ctx.apply_wall_damage(0, 0, Vector2i(4, 4), 100)
	assert(not WorldSave.has_player_wall(0, 0, Vector2i(4, 4)),
		"wall should be removed after destroy damage drives hp to zero")
	WorldSave.remove_placed_entity("scenario:build:barrel")
	assert(WorldSave.find_placed_entity("scenario:build:barrel").is_empty(),
		"destroyed placeable should be absent from canonical state before save")

	ctx.save_load_roundtrip({
		"seed": 501,
		"player_pos": Vector2(22.0, 14.0),
		"run_clock": {"seconds": 420},
	})
	assert(not WorldSave.has_player_wall(0, 0, Vector2i(4, 4)),
		"destroyed wall must stay absent after save/load")
	var projection: SpatialIndexProjection = ctx.rebuild_projection("destroyed_assets")
	var workbenches: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
	var barrels: Array[Dictionary] = projection.get_all_placeables_by_item_id("barrel")
	assert(workbenches.size() == 1, "remaining placeable should survive save/load and projection rebuild")
	assert(barrels.is_empty(), "destroyed placeable should not reappear in projection after rebuild")


func _scenario_raid_assault_active_save_load_resume(ctx: RuntimeSandboxScenarioFramework.ScenarioContext) -> void:
	ctx.upsert_chunk(2, 1, {"bandit_group": {"members": ["b1", "b2"]}}, {})
	ctx.upsert_player_wall(2, 1, Vector2i(66, 39), 70)
	ctx.upsert_placeable("scenario:raid:target", "workbench", Vector2i(66, 39))
	WorldSave.global_flags["raid_assault_active"] = true

	var roundtrip: Dictionary = ctx.save_load_roundtrip({
		"seed": 90210,
		"bandit_group_memory": {
			"groups": {
				"g-raid": {
					"current_group_intent": "raiding",
					"assault_target": {"tile": Vector2i(66, 39), "kind": "structure"},
				}
			}
		},
		"extortion_queue": [{"group_id": "g-raid", "status": "active"}],
	})
	assert(bool(WorldSave.global_flags.get("raid_assault_active", false)),
		"active raid flag should persist across save/load")
	var restored_raw: Variant = roundtrip.get("restored", null)
	assert(restored_raw is WorldSnapshot, "save/load roundtrip should return a typed WorldSnapshot")
	var restored: WorldSnapshot = restored_raw as WorldSnapshot
	var bandit_memory: Dictionary = restored.bandit_group_memory
	var raid_group: Dictionary = (bandit_memory.get("groups", {}) as Dictionary).get("g-raid", {}) as Dictionary
	assert(String(raid_group.get("current_group_intent", "")) == "raiding",
		"raid canonical mode should restore after save/load")

	var intent_system: BanditIntentSystem = BanditIntentSystemScript.new()
	intent_system.setup()
	var decision: Dictionary = intent_system.decide_group_intent(
		{
			"threat_signals": {"threat_detected": false},
			"has_assault_target": true,
			"nearby_loot_count": 0,
			"nearby_resource_count": 0,
		},
		{"current_group_intent": "raiding", "has_placement_react_lock": false},
		{"policy_next_intent": "raiding", "reason": "scenario_resume", "source": "runtime_scenario_suite"}
	)
	assert(String(decision.get("decision_type", "")) == BanditIntentSystemScript.DECISION_STRUCTURE_ASSAULT,
		"restored raid state should resume canonical structure assault intent behavior")


func _scenario_chunk_window_shift_with_structures_placeables(ctx: RuntimeSandboxScenarioFramework.ScenarioContext) -> void:
	var windows: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(0, 1),
	]
	for i in range(windows.size()):
		var window_chunk: Vector2i = windows[i]
		var chunk_key: String = ctx.upsert_chunk(window_chunk.x, window_chunk.y, {"window_step": i}, {"active_window": true})
		var base_tile: Vector2i = Vector2i(window_chunk.x * 32 + 3, window_chunk.y * 32 + 5)
		ctx.upsert_player_wall(window_chunk.x, window_chunk.y, base_tile, 100 - (i * 7))
		ctx.upsert_placeable("scenario:window:%d" % i, "workbench", base_tile + Vector2i(1, 0), chunk_key)

		ctx.save_load_roundtrip({
			"seed": 1000 + i,
			"player_pos": Vector2(window_chunk.x * 32, window_chunk.y * 32),
			"run_clock": {"seconds": i * 60},
		})
		var projection: SpatialIndexProjection = ctx.rebuild_projection("window_step_%d" % i)
		var benches: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
		assert(benches.size() == i + 1,
			"window step %d should retain all prior placeables across chunk shifts" % i)
		assert(WorldSave.player_walls_by_chunk.size() == i + 1,
			"window step %d should retain all prior player wall chunks" % i)


func _scenario_long_session_repeated_save_load_cycles(ctx: RuntimeSandboxScenarioFramework.ScenarioContext) -> void:
	ctx.upsert_chunk(0, 0, {"session": "long"}, {})
	ctx.upsert_placeable("scenario:session:seed", "campfire", Vector2i(8, 8))
	var total_cycles: int = 14
	for cycle in range(total_cycles):
		var cx: int = cycle % 4
		var cy: int = int(cycle / 4)
		ctx.upsert_chunk(cx, cy, {"cycle": cycle}, {"visited": true})
		ctx.upsert_placeable("scenario:session:%d" % cycle, "workbench", Vector2i(cx * 32 + 2, cy * 32 + 3))
		ctx.upsert_player_wall(cx, cy, Vector2i(cx * 32 + 4, cy * 32 + 4), 60 + cycle)
		ctx.save_load_roundtrip({
			"seed": 77,
			"player_pos": Vector2(cx * 32 + 1, cy * 32 + 1),
			"run_clock": {"seconds": cycle * 45},
			"world_time": {"minutes": cycle * 2},
		})
		var projection: SpatialIndexProjection = ctx.rebuild_projection("long_cycle_%d" % cycle)
		var benches: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
		assert(benches.size() == cycle + 1,
			"cycle %d should keep monotonic placeable growth through repeated save/load" % cycle)
		assert(WorldSave.player_walls_by_chunk.size() >= 1,
			"cycle %d should preserve at least one player wall chunk" % cycle)

	var campfires: Array[Dictionary] = ctx.rebuild_projection("long_session_final").get_all_placeables_by_item_id("campfire")
	assert(campfires.size() == 1, "baseline placeable should survive full long-session save/load sequence")


func _scenario_projection_rebuild_consistency_after_snapshot_restore(ctx: RuntimeSandboxScenarioFramework.ScenarioContext) -> void:
	var chunk_a: String = ctx.upsert_chunk(0, 0, {"tag": "a"}, {})
	var chunk_b: String = ctx.upsert_chunk(1, 0, {"tag": "b"}, {})
	ctx.upsert_placeable("scenario:projection:a1", "workbench", Vector2i(4, 4), chunk_a)
	ctx.upsert_placeable("scenario:projection:a2", "workbench", Vector2i(6, 4), chunk_a)
	ctx.upsert_placeable("scenario:projection:b1", "workbench", Vector2i(36, 3), chunk_b)
	ctx.upsert_placeable("scenario:projection:torch", "campfire", Vector2i(37, 3), chunk_b)
	ctx.upsert_player_wall(0, 0, Vector2i(4, 3), 80)
	ctx.upsert_player_wall(1, 0, Vector2i(36, 2), 85)

	ctx.save_load_roundtrip({
		"seed": 2026,
		"player_pos": Vector2(18.0, 10.0),
		"run_clock": {"seconds": 999},
	})
	var baseline_projection: SpatialIndexProjection = ctx.rebuild_projection("baseline_after_restore")
	var baseline_ids: Array[String] = _uids_from_entries(
		baseline_projection.get_all_placeables_by_item_id("workbench")
	)
	assert(baseline_ids.size() == 3, "baseline restored projection should expose expected workbench count")

	for i in range(18):
		var projection: SpatialIndexProjection = ctx.rebuild_projection("consistency_%d" % i)
		var ids: Array[String] = _uids_from_entries(projection.get_all_placeables_by_item_id("workbench"))
		assert(ids == baseline_ids,
			"projection rebuild iteration %d should match baseline uid ordering/content" % i)


func _uids_from_entries(entries: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for entry in entries:
		ids.append(String(entry.get("uid", "")))
	ids.sort()
	return ids
