extends Node

## Autoload centralizado para efectos de cámara.
## Cualquier entidad llama CameraFX.shake() / CameraFX.shake_impulse()
## sin conocer al player ni buscar la cámara manualmente.

func shake(amount: float) -> void:
	var cam := _get_cam()
	if cam != null:
		cam.shake(amount)

func shake_impulse(duration: float, magnitude: float) -> void:
	var cam := _get_cam()
	if cam != null:
		cam.shake_impulse(duration, magnitude)

func _get_cam() -> Node:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return (players[0] as Node).get_node_or_null("Camera2D")
