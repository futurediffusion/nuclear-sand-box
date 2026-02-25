class_name BloodDroplet
extends RigidBody2D

@export var splat_lifetime: float = 60.0
@export var fly_time: float = 0.18

var _done := false
var _pool_enabled := false
var _release_callback: Callable = Callable()
var _lifecycle_token := 0

func _ready() -> void:
	add_to_group("blood_droplet")
	z_index = -1

	if has_node("Sprite2D"):
		var s := $Sprite2D as Sprite2D
		s.visible = true
		if s.texture == null:
			push_warning("BloodDroplet: Sprite2D no tiene textura asignada.")

	if has_node("CollisionShape2D"):
		$CollisionShape2D.disabled = false

	if not _pool_enabled:
		on_pool_acquired()

func setup_pooling(enabled: bool, release_callback: Callable) -> void:
	_pool_enabled = enabled
	_release_callback = release_callback

func on_pool_acquired() -> void:
	_done = false
	_lifecycle_token += 1
	freeze = false
	sleeping = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	scale = Vector2.ONE
	visible = true
	if has_node("CollisionShape2D"):
		$CollisionShape2D.disabled = false
	_start_lifecycle_timers(_lifecycle_token)

func on_pool_released() -> void:
	_lifecycle_token += 1
	_done = false
	freeze = false
	sleeping = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	visible = false
	if has_node("CollisionShape2D"):
		$CollisionShape2D.disabled = true

func _start_lifecycle_timers(token: int) -> void:
	get_tree().create_timer(fly_time).timeout.connect(func() -> void:
		if not is_instance_valid(self) or token != _lifecycle_token or _done:
			return
		_finish_splat()
	)
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if not is_instance_valid(self) or token != _lifecycle_token or _done:
			return
		_despawn()
	)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _done:
		return

	if state.get_contact_count() > 0:
		_finish_splat()

func _finish_splat() -> void:
	if _done:
		return

	_done = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze = true
	rotation = randf_range(0.0, TAU)
	scale = Vector2.ONE * randf_range(0.8, 1.4)

	if has_node("CollisionShape2D"):
		$CollisionShape2D.disabled = true

	var token := _lifecycle_token
	get_tree().create_timer(splat_lifetime).timeout.connect(func() -> void:
		if not is_instance_valid(self) or token != _lifecycle_token:
			return
		_despawn()
	)

func _despawn() -> void:
	if _pool_enabled and _release_callback.is_valid():
		_release_callback.call(self)
		return
	queue_free()
