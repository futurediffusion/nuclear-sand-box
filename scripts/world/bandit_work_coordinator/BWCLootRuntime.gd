extends RefCounted
class_name BWCLootRuntime

const RAID_LOOT_RANGE_SQ: float = 76.0 * 76.0
const CONTAINER_QUERY_TTL_SEC: float = 0.15

var _cached_query_key: String = ""
var _cached_query_at_msec: int = 0
var _cached_query_nodes: Array[WeakRef] = []


func try_loot_nearby_container(stash: BanditCampStashSystem, beh: BanditWorldBehavior,
		enemy_pos: Vector2, assault_anchor: Vector2, world_spatial_index: WorldSpatialIndex) -> Dictionary:
	if stash == null or beh == null:
		return {"looted": false, "nodes_inspected": 0}
	if beh.is_cargo_full():
		return {"looted": false, "nodes_inspected": 0}

	var nearby_containers: Array = _query_nearby_containers(enemy_pos, assault_anchor, world_spatial_index)
	var nodes_inspected: int = nearby_containers.size()
	var container: ContainerPlaceable = BanditRaidRuntimePolicy.find_nearest_raidable_container(
		enemy_pos,
		assault_anchor,
		null,
		nearby_containers
	)
	if container == null:
		return {"looted": false, "nodes_inspected": nodes_inspected}

	var chest_pos: Vector2 = container.global_position
	if enemy_pos.distance_squared_to(chest_pos) > RAID_LOOT_RANGE_SQ:
		return {"looted": false, "nodes_inspected": nodes_inspected}

	var capacity_left: int = maxi(0, beh.cargo_capacity - beh.cargo_count)
	if capacity_left <= 0:
		return {"looted": false, "nodes_inspected": nodes_inspected}

	var extracted: Array[Dictionary] = container.extract_items_for_raid(capacity_left)
	if extracted.is_empty():
		return {"looted": false, "nodes_inspected": nodes_inspected}

	var cargo_result: Dictionary = stash.collect_entries_canonical(beh, extracted, "raid_container")
	var added: int = int(cargo_result.get("added", 0))
	_restore_leftovers(container, cargo_result.get("leftovers", []) as Array)

	if added <= 0:
		_restore_leftovers(container, extracted)
		return {"looted": false, "nodes_inspected": nodes_inspected}

	return {
		"looted": true,
		"container": container,
		"added": added,
		"taken": cargo_result.get("taken", []) as Array,
		"nodes_inspected": nodes_inspected,
	}


func _query_nearby_containers(enemy_pos: Vector2, assault_anchor: Vector2, world_spatial_index: WorldSpatialIndex) -> Array:
	if world_spatial_index == null:
		return []
	var query_key: String = _build_query_key(enemy_pos, assault_anchor)
	var now_msec: int = Time.get_ticks_msec()
	if query_key == _cached_query_key:
		var age_sec: float = float(now_msec - _cached_query_at_msec) / 1000.0
		if age_sec <= CONTAINER_QUERY_TTL_SEC:
			var cached_live: Array = _collect_live_cached_nodes()
			if not cached_live.is_empty():
				return cached_live
	var live_nodes: Array = _query_spatial_storage_nodes(enemy_pos, assault_anchor, world_spatial_index)
	_cached_query_key = query_key
	_cached_query_at_msec = now_msec
	_cached_query_nodes = _to_weak_refs(live_nodes)
	return live_nodes


func _query_spatial_storage_nodes(enemy_pos: Vector2, assault_anchor: Vector2, world_spatial_index: WorldSpatialIndex) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	var centers: Array[Vector2] = [assault_anchor]
	if enemy_pos.distance_squared_to(assault_anchor) > 1.0:
		centers.append(enemy_pos)
	for center in centers:
		if not BanditWallAssaultPolicy.is_valid_target(center):
			continue
		var nearby: Array = world_spatial_index.get_runtime_nodes_near(
			WorldSpatialIndex.KIND_STORAGE,
			center,
			BanditRaidRuntimePolicy.RAID_TARGET_SEARCH_RADIUS
		)
		for raw in nearby:
			var container := raw as ContainerPlaceable
			if container == null or not is_instance_valid(container) or container.is_queued_for_deletion():
				continue
			var iid: int = container.get_instance_id()
			if seen.has(iid):
				continue
			seen[iid] = true
			out.append(container)
	return out


func _collect_live_cached_nodes() -> Array:
	var out: Array = []
	for ref_obj in _cached_query_nodes:
		if not (ref_obj is WeakRef):
			continue
		var node: Node = (ref_obj as WeakRef).get_ref()
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		out.append(node)
	return out


func _to_weak_refs(nodes: Array) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		refs.append(weakref(node))
	return refs


func _build_query_key(enemy_pos: Vector2, assault_anchor: Vector2) -> String:
	return "%d:%d|%d:%d" % [
		int(round(enemy_pos.x)),
		int(round(enemy_pos.y)),
		int(round(assault_anchor.x)),
		int(round(assault_anchor.y)),
	]


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
