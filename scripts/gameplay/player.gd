class_name Player
extends CharacterBody2D

var DEBUG_PLAYER := OS.is_debug_build()
const HealthComponentScript = preload("res://scripts/components/HealthComponent.gd")
const InventoryComponentScript = preload("res://scripts/components/InventoryComponent.gd")

@onready var stamina_component: StaminaComponent = get_node_or_null("StaminaComponent") as StaminaComponent
@onready var movement_component: MovementComponent = get_node_or_null("MovementComponent") as MovementComponent
@onready var combat_component: CombatComponent = get_node_or_null("CombatComponent") as CombatComponent
@onready var block_component: BlockComponent = get_node_or_null("BlockComponent") as BlockComponent
@onready var wall_occlusion_component: WallOcclusionComponent = get_node_or_null("WallOcclusionComponent") as WallOcclusionComponent
@onready var vfx_component: VFXComponent = get_node_or_null("VFXComponent") as VFXComponent

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
@export var max_hp: int = 3
@export var hearts_ui: Node
var hp: int

@export_group("Attack Push")
@export var attack_push_speed: float = 220.0
@export var attack_push_time: float = 0.08
@export var attack_push_deadzone: float = 15.0

@export_group("Knockback")
@export var knockback_friction: float = 2200.0

@export_group("Juice")
@export var hurt_time: float = 0.15

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
@onready var health_component: Node = get_node_or_null("HealthComponent")
@onready var inventory: Node = get_node_or_null("InventoryComponent")

@export_group("FX")
@export var blood_scene: PackedScene
@export var blood_hit_amount: int = 12
@export var blood_death_amount: int = 40
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
var knock_vel: Vector2 = Vector2.ZERO
var hurt_t: float = 0.0
var dying: bool = false

var blocking: bool = false
var block_angle: float = 0.0
@export var block_stamina_drain: float = 12.0
@export var block_hit_stamina_cost: float = 0.10
@export var block_wiggle_deg: float = 60.0
@export var block_wiggle_hz: float = 6.0
var block_wiggle_t: float = 0.0

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
	_update_hearts_ui()
	var listener := AudioListener2D.new()
	add_child(listener)
	listener.make_current()
	weapon_sprite.visible = true
	weapon_sprite.show()
	if inventory != null and DEBUG_PLAYER:
		inventory.debug_print()
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
	# if wall_occlusion_component != null:
	# 	wall_occlusion_component.setup(self)
	# 	if Debug.safe_mode and Debug.disable_wall_occlusion:
	# 		wall_occlusion_component.set_enabled(false)
	# else:
	# 	push_warning("[Player] Missing WallOcclusionComponent")
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
		collision_mask = 2

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
	if health_component == null:
		health_component = HealthComponentScript.new()
		health_component.name = "HealthComponent"
		add_child(health_component)
	if health_component != null:
		health_component.max_hp = max_hp
		health_component.hp = max_hp
		if health_component.has_signal("damaged") and not health_component.damaged.is_connected(_on_health_damaged):
			health_component.damaged.connect(_on_health_damaged)
		if not health_component.died.is_connected(die):
			health_component.died.connect(die)
		hp = health_component.hp
	else:
		hp = max_hp

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
	if inventory == null:
		inventory = InventoryComponentScript.new()
		inventory.name = "InventoryComponent"
		add_child(inventory)
		Debug.log("inv", "[INV] InventoryComponent creado en Player")

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

func _input(event: InputEvent) -> void:
	if inventory == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_1:
			inventory.add_item("copper", 3)
			if DEBUG_PLAYER: inventory.debug_print()
		elif key_event.keycode == KEY_2:
			inventory.sell_all("copper", 5)
			if DEBUG_PLAYER: inventory.debug_print()
		elif key_event.keycode == KEY_3:
			inventory.buy_item("medkit", 1, 20)
			if DEBUG_PLAYER: inventory.debug_print()
		elif key_event.keycode == KEY_4:
			inventory.gold += 50
			Debug.log("inv", "[INV] cheat +50 gold. gold=%s" % inventory.gold)
			if DEBUG_PLAYER: inventory.debug_print()

func _physics_process(delta: float) -> void:
	if dying:
		velocity = Vector2.ZERO
		_update_wall(delta)
		move_and_slide()
		return

	if hurt_t > 0.0:
		hurt_t -= delta

	if use_movement_component and movement_component != null:
		movement_component.physics_tick(delta)
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
	if use_combat_component and combat_component != null:
		combat_component.tick(delta)
	else:
		_legacy_attack_tick(delta)

	if use_block_component and block_component != null:
		block_component.tick(delta)
		blocking = block_component.is_blocking()
	else:
		_legacy_block_input_and_drain(delta)

	_update_animation()
	if attack_push_t > 0.0:
		attack_push_t -= delta
		velocity += attack_push_vel

	velocity += knock_vel
	knock_vel = knock_vel.move_toward(Vector2.ZERO, knockback_friction * delta)
	_update_wall(delta)
	move_and_slide()

func _update_wall(delta: float) -> void:
	pass  # Oclusión manejada por OcclusionStripBuilder en world.gd

func _legacy_movement_physics(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		last_direction = input_dir
		var current_speed := acceleration
		if velocity.length() > 0.0 and velocity.normalized().dot(input_dir) < 0.5:
			current_speed = turn_speed
		velocity = velocity.move_toward(input_dir * max_speed, current_speed * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func _legacy_attack_tick(delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not attacking:
		if stamina_component == null or not stamina_component.has_method("spend_attack_cost"):
			return
		if not stamina_component.spend_attack_cost():
			return
		emit_signal("request_attack")
		_calculate_attack_angle()
		_spawn_slash(mouse_angle)
		_try_attack_push()
		attacking = true
		attack_t = 0.0
	if attacking:
		attack_t += delta
		if attack_t >= attack_duration:
			attacking = false

func _legacy_block_tick(delta: float) -> void:
	block_wiggle_t += delta
	var wiggle_rad := deg_to_rad(block_wiggle_deg) * sin(block_wiggle_t * TAU * block_wiggle_hz)
	block_angle = mouse_angle + wiggle_rad

func _legacy_block_input_and_drain(delta: float) -> void:
	if Input.is_action_just_pressed("block"):
		if stamina_component != null and stamina_component.current_stamina > 0.0:
			blocking = true
			block_wiggle_t = 0.0
			emit_signal("block_started")
	if Input.is_action_just_released("block"):
		if blocking:
			blocking = false
			emit_signal("block_ended")
	if blocking and stamina_component != null:
		var drained := (block_stamina_drain * 2.0) * delta
		stamina_component.current_stamina = maxf(stamina_component.current_stamina - drained, 0.0)
		stamina_component.stamina_changed.emit(stamina_component.current_stamina, stamina_component.max_stamina)
		if stamina_component.current_stamina <= 0.0:
			blocking = false
			emit_signal("block_ended")

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

func _spawn_slash(angle: float) -> void:
	if slash_scene == null:
		return
	var s = slash_scene.instantiate()
	s.setup(&"player", self)
	get_tree().current_scene.add_child(s)
	s.global_position = slash_spawn.global_position
	s.global_rotation = angle + deg_to_rad(slash_visual_offset_deg)
	_legacy_play_attack_vfx()

func _legacy_play_attack_vfx() -> void:
	if has_node("Camera2D"):
		$Camera2D.shake(4.0)

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
			stamina_component.current_stamina = maxf(stamina_component.current_stamina - cost, 0.0)
			stamina_component.stamina_changed.emit(stamina_component.current_stamina, stamina_component.max_stamina)
			if stamina_component.current_stamina <= 0.0:
				blocking = false
		emit_signal("took_damage", 0)
		if use_vfx_component and vfx_component != null:
			vfx_component.play_block_vfx()
		return

	if health_component != null and health_component.has_method("take_damage"):
		health_component.take_damage(dmg)
		hp = health_component.hp
	else:
		hp -= dmg

	emit_signal("took_damage", dmg)
	_update_hearts_ui()

	var hit_dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	if from_pos != Vector2.INF:
		hit_dir = (global_position - from_pos).normalized()

	if use_vfx_component and vfx_component != null:
		vfx_component.play_hit_vfx(hit_dir, hp <= 0)
	else:
		_spawn_blood(blood_hit_amount)
		_spawn_droplets(droplet_count_hit, hit_dir)
		if hp <= 0:
			_spawn_blood(blood_death_amount)
			_spawn_droplets(droplet_count_death, hit_dir)

	if hp <= 0:
		if health_component == null:
			die()
		return

	play_hurt()
	if use_vfx_component and vfx_component != null:
		vfx_component.play_hit_flash()
	else:
		sprite.modulate = Color(1, 0.5, 0.5, 1)
		get_tree().create_timer(0.06).timeout.connect(func():
			if is_instance_valid(self):
				sprite.modulate = Color(1, 1, 1, 1)
		)

func play_hurt() -> void:
	hurt_t = hurt_time
	sprite.play("hurt")
	get_tree().create_timer(hurt_time).timeout.connect(func():
		if is_instance_valid(self) and hp > 0:
			_update_animation()
	)

func apply_knockback(force: Vector2) -> void:
	knock_vel += force

func _on_health_damaged(_amount: int) -> void:
	hp = health_component.hp if health_component != null else hp
	_update_hearts_ui()

func _update_hearts_ui() -> void:
	if hearts_ui != null and hearts_ui.has_method("set_hearts"):
		hearts_ui.set("max_hearts", max_hp)
		hearts_ui.call("set_hearts", hp)

func die() -> void:
	if dying:
		return
	dying = true
	weapon_sprite.visible = false
	hurt_t = 0.0
	attacking = false
	attack_push_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	sprite.play("death")
	await sprite.animation_finished
	GameManager.player_died.emit()
	queue_free()

func _spawn_blood(amount: int) -> void:
	if blood_scene == null:
		return
	var p := blood_scene.instantiate() as GPUParticles2D
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.amount = amount
	p.one_shot = true
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.1).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)

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
	if wall_occlusion_component != null:
		wall_occlusion_component.on_player_moved(global_position)

func _exit_tree() -> void:
	if wall_occlusion_component != null:
		wall_occlusion_component.close()

func get_inventory() -> Node:
	return inventory
