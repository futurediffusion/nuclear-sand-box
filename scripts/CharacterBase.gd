class_name CharacterBase
extends CharacterBody2D

const HealthComponentScript = preload("res://scripts/components/HealthComponent.gd")
const DownedComponentScript = preload("res://scripts/components/DownedComponent.gd")
const DownedBarViewScene = preload("res://scenes/ui/DownedBarView.tscn")
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

signal downed_entered
signal revived
signal dying_started
signal death_finished

@onready var health_component: Node = get_node_or_null("HealthComponent")
@onready var downed_component: DownedComponent = get_node_or_null("DownedComponent") as DownedComponent

var hp: int = 0
var dying: bool = false
var is_downed: bool = false
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

	if downed_component == null:
		downed_component = DownedComponentScript.new()
		downed_component.name = "DownedComponent"
		add_child(downed_component)

	if downed_component != null:
		if not downed_component.entered_downed.is_connected(_on_entered_downed):
			downed_component.entered_downed.connect(_on_entered_downed)
		if not downed_component.revived.is_connected(_on_revived):
			downed_component.revived.connect(_on_revived)
		if not downed_component.died_final.is_connected(die_final):
			downed_component.died_final.connect(die_final)

		_ensure_downed_bar_view()

func _ensure_downed_bar_view() -> void:
	if not has_node("DownedBarView"):
		var view := DownedBarViewScene.instantiate()
		view.name = "DownedBarView"
		add_child(view)

func take_damage(dmg: int, from_pos: Vector2 = Vector2.INF) -> void:
	if dying:
		return

	if is_downed:
		if downed_component != null and downed_component.has_method("can_take_finishing_blow"):
			if downed_component.call("can_take_finishing_blow"):
				die_final()
		else:
			die_final()
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
			_on_health_died()
		return

	play_hurt()
	_play_hit_flash()

func _on_health_died() -> void:
	if downed_component != null:
		downed_component.enter_downed()
	else:
		die_final()

func _on_entered_downed() -> void:
	is_downed = true
	hurt_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	var _cc := get_node_or_null("CarryComponent")
	if _cc != null:
		_cc.force_drop_all()
	if has_node("AnimatedSprite2D"):
		var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
		sprite.play("death")
		# Pausar en el último frame
		sprite.animation_finished.connect(func():
			if is_downed and sprite.animation == "death":
				sprite.stop()
				sprite.frame = sprite.sprite_frames.get_frame_count("death") - 1
		, CONNECT_ONE_SHOT)
	downed_entered.emit()

func _on_revived() -> void:
	is_downed = false
	var _cc := get_node_or_null("CarryComponent")
	if _cc != null:
		_cc.force_drop_all()
	if health_component != null:
		var revive_hp := maxi(1, downed_component.downed_revive_hp)
		health_component.set_hp_clamped(revive_hp)
		hp = health_component.hp
	if has_node("AnimatedSprite2D"):
		var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
		sprite.play("idle")

	if DownedEncounterCoordinator != null and DownedEncounterCoordinator.has_method("notify_target_revived"):
		DownedEncounterCoordinator.notify_target_revived(self)
	if AggroTrackerService != null and AggroTrackerService.has_method("clear_target"):
		AggroTrackerService.clear_target(self)

	revived.emit()

func die_final() -> void:
	if dying:
		return
	dying = true
	is_downed = false
	hurt_t = 0.0
	knock_vel = Vector2.ZERO
	velocity = Vector2.ZERO

	if DownedEncounterCoordinator != null and DownedEncounterCoordinator.has_method("notify_target_died_final"):
		DownedEncounterCoordinator.notify_target_died_final(self)
	if AggroTrackerService != null and AggroTrackerService.has_method("clear_target"):
		AggroTrackerService.clear_target(self)

	var _cc := get_node_or_null("CarryComponent")
	if _cc != null:
		_cc.force_drop_all()

	dying_started.emit()
	_on_before_die()
	if has_node("AnimatedSprite2D"):
		var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
		if sprite.animation != "death" or not sprite.is_playing():
			sprite.play("death")
			await sprite.animation_finished
	_on_after_die()
	death_finished.emit()

func die() -> void:
	_on_health_died()

func is_final_dead() -> bool:
	return dying

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
