class_name CopperOre
extends Area2D

signal ore_hit(item_id: String, amount: int, origin: Vector2, hitter: Node)
signal ore_depleted(origin: Vector2)
signal request_drop(item_id: String, amount: int, origin: Vector2, hitter: Node)

@export var drop_item: ItemData
@export var give_item_id: String = "copper"
@export var give_amount: int = 1
@export var mining_sfx: AudioStream = preload("res://art/Sounds/mining.ogg")
@export var use_systems: bool = true
func get_hit_sound() -> AudioStream:
	return mining_sfx

# --- Feedback al golpear (WorldBox vibe) ---
@export var shake_duration: float = 0.08
@export var shake_px: float = 6.0
@export var shake_speed: float = 40.0 # qué tan rápido tiembla

@export var hit_flash_time: float = 0.06

@onready var sprite: Sprite2D = $Sprite2D
@onready var hit_particles: GPUParticles2D = $HitParticles

# coper finito
@export var total_min: int = 1500
@export var total_max: int = 3000
@export var remaining: int = -1  # -1 => se inicializa random
@export var yield_per_hit: int = 1

@export var yield_multiplier: float = 1.0  # “calidad” (opcional)
#owner ship enchufe para futuro
@export var faction_owner_id: int = -1  # -1 = nadie

#item drops 
@export var drop_scene: PackedScene
@export var drop_icon: Texture2D
@export var drop_pickup_sfx: AudioStream

#-------

var _base_sprite_pos: Vector2
var _shake_t: float = 0.0
var _flash_t: float = 0.0

var entity_uid: String = ""

func _ready() -> void:
	if remaining < 0:
		remaining = randi_range(total_min, total_max)
	_base_sprite_pos = sprite.position

	if drop_item == null and give_item_id == "":
		push_warning("[COPPER] Define drop_item o give_item_id")
	elif drop_item != null:
		Debug.log("copper", "drop_item id=%s" % drop_item.id)
	else:
		Debug.log("copper", "using legacy give_item_id=%s" % give_item_id)

func _physics_process(delta: float) -> void:
	# --- Temblor ---
	if _shake_t > 0.0:
		_shake_t -= delta
		var t := (shake_duration - _shake_t) * shake_speed
		var off := sin(t) * shake_px
		sprite.position = _base_sprite_pos + Vector2(off, 0.0)
	else:
		sprite.position = _base_sprite_pos

	# --- Flash rojo ---
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			sprite.modulate = Color(1, 1, 1, 1)

func hit(by: Node) -> void:
	_play_hit_feedback()

	if remaining <= 0:
		Debug.log("copper", "agotado")
		return

	var amount := int(round(yield_per_hit * yield_multiplier))
	amount = clampi(amount, 1, remaining)

	# 1) gastar la mena
	remaining -= amount

	var resolved_item_id := give_item_id
	if drop_item != null and drop_item.id != "":
		resolved_item_id = drop_item.id

	var origin := global_position + Vector2(0.0, -10.0)
	ore_hit.emit(resolved_item_id, amount, origin, by)
	request_drop.emit(resolved_item_id, amount, origin, by)

	if use_systems:
		_spawn_drop(amount)
		AudioSystem.play_2d(get_hit_sound(), global_position)
	else:
		_spawn_drop_legacy(amount)

	Debug.log("copper", "dropped=%s remaining=%s" % [str(amount), str(remaining)])

	if remaining <= 0:
		ore_depleted.emit(origin)

	if hit_particles:
		hit_particles.restart()
		hit_particles.emitting = true


func _play_hit_feedback() -> void:
	_shake_t = shake_duration

	_flash_t = hit_flash_time
	sprite.modulate = Color(1, 0.5, 0.5, 1) # rojito tipo “hurt”

func _give_to_player(by: Node) -> void:
	# 1) Si quien golpeó tiene InventoryComponent directo
	if by != null and by.has_method("get_node_or_null"):
		var inv := by.get_node_or_null("InventoryComponent")
		if inv != null and inv.has_method("add_item"):
			inv.add_item(give_item_id, give_amount)
			return

	# 2) Fallback: buscar al player por grupo
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p := players[0]
		var inv2 := p.get_node_or_null("InventoryComponent")
		if inv2 != null and inv2.has_method("add_item"):
			inv2.add_item(give_item_id, give_amount)
func _give_to_player_amount(by: Node, amount: int) -> int:
	if by != null and by.has_method("get_node_or_null"):
		var inv := by.get_node_or_null("InventoryComponent")
		if inv != null and inv.has_method("add_item"):
			return int(inv.add_item(give_item_id, amount))

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p := players[0]
		var inv2 := p.get_node_or_null("InventoryComponent")
		if inv2 != null and inv2.has_method("add_item"):
			return int(inv2.add_item(give_item_id, amount))

	return 0
	
func _try_give_to_player(by: Node, amount: int) -> int:
	# 1) directo en el que pegó
	if by != null and by.has_method("get_node_or_null"):
		var inv := by.get_node_or_null("InventoryComponent")
		if inv != null and inv.has_method("add_item"):
			return int(inv.add_item(give_item_id, amount))

	# 2) fallback: primer player del grupo
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p := players[0]
		var inv2 := p.get_node_or_null("InventoryComponent")
		if inv2 != null and inv2.has_method("add_item"):
			return int(inv2.add_item(give_item_id, amount))

	return 0

func _spawn_drop(amount_to_drop: int) -> void:
	if not use_systems:
		_spawn_drop_legacy(amount_to_drop)
		return

	var icon_override: Texture2D = drop_icon if drop_icon != null else null
	var pickup_override: AudioStream = drop_pickup_sfx if drop_pickup_sfx != null else null

	var overrides := {
		"drop_scene": drop_scene,
		"icon": icon_override,
		"pickup_sfx": pickup_override,
	}

	var origin := global_position + Vector2(0.0, -10.0)
	var spawned := LootSystem.spawn_drop(drop_item, give_item_id, amount_to_drop, origin, get_parent(), overrides, entity_uid)
	if spawned == null:
		push_warning("[COPPER] LootSystem no pudo crear drop")

func _spawn_drop_legacy(amount_to_drop: int) -> void:
	Debug.log("loot", "spawn_drop amount=%s drop_scene=%s" % [str(amount_to_drop), str(drop_scene)])
	if drop_scene == null:
		push_warning("[COPPER] drop_scene no asignado")
		return

	var drop := drop_scene.instantiate() as ItemDrop
	if drop_item != null:
		drop.item_data = drop_item
		drop.item_id = drop_item.id
	else:
		drop.item_id = give_item_id

	drop.amount = amount_to_drop
	if drop_icon != null:
		drop.icon = drop_icon
	if drop_pickup_sfx != null:
		drop.pickup_sfx = drop_pickup_sfx

	# spawn EXACTO desde la mena (un poquito arriba del centro)
	var origin := global_position + Vector2(0.0, -10.0)

	get_parent().add_child(drop)

	# Dirección random + fuerza
	var angle := randf_range(-PI * 0.15, PI + PI * 0.15)
	var dir := Vector2(cos(angle), sin(angle))

	var speed := randf_range(160.0, 220.0)
	var up_boost := randf_range(240.0, 320.0)

	drop.throw_from(origin, dir, speed, up_boost)


func get_save_state() -> Dictionary:
	return {"remaining": remaining}

func apply_save_state(state: Dictionary) -> void:
	if state.has("remaining"):
		remaining = int(state["remaining"])
