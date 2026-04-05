extends Node
class_name DayNightController

const DAY_NIGHT_SHADER: Shader = preload("res://shaders/day_night_overlay.gdshader")

var _canvas_layer: CanvasLayer
var _overlay_rect: ColorRect
var _material: ShaderMaterial
var _current_night_amount: float = 0.0

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

func set_night_amount(value: float) -> void:
	_current_night_amount = clampf(value, 0.0, 1.0)
	if _material == null:
		initialize_overlay()
	if _material != null:
		_material.set_shader_parameter("night_amount", _current_night_amount)

func get_current_night_amount() -> float:
	return _current_night_amount
