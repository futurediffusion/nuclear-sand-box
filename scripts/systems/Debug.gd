extends Node

@export var enabled := false
@export var categories := {
	"audio": false,
	"events": false,
	"ai": false,
	"wall": false,
	"inv": false,
	"chunk": false,
}

func log(cat: String, msg: String) -> void:
	if not enabled:
		return
	if categories.has(cat) and not categories[cat]:
		return
	print("[", cat.to_upper(), "] ", msg)
