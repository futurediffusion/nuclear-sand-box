extends RefCounted
class_name SnapshotRebuildNotificationDto

static func build(report: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"kind": "snapshot_rebuild_notification",
		"calls": int(report.get("calls", 0)),
		"warnings": (report.get("warnings", []) as Array).duplicate(true),
		"loaded_structure_count": int(report.get("loaded_structure_count", 0)),
		"tilemap_projection_applied": int(report.get("tilemap_projection_applied", 0)),
		"collider_projection_rebuilt": int(report.get("collider_projection_rebuilt", 0)),
		"spatial_projection_rebuilt": int(report.get("spatial_projection_rebuilt", 0)),
		"territory_rebuild_requests": int(report.get("territory_rebuild_requests", 0)),
	}
	return out
