extends Node

enum SessionPhase { EXPLORE, RETURNING, RESTING, GAME_OVER }

signal player_died
signal player_healed(amount: int)
signal zone_entered(zone_name: String)
signal phase_changed(new_phase: SessionPhase)
signal threat_level_changed(new_level: int)

var session_phase: SessionPhase = SessionPhase.EXPLORE

var enemies_killed: int = 0
var resources_gathered: int = 0
var chunks_explored: int = 0
var session_time_seconds: float = 0.0
var threat_level: int = 0

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
