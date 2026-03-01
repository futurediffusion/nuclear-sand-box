extends Resource
class_name VendorOffer

enum OfferMode {
	INFINITE,
	STOCKED,
}

@export var item_id: String = ""
@export var mode: OfferMode = OfferMode.INFINITE
@export var base_stock: int = 0
@export var buy_price_override: int = 0
@export var sell_price_override: int = 0
@export var restock_enabled: bool = false
@export var restock_rate: float = 0.0
@export var restock_amount: int = 0
