extends RefCounted
class_name TavernAuthorityFacade

var _memory: TavernLocalMemory
var _policy: TavernAuthorityPolicy
var _director: TavernSanctionDirector
var _presence_monitor: TavernPresenceMonitor
var _garrison_monitor: TavernGarrisonMonitor
var _brawl: TavernPerimeterBrawl
var _orchestrator: TavernAuthorityOrchestrator
var _ports: LocalSocialAuthorityPorts

func setup(ctx: Dictionary) -> Dictionary:
	_memory = TavernLocalMemory.new()
	_policy = TavernAuthorityPolicy.new()
	_policy.setup({"memory": _memory})

	_director = TavernSanctionDirector.new()
	_director.setup({
		"get_keeper": ctx.get("get_keeper", Callable()),
		"get_sentinels": ctx.get("get_sentinels", Callable()),
		"memory_deny_service": Callable(_memory, "deny_service_for"),
		"tavern_site_id": "tavern_main",
	})

	_presence_monitor = TavernPresenceMonitor.new()
	_presence_monitor.setup({
		"incident_reporter": ctx.get("incident_reporter", Callable()),
		"get_candidates": ctx.get("get_presence_candidates", Callable()),
		"interior_bounds": ctx.get("get_tavern_inner_bounds_world", Callable()),
	})

	_garrison_monitor = TavernGarrisonMonitor.new()
	_garrison_monitor.setup({
		"get_sentinels": ctx.get("get_sentinels", Callable()),
		"tavern_site_id": "tavern_main",
	})

	_brawl = TavernPerimeterBrawl.new()
	_brawl.setup({
		"get_sentinels": ctx.get("get_sentinels", Callable()),
		"get_nearby_enemies": ctx.get("get_nearby_enemies", Callable()),
		"get_tavern_center": ctx.get("get_tavern_center", Callable()),
	})

	_orchestrator = TavernAuthorityOrchestrator.new()
	_orchestrator.setup({
		"memory": _memory,
		"policy": _policy,
		"director": _director,
		"presence_monitor": _presence_monitor,
		"get_tavern_inner_bounds_world": ctx.get("get_tavern_inner_bounds_world", Callable()),
		"get_tavern_sentinels": ctx.get("get_sentinels", Callable()),
		"find_nearest_player": ctx.get("find_nearest_player", Callable()),
	})

	_ports = LocalSocialAuthorityPorts.new()
	_ports.setup({
		"local_authority_policy": Callable(_policy, "evaluate"),
		"local_memory_source": Callable(_memory, "get_snapshot"),
		"local_sanction_director": Callable(_director, "dispatch"),
	})

	return {
		"memory": _memory,
		"policy": _policy,
		"director": _director,
		"presence_monitor": _presence_monitor,
		"garrison_monitor": _garrison_monitor,
		"brawl": _brawl,
		"orchestrator": _orchestrator,
		"local_social_ports": _ports,
	}

func get_debug_snapshot() -> Dictionary:
	return {
		"ready": _orchestrator != null,
	}
