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

func take_damage(amount: int) -> void:
	if is_dead():
		return

	var final_damage: int = maxi(1, amount - armor)
	hp -= final_damage
	damaged.emit(final_damage)
	hp_changed.emit(maxi(hp, 0), max_hp)

	if hp <= 0 and not _dead_emitted:
		_dead_emitted = true
		died.emit()

func heal(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	var prev_hp := hp
	hp = min(max_hp, hp + amount)
	if hp != prev_hp:
		hp_changed.emit(hp, max_hp)

func is_dead() -> bool:
	return hp <= 0
