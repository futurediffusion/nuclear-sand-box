class_name ArchitectureContractValidator
extends RefCounted

const _CADENCE_PATH := "res://scripts/world/WorldCadenceCoordinator.gd"
const _SPATIAL_PATH := "res://scripts/world/WorldSpatialIndex.gd"

static func validate_source_contracts() -> Dictionary:
	var failures: Array[String] = []
	var cadence_src := _read_text(_CADENCE_PATH)
	var spatial_src := _read_text(_SPATIAL_PATH)

	if cadence_src == "":
		failures.append("missing cadence source")
	else:
		if cadence_src.find("func when_to_run(") == -1:
			failures.append("cadence must expose when_to_run")
		if cadence_src.find("func when_due(") == -1:
			failures.append("cadence must expose when_due")

	if spatial_src == "":
		failures.append("missing spatial index source")
	else:
		if spatial_src.find("func get_runtime_nodes_near(") == -1:
			failures.append("spatial index must expose runtime where/query")
		if spatial_src.find("func get_placeables_in_tile_rect(") == -1:
			failures.append("spatial index must expose persistent where/query")
		if spatial_src.find("func rebuild_placeables_cache_from_truth(") == -1:
			failures.append("spatial index must expose rebuild from canonical truth")
		if spatial_src.find("func try_write_placeables_cache(") == -1:
			failures.append("spatial index must expose blocked semantic-write API")

		# Domain truth must live in domain owners, not inside the index.
		for forbidden in [
			"func placeable_blocks_movement(",
			"func is_storage_item_id(",
			"const BLOCKING_EXCLUDED_ITEM_IDS",
			"const STORAGE_ITEM_IDS",
			"func set_placeables_cache_entry(",
			"func upsert_placeables_cache_entry(",
		]:
			if spatial_src.find(forbidden) != -1:
				failures.append("spatial index leaked semantic rule: %s" % forbidden)

	return {
		"ok": failures.is_empty(),
		"failures": failures,
	}


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
