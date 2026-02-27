extends Node2D

@export var knockback_strength: float = 120.0
@export var damage: int = 1
@export var CharacterHitbox_active_time: float = 0.10

@onready var anim: AnimatedSprite2D = $Anim
@onready var CharacterHitbox: Area2D = $CharacterHitbox
@onready var sfx: AudioStreamPlayer2D = $Sfx
@onready var impact_sound: AudioStreamPlayer2D = $ImpactSound

@export var pitch_min: float = 0.8
@export var pitch_max: float = 1.2
@export var can_mine: bool = true

	
var already_hit := {}
var owner_team: StringName = &"player"
var owner_node: Node = null
var did_hitstop: bool = false



func setup(team: StringName, owner: Node) -> void:
	owner_team = team
	owner_node = owner

func _get_combat_CharacterHitbox() -> CharacterHitbox:
	if CharacterHitbox is CharacterHitbox:
		return CharacterHitbox as CharacterHitbox
	return null

func _ready() -> void:
	# SFX arma
	if sfx and sfx.stream:
		sfx.pitch_scale = randf_range(pitch_min, pitch_max)
		sfx.play()
	
	_configure_mask()
	
	var combat_CharacterHitbox := _get_combat_CharacterHitbox()
	if combat_CharacterHitbox != null:
		combat_CharacterHitbox.damage = damage
		combat_CharacterHitbox.knockback_force = knockback_strength
		combat_CharacterHitbox.activate()
	else:
		# Fallback legado
		CharacterHitbox.body_entered.connect(_on_body_entered)
		CharacterHitbox.area_entered.connect(_on_area_entered)
		_set_CharacterHitbox_enabled(true)

	# Apagar CharacterHitbox rápido
	get_tree().create_timer(CharacterHitbox_active_time).timeout.connect(func():
		if combat_CharacterHitbox != null:
			combat_CharacterHitbox.deactivate()
		else:
			_set_CharacterHitbox_enabled(false)
	)
	
	# Animación y borrado final visual
	anim.play("slash")
	anim.animation_finished.connect(_on_anim_finished)

func _set_CharacterHitbox_enabled(enabled: bool) -> void:
	CharacterHitbox.monitoring = enabled
	CharacterHitbox.monitorable = enabled
	var shape := CharacterHitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = not enabled

func _configure_mask() -> void:
	if owner_team == &"player":
		# Enemy (3) + Resources (4)
		CharacterHitbox.collision_mask = (1 << (3 - 1)) | (1 << (4 - 1))
	else:
		# Player (1)
		CharacterHitbox.collision_mask = 1 << (1 - 1)

func _on_anim_finished() -> void:
	queue_free()

func _try_damage(target: Node) -> void:
	if target == null:
		return
	
	# Nunca pegarle al dueño
	if owner_node != null and target == owner_node:
		return
	
	var id := target.get_instance_id()
	if already_hit.has(id):
		return
	
	already_hit[id] = true

	# 1) Si es un recurso (cobre, etc) y tiene método hit()
	#    Le pasamos el dueño del slash (player/enemy)
	# Solo minar si este slash puede minar
	if can_mine and target.has_method("hit"):
		target.call("hit", owner_node)

		# Sonido especial si el recurso lo define (mining/clink)
		var s: AudioStream = null
		if target.has_method("get_hit_sound"):
			s = target.call("get_hit_sound")

		if s != null:
			impact_sound.stream = s
			impact_sound.play()
		elif impact_sound and impact_sound.stream:
			# fallback por si no tiene sonido custom
			impact_sound.play()

		return

	# 2) Si no es recurso, entonces es combate normal
	if target.has_method("take_damage"):
		var from_pos := global_position
		if owner_node != null and "global_position" in owner_node:
			from_pos = owner_node.global_position

		target.call("take_damage", damage, from_pos)

		# Impact SFX SOLO si pegó
		if impact_sound and impact_sound.stream:
			impact_sound.play()

		# Knockback
		if target.has_method("apply_knockback"):
			var knockback_dir: Vector2
			if owner_node != null and "global_position" in owner_node:
				knockback_dir = (target.global_position - owner_node.global_position).normalized()
			else:
				knockback_dir = Vector2.RIGHT.rotated(global_rotation)

			target.call("apply_knockback", knockback_dir * knockback_strength)

		# Hitstop
		if not did_hitstop and target.has_method("apply_hitstop"):
			did_hitstop = true
			target.call("apply_hitstop")

func _on_body_entered(body: Node) -> void:
	_try_damage(body)

func _on_area_entered(area: Area2D) -> void:
	_try_damage(area)
