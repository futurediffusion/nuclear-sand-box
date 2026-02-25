extends Node
class_name VFXComponent

const MAX_DROPLETS_IN_SCENE: int = 40

var player: Player = null

func setup(p_player: Player) -> void:
	player = p_player

func tick(_delta: float) -> void:
	if player == null:
		return
	pass

func physics_tick(_delta: float) -> void:
	if player == null:
		return
	pass

func play_attack_vfx() -> void:
	if player == null:
		return
	if player.has_node("Camera2D"):
		player.get_node("Camera2D").shake(4.0)

func play_block_vfx() -> void:
	if player == null:
		return
	pass

func play_hit_vfx(hit_dir: Vector2, is_death: bool = false) -> void:
	if player == null:
		return
	_spawn_blood(player.blood_hit_amount)
	_spawn_droplets(player.droplet_count_hit, hit_dir)
	if is_death:
		_spawn_blood(player.blood_death_amount)
		_spawn_droplets(player.droplet_count_death, hit_dir)

func play_hit_flash() -> void:
	if player == null:
		return
	player.sprite.modulate = Color(1, 0.5, 0.5, 1)
	player.get_tree().create_timer(0.06).timeout.connect(func() -> void:
		if is_instance_valid(player):
			player.sprite.modulate = Color(1, 1, 1, 1)
	)

func _spawn_blood(amount: int) -> void:
	if player == null or player.blood_scene == null:
		return
	var p: GPUParticles2D = player.blood_scene.instantiate() as GPUParticles2D
	player.get_tree().current_scene.add_child(p)
	p.global_position = player.global_position
	p.amount = amount
	p.one_shot = true
	p.emitting = true
	player.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)

func _spawn_droplets(count: int, base_dir: Vector2) -> void:
	if player == null or player.droplet_scene == null:
		return
	var existing: int = player.get_tree().get_nodes_in_group("blood_droplet").size()
	var allowed: int = mini(count, MAX_DROPLETS_IN_SCENE - existing)
	if allowed <= 0:
		return
	for i: int in range(allowed):
		var d: RigidBody2D = player.droplet_scene.instantiate() as RigidBody2D
		if d == null:
			continue
		d.add_to_group("blood_droplet")
		player.get_tree().current_scene.add_child(d)
		d.global_position = player.global_position
		var ang: float = randf_range(-deg_to_rad(player.droplet_spread_deg), deg_to_rad(player.droplet_spread_deg))
		var dir: Vector2 = base_dir.rotated(ang)
		d.linear_velocity = dir * randf_range(player.droplet_speed_min, player.droplet_speed_max)
