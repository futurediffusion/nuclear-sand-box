extends RefCounted
class_name WallDamageExecution


func try_wall_slash_strike(enemy_node: Node, world_node: Node, world_pos: Vector2) -> bool:
	if enemy_node == null or not is_instance_valid(enemy_node):
		return false
	if enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", world_pos)
	return damage_player_wall_at(world_node, world_pos)


func damage_player_wall_at(world_node: Node, world_pos: Vector2) -> bool:
	if world_node == null:
		return false
	if not world_node.has_method("hit_wall_at_world_pos"):
		push_warning("BanditWorkCoordinator: world_node missing hit_wall_at_world_pos canonical API.")
		return false
	return bool(world_node.call("hit_wall_at_world_pos", world_pos, 1, 24.0, true))
