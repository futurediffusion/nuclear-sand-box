extends Node
class_name BanditExtortionDirector

## Coordinador fino. No contiene lógica de juego propia.
## Instancia y conecta ExtortionFlow (orquestación) y ExtortionUIAdapter (presentación).
##
## Persistencia: los jobs activos son estado efímero de runtime — no se serializan.
## Si el chunk se descarga o el mundo se reconstruye, el encuentro se descarta
## y el grupo puede generar un nuevo intento desde ExtortionQueue.

const ExtortionFlowScript      := preload("res://scripts/world/ExtortionFlow.gd")
const ExtortionUIAdapterScript := preload("res://scripts/world/ExtortionUIAdapter.gd")
const BanditDomainPortsScript := preload("res://scripts/world/BanditDomainPorts.gd")

var _flow: ExtortionFlow      = null
var _ui:   ExtortionUIAdapter = null
var _domain_ports: BanditDomainPorts = null


func setup(ctx: Dictionary) -> void:
	_domain_ports = ctx.get("domain_ports") as BanditDomainPorts
	if _domain_ports == null:
		_domain_ports = BanditDomainPortsScript.new() as BanditDomainPorts
		_domain_ports.setup()
	_ui = ExtortionUIAdapterScript.new() as ExtortionUIAdapter
	_ui.name = "ExtortionUIAdapter"
	add_child(_ui)
	_ui.setup(ctx.get("speech_bubble_manager") as WorldSpeechBubbleManager)

	var flow_ctx: Dictionary = ctx.duplicate()
	flow_ctx["domain_ports"] = _domain_ports
	flow_ctx["show_choice_ui"]  = Callable(_ui, "show_choice")
	flow_ctx["close_choice_ui"] = Callable(_ui, "close_choice_for_group")

	_flow = ExtortionFlowScript.new() as ExtortionFlow
	_flow.name = "ExtortionFlow"
	add_child(_flow)
	_flow.setup(flow_ctx)

	_ui.choice_resolved.connect(_flow.on_choice_resolved)


func process_extortion(now: float) -> void:
	if _flow != null:
		_flow.process_flow(now)


func apply_extortion_movement(friction_compensation: float) -> void:
	if _flow != null:
		_flow.apply_movement(friction_compensation)
