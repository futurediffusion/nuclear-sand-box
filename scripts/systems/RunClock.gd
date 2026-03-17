extends Node

var time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	time += delta

func reset() -> void:
	time = 0.0

func get_save_data() -> Dictionary:
	return {
		"time": time
	}

func load_save_data(data: Dictionary) -> void:
	time = data.get("time", 0.0)
