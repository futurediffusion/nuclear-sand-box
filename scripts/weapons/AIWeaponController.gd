extends WeaponController
class_name AIWeaponController

var _attack_down: bool = false
var _prev_attack_down: bool = false

var _just_pressed: bool = false
var _just_released: bool = false
var _queued_press: bool = false

var _aim_global: Vector2 = Vector2.ZERO

# --- Setters (AIComponent los usará) ---
func set_attack_down(down: bool) -> void:
	_attack_down = down

func set_aim_global_position(pos: Vector2) -> void:
	_aim_global = pos

func queue_attack_press() -> void:
	_queued_press = true

func queue_attack_press_with_aim(pos: Vector2) -> void:
	# API atómica para evitar taps con aim desactualizado.
	_aim_global = pos
	_queued_press = true

# Llamar 1 vez por frame de physics (Enemy._physics_process o AIComponent.physics_tick)
func physics_tick() -> void:
	# Reset seguro por frame: los eventos one-shot no deben sobrevivir.
	_just_pressed = false
	_just_released = false

	# Consumimos el tap en cola antes de terminar el frame actual.
	var queued_press := _queued_press
	_queued_press = false

	if ((not _prev_attack_down) and _attack_down) or queued_press:
		_just_pressed = true
	if _prev_attack_down and (not _attack_down):
		_just_released = true

	_prev_attack_down = _attack_down

# --- Interfaz para armas ---
func is_attack_pressed() -> bool:
	return _attack_down

func is_attack_just_pressed() -> bool:
	var value := _just_pressed
	_just_pressed = false
	return value

func is_attack_just_released() -> bool:
	var value := _just_released
	_just_released = false
	return value

func get_aim_global_position() -> Vector2:
	return _aim_global
