extends RefCounted
class_name WorldSnapshotSerializer


## Serializer for the canonical WorldSnapshot root DTO.
## Keeps disk payload conversion isolated from runtime adapter concerns.

static func serialize(snapshot: WorldSnapshot) -> Dictionary:
	if snapshot == null:
		return {}
	return snapshot.to_dict()

static func deserialize(payload: Dictionary) -> WorldSnapshot:
	var report: Dictionary = deserialize_with_report(payload)
	var snapshot_raw: Variant = report.get("snapshot", null)
	if snapshot_raw is WorldSnapshot:
		return snapshot_raw as WorldSnapshot
	return WorldSnapshot.new()

static func deserialize_with_report(payload: Dictionary) -> Dictionary:
	var normalized: Dictionary = WorldSnapshotVersioning.normalize_payload(payload)
	if not bool(normalized.get("ok", false)):
		return {
			"ok": false,
			"snapshot": null,
			"loaded_snapshot_version": int(normalized.get("loaded_snapshot_version", 0)),
			"target_snapshot_version": int(normalized.get("target_snapshot_version", WorldSnapshotVersioning.LATEST_SNAPSHOT_VERSION)),
			"migration_path": normalized.get("migration_path", []),
			"warnings": normalized.get("warnings", []),
			"migration_applied": false,
		}

	var normalized_payload: Dictionary = normalized.get("normalized_payload", {}) as Dictionary
	var snapshot: WorldSnapshot = WorldSnapshot.from_dict(normalized_payload)
	return {
		"ok": true,
		"snapshot": snapshot,
		"loaded_snapshot_version": int(normalized.get("loaded_snapshot_version", snapshot.snapshot_version)),
		"target_snapshot_version": int(normalized.get("target_snapshot_version", snapshot.snapshot_version)),
		"migration_path": normalized.get("migration_path", []),
		"warnings": normalized.get("warnings", []),
		"migration_applied": bool(normalized.get("migration_applied", false)),
	}
