extends Control
class_name ExtortionChoiceBubble

# Emitted when the player picks an option. Caller must connect before showing.
signal choice_made(option: int)

@onready var _label: Label  = $Content/VBox/MainLabel
@onready var _btn1:  Button = $Content/VBox/Btn1
@onready var _btn2:  Button = $Content/VBox/Btn2
@onready var _btn3:  Button = $Content/VBox/Btn3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_btn1.pressed.connect(func(): _emit(1))
	_btn2.pressed.connect(func(): _emit(2))
	_btn3.pressed.connect(func(): _emit(3))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _emit(1)
			KEY_2: _emit(2)
			KEY_3: _emit(3)


func set_main_text(text: String) -> void:
	_label.text = text


func _emit(option: int) -> void:
	choice_made.emit(option)
