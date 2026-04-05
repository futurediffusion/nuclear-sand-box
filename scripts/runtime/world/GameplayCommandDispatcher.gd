extends RefCounted
class_name GameplayCommandDispatcher

## Command routing contract:
## - World receives gameplay-facing commands and forwards them to this dispatcher.
## - This dispatcher does no scene orchestration; it routes to specialized systems.
## - Current routed commands:
##   * Player walls: can_place/place/damage/hit/remove.
##   * Settlement intel writes: record_interest_event, rescan_workbench_markers, mark_interest_scan_dirty.
##   * Tavern authority incidents: report_tavern_incident.

var _player_wall_system: PlayerWallSystem
var _settlement_intel: SettlementIntel
var _world_territory_policy: WorldTerritoryPolicy
var _tavern_memory: TavernLocalMemory
var _tavern_policy: TavernAuthorityPolicy
var _tavern_director: TavernSanctionDirector

var _register_drop_compaction_hotspot: Callable = Callable()
var _mark_player_territory_dirty: Callable = Callable()
var _find_nearest_player: Callable = Callable()

func setup(ctx: Dictionary) -> void:
	_player_wall_system = ctx.get("player_wall_system", null) as PlayerWallSystem
	_settlement_intel = ctx.get("settlement_intel", null) as SettlementIntel
	_world_territory_policy = ctx.get("world_territory_policy", null) as WorldTerritoryPolicy
	_tavern_memory = ctx.get("tavern_memory", null) as TavernLocalMemory
	_tavern_policy = ctx.get("tavern_policy", null) as TavernAuthorityPolicy
	_tavern_director = ctx.get("tavern_director", null) as TavernSanctionDirector
	_register_drop_compaction_hotspot = ctx.get("register_drop_compaction_hotspot", Callable()) as Callable
	_mark_player_territory_dirty = ctx.get("mark_player_territory_dirty", Callable()) as Callable
	_find_nearest_player = ctx.get("find_nearest_player", Callable()) as Callable

func can_place_player_wall_at_tile(tile_pos: Vector2i) -> bool:
	return _player_wall_system != null and _player_wall_system.can_place_player_wall_at_tile(tile_pos)

func place_player_wall_at_tile(tile_pos: Vector2i, hp_override: int = -1) -> bool:
	return _player_wall_system != null and _player_wall_system.place_player_wall_at_tile(tile_pos, hp_override)

func damage_player_wall_from_contact(hit_pos: Vector2, hit_normal: Vector2, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_from_contact(hit_pos, hit_normal, amount)

func damage_player_wall_near_world_pos(world_pos: Vector2, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_near_world_pos(world_pos, amount)

func damage_player_wall_at_world_pos(world_pos: Vector2, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_at_world_pos(world_pos, amount)

func damage_player_wall_in_circle(world_center: Vector2, world_radius: float, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_in_circle(world_center, world_radius, amount)

func hit_wall_at_world_pos(world_pos: Vector2, amount: int = 1, radius: float = 20.0, allow_structural_feedback: bool = true) -> bool:
	return _player_wall_system != null and _player_wall_system.hit_wall_at_world_pos(world_pos, amount, radius, allow_structural_feedback)

func damage_player_wall_at_tile(tile_pos: Vector2i, amount: int = 1) -> bool:
	return _player_wall_system != null and _player_wall_system.damage_player_wall_at_tile(tile_pos, amount)

func remove_player_wall_at_tile(tile_pos: Vector2i, drop_item: bool = true) -> bool:
	return _player_wall_system != null and _player_wall_system.remove_player_wall_at_tile(tile_pos, drop_item)

func record_interest_event(kind: String, world_pos: Vector2, metadata: Dictionary = {}) -> void:
	if _settlement_intel != null:
		_settlement_intel.record_interest_event(kind, world_pos, metadata)
	if _world_territory_policy != null:
		_world_territory_policy.record_interest_event(kind, world_pos)
	if _register_drop_compaction_hotspot.is_valid():
		if kind in ["copper_mined", "stone_mined", "wood_chopped"]:
			_register_drop_compaction_hotspot.call(world_pos, 3)
		elif kind.find("destroy") >= 0:
			_register_drop_compaction_hotspot.call(world_pos, 2)
	if _mark_player_territory_dirty.is_valid() and (kind == "workbench" or kind == "structure_placed"):
		_mark_player_territory_dirty.call()

func rescan_workbench_markers() -> void:
	if _settlement_intel != null:
		_settlement_intel.rescan_workbench_markers()
	if _mark_player_territory_dirty.is_valid():
		_mark_player_territory_dirty.call()

func mark_interest_scan_dirty() -> void:
	if _settlement_intel != null:
		_settlement_intel.mark_interest_scan_dirty()

func report_tavern_incident(incident_type: String, payload: Dictionary = {}) -> void:
	if _tavern_memory == null or _tavern_policy == null or _tavern_director == null:
		return
	var incident := _build_tavern_incident(incident_type, payload)
	if incident == null:
		Debug.log("authority", "[TAVERN] incident_type='%s' sin mapping — ignorado" % incident_type)
		return

	var directive: LocalAuthorityDirective = _tavern_policy.evaluate(incident)
	_tavern_memory.record(incident)
	Debug.log("authority", "[TAVERN] %s" % directive.describe())

	if directive.response_type == LocalAuthorityResponse.Response.RECORD_ONLY:
		return

	var offender_node: CharacterBody2D = payload.get("offender", null) as CharacterBody2D
	if offender_node == null or not is_instance_valid(offender_node):
		var is_enemy_incident := incident_type in ["armed_intruder", "bandit_attack", "murder_in_tavern"]
		if not is_enemy_incident and _find_nearest_player.is_valid():
			var incident_pos: Vector2 = payload.get("pos", Vector2.ZERO)
			offender_node = _find_nearest_player.call(incident_pos) as CharacterBody2D

	_tavern_director.dispatch(directive, offender_node)

func _build_tavern_incident(incident_type: String, payload: Dictionary) -> LocalCivilIncident:
	var C := LocalCivilAuthorityConstants
	var offense: String = ""
	var severity: float = 0.0
	var victim_kind: String = C.VictimKind.CIVILIAN
	var zone: String = C.ZONE_TAVERN_INTERIOR

	match incident_type:
		"assault_keeper":
			offense = C.Offense.ASSAULT
			severity = C.SEVERITY_SERIOUS
			victim_kind = C.VictimKind.AUTHORITY_MEMBER
		"assault_sentinel":
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
		"barrel_opened":
			offense = C.Offense.TRESPASS
			severity = C.SEVERITY_MINOR
			victim_kind = C.VictimKind.TAVERN_PROPERTY
		"barrel_destroyed":
			offense = C.Offense.VANDALISM
			severity = C.SEVERITY_MODERATE
			victim_kind = C.VictimKind.TAVERN_PROPERTY
		"armed_intruder":
			offense = C.Offense.WEAPON_THREAT
			severity = C.SEVERITY_SERIOUS
		"trespass":
			offense = C.Offense.TRESPASS
			severity = C.SEVERITY_MINOR
			victim_kind = C.VictimKind.TAVERN_PROPERTY
			zone = C.ZONE_TAVERN_GROUNDS
		"bandit_attack":
			offense = C.Offense.ASSAULT
			severity = C.SEVERITY_SERIOUS
		"disturbance":
			offense = C.Offense.DISTURBANCE
			severity = C.SEVERITY_MINOR
			zone = C.ZONE_TAVERN_INTERIOR
		"suspicious_presence":
			offense = C.Offense.DISTURBANCE
			severity = C.SEVERITY_MINOR
			zone = C.ZONE_TAVERN_PERIMETER
		"loitering":
			offense = C.Offense.TRESPASS
			severity = C.SEVERITY_MINOR
			zone = C.ZONE_TAVERN_GROUNDS
		_:
			return null

	var offender_node: Node2D = payload.get("offender", null) as Node2D
	var offender_id: String = ""
	var offender_pos: Vector2 = payload.get("pos", Vector2.ZERO)

	if offender_node != null and is_instance_valid(offender_node):
		offender_id = offender_node.name
		if offender_pos == Vector2.ZERO:
			offender_pos = offender_node.global_position

	return LocalCivilIncidentFactory.create(
		"tavern_main",
		offense,
		severity,
		offender_pos,
		offender_id,
		victim_kind,
		zone,
		[],
		incident_type,
		{}
	)
