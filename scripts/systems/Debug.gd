extends Node
class_name DebugSystem

const BOOT_TRACE := true

@export var enabled := BOOT_TRACE
@export var diagnostic_mode := false
@export var safe_mode := true
@export var dev_cheats_enabled := OS.is_debug_build()
@export var ghost_mode: bool = false   # /inv — player invisible a enemigos y sin daño
@export var disable_vfx_pooling := false
@export var disable_wall_occlusion := false
@export var disable_enemy_cache := false
@export var use_legacy_wall_collision: bool = false
@export var test_density_enabled := false # Disable before release by setting Debug.test_density_enabled = false in res://scripts/Debug.gd before release builds.
@export var test_density_extra_copper_per_chunk_load := 4
@export var test_density_extra_bandit_camps_per_chunk_load := 1
@export var categories := {
	"boot": false,
	"audio": false,
	"events": false,
	"ai": false,
	"wall": false,
	"inv": false,
	"chunk": false,
	"spawn": false,
	"save": false,
	"copper": false,
	"loot": false,
	"npc_data": false,
	"npc_lite": false,
	"bandit_ai": false,
	"bandit_pipeline": false,
	"bandit_lod": false,
	"bandit_group": false,
	"intel": false,
	"camp_stash": false,
	"sentinel": false,
	"authority": false,
	"world": false,
	"territory": false,
	"raid": false,
	"resource_repop": false,
	"npc_path": false,
	"grass": false,
	"faction_hostility": false,
	"crafting": false,
	"chunk_perf": false,
	"ground": false,
	"perf_telemetry": false,
	"faction_eradication": false,
	"placement_react": false,
	"item_db": false,
	"ui_mode": false,
	"occlusion": false,
	"item_drop": false,
	"commands": false,
	"stone": false,
	"bandit_intel": false,
}
var _sample_counters: Dictionary = {}

func is_enabled(cat: String) -> bool:
	if not enabled:
		return false
	if categories.has(cat) and not categories[cat]:
		return false
	return true

func is_diagnostic_mode() -> bool:
	return diagnostic_mode

func should_sample(cat: String, sample_key: String, every_n: int) -> bool:
	if every_n <= 1:
		return is_enabled(cat)
	if not enabled:
		return false
	if categories.has(cat) and not categories[cat]:
		return false
	if diagnostic_mode:
		return true
	var prev: int = int(_sample_counters.get(sample_key, 0))
	var next: int = prev + 1
	_sample_counters[sample_key] = next
	return (next % every_n) == 0

func is_ghost_mode() -> bool:
	return ghost_mode

func log(cat: String, msg: String) -> void:
	if not is_enabled(cat):
		return
	print("[", cat.to_upper(), "] ", msg)
