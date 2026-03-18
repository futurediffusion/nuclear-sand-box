extends Node
class_name DownedComponent

signal entered_downed
signal revived
signal died_final

@export var downed_duration_seconds: float = 10.0
@export var downed_survival_chance: float = 0.5
@export var downed_revive_hp: int = 1
@export var grace_period: float = 1.0

var is_downed: bool = false
var downed_resolve_at: float = 0.0
var downed_at: float = 0.0

func _process(_delta: float) -> void:
	if not is_downed:
		return

	var now := RunClock.now()
	var remaining := downed_resolve_at - now

	if remaining <= 0.0:
		_resolve_downed()

func get_remaining_seconds() -> float:
	if not is_downed:
		return 0.0
	return maxf(0.0, downed_resolve_at - RunClock.now())

func get_progress_ratio() -> float:
	if not is_downed:
		return 0.0
	var total := maxf(downed_duration_seconds, 0.001)
	var elapsed := total - get_remaining_seconds()
	return clampf(elapsed / total, 0.0, 1.0)

func enter_downed(resolve_at: float = -1.0, entered_at: float = -1.0) -> void:
	if is_downed:
		return

	is_downed = true
	downed_at = RunClock.now() if entered_at < 0.0 else entered_at

	if resolve_at < 0.0:
		downed_resolve_at = downed_at + downed_duration_seconds
	else:
		downed_resolve_at = resolve_at

	entered_downed.emit()

func revive() -> void:
	if not is_downed:
		return

	is_downed = false
	revived.emit()

func die_final() -> void:
	if not is_downed:
		return

	is_downed = false
	died_final.emit()

func reset() -> void:
	is_downed = false
	downed_at = 0.0
	downed_resolve_at = 0.0

func _resolve_downed() -> void:
	if randf() < downed_survival_chance:
		revive()
	else:
		die_final()

func can_take_finishing_blow() -> bool:
	if not is_downed:
		return true
	return RunClock.now() - downed_at >= grace_period

func get_save_data() -> Dictionary:
	return {
		"is_downed": is_downed,
		"downed_at": downed_at,
		"downed_resolve_at": downed_resolve_at
	}

func load_save_data(data: Dictionary) -> void:
	if data.get("is_downed", false):
		var saved_downed_at := float(data.get("downed_at", RunClock.now()))
		var saved_resolve_at := float(data.get("downed_resolve_at", saved_downed_at + downed_duration_seconds))
		enter_downed(saved_resolve_at, saved_downed_at)

		if downed_resolve_at <= RunClock.now():
			call_deferred("_resolve_downed")
	else:
		reset()
