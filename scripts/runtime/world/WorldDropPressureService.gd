extends RefCounted
class_name WorldDropPressureService

const DROP_PRESSURE_NORMAL: StringName = &"normal"
const DROP_PRESSURE_HIGH: StringName = &"high"
const DROP_PRESSURE_CRITICAL: StringName = &"critical"

const DROP_PRESSURE_STAGE_NORMAL: int = 0
const DROP_PRESSURE_STAGE_HIGH: int = 5
const DROP_PRESSURE_STAGE_CRITICAL: int = 6

var _world_spatial_index: WorldSpatialIndex
var _loot_system: Node
var _now_msec_provider: Callable = Callable(Time, "get_ticks_msec")

var _high_item_drop_count: int = 140
var _critical_item_drop_count: int = 240
var _high_orphan_ttl_sec: float = 25.0

var _snapshot: Dictionary = {
	"level": String(DROP_PRESSURE_NORMAL),
	"item_drop_count": 0,
	"drop_pressure_stage": DROP_PRESSURE_STAGE_NORMAL,
}

func setup(ctx: Dictionary) -> void:
	_world_spatial_index = ctx.get("world_spatial_index", null) as WorldSpatialIndex
	_loot_system = ctx.get("loot_system", null) as Node
	_high_item_drop_count = int(ctx.get("high_item_drop_count", _high_item_drop_count))
	_critical_item_drop_count = int(ctx.get("critical_item_drop_count", _critical_item_drop_count))
	_high_orphan_ttl_sec = float(ctx.get("high_orphan_ttl_sec", _high_orphan_ttl_sec))
	var now_msec_provider: Callable = ctx.get("now_msec_provider", Callable()) as Callable
	if now_msec_provider.is_valid():
		_now_msec_provider = now_msec_provider

func update_snapshot() -> void:
	if _world_spatial_index == null:
		return
	var item_drop_count: int = _world_spatial_index.get_runtime_node_count(WorldSpatialIndex.KIND_ITEM_DROP)
	var level: StringName = _get_level_for_count(item_drop_count)
	var stage: int = DROP_PRESSURE_STAGE_NORMAL
	if level == DROP_PRESSURE_HIGH:
		stage = DROP_PRESSURE_STAGE_HIGH
	elif level == DROP_PRESSURE_CRITICAL:
		stage = DROP_PRESSURE_STAGE_CRITICAL
	_snapshot = {
		"level": String(level),
		"item_drop_count": item_drop_count,
		"drop_pressure_stage": stage,
		"force_compact_deposit": level != DROP_PRESSURE_NORMAL,
		"high_orphan_ttl_sec": _high_orphan_ttl_sec if level != DROP_PRESSURE_NORMAL else 0.0,
		"pickup_budget_scale": 0.80 if level != DROP_PRESSURE_NORMAL else 1.0,
		"updated_at_msec": _resolve_now_msec(),
	}
	_push_snapshot_to_dependents()

func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func scale_int(base_value: int, high_mult: float, critical_mult: float) -> int:
	var level: String = String(_snapshot.get("level", String(DROP_PRESSURE_NORMAL)))
	var scaled: float = float(base_value)
	if level == String(DROP_PRESSURE_HIGH):
		scaled *= maxf(1.0, high_mult)
	elif level == String(DROP_PRESSURE_CRITICAL):
		scaled *= maxf(1.0, critical_mult)
	return maxi(int(ceil(scaled)), 1)

func scale_float(base_value: float, high_mult: float, critical_mult: float) -> float:
	var level: String = String(_snapshot.get("level", String(DROP_PRESSURE_NORMAL)))
	if level == String(DROP_PRESSURE_HIGH):
		return base_value * maxf(1.0, high_mult)
	if level == String(DROP_PRESSURE_CRITICAL):
		return base_value * maxf(1.0, critical_mult)
	return base_value

func _get_level_for_count(item_drop_count: int) -> StringName:
	if item_drop_count >= maxi(_critical_item_drop_count, _high_item_drop_count + 1):
		return DROP_PRESSURE_CRITICAL
	if item_drop_count >= maxi(0, _high_item_drop_count):
		return DROP_PRESSURE_HIGH
	return DROP_PRESSURE_NORMAL

func _push_snapshot_to_dependents() -> void:
	if _loot_system != null and _loot_system.has_method("set_drop_pressure_snapshot"):
		_loot_system.call("set_drop_pressure_snapshot", _snapshot)

func _resolve_now_msec() -> int:
	if _now_msec_provider.is_valid():
		return int(_now_msec_provider.call())
	return Time.get_ticks_msec()
