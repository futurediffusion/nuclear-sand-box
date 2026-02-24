extends Node
class_name VFXComponent

const MAX_DROPLETS_IN_SCENE := 40

var owner: Node = null

func setup(p_owner: Node) -> void:
	owner = p_owner

func tick(_delta: float) -> void:
	pass

func physics_tick(_delta: float) -> void:
	pass

func play_attack_vfx() -> void:
	if owner != null and owner.has_node("Camera2D"):
		owner.get_node("Camera2D").shake(4.0)

func play_block_vfx() -> void:
	pass

func play_hit_vfx(hit_dir: Vector2, is_death: bool = false) -> void:
	if owner == null:
		return
	_spawn_blood(owner.blood_hit_amount)
	_spawn_droplets(owner.droplet_count_hit, hit_dir)
	if is_death:
		_spawn_blood(owner.blood_death_amount)
		_spawn_droplets(owner.droplet_count_death, hit_dir)

func play_hit_flash() -> void:
	if owner == null:
		return
	owner.sprite.modulate = Color(1, 0.5, 0.5, 1)
	owner.get_tree().create_timer(0.06).timeout.connect(func():
		if is_instance_valid(owner):
			owner.sprite.modulate = Color(1, 1, 1, 1)
	)

func _spawn_blood(amount: int) -> void:
	if owner == null or owner.blood_scene == null:
		return
	var p := owner.blood_scene.instantiate() as GPUParticles2D
	owner.get_tree().current_scene.add_child(p)
	p.global_position = owner.global_position
	p.amount = amount
	p.one_shot = true
	p.emitting = true
	owner.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)

func _spawn_droplets(count: int, base_dir: Vector2) -> void:
	if owner == null or owner.droplet_scene == null:
		return
	var existing := owner.get_tree().get_nodes_in_group("blood_droplet").size()
	var allowed := mini(count, MAX_DROPLETS_IN_SCENE - existing)
	if allowed <= 0:
		return
	for i in range(allowed):
		var d := owner.droplet_scene.instantiate() as RigidBody2D
		if d == null:
			continue
		d.add_to_group("blood_droplet")
		owner.get_tree().current_scene.add_child(d)
		d.global_position = owner.global_position
		var ang := randf_range(-deg_to_rad(owner.droplet_spread_deg), deg_to_rad(owner.droplet_spread_deg))
		var dir := base_dir.rotated(ang)
		d.linear_velocity = dir * randf_range(owner.droplet_speed_min, owner.droplet_speed_max)
