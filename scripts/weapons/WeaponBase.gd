extends Node
class_name WeaponBase

var player: Node = null
var controller: Node = null

func on_equipped(p_player: Node, p_controller: Node = null) -> void:
	player = p_player
	controller = p_controller

func set_controller(p_controller: Node) -> void:
	controller = p_controller

func on_unequipped() -> void:
	player = null
	controller = null

func tick(_delta: float) -> void:
	pass

func _is_attack_pressed() -> bool:
	if controller != null and controller.has_method("is_attack_pressed"):
		return bool(controller.call("is_attack_pressed"))
	return Input.is_action_pressed("attack")

func _is_attack_just_pressed() -> bool:
	if controller != null and controller.has_method("is_attack_just_pressed"):
		return bool(controller.call("is_attack_just_pressed"))
	return Input.is_action_just_pressed("attack")

func _is_attack_just_released() -> bool:
	if controller != null and controller.has_method("is_attack_just_released"):
		return bool(controller.call("is_attack_just_released"))
	return Input.is_action_just_released("attack")

func _get_aim_global_position() -> Vector2:
	if controller != null and controller.has_method("get_aim_global_position"):
		return controller.call("get_aim_global_position") as Vector2
	var player_node := player as Node2D
	if player_node != null:
		return player_node.get_global_mouse_position()
	return Vector2.ZERO
