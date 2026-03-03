extends Area2D
class_name CharacterHurtbox

@export var invincible: bool = false
@export var iframe_duration: float = 0.5

var _iframe_timer: float = 0.0

signal damaged(dmg: int, from_pos: Vector2)

func take_damage(dmg: int, from_pos: Vector2 = Vector2.INF) -> void:
	if invincible or _iframe_timer > 0.0:
		return

	_iframe_timer = iframe_duration
	damaged.emit(dmg, from_pos)

func _physics_process(delta: float) -> void:
	if _iframe_timer > 0.0:
		_iframe_timer -= delta
