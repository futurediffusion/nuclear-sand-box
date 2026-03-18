extends HBoxContainer

@export var full_heart: Texture2D
@export var empty_heart: Texture2D
@export var max_hearts: int = 3
@export var heart_scale: float = 4.0

var _hearts: Array[TextureRect] = []

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	# Separación va aquí, UNA VEZ, antes de construir los hijos
	add_theme_constant_override("separation", 4)
	_build()

func _build() -> void:
	# Borrar hijos viejos
	for c in get_children():
		c.queue_free()
	_hearts.clear()

	# Calcular tamaño base del sprite
	var sprite_size := Vector2(9, 8)
	if full_heart:
		sprite_size = full_heart.get_size()

	var final_size := sprite_size * heart_scale

	for i in range(max_hearts):
		var t := TextureRect.new()
		t.texture = full_heart if full_heart else null

		# STRETCH_SCALE escala la textura al tamaño que le indiques
		# (a diferencia de STRETCH_KEEP que solo la muestra a tamaño nativo)
		t.stretch_mode = TextureRect.STRETCH_SCALE

		# Esto es lo que respeta el HBoxContainer para dimensionar el hijo
		t.custom_minimum_size = final_size

		# expand_mode KEEP_SIZE le dice al TextureRect que respete su minimum_size
		t.expand_mode = TextureRect.EXPAND_KEEP_SIZE

		add_child(t)
		_hearts.append(t)

func set_hearts(current_hp: int) -> void:
	set_hp(current_hp)

func set_hp(hp: int) -> void:
	if max_hearts != _hearts.size():
		_build()

	for i in range(_hearts.size()):
		if full_heart and empty_heart:
			_hearts[i].texture = full_heart if i < hp else empty_heart
		else:
			_hearts[i].modulate = Color.WHITE if i < hp else Color(0.3, 0.3, 0.3, 1.0)
