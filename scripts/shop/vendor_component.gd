extends Node
class_name VendorComponent

# INFINITE: vende sin consumir stock real del vendor.
# STOCKED: requiere stock real y lo consume al vender.
const VendorOfferScript = preload("res://scripts/shop/vendor_offer.gd")

enum BuybackMode {
	STOCKED_TO_INVENTORY,
	DISCARD,
}

@export var offers: Array[VendorOffer] = []
@export var use_vendor_gold: bool = false
@export var allow_buyback: bool = true
@export var buyback_mode: BuybackMode = BuybackMode.STOCKED_TO_INVENTORY

var inv: InventoryComponent = null
var stock: Dictionary = {}

func _ready() -> void:
	inv = get_parent().get_node_or_null("InventoryComponent") as InventoryComponent
	_init_stocked_offers()

func find_offer(item_id: String) -> VendorOffer:
	for offer in offers:
		if offer != null and offer.item_id == item_id:
			return offer
	return null

func has_offer(item_id: String) -> bool:
	return find_offer(item_id) != null

func get_offer_mode(item_id: String) -> int:
	var offer := find_offer(item_id)
	if offer == null:
		return VendorOfferScript.OfferMode.STOCKED
	return offer.mode

func get_stock(item_id: String) -> int:
	if inv != null:
		return inv.count_item(item_id)
	return int(stock.get(item_id, 0))

func add_stock(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	if inv != null:
		return inv.add_item(item_id, amount)
	stock[item_id] = int(stock.get(item_id, 0)) + amount
	return amount

func remove_stock(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	if inv != null:
		return inv.remove_item(item_id, amount)
	var current := int(stock.get(item_id, 0))
	var removed := mini(current, amount)
	stock[item_id] = current - removed
	return removed

func _init_stocked_offers() -> void:
	for offer in offers:
		if offer == null or offer.mode != VendorOfferScript.OfferMode.STOCKED:
			continue
		if offer.base_stock <= 0:
			continue
		if get_stock(offer.item_id) > 0:
			continue
		add_stock(offer.item_id, offer.base_stock)
