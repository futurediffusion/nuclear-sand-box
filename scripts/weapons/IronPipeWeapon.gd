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
	if controller == null:
		return

	if _cooldown > 0.0:
		_cooldown -= delta
		return

	if UiManager.is_combat_input_blocked():
		return

	var owner_is_attacking := _is_owner_attacking()
	if controller.is_attack_just_pressed() and not owner_is_attacking:
		var stamina := _get_stamina_component()
		if stamina != null and stamina.has_method("spend_attack_cost"):
			if not stamina.spend_attack_cost():
				return

		var angle_info := _get_attack_angle_and_direction()
		if not bool(angle_info["valid"]):
			return
		var aim_angle := float(angle_info["angle"])
		var swing_angle := _resolve_swing_angle(aim_angle)

		if owner_entity.has_signal("request_attack"):
			owner_entity.emit_signal("request_attack")
		_try_set_attack_target_angle(swing_angle)
		_try_spawn_slash(swing_angle)
		_try_attack_push(angle_info["direction"] as Vector2)
		_try_set_attacking_state(true, 0.0)
		if _character_hitbox != null:
			_character_hitbox.activate()
		_cooldown = attack_cooldown

	if _is_owner_attacking():
		if _has_owner_property("attack_t"):
			owner_entity.set("attack_t", float(owner_entity.get("attack_t")) + delta)

		if _has_owner_property("attack_t") and _has_owner_property("attack_duration"):
			if float(owner_entity.get("attack_t")) >= float(owner_entity.get("attack_duration")):
				_try_set_attacking_state(false)
				if _character_hitbox != null:
					_character_hitbox.deactivate()
		elif not _has_owner_property("attack_duration"):
			# Si el dueño no implementa temporizador de ataque, desactivar para evitar hitbox pegada.
			_try_set_attacking_state(false)
			if _character_hitbox != null:
				_character_hitbox.deactivate()


func _try_attack_push(direction: Vector2) -> void:
	if owner_entity == null or direction.length_squared() < 0.0001:
		return
	if not _has_owner_property("velocity"):
		return
	if not _has_owner_property("attack_push_deadzone"):
		return
	if not _has_owner_property("attack_push_vel"):
		return
	if not _has_owner_property("attack_push_speed"):
		return
	if not _has_owner_property("attack_push_t"):
		return
	if not _has_owner_property("attack_push_time"):
		return

	var vel_value: Variant = owner_entity.get("velocity")
	if typeof(vel_value) != TYPE_VECTOR2:
		return
	var velocity := vel_value as Vector2
	if velocity.length() > float(owner_entity.get("attack_push_deadzone")):
		return
	owner_entity.set("attack_push_vel", direction.normalized() * float(owner_entity.get("attack_push_speed")))
	owner_entity.set("attack_push_t", float(owner_entity.get("attack_push_time")))


func _get_owner_node2d() -> Node2D:
	if owner_entity is Node2D:
		return owner_entity as Node2D
	return null

func _get_stamina_component() -> Node:
	if owner_entity == null:
		return null
	return owner_entity.get_node_or_null("StaminaComponent")

func _get_aim_global_position() -> Vector2:
	if controller == null:
		return Vector2.ZERO
	return controller.get_aim_global_position()

func _try_spawn_slash(angle: float) -> void:
	if owner_entity == null:
		return
	if owner_entity.has_method("spawn_slash"):
		owner_entity.call("spawn_slash", angle)

func _try_set_attacking_state(is_attacking: bool, attack_time: float = -1.0) -> void:
	if owner_entity == null:
		return
	if _has_owner_property("attacking"):
		owner_entity.set("attacking", is_attacking)
	if attack_time >= 0.0 and _has_owner_property("attack_t"):
		owner_entity.set("attack_t", attack_time)

func _is_owner_attacking() -> bool:
	if owner_entity == null:
		return false
	if not _has_owner_property("attacking"):
		return false
	return bool(owner_entity.get("attacking"))

func _has_owner_property(property_name: StringName) -> bool:
	if owner_entity == null:
		return false
	for prop in owner_entity.get_property_list():
		if StringName(prop.get("name", "")) == property_name:
			return true
	return false

func _get_attack_angle_and_direction() -> Dictionary:
	var result := {
		"valid": false,
		"angle": 0.0,
		"direction": Vector2.ZERO,
	}

	var owner_entity_node := _get_owner_node2d()
	if owner_entity_node == null:
		return result

	var aim_global := _get_aim_global_position()
	if not is_finite(aim_global.x) or not is_finite(aim_global.y):
		return result

	var dir := aim_global - owner_entity_node.global_position
	if dir.length_squared() < 0.0001:
		return result

	result["valid"] = true
	result["direction"] = dir.normalized()
	result["angle"] = (result["direction"] as Vector2).angle()
	return result

func _resolve_swing_angle(base_angle: float) -> float:
	if owner_entity == null:
		return base_angle
	if not _has_owner_property("use_left_offset"):
		return base_angle
	if not _has_owner_property("angle_offset_left"):
		return base_angle
	if not _has_owner_property("angle_offset_right"):
		return base_angle

	var use_left := bool(owner_entity.get("use_left_offset"))
	var offset_deg := float(owner_entity.get("angle_offset_left")) if use_left else float(owner_entity.get("angle_offset_right"))
	owner_entity.set("use_left_offset", not use_left)
	return base_angle + deg_to_rad(offset_deg)

func _try_set_attack_target_angle(angle: float) -> void:
	if owner_entity == null:
		return
	if _has_owner_property("target_attack_angle"):
		owner_entity.set("target_attack_angle", angle)
