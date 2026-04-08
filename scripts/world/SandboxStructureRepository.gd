extends RefCounted
class_name SandboxStructureRepository

const SandboxStructureContractScript := preload("res://scripts/domain/building/SandboxStructureContract.gd")

var structural_wall_persistence: StructuralWallPersistence

func setup(ctx: Dictionary) -> void:
	structural_wall_persistence = ctx.get("structural_wall_persistence", null) as StructuralWallPersistence

func list_structures_in_chunk(chunk_pos: Vector2i, include_placeables: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in WorldSave.list_player_walls_in_chunk(chunk_pos.x, chunk_pos.y):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw as Dictionary
		var tile_raw: Variant = row.get("tile", Vector2i(-1, -1))
		if not (tile_raw is Vector2i):
			continue
		var hp: int = int(row.get("hp", 0))
		if hp <= 0:
			continue
		out.append(SandboxStructureContractScript.create_player_wall_record(
			chunk_pos,
			tile_raw as Vector2i,
			hp,
			{ "buildable_id": BuildableCatalog.ID_WALLWOOD },
			hp
		))

	if structural_wall_persistence != null:
		out.append_array(structural_wall_persistence.load_chunk_structure_records(chunk_pos))

	if include_placeables:
		for entry in WorldSave.get_placed_entities_in_chunk(chunk_pos.x, chunk_pos.y):
			var uid: String = String(entry.get("uid", "")).strip_edges()
			if uid == "":
				continue
			var tile_pos := Vector2i(int(entry.get("tile_pos_x", 0)), int(entry.get("tile_pos_y", 0)))
			var item_id: String = String(entry.get("item_id", "")).strip_edges()
			var persisted: Dictionary = WorldSave.get_placed_entity_data(uid)
			var max_hp: int = maxi(1, int(persisted.get("max_hp", persisted.get("hp", 1))))
			var hp: int = clampi(int(persisted.get("hp", max_hp)), 0, max_hp)
			var metadata: Dictionary = {
				"entry": entry.duplicate(true),
				"breakable": bool(persisted.get("breakable", true)),
			}
			out.append(SandboxStructureContractScript.create_placeable_record(
				chunk_pos,
				tile_pos,
				uid,
				item_id,
				hp,
				max_hp,
				metadata
			))
	return out
