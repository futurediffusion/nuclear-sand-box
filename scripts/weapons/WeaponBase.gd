extends Node
class_name WeaponBase

var owner_entity: Node = null
var controller: WeaponController = null

func on_equipped(p_owner: Node, p_controller: WeaponController = null) -> void:
	owner_entity = p_owner
	controller = p_controller

func on_unequipped() -> void:
	owner_entity = null
	controller = null

func set_controller(p_controller: WeaponController) -> void:
	controller = p_controller

func tick(_delta: float) -> void:
	pass
