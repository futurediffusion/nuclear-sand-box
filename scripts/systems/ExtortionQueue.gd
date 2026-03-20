extends Node

# ExtortionQueue owns queued extortion intents and request-side bookkeeping.
# It is the data bus for pending extortion work; group memory does not track
# extortion lifecycle flags or cooldown timestamps.
#
# Intent dict:
# {
#   "target_id":    String,   # uid del objetivo ("player" o uid concreto)
#   "faction_id":   String,   # facción que extorsiona
#   "group_id":     String,   # grupo concreto que extorsiona
#   "source_npc_id": String,  # NPC que emite la intención (líder, explorador…)
#   "trigger_kind": String,   # "settlement_detected" | "resource_claimed" | "proximity"
#   "world_pos":    Vector2,  # posición donde ocurrió el trigger
#   "created_at":   float,    # RunClock.now() al crear
#   "severity":     float,    # 0.0 = aviso suave, 1.0 = demanda fuerte
# }

var _intents: Array = []  # Array[Dictionary]
var _last_request_time_by_group: Dictionary = {}  # group_id -> created_at


# ---------------------------------------------------------------------------
# Write API
# ---------------------------------------------------------------------------

## Encola una intención de extorsión. El caller es responsable de rellenar
## todos los campos del dict antes de llamar a este método.
func enqueue(intent: Dictionary) -> void:
	_intents.append(intent)
	var gid: String = String(intent.get("group_id", ""))
	if gid != "":
		_last_request_time_by_group[gid] = float(intent.get("created_at", RunClock.now()))
	Debug.log("extortion", "[EXTORT] enqueued group=%s trigger=%s severity=%.2f pos=%s" % [
		gid if gid != "" else intent.get("group_id", "?"),
		intent.get("trigger_kind", "?"),
		float(intent.get("severity", 0.0)),
		str(intent.get("world_pos", Vector2.ZERO)),
	])


## Crea y encola una intención completa desde sus partes.
## Convenience wrapper para no armar el dict manualmente.
func enqueue_intent(
		target_id: String,
		faction_id: String,
		group_id: String,
		source_npc_id: String,
		trigger_kind: String,
		world_pos: Vector2,
		severity: float) -> void:
	enqueue({
		"target_id":     target_id,
		"faction_id":    faction_id,
		"group_id":      group_id,
		"source_npc_id": source_npc_id,
		"trigger_kind":  trigger_kind,
		"world_pos":     world_pos,
		"created_at":    RunClock.now(),
		"severity":      clampf(severity, 0.0, 1.0),
	})


# ---------------------------------------------------------------------------
# Read API
# ---------------------------------------------------------------------------

## Devuelve los intents pendientes del grupo sin consumirlos.
func get_pending_for_group(group_id: String) -> Array:
	var result: Array = []
	for i in _intents:
		if String(i.get("group_id", "")) == group_id:
			result.append(i)
	return result

func has_pending_for_group(group_id: String) -> bool:
	for i in _intents:
		if String(i.get("group_id", "")) == group_id:
			return true
	return false

func get_all_pending() -> Array:
	return _intents.duplicate()

func get_last_request_time(group_id: String) -> float:
	return float(_last_request_time_by_group.get(group_id, 0.0))


# ---------------------------------------------------------------------------
# Consume API
# ---------------------------------------------------------------------------

## Retira y devuelve todos los intents del grupo.
func consume_for_group(group_id: String) -> Array:
	var result: Array = []
	var remaining: Array = []
	for i in _intents:
		if String(i.get("group_id", "")) == group_id:
			result.append(i)
		else:
			remaining.append(i)
	_intents = remaining
	return result

func clear_all() -> void:
	_intents.clear()
	_last_request_time_by_group.clear()


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func serialize() -> Array:
	var out: Array = []
	for intent in _intents:
		var s: Dictionary = (intent as Dictionary).duplicate(true)
		var wp: Vector2 = s.get("world_pos", Vector2.ZERO)
		s["world_pos"] = {"x": wp.x, "y": wp.y}
		out.append(s)
	out.append({"__meta__": "extortion_queue_state", "last_request_time_by_group": _last_request_time_by_group.duplicate(true)})
	return out


func deserialize(data: Array) -> void:
	_intents.clear()
	_last_request_time_by_group.clear()
	for item in data:
		if not item is Dictionary:
			continue
		var i: Dictionary = (item as Dictionary).duplicate(true)
		if String(i.get("__meta__", "")) == "extortion_queue_state":
			_last_request_time_by_group = i.get("last_request_time_by_group", {}).duplicate(true)
			continue
		var wp = i.get("world_pos", {"x": 0.0, "y": 0.0})
		if wp is Dictionary:
			i["world_pos"] = Vector2(float(wp.get("x", 0.0)), float(wp.get("y", 0.0)))
		else:
			i["world_pos"] = Vector2.ZERO
		_intents.append(i)


func reset() -> void:
	_intents.clear()
	_last_request_time_by_group.clear()
