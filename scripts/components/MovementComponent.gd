extends Node
class_name MovementComponent

var owner: Node = null

func setup(p_owner: Node) -> void:
	owner = p_owner

func tick(_delta: float) -> void:
	pass

func physics_tick(delta: float) -> void:
	if owner == null:
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		owner.last_direction = input_dir

		var current_speed: float = owner.acceleration
		if owner.velocity.length() > 0.0 and owner.velocity.normalized().dot(input_dir) < 0.5:
			current_speed = owner.turn_speed

		owner.velocity = owner.velocity.move_toward(input_dir * owner.max_speed, current_speed * delta)
	else:
		owner.velocity = owner.velocity.move_toward(Vector2.ZERO, owner.friction * delta)
