extends RefCounted
class_name WorldCadenceFacade

var _coordinator: WorldCadenceCoordinator

func setup(ctx: Dictionary) -> WorldCadenceCoordinator:
	_coordinator = ctx.get("cadence", WorldCadenceCoordinator.new())
	_coordinator.configure_lane(&"short_pulse", 0.12, 0.15)
	_coordinator.configure_lane(&"medium_pulse", 0.50, 0.42)
	_coordinator.configure_lane(&"director_pulse", 0.12, 0.67)
	_coordinator.configure_lane(&"bandit_behavior_tick", BanditTuning.behavior_tick_interval(), 0.35)
	_coordinator.configure_lane(
		&"bandit_group_scan_slice",
		BanditTuning.group_scan_interval() / float(maxi(BanditGroupIntel.GROUP_SCAN_SLICE_COUNT, 1)),
		0.24,
		WorldCadenceCoordinator.DEFAULT_MAX_CATCHUP,
		1.5,
		maxi(1, int(ceil(12.0 / float(maxi(BanditGroupIntel.GROUP_SCAN_SLICE_COUNT, 1)))))
	)
	_coordinator.configure_lane(&"chunk_pulse", float(ctx.get("chunk_check_interval", 0.3)), 0.68)
	_coordinator.configure_lane(&"autosave", float(ctx.get("autosave_interval", 120.0)), 0.31, 1)
	_coordinator.configure_lane(
		&"settlement_base_scan",
		SettlementIntel.BASE_RESCAN_INTERVAL,
		SettlementIntel.BASE_SCAN_PHASE_RATIO,
		1,
		2.0,
		SettlementIntel.BASE_SCAN_DOOR_BUDGET_PER_PULSE
	)
	_coordinator.configure_lane(&"settlement_workbench_scan", SettlementIntel.WORKBENCH_RESCAN_INTERVAL, SettlementIntel.WORKBENCH_SCAN_PHASE_RATIO, 1)
	return _coordinator

func get_debug_snapshot() -> Dictionary:
	if _coordinator == null:
		return {"configured": false}
	return {"configured": true}
