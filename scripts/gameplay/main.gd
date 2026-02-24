extends Node2D

@export var world_data: WorldData
@export var world_map_size: Vector2i = Vector2i(128, 128)
@export var default_tavern_position: Vector2i = Vector2i.ZERO

@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var retry_button: Button = $UI/GameOverPanel/VBoxContainer/RetryButton
@onready var inv_ui: InventoryUI = $UI/InventoryUI
func _ready() -> void:
	_ensure_world_data()
	game_over_panel.visible = false
	retry_button.pressed.connect(_on_retry_pressed)
	if not GameManager.player_died.is_connected(_on_player_died_from_manager):
		GameManager.player_died.connect(_on_player_died_from_manager)

func _on_player_died_from_manager() -> void:
	game_over_panel.visible = true
	get_tree().paused = true  # congela todo (enemigos, spawner, etc.)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# Compatibilidad temporal para llamadas legacy.
func on_player_died() -> void:
	_on_player_died_from_manager()

func _on_retry_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _ensure_world_data() -> void:
	if world_data == null:
		world_data = WorldData.new()

	world_data.setup(world_map_size, default_tavern_position)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		inv_ui.toggle()
