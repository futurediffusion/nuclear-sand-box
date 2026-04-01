extends Node

const ShopPortScript := preload("res://scripts/systems/shop_port.gd")

## DEPRECATION(2026-04-01): Este autoload mantiene compatibilidad con API legacy.
## Fecha objetivo de retiro del adaptador: 2026-09-30, cuando telemetry reporte 0 usos.
@export var sell_ratio_default: float = 0.5
@export var debug_shop_tx: bool = false
@export var debug_shop_tx_assert: bool = true

var _port: ShopPort
var _legacy_call_count: Dictionary = {}
var _legacy_deprecation_warned: Dictionary = {}

func _ready() -> void:
	_port = ShopPortScript.new()
	_port.name = "ShopPort"
	add_child(_port)
	_sync_port_config()

func get_port() -> ShopPort:
	if _port == null:
		_port = ShopPortScript.new()
		_port.name = "ShopPort"
		add_child(_port)
	_sync_port_config()
	return _port

func get_legacy_telemetry_snapshot() -> Dictionary:
	return _legacy_call_count.duplicate(true)

func has_legacy_consumers() -> bool:
	for key in _legacy_call_count.keys():
		if int(_legacy_call_count[key]) > 0:
			return true
	return false

func _track_legacy(route: String) -> void:
	_legacy_call_count[route] = int(_legacy_call_count.get(route, 0)) + 1
	if _legacy_deprecation_warned.get(route, false):
		return
	_legacy_deprecation_warned[route] = true
	push_warning("[ShopService][DEPRECATED][retire:2026-09-30] Ruta legacy usada: %s. Migrar al puerto ShopService.get_port()." % route)

func _sync_port_config() -> void:
	if _port == null:
		return
	_port.sell_ratio_default = sell_ratio_default
	_port.debug_shop_tx = debug_shop_tx
	_port.debug_shop_tx_assert = debug_shop_tx_assert

## API LEGACY (adapter) -----------------------------------------------------
## DEPRECATION(2026-04-01): usar ShopService.get_port().get_buy_price(...)
func get_buy_price(vendor: VendorComponent, item_id: String) -> int:
	_track_legacy("get_buy_price")
	return get_port().get_buy_price(vendor, item_id)

## DEPRECATION(2026-04-01): usar ShopService.get_port().get_sell_price(...)
func get_sell_price(vendor: VendorComponent, item_id: String) -> int:
	_track_legacy("get_sell_price")
	return get_port().get_sell_price(vendor, item_id)

## DEPRECATION(2026-04-01): usar ShopService.get_port().can_buy(...)
func can_buy(vendor: VendorComponent, buyer_inv: InventoryComponent, item_id: String, amount: int) -> Dictionary:
	_track_legacy("can_buy")
	return get_port().can_buy(vendor, buyer_inv, item_id, amount)

## DEPRECATION(2026-04-01): usar ShopService.get_port().can_buy_from_meta(...)
func can_buy_from_meta(vendor: VendorComponent, buyer_inv: InventoryComponent, slot_meta: Dictionary, amount: int) -> Dictionary:
	_track_legacy("can_buy_from_meta")
	return get_port().can_buy_from_meta(vendor, buyer_inv, slot_meta, amount)

## DEPRECATION(2026-04-01): usar ShopService.get_port().buy(...)
func buy(vendor: VendorComponent, buyer_inv: InventoryComponent, item_id: String, amount: int, debug_context: Dictionary = {}) -> Dictionary:
	_track_legacy("buy")
	return get_port().buy(vendor, buyer_inv, item_id, amount, debug_context)

## DEPRECATION(2026-04-01): usar ShopService.get_port().buy_from_meta(...)
func buy_from_meta(vendor: VendorComponent, buyer_inv: InventoryComponent, slot_meta: Dictionary, amount: int) -> Dictionary:
	_track_legacy("buy_from_meta")
	return get_port().buy_from_meta(vendor, buyer_inv, slot_meta, amount)

## DEPRECATION(2026-04-01): usar ShopService.get_port().can_sell(...)
func can_sell(vendor: VendorComponent, seller_inv: InventoryComponent, item_id: String, amount: int) -> Dictionary:
	_track_legacy("can_sell")
	return get_port().can_sell(vendor, seller_inv, item_id, amount)

## DEPRECATION(2026-04-01): usar ShopService.get_port().sell(...)
func sell(vendor: VendorComponent, seller_inv: InventoryComponent, item_id: String, amount: int, debug_context: Dictionary = {}) -> Dictionary:
	_track_legacy("sell")
	return get_port().sell(vendor, seller_inv, item_id, amount, debug_context)

## DEPRECATION(2026-04-01): usar ShopService.get_port().debug_run_randomized_tx_test(...)
func debug_run_randomized_tx_test(seed: int = 1337, steps: int = 20) -> Dictionary:
	_track_legacy("debug_run_randomized_tx_test")
	return get_port().debug_run_randomized_tx_test(seed, steps)
