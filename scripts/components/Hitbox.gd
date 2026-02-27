extends Area2D
class_name CharacterHitbox

@export var damage: int = 1
@export var knockback_force: float = 300.0
@export var hit_once: bool = true

var _hit_bodies: Array = []

signal hit_landed(CharacterHurtbox: CharacterHurtbox)

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	deactivate()

func activate() -> void:
	_hit_bodies.clear()
	monitoring = true

func deactivate() -> void:
	monitoring = false

func _on_area_entered(area: Area2D) -> void:
	if not (area is CharacterHurtbox):
		return

	var hurtbox := area as CharacterHurtbox
	if hit_once and _hit_bodies.has(hurtbox):
		return

	_hit_bodies.append(hurtbox)
	hit_landed.emit(hurtbox)
	hurtbox.receive_hit(damage, knockback_force, global_position)
