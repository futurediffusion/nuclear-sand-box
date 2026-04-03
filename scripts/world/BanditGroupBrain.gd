extends RefCounted
class_name BanditGroupBrain

const BodyguardControllerScript := preload("res://scripts/world/BodyguardController.gd")
const ScavengerControllerScript := preload("res://scripts/world/ScavengerController.gd")

const MACRO_STATES: Array[String] = [
	"idle",
	"patrol",
	"alerted",
	"hunting",
	"raiding",
	"working",
	"retreating",
	"depositing",
	"defending_camp",
]

var _bodyguard_controller: BodyguardController = BodyguardControllerScript.new()
var _scavenger_controller: ScavengerController = ScavengerControllerScript.new()


func assign_group_orders(group_id: String, members: Array, group_ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if group_id == "" or members.is_empty():
		return out
	var macro_state: String = _resolve_macro_state(group_ctx)
	BanditGroupMemory.bb_write_group_mode(group_id, macro_state, "group_brain")
	for item in members:
		if not (item is Dictionary):
			continue
		var member: Dictionary = item as Dictionary
		var member_id: String = String(member.get("member_id", ""))
		if member_id == "":
			continue
		var role: String = String(member.get("role", "scavenger"))
		var order: Dictionary = _build_order_for_member(role, group_ctx, member)
		order["macro_state"] = macro_state
		out[member_id] = order
		BanditGroupMemory.bb_set_assignment(group_id, member_id, order, 2.0, "group_brain")
	return out


func _resolve_macro_state(group_ctx: Dictionary) -> String:
	var requested: String = String(group_ctx.get("group_mode", "idle"))
	if requested in MACRO_STATES:
		return requested
	match requested:
		"extorting":
			return "raiding"
		"returning", "hold":
			return "retreating"
		_:
			return "idle"


func _build_order_for_member(role: String, group_ctx: Dictionary, member_ctx: Dictionary) -> Dictionary:
	var merged: Dictionary = group_ctx.duplicate(true)
	merged["macro_state"] = _resolve_macro_state(group_ctx)
	for key in member_ctx.keys():
		merged[key] = member_ctx[key]
	match role:
		"leader":
			return _build_leader_order(merged)
		"bodyguard":
			return _bodyguard_controller.build_order(merged)
		_:
			return _scavenger_controller.build_order(merged)


func _build_leader_order(ctx: Dictionary) -> Dictionary:
	var macro_state: String = String(ctx.get("macro_state", _resolve_macro_state(ctx)))
	var interest_pos: Vector2 = ctx.get("interest_pos", Vector2.ZERO)
	match macro_state:
		"retreating", "depositing":
			return {"order": "return_home"}
		"working":
			return {"order": "move_to_target", "target_pos": interest_pos if interest_pos != Vector2.ZERO else ctx.get("home_pos", Vector2.ZERO)}
		"hunting", "raiding", "alerted":
			return {"order": "attack_target", "target_pos": interest_pos}
		_:
			return {"order": "follow_slot", "slot_name": "frontal"}
