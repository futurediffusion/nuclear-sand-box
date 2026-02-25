extends Node
class_name VFXComponent

const MAX_DROPLETS_IN_SCENE: int = 40
const NodePoolScript = preload("res://scripts/systems/NodePool.gd")

var player: Player = null
var _burst_pool: NodePool = null
var _droplet_pool: NodePool = null

@export_group("Pooling")
@export var use_pooling := true
@export var blood_burst_prewarm := 12
@export var blood_droplet_prewarm := 24

func setup(p_player: Player) -> void:
	player = p_player
	_setup_pools()

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

func _setup_pools() -> void:
	if player == null:
		return
	if not use_pooling:
		return
	var root := player.get_tree().current_scene
	if root == null:
		root = player.get_tree().root
	if player.blood_scene != null:
		_burst_pool = NodePoolScript.new()
		add_child(_burst_pool)
		_burst_pool.configure(player.blood_scene, root, blood_burst_prewarm)
	if player.droplet_scene != null:
		_droplet_pool = NodePoolScript.new()
		add_child(_droplet_pool)
		_droplet_pool.configure(player.droplet_scene, root, blood_droplet_prewarm)

func _spawn_blood(amount: int) -> void:
	if player == null or player.blood_scene == null:
		return
	var p: GPUParticles2D = null
	if use_pooling and _burst_pool != null:
		p = _burst_pool.acquire() as GPUParticles2D
	else:
		p = player.blood_scene.instantiate() as GPUParticles2D
		player.get_tree().current_scene.add_child(p)
	if p == null:
		return
	p.global_position = player.global_position
	p.amount = amount
	p.one_shot = true
	p.restart()
	p.emitting = true
	player.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(func() -> void:
		if not is_instance_valid(p):
			return
		if use_pooling and _burst_pool != null:
			_burst_pool.release(p)
		else:
			p.queue_free()
	)

func _spawn_droplets(count: int, base_dir: Vector2) -> void:
	if player == null or player.droplet_scene == null:
		return
	var existing: int = player.get_tree().get_nodes_in_group("blood_droplet").size()
	var allowed: int = mini(count, MAX_DROPLETS_IN_SCENE - existing)
	if allowed <= 0:
		return
	for _i: int in range(allowed):
		var d: RigidBody2D = null
		if use_pooling and _droplet_pool != null:
			d = _droplet_pool.acquire() as RigidBody2D
		else:
			d = player.droplet_scene.instantiate() as RigidBody2D
			if d == null:
				continue
			d.add_to_group("blood_droplet")
			player.get_tree().current_scene.add_child(d)
		if d == null:
			continue
		d.global_position = player.global_position
		if d.has_method("setup_pooling"):
			d.call("setup_pooling", use_pooling and _droplet_pool != null, Callable(self, "_release_droplet"))
		if d.has_method("on_pool_acquired"):
			d.call("on_pool_acquired")
		var ang: float = randf_range(-deg_to_rad(player.droplet_spread_deg), deg_to_rad(player.droplet_spread_deg))
		var dir: Vector2 = base_dir.rotated(ang)
		d.linear_velocity = dir * randf_range(player.droplet_speed_min, player.droplet_speed_max)

func _release_droplet(node: Node) -> void:
	if _droplet_pool != null:
		_droplet_pool.release(node)
