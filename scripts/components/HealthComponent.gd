extends Node

signal died
signal damaged(amount)
signal hp_changed(current: int, max: int)

@export var max_hp: int = 3
@export var armor: int = 0

var hp: int
var _dead_emitted: bool = false

func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)

func set_hp_clamped(value: int) -> void:
	var new_hp = clampi(value, 0, max_hp)
	var prev_hp = hp
	hp = new_hp

	if hp > 0:
		_dead_emitted = false

	if hp != prev_hp:
		hp_changed.emit(hp, max_hp)

func take_damage(amount: int) -> void:
	if is_dead():
		return

	var final_damage: int = maxi(1, amount - armor)
	var new_hp := maxi(0, hp - final_damage)

	var hp_did_change = (hp != new_hp)
	hp = new_hp
	damaged.emit(final_damage)

	if hp_did_change:
		hp_changed.emit(hp, max_hp)

	if hp <= 0 and not _dead_emitted:
		_dead_emitted = true
		died.emit()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	set_hp_clamped(hp + amount)

func is_dead() -> bool:
	return hp <= 0

func reset() -> void:
	set_hp_clamped(max_hp)
