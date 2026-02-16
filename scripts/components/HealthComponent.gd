extends Node

signal died
signal damaged(amount)

@export var max_hp: int = 3
@export var armor: int = 0

var hp: int
var _dead_emitted: bool = false

func _ready() -> void:
	hp = max_hp

func take_damage(amount: int) -> void:
	if is_dead():
		return

	var final_damage := max(1, amount - armor)
	hp -= final_damage
	damaged.emit(final_damage)

	if hp <= 0 and not _dead_emitted:
		_dead_emitted = true
		died.emit()

func heal(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	hp = min(max_hp, hp + amount)

func is_dead() -> bool:
	return hp <= 0
