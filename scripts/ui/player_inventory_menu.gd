extends CanvasLayer
class_name PlayerInventoryMenu

@onready var panel: InventoryPanel = $Root/InventoryPanel

func _ready() -> void:
	visible = false

func toggle() -> void:
	visible = not visible
	if visible:
		_bind_player_inventory()
	print("[PIM] toggle visible=", visible)

func _bind_player_inventory() -> void:
	var player := get_tree().current_scene.get_node_or_null("Player")
	if player == null:
		var arr := get_tree().get_nodes_in_group("player")
		if arr.size() > 0:
			player = arr[0]

	if player != null:
		var inv := player.get_node_or_null("InventoryComponent") as InventoryComponent
		if inv != null:
			panel.set_inventory(inv)
