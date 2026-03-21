class_name ExtortionUIAdapter
extends Node

## Responsabilidad única: presentación del modal de extorsión.
## Muestra la burbuja de elección, la cierra, y emite choice_resolved
## cuando el jugador elige o el modal se descarta externamente.
##
## Nunca toca lógica de juego — solo UI y señales.

## option 1/2/3 = elección confirmada. option 0 = descarte externo → el flow lo mapea a warn.
signal choice_resolved(option: int, gid: String)

const CHOICE_SCENE: PackedScene = preload("res://scenes/ui/extortion_choice_bubble.tscn")

var _bubble_manager: WorldSpeechBubbleManager = null
var _choice_node:           ExtortionChoiceBubble = null
var _choice_gid:            String                = ""
var _closing_from_selection: bool                 = false


func setup(bubble_manager: WorldSpeechBubbleManager) -> void:
	_bubble_manager = bubble_manager
	if not ModalWorldUIController.modal_closed.is_connected(_on_modal_closed):
		ModalWorldUIController.modal_closed.connect(_on_modal_closed)


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

func show_choice(gid: String) -> void:
	if _bubble_manager == null:
		return
	var bubble: ExtortionChoiceBubble = CHOICE_SCENE.instantiate() as ExtortionChoiceBubble
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var visual:  Vector2 = bubble.custom_minimum_size * bubble.scale
	bubble.position = (vp_size - visual) * 0.5
	bubble.set_main_text("¿Entonces qué?\n¿Pagas o prefieres problemas?")
	bubble.choice_made.connect(func(option: int): _on_raw_choice(option, gid), CONNECT_ONE_SHOT)
	_choice_gid  = gid
	_choice_node = ModalWorldUIController.show_modal(
		bubble, _bubble_manager, "extortion_choice"
	) as ExtortionChoiceBubble
	Debug.log("extortion", "[EXTORT UI] choice bubble shown group=%s" % gid)


func close_choice_for_group(gid: String) -> void:
	if _choice_gid != gid or _choice_node == null:
		return
	var node        := _choice_node
	_choice_node     = null
	_choice_gid      = ""
	_closing_from_selection = false
	ModalWorldUIController.close_modal(node)


# ---------------------------------------------------------------------------
# Handlers internos
# ---------------------------------------------------------------------------

func _on_raw_choice(option: int, gid: String) -> void:
	_closing_from_selection = true
	ModalWorldUIController.close_modal(_choice_node)
	_closing_from_selection = false
	_choice_node = null
	_choice_gid  = ""
	choice_resolved.emit(option, gid)
	Debug.log("extortion", "[EXTORT UI] choice made option=%d group=%s" % [option, gid])


func _on_modal_closed(reason: String) -> void:
	if reason != "extortion_choice":
		return
	var gid            := _choice_gid
	var from_selection := _closing_from_selection
	_choice_node            = null
	_choice_gid             = ""
	_closing_from_selection = false

	if from_selection:
		Debug.log("extortion", "[EXTORT UI] modal closed from selection group=%s" % gid)
		return
	if gid == "":
		return
	Debug.log("extortion", "[EXTORT UI] modal dismissed externally — escalating warn group=%s" % gid)
	choice_resolved.emit(0, gid)  # 0 → ExtortionFlow lo trata como warn
