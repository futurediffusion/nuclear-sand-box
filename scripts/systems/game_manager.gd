extends Node

signal player_died
signal player_healed(amount: int)
signal zone_entered(zone_name: String)

var current_wave: int = 0
var gold: int = 0

func _ready() -> void:
	Seed.initialize_run_seed()
	Debug.log("boot", "RUN_SEED=%d use_debug_seed=%s" % [Seed.run_seed, str(Seed.use_debug_seed)])
