extends CanvasLayer
class_name KeeperMenuUi

@onready var player_panel: InventoryPanel = $Root/Panel/ContentArea/Layout/Playerbox/PlayerInventoryPanel
@onready var keeper_panel: InventoryPanel = $Root/Panel/ContentArea/Layout/KeeperBox/KeeperInventoryPanel

var _player_inv: InventoryComponent = null
var _vendor: VendorComponent = null
var _keeper_inv: InventoryComponent = null
var _refresh_queued: bool = false


func _ready() -> void:
	visible = false
	player_panel.slot_clicked.connect(_on_player_slot_clicked)
	keeper_panel.slot_clicked.connect(_on_keeper_slot_clicked)


func toggle() -> void:
	visible = not visible
	print("[MENU] toggle visible=", visible)
	if visible:
		UiManager.open_ui("shop")
	else:
		UiManager.close_ui("shop")


func set_player_inventory(inv: InventoryComponent) -> void:
	if _player_inv != null and _player_inv.inventory_changed.is_connected(_on_inventory_changed):
		_player_inv.inventory_changed.disconnect(_on_inventory_changed)
	_player_inv = inv
	if _player_inv != null and not _player_inv.inventory_changed.is_connected(_on_inventory_changed):
		_player_inv.inventory_changed.connect(_on_inventory_changed)
	player_panel.set_inventory(inv)


func set_keeper_inventory(inv: InventoryComponent) -> void:
	if _keeper_inv != null and _keeper_inv.inventory_changed.is_connected(_on_inventory_changed):
		_keeper_inv.inventory_changed.disconnect(_on_inventory_changed)
	_keeper_inv = inv
	if _keeper_inv != null and not _keeper_inv.inventory_changed.is_connected(_on_inventory_changed):
		_keeper_inv.inventory_changed.connect(_on_inventory_changed)
	keeper_panel.set_inventory(inv)
	_queue_refresh_keeper_slot_meta()


func set_vendor(vendor: VendorComponent) -> void:
	if _vendor != null and _vendor.inv != null and _vendor.inv.inventory_changed.is_connected(_on_inventory_changed):
		_vendor.inv.inventory_changed.disconnect(_on_inventory_changed)
	_vendor = vendor
	if _vendor != null and _vendor.inv != null and not _vendor.inv.inventory_changed.is_connected(_on_inventory_changed):
		_vendor.inv.inventory_changed.connect(_on_inventory_changed)
	_queue_refresh_keeper_slot_meta()
	if vendor != null:
		keeper_panel.set_price_resolver(func(item_id: String) -> int:
			return ShopService.get_buy_price(vendor, item_id)
		)
		player_panel.set_price_resolver(func(item_id: String) -> int:
			return ShopService.get_sell_price(vendor, item_id)
		)
	else:
		keeper_panel.set_price_resolver(Callable())
		player_panel.set_price_resolver(Callable())


func _on_player_slot_clicked(slot_index: int, _button: int) -> void:
	if _player_inv == null or _vendor == null:
		return
	var item_id := _get_item_from_slot(_player_inv, slot_index)
	if item_id == "":
		return
	_try_sell_item(item_id, _resolve_click_amount())


func _on_keeper_slot_clicked(slot_index: int, _button: int) -> void:
	if _player_inv == null or _vendor == null:
		return
	var meta := keeper_panel.get_slot_meta(slot_index)
	var item_id := String(meta.get("item_id", ""))
	if item_id == "":
		return
	_try_buy_item(meta, _resolve_click_amount())


func _try_sell_item(item_id: String, amount: int) -> void:
	if _vendor == null or _player_inv == null:
		return
	# KeeperMenuUi no muta inventario ni oro directamente.
	# ShopService es la única autoridad de transacciones.
	var check := ShopService.can_sell(_vendor, _player_inv, item_id, amount)
	if not bool(check.get("ok", false)):
		print("[SHOP][UI] sell blocked reason=", check.get("reason", "UNKNOWN"))
		return
	ShopService.sell(_vendor, _player_inv, item_id, amount)
	_queue_refresh_keeper_slot_meta()


func _try_buy_item(slot_meta: Dictionary, amount: int) -> void:
	if _vendor == null or _player_inv == null:
		return
	var item_id := String(slot_meta.get("item_id", ""))
	if item_id == "":
		return
	# KeeperMenuUi no muta inventario ni oro directamente.
	# ShopService es la única autoridad de transacciones.
	var check := ShopService.can_buy_from_meta(_vendor, _player_inv, slot_meta, amount)
	if not bool(check.get("ok", false)):
		print("[SHOP][UI] buy blocked reason=", check.get("reason", "UNKNOWN"))
		return
	ShopService.buy_from_meta(_vendor, _player_inv, slot_meta, amount)
	_queue_refresh_keeper_slot_meta()


func _get_item_from_slot(inv: InventoryComponent, slot_index: int) -> String:
	if inv == null:
		return ""
	if slot_index < 0 or slot_index >= inv.max_slots:
		return ""
	var data = inv.slots[slot_index]
	if data == null:
		return ""
	return String(data.get("id", ""))


func _refresh_keeper_slot_meta() -> void:
	_refresh_queued = false
	keeper_panel.clear_slot_meta()
	if _vendor == null:
		return

	var used_item_ids: Dictionary = {}
	var cursor := 0

	var keeper_inv := _vendor.inv
	if keeper_inv != null:
		for slot_index in range(keeper_inv.max_slots):
			var item_id := _get_item_from_slot(keeper_inv, slot_index)
			if item_id == "":
				continue
			keeper_panel.set_slot_meta(cursor, {
				"item_id": item_id,
				"source": "INV",
				"slot_index": slot_index,
			})
			used_item_ids[item_id] = true
			cursor += 1

	for offer_index in range(_vendor.offers.size()):
		var offer: VendorOffer = _vendor.offers[offer_index]
		if offer == null:
			continue
		var item_id := String(offer.item_id)
		if item_id == "":
			continue
		if used_item_ids.has(item_id):
			continue

		var best_offer_idx := _choose_offer_index_for_item(item_id)
		keeper_panel.set_slot_meta(cursor, {
			"item_id": item_id,
			"source": "OFFER",
			"offer_index": best_offer_idx,
		})
		used_item_ids[item_id] = true
		cursor += 1


func _choose_offer_index_for_item(item_id: String) -> int:
	if _vendor == null:
		return -1
	var best_idx := -1
	var best_score := -1
	for i in range(_vendor.offers.size()):
		var offer: VendorOffer = _vendor.offers[i]
		if offer == null or String(offer.item_id) != item_id:
			continue
		var score := 0
		if offer.buy_price_override > 0:
			score += 2
		if offer.sell_price_override > 0:
			score += 1
		if score > best_score:
			best_score = score
			best_idx = i
	return best_idx


func _queue_refresh_keeper_slot_meta() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_keeper_slot_meta")


func _on_inventory_changed() -> void:
	_queue_refresh_keeper_slot_meta()


func _resolve_click_amount() -> int:
	return 5 if Input.is_key_pressed(KEY_SHIFT) else 1
