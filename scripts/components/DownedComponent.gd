extends Node
class_name DownedComponent

signal entered_downed
signal revived
signal died_final

@export var downed_duration_seconds: float = 10.0
@export var downed_survival_chance: float = 0.5
@export var downed_revive_hp: int = 1
@export var grace_period: float = 1.0

var is_downed: bool = false
var downed_resolve_at: float = 0.0
var downed_at: float = 0.0

var _progress_bar: TextureProgressBar
var _owner_character: CharacterBody2D

func _ready() -> void:
	_owner_character = get_parent() as CharacterBody2D
	_setup_ui()

func _process(_delta: float) -> void:
	if not is_downed:
		return

	var now := RunClock.now()
	var remaining := downed_resolve_at - now

	if _progress_bar:
		var total := maxf(downed_duration_seconds, 0.001)
		var elapsed := total - remaining
		_progress_bar.value = clampf((elapsed / total) * 100.0, 0.0, 100.0)
		_progress_bar.visible = true

	if remaining <= 0.0:
		_resolve_downed()

func enter_downed(resolve_at: float = -1.0, entered_at: float = -1.0) -> void:
	if is_downed:
		return

	is_downed = true
	downed_at = RunClock.now() if entered_at < 0.0 else entered_at

	if resolve_at < 0.0:
		downed_resolve_at = downed_at + downed_duration_seconds
	else:
		downed_resolve_at = resolve_at

	if _progress_bar:
		_progress_bar.visible = true

	entered_downed.emit()

func revive() -> void:
	if not is_downed:
		return

	is_downed = false
	if _progress_bar:
		_progress_bar.visible = false

	revived.emit()

func die_final() -> void:
	if not is_downed:
		return

	is_downed = false
	if _progress_bar:
		_progress_bar.visible = false

	died_final.emit()

func reset() -> void:
	is_downed = false
	downed_at = 0.0
	downed_resolve_at = 0.0
	if _progress_bar:
		_progress_bar.visible = false

func _resolve_downed() -> void:
	if randf() < downed_survival_chance:
		revive()
	else:
		die_final()

func _setup_ui() -> void:
	_progress_bar = TextureProgressBar.new()
	_progress_bar.name = "DownedProgressBar"

	# Reutilizar texturas de stamina
	_progress_bar.texture_under = load("res://art/sprites/stamina-under.png")
	_progress_bar.texture_progress = load("res://art/sprites/stamina-progress.png")

	# Tintar para diferenciar de stamina (ej: amarillo o naranja)
	_progress_bar.tint_progress = Color(1.0, 0.8, 0.2)

	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.step = 0.1
	_progress_bar.visible = false
	_progress_bar.z_index = 100

	# Posicionamiento simple world-space debajo del personaje
	var w := float(_progress_bar.texture_under.get_width())
	var h := float(_progress_bar.texture_under.get_height())
	var bar_scale := 0.3
	_progress_bar.scale = Vector2(bar_scale, bar_scale)
	_progress_bar.custom_minimum_size = Vector2(w, h)
	_progress_bar.position = Vector2(-w * bar_scale * 0.5, 10.0)

	if _owner_character != null:
		_owner_character.add_child(_progress_bar)
	else:
		add_child(_progress_bar)

func can_take_finishing_blow() -> bool:
	if not is_downed:
		return true
	return RunClock.now() - downed_at >= grace_period

func get_save_data() -> Dictionary:
	return {
		"is_downed": is_downed,
		"downed_at": downed_at,
		"downed_resolve_at": downed_resolve_at
	}

func load_save_data(data: Dictionary) -> void:
	if data.get("is_downed", false):
		var saved_downed_at := float(data.get("downed_at", RunClock.now()))
		var saved_resolve_at := float(data.get("downed_resolve_at", saved_downed_at + downed_duration_seconds))
		enter_downed(saved_resolve_at, saved_downed_at)

		if downed_resolve_at <= RunClock.now():
			call_deferred("_resolve_downed")
	else:
		reset()
