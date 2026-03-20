extends Node2D

const PHRASES: Array[String] = [
	"Mira quién cree que puede pasar por aquí.",
	"Paga y quizá sigas respirando.",
	"No pongas esa cara. Esto es solo negocios.",
]

@export var phrase_duration: float = 2.5
@export var phrase_interval: float = 3.2

@onready var _actor: Node2D = $Actor

var _manager: WorldSpeechBubbleManager
var _index: int = 0


func _ready() -> void:
	# Apagar toda la IA de combate — el enemy solo existe como actor visual.
	if "suppress_ai" in _actor:
		_actor.suppress_ai = true
	var ai := _actor.get_node_or_null("AIComponent")
	if ai != null:
		ai.set_process(false)
		ai.set_physics_process(false)

	_manager = WorldSpeechBubbleManager.new()
	add_child(_manager)
	_show_next()


func _show_next() -> void:
	_manager.show_actor_bubble(_actor, PHRASES[_index], phrase_duration)
	_index = (_index + 1) % PHRASES.size()
	get_tree().create_timer(phrase_interval).timeout.connect(_show_next, CONNECT_ONE_SHOT)
