extends RefCounted
class_name BanditGroupIntel

# ── BanditGroupIntel ─────────────────────────────────────────────────────────
# Responsibility boundary:
# BanditGroupIntel owns group-level sensing plus the immediate dispatch that
# follows from each scan: it scans nearby settlement markers/bases, builds the
# activity score, chooses the best interest point, forwards the score +
# persistent faction profile to BanditIntentPolicy, and can enqueue short-term
# group responses (presence hostility, extortion, raids) when policy gates pass.
# It does not own long-term hostility state storage, the intent-policy tuning
# itself, or the execution of those queued social escalations.
#
# Future tavern note:
# when a local civil authority exists, its memory/authority should feed this
# layer as extra inputs or parallel signals, not replace the bandit global
# hostility profile and not live inside BanditBehaviorLayer.

# ── Scoring weights ───────────────────────────────────────────────────────────
const W_BASE_DETECTED: float  = 15.0
const W_WORKBENCH: float      = 10.0
const W_STRUCTURE: float      =  6.0
const W_MINE: float           =  3.0
const W_CHOP: float           =  2.0

const SimulationLODPolicyScript := preload("res://scripts/world/SimulationLODPolicy.gd")
const CombatStateServiceScript  := preload("res://scripts/world/CombatStateService.gd")

var _get_markers_near: Callable
var _get_bases_near: Callable
var _npc_simulator: NpcSimulator
var _player: Node2D
const GROUP_SCAN_SLICE_COUNT: int = 4

var _scan_timer: float = BanditTuning.group_scan_interval() * 0.37
var _scan_cursor: int = 0
var _intent_policy := BanditIntentPolicy.new()
var _scan_accumulator_by_group: Dictionary = {}
var _lod_debug_last_group: Dictionary = {}
var _lod_debug_group_counts: Dictionary = {"fast": 0, "medium": 0, "slow": 0}
const EXECUTION_INTENT_TTL_EXTORT: float = 120.0
const EXECUTION_INTENT_TTL_RAID: float = 240.0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	_get_markers_near = ctx.get("get_interest_markers_near", Callable())
	_get_bases_near   = ctx.get("get_detected_bases_near",   Callable())
	_npc_simulator    = ctx.get("npc_simulator")
	_player           = ctx.get("player") as Node2D


# ---------------------------------------------------------------------------
# Tick — called from BanditBehaviorLayer._process()
# This scan slice remains intentionally local: it is an internal fairness loop
# over bandit groups, not a shared world-maintenance pulse. The coordinator
# governs when the outer bandit layer/directors wake up; this class governs how
# it amortizes its own per-group scan budget once awake.
# ---------------------------------------------------------------------------

func tick(delta: float) -> void:
	var slice_interval: float = BanditTuning.group_scan_interval() / float(maxi(GROUP_SCAN_SLICE_COUNT, 1))
	_scan_timer += delta
	if _scan_timer < slice_interval:
		return
	_scan_timer -= slice_interval
	_scan_group_slice()


# ---------------------------------------------------------------------------
# Scan all registered groups
# ---------------------------------------------------------------------------

func _scan_group_slice() -> void:
	var group_ids: Array = BanditGroupMemory.get_all_group_ids()
	if group_ids.is_empty():
		_scan_cursor = 0
		_scan_accumulator_by_group.clear()
		_lod_debug_last_group.clear()
		_lod_debug_group_counts = {"fast": 0, "medium": 0, "slow": 0}
		return
	_prune_removed_groups(group_ids)
	_lod_debug_last_group.clear()
	_lod_debug_group_counts = {"fast": 0, "medium": 0, "slow": 0}
	var per_slice: int = maxi(1, int(ceil(float(group_ids.size()) / float(maxi(GROUP_SCAN_SLICE_COUNT, 1)))))
	for _i in per_slice:
		if group_ids.is_empty():
			break
		if _scan_cursor >= group_ids.size():
			_scan_cursor = 0
		var group_id: String = String(group_ids[_scan_cursor])
		_scan_cursor += 1
		var g: Dictionary = BanditGroupMemory.get_group(group_id)
		if g.is_empty():
			continue
		var elapsed: float = _get_elapsed_for_group(group_id)
		var interval: float = _get_group_scan_interval(group_id, g)
		if elapsed < interval:
			continue
		_scan_group(group_id, g)
		_scan_accumulator_by_group[group_id] = maxf(elapsed - interval, 0.0)




func _prune_removed_groups(group_ids: Array) -> void:
	var live: Dictionary = {}
	for gid in group_ids:
		live[String(gid)] = true
	for gid in _scan_accumulator_by_group.keys():
		if not live.has(String(gid)):
			_scan_accumulator_by_group.erase(gid)


func _get_elapsed_for_group(group_id: String) -> float:
	var elapsed: float = float(_scan_accumulator_by_group.get(group_id, 0.0))
	elapsed += BanditTuning.group_scan_interval() / float(maxi(GROUP_SCAN_SLICE_COUNT, 1))
	_scan_accumulator_by_group[group_id] = elapsed
	return elapsed


func _get_group_scan_interval(group_id: String, g: Dictionary) -> float:
	var leader_id: String = String(g.get("leader_id", ""))
	var leader = _npc_simulator.get_enemy_node(leader_id) if _npc_simulator != null and leader_id != "" else null
	var home_pos: Vector2 = g.get("home_world_pos", Vector2.ZERO)
	var distance_to_player: float = INF
	var is_visible: bool = false
	if _player != null and is_instance_valid(_player):
		var anchor: Vector2 = leader.global_position if leader != null else home_pos
		distance_to_player = anchor.distance_to(_player.global_position)
		if leader != null and leader.has_method("is_on_screen"):
			is_visible = bool(leader.is_on_screen())
	var current_intent: String = String(g.get("current_group_intent", "idle"))
	var group_signals: Dictionary = _get_group_lod_signals(leader, current_intent, g)
	var lod_debug: Dictionary = SimulationLODPolicyScript.get_bandit_group_scan_debug({
		"base_interval": BanditTuning.group_scan_interval(),
		"distance_to_player": distance_to_player,
		"intent": current_intent,
		"is_visible": is_visible,
		"in_combat": bool(group_signals.get("is_in_direct_combat", false)),
		"recently_engaged": bool(group_signals.get("was_recently_engaged", false)),
		"has_player_signal": bool(group_signals.get("is_alerted_to_player_activity", false)),
		"has_base_signal": String(g.get("last_interest_kind", "")) == "base_detected",
	})
	_record_group_lod_debug(group_id, current_intent, lod_debug, group_signals)
	return float(lod_debug.get("interval", BanditTuning.group_scan_interval()))


func _get_group_lod_signals(leader: Node, current_intent: String, g: Dictionary) -> Dictionary:
	var combat_state: Dictionary = CombatStateServiceScript.read_actor_state(leader)
	if leader != null and is_instance_valid(leader):
		var _let: Variant = leader.get("last_engaged_time")
		var ai_comp = leader.get("ai_component")
		var current_state: int = int(ai_comp.get("current_state")) if ai_comp != null else -1
		var current_target = ai_comp.get_current_target() if ai_comp != null and ai_comp.has_method("get_current_target") else null
		var has_active_target: bool = current_target != null and is_instance_valid(current_target)
		combat_state = CombatStateServiceScript.update_actor_state(leader, {
			"current_state": current_state,
			"has_active_target": has_active_target,
			"is_world_behavior_eligible": bool(leader.has_method("is_world_behavior_eligible") and leader.is_world_behavior_eligible()),
			"last_engaged_time": float(_let) if _let != null else 0.0,
		})
	var is_alerted_to_player_activity: bool = current_intent != "idle" or String(g.get("last_interest_kind", "")) != ""
	var is_pursuing_pressure: bool = current_intent == "hunting" or current_intent == "raiding" or current_intent == "extorting"
	return {
		"is_in_direct_combat": bool(combat_state.get("is_in_direct_combat", false)),
		"was_recently_engaged": bool(combat_state.get("was_recently_engaged", false)),
		"is_alerted_to_player_activity": is_alerted_to_player_activity,
		"is_pursuing_pressure": is_pursuing_pressure,
		"is_runtime_busy_but_not_combat": bool(combat_state.get("is_runtime_busy_but_not_combat", false)),
	}


func _record_group_lod_debug(group_id: String, current_intent: String, lod_debug: Dictionary, group_signals: Dictionary) -> void:
	var bucket: String = String(lod_debug.get("bucket", "medium"))
	_lod_debug_group_counts[bucket] = int(_lod_debug_group_counts.get(bucket, 0)) + 1
	_lod_debug_last_group[group_id] = {
		"intent": current_intent,
		"interval": float(lod_debug.get("interval", BanditTuning.group_scan_interval())),
		"bucket": bucket,
		"dominant_reason": String(lod_debug.get("dominant_reason", "baseline")),
		"is_in_direct_combat": bool(group_signals.get("is_in_direct_combat", false)),
		"was_recently_engaged": bool(group_signals.get("was_recently_engaged", false)),
		"is_alerted_to_player_activity": bool(group_signals.get("is_alerted_to_player_activity", false)),
		"is_pursuing_pressure": bool(group_signals.get("is_pursuing_pressure", false)),
		"is_runtime_busy_but_not_combat": bool(group_signals.get("is_runtime_busy_but_not_combat", false)),
	}
	if _is_lod_debug_logging_enabled():
		Debug.log("bandit_lod", "[BanditLOD][group] group=%s interval=%.2f bucket=%s reason=%s combat=%s engaged=%s alert=%s pursue=%s" % [
			group_id,
			float(lod_debug.get("interval", 0.0)),
			bucket,
			String(lod_debug.get("dominant_reason", "baseline")),
			str(bool(group_signals.get("is_in_direct_combat", false))),
			str(bool(group_signals.get("was_recently_engaged", false))),
			str(bool(group_signals.get("is_alerted_to_player_activity", false))),
			str(bool(group_signals.get("is_pursuing_pressure", false))),
		])


func get_lod_debug_snapshot() -> Dictionary:
	return {
		"group_counts": _lod_debug_group_counts.duplicate(true),
		"group_intervals": _lod_debug_last_group.duplicate(true),
	}


func _is_lod_debug_logging_enabled() -> bool:
	return Debug.is_enabled("ai") and Debug.is_enabled("bandit_lod")

func _scan_group(group_id: String, g: Dictionary) -> void:
	# Only react if the group has a live leader node
	var leader_id: String = String(g.get("leader_id", ""))
	if leader_id == "":
		return
	if _npc_simulator == null or _npc_simulator.get_enemy_node(leader_id) == null:
		return

	var home_pos: Vector2 = g.get("home_world_pos", Vector2.ZERO)

	# Query SettlementIntel
	var markers: Array[Dictionary] = []
	var bases: Array[Dictionary]   = []
	if _get_markers_near.is_valid():
		markers = _get_markers_near.call(home_pos, BanditTuning.group_territory_radius())
	if _get_bases_near.is_valid():
		bases = _get_bases_near.call(home_pos, BanditTuning.group_territory_radius())

	var score: float = _score_activity(markers, bases)

	var faction_id: String = String(g.get("faction_id", "bandits"))

	# ── Presencia del jugador: eventos granulares por tipo de actividad ───
	# Cada categoría detectada dispara su propio incidente con entity_id distinto
	# para que el dedup no los bloquee entre sí. El total por scan puede ser
	# mayor que un simple "player_trespassed" si el jugador tiene base + taller + minería.
	_fire_presence_hostility(markers, bases, faction_id, group_id, home_pos)

	var profile: FactionBehaviorProfile = FactionHostilityManager.get_behavior_profile(faction_id)
	var h_level: int = profile.hostility_level
	var w_tier: int = FactionHostilityManager.get_wealth_tier(faction_id)
	var current_intent: String = String(g.get("current_group_intent", "idle"))
	_resolve_execution_rejections(group_id, current_intent)
	g = BanditGroupMemory.get_group(group_id)
	current_intent = String(g.get("current_group_intent", "idle"))
	var intent_time: float = BanditGroupMemory.get_intent_time(group_id)
	var internal_cd: float = BanditGroupMemory.get_internal_social_cooldown_remaining(group_id)
	var policy: Dictionary = _intent_policy.evaluate(score, profile, w_tier, current_intent, intent_time, internal_cd)
	var effective_score: float = float(policy.get("effective_score", score))
	var effective_t_alerted: float = float(policy.get("effective_alerted_threshold", BanditTuning.alerted_threshold()))
	var effective_t_hunting: float = float(policy.get("effective_hunting_threshold", BanditTuning.hunting_threshold()))
	var new_intent: String = String(policy.get("next_intent", current_intent))

	# No resetear a "idle" si hay un asalto de placement_react activo para este grupo
	if new_intent == "idle" and BanditGroupMemory.has_placement_react_lock(group_id):
		return
	BanditGroupMemory.update_intent(group_id, new_intent)

	if new_intent == "idle":
		BanditGroupMemory.set_scout(group_id, "")
		return

	# Pick and record best interest point
	var interest = _pick_best_interest(markers, bases)
	if interest != null:
		BanditGroupMemory.record_interest(group_id, interest.pos, interest.kind)
		Debug.log("bandit_intel", "[BGI] group=%s score=%.1f eff=%.1f intent=%s lv%d a=%.1f h=%.1f t=%.1f cd=%.1f" % [
			group_id, score, effective_score, new_intent, h_level, effective_t_alerted, effective_t_hunting, intent_time, internal_cd])

	# For "alerted": designate exactly one scout
	if new_intent == "alerted":
		var scout: String = _pick_scout(group_id, g)
		BanditGroupMemory.set_scout(group_id, scout)
	else:
		# hunting/extorting: clear scout (leader + bodyguards handle it)
		BanditGroupMemory.set_scout(group_id, "")

	if interest != null and bool(policy.get("can_extort_now", false)):
		_maybe_enqueue_extortion(group_id, g, interest, score, markers, bases)

	if not bases.is_empty() and bool(policy.get("can_full_raid_now", false)):
		_maybe_enqueue_raid(group_id, g, bases[0], faction_id)
	elif not bases.is_empty() and bool(policy.get("can_light_raid_now", false)):
		_maybe_enqueue_light_raid(group_id, g, bases[0], faction_id)
	elif not bases.is_empty() and bool(policy.get("can_wall_probe_now", false)):
		_maybe_enqueue_wall_probe(group_id, g, bases[0], faction_id, h_level)


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

func _score_activity(markers: Array, bases: Array) -> float:
	var score: float = 0.0
	for b in bases:
		score += W_BASE_DETECTED
	for m in markers:
		match String(m.get("kind", "")):
			"workbench":        score += W_WORKBENCH
			"structure_placed": score += W_STRUCTURE
			"copper_mined":     score += W_MINE
			"stone_mined":      score += W_MINE
			"wood_chopped":     score += W_CHOP
	return score


# ---------------------------------------------------------------------------
# Interest point selection — priority: base > workbench > structure > activity
# ---------------------------------------------------------------------------

func _pick_best_interest(markers: Array, bases: Array) -> Dictionary:
	if not bases.is_empty():
		var b: Dictionary = bases[0] as Dictionary
		return {"pos": b.get("center_world_pos", Vector2.ZERO), "kind": "base_detected"}
	var best_wb: Dictionary  = {}
	var best_st: Dictionary  = {}
	var best_act: Dictionary = {}
	for m in markers:
		var kind: String  = String(m.get("kind", ""))
		var pos: Vector2  = m.get("world_pos", Vector2.ZERO)
		if kind == "workbench" and best_wb.is_empty():
			best_wb = {"pos": pos, "kind": kind}
		elif kind == "structure_placed" and best_st.is_empty():
			best_st = {"pos": pos, "kind": kind}
		elif best_act.is_empty():
			best_act = {"pos": pos, "kind": kind}
	if not best_wb.is_empty():
		return best_wb
	if not best_st.is_empty():
		return best_st
	return best_act


# ---------------------------------------------------------------------------
# Scout selection — one non-leader sleeping member per group
# ---------------------------------------------------------------------------

func _pick_scout(group_id: String, g: Dictionary) -> String:
	var member_ids: Array = g.get("member_ids", [])
	var leader_id: String = String(g.get("leader_id", ""))

	# Priority: scavenger+sleeping > bodyguard+sleeping > scavenger+alive > bodyguard+alive > any alive non-leader
	var best_scav_sleep:  String = ""
	var best_guard_sleep: String = ""
	var best_scav_alive:  String = ""
	var best_guard_alive: String = ""
	var best_any_alive:   String = ""

	for mid in member_ids:
		var id: String = String(mid)
		if id == leader_id:
			continue
		var node = _npc_simulator.get_enemy_node(id)
		if node == null:
			continue
		var r: String = String(NpcProfileSystem.get_profile(id).get("role", ""))
		var sleeping: bool = node.is_sleeping()
		if r == "scavenger":
			if sleeping and best_scav_sleep == "":
				best_scav_sleep = id
			elif best_scav_alive == "":
				best_scav_alive = id
		elif r == "bodyguard":
			if sleeping and best_guard_sleep == "":
				best_guard_sleep = id
			elif best_guard_alive == "":
				best_guard_alive = id
		if best_any_alive == "":
			best_any_alive = id

	if best_scav_sleep  != "": return best_scav_sleep
	if best_guard_sleep != "": return best_guard_sleep
	if best_scav_alive  != "": return best_scav_alive
	if best_guard_alive != "": return best_guard_alive
	return best_any_alive


# ---------------------------------------------------------------------------
# Extortion enqueue — one intent per group, spam-guarded
# ---------------------------------------------------------------------------

func _maybe_enqueue_extortion(group_id: String, g: Dictionary,
		interest: Dictionary, score: float,
		markers: Array, bases: Array) -> void:
	# Guard 1: already queued for this group
	if ExtortionQueue.has_pending_for_group(group_id):
		Debug.log("bandit_intel", "[BGI] extortion pending — skip group=%s" % group_id)
		return

	var leader_id:  String = String(g.get("leader_id",  ""))
	var faction_id: String = String(g.get("faction_id", "bandits"))
	var pay_data: FactionHostilityData = FactionHostilityManager.get_faction_state(faction_id)
	var w_tier: int = FactionHostilityManager.get_wealth_tier(faction_id)

	# Guard 2: cooldown efectivo con dos modificadores acumulativos:
	#   • compliance_score → pagadores frecuentes reciben demandas más seguidas (−50% max)
	#   • wealth_tier → banda rica también extorsiona más (hasta −45% adicional)
	var compliance_factor: float = 1.0 - pay_data.compliance_score * 0.5
	var wealth_factor: float     = FactionHostilityManager.WEALTH_EXTORT_COOLDOWN_FACTOR[w_tier]
	var effective_cooldown: float = BanditTuning.extort_cooldown_base() * compliance_factor * wealth_factor
	var cooldown_remaining: float = ExtortionQueue.get_cooldown_remaining(group_id, effective_cooldown)
	if cooldown_remaining > 0.0:
		Debug.log("bandit_intel", "[BGI] extortion cooldown %.0fs left group=%s" % [
			cooldown_remaining, group_id])
		return

	# Severity: score base + bonus compliance (saben que paga) + bonus wealth (demandan más)
	var base_severity: float    = clampf((score - BanditIntentPolicy.EXTORT_SCORE_THRESHOLD) / (W_BASE_DETECTED * 2.0), 0.1, 1.0)
	var compliance_bonus: float = pay_data.compliance_score * 0.3
	var wealth_bonus: float     = float(w_tier) * 0.1  # tier 3 → +0.3 severidad
	var severity: float         = clampf(base_severity + compliance_bonus + wealth_bonus, 0.1, 1.0)

	# Causa dominante — decide qué texto verá el jugador en el modal de extorsión
	var extort_reason: String = _pick_extort_reason(markers, bases, pay_data.compliance_score, w_tier)

	ExtortionQueue.enqueue({
		"target_id":     "player",
		"faction_id":    faction_id,
		"group_id":      group_id,
		"source_npc_id": leader_id,
		"trigger_kind":  interest.kind,
		"world_pos":     interest.pos,
		"created_at":    RunClock.now(),
		"severity":      clampf(severity, 0.0, 1.0),
		"extort_reason": extort_reason,
	})
	BanditGroupMemory.issue_execution_intent(
		group_id, "extorting", "BanditGroupIntel", EXECUTION_INTENT_TTL_EXTORT, {"source": "extortion_queue"})
	BanditGroupMemory.push_social_cooldown(group_id, maxf(4.0, effective_cooldown * 0.15))
	BanditGroupMemory.update_intent(group_id, "extorting")
	Debug.log("bandit_intel",
		"[BGI] extortion enqueued group=%s leader=%s kind=%s sev=%.2f compliance=%.2f wealth=%.0f(t%d)" % [
		group_id, leader_id, interest.kind, severity, pay_data.compliance_score,
		pay_data.band_wealth, w_tier])


# ---------------------------------------------------------------------------
# Presence hostility — disparo granular por tipo de actividad detectada
# ---------------------------------------------------------------------------

## Dispara un incidente de hostilidad por cada categoría de actividad presente
## en el scan. Cada categoría tiene entity_id distinto para que el dedup
## no bloquee el conjunto — base + workbench + minería suman todos.
##
## Tabla de pts/scan (producción, SCAN_INTERVAL ≈ 8 s):
##   base_detected     10 pts  — amenaza territorial seria
##   workbench_near     5 pts  — estás produciendo, progresando
##   resource_extracted 2.5 pts — sacando recursos de su zona
##   structure_near     1.5 pts — señal de asentamiento
##   player_trespassed  6 pts  — fallback: actividad sin categoría clara
func _fire_presence_hostility(markers: Array, bases: Array,
		faction_id: String, group_id: String, home_pos: Vector2) -> void:
	var fired: bool = false

	# Base detectada — la mayor amenaza
	for b in bases:
		var base_id: String = String(b.get("id", group_id + ":base"))
		FactionHostilityManager.add_hostility(faction_id, 0.0, "base_detected",
			{"group_id": group_id, "entity_id": base_id, "position": home_pos})
		fired = true
		break  # una base por scan es suficiente

	# Clasificar marcadores por tipo
	var has_workbench: bool = false
	var has_structure: bool = false
	var has_mining:    bool = false
	for m in markers:
		match String(m.get("kind", "")):
			"workbench":        has_workbench = true
			"structure_placed": has_structure = true
			"copper_mined", "stone_mined", "wood_chopped":
				has_mining = true

	if has_workbench:
		FactionHostilityManager.add_hostility(faction_id, 0.0, "workbench_near",
			{"group_id": group_id, "entity_id": group_id + ":wb", "position": home_pos})
		fired = true

	if has_mining:
		FactionHostilityManager.add_hostility(faction_id, 0.0, "resource_extracted",
			{"group_id": group_id, "entity_id": group_id + ":mine", "position": home_pos})
		fired = true

	if has_structure:
		FactionHostilityManager.add_hostility(faction_id, 0.0, "structure_near",
			{"group_id": group_id, "entity_id": group_id + ":st", "position": home_pos})
		fired = true

	# Fallback: actividad genérica sin categoría clara (o jugador merodeando sin dejar rastro)
	if not fired:
		var score_val: float = _score_activity(markers, bases)
		if score_val > 0.0:
			FactionHostilityManager.add_hostility(faction_id, 0.0, "player_trespassed",
				{"group_id": group_id, "entity_id": group_id, "position": home_pos})


# ---------------------------------------------------------------------------
# Extortion reason — causa dominante de esta extorsión
# ---------------------------------------------------------------------------

## Elige la razón principal que el jugador verá en el modal de extorsión.
## Prioridad: pagador recurrente > base creciendo > minería activa >
##             riqueza visible > territorial genérico.
func _pick_extort_reason(markers: Array, bases: Array,
		compliance: float, w_tier: int) -> String:
	# "Ya pagaste antes, sabemos que tienes con qué"
	if compliance > 0.5:
		return "returning_payer"
	# "Tu base está creciendo demasiado cerca"
	if not bases.is_empty():
		return "base_growth"
	# "Estás sacando demasiado de nuestro territorio"
	var mining_score: float = 0.0
	for m in markers:
		match String(m.get("kind", "")):
			"copper_mined", "stone_mined": mining_score += W_MINE
			"wood_chopped":                mining_score += W_CHOP
	if mining_score >= W_MINE * 2.0:
		return "mining"
	# "Tienes taller, tienes recursos"
	if w_tier >= 2:
		return "visible_wealth"
	# "Te dejamos pasar una vez. Esta vez cobras peaje."
	return "territorial"


# ---------------------------------------------------------------------------
# Wall probe enqueue — niveles 1-6, envía 1-2 bandidos a golpear una pared
# ---------------------------------------------------------------------------

## Encola un probe de pared para bandas de nivel 1-6 que detectaron una base.
## Solo "de vez en cuando": gate triple de cooldown × probabilidad × pendiente.
## squad_size y cooldown escalan con el nivel (ver BanditTuning.wall_probe_config).
func _maybe_enqueue_wall_probe(group_id: String, g: Dictionary,
		base: Dictionary, faction_id: String, h_level: int) -> void:
	# Guard 1: ya raideando o con raid/probe pendiente
	var current_intent: String = String(BanditGroupMemory.get_group(group_id).get("current_group_intent", ""))
	if current_intent == "raiding":
		return
	if RaidQueue.has_pending_for_group(group_id):
		return

	# Guard 2: cooldown específico de probe (más largo que raids, varía por nivel)
	var cfg: Dictionary   = BanditTuning.wall_probe_config(h_level)
	var probe_cd: float   = float(cfg.get("cooldown", 300.0))
	if not RaidQueue.is_wall_probe_available(group_id, probe_cd):
		return

	# Guard 3: roll de probabilidad — "de vez en cuando", no sistemático
	var chance: float = float(cfg.get("chance", 0.10))
	if randf() >= chance:
		return

	var leader_id: String    = String(g.get("leader_id", ""))
	var base_center: Vector2 = base.get("center_world_pos", Vector2.ZERO) as Vector2
	var base_id: String      = String(base.get("id", ""))
	var squad_size: int      = int(cfg.get("squad_size", 1))

	RaidQueue.enqueue_wall_probe(faction_id, group_id, leader_id, base_center, base_id, squad_size)
	BanditGroupMemory.issue_execution_intent(
		group_id, "raiding", "BanditGroupIntel", EXECUTION_INTENT_TTL_RAID, {"source": "wall_probe"})
	BanditGroupMemory.push_social_cooldown(group_id, maxf(6.0, probe_cd * 0.10))
	BanditGroupMemory.update_intent(group_id, "raiding")
	BanditGroupMemory.record_interest(group_id, base_center, "base_detected")
	Debug.log("bandit_intel",
		"[BGI] wall probe enqueued group=%s leader=%s base=%s squad=%d lv%d chance=%.2f" % [
		group_id, leader_id, base_id, squad_size, h_level, chance])


# ---------------------------------------------------------------------------
# Light raid enqueue — niveles 7-9, requiere base detectada
# ---------------------------------------------------------------------------

## Encola un raid leve para bandas de nivel 7-9 con can_damage_workbenches.
## El grupo converge en la base del jugador para sabotear workbenches y storage.
## Cooldown independiente: 120s (más frecuente que el raid completo de nivel 10).
func _maybe_enqueue_light_raid(group_id: String, g: Dictionary,
		base: Dictionary, faction_id: String) -> void:
	# Guard 1: ya raideando o con raid pendiente
	var current_intent: String = String(BanditGroupMemory.get_group(group_id).get("current_group_intent", ""))
	if current_intent == "raiding":
		return
	if RaidQueue.has_pending_for_group(group_id):
		return
	# Guard 2: cooldown desde el último raid
	if not RaidQueue.is_raid_available(group_id, BanditTuning.raid_cooldown_base()):
		return

	var leader_id: String    = String(g.get("leader_id", ""))
	var base_center: Vector2 = base.get("center_world_pos", Vector2.ZERO) as Vector2
	var base_id: String      = String(base.get("id", ""))

	RaidQueue.enqueue_light_raid(faction_id, group_id, leader_id, base_center, base_id)
	BanditGroupMemory.issue_execution_intent(
		group_id, "raiding", "BanditGroupIntel", EXECUTION_INTENT_TTL_RAID, {"source": "light_raid"})
	BanditGroupMemory.push_social_cooldown(group_id, maxf(8.0, BanditTuning.raid_cooldown_base() * 0.12))
	BanditGroupMemory.update_intent(group_id, "raiding")
	BanditGroupMemory.record_interest(group_id, base_center, "base_detected")
	Debug.log("bandit_intel", "[BGI] light raid enqueued group=%s leader=%s base=%s" % [
		group_id, leader_id, base_id])


# ---------------------------------------------------------------------------
# Raid enqueue — capacidad exclusiva nivel 10, requiere base detectada
# ---------------------------------------------------------------------------

func _maybe_enqueue_raid(group_id: String, g: Dictionary,
		base: Dictionary, faction_id: String) -> void:
	# Guard 1: ya raideando o con raid pendiente
	var current_intent: String = String(BanditGroupMemory.get_group(group_id).get("current_group_intent", ""))
	if current_intent == "raiding":
		return
	if RaidQueue.has_pending_for_group(group_id):
		return
	# Guard 2: cooldown desde el último raid, reducido por riqueza de la banda
	var w_tier_raid: int         = FactionHostilityManager.get_wealth_tier(faction_id)
	var raid_cd_factor: float    = FactionHostilityManager.WEALTH_RAID_COOLDOWN_FACTOR[w_tier_raid]
	var effective_raid_cd: float = BanditTuning.raid_cooldown_base() * raid_cd_factor
	if not RaidQueue.is_raid_available(group_id, effective_raid_cd):
		Debug.log("bandit_intel", "[BGI] raid cooldown — group=%s" % group_id)
		return

	var leader_id: String  = String(g.get("leader_id",  ""))
	var base_center: Vector2 = base.get("center_world_pos", Vector2.ZERO) as Vector2
	var base_id: String    = String(base.get("id", ""))

	RaidQueue.enqueue_raid(faction_id, group_id, leader_id, base_center, base_id)
	BanditGroupMemory.issue_execution_intent(
		group_id, "raiding", "BanditGroupIntel", EXECUTION_INTENT_TTL_RAID, {"source": "full_raid"})
	BanditGroupMemory.push_social_cooldown(group_id, maxf(12.0, effective_raid_cd * 0.15))
	BanditGroupMemory.update_intent(group_id, "raiding")
	BanditGroupMemory.record_interest(group_id, base_center, "base_detected")
	Debug.log("bandit_intel", "[BGI] raid enqueued group=%s leader=%s base=%s" % [
		group_id, leader_id, base_id])


func _resolve_execution_rejections(group_id: String, current_intent: String) -> void:
	var events: Array = BanditGroupMemory.consume_execution_rejections(group_id)
	if events.is_empty():
		return
	var should_reset: bool = false
	for raw_event in events:
		if not (raw_event is Dictionary):
			continue
		var event: Dictionary = raw_event as Dictionary
		var rejected_intent: String = String(event.get("intent", ""))
		Debug.log("bandit_intel", "[BGI] execution rejection observed group=%s intent=%s source=%s reason=%s owner=%s" % [
			group_id,
			rejected_intent,
			String(event.get("source", "")),
			String(event.get("reason", "")),
			String(event.get("owner", "")),
		])
		if rejected_intent == current_intent:
			should_reset = true
	if should_reset and current_intent != "idle":
		BanditGroupMemory.update_intent(group_id, "idle")
