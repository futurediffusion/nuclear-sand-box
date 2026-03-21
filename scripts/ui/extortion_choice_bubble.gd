extends Control
class_name ExtortionChoiceBubble

# Emitted when the player picks an option. Caller must connect before showing.
signal choice_made(option: int)

@onready var _label: Label  = $Content/VBox/MainLabel
@onready var _btn1:  Button = $Content/VBox/Btn1
@onready var _btn2:  Button = $Content/VBox/Btn2
@onready var _btn3:  Button = $Content/VBox/Btn3

var _pending_text: String = ""
var _pending_pay_amount: int = 0
var _pay_is_minimum: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_btn1.pressed.connect(func(): _emit(1))
	_btn2.pressed.connect(func(): _emit(2))
	_btn3.pressed.connect(func(): _emit(3))
	if _pending_text != "":
		_label.text = _pending_text
	_update_pay_button()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _emit(1)
			KEY_2: _emit(2)
			KEY_3: _emit(3)


func set_main_text(text: String) -> void:
	_pending_text = text
	if _label != null:
		_label.text = text


func set_pay_amount(amount: int, is_minimum: bool = false) -> void:
	_pending_pay_amount = amount
	_pay_is_minimum     = is_minimum
	if _btn1 != null:
		_update_pay_button()


func _update_pay_button() -> void:
	if _btn1 == null:
		return
	_btn1.text = "[1]  Pagar  (%d dogs)" % _pending_pay_amount
	if _pay_is_minimum:
		_btn1.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	else:
		_btn1.remove_theme_color_override("font_color")


func _emit(option: int) -> void:
	choice_made.emit(option)
