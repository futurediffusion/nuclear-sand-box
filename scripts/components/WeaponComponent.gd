extends Node
class_name WeaponComponent

signal weapon_list_changed(weapon_ids: Array[String])
signal weapon_equipped(weapon_id: String)

@export var debug_logs: bool = false

# IDs de items que son armas (según ItemData.tags contiene "weapon")
var weapon_ids: Array[String] = []

var current_index: int = 0
var current_weapon_id: String = "ironpipe"
var current_weapon: WeaponBase = null
var _weapon_texture_cache: Dictionary = {}

# Cache del DB (autoload)
@onready var _item_db := get_node_or_null("/root/ItemDB")

# ---- Visual config por arma (mínimo viable) ----
# En el futuro esto debería ser un Resource por arma, pero por ahora lo dejamos simple.
const VISUALS := {
	"ironpipe": {
		"sprite_path": "res://art/sprites/palo.png",
		"weapon_sprite_offset": Vector2(12, 0),
		"slash_spawn_pos": Vector2(20, 0),
		"scale": Vector2(1, 1),
	},
	"bow": {
		"sprite_path": "res://art/items/bow.png",
		"weapon_sprite_offset": Vector2(9, -1),
		"slash_spawn_pos": Vector2(18, 0),
		"scale": Vector2(0.5, 0.5),
	},
	"axe_wood": {
		"sprite_path": "res://art/tools/axe-wood.png",
		"weapon_sprite_offset": Vector2(10, -2),
		"slash_spawn_pos": Vector2(18, 0),
		"scale": Vector2(0.6, 0.6),
	},
	"axe_stone": {
		"sprite_path": "res://art/tools/axe-stone.png",
		"weapon_sprite_offset": Vector2(10, -2),
		"slash_spawn_pos": Vector2(18, 0),
		"scale": Vector2(0.6, 0.6),
	},
	"axe_copper": {
		"sprite_path": "res://art/tools/axe-copper.png",
		"weapon_sprite_offset": Vector2(10, -2),
		"slash_spawn_pos": Vector2(18, 0),
		"scale": Vector2(0.6, 0.6),
	},
	"sword_wood": {
		"sprite_path": "res://art/weapons/sword-wood.png",
		"weapon_sprite_offset": Vector2(12, -1),
		"slash_spawn_pos": Vector2(20, 0),
		"scale": Vector2(0.6, 0.6),
	},
	"sword_stone": {
		"sprite_path": "res://art/weapons/sword-stone.png",
		"weapon_sprite_offset": Vector2(12, -1),
		"slash_spawn_pos": Vector2(20, 0),
		"scale": Vector2(0.6, 0.6),
	},
	"sword_copper": {
		"sprite_path": "res://art/weapons/sword-copper.png",
		"weapon_sprite_offset": Vector2(12, -1),
		"slash_spawn_pos": Vector2(20, 0),
		"scale": Vector2(0.6, 0.6),
	},
	"pickaxe_wood": {
		"sprite_path": "res://art/tools/pickaxe-wood.png",
		"weapon_sprite_offset": Vector2(10, -2),
		"slash_spawn_pos": Vector2(18, 0),
		"scale": Vector2(0.6, 0.6),
	},
	"pickaxe_stone": {
		"sprite_path": "res://art/tools/pickaxe-stone.png",
		"weapon_sprite_offset": Vector2(10, -2),
		"slash_spawn_pos": Vector2(18, 0),
		"scale": Vector2(0.6, 0.6),
	},
	"pickaxe_copper": {
		"sprite_path": "res://art/tools/pickaxe-copper.png",
		"weapon_sprite_offset": Vector2(10, -2),
		"slash_spawn_pos": Vector2(18, 0),
		"scale": Vector2(0.6, 0.6),
	},
}

func setup_from_inventory(inventory: InventoryComponent) -> void:
	rebuild_weapon_list_from_inventory(inventory)
	# Asegura que haya algo equipado
	if weapon_ids.is_empty():
		_equip_fallback()
	else:
		# Mantener si sigue existiendo, si no, equipa el primero
		if not weapon_ids.has(current_weapon_id):
			current_index = 0
			current_weapon_id = _normalize_weapon_id(weapon_ids[0])
			weapon_equipped.emit(current_weapon_id)
			weapon_list_changed.emit(weapon_ids)

func rebuild_weapon_list_from_inventory(inventory: InventoryComponent) -> void:
	if inventory == null:
		weapon_ids = []
		_equip_fallback()
		weapon_list_changed.emit(weapon_ids)
		return

	var found: Dictionary = {} # set para evitar duplicados

	# inventory.slots: Array de null o Dictionary {"id": String, "count": int}
	for slot in inventory.slots:
		if slot == null:
			continue
		if not (slot is Dictionary):
			continue

		var item_id := _normalize_weapon_id(String(slot.get("id", "")))
		if item_id == "":
			continue

		var data := _get_item_data(item_id)
		if data == null:
			continue

		if _has_tag(data.tags, "weapon"):
			found[item_id] = true

	var new_weapon_ids: Array[String] = []
	for found_id in found.keys():
		new_weapon_ids.append(String(found_id))
	new_weapon_ids.sort() # estable (opcional)
	weapon_ids = new_weapon_ids

	if debug_logs:
		print("[WeaponComponent] rebuild weapon_ids=", weapon_ids)

	# Ajusta arma equipada si ya no existe
	if weapon_ids.is_empty():
		_equip_fallback()
	else:
		if weapon_ids.has(current_weapon_id):
			current_index = weapon_ids.find(current_weapon_id)
		else:
			current_index = clampi(current_index, 0, weapon_ids.size() - 1)
			current_weapon_id = _normalize_weapon_id(weapon_ids[current_index])
			weapon_equipped.emit(current_weapon_id)

	weapon_list_changed.emit(weapon_ids)

func equip_weapon_id(weapon_id: String) -> bool:
	if weapon_ids.is_empty():
		_equip_fallback()
		return false
	var normalized_weapon_id := _normalize_weapon_id(weapon_id)
	var next_index := weapon_ids.find(normalized_weapon_id)
	if next_index == -1:
		return false
	if current_weapon_id == normalized_weapon_id and current_index == next_index:
		return false
	equip_index(next_index)
	return true

func equip_index(i: int) -> void:
	if weapon_ids.is_empty():
		_equip_fallback()
		return
	if i < 0 or i >= weapon_ids.size():
		return

	current_index = i
	current_weapon_id = _normalize_weapon_id(weapon_ids[current_index])
	if debug_logs:
		print("[WeaponComponent] equip_index -> ", current_weapon_id)
	weapon_equipped.emit(current_weapon_id)

func equip_next() -> void:
	if weapon_ids.is_empty():
		_equip_fallback()
		return
	current_index = (current_index + 1) % weapon_ids.size()
	current_weapon_id = _normalize_weapon_id(weapon_ids[current_index])
	if debug_logs:
		print("[WeaponComponent] equip_next -> ", current_weapon_id)
	weapon_equipped.emit(current_weapon_id)

func equip_prev() -> void:
	if weapon_ids.is_empty():
		_equip_fallback()
		return
	current_index = (current_index - 1 + weapon_ids.size()) % weapon_ids.size()
	current_weapon_id = _normalize_weapon_id(weapon_ids[current_index])
	if debug_logs:
		print("[WeaponComponent] equip_prev -> ", current_weapon_id)
	weapon_equipped.emit(current_weapon_id)

func equip_runtime_weapon(weapon_owner: Node, controller: WeaponController = null) -> void:
	_equip_runtime_weapon(weapon_owner, controller)

func refresh_runtime_weapon_controller(weapon_owner: Node, controller: WeaponController) -> void:
	if weapon_owner == null or controller == null:
		return
	if current_weapon == null:
		_equip_runtime_weapon(weapon_owner, controller)
		return
	current_weapon.owner_entity = weapon_owner
	current_weapon.set_controller(controller)

func tick(delta: float) -> void:
	if current_weapon != null:
		current_weapon.tick(delta)

func get_current_weapon_id() -> String:
	return _normalize_weapon_id(current_weapon_id)

# ---- Visual application (llamar desde Player) ----
func apply_visuals(player: Node) -> void:
	if player == null:
		return

	var weapon_sprite: Sprite2D = player.get_node_or_null("WeaponPivot/WeaponSprite")
	var slash_spawn: Marker2D = player.get_node_or_null("WeaponPivot/SlashSpawn")

	if weapon_sprite == null or slash_spawn == null:
		return

	var weapon_id := _normalize_weapon_id(current_weapon_id)
	if weapon_id == "":
		weapon_sprite.texture = null
		weapon_sprite.visible = false
		return

	var conf = VISUALS.get(weapon_id, VISUALS["ironpipe"])
	var sprite_path: String = String(conf.get("sprite_path", ""))
	var sprite_offset: Vector2 = conf.get("weapon_sprite_offset", Vector2(12, 0))
	var slash_pos: Vector2 = conf.get("slash_spawn_pos", Vector2(20, 0))
	var sprite_scale: Vector2 = conf.get("scale", Vector2.ONE)

	weapon_sprite.offset = sprite_offset
	weapon_sprite.scale = sprite_scale
	slash_spawn.position = slash_pos

	if sprite_path == "":
		weapon_sprite.texture = null
		weapon_sprite.visible = false
		return

	var texture: Texture2D = _weapon_texture_cache.get(sprite_path)
	if texture == null and ResourceLoader.exists(sprite_path):
		texture = ResourceLoader.load(sprite_path) as Texture2D
		if texture != null:
			_weapon_texture_cache[sprite_path] = texture

	weapon_sprite.texture = texture
	weapon_sprite.visible = texture != null

# ---- Helpers ----
func _equip_fallback() -> void:
	current_index = 0
	if current_weapon_id == "":
		return
	current_weapon_id = ""
	weapon_equipped.emit(current_weapon_id)

func _equip_runtime_weapon(weapon_owner: Node, controller: WeaponController = null) -> void:
	if current_weapon != null:
		current_weapon.on_unequipped()
		current_weapon.queue_free()
		current_weapon = null

	current_weapon = _make_weapon_node(current_weapon_id)
	if current_weapon == null:
		return

	if current_weapon is BowWeapon and controller is AIWeaponController:
		(current_weapon as BowWeapon).consume_arrows = false
	current_weapon.name = "CurrentWeapon"
	add_child(current_weapon)
	current_weapon.on_equipped(weapon_owner, controller)

func _make_weapon_node(weapon_id: String) -> WeaponBase:
	var normalized_weapon_id := _normalize_weapon_id(weapon_id)
	if normalized_weapon_id == "":
		return null

	match normalized_weapon_id:
		"ironpipe":
			return IronPipeWeapon.new()
		"bow":
			return BowWeapon.new()
		"axe_wood":
			# Herramienta pesada — siempre más lenta que todo, 2 hits a enemigo base
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.55
			w.damage_bonus = 1
			return w
		"axe_stone":
			# Stone: mismo daño que wood pero levemente menos lento — sigue siendo 2 hits
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.52
			w.damage_bonus = 1
			return w
		"axe_copper":
			# Copper: gran salto de daño — 1 hit, sigue siendo la más lenta
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.50
			w.damage_bonus = 3
			return w
		"sword_wood":
			# Arma de combate: la más rápida, mayor DPS por tier
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.22
			w.damage_bonus = 1
			return w
		"sword_stone":
			# Stone: mismo daño que wood pero más rápida — sigue siendo 2 hits
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.18
			w.damage_bonus = 1
			return w
		"sword_copper":
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.16
			w.damage_bonus = 3
			return w
		"pickaxe_wood":
			# Herramienta de minería — más lenta que armas, un poco más rápida que hachas
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.45
			w.damage_bonus = 0
			return w
		"pickaxe_stone":
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.43
			w.damage_bonus = 0
			return w
		"pickaxe_copper":
			# Copper: finalmente usable como arma de emergencia
			var w := MeleeWeapon.new()
			w.attack_cooldown = 0.42
			w.damage_bonus = 1
			return w
		_:
			return null


func _normalize_weapon_id(weapon_id: String) -> String:
	if weapon_id == "melee":
		return "ironpipe"
	return weapon_id

func _get_item_data(item_id: String) -> ItemData:
	if _item_db == null:
		_item_db = get_node_or_null("/root/ItemDB")
	if _item_db == null:
		return null
	if not _item_db.has_method("get_item"):
		return null
	return _item_db.get_item(item_id) as ItemData

func _has_tag(tags: Array, tag: String) -> bool:
	for t in tags:
		if String(t) == tag:
			return true
	return false
