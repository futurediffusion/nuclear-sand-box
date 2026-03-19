extends RefCounted
class_name BanditGroupIntel

# ── BanditGroupIntel ─────────────────────────────────────────────────────────
# Group-level intelligence scanner. Runs once every SCAN_INTERVAL seconds and
# checks SettlementIntel for player activity near each bandit group's home.
#
# Responsibilities:
#   • Compute an "opportunity score" per group from nearby markers + detected bases.
#   • Update BanditGroupMemory: intent, last_interest_pos/kind, scout_npc_id.
#   • Enqueue a single ExtortionQueue intent per group when threshold is crossed.
#
# Anti-spam guarantees:
#   • One scan per group per SCAN_INTERVAL (8 s).
#   • Only fires if the group has a live leader node.
#   • Extortion: skipped if group already has pending intent OR cooldown not elapsed.
#   • Scout selection: one specific NPC is designated per group (not all at once).
#
# Does NOT modify NPC behavior states directly — intent changes are picked up by
# BanditWorldBehavior.tick() on the next 0.5 s behavior tick.

const SCAN_INTERVAL: float     = 8.0    # s between full scans
const TERRITORY_RADIUS: float  = 384.0  # px around group home_world_pos
const EXTORT_COOLDOWN: float   = 90.0   # RunClock seconds between extortion intents

# ── Scoring weights ───────────────────────────────────────────────────────────
const W_BASE_DETECTED: float  = 15.0
const W_WORKBENCH: float      = 10.0
const W_STRUCTURE: float      =  6.0
const W_MINE: float           =  3.0
const W_CHOP: float           =  2.0

# ── Intent thresholds (cumulative score) ─────────────────────────────────────
const T_ALERTED: float  =  3.0   # → "alerted",  send 1 scout
const T_HUNTING: float  =  8.0   # → "hunting",  leader + bodyguards advance
const T_EXTORT: float   = 12.0   # → "extorting" + enqueue ExtortionQueue intent

var _get_markers_near: Callable
var _get_bases_near: Callable
var _npc_simulator: NpcSimulator
var _scan_timer: float = 0.0


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
	if _scan_timer < SCAN_INTERVAL:
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
	if _npc_simulator == null or _npc_simulator._get_active_enemy_node(leader_id) == null:
		return

	var home_pos: Vector2 = g.get("home_world_pos", Vector2.ZERO)

	# Query SettlementIntel
	var markers: Array[Dictionary] = []
	var bases: Array[Dictionary]   = []
	if _get_markers_near.is_valid():
		markers = _get_markers_near.call(home_pos, TERRITORY_RADIUS)
	if _get_bases_near.is_valid():
		bases = _get_bases_near.call(home_pos, TERRITORY_RADIUS)

	var score: float = _score_activity(markers, bases)

	# Determine new intent
	var new_intent: String
	if score >= T_HUNTING:
		new_intent = "hunting"
	elif score >= T_ALERTED:
		new_intent = "alerted"
	else:
		new_intent = "idle"

	BanditGroupMemory.update_intent(group_id, new_intent)

	if new_intent == "idle":
		BanditGroupMemory.set_scout(group_id, "")
		return

	# Pick and record best interest point
	var interest = _pick_best_interest(markers, bases)
	if interest != null:
		BanditGroupMemory.record_interest(group_id, interest.pos, interest.kind)
		Debug.log("bandit_intel", "[BGI] group=%s score=%.1f intent=%s kind=%s pos=%s" % [
			group_id, score, new_intent, interest.kind, str(interest.pos)])

	# For "alerted": designate exactly one scout
	if new_intent == "alerted":
		var scout: String = _pick_scout(group_id, g)
		BanditGroupMemory.set_scout(group_id, scout)
	else:
		# hunting/extorting: clear scout (leader + bodyguards handle it)
		BanditGroupMemory.set_scout(group_id, "")

	# Extortion intent if threshold crossed
	if score >= T_EXTORT and interest != null:
		_maybe_enqueue_extortion(group_id, g, interest, score)


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
		var node = _npc_simulator._get_active_enemy_node(id)
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
		interest: Dictionary, score: float) -> void:
	# Guard 1: already queued for this group
	if ExtortionQueue.has_pending_for_group(group_id):
		Debug.log("bandit_intel", "[BGI] extortion pending — skip group=%s" % group_id)
		return
	# Guard 2: cooldown since last request
	var last_time: float = float(g.get("last_extortion_request_time", 0.0))
	var elapsed: float   = RunClock.now() - last_time
	if elapsed < EXTORT_COOLDOWN:
		Debug.log("bandit_intel", "[BGI] extortion cooldown %.0fs left group=%s" % [
			EXTORT_COOLDOWN - elapsed, group_id])
		return

	var leader_id:  String = String(g.get("leader_id",  ""))
	var faction_id: String = String(g.get("faction_id", "bandits"))
	# Severity scales from 0.1 at T_EXTORT to 1.0 at T_EXTORT + W_BASE_DETECTED*2
	var severity: float = clampf((score - T_EXTORT) / (W_BASE_DETECTED * 2.0), 0.1, 1.0)

	ExtortionQueue.enqueue_intent(
		"player",
		faction_id,
		group_id,
		leader_id,
		interest.kind,
		interest.pos,
		severity
	)
	BanditGroupMemory.update_intent(group_id, "extorting")
	Debug.log("bandit_intel", "[BGI] extortion enqueued group=%s leader=%s kind=%s sev=%.2f" % [
		group_id, leader_id, interest.kind, severity])
