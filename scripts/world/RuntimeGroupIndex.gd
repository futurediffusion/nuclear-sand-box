extends RefCounted
class_name RuntimeGroupIndex

var _tree_getter: Callable
var _group_entries: Dictionary = {}

func setup(ctx: Dictionary) -> void:
	_tree_getter = ctx.get("tree_getter", Callable())

func get_nodes(group_name: String, max_age_sec: float = 0.4, force_refresh: bool = false) -> Array:
	if group_name.strip_edges() == "":
		return []
	if force_refresh or _needs_refresh(group_name, max_age_sec):
		_refresh_group(group_name)
	var entry: Dictionary = _group_entries.get(group_name, {})
	var refs: Array = entry.get("refs", [])
	var out: Array = []
	for ref_obj in refs:
		if not (ref_obj is WeakRef):
			continue
		var node: Node = (ref_obj as WeakRef).get_ref()
		if node != null and is_instance_valid(node):
			out.append(node)
	entry["refs"] = _to_weak_refs(out)
	entry["updated_at"] = Time.get_ticks_msec()
	_group_entries[group_name] = entry
	return out

func invalidate(group_name: String = "") -> void:
	if group_name.strip_edges() == "":
		_group_entries.clear()
		return
	_group_entries.erase(group_name)

func _needs_refresh(group_name: String, max_age_sec: float) -> bool:
	if not _group_entries.has(group_name):
		return true
	var entry: Dictionary = _group_entries[group_name]
	var updated_at: int = int(entry.get("updated_at", 0))
	if updated_at <= 0:
		return true
	var max_age_msec: int = int(maxf(0.0, max_age_sec) * 1000.0)
	if max_age_msec <= 0:
		return true
	return (Time.get_ticks_msec() - updated_at) > max_age_msec

func _refresh_group(group_name: String) -> void:
	var tree: SceneTree = _tree_getter.call() if _tree_getter.is_valid() else null
	var nodes: Array = []
	if tree != null:
		nodes = tree.get_nodes_in_group(group_name)
	_group_entries[group_name] = {
		"updated_at": Time.get_ticks_msec(),
		"refs": _to_weak_refs(nodes),
	}

func _to_weak_refs(nodes: Array) -> Array:
	var refs: Array = []
	for node in nodes:
		if node != null and is_instance_valid(node) and node is Node:
			refs.append(weakref(node))
	return refs
