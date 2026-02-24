extends Node
class_name InventoryComponent

signal inventory_changed

@export var max_slots: int = 15
@export var max_stack: int = 10

var gold: int = 0

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

	var remaining := amount

	# 1) llenar stacks existentes del mismo item
	for i in range(max_slots):
		if remaining <= 0:
			break
		var s = slots[i]
		if s == null:
			continue
		if String(s["id"]) != item_id:
			continue

		var can_put := max_stack - int(s["count"])
		if can_put <= 0:
			continue

		var put: int = mini(can_put, remaining)
		s["count"] = int(s["count"]) + put
		slots[i] = s
		remaining -= put

	# 2) crear nuevos stacks en slots vacíos
	for i in range(max_slots):
		if remaining <= 0:
			break
		if slots[i] != null:
			continue

		var put: int = mini(max_stack, remaining)
		slots[i] = {"id": item_id, "count": put}
		remaining -= put

	var inserted := amount - remaining
	if inserted > 0:
		inventory_changed.emit()

	if remaining > 0:
		print("[INV] FULL. couldn't add ", remaining, " of ", item_id)

	return inserted


func remove_item(item_id: String, amount: int) -> int:
	# Devuelve CUÁNTO se pudo quitar (0..amount)
	if amount <= 0:
		return 0

	var remaining := amount

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

	var removed := amount - remaining
	if removed > 0:
		inventory_changed.emit()
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


func has_space_for(item_id: String, amount: int) -> bool:
	# Simulación rápida: cuánto “hueco” hay para ese item
	var capacity := 0

	# hueco en stacks existentes
	for i in range(max_slots):
		var s = slots[i]
		if s == null:
			continue
		if String(s["id"]) == item_id:
			capacity += (max_stack - int(s["count"]))

	# hueco en slots vacíos
	for i in range(max_slots):
		if slots[i] == null:
			capacity += max_stack

	return capacity >= amount


func debug_print() -> void:
	print("[INV] gold=", gold, " slots=", slots)
