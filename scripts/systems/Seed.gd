extends Node

@export var use_debug_seed := true
@export var debug_seed := 123456

var run_seed := 0

func initialize_run_seed() -> void:
	if run_seed != 0:
		return

	if use_debug_seed:
		run_seed = debug_seed
	else:
		run_seed = int(Time.get_unix_time_from_system()) % 2147483647
		if run_seed <= 0:
			run_seed = 1

	seed(run_seed)

func chunk_seed(cx: int, cy: int) -> int:
	var mix: int = int(run_seed)
	mix = int((mix ^ (cx * 73856093) ^ (cy * 19349663)) & 0x7fffffff)
	if mix <= 0:
		mix = 1
	return mix
