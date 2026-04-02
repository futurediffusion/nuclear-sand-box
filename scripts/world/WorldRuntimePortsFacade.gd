extends RefCounted
class_name WorldRuntimePortsFacade

var _group_index: RuntimeGroupIndex
var _player_getter: Callable
var _npc_simulator_getter: Callable
var _world_spatial_index_getter: Callable

func setup(ctx: Dictionary) -> void:
	_group_index = ctx.get("group_index")
	_player_getter = ctx.get("player_getter", Callable())
	_npc_simulator_getter = ctx.get("npc_simulator_getter", Callable())
	_world_spatial_index_getter = ctx.get("world_spatial_index_getter", Callable())

func get_tavern_keeper(cached_keeper: TavernKeeper) -> Dictionary:
	if cached_keeper != null and is_instance_valid(cached_keeper):
		return {"keeper": cached_keeper, "cached_keeper": cached_keeper}
	var keepers: Array = _get_group_nodes("tavern_keeper", 1.0)
	for node in keepers:
		if node is TavernKeeper:
			return {"keeper": node, "cached_keeper": node}
	return {"keeper": null, "cached_keeper": null}

func get_tavern_sentinels() -> Array:
	return _get_group_nodes("tavern_sentinel", 0.4)

func get_live_enemy_nodes() -> Array:
	var simulator: NpcSimulator = _npc_simulator_getter.call() if _npc_simulator_getter.is_valid() else null
	var result: Array = []
	if simulator != null:
		for enemy_node in simulator.active_enemies.values():
			if enemy_node != null and is_instance_valid(enemy_node):
				result.append(enemy_node)
		return result
	return _get_group_nodes("enemy", 0.4)

func get_live_npc_nodes() -> Array:
	return _get_group_nodes("npc", 0.4)

func get_live_player_nodes() -> Array:
	var player: Node = _player_getter.call() if _player_getter.is_valid() else null
	if player != null and is_instance_valid(player):
		return [player]
	return _get_group_nodes("player", 0.4)

func get_runtime_workbench_nodes() -> Array:
	var index: WorldSpatialIndex = _world_spatial_index_getter.call() if _world_spatial_index_getter.is_valid() else null
	if index != null:
		return index.get_all_runtime_nodes(WorldSpatialIndex.KIND_WORKBENCH)
	return _get_group_nodes("workbench", 0.4)

func get_enemies_near_runtime(pos: Vector2, radius: float) -> Array:
	var result: Array = []
	var radius_sq: float = radius * radius
	for e in get_live_enemy_nodes():
		if e == null or not is_instance_valid(e) or not (e is Node2D):
			continue
		if (e as Node2D).global_position.distance_squared_to(pos) <= radius_sq:
			result.append(e)
	return result

func register_tavern_containers(bounds: Rect2, reporter: Callable) -> int:
	if bounds.size == Vector2.ZERO:
		return 0
	var registered: int = 0
	var search_bounds := bounds.grow(32.0)
	for group_name in ["chest", "interactable"]:
		for node in _get_group_nodes(group_name, 0.0, true):
			if not is_instance_valid(node) or not (node is Node2D):
				continue
			var pos: Vector2 = (node as Node2D).global_position
			if not pos.is_zero_approx() and not search_bounds.has_point(pos):
				continue
			if node.has_method("set_civil_incident_reporter"):
				node.call("set_civil_incident_reporter", reporter)
				registered += 1
	return registered

func _get_group_nodes(group_name: String, max_age_sec: float, force_refresh: bool = false) -> Array:
	if _group_index == null:
		return []
	return _group_index.get_nodes(group_name, max_age_sec, force_refresh)
