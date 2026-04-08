extends SceneTree

const WorldSaveAdapter := preload("res://scripts/persistence/save/WorldSaveAdapter.gd")
const WorldSnapshotSerializer := preload("res://scripts/persistence/save/WorldSnapshotSerializer.gd")
const WorldSnapshot := preload("res://scripts/core/WorldSnapshot.gd")
const SpatialIndexProjectionScript := preload("res://scripts/projections/index/SpatialIndexProjection.gd")


func _init() -> void:
	run()


func run() -> void:
	print("[PHASE7] Running sandbox persistence durability/compat validation...")
	_reset_worldsave_state()
	_test_snapshot_versioning_and_migration_path()
	_test_repeated_save_load_cycles_with_window_changes()
	_test_projection_rebuild_consistency_long_session()
	print("[PHASE7] PASS: sandbox persistence durability validations are stable")
	quit(0)


func _test_snapshot_versioning_and_migration_path() -> void:
	var legacy_payload: Dictionary = {
		"snapshot_version": 1,
		"save_version": 2,
		"seed": 777,
		"player_pos": Vector2(10.0, 5.0),
		"chunks": [],
	}
	var report: Dictionary = WorldSnapshotSerializer.deserialize_with_report(legacy_payload)
	assert(bool(report.get("ok", false)), "legacy v1 payload should deserialize through versioning policy")
	assert(int(report.get("loaded_snapshot_version", 0)) == 1,
		"report should expose loaded snapshot version")
	var migration_path: Array = report.get("migration_path", [])
	assert(migration_path.size() == 1,
		"v1 payload should expose one explicit migration step to current version")


func _test_repeated_save_load_cycles_with_window_changes() -> void:
	_seed_base_world_state()
	var projection: SpatialIndexProjection = SpatialIndexProjectionScript.new()
	projection.setup({"chunk_size": 32})

	for cycle in range(0, 12):
		# Simulate changing loaded chunk windows over time by mutating canonical data
		# in neighboring chunks before every snapshot build.
		var chunk_x: int = cycle % 3
		var chunk_y: int = int(cycle / 3) % 2
		var chunk_key: String = WorldSave.chunk_key(chunk_x, chunk_y)
		WorldSave.chunks[chunk_key] = {
			"entities": {"cycle": cycle},
			"flags": {"visited": true},
		}
		WorldSave.set_player_wall(chunk_x, chunk_y, Vector2i(2 + cycle, 3), 40 + cycle)
		var uid: String = "phase7:bench:%d" % cycle
		WorldSave.add_placed_entity({
			"uid": uid,
			"item_id": "workbench",
			"tile_pos_x": chunk_x * 32 + 4,
			"tile_pos_y": chunk_y * 32 + 6,
			"chunk_key": chunk_key,
		})

		var snapshot = WorldSaveAdapter.build_world_snapshot({
			"save_version": 2,
			"seed": 999,
			"player_pos": Vector2(32.0, 32.0),
		})
		var payload: Dictionary = WorldSnapshotSerializer.serialize(snapshot)
		var decode_report: Dictionary = WorldSnapshotSerializer.deserialize_with_report(payload)
		assert(bool(decode_report.get("ok", false)), "serialized payload should deserialize in repeated cycles")
		var restored_raw: Variant = decode_report.get("snapshot", null)
		assert(restored_raw != null, "deserialize_with_report should return snapshot instance")
		assert(restored_raw is WorldSnapshot, "deserialize report should return typed WorldSnapshot")
		var restored: WorldSnapshot = restored_raw as WorldSnapshot

		_reset_worldsave_state()
		var applied: bool = WorldSaveAdapter.apply_world_snapshot(restored)
		assert(applied, "cycle %d should restore canonical world snapshot" % cycle)
		projection.rebuild_from_source("phase7_cycle_%d" % cycle)

		var expected_entries: int = cycle + 1
		var workbenches: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
		assert(workbenches.size() == expected_entries,
			"cycle %d should preserve all previous placeables across repeated save/load" % cycle)


func _test_projection_rebuild_consistency_long_session() -> void:
	var projection: SpatialIndexProjection = SpatialIndexProjectionScript.new()
	projection.setup({"chunk_size": 32})
	projection.rebuild_from_source("phase7_long_session_seed")
	var baseline: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")

	for i in range(0, 20):
		projection.rebuild_from_source("phase7_long_session_%d" % i)
		var current: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
		assert(current.size() == baseline.size(),
			"projection rebuild count should stay deterministic in long-session loop")

	var debug_snapshot: Dictionary = projection.get_debug_snapshot()
	assert(int(debug_snapshot.get("persistent_full_rebuild_calls", 0)) >= 21,
		"projection debug snapshot should expose rebuild count observability")


func _seed_base_world_state() -> void:
	var key := WorldSave.chunk_key(0, 0)
	WorldSave.chunks[key] = {
		"entities": {"seeded": true},
		"flags": {"visited": true},
	}
	WorldSave.set_player_wall(0, 0, Vector2i(1, 1), 42)
	WorldSave.add_placed_entity({
		"uid": "phase7:bench:seed",
		"item_id": "workbench",
		"tile_pos_x": 5,
		"tile_pos_y": 5,
		"chunk_key": key,
	})


func _reset_worldsave_state() -> void:
	WorldSave.chunks.clear()
	WorldSave.enemy_state_by_chunk.clear()
	WorldSave.enemy_spawns_by_chunk.clear()
	WorldSave.global_flags.clear()
	WorldSave.player_walls_by_chunk.clear()
	WorldSave.clear_placed_entities()
	WorldSave.placed_entity_data_by_uid.clear()
