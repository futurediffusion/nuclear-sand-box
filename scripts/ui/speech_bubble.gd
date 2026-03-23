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
@export var max_text_width: float = 340.0

@onready var _content: MarginContainer = $Content
@onready var _label:   Label           = $Content/Label

# Captured in _ready() from the tscn values; used as minimum on every resize.
var _size_floor: Vector2
var _autowrap:   TextServer.AutowrapMode


func _ready() -> void:
	_size_floor = custom_minimum_size
	_autowrap   = _label.autowrap_mode
	_apply_width(max_text_width + _h_margin())


## Set text and resize the bubble height to fit the wrapped content.
func set_text(text: String) -> void:
	_label.text = text
	_fit()


## Return currently displayed text.
func get_text() -> String:
	return _label.text


# ── internal ──────────────────────────────────────────────────────────────────

func _apply_width(w: float) -> void:
	size.x                = w
	custom_minimum_size.x = w


func _fit() -> void:
	# ── Reset to floor so nothing carries over from the previous phrase ──────
	size                = _size_floor
	custom_minimum_size = _size_floor

	# ── Frame 1: measure natural (unwrapped) text width ──────────────────────
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_apply_width(max_text_width + _h_margin())   # give it room so it doesn't clip
	await get_tree().process_frame

	# get_combined_minimum_size() on Label with no-wrap = natural single-line width.
	var natural_text_w := _label.get_combined_minimum_size().x
	var h_pad          := _h_margin()
	var min_text_w     := maxf(_size_floor.x - h_pad, 0.0)
	var text_col_w     := clampf(natural_text_w, min_text_w, max_text_width)
	var final_w        := text_col_w + h_pad

	# ── Frame 2: apply final width, re-enable wrap, measure height ────────────
	_label.autowrap_mode = _autowrap
	_apply_width(final_w)
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return

	var lines        := _label.get_line_count()
	var line_h       := float(_label.get_line_height())
	var line_spacing := float(_label.get_theme_constant("line_spacing"))
	var text_h       := lines * line_h + maxf(0.0, float(lines - 1)) * line_spacing
	var v_pad        := float(
		_content.get_theme_constant("margin_top") +
		_content.get_theme_constant("margin_bottom")
	)
	var final_h  := maxf(text_h + v_pad, _size_floor.y)
	var new_size := Vector2(final_w, final_h)
	size                = new_size
	custom_minimum_size = new_size


# Sum of left + right margin overrides on Content.
func _h_margin() -> float:
	return float(
		_content.get_theme_constant("margin_left") +
		_content.get_theme_constant("margin_right")
	)
