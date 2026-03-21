class_name ExtortionUIAdapter
extends Node

## Responsabilidad única: presentación del modal de extorsión.
## Muestra la burbuja de elección, la cierra, y emite choice_resolved
## cuando el jugador elige o el modal se descarta externamente.
##
## Nunca toca lógica de juego — solo UI y señales.

## option 1/2/3 = elección confirmada. option 0 = descarte externo → el flow lo mapea a warn.
signal choice_resolved(option: int, gid: String)

# ---------------------------------------------------------------------------
# Frases por causa dominante — 3 variantes por razón para evitar repetición
# ---------------------------------------------------------------------------
const REASON_PHRASES: Dictionary = {
	"base_growth": [
		"Tu base está creciendo demasiado cerca de nuestro territorio.",
		"Cada estructura que levantas aquí nos cuesta.\nEso se paga.",
		"Construir tan cerca tiene un precio.\nLo llamamos impuesto de vecindario.",
		"Mucho progreso para alguien que no ha pedido permiso.",
		"Esa base tuya ya se ve desde donde vivimos.\nNo nos gusta lo que vemos.",
		"Sigues expandiéndote. Nosotros también tenemos que crecer.\nEmpezando por tus bolsillos.",
		"Pones paredes, ponemos peajes.\nAsí funciona esto.",
		"Cada ladrillo que pones en nuestra zona tiene precio.\nHoy te presentamos la factura.",
		"Qué bonita construcción.\nPena que esté en el lugar equivocado.",
	],
	"mining": [
		"Estás sacando demasiado de nuestro territorio.",
		"Ese mineral tiene dueño.\nNosotros.",
		"Llevas días llenándote los bolsillos con lo que es nuestro.",
		"Mucho mineral para alguien que no paga renta.",
		"El suelo es nuestro. Lo que sale de él, también.",
		"Pico, sudor y beneficio.\nNosotros queremos nuestra parte del beneficio.",
		"Sabemos cuánto llevas sacado.\nEs hora de compartir.",
		"Minas como si nadie te estuviera mirando.\nTe estábamos mirando.",
		"Todo ese esfuerzo y ni un perro para nosotros.\nEso se corrige hoy.",
	],
	"returning_payer": [
		"Ya pagaste antes.\nSabemos que tienes con qué.",
		"Eres cliente frecuente.\nEso tiene ventajas... y obligaciones.",
		"Conocemos tus hábitos.\nY tus bolsillos.",
		"Pagaste la última vez sin hacernos perder el tiempo.\nApreciamos eso.\nSigue así.",
		"Un pagador confiable.\nRaro encontrar uno.\nNo nos decepciones ahora.",
		"Volvemos porque sabemos que eres razonable.\n¿Seguimos siendo razonables?",
		"La última vez fue fácil para todos.\nHagámoslo fácil otra vez.",
		"Tu historial habla bien de ti.\nMantén esa reputación.",
		"Sabemos que puedes pagar.\nLo hiciste antes.\nNo finjas que no.",
	],
	"visible_wealth": [
		"Tienes taller, tienes recursos.\nNosotros, necesidades. Es simple.",
		"Vienes acumulando demasiado sin pagar tu parte.",
		"Todo ese trabajo tiene que ser rentable para alguien.\nHoy somos nosotros.",
		"Mucho equipo. Mucho material.\nAlguien tiene que cobrar por la tranquilidad.",
		"Se nota que te ha ido bien.\nNos alegra.\nAhora comparte un poco.",
		"Tanto esfuerzo acumulando cosas.\nSería una lástima que pasara algo.",
		"Lo que tienes lo construiste en nuestra zona.\nNosotros también tenemos gastos.",
		"No pagaste en su momento.\nEl interés se acumuló.\nAquí está la cuenta.",
		"Tanta riqueza y tan poco agradecimiento.\nRemediemos eso.",
	],
	"territorial": [
		"Te dejamos pasar una vez.\nEsta vez cobras peaje.",
		"Este territorio no es gratis.\nNunca lo fue.",
		"Otro día rondando por aquí.\nOtro día que se paga.",
		"No pongas esa cara. Esto es solo negocios.",
		"Pagas y nos olvidamos de ti.\nPor un tiempo.",
		"Pasa mucha gente por aquí sin pagar.\nTú no vas a ser uno de ellos.",
		"Zona nuestra, reglas nuestras.\nLa primera regla: se paga.",
		"Podríamos haberte encontrado antes.\nDa gracias que te encontramos ahora.",
		"No te conocemos de nada.\nY ya nos debes algo.",
		"Cada vez que pises por aquí sin pagar, el precio sube.\nHoy todavía es barato.",
	],
}

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

func show_choice(gid: String, pay_amount: int = 0, is_minimum: bool = false,
		reason: String = "territorial") -> void:
	if _bubble_manager == null:
		return
	var bubble: ExtortionChoiceBubble = CHOICE_SCENE.instantiate() as ExtortionChoiceBubble
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var visual:  Vector2 = bubble.custom_minimum_size * bubble.scale
	bubble.position = (vp_size - visual) * 0.5
	var phrases: Array = REASON_PHRASES.get(reason, REASON_PHRASES["territorial"]) as Array
	var main_text: String = phrases[randi() % phrases.size()] as String
	bubble.set_main_text(main_text)
	bubble.set_pay_amount(pay_amount, is_minimum)
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
