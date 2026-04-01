extends Node
class_name ShopPort

const VendorOfferScript = preload("res://scripts/shop/vendor_offer.gd")

var sell_ratio_default: float = 0.5
var debug_shop_tx: bool = false
var debug_shop_tx_assert: bool = true

const _WATCHED_ITEM_IDS: Array[String] = ["arrow", "copper"]

func get_buy_price(vendor: VendorComponent, item_id: String) -> int:
	if vendor == null:
		return 0
	var offer := vendor.find_offer(item_id)
	if offer == null:
		return 0
	if offer.buy_price_override > 0:
		return offer.buy_price_override
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return 0
	return maxi(0, int(item_db.get_buy_price(item_id, 0)))

func get_sell_price(vendor: VendorComponent, item_id: String) -> int:
	if vendor == null:
		return 0
	var offer := vendor.find_offer(item_id)
	if offer != null and offer.sell_price_override > 0:
		return offer.sell_price_override
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return 0
	var item_data: ItemData = item_db.get_item(item_id)
	if item_data == null:
		return 0
	if item_data.sell_price > 0:
		return item_data.sell_price
	return maxi(0, int(floor(float(item_data.buy_price) * sell_ratio_default)))

func can_buy(vendor: VendorComponent, buyer_inv: InventoryComponent, item_id: String, amount: int) -> Dictionary:
	if vendor == null or buyer_inv == null or amount <= 0:
		return {"ok": false, "reason": "INVALID", "cost": 0}
	var offer := vendor.find_offer(item_id)
	if offer == null:
		return {"ok": false, "reason": "NO_OFFER", "cost": 0}
	var unit_price := get_buy_price(vendor, item_id)
	var cost := unit_price * amount
	if buyer_inv.gold < cost:
		return {"ok": false, "reason": "NO_GOLD", "cost": cost}
	if not buyer_inv.can_add(item_id, amount):
		return {"ok": false, "reason": "NO_SPACE", "cost": cost}
	if offer.mode == VendorOfferScript.OfferMode.STOCKED and vendor.get_stock(item_id) < amount:
		return {"ok": false, "reason": "NO_STOCK", "cost": cost}
	return {"ok": true, "reason": "OK", "cost": cost}

func can_buy_from_meta(vendor: VendorComponent, buyer_inv: InventoryComponent, slot_meta: Dictionary, amount: int) -> Dictionary:
	var item_id := String(slot_meta.get("item_id", ""))
	if item_id == "":
		return {"ok": false, "reason": "INVALID", "cost": 0}
	if not _is_buyable_slot_meta(vendor, slot_meta, item_id):
		return {"ok": false, "reason": "NO_OFFER", "cost": 0}
	return can_buy(vendor, buyer_inv, item_id, amount)

func buy(vendor: VendorComponent, buyer_inv: InventoryComponent, item_id: String, amount: int, debug_context: Dictionary = {}) -> Dictionary:
	var check := can_buy(vendor, buyer_inv, item_id, amount)
	var offer_mode := "NONE"
	var stock_src := "DICT"
	if vendor != null:
		var vendor_offer := vendor.find_offer(item_id)
		if vendor_offer != null:
			offer_mode = "INFINITE" if vendor_offer.mode == VendorOfferScript.OfferMode.INFINITE else "STOCKED"
		stock_src = "INV" if vendor.inv != null else "DICT"
	if not check.ok:
		print("[SHOP][BUY] item=", item_id, " amt=", amount, " cost=", check.cost, " ok=false reason=", check.reason, " offer_mode=", offer_mode, " stock_src=", stock_src)
		return _result(false, String(check.reason), int(check.cost), item_id, amount)

	var cost := int(check.cost)
	var offer := vendor.find_offer(item_id)
	var stock_before := vendor.get_stock(item_id)
	var removed_stock := 0
	var buyer_gold_before := buyer_inv.gold
	var buyer_begin_batch := buyer_inv.has_method("begin_batch")
	var vendor_inv := vendor.inv if vendor != null else null
	var vendor_begin_batch := vendor_inv != null and vendor_inv.has_method("begin_batch")
	var result := _result(false, "INVALID", cost, item_id, amount)

	if buyer_begin_batch:
		buyer_inv.begin_batch()
	if vendor_begin_batch:
		vendor_inv.begin_batch()

	var tx_context := _build_tx_context("BUY", item_id, amount, cost, buyer_inv, vendor_inv, debug_context)
	var before := _capture_tx_snapshot(tx_context)

	if offer.mode == VendorOfferScript.OfferMode.STOCKED:
		removed_stock = vendor.remove_stock(item_id, amount)
		if removed_stock < amount:
			if removed_stock > 0:
				vendor.add_stock(item_id, removed_stock)
			result = _result(false, "NO_STOCK", cost, item_id, amount)
		else:
			var inserted := buyer_inv.add_item(item_id, amount)
			if inserted < amount:
				vendor.add_stock(item_id, removed_stock)
				result = _result(false, "NO_SPACE", cost, item_id, amount)
			elif not buyer_inv.spend_gold(cost):
				buyer_inv.remove_item(item_id, amount)
				vendor.add_stock(item_id, removed_stock)
				result = _result(false, "NO_GOLD", cost, item_id, amount)
			else:
				if vendor.use_vendor_gold and vendor_inv != null:
					vendor_inv.add_gold(cost)
				result = _result(true, "OK", cost, item_id, amount)
	else:
		var inserted_infinite := buyer_inv.add_item(item_id, amount)
		if inserted_infinite < amount:
			result = _result(false, "NO_SPACE", cost, item_id, amount)
		elif not buyer_inv.spend_gold(cost):
			buyer_inv.remove_item(item_id, amount)
			result = _result(false, "NO_GOLD", cost, item_id, amount)
		else:
			if vendor.use_vendor_gold and vendor_inv != null:
				vendor_inv.add_gold(cost)
			result = _result(true, "OK", cost, item_id, amount)
			if item_id == "bandage":
				print("[SHOP] bought bandage infinite=true")

	if vendor_begin_batch:
		vendor_inv.end_batch()
	if buyer_begin_batch:
		buyer_inv.end_batch()

	if _enforce_tx_invariants(tx_context, before):
		return _result(false, "TX_INVARIANT", cost, item_id, amount)

	print("[SHOP][BUY] item=", item_id, " amt=", amount, " cost=", cost, " ok=", result.ok, " reason=", result.reason, " offer_mode=", offer_mode, " stock_src=", stock_src, " stock_before=", stock_before, " stock_after=", vendor.get_stock(item_id), " buyer_gold_before=", buyer_gold_before, " buyer_gold_after=", buyer_inv.gold)
	return result

func buy_from_meta(vendor: VendorComponent, buyer_inv: InventoryComponent, slot_meta: Dictionary, amount: int) -> Dictionary:
	var safe_meta := slot_meta.duplicate(true)
	var item_id := String(safe_meta.get("item_id", ""))
	if item_id == "":
		return _result(false, "INVALID", 0, item_id, amount)
	if not _is_buyable_slot_meta(vendor, safe_meta, item_id):
		return _result(false, "NO_OFFER", 0, item_id, amount)
	return buy(vendor, buyer_inv, item_id, amount, safe_meta)

func can_sell(vendor: VendorComponent, seller_inv: InventoryComponent, item_id: String, amount: int) -> Dictionary:
	if vendor == null or seller_inv == null or amount <= 0:
		return {"ok": false, "reason": "INVALID", "payout": 0}
	if seller_inv.count_item(item_id) < amount:
		return {"ok": false, "reason": "NO_ITEM", "payout": 0}
	var payout := get_sell_price(vendor, item_id) * amount
	if vendor.use_vendor_gold:
		if vendor.inv == null or vendor.inv.gold < payout:
			return {"ok": false, "reason": "VENDOR_NO_GOLD", "payout": payout}
	return {"ok": true, "reason": "OK", "payout": payout}

func sell(vendor: VendorComponent, seller_inv: InventoryComponent, item_id: String, amount: int, debug_context: Dictionary = {}) -> Dictionary:
	var check := can_sell(vendor, seller_inv, item_id, amount)
	var is_infinite_offer := _is_infinite_offer(vendor, item_id)
	print("[SHOP][SELL] check_infinite_offer item=%s infinite=%s" % [item_id, str(is_infinite_offer)])
	var buyback_mode := "NONE"
	var stock_src := "DICT"
	if vendor != null:
		buyback_mode = "STOCKED_TO_INVENTORY" if vendor.buyback_mode == VendorComponent.BuybackMode.STOCKED_TO_INVENTORY else "DISCARD"
		stock_src = "INV" if vendor.inv != null else "DICT"
	if not check.ok:
		print("[SHOP][SELL] item=", item_id, " amt=", amount, " payout=", check.payout, " ok=false reason=", check.reason, " buyback_mode=", buyback_mode, " stock_src=", stock_src)
		return _result(false, String(check.reason), int(check.payout), item_id, amount)

	var payout := int(check.payout)
	var seller_gold_before := seller_inv.gold
	var stock_before := vendor.get_stock(item_id)
	var seller_begin_batch := seller_inv.has_method("begin_batch")
	var vendor_inv := vendor.inv if vendor != null else null
	var vendor_begin_batch := vendor_inv != null and vendor_inv.has_method("begin_batch")
	var result := _result(false, "INVALID", payout, item_id, amount)

	if seller_begin_batch:
		seller_inv.begin_batch()
	if vendor_begin_batch:
		vendor_inv.begin_batch()

	var tx_context := _build_tx_context("SELL", item_id, amount, payout, seller_inv, vendor_inv, debug_context)
	var before := _capture_tx_snapshot(tx_context)

	var removed := seller_inv.remove_item(item_id, amount)
	if removed < amount:
		result = _result(false, "NO_ITEM", payout, item_id, amount)
	else:
		seller_inv.add_gold(payout)
		if vendor.use_vendor_gold and vendor_inv != null:
			vendor_inv.spend_gold(payout)
		if is_infinite_offer:
			buyback_mode = "SINK_INFINITE_OFFER"
		elif vendor.allow_buyback and vendor.buyback_mode == VendorComponent.BuybackMode.STOCKED_TO_INVENTORY:
			vendor.add_stock(item_id, amount)
		result = _result(true, "OK", payout, item_id, amount)

	if vendor_begin_batch:
		vendor_inv.end_batch()
	if seller_begin_batch:
		seller_inv.end_batch()

	if _enforce_tx_invariants(tx_context, before):
		return _result(false, "TX_INVARIANT", payout, item_id, amount)

	print("[SHOP][SELL] item=", item_id, " amt=", amount, " payout=", payout, " ok=", result.ok, " reason=", result.reason, " buyback_mode=", buyback_mode, " stock_src=", stock_src, " stock_before=", stock_before, " stock_after=", vendor.get_stock(item_id), " seller_gold_before=", seller_gold_before, " seller_gold_after=", seller_inv.gold)
	return result

func debug_run_randomized_tx_test(seed: int = 1337, steps: int = 20) -> Dictionary:
	if steps <= 0:
		return {"ok": false, "reason": "INVALID_STEPS", "steps": steps}

	var previous_debug := debug_shop_tx
	debug_shop_tx = true

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var player := InventoryComponent.new()
	player.max_slots = 20
	player._ready()
	player.add_gold(1000)
	player.add_item("arrow", 12)
	player.add_item("copper", 8)
	player.add_item("bandage", 4)

	var keeper := InventoryComponent.new()
	keeper.max_slots = 20
	keeper._ready()
	keeper.add_gold(1000)

	var vendor := VendorComponent.new()
	vendor.inv = keeper
	vendor.use_vendor_gold = true
	vendor.allow_buyback = true
	vendor.buyback_mode = VendorComponent.BuybackMode.STOCKED_TO_INVENTORY

	var offer_arrow := VendorOffer.new()
	offer_arrow.item_id = "arrow"
	offer_arrow.mode = VendorOfferScript.OfferMode.STOCKED
	offer_arrow.buy_price_override = 2
	offer_arrow.sell_price_override = 1

	var offer_copper := VendorOffer.new()
	offer_copper.item_id = "copper"
	offer_copper.mode = VendorOfferScript.OfferMode.STOCKED
	offer_copper.buy_price_override = 4
	offer_copper.sell_price_override = 2

	var offer_bandage := VendorOffer.new()
	offer_bandage.item_id = "bandage"
	offer_bandage.mode = VendorOfferScript.OfferMode.STOCKED
	offer_bandage.buy_price_override = 6
	offer_bandage.sell_price_override = 3

	vendor.offers = [offer_arrow, offer_copper, offer_bandage]
	keeper.add_item("arrow", 20)
	keeper.add_item("copper", 20)
	keeper.add_item("bandage", 20)

	var item_pool := ["arrow", "copper", "bandage"]
	for i in range(steps):
		var item_id := String(item_pool[rng.randi_range(0, item_pool.size() - 1)])
		var amount := rng.randi_range(1, 3)
		if rng.randf() < 0.5:
			buy(vendor, player, item_id, amount, {"source": "debug_random", "step": i})
		else:
			sell(vendor, player, item_id, amount, {"source": "debug_random", "step": i})

	debug_shop_tx = previous_debug
	return {"ok": true, "reason": "OK", "seed": seed, "steps": steps}

func _is_infinite_offer(vendor: VendorComponent, item_id: String) -> bool:
	if vendor == null:
		return false
	var offer := vendor.find_offer(item_id)
	if offer == null:
		return false
	return offer.mode == VendorOfferScript.OfferMode.INFINITE

func _result(ok: bool, reason: String, cost_or_payout: int, item_id: String, amount: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"cost_or_payout": cost_or_payout,
		"item_id": item_id,
		"amount": amount,
	}

func _is_buyable_slot_meta(vendor: VendorComponent, slot_meta: Dictionary, item_id: String) -> bool:
	if vendor == null:
		return false
	var source := String(slot_meta.get("source", ""))
	match source:
		"INV":
			return vendor.get_stock(item_id) > 0
		"OFFER":
			if slot_meta.has("offer_index"):
				var offer_idx := int(slot_meta.get("offer_index", -1))
				var offer := vendor.find_offer_by_index(offer_idx)
				return offer != null and String(offer.item_id) == item_id
			return vendor.has_offer(item_id)
		_:
			return vendor.has_offer(item_id)

func _build_tx_context(op: String, item_id: String, qty: int, price_total: int, player_inv: InventoryComponent, keeper_inv: InventoryComponent, debug_context: Dictionary) -> Dictionary:
	var ctx := debug_context.duplicate(true)
	ctx["op"] = op
	ctx["item_id"] = item_id
	ctx["qty"] = qty
	ctx["price_total"] = price_total
	ctx["player_inv"] = player_inv
	ctx["keeper_inv"] = keeper_inv
	ctx["player_inv_id"] = player_inv.get_instance_id() if player_inv != null else -1
	ctx["keeper_inv_id"] = keeper_inv.get_instance_id() if keeper_inv != null else -1
	var watched: Array[String] = _WATCHED_ITEM_IDS.duplicate()
	if item_id != "" and not watched.has(item_id):
		watched.append(item_id)
	ctx["watched_ids"] = watched
	return ctx

func _capture_tx_snapshot(context: Dictionary) -> Dictionary:
	return {
		"player": _tx_debug_snapshot(context.get("player_inv"), context),
		"keeper": _tx_debug_snapshot(context.get("keeper_inv"), context),
	}

func _tx_debug_snapshot(inv: InventoryComponent, context: Dictionary) -> Dictionary:
	var watched := context.get("watched_ids", []) as Array[String]
	var items: Dictionary = {}
	if inv != null:
		for item_id in watched:
			items[item_id] = inv.count_item(item_id)
	return {
		"instance_id": inv.get_instance_id() if inv != null else -1,
		"gold": inv.gold if inv != null else 0,
		"items": items,
		"serial": _serialize_inventory_short(inv),
	}

func _serialize_inventory_short(inv: InventoryComponent) -> String:
	if inv == null:
		return "null"
	var parts: Array[String] = []
	for i in range(inv.max_slots):
		var stack = inv.slots[i]
		if stack == null:
			continue
		var slot_id := String(stack.get("id", ""))
		var slot_count := int(stack.get("count", 0))
		if slot_id == "" or slot_count <= 0:
			continue
		parts.append("%d:%s:%d" % [i, slot_id, slot_count])
	return "|".join(parts)

func _enforce_tx_invariants(context: Dictionary, before: Dictionary) -> bool:
	if not debug_shop_tx:
		return false
	var after := _capture_tx_snapshot(context)
	print("[SHOP][TX] op=%s item_id=%s qty=%s price_total=%s player_inv=%s keeper_inv=%s ctx=%s" % [
		str(context.get("op", "?")),
		str(context.get("item_id", "")),
		str(context.get("qty", 0)),
		str(context.get("price_total", 0)),
		str(context.get("player_inv_id", -1)),
		str(context.get("keeper_inv_id", -1)),
		str(context),
	])
	print("[SHOP][TX][BEFORE] %s" % str(before))
	print("[SHOP][TX][AFTER] %s" % str(after))

	var item_id := String(context.get("item_id", ""))
	var corruption_reasons: Array[String] = []

	if item_id != "arrow" and _snapshot_item_delta(before, after, "arrow") != 0:
		corruption_reasons.append("arrow_changed")
	if item_id != "copper" and _snapshot_item_delta(before, after, "copper") != 0:
		corruption_reasons.append("copper_changed")

	if corruption_reasons.is_empty():
		return false

	var corruption_msg := "[SHOP][TX][BUG] cross-item mutation detected reasons=%s slot_index=%s ui_slot=%s offer_index=%s meta=%s source=%s" % [
		str(corruption_reasons),
		str(context.get("slot_index", -1)),
		str(context.get("ui_slot", -1)),
		str(context.get("offer_index", -1)),
		str(context),
		str(context.get("source", "unknown")),
	]
	push_error(corruption_msg)
	if debug_shop_tx_assert:
		assert(false, corruption_msg)
	return true

func _snapshot_item_delta(before: Dictionary, after: Dictionary, item_id: String) -> int:
	var before_player := int(before.get("player", {}).get("items", {}).get(item_id, 0))
	var before_keeper := int(before.get("keeper", {}).get("items", {}).get(item_id, 0))
	var after_player := int(after.get("player", {}).get("items", {}).get(item_id, 0))
	var after_keeper := int(after.get("keeper", {}).get("items", {}).get(item_id, 0))
	return (after_player + after_keeper) - (before_player + before_keeper)
