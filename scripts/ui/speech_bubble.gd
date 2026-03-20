extends Control
class_name SpeechBubble

## Reusable speech bubble backed by a NinePatchRect.
## Call set_text() to update content — the bubble resizes height automatically.
##
## Layout contract (set in .tscn):
##   BubbleBG  — NinePatchRect, full-rect anchors, visual frame only
##   Content   — MarginContainer, full-rect anchors, drives minimum size
##   Label     — child of Content, autowrap on, text_overrun_behavior = 0

## Width of the text column inside the bubble.
## Bubble total width = max_text_width + left/right Content margins.
@export var max_text_width: float = 280.0

@onready var _content: MarginContainer = $Content
@onready var _label:   Label           = $Content/Label


func _ready() -> void:
	_apply_width()


## Set text and resize the bubble height to fit the wrapped content.
func set_text(text: String) -> void:
	_label.text = text
	_fit()


## Return currently displayed text.
func get_text() -> String:
	return _label.text


# ── internal ──────────────────────────────────────────────────────────────────

func _apply_width() -> void:
	var w := max_text_width + _h_margin()
	size.x                = w
	custom_minimum_size.x = w


func _fit() -> void:
	_apply_width()
	# One layout frame lets Godot wrap the label and compute Content height.
	await get_tree().process_frame
	var h    := maxf(_content.size.y, custom_minimum_size.y)
	var new_size := Vector2(size.x, h)
	size                = new_size
	custom_minimum_size = new_size


# Sum of left + right margin overrides on Content.
func _h_margin() -> float:
	return float(
		_content.get_theme_constant("margin_left") +
		_content.get_theme_constant("margin_right")
	)
