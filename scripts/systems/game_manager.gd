extends Node

enum SessionPhase { EXPLORE, RETURNING, RESTING, GAME_OVER }

@warning_ignore("unused_signal")
signal player_died
@warning_ignore("unused_signal")
signal player_healed(amount: int)
@warning_ignore("unused_signal")
signal zone_entered(zone_name: String)
@warning_ignore("unused_signal")
signal phase_changed(new_phase: SessionPhase)
signal threat_level_changed(new_level: int)

var session_phase: SessionPhase = SessionPhase.EXPLORE

var enemies_killed: int = 0
var resources_gathered: int = 0
var chunks_explored: int = 0
var session_time_seconds: float = 0.0
var threat_level: int = 0

var _balance_config: BalanceConfig = null

func configure(settings: BalanceConfig) -> void:
	if settings == null:
		_balance_config = BalanceConfig.new()
	else:
		_balance_config = settings.duplicate(true) as BalanceConfig

	_balance_config.finish_off_chance_min = clampf(_balance_config.finish_off_chance_min, 0.0, 1.0)
	_balance_config.finish_off_chance_max = clampf(_balance_config.finish_off_chance_max, 0.0, 1.0)

	if _balance_config.finish_off_chance_min > _balance_config.finish_off_chance_max:
		var temp: float = _balance_config.finish_off_chance_min
		_balance_config.finish_off_chance_min = _balance_config.finish_off_chance_max
		_balance_config.finish_off_chance_max = temp

func get_keep_corpses() -> bool:
	return _balance_config.keep_corpses if _balance_config else false

func get_finish_off_chance_min() -> float:
	return _balance_config.finish_off_chance_min if _balance_config else 0.2

func get_finish_off_chance_max() -> float:
	return _balance_config.finish_off_chance_max if _balance_config else 0.4

func _ready() -> void:
	Seed.initialize_run_seed()
	Debug.log("boot", "RUN_SEED=%d use_debug_seed=%s" % [Seed.run_seed, str(Seed.use_debug_seed)])

func _process(delta: float) -> void:
	session_time_seconds += delta

func register_kill() -> void:
	enemies_killed += 1
	if enemies_killed % 5 == 0:
		_maybe_escalate_threat()

func register_resource_gathered() -> void:
	resources_gathered += 1

func register_chunk_explored() -> void:
	chunks_explored += 1

func _maybe_escalate_threat() -> void:
	threat_level += 1
	threat_level_changed.emit(threat_level)
