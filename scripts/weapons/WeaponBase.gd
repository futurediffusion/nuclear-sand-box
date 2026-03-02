extends Node
class_name WeaponBase

var player: Node = null

func on_equipped(p_player: Node) -> void:
	player = p_player

func on_unequipped() -> void:
	player = null

func tick(_delta: float) -> void:
	pass
