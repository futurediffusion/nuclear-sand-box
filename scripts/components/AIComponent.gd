extends Node
class_name AIComponent

enum AIState { IDLE, CHASE, ATTACK, HURT, DEAD }

var owner: EnemyAI = null
var player: CharacterBody2D = null
var current_state: AIState = AIState.IDLE
var can_attack: bool = true

func setup(p_owner: EnemyAI) -> void:
	owner = p_owner
	_find_player()

func physics_tick(delta: float) -> void:
	if owner == null:
		return
	if current_state == AIState.DEAD:
		owner.velocity = owner.velocity.move_toward(Vector2.ZERO, owner.friction * delta)
		return
	if player == null or not is_instance_valid(player):
		_find_player()
	_update_state()
	_execute_state(delta)

func set_hurt() -> void:
	if current_state == AIState.DEAD:
		return
	current_state = AIState.HURT

func set_dead() -> void:
	current_state = AIState.DEAD

func _update_state() -> void:
	if current_state == AIState.DEAD:
		return
	if owner.hurt_t > 0.0:
		current_state = AIState.HURT
		return
	if player == null:
		current_state = AIState.IDLE
		return

	var distance := owner.global_position.distance_to(player.global_position)
	if distance > owner.detection_range:
		current_state = AIState.IDLE
	elif distance <= owner.attack_range and can_attack and not owner.attacking:
		current_state = AIState.ATTACK
	else:
		current_state = AIState.CHASE

func _execute_state(delta: float) -> void:
	match current_state:
		AIState.IDLE:
			owner.velocity = owner.velocity.move_toward(Vector2.ZERO, owner.friction * delta)
		AIState.CHASE:
			if player == null:
				owner.velocity = owner.velocity.move_toward(Vector2.ZERO, owner.friction * delta)
				return
			var dir := owner.global_position.direction_to(player.global_position)
			var target_velocity := dir * owner.max_speed
			owner.velocity = owner.velocity.move_toward(target_velocity, owner.acceleration * delta)
		AIState.ATTACK:
			owner.velocity = owner.velocity.move_toward(Vector2.ZERO, owner.friction * delta)
			_try_attack()
		AIState.HURT:
			owner.velocity = owner.velocity.move_toward(Vector2.ZERO, owner.friction * delta)
			if owner.hurt_t <= 0.0:
				current_state = AIState.IDLE
		AIState.DEAD:
			owner.velocity = owner.velocity.move_toward(Vector2.ZERO, owner.friction * delta)

func _try_attack() -> void:
	if not can_attack:
		return
	if owner == null or player == null:
		return
	can_attack = false
	owner.perform_attack(player.global_position)
	_start_attack_cooldown()

func _start_attack_cooldown() -> void:
	if owner == null:
		return
	await owner.get_tree().create_timer(owner.attack_cooldown).timeout
	if not is_instance_valid(self):
		return
	can_attack = true

func _find_player() -> void:
	if owner == null:
		return
	var players := owner.get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as CharacterBody2D
