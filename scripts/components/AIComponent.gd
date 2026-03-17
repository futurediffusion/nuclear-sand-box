extends Node
class_name AIComponent

enum AIState { IDLE, CHASE, ATTACK, HURT, DEAD, DOWNED }
enum BowState { IDLE, CHARGING, COOLDOWN }

@export_group("AI Combat")
@export var prefer_bow_distance: float = 220.0
@export var prefer_melee_distance: float = 90.0
@export var bow_engage_buffer: float = 24.0
@export var engage_hysteresis: float = 18.0
@export var bow_charge_min: float = 0.2
@export var bow_charge_max: float = 0.8
@export var bow_cooldown_min: float = 0.6
@export var bow_cooldown_max: float = 1.0
@export var melee_cooldown_min: float = 0.35
@export var melee_cooldown_max: float = 0.8
@export var enable_combat_style_windows: bool = true
@export var style_window_min: float = 3.0
@export var style_window_max: float = 8.0
@export var style_ranged_bias: float = 0.6
@export var style_swap_cooldown: float = 1.0
@export var debug_log_style: bool = false
@export var debug_log_combat: bool = false

@export_group("AI LOD")
@export var lod_near_distance: float = 160.0
@export var lod_mid_distance: float = 320.0
@export var lod_far_distance: float = 520.0
@export var lod_mid_interval: float = 0.2
@export var lod_far_interval_min: float = 0.5
@export var lod_far_interval_max: float = 1.0
@export var lod_enable: bool = true
@export var lod_debug: bool = false

@export_group("AI Awake Ramp")
@export var awake_warmup_seconds: float = 0.3
@export var awake_warmup_tick_interval_min: float = 0.10
@export var awake_warmup_tick_interval_max: float = 0.20

var owner_entity = null  # tipado suelto — acepta EnemyAI o TavernKeeper vía duck typing
var player: CharacterBody2D = null
var current_state: AIState = AIState.IDLE
var sleeping: bool = false
var sleep_check_timer: SceneTreeTimer = null

var _bow_state: BowState = BowState.IDLE
var _bow_charge_t: float = 0.0
var _bow_charge_target: float = 0.0
var _bow_cooldown_t: float = 0.0
var _melee_cooldown_t: float = 0.0
var _last_weapon_id: String = ""
var _combat_style: StringName = &"ranged"
var _style_t: float = 0.0
var _style_duration: float = 0.0
var _style_swap_cd_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _lod_timer: float = 0.0
var _lod_interval: float = 0.0
var _lod_bucket: int = 0
var _lod_rng_seeded: bool = false
var _player_find_timer: float = 0.0
var _warmup_remaining: float = 0.0
var _is_warming_up: bool = false
var _warmup_tick_timer: float = 0.0
var _awaiting_first_full_tick: bool = false
var _finish_off_downed_player: bool = false
var _was_player_downed: bool = false
var _contract_valid: bool = false

func _validate_owner_contract(actor: Node) -> bool:
	var required_properties: Array[String] = [
		"max_speed", "friction", "acceleration", "attack_range",
		"detection_range", "ACTIVE_RADIUS_PX", "WAKE_HYSTERESIS_PX",
		"SLEEP_CHECK_INTERVAL", "velocity", "hurt_t", "global_position"
	]
	for prop: String in required_properties:
		if not (prop in actor):
			push_error("[AIComponent] Contract validation failed for owner '%s': missing property '%s'" % [actor.name, prop])
			return false

	var required_methods: Array[String] = [
		"queue_ai_attack_press"
	]
	for method: String in required_methods:
		if not actor.has_method(method):
			push_error("[AIComponent] Contract validation failed for owner '%s': missing method '%s'" % [actor.name, method])
			return false

	var weapon_component := actor.get_node_or_null("WeaponComponent")
	if weapon_component == null:
		push_warning("[AIComponent] Contract validation for owner '%s': 'WeaponComponent' is missing. Combat logic may be degraded." % actor.name)

	var has_controller_method: bool = actor.has_method("_ensure_ai_weapon_controller")
	var has_controller_node: bool = actor.get_node_or_null("AIWeaponController") != null
	if not has_controller_method and not has_controller_node:
		push_error("[AIComponent] Contract validation failed for owner '%s': missing method '_ensure_ai_weapon_controller' and 'AIWeaponController' node" % actor.name)
		return false

	return true

func setup(p_owner_entity: Node) -> void:
	_contract_valid = false
	if p_owner_entity == null:
		push_error("[AIComponent] setup() called with null owner_entity")
		return
	if not _validate_owner_contract(p_owner_entity):
		return
	_contract_valid = true

	owner_entity = p_owner_entity
	_rng.seed = int(owner_entity.get_instance_id())
	_lod_rng_seeded = true
	_init_combat_style_window()
	_find_player()
	_schedule_sleep_check()

func physics_tick(delta: float) -> void:
	if not _contract_valid or owner_entity == null:
		return
	_update_timers(delta)
	_update_combat_style_window(delta)
	if sleeping:
		_release_attack_input()
		return
	if current_state == AIState.DEAD or current_state == AIState.DOWNED:
		_release_attack_input()
		owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
		return

	if _is_warming_up:
		_process_awake_warmup(delta)
		return
	if player == null or not is_instance_valid(player):
		_player_find_timer = maxf(_player_find_timer - delta, 0.0)
		if _player_find_timer <= 0.0:
			_find_player()
			_player_find_timer = 0.25

	var distance := INF
	if player != null and is_instance_valid(player):
		distance = owner_entity.global_position.distance_to(player.global_position)

	var force_full_tick := _bow_state == BowState.CHARGING
	if _awaiting_first_full_tick:
		force_full_tick = false
	var bucket := _compute_lod_bucket(distance)
	var new_interval := 0.0 if force_full_tick else _compute_lod_interval(distance)
	if bucket != _lod_bucket:
		_lod_bucket = bucket
		if _lod_bucket == 0:
			_lod_timer = 0.0
		else:
			_lod_timer = minf(_lod_timer, new_interval)
		if lod_debug:
			print("[AI LOD] enemy_id=", owner_entity.get_instance_id(), " bucket=", _lod_bucket_name(_lod_bucket), " interval=", snappedf(new_interval, 0.01))
	_lod_interval = new_interval

	# Bow charging always wins over LOD cadence: heavy tick must execute now.
	var should_run_heavy := false
	if force_full_tick:
		_lod_timer = 0.0
		should_run_heavy = true
	elif _awaiting_first_full_tick:
		if AwakeRampQueue == null:
			_awaiting_first_full_tick = false
		else:
			if not AwakeRampQueue.is_ticket_ready(owner_entity.get_instance_id()):
				_process_queued_minimal_tick(delta)
				return
			AwakeRampQueue.consume_ticket(owner_entity.get_instance_id())
			_awaiting_first_full_tick = false
		_lod_timer = 0.0
		should_run_heavy = true
	elif is_zero_approx(_lod_interval):
		should_run_heavy = true
	if not should_run_heavy:
		_lod_timer -= delta
		if _lod_timer <= 0.0:
			should_run_heavy = true

	if should_run_heavy:
		_update_state()
		if current_state == AIState.ATTACK or current_state == AIState.CHASE:
			_try_attack_logic(delta)
		else:
			_release_attack_input()
		if _lod_interval > 0.0:
			_lod_timer = _lod_interval * _rng.randf_range(0.3, 1.0)
		else:
			_lod_timer = 0.0

	_execute_light_tick(delta, force_full_tick)

func _execute_light_tick(delta: float, force_hold_override: bool = false) -> void:
	if not _contract_valid or owner_entity == null:
		return
	# Safety: lightweight tick must not cut bow hold while CHARGING (or while
	# a full-rate override is active for the current frame).
	if _bow_state != BowState.CHARGING and not force_hold_override:
		_release_attack_input()
	match current_state:
		AIState.IDLE, AIState.ATTACK, AIState.HURT, AIState.DEAD, AIState.DOWNED:
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
			if current_state == AIState.HURT and owner_entity.hurt_t <= 0.0:
				current_state = AIState.IDLE
		AIState.CHASE:
			if player == null or not is_instance_valid(player):
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
				return
			var dir: Vector2 = owner_entity.global_position.direction_to(player.global_position)
			var target_velocity: Vector2 = dir * float(owner_entity.max_speed)
			owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)

func is_sleeping() -> bool:
	return sleeping

func wake_now() -> void:
	if current_state == AIState.DEAD:
		return
	var was_sleeping := sleeping
	sleeping = false
	if was_sleeping:
		_start_awake_warmup()
	if current_state == AIState.HURT and owner_entity != null and owner_entity.hurt_t > 0.0:
		return
	if current_state != AIState.HURT:
		current_state = AIState.IDLE

func set_hurt() -> void:
	if current_state == AIState.DEAD or current_state == AIState.DOWNED:
		return
	wake_now()
	current_state = AIState.HURT

func set_dead() -> void:
	sleeping = false
	current_state = AIState.DEAD
	sleep_check_timer = null
	_release_attack_input()
	_reset_combat_state()

func set_downed() -> void:
	sleeping = false
	current_state = AIState.DOWNED
	_release_attack_input()
	_reset_combat_state()

func _update_timers(delta: float) -> void:
	if _style_swap_cd_t > 0.0:
		_style_swap_cd_t = maxf(_style_swap_cd_t - delta, 0.0)
	if _melee_cooldown_t > 0.0:
		_melee_cooldown_t = maxf(_melee_cooldown_t - delta, 0.0)
	if _bow_state == BowState.CHARGING:
		_bow_charge_t += delta
	elif _bow_state == BowState.COOLDOWN:
		_bow_cooldown_t = maxf(_bow_cooldown_t - delta, 0.0)
		if _bow_cooldown_t <= 0.0:
			_bow_state = BowState.IDLE

func _start_awake_warmup() -> void:
	_warmup_remaining = maxf(awake_warmup_seconds, 0.0)
	_is_warming_up = _warmup_remaining > 0.0
	_warmup_tick_timer = 0.0
	_awaiting_first_full_tick = true
	if AwakeRampQueue != null and owner_entity != null:
		AwakeRampQueue.request_ticket(owner_entity.get_instance_id())
	_reset_bow_charge_state()

func _cancel_awake_ramp() -> void:
	_is_warming_up = false
	_warmup_remaining = 0.0
	_warmup_tick_timer = 0.0
	_awaiting_first_full_tick = false
	if AwakeRampQueue != null and owner_entity != null:
		AwakeRampQueue.cancel_ticket(owner_entity.get_instance_id())

func _process_awake_warmup(delta: float) -> void:
	_warmup_remaining = maxf(_warmup_remaining - delta, 0.0)
	_reset_bow_charge_state()
	_release_attack_input()
	_warmup_tick_timer -= delta
	if _warmup_tick_timer <= 0.0:
		_execute_warmup_minimal_tick(delta)
		_warmup_tick_timer = _randf_range(awake_warmup_tick_interval_min, awake_warmup_tick_interval_max)
	if _warmup_remaining <= 0.0:
		_is_warming_up = false

func _process_queued_minimal_tick(delta: float) -> void:
	_reset_bow_charge_state()
	_release_attack_input()
	_warmup_tick_timer -= delta
	if _warmup_tick_timer <= 0.0:
		_execute_warmup_minimal_tick(delta)
		_warmup_tick_timer = _randf_range(awake_warmup_tick_interval_min, awake_warmup_tick_interval_max)

func _execute_warmup_minimal_tick(delta: float) -> void:
	if owner_entity == null:
		return
	owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
	if current_state == AIState.HURT and owner_entity.hurt_t <= 0.0:
		current_state = AIState.IDLE

func _reset_bow_charge_state() -> void:
	if _bow_state == BowState.IDLE and is_zero_approx(_bow_charge_t) and is_zero_approx(_bow_charge_target):
		return
	_bow_state = BowState.IDLE
	_bow_charge_t = 0.0
	_bow_charge_target = 0.0

func _update_state() -> void:
	if not _contract_valid or owner_entity == null:
		return
	if current_state == AIState.DEAD or current_state == AIState.DOWNED:
		return
	if owner_entity.hurt_t > 0.0:
		current_state = AIState.HURT
		return
	if player == null:
		current_state = AIState.IDLE
		return

	var player_is_downed = ("is_downed" in player) and player.is_downed

	if player_is_downed and not _was_player_downed:
		_was_player_downed = true
		var min_chance: float = 0.2
		var max_chance: float = 0.4
		if GameManager != null and GameManager.has_method("get_finish_off_chance_min"):
			min_chance = float(GameManager.get_finish_off_chance_min())
			max_chance = float(GameManager.get_finish_off_chance_max())
		var chance: float = _randf_range(min_chance, max_chance)
		_finish_off_downed_player = _randf() < chance

	if not player_is_downed and _was_player_downed:
		_was_player_downed = false
		_finish_off_downed_player = false

	if player_is_downed and not _finish_off_downed_player:
		current_state = AIState.IDLE
		return

	var distance: float = owner_entity.global_position.distance_to(player.global_position)
	var weapon_id_for_state := _get_weapon_id_for_state_decision(distance)
	var engage_distance := _get_engage_distance_for_weapon(weapon_id_for_state)
	var hysteresis := maxf(engage_hysteresis, 0.0)
	var attack_enter_threshold := maxf(engage_distance - hysteresis, 0.0)
	var attack_exit_threshold := engage_distance + hysteresis
	if distance > owner_entity.detection_range:
		current_state = AIState.IDLE
	else:
		match current_state:
			AIState.ATTACK:
				current_state = AIState.ATTACK if distance <= attack_exit_threshold else AIState.CHASE
			AIState.CHASE:
				current_state = AIState.ATTACK if distance <= attack_enter_threshold else AIState.CHASE
			_:
				current_state = AIState.ATTACK if distance <= engage_distance else AIState.CHASE

func _get_engage_distance_for_state() -> float:
	return _get_engage_distance_for_weapon(_get_weapon_id_for_state_decision())

func _get_engage_distance_for_weapon(weapon_id: String) -> float:
	if owner_entity == null:
		return prefer_melee_distance
	var engage_distance := maxf(prefer_melee_distance, owner_entity.attack_range)
	if weapon_id == "bow":
		return maxf(prefer_bow_distance + maxf(bow_engage_buffer, 0.0), engage_distance)
	return engage_distance

func _get_weapon_id_for_state_decision(distance: float = -1.0) -> String:
	if owner_entity == null:
		return ""
	var weapon_component := owner_entity.get_node_or_null("WeaponComponent") as WeaponComponent
	if weapon_component == null:
		return ""
	if distance < 0.0 and player != null and is_instance_valid(player):
		distance = owner_entity.global_position.distance_to(player.global_position)
	if distance < 0.0:
		return weapon_component.get_current_weapon_id()
	var selection := _update_weapon_selection(distance)
	return String(selection.get("weapon_id", weapon_component.get_current_weapon_id()))

func _execute_state(delta: float) -> void:
	match current_state:
		AIState.IDLE:
			_release_attack_input()
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
		AIState.CHASE:
			_release_attack_input()
			if player == null:
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
				return
			var dir: Vector2 = owner_entity.global_position.direction_to(player.global_position)
			var target_velocity: Vector2 = dir * float(owner_entity.max_speed)
			owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)
		AIState.ATTACK:
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
			_try_attack_logic(delta)
		AIState.HURT:
			_release_attack_input()
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
			if owner_entity.hurt_t <= 0.0:
				current_state = AIState.IDLE
		AIState.DEAD:
			_release_attack_input()
			owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)

func _try_attack_logic(delta: float) -> void:
	if owner_entity == null or player == null:
		_release_attack_input()
		return

	var ctrl := _get_ai_controller()
	if ctrl == null:
		return

	var aim_pos := player.global_position
	ctrl.set_aim_global_position(aim_pos)

	var distance: float = owner_entity.global_position.distance_to(aim_pos)
	var weapon_selection := _update_weapon_selection(distance)
	var weapon_id := String(weapon_selection.get("weapon_id", ""))
	var current_weapon_id := String(weapon_selection.get("current_weapon_id", ""))
	var target_weapon_id := String(weapon_selection.get("target_weapon_id", ""))
	_sync_weapon_state_with_equipped(weapon_id)
	_debug_combat_status(distance, current_weapon_id, target_weapon_id)

	if weapon_id == "bow":
		_process_bow(ctrl, distance)
		return

	if weapon_id == "ironpipe":
		_process_melee(aim_pos, distance, delta)
		return

	_release_attack_input()

func _update_weapon_selection(distance: float) -> Dictionary:
	if owner_entity == null:
		return {"weapon_id": "", "current_weapon_id": "", "target_weapon_id": ""}
	var weapon_component := owner_entity.get_node_or_null("WeaponComponent") as WeaponComponent
	if weapon_component == null:
		return {"weapon_id": "", "current_weapon_id": "", "target_weapon_id": ""}

	var current_weapon_id := weapon_component.get_current_weapon_id()
	var target_weapon_id := current_weapon_id

	if current_weapon_id == "bow":
		if distance <= prefer_melee_distance:
			target_weapon_id = "ironpipe"
	elif current_weapon_id == "ironpipe":
		if distance >= prefer_bow_distance:
			target_weapon_id = "bow"
	else:
		if distance >= prefer_bow_distance:
			target_weapon_id = "bow"
		elif distance <= prefer_melee_distance:
			target_weapon_id = "ironpipe"

	target_weapon_id = _apply_combat_style_bias(target_weapon_id, current_weapon_id, distance)

	if target_weapon_id != "" and target_weapon_id != current_weapon_id:
		if _style_swap_cd_t > 0.0:
			return {"weapon_id": current_weapon_id, "current_weapon_id": current_weapon_id, "target_weapon_id": target_weapon_id}
		if _bow_state == BowState.CHARGING and target_weapon_id != "bow":
			_release_attack_input()
			_bow_state = BowState.IDLE
			_bow_charge_t = 0.0
			_bow_charge_target = 0.0
			_bow_cooldown_t = 0.0
		if weapon_component.equip_weapon_id(target_weapon_id):
			_on_weapon_switched(target_weapon_id)
			_style_swap_cd_t = maxf(style_swap_cooldown, 0.0)
			current_weapon_id = weapon_component.get_current_weapon_id()

	return {
		"weapon_id": current_weapon_id,
		"current_weapon_id": current_weapon_id,
		"target_weapon_id": target_weapon_id
	}

func _debug_combat_status(distance: float, current_weapon_id: String, target_weapon_id: String) -> void:
	if not debug_log_combat:
		return
	print(
		"[AICombat] ",
		owner_entity.name,
		" state=", AIState.keys()[current_state],
		" distance=", snappedf(distance, 0.1),
		" current_weapon_id=", current_weapon_id,
		" target_weapon_id=", target_weapon_id,
		" combat_style=", _combat_style,
		" mood=", _combat_style
	)

func _on_weapon_switched(weapon_id: String) -> void:
	_release_attack_input()
	_last_weapon_id = weapon_id
	if weapon_id != "bow":
		_bow_state = BowState.IDLE
		_bow_charge_t = 0.0
		_bow_charge_target = 0.0
		_bow_cooldown_t = 0.0

func _sync_weapon_state_with_equipped(current_weapon_id: String) -> void:
	if current_weapon_id == "" or current_weapon_id == _last_weapon_id:
		return
	_release_attack_input()
	if current_weapon_id != "bow":
		_bow_state = BowState.IDLE
		_bow_charge_t = 0.0
		_bow_charge_target = 0.0
		_bow_cooldown_t = 0.0
	_last_weapon_id = current_weapon_id

func _process_bow(ctrl: AIWeaponController, distance: float) -> void:
	if distance < prefer_melee_distance:
		_release_attack_input()
		return
	if _melee_cooldown_t > 0.0:
		_release_attack_input()
		return

	if _bow_state == BowState.IDLE:
		ctrl.set_attack_down(true)
		_bow_charge_t = 0.0
		_bow_charge_target = _randf_range(bow_charge_min, bow_charge_max)
		_bow_state = BowState.CHARGING
		return

	if _bow_state == BowState.CHARGING and _bow_charge_t >= _bow_charge_target:
		ctrl.set_attack_down(false)
		_bow_state = BowState.COOLDOWN
		_bow_cooldown_t = _randf_range(bow_cooldown_min, bow_cooldown_max)
		return

	if _bow_state != BowState.CHARGING:
		ctrl.set_attack_down(false)

func _process_melee(aim_pos: Vector2, distance: float, delta: float) -> void:
	if not _contract_valid or owner_entity == null:
		return
	_release_attack_input()
	if distance > prefer_melee_distance:
		var dir: Vector2 = owner_entity.global_position.direction_to(aim_pos)
		var target_velocity: Vector2 = dir * float(owner_entity.max_speed)
		owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)
		return
	if _bow_state == BowState.CHARGING:
		_bow_state = BowState.COOLDOWN
		_bow_cooldown_t = _randf_range(bow_cooldown_min, bow_cooldown_max)
	if _melee_cooldown_t > 0.0:
		return
	owner_entity.queue_ai_attack_press(aim_pos)
	_melee_cooldown_t = _randf_range(melee_cooldown_min, melee_cooldown_max)

func _get_ai_controller() -> AIWeaponController:
	if not _contract_valid or owner_entity == null:
		return null
	if owner_entity.has_method("_ensure_ai_weapon_controller"):
		return owner_entity.call("_ensure_ai_weapon_controller") as AIWeaponController
	return owner_entity.get_node_or_null("AIWeaponController") as AIWeaponController

func _release_attack_input() -> void:
	var ctrl := _get_ai_controller()
	if ctrl == null:
		return
	ctrl.set_attack_down(false)

func _reset_combat_state() -> void:
	_bow_state = BowState.IDLE
	_bow_charge_t = 0.0
	_bow_charge_target = 0.0
	_bow_cooldown_t = 0.0
	_melee_cooldown_t = 0.0
	_style_swap_cd_t = 0.0

func _init_combat_style_window() -> void:
	_combat_style = _roll_combat_style()
	_style_t = 0.0
	_style_duration = _randf_range(style_window_min, style_window_max)
	_style_swap_cd_t = 0.0

func _update_combat_style_window(delta: float) -> void:
	if not enable_combat_style_windows:
		return
	_style_t += delta
	if _style_t < _style_duration:
		return
	if _style_swap_cd_t > 0.0:
		return
	if _bow_state == BowState.CHARGING:
		return
	if _is_in_critical_cooldown():
		return

	_combat_style = _roll_combat_style()
	_style_t = 0.0
	_style_duration = _randf_range(style_window_min, style_window_max)
	_style_swap_cd_t = maxf(style_swap_cooldown, 0.0)
	if debug_log_style:
		print("[AIStyle] ", owner_entity.name, "#", owner_entity.get_instance_id(), " -> ", _combat_style)

func _is_in_critical_cooldown() -> bool:
	return _bow_state == BowState.COOLDOWN or _melee_cooldown_t > 0.0

func _apply_combat_style_bias(target_weapon_id: String, current_weapon_id: String, distance: float) -> String:
	if not enable_combat_style_windows:
		return target_weapon_id

	if distance <= prefer_melee_distance:
		return "ironpipe"

	if _combat_style == &"melee":
		return "ironpipe"

	if _combat_style == &"ranged":
		if distance >= prefer_bow_distance:
			return "bow"
		if current_weapon_id == "bow":
			return "bow"

	return target_weapon_id

func _roll_combat_style() -> StringName:
	if _randf() < clampf(style_ranged_bias, 0.0, 1.0):
		return &"ranged"
	return &"melee"

func _randf() -> float:
	return _rng.randf()

func _randf_range(min_value: float, max_value: float) -> float:
	var lo := minf(min_value, max_value)
	var hi := maxf(min_value, max_value)
	if is_equal_approx(lo, hi):
		return lo
	return _rng.randf_range(lo, hi)

func _compute_lod_bucket(distance: float) -> int:
	if not lod_enable:
		return 0
	var near_distance := maxf(lod_near_distance, 0.0)
	var mid_distance := maxf(lod_mid_distance, near_distance)
	if distance <= near_distance:
		return 0
	if distance <= mid_distance:
		return 1
	return 2

func _compute_lod_interval(distance: float) -> float:
	if not lod_enable:
		return 0.0
	var detection_limit: float = float(owner_entity.detection_range) if owner_entity != null else lod_far_distance
	var near_distance := minf(maxf(lod_near_distance, 0.0), detection_limit)
	var mid_distance := minf(maxf(lod_mid_distance, near_distance), detection_limit)
	var far_distance := minf(maxf(lod_far_distance, mid_distance), detection_limit)
	if distance <= near_distance:
		return 0.0
	if distance <= mid_distance:
		return maxf(lod_mid_interval, 0.0)
	if distance <= far_distance or distance <= detection_limit:
		return _randf_range(maxf(lod_far_interval_min, 0.0), maxf(lod_far_interval_max, 0.0))
	return _randf_range(maxf(lod_far_interval_min, 0.0), maxf(lod_far_interval_max, 0.0))

func get_lod_bucket() -> int:
	return _lod_bucket

func _lod_bucket_name(bucket: int) -> String:
	match bucket:
		0:
			return "near"
		1:
			return "mid"
		_:
			return "far"

func _find_player() -> void:
	if owner_entity == null:
		return
	var players: Array = owner_entity.get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as CharacterBody2D

func _schedule_sleep_check() -> void:
	if not _contract_valid or owner_entity == null:
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
	if current_state == AIState.DEAD or current_state == AIState.DOWNED:
		return
	if player == null or not is_instance_valid(player):
		_find_player()
	if player == null:
		sleeping = false
		_schedule_sleep_check()
		return

	var distance: float = owner_entity.global_position.distance_to(player.global_position)
	var wake_distance: float = maxf(float(owner_entity.ACTIVE_RADIUS_PX - owner_entity.WAKE_HYSTERESIS_PX), 0.0)
	if sleeping:
		if distance <= wake_distance:
			wake_now()
	else:
		if distance > owner_entity.ACTIVE_RADIUS_PX:
			sleeping = true
			current_state = AIState.IDLE
			_release_attack_input()
			_reset_combat_state()
			_cancel_awake_ramp()

	_schedule_sleep_check()


func on_owner_exit_tree() -> void:
	_cancel_awake_ramp()
	_release_attack_input()
	_reset_bow_charge_state()

func on_enter_lite() -> void:
	_cancel_awake_ramp()
	_release_attack_input()
	_reset_combat_state()
	_lod_timer = 0.0

func on_awake_from_lite() -> void:
	if owner_entity == null:
		return
	if current_state == AIState.DEAD or current_state == AIState.DOWNED:
		return
	sleeping = false
	current_state = AIState.IDLE
	_lod_timer = 0.0
	_lod_interval = 0.0
	_lod_bucket = 0
	_start_awake_warmup()
	_release_attack_input()
	_reset_combat_state()

func is_in_awake_warmup() -> bool:
	return _is_warming_up
