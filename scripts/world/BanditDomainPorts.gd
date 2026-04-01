extends RefCounted
class_name BanditDomainPorts

var _bandit_group_memory: Object = null
var _run_clock: Object = null
var _world_save: Object = null
var _faction_hostility: Object = null
var _extortion_queue: Object = null
var _debug: Object = null

func setup(ctx: Dictionary = {}) -> void:
	_bandit_group_memory = ctx.get("bandit_group_memory", BanditGroupMemory)
	_run_clock = ctx.get("run_clock", RunClock)
	_world_save = ctx.get("world_save", WorldSave)
	_faction_hostility = ctx.get("faction_hostility", FactionHostilityManager)
	_extortion_queue = ctx.get("extortion_queue", ExtortionQueue)
	_debug = ctx.get("debug", Debug)

func bandit_group_memory() -> Object:
	return _bandit_group_memory

func run_clock() -> Object:
	return _run_clock

func world_save() -> Object:
	return _world_save

func faction_hostility() -> Object:
	return _faction_hostility

func extortion_queue() -> Object:
	return _extortion_queue

func debug_log(channel: String, message: String) -> void:
	if _debug != null and _debug.has_method("log"):
		_debug.call("log", channel, message)

func now() -> float:
	if _run_clock != null and _run_clock.has_method("now"):
		return float(_run_clock.call("now"))
	return 0.0

func capture_input_context(extra: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {
		"now": now(),
	}
	for key in extra.keys():
		ctx[key] = extra[key]
	return ctx
