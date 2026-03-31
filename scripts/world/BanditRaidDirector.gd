extends Node
class_name BanditRaidDirector

## Coordinador de raids. No contiene lógica de juego propia.
## Instancia y conecta RaidFlow.
##
## Paralelo a BanditExtortionDirector pero para can_raid_base (nivel 10).

const RaidFlowScript := preload("res://scripts/world/RaidFlow.gd")

var _flow: RaidFlow = null


func setup(ctx: Dictionary) -> void:
	if _flow != null and is_instance_valid(_flow):
		_flow.queue_free()
	_flow = RaidFlowScript.new() as RaidFlow
	_flow.name = "RaidFlow"
	add_child(_flow)
	_flow.setup(ctx)


func set_wall_query(cb: Callable) -> void:
	if _flow != null:
		_flow.set_wall_query(cb)

func set_workbench_query(cb: Callable) -> void:
	if _flow != null:
		_flow.set_workbench_query(cb)

func set_storage_query(cb: Callable) -> void:
	if _flow != null:
		_flow.set_storage_query(cb)


func set_placeable_query(cb: Callable) -> void:
	if _flow != null:
		_flow.set_placeable_query(cb)


func process_raid() -> void:
	if _flow != null:
		_flow.process_flow()
