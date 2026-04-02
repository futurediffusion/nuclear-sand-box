extends Node

const ShopPortScript := preload("res://scripts/systems/shop_port.gd")

@export var sell_ratio_default: float = 0.5
@export var debug_shop_tx: bool = false
@export var debug_shop_tx_assert: bool = true

var _port: ShopPort

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

func _sync_port_config() -> void:
	if _port == null:
		return
	_port.sell_ratio_default = sell_ratio_default
	_port.debug_shop_tx = debug_shop_tx
	_port.debug_shop_tx_assert = debug_shop_tx_assert
