extends RefCounted
class_name IntentPublicationRecordDto

const INTENT_KIND_ASSAULT_TARGET := "assault_target"
const DEFAULT_SOURCE := "opportunistic"

static func build_assault_target_record(group_id: String, anchor: Vector2, target_pos: Vector2,
		reason: String, source: String, priority: int, created_at: float, ttl_seconds: float) -> Dictionary:
	var ttl: float = maxf(0.0, ttl_seconds)
	var expires_at: float = created_at + ttl
	return {
		"kind": INTENT_KIND_ASSAULT_TARGET,
		"group_id": group_id,
		"anchor": anchor,
		"target_pos": target_pos,
		"reason": reason,
		"source": source if source != "" else DEFAULT_SOURCE,
		"priority": maxi(priority, 0),
		"created_at": created_at,
		"ttl": ttl,
		"expires_at": expires_at,
		"lifecycle": {
			"created_at": created_at,
			"ttl_seconds": ttl,
			"expires_at": expires_at,
		},
	}

static func get_expires_at(record: Dictionary) -> float:
	var lifecycle: Dictionary = record.get("lifecycle", {}) as Dictionary
	if not lifecycle.is_empty():
		return float(lifecycle.get("expires_at", 0.0))
	return float(record.get("expires_at", 0.0))

static func with_target_update(record: Dictionary, new_anchor: Vector2, new_target: Vector2,
		now: float, ttl_seconds: float) -> Dictionary:
	var out: Dictionary = record.duplicate(true)
	out["anchor"] = new_anchor
	out["target_pos"] = new_target
	out["expires_at"] = now + maxf(0.0, ttl_seconds)
	var lifecycle: Dictionary = out.get("lifecycle", {}) as Dictionary
	if lifecycle.is_empty():
		lifecycle = {}
	lifecycle["expires_at"] = now + maxf(0.0, ttl_seconds)
	if not lifecycle.has("created_at"):
		lifecycle["created_at"] = now
	if not lifecycle.has("ttl_seconds"):
		lifecycle["ttl_seconds"] = maxf(0.0, ttl_seconds)
	out["lifecycle"] = lifecycle
	return out
