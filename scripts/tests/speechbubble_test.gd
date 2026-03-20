extends Control

## Visual test for SpeechBubble dynamic resize.
## Press Space / Enter / click to cycle phrases.  Auto-advances every 3 s.
##
## Run standalone with F6 — no world, no NPCs, no game logic.

const AUTO_SEC: float = 3.0

const PHRASES: Array[String] = [
	"¡Hola!",
	"Tengo algo que venderte.",
	"¿Sabes que por aquí hay bandidos? Mejor ten cuidado cuando salgas.",
	"Escuché que los bandidos del norte están buscando a alguien. No preguntes demasiado si no quieres meterte en problemas.",
	"Antes vivía en la ciudad, pero los tiempos cambiaron y tuve que salir huyendo. Ahora vendo lo que puedo para sobrevivir. Si necesitas algo pregúntame, tengo lo que buscas o al menos algo parecido.",
]

@onready var _bubble:     SpeechBubble = $Bubble
@onready var _idx_label:  Label        = $IndexLabel
@onready var _hint_label: Label        = $HintLabel
@onready var _timer:      Timer        = $AutoTimer

var _index: int = 0
var _busy:  bool = false


func _ready() -> void:
	_timer.wait_time = AUTO_SEC
	_timer.timeout.connect(_advance)
	_timer.start()
	_show(_index)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT]:
				_advance()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_advance()
			get_viewport().set_input_as_handled()


func _advance() -> void:
	_index = (_index + 1) % PHRASES.size()
	_timer.start()   # reset auto-advance countdown
	_show(_index)


func _show(idx: int) -> void:
	if _busy:
		return
	_busy = true
	_idx_label.text = "Frase %d / %d" % [idx + 1, PHRASES.size()]
	_bubble.set_text(PHRASES[idx])
	# set_text awaits one layout frame internally; wait one more to read final size.
	await get_tree().process_frame
	await get_tree().process_frame
	_center_bubble()
	_busy = false


func _center_bubble() -> void:
	var vp := get_viewport_rect().size
	_bubble.position = (vp - _bubble.size) * 0.5
