class_name EnemyAI
extends CharacterBody2D

# =============================================================================
# STATS & CONFIG
# =============================================================================
@export_group("Combat")
@export var max_hp: int = 3
@export var attack_damage: int = 1
@export var attack_cooldown: float = 0.8
@export var attack_range: float = 60.0

@export_group("Movement")
@export var max_speed: float = 280.0  # Ligeramente más lento que player
@export var acceleration: float = 1000.0
@export var friction: float = 1500.0

@export_group("AI Behavior")
@export var detection_range: float = 400.0
@export var aggro_range: float = 350.0
@export var personal_space: float = 50.0  # Distancia mínima antes de retroceder
@export var circle_distance: float = 80.0  # Distancia ideal de combate
@export var predict_distance: float = 150.0  # Cuánto predice movimiento del player

@export_group("Tactics")
@export var feint_chance: float = 0.3  # 30% chance de hacer finta
@export var dodge_chance: float = 0.4  # 40% chance de esquivar
@export var aggressive_chance: float = 0.5  # 50% chance de ser agresivo
@export var patience_time: float = 2.0  # Tiempo antes de cambiar táctica

@export_group("References")
@export var slash_scene: PackedScene

@export_group("Juice")
@export var hurt_time: float = 0.15       # cuanto dura "hurt"
@export var hitstop_time: float = 0.04    # mini freeze
@export var hitstop_time_scale: float = 0.05
@export var knockback_damp: float = 16.0  # que tan rapido se apaga el empuje

# =============================================================================
# SANGRE
# =============================================================================

@export_group("FX")
@export var blood_scene: PackedScene
@export var blood_hit_amount: int = 10
@export var blood_death_amount: int = 30

var dying: bool = false


# =============================================================================
# NODOS
# =============================================================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: Sprite2D = $WeaponPivot/WeaponSprite
@onready var slash_spawn: Marker2D = $WeaponPivot/SlashSpawn
@onready var detection_timer: Timer = Timer.new()
@onready var tactic_timer: Timer = Timer.new()

# =============================================================================
# ESTADO DE COMBATE
# =============================================================================
var hp: int
var player: CharacterBody2D = null
var can_attack: bool = true

# Estados de IA
enum AIState { IDLE, PATROL, CHASE, COMBAT, RETREAT, CIRCLE, FEINT }
var current_state: AIState = AIState.IDLE
var previous_state: AIState = AIState.IDLE

# Tácticas
var is_aggressive: bool = false
var is_feinting: bool = false
var feint_direction: Vector2 = Vector2.ZERO
var circle_clockwise: bool = true
var last_player_pos: Vector2 = Vector2.ZERO
var predicted_player_pos: Vector2 = Vector2.ZERO

# Weapon system (igual que player)
var weapon_follow_speed: float = 25.0
var attack_snap_speed: float = 50.0
var attacking: bool = false
var attack_t: float = 0.0
var use_left_offset: bool = false
var target_attack_angle: float = 0.0
var angle_offset_left: float = -150.0
var angle_offset_right: float = 150.0

# Timers internos
var state_timer: float = 0.0
var dodge_timer: float = 0.0

@export_group("Knockback")
@export var knockback_friction: float = 2200.0

var knock_vel: Vector2 = Vector2.ZERO

var hurt_t: float = 0.0
var hitstopping: bool = false


# =============================================================================
# READY
# =============================================================================
func _ready() -> void:
	hp = max_hp
	sprite.play("idle")
	
	# Setup z-index
	sprite.z_index = 0
	weapon_pivot.z_index = 10
	weapon_sprite.z_index = 10
	weapon_sprite.visible = true
	
	# Timers
	add_child(detection_timer)
	detection_timer.wait_time = 0.2
	detection_timer.timeout.connect(_update_detection)
	detection_timer.start()
	
	add_child(tactic_timer)
	tactic_timer.wait_time = patience_time
	tactic_timer.timeout.connect(_change_tactic)
	tactic_timer.start()
	
	# Encontrar player
	call_deferred("_find_player")

func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

# =============================================================================
# PROCESS
# =============================================================================
func _physics_process(delta: float) -> void:
	if not player or hp <= 0:
		return

	var dt := delta * Engine.time_scale

	if hurt_t > 0.0:
		hurt_t -= dt

	state_timer += dt
	_update_ai_state()
	_execute_current_state(dt)
	_update_weapon(dt)
	_update_animation()

	velocity += knock_vel
	knock_vel = knock_vel.move_toward(Vector2.ZERO, knockback_friction * dt)
	move_and_slide()



# =============================================================================
# IA - DECISIÓN DE ESTADOS
# =============================================================================
func _update_detection() -> void:
	if not player:
		return
	
	var dist := global_position.distance_to(player.global_position)
	
	# Actualizar predicción de posición del player
	var player_velocity = player.velocity if player.has_method("velocity") else Vector2.ZERO
	predicted_player_pos = player.global_position + player_velocity * 0.3

func _update_ai_state() -> void:
	if not player:
		current_state = AIState.IDLE
		return
	
	var dist := global_position.distance_to(player.global_position)
	var to_player := global_position.direction_to(player.global_position)
	
	# LÓGICA DE DECISIÓN TÁCTICA
	if dist > detection_range:
		current_state = AIState.IDLE
		
	elif dist > aggro_range:
		current_state = AIState.PATROL
		
	elif dist <= attack_range and can_attack:
		# RANGO DE ATAQUE - Decisiones complejas
		if is_feinting and state_timer < 0.5:
			current_state = AIState.FEINT
		elif randf() < dodge_chance and _player_is_attacking():
			current_state = AIState.RETREAT
		elif dist < personal_space:
			current_state = AIState.RETREAT  # Demasiado cerca
		else:
			current_state = AIState.COMBAT
			
	elif dist <= circle_distance + 20.0:
		# DISTANCIA MEDIA - Circular y buscar oportunidad
		if is_aggressive:
			current_state = AIState.CHASE
		else:
			current_state = AIState.CIRCLE
			
	else:
		# FUERA DE RANGO - Perseguir
		current_state = AIState.CHASE

# =============================================================================
# IA - EJECUCIÓN DE ESTADOS
# =============================================================================
func _execute_current_state(dt: float) -> void:
	match current_state:
		AIState.IDLE:
			_state_idle(dt)
		AIState.PATROL:
			_state_patrol(dt)
		AIState.CHASE:
			_state_chase(dt)
		AIState.COMBAT:
			_state_combat(dt)
		AIState.RETREAT:
			_state_retreat(dt)
		AIState.CIRCLE:
			_state_circle(dt)
		AIState.FEINT:
			_state_feint(dt)

func _state_idle(dt: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, friction * dt)

func _state_patrol(dt: float) -> void:
	# Movimiento lento hacia el player
	var dir := global_position.direction_to(player.global_position)
	var target_vel := dir * max_speed * 0.4
	velocity = velocity.move_toward(target_vel, acceleration * dt * 0.5)

func _state_chase(dt: float) -> void:
	var target := predicted_player_pos if randf() < 0.7 else player.global_position
	var dir := global_position.direction_to(target)
	var target_vel := dir * max_speed
	velocity = velocity.move_toward(target_vel, acceleration * dt)


func _state_combat(dt: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	
	# Movimiento táctico - acercarse/alejarse para mantener distancia óptima
	var dir := global_position.direction_to(player.global_position)
	var desired_dist := attack_range * 0.8
	
	if dist > desired_dist:
		# Acercarse
		velocity = velocity.move_toward(dir * max_speed * 0.6, acceleration * dt)
	else:
		# Mantener distancia
		velocity = velocity.move_toward(Vector2.ZERO, friction * dt * 2.0)
	
	# ATACAR
	if can_attack and dist <= attack_range:
		_perform_attack()

func _state_retreat(dt: float) -> void:
	# Retroceder rápidamente
	var dir := global_position.direction_to(player.global_position)
	var retreat_vel := -dir * max_speed * 1.2  # Más rápido al retroceder
	velocity = velocity.move_toward(retreat_vel, acceleration * dt * 1.5)
	
	dodge_timer += dt
	if dodge_timer > 0.4:
		dodge_timer = 0.0
		current_state = AIState.CIRCLE

func _state_circle(dt: float) -> void:
	# Circular alrededor del player
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	
	# Perpendicular al player
	var tangent := to_player.rotated(PI / 2.0 if circle_clockwise else -PI / 2.0).normalized()
	
	# Combinar movimiento tangencial con corrección de distancia
	var desired_dir := tangent
	if dist < circle_distance - 10.0:
		desired_dir = (desired_dir + to_player.normalized() * -0.3).normalized()
	elif dist > circle_distance + 10.0:
		desired_dir = (desired_dir + to_player.normalized() * 0.3).normalized()
	
	velocity = velocity.move_toward(desired_dir * max_speed * 0.7, acceleration * dt)

func _state_feint(dt: float) -> void:
	# Finta - movimiento engañoso
	velocity = velocity.move_toward(feint_direction * max_speed * 1.3, acceleration * dt * 2.0)
	
	if state_timer > 0.5:
		is_feinting = false
		state_timer = 0.0

# =============================================================================
# TÁCTICAS
# =============================================================================
func _change_tactic() -> void:
	# Cambiar entre agresivo/defensivo
	is_aggressive = randf() < aggressive_chance
	
	# Cambiar dirección de circulación
	circle_clockwise = randf() < 0.5
	
	# Posibilidad de finta
	if randf() < feint_chance and player:
		_initiate_feint()

func _initiate_feint() -> void:
	is_feinting = true
	state_timer = 0.0
	# Dirección de finta: hacia el player + offset aleatorio
	var to_player := global_position.direction_to(player.global_position)
	feint_direction = to_player.rotated(randf_range(-PI/3, PI/3))

func _player_is_attacking() -> bool:
	# Detectar si el player está atacando (requiere que player tenga variable 'attacking')
	if player.has_method("get") and player.get("attacking") != null:
		return player.get("attacking")
	return false

# =============================================================================
# COMBATE - ATAQUE
# =============================================================================
func _perform_attack() -> void:
	if not can_attack:
		return
	
	can_attack = false
	attacking = true
	attack_t = 0.0
	
	# Calcular ángulo de ataque
	var angle_to_player := global_position.angle_to_point(player.global_position)
	_calculate_attack_angle(angle_to_player)
	_spawn_slash(angle_to_player)
	
	# Cooldown
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true
	attacking = false

func _calculate_attack_angle(base_angle: float) -> void:
	if use_left_offset:
		target_attack_angle = base_angle + deg_to_rad(angle_offset_left)
	else:
		target_attack_angle = base_angle + deg_to_rad(angle_offset_right)
	use_left_offset = not use_left_offset

func _spawn_slash(angle: float) -> void:
	if slash_scene == null:
		return
	
	var s = slash_scene.instantiate()

	s.setup(&"enemy", self)

	get_tree().current_scene.add_child(s)
	s.global_position = slash_spawn.global_position
	s.global_rotation = angle


# =============================================================================
# WEAPON SYSTEM (igual que player)
# =============================================================================
func _update_weapon(delta: float) -> void:
	if not player:
		return
	
	var angle_to_player := global_position.angle_to_point(player.global_position)
	
	if attacking:
		_snap_to_attack_angle(delta)
	else:
		_update_weapon_aim(angle_to_player, delta)
	
	_update_weapon_flip()
	_update_sprite_flip(angle_to_player)

func _update_weapon_aim(target_angle: float, delta: float) -> void:
	weapon_pivot.rotation = lerp_angle(
		weapon_pivot.rotation,
		target_angle,
		1.0 - exp(-weapon_follow_speed * delta)
	)

func _snap_to_attack_angle(delta: float) -> void:
	weapon_pivot.rotation = lerp_angle(
		weapon_pivot.rotation,
		target_attack_angle,
		1.0 - exp(-attack_snap_speed * delta)
	)

func _update_weapon_flip() -> void:
	var angle := wrapf(weapon_pivot.rotation, -PI, PI)
	weapon_sprite.flip_v = abs(angle) > PI / 2.0

func _update_sprite_flip(angle_to_player: float) -> void:
	var angle_deg := rad_to_deg(angle_to_player)
	sprite.flip_h = abs(angle_deg) > 90.0

# =============================================================================
# RECIBIR DAÑO
# =============================================================================
func take_damage(dmg: int, from_pos: Vector2 = Vector2.INF) -> void:
	if dying:
		return

	hp -= dmg
	print("ENEMY HP:", hp)

	_spawn_blood(blood_hit_amount)

	# Muerte
	if hp <= 0:
		dying = true
		_spawn_blood(blood_death_amount)

		# parar IA y movimiento
		can_attack = false
		attacking = false
		velocity = Vector2.ZERO
		knock_vel = Vector2.ZERO
		set_physics_process(false)

		sprite.play("death")
		await sprite.animation_finished
		queue_free()
		return

	# Hurt normal
	play_hurt()

	sprite.modulate = Color(1, 0.5, 0.5, 1)
	get_tree().create_timer(0.06).timeout.connect(func():
		if is_instance_valid(self):
			sprite.modulate = Color(1, 1, 1, 1)
	)




# =============================================================================
# ANIMACIÓN
# =============================================================================
func _update_animation() -> void:
	# NO cambiar animación si está en hurt
	if hurt_t > 0.0:
		return
	
	if velocity.length() > 10.0:
		sprite.play("walk")
	else:
		sprite.play("idle")

func apply_knockback(force: Vector2) -> void:
	knock_vel += force
	
func play_hurt() -> void:
	hurt_t = hurt_time
	sprite.play("hurt")
	
	# Cuando termine la animación hurt, volver a idle/walk automáticamente
	# (solo si el enemy sigue vivo)
	get_tree().create_timer(hurt_time).timeout.connect(func():
		if is_instance_valid(self) and hp > 0:
			_update_animation()
	)


func apply_hitstop() -> void:
	if hitstopping:
		return
	
	hitstopping = true
	
	# Guardar velocidad actual antes del hitstop
	var saved_velocity = velocity
	var saved_knock = knock_vel
	
	var old_scale := Engine.time_scale
	Engine.time_scale = hitstop_time_scale
	
	await get_tree().create_timer(hitstop_time * hitstop_time_scale, true, false, true).timeout
	
	# Solo restaurar si seguimos en hitstop_time_scale
	if Engine.time_scale == hitstop_time_scale:
		Engine.time_scale = old_scale
	
	# Restaurar velocidades (por si acaso el physics_process se saltó frames)
	velocity = saved_velocity
	knock_vel = saved_knock
	
	hitstopping = false

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
