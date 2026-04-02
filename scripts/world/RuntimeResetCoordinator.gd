class_name RuntimeResetCoordinator
extends RefCounted

## Runtime reset boundary:
## Encapsulates "what resets" and "in what sequence" for new game bootstrap.
func reset_for_new_game() -> void:
	PlacementSystem.clear_runtime_instances()
	FactionSystem.reset()
	SiteSystem.reset()
	NpcProfileSystem.reset()
	BanditGroupMemory.reset()
	ExtortionQueue.reset()
	RunClock.reset()
	WorldTime.load_save_data({})
	FactionHostilityManager.reset()
