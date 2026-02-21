class_name StaminaComponent
extends Node



signal stamina_changed(current_stamina: float, max_stamina: float)

@export var max_stamina: float = 100.0
@export var current_stamina: float = 100.0
@export var stamina_cost_attack: float = 10.0
@export var stamina_regen_rate: float = 100.0 / 8.0

func _ready() -> void:
	current_stamina = clampf(current_stamina, 0.0, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)

func _physics_process(delta: float) -> void:
	var previous_stamina := current_stamina
	current_stamina = clampf(current_stamina + stamina_regen_rate * delta, 0.0, max_stamina)
	if not is_equal_approx(previous_stamina, current_stamina):
		stamina_changed.emit(current_stamina, max_stamina)

func can_attack() -> bool:
	return current_stamina >= stamina_cost_attack

func spend_attack_cost() -> bool:
	if not can_attack():
		return false

	current_stamina = maxf(current_stamina - stamina_cost_attack, 0.0)
	stamina_changed.emit(current_stamina, max_stamina)
	return true

func get_current_stamina() -> float:
	return current_stamina

func get_max_stamina() -> float:
	return max_stamina
