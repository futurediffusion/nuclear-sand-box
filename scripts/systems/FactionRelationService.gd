extends Node


var _faction_hostilities: Dictionary = {}

func get_hostility_score(faction_id: String) -> float:
	return _faction_hostilities.get(faction_id, 0.0)

func get_finish_modifier(faction_id: String, hostility_finish_bonus_max: float) -> float:
	var score: float = get_hostility_score(faction_id)
	return score * hostility_finish_bonus_max
