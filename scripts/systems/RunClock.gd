extends Node

var time_seconds: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	time_seconds += delta

func now() -> float:
	return time_seconds

func reset(start_time: float = 0.0) -> void:
	time_seconds = maxf(start_time, 0.0)

func get_save_data() -> Dictionary:
	return {
		"time_seconds": time_seconds
	}

func load_save_data(data: Dictionary) -> void:
	time_seconds = maxf(float(data.get("time_seconds", 0.0)), 0.0)
