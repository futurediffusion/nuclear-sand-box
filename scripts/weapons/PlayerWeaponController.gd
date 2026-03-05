extends WeaponController
class_name PlayerWeaponController

@export var attack_action: StringName = &"attack"

# Node2D dueño (Player o quien tenga mouse).
# En runtime conviene usar parent primero (add_child), porque `owner` puede quedar null.
func _get_owner_node2d() -> Node2D:
	if get_parent() is Node2D:
		return get_parent() as Node2D
	if owner is Node2D:
		return owner as Node2D
	return null

func is_attack_pressed() -> bool:
	return Input.is_action_pressed(attack_action)

func is_attack_just_pressed() -> bool:
	return Input.is_action_just_pressed(attack_action)

func is_attack_just_released() -> bool:
	return Input.is_action_just_released(attack_action)

func get_aim_global_position() -> Vector2:
	var o := _get_owner_node2d()
	if o == null:
		return Vector2.ZERO
	return o.get_global_mouse_position()
