extends SceneTree

const WINDOW_SEC: float = 1.0
const HARNESS_DURATION_SEC: float = 16.0
const PLACEMENT_BURSTS: int = 12
const WALLS_PER_BURST: int = 8
const DOORS_PER_BURST: int = 3
const FRAMES_BETWEEN_BURSTS: int = 3
const EXTRA_HOSTILES_TARGET: int = 28

const THRESHOLDS := {
	"p95_frame_ms_max": 45.0,
	"p99_frame_ms_max": 65.0,
	"dispatches_per_event_min": 0.8,
	"repaths_per_pulse_max": 18.0,
	"invalidate_path_per_sec_max": 140.0,
	"groups_activated_per_event_min": 0.8,
	"scavenger_non_econ_orders_max": 0,
	"raid_loot_carry_coexistence_min_hits": 1,
}

var _results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")


func _record(name: String, ok: bool, evidence: String) -> void:
	_results.append({"metric": name, "ok": ok, "evidence": evidence})
	print("[HARNESS] ", name, " => ", ("PASS" if ok else "FAIL"), " :: ", evidence)


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await process_frame


func _get_inventory(player: Node) -> Node:
	if player == null:
		return null
	return player.get_node_or_null("InventoryComponent")


func _inject_build_items(player: Node, amount_walls: int, amount_doors: int) -> void:
	var inv := _get_inventory(player)
	if inv == null or not inv.has_method("add_item"):
		return
	inv.call("add_item", "wallwood", amount_walls)
	inv.call("add_item", "doorwood", amount_doors)


func _find_valid_wall_tiles(world: Node, origin: Vector2i, count: int, radius: int = 24) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(1, radius + 1):
		for y in range(origin.y - r, origin.y + r + 1):
			for x in range(origin.x - r, origin.x + r + 1):
				if out.size() >= count:
					return out
				var tile := Vector2i(x, y)
				if bool(world.call("can_place_player_wall_at_tile", tile)):
					out.append(tile)
	return out


func _find_valid_door_tiles(origin: Vector2i, count: int, radius: int = 24) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(1, radius + 1):
		for y in range(origin.y - r, origin.y + r + 1):
			for x in range(origin.x - r, origin.x + r + 1):
				if out.size() >= count:
					return out
				var tile := Vector2i(x, y)
				if PlacementSystem.can_place_at(tile):
					out.append(tile)
	return out


func _seed_extra_hostiles(world: Node, npc_sim: Node, player_pos: Vector2) -> int:
	if npc_sim == null or not npc_sim.has_method("enqueue_spawn"):
		return 0
	var loaded_chunks: Dictionary = world.get("loaded_chunks") as Dictionary
	if loaded_chunks.is_empty():
		return 0
	var sample_states: Array[Dictionary] = []
	for chunk_pos in loaded_chunks.keys():
		for enemy_id in WorldSave.iter_enemy_ids_in_chunk_pos(chunk_pos):
			var st: Dictionary = WorldSave.get_enemy_state_at_chunk_pos(chunk_pos, enemy_id)
			if st.is_empty() or bool(st.get("is_dead", false)):
				continue
			sample_states.append(st)
			if sample_states.size() >= 8:
				break
		if sample_states.size() >= 8:
			break
	if sample_states.is_empty():
		return 0
	var spawned: int = 0
	var target_chunk: Vector2i = loaded_chunks.keys()[0]
	for i in range(EXTRA_HOSTILES_TARGET):
		var template: Dictionary = sample_states[i % sample_states.size()].duplicate(true)
		var angle: float = (TAU * float(i)) / float(maxi(EXTRA_HOSTILES_TARGET, 1))
		var radius: float = 180.0 + float(i % 5) * 18.0
		template["pos"] = player_pos + Vector2(cos(angle), sin(angle)) * radius
		template["is_dead"] = false
		var enemy_id: String = "stress_hostile_%d_%d" % [Time.get_ticks_msec(), i]
		npc_sim.call("enqueue_spawn", target_chunk, enemy_id, template, false)
		spawned += 1
	return spawned


func _percentile(samples: Array[float], q: float) -> float:
	if samples.is_empty():
		return 0.0
	var copy: Array[float] = samples.duplicate()
	copy.sort()
	var idx: int = int(clampf(q, 0.0, 1.0) * float(copy.size() - 1))
	return copy[idx]


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		_record("bootstrap", false, "No se pudo cargar scenes/main.tscn")
		_finalize_and_quit()
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait_frames(25)

	var world := main.get_node_or_null("World")
	var player := main.get_node_or_null("Player") as Node2D
	var npc_sim := world.get_node_or_null("NpcSimulator")
	var bbl := world.get_node_or_null("BanditBehaviorLayer")
	var walls_tm := world.get_node_or_null("StructureWallsMap") as TileMap
	if world == null or player == null or walls_tm == null or bbl == null:
		_record("bootstrap", false, "World/Player/BanditBehaviorLayer/StructureWallsMap no disponibles")
		_finalize_and_quit()
		return

	if world.has_method("reset_placement_react_debug_metrics"):
		world.call("reset_placement_react_debug_metrics")
	if bbl.has_method("reset_structure_dispatch_debug_metrics"):
		bbl.call("reset_structure_dispatch_debug_metrics")

	var spawned_extra: int = _seed_extra_hostiles(world, npc_sim, player.global_position)
	await _wait_frames(40)

	_inject_build_items(player, PLACEMENT_BURSTS * WALLS_PER_BURST + 24, PLACEMENT_BURSTS * DOORS_PER_BURST + 24)
	var origin_tile: Vector2i = walls_tm.local_to_map(walls_tm.to_local(player.global_position))

	var frame_ms_samples: Array[float] = []
	var window_data: Dictionary = {}
	var start_usec: int = Time.get_ticks_usec()
	var prev_react_events: int = 0
	var prev_dispatches: int = 0
	var prev_groups_activated: int = 0
	var prev_scav_non_econ: int = 0
	var prev_invalidate_total: int = 0
	var prev_deposit_hits: int = 0
	var raid_loot_carry_hits: int = 0
	var repaths_per_pulse_peak: int = 0

	for burst in range(PLACEMENT_BURSTS):
		var wall_tiles: Array[Vector2i] = _find_valid_wall_tiles(world, origin_tile + Vector2i(burst * 2, 0), WALLS_PER_BURST)
		for tile in wall_tiles:
			world.call("place_player_wall_at_tile", tile)
		var door_tiles: Array[Vector2i] = _find_valid_door_tiles(origin_tile + Vector2i(0, burst * 2), DOORS_PER_BURST)
		PlacementSystem.begin_placement("doorwood")
		for tile in door_tiles:
			PlacementSystem.call("_do_place_at_tile", tile)
		PlacementSystem.cancel_placement()

		for _f in range(FRAMES_BETWEEN_BURSTS):
			var frame_t0: int = Time.get_ticks_usec()
			await process_frame
			var frame_ms: float = float(Time.get_ticks_usec() - frame_t0) / 1000.0
			frame_ms_samples.append(frame_ms)
			var elapsed_sec: float = float(Time.get_ticks_usec() - start_usec) / 1000000.0
			var bucket: int = int(floor(elapsed_sec / WINDOW_SEC))
			if not window_data.has(bucket):
				window_data[bucket] = {
					"dispatches": 0,
					"events": 0,
					"groups_activated": 0,
					"invalidate": 0,
					"repaths_peak": 0,
					"scav_non_econ_delta": 0,
				}
			var bucket_row: Dictionary = window_data[bucket] as Dictionary

			var react_snap: Dictionary = world.call("get_placement_react_debug_snapshot") if world.has_method("get_placement_react_debug_snapshot") else {}
			var dispatch_snap: Dictionary = bbl.call("get_structure_dispatch_debug_snapshot") if bbl.has_method("get_structure_dispatch_debug_snapshot") else {}
			var invalidate_snap: Dictionary = NpcPathService.get_invalidate_debug_snapshot() if NpcPathService.has_method("get_invalidate_debug_snapshot") else {}
			var world_snap: Dictionary = world.call("get_debug_snapshot") if world.has_method("get_debug_snapshot") else {}
			var drop_metrics: Dictionary = world_snap.get("drop_metrics", {}) as Dictionary

			var events_total: int = int(react_snap.get("events_total", 0))
			var dispatch_total: int = int(react_snap.get("intents_published_total", 0))
			var groups_total: int = int(react_snap.get("groups_activated_total", 0))
			var scav_non_econ_total: int = int(dispatch_snap.get("scavenger_non_econ_orders", 0))
			var repath_pulse: int = int(dispatch_snap.get("repaths_last_pulse", 0))
			var inv_counts: Dictionary = invalidate_snap.get("counts_total", {}) as Dictionary
			var inv_total: int = int(inv_counts.get("new_target", 0)) + int(inv_counts.get("state_change", 0)) + int(inv_counts.get("forced_reset", 0))
			var deposit_hits: int = int(drop_metrics.get("deposit_compact_path_hits", 0))

			bucket_row["events"] = int(bucket_row.get("events", 0)) + maxi(events_total - prev_react_events, 0)
			bucket_row["dispatches"] = int(bucket_row.get("dispatches", 0)) + maxi(dispatch_total - prev_dispatches, 0)
			bucket_row["groups_activated"] = int(bucket_row.get("groups_activated", 0)) + maxi(groups_total - prev_groups_activated, 0)
			bucket_row["invalidate"] = int(bucket_row.get("invalidate", 0)) + maxi(inv_total - prev_invalidate_total, 0)
			bucket_row["scav_non_econ_delta"] = int(bucket_row.get("scav_non_econ_delta", 0)) + maxi(scav_non_econ_total - prev_scav_non_econ, 0)
			bucket_row["repaths_peak"] = maxi(int(bucket_row.get("repaths_peak", 0)), repath_pulse)

			if repath_pulse > repaths_per_pulse_peak:
				repaths_per_pulse_peak = repath_pulse

			var raiding_groups: int = 0
			for gid in BanditGroupMemory.get_all_group_ids():
				var g: Dictionary = BanditGroupMemory.get_group(String(gid))
				if String(g.get("current_group_intent", "")) == "raiding":
					raiding_groups += 1
			if raiding_groups > 0 and deposit_hits > prev_deposit_hits and int(dispatch_total - prev_dispatches) > 0:
				raid_loot_carry_hits += 1

			prev_react_events = events_total
			prev_dispatches = dispatch_total
			prev_groups_activated = groups_total
			prev_scav_non_econ = scav_non_econ_total
			prev_invalidate_total = inv_total
			prev_deposit_hits = deposit_hits

	var elapsed_total: float = float(Time.get_ticks_usec() - start_usec) / 1000000.0
	if elapsed_total < HARNESS_DURATION_SEC:
		await _wait_frames(int((HARNESS_DURATION_SEC - elapsed_total) * 60.0))

	var p95: float = _percentile(frame_ms_samples, 0.95)
	var p99: float = _percentile(frame_ms_samples, 0.99)
	var react_final: Dictionary = world.call("get_placement_react_debug_snapshot") if world.has_method("get_placement_react_debug_snapshot") else {}
	var events_final: int = int(react_final.get("events_total", 0))
	var dispatch_final: int = int(react_final.get("intents_published_total", 0))
	var groups_final: int = int(react_final.get("groups_activated_total", 0))
	var dispatches_per_event: float = float(dispatch_final) / float(maxi(events_final, 1))
	var groups_per_event: float = float(groups_final) / float(maxi(events_final, 1))
	var inv_final: Dictionary = NpcPathService.get_invalidate_debug_snapshot() if NpcPathService.has_method("get_invalidate_debug_snapshot") else {}
	var inv_final_counts: Dictionary = inv_final.get("counts_total", {}) as Dictionary
	var invalidate_total: int = int(inv_final_counts.get("new_target", 0)) + int(inv_final_counts.get("state_change", 0)) + int(inv_final_counts.get("forced_reset", 0))
	var invalidate_per_sec: float = float(invalidate_total) / maxf(HARNESS_DURATION_SEC, 1.0)
	var dispatch_final_snap: Dictionary = bbl.call("get_structure_dispatch_debug_snapshot") if bbl.has_method("get_structure_dispatch_debug_snapshot") else {}
	var scav_non_econ_total: int = int(dispatch_final_snap.get("scavenger_non_econ_orders", 0))

	_record("frame_p95_ms", p95 <= float(THRESHOLDS["p95_frame_ms_max"]), "p95=%.2f threshold<=%.2f" % [p95, float(THRESHOLDS["p95_frame_ms_max"])])
	_record("frame_p99_ms", p99 <= float(THRESHOLDS["p99_frame_ms_max"]), "p99=%.2f threshold<=%.2f" % [p99, float(THRESHOLDS["p99_frame_ms_max"])])
	_record("dispatches_per_event", dispatches_per_event >= float(THRESHOLDS["dispatches_per_event_min"]), "dispatches_per_event=%.2f threshold>=%.2f events=%d" % [dispatches_per_event, float(THRESHOLDS["dispatches_per_event_min"]), events_final])
	_record("repaths_per_pulse_peak", float(repaths_per_pulse_peak) <= float(THRESHOLDS["repaths_per_pulse_max"]), "peak=%d threshold<=%.2f" % [repaths_per_pulse_peak, float(THRESHOLDS["repaths_per_pulse_max"])])
	_record("invalidate_path_per_sec", invalidate_per_sec <= float(THRESHOLDS["invalidate_path_per_sec_max"]), "invalidate/s=%.2f threshold<=%.2f" % [invalidate_per_sec, float(THRESHOLDS["invalidate_path_per_sec_max"])])
	_record("groups_activated_per_event", groups_per_event >= float(THRESHOLDS["groups_activated_per_event_min"]), "groups/event=%.2f threshold>=%.2f" % [groups_per_event, float(THRESHOLDS["groups_activated_per_event_min"])])
	_record("scavenger_non_economic_orders", scav_non_econ_total <= int(THRESHOLDS["scavenger_non_econ_orders_max"]), "count=%d threshold<=%d" % [scav_non_econ_total, int(THRESHOLDS["scavenger_non_econ_orders_max"])])
	_record("raid_loot_carry_coexistence", raid_loot_carry_hits >= int(THRESHOLDS["raid_loot_carry_coexistence_min_hits"]), "hits=%d threshold>=%d spawned_extra_hostiles=%d" % [raid_loot_carry_hits, int(THRESHOLDS["raid_loot_carry_coexistence_min_hits"]), spawned_extra])

	var report: Dictionary = {
		"thresholds": THRESHOLDS,
		"metrics": {
			"frame_p95_ms": p95,
			"frame_p99_ms": p99,
			"events_total": events_final,
			"dispatches_total": dispatch_final,
			"dispatches_per_event": dispatches_per_event,
			"groups_activated_total": groups_final,
			"groups_activated_per_event": groups_per_event,
			"repaths_per_pulse_peak": repaths_per_pulse_peak,
			"invalidate_path_per_sec": invalidate_per_sec,
			"scavenger_non_economic_orders": scav_non_econ_total,
			"raid_loot_carry_coexistence_hits": raid_loot_carry_hits,
			"spawned_extra_hostiles": spawned_extra,
		},
		"windows": window_data,
		"results": _results,
	}
	var file := FileAccess.open("user://placement_raid_loot_stress_report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()

	_finalize_and_quit()


func _finalize_and_quit() -> void:
	var total: int = _results.size()
	var passed: int = 0
	for row in _results:
		if bool((row as Dictionary).get("ok", false)):
			passed += 1
	print("[HARNESS] SUMMARY passed=", passed, " total=", total)
	quit(0 if passed == total else 1)
