extends Node2D

@export var knockback_strength: float = 120.0
@export var damage: int = 1
@export var hitbox_active_time: float = 0.10

@onready var anim: AnimatedSprite2D = $Anim
@onready var hitbox: Area2D = $Hitbox
@onready var sfx: AudioStreamPlayer2D = $Sfx
@onready var impact_sound: AudioStreamPlayer2D = $ImpactSound

@export var pitch_min: float = 0.8
@export var pitch_max: float = 1.2

var already_hit := {}
var owner_team: StringName = &"player"
var owner_node: Node = null
var did_hitstop: bool = false

func setup(team: StringName, owner: Node) -> void:
	owner_team = team
	owner_node = owner

func _ready() -> void:
	# SFX arma
	if sfx and sfx.stream:
		sfx.pitch_scale = randf_range(pitch_min, pitch_max)
		sfx.play()
	
	_configure_mask()
	
	# Conectar hitbox
	hitbox.body_entered.connect(_on_body_entered)
	hitbox.area_entered.connect(_on_area_entered)
	
	# Encender hitbox SOLO al inicio
	_set_hitbox_enabled(true)
	
	# Apagar hitbox rápido
	get_tree().create_timer(hitbox_active_time).timeout.connect(func():
		_set_hitbox_enabled(false)
	)
	
	# Animación y borrado final visual
	anim.play("slash")
	anim.animation_finished.connect(_on_anim_finished)

func _set_hitbox_enabled(enabled: bool) -> void:
	hitbox.monitoring = enabled
	hitbox.monitorable = enabled
	var shape := hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = not enabled

func _configure_mask() -> void:
	if owner_team == &"player":
		hitbox.collision_mask = 1 << (3 - 1) # pega enemies
	else:
		hitbox.collision_mask = 1 << (1 - 1) # pega player

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
	
	# Solo si realmente tiene vida/daño
	if target.has_method("take_damage"):

		var from_pos := global_position
		if owner_node != null:
			from_pos = owner_node.global_position

		target.call("take_damage", damage, from_pos)

		
		# Impact SFX SOLO si pegó
		if impact_sound and impact_sound.stream:
			impact_sound.play()
		
		# Knockback - CALCULADO CORRECTAMENTE desde el atacante hacia el objetivo
		if target.has_method("apply_knockback"):
			var knockback_dir: Vector2
			
			# Calcular dirección desde el DUEÑO del slash hacia el objetivo
			if owner_node != null:
				knockback_dir = (target.global_position - owner_node.global_position).normalized()
			else:
				# Fallback: usar la rotación del slash
				knockback_dir = Vector2.RIGHT.rotated(global_rotation)
			
			target.call("apply_knockback", knockback_dir * knockback_strength)
		
		# Hitstop SOLO si el objetivo tiene el método
		if not did_hitstop and target.has_method("apply_hitstop"):
			did_hitstop = true
			target.call("apply_hitstop")

func _on_body_entered(body: Node) -> void:
	_try_damage(body)

func _on_area_entered(area: Area2D) -> void:
	_try_damage(area)
