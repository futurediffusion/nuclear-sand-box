extends RefCounted
class_name TavernSecurityRuntime

const _POSTURE_EVAL_INTERVAL: float = 10.0

var _world_node: Node = null
var _entity_root: Node2D = null
var _sentinel_scene: PackedScene = null
var _tavern_chunk: Vector2i = Vector2i.ZERO
var _chunk_size: int = 32

var _tile_to_world: Callable = Callable()
var _get_tavern_exit_world_pos: Callable = Callable()
var _get_tavern_inner_bounds_world: Callable = Callable()
var _report_tavern_incident: Callable = Callable()

var _tavern_memory: TavernLocalMemory
var _tavern_policy: TavernAuthorityPolicy
var _tavern_director: TavernSanctionDirector
var _tavern_presence_monitor: TavernPresenceMonitor
var _tavern_garrison_monitor: TavernGarrisonMonitor
var _tavern_brawl: TavernPerimeterBrawl

var _posture_eval_accum: float = 0.0
var _current_posture: int = TavernDefensePosture.NORMAL
var _perimeter_patrol_cache: Dictionary = {}
var _tavern_sentinels_spawned: bool = false

func setup(ctx: Dictionary) -> void:
	_world_node = ctx.get("world_node", null) as Node
	_entity_root = ctx.get("entity_root", null) as Node2D
	_sentinel_scene = ctx.get("sentinel_scene", null) as PackedScene
	_tavern_chunk = ctx.get("tavern_chunk", Vector2i.ZERO) as Vector2i
	_chunk_size = int(ctx.get("chunk_size", 32))
	_tile_to_world = ctx.get("tile_to_world", Callable()) as Callable
	_get_tavern_exit_world_pos = ctx.get("get_tavern_exit_world_pos", Callable()) as Callable
	_get_tavern_inner_bounds_world = ctx.get("get_tavern_inner_bounds_world", Callable()) as Callable
	_report_tavern_incident = ctx.get("report_tavern_incident", Callable()) as Callable

	_tavern_memory = TavernLocalMemory.new()
	_tavern_policy = TavernAuthorityPolicy.new()
	_tavern_policy.setup({"memory": _tavern_memory})

	_tavern_director = TavernSanctionDirector.new()
	_tavern_director.setup({
		"get_keeper": Callable(self, "_get_tavern_keeper_node"),
		"get_sentinels": func() -> Array: return _get_tree_nodes_in_group("tavern_sentinel"),
		"memory_deny_service": Callable(_tavern_memory, "deny_service_for"),
		"tavern_site_id": "tavern_main",
	})

	_tavern_presence_monitor = TavernPresenceMonitor.new()
	_tavern_presence_monitor.setup({
		"incident_reporter": Callable(self, "report_tavern_incident"),
		"get_candidates": func() -> Array:
			var r: Array = []
			r.append_array(_get_tree_nodes_in_group("player"))
			r.append_array(_get_tree_nodes_in_group("enemy"))
			r.append_array(_get_tree_nodes_in_group("npc"))
			return r,
		"interior_bounds": Callable(self, "_get_inner_bounds"),
	})

	_tavern_garrison_monitor = TavernGarrisonMonitor.new()
	_tavern_garrison_monitor.setup({
		"get_sentinels": func() -> Array: return _get_tree_nodes_in_group("tavern_sentinel"),
		"tavern_site_id": "tavern_main",
	})

	_tavern_brawl = TavernPerimeterBrawl.new()
	_tavern_brawl.setup({
		"get_sentinels": func() -> Array: return _get_tree_nodes_in_group("tavern_sentinel"),
		"get_nearby_enemies": Callable(self, "_query_nearby_enemies"),
		"get_tavern_center": func() -> Vector2:
			var b: Rect2 = _get_inner_bounds()
			return b.get_center() if b.size != Vector2.ZERO else Vector2.ZERO,
	})

func get_tavern_memory() -> TavernLocalMemory:
	return _tavern_memory

func get_tavern_policy() -> TavernAuthorityPolicy:
	return _tavern_policy

func get_tavern_director() -> TavernSanctionDirector:
	return _tavern_director

func tick(delta: float) -> void:
	if _tavern_presence_monitor != null:
		_tavern_presence_monitor.tick(delta)
	if _tavern_garrison_monitor != null:
		_tavern_garrison_monitor.tick(delta)
	if _tavern_brawl != null:
		_tavern_brawl.tick(delta)
	_tick_defense_posture(delta)

func on_chunk_stage_completed(chunk_pos: Vector2i, stage: String) -> void:
	if stage == "entities_enqueued" and chunk_pos == _tavern_chunk:
		ensure_tavern_sentinels_spawned()

func on_spawn_job_completed(job: Dictionary, _node: Node) -> void:
	if String(job.get("kind", "")) == "npc_keeper":
		_wire_keeper_incident_reporter()

func on_wall_hit_activity(tile_pos: Vector2i, player_world_pos: Vector2) -> void:
	var keepers := _get_tree_nodes_in_group("tavern_keeper")
	if keepers.is_empty():
		return
	var keeper := keepers[0]
	var inner_min: Vector2i = keeper.get("tavern_inner_min")
	var inner_max: Vector2i = keeper.get("tavern_inner_max")
	var world_pos: Vector2 = _call_tile_to_world(tile_pos)
	var player_tile: Vector2i = _call_world_to_tile(player_world_pos)
	var player_inside: bool = player_tile.x >= inner_min.x and player_tile.x <= inner_max.x \
						  and player_tile.y >= inner_min.y and player_tile.y <= inner_max.y
	if player_inside:
		report_tavern_incident("wall_damaged", {"pos": world_pos})
		return
	const PERIM: int = 10
	var in_perim: bool = tile_pos.x >= inner_min.x - PERIM \
					 and tile_pos.x <= inner_max.x + PERIM \
					 and tile_pos.y >= inner_min.y - PERIM \
					 and tile_pos.y <= inner_max.y + PERIM
	if in_perim:
		report_tavern_incident("wall_damaged_exterior", {"pos": world_pos})

func on_entity_died(pos: Vector2, killer: Node) -> void:
	var tavern_bounds: Rect2 = _get_inner_bounds()
	if tavern_bounds.size == Vector2.ZERO:
		return
	if not tavern_bounds.grow(16.0).has_point(pos):
		return
	var killer_node: CharacterBody2D = killer as CharacterBody2D
	report_tavern_incident("murder_in_tavern", {"offender": killer_node, "pos": pos})

func ensure_tavern_sentinels_spawned() -> void:
	if _tavern_sentinels_spawned:
		return
	if not _get_tree_nodes_in_group("tavern_sentinel").is_empty():
		_tavern_sentinels_spawned = true
		return
	if _sentinel_scene == null:
		Debug.log("world", "ensure_tavern_sentinels_spawned: sentinel_scene no asignada en Inspector")
		return
	if _entity_root == null:
		Debug.log("world", "ensure_tavern_sentinels_spawned: _entity_root no disponible")
		return

	_tavern_sentinels_spawned = true

	var keeper_pos: Vector2 = _get_tavern_keeper_pos()
	var exit_pos: Vector2 = _get_exit_world_pos()
	var bounds: Rect2 = _get_inner_bounds()
	var cx: float = bounds.position.x + bounds.size.x * 0.5
	var cy: float = bounds.position.y + bounds.size.y * 0.5

	_spawn_single_tavern_sentinel("interior_guard", keeper_pos + Vector2(-28.0, 16.0))
	_spawn_single_tavern_sentinel("interior_guard", keeper_pos + Vector2(28.0, 16.0))

	var dg := _spawn_single_tavern_sentinel("door_guard", exit_pos + Vector2(0.0, 32.0))
	if dg != null:
		dg.patrol_points = PackedVector2Array([
			exit_pos + Vector2(-52.0, 28.0),
			exit_pos + Vector2(0.0, 20.0),
			exit_pos + Vector2(44.0, 36.0),
			exit_pos + Vector2(16.0, 52.0),
			exit_pos + Vector2(-32.0, 44.0),
		])

	const _PM: float = 128.0
	const _PO: float = 56.0
	_spawn_single_tavern_sentinel("perimeter_guard", Vector2(cx - _PO, bounds.position.y - _PM), "north")
	_spawn_single_tavern_sentinel("perimeter_guard", Vector2(cx + _PO, bounds.position.y - _PM), "north")
	_spawn_single_tavern_sentinel("perimeter_guard", Vector2(cx - _PO, bounds.position.y + bounds.size.y + _PM), "south")
	_spawn_single_tavern_sentinel("perimeter_guard", Vector2(cx + _PO, bounds.position.y + bounds.size.y + _PM), "south")
	_spawn_single_tavern_sentinel("perimeter_guard", Vector2(bounds.position.x + bounds.size.x + _PM, cy - _PO), "east")
	_spawn_single_tavern_sentinel("perimeter_guard", Vector2(bounds.position.x + bounds.size.x + _PM, cy + _PO), "east")
	_spawn_single_tavern_sentinel("perimeter_guard", Vector2(bounds.position.x - _PM, cy - _PO), "west")
	_spawn_single_tavern_sentinel("perimeter_guard", Vector2(bounds.position.x - _PM, cy + _PO), "west")

	Debug.log("world", "[TavernSentinels] 11 desplegados — keeper=%s exit=%s bounds=%s" % [str(keeper_pos), str(exit_pos), str(bounds)])

func report_tavern_incident(incident_type: String, payload: Dictionary = {}) -> void:
	if _report_tavern_incident.is_valid():
		_report_tavern_incident.call(incident_type, payload)

func _spawn_single_tavern_sentinel(role: String, pos: Vector2, side: String = "") -> Sentinel:
	var s := _sentinel_scene.instantiate() as Sentinel
	match role:
		"door_guard":
			s.name = "door_guard"
		"perimeter_guard":
			s.name = "perimeter_guard_" + side if not side.is_empty() else "perimeter_guard"
		"interior_guard":
			s.name = "interior_guard"
	_entity_root.add_child(s)
	s.global_position = pos
	s.home_pos = pos
	s.sentinel_role = role
	s.tavern_site_id = "tavern_main"
	s.add_to_group("tavern_sentinel")
	s.set_incident_reporter(Callable(self, "report_tavern_incident"))
	match role:
		"interior_guard":
			s.patrol_points = _get_interior_patrol_points()
		"perimeter_guard":
			if not side.is_empty():
				var pts := _get_perimeter_patrol_points(side, pos)
				s.patrol_points = pts
				_perimeter_patrol_cache[s] = pts.duplicate()
	return s

func _get_interior_patrol_points() -> PackedVector2Array:
	var b: Rect2 = _get_inner_bounds()
	var inset: float = 28.0
	var bi: Rect2 = b.grow(-inset)
	var cx: float = bi.position.x + bi.size.x * 0.5
	var cy: float = bi.position.y + bi.size.y * 0.5
	var hw: float = bi.size.x * 0.5
	var hh: float = bi.size.y * 0.5
	return PackedVector2Array([
		bi.position,
		bi.position + Vector2(bi.size.x, 0.0),
		bi.position + bi.size,
		bi.position + Vector2(0.0, bi.size.y),
		Vector2(cx, cy - hh * 0.45),
		Vector2(cx + hw * 0.40, cy),
		Vector2(cx, cy + hh * 0.45),
		Vector2(cx - hw * 0.40, cy),
	])

func _get_perimeter_patrol_points(side: String, home: Vector2) -> PackedVector2Array:
	var b: Rect2 = _get_inner_bounds()
	const M: float = 128.0
	var d1: float = randf_range(20.0, 32.0)
	var d2: float = randf_range(16.0, 26.0)
	match side:
		"north", "south":
			var toward: float = 1.0 if side == "north" else -1.0
			return PackedVector2Array([
				Vector2(b.position.x - M, home.y + toward * d1),
				Vector2(b.position.x + b.size.x * 0.25, home.y - toward * d2),
				Vector2(b.position.x + b.size.x * 0.5, home.y),
				Vector2(b.position.x + b.size.x * 0.75, home.y - toward * d2),
				Vector2(b.position.x + b.size.x + M, home.y + toward * d1),
			])
		"east", "west":
			var toward: float = -1.0 if side == "east" else 1.0
			return PackedVector2Array([
				Vector2(home.x + toward * d1, b.position.y - M),
				Vector2(home.x - toward * d2, b.position.y + b.size.y * 0.25),
				Vector2(home.x, b.position.y + b.size.y * 0.5),
				Vector2(home.x - toward * d2, b.position.y + b.size.y * 0.75),
				Vector2(home.x + toward * d1, b.position.y + b.size.y + M),
			])
	return PackedVector2Array()

func _tick_defense_posture(delta: float) -> void:
	if _tavern_memory == null:
		return
	_posture_eval_accum += delta
	if _posture_eval_accum < _POSTURE_EVAL_INTERVAL:
		return
	_posture_eval_accum = 0.0
	var bounds: Rect2 = _get_inner_bounds()
	var tavern_center: Vector2 = bounds.get_center() if bounds.size != Vector2.ZERO else Vector2.ZERO
	var new_posture: int = TavernDefensePosture.compute(_tavern_memory, tavern_center, RunClock.now())
	if new_posture == _current_posture:
		return
	var old_posture: int = _current_posture
	_current_posture = new_posture
	_apply_defense_posture(new_posture, old_posture)
	Debug.log("authority", "[POSTURE] %s → %s" % [
		TavernDefensePosture.name_of(old_posture),
		TavernDefensePosture.name_of(new_posture),
	])

func _apply_defense_posture(posture: int, old_posture: int) -> void:
	if _tavern_presence_monitor != null:
		_tavern_presence_monitor.set_defense_posture(posture)
	if _tavern_policy != null:
		_tavern_policy.set_defense_posture(posture)
	_adapt_perimeter_patrols(posture, old_posture)

func _adapt_perimeter_patrols(posture: int, old_posture: int) -> void:
	for node in _get_tree_nodes_in_group("tavern_sentinel"):
		if not (node is Sentinel and is_instance_valid(node)):
			continue
		var s := node as Sentinel
		if s.sentinel_role != "perimeter_guard":
			continue
		if posture == TavernDefensePosture.FORTIFIED:
			if not _perimeter_patrol_cache.has(s) and not s.patrol_points.is_empty():
				_perimeter_patrol_cache[s] = s.patrol_points.duplicate()
			s.patrol_points = PackedVector2Array()
		elif old_posture == TavernDefensePosture.FORTIFIED:
			if _perimeter_patrol_cache.has(s):
				s.patrol_points = _perimeter_patrol_cache[s] as PackedVector2Array

func _get_tavern_keeper_pos() -> Vector2:
	var keepers := _get_tree_nodes_in_group("tavern_keeper")
	if not keepers.is_empty() and keepers[0] is Node2D:
		return (keepers[0] as Node2D).global_position
	var x0 := _tavern_chunk.x * _chunk_size + 4
	var y0 := _tavern_chunk.y * _chunk_size + 3
	return _tile_to_world.call(Vector2i(x0 + 6, y0 + 2)) if _tile_to_world.is_valid() else Vector2.ZERO

func _get_tavern_keeper_node() -> TavernKeeper:
	var keepers := _get_tree_nodes_in_group("tavern_keeper")
	if not keepers.is_empty() and keepers[0] is TavernKeeper:
		return keepers[0] as TavernKeeper
	return null

func _wire_keeper_incident_reporter() -> void:
	var keeper := _get_tavern_keeper_node()
	if keeper != null:
		keeper.set_incident_reporter(Callable(self, "report_tavern_incident"))
		keeper.set_service_check(Callable(_tavern_memory, "is_service_denied"))
	_register_tavern_containers()

func _register_tavern_containers() -> void:
	var bounds: Rect2 = _get_inner_bounds()
	if bounds.size == Vector2.ZERO:
		return
	var search_bounds := bounds.grow(32.0)
	var reporter := Callable(self, "report_tavern_incident")
	var registered: int = 0
	for group_name in ["chest", "interactable"]:
		for node in _get_tree_nodes_in_group(group_name):
			if not is_instance_valid(node) or not (node is Node2D):
				continue
			if not (node as Node2D).global_position.is_zero_approx() \
					and not search_bounds.has_point((node as Node2D).global_position):
				continue
			if node.has_method("set_civil_incident_reporter"):
				node.call("set_civil_incident_reporter", reporter)
				registered += 1
	Debug.log("authority", "[TAVERN] containers registrados con reporter: %d" % registered)

func _query_nearby_enemies(center: Vector2, radius: float) -> Array:
	var result: Array = []
	var candidate_chunks: Array[Node2D] = []
	var center_chunk_opt: Variant = EnemyRegistry.world_to_chunk(center)
	if center_chunk_opt != null:
		candidate_chunks = EnemyRegistry.get_bucket_neighborhood(center_chunk_opt as Vector2i)
	else:
		candidate_chunks = EnemyRegistry.get_live_enemies()
	for enemy_node in candidate_chunks:
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if enemy_node.global_position.distance_to(center) <= radius:
			result.append(enemy_node)
	return result

func _get_tree_nodes_in_group(group_name: String) -> Array:
	if _world_node == null or _world_node.get_tree() == null:
		return []
	return _world_node.get_tree().get_nodes_in_group(group_name)

func _get_inner_bounds() -> Rect2:
	if _get_tavern_inner_bounds_world.is_valid():
		return _get_tavern_inner_bounds_world.call() as Rect2
	return Rect2()

func _get_exit_world_pos() -> Vector2:
	if _get_tavern_exit_world_pos.is_valid():
		return _get_tavern_exit_world_pos.call() as Vector2
	return Vector2.ZERO

func _call_tile_to_world(tile_pos: Vector2i) -> Vector2:
	if _tile_to_world.is_valid():
		return _tile_to_world.call(tile_pos) as Vector2
	return Vector2.ZERO

func _call_world_to_tile(world_pos: Vector2) -> Vector2i:
	if _world_node != null and _world_node.has_method("_world_to_tile"):
		return _world_node.call("_world_to_tile", world_pos) as Vector2i
	return Vector2i(int(floor(world_pos.x)), int(floor(world_pos.y)))
