class_name EnemyAI
extends "res://scripts/CharacterBase.gd"

const AIComponentScript = preload("res://scripts/components/AIComponent.gd")
const ENEMY_DEATH_SOUND: AudioStream = preload("res://art/Sounds/impact.ogg")

@export_group("Combat")
@export var attack_damage: int = 1
@export var attack_cooldown: float = 0.8
@export var attack_range: float = 60.0

@export_group("Movement")
@export var max_speed: float = 280.0
@export var acceleration: float = 1000.0
@export var friction: float = 1500.0

@export_group("AI Behavior")
@export var detection_range: float = 400.0

@export_group("References")
@export var slash_scene: PackedScene

@export_group("Death Feedback")
@export var death_shake_duration: float = 0.28
@export var death_shake_magnitude: float = 18.0
@export var death_sound_pitch_scale: float = 0.68
@export var death_sound_volume_db: float = 2.0

@export_group("Ally Separation")
@export var separation_radius: float = 40.0
@export var separation_strength: float = 120.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: Sprite2D = $WeaponPivot/WeaponSprite
@onready var slash_spawn: Marker2D = $WeaponPivot/SlashSpawn
@onready var ai_component: AIComponent = get_node_or_null("AIComponent") as AIComponent
@onready var hurtbox: CharacterHurtbox = get_node_or_null("Hurtbox") as CharacterHurtbox

var weapon_follow_speed: float = 25.0
var attack_snap_speed: float = 50.0
var attacking: bool = false
var use_left_offset: bool = false
var target_attack_angle: float = 0.0
var angle_offset_left: float = -150.0
var angle_offset_right: float = 150.0

func _enter_tree() -> void:
	EnemyRegistry.register_enemy(self)

func _exit_tree() -> void:
	EnemyRegistry.unregister_enemy(self)

func _ready() -> void:
	add_to_group("enemy")
	sprite.play("idle")
	sprite.z_index = 0
	weapon_pivot.z_index = 10
	weapon_sprite.z_index = 10
	weapon_sprite.visible = true

	_setup_components()
	_setup_health_component()

func _setup_components() -> void:
	if ai_component == null:
		ai_component = AIComponentScript.new()
		ai_component.name = "AIComponent"
		add_child(ai_component)
	if ai_component != null:
		ai_component.setup(self)
	else:
		push_warning("[Enemy] Missing AIComponent")


func _setup_health_component() -> void:
	super._setup_health_component()
	if hurtbox != null and not hurtbox.damaged.is_connected(_on_hurtbox_damaged):
		hurtbox.damaged.connect(_on_hurtbox_damaged)

func _physics_process(delta: float) -> void:
	if hp <= 0:
		return

	if hurt_t > 0.0:
		hurt_t -= delta

	if ai_component != null:
		ai_component.physics_tick(delta)

	_update_weapon(delta)
	_update_animation()
	_apply_separation_force(delta)

	_apply_knockback_step(delta)
	move_and_slide()

func perform_attack(target_position: Vector2) -> void:
	if dying:
		return
	attacking = true
	var angle_to_target := global_position.angle_to_point(target_position)
	_calculate_attack_angle(angle_to_target)
	_spawn_slash(angle_to_target)
	await get_tree().process_frame
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

func _update_animation() -> void:
	if hurt_t > 0.0:
		return
	if velocity.length() > 10.0:
		sprite.play("walk")
	else:
		sprite.play("idle")

func _apply_separation_force(dt: float) -> void:
	var enemies: Array[Node2D] = EnemyRegistry.get_live_enemies()
	if enemies.is_empty():
		return
	var radius_sq := separation_radius * separation_radius
	for e in enemies:
		if e == self:
			continue
		var delta_pos := global_position - e.global_position
		var dist_sq := delta_pos.length_squared()
		if dist_sq <= 0.0001 or dist_sq >= radius_sq:
			continue
		var dist := sqrt(dist_sq)
		var push_dir := delta_pos / dist
		var t := 1.0 - (dist / separation_radius)
		velocity += push_dir * separation_strength * t * dt

func take_damage(dmg: int, from_pos: Vector2 = Vector2.INF) -> void:
	super.take_damage(dmg, from_pos)


func _on_hurtbox_damaged(dmg: int, from_pos: Vector2) -> void:
	take_damage(dmg, from_pos)

func _on_before_die() -> void:
	EnemyRegistry.unregister_enemy(self)
	if GameEvents != null and GameEvents.has_method("emit_entity_died"):
		GameEvents.emit_entity_died("", "enemy", global_position, null)
	_play_death_sound()
	_trigger_death_shake()
	if ai_component != null:
		ai_component.can_attack = false
	attacking = false
	set_physics_process(false)
	velocity = Vector2.ZERO
	knock_vel = Vector2.ZERO
	if ai_component != null:
		ai_component.set_dead()

func _on_after_die() -> void:
	queue_free()

func _trigger_death_shake() -> void:
	if ai_component == null or not is_instance_valid(ai_component.player):
		return
	var p := ai_component.player
	if not p.has_node("Camera2D"):
		return
	var cam := p.get_node("Camera2D")
	if cam and cam.has_method("shake_impulse"):
		cam.shake_impulse(death_shake_duration, death_shake_magnitude)
	elif cam and cam.has_method("shake"):
		cam.shake(death_shake_magnitude)

func _play_death_sound() -> void:
	if ENEMY_DEATH_SOUND == null:
		return
	var death_audio := AudioStreamPlayer2D.new()
	death_audio.stream = ENEMY_DEATH_SOUND
	death_audio.pitch_scale = death_sound_pitch_scale
	death_audio.volume_db = death_sound_volume_db
	death_audio.global_position = global_position
	get_tree().current_scene.add_child(death_audio)
	death_audio.finished.connect(func():
		if is_instance_valid(death_audio):
			death_audio.queue_free()
	)
	death_audio.play()
