extends Node
class_name CombatComponent

var player: Player = null

func setup(p_player: Player) -> void:
	player = p_player

func tick(delta: float) -> void:
	if player == null:
		return

	if Input.is_action_just_pressed("attack") and not player.attacking:
		if player.stamina_component == null or not player.stamina_component.has_method("spend_attack_cost"):
			return
		if not player.stamina_component.spend_attack_cost():
			return
		player.emit_signal("request_attack")
		player._calculate_attack_angle()
		_spawn_slash(player.mouse_angle)
		_try_attack_push()
		player.attacking = true
		player.attack_t = 0.0

	if player.attacking:
		player.attack_t += delta
		if player.attack_t >= player.attack_duration:
			player.attacking = false

func request_attack() -> void:
	if player == null:
		return
	if Input.is_action_just_pressed("attack"):
		pass

func _spawn_slash(angle: float) -> void:
	if player == null:
		return
	if player.slash_scene == null:
		return

	var s: Node = player.slash_scene.instantiate()
	s.setup(&"player", player)
	player.get_tree().current_scene.add_child(s)
	s.global_position = player.slash_spawn.global_position
	s.global_rotation = angle + deg_to_rad(player.slash_visual_offset_deg)

	if player.vfx_component != null and player.use_vfx_component:
		player.vfx_component.play_attack_vfx()
	else:
		player._legacy_play_attack_vfx()

func _try_attack_push() -> void:
	if player == null:
		return
	if player.velocity.length() > player.attack_push_deadzone:
		return

	var mouse_pos: Vector2 = player.get_global_mouse_position()
	var dir: Vector2 = mouse_pos - player.global_position
	if dir.length() < 0.001:
		return
	player.attack_push_vel = dir.normalized() * player.attack_push_speed
	player.attack_push_t = player.attack_push_time
