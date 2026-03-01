extends Node
class_name UiManager

var _open_reasons: Dictionary = {}
var _cursor: CanvasItem = null


func _ready() -> void:
	get_tree().node_added.connect(_on_tree_node_added)
	_resolve_cursor(true)
	_apply_mode()


func open_ui(reason: String) -> void:
	var key := _normalize_reason(reason)
	_open_reasons[key] = int(_open_reasons.get(key, 0)) + 1
	print("[UI-MODE] open_ui reason=", key, " count=", _open_reasons[key], " reasons=", _open_reasons)
	_resolve_cursor()
	_apply_mode()


func close_ui(reason: String) -> void:
	var key := _normalize_reason(reason)
	if not _open_reasons.has(key):
		print("[UI-MODE] close_ui ignored reason=", key, " reasons=", _open_reasons)
		return

	var count := int(_open_reasons[key]) - 1
	if count <= 0:
		_open_reasons.erase(key)
	else:
		_open_reasons[key] = count

	print("[UI-MODE] close_ui reason=", key, " remaining=", _open_reasons.get(key, 0), " reasons=", _open_reasons)
	_resolve_cursor()
	_apply_mode()


func is_ui_open() -> bool:
	return _open_reasons.size() > 0


func _apply_mode() -> void:
	var ui_open := is_ui_open()
	if ui_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if _cursor != null:
			_cursor.visible = false
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		if _cursor != null:
			_cursor.visible = true

	print("[UI-MODE] apply ui_open=", ui_open,
		" mouse_mode=", Input.get_mouse_mode(),
		" cursor=", _cursor,
		" cursor_visible=", _cursor.visible if _cursor != null else "<missing>")


func _resolve_cursor(force: bool = false) -> void:
	if _cursor != null and is_instance_valid(_cursor) and not force:
		return

	_cursor = null
	var scene := get_tree().current_scene
	if scene != null:
		_cursor = scene.get_node_or_null("CursorLayer/MouseCursor") as CanvasItem

	if _cursor == null:
		var cursors := get_tree().get_nodes_in_group("cursor")
		for node in cursors:
			if node is CanvasItem:
				_cursor = node as CanvasItem
				break


func _normalize_reason(reason: String) -> String:
	return "unknown" if reason.strip_edges() == "" else reason


func _on_tree_node_added(_node: Node) -> void:
	if _cursor == null or not is_instance_valid(_cursor):
		_resolve_cursor()
		_apply_mode()
