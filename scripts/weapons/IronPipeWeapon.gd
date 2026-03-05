extends WeaponBase
class_name IronPipeWeapon

@export var stamina_cost: float = 10.0
@export var attack_cooldown: float = 0.25

var _cooldown: float = 0.0
var _character_hitbox: CharacterHitbox = null

func on_equipped(p_owner: Node, p_controller: WeaponController = null) -> void:
	super.on_equipped(p_owner, p_controller)
	if owner_entity == null:
		return
	_character_hitbox = owner_entity.get_node_or_null("CharacterHitbox") as CharacterHitbox
	if _character_hitbox != null:
		_character_hitbox.deactivate()

func on_unequipped() -> void:
	if _character_hitbox != null:
		_character_hitbox.deactivate()
	_character_hitbox = null
	super.on_unequipped()

func tick(delta: float) -> void:
	if owner_entity == null:
		return

	if _cooldown > 0.0:
		_cooldown -= delta
		return

	if UiManager.is_combat_input_blocked():
		return

	if Input.is_action_just_pressed("attack") and not owner_entity.attacking:
		if owner_entity.stamina_component == null or not owner_entity.stamina_component.has_method("spend_attack_cost"):
			return
		if not owner_entity.stamina_component.spend_attack_cost():
			return
		owner_entity.emit_signal("request_attack")
		owner_entity._calculate_attack_angle()
		owner_entity.spawn_slash(owner_entity.mouse_angle)
		_try_attack_push()
		owner_entity.attacking = true
		owner_entity.attack_t = 0.0
		if _character_hitbox != null:
			_character_hitbox.activate()
		_cooldown = attack_cooldown

	if owner_entity.attacking:
		owner_entity.attack_t += delta
		if owner_entity.attack_t >= owner_entity.attack_duration:
			owner_entity.attacking = false
			if _character_hitbox != null:
				_character_hitbox.deactivate()


func _try_attack_push() -> void:
	if owner_entity == null:
		return
	if owner_entity.velocity.length() > owner_entity.attack_push_deadzone:
		return

	var mouse_pos: Vector2 = owner_entity.get_global_mouse_position()
	var dir: Vector2 = mouse_pos - owner_entity.global_position
	if dir.length() < 0.001:
		return
	owner_entity.attack_push_vel = dir.normalized() * owner_entity.attack_push_speed
	owner_entity.attack_push_t = owner_entity.attack_push_time
