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
@export var debug_inventory_logs: bool = false

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
	# Nota de diseño: este inventario NO usa ranuras fijas por tipo de item.
	# La inserción es dinámica: primero completa stacks existentes y luego usa
	# el primer slot vacío disponible según el orden actual de slots.
	if amount <= 0:
		return 0

	var stack_limit := _get_stack_limit(item_id)
	_inv_log("[INV] add_item id=%s amount=%d stack_limit=%d" % [item_id, amount, stack_limit])
	var remaining := amount
	var touched := {}

	for i in range(max_slots):
		if _normalize_slot_if_needed(i):
			touched[i] = true

	# 1) llenar stacks existentes del mismo item
	_inv_log("[INV] add_item scan_merge start=0 slots=%d" % max_slots)
	for i in range(max_slots):
		if remaining <= 0:
			break
		var s = slots[i]
		if _is_empty_slot(s):
			continue

		var slot_id := String(s.get("id", ""))
		if slot_id != item_id:
			continue

		var slot_count := int(s.get("count", 0))
		if slot_count <= 0:
			continue

		var can_put := stack_limit - slot_count
		if can_put <= 0:
			continue

		var moved: int = mini(can_put, remaining)
		s["count"] = slot_count + moved
		slots[i] = s
		touched[i] = true
		remaining -= moved
		_inv_log("[INV] add_item MERGE slot=%d moved=%d new_dst=%d remaining=%d" % [i, moved, int(s["count"]), remaining])

	# 2) crear nuevos stacks en slots vacíos
	# Importante: esto mantiene un comportamiento "first-fit" (sin categorías
	# fijas). Visualmente puede parecer que un item "salta" de posición cuando
	# la ocupación cambia, pero es esperado para este modelo.
	_inv_log("[INV] add_item scan_empty start=0")
	for i in range(max_slots):
		if remaining <= 0:
			break
		if not _is_empty_slot(slots[i]):
			continue

		var inserted: int = mini(stack_limit, remaining)
		slots[i] = {"id": item_id, "count": inserted}
		touched[i] = true
		remaining -= inserted
		_inv_log("[INV] add_item INSERT slot=%d inserted=%d remaining=%d" % [i, inserted, remaining])

	var inserted := amount - remaining
	if inserted > 0:
		for idx in touched.keys():
			_emit_slot_changed(int(idx))
		_emit_changed("add_item")

	if remaining > 0:
		_inv_log("[INV] add_item INCOMPLETE remaining=%d" % remaining)

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
	_inv_log("[INV] has_space_for id=%s amount=%d stack_limit=%d" % [item_id, amount, stack_limit])
	var capacity := 0

	# hueco en stacks existentes
	for i in range(max_slots):
		var s = slots[i]
		if _is_empty_slot(s):
			continue
		if String(s.get("id", "")) == item_id:
			capacity += (stack_limit - int(s.get("count", 0)))

	# hueco en slots vacíos
	for i in range(max_slots):
		if _is_empty_slot(slots[i]):
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
	_inv_log("[INV] gold=%s slots=%s" % [str(gold), str(slots)])


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


func drag_move_or_merge(from_slot: int, to_slot: int) -> bool:
	if from_slot < 0 or from_slot >= max_slots:
		_inv_log("[INV] drag_move_or_merge from=%d to=%d action=noop" % [from_slot, to_slot])
		return false
	if to_slot < 0 or to_slot >= max_slots:
		_inv_log("[INV] drag_move_or_merge from=%d to=%d action=noop" % [from_slot, to_slot])
		return false
	if from_slot == to_slot:
		_inv_log("[INV] drag_move_or_merge from=%d to=%d action=noop" % [from_slot, to_slot])
		return false

	var from_stack = slots[from_slot]
	if from_stack == null:
		_inv_log("[INV] drag_move_or_merge from=%d to=%d action=noop" % [from_slot, to_slot])
		return false

	var from_id := String(from_stack.get("id", ""))
	var from_count := int(from_stack.get("count", 0))
	if from_id == "" or from_count <= 0:
		_inv_log("[INV] drag_move_or_merge from=%d to=%d action=noop" % [from_slot, to_slot])
		return false

	var to_stack = slots[to_slot]
	if to_stack == null:
		slots[to_slot] = from_stack.duplicate(true)
		slots[from_slot] = null
		_emit_slot_changed(from_slot)
		_emit_slot_changed(to_slot)
		_inv_log("[INV] drag_move_or_merge from=%d to=%d action=move" % [from_slot, to_slot])
		return true

	var to_id := String(to_stack.get("id", ""))
	var to_count := int(to_stack.get("count", 0))
	if to_id == "" or to_count <= 0:
		slots[to_slot] = from_stack.duplicate(true)
		slots[from_slot] = null
		_emit_slot_changed(from_slot)
		_emit_slot_changed(to_slot)
		_inv_log("[INV] drag_move_or_merge from=%d to=%d action=move" % [from_slot, to_slot])
		return true

	if from_id == to_id:
		var stack_limit := _get_stack_limit(from_id)
		var space := stack_limit - to_count
		if space <= 0:
			_inv_log("[INV] drag_move_or_merge from=%d to=%d action=noop" % [from_slot, to_slot])
			return false

		var moved := mini(space, from_count)
		to_stack["count"] = to_count + moved
		from_count -= moved
		slots[to_slot] = to_stack

		if from_count <= 0:
			slots[from_slot] = null
		else:
			from_stack["count"] = from_count
			slots[from_slot] = from_stack

		_emit_slot_changed(from_slot)
		_emit_slot_changed(to_slot)
		_inv_log("[INV] drag_move_or_merge from=%d to=%d action=merge" % [from_slot, to_slot])
		return true

	slots[from_slot] = to_stack.duplicate(true)
	slots[to_slot] = from_stack.duplicate(true)
	_emit_slot_changed(from_slot)
	_emit_slot_changed(to_slot)
	_inv_log("[INV] drag_move_or_merge from=%d to=%d action=swap" % [from_slot, to_slot])
	return true


func drag_transfer_amount(from_slot: int, to_slot: int, amount: int) -> bool:
	if from_slot < 0 or from_slot >= max_slots:
		return false
	if to_slot < 0 or to_slot >= max_slots:
		return false
	if from_slot == to_slot:
		return false
	if amount <= 0:
		return false

	var from_stack = slots[from_slot]
	if from_stack == null:
		return false

	var from_id := String(from_stack.get("id", ""))
	var from_count := int(from_stack.get("count", 0))
	if from_id == "" or from_count <= 0:
		return false

	var requested_amount := mini(amount, from_count)
	if requested_amount <= 0:
		return false

	var to_stack = slots[to_slot]
	var action := "noop"
	var moved_amount := 0

	if to_stack == null:
		action = "move_full" if requested_amount == from_count else "move_partial"
		slots[to_slot] = {"id": from_id, "count": requested_amount}
		from_count -= requested_amount
		moved_amount = requested_amount

		if from_count <= 0:
			slots[from_slot] = null
		else:
			from_stack["count"] = from_count
			slots[from_slot] = from_stack

		_emit_slot_changed(from_slot)
		_emit_slot_changed(to_slot)
		_inv_log("[INV] drag_transfer_amount from=%d to=%d id=%s amount=%d action=%s ok=true" % [from_slot, to_slot, from_id, moved_amount, action])
		return true

	var to_id := String(to_stack.get("id", ""))
	var to_count := int(to_stack.get("count", 0))
	if to_id == "" or to_count <= 0:
		action = "move_full" if requested_amount == from_count else "move_partial"
		slots[to_slot] = {"id": from_id, "count": requested_amount}
		from_count -= requested_amount
		moved_amount = requested_amount

		if from_count <= 0:
			slots[from_slot] = null
		else:
			from_stack["count"] = from_count
			slots[from_slot] = from_stack

		_emit_slot_changed(from_slot)
		_emit_slot_changed(to_slot)
		_inv_log("[INV] drag_transfer_amount from=%d to=%d id=%s amount=%d action=%s ok=true" % [from_slot, to_slot, from_id, moved_amount, action])
		return true

	if to_id == from_id:
		var stack_limit := _get_stack_limit(from_id)
		var space := stack_limit - to_count
		var moved := mini(space, requested_amount)
		if moved <= 0:
			return false

		to_stack["count"] = to_count + moved
		slots[to_slot] = to_stack
		from_count -= moved
		moved_amount = moved

		if from_count <= 0:
			slots[from_slot] = null
		else:
			from_stack["count"] = from_count
			slots[from_slot] = from_stack

		_emit_slot_changed(from_slot)
		_emit_slot_changed(to_slot)
		_inv_log("[INV] drag_transfer_amount from=%d to=%d id=%s amount=%d action=merge ok=true" % [from_slot, to_slot, from_id, moved_amount])
		return true

	if requested_amount < from_count:
		return false

	slots[from_slot] = to_stack.duplicate(true)
	slots[to_slot] = from_stack.duplicate(true)
	_emit_slot_changed(from_slot)
	_emit_slot_changed(to_slot)
	_inv_log("[INV] drag_transfer_amount from=%d to=%d id=%s amount=%d action=swap ok=true" % [from_slot, to_slot, from_id, requested_amount])
	return true


func extract_amount_for_drop(slot_index: int, amount: int) -> Dictionary:
	if slot_index < 0 or slot_index >= max_slots:
		_inv_log("[INV] extract_amount_for_drop slot=%d id=%s amount=%d ok=false" % [slot_index, "", amount])
		return {}

	var slot = slots[slot_index]
	if slot == null:
		_inv_log("[INV] extract_amount_for_drop slot=%d id=%s amount=%d ok=false" % [slot_index, "", amount])
		return {}

	var item_id := String(slot.get("id", ""))
	var slot_count := int(slot.get("count", 0))
	if item_id == "" or slot_count <= 0:
		_inv_log("[INV] extract_amount_for_drop slot=%d id=%s amount=%d ok=false" % [slot_index, item_id, amount])
		return {}

	var clamped_amount := mini(amount, slot_count)
	if clamped_amount <= 0:
		_inv_log("[INV] extract_amount_for_drop slot=%d id=%s amount=%d ok=false" % [slot_index, item_id, clamped_amount])
		return {}

	slot_count -= clamped_amount
	if slot_count <= 0:
		slot["id"] = ""
		slot["count"] = 0
	else:
		slot["count"] = slot_count

	slots[slot_index] = slot
	_emit_slot_changed(slot_index)

	_inv_log("[INV] extract_amount_for_drop slot=%d id=%s amount=%d ok=true" % [slot_index, item_id, clamped_amount])
	return {"id": item_id, "amount": clamped_amount}


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
		_inv_log("[INV][emit#%d] tag=%s gold=%d" % [_dbg_emit_count, tag, gold])
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

	_inv_log("[INV] used bandage heal_hp=%d slot=%d" % [heal_amount, slot_index])

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


func _is_empty_slot(slot: Variant) -> bool:
	if slot == null:
		return true
	if not (slot is Dictionary):
		return false
	return String(slot.get("id", "")) == "" and int(slot.get("count", 0)) == 0


func _normalize_slot_if_needed(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= max_slots:
		return false

	var slot = slots[slot_index]
	if slot == null:
		return false
	if not (slot is Dictionary):
		return false

	var slot_id := String(slot.get("id", ""))
	var slot_count := int(slot.get("count", 0))
	var normalized_id := slot_id
	var normalized_count := slot_count
	var changed := false

	if normalized_count <= 0:
		normalized_count = 0
		normalized_id = ""
		changed = true
	elif normalized_id == "":
		normalized_count = 0
		changed = true

	if not changed and normalized_id == slot_id and normalized_count == slot_count:
		return false

	_inv_log("[INV][WARN] inconsistent slot=%d id='%s' count=%d (fixing)" % [slot_index, slot_id, slot_count])
	slots[slot_index] = {"id": normalized_id, "count": normalized_count}
	return true


func _inv_log(message: String) -> void:
	if not debug_inventory_logs:
		return
	print(message)
