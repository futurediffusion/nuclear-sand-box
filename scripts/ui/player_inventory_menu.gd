extends CanvasLayer
class_name PlayerInventoryMenu

const DEFAULT_INVENTORY_OPEN_SFX: AudioStream = preload("res://art/Sounds/inventoryopen.ogg")
const DEFAULT_INVENTORY_CLOSE_SFX: AudioStream = preload("res://art/Sounds/inventoryclose.ogg")
const DEFAULT_INVENTORY_OPEN_VOLUME_DB: float = 0.0
const DEFAULT_INVENTORY_CLOSE_VOLUME_DB: float = 0.0

@onready var panel: InventoryPanel = $Root/InventoryPanel

var _inv: InventoryComponent = null

func _ready() -> void:
	visible = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory"):
		close()
		UiManager.block_interact_for(150)
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	if visible:
		return
	_close_keeper_menu_if_open()
	_close_container_ui_if_open()
	_close_workbench_menu_if_open()
	visible = true
	UiManager.open_ui("inventory")
	UiManager.push_combat_block()
	_play_inventory_open_sfx()
	call_deferred("_bind_player_inventory")

func close() -> void:
	if not visible:
		return
	if panel != null:
		panel.cancel_drag()
	visible = false
	UiManager.close_ui("inventory")
	UiManager.pop_combat_block()
	_play_inventory_close_sfx()


func _close_keeper_menu_if_open() -> void:
	var keeper_menu := _get_keeper_menu_ui()
	if keeper_menu != null and keeper_menu.is_shop_open():
		keeper_menu.close_shop()


func _close_container_ui_if_open() -> void:
	var container_ui := _get_container_ui()
	if container_ui == null:
		return
	var is_open := bool(container_ui.visible)
	if container_ui.has_method("is_open"):
		is_open = bool(container_ui.call("is_open"))
	if not is_open:
		return
	if container_ui.has_method("close_menu"):
		container_ui.call("close_menu")
		return
	container_ui.visible = false


func _close_workbench_menu_if_open() -> void:
	var workbench_menu := _get_workbench_menu_ui()
	if workbench_menu == null:
		return
	var is_open := bool(workbench_menu.visible)
	if workbench_menu.has_method("is_open"):
		is_open = bool(workbench_menu.call("is_open"))
	if not is_open:
		return
	if workbench_menu.has_method("close_menu"):
		workbench_menu.call("close_menu")
		return
	workbench_menu.visible = false


func _get_container_ui() -> CanvasLayer:
	var scene := get_tree().current_scene
	if scene != null:
		var by_container_path := scene.get_node_or_null("UI/ContainerUi") as CanvasLayer
		if by_container_path != null:
			return by_container_path
		var by_chest_path := scene.get_node_or_null("UI/ChestUi") as CanvasLayer
		if by_chest_path != null:
			return by_chest_path
	for node in get_tree().get_nodes_in_group("container_ui"):
		if node is CanvasLayer:
			return node as CanvasLayer
	for node in get_tree().get_nodes_in_group("chest_ui"):
		if node is CanvasLayer:
			return node as CanvasLayer
	return null


func _get_workbench_menu_ui() -> CanvasLayer:
	var scene := get_tree().current_scene
	if scene != null:
		var by_path := scene.get_node_or_null("UI/WorkbenchMenuUi") as CanvasLayer
		if by_path != null:
			return by_path
	for node in get_tree().get_nodes_in_group("workbench_menu_ui"):
		if node is CanvasLayer:
			return node as CanvasLayer
	return null


func _get_keeper_menu_ui() -> KeeperMenuUi:
	var scene := get_tree().current_scene
	if scene != null:
		var by_path := scene.get_node_or_null("UI/KeeperMenuUi") as KeeperMenuUi
		if by_path != null:
			return by_path
	for node in get_tree().get_nodes_in_group("keeper_menu_ui"):
		if node is KeeperMenuUi:
			return node as KeeperMenuUi
	return null

func _on_root_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mouse_ev := ev as InputEventMouseButton
		if mouse_ev.pressed:
			get_viewport().set_input_as_handled()

func _on_texture_rect_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mouse_ev := ev as InputEventMouseButton
		if mouse_ev.pressed:
			get_viewport().set_input_as_handled()

func _bind_player_inventory() -> void:
	var player := get_tree().current_scene.get_node_or_null("Player")
	if player == null:
		var arr := get_tree().get_nodes_in_group("player")
		if arr.size() > 0:
			player = arr[0]

	if player == null:
		return

	var inv := player.get_node_or_null("InventoryComponent") as InventoryComponent
	if inv == null:
		return

	_inv = inv
	panel.set_inventory(inv)
	if not panel.placeable_requested.is_connected(_on_placeable_requested):
		panel.placeable_requested.connect(_on_placeable_requested)


func _on_placeable_requested(item_id: String) -> void:
	var item_db := get_node_or_null("/root/ItemDB")
	var icon: Texture2D = null
	if item_db != null and item_db.has_method("get_icon"):
		icon = item_db.get_icon(item_id) as Texture2D
	close()  # cerrar inventario
	PlacementSystem.begin_placement(item_id, icon)


func _play_inventory_open_sfx() -> void:
	var panel_sound := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_INVENTORY_OPEN_SFX
	var volume_db: float = DEFAULT_INVENTORY_OPEN_VOLUME_DB
	if panel_sound != null:
		if panel_sound.inventory_open_sfx != null:
			stream = panel_sound.inventory_open_sfx
		volume_db = panel_sound.inventory_open_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _play_inventory_close_sfx() -> void:
	var panel_sound := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_INVENTORY_CLOSE_SFX
	var volume_db: float = DEFAULT_INVENTORY_CLOSE_VOLUME_DB
	if panel_sound != null:
		if panel_sound.inventory_close_sfx != null:
			stream = panel_sound.inventory_close_sfx
		volume_db = panel_sound.inventory_close_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null
