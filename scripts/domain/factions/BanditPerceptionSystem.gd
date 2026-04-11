extends RefCounted
class_name BanditPerceptionSystem

const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")

var _world_spatial_index: WorldSpatialIndex = null
var _player: Node2D = null
var _find_wall_cb: Callable = Callable()
var _find_workbench_cb: Callable = Callable()
var _find_storage_cb: Callable = Callable()
var _find_placeable_cb: Callable = Callable()
var _log_worker_event_cb: Callable = Callable()
var _work_coordinator: Node = null
var _legacy_resource_sticky_fallback_uses: int = 0

const _WALL_CACHE_TTL: float = 2.5
const _ASSAULT_TARGET_CACHE_TTL: float = 2.5

var _group_wall_target_cache: Dictionary = {}
var _group_wall_target_expires: Dictionary = {}
var _group_workbench_target_cache: Dictionary = {}
var _group_workbench_target_expires: Dictionary = {}
var _group_storage_target_cache: Dictionary = {}
var _group_storage_target_expires: Dictionary = {}
var _group_placeable_target_cache: Dictionary = {}
var _group_placeable_target_expires: Dictionary = {}
var _wall_query_attempted: int = 0
var _wall_query_skipped: int = 0
var _wall_query_cache_hit: int = 0
var _wall_query_executed: int = 0


func setup(ctx: Dictionary) -> void:
	_world_spatial_index = ctx.get("world_spatial_index") as WorldSpatialIndex
	_player = ctx.get("player") as Node2D
	_find_wall_cb = ctx.get("find_nearest_player_wall", Callable()) as Callable
	_find_workbench_cb = ctx.get("find_nearest_player_workbench", Callable()) as Callable
	_find_storage_cb = ctx.get("find_nearest_player_storage", Callable()) as Callable
	_find_placeable_cb = ctx.get("find_nearest_player_placeable", Callable()) as Callable
	_log_worker_event_cb = ctx.get("log_worker_event_cb", Callable()) as Callable
	_work_coordinator = ctx.get("work_coordinator") as Node


func update_queries(ctx: Dictionary) -> void:
	_find_wall_cb = ctx.get("find_nearest_player_wall", _find_wall_cb) as Callable
	_find_workbench_cb = ctx.get("find_nearest_player_workbench", _find_workbench_cb) as Callable
	_find_storage_cb = ctx.get("find_nearest_player_storage", _find_storage_cb) as Callable
	_find_placeable_cb = ctx.get("find_nearest_player_placeable", _find_placeable_cb) as Callable


func fill_drops_info_buffer(node_pos: Vector2, out: Array[Dictionary],
		enough_threshold: int = 10, max_candidates_eval: int = 40) -> void:
	var r2: float = BanditTuningScript.loot_scan_radius_sq()
	var radius: float = sqrt(r2)
	if _world_spatial_index == null:
		out.clear()
		return
	var drops_source: Array = _world_spatial_index.get_runtime_nodes_near(
		WorldSpatialIndex.KIND_ITEM_DROP,
		node_pos,
		radius,
		{
			"intent": "idle",
			"stage": "drop_scan",
			"enough_threshold": enough_threshold,
			"max_candidates_eval": max_candidates_eval,
		}
	)
	var write_idx: int = 0
	for drop in drops_source:
		var drop_node := drop as Node2D
		if drop_node == null or not is_instance_valid(drop_node) \
				or drop_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(drop_node.global_position) > r2:
			continue
		var info: Dictionary
		if write_idx < out.size():
			info = out[write_idx]
			info.clear()
		else:
			info = {}
			out.append(info)
		info["id"] = drop_node.get_instance_id()
		info["pos"] = drop_node.global_position
		info["amount"] = int(drop_node.get("amount") if drop_node.get("amount") != null else 1)
		write_idx += 1
	if write_idx < out.size():
		out.resize(write_idx)


func fill_res_info_buffer(beh: BanditWorldBehavior, node_pos: Vector2,
		all_resources: Array, out: Array[Dictionary]) -> void:
	var r2: float = BanditTuningScript.resource_scan_radius_sq()
	var resources_source: Array = all_resources
	if _world_spatial_index != null:
		resources_source = _world_spatial_index.get_runtime_nodes_near(
			WorldSpatialIndex.KIND_WORLD_RESOURCE,
			node_pos,
			sqrt(r2),
			{
				"intent": "idle",
				"stage": "resource_scan",
				"enough_threshold": 14,
				"max_candidates_eval": 48,
			}
		)
	if BanditTuningScript.enable_worker_resource_fallback() and beh != null:
		var sticky_id: int = int(beh.last_valid_resource_node_id)
		var has_recent_hit: bool = (_work_coordinator != null) and _work_coordinator.has_method("has_recent_resource_hit") and _work_coordinator.call("has_recent_resource_hit", beh)
		if sticky_id != 0 and has_recent_hit:
			var sticky_node: Node2D = null
			if _world_spatial_index != null:
				sticky_node = _world_spatial_index.resolve_runtime_node_with_fallback(
					WorldSpatialIndex.KIND_WORLD_RESOURCE,
					sticky_id,
					{"expected_group": "world_resource"}
				)
			elif is_instance_id_valid(sticky_id):
				sticky_node = instance_from_id(sticky_id) as Node2D
			if sticky_node != null and is_instance_valid(sticky_node) and not sticky_node.is_queued_for_deletion():
				var already_present: bool = false
				for raw_existing in resources_source:
					if raw_existing == sticky_node:
						already_present = true
						break
				if not already_present:
					_register_legacy_bridge_usage(
						"bandit_perception.resource_sticky_fallback",
						"world resource scan injected sticky runtime node fallback."
					)
					resources_source.append(sticky_node)
					if _log_worker_event_cb.is_valid():
						_log_worker_event_cb.call("resource_fallback_applied", {
							"npc_id": beh.member_id,
							"group_id": beh.group_id,
							"camp_id": beh.group_id,
							"target_id": str(sticky_id),
							"state": str(int(beh.state)),
							"position_used": "%.2f,%.2f" % [node_pos.x, node_pos.y],
							"stage": "res_scan_recent_hit",
						})
	var write_idx: int = 0
	for res in resources_source:
		var res_node := res as Node2D
		if res_node == null or not is_instance_valid(res_node) \
				or res_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(res_node.global_position) > r2:
			continue
		var info: Dictionary
		if write_idx < out.size():
			info = out[write_idx]
			info.clear()
		else:
			info = {}
			out.append(info)
		info["pos"] = res_node.global_position
		info["id"] = res_node.get_instance_id()
		write_idx += 1
	if write_idx < out.size():
		out.resize(write_idx)


func prioritize_group_drops(anchor_pos: Vector2, drops: Array) -> Array:
	var scored: Array = []
	for raw in drops:
		if not (raw is Dictionary):
			continue
		var drop: Dictionary = raw as Dictionary
		var pos_raw: Variant = drop.get("pos", null)
		if not (pos_raw is Vector2):
			continue
		var pos: Vector2 = pos_raw as Vector2
		var amount: int = int(drop.get("amount", 1))
		var score: float = 1000.0 / maxf(anchor_pos.distance_to(pos), 32.0) + float(amount) * 0.5
		var out: Dictionary = drop.duplicate(true)
		out["priority_score"] = score
		scored.append(out)
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("priority_score", 0.0)) > float(b.get("priority_score", 0.0))
	)
	return scored


func prioritize_group_resources(anchor_pos: Vector2, resources: Array) -> Array:
	var scored: Array = []
	for raw in resources:
		if not (raw is Dictionary):
			continue
		var res: Dictionary = raw as Dictionary
		var pos_raw: Variant = res.get("pos", null)
		if not (pos_raw is Vector2):
			continue
		var pos: Vector2 = pos_raw as Vector2
		var score: float = 1000.0 / maxf(anchor_pos.distance_to(pos), 32.0)
		var out: Dictionary = res.duplicate(true)
		out["priority_score"] = score
		scored.append(out)
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("priority_score", 0.0)) > float(b.get("priority_score", 0.0))
	)
	return scored


func build_member_context(input: Dictionary) -> Dictionary:
	var node_pos: Vector2 = input.get("node_pos", Vector2.ZERO) as Vector2
	var drops_info: Array = input.get("nearby_drops_info", []) as Array
	var res_info: Array = input.get("nearby_res_info", []) as Array
	var in_combat: bool = bool(input.get("in_combat", false))
	var recently_engaged: bool = bool(input.get("recently_engaged", false))
	var simulation_profile: String = String(input.get("simulation_profile", "full"))
	var wall_query_allowed: bool = bool(input.get("wall_query_allowed", false))
	var group_id: String = String(input.get("group_id", ""))
	var player_presence: Dictionary = _build_player_presence(node_pos)
	var assault_targets: Dictionary = _build_assault_targets(node_pos, wall_query_allowed, group_id)
	var threat_signals: Dictionary = {
		"in_combat": in_combat,
		"recently_engaged": recently_engaged,
		"nearby_threats_count": int(input.get("nearby_threats_count", 0)),
		"threat_detected": in_combat or recently_engaged,
	}
	var combat_signals: Dictionary = {
		"in_combat": in_combat,
		"recently_engaged": recently_engaged,
	}
	return {
		"node_pos": node_pos,
		"nearby_drops_info": drops_info,
		"nearby_res_info": res_info,
		"find_nearest_player_wall": _find_wall_cb,
		"find_nearest_player_workbench": _find_workbench_cb,
		"find_nearest_player_storage": _find_storage_cb,
		"find_nearest_player_placeable": _find_placeable_cb,
		"in_combat": in_combat,
		"recently_engaged": recently_engaged,
		"simulation_profile": simulation_profile,
		"perception": {
			"threat_signals": threat_signals,
			"player_presence": player_presence,
			"nearby_loot": drops_info,
			"nearby_resources": res_info,
			"assault_targets": assault_targets,
			"combat_signals": combat_signals,
		},
	}


func build_group_intent_perception(input: Dictionary) -> Dictionary:
	var members: Array = input.get("members", []) as Array
	var threat_count: int = 0
	var recently_engaged_count: int = 0
	for raw_member in members:
		if not (raw_member is Dictionary):
			continue
		var member: Dictionary = raw_member as Dictionary
		if bool(member.get("in_combat", false)):
			threat_count += 1
		if bool(member.get("recently_engaged", false)):
			recently_engaged_count += 1
	var nearby_loot: Array = input.get("prioritized_drops", []) as Array
	var nearby_resources: Array = input.get("prioritized_resources", []) as Array
	var structure_assault_active: bool = bool(input.get("structure_assault_active", false))
	var has_assault_target: bool = bool(input.get("has_assault_target", structure_assault_active))
	var group_id: String = String(input.get("group_id", ""))
	return {
		"group_id": group_id,
		"stage": "perception",
		"threat_signals": {
			"in_combat_member_count": threat_count,
			"recently_engaged_member_count": recently_engaged_count,
			"threat_detected": threat_count > 0 or recently_engaged_count > 0,
		},
		"nearby_loot_count": nearby_loot.size(),
		"nearby_resource_count": nearby_resources.size(),
		"has_assault_target": has_assault_target,
		"structure_assault_active": structure_assault_active,
		"trace": {
			"path": "BanditPerceptionSystem.build_group_intent_perception",
			"compatibility_bridge": "group_blackboard_perception_deprecated",
		},
	}

func get_debug_snapshot() -> Dictionary:
	return {
		"legacy_resource_sticky_fallback_uses": _legacy_resource_sticky_fallback_uses,
		"wall_query_attempted": _wall_query_attempted,
		"wall_query_skipped": _wall_query_skipped,
		"wall_query_cache_hit": _wall_query_cache_hit,
		"wall_query_executed": _wall_query_executed,
	}

func _register_legacy_bridge_usage(bridge_id: String, details: String) -> void:
	if bridge_id == "bandit_perception.resource_sticky_fallback":
		_legacy_resource_sticky_fallback_uses += 1
	Debug.log("compat", "[DEPRECATED_BRIDGE][%s] %s" % [bridge_id, details])
	push_warning("[BanditPerceptionSystem] Deprecated compatibility bridge used: %s" % bridge_id)
	if OS.is_debug_build():
		assert(false, "[BanditPerceptionSystem] Deprecated compatibility bridge used: %s — %s" % [bridge_id, details])


func _build_player_presence(node_pos: Vector2) -> Dictionary:
	if _player == null or not is_instance_valid(_player):
		return {
			"known": false,
			"distance": INF,
			"distance_sq": INF,
			"position": Vector2.ZERO,
		}
	var player_pos: Vector2 = _player.global_position
	var d_sq: float = node_pos.distance_squared_to(player_pos)
	var d: float = sqrt(d_sq)
	return {
		"known": true,
		"distance": d,
		"distance_sq": d_sq,
		"position": player_pos,
	}


func _build_assault_targets(node_pos: Vector2, wall_query_allowed: bool = false, group_id: String = "") -> Dictionary:
	var radius: float = 12000.0
	var nearest_wall: Vector2 = Vector2.ZERO
	var nearest_workbench: Vector2 = Vector2.ZERO
	var nearest_storage: Vector2 = Vector2.ZERO
	var nearest_placeable: Vector2 = Vector2.ZERO
	_wall_query_attempted += 1
	if not wall_query_allowed:
		_wall_query_skipped += 1
	else:
		var now: float = RunClock.now()
		if group_id != "" and _group_wall_target_cache.has(group_id) \
				and now < float(_group_wall_target_expires.get(group_id, 0.0)):
			_wall_query_cache_hit += 1
			nearest_wall = _group_wall_target_cache[group_id] as Vector2
		elif _find_wall_cb.is_valid():
			_wall_query_executed += 1
			nearest_wall = _find_wall_cb.call(node_pos, radius)
			if group_id != "":
				_group_wall_target_cache[group_id] = nearest_wall
				_group_wall_target_expires[group_id] = now + _WALL_CACHE_TTL
	var cache_now: float = RunClock.now()
	if group_id != "" and _group_workbench_target_cache.has(group_id) \
			and cache_now < float(_group_workbench_target_expires.get(group_id, 0.0)):
		nearest_workbench = _group_workbench_target_cache[group_id] as Vector2
	elif _find_workbench_cb.is_valid():
		nearest_workbench = _find_workbench_cb.call(node_pos, radius)
		if group_id != "":
			_group_workbench_target_cache[group_id] = nearest_workbench
			_group_workbench_target_expires[group_id] = cache_now + _ASSAULT_TARGET_CACHE_TTL
	if group_id != "" and _group_storage_target_cache.has(group_id) \
			and cache_now < float(_group_storage_target_expires.get(group_id, 0.0)):
		nearest_storage = _group_storage_target_cache[group_id] as Vector2
	elif _find_storage_cb.is_valid():
		nearest_storage = _find_storage_cb.call(node_pos, radius)
		if group_id != "":
			_group_storage_target_cache[group_id] = nearest_storage
			_group_storage_target_expires[group_id] = cache_now + _ASSAULT_TARGET_CACHE_TTL
	if group_id != "" and _group_placeable_target_cache.has(group_id) \
			and cache_now < float(_group_placeable_target_expires.get(group_id, 0.0)):
		nearest_placeable = _group_placeable_target_cache[group_id] as Vector2
	elif _find_placeable_cb.is_valid():
		nearest_placeable = _find_placeable_cb.call(node_pos, radius, {})
		if group_id != "":
			_group_placeable_target_cache[group_id] = nearest_placeable
			_group_placeable_target_expires[group_id] = cache_now + _ASSAULT_TARGET_CACHE_TTL
	return {
		"nearest_wall": nearest_wall,
		"nearest_workbench": nearest_workbench,
		"nearest_storage": nearest_storage,
		"nearest_placeable": nearest_placeable,
	}


func invalidate_group_wall_cache(group_id: String) -> void:
	invalidate_group_assault_cache(group_id)


func invalidate_group_assault_cache(group_id: String) -> void:
	_group_wall_target_cache.erase(group_id)
	_group_wall_target_expires.erase(group_id)
	_group_workbench_target_cache.erase(group_id)
	_group_workbench_target_expires.erase(group_id)
	_group_storage_target_cache.erase(group_id)
	_group_storage_target_expires.erase(group_id)
	_group_placeable_target_cache.erase(group_id)
	_group_placeable_target_expires.erase(group_id)
