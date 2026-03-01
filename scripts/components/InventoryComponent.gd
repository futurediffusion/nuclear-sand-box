extends Node
class_name InventoryComponent

signal inventory_changed
signal slot_changed(slot_index: int)

@export var max_slots: int = 15
@export var max_stack: int = 10

var _gold: int = 0
var _batch_depth: int = 0
var _pending_emit: bool = false
var _dbg_emit_count: int = 0
@export var debug_emit_logs: bool = false

var gold: int:
	get:
		return _gold
	set(value):
		var clamped := maxi(0, value)
		if _gold == clamped:
			return
		_gold = clamped
		_emit_changed("gold")

# Cada slot: null o Dictionary {"id": String, "count": int}
var slots: Array = []


func _ready() -> void:
	slots.resize(max_slots)
	for i in range(max_slots):
		slots[i] = null


# ==========================
# API PRO
# ==========================
func add_item(item_id: String, amount: int) -> int:
	# Devuelve CUÁNTO se pudo meter (0..amount)
	if amount <= 0:
		return 0

	var stack_limit := _get_stack_limit(item_id)
	print("[INV] add_item id=", item_id, " amount=", amount, " stack_limit=", stack_limit)
	var remaining := amount
	var touched := {}

	# 1) llenar stacks existentes del mismo item
	for i in range(max_slots):
		if remaining <= 0:
			break
		var s = slots[i]
		if s == null:
			continue
		if String(s["id"]) != item_id:
			continue

		var can_put := stack_limit - int(s["count"])
		if can_put <= 0:
			continue

		var put: int = mini(can_put, remaining)
		s["count"] = int(s["count"]) + put
		slots[i] = s
		touched[i] = true
		remaining -= put

	# 2) crear nuevos stacks en slots vacíos
	for i in range(max_slots):
		if remaining <= 0:
			break
		if slots[i] != null:
			continue

		var put: int = mini(stack_limit, remaining)
		slots[i] = {"id": item_id, "count": put}
		touched[i] = true
		remaining -= put

	var inserted := amount - remaining
	if inserted > 0:
		for idx in touched.keys():
			_emit_slot_changed(int(idx))
		_emit_changed("add_item")

	if remaining > 0:
		print("[INV] FULL. couldn't add ", remaining, " of ", item_id)

	return inserted


func remove_item(item_id: String, amount: int) -> int:
	# Devuelve CUÁNTO se pudo quitar (0..amount)
	if amount <= 0:
		return 0

	var remaining := amount
	var touched := {}

	# Quitar empezando por el final (opcional) o por el principio.
	# Yo lo hago por el final para “vaciar” stacks de forma limpia.
	for i in range(max_slots - 1, -1, -1):
		if remaining <= 0:
			break
		var s = slots[i]
		if s == null:
			continue
		if String(s["id"]) != item_id:
			continue

		var have := int(s["count"])
		var take: int = mini(have, remaining)
		have -= take
		remaining -= take

		if have <= 0:
			slots[i] = null
		else:
			s["count"] = have
			slots[i] = s
		touched[i] = true

	var removed := amount - remaining
	if removed > 0:
		for idx in touched.keys():
			_emit_slot_changed(int(idx))
		_emit_changed("remove_item")
	return removed


func get_total(item_id: String) -> int:
	var total := 0
	for i in range(max_slots):
		var s = slots[i]
		if s == null:
			continue
		if String(s["id"]) == item_id:
			total += int(s["count"])
	return total


func count_item(item_id: String) -> int:
	return get_total(item_id)


func use_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= max_slots:
		return false

	var stack = slots[slot_index]
	if stack == null:
		return false

	var item_id := String(stack.get("id", ""))
	if item_id == "":
		return false

	var item_data := _get_item_data(item_id)
	if item_data == null:
		return false

	if item_data.consumable and item_data.heal_hp > 0:
		return _use_heal_item(slot_index, item_data.heal_hp)

	return false


func has_space_for(item_id: String, amount: int) -> bool:
	# Simulación rápida: cuánto “hueco” hay para ese item
	var stack_limit := _get_stack_limit(item_id)
	print("[INV] has_space_for id=", item_id, " amount=", amount, " stack_limit=", stack_limit)
	var capacity := 0

	# hueco en stacks existentes
	for i in range(max_slots):
		var s = slots[i]
		if s == null:
			continue
		if String(s["id"]) == item_id:
			capacity += (stack_limit - int(s["count"]))

	# hueco en slots vacíos
	for i in range(max_slots):
		if slots[i] == null:
			capacity += stack_limit

	return capacity >= amount


func can_add(item_id: String, amount: int) -> bool:
	return has_space_for(item_id, amount)


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	return true


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount


func debug_print() -> void:
	print("[INV] gold=", gold, " slots=", slots)


func sell_all(item_id: String, unit_price: int) -> int:
	if unit_price < 0:
		push_warning("[INV] sell_all recibió unit_price negativo")
		return 0

	var total := get_total(item_id)
	if total <= 0:
		return 0

	begin_batch()
	var removed := remove_item(item_id, total)
	if removed <= 0:
		end_batch()
		return 0

	gold += removed * unit_price
	end_batch()
	return removed


func buy_item(item_id: String, amount: int, unit_price: int) -> int:
	if amount <= 0:
		return 0
	if unit_price < 0:
		push_warning("[INV] buy_item recibió unit_price negativo")
		return 0

	if unit_price == 0:
		var free_added := add_item(item_id, amount)
		return free_added

	var affordable := gold / unit_price
	var to_buy := mini(amount, affordable)
	if to_buy <= 0:
		return 0

	begin_batch()
	var added := add_item(item_id, to_buy)
	if added <= 0:
		end_batch()
		return 0

	gold -= added * unit_price
	end_batch()
	return added


func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	if _batch_depth <= 0:
		push_warning("[INV] end_batch() llamado con _batch_depth <= 0")
		return
	_batch_depth -= 1
	if _batch_depth == 0 and _pending_emit:
		_pending_emit = false
		_emit_changed_internal("batch_flush")




func _emit_slot_changed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= max_slots:
		return
	slot_changed.emit(slot_index)

func _emit_changed(tag: String = "") -> void:
	if _batch_depth > 0:
		_pending_emit = true
		return
	_emit_changed_internal(tag)


func _emit_changed_internal(tag: String = "") -> void:
	_dbg_emit_count += 1
	if debug_emit_logs:
		print("[INV][emit#", _dbg_emit_count, "] tag=", tag, " gold=", gold)
	inventory_changed.emit()

func _get_stack_limit(item_id: String) -> int:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db != null and item_db.has_method("get_max_stack"):
		return int(item_db.get_max_stack(item_id, max_stack))
	return max_stack


func _get_item_data(item_id: String) -> ItemData:
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null or not item_db.has_method("get_item"):
		return null
	return item_db.get_item(item_id) as ItemData


func _use_heal_item(slot_index: int, heal_amount: int) -> bool:
	if heal_amount <= 0:
		return false

	var owner_node := get_parent()
	if owner_node == null:
		return false

	var health := owner_node.get_node_or_null("HealthComponent")
	if health == null:
		return false

	var before := int(health.hp)
	var max_hp_value := int(health.max_hp)
	if before >= max_hp_value:
		return false

	health.heal(heal_amount)
	var after := int(health.hp)
	if after <= before:
		return false

	_remove_from_slot(slot_index, 1)
	return true


func _remove_from_slot(slot_index: int, amount: int) -> int:
	if amount <= 0:
		return 0
	if slot_index < 0 or slot_index >= max_slots:
		return 0

	var stack = slots[slot_index]
	if stack == null:
		return 0

	var current := int(stack.get("count", 0))
	if current <= 0:
		slots[slot_index] = null
		return 0

	var removed := mini(amount, current)
	current -= removed

	if current <= 0:
		slots[slot_index] = null
	else:
		stack["count"] = current
		slots[slot_index] = stack

	if removed > 0:
		_emit_slot_changed(slot_index)
		_emit_changed("use_item")

	return removed
