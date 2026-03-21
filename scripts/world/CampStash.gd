class_name CampStash
extends Node2D

## Physical stash for bandit camps.
## Add as a child of the world scene near the camp's home_world_pos.
## Implements try_insert_item / is_position_nearby so BanditBehaviorLayer
## can find and use it exactly like a ContainerPlaceable chest.

const BARREL_SPRITE: Texture2D  = preload("res://art/props/barrel.png")
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")

## Items per barrel — matches ContainerPlaceable defaults (15 slots × 10 max_stack)
const BARREL_CAPACITY: int   = 150
## NPC deposit radius (pixels)
const NEARBY_RADIUS: float   = 80.0
## Hits to break one barrel
const BARREL_MAX_HITS: int   = 4
## Materials consumed from storage to auto-craft a new barrel
const BARREL_RECIPE: Dictionary = {"wood": 4}

@export var barrel_spacing: float = 24.0

## Set after adding to scene (used for wealth tracking in BanditGroupMemory)
var group_id: String = ""

# ── Storage ──────────────────────────────────────────────────────────────────
var _storage: Dictionary = {}   # item_id -> amount
var _total_stored: int   = 0

# ── Barrel state ─────────────────────────────────────────────────────────────
var _barrel_count: int    = 1
var _barrel_hits: Array   = []   # Array[int], one per barrel
var _barrel_sprites: Array = []  # Array[Sprite2D], one per barrel


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("camp_stash")
	_sync_barrel_visuals()


# ---------------------------------------------------------------------------
# Public API — duck-typed compatibility with ContainerPlaceable
# ---------------------------------------------------------------------------

func is_position_nearby(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= NEARBY_RADIUS


## Insert up to [amount] of [item_id]. Returns how many were accepted (0 = full).
func try_insert_item(item_id: String, amount: int) -> int:
	if item_id == "" or amount <= 0:
		return 0

	var capacity := _barrel_count * BARREL_CAPACITY
	var space    := capacity - _total_stored
	if space <= 0:
		return 0

	var inserted := mini(amount, space)
	_storage[item_id] = _storage.get(item_id, 0) + inserted
	_total_stored     += inserted

	# Band wealth
	if group_id != "" and BanditGroupMemory.has_group(group_id):
		var sell_val := ItemDB.get_sell_price(item_id, 1)
		BanditGroupMemory.add_wealth(group_id, sell_val * inserted)

	_try_autocraft_barrel()
	_sync_barrel_visuals()

	Debug.log("camp_stash", "[CampStash] +%d %s  total=%d/%d  barrels=%d  wealth=%.0f" % [
		inserted, item_id, _total_stored, _barrel_count * BARREL_CAPACITY, _barrel_count,
		BanditGroupMemory.get_wealth(group_id)])
	return inserted


# ---------------------------------------------------------------------------
# Hit / destruction
# ---------------------------------------------------------------------------

## Called by player or system hitting the stash directly — damages last barrel.
func hit(_by: Node) -> void:
	if _barrel_count > 0:
		_hit_barrel(_barrel_count - 1)


func _hit_barrel(idx: int) -> void:
	if idx < 0 or idx >= _barrel_hits.size():
		return
	_barrel_hits[idx] = int(_barrel_hits[idx]) + 1
	var spr := _barrel_sprites[idx] as Node2D
	if spr != null and is_instance_valid(spr):
		_shake(spr)
	if int(_barrel_hits[idx]) >= BARREL_MAX_HITS:
		_destroy_barrel(idx)


func _destroy_barrel(idx: int) -> void:
	# Determine how many items this barrel holds
	var full_barrels := maxi(0, _barrel_count - 1)
	var items_in_barrel: int
	if _barrel_count <= 1:
		items_in_barrel = _total_stored
	elif idx == _barrel_count - 1:
		# Last (possibly partial) barrel
		items_in_barrel = maxi(0, _total_stored - full_barrels * BARREL_CAPACITY)
	else:
		items_in_barrel = BARREL_CAPACITY

	_drop_from_storage(items_in_barrel)

	_barrel_count = maxi(0, _barrel_count - 1)
	Debug.log("camp_stash", "[CampStash] barrel %d destroyed, remaining barrels=%d" % [idx, _barrel_count])

	_sync_barrel_visuals()

	if _barrel_count == 0 and _total_stored == 0:
		queue_free()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _try_autocraft_barrel() -> void:
	if _total_stored < _barrel_count * BARREL_CAPACITY:
		return
	for res_id in BARREL_RECIPE:
		if _storage.get(res_id, 0) < int(BARREL_RECIPE[res_id]):
			return   # not enough materials
	# Consume
	for res_id in BARREL_RECIPE:
		var cost: int = int(BARREL_RECIPE[res_id])
		_storage[res_id] -= cost
		_total_stored     -= cost
		if int(_storage[res_id]) <= 0:
			_storage.erase(res_id)
	_barrel_count += 1
	Debug.log("camp_stash", "[CampStash] auto-crafted barrel #%d" % _barrel_count)


func _drop_from_storage(budget: int) -> void:
	if budget <= 0:
		return
	var world := get_parent() if get_parent() != null else get_tree().current_scene
	var overrides := {"drop_scene": ITEM_DROP_SCENE, "scatter_mode": "prop_radial_short"}
	var remaining := budget
	for item_id in _storage.keys().duplicate():   # duplicate: safe iteration while mutating
		if remaining <= 0:
			break
		var stored: int = _storage.get(item_id, 0)
		if stored <= 0:
			continue
		var drop_amount := mini(stored, remaining)
		LootSystem.spawn_drop(null, item_id, drop_amount, global_position, world, overrides)
		_storage[item_id] = stored - drop_amount
		_total_stored      -= drop_amount
		remaining          -= drop_amount
		if int(_storage[item_id]) <= 0:
			_storage.erase(item_id)


func _sync_barrel_visuals() -> void:
	var target := maxi(0, _barrel_count)

	# Trim hits array
	while _barrel_hits.size() > target:
		_barrel_hits.pop_back()
	while _barrel_hits.size() < target:
		_barrel_hits.append(0)

	# Remove excess sprites
	while _barrel_sprites.size() > target:
		var spr: Node2D = _barrel_sprites.pop_back() as Node2D
		if spr != null and is_instance_valid(spr):
			spr.queue_free()

	# Add missing sprites
	while _barrel_sprites.size() < target:
		var spr := Sprite2D.new()
		spr.texture  = BARREL_SPRITE
		spr.position = Vector2(_barrel_sprites.size() * barrel_spacing, 0.0)
		add_child(spr)
		_barrel_sprites.append(spr)


func _shake(spr: Node2D) -> void:
	var base := spr.position
	var tw   := create_tween()
	tw.tween_property(spr, "position", base + Vector2(4.0, 0.0), 0.04)
	tw.tween_property(spr, "position", base - Vector2(4.0, 0.0), 0.04)
	tw.tween_property(spr, "position", base, 0.04)
