extends Node
class_name DebugSystem

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
	"copper": false,
	"loot": false,
}

static func _get_singleton() -> DebugSystem:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("Debug") as DebugSystem

static func is_enabled(cat: String) -> bool:
	var singleton := _get_singleton()
	if singleton == null:
		return false
	if not singleton.enabled:
		return false
	if singleton.categories.has(cat) and not singleton.categories[cat]:
		return false
	return true

static func log(cat: String, msg: String) -> void:
	if not is_enabled(cat):
		return
	print("[", cat.to_upper(), "] ", msg)
