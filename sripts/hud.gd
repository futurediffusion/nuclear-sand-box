extends Control

@onready var stamina_bar: TextureProgressBar = $StaminaBar

var player: Player = null

func _ready() -> void:
	stamina_bar.min_value = 0.0
	if not _try_bind_player():
		call_deferred("_retry_bind_player")

func _try_bind_player() -> bool:
	var found_player := _find_player()
	if found_player == null:
		return false

	if player != found_player:
		_disconnect_from_player()
		player = found_player

	_update_stamina_bar()
	var on_stamina_changed := Callable(self, "_on_player_stamina_changed")
	if not player.stamina_changed.is_connected(on_stamina_changed):
		player.stamina_changed.connect(on_stamina_changed)

	return true

func _retry_bind_player() -> void:
	if _try_bind_player():
		return

	var retry_timer := get_tree().create_timer(0.2)
	if not retry_timer.timeout.is_connected(_retry_bind_player):
		retry_timer.timeout.connect(_retry_bind_player, CONNECT_ONE_SHOT)

func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Player

	var scene_root := get_tree().current_scene
	if scene_root != null:
		return scene_root.get_node_or_null("Player") as Player

	return null

func _on_player_stamina_changed(current_stamina: float, current_max_stamina: float) -> void:
	stamina_bar.max_value = current_max_stamina
	stamina_bar.value = current_stamina

func _update_stamina_bar() -> void:
	if player == null:
		return

	stamina_bar.max_value = player.max_stamina
	stamina_bar.value = player.stamina

func _disconnect_from_player() -> void:
	if player == null:
		return

	var on_stamina_changed := Callable(self, "_on_player_stamina_changed")
	if player.stamina_changed.is_connected(on_stamina_changed):
		player.stamina_changed.disconnect(on_stamina_changed)
