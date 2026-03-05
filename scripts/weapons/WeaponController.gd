extends Node
class_name WeaponController

# IMPORTANT:
# just_pressed / just_released events are CONSUMABLE.
# They must only be read by Weapon systems.
# Do NOT query them from AIComponent, Animation systems, or other logic.

# Interfaz mínima para armas
func is_attack_pressed() -> bool:
	return false

func is_attack_just_pressed() -> bool:
	return false

func is_attack_just_released() -> bool:
	return false

func get_aim_global_position() -> Vector2:
	return Vector2.ZERO
