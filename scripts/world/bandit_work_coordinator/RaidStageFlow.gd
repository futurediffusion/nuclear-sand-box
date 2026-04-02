extends RefCounted
class_name RaidStageFlow

const BWCAssaultStagesScript := preload("res://scripts/world/bandit_work_coordinator/BWCAssaultStages.gd")


func ensure_run(stages: BWCAssaultStages, member_id: String) -> void:
	if stages != null:
		stages.ensure_run(member_id)


func stage_of(stages: BWCAssaultStages, member_id: String) -> String:
	if stages == null:
		return BWCAssaultStagesScript.RAID_STAGE_CLOSED
	return stages.stage_of(member_id)


func is_closed(stage: String) -> bool:
	return stage == BWCAssaultStagesScript.RAID_STAGE_CLOSED


func transition(stages: BWCAssaultStages, member_id: String, from_stage: String, to_stage: String) -> bool:
	if stages == null:
		return false
	return stages.transition(member_id, from_stage, to_stage)


func set_result(stages: BWCAssaultStages, member_id: String, result: String) -> void:
	if stages != null:
		stages.set_result(member_id, result)


func result_of(stages: BWCAssaultStages, member_id: String, fallback: String) -> String:
	if stages == null:
		return fallback
	return stages.result_of(member_id, fallback)


func close(stages: BWCAssaultStages, member_id: String, result: String) -> void:
	if stages != null:
		stages.close(member_id, result)


func close_payload(result: String, reason: String, closed_stage: String) -> Dictionary:
	return {
		"allow": result != BWCAssaultStagesScript.RAID_RESULT_ABORT,
		"reason": reason,
		"stage": closed_stage,
		"stage_closed": true,
		"result": result,
	}
