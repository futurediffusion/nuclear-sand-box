extends Node
class_name ModalWorldUIController

signal modal_opened(reason: String, modal: Control)
signal modal_closed(reason: String)

var _active_modal: Control = null
var _active_reason: String = ""
var _pause_depth: int = 0


func show_modal(modal: Control, parent: Node, reason: String = "world_modal", pause_world: bool = true) -> Control:
	if modal == null or parent == null:
		return null

	close_modal(_active_modal)

	_active_modal = modal
	_active_reason = _normalize_reason(reason)
	_active_modal.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(_active_modal)

	if pause_world:
		_pause_depth += 1
		get_tree().paused = true

	if UiManager != null:
		UiManager.open_ui(_active_reason)

	modal_opened.emit(_active_reason, _active_modal)
	return _active_modal


func close_modal(modal: Control = null) -> void:
	var target := modal if modal != null else _active_modal
	if target == null:
		return
	if _active_modal != null and target != _active_modal:
		return

	var reason := _active_reason
	var should_queue_free := is_instance_valid(target)

	_active_modal = null
	_active_reason = ""

	if UiManager != null and reason != "":
		UiManager.close_ui(reason)

	if _pause_depth > 0:
		_pause_depth -= 1
	if _pause_depth <= 0:
		_pause_depth = 0
		get_tree().paused = false

	if should_queue_free:
		target.queue_free()

	modal_closed.emit(reason)


func has_active_modal() -> bool:
	return _active_modal != null and is_instance_valid(_active_modal)


func get_active_modal() -> Control:
	return _active_modal if has_active_modal() else null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close_modal()


func _normalize_reason(reason: String) -> String:
	return "world_modal" if reason.strip_edges() == "" else reason
