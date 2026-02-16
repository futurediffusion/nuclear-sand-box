class_name Player
extends CharacterBody2D

const HealthComponentScript = preload("res://scripts/components/HealthComponent.gd")

# =============================================================================
# MOVIMIENTO
# =============================================================================
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
@export var attack_push_speed: float = 220.0     # fuerza del empujón
@export var attack_push_time: float = 0.08       # cuánto dura
@export var attack_push_deadzone: float = 15.0   # si ya te estás moviendo, no aplica

@export_group("Knockback")
@export var knockback_friction: float = 2200.0   # qué tan rápido se detiene el empuje cuando te pegan

@export_group("Juice")
@export var hurt_time: float = 0.15  # cuánto dura la animación hurt

# =============================================================================
# ARMA / APUNTADO / ATAQUE
# =============================================================================
@export_group("Weapon")
@export var weapon_follow_speed: float = 25.0
@export var attack_snap_speed: float = 50.0
@export var attack_duration: float = 0.3
@export var facing_deadzone_px: float = 2.0

# Offsets relativos al ángulo del mouse (SOLO para el arma visual)
@export_group("Attack Angles")
@export var angle_offset_left: float = -150.0     # Offset cuando alterna a la izquierda
@export var angle_offset_right: float = 150.0     # Offset cuando alterna a la derecha

@export_group("Slash")
@export var slash_scene: PackedScene
@export var slash_visual_offset_deg: float = 0.0  # Por si el sprite del slash está rotado

# =============================================================================
# NODOS
# =============================================================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: Sprite2D = $WeaponPivot/WeaponSprite
@onready var slash_spawn: Marker2D = $WeaponPivot/SlashSpawn
@onready var health_component: Node = get_node_or_null("HealthComponent")

#____________________
# SANGRE
#*******************
@export_group("FX")
@export var blood_scene: PackedScene
@export var blood_hit_amount: int = 12
@export var blood_death_amount: int = 40
#____________________
# DROPLETS
#*******************

@export var droplet_scene: PackedScene
@export var splat_scene: PackedScene
@export var splat_lifetime: float = 60.0

@export var droplet_count_hit: int = 6
@export var droplet_count_death: int = 14
@export var droplet_speed_min: float = 80.0
@export var droplet_speed_max: float = 140.0
@export var droplet_spread_deg: float = 70.0


# =============================================================================
# ESTADO
# =============================================================================
var last_direction: Vector2 = Vector2.RIGHT
var mouse_angle: float = 0.0

var attacking := false
var attack_t := 0.0

# Sistema de alternancia (SOLO para el arma)
var use_left_offset: bool = false
var target_attack_angle: float = 0.0

var attack_push_vel: Vector2 = Vector2.ZERO
var attack_push_t: float = 0.0

# Knockback cuando te pegan
var knock_vel: Vector2 = Vector2.ZERO

# Sistema hurt
var hurt_t: float = 0.0
var dying: bool = false


# =============================================================================
func _ready() -> void:
	sprite.play("idle")
	sprite.flip_h = false
	add_to_group("player")
	sprite.z_index = 0
	weapon_pivot.z_index = 10
	weapon_sprite.z_index = 10
	_resolve_hearts_ui()
	_setup_health_component()
	_update_hearts_ui()
	weapon_sprite.visible = true
	weapon_sprite.show()

func _resolve_hearts_ui() -> void:
	if hearts_ui != null:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

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

func _physics_process(delta: float) -> void:
	# 0) Si está muriendo: no hacer nada más
	if dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 1) Actualizar timer de hurt
	if hurt_t > 0.0:
		hurt_t -= delta

	_process_movement(delta)
	_update_facing_from_mouse()
	_update_mouse_angle()

	if attacking:
		_snap_to_attack_angle(delta)
	else:
		_update_weapon_aim(delta)

	_update_weapon_flip()
	_process_attack(delta)
	_update_animation()
	


	# Empujón corto del ataque (solo dura attack_push_time)
	if attack_push_t > 0.0:
		attack_push_t -= delta
		velocity += attack_push_vel

	# Knockback cuando te pegan (se va frenando con fricción)
	velocity += knock_vel
	knock_vel = knock_vel.move_toward(Vector2.ZERO, knockback_friction * delta)

	move_and_slide()
	
	# Empujón corto del ataque (solo dura attack_push_time)
	if attack_push_t > 0.0:
		attack_push_t -= delta
		velocity += attack_push_vel
	
	# Knockback cuando te pegan (se va frenando con fricción)
	velocity += knock_vel
	knock_vel = knock_vel.move_toward(Vector2.ZERO, knockback_friction * delta)

	move_and_slide()

# =============================================================================
# MOVIMIENTO SUAVE
# =============================================================================
func _process_movement(delta: float) -> void:
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

# =============================================================================
# PERSONAJE MIRA AL MOUSE
# =============================================================================
func _update_facing_from_mouse() -> void:
	var mouse := get_global_mouse_position()
	var dx := mouse.x - global_position.x

	if abs(dx) > facing_deadzone_px:
		sprite.flip_h = dx < 0.0

# =============================================================================
# CALCULAR ÁNGULO HACIA EL MOUSE
# =============================================================================
func _update_mouse_angle() -> void:
	var mouse := get_global_mouse_position()
	var dir := mouse - global_position
	if dir.length() > 0.001:
		mouse_angle = dir.angle()

# =============================================================================
# APUNTADO SUAVE (cuando NO está atacando)
# =============================================================================
func _update_weapon_aim(delta: float) -> void:
	weapon_pivot.rotation = lerp_angle(
		weapon_pivot.rotation,
		mouse_angle,
		1.0 - exp(-weapon_follow_speed * delta)
	)

# =============================================================================
# SNAP RÁPIDO AL ÁNGULO DE ATAQUE
# =============================================================================
func _snap_to_attack_angle(delta: float) -> void:
	weapon_pivot.rotation = lerp_angle(
		weapon_pivot.rotation,
		target_attack_angle,
		1.0 - exp(-attack_snap_speed * delta)
	)

# =============================================================================
# ATAQUE CON OFFSETS RELATIVOS AL MOUSE
# =============================================================================
func _process_attack(delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not attacking:
		_calculate_attack_angle()
		_spawn_slash(mouse_angle)
		_try_attack_push()
		attacking = true
		attack_t = 0.0

	if attacking:
		attack_t += delta
		
		if attack_t >= attack_duration:
			attacking = false

func _calculate_attack_angle() -> void:
	# El ángulo base es donde apunta el mouse
	var base_angle := mouse_angle
	
	# Agregar offset según alternancia (SOLO para el arma visual)
	if use_left_offset:
		target_attack_angle = base_angle + deg_to_rad(angle_offset_left)
	else:
		target_attack_angle = base_angle + deg_to_rad(angle_offset_right)
	
	# Alternar para el próximo ataque
	use_left_offset = not use_left_offset

func _spawn_slash(angle: float) -> void:
	if slash_scene == null:
		return

	var s = slash_scene.instantiate()

	# primero setup
	s.setup(&"player", self)

	# ahora lo metes a la escena
	get_tree().current_scene.add_child(s)

	s.global_position = slash_spawn.global_position
	s.global_rotation = angle + deg_to_rad(slash_visual_offset_deg)
	
	# camera shake pequeño al atacar
	if has_node("Camera2D"):
		$Camera2D.shake(4.0)

func _try_attack_push() -> void:
	# Solo si NO estás moviendo con WASD (o sea, casi quieto)
	if velocity.length() > attack_push_deadzone:
		return

	var mouse_pos := get_global_mouse_position()
	var dir := (mouse_pos - global_position)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()

	attack_push_vel = dir * attack_push_speed
	attack_push_t = attack_push_time

# =============================================================================
# FLIP DEL ARMA
# =============================================================================
func _update_weapon_flip() -> void:
	var angle := wrapf(weapon_pivot.rotation, -PI, PI)
	
	if abs(angle) > PI / 2.0:
		weapon_sprite.flip_v = true
	else:
		weapon_sprite.flip_v = false

# =============================================================================
# ANIMACIONES
# =============================================================================
func _update_animation() -> void:
	# NO cambiar animación si está en hurt
	if hurt_t > 0.0:
		return
	
	var is_moving := velocity.length() > 5.0

	if is_moving:
		sprite.play("walk")
	else:
		sprite.play("idle")

# =============================================================================
# RECIBIR DAÑO
# =============================================================================
func take_damage(dmg: int, from_pos: Vector2 = Vector2.INF) -> void:
	if health_component != null and health_component.has_method("take_damage"):
		health_component.take_damage(dmg)
		hp = health_component.hp
	else:
		hp -= dmg

	print("PLAYER HP:", hp)
	_update_hearts_ui()

	_spawn_blood(blood_hit_amount)

	# Dirección del golpe (si no la mandan, sale random)
	var hit_dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	if from_pos != Vector2.INF:
		hit_dir = (global_position - from_pos).normalized()

	_spawn_droplets(droplet_count_hit, hit_dir)

	if hp <= 0:
		_spawn_blood(blood_death_amount)
		_spawn_droplets(droplet_count_death, hit_dir)
		if health_component == null:
			die()
		return

	play_hurt()
	sprite.modulate = Color(1, 0.5, 0.5, 1)
	get_tree().create_timer(0.06).timeout.connect(func():
		if is_instance_valid(self):
			sprite.modulate = Color(1, 1, 1, 1)
	)


func play_hurt() -> void:
	hurt_t = hurt_time
	sprite.play("hurt")
	
	# Cuando termine la animación hurt, volver a idle/walk automáticamente
	# (solo si el player sigue vivo)
	get_tree().create_timer(hurt_time).timeout.connect(func():
		if is_instance_valid(self) and hp > 0:
			_update_animation()
	)

# =============================================================================
# KNOCKBACK (llamado desde el slash del enemigo)
# =============================================================================
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

	# Esconder arma
	weapon_sprite.visible = false

	# Limpiar estados para que nada "pise" la animación
	hurt_t = 0.0
	attacking = false
	attack_push_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO

	# Reproducir animación de muerte
	sprite.play("death")

	# Esperar a que termine (IMPORTANTE: death debe NO tener loop)
	await sprite.animation_finished

	# Avisar al Main (Game Over)
	var main = get_tree().current_scene
	if main and main.has_method("on_player_died"):
		main.call("on_player_died")

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

	for i in range(count):
		var d := droplet_scene.instantiate() as RigidBody2D
		get_tree().current_scene.add_child(d)
		d.global_position = global_position

		# abanico alrededor de la dirección del golpe
		var ang := randf_range(-deg_to_rad(droplet_spread_deg), deg_to_rad(droplet_spread_deg))
		var dir := base_dir.rotated(ang)

		var spd := randf_range(droplet_speed_min, droplet_speed_max)
		d.linear_velocity = dir * spd
