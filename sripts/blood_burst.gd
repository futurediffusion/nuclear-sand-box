@export var blood_scene: PackedScene
@export var blood_hit_amount: int = 12
@export var blood_death_amount: int = 40

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
