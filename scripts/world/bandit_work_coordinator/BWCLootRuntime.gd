extends RefCounted
class_name BWCLootRuntime

const RAID_LOOT_RANGE_SQ: float = 76.0 * 76.0


func try_loot_nearby_container(stash: BanditCampStashSystem, beh: BanditWorldBehavior,
		enemy_pos: Vector2, assault_anchor: Vector2, world_spatial_index: WorldSpatialIndex, scene_tree: SceneTree) -> Dictionary:
	if stash == null or beh == null:
		return {"looted": false}
	if beh.is_cargo_full():
		return {"looted": false}

	var runtime_interactables: Array = []
	if scene_tree != null:
		runtime_interactables = scene_tree.get_nodes_in_group("interactable")
	var container: ContainerPlaceable = BanditRaidRuntimePolicy.find_nearest_raidable_container(
		enemy_pos,
		assault_anchor,
		world_spatial_index,
		runtime_interactables
	)
	if container == null:
		return {"looted": false}

	var chest_pos: Vector2 = container.global_position
	if enemy_pos.distance_squared_to(chest_pos) > RAID_LOOT_RANGE_SQ:
		return {"looted": false}

	var capacity_left: int = maxi(0, beh.cargo_capacity - beh.cargo_count)
	if capacity_left <= 0:
		return {"looted": false}

	var extracted: Array[Dictionary] = container.extract_items_for_raid(capacity_left)
	if extracted.is_empty():
		return {"looted": false}

	var cargo_result: Dictionary = stash.collect_entries_canonical(beh, extracted, "raid_container")
	var added: int = int(cargo_result.get("added", 0))
	_restore_leftovers(container, cargo_result.get("leftovers", []) as Array)

	if added <= 0:
		_restore_leftovers(container, extracted)
		return {"looted": false}

	return {
		"looted": true,
		"container": container,
		"added": added,
		"taken": cargo_result.get("taken", []) as Array,
	}


func format_loot_entries(entries: Array) -> String:
	if entries.is_empty():
		return "[]"
	var parts: Array[String] = []
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw as Dictionary
		parts.append("%s×%d" % [String(e.get("item_id", "")), int(e.get("amount", 0))])
	return "[" + ", ".join(parts) + "]"


func _restore_leftovers(container: ContainerPlaceable, entries: Array) -> void:
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw as Dictionary
		container.try_insert_item(String(e.get("item_id", "")), int(e.get("amount", 0)))
