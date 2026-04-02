extends RefCounted
class_name BWCAssaultStages

const RAID_STAGE_ENGAGE: String = "engage"
const RAID_STAGE_BREACH: String = "breach"
const RAID_STAGE_LOOT: String = "loot"
const RAID_STAGE_RETREAT: String = "retreat"
const RAID_STAGE_CLOSED: String = "closed"

const RAID_RESULT_SUCCESS: String = "success"
const RAID_RESULT_ABORT: String = "abort"
const RAID_RESULT_RETREAT: String = "retreat"

var _stage_by_member: Dictionary = {}
var _result_by_member: Dictionary = {}


func clear_member(member_id: String) -> void:
	_stage_by_member.erase(member_id)
	_result_by_member.erase(member_id)


func ensure_run(member_id: String) -> void:
	if _stage_by_member.has(member_id):
		return
	_stage_by_member[member_id] = RAID_STAGE_ENGAGE
	_result_by_member[member_id] = ""


func stage_of(member_id: String) -> String:
	return String(_stage_by_member.get(member_id, RAID_STAGE_ENGAGE))


func result_of(member_id: String, fallback: String = RAID_RESULT_ABORT) -> String:
	return String(_result_by_member.get(member_id, fallback))


func set_result(member_id: String, result: String) -> void:
	_result_by_member[member_id] = result


func transition(member_id: String, from_stage: String, to_stage: String) -> bool:
	var current: String = String(_stage_by_member.get(member_id, RAID_STAGE_ENGAGE))
	if current != from_stage:
		return false
	match from_stage:
		RAID_STAGE_ENGAGE:
			if to_stage != RAID_STAGE_BREACH:
				return false
		RAID_STAGE_BREACH:
			if to_stage != RAID_STAGE_LOOT and to_stage != RAID_STAGE_RETREAT:
				return false
		RAID_STAGE_LOOT:
			if to_stage != RAID_STAGE_RETREAT:
				return false
		RAID_STAGE_RETREAT:
			if to_stage != RAID_STAGE_CLOSED:
				return false
		_:
			return false
	_stage_by_member[member_id] = to_stage
	return true


func close(member_id: String, result: String) -> void:
	var stage: String = String(_stage_by_member.get(member_id, RAID_STAGE_ENGAGE))
	if stage != RAID_STAGE_CLOSED:
		if stage == RAID_STAGE_RETREAT:
			transition(member_id, RAID_STAGE_RETREAT, RAID_STAGE_CLOSED)
		else:
			_stage_by_member[member_id] = RAID_STAGE_CLOSED
	_result_by_member[member_id] = result
