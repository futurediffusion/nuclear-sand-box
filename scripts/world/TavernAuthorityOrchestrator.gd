class_name TavernAuthorityOrchestrator
extends RefCounted

const _POSTURE_EVAL_INTERVAL: float = 10.0

var _memory: TavernLocalMemory
var _policy: TavernAuthorityPolicy
var _director: TavernSanctionDirector
var _presence_monitor: TavernPresenceMonitor
var _get_tavern_inner_bounds_world: Callable
var _get_tavern_sentinels: Callable
var _find_nearest_player: Callable

var _posture_eval_accum: float = 0.0
var _current_posture: int = TavernDefensePosture.NORMAL
var _perimeter_patrol_cache: Dictionary = {}

func setup(ctx: Dictionary) -> void:
	_memory = ctx.get("memory", null)
	_policy = ctx.get("policy", null)
	_director = ctx.get("director", null)
	_presence_monitor = ctx.get("presence_monitor", null)
	_get_tavern_inner_bounds_world = ctx.get("get_tavern_inner_bounds_world", Callable())
	_get_tavern_sentinels = ctx.get("get_tavern_sentinels", Callable())
	_find_nearest_player = ctx.get("find_nearest_player", Callable())

func report_incident(incident_type: String, payload: Dictionary = {}) -> void:
	if _memory == null or _policy == null or _director == null:
		return
	var incident := _build_tavern_incident(incident_type, payload)
	if incident == null:
		Debug.log("authority", "[TAVERN] incident_type='%s' sin mapping — ignorado" % incident_type)
		return

	var directive: LocalAuthorityDirective = _policy.evaluate(incident)
	_memory.record(incident)
	Debug.log("authority", "[TAVERN] %s" % directive.describe())

	if directive.response_type == LocalAuthorityResponse.Response.RECORD_ONLY:
		return

	var offender_node: CharacterBody2D = payload.get("offender", null) as CharacterBody2D
	if offender_node == null or not is_instance_valid(offender_node):
		var is_enemy_incident := incident_type in ["armed_intruder", "bandit_attack", "murder_in_tavern"]
		if not is_enemy_incident and _find_nearest_player.is_valid():
			var incident_pos: Vector2 = payload.get("pos", Vector2.ZERO)
			offender_node = _find_nearest_player.call(incident_pos) as CharacterBody2D

	_director.dispatch(directive, offender_node)

func tick_defense_posture(delta: float) -> void:
	if _memory == null:
		return
	_posture_eval_accum += delta
	if _posture_eval_accum < _POSTURE_EVAL_INTERVAL:
		return
	_posture_eval_accum = 0.0

	var bounds: Rect2 = _get_tavern_inner_bounds_world.call() if _get_tavern_inner_bounds_world.is_valid() else Rect2()
	var tavern_center: Vector2 = bounds.get_center() if bounds.size != Vector2.ZERO else Vector2.ZERO
	var new_posture: int = TavernDefensePosture.compute(_memory, tavern_center, RunClock.now())
	if new_posture == _current_posture:
		return

	var old_posture: int = _current_posture
	_current_posture = new_posture
	_apply_defense_posture(new_posture, old_posture)
	Debug.log("authority", "[POSTURE] %s → %s" % [
		TavernDefensePosture.name_of(old_posture),
		TavernDefensePosture.name_of(new_posture),
	])

func remember_perimeter_patrol(sentinel: Sentinel, patrol_points: PackedVector2Array) -> void:
	if sentinel == null or patrol_points.is_empty():
		return
	_perimeter_patrol_cache[sentinel] = patrol_points.duplicate()

func build_perimeter_patrol_points(side: String, home: Vector2) -> PackedVector2Array:
	var b: Rect2 = _get_tavern_inner_bounds_world.call() if _get_tavern_inner_bounds_world.is_valid() else Rect2()
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

func _apply_defense_posture(posture: int, old_posture: int) -> void:
	if _presence_monitor != null:
		_presence_monitor.set_defense_posture(posture)
	if _policy != null:
		_policy.set_defense_posture(posture)
	_adapt_perimeter_patrols(posture, old_posture)

func _adapt_perimeter_patrols(posture: int, old_posture: int) -> void:
	if not _get_tavern_sentinels.is_valid():
		return
	var sentinels: Array = _get_tavern_sentinels.call()
	for node: Variant in sentinels:
		if not (node is Sentinel and is_instance_valid(node)):
			continue
		var s := node as Sentinel
		if s.sentinel_role != "perimeter_guard":
			continue
		if posture == TavernDefensePosture.FORTIFIED:
			if not _perimeter_patrol_cache.has(s) and not s.patrol_points.is_empty():
				_perimeter_patrol_cache[s] = s.patrol_points.duplicate()
			s.patrol_points = PackedVector2Array()
		elif old_posture == TavernDefensePosture.FORTIFIED and _perimeter_patrol_cache.has(s):
			s.patrol_points = _perimeter_patrol_cache[s] as PackedVector2Array

func _build_tavern_incident(incident_type: String, payload: Dictionary) -> LocalCivilIncident:
	var C := LocalCivilAuthorityConstants
	var offense: String = ""
	var severity: float = 0.0
	var victim_kind: String = C.VictimKind.CIVILIAN
	var zone: String = C.ZONE_TAVERN_INTERIOR
	match incident_type:
		"assault_keeper", "assault_sentinel":
			offense = C.Offense.ASSAULT
			severity = C.SEVERITY_SERIOUS
			victim_kind = C.VictimKind.AUTHORITY_MEMBER
		"murder_in_tavern":
			offense = C.Offense.MURDER
			severity = C.SEVERITY_CRITICAL
		"wall_damaged":
			offense = C.Offense.VANDALISM
			severity = C.SEVERITY_MODERATE
			victim_kind = C.VictimKind.TAVERN_PROPERTY
		"wall_damaged_exterior":
			offense = C.Offense.VANDALISM
			severity = C.SEVERITY_SERIOUS
			victim_kind = C.VictimKind.TAVERN_PROPERTY
			zone = C.ZONE_TAVERN_PERIMETER
		"barrel_opened", "trespass", "loitering":
			offense = C.Offense.TRESPASS
			severity = C.SEVERITY_MINOR
			victim_kind = C.VictimKind.TAVERN_PROPERTY
			zone = C.ZONE_TAVERN_GROUNDS if incident_type != "barrel_opened" else C.ZONE_TAVERN_INTERIOR
		"barrel_destroyed":
			offense = C.Offense.VANDALISM
			severity = C.SEVERITY_MODERATE
			victim_kind = C.VictimKind.TAVERN_PROPERTY
		"armed_intruder":
			offense = C.Offense.WEAPON_THREAT
			severity = C.SEVERITY_SERIOUS
		"bandit_attack":
			offense = C.Offense.ASSAULT
			severity = C.SEVERITY_SERIOUS
		"disturbance", "suspicious_presence":
			offense = C.Offense.DISTURBANCE
			severity = C.SEVERITY_MINOR
			zone = C.ZONE_TAVERN_PERIMETER if incident_type == "suspicious_presence" else C.ZONE_TAVERN_INTERIOR
		_:
			return null

	var offender_node: Node2D = payload.get("offender", null) as Node2D
	var offender_id: String = ""
	var offender_pos: Vector2 = payload.get("pos", Vector2.ZERO)
	if offender_node != null and is_instance_valid(offender_node):
		offender_id = offender_node.name
		if offender_pos == Vector2.ZERO:
			offender_pos = offender_node.global_position
	return LocalCivilIncidentFactory.create("tavern_main", offense, severity, offender_pos, offender_id, victim_kind, zone, [], incident_type, {})
