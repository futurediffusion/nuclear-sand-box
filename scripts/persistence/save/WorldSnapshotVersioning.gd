extends RefCounted
class_name WorldSnapshotVersioning

const SandboxDomainLanguageScript := preload("res://scripts/core/SandboxDomainLanguage.gd")

const LATEST_SNAPSHOT_VERSION: int = 2
const MIN_SUPPORTED_SNAPSHOT_VERSION: int = 1

## Versioning + migration policy for canonical WorldSnapshot payloads.
##
## Rules:
## - Snapshot payloads MUST declare `snapshot_version`.
## - We support explicit migrations from MIN_SUPPORTED..LATEST.
## - Loading a version newer than LATEST is rejected.
## - Migrations are deterministic and side-effect free.

static func normalize_payload(payload: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var migration_path: Array[String] = []
	var working: Dictionary = payload.duplicate(true)

	var loaded_version: int = _extract_snapshot_version(working)
	if loaded_version <= 0:
		loaded_version = MIN_SUPPORTED_SNAPSHOT_VERSION
		warnings.append("missing_snapshot_version_assumed_v%d" % MIN_SUPPORTED_SNAPSHOT_VERSION)

	if loaded_version < MIN_SUPPORTED_SNAPSHOT_VERSION:
		return {
			"ok": false,
			"loaded_snapshot_version": loaded_version,
			"target_snapshot_version": LATEST_SNAPSHOT_VERSION,
			"migration_path": migration_path,
			"warnings": ["unsupported_snapshot_version_too_old"],
			"normalized_payload": {},
		}

	if loaded_version > LATEST_SNAPSHOT_VERSION:
		return {
			"ok": false,
			"loaded_snapshot_version": loaded_version,
			"target_snapshot_version": LATEST_SNAPSHOT_VERSION,
			"migration_path": migration_path,
			"warnings": ["unsupported_snapshot_version_too_new"],
			"normalized_payload": {},
		}

	var cursor: int = loaded_version
	while cursor < LATEST_SNAPSHOT_VERSION:
		var next_v: int = cursor + 1
		var migration_result: Dictionary = _apply_migration(cursor, next_v, working)
		working = migration_result.get("payload", working) as Dictionary
		var migration_id: String = String(migration_result.get("migration_id", "v%d_to_v%d" % [cursor, next_v]))
		migration_path.append(migration_id)
		for warning in migration_result.get("warnings", []):
			warnings.append(String(warning))
		cursor = next_v

	working["snapshot_version"] = LATEST_SNAPSHOT_VERSION
	return {
		"ok": true,
		"loaded_snapshot_version": loaded_version,
		"target_snapshot_version": LATEST_SNAPSHOT_VERSION,
		"migration_path": migration_path,
		"warnings": warnings,
		"migration_applied": not migration_path.is_empty(),
		"normalized_payload": working,
	}


static func _extract_snapshot_version(payload: Dictionary) -> int:
	if payload.has("snapshot_version"):
		return int(payload.get("snapshot_version", 0))
	# Backward-compatible fallback for old saves that only had `version`
	if payload.has("version"):
		return int(payload.get("version", 0))
	return 0


static func _apply_migration(from_version: int, to_version: int, payload: Dictionary) -> Dictionary:
	if from_version == 1 and to_version == 2:
		return _migrate_v1_to_v2(payload)
	return {
		"payload": payload,
		"migration_id": "noop_v%d_to_v%d" % [from_version, to_version],
		"warnings": ["missing_migration_handler_v%d_to_v%d" % [from_version, to_version]],
	}


static func _migrate_v1_to_v2(payload: Dictionary) -> Dictionary:
	var migrated: Dictionary = payload.duplicate(true)
	var persistence_meta: Dictionary = {}
	var meta_raw: Variant = migrated.get("persistence_meta", {})
	if meta_raw is Dictionary:
		persistence_meta = (meta_raw as Dictionary).duplicate(true)
	persistence_meta["snapshot_contract"] = "canonical_world_snapshot_v2"
	persistence_meta["canonical_snapshot_path"] = true
	persistence_meta["domain_language"] = SandboxDomainLanguageScript.get_snapshot()
	persistence_meta["migration_steps"] = ["v1_to_v2_persistence_meta"]
	persistence_meta["runtime_derived_sections"] = [
		"projections",
		"telemetry",
		"runtime_caches",
	]
	persistence_meta["compat_legacy_hints"] = {
		"legacy_snapshot_key": "version",
		"legacy_envelope_key": "world_snapshot_state",
	}
	if not persistence_meta.has("migration_origin"):
		persistence_meta["migration_origin"] = "v1"
	migrated["persistence_meta"] = persistence_meta
	return {
		"payload": migrated,
		"migration_id": "v1_to_v2_persistence_meta",
		"warnings": [],
	}
