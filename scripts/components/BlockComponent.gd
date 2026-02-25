extends Node
class_name BlockComponent

var player: Player = null
var blocking: bool = false
var block_angle: float = 0.0
var block_wiggle_t: float = 0.0

func setup(p_player: Player) -> void:
	player = p_player

func tick(delta: float) -> void:
	if player == null:
		return

	if Input.is_action_just_pressed("block"):
		if player.stamina_component != null and player.stamina_component.current_stamina > 0.0:
			blocking = true
			block_wiggle_t = 0.0
			player.emit_signal("block_started")

	if Input.is_action_just_released("block") and blocking:
		blocking = false
		player.emit_signal("block_ended")
		player.player_debug("[BLOCK] desactivado")

	if blocking and player.stamina_component != null:
		var drained: float = (player.block_stamina_drain * 2.0) * delta
		player.stamina_component.current_stamina = maxf(player.stamina_component.current_stamina - drained, 0.0)
		player.stamina_component.stamina_changed.emit(player.stamina_component.current_stamina, player.stamina_component.max_stamina)
		if player.stamina_component.current_stamina <= 0.0:
			blocking = false
			player.emit_signal("block_ended")
			player.player_debug("[BLOCK] roto por stamina agotada")

func is_blocking() -> bool:
	if player == null:
		return false
	return blocking

func get_block_angle() -> float:
	if player == null:
		return block_angle
	block_wiggle_t += player.get_physics_process_delta_time()
	var wiggle_rad: float = deg_to_rad(player.block_wiggle_deg) * sin(block_wiggle_t * TAU * player.block_wiggle_hz)
	block_angle = player.mouse_angle + wiggle_rad
	return block_angle

func can_block_hit(from_pos: Vector2) -> bool:
	if player == null:
		return false
	if from_pos == Vector2.INF:
		return false

	var to_attacker: Vector2 = from_pos - player.global_position
	if to_attacker.length() < 0.001:
		return true

	to_attacker = to_attacker.normalized()

	var block_dir: Vector2 = Vector2.RIGHT.rotated(player.mouse_angle)
	var dotv: float = clampf(block_dir.dot(to_attacker), -1.0, 1.0)
	var ang: float = acos(dotv)
	var half_cone: float = deg_to_rad(player.block_wiggle_deg + player.block_guard_margin_deg)

	return ang <= half_cone

func on_blocked_hit() -> void:
	if player == null:
		return
	if player.stamina_component == null:
		return

	var cost: float = player.stamina_component.max_stamina * player.block_hit_stamina_cost

	player.stamina_component.current_stamina = maxf(
		player.stamina_component.current_stamina - cost,
		0.0
	)

	player.stamina_component.stamina_changed.emit(
		player.stamina_component.current_stamina
	)

	if player.stamina_component.current_stamina <= 0.0:
		blocking = false
		player.emit_signal("block_ended")
		player.player_debug("[BLOCK] roto por golpe sin stamina")
