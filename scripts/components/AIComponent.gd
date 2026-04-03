extends Node
class_name AIComponent

const WEAPON_BOW: StringName = &"bow"
const WEAPON_IRONPIPE: StringName = &"ironpipe"
const COMBAT_STYLE_RANGED: StringName = &"ranged"
const COMBAT_STYLE_MELEE: StringName = &"melee"
const SIM_PROFILE_FULL: StringName = &"full"
const SIM_PROFILE_OBEDIENT: StringName = &"obedient"
const SIM_PROFILE_DECORATIVE: StringName = &"decorative"

enum AIState { IDLE, CHASE, ATTACK, HURT, DEAD, DOWNED, DISENGAGE, HOLD_PERIMETER }
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

@export_group("AI Chase")
## Radio de adquisición. 0 = usar owner_entity.detection_range.
@export var acquire_radius: float = 0.0
## Radio de retención durante el chase. 0 = acquire_radius * 2.
@export var chase_retain_radius: float = 0.0
## Segundos que el NPC sigue persiguiendo la última posición vista sin contacto visual.
@export var lost_target_timeout: float = 5.0

var owner_entity = null  # tipado suelto — acepta EnemyAI o TavernKeeper vía duck typing
var player: CharacterBody2D = null
var current_target: CharacterBody2D = null
var current_state: AIState = AIState.IDLE
var sleeping: bool = false
var sleep_check_timer: SceneTreeTimer = null

## Última posición confirmada del target (actualizada mientras está en acquire_radius).
var last_seen_player_pos: Vector2 = Vector2.ZERO
## RunClock.now() de la última vez que el target estuvo en acquire_radius.
var last_seen_target_time: float = -INF

var _current_target_ref: WeakRef = null
var _current_target_id: int = -1
var _ignored_target_id: int = -1
var _ignore_target_until: float = 0.0

## Duel system: when set, this AI ignores normal target acquisition and chases
## the duel opponent until they die or the lock expires.
var _duel_target_id: int    = -1
var _duel_locked_until: float = 0.0

var _bow_state: BowState = BowState.IDLE
var _bow_charge_t: float = 0.0
var _bow_charge_target: float = 0.0
var _bow_cooldown_t: float = 0.0
var _melee_cooldown_t: float = 0.0
var _last_weapon_id: String = ""
var _combat_style: StringName = COMBAT_STYLE_RANGED
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
var _disengage_anchor: Vector2 = Vector2.ZERO
var _perimeter_anchor: Vector2 = Vector2.ZERO
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0
var _current_downed_target_id: int = -1
var _contract_valid: bool = false
var _path_id: String = ""   # agent_id for NpcPathService cache (lazy-init)
## Hasta cuándo puede perseguir al jugador por autodefensa (aunque el perfil no lo permita).
var _provoked_until: float = 0.0
## Mientras esté activo, no adquiere al player de forma proactiva.
## Se usa para raids de estructuras: foco en objetivo estructural, no en jugador.
var _structure_focus_until: float = 0.0
var _simulation_profile: StringName = SIM_PROFILE_FULL

func _has_property(obj: Object, property_name: String) -> bool:
	if obj == null:
		return false
	for prop in obj.get_property_list():
		if String(prop.get("name", "")) == property_name:
			return true
	return false

func _validate_owner_contract(actor: Node) -> bool:
	var required_properties: Array[String] = [
		"max_speed",
		"friction",
		"acceleration",
		"attack_range",
		"detection_range",
		"ACTIVE_RADIUS_PX",
		"WAKE_HYSTERESIS_PX",
		"SLEEP_CHECK_INTERVAL",
		"velocity",
		"hurt_t",
		"global_position"
	]

	for prop: String in required_properties:
		if not _has_property(actor, prop):
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


func set_current_target(target: Node) -> void:
	if target == null:
		clear_current_target()
		return
	current_target = target as CharacterBody2D
	_current_target_ref = weakref(target)
	_current_target_id = target.get_instance_id()

func clear_current_target() -> void:
	current_target = null
	_current_target_ref = null
	_current_target_id = -1

## Forces this AI to target opponent for a 1v1 duel.
## Both the attacker and the victim should call this on each other.
## The duel persists until the target dies or lock_duration seconds elapse.
func force_target(opponent: Node, lock_duration: float = 25.0) -> void:
	if opponent == null or not is_instance_valid(opponent):
		return
	_duel_target_id    = opponent.get_instance_id()
	_duel_locked_until = RunClock.now() + lock_duration
	set_current_target(opponent)
	wake_now()
	if current_state != AIState.DEAD and current_state != AIState.DOWNED:
		current_state = AIState.CHASE

func get_current_target() -> Node:
	# Duel lock: override everything while the opponent is alive and lock is active
	if _duel_target_id != -1:
		if RunClock.now() < _duel_locked_until and is_instance_id_valid(_duel_target_id):
			var duel_node := instance_from_id(_duel_target_id) as Node
			if duel_node != null and is_instance_valid(duel_node):
				var target_dead: bool = false
				if duel_node.has_method("is_final_dead"):
					target_dead = bool(duel_node.call("is_final_dead"))
				if not target_dead:
					current_target = duel_node as CharacterBody2D
					_current_target_ref = weakref(duel_node)
					_current_target_id  = _duel_target_id
					return current_target
		# Duel ended: target died or timed out
		_duel_target_id    = -1
		_duel_locked_until = 0.0

	if current_target != null and is_instance_valid(current_target):
		return current_target
	if _current_target_ref != null:
		var target = _current_target_ref.get_ref()
		if target != null and is_instance_valid(target):
			current_target = target as CharacterBody2D
			return current_target

	# Fallback
	if _simulation_profile != SIM_PROFILE_FULL:
		return null
	if player != null and is_instance_valid(player):
		set_current_target(player)
		return player

	return null

func setup(p_owner_entity: Node) -> void:
	_contract_valid = false
	owner_entity = null
	player = null
	clear_current_target()
	sleep_check_timer = null

	current_state = AIState.IDLE
	sleeping = false
	_ignore_target_until = 0.0
	_ignored_target_id = -1
	_disengage_anchor = Vector2.ZERO
	_perimeter_anchor = Vector2.ZERO
	_current_downed_target_id = -1
	_simulation_profile = SIM_PROFILE_FULL

	if p_owner_entity == null:
		push_error("[AIComponent] setup() called with null owner_entity")
		return

	if not _validate_owner_contract(p_owner_entity):
		return

	owner_entity = p_owner_entity
	_contract_valid = true
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
	var target := get_current_target()
	if target == null:
		if _simulation_profile != SIM_PROFILE_FULL:
			_execute_light_tick(delta, false)
			return
		_player_find_timer = maxf(_player_find_timer - delta, 0.0)
		if _player_find_timer <= 0.0:
			_find_player()
			_player_find_timer = 0.25
			target = get_current_target()

	var distance := INF
	if target != null:
		distance = owner_entity.global_position.distance_to(target.global_position)

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
		# _try_attack_logic solo cuando el target está en rango visible:
		# ATTACK siempre, CHASE solo si aún dentro de acquire_radius (no en chase retenido)
		var can_attack: bool = current_state == AIState.ATTACK or \
				(current_state == AIState.CHASE and distance <= _get_effective_acquire_radius())
		if can_attack:
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
			var target = get_current_target()
			if target == null:
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
				return
			var my_pos: Vector2 = owner_entity.global_position
			var dist_now: float = (my_pos as Vector2).distance_to(target.global_position)
			# usar posición real si en acquire; usar last_seen_player_pos si reteniendo desde lejos
			var target_pos: Vector2 = target.global_position \
					if dist_now <= _get_effective_acquire_radius() \
					else last_seen_player_pos
			var dir: Vector2
			var pid: String = _get_owner_path_id()
			if pid != "" and NpcPathService.is_ready():
				var wp: Vector2 = NpcPathService.get_next_waypoint(
					pid, my_pos, target_pos, {"repath_interval": 0.5})
				var d: Vector2  = wp - my_pos
				var dsq: float  = d.length_squared()
				dir = (d / sqrt(dsq)) if dsq > 0.001 else my_pos.direction_to(target_pos)
			else:
				dir = my_pos.direction_to(target_pos)
			var target_velocity: Vector2 = dir * float(owner_entity.max_speed)
			owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)
		AIState.DISENGAGE:
			var dist: float = owner_entity.global_position.distance_to(_disengage_anchor)
			if dist > 20.0:
				var dir: Vector2 = owner_entity.global_position.direction_to(_disengage_anchor)
				var target_velocity: Vector2 = dir * float(owner_entity.max_speed * 0.7)
				owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)
			else:
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
				# Anchor reached — resume normal routine instead of freezing here
				current_state = AIState.IDLE
				_release_attack_input()
				# Si llegó cargando loot, depositar en el chest más cercano
				if owner_entity != null and owner_entity.has_method("release_carry"):
					var carry: Node = owner_entity.get_node_or_null("CarryComponent")
					if carry != null and carry.has_method("is_carrying") and bool(carry.call("is_carrying")):
						owner_entity.call("release_carry")
		AIState.HOLD_PERIMETER:
			var dist: float = owner_entity.global_position.distance_to(_perimeter_anchor)
			if dist > 40.0:
				var dir: Vector2 = owner_entity.global_position.direction_to(_perimeter_anchor)
				var target_velocity: Vector2 = dir * float(owner_entity.max_speed * 0.5)
				owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)
			else:
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)

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

	var target = get_current_target()
	if target == null:
		current_state = AIState.IDLE
		return

	var target_is_downed = false
	if target.has_method("is_downed"):
		target_is_downed = target.call("is_downed")
	elif "is_downed" in target:
		target_is_downed = target.get("is_downed")

	if target_is_downed:
		var policy: Dictionary = {}
		if DownedEncounterCoordinator != null:
			policy = DownedEncounterCoordinator.get_policy_for_enemy(owner_entity, target)

		if not policy.get("active", false):
			current_state = AIState.IDLE
			_release_attack_input()
			return

		var verdict: int = int(policy.get("verdict", 0))

		if verdict == DownedEncounterCoordinator.Verdict.SPARE:
			if current_state != AIState.DISENGAGE:
				# Don't re-enter DISENGAGE if we already reached the anchor
				var at_anchor: bool = _disengage_anchor != Vector2.ZERO and \
						owner_entity.global_position.distance_squared_to(_disengage_anchor) <= 24.0 * 24.0
				if not at_anchor:
					_release_attack_input()
					current_state = AIState.DISENGAGE
					_ignore_target_until = float(policy.get("ignore_until", 0.0))
					_ignored_target_id = target.get_instance_id()
					_compute_disengage_anchor(float(policy.get("safe_radius", 180.0)))
			return

		elif verdict == DownedEncounterCoordinator.Verdict.FINISH:
			var is_executor := false
			var enemy_uid: String = ""
			if owner_entity.has_method("get_enemy_uid"):
				enemy_uid = owner_entity.call("get_enemy_uid")
			elif "entity_uid" in owner_entity:
				enemy_uid = String(owner_entity.get("entity_uid"))
			if enemy_uid == "":
				enemy_uid = str(owner_entity.get_instance_id())

			is_executor = (enemy_uid == String(policy.get("executor_uid", "")))

			if is_executor:
				# Proceed with normal attack logic against downed target
				pass
			else:
				# Non-executor: brief retreat then return to idle (not a permanent orbit)
				if current_state != AIState.DISENGAGE:
					var at_anchor: bool = _disengage_anchor != Vector2.ZERO and \
							owner_entity.global_position.distance_squared_to(_disengage_anchor) <= 24.0 * 24.0
					if not at_anchor:
						_release_attack_input()
						current_state = AIState.DISENGAGE
						_compute_disengage_anchor(120.0)
				return
	else:
		if target.get_instance_id() == _ignored_target_id and RunClock.now() < _ignore_target_until:
			if current_state != AIState.DISENGAGE:
				# Don't re-enter DISENGAGE if already at anchor (arrived, now idling)
				var at_anchor: bool = _disengage_anchor != Vector2.ZERO and \
						owner_entity.global_position.distance_squared_to(_disengage_anchor) <= 24.0 * 24.0
				if not at_anchor:
					current_state = AIState.DISENGAGE
			return
		elif current_state == AIState.DISENGAGE or current_state == AIState.HOLD_PERIMETER:
			current_state = AIState.IDLE

	var distance: float = owner_entity.global_position.distance_to(target.global_position)
	var weapon_id_for_state := _get_weapon_id_for_state_decision(distance)
	var engage_distance := _get_engage_distance_for_weapon(weapon_id_for_state)
	var hysteresis := maxf(engage_hysteresis, 0.0)
	var attack_enter_threshold := maxf(engage_distance - hysteresis, 0.0)
	var attack_exit_threshold := engage_distance + hysteresis

	var eff_acquire: float = _get_effective_acquire_radius()
	var eff_retain:  float = _get_effective_retain_radius()
	var now:         float = RunClock.now()
	var in_active_pursuit: bool = current_state == AIState.CHASE or current_state == AIState.ATTACK

	# refrescar última posición confirmada cuando el target está en acquire_radius
	if distance <= eff_acquire:
		last_seen_player_pos = target.global_position
		last_seen_target_time = now

	var retain_ok: bool = distance <= eff_retain \
			or (now - last_seen_target_time) <= lost_target_timeout

	if in_active_pursuit:
		if not retain_ok or Debug.is_ghost_mode():
			# perdido definitivamente (o ghost_mode) — soltar limpio, sin lógica específica de actor
			current_state = AIState.IDLE
			_release_attack_input()
		elif distance <= eff_acquire:
			# target visible — máquina normal de CHASE/ATTACK
			match current_state:
				AIState.ATTACK:
					current_state = AIState.ATTACK if distance <= attack_exit_threshold else AIState.CHASE
				AIState.CHASE:
					current_state = AIState.ATTACK if distance <= attack_enter_threshold else AIState.CHASE
		else:
			# retain_ok pero fuera de acquire → bajar a CHASE (ATTACK sin rango no tiene sentido)
			current_state = AIState.CHASE
	else:
		# adquirir si entra en acquire_radius (bloqueado en ghost_mode)
		if distance <= eff_acquire and not Debug.is_ghost_mode() and _can_acquire_player():
			current_state = AIState.ATTACK if distance <= engage_distance else AIState.CHASE

	if (current_state == AIState.ATTACK or current_state == AIState.CHASE) and target != null:
		if AggroTrackerService != null and AggroTrackerService.has_method("register_engagement"):
			AggroTrackerService.register_engagement(owner_entity, target)

## Llamar desde el enemy cuando el player le pegó directamente.
## Activa autodefensa: el enemy puede perseguir aunque el perfil de facción no lo permita.
## Inicia retorno al origen llevando loot. Al llegar al anchor, release_carry() deposita
## el ítem en el chest más cercano via CarryComponent.release_with_chest_check().
func begin_carry_return(anchor: Vector2) -> void:
	_disengage_anchor = anchor
	current_state = AIState.DISENGAGE
	_release_attack_input()


func notify_provoked(duration: float = 15.0) -> void:
	_provoked_until = RunClock.now() + duration


## Foco temporal en objetivo estructural.
## Durante esta ventana, el AI no adquiere al player salvo autodefensa provocada.
func focus_on_structure_for(duration: float = 15.0) -> void:
	if duration <= 0.0:
		return
	_structure_focus_until = maxf(_structure_focus_until, RunClock.now() + duration)
	wake_now()
	if current_state != AIState.DEAD and current_state != AIState.DOWNED:
		current_state = AIState.IDLE
	_release_attack_input()


func is_structure_focus_active() -> bool:
	return RunClock.now() < _structure_focus_until


## Devuelve true si este AI puede iniciar una persecución no provocada contra el player.
## Respeta el perfil de hostilidad de la facción; siempre permite autodefensa.
func _can_acquire_player() -> bool:
	var now: float = RunClock.now()
	# Autodefensa: el player nos atacó recientemente
	if now < _provoked_until:
		return true
	if _simulation_profile != SIM_PROFILE_FULL:
		return false
	# Raid estructural activo: no perseguir al player proactivamente.
	if now < _structure_focus_until:
		return false
	# Consultar perfil de facción
	if owner_entity != null and "faction_id" in owner_entity:
		var fid: String = String(owner_entity.get("faction_id"))
		if fid != "":
			var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(fid)
			return profile.can_attack_punitively
	# Sin facción conocida: comportamiento original (siempre persigue)
	return true


func _get_effective_acquire_radius() -> float:
	var base: float
	if acquire_radius > 0.0:
		base = acquire_radius
	elif owner_entity != null and "detection_range" in owner_entity:
		base = float(owner_entity.get("detection_range"))
	else:
		base = 400.0
	# can_hunt_player (nivel 9+): la facción busca activamente al player — radio x1.6
	if owner_entity != null and "faction_id" in owner_entity:
		var fid: String = String(owner_entity.get("faction_id"))
		if fid != "":
			var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(fid)
			if profile.can_hunt_player:
				return base * 1.6
	return base

func _get_effective_retain_radius() -> float:
	if chase_retain_radius > 0.0:
		return chase_retain_radius
	return _get_effective_acquire_radius() * 2.0

func _compute_disengage_anchor(safe_radius: float) -> void:
	var target = get_current_target()
	if owner_entity == null or target == null:
		return
	var target_pos: Vector2 = target.global_position
	var my_pos: Vector2 = owner_entity.global_position
	var dir_away: Vector2 = my_pos - target_pos
	if dir_away.length_squared() < 1.0:
		dir_away = Vector2.RIGHT.rotated(_randf() * TAU)
	var angle_offset: float = _randf_range(-PI/4.0, PI/4.0)
	var final_dir: Vector2 = dir_away.normalized().rotated(angle_offset)
	_disengage_anchor = target_pos + final_dir * safe_radius

func _compute_perimeter_anchor(perimeter_radius: float) -> void:
	var target = get_current_target()
	if owner_entity == null or target == null:
		return
	var target_pos: Vector2 = target.global_position
	var enemy_uid_hash := hash(str(owner_entity.get_instance_id()))
	var angle: float = fmod(absf(float(enemy_uid_hash)), TAU)
	var offset: Vector2 = Vector2.RIGHT.rotated(angle) * perimeter_radius
	_perimeter_anchor = target_pos + offset

func _get_engage_distance_for_state() -> float:
	return _get_engage_distance_for_weapon(_get_weapon_id_for_state_decision())

func _get_engage_distance_for_weapon(weapon_id: String) -> float:
	if owner_entity == null:
		return prefer_melee_distance
	var engage_distance := maxf(prefer_melee_distance, owner_entity.attack_range)
	if weapon_id == WEAPON_BOW:
		return maxf(prefer_bow_distance + maxf(bow_engage_buffer, 0.0), engage_distance)
	return engage_distance

func _get_weapon_id_for_state_decision(distance: float = -1.0) -> String:
	if owner_entity == null:
		return ""
	var weapon_component := owner_entity.get_node_or_null("WeaponComponent") as WeaponComponent
	if weapon_component == null:
		return ""
	if distance < 0.0:
		var target = get_current_target()
		if target != null:
			distance = owner_entity.global_position.distance_to(target.global_position)
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
			var target = get_current_target()
			if target == null:
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
				return
			# si el target está en acquire_radius, perseguir directo; si no, ir a last_seen_player_pos
			var dist_to_target: float = (owner_entity.global_position as Vector2).distance_to(target.global_position)
			var chase_goal: Vector2 = target.global_position \
					if dist_to_target <= _get_effective_acquire_radius() \
					else last_seen_player_pos
			var dir: Vector2 = owner_entity.global_position.direction_to(chase_goal)
			# Zigzag mientras persigue al jugador provocado — dificulta el puntería con arco.
			if RunClock.now() < _provoked_until:
				_strafe_timer -= delta
				if _strafe_timer <= 0.0:
					_strafe_dir = _rng.randf_range(0.6, 1.0) * sign(_rng.randf() - 0.5)
					_strafe_timer = _rng.randf_range(0.25, 0.55)
				dir = (dir + dir.orthogonal() * _strafe_dir * 0.55).normalized()
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
		AIState.DISENGAGE:
			_release_attack_input()
			var dist: float = owner_entity.global_position.distance_to(_disengage_anchor)
			if dist > 20.0:
				var dir: Vector2 = owner_entity.global_position.direction_to(_disengage_anchor)
				var target_velocity: Vector2 = dir * float(owner_entity.max_speed * 0.7)
				owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)
			else:
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)
		AIState.HOLD_PERIMETER:
			_release_attack_input()
			var dist: float = owner_entity.global_position.distance_to(_perimeter_anchor)
			if dist > 40.0:
				var dir: Vector2 = owner_entity.global_position.direction_to(_perimeter_anchor)
				var target_velocity: Vector2 = dir * float(owner_entity.max_speed * 0.5)
				owner_entity.velocity = owner_entity.velocity.move_toward(target_velocity, owner_entity.acceleration * delta)
			else:
				owner_entity.velocity = owner_entity.velocity.move_toward(Vector2.ZERO, owner_entity.friction * delta)

func _try_attack_logic(delta: float) -> void:
	var target = get_current_target()
	if owner_entity == null or target == null:
		_release_attack_input()
		return

	var ctrl := _get_ai_controller()
	if ctrl == null:
		return

	var aim_pos: Vector2 = target.global_position
	ctrl.set_aim_global_position(aim_pos)

	var distance: float = owner_entity.global_position.distance_to(aim_pos)
	var weapon_selection := _update_weapon_selection(distance)
	var weapon_id := String(weapon_selection.get("weapon_id", ""))
	var current_weapon_id := String(weapon_selection.get("current_weapon_id", ""))
	var target_weapon_id := String(weapon_selection.get("target_weapon_id", ""))
	_sync_weapon_state_with_equipped(weapon_id)
	_debug_combat_status(distance, current_weapon_id, target_weapon_id)

	if weapon_id == WEAPON_BOW:
		_process_bow(ctrl, distance)
		return

	if weapon_id == WEAPON_IRONPIPE:
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
	if _simulation_profile != SIM_PROFILE_FULL:
		return {"weapon_id": current_weapon_id, "current_weapon_id": current_weapon_id, "target_weapon_id": current_weapon_id}
	var target_weapon_id := current_weapon_id

	if current_weapon_id == WEAPON_BOW:
		if distance <= prefer_melee_distance:
			target_weapon_id = WEAPON_IRONPIPE
	elif current_weapon_id == WEAPON_IRONPIPE:
		if distance >= prefer_bow_distance:
			target_weapon_id = WEAPON_BOW
	else:
		if distance >= prefer_bow_distance:
			target_weapon_id = WEAPON_BOW
		elif distance <= prefer_melee_distance:
			target_weapon_id = WEAPON_IRONPIPE

	target_weapon_id = _apply_combat_style_bias(target_weapon_id, current_weapon_id, distance)

	if target_weapon_id != "" and target_weapon_id != current_weapon_id:
		if _style_swap_cd_t > 0.0:
			return {"weapon_id": current_weapon_id, "current_weapon_id": current_weapon_id, "target_weapon_id": target_weapon_id}
		if _bow_state == BowState.CHARGING and target_weapon_id != WEAPON_BOW:
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
	if weapon_id != WEAPON_BOW:
		_bow_state = BowState.IDLE
		_bow_charge_t = 0.0
		_bow_charge_target = 0.0
		_bow_cooldown_t = 0.0

func _sync_weapon_state_with_equipped(current_weapon_id: String) -> void:
	if current_weapon_id == "" or current_weapon_id == _last_weapon_id:
		return
	_release_attack_input()
	if current_weapon_id != WEAPON_BOW:
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

func set_simulation_profile(profile: StringName) -> void:
	var normalized: StringName = profile
	if normalized != SIM_PROFILE_FULL and normalized != SIM_PROFILE_OBEDIENT and normalized != SIM_PROFILE_DECORATIVE:
		normalized = SIM_PROFILE_FULL
	_simulation_profile = normalized

func get_simulation_profile() -> StringName:
	return _simulation_profile

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
		return WEAPON_IRONPIPE

	if _combat_style == COMBAT_STYLE_MELEE:
		return WEAPON_IRONPIPE

	if _combat_style == COMBAT_STYLE_RANGED:
		if distance >= prefer_bow_distance:
			return WEAPON_BOW
		if current_weapon_id == WEAPON_BOW:
			return WEAPON_BOW

	return target_weapon_id

func _roll_combat_style() -> StringName:
	if _randf() < clampf(style_ranged_bias, 0.0, 1.0):
		return COMBAT_STYLE_RANGED
	return COMBAT_STYLE_MELEE

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

## Returns a stable cache key for NpcPathService for this enemy.
## Uses entity_uid when available; falls back to instance_id string.
func _get_owner_path_id() -> String:
	if _path_id != "":
		return _path_id
	if owner_entity == null:
		return ""
	var uid = owner_entity.get("entity_uid")
	if uid != null and String(uid) != "":
		_path_id = String(uid)
	else:
		_path_id = str(owner_entity.get_instance_id())
	return _path_id


func _find_player() -> void:
	if owner_entity == null:
		return
	# Don't touch target assignment while locked in a duel
	if _duel_target_id != -1 and RunClock.now() < _duel_locked_until:
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
	# Never sleep while locked in a duel
	if _duel_target_id != -1 and RunClock.now() < _duel_locked_until:
		sleeping = false
		_schedule_sleep_check()
		return

	var target = get_current_target()
	if target == null:
		_find_player()
		target = get_current_target()

	if target == null:
		sleeping = false
		_schedule_sleep_check()
		return

	var distance: float = owner_entity.global_position.distance_to(target.global_position)
	var wake_distance: float = maxf(float(owner_entity.ACTIVE_RADIUS_PX - owner_entity.WAKE_HYSTERESIS_PX), 0.0)
	if sleeping:
		if distance <= wake_distance:
			wake_now()
	else:
		if distance > owner_entity.ACTIVE_RADIUS_PX:
			# No dormir si el actor está en chase retenido activo
			var retain_active: bool = distance <= _get_effective_retain_radius() \
					or (RunClock.now() - last_seen_target_time) <= lost_target_timeout
			if not retain_active:
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
	if AggroTrackerService != null and AggroTrackerService.has_method("clear_enemy"):
		AggroTrackerService.clear_enemy(owner_entity)
	var pid: String = _get_owner_path_id()
	if pid != "" and NpcPathService.is_ready():
		NpcPathService.clear_agent(pid)

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
