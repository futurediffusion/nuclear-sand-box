extends CanvasLayer

@onready var player_panel: InventoryPanel = $Root/Panel/PlayerPanel
@onready var shop_panel: InventoryPanel = $Root/Panel/ShopPanel

var _player_inv: InventoryComponent = null
var _shop_inv: InventoryComponent = null

# Para test rápido: cantidad a mover por click (1 unidad)
@export var transfer_amount: int = 1

func _ready() -> void:
	visible = false

func open(player_inv: InventoryComponent, shop_inv: InventoryComponent) -> void:
	_player_inv = player_inv
	_shop_inv = shop_inv
	visible = true

	# Conecta inventarios a panels
	player_panel.set_inventory(_player_inv)
	shop_panel.set_inventory(_shop_inv)

	# Conecta clicks una sola vez
	if not player_panel.slot_clicked.is_connected(_on_player_slot_clicked):
		player_panel.slot_clicked.connect(_on_player_slot_clicked)

	if not shop_panel.slot_clicked.is_connected(_on_shop_slot_clicked):
		shop_panel.slot_clicked.connect(_on_shop_slot_clicked)

func close() -> void:
	visible = false

func toggle(player_inv: InventoryComponent, shop_inv: InventoryComponent) -> void:
	if visible:
		close()
	else:
		open(player_inv, shop_inv)

# -------------------------
# Click handlers (ESTO es lo que te faltaba)
# -------------------------
func _on_player_slot_clicked(slot_index: int, button: int) -> void:
	# VENDER: player -> shop con click izquierdo
	if button != MOUSE_BUTTON_LEFT:
		return
	_transfer_from_to(_player_inv, _shop_inv, slot_index, transfer_amount)

func _on_shop_slot_clicked(slot_index: int, button: int) -> void:
	# COMPRAR: shop -> player con click izquierdo
	if button != MOUSE_BUTTON_LEFT:
		return
	_transfer_from_to(_shop_inv, _player_inv, slot_index, transfer_amount)

# -------------------------
# Transfer core (usa tu API real)
# -------------------------
func _transfer_from_to(from_inv: InventoryComponent, to_inv: InventoryComponent, from_slot_index: int, amount: int) -> void:
	if from_inv == null or to_inv == null:
		return

	# slot data: null o {"id": String, "count": int}
	if from_slot_index < 0 or from_slot_index >= from_inv.max_slots:
		return

	var s = from_inv.slots[from_slot_index]
	if s == null:
		return

	var item_id: String = String(s["id"])
	if item_id == "":
		return

	var have: int = int(s["count"])
	if have <= 0:
		return

	var to_move: int = mini(amount, have)

	# 1) intenta meter en destino
	var inserted: int = to_inv.add_item(item_id, to_move)
	if inserted <= 0:
		return

	# 2) quita del origen lo que realmente se insertó
	from_inv.remove_item(item_id, inserted)
