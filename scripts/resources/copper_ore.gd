class_name CopperOre
extends Area2D

@export var give_item_id: String = "copper"
@export var give_amount: int = 1
@export var mining_sfx: AudioStream = preload("res://art/Sounds/mining.ogg")
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

#-------

var _base_sprite_pos: Vector2
var _shake_t: float = 0.0
var _flash_t: float = 0.0

func _ready() -> void:
	if remaining < 0:
		remaining = randi_range(total_min, total_max)
	_base_sprite_pos = sprite.position

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
		print("[COPPER] agotado")
		return

	var amount := int(round(yield_per_hit * yield_multiplier))
	amount = clampi(amount, 1, remaining)

	# ✅ 1) intentar meter al inventario primero
	var inserted: int = _give_to_player_amount(by, amount)

	# ✅ 2) si no entró nada, NO gastes la mena
	if inserted <= 0:
		print("[COPPER] Inventario lleno. No se pudo guardar.")
		return

	# ✅ 3) ahora sí, resta SOLO lo que realmente entró
	remaining -= inserted
	print("[COPPER] +", inserted, give_item_id, " remaining=", remaining)

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
