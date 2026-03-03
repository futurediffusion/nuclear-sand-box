extends Node
class_name CombatComponent

var player: Player = null
@onready var CharacterHitbox: CharacterHitbox = get_node_or_null("CharacterHitbox") as CharacterHitbox

func setup(p_player: Player) -> void:
	player = p_player
	if CharacterHitbox == null and player != null:
		CharacterHitbox = player.get_node_or_null("CharacterHitbox") as CharacterHitbox
	if CharacterHitbox != null:
		CharacterHitbox.deactivate()

func tick(delta: float) -> void:
	if player == null:
		return

	# Legacy only: si existe WeaponComponent, este componente solo puede correr
	# cuando el arma actual sea ironpipe. Para armas runtime (ej. bow), no procesa.
	if player.weapon_component != null and player.weapon_component.get_current_weapon_id() != "ironpipe":
		return

	if UiManager.is_combat_input_blocked():
		return

	if Input.is_action_just_pressed("attack") and not player.attacking:
		if player.stamina_component == null or not player.stamina_component.has_method("spend_attack_cost"):
			return
		if not player.stamina_component.spend_attack_cost():
			return
		player.emit_signal("request_attack")
		player._calculate_attack_angle()
		player.spawn_slash(player.mouse_angle)
		_try_attack_push()
		player.attacking = true
		player.attack_t = 0.0
		if CharacterHitbox != null:
			CharacterHitbox.activate()

	if player.attacking:
		player.attack_t += delta
		if player.attack_t >= player.attack_duration:
			player.attacking = false
			if CharacterHitbox != null:
				CharacterHitbox.deactivate()

func request_attack() -> void:
	if player == null:
		return
	if Input.is_action_just_pressed("attack"):
		pass

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
