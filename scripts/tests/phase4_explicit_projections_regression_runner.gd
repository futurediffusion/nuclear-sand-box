extends SceneTree

const SpatialIndexProjectionScript := preload("res://scripts/projections/index/SpatialIndexProjection.gd")
const WallColliderProjectionScript := preload("res://scripts/projections/collision/WallColliderProjection.gd")
const TerritoryProjectionScript := preload("res://scripts/projections/territory/TerritoryProjection.gd")
const WorldProjectionRefreshContractScript := preload("res://scripts/world/contracts/WorldProjectionRefreshContract.gd")
const WorldChunkDirtyNotifierContractScript := preload("res://scripts/world/contracts/WorldChunkDirtyNotifierContract.gd")

class FakeProjectionRefreshPort extends WorldProjectionRefreshContractScript:
	var calls: Array[Array] = []

	func refresh_for_tiles(tile_positions: Array[Vector2i]) -> void:
		calls.append(tile_positions.duplicate())


class FakeChunkDirtyNotifierPort extends WorldChunkDirtyNotifierContractScript:
	var dirty_calls: Array[Vector2i] = []

	func mark_chunk_dirty(chunk_pos: Vector2i) -> void:
		dirty_calls.append(chunk_pos)


func _init() -> void:
	run()


func run() -> void:
	print("[PHASE4] Running explicit projections regression harness...")
	_reset_worldsave_placeables()
	_test_spatial_index_rebuild_and_resync()
	_test_wall_collider_projection_refresh_and_chunk_dirty_fallback()
	_test_territory_projection_rebuild_contract()
	print("[PHASE4] PASS: spatial/wall/territory projection contracts remain stable")
	quit(0)


func _test_spatial_index_rebuild_and_resync() -> void:
	var projection: SpatialIndexProjection = SpatialIndexProjectionScript.new()
	projection.setup({"chunk_size": 32})

	WorldSave.add_placed_entity(_make_placeable_entry("wb-1", "workbench", Vector2i(2, 2)))
	projection.ensure_synced()
	var initial_items: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
	assert(initial_items.size() == 1, "spatial projection should rebuild from canonical snapshot")

	# mutate canonical data without projection event feed; ensure sanity/resync keeps canonical truth
	WorldSave.add_placed_entity(_make_placeable_entry("wb-2", "workbench", Vector2i(5, 2)))
	projection.rebuild_from_source("phase4_test_manual")
	var rebuilt_items: Array[Dictionary] = projection.get_all_placeables_by_item_id("workbench")
	assert(rebuilt_items.size() == 2, "manual rebuild must sync projection with canonical placeables")

	# direct projection-side invalidation should never mutate canonical ownership
	projection.notify_placeables_changed("workbench", Vector2i(5, 2))
	projection.ensure_synced()
	assert(int(WorldSave.placed_entity_chunk_by_uid.size()) == 2,
		"projection invalidation must not act as canonical source-of-truth")
	var spatial_snapshot: Dictionary = projection.get_debug_snapshot()
	assert(String(spatial_snapshot.get("last_sync_reason", "")) != "",
		"spatial projection should expose sync observability snapshot")


func _test_wall_collider_projection_refresh_and_chunk_dirty_fallback() -> void:
	var refresh_port := FakeProjectionRefreshPort.new()
	var dirty_port := FakeChunkDirtyNotifierPort.new()
	var touched_base_scan_world_pos := Vector2.INF
	var territory_dirty_calls: int = 0
	var loaded_chunks := {Vector2i(0, 0): true}

	var projection: WallColliderProjection = WallColliderProjectionScript.new()
	projection.setup({
		"projection_refresh_port": refresh_port,
		"chunk_dirty_notifier_port": dirty_port,
		"loaded_chunks": loaded_chunks,
		"tile_to_chunk": func(tile: Vector2i) -> Vector2i: return Vector2i(int(floor(float(tile.x) / 32.0)), int(floor(float(tile.y) / 32.0))),
		"tile_to_world": func(tile: Vector2i) -> Vector2: return Vector2(float(tile.x) * 32.0, float(tile.y) * 32.0),
		"mark_base_scan_dirty_near": func(world_pos: Vector2) -> void: touched_base_scan_world_pos = world_pos,
		"mark_player_territory_dirty": func() -> void: territory_dirty_calls += 1,
		"wall_reconnect_offsets": [Vector2i.ZERO, Vector2i.RIGHT],
	})

	projection.apply_snapshot([{
		"kind": "player_wall",
		"tile_pos": Vector2i(10, 10),
		"metadata": {"is_player_wall": true},
	}])
	assert(refresh_port.calls.size() == 1, "wall projection should refresh scope for snapshot rebuild")
	assert(territory_dirty_calls == 1, "wall projection should dirty territory read model side-effects")
	assert(touched_base_scan_world_pos != Vector2.INF, "wall projection should mark settlement base scan dirty")
	var wall_snapshot: Dictionary = projection.get_debug_snapshot()
	assert(int(wall_snapshot.get("last_scope_tile_count", 0)) > 0,
		"wall projection should expose scope size observability")

	# fallback mode without projection refresh port still must produce chunk dirty invalidation
	var fallback_projection: WallColliderProjection = WallColliderProjectionScript.new()
	fallback_projection.setup({
		"chunk_dirty_notifier_port": dirty_port,
		"loaded_chunks": loaded_chunks,
		"tile_to_chunk": func(tile: Vector2i) -> Vector2i: return Vector2i(int(floor(float(tile.x) / 32.0)), int(floor(float(tile.y) / 32.0))),
		"wall_reconnect_offsets": [Vector2i.ZERO],
	})
	fallback_projection.apply_change_set([{
		"action": "placed",
		"before": {},
		"after": {
			"kind": "player_wall",
			"tile_pos": Vector2i(15, 15),
			"metadata": {"is_player_wall": true},
		}
	}])
	assert(dirty_port.dirty_calls.size() >= 1,
		"wall projection fallback should invalidate chunk colliders when refresh port is absent")
	var fallback_snapshot: Dictionary = fallback_projection.get_debug_snapshot()
	assert(bool(fallback_snapshot.get("uses_projection_refresh_port", true)) == false,
		"wall projection snapshot should report fallback wiring")


func _test_territory_projection_rebuild_contract() -> void:
	var territory: TerritoryProjection = TerritoryProjectionScript.new()
	var sources := {
		"workbench_nodes": [{"world_pos": Vector2(96.0, 96.0)}],
		"detected_bases": [{
			"id": "base-alpha",
			"center_world_pos": Vector2(320.0, 320.0),
			"bounds": Rect2i(8, 8, 3, 3),
		}],
	}
	territory.rebuild_from_sources(sources)
	assert(territory.zone_count() == 2, "territory projection should rebuild both workbench and enclosed zones")
	assert(territory.has_workbench_anchor(), "territory projection should include workbench zone from source snapshot")
	assert(territory.has_enclosed_base(), "territory projection should include enclosed base zone from source snapshot")

	# Ensure projection output is read-only and cannot become canonical owner by mutation.
	var zone_copy: Array[Dictionary] = territory.get_zones()
	zone_copy.clear()
	assert(territory.zone_count() == 2, "territory get_zones must return copies, not mutable canonical state")
	var territory_snapshot: Dictionary = territory.get_debug_snapshot()
	assert(int(territory_snapshot.get("rebuild_calls", 0)) >= 1,
		"territory projection should expose rebuild observability")


func _make_placeable_entry(uid: String, item_id: String, tile_pos: Vector2i) -> Dictionary:
	return {
		"uid": uid,
		"item_id": item_id,
		"tile_pos_x": tile_pos.x,
		"tile_pos_y": tile_pos.y,
		"chunk_key": WorldSave.get_chunk_key_for_tile(tile_pos.x, tile_pos.y),
	}


func _reset_worldsave_placeables() -> void:
	WorldSave.clear_placed_entities()
	WorldSave.placed_entity_data_by_uid.clear()
