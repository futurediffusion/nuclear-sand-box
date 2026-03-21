extends CanvasLayer
class_name WorkbenchMenuUi

const RECIPE_SLOT_SCENE:    PackedScene = preload("res://scenes/ui/crafting_recipe_slot.tscn")
const INGREDIENT_ROW_SCENE: PackedScene = preload("res://scenes/ui/crafting_ingredient_row.tscn")
const TIER_REQ_SLOT_SCENE:  PackedScene = preload("res://scenes/ui/tier_requirement_slot.tscn")
const CRAFT_SFX: AudioStream = preload("res://art/Sounds/craft.ogg")
const DEFAULT_WORKBENCH_OPEN_SFX: AudioStream = preload("res://art/Sounds/workbenchopen.ogg")
const DEFAULT_WORKBENCH_CLOSE_SFX: AudioStream = preload("res://art/Sounds/workbenchclose.ogg")
const DEFAULT_WORKBENCH_SELECT_RECIPE_SFX: AudioStream = preload("res://art/Sounds/chooseitem.ogg")
const DEFAULT_WORKBENCH_TAB_SFX: AudioStream = preload("res://art/Sounds/workbenchtab.ogg")
const DEFAULT_WORKBENCH_OPEN_VOLUME_DB: float = 0.0
const DEFAULT_WORKBENCH_CLOSE_VOLUME_DB: float = 0.0
const DEFAULT_WORKBENCH_SELECT_RECIPE_VOLUME_DB: float = 0.0
const DEFAULT_WORKBENCH_TAB_VOLUME_DB: float = 0.0

# Materiales para subir la workbench de Tier 1 → Tier 2.
# Cambiar aquí cuando se implemente el sistema de tiers real.
const TIER_2_REQUIREMENTS: Array = [
	{"item_id": "stone",  "amount": 50},
	{"item_id": "copper", "amount": 30},
	{"item_id": "book",   "amount": 10},
]

# ── Botones de craft ──────────────────────────────────────────────────────────
@onready var craft_button:     TextureButton = $Root/CraftArea/CraftButton
@onready var craft_x10_button: TextureButton = $Root/CraftArea/BottomCraftButtons/CraftX10Button
@onready var craft_all_button: TextureButton = $Root/CraftArea/BottomCraftButtons/CraftAllButton
@onready var upgrade_button:   TextureButton = $Root/SidePanelArea/UpgradeButton

# ── Tabs ─────────────────────────────────────────────────────────────────────
@onready var tab_survival:  TextureButton = $Root/Tabs/TabSurvival
@onready var tab_tools:     TextureButton = $Root/Tabs/TabTools
@onready var tab_stations:  TextureButton = $Root/Tabs/TabStations
@onready var tab_tinkering: TextureButton = $Root/Tabs/TabTinkering
@onready var tab_title:     Label         = $Root/Tabs/TabTitle

# ── Panel de recetas ──────────────────────────────────────────────────────────
@onready var recipe_grid:       GridContainer = $Root/CraftArea/RecipeGridAnchor/RecipeScroll/RecipeGrid
@onready var ingredients_vbox:  VBoxContainer = $Root/CraftArea/IngredientsAnchor/VBoxContainer
@onready var result_title:      Label         = $Root/CraftArea/PreviewAnchor/ResultTitleLabel
@onready var result_icon:       TextureRect   = $Root/CraftArea/PreviewAnchor/ResultIcon

# ── Panel lateral ─────────────────────────────────────────────────────────────
# Nota: "WorkbenchTierLabe" es un typo en la escena — no lo cambiamos.
@onready var workbench_tier_label: Label      = $Root/SidePanelArea/WorkbenchPreviewAnchor/WorkbenchTierLabe
@onready var workbench_icon:       TextureRect = $Root/SidePanelArea/WorkbenchPreviewAnchor/WorkbenchIcon
@onready var tier_req_title:       Label      = $Root/SidePanelArea/TierRequirementsAnchor/TierRequirementsTitleLabel
@onready var tier_req_hbox:        HBoxContainer = $Root/SidePanelArea/TierRequirementsAnchor/TierRequirementsList

# ── Panel de inventario del player ───────────────────────────────────────────
@onready var player_panel: InventoryPanel = $Root/Playerbox/PlayerInventoryPanel

# ── Estado ───────────────────────────────────────────────────────────────────
var _selected_recipe: CraftingRecipe = null
var _current_category: String = "survival"
var _slot_nodes: Array[Control] = []
var _connected_inventory: InventoryComponent = null
var _tier_req_slots: Array[Dictionary] = []  # [{slot, item_id, needed}]
var _inventory_refresh_queued: bool = false


func _ready() -> void:
	visible = false
	add_to_group("workbench_menu_ui")
	UiManager.force_close_all.connect(close_menu)

	# Craft desactivado hasta que haya una receta seleccionada y materiales
	craft_button.disabled     = true
	craft_x10_button.disabled = true
	craft_all_button.disabled = true
	upgrade_button.disabled   = true

	craft_button.pressed.connect(_try_craft_one)
	craft_x10_button.pressed.connect(_try_craft_x10)
	craft_all_button.pressed.connect(_try_craft_all)

	_setup_tabs()
	_setup_side_panel()

	# Poblar al final del frame para asegurar que CraftingDB ya terminó _ready()
	call_deferred("_populate_grid")


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		close_menu()
		UiManager.block_interact_for(150)
		get_viewport().set_input_as_handled()


# ── API pública ───────────────────────────────────────────────────────────────

func open_menu() -> void:
	if visible:
		return
	_close_inventory_if_open()
	visible = true
	UiManager.open_ui("workbench")
	UiManager.push_combat_block()
	_play_workbench_open_sfx()
	_reset_recipe_selection()
	_connect_player_inventory()
	_populate_grid()
	_queue_inventory_dependent_refresh()


func close_menu() -> void:
	if not visible:
		return
	_disconnect_player_inventory()
	_reset_recipe_selection()
	visible = false
	UiManager.close_ui("workbench")
	UiManager.pop_combat_block()
	_play_workbench_close_sfx()


func is_open() -> bool:
	return visible


# ── Tabs ──────────────────────────────────────────────────────────────────────

func _setup_tabs() -> void:
	tab_survival.toggle_mode    = true
	tab_survival.button_pressed = true
	tab_tools.toggle_mode       = true
	tab_tools.button_pressed    = false
	tab_stations.toggle_mode    = true
	tab_stations.button_pressed = false
	tab_tinkering.toggle_mode   = true
	tab_tinkering.button_pressed = false

	tab_survival.pressed.connect(func(): _switch_tab("survival",  "Survival"))
	tab_tools.pressed.connect(func():    _switch_tab("tools",     "Tools"))
	tab_stations.pressed.connect(func(): _switch_tab("stations",  "Stations"))
	tab_tinkering.pressed.connect(func():_switch_tab("tinkering", "Tinkering"))


func _switch_tab(category: String, title: String) -> void:
	if _current_category == category:
		return
	_current_category = category
	_play_workbench_tab_sfx()
	tab_title.text = title

	tab_survival.button_pressed  = (category == "survival")
	tab_tools.button_pressed     = (category == "tools")
	tab_stations.button_pressed  = (category == "stations")
	tab_tinkering.button_pressed = (category == "tinkering")

	_reset_recipe_selection()
	_populate_grid()


# ── Panel lateral estático ────────────────────────────────────────────────────

func _setup_side_panel() -> void:
	workbench_tier_label.text = "Tier 1"
	tier_req_title.text = "Tier 2 Requirements"
	var wb_tex := _get_item_icon("workbench")
	if wb_tex != null:
		workbench_icon.texture = wb_tex
	_setup_tier_requirements()


func _setup_tier_requirements() -> void:
	for child in tier_req_hbox.get_children():
		child.queue_free()
	_tier_req_slots.clear()

	for req in TIER_2_REQUIREMENTS:
		var item_id: String = String(req["item_id"])
		var needed: int     = int(req["amount"])

		var slot: Control = TIER_REQ_SLOT_SCENE.instantiate() as Control
		slot.custom_minimum_size = Vector2(50, 62)
		tier_req_hbox.add_child(slot)

		var icon_node := slot.get_node_or_null("icon") as TextureRect
		if icon_node != null:
			icon_node.texture      = _get_item_icon(item_id)
			icon_node.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		_tier_req_slots.append({"slot": slot, "item_id": item_id, "needed": needed})

	# Mostrar estado inicial (sin inventario conectado aún)
	_refresh_tier_requirements()


func _refresh_tier_requirements() -> void:
	var inventory := _get_player_inventory()
	var all_met := true

	for data in _tier_req_slots:
		var slot:    Control = data["slot"]
		var item_id: String  = String(data["item_id"])
		var needed:  int     = int(data["needed"])
		var has:     int     = _count_in_inventory(inventory, item_id)
		var met:     bool    = has >= needed
		if not met:
			all_met = false

		var amount_label := slot.get_node_or_null("AmountLabel") as Label
		if amount_label != null:
			amount_label.text = "%d/%d" % [has, needed]
			amount_label.add_theme_color_override(
				"font_color",
				Color(0.4, 1.0, 0.4) if met else Color(1.0, 0.4, 0.4)
			)

	upgrade_button.disabled = not all_met


# ── Grid de recetas ───────────────────────────────────────────────────────────

func _populate_grid() -> void:
	for child in recipe_grid.get_children():
		child.queue_free()
	_slot_nodes.clear()
	_reset_recipe_selection()

	var crafting_db := get_node_or_null("/root/CraftingDB")
	if crafting_db == null:
		push_warning("[WorkbenchMenuUi] CraftingDB autoload no encontrado")
		return

	var recipes: Array = crafting_db.call("get_recipes_for_category", _current_category)
	for recipe in recipes:
		_add_recipe_slot(recipe as CraftingRecipe)


func _add_recipe_slot(recipe: CraftingRecipe) -> void:
	var slot: Control = RECIPE_SLOT_SCENE.instantiate() as Control
	slot.custom_minimum_size = Vector2(96, 68)
	recipe_grid.add_child(slot)
	_slot_nodes.append(slot)

	var icon_node := slot.get_node_or_null("Icon") as TextureRect
	if icon_node != null:
		icon_node.texture = _get_item_icon(recipe.result_item_id)
		icon_node.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var count_label := slot.get_node_or_null("CountLabel") as Label
	if count_label != null:
		count_label.visible = recipe.result_count > 1
		count_label.text    = "×%d" % recipe.result_count

	var overlay := slot.get_node_or_null("SelectedOverlay") as TextureRect
	if overlay != null:
		overlay.visible = false

	slot.set_meta("recipe", recipe)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_slot_gui_input.bind(slot))


func _on_slot_gui_input(event: InputEvent, slot: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_select_recipe(slot.get_meta("recipe") as CraftingRecipe)
		slot.accept_event()


# ── Selección de receta ───────────────────────────────────────────────────────

func _select_recipe(recipe: CraftingRecipe) -> void:
	if recipe == null:
		_reset_recipe_selection()
		return

	# Garantiza que el menú lea el inventario actual al momento de seleccionar.
	_connect_player_inventory()
	_selected_recipe = recipe

	# Actualizar overlays de selección
	for slot in _slot_nodes:
		var overlay := slot.get_node_or_null("SelectedOverlay") as TextureRect
		if overlay != null:
			overlay.visible = (slot.get_meta("recipe") as CraftingRecipe) == recipe

	_update_result_preview(recipe)
	_refresh_selected_recipe_ui()
	# Refresco diferido para cubrir cambios del inventario aplicados al final del frame.
	_queue_inventory_dependent_refresh()
	_play_workbench_recipe_select_sfx()


func _update_result_preview(recipe: CraftingRecipe) -> void:
	var name_str := _get_item_display_name(recipe.result_item_id)
	result_title.text = name_str if name_str != "" else recipe.result_item_id
	result_icon.texture = _get_item_icon(recipe.result_item_id)
	if result_icon.texture != null:
		result_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		result_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _update_ingredients_panel(recipe: CraftingRecipe) -> void:
	for child in ingredients_vbox.get_children():
		child.queue_free()

	var inventory := _get_player_inventory()

	for ing in recipe.get_ingredients():
		var item_id: String = String(ing["item_id"])
		var needed:  int    = int(ing["amount"])
		var has:     int    = _count_in_inventory(inventory, item_id)

		var row: Control = INGREDIENT_ROW_SCENE.instantiate() as Control
		row.custom_minimum_size = Vector2(100, 50)
		ingredients_vbox.add_child(row)

		var icon_node := row.get_node_or_null("Icon") as TextureRect
		if icon_node != null:
			icon_node.texture      = _get_item_icon(item_id)
			icon_node.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var name_label := row.get_node_or_null("IgredientNameLabel") as Label
		if name_label != null:
			var display := _get_item_display_name(item_id)
			name_label.text = display if display != "" else item_id

		var amount_label := row.get_node_or_null("AmountLabel") as Label
		if amount_label != null:
			amount_label.text = "%d / %d" % [has, needed]
			amount_label.add_theme_color_override(
				"font_color",
				Color(0.4, 1.0, 0.4) if has >= needed else Color(1.0, 0.4, 0.4)
			)

		var glow := row.get_node_or_null("EnoughGlow") as TextureRect
		if glow != null:
			glow.visible = has >= needed


func _update_craft_button_state() -> void:
	_update_all_craft_buttons()


func _update_all_craft_buttons() -> void:
	if _selected_recipe == null:
		craft_button.disabled     = true
		craft_x10_button.disabled = true
		craft_all_button.disabled = true
		return
	var inventory := _get_player_inventory()
	var max_n := _max_craftable(_selected_recipe, inventory)
	craft_button.disabled     = max_n < 1
	craft_x10_button.disabled = max_n < 10
	craft_all_button.disabled = max_n < 1


func _max_craftable(recipe: CraftingRecipe, inventory: InventoryComponent) -> int:
	if inventory == null or recipe == null:
		return 0
	var max_n := 9999
	for ing in recipe.get_ingredients():
		var item_id: String = String(ing["item_id"])
		var needed:  int    = int(ing["amount"])
		if needed <= 0:
			continue
		var has: int = _count_in_inventory(inventory, item_id)
		max_n = mini(max_n, has / needed)
	if max_n <= 0:
		return 0
	if not inventory.has_method("has_space_for"):
		return max_n
	# Check if all results fit; binary search if not
	if bool(inventory.call("has_space_for", recipe.result_item_id, recipe.result_count * max_n)):
		return max_n
	var lo := 1
	var hi := max_n - 1
	var best := 0
	while lo <= hi:
		var mid := (lo + hi) / 2
		if bool(inventory.call("has_space_for", recipe.result_item_id, recipe.result_count * mid)):
			best = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return best


func _clear_preview() -> void:
	result_title.text    = ""
	result_icon.texture  = null
	for child in ingredients_vbox.get_children():
		child.queue_free()
	craft_button.disabled     = true
	craft_x10_button.disabled = true
	craft_all_button.disabled = true


# ── Helpers ───────────────────────────────────────────────────────────────────

func _reset_recipe_selection() -> void:
	_selected_recipe = null
	for slot in _slot_nodes:
		var overlay := slot.get_node_or_null("SelectedOverlay") as TextureRect
		if overlay != null:
			overlay.visible = false
	_clear_preview()


func _refresh_selected_recipe_ui() -> void:
	if _selected_recipe != null:
		_update_ingredients_panel(_selected_recipe)
	_update_all_craft_buttons()


func _queue_inventory_dependent_refresh() -> void:
	if _inventory_refresh_queued:
		return
	_inventory_refresh_queued = true
	call_deferred("_flush_inventory_dependent_refresh")


func _flush_inventory_dependent_refresh() -> void:
	_inventory_refresh_queued = false
	_refresh_selected_recipe_ui()
	_refresh_tier_requirements()


func _connect_player_inventory() -> void:
	var inv := _get_player_inventory()
	if inv == _connected_inventory:
		if player_panel != null and inv != null:
			player_panel.set_inventory(inv)
		_queue_inventory_dependent_refresh()
		return
	_disconnect_player_inventory()
	_connected_inventory = inv
	if inv == null:
		_queue_inventory_dependent_refresh()
		return
	player_panel.set_inventory(inv)
	if not inv.inventory_changed.is_connected(_on_player_inventory_changed):
		inv.inventory_changed.connect(_on_player_inventory_changed)
	if not inv.slot_changed.is_connected(_on_player_inventory_slot_changed):
		inv.slot_changed.connect(_on_player_inventory_slot_changed)
	_queue_inventory_dependent_refresh()


func _disconnect_player_inventory() -> void:
	if _connected_inventory == null:
		return
	if _connected_inventory.inventory_changed.is_connected(_on_player_inventory_changed):
		_connected_inventory.inventory_changed.disconnect(_on_player_inventory_changed)
	if _connected_inventory.slot_changed.is_connected(_on_player_inventory_slot_changed):
		_connected_inventory.slot_changed.disconnect(_on_player_inventory_slot_changed)
	_connected_inventory = null


func _on_player_inventory_changed() -> void:
	_queue_inventory_dependent_refresh()


func _on_player_inventory_slot_changed(_slot_index: int) -> void:
	_queue_inventory_dependent_refresh()


func _get_player_inventory() -> InventoryComponent:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0].get_node_or_null("InventoryComponent") as InventoryComponent


func _count_in_inventory(inventory: InventoryComponent, item_id: String) -> int:
	if inventory == null:
		return 0
	if inventory.has_method("get_total"):
		return int(inventory.call("get_total", item_id))
	return 0


func _get_item_icon(item_id: String) -> Texture2D:
	var db := get_node_or_null("/root/ItemDB")
	if db == null or not db.has_method("get_icon"):
		return null
	return db.get_icon(item_id) as Texture2D


func _get_item_display_name(item_id: String) -> String:
	var db := get_node_or_null("/root/ItemDB")
	if db == null or not db.has_method("get_display_name"):
		return ""
	return String(db.get_display_name(item_id))


func _close_inventory_if_open() -> void:
	var inv_menu := _get_player_inventory_menu()
	if inv_menu != null and inv_menu.visible:
		inv_menu.close()


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


func _try_craft_one() -> void:
	if _execute_craft(_selected_recipe, 1):
		_play_craft_sfx()
		_refresh_after_craft()


func _try_craft_x10() -> void:
	if _execute_craft(_selected_recipe, 10):
		_play_craft_sfx()
		_refresh_after_craft()


func _try_craft_all() -> void:
	var inventory := _get_player_inventory()
	var max_n := _max_craftable(_selected_recipe, inventory)
	if max_n <= 0:
		return
	if _execute_craft(_selected_recipe, max_n):
		_play_craft_sfx()
		_refresh_after_craft()


func _play_craft_sfx() -> void:
	if CRAFT_SFX == null:
		return
	AudioSystem.play_1d(CRAFT_SFX, null, &"SFX")


func _play_workbench_open_sfx() -> void:
	var panel := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_WORKBENCH_OPEN_SFX
	var volume_db: float = DEFAULT_WORKBENCH_OPEN_VOLUME_DB
	if panel != null:
		if panel.workbench_open_sfx != null:
			stream = panel.workbench_open_sfx
		volume_db = panel.workbench_open_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _play_workbench_close_sfx() -> void:
	var panel := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_WORKBENCH_CLOSE_SFX
	var volume_db: float = DEFAULT_WORKBENCH_CLOSE_VOLUME_DB
	if panel != null:
		if panel.workbench_close_sfx != null:
			stream = panel.workbench_close_sfx
		volume_db = panel.workbench_close_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _play_workbench_recipe_select_sfx() -> void:
	var panel := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_WORKBENCH_SELECT_RECIPE_SFX
	var volume_db: float = DEFAULT_WORKBENCH_SELECT_RECIPE_VOLUME_DB
	if panel != null:
		if panel.workbench_select_recipe_sfx != null:
			stream = panel.workbench_select_recipe_sfx
		volume_db = panel.workbench_select_recipe_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _play_workbench_tab_sfx() -> void:
	var panel := _resolve_sound_panel()
	var stream: AudioStream = DEFAULT_WORKBENCH_TAB_SFX
	var volume_db: float = DEFAULT_WORKBENCH_TAB_VOLUME_DB
	if panel != null:
		if panel.workbench_tab_sfx != null:
			stream = panel.workbench_tab_sfx
		volume_db = panel.workbench_tab_volume_db
	if stream != null:
		AudioSystem.play_1d(stream, null, &"SFX", volume_db)


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null


func _execute_craft(recipe: CraftingRecipe, times: int) -> bool:
	if recipe == null or times <= 0:
		return false
	var inventory := _get_player_inventory()
	if inventory == null:
		return false

	# Pre-validate: enough materials and output space
	if _max_craftable(recipe, inventory) < times:
		return false

	# Atomic transaction
	if inventory.has_method("begin_batch"):
		inventory.call("begin_batch")

	var removed: Array[Dictionary] = []
	var ok := true
	for ing in recipe.get_ingredients():
		var item_id: String = String(ing["item_id"])
		var needed:  int    = int(ing["amount"]) * times
		var actually_removed: int = 0
		if inventory.has_method("remove_item"):
			actually_removed = int(inventory.call("remove_item", item_id, needed))
		if actually_removed < needed:
			ok = false
			removed.append({"item_id": item_id, "amount": actually_removed})
			break
		removed.append({"item_id": item_id, "amount": actually_removed})

	if ok:
		var total_result := recipe.result_count * times
		var added: int = 0
		if inventory.has_method("add_item"):
			added = int(inventory.call("add_item", recipe.result_item_id, total_result))
		if added < total_result:
			ok = false

	if not ok:
		for entry in removed:
			if inventory.has_method("add_item"):
				inventory.call("add_item", String(entry["item_id"]), int(entry["amount"]))

	if inventory.has_method("end_batch"):
		inventory.call("end_batch")

	return ok


func _refresh_after_craft() -> void:
	_queue_inventory_dependent_refresh()


func _exit_tree() -> void:
	_disconnect_player_inventory()
	if visible:
		close_menu()
