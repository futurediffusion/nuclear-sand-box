class_name CharacterBase
extends CharacterBody2D

const HealthComponentScript = preload("res://scripts/components/HealthComponent.gd")
const DownedComponentScript = preload("res://scripts/components/DownedComponent.gd")
const CollisionLayersScript = preload("res://scripts/systems/CollisionLayers.gd")

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

@export_group("Collision")
@export var ignore_world_walls: bool = false

@onready var health_component: Node = get_node_or_null("HealthComponent")
@onready var downed_component: DownedComponent = get_node_or_null("DownedComponent")

var hp: int = 0
var dying: bool = false
var knock_vel: Vector2 = Vector2.ZERO
var hurt_t: float = 0.0
var _base_ready_initialized: bool = false
var _base_ready_call_count: int = 0

func _ready() -> void:
	_base_ready_call_count += 1
	if _base_ready_initialized:
		return
	_base_ready_initialized = true
	_apply_world_collision_policy()
	_debug_validate_world_collision_setup("CharacterBase._ready")

func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		call_deferred("_debug_validate_ready_contract")

func _setup_health_component() -> void:
	if health_component == null:
		health_component = HealthComponentScript.new()
		health_component.name = "HealthComponent"
		add_child(health_component)
	if health_component != null:
		health_component.max_hp = max_hp
		health_component.hp = max_hp
		if not health_component.died.is_connected(_on_health_died):
			health_component.died.connect(_on_health_died)
		hp = health_component.hp
	else:
		hp = max_hp

	_ensure_downed_component()

func _ensure_downed_component() -> void:
	if downed_component == null:
		downed_component = get_node_or_null("DownedComponent")

	if downed_component == null:
		downed_component = DownedComponentScript.new()
		downed_component.name = "DownedComponent"
		add_child(downed_component)

	if not downed_component.became_downed.is_connected(_on_became_downed):
		downed_component.became_downed.connect(_on_became_downed)
	if not downed_component.recovered.is_connected(recover_from_downed):
		downed_component.recovered.connect(recover_from_downed)
	if not downed_component.died_final.is_connected(die_final):
		downed_component.died_final.connect(die_final)

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

func _on_health_died() -> void:
	if is_downed():
		die_final()
	else:
		enter_downed()

func _on_became_downed() -> void:
	pass

func enter_downed(resolve_at: float = -1.0) -> void:
	if is_downed() or dying:
		return

	if health_component:
		health_component.is_downed = true

	if downed_component:
		downed_component.enter_downed(resolve_at)

	velocity = Vector2.ZERO
	knock_vel = Vector2.ZERO

	if has_node("AnimatedSprite2D"):
		var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
		sprite.play("death")
		# We want to stay at the last frame
		if sprite.sprite_frames.has_animation("death"):
			var frame_count = sprite.sprite_frames.get_frame_count("death")
			sprite.frame = frame_count - 1
			sprite.stop()

func recover_from_downed() -> void:
	if not is_downed():
		return

	if health_component:
		if health_component.has_method("revive"):
			health_component.call("revive", downed_component.downed_revive_hp if downed_component else 1)
		else:
			health_component.is_downed = false
			health_component.hp = downed_component.downed_revive_hp if downed_component else 1
			if health_component.get("_dead_emitted") != null:
				health_component.set("_dead_emitted", false)
		hp = health_component.hp

	if has_node("AnimatedSprite2D"):
		var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
		sprite.play("idle")

	_update_animation()
	_on_recovered_from_downed()

func _on_recovered_from_downed() -> void:
	pass

func is_downed() -> bool:
	return downed_component != null and downed_component.is_downed

func die_final() -> void:
	if dying:
		return
	dying = true

	if health_component:
		health_component.is_downed = false
		health_component.hp = 0
		hp = 0

	if downed_component:
		downed_component.is_downed = false

	hurt_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	_on_before_die()

	if has_node("AnimatedSprite2D"):
		var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
		sprite.play("death")
		# If we were already at the last frame, it might not play.
		# But usually we want to ensure it's at the end.
		if sprite.is_playing() and sprite.animation == "death":
			await sprite.animation_finished
		else:
			var frame_count = sprite.sprite_frames.get_frame_count("death")
			sprite.frame = frame_count - 1

	_on_after_die()

func die() -> void:
	# Deprecated or redirected to die_final
	die_final()

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

func _apply_world_collision_policy() -> void:
	if Debug.use_legacy_wall_collision:
		set_collision_mask_value(CollisionLayersScript.WORLD_WALL_LAYER_BIT, false)
		return
	set_collision_mask_value(CollisionLayersScript.WORLD_WALL_LAYER_BIT, not ignore_world_walls)

func _debug_validate_world_collision_setup(source: String) -> void:
	if not OS.is_debug_build():
		return
	var expected_enabled := (not Debug.use_legacy_wall_collision) and (not ignore_world_walls)
	var enabled := get_collision_mask_value(CollisionLayersScript.WORLD_WALL_LAYER_BIT)
	if enabled == expected_enabled:
		return
	push_warning("[%s] Invalid world collision policy on '%s'. Expected WORLD_WALL mask=%s but got %s. If this is a CharacterBase-derived script, you likely forgot super._ready() at the start of _ready()." % [source, name, str(expected_enabled), str(enabled)])
	assert(false, "CharacterBase world collision policy mismatch. Likely missing super._ready() in derived _ready().")

func _debug_validate_ready_contract() -> void:
	if not OS.is_debug_build():
		return
	if _base_ready_call_count <= 0:
		push_warning("[CharacterBase] '%s' reached READY without CharacterBase._ready(). A derived _ready() probably forgot to call super._ready() first." % name)
		assert(false, "CharacterBase._ready() was not executed. Derived _ready() must call super._ready() first.")
		return
	_debug_validate_world_collision_setup("CharacterBase._notification")

func ensure_wall_collision() -> void:
	# Backward compatible alias while callers migrate.
	_apply_world_collision_policy()
