extends Node2D

const CommandSystemScript = preload("res://scripts/systems/CommandSystem.gd")

@export var world_data: WorldData
@export var world_map_size: Vector2i = Vector2i(256, 256)
@export var default_tavern_position: Vector2i = Vector2i.ZERO

@export_group("Balance Settings")
@export var balance_config: BalanceConfig

@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var retry_button: Button = $UI/GameOverPanel/VBoxContainer/RetryButton
@onready var inv_menu = $UI/PlayerInventoryMenu
@onready var player: Node = $Player
@onready var world: Node2D = $World
@onready var warmup_manager: Node = $WarmupManager
@onready var sound_panel: Node = $SoundPanel
@onready var ui_layer: CanvasLayer = $UI
@export var debug_input_logs: bool = false

var _command_system: CommandSystem = null


func _enter_tree() -> void:
	# Register as early as possible so child _ready() calls can resolve SoundPanel.
	if AudioSystem != null and AudioSystem.has_method("register_sound_panel"):
		AudioSystem.register_sound_panel(get_node_or_null("SoundPanel"))


func _ready() -> void:
	Debug.log("boot", "Main._ready begin")
	if balance_config == null:
		balance_config = BalanceConfig.new()
	GameManager.configure(balance_config)
	_remap_inventory_key_to_tab()
	if AudioSystem != null and AudioSystem.has_method("register_sound_panel"):
		AudioSystem.register_sound_panel(sound_panel)
	_ensure_world_data()
	if warmup_manager != null and warmup_manager.has_method("run_warmup"):
		await warmup_manager.run_warmup()
	if PartyControlManager != null:
		PartyControlManager.set_controlled_actor(player)
	game_over_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	game_over_panel.visible = false
	retry_button.pressed.connect(_on_retry_pressed)
	if not GameManager.player_died.is_connected(_on_player_died_from_manager):
		GameManager.player_died.connect(_on_player_died_from_manager)

	_command_system = CommandSystemScript.new()
	_command_system.name = "CommandSystem"
	add_child(_command_system)
	_command_system.setup(player, world, ui_layer)

	get_tree().process_frame.connect(_boot_frame_ping, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	if AudioSystem != null and AudioSystem.has_method("register_sound_panel"):
		AudioSystem.register_sound_panel(null)


func _on_player_died_from_manager() -> void:
	game_over_panel.visible = true
	get_tree().paused = true
	UiManager.open_ui("game_over")


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


func _remap_inventory_key_to_tab() -> void:
	if not InputMap.has_action("inventory"):
		return
	for event_variant in InputMap.action_get_events("inventory"):
		if event_variant is InputEventKey:
			InputMap.action_erase_event("inventory", event_variant)
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	InputMap.action_add_event("inventory", tab_event)


func _input(event: InputEvent) -> void:
	if debug_input_logs and event is InputEventMouseButton:
		print("[INPUT][_input] ev=", event, " mode=", Input.get_mouse_mode(), " pos=", get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if debug_input_logs and event is InputEventMouseButton:
		print("[INPUT][_unhandled_input] ev=", event, " mode=", Input.get_mouse_mode(), " pos=", get_viewport().get_mouse_position())

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if _command_system != null and _command_system.handle_key(key_event):
			get_viewport().set_input_as_handled()
			return

	if _command_system != null and _command_system.is_open():
		if event.is_action_pressed("inventory"):
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("inventory"):
		if debug_input_logs:
			print("[INPUT] inventory toggle requested mode_before=", Input.get_mouse_mode(), " pos=", get_viewport().get_mouse_position())
		inv_menu.toggle()
		if debug_input_logs:
			print("[INPUT] inventory toggled mode_after=", Input.get_mouse_mode(), " menu_visible=", inv_menu.visible)


func _boot_frame_ping() -> void:
	Debug.log("boot", "First frame reached")
