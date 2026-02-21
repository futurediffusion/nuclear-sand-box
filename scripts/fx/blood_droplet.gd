class_name BloodDroplet
extends RigidBody2D

@export var splat_lifetime: float = 60.0
@export var fly_time: float = 0.18

var _done := false

func _ready() -> void:
	add_to_group("blood_droplet")

	# Que la mancha quede debajo del player, pero visible sobre el fondo
	z_index = -1

	# Seguridad: asegurar que la gota tenga sprite visible con textura
	if has_node("Sprite2D"):
		var s := $Sprite2D as Sprite2D
		s.visible = true
		if s.texture == null:
			push_warning("BloodDroplet: Sprite2D no tiene textura asignada.")

	# Seguridad: asegurar que la forma de colisión esté activa
	if has_node("CollisionShape2D"):
		$CollisionShape2D.disabled = false

	# En top-down no existe "piso" con colisión, así que forzamos el splat
	# tras un tiempo corto de vuelo aunque no haya contacto físico.
	get_tree().create_timer(fly_time).timeout.connect(func():
		if is_instance_valid(self) and not _done:
			_finish_splat()
	)

	# Por si no toca nada, se borra solo (evita basura)
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(self) and not _done:
			queue_free()
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

	# Se "congela" como mancha en el piso
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze = true

	# Un poco de variación para que no se vean clonadas
	rotation = randf_range(0.0, TAU)
	scale = Vector2.ONE * randf_range(0.8, 1.4)

	# Quitar colisión para que no estorbe
	if has_node("CollisionShape2D"):
		$CollisionShape2D.disabled = true

	# Se borra después de X segundos
	get_tree().create_timer(splat_lifetime).timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)
