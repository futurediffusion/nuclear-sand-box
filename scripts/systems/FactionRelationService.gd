extends Node

## Compatibilidad temporal (Cut 3):
## - Este servicio deja de mantener estado propio de hostilidad.
## - Owner canónico: FactionHostilityManager.
## - Fecha objetivo de eliminación de este wrapper: 2026-06-30.
const REMOVE_AFTER: String = "2026-06-30"

signal hostility_score_changed(faction_id: String, new_points: float, new_level: int)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if FactionHostilityManager != null and FactionHostilityManager.has_signal("hostility_changed"):
		FactionHostilityManager.hostility_changed.connect(_on_hostility_changed)

func get_hostility_score(faction_id: String) -> float:
	if FactionHostilityManager == null:
		return 0.0
	return FactionHostilityManager.get_hostility_points(faction_id)

func get_finish_modifier(faction_id: String, hostility_finish_bonus_max: float) -> float:
	var score: float = get_hostility_score(faction_id)
	return score * hostility_finish_bonus_max

func _on_hostility_changed(faction_id: String, new_points: float, new_level: int) -> void:
	hostility_score_changed.emit(faction_id, new_points, new_level)
