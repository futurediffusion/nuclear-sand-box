extends RefCounted
class_name LocalSocialAuthorityPorts

# Responsibility boundary:
# This is a tiny composition seam for future local civil authority systems
# (for example a tavern with local memory, authority policy, and sanctions).
# It intentionally contains only optional callables so world composition can
# expose integration points now without forcing fake implementations yet.

var _authority_policy: Callable = Callable()
var _memory_source: Callable = Callable()
var _sanction_director: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_authority_policy = ctx.get("local_authority_policy", Callable())
	_memory_source = ctx.get("local_memory_source", Callable())
	_sanction_director = ctx.get("local_sanction_director", Callable())


func has_authority_policy() -> bool:
	return _authority_policy.is_valid()


func has_memory_source() -> bool:
	return _memory_source.is_valid()


func has_sanction_director() -> bool:
	return _sanction_director.is_valid()


func evaluate_local_authority(event_name: String, payload: Dictionary = {}) -> Variant:
	if not _authority_policy.is_valid():
		return null
	return _authority_policy.call(event_name, payload)


func get_local_memory_snapshot(scope_id: String, payload: Dictionary = {}) -> Variant:
	if not _memory_source.is_valid():
		return null
	return _memory_source.call(scope_id, payload)


func direct_local_sanction(event_name: String, payload: Dictionary = {}) -> void:
	if not _sanction_director.is_valid():
		return
	_sanction_director.call(event_name, payload)
