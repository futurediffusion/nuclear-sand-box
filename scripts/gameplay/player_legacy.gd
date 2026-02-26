## DEPRECATED — métodos legacy de player.gd. Se eliminan cuando use_*_component = true sea permanente.

func _legacy_movement_physics(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		last_direction = input_dir
		var current_speed := acceleration
		if velocity.length() > 0.0 and velocity.normalized().dot(input_dir) < 0.5:
			current_speed = turn_speed
		velocity = velocity.move_toward(input_dir * max_speed, current_speed * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func _legacy_attack_tick(delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not attacking:
		if stamina_component == null or not stamina_component.has_method("spend_attack_cost"):
			return
		if not stamina_component.spend_attack_cost():
			return
		emit_signal("request_attack")
		_calculate_attack_angle()
		_spawn_slash(mouse_angle)
		_try_attack_push()
		attacking = true
		attack_t = 0.0
	if attacking:
		attack_t += delta
		if attack_t >= attack_duration:
			attacking = false

func _legacy_block_tick(delta: float) -> void:
	block_wiggle_t += delta
	var wiggle_rad := deg_to_rad(block_wiggle_deg) * sin(block_wiggle_t * TAU * block_wiggle_hz)
	block_angle = mouse_angle + wiggle_rad

func _legacy_block_input_and_drain(delta: float) -> void:
	if Input.is_action_just_pressed("block"):
		if stamina_component != null and stamina_component.current_stamina > 0.0:
			blocking = true
			block_wiggle_t = 0.0
			emit_signal("block_started")
	if Input.is_action_just_released("block"):
		if blocking:
			blocking = false
			emit_signal("block_ended")
	if blocking and stamina_component != null:
		var drained := (block_stamina_drain * 2.0) * delta
		stamina_component.current_stamina = maxf(stamina_component.current_stamina - drained, 0.0)
		stamina_component.stamina_changed.emit(stamina_component.current_stamina, stamina_component.max_stamina)
		if stamina_component.current_stamina <= 0.0:
			blocking = false
			emit_signal("block_ended")

func _is_currently_blocking() -> bool:
	if use_block_component and block_component != null:
		return block_component.is_blocking()
	return blocking

func _legacy_is_hit_blocked(from_pos: Vector2) -> bool:
	if from_pos == Vector2.INF:
		return false
	var to_attacker := (from_pos - global_position)
	if to_attacker.length() < 0.001:
		return true
	to_attacker = to_attacker.normalized()
	var block_dir := Vector2.RIGHT.rotated(mouse_angle)
	var dot := clampf(block_dir.dot(to_attacker), -1.0, 1.0)
	var ang := acos(dot)
	var half_cone := deg_to_rad(block_wiggle_deg + block_guard_margin_deg)
	return ang <= half_cone

func _legacy_play_attack_vfx() -> void:
	if has_node("Camera2D"):
		$Camera2D.shake(4.0)

func _legacy_wall_toggle_update() -> void:
	if wall_occlusion_component != null:
		wall_occlusion_component.on_player_moved(global_position)
