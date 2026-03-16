extends Node2D

const CombatQueryScript := preload("res://scripts/systems/CombatQuery.gd")
const CollisionLayersScript := preload("res://scripts/systems/CollisionLayers.gd")

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
var _hit_player_wall_this_swing: bool = false



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
	_apply_sound_panel_overrides()

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
	# Intento directo por tile (player walls) para no depender de un collider agregado por chunk.
	_try_damage_player_wall_once()
	if _is_slash_overlapping_wall():
		_try_damage_player_wall_once()
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

	# Player + EnemyNPC + Resources + World walls
	hitbox.collision_mask = (1 << 0) | (1 << 2) | (1 << 3) | CollisionLayersScript.WORLD_WALL_LAYER_MASK

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
		# El solape con muro no debe cancelar todo el swing:
		# se dana muro si aplica y luego se valida LOS por objetivo.
		_try_damage_player_wall_once()

	if _is_target_blocked_by_wall(target, target_hurtbox):
		return

	var id := target.get_instance_id()
	if already_hit.has(id):
		return

	already_hit[id] = true

	if can_mine and target.has_method("hit"):
		target.call("hit", owner_node)

		var suppress_default_impact_sound := false
		if target.has_method("suppress_default_impact_sound"):
			suppress_default_impact_sound = bool(target.call("suppress_default_impact_sound"))
		if suppress_default_impact_sound:
			return

		var s: AudioStream = null
		if target.has_method("get_hit_sound"):
			s = target.call("get_hit_sound")

		if s != null:
			impact_sound.stream = s
			impact_sound.play()
		elif not suppress_default_impact_sound and impact_sound and impact_sound.stream:
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

func _try_damage_player_wall_once() -> void:
	if _hit_player_wall_this_swing:
		return
	var world := _get_world_node()
	if world == null:
		return
	var can_exact_contact: bool = world.has_method("damage_player_wall_from_contact")
	var can_exact_near: bool = world.has_method("damage_player_wall_near_world_pos")
	var can_damage_wall_legacy: bool = world.has_method("damage_player_wall_at_world_pos")
	if not can_exact_contact and not can_exact_near and not can_damage_wall_legacy:
		return
	var amount: int = maxi(1, damage)
	var damaged := false
	var owner_pos := global_position
	if owner_node is Node2D:
		owner_pos = (owner_node as Node2D).global_position
	var excluded: Array = [self]
	if owner_node != null:
		excluded.append(owner_node)
	var wall_hit := CombatQueryScript.find_first_wall_hit(self, owner_pos, global_position, excluded, true)
	var has_ray_wall_hit: bool = not wall_hit.is_empty()
	var hit_pos := global_position
	var hit_normal: Vector2 = Vector2.ZERO
	if has_ray_wall_hit:
		hit_pos = wall_hit.get("position", global_position)
		hit_normal = wall_hit.get("normal", Vector2.ZERO)

	if has_ray_wall_hit and can_exact_contact:
		damaged = bool(world.call("damage_player_wall_from_contact", hit_pos, hit_normal, amount))
		if damaged:
			_hit_player_wall_this_swing = true
			return

	# Exact fallback only for overlap cases without ray hit.
	if not has_ray_wall_hit and can_exact_near and _is_slash_overlapping_wall():
		damaged = bool(world.call("damage_player_wall_near_world_pos", global_position, amount))
		if damaged:
			_hit_player_wall_this_swing = true
			return

	# If world exposes exact wall-hit API, skip radius fallback.
	if can_exact_contact or can_exact_near:
		return

	if not can_damage_wall_legacy:
		return

	var radius := _estimate_wall_hit_radius_world()
	if world.has_method("damage_player_wall_in_circle"):
		damaged = bool(world.call("damage_player_wall_in_circle", global_position, radius, amount))
		if damaged:
			_hit_player_wall_this_swing = true
			return
	damaged = bool(world.call("damage_player_wall_at_world_pos", hit_pos, amount))
	if not damaged:
		damaged = bool(world.call("damage_player_wall_at_world_pos", global_position, amount))
	if damaged:
		_hit_player_wall_this_swing = true

func _estimate_wall_hit_radius_world() -> float:
	var default_radius: float = 20.0
	if hitbox == null:
		return default_radius
	var shape_node := hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return default_radius

	var scale_x: float = absf(hitbox.global_scale.x * shape_node.global_scale.x)
	var scale_y: float = absf(hitbox.global_scale.y * shape_node.global_scale.y)
	var world_scale: float = maxf(scale_x, scale_y)
	var shape := shape_node.shape

	if shape is CircleShape2D:
		return maxf((shape as CircleShape2D).radius * world_scale, default_radius)
	if shape is RectangleShape2D:
		var half_size: Vector2 = (shape as RectangleShape2D).size * 0.5
		return maxf(maxf(half_size.x, half_size.y) * world_scale, default_radius)
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return maxf(maxf(capsule.radius, capsule.height * 0.5) * world_scale, default_radius)

	return default_radius

func _get_world_node() -> Node:
	var worlds := get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		return null
	return worlds[0]

func _on_body_entered(body: Node) -> void:
	if CombatQueryScript.is_wall_collider(body) and CombatQueryScript.resolve_damage_target(body).is_empty():
		_try_damage_player_wall_once()
		return
	_try_damage(body)

func _on_area_entered(area: Area2D) -> void:
	_try_damage(area)


func _apply_sound_panel_overrides() -> void:
	var panel := _resolve_sound_panel()
	if panel == null:
		return
	if sfx != null:
		if panel.slash_swing_sfx != null:
			sfx.stream = panel.slash_swing_sfx
		sfx.volume_db = panel.slash_swing_volume_db
	if impact_sound != null:
		var npc_hit := panel.npc_enemy_hit_sfx
		if npc_hit != null:
			impact_sound.stream = npc_hit
			impact_sound.volume_db = panel.npc_enemy_hit_volume_db
		elif panel.slash_impact_sfx != null:
			impact_sound.stream = panel.slash_impact_sfx
			impact_sound.volume_db = panel.slash_impact_volume_db
		else:
			impact_sound.volume_db = panel.npc_enemy_hit_volume_db


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null
