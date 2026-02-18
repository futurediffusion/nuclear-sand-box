extends Control

# Apunta a StaminaBar2, que es la barra con texturas visuales
@onready var stamina_bar: TextureProgressBar = $StaminaBar2

var player: Player

func _ready() -> void:
	_try_bind_player()
	if not GameManager.player_healed.is_connected(_on_player_healed):
		GameManager.player_healed.connect(_on_player_healed)

func _try_bind_player() -> void:
	player = _find_player()

	if player == null:
		call_deferred("_try_bind_player")
		return

	# Configurar rango de la barra
	stamina_bar.min_value = 0.0
	stamina_bar.max_value = player.get_max_stamina()
	stamina_bar.value = player.get_current_stamina()

	# Conectar señal de stamina
	if not player.stamina_changed.is_connected(_on_player_stamina_changed):
		player.stamina_changed.connect(_on_player_stamina_changed)

func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Player:
		return players[0] as Player
	return null

func _on_player_stamina_changed(new_stamina: float, new_max_stamina: float) -> void:
	stamina_bar.max_value = new_max_stamina
	stamina_bar.value = new_stamina

func _on_player_healed(amount: int) -> void:
	# Hook listo para feedback visual/sonoro de curación.
	pass
