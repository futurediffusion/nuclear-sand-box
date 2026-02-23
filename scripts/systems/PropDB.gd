extends Node
class_name PropDB

static func scene_path(prop_id: String) -> String:
	match prop_id:
		"barrel":
			return "res://scenes/props/Barrel.tscn"
		"table":
			return "res://scenes/props/Table.tscn"
		"counter":
			return "res://scenes/props/Counter.tscn"
		_:
			return ""
