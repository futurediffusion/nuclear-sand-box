extends Node2D

func _ready() -> void:
	print("[MOUSE][Cursor2D] _ready mode=", Input.get_mouse_mode(), " visible=", visible)

func _process(_delta: float) -> void:
	global_position = get_global_mouse_position()
