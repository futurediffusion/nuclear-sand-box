extends Node2D

func _ready() -> void:
	# NO forzar mouse_mode aquí.
	pass

func _process(_delta: float) -> void:
	if visible:
		global_position = get_global_mouse_position()
