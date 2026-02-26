class_name CharacterBase
extends CharacterBody2D

const HealthComponentScript = preload("res://scripts/components/HealthComponent.gd")

@export_group("Health")
@export var max_hp: int = 3

@export_group("Knockback")
@export var knockback_friction: float = 2200.0

@export_group("Juice")
@export var hurt_time: float = 0.15

@export_group("FX")
@export var blood_scene: PackedScene
@export var blood_hit_amount: int = 10
@export var blood_death_amount: int = 30

@onready var health_component: Node = get_node_or_null("HealthComponent")

var hp: int = 0
var dying: bool = false
var knock_vel: Vector2 = Vector2.ZERO
var hurt_t: float = 0.0

func _setup_health_component() -> void:
	if health_component == null:
		health_component = HealthComponentScript.new()
		health_component.name = "HealthComponent"
		add_child(health_component)
	if health_component != null:
		health_component.max_hp = max_hp
		health_component.hp = max_hp
		if not health_component.died.is_connected(die):
			health_component.died.connect(die)
		hp = health_component.hp
	else:
		hp = max_hp

func take_damage(dmg: int, from_pos: Vector2 = Vector2.INF) -> void:
	if dying:
		return

	if health_component != null and health_component.has_method("take_damage"):
		health_component.take_damage(dmg)
		hp = health_component.hp
	else:
		hp -= dmg

	var hit_dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	if from_pos != Vector2.INF:
		hit_dir = (global_position - from_pos).normalized()

	_spawn_blood(blood_hit_amount)

	if hp <= 0:
		_spawn_blood(blood_death_amount)
		if health_component == null:
			die()
		return

	play_hurt()
	_play_hit_flash()

func die() -> void:
	if dying:
		return
	dying = true
	hurt_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	_on_before_die()
	if has_node("AnimatedSprite2D"):
		var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
		sprite.play("death")
		await sprite.animation_finished
	_on_after_die()

func apply_knockback(force: Vector2) -> void:
	knock_vel += force

func play_hurt() -> void:
	hurt_t = hurt_time
	if has_node("AnimatedSprite2D"):
		var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
		sprite.play("hurt")
	get_tree().create_timer(hurt_time).timeout.connect(func():
		if is_instance_valid(self) and hp > 0 and has_method("_update_animation"):
			_update_animation()
	)

func _play_hit_flash() -> void:
	if not has_node("AnimatedSprite2D"):
		return
	var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
	sprite.modulate = Color(1, 0.5, 0.5, 1)
	get_tree().create_timer(0.06).timeout.connect(func():
		if is_instance_valid(self):
			sprite.modulate = Color(1, 1, 1, 1)
	)

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

func _apply_knockback_step(delta: float) -> void:
	velocity += knock_vel
	knock_vel = knock_vel.move_toward(Vector2.ZERO, knockback_friction * delta)

func _on_before_die() -> void:
	pass

func _update_animation() -> void:
	pass

func _on_after_die() -> void:
	pass
