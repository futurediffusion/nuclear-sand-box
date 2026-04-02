extends RefCounted
class_name BWCCooldowns

var _attack_next_at: Dictionary = {}
var _loot_next_at: Dictionary = {}
var _breach_resolved_at: Dictionary = {}


func clear_member(member_id: String) -> void:
	_attack_next_at.erase(member_id)
	_loot_next_at.erase(member_id)
	_breach_resolved_at.erase(member_id)


func attack_next_at(member_id: String) -> float:
	return float(_attack_next_at.get(member_id, 0.0))


func loot_next_at(member_id: String) -> float:
	return float(_loot_next_at.get(member_id, 0.0))


func breach_resolved_at(member_id: String) -> float:
	return float(_breach_resolved_at.get(member_id, 0.0))


func set_attack_next_at(member_id: String, next_at: float) -> void:
	_attack_next_at[member_id] = next_at


func set_loot_next_at(member_id: String, next_at: float) -> void:
	_loot_next_at[member_id] = next_at


func set_breach_resolved_at(member_id: String, at: float) -> void:
	_breach_resolved_at[member_id] = at
