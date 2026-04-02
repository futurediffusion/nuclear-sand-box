extends RefCounted
class_name CargoDepositExecution


func execute(stash: BanditCampStashSystem, beh: BanditWorldBehavior, enemy_node: Node,
		drops_cache: Array) -> void:
	if stash == null or beh == null or enemy_node == null or not is_instance_valid(enemy_node):
		return

	if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH:
		var res_center := _resolve_resource_center(beh, enemy_node)
		stash.sweep_collect_orbit(beh, enemy_node, res_center, drops_cache)
	elif beh.pending_collect_id != 0:
		stash.sweep_collect_arrive(beh, enemy_node,
			(enemy_node as Node2D).global_position, drops_cache)

	stash.handle_cargo_deposit(beh, enemy_node)


func _resolve_resource_center(beh: BanditWorldBehavior, enemy_node: Node) -> Vector2:
	var fallback := (enemy_node as Node2D).global_position
	if beh._resource_node_id == 0 or not is_instance_id_valid(beh._resource_node_id):
		if beh._resource_node_id != 0:
			beh._resource_node_id = 0
		return fallback
	var res := instance_from_id(beh._resource_node_id) as Node2D
	if res == null or not is_instance_valid(res) or res.is_queued_for_deletion():
		beh._resource_node_id = 0
		return fallback
	return res.global_position
