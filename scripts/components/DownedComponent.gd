extends Node2D
class_name DownedComponent

signal became_downed
signal recovered
signal died_final

@export var downed_duration_seconds: float = 10.0
@export var downed_survival_chance: float = 0.5
@export var downed_revive_hp: int = 1

var is_downed: bool = false
var resolve_at_timestamp: float = 0.0

var recovery_bar: TextureProgressBar

func _ready() -> void:
	if not recovery_bar:
		_create_default_bar()

	if recovery_bar:
		recovery_bar.visible = false
		recovery_bar.min_value = 0
		recovery_bar.max_value = 100
		recovery_bar.value = 0

func _create_default_bar() -> void:
	recovery_bar = TextureProgressBar.new()
	recovery_bar.name = "RecoveryBar"

	# Try to load existing stamina textures
	var under = load("res://art/sprites/stamina-under.png")
	var progress = load("res://art/sprites/stamina-progress.png")

	if under: recovery_bar.texture_under = under
	if progress: recovery_bar.texture_progress = progress

	# Minimalist style: small, centered below
	recovery_bar.size = Vector2(32, 4)
	recovery_bar.position = Vector2(-16, 8) # Adjust based on character size
	recovery_bar.nine_patch_stretch = true
	recovery_bar.stretch_margin_left = 1
	recovery_bar.stretch_margin_right = 1
	recovery_bar.stretch_margin_top = 1
	recovery_bar.stretch_margin_bottom = 1

	# Tint it differently (e.g., yellow/orange for recovery)
	recovery_bar.tint_progress = Color(1.0, 0.8, 0.2, 1.0)

	add_child(recovery_bar)

func _process(_delta: float) -> void:
	if not is_downed:
		return

	var now := Time.get_unix_time_from_system()
	var remaining := resolve_at_timestamp - now

	if remaining <= 0:
		_resolve_downed()
	else:
		_update_ui(remaining)

func enter_downed(p_resolve_at: float = -1.0) -> void:
	if is_downed:
		return

	is_downed = true
	if p_resolve_at > 0:
		resolve_at_timestamp = p_resolve_at
	else:
		resolve_at_timestamp = Time.get_unix_time_from_system() + downed_duration_seconds

	if recovery_bar:
		recovery_bar.visible = true

	became_downed.emit()

func _update_ui(remaining: float) -> void:
	if not recovery_bar:
		return

	var elapsed := downed_duration_seconds - remaining
	var progress := (elapsed / downed_duration_seconds) * 100.0
	recovery_bar.value = progress

func _resolve_downed() -> void:
	if not is_downed:
		return

	is_downed = false
	if recovery_bar:
		recovery_bar.visible = false

	if randf() < downed_survival_chance:
		recovered.emit()
	else:
		died_final.emit()

func cancel_and_die() -> void:
	if not is_downed:
		return
	is_downed = false
	if recovery_bar:
		recovery_bar.visible = false
	died_final.emit()

func setup_ui(p_bar: TextureProgressBar) -> void:
	recovery_bar = p_bar
	if recovery_bar:
		recovery_bar.visible = is_downed
