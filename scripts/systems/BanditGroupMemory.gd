extends Node

# Responsibility boundary:
# BanditGroupMemory stores shared bandit-group memory plus current_group_intent.
# It does not own extortion job state, UI flow, payment, or phase bookkeeping.
# Extortion-specific persistence stops at shared intent/memory: active encounters
# live elsewhere as ephemeral runtime state and are allowed to vanish on world
# reconstruction so they can be regenerated from queued intent if still relevant.
#
# group_id format: "camp:{chunk_key}:{camp_index:03d}"  (producido por NpcSimulator)
#
# Separación de conceptos:
#   - NpcProfileSystem  → estado individual por NPC  (role, status)
#   - BanditGroupMemory → estado colectivo por grupo (intent, members, shared memory)

var _groups: Dictionary = {}  # group_id -> group data dict
var _blackboard_consistency_log_at: Dictionary = {}  # group_id -> last log ts

const BLACKBOARD_SECTION_PERCEPTION: String = "perception"
const BLACKBOARD_SECTION_ASSIGNMENTS: String = "assignments"
const BLACKBOARD_SECTION_STATUS: String = "status"
const BLACKBOARD_SECTION_EXPIRATIONS: String = "expirations"
const BLACKBOARD_RESOURCES_TTL: float = 45.0
const BLACKBOARD_DROPS_TTL: float = 20.0
const BLACKBOARD_STATUS_TTL: float = 90.0
const BLACKBOARD_CONSISTENCY_LOG_COOLDOWN: float = 8.0


# ---------------------------------------------------------------------------
# Member registration (called from NpcSimulator.on_enemy_job_spawned)
# ---------------------------------------------------------------------------

## Registra un miembro en el grupo. Idempotente: si ya está, solo actualiza el role.
func register_member(
		group_id: String,
		member_id: String,
		role: String,
		home_world_pos: Vector2,
		faction_id: String) -> void:

	if not _groups.has(group_id):
		_groups[group_id] = _make_group(group_id, faction_id, home_world_pos)
		Debug.log("bandit_group", "[BGM] group created id=%s faction=%s home=%s" % [
			group_id, faction_id, str(home_world_pos)])

	var g: Dictionary = _groups[group_id]
	var members: Array = g["member_ids"]
	if not members.has(member_id):
		members.append(member_id)

	# First-registered leader wins; only update if no leader yet
	if role == "leader" and String(g["leader_id"]) == "":
		g["leader_id"] = member_id
		bb_set_status(group_id, "leader_id", member_id, BLACKBOARD_STATUS_TTL, "register_member")
		Debug.log("bandit_group", "[BGM] leader set id=%s group=%s" % [member_id, group_id])


## Elimina un miembro (p.ej. al morir). Si era el leader, lo limpia.
func remove_member(group_id: String, member_id: String) -> void:
	if not _groups.has(group_id):
		return
	var g: Dictionary = _groups[group_id]
	(g["member_ids"] as Array).erase(member_id)
	if String(g["leader_id"]) == member_id:
		g["leader_id"] = ""
		bb_set_status(group_id, "leader_id", "", BLACKBOARD_STATUS_TTL, "remove_member")
		Debug.log("bandit_group", "[BGM] leader died group=%s" % group_id)
	# Release any resource claim held by this member
	if g.has("resource_claims"):
		var claims: Dictionary = g["resource_claims"]
		for key in claims.keys():
			if String(claims[key]) == member_id:
				claims.erase(key)
				break
	Debug.log("bandit_group", "[BGM] member removed id=%s group=%s remaining=%d" % [
		member_id, group_id, (g["member_ids"] as Array).size()])


# ---------------------------------------------------------------------------
# Intent / interest API
# ---------------------------------------------------------------------------

## Actualiza el intent colectivo del grupo.
## Valores esperados: "idle" | "alerted" | "hunting" | "extorting"
func update_intent(group_id: String, intent: String) -> void:
	if not _groups.has(group_id):
		return
	var g: Dictionary = _groups[group_id]
	var prev: String = String(g["current_group_intent"])
	if prev != intent:
		g["current_group_intent"] = intent
		g["current_intent_since"] = RunClock.now()
		bb_set_status(group_id, "group_mode", intent, BLACKBOARD_STATUS_TTL, "update_intent")
		Debug.log("bandit_group", "[BGM] intent changed group=%s %s→%s" % [group_id, prev, intent])


## Registra la última posición/tipo de actividad que llamó la atención del grupo.
func record_interest(group_id: String, world_pos: Vector2, kind: String) -> void:
	if not _groups.has(group_id):
		return
	_groups[group_id]["last_interest_pos"] = world_pos
	_groups[group_id]["last_interest_kind"] = kind


# ---------------------------------------------------------------------------
# Query API
# ---------------------------------------------------------------------------

func get_group(group_id: String) -> Dictionary:
	_blackboard_prune(group_id)
	return _groups.get(group_id, {})

func has_group(group_id: String) -> bool:
	return _groups.has(group_id)

func get_all_group_ids() -> Array:
	return _groups.keys()

func get_groups_for_faction(faction_id: String) -> Array:
	var result: Array = []
	for gid in _groups:
		if String(_groups[gid].get("faction_id", "")) == faction_id:
			result.append(_groups[gid])
	return result



func get_intent_time(group_id: String) -> float:
	var g: Dictionary = _groups.get(group_id, {})
	if g.is_empty():
		return 0.0
	var since: float = float(g.get("current_intent_since", RunClock.now()))
	return maxf(0.0, RunClock.now() - since)


func push_social_cooldown(group_id: String, duration: float) -> void:
	if not _groups.has(group_id):
		return
	var g: Dictionary = _groups[group_id]
	var now: float = RunClock.now()
	var until: float = maxf(float(g.get("internal_social_cooldown_until", 0.0)), now)
	g["internal_social_cooldown_until"] = until + maxf(duration, 0.0)


func get_internal_social_cooldown_remaining(group_id: String) -> float:
	var g: Dictionary = _groups.get(group_id, {})
	if g.is_empty():
		return 0.0
	return maxf(0.0, float(g.get("internal_social_cooldown_until", 0.0)) - RunClock.now())


# ---------------------------------------------------------------------------
# Internal factory
# ---------------------------------------------------------------------------

## Scavenger reports a resource to group memory.
## Deduplicates by 32 px grid cell; trims entries older than 90 s.
func report_resource(group_id: String, pos: Vector2, reporter_id: String) -> void:
	if not _groups.has(group_id):
		return
	if not _groups[group_id].has("reported_resources"):
		_groups[group_id]["reported_resources"] = []
	var key: String = _res_pos_key(pos)
	var now: float  = RunClock.now()
	var arr: Array  = _groups[group_id]["reported_resources"]
	for i in range(arr.size() - 1, -1, -1):
		var e: Dictionary = arr[i]
		if now - float(e.get("time", 0.0)) > 90.0 or String(e.get("res_key", "")) == key:
			arr.remove_at(i)
	arr.append({"pos": pos, "reporter_id": reporter_id, "res_key": key, "time": now})


func get_reported_resources(group_id: String) -> Array:
	if not _groups.has(group_id):
		return []
	if not _groups[group_id].has("reported_resources"):
		return []
	# Trim stale entries on every read so the list doesn't grow unbounded
	var arr: Array = _groups[group_id]["reported_resources"]
	var now: float = RunClock.now()
	for i in range(arr.size() - 1, -1, -1):
		if now - float((arr[i] as Dictionary).get("time", 0.0)) > 90.0:
			arr.remove_at(i)
	return arr


## Mark a resource cell as claimed by member_id.
func claim_resource(group_id: String, res_key: String, member_id: String) -> void:
	if not _groups.has(group_id) or res_key == "":
		return
	if not _groups[group_id].has("resource_claims"):
		_groups[group_id]["resource_claims"] = {}
	_groups[group_id]["resource_claims"][res_key] = member_id


## Release any resource cell previously claimed by this member.
func release_resource_by_member(group_id: String, member_id: String) -> void:
	if not _groups.has(group_id):
		return
	if not _groups[group_id].has("resource_claims"):
		return
	var claims: Dictionary = _groups[group_id]["resource_claims"]
	for key in claims.keys():
		if String(claims[key]) == member_id:
			claims.erase(key)
			return


## Returns true if res_key is claimed by a *different* member.
func is_resource_claimed_by_other(group_id: String, res_key: String, member_id: String) -> bool:
	if not _groups.has(group_id) or res_key == "":
		return false
	if not _groups[group_id].has("resource_claims"):
		return false
	var claimer: String = String(_groups[group_id]["resource_claims"].get(res_key, ""))
	return claimer != "" and claimer != member_id


## Stable 32 px grid key for a world position.
static func _res_pos_key(pos: Vector2) -> String:
	return "%d_%d" % [int(pos.x / 32.0), int(pos.y / 32.0)]


## Bloquea el reset de intent a "idle" por BGI durante N segundos (asalto activo).
func set_placement_react_lock(group_id: String, duration: float) -> void:
	if not _groups.has(group_id):
		return
	_groups[group_id]["placement_react_until"] = RunClock.now() + duration


## Devuelve true si hay un asalto de placement_react activo para este grupo.
func has_placement_react_lock(group_id: String) -> bool:
	if not _groups.has(group_id):
		return false
	return RunClock.now() < float(_groups.get(group_id, {}).get("placement_react_until", 0.0))


## Marca contexto runtime de structure_assault para un grupo.
## Debe refrescarse periódicamente desde RaidFlow.
func mark_structure_assault_active(group_id: String, ttl_seconds: float) -> void:
	if not _groups.has(group_id):
		return
	var ttl: float = maxf(ttl_seconds, 0.0)
	var now: float = RunClock.now()
	var g: Dictionary = _groups[group_id]
	var was_until: float = float(g.get("structure_assault_active_until", 0.0))
	g["structure_assault_active_until"] = now + ttl
	if was_until <= now:
		Debug.log("raid", "[BGM] structure assault active start group=%s ttl=%.1fs" % [group_id, ttl])
		g["structure_assault_active_log_at"] = now
		return
	var last_log: float = float(g.get("structure_assault_active_log_at", 0.0))
	if now - last_log >= 10.0:
		Debug.log("raid", "[BGM] structure assault active refresh group=%s ttl=%.1fs" % [group_id, ttl])
		g["structure_assault_active_log_at"] = now


## Devuelve true mientras el grupo tenga structure_assault runtime vigente.
func is_structure_assault_active(group_id: String) -> bool:
	if not _groups.has(group_id):
		return false
	return RunClock.now() < float(_groups[group_id].get("structure_assault_active_until", 0.0))


## Limpia el contexto runtime de structure_assault.
func clear_structure_assault_active(group_id: String) -> void:
	if not _groups.has(group_id):
		return
	var g: Dictionary = _groups[group_id]
	if float(g.get("structure_assault_active_until", 0.0)) > RunClock.now():
		Debug.log("raid", "[BGM] structure assault active clear group=%s" % group_id)
	g.erase("structure_assault_active_until")
	g.erase("structure_assault_active_log_at")


## Almacena un target de asalto pendiente para cuando el grupo spawne.
func set_assault_target(group_id: String, target_pos: Vector2) -> void:
	if not _groups.has(group_id):
		return
	_groups[group_id]["pending_assault_target"] = target_pos


## Lee el target pendiente sin borrarlo. Vector2(-1,-1) si no hay ninguno.
func get_assault_target(group_id: String) -> Vector2:
	if not _groups.has(group_id):
		return Vector2(-1.0, -1.0)
	var g: Dictionary = _groups[group_id]
	if not g.has("pending_assault_target"):
		return Vector2(-1.0, -1.0)
	return g["pending_assault_target"] as Vector2


## Elimina el target pendiente del grupo.
func clear_assault_target(group_id: String) -> void:
	if not _groups.has(group_id):
		return
	_groups[group_id].erase("pending_assault_target")


func promote_leader(group_id: String, npc_id: String) -> void:
	if not _groups.has(group_id):
		return
	_groups[group_id]["leader_id"] = npc_id
	bb_set_status(group_id, "leader_id", npc_id, BLACKBOARD_STATUS_TTL, "promote_leader")
	Debug.log("bandit_group", "[BGM] leader promoted id=%s group=%s" % [npc_id, group_id])

func set_scout(group_id: String, npc_id: String) -> void:
	if not _groups.has(group_id):
		return
	_groups[group_id]["scout_npc_id"] = npc_id

func get_scout(group_id: String) -> String:
	return String(_groups.get(group_id, {}).get("scout_npc_id", ""))


func add_wealth(group_id: String, delta: float) -> void:
	if not _groups.has(group_id):
		return
	_groups[group_id]["wealth"] = float(_groups[group_id].get("wealth", 0.0)) + delta


func get_wealth(group_id: String) -> float:
	return float(_groups.get(group_id, {}).get("wealth", 0.0))


func _make_group(group_id: String, faction_id: String, home_world_pos: Vector2) -> Dictionary:
	return {
		"group_id":                   group_id,
		"faction_id":                 faction_id,
		"leader_id":                  "",
		"member_ids":                 [],
		"home_world_pos":             home_world_pos,
		"current_group_intent":       "idle",
		"current_intent_since":       RunClock.now(),
		"internal_social_cooldown_until": 0.0,
		"last_interest_pos":          Vector2.ZERO,
		"last_interest_kind":         "",
		"scout_npc_id":               "",
		"reported_resources":         [],   # [{pos, reporter_id, res_key, time}]
		"resource_claims":            {},   # {res_key -> member_id}
		"wealth":                     0.0, # cumulative sell-price of stashed goods
		"structure_assault_active_until": 0.0,
		"eradicated":                 false,
		"group_blackboard":           _make_group_blackboard(),
	}


func _make_group_blackboard() -> Dictionary:
	return {
		BLACKBOARD_SECTION_PERCEPTION: {
			"known_resources": {},
			"known_drops": {},
			"prioritized_resources": _bb_make_entry([], BLACKBOARD_RESOURCES_TTL, "init"),
			"prioritized_drops": _bb_make_entry([], BLACKBOARD_DROPS_TTL, "init"),
		},
		BLACKBOARD_SECTION_ASSIGNMENTS: {},
		BLACKBOARD_SECTION_STATUS: {
			"threat_level": _bb_make_entry(0.0, BLACKBOARD_STATUS_TTL, "init"),
			"leader_id": _bb_make_entry("", BLACKBOARD_STATUS_TTL, "init"),
			"group_mode": _bb_make_entry("idle", BLACKBOARD_STATUS_TTL, "init"),
		},
		BLACKBOARD_SECTION_EXPIRATIONS: {},
	}


func _bb_make_entry(value: Variant, ttl_seconds: float, source: String = "") -> Dictionary:
	var now: float = RunClock.now()
	var ttl: float = maxf(ttl_seconds, 0.0)
	return {
		"value": value,
		"timestamp": now,
		"expires_at": now + ttl,
		"ttl_seconds": ttl,
		"source": source,
	}


func _ensure_blackboard(group_id: String) -> Dictionary:
	if not _groups.has(group_id):
		return {}
	var g: Dictionary = _groups[group_id]
	if not g.has("group_blackboard") or not (g["group_blackboard"] is Dictionary):
		g["group_blackboard"] = _make_group_blackboard()
	return g["group_blackboard"] as Dictionary


func _blackboard_perception(group_id: String) -> Dictionary:
	var bb: Dictionary = _ensure_blackboard(group_id)
	if bb.is_empty():
		return {}
	if not bb.has(BLACKBOARD_SECTION_PERCEPTION):
		bb[BLACKBOARD_SECTION_PERCEPTION] = {
			"known_resources": {},
			"known_drops": {},
			"prioritized_resources": _bb_make_entry([], BLACKBOARD_RESOURCES_TTL, "init"),
			"prioritized_drops": _bb_make_entry([], BLACKBOARD_DROPS_TTL, "init"),
		}
	if not bb[BLACKBOARD_SECTION_PERCEPTION].has("prioritized_resources"):
		bb[BLACKBOARD_SECTION_PERCEPTION]["prioritized_resources"] = _bb_make_entry([], BLACKBOARD_RESOURCES_TTL, "init")
	if not bb[BLACKBOARD_SECTION_PERCEPTION].has("prioritized_drops"):
		bb[BLACKBOARD_SECTION_PERCEPTION]["prioritized_drops"] = _bb_make_entry([], BLACKBOARD_DROPS_TTL, "init")
	return bb[BLACKBOARD_SECTION_PERCEPTION] as Dictionary


func _blackboard_status(group_id: String) -> Dictionary:
	var bb: Dictionary = _ensure_blackboard(group_id)
	if bb.is_empty():
		return {}
	if not bb.has(BLACKBOARD_SECTION_STATUS):
		bb[BLACKBOARD_SECTION_STATUS] = {}
	return bb[BLACKBOARD_SECTION_STATUS] as Dictionary


func _blackboard_expirations(group_id: String) -> Dictionary:
	var bb: Dictionary = _ensure_blackboard(group_id)
	if bb.is_empty():
		return {}
	if not bb.has(BLACKBOARD_SECTION_EXPIRATIONS):
		bb[BLACKBOARD_SECTION_EXPIRATIONS] = {}
	return bb[BLACKBOARD_SECTION_EXPIRATIONS] as Dictionary


func bb_set_status(group_id: String, key: String, value: Variant, ttl_seconds: float = BLACKBOARD_STATUS_TTL, source: String = "status_write") -> void:
	var status: Dictionary = _blackboard_status(group_id)
	if status.is_empty():
		return
	status[key] = _bb_make_entry(value, ttl_seconds, source)
	_blackboard_expirations(group_id)["status.%s" % key] = float((status[key] as Dictionary).get("expires_at", 0.0))
	_log_blackboard_consistency(group_id, source)


func bb_write_threat_level(group_id: String, threat_level: float, source: String = "intel_scan") -> void:
	bb_set_status(group_id, "threat_level", maxf(threat_level, 0.0), BLACKBOARD_STATUS_TTL, source)


func bb_write_group_mode(group_id: String, group_mode: String, source: String = "intent_policy") -> void:
	bb_set_status(group_id, "group_mode", group_mode, BLACKBOARD_STATUS_TTL, source)


func bb_write_known_resources(group_id: String, resources: Array, ttl_seconds: float = BLACKBOARD_RESOURCES_TTL, source: String = "passive_resource_scan") -> void:
	var perception: Dictionary = _blackboard_perception(group_id)
	if perception.is_empty():
		return
	if not perception.has("known_resources"):
		perception["known_resources"] = {}
	var known_resources: Dictionary = perception["known_resources"]
	var now: float = RunClock.now()
	for raw in resources:
		if not (raw is Dictionary):
			continue
		var info: Dictionary = raw as Dictionary
		var pos_raw: Variant = info.get("pos", null)
		if not (pos_raw is Vector2):
			continue
		var pos: Vector2 = pos_raw as Vector2
		var key: String = _res_pos_key(pos)
		known_resources[key] = _bb_make_entry({
			"id": int(info.get("id", 0)),
			"pos": pos,
		}, ttl_seconds, source)
	_blackboard_expirations(group_id)["perception.known_resources"] = now + maxf(ttl_seconds, 0.0)
	_log_blackboard_consistency(group_id, source)


func bb_write_known_drops(group_id: String, drops: Array, ttl_seconds: float = BLACKBOARD_DROPS_TTL, source: String = "passive_drop_scan") -> void:
	var perception: Dictionary = _blackboard_perception(group_id)
	if perception.is_empty():
		return
	if not perception.has("known_drops"):
		perception["known_drops"] = {}
	var known_drops: Dictionary = perception["known_drops"]
	var now: float = RunClock.now()
	for raw in drops:
		if not (raw is Dictionary):
			continue
		var info: Dictionary = raw as Dictionary
		var id: int = int(info.get("id", 0))
		if id == 0:
			continue
		var pos_raw: Variant = info.get("pos", null)
		var pos: Vector2 = pos_raw as Vector2 if pos_raw is Vector2 else Vector2.ZERO
		known_drops[str(id)] = _bb_make_entry({
			"id": id,
			"pos": pos,
			"amount": int(info.get("amount", 1)),
		}, ttl_seconds, source)
	_blackboard_expirations(group_id)["perception.known_drops"] = now + maxf(ttl_seconds, 0.0)
	_log_blackboard_consistency(group_id, source)


func bb_write_prioritized_resources(group_id: String, resources: Array, ttl_seconds: float = BLACKBOARD_RESOURCES_TTL, source: String = "group_pulse_scan") -> void:
	var perception: Dictionary = _blackboard_perception(group_id)
	if perception.is_empty():
		return
	perception["prioritized_resources"] = _bb_make_entry(resources.duplicate(true), ttl_seconds, source)
	_blackboard_expirations(group_id)["perception.prioritized_resources"] = float((perception["prioritized_resources"] as Dictionary).get("expires_at", 0.0))
	_log_blackboard_consistency(group_id, source)


func bb_write_prioritized_drops(group_id: String, drops: Array, ttl_seconds: float = BLACKBOARD_DROPS_TTL, source: String = "group_pulse_scan") -> void:
	var perception: Dictionary = _blackboard_perception(group_id)
	if perception.is_empty():
		return
	perception["prioritized_drops"] = _bb_make_entry(drops.duplicate(true), ttl_seconds, source)
	_blackboard_expirations(group_id)["perception.prioritized_drops"] = float((perception["prioritized_drops"] as Dictionary).get("expires_at", 0.0))
	_log_blackboard_consistency(group_id, source)


func bb_get_prioritized_resources(group_id: String) -> Array:
	var perception: Dictionary = _blackboard_perception(group_id)
	if perception.is_empty():
		return []
	var entry: Dictionary = perception.get("prioritized_resources", {})
	return (entry.get("value", []) as Array).duplicate(true)


func bb_get_prioritized_drops(group_id: String) -> Array:
	var perception: Dictionary = _blackboard_perception(group_id)
	if perception.is_empty():
		return []
	var entry: Dictionary = perception.get("prioritized_drops", {})
	return (entry.get("value", []) as Array).duplicate(true)


func bb_get(group_id: String) -> Dictionary:
	_blackboard_prune(group_id)
	return _ensure_blackboard(group_id)


func _blackboard_prune(group_id: String) -> void:
	var bb: Dictionary = _ensure_blackboard(group_id)
	if bb.is_empty():
		return
	var now: float = RunClock.now()
	var perception: Dictionary = _blackboard_perception(group_id)
	if not perception.is_empty():
		for collection_key in ["known_resources", "known_drops"]:
			if not perception.has(collection_key):
				continue
			var collection: Dictionary = perception[collection_key]
			var to_remove: Array = []
			for key in collection.keys():
				var entry: Dictionary = collection[key]
				if now >= float(entry.get("expires_at", 0.0)):
					to_remove.append(key)
			for key in to_remove:
				collection.erase(key)
		for prioritized_key in ["prioritized_resources", "prioritized_drops"]:
			if not perception.has(prioritized_key):
				continue
			var entry: Dictionary = perception[prioritized_key]
			if now >= float(entry.get("expires_at", 0.0)):
				var default_ttl: float = BLACKBOARD_RESOURCES_TTL if prioritized_key == "prioritized_resources" else BLACKBOARD_DROPS_TTL
				perception[prioritized_key] = _bb_make_entry([], default_ttl, "expired")
	var status: Dictionary = _blackboard_status(group_id)
	if not status.is_empty():
		var status_remove: Array = []
		for key in status.keys():
			var entry: Dictionary = status[key]
			if now >= float(entry.get("expires_at", 0.0)):
				status_remove.append(key)
		for key in status_remove:
			status.erase(key)


func _log_blackboard_consistency(group_id: String, source: String) -> void:
	var now: float = RunClock.now()
	var last_log: float = float(_blackboard_consistency_log_at.get(group_id, -INF))
	if now - last_log < BLACKBOARD_CONSISTENCY_LOG_COOLDOWN:
		return
	_blackboard_consistency_log_at[group_id] = now
	var bb: Dictionary = _ensure_blackboard(group_id)
	var perception: Dictionary = bb.get(BLACKBOARD_SECTION_PERCEPTION, {})
	var status: Dictionary = bb.get(BLACKBOARD_SECTION_STATUS, {})
	var known_resources_count: int = int((perception.get("known_resources", {}) as Dictionary).size())
	var known_drops_count: int = int((perception.get("known_drops", {}) as Dictionary).size())
	var prioritized_resources_count: int = int(((perception.get("prioritized_resources", {}) as Dictionary).get("value", []) as Array).size())
	var prioritized_drops_count: int = int(((perception.get("prioritized_drops", {}) as Dictionary).get("value", []) as Array).size())
	var threat_entry: Dictionary = status.get("threat_level", {})
	var mode_entry: Dictionary = status.get("group_mode", {})
	var leader_entry: Dictionary = status.get("leader_id", {})
	Debug.log("bandit_group", "[BGM][BB] consistency group=%s src=%s resources=%d drops=%d prio_res=%d prio_drops=%d threat=%.1f mode=%s leader=%s" % [
		group_id,
		source,
		known_resources_count,
		known_drops_count,
		prioritized_resources_count,
		prioritized_drops_count,
		float(threat_entry.get("value", 0.0)),
		String(mode_entry.get("value", "idle")),
		String(leader_entry.get("value", "")),
	])


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	var out: Dictionary = {}
	for gid: String in _groups:
		var g: Dictionary = _groups[gid].duplicate(true)
		# Strip ephemeral session-only fields (contain Vector2 that can't round-trip JSON)
		g.erase("reported_resources")
		g.erase("resource_claims")
		g.erase("pending_assault_target")
		g.erase("placement_react_until")
		g.erase("structure_assault_active_until")
		g.erase("structure_assault_active_log_at")
		# Vector2 → plain dict (JSON-safe)
		var hwp: Vector2 = g.get("home_world_pos", Vector2.ZERO)
		g["home_world_pos"] = {"x": hwp.x, "y": hwp.y}
		var lip: Vector2 = g.get("last_interest_pos", Vector2.ZERO)
		g["last_interest_pos"] = {"x": lip.x, "y": lip.y}
		out[gid] = g
	return out


func deserialize(data: Dictionary) -> void:
	_groups.clear()
	_blackboard_consistency_log_at.clear()
	for gid: String in data:
		var g: Dictionary = (data[gid] as Dictionary).duplicate(true)
		if not g.has("current_intent_since"):
			g["current_intent_since"] = RunClock.now()
		if not g.has("internal_social_cooldown_until"):
			g["internal_social_cooldown_until"] = 0.0
		if not g.has("structure_assault_active_until"):
			g["structure_assault_active_until"] = 0.0
		# Restore Vector2
		var hwp = g.get("home_world_pos", {"x": 0.0, "y": 0.0})
		if hwp is Dictionary:
			g["home_world_pos"] = Vector2(float(hwp.get("x", 0.0)), float(hwp.get("y", 0.0)))
		else:
			g["home_world_pos"] = Vector2.ZERO
		var lip = g.get("last_interest_pos", {"x": 0.0, "y": 0.0})
		if lip is Dictionary:
			g["last_interest_pos"] = Vector2(float(lip.get("x", 0.0)), float(lip.get("y", 0.0)))
		else:
			g["last_interest_pos"] = Vector2.ZERO
		if not g.has("group_blackboard") or not (g.get("group_blackboard") is Dictionary):
			g["group_blackboard"] = _make_group_blackboard()
		_groups[gid] = g


func reset() -> void:
	_groups.clear()
	_blackboard_consistency_log_at.clear()


func print_all() -> void:
	Debug.log("bandit_group", "=== BanditGroupMemory (%d groups) ===" % _groups.size())
	for gid: String in _groups:
		var g: Dictionary = _groups[gid]
		Debug.log("bandit_group", "  [%s] leader=%s members=%d intent=%s" % [
			gid,
			String(g.get("leader_id", "")),
			(g.get("member_ids", []) as Array).size(),
			String(g.get("current_group_intent", "?")),
		])
