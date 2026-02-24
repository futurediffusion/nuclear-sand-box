extends Node

# Componente genérico de inventario + monedas.
# Se puede usar como hijo del Player u otros actores.

signal inventory_changed

var gold: int = 0
var items: Dictionary = {} # item_id:String -> count:int


func add_item(item_id: String, amount: int) -> void:
	if amount <= 0:
		print("[INV] add_item ignored amount<=0 item=", item_id, " amount=", amount)
		return

	items[item_id] = get_count(item_id) + amount
	print("[INV] +", item_id, "=", amount, " total=", get_count(item_id))
	
	# ✅ avisar a la UI
	inventory_changed.emit()
	print("[INV] inv_id=", get_instance_id())

func remove_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		print("[INV] remove_item ignored amount<=0 item=", item_id, " amount=", amount)
		return false

	var current := get_count(item_id)
	if current < amount:
		print("[INV] remove failed item=", item_id, " need=", amount, " have=", current)
		return false

	var new_total := current - amount
	if new_total <= 0:
		items.erase(item_id)
	else:
		items[item_id] = new_total

	print("[INV] -", item_id, "=", amount, " total=", get_count(item_id))

	# ✅ avisar a la UI
	inventory_changed.emit()
	return true


func get_count(item_id: String) -> int:
	if items.has(item_id):
		return int(items[item_id])
	return 0


func sell_item(item_id: String, amount: int, price_per_unit: int) -> int:
	if amount <= 0:
		print("[INV] sell_item ignored amount<=0 item=", item_id, " amount=", amount)
		return 0

	if price_per_unit < 0:
		print("[INV] sell_item ignored price<0 item=", item_id, " price=", price_per_unit)
		return 0

	if not remove_item(item_id, amount):
		return 0

	var gained := amount * price_per_unit
	gold += gained
	print("[INV] sold ", amount, "x", item_id, " gained=", gained, " gold=", gold)

	# remove_item ya emite señal, pero esto cambia gold también:
	inventory_changed.emit()
	return gained


func sell_all(item_id: String, price_per_unit: int) -> int:
	var amount := get_count(item_id)
	if amount <= 0:
		print("[INV] sell_all nothing to sell item=", item_id)
		return 0

	return sell_item(item_id, amount, price_per_unit)


func buy_item(item_id: String, amount: int, cost_per_unit: int) -> bool:
	if amount <= 0:
		print("[INV] buy_item ignored amount<=0 item=", item_id, " amount=", amount)
		return false

	if cost_per_unit < 0:
		print("[INV] buy_item ignored cost<0 item=", item_id, " cost=", cost_per_unit)
		return false

	var cost := amount * cost_per_unit
	if gold < cost:
		print("[INV] buy failed item=", item_id, " need=", cost, " gold=", gold)
		return false

	gold -= cost
	add_item(item_id, amount)
	print("[INV] bought ", amount, "x", item_id, " cost=", cost, " gold=", gold)

	# add_item ya emite señal, pero por claridad:
	inventory_changed.emit()
	return true


func debug_print() -> void:
	print("[INV] gold=", gold, " items=", items)
