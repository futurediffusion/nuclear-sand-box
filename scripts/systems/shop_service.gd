extends Node

const VendorOfferScript = preload("res://scripts/shop/vendor_offer.gd")

@export var sell_ratio_default: float = 0.5

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

func buy(vendor: VendorComponent, buyer_inv: InventoryComponent, item_id: String, amount: int) -> Dictionary:
	var check := can_buy(vendor, buyer_inv, item_id, amount)
	var offer_mode := "NONE"
	if vendor != null:
		var offer := vendor.find_offer(item_id)
		if offer != null:
			offer_mode = "INFINITE" if offer.mode == VendorOfferScript.OfferMode.INFINITE else "STOCKED"
	if not check.ok:
		print("[SHOP][BUY] item=", item_id, " amt=", amount, " cost=", check.cost, " ok=false reason=", check.reason, " offer_mode=", offer_mode)
		return _result(false, String(check.reason), int(check.cost), item_id, amount)

	var cost := int(check.cost)
	var removed_stock := 0
	var offer := vendor.find_offer(item_id)
	if offer.mode == VendorOfferScript.OfferMode.STOCKED:
		removed_stock = vendor.remove_stock(item_id, amount)
		if removed_stock < amount:
			if removed_stock > 0:
				vendor.add_stock(item_id, removed_stock)
			print("[SHOP][BUY] item=", item_id, " amt=", amount, " cost=", cost, " ok=false reason=NO_STOCK offer_mode=STOCKED")
			return _result(false, "NO_STOCK", cost, item_id, amount)

	var inserted := buyer_inv.add_item(item_id, amount)
	if inserted < amount:
		if offer.mode == VendorOfferScript.OfferMode.STOCKED:
			vendor.add_stock(item_id, removed_stock)
		print("[SHOP][BUY] item=", item_id, " amt=", amount, " cost=", cost, " ok=false reason=NO_SPACE offer_mode=", offer_mode)
		return _result(false, "NO_SPACE", cost, item_id, amount)

	if not buyer_inv.spend_gold(cost):
		buyer_inv.remove_item(item_id, amount)
		if offer.mode == VendorOfferScript.OfferMode.STOCKED:
			vendor.add_stock(item_id, removed_stock)
		print("[SHOP][BUY] item=", item_id, " amt=", amount, " cost=", cost, " ok=false reason=NO_GOLD offer_mode=", offer_mode)
		return _result(false, "NO_GOLD", cost, item_id, amount)

	if vendor.use_vendor_gold and vendor.inv != null:
		vendor.inv.add_gold(cost)

	print("[SHOP][BUY] item=", item_id, " amt=", amount, " cost=", cost, " ok=true reason=OK offer_mode=", offer_mode)
	return _result(true, "OK", cost, item_id, amount)

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

func sell(vendor: VendorComponent, seller_inv: InventoryComponent, item_id: String, amount: int) -> Dictionary:
	var check := can_sell(vendor, seller_inv, item_id, amount)
	var buyback_mode := "NONE"
	if vendor != null:
		buyback_mode = "STOCKED_TO_INVENTORY" if vendor.buyback_mode == VendorComponent.BuybackMode.STOCKED_TO_INVENTORY else "DISCARD"
	if not check.ok:
		print("[SHOP][SELL] item=", item_id, " amt=", amount, " payout=", check.payout, " ok=false reason=", check.reason, " buyback_mode=", buyback_mode)
		return _result(false, String(check.reason), int(check.payout), item_id, amount)

	var removed := seller_inv.remove_item(item_id, amount)
	if removed < amount:
		print("[SHOP][SELL] item=", item_id, " amt=", amount, " payout=", check.payout, " ok=false reason=NO_ITEM buyback_mode=", buyback_mode)
		return _result(false, "NO_ITEM", int(check.payout), item_id, amount)

	var payout := int(check.payout)
	seller_inv.add_gold(payout)
	if vendor.use_vendor_gold and vendor.inv != null:
		vendor.inv.spend_gold(payout)

	if vendor.allow_buyback:
		if vendor.buyback_mode == VendorComponent.BuybackMode.STOCKED_TO_INVENTORY:
			vendor.add_stock(item_id, amount)

	print("[SHOP][SELL] item=", item_id, " amt=", amount, " payout=", payout, " ok=true reason=OK buyback_mode=", buyback_mode)
	return _result(true, "OK", payout, item_id, amount)

func _result(ok: bool, reason: String, cost_or_payout: int, item_id: String, amount: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"cost_or_payout": cost_or_payout,
		"item_id": item_id,
		"amount": amount,
	}
