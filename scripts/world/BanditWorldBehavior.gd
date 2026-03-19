extends NpcWorldBehavior
class_name BanditWorldBehavior

# ── BanditWorldBehavior ──────────────────────────────────────────────────────
# Bandit-specific extension of NpcWorldBehavior.
# Adds role-based cargo capacity, loot pickup, resource watching,
# and group-intent reactions.
#
# Carry preference: NPCs prefer to carry cargo to their base (RETURN_HOME)
# rather than consume drops individually. Inventory is not involved.
#
# ctx keys consumed here (in addition to base):
#   "nearby_drops_info":  Array[Dictionary]  — [{id:int, pos:Vector2, amount:int}]
#   "nearby_res_info":    Array[Dictionary]  — [{pos:Vector2}]

const _PATROL_RADIUS_BY_ROLE: Dictionary = {
	"leader":    160.0,   # keeps camp identity, but no longer statues at the fire
	"bodyguard": 560.0,   # visible perimeter sweeps around the leader / camp
	"scavenger": 2600.0,  # broad roaming across much of the 64x64 world (~4096px)
}

const _SPEED_BY_ROLE: Dictionary = {
	"leader":    46.0,
	"bodyguard": 56.0,
	"scavenger": 60.0,
}

# Safety leash: how far from home before being forced RETURN_HOME
const _HOME_RETURN_DIST_BY_ROLE: Dictionary = {
	"leader":    280.0,
	"bodyguard": 760.0,
	"scavenger": 3200.0,
}

# Max time in PATROL/APPROACH_INTEREST before giving up and going idle
const _MAX_PATROL_TIME_BY_ROLE: Dictionary = {
	"leader":    22.0,
	"bodyguard": 44.0,
	"scavenger": 150.0,
}

const _IDLE_BIAS_BY_ROLE: Dictionary = {
	"leader":    3.0,
	"bodyguard": 1.5,
	"scavenger": 1.0,
}

# How much cargo each role can carry before heading home
const _CARGO_CAP_BY_ROLE: Dictionary = {
	"leader":    1,   # leaders carry little — they lead, not haul
	"bodyguard": 2,
	"scavenger": 4,
}

var _last_intent: String = ""


# ---------------------------------------------------------------------------
# Setup — override to set role-based cargo capacity
# ---------------------------------------------------------------------------

func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	cargo_capacity = int(_CARGO_CAP_BY_ROLE.get(role, 3))


# ---------------------------------------------------------------------------
# Virtual overrides
# ---------------------------------------------------------------------------

func _get_patrol_radius() -> float:
	return float(_PATROL_RADIUS_BY_ROLE.get(role, 64.0))

func _get_speed() -> float:
	return float(_SPEED_BY_ROLE.get(role, 55.0))

func _get_home_return_dist() -> float:
	return float(_HOME_RETURN_DIST_BY_ROLE.get(role, 192.0))

func _get_max_patrol_time() -> float:
	return float(_MAX_PATROL_TIME_BY_ROLE.get(role, 14.0))

func _enter_idle_at_home() -> void:
	super._enter_idle_at_home()
	_idle_timer *= float(_IDLE_BIAS_BY_ROLE.get(role, 1.0))


# ---------------------------------------------------------------------------
# tick
# ---------------------------------------------------------------------------

func tick(delta: float, ctx: Dictionary) -> void:
	# ── 1. React to group intent changes ──────────────────────────────────
	if group_id != "":
		var g: Dictionary = BanditGroupMemory.get_group(group_id)
		var intent: String = String(g.get("current_group_intent", "idle"))
		if intent != _last_intent:
			_last_intent = intent
			_on_group_intent_changed(intent, ctx)

	# ── 2. Cargo full → return home (highest priority, interrupts any state) ──
	if is_cargo_full() and state != State.RETURN_HOME and state != State.HOLD_POSITION:
		Debug.log("bandit_ai", "[BWB] cargo full → RETURN_HOME member=%s cargo=%d/%d" % [
			member_id, cargo_count, cargo_capacity])
		_enter_return_home()

	# ── 3. Base state machine (movement, arrive checks, etc.) ────────────
	super.tick(delta, ctx)

	# ── 4. From quiescent states, try to find useful work ────────────────
	if state == State.IDLE_AT_HOME or state == State.PATROL:
		_try_find_work(ctx)


# ---------------------------------------------------------------------------
# Work seeking — loot > resource watch (role-gated)
# ---------------------------------------------------------------------------

func _try_find_work(ctx: Dictionary) -> void:
	var node_pos: Vector2 = ctx.get("node_pos", home_pos)

	# Prefer loot if allowed and not full
	if _can_loot() and not is_cargo_full():
		var drops: Array = ctx.get("nearby_drops_info", [])
		var best_id: int = _pick_nearest_drop_id(drops, node_pos)
		if best_id != 0:
			enter_loot_approach(best_id)
			return

	# Resource watch as fallback activity for eligible roles
	if _can_watch_resources() and not is_cargo_full():
		var resources: Array = ctx.get("nearby_res_info", [])
		var res_pos: Vector2 = _pick_nearest_res_pos(resources, node_pos)
		if res_pos != Vector2.ZERO:
			enter_resource_watch(res_pos)
			return


# ---------------------------------------------------------------------------
# Role gates
# ---------------------------------------------------------------------------

func _can_loot() -> bool:
	return role == "scavenger" or role == "bodyguard"

func _can_watch_resources() -> bool:
	return role == "scavenger"


# ---------------------------------------------------------------------------
# Pick helpers — work on plain data (no node access)
# ---------------------------------------------------------------------------

func _pick_nearest_drop_id(drops_info: Array, node_pos: Vector2) -> int:
	var best_id: int    = 0
	var best_dsq: float = INF
	for d in drops_info:
		var info: Dictionary = d as Dictionary
		var pos: Vector2     = info.get("pos", Vector2.ZERO)
		var dsq: float       = node_pos.distance_squared_to(pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best_id  = int(info.get("id", 0))
	return best_id


func _pick_nearest_res_pos(res_info: Array, node_pos: Vector2) -> Vector2:
	var best_pos: Vector2 = Vector2.ZERO
	var best_dsq: float   = INF
	for r in res_info:
		var info: Dictionary = r as Dictionary
		var pos: Vector2     = info.get("pos", Vector2.ZERO)
		if pos == Vector2.ZERO:
			continue
		var dsq: float = node_pos.distance_squared_to(pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best_pos = pos
	return best_pos


# ---------------------------------------------------------------------------
# Group intent reaction
# ---------------------------------------------------------------------------

func _on_group_intent_changed(intent: String, ctx: Dictionary) -> void:
	Debug.log("bandit_ai", "[BWB] intent changed member=%s role=%s group=%s %s→%s" % [
		member_id, role, group_id, _last_intent, intent])

	match intent:
		"hunting":
			match role:
				"leader":
					var g: Dictionary = BanditGroupMemory.get_group(group_id)
					var interest_pos: Vector2 = g.get("last_interest_pos", home_pos)
					if interest_pos.distance_squared_to(home_pos) > 1.0:
						_move_target = interest_pos
						state        = State.APPROACH_INTEREST
						_state_timer = 0.0
				"bodyguard":
					state        = State.FOLLOW_LEADER
					_state_timer = 0.0
				_:
					pass  # scavengers keep their own work

		"extorting":
			if role == "leader":
				var g: Dictionary = BanditGroupMemory.get_group(group_id)
				var interest_pos: Vector2 = g.get("last_interest_pos", home_pos)
				if interest_pos.distance_squared_to(home_pos) > 1.0:
					_move_target = interest_pos
					state        = State.APPROACH_INTEREST
					_state_timer = 0.0

		"alerted":
			# One designated scout investigates; others hold their current state
			if group_id != "" and member_id != "":
				var scout_id: String = BanditGroupMemory.get_scout(group_id)
				if scout_id == member_id:
					var g: Dictionary = BanditGroupMemory.get_group(group_id)
					var interest_pos: Vector2 = g.get("last_interest_pos", home_pos)
					if interest_pos.distance_squared_to(home_pos) > 1.0:
						_move_target = interest_pos
						state        = State.APPROACH_INTEREST
						_state_timer = 0.0
						Debug.log("bandit_ai", "[BWB] scout dispatched member=%s → %s" % [
							member_id, str(interest_pos)])

		"idle":
			# Wind down any active group pursuit when returning to idle
			if state == State.APPROACH_INTEREST or state == State.FOLLOW_LEADER:
				_enter_return_home()


# ---------------------------------------------------------------------------
# Serialization — adds _last_intent to base class export / import
# ---------------------------------------------------------------------------

func export_state() -> Dictionary:
	var d: Dictionary = super.export_state()
	d["wb_last_intent"] = _last_intent
	return d

func import_state(data: Dictionary) -> void:
	super.import_state(data)
	_last_intent = String(data.get("wb_last_intent", ""))
