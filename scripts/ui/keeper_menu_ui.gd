extends CanvasLayer
class_name KeeperMenuUi

@onready var player_panel: InventoryPanel = $Root/Panel/ContentArea/Layout/Playerbox/PlayerInventoryPanel
@onready var keeper_panel: InventoryPanel = $Root/Panel/ContentArea/Layout/KeeperBox/KeeperInventoryPanel

var _player_inv: InventoryComponent = null
var _vendor: VendorComponent = null


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
	_player_inv = inv
	player_panel.set_inventory(inv)


func set_keeper_inventory(inv: InventoryComponent) -> void:
	keeper_panel.set_inventory(inv)

func set_vendor(vendor: VendorComponent) -> void:
	_vendor = vendor
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
	_try_sell_item(item_id, 1)


func _on_keeper_slot_clicked(slot_index: int, _button: int) -> void:
	if _player_inv == null or _vendor == null:
		return
	var keeper_inv := _vendor.inv
	if keeper_inv == null:
		return
	var item_id := _get_item_from_slot(keeper_inv, slot_index)
	if item_id == "":
		return
	_try_buy_item(item_id, 1)


func _try_sell_item(item_id: String, amount: int) -> void:
	# KeeperMenuUi no muta inventario ni oro directamente.
	# ShopService es la única autoridad de transacciones.
	var check := ShopService.can_sell(_vendor, _player_inv, item_id, amount)
	if not bool(check.get("ok", false)):
		print("[SHOP][UI] sell blocked reason=", check.get("reason", "UNKNOWN"))
		return
	ShopService.sell(_vendor, _player_inv, item_id, amount)


func _try_buy_item(item_id: String, amount: int) -> void:
	# KeeperMenuUi no muta inventario ni oro directamente.
	# ShopService es la única autoridad de transacciones.
	var check := ShopService.can_buy(_vendor, _player_inv, item_id, amount)
	if not bool(check.get("ok", false)):
		print("[SHOP][UI] buy blocked reason=", check.get("reason", "UNKNOWN"))
		return
	ShopService.buy(_vendor, _player_inv, item_id, amount)

func _get_item_from_slot(inv: InventoryComponent, slot_index: int) -> String:
	if inv == null:
		return ""
	if slot_index < 0 or slot_index >= inv.max_slots:
		return ""
	var data = inv.slots[slot_index]
	if data == null:
		return ""
	return String(data.get("id", ""))
