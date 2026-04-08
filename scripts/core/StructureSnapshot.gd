extends RefCounted
class_name StructureSnapshot

## Canonical snapshot DTO for a single saveable structure/building record.
##
## Canonical:
## - structure identity + spatial ownership (chunk/tile)
## - durability (hp/max_hp)
## - domain metadata required to reconstruct building state
##
## Derived / non-canonical:
## - tilemap cells, collider bodies, nav/index entries, runtime node references

var structure_id: String = ""
var kind: String = ""
var chunk_pos: Vector2i = Vector2i.ZERO
var tile_pos: Vector2i = Vector2i.ZERO
var hp: int = 0
var max_hp: int = 0
var metadata: Dictionary = {}

static func from_dict(data: Dictionary) -> StructureSnapshot:
	var snapshot := StructureSnapshot.new()
	snapshot.structure_id = String(data.get("structure_id", ""))
	snapshot.kind = String(data.get("kind", ""))
	snapshot.chunk_pos = data.get("chunk_pos", Vector2i.ZERO)
	snapshot.tile_pos = data.get("tile_pos", Vector2i.ZERO)
	snapshot.hp = int(data.get("hp", 0))
	snapshot.max_hp = int(data.get("max_hp", snapshot.hp))
	var metadata_raw: Variant = data.get("metadata", {})
	if metadata_raw is Dictionary:
		snapshot.metadata = (metadata_raw as Dictionary).duplicate(true)
	return snapshot

func to_dict() -> Dictionary:
	return {
		"structure_id": structure_id,
		"kind": kind,
		"chunk_pos": chunk_pos,
		"tile_pos": tile_pos,
		"hp": hp,
		"max_hp": max_hp,
		"metadata": metadata.duplicate(true),
	}
