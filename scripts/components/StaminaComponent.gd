class_name StaminaComponent
extends Node



signal stamina_changed(current_stamina: float, max_stamina: float)

@export var max_stamina: float = 100.0
@export var current_stamina: float = 100.0
@export var stamina_cost_attack: float = 10.0
@export var stamina_regen_rate: float = 100.0 / 8.0
var _regen_blockers: Dictionary = {}

func _ready() -> void:
	current_stamina = clampf(current_stamina, 0.0, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)

func _physics_process(delta: float) -> void:
	if not _regen_blockers.is_empty():
		return
	var previous_stamina := current_stamina
	current_stamina = clampf(current_stamina + stamina_regen_rate * delta, 0.0, max_stamina)
	if not is_equal_approx(previous_stamina, current_stamina):
		stamina_changed.emit(current_stamina, max_stamina)

func set_regen_blocked(blocked: bool, source: String = "default") -> void:
	var key := source.strip_edges()
	if key == "":
		key = "default"

	if blocked:
		_regen_blockers[key] = true
	else:
		_regen_blockers.erase(key)

func is_regen_blocked() -> bool:
	return not _regen_blockers.is_empty()

func can_attack() -> bool:
	return current_stamina >= stamina_cost_attack

func can_spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	return current_stamina >= amount

func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if not can_spend(amount):
		return false

	current_stamina -= amount
	if current_stamina < 0.0:
		current_stamina = 0.0

	stamina_changed.emit(current_stamina, max_stamina)
	return true

func spend_continuous(rate_per_second: float, delta: float) -> bool:
	if rate_per_second <= 0.0:
		return true
	var amount := rate_per_second * delta
	return spend(amount)

func spend_attack_cost() -> bool:
	return spend(stamina_cost_attack)

func get_current_stamina() -> float:
	return current_stamina

func get_max_stamina() -> float:
	return max_stamina
