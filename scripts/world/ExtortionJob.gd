class_name ExtortionJob
extends RefCounted

## Dato puro de un trabajo de extorsión en curso.
## Sin dependencias de escena; vive y muere con el Director.

enum Phase {
	APPROACHING,
	TAUNTED,
	WAITING_CHOICE,
	WARNING_STRIKE,
	FULL_AGGRO,
	RESOLVED,
	ABORTED,
}

var group_id:        String         = ""
var leader_id:       String         = ""
var assigned_ids:    Array[String]  = []
var taunt_speaker_id: String        = ""
var phase:           Phase          = Phase.APPROACHING
## Causa dominante de esta extorsión. Usada por la UI para seleccionar el texto.
## Valores: "base_growth" | "mining" | "returning_payer" | "visible_wealth" | "territorial"
var extort_reason:   String         = "territorial"


func _init(p_group_id: String, p_leader_id: String, p_assigned_ids: Array[String]) -> void:
	group_id     = p_group_id
	leader_id    = p_leader_id
	assigned_ids = p_assigned_ids.duplicate()


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func is_finished() -> bool:
	return phase == Phase.RESOLVED or phase == Phase.ABORTED

func is_aggressive() -> bool:
	return phase == Phase.FULL_AGGRO

func needs_warning_strike() -> bool:
	return phase == Phase.WARNING_STRIKE

func is_collecting() -> bool:
	return phase == Phase.WAITING_CHOICE

func has_taunted() -> bool:
	return phase >= Phase.TAUNTED

func can_open_choice() -> bool:
	return phase == Phase.TAUNTED


# ---------------------------------------------------------------------------
# Transitions
# ---------------------------------------------------------------------------

func mark_taunted(speaker_id: String) -> void:
	taunt_speaker_id = speaker_id
	phase = Phase.TAUNTED

func mark_waiting_choice() -> void:
	phase = Phase.WAITING_CHOICE

func mark_warning_strike() -> void:
	phase = Phase.WARNING_STRIKE

func mark_full_aggro() -> void:
	phase = Phase.FULL_AGGRO

func mark_resolved() -> void:
	phase = Phase.RESOLVED

func mark_aborted() -> void:
	phase = Phase.ABORTED
