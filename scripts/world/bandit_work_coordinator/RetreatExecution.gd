extends RefCounted
class_name RetreatExecution


func should_retreat_on_attack_deny(reason: String) -> bool:
	return BanditRaidRuntimePolicy.should_retreat_on_attack_deny(reason)


func should_retreat_on_loot_deny(reason: String) -> bool:
	return BanditRaidRuntimePolicy.should_retreat_on_loot_deny(reason)


func execute(beh: BanditWorldBehavior) -> void:
	if beh != null and beh.has_method("force_return_home"):
		beh.call("force_return_home")
