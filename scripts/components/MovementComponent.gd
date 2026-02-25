extends Node
class_name MovementComponent

var player: Player = null

func setup(p_player: Player) -> void:
	player = p_player

func tick(_delta: float) -> void:
	if player == null:
		return
	pass

func physics_tick(delta: float) -> void:
	if player == null:
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		player.last_direction = input_dir

		var current_speed: float = player.acceleration
		if player.velocity.length() > 0.0 and player.velocity.normalized().dot(input_dir) < 0.5:
			current_speed = player.turn_speed

		player.velocity = player.velocity.move_toward(input_dir * player.max_speed, current_speed * delta)
	else:
		player.velocity = player.velocity.move_toward(Vector2.ZERO, player.friction * delta)
