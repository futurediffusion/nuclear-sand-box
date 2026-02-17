extends Control

@onready var stamina_bar: TextureProgressBar = $StaminaBar

var player: Player

func _ready() -> void:
	stamina_bar.min_value = 0.0
	_try_bind_player()

func _try_bind_player() -> void:
	player = _find_player()
	
	if player == null:
		# Intenta de nuevo el próximo frame
		call_deferred("_try_bind_player")
		return

	# Set inicial
	_update_bar(player.stamina, player.max_stamina)

	# Conectar señal
	if not player.stamina_changed.is_connected(_on_player_stamina_changed):
		player.stamina_changed.connect(_on_player_stamina_changed)

func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Player:
		return players[0] as Player
	
	return null

func _on_player_stamina_changed(new_stamina: float, new_max_stamina: float) -> void:
	_update_bar(new_stamina, new_max_stamina)

func _update_bar(value: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value
