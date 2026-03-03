extends CanvasLayer
class_name KeeperMenuUi

const VendorOfferScript = preload("res://scripts/shop/vendor_offer.gd")

signal shop_opened(owner: Node)
signal shop_closed(owner: Node)

@onready var player_panel: InventoryPanel = $Root/Panel/ContentArea/Layout/Playerbox/PlayerInventoryPanel
@onready var keeper_panel: InventoryPanel = $Root/Panel/ContentArea/Layout/KeeperBox/KeeperInventoryPanel

var _player_inv: InventoryComponent = null
var _vendor: VendorComponent = null
var _keeper_inv: InventoryComponent = null
var _refresh_queued: bool = false
var _current_owner: Node = null
var _closing_shop: bool = false


func _ready() -> void:
	visible = false
	add_to_group("keeper_menu_ui")
	set_process_input(true)
	var root := get_node_or_null("Root") as Control
	if root != null:
		root.focus_mode = Control.FOCUS_ALL
	if not player_panel.slot_clicked.is_connected(_on_player_slot_clicked):
		player_panel.slot_clicked.connect(_on_player_slot_clicked)
	if not keeper_panel.slot_clicked.is_connected(_on_keeper_slot_clicked):
		keeper_panel.slot_clicked.connect(_on_keeper_slot_clicked)


func _process(_delta: float) -> void:
	if not visible:
		return
	if _current_owner == null or not is_instance_valid(_current_owner):
		close_shop()


func toggle() -> void:
	if visible:
		close_shop()
	else:
		open_shop(_current_owner)


func open_shop(owner: Node) -> void:
	if visible and _current_owner == owner:
		return
	if visible and _current_owner != owner:
		close_shop()

	visible = true
	_current_owner = owner
	UiManager.open_ui("shop")
	UiManager.push_combat_block()
	var root := get_node_or_null("Root") as Control
	if root != null:
		root.grab_focus()
	shop_opened.emit(_current_owner)


func close_shop() -> void:
	if not visible or _closing_shop:
		return
	_closing_shop = true
	var closed_owner := _current_owner
	visible = false
	_current_owner = null
	UiManager.close_ui("shop")
	UiManager.pop_combat_block()
	shop_closed.emit(closed_owner)
	_closing_shop = false


func is_shop_open() -> bool:
	return visible


func is_owner(owner: Node) -> bool:
	return visible and _current_owner == owner


func set_player_inventory(inv: InventoryComponent) -> void:
	if _player_inv != null and _player_inv.inventory_changed.is_connected(_on_inventory_changed):
		_player_inv.inventory_changed.disconnect(_on_inventory_changed)
	_player_inv = inv
	if _player_inv != null and not _player_inv.inventory_changed.is_connected(_on_inventory_changed):
		_player_inv.inventory_changed.connect(_on_inventory_changed)
	player_panel.set_inventory(inv)
	player_panel.set_shop_context(_vendor, _player_inv, "SELL")


func set_keeper_inventory(inv: InventoryComponent) -> void:
	if _keeper_inv != null and _keeper_inv.inventory_changed.is_connected(_on_inventory_changed):
		_keeper_inv.inventory_changed.disconnect(_on_inventory_changed)
	_keeper_inv = inv
	if _keeper_inv != null and not _keeper_inv.inventory_changed.is_connected(_on_inventory_changed):
		_keeper_inv.inventory_changed.connect(_on_inventory_changed)
	keeper_panel.set_inventory(inv)
	keeper_panel.set_shop_context(_vendor, _player_inv, "BUY")
	_queue_refresh_keeper_slot_meta()


func set_vendor(vendor: VendorComponent) -> void:
	if _vendor != null and _vendor.inv != null and _vendor.inv.inventory_changed.is_connected(_on_inventory_changed):
		_vendor.inv.inventory_changed.disconnect(_on_inventory_changed)
	_vendor = vendor
	if _vendor != null and _vendor.inv != null and not _vendor.inv.inventory_changed.is_connected(_on_inventory_changed):
		_vendor.inv.inventory_changed.connect(_on_inventory_changed)
	_queue_refresh_keeper_slot_meta()
	keeper_panel.set_shop_context(_vendor, _player_inv, "BUY")
	player_panel.set_shop_context(_vendor, _player_inv, "SELL")
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
	var meta := keeper_panel.get_slot_meta(slot_index).duplicate(true)
	var item_id := String(meta.get("item_id", ""))
	if OS.is_debug_build():
		print("[SHOP][UI] click BUY slot=%d item=%s offer_index=%s meta=%s" % [slot_index, item_id, str(meta.get("offer_index", -1)), str(meta)])
	if item_id == "":
		return
	meta["ui_slot"] = slot_index
	meta["source"] = String(meta.get("source", "ui_keeper_slot"))
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
	ShopService.sell(_vendor, _player_inv, item_id, amount, {
		"source": "ui_player_slot",
		"ui_slot": -1,
		"slot_index": -1,
		"offer_index": -1,
		"meta": {"item_id": item_id},
	})
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
		print("[SHOP][UI] buy blocked reason=%s slot_meta=%s" % [str(check.get("reason", "UNKNOWN")), str(slot_meta)])
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
		keeper_panel.call_deferred("_refresh")
		return

	if OS.is_debug_build():
		print("[SHOP] offers_count=%d" % _vendor.offers.size())
		for i in range(_vendor.offers.size()):
			var dbg_offer: VendorOffer = _vendor.offers[i]
			if dbg_offer == null:
				print("[SHOP] offer[%d] id=<null> mode=<null>" % i)
				continue
			var dbg_mode := "INFINITE" if dbg_offer.mode == VendorOfferScript.OfferMode.INFINITE else "STOCKED"
			print("[SHOP] offer[%d] id=%s mode=%s" % [i, dbg_offer.item_id, dbg_mode])

	var used_item_ids: Dictionary = {}
	var cursor := 0

	var keeper_inv := _vendor.inv
	if keeper_inv != null:
		for slot_index in range(keeper_inv.max_slots):
			var item_id := _get_item_from_slot(keeper_inv, slot_index)
			if item_id == "":
				continue
			if used_item_ids.has(item_id):
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

	keeper_panel.call_deferred("_refresh")


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



func _on_root_gui_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventMouseButton:
		var mouse_ev := ev as InputEventMouseButton
		if mouse_ev.pressed:
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	var interact_pressed := event.is_action_pressed("interact")
	var cancel_pressed := event.is_action_pressed("ui_cancel")
	var fallback_key_e: bool = false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		fallback_key_e = key_event.pressed and not key_event.echo and key_event.keycode == KEY_E

	print(
		"[SHOP][INPUT] keeper_menu_ui _input instance=", get_instance_id(),
		" owner=", _current_owner,
		" shop_open=", is_shop_open(),
		" event=", event.as_text(),
		" interact=", interact_pressed,
		" ui_cancel=", cancel_pressed,
		" fallback_key_e=", fallback_key_e
	)

	if interact_pressed or cancel_pressed or fallback_key_e:
		print("[SHOP][INPUT] keeper_menu_ui closing shop by input instance=", get_instance_id())
		close_shop()
		UiManager.block_interact_for(150)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and visible and get_tree().paused:
		close_shop()


func _exit_tree() -> void:
	if visible:
		close_shop()
