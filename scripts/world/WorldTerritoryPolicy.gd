extends RefCounted
class_name WorldTerritoryPolicy

# WorldTerritoryPolicy centralizes territory/social rules that world.gd only
# orchestrates. It validates placement restrictions and translates player
# actions into bandit-territory hostility events, while delegating bandit-side
# reactions to a small callback bridge.
#
# Future-facing seam:
# local civil authority (tavern, village, etc.) should plug in through
# LocalSocialAuthorityPorts. This policy may consult those ports for local
# rules later, but bandit global hostility remains independent and persistent.

const TAVERN_BUILD_RADIUS_SQ: float = 320.0 * 320.0
const CONTEST_MIN_LEVEL: int = 3
const CONTESTED_TERRITORY_BUFFER: float = 200.0
const TERRITORY_INTRUSION_COOLDOWN: float = 6.0
const TERRITORY_INTRUSION_PTS: Dictionary = {
	"workbench": 8.0,
	"structure_placed": 5.0,
	"copper_mined": 4.0,
	"stone_mined": 4.0,
	"wood_chopped": 2.0,
}

var _tile_to_world: Callable = Callable()
var _get_tavern_center_tile: Callable = Callable()
var _react_to_bandit_territory_intrusion: Callable = Callable()
var _local_social_ports: LocalSocialAuthorityPorts = null
var _territory_intrusion_cooldown: Dictionary = {}
var _legacy_intrusion_reaction_callback_missing_uses: int = 0

func setup(ctx: Dictionary) -> void:
	_tile_to_world = ctx.get("tile_to_world", Callable())
	_get_tavern_center_tile = ctx.get("get_tavern_center_tile", Callable())
	_react_to_bandit_territory_intrusion = ctx.get("react_to_bandit_territory_intrusion", Callable())
	_local_social_ports = ctx.get("local_social_ports") as LocalSocialAuthorityPorts

func validate_placement(tile_pos: Vector2i, tavern_chunk: Vector2i) -> bool:
	if not _tile_to_world.is_valid() or not _get_tavern_center_tile.is_valid():
		return true
	var world_pos: Vector2 = _tile_to_world.call(tile_pos)
	var tavern_tile: Vector2i = _get_tavern_center_tile.call(tavern_chunk)
	var tavern_pos: Vector2 = _tile_to_world.call(tavern_tile)

	# Frontier note:
	# this is only a spatial world rule today. A future tavern civil authority
	# may add local permissions through _local_social_ports without moving the
	# source of truth back into world.gd or NPC actors.
	if world_pos.distance_squared_to(tavern_pos) <= TAVERN_BUILD_RADIUS_SQ:
		return false
	for gid in BanditGroupMemory.get_all_group_ids():
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		if g.is_empty():
			continue
		var leader_id: String = String(g.get("leader_id", ""))
		if leader_id == "":
			continue
		var home_pos: Vector2 = g.get("home_world_pos", Vector2.ZERO) as Vector2
		var faction_id: String = String(g.get("faction_id", "bandits"))
		var territory_radius: float = BanditTerritoryQuery.radius_for_faction(faction_id)
		var camp_core_radius: float = maxf(0.0, territory_radius - CONTESTED_TERRITORY_BUFFER)
		var dist: float = world_pos.distance_to(home_pos)
		if dist <= camp_core_radius:
			return false
		var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
		if profile.hostility_level < CONTEST_MIN_LEVEL:
			continue
		if dist <= territory_radius:
			return false
	return true

func record_interest_event(kind: String, world_pos: Vector2) -> void:
	if not TERRITORY_INTRUSION_PTS.has(kind):
		return

	# Optional future bridge: local civil authority can observe the same world
	# event stream later, but no tavern memory/sanction logic is implemented yet.
	if _local_social_ports != null:
		_local_social_ports.evaluate_local_authority("world_interest_event", {
			"kind": kind,
			"world_pos": world_pos,
		})

	var groups: Array[Dictionary] = BanditTerritoryQuery.groups_at(world_pos)
	if groups.is_empty():
		return
	var pts: float = float(TERRITORY_INTRUSION_PTS[kind])
	var now: float = RunClock.now()
	var reacted_group: Dictionary = {}
	for entry in groups:
		var faction_id: String = String(entry.get("faction_id", ""))
		if now - float(_territory_intrusion_cooldown.get(faction_id, 0.0)) < TERRITORY_INTRUSION_COOLDOWN:
			continue
		_territory_intrusion_cooldown[faction_id] = now
		var group_id: String = String(entry.get("group_id", ""))
		var reason: String
		match kind:
			"workbench":
				reason = "workbench_near"
			"copper_mined", "stone_mined", "wood_chopped":
				reason = "resource_extracted"
			_:
				reason = "structure_near"
		var entity_id: String = "territory:%s:%s" % [faction_id, kind]
		FactionHostilityManager.add_hostility(faction_id, pts, reason, {
			"entity_id": entity_id,
			"group_id": group_id,
			"position": world_pos,
		})
		Debug.log("territory", "[TERRITORY] intrusion kind=%s faction=%s pts=%.0f pos=%s" % [
			kind, faction_id, pts, str(world_pos)])
		if reacted_group.is_empty():
			reacted_group = entry
	if reacted_group.is_empty():
		return
	if _react_to_bandit_territory_intrusion.is_valid():
		_react_to_bandit_territory_intrusion.call(reacted_group, world_pos, kind)
		return
	_register_legacy_bridge_usage(
		"world_territory_policy.intrusion_reaction_callback_missing",
		"Bandit intrusion reaction callback missing; hostility applied without behavior reaction."
	)

func get_debug_snapshot() -> Dictionary:
	return {
		"legacy_intrusion_reaction_callback_missing_uses": _legacy_intrusion_reaction_callback_missing_uses,
	}

func _register_legacy_bridge_usage(bridge_id: String, details: String) -> void:
	_legacy_intrusion_reaction_callback_missing_uses += 1
	Debug.log("compat", "[DEPRECATED_BRIDGE][%s] %s count=%d" % [
		bridge_id,
		details,
		_legacy_intrusion_reaction_callback_missing_uses,
	])
	push_warning("[WorldTerritoryPolicy] Deprecated compatibility bridge used: %s" % bridge_id)
	if OS.is_debug_build():
		assert(false, "[WorldTerritoryPolicy] Deprecated compatibility bridge used: %s — %s" % [bridge_id, details])
