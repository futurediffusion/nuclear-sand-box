extends WeaponBase
class_name MeleePipeWeapon

@export var stamina_cost: float = 10.0
@export var attack_cooldown: float = 0.25

var _cooldown: float = 0.0
var _character_hitbox: CharacterHitbox = null

func on_equipped(p_player: Node) -> void:
	super.on_equipped(p_player)
	if player == null:
		return
	_character_hitbox = player.get_node_or_null("CharacterHitbox") as CharacterHitbox
	if _character_hitbox != null:
		_character_hitbox.deactivate()

func on_unequipped() -> void:
	if _character_hitbox != null:
		_character_hitbox.deactivate()
	_character_hitbox = null
	super.on_unequipped()

func tick(delta: float) -> void:
	if player == null:
		return

	if _cooldown > 0.0:
		_cooldown -= delta

	if UiManager.is_gameplay_input_blocked():
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
		if _character_hitbox != null:
			_character_hitbox.activate()
		_cooldown = attack_cooldown

	if player.attacking:
		player.attack_t += delta
		if player.attack_t >= player.attack_duration:
			player.attacking = false
			if _character_hitbox != null:
				_character_hitbox.deactivate()


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
