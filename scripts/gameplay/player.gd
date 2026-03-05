class_name Player
extends CharacterBase

var DEBUG_PLAYER := OS.is_debug_build()
const InventoryComponentScript = preload("res://scripts/components/InventoryComponent.gd")
const AIWeaponControllerScript = preload("res://scripts/weapons/AIWeaponController.gd")

@onready var stamina_component: StaminaComponent = get_node_or_null("StaminaComponent") as StaminaComponent
@onready var movement_component: MovementComponent = get_node_or_null("MovementComponent") as MovementComponent
@onready var combat_component: CombatComponent = get_node_or_null("CombatComponent") as CombatComponent
@onready var block_component: BlockComponent = get_node_or_null("BlockComponent") as BlockComponent
@onready var wall_occlusion_component: WallOcclusionComponent = get_node_or_null("WallOcclusionComponent") as WallOcclusionComponent
@onready var vfx_component: VFXComponent = get_node_or_null("VFXComponent") as VFXComponent
@onready var CharacterHurtbox: CharacterHurtbox = get_node_or_null("CharacterHurtbox") as CharacterHurtbox

@export_group("Component Toggles")
@export var use_movement_component := true
@export var use_combat_component := true
@export var use_block_component := true
@export var use_wall_component := true
@export var use_vfx_component := true

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


signal stamina_changed(stamina: float, max_stamina: float)
signal request_attack
signal took_damage(amount: int)
signal picked_item(item_id: String, amount: int)
signal block_started
signal block_ended

func player_debug(message: String) -> void:
	if DEBUG_PLAYER:
		print(message)

func _ready() -> void:
	Debug.log("boot", "Player ready begin")
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
	_grant_temporary_starting_weapon()
	_setup_weapon_component()
	_update_hearts_ui()
	var listener := AudioListener2D.new()
	add_child(listener)
	listener.make_current()
	if inventory_component != null and DEBUG_PLAYER:
		inventory_component.debug_print()
	Debug.log("boot", "Player ready end")
	var db := get_node("/root/ItemDB")
	print("ItemDB=", db)
	print("Copper item=", db.get_item("copper"))
	print("Copper icon=", db.get_icon("copper"))

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

func _configure_collision_mode() -> void:
	if Debug.use_legacy_wall_collision:
		collision_mask = 1
	else:
		collision_mask = 2 | 16

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
	if CharacterHurtbox != null and not CharacterHurtbox.damaged.is_connected(_on_CharacterHurtbox_damaged):
		CharacterHurtbox.damaged.connect(_on_CharacterHurtbox_damaged)

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
		inventory_component = InventoryComponentScript.new()
		inventory_component.name = "InventoryComponent"
		add_child(inventory_component)
		Debug.log("inv", "[INV] InventoryComponent creado en Player")


func _grant_temporary_starting_weapon() -> void:
	if inventory_component == null:
		return
	if inventory_component.get_total("ironpipe") > 0:
		return
	inventory_component.add_item("ironpipe", 1)
	Debug.log("inv", "[INV] arma temporal inicial agregada: ironpipe")

func _setup_weapon_component() -> void:
	if weapon_component == null:
		weapon_component = WeaponComponent.new()
		weapon_component.name = "WeaponComponent"
		add_child(weapon_component)

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
	if weapon_controller != null:
		return weapon_controller
	weapon_controller = PlayerWeaponController.new()
	weapon_controller.name = "PlayerWeaponController"
	add_child(weapon_controller)
	return weapon_controller

func ensure_ai_weapon_controller() -> AIWeaponController:
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

func _input(event: InputEvent) -> void:
	if _movement_control_mode != &"player":
		return
	if UiManager.is_combat_input_blocked():
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

	if inventory_component == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_1:
			inventory_component.add_item("copper", 3)
			if DEBUG_PLAYER: inventory_component.debug_print()
		elif key_event.keycode == KEY_2:
			inventory_component.sell_all("copper", 5)
			if DEBUG_PLAYER: inventory_component.debug_print()
		elif key_event.keycode == KEY_3:
			inventory_component.buy_item("medkit", 1, 20)
			if DEBUG_PLAYER: inventory_component.debug_print()
		elif key_event.keycode == KEY_4:
			inventory_component.gold += 50
			Debug.log("inv", "[INV] cheat +50 gold. gold=%s" % inventory_component.gold)
			if DEBUG_PLAYER: inventory_component.debug_print()

func _physics_process(delta: float) -> void:
	if dying:
		velocity = Vector2.ZERO
		_update_wall(delta)
		move_and_slide()
		return

	if hurt_t > 0.0:
		hurt_t -= delta

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
	var s = slash_scene.instantiate()
	s.setup(&"player", self)
	get_tree().current_scene.add_child(s)
	s.global_position = slash_spawn.global_position
	s.global_rotation = angle + deg_to_rad(slash_visual_offset_deg)
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

func _on_before_die() -> void:
	weapon_sprite.visible = false
	hurt_t = 0.0
	attacking = false
	attack_push_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO

func _on_after_die() -> void:
	GameManager.player_died.emit()
	queue_free()

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
	if wall_occlusion_component != null:
		wall_occlusion_component.close()

func get_inventory() -> Node:
	return inventory_component
