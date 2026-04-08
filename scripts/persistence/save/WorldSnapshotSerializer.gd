extends RefCounted
class_name WorldSnapshotSerializer

const WorldSnapshot := preload("res://scripts/core/WorldSnapshot.gd")

## Serializer for the canonical WorldSnapshot root DTO.
## Keeps disk payload conversion isolated from runtime adapter concerns.

static func serialize(snapshot: WorldSnapshot) -> Dictionary:
	if snapshot == null:
		return {}
	return snapshot.to_dict()

static func deserialize(payload: Dictionary) -> WorldSnapshot:
	return WorldSnapshot.from_dict(payload)
