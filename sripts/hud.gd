extends Control

@onready var stamina_bar: TextureProgressBar = $StaminaBar

var player: Player

func _ready() -> void:
	stamina_bar.min_value = 0.0
	_try_bind_player()

func _try_bind_player() -> void:
	player = _find_player()
	if player == null:
		call_deferred("_try_bind_player")
		return

	stamina_bar.max_value = player.max_stamina
	stamina_bar.value = player.stamina

	if not player.stamina_changed.is_connected(_on_player_stamina_changed):
		player.stamina_changed.connect(_on_player_stamina_changed)

func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Player:
		return players[0] as Player

	var by_path := get_node_or_null("/root/Main/Player")
	if by_path is Player:
		return by_path as Player

	return null

func _on_player_stamina_changed(new_stamina: float, new_max_stamina: float) -> void:
	stamina_bar.max_value = new_max_stamina
	stamina_bar.value = new_stamina
