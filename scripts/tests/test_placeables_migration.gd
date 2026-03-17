extends SceneTree

func run():
	print("--- Running Migration Tests for Placed Entities ---")

	# 1. Test Add/Remove and Consistency
	test_add_remove_consistency()

	# 2. Test Occupation Lookup
	test_occupation_lookup()

	# 3. Test Save Migration (Legacy to Chunk-based)
	test_save_migration()

	# 4. Test Door Neighborhood Lookup
	test_door_neighborhood()

	print("--- All Migration Tests Passed! ---")
	quit(0)

func test_add_remove_consistency():
	print("Testing Add/Remove Consistency...")
	WorldSave.clear_placed_entities()

	var entry = {
		"uid": "test_1",
		"item_id": "workbench",
		"scene": "res://scenes/placeables/workbench_world.tscn",
		"tile_pos_x": 10,
		"tile_pos_y": 20
	}

	WorldSave.add_placed_entity(entry)

	# Check if it was added to the correct chunk (10, 20) -> chunk (0, 0) assuming size 32
	var chunk_entities = WorldSave.get_placed_entities_in_chunk(0, 0)
	assert(chunk_entities.size() == 1, "Should have 1 entity in chunk 0,0")
	assert(chunk_entities[0]["uid"] == "test_1", "UID should match")
	assert(chunk_entities[0]["chunk_key"] == "0,0", "Chunk key should be auto-populated")

	assert(WorldSave.placed_entity_chunk_by_uid.has("test_1"), "Index should contain UID")
	assert(WorldSave.placed_entity_chunk_by_uid["test_1"] == "0,0", "Index should point to correct chunk")

	# Test Removal
	WorldSave.remove_placed_entity("test_1")
	assert(WorldSave.get_placed_entities_in_chunk(0, 0).is_empty(), "Chunk should be empty after removal")
	assert(not WorldSave.placed_entity_chunk_by_uid.has("test_1"), "Index should be cleaned up")

	print("SUCCESS: Add/Remove Consistency")

func test_occupation_lookup():
	print("Testing Occupation Lookup...")
	WorldSave.clear_placed_entities()

	WorldSave.add_placed_entity({
		"uid": "bench_1",
		"item_id": "workbench",
		"tile_pos_x": 5,
		"tile_pos_y": 5
	})

	assert(WorldSave.has_placed_entity_at_tile(0, 0, Vector2i(5, 5)), "Tile 5,5 should be occupied")
	assert(not WorldSave.has_placed_entity_at_tile(0, 0, Vector2i(6, 5)), "Tile 6,5 should be free")

	var entry = WorldSave.get_placed_entity_at_tile(0, 0, Vector2i(5, 5))
	assert(entry["uid"] == "bench_1", "Should return correct entry data")

	print("SUCCESS: Occupation Lookup")

func test_save_migration():
	print("Testing Save Migration via SaveManager...")
	WorldSave.clear_placed_entities()

	var save_path := "user://savegame.json"
	var backup_exists := FileAccess.file_exists(save_path)
	var backup_data: String = ""
	if backup_exists:
		var f := FileAccess.open(save_path, FileAccess.READ)
		backup_data = f.get_as_text()
		f.close()

	# 1. Create a legacy save file
	var legacy_data = {
		"version": 1,
		"seed": 12345,
		"placed_entities": [
			{"uid": "legacy_1", "item_id": "chest", "tile_pos_x": 40, "tile_pos_y": 10},
			{"uid": "legacy_2", "item_id": "door", "tile_pos_x": 5, "tile_pos_y": 5}
		]
	}

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_data))
	file.close()

	# 2. Trigger load via SaveManager
	var success = SaveManager.load_world_save()
	assert(success, "SaveManager should successfully load legacy save")

	# 3. Verify migration results in WorldSave
	# (40, 10) -> chunk (1, 0) assuming size 32
	# (5, 5) -> chunk (0, 0)
	assert(WorldSave.placed_entities_by_chunk.has("1,0"), "Chunk 1,0 should exist after migration")
	assert(WorldSave.placed_entities_by_chunk.has("0,0"), "Chunk 0,0 should exist after migration")

	var c1 = WorldSave.get_placed_entities_in_chunk(1, 0)
	assert(c1.size() == 1 and c1[0]["uid"] == "legacy_1", "legacy_1 should be migrated to chunk 1,0")

	var c0 = WorldSave.get_placed_entities_in_chunk(0, 0)
	assert(c0.size() == 1 and c0[0]["uid"] == "legacy_2", "legacy_2 should be migrated to chunk 0,0")

	assert(WorldSave.placed_entity_chunk_by_uid.get("legacy_1") == "1,0", "UID index should point to 1,0")
	assert(WorldSave.placed_entity_chunk_by_uid.get("legacy_2") == "0,0", "UID index should point to 0,0")

	# Cleanup / Restore backup
	if backup_exists:
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		f.store_string(backup_data)
		f.close()
	else:
		DirAccess.remove_absolute(save_path)

	print("SUCCESS: Save Migration via SaveManager")

func test_door_neighborhood():
	print("Testing Door Neighborhood Lookup...")
	WorldSave.clear_placed_entities()

	# Place doors in adjacent chunks
	# Chunk size 32
	# Door A: (31, 10) -> Chunk 0,0
	# Door B: (32, 10) -> Chunk 1,0

	WorldSave.add_placed_entity({
		"uid": "door_a",
		"item_id": "doorwood",
		"tile_pos_x": 31,
		"tile_pos_y": 10
	})

	WorldSave.add_placed_entity({
		"uid": "door_b",
		"item_id": "doorwood",
		"tile_pos_x": 32,
		"tile_pos_y": 10
	})

	# Test the neighborhood collector used by PlacementSystem
	var doors_near_a = PlacementSystem._collect_door_uid_in_chunk_neighborhood(Vector2i(0, 0))
	assert(doors_near_a.has("31,10"), "Should find door A")
	assert(doors_near_a.has("32,10"), "Should find door B in neighbor chunk")

	print("SUCCESS: Door Neighborhood Lookup")

func _init():
	run()
