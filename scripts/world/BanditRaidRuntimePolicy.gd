extends RefCounted
class_name BanditRaidRuntimePolicy

## Domain policy for raid runtime decisions consumed by BanditWorkCoordinator.
## Keeps semantic choices out of the coordinator so it can stay orchestration-only.

const RAID_TARGET_SEARCH_RADIUS: float = 180.0


static func should_retreat_on_attack_deny(reason: String) -> bool:
	match reason:
		"canonical_target_missing", "no_attack_target", "invalid_target", "out_of_engage_radius", "raid_context_lost", "no_raid_context":
			return true
		_:
			return false


static func should_retreat_on_loot_deny(reason: String) -> bool:
	match reason:
		"loot_out_of_range", "invalid_loot_anchor", "raid_context_lost", "no_raid_context":
			return true
		_:
			return false


static func find_nearest_raidable_container(enemy_pos: Vector2, assault_anchor: Vector2,
		world_spatial_index: WorldSpatialIndex, runtime_interactables: Array) -> ContainerPlaceable:
	var best: ContainerPlaceable = null
	var best_dsq: float = INF
	var search_centers: Array[Vector2] = [assault_anchor]
	if enemy_pos.distance_squared_to(assault_anchor) > 1.0:
		search_centers.append(enemy_pos)

	# Canonical runtime truth: live interactable nodes in scene tree.
	# Spatial index is derived and may lag, so it can only add candidates.
	var candidates: Array = runtime_interactables.duplicate()
	if world_spatial_index != null:
		for center in search_centers:
			if not BanditWallAssaultPolicy.is_valid_target(center):
				continue
			candidates.append_array(world_spatial_index.get_runtime_nodes_near(
				WorldSpatialIndex.KIND_STORAGE,
				center,
				RAID_TARGET_SEARCH_RADIUS
			))

	var seen_containers: Dictionary = {}
	for raw_node in candidates:
		var container := raw_node as ContainerPlaceable
		if container == null:
			continue
		var iid: int = container.get_instance_id()
		if seen_containers.has(iid):
			continue
		seen_containers[iid] = true
		if not is_valid_raid_container(container):
			continue
		var near_any_center: bool = false
		for center in search_centers:
			if not BanditWallAssaultPolicy.is_valid_target(center):
				continue
			if container.global_position.distance_squared_to(center) <= RAID_TARGET_SEARCH_RADIUS * RAID_TARGET_SEARCH_RADIUS:
				near_any_center = true
				break
		if not near_any_center:
			continue
		var dsq: float = enemy_pos.distance_squared_to(container.global_position)
		if dsq < best_dsq:
			best_dsq = dsq
			best = container
	return best


static func is_valid_raid_container(container: ContainerPlaceable) -> bool:
	if container == null or not is_instance_valid(container) or container.is_queued_for_deletion():
		return false
	if not container.is_raid_lootable():
		return false
	if container.get_raid_loot_total_units() <= 0:
		return false
	return true
