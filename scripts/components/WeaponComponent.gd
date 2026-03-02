extends Node
class_name WeaponComponent

signal weapon_list_changed(weapon_ids: Array[String])
signal weapon_equipped(weapon_id: String)

@export var debug_logs: bool = false

# IDs de items que son armas (según ItemData.tags contiene "weapon")
var weapon_ids: Array[String] = []

var current_index: int = 0
var current_weapon_id: String = "melee"

# Cache del DB (autoload)
@onready var _item_db := get_node_or_null("/root/ItemDB")

# ---- Visual config por arma (mínimo viable) ----
# En el futuro esto debería ser un Resource por arma, pero por ahora lo dejamos simple.
const VISUALS := {
	"melee": {
		"sprite_path": "res://art/sprites/palo.png",
		"weapon_sprite_offset": Vector2(12, 0),
		"slash_spawn_pos": Vector2(20, 0),
	},
	"bow": {
		# Placeholder, puedes crear el PNG después. Si no existe no crashea.
		"sprite_path": "res://art/sprites/bow.png",
		"weapon_sprite_offset": Vector2(12, 0),
		"slash_spawn_pos": Vector2(20, 0),
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
			current_weapon_id = weapon_ids[0]
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

		var item_id := String(slot.get("id", ""))
		if item_id == "":
			continue

		var data := _get_item_data(item_id)
		if data == null:
			continue

		if _has_tag(data.tags, "weapon"):
			found[item_id] = true

	weapon_ids = found.keys()
	weapon_ids.sort() # estable (opcional)

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
			current_weapon_id = weapon_ids[current_index]
			weapon_equipped.emit(current_weapon_id)

	weapon_list_changed.emit(weapon_ids)

func equip_index(i: int) -> void:
	if weapon_ids.is_empty():
		_equip_fallback()
		return
	if i < 0 or i >= weapon_ids.size():
		return

	current_index = i
	current_weapon_id = weapon_ids[current_index]
	if debug_logs:
		print("[WeaponComponent] equip_index -> ", current_weapon_id)
	weapon_equipped.emit(current_weapon_id)

func equip_next() -> void:
	if weapon_ids.is_empty():
		_equip_fallback()
		return
	current_index = (current_index + 1) % weapon_ids.size()
	current_weapon_id = weapon_ids[current_index]
	if debug_logs:
		print("[WeaponComponent] equip_next -> ", current_weapon_id)
	weapon_equipped.emit(current_weapon_id)

func equip_prev() -> void:
	if weapon_ids.is_empty():
		_equip_fallback()
		return
	current_index = (current_index - 1 + weapon_ids.size()) % weapon_ids.size()
	current_weapon_id = weapon_ids[current_index]
	if debug_logs:
		print("[WeaponComponent] equip_prev -> ", current_weapon_id)
	weapon_equipped.emit(current_weapon_id)

func get_current_weapon_id() -> String:
	return current_weapon_id

# ---- Visual application (llamar desde Player) ----
func apply_visuals(player: Node) -> void:
	if player == null:
		return

	var weapon_sprite: Sprite2D = player.get_node_or_null("WeaponPivot/WeaponSprite")
	var slash_spawn: Marker2D = player.get_node_or_null("WeaponPivot/SlashSpawn")

	if weapon_sprite == null or slash_spawn == null:
		return

	var conf = VISUALS.get(current_weapon_id, VISUALS["melee"])
	var sprite_path: String = String(conf.get("sprite_path", ""))
	var sprite_offset: Vector2 = conf.get("weapon_sprite_offset", Vector2(12, 0))
	var slash_pos: Vector2 = conf.get("slash_spawn_pos", Vector2(20, 0))

	weapon_sprite.offset = sprite_offset
	slash_spawn.position = slash_pos

	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		weapon_sprite.texture = load(sprite_path)

# ---- Helpers ----
func _equip_fallback() -> void:
	current_index = 0
	current_weapon_id = "melee"
	weapon_equipped.emit(current_weapon_id)

func _get_item_data(item_id: String) -> ItemData:
	if _item_db == null:
		_item_db = get_node_or_null("/root/ItemDB")
	if _item_db == null:
		return null
	if not _item_db.has_method("get_item"):
		return null
	return _item_db.get_item(item_id) as ItemData

func _has_tag(tags: Array[String], tag: String) -> bool:
	for t in tags:
		if String(t) == tag:
			return true
	return false
