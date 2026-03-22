extends Node
class_name BanditWorkCoordinator

## Coordina el runtime laboral de bajo nivel para bandidos ya tickeados.
##
## BanditBehaviorLayer emite intención y persistencia; este coordinador ejecuta
## interacciones concretas con el mundo y delega el ciclo de cargo a
## BanditCampStashSystem.
##
## Frontera futura:
## si mañana existe una TavernResponseDirector, no debe entrar aquí salvo como
## efecto ya resuelto externamente. Este coordinador sigue siendo runtime
## laboral/físico, no autoridad social.

const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")

var _stash: BanditCampStashSystem = null


func setup(ctx: Dictionary) -> void:
	_stash = ctx.get("stash") as BanditCampStashSystem


func process_post_behavior(beh: BanditWorldBehavior, enemy_node: Node, drops_cache: Array) -> void:
	if beh == null:
		return
	if enemy_node == null or not is_instance_valid(enemy_node):
		_handle_missing_enemy(beh)
		return

	_maybe_drop_carry_on_aggro(beh, enemy_node)
	_handle_mining(beh, enemy_node)
	_handle_collection_and_deposit(beh, enemy_node, drops_cache)


func _handle_missing_enemy(beh: BanditWorldBehavior) -> void:
	if _stash != null and not beh._cargo_manifest.is_empty():
		_stash.drop_carry_on_aggro(beh, null)
	if beh.pending_mine_id != 0 and not is_instance_id_valid(beh.pending_mine_id):
		beh.pending_mine_id = 0
		beh._resource_node_id = 0
	if beh.pending_collect_id != 0 and not is_instance_id_valid(beh.pending_collect_id):
		beh.pending_collect_id = 0


func _maybe_drop_carry_on_aggro(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	if _stash == null or beh._cargo_manifest.is_empty():
		return
	var ai_comp := enemy_node.get_node_or_null("AIComponent")
	if ai_comp != null and ai_comp.get("target") != null:
		_stash.drop_carry_on_aggro(beh, enemy_node)


func _handle_collection_and_deposit(beh: BanditWorldBehavior, enemy_node: Node,
		drops_cache: Array) -> void:
	if _stash == null:
		return

	if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH:
		var res_center := _resolve_resource_center(beh, enemy_node)
		_stash.sweep_collect_orbit(beh, enemy_node, res_center, drops_cache)
	elif beh.pending_collect_id != 0:
		_stash.sweep_collect_arrive(beh, enemy_node,
			(enemy_node as Node2D).global_position, drops_cache)

	_stash.handle_cargo_deposit(beh, enemy_node)


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


func _handle_mining(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	var mine_id: int = beh.pending_mine_id
	if mine_id == 0:
		return
	beh.pending_mine_id = 0
	if not is_instance_id_valid(mine_id):
		beh._resource_node_id = 0
		return

	var res_node: Node = instance_from_id(mine_id) as Node
	if res_node == null or not is_instance_valid(res_node) or res_node.is_queued_for_deletion():
		beh._resource_node_id = 0
		return

	var enemy_pos: Vector2 = (enemy_node as Node2D).global_position
	var res_pos: Vector2 = (res_node as Node2D).global_position
	if enemy_pos.distance_squared_to(res_pos) > BanditTuningScript.mine_range_sq():
		return

	var wc: WeaponComponent = enemy_node.get_node_or_null("WeaponComponent") as WeaponComponent
	if wc != null and wc.current_weapon_id != "ironpipe":
		wc.equip_weapon_id("ironpipe")
		if wc.current_weapon_id != "ironpipe":
			return
		beh.pending_mine_id = mine_id
		return

	res_node.hit(enemy_node)
	if enemy_node.has_method("queue_ai_attack_press"):
		enemy_node.call("queue_ai_attack_press", res_pos)
