extends WeaponController
class_name PlayerWeaponController

@export var attack_action: StringName = &"attack"

# Node2D dueño (Player o quien tenga mouse)
# Nota: usamos owner, pero si lo instancias como hijo, owner debería ser el Player.
func _get_owner_node2d() -> Node2D:
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
