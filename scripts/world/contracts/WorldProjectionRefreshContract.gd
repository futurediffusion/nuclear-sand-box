extends RefCounted
class_name WorldProjectionRefreshContract

# Typed contract for refresh + projection triggers after wall mutations.
# "Projection" here refers to side projections fed from wall state updates
# (e.g. settlement/base dirty scans and territory dirty marks).

func refresh_for_tiles(_tile_positions: Array[Vector2i]) -> void:
	pass
