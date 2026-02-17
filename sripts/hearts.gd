extends HBoxContainer

@export var full_heart: Texture2D
@export var empty_heart: Texture2D
@export var max_hearts: int = 3
@export var heart_scale: float = 4.0

var _hearts: Array[TextureRect] = []
var _player: Node = null

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	_build()
	call_deferred("_find_and_connect_player")

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_hearts.clear()
	
	# Aplicar separación AQUÍ, después de limpiar
	add_theme_constant_override("separation", 4)
	
	for i in range(max_hearts):
		var t := TextureRect.new()
		t.texture = full_heart if full_heart else null
		t.stretch_mode = TextureRect.STRETCH_KEEP
		t.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		
		# Tamaño exacto: sprite real * escala
		var sprite_size := Vector2(9, 8)
		if full_heart:
			sprite_size = full_heart.get_size()
		
		var final_size := sprite_size * heart_scale
		t.custom_minimum_size = final_size
		t.size = final_size
		
		add_child(t)
		_hearts.append(t)

func _find_and_connect_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		get_tree().create_timer(0.5).timeout.connect(_find_and_connect_player)
		return
	
	_player = players[0]
	
	var health_comp := _player.get_node_or_null("HealthComponent")
	if health_comp == null:
		return
	
	if not health_comp.damaged.is_connected(_on_player_damaged):
		health_comp.damaged.connect(_on_player_damaged)
	
	if not health_comp.died.is_connected(_on_player_died):
		health_comp.died.connect(_on_player_died)
	
	max_hearts = health_comp.max_hp
	_build()
	set_hp(health_comp.hp)

func _on_player_damaged(_amount: int) -> void:
	if _player == null:
		return
	var health_comp := _player.get_node_or_null("HealthComponent")
	if health_comp:
		set_hp(health_comp.hp)

func _on_player_died() -> void:
	set_hp(0)

func set_hp(hp: int) -> void:
	for i in range(_hearts.size()):
		if full_heart and empty_heart:
			_hearts[i].texture = full_heart if i < hp else empty_heart
		else:
			_hearts[i].modulate = Color.WHITE if i < hp else Color(0.3, 0.3, 0.3, 1.0)
