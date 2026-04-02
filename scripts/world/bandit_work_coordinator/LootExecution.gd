extends RefCounted
class_name LootExecution

const BWCAssaultStagesScript := preload("res://scripts/world/bandit_work_coordinator/BWCAssaultStages.gd")
const BWCLootRuntimeScript := preload("res://scripts/world/bandit_work_coordinator/BWCLootRuntime.gd")

var _loot_runtime: BWCLootRuntime = BWCLootRuntimeScript.new()


func execute_raid_loot_stage(ctx: Dictionary) -> Dictionary:
	var stash: BanditCampStashSystem = ctx.get("stash") as BanditCampStashSystem
	var beh: BanditWorldBehavior = ctx.get("beh") as BanditWorldBehavior
	var enemy_pos: Vector2 = ctx.get("enemy_pos", Vector2.ZERO) as Vector2
	var attack_anchor: Vector2 = ctx.get("attack_anchor", Vector2.ZERO) as Vector2
	var world_spatial_index: WorldSpatialIndex = ctx.get("world_spatial_index") as WorldSpatialIndex
	var member_id: String = String(ctx.get("member_id", ""))
	var now: float = float(ctx.get("now", 0.0))
	var breach_resolved_at: float = float(ctx.get("breach_resolved_at", 0.0))
	var loot_next_at: float = float(ctx.get("loot_next_at", 0.0))

	var loot_gate: Dictionary = BanditWallAssaultPolicy.can_transition_breach_to_loot({
		"has_raid_context": true,
		"now": now,
		"breach_resolved_at": breach_resolved_at,
		"loot_next_at": loot_next_at,
		"enemy_pos": enemy_pos,
		"loot_anchor": attack_anchor,
		"loot_range_sq": BWCLootRuntime.RAID_LOOT_RANGE_SQ,
	})
	if not bool(loot_gate.get("allow", false)):
		return {
			"allow": false,
			"reason": String(loot_gate.get("reason", "loot_blocked")),
			"stage": BWCAssaultStagesScript.RAID_STAGE_LOOT,
		}

	var loot_started_usec: int = Time.get_ticks_usec()
	var loot_result: Dictionary = _loot_runtime.try_loot_nearby_container(stash, beh, enemy_pos, attack_anchor, world_spatial_index)
	var loot_stage_ms: float = maxf(0.0, float(Time.get_ticks_usec() - loot_started_usec) / 1000.0)
	var loot_nodes_inspected: int = int(loot_result.get("nodes_inspected", 0))
	var looted: bool = bool(loot_result.get("looted", false))
	var payload: Dictionary = {
		"allow": true,
		"reason": "loot_empty_or_unavailable",
		"stage": BWCAssaultStagesScript.RAID_STAGE_RETREAT,
		"result": BWCAssaultStagesScript.RAID_RESULT_SUCCESS,
		"loot_next_at": now + BanditWallAssaultPolicy.STRUCTURE_LOOT_COOLDOWN,
		"attack_next_at": now + BanditWallAssaultPolicy.STRUCTURE_ATTACK_COOLDOWN,
		"member_id": member_id,
		"loot_stage_ms": loot_stage_ms,
		"loot_nodes_inspected": loot_nodes_inspected,
	}
	Debug.log("raid", "[BWC] loot attempt npc=%s group=%s looted=%s stage_ms=%.2f inspected=%d" % [
		beh.member_id,
		beh.group_id,
		str(looted),
		loot_stage_ms,
		loot_nodes_inspected,
	])
	if looted:
		var container: ContainerPlaceable = loot_result.get("container") as ContainerPlaceable
		Debug.log("raid", "[BWC] chest looted npc=%s group=%s chest_uid=%s +%d cargo=%d/%d items=%s" % [
			beh.member_id,
			beh.group_id,
			container.placed_uid if container != null else "",
			int(loot_result.get("added", 0)),
			beh.cargo_count,
			beh.cargo_capacity,
			_loot_runtime.format_loot_entries(loot_result.get("taken", []) as Array),
		])
		payload["reason"] = "container_looted"
	return payload
