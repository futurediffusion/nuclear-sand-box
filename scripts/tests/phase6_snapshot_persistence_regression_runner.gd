extends SceneTree

const ChunkSnapshotSerializer := preload("res://scripts/persistence/save/ChunkSnapshotSerializer.gd")
const WorldSaveAdapter := preload("res://scripts/persistence/save/WorldSaveAdapter.gd")
const WorldSnapshotSerializer := preload("res://scripts/persistence/save/WorldSnapshotSerializer.gd")
const SpatialIndexProjectionScript := preload("res://scripts/projections/index/SpatialIndexProjection.gd")


func _init() -> void:
	run()


func run() -> void:
	print("[PHASE6] Running snapshot persistence regression harness...")
	_reset_worldsave_state()
	_seed_canonical_worldsave_state()
	_test_snapshot_construction_from_canonical_state()
	_test_world_snapshot_serialization_roundtrip()
	_test_load_reconstruction_into_canonical_state()
	_test_post_load_projection_rebuild()
	_test_runtime_projection_cannot_become_save_truth()
	print("[PHASE6] PASS: snapshot persistence closure regressions are stable")
	quit(0)


func _test_snapshot_construction_from_canonical_state() -> void:
	var canonical_state := {
		"save_version": 1,
		"seed": 777,
		"player_pos": Vector2(128.0, 64.0),
		"player_inv": [{"item_id": "wood", "count": 3}],
		"player_gold": 25,
		"run_clock": {"seconds": 120},
		"world_time": {"minutes": 30},
		"faction_system": {"v": 1},
		"site_system": {"v": 2},
		"npc_profile_system": {"v": 3},
		"bandit_group_memory": {"v": 4},
		"extortion_queue": [],
		"faction_hostility": {"v": 5},
	}
	var snapshot = WorldSaveAdapter.build_world_snapshot(canonical_state)
	assert(int(snapshot.world_seed) == 777, "world snapshot should keep canonical seed")
	assert(int(snapshot.chunks.size()) == 1, "world snapshot should include canonical chunk snapshots")
	assert(int(snapshot.chunks[0].structures.size()) == 1, "chunk snapshot should include canonical structures from walls")
	assert(int(snapshot.chunks[0].placed_entities.size()) == 1, "chunk snapshot should include canonical placeables")


func _test_world_snapshot_serialization_roundtrip() -> void:
	var snapshot = WorldSaveAdapter.build_world_snapshot({
		"save_version": 1,
		"seed": 123,
		"player_pos": Vector2(10.0, 20.0),
		"player_inv": [{"item_id": "copper", "count": 2}],
		"player_gold": 99,
	})
	var payload: Dictionary = WorldSnapshotSerializer.serialize(snapshot)
	var restored = WorldSnapshotSerializer.deserialize(payload)
	assert(int(restored.seed) == 123, "serializer roundtrip should preserve snapshot seed")
	assert((restored.player_pos as Vector2).is_equal_approx(Vector2(10.0, 20.0)),
		"serializer roundtrip should preserve player position")
	assert(int(restored.chunks.size()) == int(snapshot.chunks.size()),
		"serializer roundtrip should preserve chunk snapshot count")


func _test_load_reconstruction_into_canonical_state() -> void:
	var snapshot = WorldSaveAdapter.build_world_snapshot({
		"save_version": 1,
		"seed": 321,
		"player_pos": Vector2(32.0, 32.0),
	})
	_reset_worldsave_state()
	var applied: bool = WorldSaveAdapter.apply_world_snapshot(snapshot)
	assert(applied, "world snapshot should restore canonical owners")

	var chunk_key: String = WorldSave.chunk_key(0, 0)
	assert(WorldSave.chunks.has(chunk_key), "snapshot load should reconstruct WorldSave chunk map")
	assert(WorldSave.player_walls_by_chunk.has(chunk_key), "snapshot load should reconstruct canonical player walls")
	assert(WorldSave.placed_entities_by_chunk.has(chunk_key), "snapshot load should reconstruct canonical placeables")
	assert(WorldSave.placed_entity_data_by_uid.has("phase6:barrel"),
		"snapshot load should restore canonical per-uid placeable data")


func _test_post_load_projection_rebuild() -> void:
	var projection: SpatialIndexProjection = SpatialIndexProjectionScript.new()
	projection.setup({"chunk_size": 32})
	projection.rebuild_from_source("phase6_post_load_rebuild")
	var workbenches: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
	assert(workbenches.size() == 1, "projection rebuild should derive state from canonical placeables after load")


func _test_runtime_projection_cannot_become_save_truth() -> void:
	var projection: SpatialIndexProjection = SpatialIndexProjectionScript.new()
	projection.setup({"chunk_size": 32})
	projection.rebuild_from_source("phase6_runtime_mutation")
	var projection_entries: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
	assert(projection_entries.size() == 1, "projection should start from canonical placeables")
	projection_entries[0]["item_id"] = "tampered_runtime_only"
	projection.rebuild_from_source("phase6_runtime_mutation_rebuild")

	var canonical_entry: Dictionary = WorldSave.find_placed_entity("phase6:workbench")
	assert(String(canonical_entry.get("item_id", "")) == "workbench",
		"runtime projection mutation must not become canonical save truth")
	var chunk_snapshot = ChunkSnapshotSerializer.serialize_chunk_from_worldsave(WorldSave.chunk_key(0, 0))
	assert(int(chunk_snapshot.placed_entities.size()) == 1,
		"canonical snapshot source should only contain canonical placeables")


func _seed_canonical_worldsave_state() -> void:
	var chunk_key: String = WorldSave.chunk_key(0, 0)
	WorldSave.chunks[chunk_key] = {
		"entities": {"enemy:1": {"hp": 12}},
		"flags": {"visited": true},
	}
	WorldSave.enemy_state_by_chunk[chunk_key] = {
		"enemy:1": {"hp": 12, "state": "idle"},
	}
	WorldSave.enemy_spawns_by_chunk[chunk_key] = [{
		"uid": "enemy:spawn:1",
		"scene": "res://scenes/enemy.tscn",
		"tile": Vector2i(3, 3),
	}]
	WorldSave.global_flags = {"phase6_seeded": true}
	WorldSave.set_player_wall(0, 0, Vector2i(8, 9), 45)

	WorldSave.add_placed_entity({
		"uid": "phase6:workbench",
		"item_id": "workbench",
		"tile_pos_x": 6,
		"tile_pos_y": 6,
		"chunk_key": chunk_key,
	})
	WorldSave.add_placed_entity({
		"uid": "phase6:barrel",
		"item_id": "barrel",
		"tile_pos_x": 7,
		"tile_pos_y": 6,
		"chunk_key": chunk_key,
	})
	WorldSave.set_placed_entity_data("phase6:barrel", {"slots": [{"item_id": "copper", "count": 4}]})


func _reset_worldsave_state() -> void:
	WorldSave.chunks.clear()
	WorldSave.enemy_state_by_chunk.clear()
	WorldSave.enemy_spawns_by_chunk.clear()
	WorldSave.global_flags.clear()
	WorldSave.player_walls_by_chunk.clear()
	WorldSave.clear_placed_entities()
	WorldSave.placed_entity_data_by_uid.clear()
