extends Node2D

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const COMMAND_PREFIX := "/"
const COMMAND_BAR_HEIGHT := 34.0
const COMMAND_SPAWN_MIN_DIST := 56.0
const COMMAND_SPAWN_MAX_DIST := 110.0

@export var world_data: WorldData
@export var world_map_size: Vector2i = Vector2i(256, 256)
@export var default_tavern_position: Vector2i = Vector2i.ZERO

@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var retry_button: Button = $UI/GameOverPanel/VBoxContainer/RetryButton
@onready var inv_menu = $UI/PlayerInventoryMenu
@onready var player: Node = $Player
@onready var world: Node2D = $World
@onready var warmup_manager: Node = $WarmupManager
@onready var ui_layer: CanvasLayer = $UI
@export var debug_input_logs: bool = false

var _command_container: Control
var _command_input: LineEdit
var _command_open: bool = false

func _ready() -> void:
	Debug.log("boot", "Main._ready begin")
	_ensure_world_data()
	if warmup_manager != null and warmup_manager.has_method("run_warmup"):
		await warmup_manager.run_warmup()
	if PartyControlManager != null:
		PartyControlManager.set_controlled_actor(player)
	# Permite que el menú de game over siga recibiendo input aun con el árbol pausado.
	game_over_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	game_over_panel.visible = false
	retry_button.pressed.connect(_on_retry_pressed)
	if not GameManager.player_died.is_connected(_on_player_died_from_manager):
		GameManager.player_died.connect(_on_player_died_from_manager)
	_setup_command_bar()
	get_tree().process_frame.connect(_boot_frame_ping, CONNECT_ONE_SHOT)

func _on_player_died_from_manager() -> void:
	game_over_panel.visible = true
	get_tree().paused = true  # congela todo (enemigos, spawner, etc.)
	UiManager.open_ui("game_over")

# Compatibilidad temporal para llamadas legacy.
func on_player_died() -> void:
	_on_player_died_from_manager()

func _on_retry_pressed() -> void:
	UiManager.close_ui("game_over")
	game_over_panel.visible = false
	get_tree().paused = false
	if player != null and player.has_method("respawn") and world != null and world.has_method("get_spawn_world_pos"):
		player.call("respawn", world.call("get_spawn_world_pos"))

func _ensure_world_data() -> void:
	if world_data == null:
		world_data = WorldData.new()

	world_data.setup(world_map_size, default_tavern_position)
func _input(event: InputEvent) -> void:
	if debug_input_logs and event is InputEventMouseButton:
		print("[INPUT][_input] ev=", event, " mode=", Input.get_mouse_mode(), " pos=", get_viewport().get_mouse_position())

func _unhandled_input(event: InputEvent) -> void:
	if debug_input_logs and event is InputEventMouseButton:
		print("[INPUT][_unhandled_input] ev=", event, " mode=", Input.get_mouse_mode(), " pos=", get_viewport().get_mouse_position())

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_T and not _command_open:
			_open_command_bar()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_ESCAPE and _command_open:
			_close_command_bar()
			get_viewport().set_input_as_handled()
			return

	if _command_open:
		if event.is_action_pressed("inventory"):
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("inventory"):
		if debug_input_logs:
			print("[INPUT] inventory toggle requested mode_before=", Input.get_mouse_mode(), " pos=", get_viewport().get_mouse_position())
		inv_menu.toggle()
		if debug_input_logs:
			print("[INPUT] inventory toggled mode_after=", Input.get_mouse_mode(), " menu_visible=", inv_menu.visible)

func _setup_command_bar() -> void:
	if ui_layer == null:
		return

	_command_container = Control.new()
	_command_container.name = "CommandBar"
	_command_container.visible = false
	_command_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_command_container.anchor_left = 0.0
	_command_container.anchor_top = 1.0
	_command_container.anchor_right = 1.0
	_command_container.anchor_bottom = 1.0
	_command_container.offset_left = 8.0
	_command_container.offset_top = -COMMAND_BAR_HEIGHT - 8.0
	_command_container.offset_right = -8.0
	_command_container.offset_bottom = -8.0
	ui_layer.add_child(_command_container)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.03, 0.03, 0.03, 0.9)
	_command_container.add_child(bg)

	_command_input = LineEdit.new()
	_command_input.name = "Input"
	_command_input.anchor_right = 1.0
	_command_input.anchor_bottom = 1.0
	_command_input.offset_left = 8.0
	_command_input.offset_top = 4.0
	_command_input.offset_right = -8.0
	_command_input.offset_bottom = -4.0
	_command_input.placeholder_text = "/summon enemy"
	_command_input.clear_button_enabled = true
	_command_input.text_submitted.connect(_on_command_submitted)
	_command_input.gui_input.connect(_on_command_gui_input)
	_command_container.add_child(_command_input)

func _open_command_bar() -> void:
	if _command_container == null or _command_input == null:
		return
	_command_open = true
	_command_container.visible = true
	if _command_input.text.is_empty():
		_command_input.text = COMMAND_PREFIX
	_command_input.caret_column = _command_input.text.length()
	_command_input.grab_focus()

func _close_command_bar() -> void:
	if _command_container == null or _command_input == null:
		return
	_command_open = false
	_command_container.visible = false
	_command_input.text = ""
	_command_input.release_focus()

func _on_command_gui_input(event: InputEvent) -> void:
	if not _command_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_close_command_bar()
			_command_input.accept_event()

func _on_command_submitted(raw_text: String) -> void:
	var command_text := raw_text.strip_edges()
	if command_text.is_empty():
		_close_command_bar()
		return

	_execute_command(command_text)
	_close_command_bar()

func _execute_command(command_text: String) -> void:
	if not command_text.begins_with(COMMAND_PREFIX):
		Debug.log("commands", "Comando inválido: falta '/' (%s)" % command_text)
		return

	var parts := command_text.substr(1).split(" ", false)
	if parts.size() == 0:
		return

	var base_command := String(parts[0]).to_lower()
	if base_command == "summon":
		if parts.size() >= 2 and String(parts[1]).to_lower() == "enemy":
			_summon_enemy_near_player()
			return
		Debug.log("commands", "Uso: /summon enemy")
		return

	Debug.log("commands", "Comando desconocido: %s" % base_command)

func _summon_enemy_near_player() -> void:
	if ENEMY_SCENE == null or world == null:
		Debug.log("commands", "No se pudo invocar enemy: escena o world no disponible")
		return

	var enemy := ENEMY_SCENE.instantiate()
	if enemy == null:
		Debug.log("commands", "No se pudo instanciar enemy")
		return

	var spawn_pos := _get_command_spawn_position()
	if enemy is Node2D:
		(enemy as Node2D).global_position = spawn_pos
	world.add_child(enemy)
	Debug.log("commands", "Enemy invocado en %s" % str(spawn_pos))

func _get_command_spawn_position() -> Vector2:
	if player != null and player is Node2D:
		var player_pos := (player as Node2D).global_position
		var angle := randf() * TAU
		var dist := randf_range(COMMAND_SPAWN_MIN_DIST, COMMAND_SPAWN_MAX_DIST)
		return player_pos + Vector2.RIGHT.rotated(angle) * dist
	return Vector2.ZERO

func _boot_frame_ping() -> void:
	Debug.log("boot", "First frame reached")
