extends Node
class_name CombatComponent

var owner: Node = null

func setup(p_owner: Node) -> void:
	owner = p_owner

func tick(delta: float) -> void:
	if owner == null:
		return

	if Input.is_action_just_pressed("attack") and not owner.attacking:
		if owner.stamina_component == null or not owner.stamina_component.has_method("spend_attack_cost"):
			return
		if not owner.stamina_component.spend_attack_cost():
			return
		owner.emit_signal("request_attack")
		owner._calculate_attack_angle()
		_spawn_slash(owner.mouse_angle)
		_try_attack_push()
		owner.attacking = true
		owner.attack_t = 0.0

	if owner.attacking:
		owner.attack_t += delta
		if owner.attack_t >= owner.attack_duration:
			owner.attacking = false

func request_attack() -> void:
	if owner == null:
		return
	if Input.is_action_just_pressed("attack"):
		pass

func _spawn_slash(angle: float) -> void:
	if owner.slash_scene == null:
		return

	var s := owner.slash_scene.instantiate()
	s.setup(&"player", owner)
	owner.get_tree().current_scene.add_child(s)
	s.global_position = owner.slash_spawn.global_position
	s.global_rotation = angle + deg_to_rad(owner.slash_visual_offset_deg)

	if owner.vfx_component != null and owner.use_vfx_component:
		owner.vfx_component.play_attack_vfx()
	else:
		owner._legacy_play_attack_vfx()

func _try_attack_push() -> void:
	if owner.velocity.length() > owner.attack_push_deadzone:
		return

	var mouse_pos := owner.get_global_mouse_position()
	var dir := mouse_pos - owner.global_position
	if dir.length() < 0.001:
		return
	owner.attack_push_vel = dir.normalized() * owner.attack_push_speed
	owner.attack_push_t = owner.attack_push_time
