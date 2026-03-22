extends RefCounted
class_name BanditGroupIntel

# ── BanditGroupIntel ─────────────────────────────────────────────────────────
# Responsibility boundary:
# BanditGroupIntel owns sensing only: scan nearby settlement markers/bases,
# build the base activity score, choose the best interest point, and forward
# the score + persistent faction profile to BanditIntentPolicy.
# It does not own long-term hostility state, intent policy tuning, or social
# escalation rules beyond dispatching the chosen intent/eligibility outcomes.
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

var _get_markers_near: Callable
var _get_bases_near: Callable
var _npc_simulator: NpcSimulator
var _scan_timer: float = 0.0
var _intent_policy := BanditIntentPolicy.new()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	_get_markers_near = ctx.get("get_interest_markers_near", Callable())
	_get_bases_near   = ctx.get("get_detected_bases_near",   Callable())
	_npc_simulator    = ctx.get("npc_simulator")


# ---------------------------------------------------------------------------
# Tick — called from BanditBehaviorLayer._process()
# ---------------------------------------------------------------------------

func tick(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer < BanditTuning.group_scan_interval():
		return
	_scan_timer = 0.0
	_scan_all_groups()


# ---------------------------------------------------------------------------
# Scan all registered groups
# ---------------------------------------------------------------------------

func _scan_all_groups() -> void:
	for group_id in BanditGroupMemory.get_all_group_ids():
		var g: Dictionary = BanditGroupMemory.get_group(group_id)
		if g.is_empty():
			continue
		_scan_group(group_id, g)


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
	var intent_time: float = BanditGroupMemory.get_intent_time(group_id)
	var internal_cd: float = BanditGroupMemory.get_internal_social_cooldown_remaining(group_id)
	var policy: Dictionary = _intent_policy.evaluate(score, profile, w_tier, current_intent, intent_time, internal_cd)
	var effective_score: float = float(policy.get("effective_score", score))
	var effective_t_alerted: float = float(policy.get("effective_alerted_threshold", BanditTuning.alerted_threshold()))
	var effective_t_hunting: float = float(policy.get("effective_hunting_threshold", BanditTuning.hunting_threshold()))
	var new_intent: String = String(policy.get("next_intent", current_intent))

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
	var last_time: float   = ExtortionQueue.get_last_request_time(group_id)
	var elapsed: float     = RunClock.now() - last_time
	var compliance_factor: float = 1.0 - pay_data.compliance_score * 0.5
	var wealth_factor: float     = FactionHostilityManager.WEALTH_EXTORT_COOLDOWN_FACTOR[w_tier]
	var effective_cooldown: float = BanditTuning.extort_cooldown_base() * compliance_factor * wealth_factor
	if elapsed < effective_cooldown:
		Debug.log("bandit_intel", "[BGI] extortion cooldown %.0fs left group=%s" % [
			effective_cooldown - elapsed, group_id])
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
	var last_time: float = RaidQueue.get_last_raid_time(group_id)
	if RunClock.now() - last_time < BanditTuning.raid_cooldown_base():
		return

	var leader_id: String    = String(g.get("leader_id", ""))
	var base_center: Vector2 = base.get("center_world_pos", Vector2.ZERO) as Vector2
	var base_id: String      = String(base.get("id", ""))

	RaidQueue.enqueue_light_raid(faction_id, group_id, leader_id, base_center, base_id)
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
	var last_time: float         = RaidQueue.get_last_raid_time(group_id)
	if RunClock.now() - last_time < effective_raid_cd:
		Debug.log("bandit_intel", "[BGI] raid cooldown — group=%s" % group_id)
		return

	var leader_id: String  = String(g.get("leader_id",  ""))
	var base_center: Vector2 = base.get("center_world_pos", Vector2.ZERO) as Vector2
	var base_id: String    = String(base.get("id", ""))

	RaidQueue.enqueue_raid(faction_id, group_id, leader_id, base_center, base_id)
	BanditGroupMemory.push_social_cooldown(group_id, maxf(12.0, effective_raid_cd * 0.15))
	BanditGroupMemory.update_intent(group_id, "raiding")
	BanditGroupMemory.record_interest(group_id, base_center, "base_detected")
	Debug.log("bandit_intel", "[BGI] raid enqueued group=%s leader=%s base=%s" % [
		group_id, leader_id, base_id])
