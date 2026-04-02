extends RefCounted
class_name PlacementReactionFacade

func setup(_ctx: Dictionary) -> void:
	pass

func trigger(target_pos: Vector2, ctx: Dictionary) -> void:
	var all_ids: Array = BanditGroupMemory.get_all_group_ids()
	Debug.log("placement_react", "--- placement react target=%s groups_total=%d ---" % [str(target_pos), all_ids.size()])
	if all_ids.is_empty():
		Debug.log("placement_react", "  SKIP: no hay grupos registrados en BanditGroupMemory")
		return
	var queued: int = 0
	var dispatched_groups: int = 0
	var pending_groups: int = 0
	var total_redirected: int = 0
	var raid_queue_port: Dictionary = ctx.get("raid_queue_port", {})
	var lock_seconds: float = float(ctx.get("intent_lock_seconds", 90.0))
	var assault_squad: int = int(ctx.get("struct_assault_squad", -1))
	var hostil_cb: Callable = ctx.get("is_hostile_cb", Callable())
	var layer: BanditBehaviorLayer = ctx.get("bandit_behavior_layer")
	for gid in all_ids:
		var g: Dictionary = BanditGroupMemory.get_group(gid)
		var faction_id: String = String(g.get("faction_id", ""))
		var eradicated: bool = bool(g.get("eradicated", false))
		var members: Array = g.get("member_ids", []) as Array
		if eradicated or members.is_empty():
			continue
		if hostil_cb.is_valid() and not bool(hostil_cb.call(g)):
			Debug.log("placement_react", "  group=%s faction=%s skipped (not hostile for structures)" % [gid, faction_id])
			continue
		var leader_id: String = String(g.get("leader_id", ""))
		if leader_id == "" and not members.is_empty():
			leader_id = String(members[0])
		if leader_id == "":
			continue
		BanditGroupMemory.record_interest(gid, target_pos, "structure_placed")
		BanditGroupMemory.set_placement_react_lock(gid, lock_seconds)
		var enqueued_now: bool = false
		var has_assault: bool = false
		var has_assault_cb: Callable = raid_queue_port.get("has_structure_assault_for_group", Callable())
		if has_assault_cb.is_valid():
			has_assault = bool(has_assault_cb.call(gid))
		if not has_assault:
			var enqueue_assault_cb: Callable = raid_queue_port.get("enqueue_structure_assault", Callable())
			if enqueue_assault_cb.is_valid():
				enqueue_assault_cb.call(faction_id, gid, leader_id, target_pos, "placed_structure", assault_squad)
				queued += 1
				enqueued_now = true
		var redirected: int = 0
		if layer != null:
			redirected = layer.dispatch_group_to_target(gid, target_pos, assault_squad)
		if redirected > 0:
			dispatched_groups += 1
			total_redirected += redirected
		else:
			pending_groups += 1
		Debug.log("placement_react", "  group=%s faction=%s redirected=%d queued_now=%s" % [gid, faction_id, redirected, str(enqueued_now)])
	Debug.log("placement_react", "  SUMMARY queued=%d dispatched_groups=%d pending_groups=%d redirected_total=%d" % [queued, dispatched_groups, pending_groups, total_redirected])
