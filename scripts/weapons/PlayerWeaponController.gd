extends WeaponController
class_name PlayerWeaponController

func is_attack_pressed() -> bool:
	return Input.is_action_pressed("attack")

func is_attack_just_pressed() -> bool:
	return Input.is_action_just_pressed("attack")

func is_attack_just_released() -> bool:
	return Input.is_action_just_released("attack")

func get_aim_global_position() -> Vector2:
	var owner_node := owner as Node2D
	if owner_node != null:
		return owner_node.get_global_mouse_position()
	var parent_node := get_parent() as Node2D
	if parent_node != null:
		return parent_node.get_global_mouse_position()
	return Vector2.ZERO
