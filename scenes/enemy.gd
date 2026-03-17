class_name EnemyAI
extends "res://scripts/CharacterBase.gd"

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
var _logged_duplicate_inventory_count: bool = false
var _logged_duplicate_weapon_count: bool = false
var _logged_duplicate_controller_count: bool = false
var _last_chunk_pos: Vector2 = Vector2.INF
var _sep_timer: float = 0.0
var _is_lite_mode: bool = false
var entity_uid: String = ""
var enemy_chunk_key: String = ""
var enemy_seed: int = 0
var last_engaged_time: float = 0.0
var _enemy_death_sound: AudioStream = DEFAULT_ENEMY_DEATH_SOUND
var _enemy_death_volume_db: float = 2.0

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

func _run_setup_once() -> void:
	if _setup_done:
		_setup_log("already_initialized")
		return
	_setup_done = true

	_setup_components()
	_setup_inventory_component()
	if not _save_state_applied:
		_grant_temporary_starting_weapon()
	_setup_weapon_component()

func _setup_components() -> void:
	if ai_component == null:
		ai_component = AIComponentScript.new()
		ai_component.name = "AIComponent"
		add_child(ai_component)
	if ai_component != null:
		ai_component.setup(self)
	else:
		push_warning("[Enemy] Missing AIComponent")

func _setup_inventory_component() -> void:
	_count_component_duplicates_once()
	if inventory_component == null:
		inventory_component = get_node_or_null("InventoryComponent") as InventoryComponent
	if inventory_component != null:
		_setup_log("setup_inventory reuse")
		return
	inventory_component = InventoryComponentScript.new()
	inventory_component.name = "InventoryComponent"
	add_child(inventory_component)
	_setup_log("setup_inventory create")

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
	_count_component_duplicates_once()
	if weapon_component == null:
		weapon_component = get_node_or_null("WeaponComponent") as WeaponComponent
	if weapon_component == null:
		weapon_component = WeaponComponentScript.new()
		weapon_component.name = "WeaponComponent"
		add_child(weapon_component)
		_setup_log("setup_weapon create")
	else:
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
	_count_component_duplicates_once()
	if ai_weapon_controller == null:
		ai_weapon_controller = get_node_or_null("AIWeaponController") as AIWeaponController
	if ai_weapon_controller != null:
		_setup_log("setup_ai_controller reuse")
		return ai_weapon_controller
	ai_weapon_controller = AIWeaponControllerScript.new()
	ai_weapon_controller.name = "AIWeaponController"
	add_child(ai_weapon_controller)
	_setup_log("setup_ai_controller create")
	return ai_weapon_controller


func _count_component_duplicates_once() -> void:
	if not debug_enemy_setup_logs:
		return

	if not _logged_duplicate_inventory_count:
		_logged_duplicate_inventory_count = true
		var inv_count := _count_children_by_name("InventoryComponent")
		if inv_count > 1:
			_setup_log("duplicate inventory_count=%d" % inv_count)

	if not _logged_duplicate_weapon_count:
		_logged_duplicate_weapon_count = true
		var weapon_count := _count_children_by_name("WeaponComponent")
		if weapon_count > 1:
			_setup_log("duplicate weapon_count=%d" % weapon_count)

	if not _logged_duplicate_controller_count:
		_logged_duplicate_controller_count = true
		var ctrl_count := _count_children_by_name("AIWeaponController")
		if ctrl_count > 1:
			_setup_log("duplicate ai_controller_count=%d" % ctrl_count)


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
	if _is_lite_mode:
		return
	if hp <= 0:
		return

	if _last_chunk_pos == Vector2.INF or global_position.distance_squared_to(_last_chunk_pos) >= 1.0:
		EnemyRegistry.update_enemy_chunk(self)
		_last_chunk_pos = global_position

	if hurt_t > 0.0:
		hurt_t -= delta

	var sleeping_now := ai_component != null and ai_component.is_sleeping()
	if ai_component != null and not sleeping_now:
		ai_component.physics_tick(delta)
	else:
		set_ai_attack_intent(false, global_position)
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	if ai_component != null and not sleeping_now:
		# IMPORTANT: mantener orden del pipeline para evitar eventos stale.
		# AI -> controller -> weapon_component -> weapon
		if ai_weapon_controller != null:
			ai_weapon_controller.physics_tick()
		if weapon_component != null:
			weapon_component.tick(delta)

	if sleeping_now != _was_sleeping_last_frame:
		_set_sleep_visual_state(sleeping_now)
		_was_sleeping_last_frame = sleeping_now

	var warming_up_now := ai_component != null and ai_component.is_in_awake_warmup()
	if not sleeping_now:
		_update_weapon(delta)
		_update_animation()
		if not warming_up_now and _should_run_separation(delta):
			_apply_separation_force(delta)
		elif warming_up_now:
			_sep_timer = 0.0
	else:
		_sep_timer = 0.0

	_apply_knockback_step(delta)
	move_and_slide()

func perform_attack(_target_position: Vector2) -> void:
	# Legacy entrypoint intentionally disabled to prevent duplicate attacks.
	return

func queue_ai_attack_press(aim_global_position: Vector2) -> void:
	if _is_lite_mode:
		return
	last_engaged_time = Time.get_unix_time_from_system()
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

func _spawn_slash(angle: float) -> void:
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

func spawn_slash(angle: float) -> void:
	_spawn_slash(angle)

func set_ai_attack_intent(attack_down: bool, aim_global_position: Vector2) -> void:
	if _is_lite_mode and attack_down:
		return
	if attack_down:
		last_engaged_time = Time.get_unix_time_from_system()
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
	if velocity.length() > 10.0:
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

func enter_lite_mode() -> void:
	if _is_lite_mode:
		return
	if hp <= 0 or dying:
		return
	_is_lite_mode = true
	attacking = false
	attack_t = 0.0
	velocity = Vector2.ZERO
	knock_vel = Vector2.ZERO
	_sep_timer = 0.0
	if ai_weapon_controller != null:
		ai_weapon_controller.clear_transient_input()
		ai_weapon_controller.set_attack_down(false)
	if ai_component != null:
		ai_component.on_enter_lite()
	if weapon_component != null:
		var character_hitbox := get_node_or_null("CharacterHitbox") as CharacterHitbox
		if character_hitbox != null:
			character_hitbox.deactivate()
	set_process(false)
	set_physics_process(false)
	if ai_component != null:
		ai_component.set_process(false)
		ai_component.set_physics_process(false)
	if weapon_component != null:
		weapon_component.set_process(false)
		weapon_component.set_physics_process(false)
	EnemyRegistry.unregister_enemy(self)

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
	last_engaged_time = Time.get_unix_time_from_system()
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
	global_position = Vector2(state.get("pos", global_position))
	if state.has("hp"):
		hp = int(state.get("hp", hp))
		if health_component != null:
			health_component.hp = hp
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
		"is_dead": hp <= 0 or dying,
		"is_downed": is_downed,
		"seed": enemy_seed,
		"weapon_ids": weapon_ids,
		"equipped_weapon_id": equipped,
		"alert": 0.0,
		"last_seen_player_pos": Vector2.ZERO,
		"last_active_time": maxf(last_engaged_time, Time.get_unix_time_from_system()),
		"version": 1,
	}
	if downed_component != null:
		res.merge(downed_component.get_save_data(), true)
	return res

func is_attacking() -> bool:
	return attacking

func _on_entered_downed() -> void:
	super._on_entered_downed()
	if ai_component != null:
		ai_component.set_downed()
	if ai_weapon_controller != null:
		ai_weapon_controller.set_attack_down(false)
	WorldSave.mark_enemy_downed(enemy_chunk_key, entity_uid, downed_component.downed_resolve_at)
	NpcProfileSystem.set_status(entity_uid, "downed")

func _on_revived() -> void:
	super._on_revived()
	if ai_component != null:
		ai_component.wake_now()
	WorldSave.set_enemy_state(enemy_chunk_key, entity_uid, capture_save_state())
	NpcProfileSystem.set_status(entity_uid, "alive")

func _on_before_die() -> void:
	EnemyRegistry.unregister_enemy(self)
	if GameEvents != null and GameEvents.has_method("emit_entity_died"):
		GameEvents.emit_entity_died(entity_uid, "enemy", global_position, null)
	_play_death_sound()
	attacking = false
	set_ai_attack_intent(false, global_position)
	set_physics_process(false)
	velocity = Vector2.ZERO
	knock_vel = Vector2.ZERO
	if ai_component != null:
		ai_component.set_dead()

func _on_after_die() -> void:
	# El cadáver persiste hasta que NpcSimulator lo limpie al alejarse o descargar el chunk,
	# a menos que keep_corpses esté desactivado.
	if not GameManager.keep_corpses:
		queue_free()

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
