extends CanvasLayer
class_name WorkbenchMenuUi

@onready var craft_button: TextureButton        = $Root/CraftArea/CraftButton
@onready var craft_x10_button: TextureButton    = $Root/CraftArea/BottomCraftButtons/CraftX10Button
@onready var craft_all_button: TextureButton    = $Root/CraftArea/BottomCraftButtons/CraftAllButton
@onready var upgrade_button: TextureButton      = $Root/SidePanelArea/UpgradeButton
@onready var tab_survival: TextureButton        = $Root/Tabs/TabSurvival
@onready var tab_tools: TextureButton           = $Root/Tabs/TabTools
@onready var tab_stations: TextureButton        = $Root/Tabs/TabStations
@onready var tab_tinkering: TextureButton       = $Root/Tabs/TabTinkering


func _ready() -> void:
	visible = false
	add_to_group("workbench_menu_ui")

	# Botones desactivados hasta que haya crafting real
	craft_button.disabled    = true
	craft_x10_button.disabled = true
	craft_all_button.disabled = true
	upgrade_button.disabled  = true

	# TabSurvival activa por defecto
	tab_survival.toggle_mode  = true
	tab_survival.button_pressed = true
	tab_tools.toggle_mode     = true
	tab_tools.button_pressed  = false
	tab_stations.toggle_mode  = true
	tab_stations.button_pressed = false
	tab_tinkering.toggle_mode = true
	tab_tinkering.button_pressed = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		close_menu()
		UiManager.block_interact_for(150)
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	if visible:
		return
	_close_inventory_if_open()
	visible = true
	UiManager.open_ui("workbench")
	UiManager.push_combat_block()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	UiManager.close_ui("workbench")
	UiManager.pop_combat_block()


func is_open() -> bool:
	return visible


func _close_inventory_if_open() -> void:
	var inv_menu := _get_player_inventory_menu()
	if inv_menu != null and inv_menu.visible:
		inv_menu.toggle()


func _get_player_inventory_menu() -> PlayerInventoryMenu:
	var scene := get_tree().current_scene
	if scene != null:
		var by_path := scene.get_node_or_null("UI/PlayerInventoryMenu") as PlayerInventoryMenu
		if by_path != null:
			return by_path
	for node in get_tree().get_nodes_in_group("inventory_ui"):
		if node is PlayerInventoryMenu:
			return node as PlayerInventoryMenu
	return null


func _exit_tree() -> void:
	if visible:
		close_menu()
