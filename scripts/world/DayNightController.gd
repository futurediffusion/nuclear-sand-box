extends Node
class_name DayNightController

const DAY_NIGHT_SHADER: Shader = preload("res://shaders/day_night_overlay.gdshader")

@export_range(0.0, 1.0, 0.001) var dawn_start: float = 0.00
@export_range(0.0, 1.0, 0.001) var day_full: float = 0.12
@export_range(0.0, 1.0, 0.001) var dusk_start: float = 0.60
@export_range(0.0, 1.0, 0.001) var night_full: float = 0.76
@export_range(0.0, 10.0, 0.01) var smoothing_seconds: float = 1.2

var _canvas_layer: CanvasLayer
var _overlay_rect: ColorRect
var _material: ShaderMaterial
var _current_night_amount: float = 0.0
var _target_night_amount: float = 0.0

func _ready() -> void:
	initialize_overlay()

func initialize_overlay() -> void:
	if _canvas_layer == null:
		_canvas_layer = CanvasLayer.new()
		_canvas_layer.name = "DayNightCanvasLayer"
		add_child(_canvas_layer)

	if _overlay_rect == null:
		_overlay_rect = ColorRect.new()
		_overlay_rect.name = "DayNightOverlay"
		_overlay_rect.color = Color(1.0, 1.0, 1.0, 1.0)
		_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_canvas_layer.add_child(_overlay_rect)

	if _material == null:
		if _overlay_rect.material is ShaderMaterial:
			_material = _overlay_rect.material as ShaderMaterial
		else:
			_material = ShaderMaterial.new()

	if _material.shader != DAY_NIGHT_SHADER:
		_material.shader = DAY_NIGHT_SHADER

	if _overlay_rect.material != _material:
		_overlay_rect.material = _material

	_material.set_shader_parameter("night_amount", _current_night_amount)

func _compute_target_night_amount(time_in_day: float) -> float:
	var t: float = clampf(time_in_day, 0.0, 1.0)
	if t < dawn_start:
		return 1.0
	if t < day_full:
		var dawn_span: float = maxf(day_full - dawn_start, 0.0001)
		var alpha_dawn: float = clampf((t - dawn_start) / dawn_span, 0.0, 1.0)
		return 1.0 - _smoothstep(alpha_dawn)
	if t < dusk_start:
		return 0.0
	if t < night_full:
		var dusk_span: float = maxf(night_full - dusk_start, 0.0001)
		var alpha_dusk: float = clampf((t - dusk_start) / dusk_span, 0.0, 1.0)
		return _smoothstep(alpha_dusk)
	return 1.0

func _get_cycle_phase(time_in_day: float) -> String:
	var t: float = clampf(time_in_day, 0.0, 1.0)
	if t < dawn_start:
		return "night"
	if t < day_full:
		return "dawn"
	if t < dusk_start:
		return "day"
	if t < night_full:
		return "dusk"
	return "night"

func _smoothstep(x: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func update_for_time_in_day(time_in_day: float, delta: float) -> void:
	_target_night_amount = _compute_target_night_amount(time_in_day)
	if smoothing_seconds <= 0.0:
		_current_night_amount = _target_night_amount
	else:
		var step: float = delta / smoothing_seconds
		_current_night_amount = move_toward(_current_night_amount, _target_night_amount, step)
	_apply_night_amount_to_material()

func sync_to_time_in_day(time_in_day: float) -> void:
	_target_night_amount = _compute_target_night_amount(time_in_day)
	_current_night_amount = _target_night_amount
	_apply_night_amount_to_material()

func _apply_night_amount_to_material() -> void:
	if _material == null:
		initialize_overlay()
	if _material != null:
		_material.set_shader_parameter("night_amount", _current_night_amount)

func set_night_amount(value: float) -> void:
	_current_night_amount = clampf(value, 0.0, 1.0)
	_target_night_amount = _current_night_amount
	_apply_night_amount_to_material()

func get_current_night_amount() -> float:
	return _current_night_amount

func get_debug_snapshot() -> Dictionary:
	var time_in_day: float = -1.0
	if WorldTime != null and WorldTime.has_method("get_time_in_day"):
		time_in_day = WorldTime.get_time_in_day()
	return {
		"time_in_day": time_in_day,
		"cycle_phase": _get_cycle_phase(time_in_day) if time_in_day >= 0.0 else "unknown",
		"target_night_amount": _target_night_amount,
		"current_night_amount": _current_night_amount,
	}
