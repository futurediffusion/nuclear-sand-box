extends Node

const BOOT_TRACE := true

@export var enabled := BOOT_TRACE
@export var safe_mode := true
@export var disable_vfx_pooling := false
@export var disable_wall_occlusion := false
@export var disable_enemy_cache := false
@export var categories := {
	"boot": BOOT_TRACE,
	"audio": false,
	"events": false,
	"ai": false,
	"wall": false,
	"inv": false,
	"chunk": true,
	"spawn": false,
	"save": false,
}

func log(cat: String, msg: String) -> void:
	if not enabled:
		return
	if categories.has(cat) and not categories[cat]:
		return
	print("[", cat.to_upper(), "] ", msg)
