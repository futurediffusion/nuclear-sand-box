extends NpcWorldBehavior
class_name BanditWorldBehavior

# Responsibility boundary:
# BanditWorldBehavior reacts to group intent with locomotion/state changes only.
# It does not own extortion jobs, taunts, payment, UI/modal flow, or resolution.
#
# Bandit-specific extension of NpcWorldBehavior.
# Adds role-based cargo capacity, loot pickup, resource watching,
# and group-intent reactions.
#
# Role behaviours:
#   scavenger — wide patrol; claims & reports resources to group memory;
#               avoids re-visiting the same resource for 45 s; yields to claims.
#   leader    — two phases: "local" (near camp) then "exploring" (full map);
#               coordinates roaming guards by dispatching them on return.
#   bodyguard — HALF are "stay guards" (follow leader, current behaviour);
#               HALF are "roaming guards" (patrol full map, check in with
#               leader periodically, get dispatched to a new direction).

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
	"leader":    1.8,
	"bodyguard": 1.5,
	"scavenger": 1.0,
}

const _CARGO_CAP_BY_ROLE: Dictionary = {
	"leader":    1,
	"bodyguard": 2,
	"scavenger": 4,
}

# ── Roaming guard constants ────────────────────────────────────────────────────
# Roaming guards patrol the full 64×64-tile map (≈2048 px per axis at 32 px/tile).
const ROAMING_GUARD_PATROL_RADIUS: float = 2200.0   # max dispatch radius from leader
const ROAMING_GUARD_PATROL_TIME: float   = 55.0     # seconds on wide patrol before returning
const ROAMING_GUARD_WAIT_TIME: float     = 7.0      # seconds near leader before next dispatch

# ── Leader exploration phase constants ────────────────────────────────────────
const LEADER_LOCAL_DURATION: float    = 40.0    # seconds near camp before switching to explore
const LEADER_EXPLORE_RADIUS: float    = 2000.0  # roam radius during explore phase
const LEADER_EXPLORE_RETURN: float    = 3500.0  # home-leash while exploring

# ── Post-deposit: leave the barrel area immediately ────────────────────────────
const POST_DEPOSIT_WANDER_RADIUS: float = 420.0  # distance from home_pos to wander after deposit

# ── Barrel exclusion zone ─────────────────────────────────────────────────────
# No NPC may stand inside this radius of deposit_pos unless actively depositing
# (i.e. RETURN_HOME with cargo_count > 0).
const BARREL_EXCLUSION_RADIUS_SQ: float = 88.0 * 88.0
# Zona suave: NPCs en IDLE_AT_HOME dentro de este radio también se mueven.
# Evita que se amontonen cerca del barril entre viajes de depósito.
const BARREL_IDLE_SOFT_RADIUS_SQ: float = 160.0 * 160.0

# ── Resource claim / avoidance (scavenger) ────────────────────────────────────
var _claimed_res_key: String = ""
var _avoid_res_key: String   = ""
var _avoid_res_until: float  = 0.0

# ── Bodyguard follow jitter ───────────────────────────────────────────────────
var _follow_offset: Vector2  = Vector2.ZERO
var _jitter_timer: float     = 0.0
var _raw_leader_pos: Vector2 = Vector2.ZERO

# ── Leader proactive roam ─────────────────────────────────────────────────────
var _leader_roam_timer: float = 0.0

# ── Roaming guard state ───────────────────────────────────────────────────────
# Determined once in setup() by member_id hash — stable across sessions.
var _is_roaming_guard: bool       = false
# "patrolling" | "returning" | "waiting"
var _roaming_phase: String        = "patrolling"
var _roaming_timer: float         = 0.0
# Leader position at last dispatch — roaming target is relative to this.
var _roaming_dispatch_pos: Vector2 = Vector2.ZERO

# ── Leader exploration phase ──────────────────────────────────────────────────
# "local" | "exploring"
var _leader_explore_phase: String = "local"
var _leader_phase_timer: float    = 0.0

# ── Post-deposit flag ─────────────────────────────────────────────────────────
var _pending_leave_home: bool = false

var _last_intent: String = ""
var _assault_suppress_log_until: float = 0.0

# ── Oportunistic wall assault ─────────────────────────────────────────────────
# Cooldown por NPC para que no spamee el ataque al mismo muro.
var _wall_assault_cooldown_until: float = 0.0
# Cuando true: leash desactivado y _move_target protegido (en camino a destruir estructura)
var _in_assault: bool = false

# ── Property sabotage (workbench / storage) ───────────────────────────────────
# Cooldown por NPC para ataques oportunistas a placeables del jugador (nivel 7+).
var _property_sabotage_cooldown_until: float = 0.0

# ── Reconocimiento del jugador ────────────────────────────────────────────────
# Cooldown para que este NPC no muestre burbujas de reconocimiento muy seguido.
var recognition_bubble_until: float = 0.0

# ── Diálogo ambiental ─────────────────────────────────────────────────────────
# Cooldown para frases de mundo mientras el NPC está ocioso o patrullando.
var idle_chat_until: float = 0.0

# ── Hostility profile ─────────────────────────────────────────────────────
# Actualizado al inicio de cada tick. No persiste: se recalcula desde el manager.
var faction_id: String              = "bandits"
var _profile: FactionBehaviorProfile = null


# ---------------------------------------------------------------------------
# Setup — override to set role-based cargo capacity and role init
# ---------------------------------------------------------------------------

func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	cargo_capacity  = int(_CARGO_CAP_BY_ROLE.get(role, 3))
	_raw_leader_pos = home_pos
	faction_id      = String(cfg.get("faction_id", "bandits"))
	if role == "bodyguard":
		var angle: float = _rng.randf_range(0.0, TAU)
		_follow_offset = Vector2(cos(angle), sin(angle)) * _rng.randf_range(64.0, 140.0)
		_jitter_timer  = _rng.randf_range(2.0, 5.0)
		# Deterministic split: even hash → roaming guard, odd hash → stay guard
		_is_roaming_guard = (absi(hash(member_id)) % 2 == 0)
		if _is_roaming_guard:
			_roaming_dispatch_pos = home_pos
			_roaming_phase        = "patrolling"
			# Stagger initial dispatch so not all roamers leave at once
			_roaming_timer = _rng.randf_range(3.0, 18.0)
	if role == "leader":
		_leader_roam_timer  = _rng.randf_range(8.0, 18.0)
		_leader_phase_timer = _rng.randf_range(15.0, LEADER_LOCAL_DURATION)
		_leader_explore_phase = "local"


# ---------------------------------------------------------------------------
# Virtual overrides
# ---------------------------------------------------------------------------

func _get_patrol_radius() -> float:
	if role == "leader" and _leader_explore_phase == "exploring":
		return LEADER_EXPLORE_RADIUS
	return float(_PATROL_RADIUS_BY_ROLE.get(role, 64.0))

func _get_speed() -> float:
	var base: float = float(_SPEED_BY_ROLE.get(role, 55.0))
	if _profile == null:
		return base
	# effective_intensity() devuelve 0.0 en nivel 0, hasta ~12 en nivel 10 con heat alto.
	# Escalamos velocidad hasta un +25% máximo para no romper navegación.
	var intensity_boost: float = clampf(_profile.effective_intensity() / 40.0, 0.0, 0.25)
	return base * (1.0 + intensity_boost)

func _get_home_return_dist() -> float:
	# Durante asalto directo: sin leash — el NPC debe llegar al target sin importar distancia
	if _in_assault:
		return 9999.0
	# Roaming guards handle their own return via timer — disable distance leash
	if role == "bodyguard" and _is_roaming_guard:
		return 9999.0
	# Leader has wider leash while exploring
	if role == "leader" and _leader_explore_phase == "exploring":
		return LEADER_EXPLORE_RETURN
	return float(_HOME_RETURN_DIST_BY_ROLE.get(role, 192.0))

func _get_max_patrol_time() -> float:
	# Roaming guards and exploring leader need longer time to reach distant targets
	if role == "bodyguard" and _is_roaming_guard:
		return 120.0
	if role == "leader" and _leader_explore_phase == "exploring":
		return 100.0
	return float(_MAX_PATROL_TIME_BY_ROLE.get(role, 14.0))

func _enter_idle_at_home() -> void:
	super._enter_idle_at_home()
	_idle_timer *= float(_IDLE_BIAS_BY_ROLE.get(role, 1.0))


# ---------------------------------------------------------------------------
# tick
# ---------------------------------------------------------------------------

func tick(delta: float, ctx: Dictionary) -> void:
	# ── Hostility profile (recalculado cada tick, barato) ─────────────────
	_profile = FactionHostilityManager.get_behavior_profile(faction_id)

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

	# ── 0b. Post-deposit: leave home immediately ───────────────────────────
	if _pending_leave_home:
		_pending_leave_home = false
		if not _try_reengage_structure_assault("post_deposit"):
			_enter_patrol_away_from_home()

	# ── 0c. Roaming guard phase management ────────────────────────────────
	if role == "bodyguard" and _is_roaming_guard:
		_tick_roaming_guard_phase(delta, ctx)

	# ── 0d. Leader exploration phase ──────────────────────────────────────
	if role == "leader":
		_tick_leader_phase(delta)

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

	# Limpiar modo asalto cuando el NPC llega/abandona APPROACH_INTEREST
	if _in_assault and state != State.APPROACH_INTEREST:
		_in_assault = false

	# ── 3b. Barrel exclusion zone ─────────────────────────────────────────
	# Hard exclusion: cualquier NPC que no esté depositando activamente
	# y esté dentro de 88 px del barril → patrol inmediato.
	# Soft exclusion: NPCs en IDLE_AT_HOME dentro de 160 px también se van
	# para evitar que se amontonen mientras esperan su turno.
	if deposit_pos != Vector2.ZERO:
		var node_pos_ex: Vector2 = ctx.get("node_pos", home_pos)
		var is_depositing: bool  = state == State.RETURN_HOME and cargo_count > 0
		if not is_depositing:
			var dist_to_barrel_sq: float = node_pos_ex.distance_squared_to(deposit_pos)
			if dist_to_barrel_sq < BARREL_EXCLUSION_RADIUS_SQ:
				_enter_patrol_away_from_home()
			elif state == State.IDLE_AT_HOME \
					and dist_to_barrel_sq < BARREL_IDLE_SOFT_RADIUS_SQ:
				_enter_patrol_away_from_home()

	# ── 3c. Stay-bodyguard band escort: push away when too close to raw leader ─
	if role == "bodyguard" and not _is_roaming_guard and state == State.FOLLOW_LEADER:
		var node_pos: Vector2 = ctx.get("node_pos", home_pos)
		var to_leader: Vector2 = node_pos - _raw_leader_pos
		var d_leader: float = to_leader.length()
		var push_dist: float = maxf(_follow_offset.length() * 0.45, 35.0)
		if d_leader < push_dist:
			var push_dir: Vector2 = to_leader.normalized() if d_leader > 0.5 \
					else Vector2(cos(_rng.randf_range(0.0, TAU)), sin(_rng.randf_range(0.0, TAU)))
			_desired_velocity = push_dir * _get_speed() * 0.5

	# ── 4a. Drops visibles = prioridad máxima para TODOS los roles ───────
	# Durante asalto de estructuras normalmente suprimimos "loot genérico" para
	# mantener foco en el objetivo, PERO si ya hay drop pegado al NPC debemos
	# permitir pickup inmediato para evitar loops de "me quedo encima del ítem".
	if not is_cargo_full():
		var suppress_generic_pickup: bool = _should_suppress_generic_drop_pickup(ctx)
		if suppress_generic_pickup:
			_log_assault_pickup_suppressed("visible_drop")
		else:
			_try_grab_visible_drop(ctx)

	# ── 4b. From quiescent states, try to find other useful work ─────────
	if pending_collect_id == 0 and (state == State.IDLE_AT_HOME or state == State.PATROL):
		if _should_suppress_generic_drop_pickup(ctx):
			_log_assault_pickup_suppressed("find_work")
		else:
			_try_find_work(ctx)

	# ── 4c. Oportunistic wall assault (nivel 6+, no en raid) ─────────────
	# Enemigos cercanos a la base del jugador comienzan a atacar muros de forma
	# progresiva a partir de nivel 6. Sin raids — comportamiento individual.
	if state == State.IDLE_AT_HOME or state == State.PATROL:
		_try_opportunistic_wall_assault(ctx)
		_try_property_sabotage(ctx)

	# ── 5. Leader: proactive roam toward reported resources / territory ───
	if role == "leader" and (state == State.IDLE_AT_HOME or state == State.PATROL):
		_leader_roam_timer -= delta
		if _leader_roam_timer <= 0.0:
			_try_leader_roam()


# ---------------------------------------------------------------------------
# Roaming guard phase tick
# ---------------------------------------------------------------------------

func _tick_roaming_guard_phase(delta: float, ctx: Dictionary) -> void:
	var node_pos: Vector2   = ctx.get("node_pos",   home_pos)
	var leader_pos: Vector2 = ctx.get("leader_pos", home_pos)

	match _roaming_phase:
		"patrolling":
			_roaming_timer -= delta
			if _roaming_timer <= 0.0:
				# Time to check in with leader
				_roaming_phase   = "returning"
				_move_target     = leader_pos
				state            = State.APPROACH_INTEREST
				_state_timer     = 0.0
				_invalidate_npc_path()
				Debug.log("bandit_ai", "[BWB] roaming_guard→returning member=%s" % member_id)

		"returning":
			# Keep the approach target updated as the leader moves
			# (pero no interferir si estamos en un asalto directo a estructura)
			if state == State.APPROACH_INTEREST and not _in_assault:
				_move_target = leader_pos
			# Arrival: either super.tick() already transitioned us to IDLE or we're close
			var near_leader := node_pos.distance_squared_to(leader_pos) < 110.0 * 110.0
			if state == State.IDLE_AT_HOME or near_leader:
				_roaming_phase   = "waiting"
				_roaming_timer   = ROAMING_GUARD_WAIT_TIME
				state            = State.HOLD_POSITION
				Debug.log("bandit_ai", "[BWB] roaming_guard→waiting member=%s" % member_id)

		"waiting":
			_roaming_timer -= delta
			if _roaming_timer <= 0.0:
				# Leader dispatches the guard to a new area
				_roaming_dispatch_pos = leader_pos
				_roaming_phase        = "patrolling"
				_roaming_timer        = _rng.randf_range(
					ROAMING_GUARD_PATROL_TIME * 0.6, ROAMING_GUARD_PATROL_TIME)
				_enter_wide_patrol()
				Debug.log("bandit_ai", "[BWB] roaming_guard dispatched member=%s from=%s" % [
					member_id, str(leader_pos)])


# ---------------------------------------------------------------------------
# Leader exploration phase tick
# ---------------------------------------------------------------------------

func _tick_leader_phase(delta: float) -> void:
	_leader_phase_timer -= delta
	if _leader_phase_timer <= 0.0:
		if _leader_explore_phase == "local":
			_leader_explore_phase = "exploring"
			_leader_phase_timer   = _rng.randf_range(80.0, 160.0)
			Debug.log("bandit_ai", "[BWB] leader→exploring phase member=%s" % member_id)
		else:
			_leader_explore_phase = "local"
			_leader_phase_timer   = _rng.randf_range(25.0, LEADER_LOCAL_DURATION)
			# Return home when switching back to local phase
			if state != State.RETURN_HOME and state != State.IDLE_AT_HOME:
				_enter_return_home()
			Debug.log("bandit_ai", "[BWB] leader→local phase member=%s" % member_id)


# ---------------------------------------------------------------------------
# Wide patrol helpers
# ---------------------------------------------------------------------------

## Override: avoid picking patrol targets near the barrel (deposit_pos).
## NPCs should only approach the barrel when they have cargo to deposit.
func _enter_patrol(ctx: Dictionary) -> void:
	const BARREL_AVOID_RADIUS_SQ: float = 140.0 * 140.0
	var radius: float = _get_patrol_radius()
	# Sesgar el ángulo inicial alejándose del barril para reducir candidatos malos.
	var base_angle: float = _rng.randf_range(0.0, TAU)
	if deposit_pos != Vector2.ZERO:
		var away: Vector2 = home_pos - deposit_pos
		if away.length_squared() > 1.0:
			base_angle = atan2(away.y, away.x) + _rng.randf_range(-PI * 0.5, PI * 0.5)
	var angle: float = base_angle
	var dist: float  = _rng.randf_range(radius * 0.3, radius)
	var candidate: Vector2 = home_pos + Vector2(cos(angle), sin(angle)) * dist
	# Si el barril está asignado, reintentar hasta 6 veces para salir de su área.
	if deposit_pos != Vector2.ZERO:
		for _i in 6:
			if candidate.distance_squared_to(deposit_pos) > BARREL_AVOID_RADIUS_SQ:
				break
			angle     = _rng.randf_range(0.0, TAU)
			dist      = _rng.randf_range(radius * 0.3, radius)
			candidate = home_pos + Vector2(cos(angle), sin(angle)) * dist
	_move_target  = candidate
	state         = State.PATROL
	_state_timer  = 0.0
	_invalidate_npc_path()


## Roaming guard wide patrol — target is relative to dispatch position (leader pos).
func _enter_wide_patrol() -> void:
	var origin := _roaming_dispatch_pos if _roaming_dispatch_pos != Vector2.ZERO else home_pos
	var angle := _rng.randf_range(0.0, TAU)
	var dist  := _rng.randf_range(ROAMING_GUARD_PATROL_RADIUS * 0.3, ROAMING_GUARD_PATROL_RADIUS)
	_move_target = origin + Vector2(cos(angle), sin(angle)) * dist
	state        = State.PATROL
	_state_timer = 0.0
	_invalidate_npc_path()

## Forces the NPC to patrol away from the barrel area.
## Guarantees the target is outside BARREL_EXCLUSION_RADIUS_SQ.
func _enter_patrol_away_from_home() -> void:
	if role == "bodyguard" and _is_roaming_guard:
		_roaming_phase = "patrolling"
		_roaming_timer = _rng.randf_range(ROAMING_GUARD_PATROL_TIME * 0.5, ROAMING_GUARD_PATROL_TIME)
		_enter_wide_patrol()
		return
	# Pick a direction pointing away from the barrel center so the target
	# is guaranteed to land outside the exclusion zone.
	var avoid_center: Vector2 = deposit_pos if deposit_pos != Vector2.ZERO else home_pos
	var angle := _rng.randf_range(0.0, TAU)
	var dist  := _rng.randf_range(POST_DEPOSIT_WANDER_RADIUS * 0.6, POST_DEPOSIT_WANDER_RADIUS)
	var candidate := home_pos + Vector2(cos(angle), sin(angle)) * dist
	# Retry up to 5 times until the target is safely outside the exclusion zone
	for _i in 5:
		if candidate.distance_squared_to(avoid_center) > BARREL_EXCLUSION_RADIUS_SQ:
			break
		angle     = _rng.randf_range(0.0, TAU)
		dist      = _rng.randf_range(POST_DEPOSIT_WANDER_RADIUS * 0.6, POST_DEPOSIT_WANDER_RADIUS)
		candidate = home_pos + Vector2(cos(angle), sin(angle)) * dist
	_move_target  = candidate
	state         = State.PATROL
	_state_timer  = 0.0
	_invalidate_npc_path()


# ---------------------------------------------------------------------------
# Drop grab — alta prioridad, interrumpe cualquier estado excepto los críticos
# ---------------------------------------------------------------------------

func _try_grab_visible_drop(ctx: Dictionary) -> void:
	if pending_collect_id != 0:
		return
	match state:
		State.RETURN_HOME, State.HOLD_POSITION, \
		State.LOOT_APPROACH, State.RESOURCE_WATCH, \
		State.EXTORT_APPROACH, State.EXTORT_RETREAT:
			return
		_:
			# Roaming guard in "returning" or "waiting" phase: don't interrupt
			if role == "bodyguard" and _is_roaming_guard:
				if _roaming_phase == "returning" or _roaming_phase == "waiting":
					return

	var drops: Array = ctx.get("nearby_drops_info", [])
	if drops.is_empty():
		return
	var node_pos: Vector2 = ctx.get("node_pos", home_pos)
	var best_id: int = _pick_nearest_drop_id(drops, node_pos)
	if best_id != 0:
		enter_loot_approach(best_id)


# ---------------------------------------------------------------------------
# Work seeking — loot > resource watch (role-gated)
# ---------------------------------------------------------------------------

func _try_find_work(ctx: Dictionary) -> void:
	var node_pos: Vector2 = ctx.get("node_pos", home_pos)

	# Roaming bodyguard: manages its own movement cycle
	if role == "bodyguard" and _is_roaming_guard:
		# If idle during "patrolling" phase, kick off a wide patrol immediately
		if _roaming_phase == "patrolling" and state == State.IDLE_AT_HOME:
			_enter_wide_patrol()
		return  # never follow leader or do normal work; loot is handled via _try_grab_visible_drop

	# Stay bodyguard: escort leader when they've moved well away from home
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
		var res: Dictionary  = _pick_nearest_res(resources, node_pos)
		if not res.is_empty():
			enter_resource_watch(res.get("pos", Vector2.ZERO), res.get("id", 0))
			return


# ---------------------------------------------------------------------------
# Role gates
# ---------------------------------------------------------------------------

func _can_loot() -> bool:
	return true

func _can_watch_resources() -> bool:
	return role == "scavenger"


func _should_suppress_generic_drop_pickup(ctx: Dictionary) -> bool:
	if not _is_structure_assault_active():
		return false
	if not BanditTuning.assault_suppress_generic_drop_pickup():
		return false
	# Escape hatch: si el drop ya está dentro de rango real de pickup, NO suprimir.
	# Así evitamos quedar pegados sobre el drop tras destruir un placeable.
	return not _has_drop_within_sq(ctx, COLLECT_DIST_SQ)


func _has_drop_within_sq(ctx: Dictionary, radius_sq: float) -> bool:
	var node_pos: Vector2 = ctx.get("node_pos", home_pos)
	var drops: Array = ctx.get("nearby_drops_info", [])
	for raw_drop in drops:
		if not (raw_drop is Dictionary):
			continue
		var drop: Dictionary = raw_drop as Dictionary
		var dpos: Variant = drop.get("pos", null)
		if dpos is Vector2 and node_pos.distance_squared_to(dpos as Vector2) <= radius_sq:
			return true
	return false


# ---------------------------------------------------------------------------
# Resource claim / report (scavenger)
# ---------------------------------------------------------------------------

func enter_resource_watch(resource_pos: Vector2, resource_id: int = 0) -> void:
	var key: String  = _res_key(resource_pos)
	_claimed_res_key = key
	_avoid_res_key   = key
	_avoid_res_until = RunClock.now() + 45.0
	if group_id != "":
		BanditGroupMemory.claim_resource(group_id, key, member_id)
		BanditGroupMemory.report_resource(group_id, resource_pos, member_id)
	super.enter_resource_watch(resource_pos, resource_id)


func _on_leave_resource_watch() -> void:
	if group_id != "" and _claimed_res_key != "":
		BanditGroupMemory.release_resource_by_member(group_id, member_id)
	_claimed_res_key = ""


# ---------------------------------------------------------------------------
# Post-deposit notification — called by BanditBehaviorLayer after deposit
# ---------------------------------------------------------------------------

## Called by BanditBehaviorLayer once cargo has been deposited in the barrel.
## Forces the NPC to leave the barrel/home area immediately.
func on_deposit_complete() -> void:
	if _try_reengage_structure_assault("deposit_complete"):
		return
	_pending_leave_home = true


# ---------------------------------------------------------------------------
# Leader proactive roam
# ---------------------------------------------------------------------------

func _try_leader_roam() -> void:
	var is_exploring: bool = _leader_explore_phase == "exploring"
	if is_exploring:
		_leader_roam_timer = _rng.randf_range(30.0, 65.0)
	else:
		_leader_roam_timer = _rng.randf_range(18.0, 40.0)

	# Prioritise resources reported by scavengers
	if group_id != "":
		var reported: Array = BanditGroupMemory.get_reported_resources(group_id)
		if not reported.is_empty():
			var pick: Dictionary = reported[_rng.randi() % reported.size()] as Dictionary
			var pos_raw          = pick.get("pos", null)
			if not (pos_raw is Vector2):
				return
			var rpos: Vector2 = pos_raw
			if rpos != Vector2.ZERO and rpos.distance_squared_to(home_pos) > 64.0 * 64.0:
				_move_target = rpos
				state        = State.APPROACH_INTEREST
				_state_timer = 0.0
				_invalidate_npc_path()
				Debug.log("bandit_ai", "[BWB] leader→resource %s gid=%s phase=%s" % [
					str(rpos), group_id, _leader_explore_phase])
				return

	# Territory sweep — full map when exploring, local when not
	var radius: float
	var min_dist: float
	if is_exploring:
		radius   = _rng.randf_range(LEADER_EXPLORE_RADIUS * 0.3, LEADER_EXPLORE_RADIUS)
		min_dist = 400.0
	else:
		radius   = float(_PATROL_RADIUS_BY_ROLE.get("leader", 160.0)) * 1.8
		min_dist = 80.0
	var angle: float = _rng.randf_range(0.0, TAU)
	_move_target = home_pos + Vector2(cos(angle), sin(angle)) * _rng.randf_range(min_dist, radius)
	state        = State.PATROL
	_state_timer = 0.0
	_invalidate_npc_path()


# ---------------------------------------------------------------------------
# Pick helpers — work on plain data (no node access)
# ---------------------------------------------------------------------------

const HOME_DROP_IGNORE_RADIUS_SQ: float = 80.0 * 80.0

func _pick_nearest_drop_id(drops_info: Array, node_pos: Vector2) -> int:
	var best_id: int    = 0
	var best_dsq: float = INF
	for d in drops_info:
		var info: Dictionary = d as Dictionary
		var pos: Vector2     = info.get("pos", Vector2.ZERO)
		if pos.distance_squared_to(home_pos) < HOME_DROP_IGNORE_RADIUS_SQ:
			continue
		var dsq: float = node_pos.distance_squared_to(pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best_id  = int(info.get("id", 0))
	return best_id


func _pick_nearest_res(res_info: Array, node_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dsq: float  = INF
	var now: float       = RunClock.now()
	for r in res_info:
		var info: Dictionary = r as Dictionary
		var pos: Vector2     = info.get("pos", Vector2.ZERO)
		if pos == Vector2.ZERO:
			continue
		var key: String = _res_key(pos)
		if key == _avoid_res_key and now < _avoid_res_until:
			continue
		if group_id != "" and BanditGroupMemory.is_resource_claimed_by_other(group_id, key, member_id):
			continue
		var dsq: float = node_pos.distance_squared_to(pos)
		if dsq < best_dsq:
			best_dsq = dsq
			best     = info
	return best


static func _res_key(pos: Vector2) -> String:
	return "%d_%d" % [int(pos.x / 32.0), int(pos.y / 32.0)]


func _is_valid_world_target(pos: Vector2) -> bool:
	return pos.is_finite() and not pos.is_equal_approx(Vector2(-1.0, -1.0))


func _is_structure_assault_active() -> bool:
	if group_id == "":
		return false
	return BanditGroupMemory.is_structure_assault_active(group_id)


func _resolve_assault_target_from_memory() -> Vector2:
	if group_id == "":
		return Vector2(-1.0, -1.0)
	var g: Dictionary = BanditGroupMemory.get_group(group_id)
	var interest_kind: String = String(g.get("last_interest_kind", ""))
	if interest_kind != "":
		var interest_pos: Vector2 = g.get("last_interest_pos", Vector2(-1.0, -1.0)) as Vector2
		if _is_valid_world_target(interest_pos):
			return interest_pos
	var pending: Vector2 = BanditGroupMemory.get_assault_target(group_id)
	if _is_valid_world_target(pending):
		return pending
	return Vector2(-1.0, -1.0)


func get_structure_assault_focus_target() -> Vector2:
	if not _in_assault:
		return Vector2(-1.0, -1.0)
	if state != State.APPROACH_INTEREST:
		return Vector2(-1.0, -1.0)
	return _move_target if _is_valid_world_target(_move_target) else Vector2(-1.0, -1.0)


func _try_reengage_structure_assault(reason: String) -> bool:
	if not _is_structure_assault_active():
		return false
	var target_pos: Vector2 = _resolve_assault_target_from_memory()
	if not _is_valid_world_target(target_pos):
		return false
	enter_wall_assault(target_pos)
	Debug.log("raid", "[BWB] re-engage structure assault member=%s group=%s reason=%s target=%s" % [
		member_id, group_id, reason, str(target_pos)
	])
	return true


func _log_assault_pickup_suppressed(point: String) -> void:
	if RunClock.now() < _assault_suppress_log_until:
		return
	_assault_suppress_log_until = RunClock.now() + 6.0
	Debug.log("raid", "[BWB] suppress pickup during structure assault member=%s group=%s point=%s" % [
		member_id, group_id, point
	])


# ---------------------------------------------------------------------------
# Group intent reaction
# ---------------------------------------------------------------------------

func _on_group_intent_changed(intent: String, ctx: Dictionary) -> void:
	Debug.log("bandit_ai", "[BWB] intent changed member=%s role=%s group=%s %s→%s" % [
		member_id, role, group_id, _last_intent, intent])

	match intent:
		"hunting":
			# Nivel 1-2: el grupo no tiene autorización para perseguir activamente.
			# Se quedan en "alerted" (solo un scout se mueve).
			if _profile != null and not _profile.can_pursue_briefly:
				_on_group_intent_changed("alerted", ctx)
				return
			match role:
				"leader":
					var g: Dictionary = BanditGroupMemory.get_group(group_id)
					var interest_pos: Vector2 = g.get("last_interest_pos", home_pos)
					if interest_pos.distance_squared_to(home_pos) > 1.0:
						_move_target = interest_pos
						state        = State.APPROACH_INTEREST
						_state_timer = 0.0
				"bodyguard":
					if _is_roaming_guard:
						# Roaming guard converges on interest point during hunt
						var g: Dictionary = BanditGroupMemory.get_group(group_id)
						var interest_pos: Vector2 = g.get("last_interest_pos", home_pos)
						if interest_pos.distance_squared_to(home_pos) > 1.0:
							_roaming_phase = "returning"  # reuse returning logic
							_move_target   = interest_pos
							state          = State.APPROACH_INTEREST
							_state_timer   = 0.0
							_invalidate_npc_path()
					else:
						state        = State.FOLLOW_LEADER
						_state_timer = 0.0
				_:
					pass

		"extorting":
			# can_knockout se habilita en nivel 5. A partir de ahí la facción
			# prefiere la violencia directa y ya no extorsiona.
			# (La condición !can_extort sería nivel 0, lo cual es incorrecto.)
			if _profile != null and _profile.can_knockout:
				_on_group_intent_changed("hunting", ctx)
				return
			match role:
				"leader", "bodyguard":
					_enter_group_extort_approach()
				_:
					pass

		"alerted":
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

		"raiding":
			# Converger en el objetivo de raid/asalto (last_interest_pos = target actual).
			# Si ya estamos en asalto directo (_in_assault), no sobreescribir el target.
			if not _in_assault:
				var g_raid: Dictionary = BanditGroupMemory.get_group(group_id)
				var base_pos: Vector2  = g_raid.get("last_interest_pos", home_pos) as Vector2
				if base_pos.distance_squared_to(home_pos) > 1.0:
					_move_target = base_pos
					state        = State.APPROACH_INTEREST
					_state_timer = 0.0
					_in_assault  = true
					_invalidate_npc_path()

		"idle":
			if state == State.APPROACH_INTEREST or state == State.FOLLOW_LEADER \
					or state == State.EXTORT_APPROACH:
				if role == "bodyguard" and _is_roaming_guard:
					# Resume wide patrol from current leader position
					var leader_pos: Vector2 = ctx.get("leader_pos", home_pos)
					_roaming_dispatch_pos = leader_pos
					_roaming_phase        = "patrolling"
					_roaming_timer        = _rng.randf_range(5.0, 20.0)
					_enter_wide_patrol()
				else:
					_enter_return_home()


func _enter_group_extort_approach() -> void:
	var g: Dictionary = BanditGroupMemory.get_group(group_id)
	var interest_pos: Vector2 = g.get("last_interest_pos", home_pos)
	if interest_pos.distance_squared_to(home_pos) > 1.0:
		enter_extort_approach(interest_pos)


## Ordena al NPC moverse hacia una posición de muro del jugador para atacarlo.
## Llamado por RaidFlow durante el phase ATTACKING, o por el comportamiento oportunista.
## Al llegar, el slash normal inflige daño al contacto con la geometría del muro.
func enter_wall_assault(wall_pos: Vector2) -> void:
	_move_target = wall_pos
	state        = State.APPROACH_INTEREST
	_state_timer = 0.0
	_in_assault  = true
	_invalidate_npc_path()


## Sabotaje oportunista a placeables (workbench / storage) — no raid:
## A partir de nivel 7 los NPCs atacan talleres; nivel 8+ también atacan storage.
## Probabilidad: (nivel-6) × 2% por tick. Cooldown: 35s por NPC.
## La IA normal (slash.gd) inflige el daño al llegar y golpear el placeable.
func _try_property_sabotage(ctx: Dictionary) -> void:
	if RunClock.now() < _property_sabotage_cooldown_until:
		return
	if _profile == null:
		return
	var h_level: int = _profile.hostility_level
	if h_level < 7:
		return
	# (nivel-6) × 2% — nivel 7→2%, 8→4%, 9→6%, 10→8%
	var chance: float = float(h_level - 6) * 0.02
	if _rng.randf() > chance:
		return
	var node_pos: Vector2 = ctx.get("node_pos", home_pos) as Vector2
	var target_pos: Vector2 = Vector2(-1.0, -1.0)
	# Nivel 7+: workbench
	if h_level >= 7:
		var find_wb: Callable = ctx.get("find_nearest_player_workbench", Callable())
		if find_wb.is_valid():
			target_pos = find_wb.call(node_pos, 400.0) as Vector2
	# Nivel 8+: storage — preferir el más cercano entre los dos tipos
	if h_level >= 8:
		var find_st: Callable = ctx.get("find_nearest_player_storage", Callable())
		if find_st.is_valid():
			var st_pos: Vector2 = find_st.call(node_pos, 400.0) as Vector2
			if _is_valid_world_target(st_pos):
				if not _is_valid_world_target(target_pos) or \
						node_pos.distance_squared_to(st_pos) < node_pos.distance_squared_to(target_pos):
					target_pos = st_pos
	if not _is_valid_world_target(target_pos):
		return
	enter_wall_assault(target_pos)
	_property_sabotage_cooldown_until = RunClock.now() + 35.0
	Debug.log("bandit_ai", "[BWB] property sabotage — member=%s level=%d target=%s" % [
		member_id, h_level, str(target_pos)])


## Comportamiento oportunista individual (no raid):
## A partir de nivel 6, con probabilidad creciente, el NPC ataca muros del jugador
## cercanos cuando está en patrulla o idle. Probabilidad: (nivel-5) × 1% por tick.
## Cooldown: 30s por NPC para evitar spam.
func _try_opportunistic_wall_assault(ctx: Dictionary) -> void:
	# Cooldown personal
	if RunClock.now() < _wall_assault_cooldown_until:
		return
	# Verificar nivel de hostilidad (mínimo 6)
	if _profile == null:
		return
	var h_level: int = _profile.hostility_level
	if h_level < 6:
		return
	# Probabilidad por tick: escala con nivel (6→1%, 7→2%, 8→3%, 9→4%)
	# Nivel 10 hace raids organizados — el oportunismo individual sigue activo
	var chance: float = float(h_level - 5) * 0.03
	if _rng.randf() > chance:
		return
	# Buscar muro cercano
	var find_wall: Callable = ctx.get("find_nearest_player_wall", Callable())
	if not find_wall.is_valid():
		return
	var node_pos: Vector2 = ctx.get("node_pos", home_pos) as Vector2
	var wall_pos: Vector2 = find_wall.call(node_pos, 300.0) as Vector2
	if not _is_valid_world_target(wall_pos):
		return
	enter_wall_assault(wall_pos)
	_wall_assault_cooldown_until = RunClock.now() + 20.0
	Debug.log("bandit_ai", "[BWB] opp. wall assault — member=%s level=%d wall=%s" % [
		member_id, h_level, str(wall_pos)])


# ---------------------------------------------------------------------------
# Serialization — adds role-state fields to base class export / import
# ---------------------------------------------------------------------------

func export_state() -> Dictionary:
	var d: Dictionary = super.export_state()
	d["wb_last_intent"]       = _last_intent
	d["wb_claimed_key"]       = _claimed_res_key
	d["wb_avoid_key"]         = _avoid_res_key
	d["wb_avoid_until"]       = _avoid_res_until
	d["wb_follow_offset"]     = _follow_offset
	d["wb_leader_roam_t"]     = _leader_roam_timer
	d["wb_is_roaming_guard"]  = _is_roaming_guard
	d["wb_roaming_phase"]     = _roaming_phase
	d["wb_roaming_timer"]     = _roaming_timer
	d["wb_roaming_dispatch"]  = _roaming_dispatch_pos
	d["wb_leader_phase"]      = _leader_explore_phase
	d["wb_leader_phase_t"]    = _leader_phase_timer
	return d

func import_state(data: Dictionary) -> void:
	super.import_state(data)
	_last_intent       = String(data.get("wb_last_intent",      ""))
	_claimed_res_key   = String(data.get("wb_claimed_key",      ""))
	_avoid_res_key     = String(data.get("wb_avoid_key",        ""))
	_avoid_res_until   = float(data.get("wb_avoid_until",       0.0))
	var fo             = data.get("wb_follow_offset", Vector2.ZERO)
	_follow_offset     = fo if fo is Vector2 else Vector2.ZERO
	_leader_roam_timer = float(data.get("wb_leader_roam_t",     0.0))
	_is_roaming_guard  = bool(data.get("wb_is_roaming_guard",   false))
	_roaming_phase     = String(data.get("wb_roaming_phase",    "patrolling"))
	_roaming_timer     = float(data.get("wb_roaming_timer",     0.0))
	var rdp            = data.get("wb_roaming_dispatch", Vector2.ZERO)
	_roaming_dispatch_pos = rdp if rdp is Vector2 else Vector2.ZERO
	_leader_explore_phase = String(data.get("wb_leader_phase",  "local"))
	_leader_phase_timer   = float(data.get("wb_leader_phase_t", 0.0))
