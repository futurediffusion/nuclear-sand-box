extends Area2D
class_name ArrowProjectile

@export var damage: int = 12
@export var knockback: float = 180.0
@export var life_time: float = 2.5

var velocity: Vector2 = Vector2.ZERO
var _time_left: float = 0.0
var _owner: Node = null

func setup(p_velocity: Vector2, p_damage: int, p_knockback: float, p_owner: Node = null) -> void:
	velocity = p_velocity
	damage = p_damage
	knockback = p_knockback
	_owner = p_owner
	_time_left = life_time

func _ready() -> void:
	_time_left = life_time
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

	if velocity.length_squared() > 0.0001:
		rotation = velocity.angle()

	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area == null:
		return

	if _owner != null and _owner.is_ancestor_of(area):
		return

	var is_hurtbox := area is CharacterHurtbox
	if not is_hurtbox and area.has_method("receive_hit"):
		is_hurtbox = true

	if not is_hurtbox:
		return

	if area.has_method("receive_hit"):
		area.receive_hit(damage, knockback, global_position)

	queue_free()
