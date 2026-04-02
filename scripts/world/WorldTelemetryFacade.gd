extends RefCounted
class_name WorldTelemetryFacade

var _telemetry: WorldSimTelemetry

func setup(ctx: Dictionary) -> WorldSimTelemetry:
	_telemetry = WorldSimTelemetry.new()
	_telemetry.setup(ctx)
	return _telemetry

func get_debug_snapshot() -> Dictionary:
	if _telemetry == null:
		return {"enabled": false}
	return _telemetry.get_debug_snapshot()

func dump_debug_summary() -> String:
	if _telemetry == null:
		return "WORLD SIM\n- telemetry: unavailable"
	return _telemetry.dump_debug_summary()

func build_overlay_lines() -> PackedStringArray:
	if _telemetry == null:
		return PackedStringArray()
	return _telemetry.build_overlay_lines()
