class_name MethodCapabilityCache
extends RefCounted

var _instance_method_cache: Dictionary = {} # instance_id(int) -> {method(StringName): bool}
var _class_method_cache: Dictionary = {}    # class_key(String) -> {method(StringName): bool}
var _tracked_nodes: Dictionary = {}         # instance_id(int) -> true (tree_exiting connected)


func has_method_cached(obj: Object, method: StringName) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var instance_id: int = obj.get_instance_id()
	var per_instance: Dictionary = _instance_method_cache.get(instance_id, {})
	if per_instance.has(method):
		return bool(per_instance[method])

	var class_key: String = _build_class_key(obj)
	var per_class: Dictionary = _class_method_cache.get(class_key, {})
	var result: bool
	if per_class.has(method):
		result = bool(per_class[method])
	else:
		result = obj.has_method(method)
		per_class[method] = result
		_class_method_cache[class_key] = per_class

	per_instance[method] = result
	_instance_method_cache[instance_id] = per_instance
	_track_node_lifecycle(obj, instance_id)
	return result


func clear_instance(obj: Object) -> void:
	if obj == null:
		return
	var instance_id: int = obj.get_instance_id()
	_instance_method_cache.erase(instance_id)
	_tracked_nodes.erase(instance_id)


func _build_class_key(obj: Object) -> String:
	var obj_class_name: String = obj.get_class()
	var script_key: String = ""
	var script_ref = obj.get_script()
	if script_ref != null:
		var script_path: String = String(script_ref.get("resource_path"))
		script_key = script_path if script_path != "" else String(script_ref)
	return "%s|%s" % [obj_class_name, script_key]


func _track_node_lifecycle(obj: Object, instance_id: int) -> void:
	if _tracked_nodes.has(instance_id):
		return
	var node := obj as Node
	if node == null:
		return
	node.tree_exiting.connect(_on_node_tree_exiting.bind(instance_id), CONNECT_ONE_SHOT)
	_tracked_nodes[instance_id] = true


func _on_node_tree_exiting(instance_id: int) -> void:
	_instance_method_cache.erase(instance_id)
	_tracked_nodes.erase(instance_id)
