extends RefCounted
class_name TaskPlanOutputDto

static func build(order_data: Dictionary, task_payload: Dictionary) -> Dictionary:
	var out: Dictionary = order_data.duplicate(true)
	out["task"] = task_payload.duplicate(true)
	return out
