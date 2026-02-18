extends Node2D

@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var retry_button: Button = $UI/GameOverPanel/VBoxContainer/RetryButton

func _ready() -> void:
	game_over_panel.visible = false
	retry_button.pressed.connect(_on_retry_pressed)

func on_player_died() -> void:
	game_over_panel.visible = true
	get_tree().paused = true  # congela todo (enemigos, spawner, etc.)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_retry_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
