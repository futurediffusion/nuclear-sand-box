extends Node
class_name AIComponent

enum AIState { IDLE, CHASE, ATTACK, HURT, DEAD }

var owner_entity: EnemyAI = null
var player: CharacterBody2D = null
var current_state: AIState = AIState.IDLE
var can_attack: bool = true
var sleeping: bool = false
var sleep_check_timer: SceneTreeTimer = null

func setup(p_owner_entity: EnemyAI) -> void:
	owner_entity = p_owner_entity
	_find_player()
	_schedule_sleep_check()

func physics_tick(delta: float) -> void:
	if owner_entity == null:
		return
	if sleeping:
		return
	if current_state == AIState.DEAD:
		owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
		return
	if player == null or not is_instance_valid(player):
		_find_player()
	_update_state()
	_execute_state(delta)

func is_sleeping() -> bool:
	return sleeping

func wake_now() -> void:
	if current_state == AIState.DEAD:
		return
	sleeping = false
	if current_state == AIState.HURT and owner_entity != null and owner_entity.hurt_t > 0.0:
		return
	if current_state != AIState.HURT:
		current_state = AIState.IDLE

func set_hurt() -> void:
	if current_state == AIState.DEAD:
		return
	wake_now()
	current_state = AIState.HURT

func set_dead() -> void:
	sleeping = false
	current_state = AIState.DEAD
	sleep_check_timer = null

func _update_state() -> void:
	if current_state == AIState.DEAD:
		return
	if owner_entity.hurt_t > 0.0:
		current_state = AIState.HURT
		return
	if player == null:
		current_state = AIState.IDLE
		return

	var distance := owner_entity.global_position.distance_to(player.global_position)
	if distance > owner_entity.detection_range:
		current_state = AIState.IDLE
	elif distance <= owner_entity.attack_range and can_attack and not owner_entity.attacking:
		current_state = AIState.ATTACK
	else:
		current_state = AIState.CHASE

func _execute_state(delta: float) -> void:
	match current_state:
		AIState.IDLE:
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
		AIState.CHASE:
			if player == null:
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
				return
			var dir := owner_entity.global_position.direction_to(player.global_position)
			var target_velocity := dir * owner_entity.max_speed
			owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)
		AIState.ATTACK:
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
			_try_attack()
		AIState.HURT:
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
			if owner_entity.hurt_t <= 0.0:
				current_state = AIState.IDLE
		AIState.DEAD:
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)

func _try_attack() -> void:
	if not can_attack:
		return
	if owner_entity == null or player == null:
		return
	can_attack = false
	owner_entity.perform_attack(player.global_position)
	_start_attack_cooldown()

func _start_attack_cooldown() -> void:
	if owner_entity == null:
		return
	await owner_entity.get_tree().create_timer(owner_entity.attack_cooldown).timeout
	if not is_instance_valid(self):
		return
	can_attack = true

func _find_player() -> void:
	if owner_entity == null:
		return
	var players := owner_entity.get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as CharacterBody2D

func _schedule_sleep_check() -> void:
	if owner_entity == null:
		return
	if sleep_check_timer != null and sleep_check_timer.time_left > 0.0:
		return
	var interval: float = maxf(float(owner_entity.SLEEP_CHECK_INTERVAL), 0.05)
	sleep_check_timer = owner_entity.get_tree().create_timer(interval)
	sleep_check_timer.timeout.connect(_on_sleep_check_timeout)

func _on_sleep_check_timeout() -> void:
	sleep_check_timer = null
	if not is_instance_valid(self) or owner_entity == null:
		return
	if current_state == AIState.DEAD:
		return
	if player == null or not is_instance_valid(player):
		_find_player()
	if player == null:
		sleeping = false
		_schedule_sleep_check()
		return

	var distance := owner_entity.global_position.distance_to(player.global_position)
	var wake_distance: float = maxf(float(owner_entity.ACTIVE_RADIUS_PX - owner_entity.WAKE_HYSTERESIS_PX), 0.0)
	if sleeping:
		if distance <= wake_distance:
			wake_now()
	else:
		if distance > owner_entity.ACTIVE_RADIUS_PX:
			sleeping = true
			current_state = AIState.IDLE

	_schedule_sleep_check()
