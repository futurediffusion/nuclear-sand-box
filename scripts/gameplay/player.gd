class_name Player
extends CharacterBase

var DEBUG_PLAYER := OS.is_debug_build()
const InventoryComponentScript = preload("res://scripts/components/InventoryComponent.gd")
const AIWeaponControllerScript = preload("res://scripts/weapons/AIWeaponController.gd")
const FootstepAudioComponentScript = preload("res://scripts/components/FootstepAudioComponent.gd")
const PLAYER_SIT_TEXTURE: Texture2D = preload("res://art/sprites/playersit.png")
const PLAYER_SIT_ANIMATION: StringName = &"sit"

@onready var stamina_component: StaminaComponent = get_node_or_null("StaminaComponent") as StaminaComponent
@onready var movement_component: MovementComponent = get_node_or_null("MovementComponent") as MovementComponent
@onready var combat_component: CombatComponent = get_node_or_null("CombatComponent") as CombatComponent
@onready var block_component: BlockComponent = get_node_or_null("BlockComponent") as BlockComponent
@onready var wall_occlusion_component: WallOcclusionComponent = get_node_or_null("WallOcclusionComponent") as WallOcclusionComponent
@onready var vfx_component: VFXComponent = get_node_or_null("VFXComponent") as VFXComponent
@onready var footstep_audio_component: FootstepAudioComponent = get_node_or_null("FootstepAudioComponent") as FootstepAudioComponent
@onready var character_hurtbox: CharacterHurtbox = get_node_or_null("Hurtbox") as CharacterHurtbox

@export_group("Component Toggles")
@export var use_movement_component := true
@export var use_combat_component := true
@export var use_block_component := true
@export var use_wall_component := true
@export var use_vfx_component := true
@export var use_footstep_audio_component := true

@export_group("Movement")
@export var max_speed: float = 300.0
@export var acceleration: float = 1200.0
@export var friction: float = 1800.0
@export var turn_speed: float = 2000.0

@export_group("Health")
@export var hearts_ui: Node

@export_group("Attack Push")
@export var attack_push_speed: float = 220.0
@export var attack_push_time: float = 0.08
@export var attack_push_deadzone: float = 15.0

@export_group("Weapon")
@export var weapon_follow_speed: float = 25.0
@export var attack_snap_speed: float = 50.0
@export var attack_duration: float = 0.3
@export var facing_deadzone_px: float = 2.0

@export_group("Attack Angles")
@export var angle_offset_left: float = -150.0
@export var angle_offset_right: float = 150.0

@export_group("Slash")
@export var slash_scene: PackedScene
@export var slash_visual_offset_deg: float = 0.0
@export var block_guard_margin_deg: float = 10.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: Sprite2D = $WeaponPivot/WeaponSprite
@onready var slash_spawn: Marker2D = $WeaponPivot/SlashSpawn
@onready var inventory_component: InventoryComponent = get_node_or_null("InventoryComponent") as InventoryComponent
@onready var weapon_component: WeaponComponent = get_node_or_null("WeaponComponent") as WeaponComponent
@onready var weapon_controller: PlayerWeaponController = get_node_or_null("PlayerWeaponController") as PlayerWeaponController
@onready var ai_weapon_controller: AIWeaponController = get_node_or_null("AIWeaponController") as AIWeaponController

@export_group("Death Feedback")
@export var death_shake_duration: float = 0.28
@export var death_shake_magnitude: float = 23.4

@export_group("FX")
@export var droplet_scene: PackedScene
@export var splat_scene: PackedScene
@export var splat_lifetime: float = 60.0
@export var droplet_count_hit: int = 6
@export var droplet_count_death: int = 14
@export var droplet_speed_min: float = 80.0
@export var droplet_speed_max: float = 140.0
@export var droplet_spread_deg: float = 70.0
const MAX_DROPLETS_IN_SCENE := 40

@export_group("Wall Toggle")
@export var tilemap_path: NodePath
@export var walls_layer: int = 2
@export var walls_source_id: int = 2
@export var wall_alt_full: int = 0
@export var wall_alt_small: int = 2
@export var wall_probe_px: float = 14.0
@export var probe_tile_offset: Vector2i = Vector2i(0, 1)

var last_direction: Vector2 = Vector2.RIGHT
var mouse_angle: float = 0.0
var attacking := false
var attack_t := 0.0
var use_left_offset: bool = false
var target_attack_angle: float = 0.0
var attack_push_vel: Vector2 = Vector2.ZERO
var attack_push_t: float = 0.0
var blocking: bool = false
var block_angle: float = 0.0
@export var block_stamina_drain: float = 12.0
@export var block_hit_stamina_cost: float = 0.10
@export var block_wiggle_deg: float = 60.0
@export var block_wiggle_hz: float = 6.0
var block_wiggle_t: float = 0.0
var _current_weapon_controller: WeaponController = null
var _movement_control_mode: StringName = &"player"
var _combat_control_mode: StringName = &"player"
var _world_node_ref: WeakRef = null
var _is_seated: bool = false
var _seat_source_ref: WeakRef = null
var _seat_return_world_pos: Vector2 = Vector2.INF


signal stamina_changed(stamina: float, max_stamina: float)
signal request_attack
signal took_damage(amount: int)
signal picked_item(item_id: String, amount: int)
signal block_started
signal block_ended

func player_debug(message: String) -> void:
	if DEBUG_PLAYER:
		print(message)

func _validate_core_components() -> bool:
	var valid := true

	if inventory_component == null:
		inventory_component = get_node_or_null("InventoryComponent") as InventoryComponent
	if weapon_component == null:
		weapon_component = get_node_or_null("WeaponComponent") as WeaponComponent
	if weapon_controller == null:
		weapon_controller = get_node_or_null("PlayerWeaponController") as PlayerWeaponController

	if inventory_component == null:
		push_error("[Player] Missing required core component 'InventoryComponent' on 'Player'")
		if OS.is_debug_build():
			assert(false, "[Player] Missing required core component 'InventoryComponent' on 'Player'")
		valid = false

	if weapon_component == null:
		push_error("[Player] Missing required core component 'WeaponComponent' on 'Player'")
		if OS.is_debug_build():
			assert(false, "[Player] Missing required core component 'WeaponComponent' on 'Player'")
		valid = false

	if weapon_controller == null:
		push_error("[Player] Missing required core component 'PlayerWeaponController' on 'Player'")
		if OS.is_debug_build():
			assert(false, "[Player] Missing required core component 'PlayerWeaponController' on 'Player'")
		valid = false

	return valid

func _ready() -> void:
	super._ready()
	Debug.log("boot", "Player ready begin")

	if not _validate_core_components():
		return

	_ensure_sit_animation()
	sprite.play("idle")
	sprite.flip_h = false
	add_to_group("player")
	sprite.z_index = 2
	weapon_pivot.z_index = 2
	weapon_sprite.z_index = 2
	
	_setup_components()
	_configure_collision_mode()
	_resolve_hearts_ui()
	_setup_health_component()
	_setup_stamina_component()
	_setup_inventory_component()
	_grant_starting_loadout()
	_setup_weapon_component()
	_update_hearts_ui()
	var listener := AudioListener2D.new()
	add_child(listener)
	listener.make_current()
	if inventory_component != null and DEBUG_PLAYER:
		inventory_component.debug_print()
	Debug.log("boot", "Player ready end")

func _setup_components() -> void:
	if movement_component != null:
		movement_component.setup(self)
	else:
		push_warning("[Player] Missing MovementComponent")
	if combat_component != null:
		combat_component.setup(self)
	else:
		push_warning("[Player] Missing CombatComponent")
	if block_component != null:
		block_component.setup(self)
	else:
		push_warning("[Player] Missing BlockComponent")
	if wall_occlusion_component != null:
		wall_occlusion_component.setup(self)
		wall_occlusion_component.set_enabled(false)  # shader se encarga
		if Debug.safe_mode and Debug.disable_wall_occlusion:
			wall_occlusion_component.set_enabled(false)
	else:
		push_warning("[Player] Missing WallOcclusionComponent")
	if vfx_component != null:
		if Debug.safe_mode and Debug.disable_vfx_pooling:
			vfx_component.use_pooling = false
		vfx_component.setup(self)
	else:
		push_warning("[Player] Missing VFXComponent")
	if footstep_audio_component == null:
		footstep_audio_component = FootstepAudioComponentScript.new()
		footstep_audio_component.name = "FootstepAudioComponent"
		add_child(footstep_audio_component)
	if footstep_audio_component != null:
		footstep_audio_component.setup(self, Callable(self, "_resolve_walk_surface_id"))
	else:
		push_warning("[Player] Missing FootstepAudioComponent")

func _configure_collision_mode() -> void:
	if Debug.use_legacy_wall_collision:
		collision_mask = 1
		return
	collision_mask = collision_mask | CollisionLayersScript.WORLD_WALL_LAYER_MASK
	_apply_world_collision_policy()

func _resolve_hearts_ui() -> void:
	if hearts_ui != null:
		return
	var scene_root := get_tree().current_scene
	if scene_root != null:
		hearts_ui = _find_hearts_ui_node(scene_root)

func _find_hearts_ui_node(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method("set_hearts"):
		return node
	for child in node.get_children():
		var found := _find_hearts_ui_node(child)
		if found != null:
			return found
	return null

func _setup_health_component() -> void:
	super._setup_health_component()
	if health_component != null and health_component.has_signal("damaged") and not health_component.damaged.is_connected(_on_health_damaged):
		health_component.damaged.connect(_on_health_damaged)
	if character_hurtbox != null and not character_hurtbox.damaged.is_connected(_on_CharacterHurtbox_damaged):
		character_hurtbox.damaged.connect(_on_CharacterHurtbox_damaged)

func _setup_stamina_component() -> void:
	if stamina_component == null:
		stamina_component = StaminaComponent.new()
		stamina_component.name = "StaminaComponent"
		add_child(stamina_component)
	if stamina_component != null:
		if stamina_component.has_signal("stamina_changed") and not stamina_component.stamina_changed.is_connected(_on_stamina_changed):
			stamina_component.stamina_changed.connect(_on_stamina_changed)
		stamina_changed.emit(stamina_component.current_stamina, stamina_component.max_stamina)

func _setup_inventory_component() -> void:
	if inventory_component == null:
		return

	if SaveManager._pending_player_inv.size() > 0:
		inventory_component.slots = SaveManager._pending_player_inv.duplicate(true)
		Debug.log("inv", "[INV] Inventory restaurado desde SaveManager")

	if SaveManager._pending_player_gold >= 0:
		inventory_component.gold = SaveManager._pending_player_gold
		Debug.log("inv", "[INV] Gold restaurado desde SaveManager: %d" % inventory_component.gold)


func _grant_starting_loadout() -> void:
	if inventory_component == null:
		return

	var granted = WorldSave.global_flags.get("starting_loadout_granted", false)
	if granted:
		return

	if inventory_component.get_total("ironpipe") <= 0:
		inventory_component.add_item("ironpipe", 1)
		Debug.log("inv", "[INV] loadout inicial agregado: ironpipe")
		WorldSave.global_flags["starting_loadout_granted"] = true

func _setup_weapon_component() -> void:
	if weapon_component == null:
		return

	if inventory_component != null:
		weapon_component.setup_from_inventory(inventory_component)
		if not inventory_component.inventory_changed.is_connected(_on_inventory_changed_rebuild_weapons):
			inventory_component.inventory_changed.connect(_on_inventory_changed_rebuild_weapons)
	else:
		weapon_component.setup_from_inventory(null)

	if not weapon_component.weapon_equipped.is_connected(_on_weapon_equipped_apply_visuals):
		weapon_component.weapon_equipped.connect(_on_weapon_equipped_apply_visuals)
	var ctrl := ensure_player_weapon_controller()
	weapon_component.apply_visuals(self)
	set_weapon_controller(ctrl)

func _ensure_weapon_controller() -> PlayerWeaponController:
	return ensure_player_weapon_controller()

func ensure_player_weapon_controller() -> PlayerWeaponController:
	return weapon_controller

func ensure_ai_weapon_controller() -> AIWeaponController:
	# AIWeaponController for the player is intentionally kept lazy
	# because it's only occasionally used when the player loses control.
	# We don't force it to be in the scene tree by default to avoid clutter.
	if ai_weapon_controller != null:
		return ai_weapon_controller
	ai_weapon_controller = AIWeaponControllerScript.new()
	ai_weapon_controller.name = "AIWeaponController"
	add_child(ai_weapon_controller)
	return ai_weapon_controller

func get_weapon_component() -> WeaponComponent:
	return weapon_component

func set_weapon_controller(controller: WeaponController) -> void:
	if weapon_component == null or controller == null:
		return
	if _current_weapon_controller == controller and weapon_component.current_weapon != null:
		if weapon_component.current_weapon.controller != controller:
			weapon_component.current_weapon.set_controller(controller)
		return
	_current_weapon_controller = controller
	weapon_component.refresh_runtime_weapon_controller(self, _current_weapon_controller)

func set_weapon_controller_mode(mode: StringName) -> void:
	if mode == &"player":
		var player_ctrl := ensure_player_weapon_controller()
		set_weapon_controller(player_ctrl)
		_movement_control_mode = &"player"
		_combat_control_mode = &"player"
		if ai_weapon_controller != null:
			ai_weapon_controller.set_attack_down(false)
	elif mode == &"ai":
		var ai_ctrl := ensure_ai_weapon_controller()
		ai_ctrl.set_attack_down(false)
		set_weapon_controller(ai_ctrl)
		_movement_control_mode = &"ai"
		_combat_control_mode = &"ai"
		if weapon_controller != null and weapon_controller.has_method("set_attack_down"):
			weapon_controller.call("set_attack_down", false)

func on_control_gained() -> void:
	_reset_control_transient_state()
	set_weapon_controller_mode(&"player")

func on_control_lost() -> void:
	_reset_control_transient_state()
	set_weapon_controller_mode(&"ai")

func _reset_control_transient_state() -> void:
	attacking = false
	attack_t = 0.0
	attack_push_t = 0.0
	attack_push_vel = Vector2.ZERO
	blocking = false

	if block_component != null and block_component.is_blocking():
		block_component.blocking = false

	var hitbox := get_node_or_null("CharacterHitbox")
	if hitbox != null and hitbox.has_method("deactivate"):
		hitbox.call("deactivate")

func _on_inventory_changed_rebuild_weapons() -> void:
	if weapon_component == null:
		return
	weapon_component.rebuild_weapon_list_from_inventory(inventory_component)

func _on_weapon_equipped_apply_visuals(_weapon_id: String) -> void:
	if weapon_component == null:
		return
	var ctrl := _current_weapon_controller
	if ctrl == null:
		ctrl = ensure_player_weapon_controller()
	weapon_component.apply_visuals(self)
	weapon_component.equip_runtime_weapon(self, ctrl)

func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	stamina_changed.emit(current_stamina, max_stamina)

func get_current_stamina() -> float:
	if stamina_component == null:
		return 0.0
	return stamina_component.get_current_stamina()

func get_max_stamina() -> float:
	if stamina_component == null:
		return 0.0
	return stamina_component.get_max_stamina()

func get_world_mouse_pos() -> Vector2:
	return get_global_mouse_position()

func get_mouse_angle() -> float:
	return mouse_angle

func is_seated() -> bool:
	return _is_seated

func is_seated_on(seat_node: Node) -> bool:
	if seat_node == null:
		return false
	if not _is_seated:
		return false
	return _seat_source_node() == seat_node

func toggle_stool_seat(seat_node: Node, seat_world_pos: Vector2) -> bool:
	if seat_node == null:
		return _is_seated
	if _is_seated and is_seated_on(seat_node):
		_leave_seat(true)
		return false
	if _is_seated:
		_leave_seat(true)
	_enter_seat(seat_node, seat_world_pos)
	return true

func force_leave_seat() -> void:
	_leave_seat(true)

func _enter_seat(seat_node: Node, seat_world_pos: Vector2) -> void:
	if dying:
		return
	_reset_control_transient_state()
	if weapon_controller != null and weapon_controller.has_method("set_attack_down"):
		weapon_controller.call("set_attack_down", false)
	if ai_weapon_controller != null:
		ai_weapon_controller.set_attack_down(false)
	_is_seated = true
	_seat_source_ref = weakref(seat_node)
	_seat_return_world_pos = global_position
	velocity = Vector2.ZERO
	knock_vel = Vector2.ZERO
	global_position = seat_world_pos
	_set_seated_visual_state(true)
	_update_animation()

func _leave_seat(restore_position: bool = true) -> void:
	if not _is_seated:
		_seat_source_ref = null
		_seat_return_world_pos = Vector2.INF
		return
	var return_pos := _seat_return_world_pos
	_is_seated = false
	_seat_source_ref = null
	_seat_return_world_pos = Vector2.INF
	if restore_position and return_pos != Vector2.INF:
		global_position = return_pos
	velocity = Vector2.ZERO
	knock_vel = Vector2.ZERO
	_set_seated_visual_state(false)
	_update_animation()

func _seat_source_node() -> Node:
	if _seat_source_ref == null:
		return null
	var source: Node = _seat_source_ref.get_ref() as Node
	if source != null and is_instance_valid(source):
		return source
	_seat_source_ref = null
	return null

func _set_seated_visual_state(seated: bool) -> void:
	if weapon_pivot != null:
		weapon_pivot.visible = not seated
	if footstep_audio_component != null and seated:
		footstep_audio_component.stop_loop()

func _ensure_sit_animation() -> void:
	if sprite == null:
		return
	var frames := sprite.sprite_frames
	if frames == null:
		frames = SpriteFrames.new()
		sprite.sprite_frames = frames
	if not frames.has_animation(PLAYER_SIT_ANIMATION):
		frames.add_animation(PLAYER_SIT_ANIMATION)
	frames.set_animation_speed(PLAYER_SIT_ANIMATION, 1.0)
	frames.set_animation_loop(PLAYER_SIT_ANIMATION, false)
	if frames.get_frame_count(PLAYER_SIT_ANIMATION) <= 0 and PLAYER_SIT_TEXTURE != null:
		frames.add_frame(PLAYER_SIT_ANIMATION, PLAYER_SIT_TEXTURE, 1.0)

func _input(event: InputEvent) -> void:
	if dying or is_downed:
		return
	if _movement_control_mode != &"player":
		return
	if UiManager.is_combat_input_blocked():
		return
	if _is_seated:
		_update_seated_facing_from_mouse_motion(event)
		return

	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if weapon_component != null:
				weapon_component.equip_prev()
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if weapon_component != null:
				weapon_component.equip_next()
			return

func _physics_process(delta: float) -> void:
	if dying or is_downed:
		velocity = Vector2.ZERO
		if footstep_audio_component != null:
			footstep_audio_component.stop_loop()
		_update_wall(delta)
		move_and_slide()
		return

	if hurt_t > 0.0:
		hurt_t -= delta

	if _is_seated:
		velocity = Vector2.ZERO
		knock_vel = Vector2.ZERO
		attack_push_t = 0.0
		attack_push_vel = Vector2.ZERO
		attacking = false
		blocking = false
		if block_component != null and block_component.is_blocking():
			block_component.blocking = false
		if footstep_audio_component != null:
			footstep_audio_component.stop_loop()
		_update_animation()
		_update_wall(delta)
		move_and_slide()
		return

	if _movement_control_mode == &"player" and use_movement_component and movement_component != null:
		movement_component.physics_tick(delta)
	elif _movement_control_mode != &"player":
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	else:
		_legacy_movement_physics(delta)

	_update_facing_from_mouse()
	_update_mouse_angle()

	if attacking:
		_snap_to_attack_angle(delta)
	elif _is_currently_blocking():
		if use_block_component and block_component != null:
			block_angle = block_component.get_block_angle()
		else:
			_legacy_block_tick(delta)
		weapon_pivot.rotation = lerp_angle(weapon_pivot.rotation, block_angle, 1.0 - exp(-attack_snap_speed * delta))
	else:
		_update_weapon_aim(delta)

	_update_weapon_flip()
	if weapon_component != null:
		weapon_component.tick(delta)
	if _combat_control_mode == &"player" and use_combat_component and combat_component != null and _should_tick_legacy_combat():
		combat_component.tick(delta)

	if _combat_control_mode == &"player" and use_block_component and block_component != null:
		block_component.tick(delta)
		blocking = block_component.is_blocking()
	else:
		blocking = false

	if use_footstep_audio_component and footstep_audio_component != null:
		footstep_audio_component.physics_tick(delta)
	elif footstep_audio_component != null:
		footstep_audio_component.stop_loop()

	_update_animation()
	if attack_push_t > 0.0:
		attack_push_t -= delta
		velocity += attack_push_vel

	_apply_knockback_step(delta)
	_update_wall(delta)
	move_and_slide()

func _should_tick_legacy_combat() -> bool:
	# Legacy únicamente: cuando no existe WeaponComponent runtime.
	return weapon_component == null

func _update_wall(delta: float) -> void:
	if use_wall_component and wall_occlusion_component != null:
		wall_occlusion_component.physics_tick(delta)
	else:
		_legacy_wall_toggle_update()

func _legacy_movement_physics(delta: float) -> void:
	push_error("LEGACY DESACTIVADO: usa el componente correspondiente")
	return

func _legacy_attack_tick(delta: float) -> void:
	push_error("LEGACY DESACTIVADO: usa el componente correspondiente")
	return

func _legacy_block_tick(delta: float) -> void:
	push_error("LEGACY DESACTIVADO: usa el componente correspondiente")
	return

func _legacy_block_input_and_drain(delta: float) -> void:
	push_error("LEGACY DESACTIVADO: usa el componente correspondiente")
	return

func _is_currently_blocking() -> bool:
	if use_block_component and block_component != null:
		return block_component.is_blocking()
	return blocking

func _legacy_is_hit_blocked(from_pos: Vector2) -> bool:
	if from_pos == Vector2.INF:
		return false
	var to_attacker := (from_pos - global_position)
	if to_attacker.length() < 0.001:
		return true
	to_attacker = to_attacker.normalized()
	var block_dir := Vector2.RIGHT.rotated(mouse_angle)
	var dot := clampf(block_dir.dot(to_attacker), -1.0, 1.0)
	var ang := acos(dot)
	var half_cone := deg_to_rad(block_wiggle_deg + block_guard_margin_deg)
	return ang <= half_cone

func _update_facing_from_mouse() -> void:
	var dx := get_global_mouse_position().x - global_position.x
	if abs(dx) > facing_deadzone_px:
		sprite.flip_h = dx < 0.0

func _update_mouse_angle() -> void:
	var dir := get_global_mouse_position() - global_position
	if dir.length() > 0.001:
		mouse_angle = dir.angle()

func _update_weapon_aim(delta: float) -> void:
	weapon_pivot.rotation = lerp_angle(weapon_pivot.rotation, mouse_angle, 1.0 - exp(-weapon_follow_speed * delta))

func _snap_to_attack_angle(delta: float) -> void:
	weapon_pivot.rotation = lerp_angle(weapon_pivot.rotation, target_attack_angle, 1.0 - exp(-attack_snap_speed * delta))

func _calculate_attack_angle() -> void:
	var base_angle := mouse_angle
	target_attack_angle = base_angle + deg_to_rad(angle_offset_left if use_left_offset else angle_offset_right)
	use_left_offset = not use_left_offset

# API pública para spawnear el slash sin acoplarse a detalles internos.
func spawn_slash(angle: float) -> void:
	_spawn_slash(angle)

func _spawn_slash(angle: float) -> void:
	if slash_scene == null:
		return
	var parent := get_tree().current_scene
	if parent == null:
		return
	var s = slash_scene.instantiate()
	s.setup(&"player", self)
	s.position = parent.to_local(slash_spawn.global_position)
	s.rotation = angle + deg_to_rad(slash_visual_offset_deg)
	parent.add_child(s)
	if vfx_component != null and use_vfx_component:
		vfx_component.play_attack_vfx()

func _legacy_play_attack_vfx() -> void:
	push_error("LEGACY DESACTIVADO: usa el componente correspondiente")
	return

func _try_attack_push() -> void:
	if velocity.length() > attack_push_deadzone:
		return
	var dir := get_global_mouse_position() - global_position
	if dir.length() < 0.001:
		return
	attack_push_vel = dir.normalized() * attack_push_speed
	attack_push_t = attack_push_time

func _update_weapon_flip() -> void:
	var angle := wrapf(weapon_pivot.rotation, -PI, PI)
	weapon_sprite.flip_v = abs(angle) > PI / 2.0

func _update_animation() -> void:
	if _is_seated:
		if sprite.animation != PLAYER_SIT_ANIMATION:
			sprite.play(PLAYER_SIT_ANIMATION)
		return
	if hurt_t > 0.0:
		return
	sprite.play("walk" if velocity.length() > 5.0 else "idle")

func take_damage(dmg: int, from_pos: Vector2 = Vector2.INF) -> void:
	var blocked := false
	if _is_currently_blocking() and stamina_component != null:
		if use_block_component and block_component != null:
			blocked = block_component.can_block_hit(from_pos)
		else:
			blocked = _legacy_is_hit_blocked(from_pos)

	if blocked:
		if use_block_component and block_component != null:
			block_component.on_blocked_hit()
		else:
			var cost := stamina_component.max_stamina * block_hit_stamina_cost
			if not stamina_component.spend(cost):
				blocking = false
		emit_signal("took_damage", 0)
		if use_vfx_component and vfx_component != null:
			vfx_component.play_block_vfx()
		return

	super.take_damage(dmg, from_pos)
	emit_signal("took_damage", dmg)
	_update_hearts_ui()

	if hp <= 0:
		return

	var hit_dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	if from_pos != Vector2.INF:
		hit_dir = (global_position - from_pos).normalized()

	if use_vfx_component and vfx_component != null:
		vfx_component.play_hit_vfx(hit_dir, false)
		vfx_component.play_hit_flash()
	else:
		_spawn_droplets(droplet_count_hit, hit_dir)

func _on_health_damaged(_amount: int) -> void:
	hp = health_component.hp if health_component != null else hp
	_update_hearts_ui()

func _on_CharacterHurtbox_damaged(dmg: int, from_pos: Vector2) -> void:
	take_damage(dmg, from_pos)

func _update_hearts_ui() -> void:
	if hearts_ui != null and hearts_ui.has_method("set_hearts"):
		hearts_ui.set("max_hearts", max_hp)
		hearts_ui.call("set_hearts", hp)

func _resolve_walk_surface_id(world_pos: Vector2) -> StringName:
	var world := _resolve_world_node()
	if world == null or not world.has_method("get_walk_surface_at_world_pos"):
		return &"grass"
	var result: Variant = world.call("get_walk_surface_at_world_pos", world_pos)
	if typeof(result) == TYPE_STRING_NAME:
		var surface_id: StringName = result
		return surface_id
	if typeof(result) == TYPE_STRING:
		var raw: String = String(result).strip_edges()
		if not raw.is_empty():
			return StringName(raw)
	return &"grass"

func _resolve_world_node() -> Node:
	if _world_node_ref != null:
		var cached: Node = _world_node_ref.get_ref() as Node
		if cached != null and is_instance_valid(cached):
			return cached
		_world_node_ref = null
	var worlds: Array = get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		return null
	var world: Node = worlds[0] as Node
	_world_node_ref = weakref(world)
	return world

func _on_entered_downed() -> void:
	super._on_entered_downed()
	_trigger_death_shake()
	weapon_sprite.visible = false
	if footstep_audio_component != null:
		footstep_audio_component.stop_loop()

func _on_revived() -> void:
	super._on_revived()
	weapon_sprite.visible = true
	_update_hearts_ui()

func _trigger_death_shake() -> void:
	var cam := get_node_or_null("Camera2D")
	if cam and cam.has_method("shake_impulse"):
		cam.shake_impulse(death_shake_duration, death_shake_magnitude)
	elif cam and cam.has_method("shake"):
		cam.shake(death_shake_magnitude)

func _on_before_die() -> void:
	_trigger_death_shake()
	_leave_seat(false)
	weapon_sprite.visible = false
	hurt_t = 0.0
	attacking = false
	attack_push_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO

func _on_after_die() -> void:
	GameManager.player_died.emit()

func respawn(pos: Vector2) -> void:
	_leave_seat(false)
	dying = false
	is_downed = false
	if downed_component != null:
		downed_component.reset()
	hurt_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	attacking = false
	attack_t = 0.0
	attack_push_t = 0.0
	attack_push_vel = Vector2.ZERO
	blocking = false
	if health_component != null and health_component.has_method("reset"):
		health_component.reset()
		hp = health_component.hp
	else:
		hp = max_hp
	weapon_sprite.visible = true
	sprite.play("idle")
	global_position = pos
	_update_hearts_ui()

func _spawn_droplets(count: int, base_dir: Vector2) -> void:
	if droplet_scene == null:
		return
	var existing := get_tree().get_nodes_in_group("blood_droplet").size()
	var allowed := mini(count, MAX_DROPLETS_IN_SCENE - existing)
	if allowed <= 0:
		return
	for i in range(allowed):
		var d := droplet_scene.instantiate() as RigidBody2D
		if d == null:
			continue
		d.add_to_group("blood_droplet")
		get_tree().current_scene.add_child(d)
		d.global_position = global_position
		var ang := randf_range(-deg_to_rad(droplet_spread_deg), deg_to_rad(droplet_spread_deg))
		var dir := base_dir.rotated(ang)
		d.linear_velocity = dir * randf_range(droplet_speed_min, droplet_speed_max)

func _legacy_wall_toggle_update() -> void:
	push_error("LEGACY DESACTIVADO: usa el componente correspondiente")
	return

func _exit_tree() -> void:
	_leave_seat(false)
	if footstep_audio_component != null:
		footstep_audio_component.stop_loop()
	if wall_occlusion_component != null:
		wall_occlusion_component.close()

func get_inventory() -> Node:
	return inventory_component


func _update_seated_facing_from_mouse_motion(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	var motion := event as InputEventMouseMotion
	if absf(motion.relative.x) <= 0.05:
		return
	# Mantiene el lado inicial al sentarse y solo gira cuando hay movimiento horizontal real.
	sprite.flip_h = motion.relative.x < 0.0
