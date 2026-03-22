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
		Debug.log("bandit_group", "[BGM] leader set id=%s group=%s" % [member_id, group_id])


## Elimina un miembro (p.ej. al morir). Si era el leader, lo limpia.
func remove_member(group_id: String, member_id: String) -> void:
	if not _groups.has(group_id):
		return
	var g: Dictionary = _groups[group_id]
	(g["member_ids"] as Array).erase(member_id)
	if String(g["leader_id"]) == member_id:
		g["leader_id"] = ""
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


func promote_leader(group_id: String, npc_id: String) -> void:
	if not _groups.has(group_id):
		return
	_groups[group_id]["leader_id"] = npc_id
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
	}


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
		# Vector2 → plain dict (JSON-safe)
		var hwp: Vector2 = g.get("home_world_pos", Vector2.ZERO)
		g["home_world_pos"] = {"x": hwp.x, "y": hwp.y}
		var lip: Vector2 = g.get("last_interest_pos", Vector2.ZERO)
		g["last_interest_pos"] = {"x": lip.x, "y": lip.y}
		out[gid] = g
	return out


func deserialize(data: Dictionary) -> void:
	_groups.clear()
	for gid: String in data:
		var g: Dictionary = (data[gid] as Dictionary).duplicate(true)
		if not g.has("current_intent_since"):
			g["current_intent_since"] = RunClock.now()
		if not g.has("internal_social_cooldown_until"):
			g["internal_social_cooldown_until"] = 0.0
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
		_groups[gid] = g


func reset() -> void:
	_groups.clear()


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
