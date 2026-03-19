extends NpcWorldBehavior
class_name BanditWorldBehavior

# ── BanditWorldBehavior ──────────────────────────────────────────────────────
# Bandit-specific extension of NpcWorldBehavior.
# Adds role-based cargo capacity, loot pickup, resource watching,
# and group-intent reactions.
#
# Role behaviours:
#   scavenger — wide patrol; claims & reports resources to group memory;
#               avoids re-visiting the same resource for 45 s; yields to claims.
#   leader    — less static; inspects resources reported by scavengers;
#               proactive territory roam every 18-40 s.
#   bodyguard — follows leader with per-instance jitter offset (not single-file);
#               auto-escorts leader when it moves > 120 px from home.

const _PATROL_RADIUS_BY_ROLE: Dictionary = {
	"leader":    160.0,
	"bodyguard": 560.0,
	"scavenger": 2600.0,
}

const _SPEED_BY_ROLE: Dictionary = {
	"leader":    46.0,
	"bodyguard": 56.0,
	"scavenger": 60.0,
}

# Safety leash: how far from home before being forced RETURN_HOME
# Leader roam reaches up to 160*1.8 = 288 px — leash must be well above that
const _HOME_RETURN_DIST_BY_ROLE: Dictionary = {
	"leader":    520.0,
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
	"leader":    1.8,   # was 3.0 — less static; _try_leader_roam drives proactive movement
	"bodyguard": 1.5,
	"scavenger": 1.0,
}

# How much cargo each role can carry before heading home
const _CARGO_CAP_BY_ROLE: Dictionary = {
	"leader":    1,
	"bodyguard": 2,
	"scavenger": 4,
}

# ── Resource claim / avoidance (scavenger) ────────────────────────────────────
var _claimed_res_key: String = ""     # BanditGroupMemory claim key while in RESOURCE_WATCH
var _avoid_res_key: String   = ""     # recently-watched resource to skip for a cooldown
var _avoid_res_until: float  = 0.0   # RunClock.now() timestamp when cooldown expires

# ── Bodyguard follow jitter ───────────────────────────────────────────────────
var _follow_offset: Vector2  = Vector2.ZERO  # per-instance offset from leader position
var _jitter_timer: float     = 0.0           # time until next offset re-roll
var _raw_leader_pos: Vector2 = Vector2.ZERO  # leader pos before jitter (for escort check)

# ── Leader proactive roam ─────────────────────────────────────────────────────
var _leader_roam_timer: float = 0.0   # time until next proactive roam/resource check

var _last_intent: String = ""


# ---------------------------------------------------------------------------
# Setup — override to set role-based cargo capacity and role init
# ---------------------------------------------------------------------------

func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	cargo_capacity  = int(_CARGO_CAP_BY_ROLE.get(role, 3))
	_raw_leader_pos = home_pos
	if role == "bodyguard":
		var angle: float = _rng.randf_range(0.0, TAU)
		_follow_offset = Vector2(cos(angle), sin(angle)) * _rng.randf_range(64.0, 140.0)
		_jitter_timer  = _rng.randf_range(2.0, 5.0)
	if role == "leader":
		_leader_roam_timer = _rng.randf_range(8.0, 18.0)


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
	# ── 0. Bodyguard: jitter offset injected into ctx before base tick ─────
	if role == "bodyguard":
		_jitter_timer -= delta
		if _jitter_timer <= 0.0:
			_jitter_timer  = _rng.randf_range(2.0, 5.0)
			var angle: float = _rng.randf_range(0.0, TAU)
			_follow_offset = Vector2(cos(angle), sin(angle)) * _rng.randf_range(64.0, 140.0)
		if ctx.has("leader_pos"):
			_raw_leader_pos   = ctx["leader_pos"] as Vector2
			ctx["leader_pos"] = _raw_leader_pos + _follow_offset
		else:
			_raw_leader_pos = home_pos

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

	# Track state before base tick to detect RESOURCE_WATCH exit
	var prev_state: State = state

	# ── 3. Base state machine (movement, arrive checks, etc.) ────────────
	super.tick(delta, ctx)

	# Release resource claim when leaving RESOURCE_WATCH
	if prev_state == State.RESOURCE_WATCH and state != State.RESOURCE_WATCH:
		_on_leave_resource_watch()

	# ── 3b. Bodyguard band escort: push away when too close to raw leader ─
	if role == "bodyguard" and state == State.FOLLOW_LEADER:
		var node_pos: Vector2 = ctx.get("node_pos", home_pos)
		var to_leader: Vector2 = node_pos - _raw_leader_pos
		var d_leader: float = to_leader.length()
		var push_dist: float = maxf(_follow_offset.length() * 0.45, 35.0)
		if d_leader < push_dist:
			var push_dir: Vector2 = to_leader.normalized() if d_leader > 0.5 \
					else Vector2(cos(_rng.randf_range(0.0, TAU)), sin(_rng.randf_range(0.0, TAU)))
			_desired_velocity = push_dir * _get_speed() * 0.5

	# ── 4. From quiescent states, try to find useful work ────────────────
	if state == State.IDLE_AT_HOME or state == State.PATROL:
		_try_find_work(ctx)

	# ── 5. Leader: proactive roam toward reported resources / territory ───
	if role == "leader" and (state == State.IDLE_AT_HOME or state == State.PATROL):
		_leader_roam_timer -= delta
		if _leader_roam_timer <= 0.0:
			_try_leader_roam()


# ---------------------------------------------------------------------------
# Work seeking — loot > resource watch (role-gated)
# ---------------------------------------------------------------------------

func _try_find_work(ctx: Dictionary) -> void:
	var node_pos: Vector2 = ctx.get("node_pos", home_pos)

	# Bodyguard: escort leader when they've moved well away from home
	if role == "bodyguard":
		if _raw_leader_pos.distance_squared_to(home_pos) > 72.0 * 72.0:
			state        = State.FOLLOW_LEADER
			_state_timer = 0.0
			return

	# Prefer loot if allowed and not full
	if _can_loot() and not is_cargo_full():
		var drops: Array = ctx.get("nearby_drops_info", [])
		var best_id: int = _pick_nearest_drop_id(drops, node_pos)
		if best_id != 0:
			enter_loot_approach(best_id)
			return

	# Resource watch as fallback for eligible roles
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
# Resource claim / report (scavenger)
# ---------------------------------------------------------------------------

## Override: claim the resource in group memory and report it before entering orbit.
func enter_resource_watch(resource_pos: Vector2) -> void:
	var key: String  = _res_key(resource_pos)
	_claimed_res_key = key
	_avoid_res_key   = key
	_avoid_res_until = RunClock.now() + 45.0
	if group_id != "":
		BanditGroupMemory.claim_resource(group_id, key, member_id)
		BanditGroupMemory.report_resource(group_id, resource_pos, member_id)
	super.enter_resource_watch(resource_pos)


## Called when leaving RESOURCE_WATCH (detected via state transition in tick).
func _on_leave_resource_watch() -> void:
	if group_id != "" and _claimed_res_key != "":
		BanditGroupMemory.release_resource_by_member(group_id, member_id)
	_claimed_res_key = ""


# ---------------------------------------------------------------------------
# Leader proactive roam
# ---------------------------------------------------------------------------

func _try_leader_roam() -> void:
	_leader_roam_timer = _rng.randf_range(18.0, 40.0)
	# Prioritise resources reported by scavengers
	if group_id != "":
		var reported: Array = BanditGroupMemory.get_reported_resources(group_id)
		if not reported.is_empty():
			var pick: Dictionary = reported[_rng.randi() % reported.size()] as Dictionary
			var pos_raw          = pick.get("pos", null)
			if not (pos_raw is Vector2):
				return  # datos corruptos de sesión anterior — ignorar
			var rpos: Vector2 = pos_raw
			if rpos != Vector2.ZERO and rpos.distance_squared_to(home_pos) > 64.0 * 64.0:
				_move_target = rpos
				state        = State.APPROACH_INTEREST
				_state_timer = 0.0
				_invalidate_npc_path()
				Debug.log("bandit_ai", "[BWB] leader→resource %s gid=%s" % [str(rpos), group_id])
				return
	# No reported resources — broad territory sweep
	var radius: float = float(_PATROL_RADIUS_BY_ROLE.get("leader", 160.0)) * 1.8
	var angle: float  = _rng.randf_range(0.0, TAU)
	_move_target = home_pos + Vector2(cos(angle), sin(angle)) * _rng.randf_range(80.0, radius)
	state        = State.PATROL
	_state_timer = 0.0
	_invalidate_npc_path()


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


## Picks nearest resource, skipping claimed-by-other and recently-visited.
func _pick_nearest_res_pos(res_info: Array, node_pos: Vector2) -> Vector2:
	var best_pos: Vector2 = Vector2.ZERO
	var best_dsq: float   = INF
	var now: float        = RunClock.now()
	for r in res_info:
		var info: Dictionary = r as Dictionary
		var pos: Vector2     = info.get("pos", Vector2.ZERO)
		if pos == Vector2.ZERO:
			continue
		var key: String = _res_key(pos)
		# Skip if in avoid-cooldown for this resource
		if key == _avoid_res_key and now < _avoid_res_until:
			continue
		# Skip if another group member has claimed it
		if group_id != "" and BanditGroupMemory.is_resource_claimed_by_other(group_id, key, member_id):
			continue
		var dsq: float = node_pos.distance_squared_to(pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best_pos = pos
	return best_pos


## Stable 32 px grid key for a world position.
static func _res_key(pos: Vector2) -> String:
	return "%d_%d" % [int(pos.x / 32.0), int(pos.y / 32.0)]


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
			match role:
				"leader", "bodyguard":
					var g: Dictionary = BanditGroupMemory.get_group(group_id)
					var interest_pos: Vector2 = g.get("last_interest_pos", home_pos)
					if interest_pos.distance_squared_to(home_pos) > 1.0:
						enter_extort_approach(interest_pos)
				_:
					pass  # scavengers keep their own work

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
			if state == State.APPROACH_INTEREST or state == State.FOLLOW_LEADER \
					or state == State.EXTORT_APPROACH:
				_enter_return_home()


# ---------------------------------------------------------------------------
# Serialization — adds role-state fields to base class export / import
# ---------------------------------------------------------------------------

func export_state() -> Dictionary:
	var d: Dictionary = super.export_state()
	d["wb_last_intent"]   = _last_intent
	d["wb_claimed_key"]   = _claimed_res_key
	d["wb_avoid_key"]     = _avoid_res_key
	d["wb_avoid_until"]   = _avoid_res_until
	d["wb_follow_offset"] = _follow_offset
	d["wb_leader_roam_t"] = _leader_roam_timer
	return d

func import_state(data: Dictionary) -> void:
	super.import_state(data)
	_last_intent       = String(data.get("wb_last_intent",   ""))
	_claimed_res_key   = String(data.get("wb_claimed_key",   ""))
	_avoid_res_key     = String(data.get("wb_avoid_key",     ""))
	_avoid_res_until   = float(data.get("wb_avoid_until",    0.0))
	var fo             = data.get("wb_follow_offset", Vector2.ZERO)
	_follow_offset     = fo if fo is Vector2 else Vector2.ZERO
	_leader_roam_timer = float(data.get("wb_leader_roam_t",  0.0))
