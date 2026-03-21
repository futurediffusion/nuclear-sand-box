class_name EnemyAI
extends "res://scripts/CharacterBase.gd"

# Responsibility boundary:
# EnemyAI owns low-level combat/control primitives and reusable movement hooks.
# Higher-level encounter rules, phase flow, UI, payment, and job ownership live
# outside this file; this script only exposes generic scripted-control helpers.

const AIComponentScript = preload("res://scripts/components/AIComponent.gd")
const InventoryComponentScript = preload("res://scripts/components/InventoryComponent.gd")
const WeaponComponentScript = preload("res://scripts/components/WeaponComponent.gd")
const AIWeaponControllerScript = preload("res://scripts/weapons/AIWeaponController.gd")
const DEFAULT_ENEMY_DEATH_SOUND: AudioStream = preload("res://art/Sounds/impact.ogg")

@export_group("Combat")
@export var attack_damage: int = 1
@export var attack_cooldown: float = 0.8
@export var attack_range: float = 60.0
@export var attack_duration: float = 0.3

@export_group("Movement")
@export var max_speed: float = 280.0
@export var acceleration: float = 1000.0
@export var friction: float = 1500.0

@export_group("AI Behavior")
@export var detection_range: float = 400.0
@export var ACTIVE_RADIUS_PX: float = 900.0
@export var WAKE_HYSTERESIS_PX: float = 200.0
@export var SLEEP_CHECK_INTERVAL: float = 0.5

@export_group("References")
@export var slash_scene: PackedScene

@export_group("Death Feedback")
@export var death_shake_duration: float = 0.28
@export var death_shake_magnitude: float = 23.4
@export var finisher_shake_multiplier: float = 2.0
@export var death_sound_pitch_scale: float = 0.68
@export var death_sound_volume_db: float = 2.0

@export_group("Ally Separation")
@export var separation_radius: float = 40.0
@export var separation_strength: float = 120.0

@export_group("AI LOD")
@export var separation_near_interval: float = 0.0
@export var separation_mid_interval: float = 0.1
@export var separation_far_interval: float = 0.25

@export_group("Debug")
@export var debug_enemy_setup_logs: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: Sprite2D = $WeaponPivot/WeaponSprite
@onready var slash_spawn: Marker2D = $WeaponPivot/SlashSpawn
@onready var ai_component: AIComponent = get_node_or_null("AIComponent") as AIComponent
@onready var inventory_component: InventoryComponent = get_node_or_null("InventoryComponent") as InventoryComponent
@onready var weapon_component: WeaponComponent = get_node_or_null("WeaponComponent") as WeaponComponent
@onready var ai_weapon_controller: AIWeaponController = get_node_or_null("AIWeaponController") as AIWeaponController
@onready var character_hurtbox: CharacterHurtbox = get_node_or_null("Hurtbox") as CharacterHurtbox
@onready var carry_component: CarryComponent = get_node_or_null("CarryComponent") as CarryComponent

var weapon_follow_speed: float = 25.0
var attack_snap_speed: float = 50.0
var attacking: bool = false
var use_left_offset: bool = false
var target_attack_angle: float = 0.0
var angle_offset_left: float = -150.0
var angle_offset_right: float = 150.0
var _was_sleeping_last_frame: bool = false
var attack_t: float = 0.0
var _setup_done: bool = false
var _save_state_applied: bool = false
var _last_chunk_pos: Vector2 = Vector2.INF
var _sep_timer: float = 0.0
var _is_lite_mode: bool = false
var external_ai_override: bool = false
var _pending_scripted_melee_action: bool = false
var _scripted_control_timer: float = 0.0
var entity_uid: String = ""
var enemy_chunk_key: String = ""
var enemy_seed: int = 0
var faction_id: String = "bandits"
var group_id: String = ""
var last_engaged_time: float = 0.0
var _enemy_death_sound: AudioStream = DEFAULT_ENEMY_DEATH_SOUND
var _enemy_death_volume_db: float = 2.0
var _last_hit_was_from_player: bool = false

const WARMUP_META_KEY := "warmup_instance"

func _is_warmup_instance() -> bool:
	if not has_meta(WARMUP_META_KEY):
		return false
	var flag: Variant = get_meta(WARMUP_META_KEY)
	return flag is bool and flag

func _enter_tree() -> void:
	if _is_warmup_instance():
		return
	EnemyRegistry.register_enemy(self)

func _exit_tree() -> void:
	if ai_weapon_controller != null:
		ai_weapon_controller.clear_transient_input()
	if ai_component != null:
		ai_component.on_owner_exit_tree()
	EnemyRegistry.unregister_enemy(self)

func _ready() -> void:
	super._ready()
	if _is_warmup_instance():
		if sprite != null:
			sprite.visible = false
		set_process(false)
		set_physics_process(false)
		return

	downed_entered.connect(_on_character_downed_entered)
	revived.connect(_on_character_revived)
	dying_started.connect(_on_character_dying_started)
	death_finished.connect(_on_character_death_finished)

	_apply_sound_panel_overrides()
	add_to_group("enemy")
	sprite.play("idle")
	sprite.z_index = 0
	weapon_pivot.z_index = 10
	weapon_sprite.z_index = 10
	weapon_sprite.visible = true

	_run_setup_once()
	_setup_health_component()
	_connect_hurtbox()



func _connect_hurtbox() -> void:
	if character_hurtbox == null:
		return
	if not character_hurtbox.damaged.is_connected(_on_character_hurtbox_damaged):
		character_hurtbox.damaged.connect(_on_character_hurtbox_damaged)

func _on_character_hurtbox_damaged(dmg: int, from_pos: Vector2) -> void:
	take_damage(dmg, from_pos)

func _validate_core_components() -> bool:
	var valid := true

	if ai_component == null:
		push_error("[Enemy] Missing required core component 'AIComponent' on '%s'" % name)
		if OS.is_debug_build():
			assert(false, "[Enemy] Missing required core component 'AIComponent' on '%s'" % name)
		valid = false

	if inventory_component == null:
		push_error("[Enemy] Missing required core component 'InventoryComponent' on '%s'" % name)
		if OS.is_debug_build():
			assert(false, "[Enemy] Missing required core component 'InventoryComponent' on '%s'" % name)
		valid = false

	if weapon_component == null:
		push_error("[Enemy] Missing required core component 'WeaponComponent' on '%s'" % name)
		if OS.is_debug_build():
			assert(false, "[Enemy] Missing required core component 'WeaponComponent' on '%s'" % name)
		valid = false

	if ai_weapon_controller == null:
		push_error("[Enemy] Missing required core component 'AIWeaponController' on '%s'" % name)
		if OS.is_debug_build():
			assert(false, "[Enemy] Missing required core component 'AIWeaponController' on '%s'" % name)
		valid = false

	if OS.is_debug_build():
		var inv_count := _count_children_by_name("InventoryComponent")
		if inv_count > 1:
			push_error("[Enemy] Duplicate core component 'InventoryComponent' detected on '%s'" % name)
			assert(false, "[Enemy] Duplicate core component 'InventoryComponent' detected on '%s'" % name)
			valid = false
		var weapon_count := _count_children_by_name("WeaponComponent")
		if weapon_count > 1:
			push_error("[Enemy] Duplicate core component 'WeaponComponent' detected on '%s'" % name)
			assert(false, "[Enemy] Duplicate core component 'WeaponComponent' detected on '%s'" % name)
			valid = false
		var ctrl_count := _count_children_by_name("AIWeaponController")
		if ctrl_count > 1:
			push_error("[Enemy] Duplicate core component 'AIWeaponController' detected on '%s'" % name)
			assert(false, "[Enemy] Duplicate core component 'AIWeaponController' detected on '%s'" % name)
			valid = false

	return valid

func _run_setup_once() -> void:
	if _setup_done:
		_setup_log("already_initialized")
		return

	if not _validate_core_components():
		return

	_setup_done = true

	_setup_components()
	if not _save_state_applied:
		_grant_temporary_starting_weapon()
	_setup_weapon_component()

func _setup_components() -> void:
	if ai_component != null:
		ai_component.setup(self)

func _grant_temporary_starting_weapon() -> void:
	if inventory_component == null:
		_setup_log("grant_starting_weapons skip no_inventory")
		return

	if inventory_component.get_total("ironpipe") <= 0:
		inventory_component.add_item("ironpipe", 1)
		_setup_log("grant_ironpipe")
	else:
		_setup_log("grant_ironpipe skip already_present")

	if inventory_component.get_total("bow") <= 0:
		inventory_component.add_item("bow", 1)
		_setup_log("grant_bow")
	else:
		_setup_log("grant_bow skip already_present")

func _setup_weapon_component() -> void:
	if weapon_component == null:
		return
	_setup_log("setup_weapon reuse")

	if inventory_component != null:
		weapon_component.setup_from_inventory(inventory_component)
		if not inventory_component.inventory_changed.is_connected(_on_inventory_changed_rebuild_weapons):
			inventory_component.inventory_changed.connect(_on_inventory_changed_rebuild_weapons)
	else:
		weapon_component.setup_from_inventory(null)

	if not weapon_component.weapon_equipped.is_connected(_on_weapon_equipped_apply_visuals):
		weapon_component.weapon_equipped.connect(_on_weapon_equipped_apply_visuals)

	var ctrl := _ensure_ai_weapon_controller()
	weapon_component.apply_visuals(self)
	weapon_component.equip_runtime_weapon(self, ctrl)

func _ensure_ai_weapon_controller() -> AIWeaponController:
	return ai_weapon_controller

func _count_children_by_name(node_name: String) -> int:
	var total := 0
	for child in get_children():
		if child != null and child.name == node_name:
			total += 1
	return total


func _setup_log(action: String) -> void:
	if not debug_enemy_setup_logs:
		return
	print("[EnemySetup] name=%s id=%s %s" % [name, str(get_instance_id()), action])

func _on_inventory_changed_rebuild_weapons() -> void:
	if weapon_component == null:
		return
	weapon_component.rebuild_weapon_list_from_inventory(inventory_component)

func _on_weapon_equipped_apply_visuals(_weapon_id: String) -> void:
	if weapon_component == null:
		return
	var ctrl := _ensure_ai_weapon_controller()
	weapon_component.apply_visuals(self)
	weapon_component.equip_runtime_weapon(self, ctrl)


func _physics_process(delta: float) -> void:
	if hp <= 0:
		return

	# Scripted-control lock: keeps combat AI suppressed until the action window ends.
	if _scripted_control_timer > 0.0:
		_scripted_control_timer -= delta
		external_ai_override = true
		if _scripted_control_timer <= 0.0:
			end_scripted_control()

	if _last_chunk_pos == Vector2.INF or global_position.distance_squared_to(_last_chunk_pos) >= 1.0:
		EnemyRegistry.update_enemy_chunk(self)
		_last_chunk_pos = global_position

	if hurt_t > 0.0:
		hurt_t -= delta

	var sleeping_now := ai_component != null and ai_component.is_sleeping()
	var can_run_full_ai := not _is_lite_mode and ai_component != null and not sleeping_now and not external_ai_override
	if can_run_full_ai:
		ai_component.physics_tick(delta)
	else:
		if not _pending_scripted_melee_action:
			set_ai_attack_intent(false, global_position)
		if _is_lite_mode:
			if velocity.length_squared() > 0.0001:
				velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	if can_run_full_ai or _pending_scripted_melee_action:
		# IMPORTANT: mantener orden del pipeline para evitar eventos stale.
		# AI -> controller -> weapon_component -> weapon
		if ai_weapon_controller != null:
			ai_weapon_controller.physics_tick()
		if weapon_component != null:
			weapon_component.tick(delta)
		_pending_scripted_melee_action = false

	if sleeping_now != _was_sleeping_last_frame:
		_set_sleep_visual_state(sleeping_now)
		_was_sleeping_last_frame = sleeping_now

	var warming_up_now := ai_component != null and ai_component.is_in_awake_warmup()
	if not sleeping_now:
		if not _is_lite_mode:
			_update_weapon(delta)
		_update_animation()
		if not _is_lite_mode and not warming_up_now and _should_run_separation(delta):
			_apply_separation_force(delta)
		elif _is_lite_mode or warming_up_now:
			_sep_timer = 0.0
	else:
		_sep_timer = 0.0

	_apply_knockback_step(delta)
	move_and_slide()

## Lanza una única acción melee guionizada y bloquea el re-aggro durante retreat_lock_seconds.
## Llamar cuando el NPC ya está en melee range. BanditExtortionDirector y futuros orquestadores usan esto.
func begin_scripted_melee_action(target_pos: Vector2, retreat_lock_seconds: float) -> void:
	_scripted_control_timer = maxf(retreat_lock_seconds, 0.1)
	external_ai_override = true
	_pending_scripted_melee_action = true
	if weapon_component != null and weapon_component.current_weapon != null:
		weapon_component.current_weapon.set("_cooldown", 0.0)  # garantizar que cooldown no bloquea
	queue_ai_attack_press(target_pos)

## Cancela el control guionizado y devuelve el control al AIComponent.
func end_scripted_control() -> void:
	_scripted_control_timer = 0.0
	external_ai_override = false
	_pending_scripted_melee_action = false

func set_scripted_control_enabled(enabled: bool) -> void:
	external_ai_override = enabled


func set_scripted_velocity(world_velocity: Vector2) -> void:
	velocity = world_velocity

func queue_ai_attack_press(aim_global_position: Vector2) -> void:
	if _is_lite_mode:
		return
	last_engaged_time = RunClock.now()
	var ctrl := _ensure_ai_weapon_controller()
	ctrl.queue_attack_press_with_aim(aim_global_position)
	ctrl.set_attack_down(false)
	var angle_to_target := global_position.angle_to_point(aim_global_position)
	_calculate_attack_angle(angle_to_target)

func _calculate_attack_angle(base_angle: float) -> void:
	if use_left_offset:
		target_attack_angle = base_angle + deg_to_rad(angle_offset_left)
	else:
		target_attack_angle = base_angle + deg_to_rad(angle_offset_right)
	use_left_offset = not use_left_offset

func spawn_slash(angle: float) -> void:
	if slash_scene == null:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var s = slash_scene.instantiate()
	s.setup(&"enemy", self)
	s.position = parent.to_local(slash_spawn.global_position)
	s.rotation = angle
	parent.add_child(s)

func set_ai_attack_intent(attack_down: bool, aim_global_position: Vector2) -> void:
	if _is_lite_mode and attack_down:
		return
	if attack_down:
		last_engaged_time = RunClock.now()
	var ctrl := _ensure_ai_weapon_controller()
	ctrl.set_attack_down(attack_down)
	ctrl.set_aim_global_position(aim_global_position)
	if attack_down:
		var angle_to_target := global_position.angle_to_point(aim_global_position)
		_calculate_attack_angle(angle_to_target)

func _update_weapon(delta: float) -> void:
	if ai_component == null or ai_component.player == null:
		return
	var angle_to_player := global_position.angle_to_point(ai_component.player.global_position)
	if attacking:
		weapon_pivot.rotation = lerp_angle(
			weapon_pivot.rotation,
			target_attack_angle,
			1.0 - exp(-attack_snap_speed * delta)
		)
	else:
		weapon_pivot.rotation = lerp_angle(
			weapon_pivot.rotation,
			angle_to_player,
			1.0 - exp(-weapon_follow_speed * delta)
		)
	var angle := wrapf(weapon_pivot.rotation, -PI, PI)
	weapon_sprite.flip_v = abs(angle) > PI / 2.0
	sprite.flip_h = abs(rad_to_deg(angle_to_player)) > 90.0

func _set_sleep_visual_state(sleeping_now: bool) -> void:
	if sleeping_now:
		if sprite.animation != "idle":
			sprite.play("idle")
		sprite.frame = 0
		sprite.speed_scale = 0.0
	else:
		if sprite.speed_scale == 0.0:
			sprite.speed_scale = 1.0

func _update_animation() -> void:
	if hurt_t > 0.0:
		return
	if velocity.length() > 4.0:
		sprite.play("walk")
	else:
		sprite.play("idle")

func _should_run_separation(delta: float) -> bool:
	var interval := _get_separation_interval()
	if is_zero_approx(interval):
		_sep_timer = 0.0
		return true
	_sep_timer -= delta
	if _sep_timer > 0.0:
		return false
	_sep_timer = interval
	return true

func _get_separation_interval() -> float:
	if ai_component == null:
		return maxf(separation_far_interval, 0.0)
	match ai_component.get_lod_bucket():
		0:
			return maxf(separation_near_interval, 0.0)
		1:
			return maxf(separation_mid_interval, 0.0)
		_:
			return maxf(separation_far_interval, 0.0)

func _apply_separation_force(dt: float) -> void:
	if ai_component != null and ai_component.is_sleeping():
		return
	var my_chunk_opt: Variant = EnemyRegistry.world_to_chunk(global_position)
	if my_chunk_opt == null:
		return
	var my_chunk: Vector2i = my_chunk_opt
	var enemies: Array[Node2D] = EnemyRegistry.get_bucket_neighborhood(my_chunk)
	if enemies.is_empty():
		return
	var radius_sq := separation_radius * separation_radius
	for e in enemies:
		if e == self or e == null or not is_instance_valid(e):
			continue
		if e.has_method("is_sleeping") and e.is_sleeping():
			continue
		var delta_pos := global_position - e.global_position
		var dist_sq := delta_pos.length_squared()
		if dist_sq <= 0.0001 or dist_sq >= radius_sq:
			continue
		var dist := sqrt(dist_sq)
		var push_dir := delta_pos / dist
		var t := 1.0 - (dist / separation_radius)
		velocity += push_dir * separation_strength * t * dt

func is_sleeping() -> bool:
	return ai_component != null and ai_component.is_sleeping()

func is_lite_mode() -> bool:
	return _is_lite_mode

## True when BanditBehaviorLayer (world-layer AI) may control this enemy.
## Allows active awake enemies in passive/idle state, not just sleeping ones.
func is_world_behavior_eligible() -> bool:
	if hp <= 0 or dying or is_downed:
		return false
	if ai_component == null:
		return false
	var s := ai_component.current_state
	# Semi-lite still allows world behavior. We only block states that imply combat,
	# damage reactions, death/downed, or explicit combat-adjacent directives.
	return s == AIComponent.AIState.IDLE or ai_component.sleeping

func enter_lite_mode() -> void:
	if _is_lite_mode:
		return
	if hp <= 0 or dying:
		return
	_is_lite_mode = true
	attacking = false
	attack_t = 0.0
	knock_vel = Vector2.ZERO
	_sep_timer = 0.0
	if ai_weapon_controller != null:
		ai_weapon_controller.clear_transient_input()
		ai_weapon_controller.set_attack_down(false)
	if ai_component != null:
		ai_component.on_enter_lite()
	var character_hitbox := get_node_or_null("CharacterHitbox") as CharacterHitbox
	if character_hitbox != null:
		character_hitbox.deactivate()
	set_process(false)
	set_physics_process(true)
	if ai_component != null:
		ai_component.set_process(false)
		ai_component.set_physics_process(false)
	if weapon_component != null:
		weapon_component.set_process(false)
		weapon_component.set_physics_process(false)
	EnemyRegistry.register_enemy(self)
	EnemyRegistry.update_enemy_chunk(self)

func exit_lite_mode() -> void:
	if not _is_lite_mode:
		return
	if hp <= 0 or dying:
		return
	_is_lite_mode = false
	_sep_timer = 0.0
	set_process(true)
	set_physics_process(true)
	if ai_component != null:
		ai_component.set_process(true)
		ai_component.set_physics_process(true)
		ai_component.on_awake_from_lite()
	if weapon_component != null:
		weapon_component.set_process(true)
		weapon_component.set_physics_process(true)
	if ai_weapon_controller != null:
		ai_weapon_controller.clear_transient_input()
		ai_weapon_controller.set_attack_down(false)
	EnemyRegistry.register_enemy(self)
	EnemyRegistry.update_enemy_chunk(self)

func take_damage(dmg: int, from_pos: Vector2 = Vector2.INF) -> void:
	last_engaged_time = RunClock.now()
	super.take_damage(dmg, from_pos)
	if ai_component != null:
		ai_component.wake_now()



func apply_save_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	_save_state_applied = true
	entity_uid = String(state.get("id", entity_uid))
	enemy_chunk_key = String(state.get("chunk_key", enemy_chunk_key))
	enemy_seed = int(state.get("seed", enemy_seed))
	faction_id = String(state.get("faction_id", faction_id))
	group_id = String(state.get("group_id", group_id))
	global_position = Vector2(state.get("pos", global_position))
	if state.has("hp"):
		var saved_hp := int(state.get("hp", hp))
		if health_component != null and health_component.has_method("set_hp_clamped"):
			health_component.set_hp_clamped(saved_hp)
			hp = health_component.hp
		else:
			hp = maxi(0, saved_hp)
	if bool(state.get("is_dead", false)):
		queue_free()
		return
	if inventory_component != null:
		for i in range(inventory_component.max_slots):
			inventory_component.slots[i] = null
		for wid in state.get("weapon_ids", []):
			inventory_component.add_item(String(wid), 1)
	last_engaged_time = float(state.get("last_active_time", 0.0))
	if weapon_component != null:
		weapon_component.setup_from_inventory(inventory_component)
		var equipped_id: String = String(state.get("equipped_weapon_id", ""))
		if equipped_id != "":
			weapon_component.equip_weapon_id(equipped_id)
		weapon_component.apply_visuals(self)
		weapon_component.equip_runtime_weapon(self, _ensure_ai_weapon_controller())

func capture_save_state() -> Dictionary:
	var weapon_ids: Array[String] = []
	if weapon_component != null:
		weapon_ids = weapon_component.weapon_ids.duplicate()
	weapon_ids.sort()
	var equipped: String = ""
	if weapon_component != null:
		equipped = String(weapon_component.current_weapon_id)
	var res := {
		"id": entity_uid,
		"chunk_key": enemy_chunk_key,
		"pos": global_position,
		"hp": hp,
		"is_dead": is_final_dead(),
		"is_downed": is_downed,
		"seed": enemy_seed,
		"faction_id": faction_id,
		"group_id": group_id,
		"weapon_ids": weapon_ids,
		"equipped_weapon_id": equipped,
		"alert": 0.0,
		"last_seen_player_pos": Vector2.ZERO,
		"last_active_time": maxf(last_engaged_time, RunClock.now()),
		"version": 1,
	}
	if downed_component != null:
		res.merge(downed_component.get_save_data(), true)
	return res

func is_attacking() -> bool:
	return attacking

func get_enemy_uid() -> String:
	return entity_uid

func get_group_id() -> String:
	return group_id

func get_faction_id() -> String:
	return faction_id

## Intentional carry release: deposits ItemDrops into a nearby chest if present,
## otherwise releases items to the ground. Call from AI behavior.
func release_carry() -> void:
	if carry_component != null:
		carry_component.release_with_chest_check()

func _on_character_downed_entered() -> void:
	_trigger_death_shake()
	_drop_carried_items()
	if carry_component != null:
		carry_component.force_drop_all()
	if ai_component != null:
		ai_component.set_downed()
	if ai_weapon_controller != null:
		ai_weapon_controller.set_attack_down(false)

	WorldSave.mark_enemy_downed(
		enemy_chunk_key,
		entity_uid,
		downed_component.downed_resolve_at,
		downed_component.downed_at
	)

	NpcProfileSystem.set_status(entity_uid, "downed")

func _on_character_revived() -> void:
	if ai_component != null:
		ai_component.wake_now()
	WorldSave.set_enemy_state(enemy_chunk_key, entity_uid, capture_save_state())
	NpcProfileSystem.set_status(entity_uid, "alive")

func _on_character_dying_started() -> void:
	EnemyRegistry.unregister_enemy(self)
	if GameEvents != null and GameEvents.has_method("emit_entity_died"):
		GameEvents.emit_entity_died(entity_uid, "enemy", global_position, null)
	if _last_hit_was_from_player:
		FactionHostilityManager.add_hostility(faction_id, 0.0, "member_killed",
			{"entity_id": entity_uid, "position": global_position})
	_play_death_sound()
	_trigger_death_shake()
	if carry_component != null:
		carry_component.force_drop_all()
	attacking = false
	set_ai_attack_intent(false, global_position)
	set_physics_process(false)
	if ai_component != null:
		ai_component.set_dead()

func _on_character_death_finished() -> void:
	# El cadáver persiste hasta que NpcSimulator lo limpie al alejarse o descargar el chunk,
	# a menos que keep_corpses esté desactivado.
	var should_keep_corpses: bool = false
	if GameManager != null and GameManager.has_method("get_keep_corpses"):
		should_keep_corpses = GameManager.get_keep_corpses()

	if not should_keep_corpses:
		queue_free()

## Reparenta al mundo cualquier ItemDrop que este NPC llevaba como carry.
## Llamado al entrar en estado downed para que los drops caigan antes de que el nodo sea liberado.
func _drop_carried_items() -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	for child in get_children():
		if not (child is ItemDrop):
			continue
		var drop := child as ItemDrop
		if drop.is_queued_for_deletion():
			continue
		var world_pos := drop.global_position
		drop.reparent(world, true)   # true = mantiene global_position
		drop.add_to_group("item_drop")
		drop.set_deferred("collision_layer", 4)
		drop.set_deferred("monitoring", true)
		drop.set_process(true)
		var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 0.2)).normalized()
		drop.throw_from(world_pos, dir, randf_range(60.0, 110.0))


## Called by slash / arrow when the hit source is the player.
func notify_player_hit() -> void:
	_last_hit_was_from_player = true
	FactionHostilityManager.add_hostility(faction_id, 0.0, "member_attacked",
		{"entity_id": entity_uid, "position": global_position})


func _trigger_death_shake() -> void:
	# Only shake when the player dealt the killing blow — not in enemy-vs-enemy fights
	if not _last_hit_was_from_player:
		return
	if ai_component == null or not is_instance_valid(ai_component.player):
		return
	var p := ai_component.player
	if not p.has_node("Camera2D"):
		return
	var cam := p.get_node("Camera2D")
	var mul := finisher_shake_multiplier if _is_finisher_death else 1.0
	if cam and cam.has_method("shake_impulse"):
		cam.shake_impulse(death_shake_duration * mul, death_shake_magnitude * mul)
	elif cam and cam.has_method("shake"):
		cam.shake(death_shake_magnitude * mul)

func _play_death_sound() -> void:
	if _enemy_death_sound == null:
		return
	var death_audio := AudioStreamPlayer2D.new()
	death_audio.stream = _enemy_death_sound
	death_audio.pitch_scale = death_sound_pitch_scale
	death_audio.volume_db = _enemy_death_volume_db
	death_audio.global_position = global_position
	get_tree().current_scene.add_child(death_audio)
	death_audio.finished.connect(func():
		if is_instance_valid(death_audio):
			death_audio.queue_free()
	)
	death_audio.play()


func _apply_sound_panel_overrides() -> void:
	var panel := _resolve_sound_panel()
	_enemy_death_sound = DEFAULT_ENEMY_DEATH_SOUND
	_enemy_death_volume_db = death_sound_volume_db
	if panel != null and panel.enemy_death_sfx != null:
		_enemy_death_sound = panel.enemy_death_sfx
	if panel != null:
		_enemy_death_volume_db = panel.enemy_death_volume_db


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null
