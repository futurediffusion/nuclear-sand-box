extends Node

signal died
signal damaged(amount)
signal hp_changed(current: int, max: int)

@export var max_hp: int = 3
@export var armor: int = 0

var hp: int
var is_downed: bool = false
var _dead_emitted: bool = false

func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)

func take_damage(amount: int) -> void:
	if is_dead() and not is_downed:
		return

	if is_downed:
		# Finishing blow
		hp = 0
		if not _dead_emitted:
			_dead_emitted = true
			died.emit()
		return

	var prev_visible_hp := maxi(hp, 0)
	var final_damage: int = maxi(1, amount - armor)
	hp -= final_damage
	damaged.emit(final_damage)

	var current_visible_hp := maxi(hp, 0)
	if current_visible_hp != prev_visible_hp:
		hp_changed.emit(current_visible_hp, max_hp)

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
	return hp <= 0 and not is_downed

func reset() -> void:
	_dead_emitted = false
	hp = max_hp
	hp_changed.emit(hp, max_hp)

func revive(amount: int) -> void:
	_dead_emitted = false
	is_downed = false
	hp = amount
	hp_changed.emit(hp, max_hp)
