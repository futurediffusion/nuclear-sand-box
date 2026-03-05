extends Node
class_name PartyControlManager

signal controlled_actor_changed(old_actor: Node, new_actor: Node)

var _controlled_actor: Node = null

func set_controlled_actor(actor: Node) -> void:
	if actor == _controlled_actor:
		return

	var old_actor := _controlled_actor
	if old_actor != null:
		_release_actor_control(old_actor)

	_controlled_actor = actor
	if _controlled_actor != null:
		_grant_actor_control(_controlled_actor)

	controlled_actor_changed.emit(old_actor, _controlled_actor)

func get_controlled_actor() -> Node:
	return _controlled_actor

func release_control(actor: Node) -> void:
	if actor == null:
		return
	if _controlled_actor != actor:
		return

	var old_actor := _controlled_actor
	_release_actor_control(old_actor)
	_controlled_actor = null
	controlled_actor_changed.emit(old_actor, null)

func _grant_actor_control(actor: Node) -> void:
	if actor.has_method("on_control_gained"):
		actor.call("on_control_gained")

	if actor.has_method("ensure_player_weapon_controller"):
		actor.call("ensure_player_weapon_controller")
	if actor.has_method("set_weapon_controller_mode"):
		actor.call("set_weapon_controller_mode", "player")

	if actor.has_node("Camera2D"):
		var cam := actor.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			cam.make_current()
	# Hook futuro: si el actor no trae Camera2D local, conectar aquí un sistema de cámara party.

func _release_actor_control(actor: Node) -> void:
	if actor.has_node("Camera2D"):
		var cam := actor.get_node_or_null("Camera2D") as Camera2D
		if cam != null and cam.is_current() and cam.has_method("clear_current"):
			cam.call("clear_current")

	if actor.has_method("on_control_lost"):
		actor.call("on_control_lost")

	if actor.has_method("ensure_ai_weapon_controller"):
		actor.call("ensure_ai_weapon_controller")
	if actor.has_method("set_weapon_controller_mode"):
		actor.call("set_weapon_controller_mode", "ai")
