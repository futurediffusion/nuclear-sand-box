extends Node2D

const CombatQueryScript := preload("res://scripts/systems/CombatQuery.gd")

@export var knockback_strength: float = 120.0
@export var damage: int = 1
@export var CharacterHitbox_active_time: float = 0.10

@onready var anim: AnimatedSprite2D = $Anim
var hitbox: Area2D = null
@onready var sfx: AudioStreamPlayer2D = $Sfx
@onready var impact_sound: AudioStreamPlayer2D = $ImpactSound

@export var pitch_min: float = 0.8
@export var pitch_max: float = 1.2
@export var can_mine: bool = true


var already_hit := {}
var owner_team: StringName = &"player"
var owner_node: Node = null
var owner_damage_entity: Node = null
var owner_hurtbox: Area2D = null
var did_hitstop: bool = false



func setup(team: StringName, owner: Node) -> void:
	owner_team = team
	owner_node = owner
	owner_damage_entity = null
	owner_hurtbox = null

	if owner_node != null:
		owner_damage_entity = owner_node
		if owner_node.has_node("Hurtbox"):
			owner_hurtbox = owner_node.get_node("Hurtbox") as Area2D

func _ready() -> void:
	hitbox = get_node_or_null("Hitbox")

	if sfx and sfx.stream:
		sfx.pitch_scale = randf_range(pitch_min, pitch_max)
		sfx.play()

	_configure_mask()
	_set_hitbox_enabled(false)
	hitbox.body_entered.connect(_on_body_entered)
	hitbox.area_entered.connect(_on_area_entered)
	call_deferred("_activate_hitbox")

	get_tree().create_timer(CharacterHitbox_active_time).timeout.connect(func():
		if is_instance_valid(self):
			_set_hitbox_enabled(false)
	)

	anim.play("slash")
	anim.animation_finished.connect(_on_anim_finished)

func _activate_hitbox() -> void:
	if hitbox == null:
		return
	if _is_slash_overlapping_wall():
		return
	_set_hitbox_enabled(true)

func _set_hitbox_enabled(enabled: bool) -> void:
	hitbox.monitoring = enabled
	hitbox.monitorable = enabled
	var shape := hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = not enabled

func _configure_mask() -> void:
	if hitbox == null:
		return

	hitbox.collision_mask = (1 << 0) | (1 << 2) | (1 << 3)  # Player + EnemyNPC + Resources

func _on_anim_finished() -> void:
	queue_free()

func _try_damage(raw_target: Node) -> void:
	if raw_target == null:
		return

	var normalized := CombatQueryScript.resolve_damage_target(raw_target)
	if normalized.is_empty():
		return

	var target := normalized.get("entity") as Node
	var target_hurtbox := normalized.get("hurtbox") as Area2D
	if target == null:
		return

	if owner_damage_entity != null and target == owner_damage_entity:
		return
	if owner_hurtbox != null and target_hurtbox != null and target_hurtbox == owner_hurtbox:
		return
	if raw_target == owner_node or raw_target == owner_hurtbox:
		return

	if CombatQueryScript.is_owner_related(owner_node, raw_target):
		return
	if CombatQueryScript.is_owner_related(owner_node, target_hurtbox):
		return
	if CombatQueryScript.is_owner_related(owner_node, target):
		return

	if _is_slash_overlapping_wall():
		return

	if _is_target_blocked_by_wall(target, target_hurtbox):
		return

	var id := target.get_instance_id()
	if already_hit.has(id):
		return

	already_hit[id] = true

	if can_mine and target.has_method("hit"):
		target.call("hit", owner_node)

		var s: AudioStream = null
		if target.has_method("get_hit_sound"):
			s = target.call("get_hit_sound")

		if s != null:
			impact_sound.stream = s
			impact_sound.play()
		elif impact_sound and impact_sound.stream:
			impact_sound.play()

		return

	if target.has_method("take_damage"):
		var from_pos := global_position
		if owner_node is Node2D:
			from_pos = (owner_node as Node2D).global_position

		target.call("take_damage", damage, from_pos)

		if impact_sound and impact_sound.stream:
			impact_sound.play()

		if target.has_method("apply_knockback"):
			var knockback_dir: Vector2
			if owner_node is Node2D and target is Node2D:
				knockback_dir = ((target as Node2D).global_position - (owner_node as Node2D).global_position).normalized()
			else:
				knockback_dir = Vector2.RIGHT.rotated(global_rotation)

			target.call("apply_knockback", knockback_dir * knockback_strength)

		if not did_hitstop and target.has_method("apply_hitstop"):
			did_hitstop = true
			target.call("apply_hitstop")


func _is_target_blocked_by_wall(target: Node, target_hurtbox: Area2D = null) -> bool:
	if target == null:
		return false
	if not (target is Node2D):
		return false

	var from_pos := global_position

	var excluded: Array = [self, target]
	if owner_node != null:
		excluded.append(owner_node)
	if target_hurtbox != null:
		excluded.append(target_hurtbox)

	return CombatQueryScript.is_melee_target_blocked_by_wall(self, from_pos, target, target_hurtbox, excluded)


func _is_slash_overlapping_wall() -> bool:
	if hitbox == null:
		return false

	var shape := hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or shape.shape == null:
		return false

	var excluded: Array = [self]
	if owner_node != null:
		excluded.append(owner_node)

	return CombatQueryScript.shape_overlaps_wall(self, shape, excluded)

func _on_body_entered(body: Node) -> void:
	_try_damage(body)

func _on_area_entered(area: Area2D) -> void:
	_try_damage(area)
