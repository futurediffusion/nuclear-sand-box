extends Node
class_name CommandSystem

## Sistema de comandos de consola del juego.
## Maneja la UI de la barra de comandos y la ejecución de todos los comandos /xxx.
## Se instancia desde main.gd vía setup().

const ENEMY_SCENE: PackedScene      = preload("res://scenes/enemy.tscn")
const WORKBENCH_SCENE: PackedScene  = preload("res://scenes/placeables/workbench_world.tscn")
const SENTINEL_SCENE: PackedScene   = preload("res://scenes/sentinel.tscn")

const COMMAND_PREFIX          := "/"
const COMMAND_BAR_HEIGHT      := 34.0
const MAX_SUGGESTIONS         := 8
const SUGGESTION_ROW_H        := 22.0
const SUGGESTION_PANEL_MAX_W  := 380.0

## Árbol de autocompletado. Valor vacío = sin subcomandos conocidos.
const COMMAND_COMPLETIONS: Dictionary = {
	"give":            [],
	"gv":              [],
	"dog":             [],
	"set_day":         [],
	"set_night":       [],
	"summon":          ["enemy", "sentinel"],
	"sentinel":        ["warn", "eject", "subdue", "return"],
	"spawn":           [],
	"spawn_workbench": [],
	"inv":             [],
	"gotocamp":        [],
	"camp":            [],
	"sellall":         [],
	"buydbg":          [],
}
const COMMAND_SPAWN_MIN_DIST  := 56.0
const COMMAND_SPAWN_MAX_DIST  := 110.0
const DEFAULT_COMMAND_TILE_SIZE := 16.0
const COMMAND_HISTORY_LIMIT   := 10
const GIVE_SHORTCUT_DEFAULT_AMOUNT: int = 200
const GIVE_SHORTCUT_OVERRIDES: Dictionary = {
	"ww": {"item_id": "wallwood", "amount": 200},
	"fw": {"item_id": "floorwood", "amount": 200},
	"dw": {"item_id": "doorwood", "amount": 200},
	"wb": {"item_id": "workbench", "amount": 200},
}
const GIVE_SHORTCUT_BUNDLES: Dictionary = {
	"ba": [
		{"item_id": "bow", "amount": 1},
		{"item_id": "arrow", "amount": 200},
	],
}
const GIVE_SHORTCUT_EXTRA_ALIASES: Dictionary = {
	"arrow": ["arr", "arw", "flecha"],
	"axe_copper": ["axc", "cax", "hachacobre", "hachac"],
	"axe_stone": ["axs", "sax", "hachapiedra", "hachas"],
	"axe_wood": ["axw", "wax", "hachamadera", "hachaw"],
	"bandage": ["bdg", "band", "venda"],
	"barrel": ["brl", "barr", "barril"],
	"book": ["bk", "bok", "libro"],
	"bow": ["bw", "arco"],
	"chest": ["cht", "chs", "cofre"],
	"copper": ["cop", "cpr", "cobre"],
	"doorwood": ["door", "wooddoor", "puerta"],
	"fiber": ["fib", "fbr", "fibra"],
	"floorwood": ["floor", "woodfloor", "piso", "suelo"],
	"ironpipe": ["ip", "pipe", "tubo"],
	"pickaxe_copper": ["pxc", "cpx", "picocobre", "pickc"],
	"pickaxe_stone": ["pxs", "spx", "picopiedra", "picks"],
	"pickaxe_wood": ["pxw", "wpx", "picomadera", "pickw"],
	"stick": ["stk", "stik", "palo"],
	"stone": ["stn", "sto", "piedra", "rock"],
	"stool": ["stl", "silla", "taburete"],
	"sword_copper": ["swc", "csw", "espadacobre", "swordc"],
	"sword_stone": ["sws", "ssw", "espadapiedra", "swords"],
	"sword_wood": ["sww", "wsw", "espadamadera", "swordw"],
	"wallwood": ["wall", "woodwall", "muro", "pared"],
	"wood": ["wd", "madera", "log"],
	"workbench": ["bench", "work", "mesa"],
}

var _player: Node        = null
var _world: Node         = null
var _ui_layer: CanvasLayer = null

var _command_container: Control = null
var _command_input: LineEdit    = null
var _command_open: bool         = false
var _command_history: Array[String] = []
var _command_history_index: int = -1
var _give_shortcut_alias_to_item: Dictionary = {}
var _give_shortcut_alias_to_amount: Dictionary = {}
var _give_shortcut_conflicts: Dictionary = {}
var _give_shortcuts_ready: bool = false

# Autocompletado
var _suggestion_root: Control       = null
var _suggestion_vbox: VBoxContainer = null
var _suggestion_candidates: Array[String] = []
var _suggestion_index: int          = -1


# ---------------------------------------------------------------------------
# Inicialización
# ---------------------------------------------------------------------------
func setup(player: Node, world: Node, ui_layer: CanvasLayer) -> void:
	_player   = player
	_world    = world
	_ui_layer = ui_layer
	_setup_command_bar()


# ---------------------------------------------------------------------------
# API pública — llamada desde main.gd en _unhandled_input
# ---------------------------------------------------------------------------

## Procesa una tecla. Devuelve true si fue consumida por el sistema de comandos.
func handle_key(key_event: InputEventKey) -> bool:
	if key_event.keycode == KEY_T and not _command_open:
		_open_command_bar()
		return true
	if key_event.keycode == KEY_ESCAPE and _command_open:
		_close_command_bar()
		return true
	return false

func is_open() -> bool:
	return _command_open


# ---------------------------------------------------------------------------
# UI de la barra de comandos
# ---------------------------------------------------------------------------
func _setup_command_bar() -> void:
	if _ui_layer == null:
		return

	_command_container = Control.new()
	_command_container.name = "CommandBar"
	_command_container.visible = false
	_command_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_command_container.anchor_left   = 0.0
	_command_container.anchor_top    = 1.0
	_command_container.anchor_right  = 1.0
	_command_container.anchor_bottom = 1.0
	_command_container.offset_left   = 8.0
	_command_container.offset_top    = -COMMAND_BAR_HEIGHT - 8.0
	_command_container.offset_right  = -8.0
	_command_container.offset_bottom = -8.0
	_ui_layer.add_child(_command_container)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.03, 0.03, 0.03, 0.9)
	_command_container.add_child(bg)

	_command_input = LineEdit.new()
	_command_input.name = "Input"
	_command_input.anchor_right  = 1.0
	_command_input.anchor_bottom = 1.0
	_command_input.offset_left   = 8.0
	_command_input.offset_top    = 4.0
	_command_input.offset_right  = -8.0
	_command_input.offset_bottom = -4.0
	if Debug.dev_cheats_enabled:
		_command_input.placeholder_text = "/give <item_id> <n>  |  /gv <alias>  |  /dog <n>  |  /sellall <id> <p>  |  /buydbg <id> <n> <p>"
	else:
		_command_input.placeholder_text = "/give <item_id> <n>  |  /gv <alias|item_id>  |  /gv list  |  /dog <n>  |  /summon enemy [n] [ox] [oy]"
	_command_input.clear_button_enabled = true
	_command_input.text_submitted.connect(_on_command_submitted)
	_command_input.gui_input.connect(_on_command_gui_input)
	_command_input.text_changed.connect(_on_command_text_changed)
	_command_container.add_child(_command_input)

	_setup_suggestion_panel()


func _setup_suggestion_panel() -> void:
	_suggestion_root = Control.new()
	_suggestion_root.name = "SuggestionPanel"
	_suggestion_root.visible = false
	_suggestion_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suggestion_root.anchor_left   = 0.0
	_suggestion_root.anchor_top    = 1.0
	_suggestion_root.anchor_right  = 0.0
	_suggestion_root.anchor_bottom = 1.0
	_suggestion_root.offset_left   = 8.0
	_suggestion_root.offset_right  = 8.0 + SUGGESTION_PANEL_MAX_W
	var bar_top: float = -(COMMAND_BAR_HEIGHT + 8.0 + 4.0)
	_suggestion_root.offset_bottom = bar_top
	_suggestion_root.offset_top    = bar_top   # altura 0 hasta que haya sugerencias
	_ui_layer.add_child(_suggestion_root)

	var bg := ColorRect.new()
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.05, 0.05, 0.05, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suggestion_root.add_child(bg)

	_suggestion_vbox = VBoxContainer.new()
	_suggestion_vbox.anchor_right  = 1.0
	_suggestion_vbox.anchor_bottom = 1.0
	_suggestion_vbox.add_theme_constant_override("separation", 0)
	_suggestion_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suggestion_root.add_child(_suggestion_vbox)


func _open_command_bar() -> void:
	if _command_container == null or _command_input == null:
		return
	_command_open = true
	UiManager.notify_command_bar_open(true)
	_command_container.visible = true
	if _command_input.text.is_empty():
		_command_input.text = COMMAND_PREFIX
	_command_input.caret_column = _command_input.text.length()
	_command_history_index = _command_history.size()
	_command_input.grab_focus()


func _close_command_bar() -> void:
	if _command_container == null or _command_input == null:
		return
	_command_open = false
	UiManager.notify_command_bar_open(false)
	_command_container.visible = false
	_command_input.text = ""
	_command_input.release_focus()
	if _suggestion_root != null:
		_suggestion_root.visible = false
	_suggestion_candidates = []
	_suggestion_index = -1


func _on_command_gui_input(event: InputEvent) -> void:
	if not _command_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_close_command_bar()
			_command_input.accept_event()
			return
		if key_event.keycode == KEY_TAB:
			_apply_suggestion()
			_command_input.accept_event()
			return
		if key_event.keycode == KEY_UP:
			if not _suggestion_candidates.is_empty():
				_navigate_suggestions(-1)
			else:
				_navigate_command_history(-1)
			_command_input.accept_event()
			return
		if key_event.keycode == KEY_DOWN:
			if not _suggestion_candidates.is_empty():
				_navigate_suggestions(1)
			else:
				_navigate_command_history(1)
			_command_input.accept_event()
			return


func _on_command_submitted(raw_text: String) -> void:
	var command_text := raw_text.strip_edges()
	if command_text.is_empty():
		_close_command_bar()
		return
	_execute_command(command_text)
	_push_command_history(command_text)
	_close_command_bar()


# ---------------------------------------------------------------------------
# Historial
# ---------------------------------------------------------------------------
func _push_command_history(command_text: String) -> void:
	if command_text.is_empty():
		return
	if not _command_history.is_empty() and _command_history[_command_history.size() - 1] == command_text:
		_command_history_index = _command_history.size()
		return
	_command_history.append(command_text)
	if _command_history.size() > COMMAND_HISTORY_LIMIT:
		_command_history.pop_front()
	_command_history_index = _command_history.size()


func _navigate_command_history(direction: int) -> void:
	if _command_input == null or _command_history.is_empty():
		return
	if _command_history_index < 0:
		_command_history_index = _command_history.size()
	_command_history_index = clampi(_command_history_index + direction, 0, _command_history.size())
	if _command_history_index >= _command_history.size():
		_command_input.text = COMMAND_PREFIX
	else:
		_command_input.text = _command_history[_command_history_index]
	_command_input.caret_column = _command_input.text.length()


# ---------------------------------------------------------------------------
# Autocompletado
# ---------------------------------------------------------------------------

func _on_command_text_changed(text: String) -> void:
	_suggestion_index = -1
	_suggestion_candidates = _get_suggestion_candidates(text)
	_rebuild_suggestion_ui()


func _get_suggestion_candidates(text: String) -> Array[String]:
	if not text.begins_with(COMMAND_PREFIX):
		return []
	var raw      := text.substr(1)
	var has_space := " " in raw
	var parts    := raw.split(" ", false)
	var result: Array[String] = []

	if not has_space:
		# Completar el comando base
		var partial: String = parts[0] if parts.size() > 0 else ""
		for cmd: String in COMMAND_COMPLETIONS.keys():
			if not cmd.begins_with(partial):
				continue
			if cmd in ["sellall", "buydbg"] and not Debug.dev_cheats_enabled:
				continue
			result.append(cmd)
		result.sort()
	else:
		# Completar subcomando
		var base: String = parts[0] if parts.size() > 0 else ""
		if COMMAND_COMPLETIONS.has(base):
			var subs: Array = COMMAND_COMPLETIONS[base]
			var partial: String = parts[1] if parts.size() > 1 else ""
			for sub: String in subs:
				if sub.begins_with(partial):
					result.append(sub)
	return result


func _rebuild_suggestion_ui() -> void:
	if _suggestion_vbox == null or _suggestion_root == null:
		return
	for child in _suggestion_vbox.get_children():
		child.queue_free()

	var n := mini(_suggestion_candidates.size(), MAX_SUGGESTIONS)
	if n == 0:
		_suggestion_root.visible = false
		return

	for i in range(n):
		var candidate := _suggestion_candidates[i]
		var selected  := (i == _suggestion_index)

		var row := Control.new()
		row.custom_minimum_size = Vector2(0.0, SUGGESTION_ROW_H)
		row.size_flags_horizontal = Control.SIZE_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var row_bg := ColorRect.new()
		row_bg.anchor_right  = 1.0
		row_bg.anchor_bottom = 1.0
		row_bg.color = Color(0.18, 0.44, 0.76, 0.65) if selected else Color(0.0, 0.0, 0.0, 0.0)
		row_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(row_bg)

		var lbl := Label.new()
		lbl.text = candidate
		lbl.anchor_bottom = 1.0
		lbl.offset_left   = 10.0
		lbl.offset_right  = -4.0
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color",
			Color(1.0, 1.0, 1.0, 0.95) if selected else Color(0.78, 0.78, 0.78, 0.88))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)

		_suggestion_vbox.add_child(row)

	_suggestion_root.offset_top = _suggestion_root.offset_bottom - n * SUGGESTION_ROW_H
	_suggestion_root.visible = true


func _navigate_suggestions(dir: int) -> void:
	var n := _suggestion_candidates.size()
	if n == 0:
		return
	if _suggestion_index < 0:
		_suggestion_index = (n - 1) if dir < 0 else 0
	else:
		_suggestion_index = (_suggestion_index + dir + n) % n
	_rebuild_suggestion_ui()


func _apply_suggestion() -> void:
	if _suggestion_candidates.is_empty():
		return
	var idx     := 0 if _suggestion_index < 0 else _suggestion_index
	if idx >= _suggestion_candidates.size():
		return
	var chosen  := _suggestion_candidates[idx]
	var raw     := _command_input.text.substr(1)
	var has_space := " " in raw
	if not has_space:
		_command_input.text = COMMAND_PREFIX + chosen + " "
	else:
		var base := raw.split(" ", false)[0]
		_command_input.text = COMMAND_PREFIX + base + " " + chosen + " "
	_command_input.caret_column = _command_input.text.length()
	_suggestion_index = -1
	_suggestion_candidates = _get_suggestion_candidates(_command_input.text)
	_rebuild_suggestion_ui()


# ---------------------------------------------------------------------------
# Dispatcher de comandos
# ---------------------------------------------------------------------------
func _execute_command(command_text: String) -> void:
	if not command_text.begins_with(COMMAND_PREFIX):
		if _try_execute_shortcut_without_prefix(command_text):
			return
		Debug.log("commands", "Comando inválido: falta '/' (%s)" % command_text)
		return

	var parts := command_text.substr(1).split(" ", false)
	if parts.size() == 0:
		return

	var base_command := String(parts[0]).to_lower()

	match base_command:
		"inv":
			_cmd_toggle_ghost_mode()
		"spawn":
			_cmd_spawn()
		"spawn_workbench":
			_cmd_spawn_workbench()
		"give":
			_cmd_give(parts.slice(1))
		"gv":
			_cmd_give_shortcut(parts.slice(1))
		"dog":
			_cmd_give_gold(parts.slice(1))
		"set_day":
			_cmd_set_day()
		"set_night":
			_cmd_set_night()
		"summon":
			if parts.size() >= 2 and String(parts[1]).to_lower() == "enemy":
				_cmd_summon_enemy(parts.slice(2))
			elif parts.size() >= 2 and String(parts[1]).to_lower() == "sentinel":
				_cmd_summon_sentinel()
			else:
				Debug.log("commands", "Uso: /summon enemy [n] [ox] [oy]  |  /summon sentinel")
		"sentinel":
			_cmd_sentinel(parts.slice(1))
		"gotocamp", "camp":
			_cmd_goto_camp()
		"sellall":
			if not Debug.dev_cheats_enabled:
				Debug.log("commands", "Comando de dev_cheats deshabilitado: %s" % base_command)
			else:
				_cmd_sellall(parts.slice(1))
		"sc":
			if not Debug.dev_cheats_enabled:
				Debug.log("commands", "Comando de dev_cheats deshabilitado: %s" % base_command)
			else:
				var new_parts: Array[String] = ["copper"]
				new_parts.append_array(parts.slice(1))
				_cmd_sellall(new_parts)
		"buydbg":
			if not Debug.dev_cheats_enabled:
				Debug.log("commands", "Comando de dev_cheats deshabilitado: %s" % base_command)
			else:
				_cmd_buydbg(parts.slice(1))
		"med":
			if not Debug.dev_cheats_enabled:
				Debug.log("commands", "Comando de dev_cheats deshabilitado: %s" % base_command)
			else:
				_cmd_buydbg(["medkit", "1", "20"])
		"g50":
			if not Debug.dev_cheats_enabled:
				Debug.log("commands", "Comando de dev_cheats deshabilitado: %s" % base_command)
			else:
				_cmd_give_gold(["50"])
		"c3":
			if not Debug.dev_cheats_enabled:
				Debug.log("commands", "Comando de dev_cheats deshabilitado: %s" % base_command)
			else:
				_cmd_give(["copper", "3"])
		_:
			Debug.log("commands", "Comando desconocido: %s" % base_command)

func _try_execute_shortcut_without_prefix(command_text: String) -> bool:
	var parts := command_text.split(" ", false)
	if parts.size() == 0:
		return false
	var base_command := String(parts[0]).to_lower()

	match base_command:
		"gv":
			_cmd_give_shortcut(parts.slice(1))
			return true
		"sc":
			if not Debug.dev_cheats_enabled:
				return false
			var new_parts: Array[String] = ["copper"]
			new_parts.append_array(parts.slice(1))
			_cmd_sellall(new_parts)
			return true
		"med":
			if not Debug.dev_cheats_enabled:
				return false
			_cmd_buydbg(["medkit", "1", "20"])
			return true
		"g50":
			if not Debug.dev_cheats_enabled:
				return false
			_cmd_give_gold(["50"])
			return true
		"c3":
			if not Debug.dev_cheats_enabled:
				return false
			_cmd_give(["copper", "3"])
			return true

	return false

func _cmd_give_shortcut(raw_args: Array) -> void:
	if raw_args.is_empty():
		Debug.log("commands", "Uso: /gv <alias|item_id> [mas_aliases...]  (ej: /gv ww ba)  |  /gv list")
		return
	var unknown_aliases: Array[String] = []
	var applied_count: int = 0
	for raw_arg in raw_args:
		var shortcut_key := String(raw_arg).strip_edges().to_lower()
		if shortcut_key.is_empty():
			continue
		if shortcut_key == "list":
			_log_give_shortcut_list()
			continue
		if _try_execute_give_shortcut_bundle(shortcut_key):
			applied_count += 1
			continue
		var resolve: Dictionary = _resolve_give_shortcut(shortcut_key)
		if not bool(resolve.get("ok", false)):
			var err: String = String(resolve.get("error", "unknown"))
			if err == "ambiguous":
				var options: Array = resolve.get("options", [])
				Debug.log("commands", "Alias ambiguo '%s'. Usa uno de: %s" % [shortcut_key, _join_to_string(options)])
				continue
			if not unknown_aliases.has(shortcut_key):
				unknown_aliases.append(shortcut_key)
			continue
		var item_id := String(resolve.get("item_id", "")).strip_edges().to_lower()
		var amount := int(resolve.get("amount", GIVE_SHORTCUT_DEFAULT_AMOUNT))
		if item_id.is_empty() or amount <= 0:
			Debug.log("commands", "Shortcut invalido: %s" % shortcut_key)
			continue
		_cmd_give([item_id, str(amount)])
		applied_count += 1
	if not unknown_aliases.is_empty():
		Debug.log("commands", "Alias/item desconocido: %s (usa /gv list)" % _join_to_string(unknown_aliases))
	if applied_count <= 0 and unknown_aliases.is_empty():
		Debug.log("commands", "No se aplicaron shortcuts. Uso: /gv <alias|item_id> [mas_aliases...]")


func _try_execute_give_shortcut_bundle(shortcut_key: String) -> bool:
	var bundle_variant: Variant = GIVE_SHORTCUT_BUNDLES.get(shortcut_key, null)
	if not (bundle_variant is Array):
		return false
	var bundle_entries: Array = bundle_variant as Array
	var granted_any: bool = false
	for raw_entry in bundle_entries:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var item_id := String(entry.get("item_id", "")).strip_edges().to_lower()
		if item_id == "":
			continue
		var amount: int = maxi(1, int(entry.get("amount", GIVE_SHORTCUT_DEFAULT_AMOUNT)))
		_cmd_give([item_id, str(amount)])
		granted_any = true
	if granted_any:
		Debug.log("commands", "Bundle gv '%s' aplicado" % shortcut_key)
	return granted_any


# ---------------------------------------------------------------------------
# Implementación de comandos
# ---------------------------------------------------------------------------

## /spawn — teletransporta al jugador al centro de la taberna (spawn inicial)
func _cmd_spawn() -> void:
	if _world == null or not _world.has_method("teleport_to_spawn"):
		Debug.log("commands", "/spawn: world no disponible")
		return
	_world.call("teleport_to_spawn")


## /spawn_workbench — spawna una crafting table 2 tiles a la derecha del player
func _cmd_spawn_workbench() -> void:
	if _player == null:
		Debug.log("commands", "/spawn_workbench: player no disponible")
		return
	var wb := WORKBENCH_SCENE.instantiate()
	get_tree().current_scene.add_child(wb)
	wb.global_position = (_player as Node2D).global_position + Vector2(200, 0)
	Debug.log("commands", "Workbench spawneado en %s" % str(wb.global_position))


## /dog <cantidad> — agrega dinero al player
func _cmd_give_gold(raw_args: Array) -> void:
	if raw_args.is_empty():
		Debug.log("commands", "Uso: /dog <cantidad>")
		return
	var amount_text := String(raw_args[0]).strip_edges()
	if not amount_text.is_valid_int():
		Debug.log("commands", "cantidad inválida: %s" % amount_text)
		return
	var amount := maxi(1, amount_text.to_int())
	var inventory := _get_player_inventory()
	if inventory == null:
		Debug.log("commands", "No se encontró InventoryComponent del jugador")
		return
	inventory.gold += amount
	Debug.log("commands", "Agregado %d de dinero. Total: %d" % [amount, inventory.gold])


## /give <item_id> <cantidad>
func _cmd_give(raw_args: Array) -> void:
	if raw_args.size() < 2:
		Debug.log("commands", "Uso: /give <item_id> <cantidad>")
		return

	var item_id     := String(raw_args[0]).strip_edges().to_lower()
	var amount_text := String(raw_args[1]).strip_edges()

	if item_id.is_empty():
		Debug.log("commands", "item_id inválido")
		return
	if not amount_text.is_valid_int():
		Debug.log("commands", "cantidad inválida: %s" % amount_text)
		return

	var amount := maxi(1, amount_text.to_int())
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null or not item_db.has_method("get_item"):
		Debug.log("commands", "ItemDB no está disponible")
		return

	var item_data: Variant = item_db.call("get_item", item_id)
	if item_data == null:
		Debug.log("commands", "Item no registrado en ItemDB: %s" % item_id)
		return
	if "id" in item_data:
		item_id = String(item_data.id).strip_edges().to_lower()

	var inventory := _get_player_inventory()
	if inventory == null:
		Debug.log("commands", "No se encontró InventoryComponent del jugador")
		return

	var inserted := int(inventory.call("add_item", item_id, amount))
	if inserted <= 0:
		Debug.log("commands", "Inventario lleno. No se pudo agregar %s" % item_id)
	elif inserted < amount:
		Debug.log("commands", "Se agregaron %d/%d de %s (inventario lleno)" % [inserted, amount, item_id])
	else:
		Debug.log("commands", "Agregados %d de %s al inventario" % [inserted, item_id])

func _resolve_give_shortcut(alias_or_item: String) -> Dictionary:
	var key := alias_or_item.strip_edges().to_lower()
	if key == "":
		return {"ok": false, "error": "unknown"}
	_ensure_give_shortcuts()
	if _give_shortcut_conflicts.has(key):
		return {
			"ok": false,
			"error": "ambiguous",
			"options": _give_shortcut_conflicts[key],
		}
	if _give_shortcut_alias_to_item.has(key):
		return {
			"ok": true,
			"item_id": String(_give_shortcut_alias_to_item[key]),
			"amount": int(_give_shortcut_alias_to_amount.get(key, GIVE_SHORTCUT_DEFAULT_AMOUNT)),
		}
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db != null and item_db.has_method("get_item"):
		var item_data: Variant = item_db.call("get_item", key)
		if item_data != null and "id" in item_data:
			return {
				"ok": true,
				"item_id": String(item_data.id).strip_edges().to_lower(),
				"amount": GIVE_SHORTCUT_DEFAULT_AMOUNT,
			}
	return {"ok": false, "error": "unknown"}

func _log_give_shortcut_list() -> void:
	_ensure_give_shortcuts()
	var aliases: Array = _give_shortcut_alias_to_item.keys()
	aliases.sort()
	if aliases.is_empty():
		Debug.log("commands", "No hay aliases cargados. ItemDB vacio o no disponible.")
		return
	var rows: Array[String] = []
	for raw_alias in aliases:
		var alias := String(raw_alias)
		var item_id := String(_give_shortcut_alias_to_item.get(alias, ""))
		if alias == item_id:
			continue
		rows.append("%s->%s" % [alias, item_id])
	if rows.is_empty():
		Debug.log("commands", "Aliases disponibles: usa directamente /gv <item_id>")
	else:
		Debug.log("commands", "Aliases gv: %s" % _join_to_string(rows))
	var bundle_rows: Array[String] = []
	for raw_alias in GIVE_SHORTCUT_BUNDLES.keys():
		var alias := String(raw_alias).strip_edges().to_lower()
		var entries_variant: Variant = GIVE_SHORTCUT_BUNDLES.get(raw_alias, null)
		if alias == "" or not (entries_variant is Array):
			continue
		var entries: Array = entries_variant as Array
		var parts: Array[String] = []
		for raw_entry in entries:
			if not (raw_entry is Dictionary):
				continue
			var entry: Dictionary = raw_entry as Dictionary
			var item_id := String(entry.get("item_id", "")).strip_edges().to_lower()
			if item_id == "":
				continue
			var amount: int = maxi(1, int(entry.get("amount", GIVE_SHORTCUT_DEFAULT_AMOUNT)))
			parts.append("%s×%d" % [item_id, amount])
		if parts.is_empty():
			continue
		bundle_rows.append("%s->%s" % [alias, "+".join(parts)])
	if not bundle_rows.is_empty():
		bundle_rows.sort()
		Debug.log("commands", "Bundles gv: %s" % _join_to_string(bundle_rows))

func _ensure_give_shortcuts() -> void:
	if _give_shortcuts_ready:
		return
	_give_shortcuts_ready = true
	_give_shortcut_alias_to_item.clear()
	_give_shortcut_alias_to_amount.clear()
	_give_shortcut_conflicts.clear()
	var item_db := get_node_or_null("/root/ItemDB")
	if item_db == null:
		return
	var items_variant: Variant = item_db.get("items")
	if not (items_variant is Dictionary):
		return
	var items_dict: Dictionary = items_variant as Dictionary
	var item_ids: Array[String] = []
	for raw_id in items_dict.keys():
		var item_id := String(raw_id).strip_edges().to_lower()
		if item_id == "":
			continue
		item_ids.append(item_id)
	item_ids.sort()
	for item_id in item_ids:
		_register_give_shortcut_alias(item_id, item_id, true, GIVE_SHORTCUT_DEFAULT_AMOUNT)
		var item_data: Variant = items_dict.get(item_id, null)
		var candidates: Array[String] = _build_shortcut_candidates_for_item(item_id, item_data)
		for candidate in candidates:
			_register_give_shortcut_alias(candidate, item_id, false, GIVE_SHORTCUT_DEFAULT_AMOUNT)
		_register_curated_give_shortcuts(item_id)
	for raw_alias in GIVE_SHORTCUT_OVERRIDES.keys():
		var alias := String(raw_alias).strip_edges().to_lower()
		var override_data: Variant = GIVE_SHORTCUT_OVERRIDES[raw_alias]
		if not (override_data is Dictionary):
			continue
		var override_dict: Dictionary = override_data as Dictionary
		var item_id := String(override_dict.get("item_id", "")).strip_edges().to_lower()
		var amount := int(override_dict.get("amount", GIVE_SHORTCUT_DEFAULT_AMOUNT))
		if alias == "" or item_id == "":
			continue
		_register_give_shortcut_alias(alias, item_id, true, amount)

func _register_curated_give_shortcuts(item_id: String) -> void:
	var aliases_variant: Variant = GIVE_SHORTCUT_EXTRA_ALIASES.get(item_id, null)
	if not (aliases_variant is Array):
		return
	var aliases: Array = aliases_variant
	for raw_alias in aliases:
		var alias := String(raw_alias).strip_edges().to_lower()
		if alias == "":
			continue
		_register_give_shortcut_alias(alias, item_id, true, GIVE_SHORTCUT_DEFAULT_AMOUNT)

func _build_shortcut_candidates_for_item(item_id: String, item_data: Variant = null) -> Array[String]:
	var candidates: Dictionary = {}
	var compact := item_id.replace("_", "")
	if compact != item_id:
		candidates[compact] = true
	var parts: PackedStringArray = item_id.split("_", false)
	if parts.size() >= 2:
		var acronym := ""
		for part in parts:
			if part.length() > 0:
				acronym += part.substr(0, 1)
		if acronym.length() >= 2:
			candidates[acronym] = true
	if compact.length() >= 2:
		candidates[compact.substr(0, 2)] = true
	if compact.length() >= 3:
		candidates[compact.substr(0, 3)] = true
	if item_data != null and "display_name" in item_data:
		var display_compact := _compact_alias_text(String(item_data.display_name))
		if display_compact != "" and display_compact != item_id:
			candidates[display_compact] = true
			if display_compact.length() >= 2:
				candidates[display_compact.substr(0, 2)] = true
			if display_compact.length() >= 3:
				candidates[display_compact.substr(0, 3)] = true
	var out: Array[String] = []
	for raw_candidate in candidates.keys():
		var alias := String(raw_candidate).strip_edges().to_lower()
		if alias != "" and alias != item_id:
			out.append(alias)
	out.sort()
	return out

func _compact_alias_text(value: String) -> String:
	var cleaned := value.to_lower()
	var separators := [
		" ",
		"_",
		"-",
		"(",
		")",
		"[",
		"]",
		"{",
		"}",
		".",
		",",
		";",
		":",
		"/",
		"\\",
		"'",
		"\"",
	]
	for separator in separators:
		cleaned = cleaned.replace(separator, "")
	return cleaned.strip_edges()

func _register_give_shortcut_alias(alias: String, item_id: String, force: bool, amount: int = GIVE_SHORTCUT_DEFAULT_AMOUNT) -> void:
	if alias == "" or item_id == "":
		return
	amount = maxi(1, amount)
	if force:
		_give_shortcut_alias_to_item[alias] = item_id
		_give_shortcut_alias_to_amount[alias] = amount
		_give_shortcut_conflicts.erase(alias)
		return
	if _give_shortcut_conflicts.has(alias):
		var conflict_existing: Array = _give_shortcut_conflicts[alias]
		if not conflict_existing.has(item_id):
			conflict_existing.append(item_id)
			conflict_existing.sort()
			_give_shortcut_conflicts[alias] = conflict_existing
		return
	if not _give_shortcut_alias_to_item.has(alias):
		_give_shortcut_alias_to_item[alias] = item_id
		_give_shortcut_alias_to_amount[alias] = amount
		return
	var existing_item: String = String(_give_shortcut_alias_to_item[alias])
	if existing_item == item_id:
		return
	var options: Array[String] = [existing_item, item_id]
	options.sort()
	_give_shortcut_alias_to_item.erase(alias)
	_give_shortcut_alias_to_amount.erase(alias)
	_give_shortcut_conflicts[alias] = options

func _join_to_string(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(String(value))
	return ", ".join(parts)


## /summon enemy [cantidad] [offset_x_tiles] [offset_y_tiles]
func _cmd_sellall(raw_args: Array) -> void:
	if raw_args.size() < 2:
		Debug.log("commands", "Uso: /sellall <item_id> <price>")
		return
	var item_id := String(raw_args[0]).to_lower()
	var price := String(raw_args[1]).to_int()

	var inventory := _get_player_inventory()
	if inventory == null:
		Debug.log("commands", "No se encontró InventoryComponent del jugador")
		return

	if inventory.has_method("sell_all"):
		inventory.call("sell_all", item_id, price)
		Debug.log("commands", "Se vendió todo '%s' a %s cada uno (si lo tenías)" % [item_id, price])
	else:
		Debug.log("commands", "El inventario no soporta sell_all")

func _cmd_buydbg(raw_args: Array) -> void:
	if raw_args.size() < 3:
		Debug.log("commands", "Uso: /buydbg <item_id> <amount> <price>")
		return
	var item_id := String(raw_args[0]).to_lower()
	var amount := String(raw_args[1]).to_int()
	var price := String(raw_args[2]).to_int()

	var inventory := _get_player_inventory()
	if inventory == null:
		Debug.log("commands", "No se encontró InventoryComponent del jugador")
		return

	if inventory.has_method("buy_item"):
		var amount_bought: int = int(inventory.call("buy_item", item_id, amount, price))
		if amount_bought > 0:
			Debug.log("commands", "Se compró %s de '%s' por %s oro cada uno" % [amount_bought, item_id, price])
		else:
			Debug.log("commands", "Fallo al comprar '%s': sin oro o sin espacio" % item_id)
	else:
		Debug.log("commands", "El inventario no soporta buy_item")

## /inv — activa/desactiva modo fantasma: el player no recibe daño y los enemigos lo ignoran
func _cmd_toggle_ghost_mode() -> void:
	var debug_node := get_node_or_null("/root/Debug") as DebugSystem
	if debug_node == null:
		Debug.log("commands", "/inv: Debug singleton no disponible")
		return

	debug_node.ghost_mode = not debug_node.ghost_mode
	var active: bool = debug_node.ghost_mode

	# Sincronizar invincible en el hurtbox del player
	if _player != null and is_instance_valid(_player):
		for child in _player.get_children():
			if "invincible" in child:
				child.invincible = active
				break

	var status: String = "ACTIVADO 👻 — enemigos te ignoran, sin daño" if active \
			else "DESACTIVADO — comportamiento normal"
	print("[INV] Modo fantasma %s" % status)


## /gotocamp — teletransporta al player a un campamento bandido aleatorio
func _cmd_goto_camp() -> void:
	if _player == null:
		Debug.log("commands", "/gotocamp: player no disponible")
		return

	# Collect unique home positions from all registered groups
	var candidates: Array[Vector2] = []
	for gid in BanditGroupMemory.get_all_group_ids():
		var g: Dictionary = BanditGroupMemory.get_group(String(gid))
		var hp = g.get("home_world_pos", null)
		if hp is Vector2 and (hp as Vector2) != Vector2.ZERO:
			candidates.append(hp as Vector2)

	# Fallback: scan WorldSave directly (catches unloaded chunks)
	if candidates.is_empty():
		var seen: Dictionary = {}
		for chunk_key in WorldSave.enemy_state_by_chunk:
			for eid in WorldSave.enemy_state_by_chunk[chunk_key]:
				var st = WorldSave.enemy_state_by_chunk[chunk_key][eid]
				if not (st is Dictionary):
					continue
				var hp = (st as Dictionary).get("home_world_pos", null)
				var key_str: String = ""
				if hp is Vector2:
					key_str = str(hp)
				elif hp is Dictionary:
					key_str = "%s_%s" % [str((hp as Dictionary).get("x", 0)), str((hp as Dictionary).get("y", 0))]
				if key_str == "" or seen.has(key_str):
					continue
				seen[key_str] = true
				var pos: Vector2
				if hp is Vector2:
					pos = hp as Vector2
				else:
					pos = Vector2(float((hp as Dictionary).get("x", 0.0)), float((hp as Dictionary).get("y", 0.0)))
				if pos != Vector2.ZERO:
					candidates.append(pos)

	if candidates.is_empty():
		Debug.log("commands", "/gotocamp: no se encontraron campamentos")
		return

	candidates.shuffle()
	var dest: Vector2 = candidates[0]
	(_player as Node2D).global_position = dest
	Debug.log("commands", "/gotocamp → %s" % str(dest))

func _cmd_set_day() -> void:
	if WorldTime == null:
		Debug.log("commands", "/set_day: WorldTime no disponible")
		return
	WorldTime.set_to_day_start()
	var time_in_day: float = WorldTime.get_time_in_day()
	var visual_target := _estimate_day_night_visual_target(time_in_day)
	Debug.log("commands", "/set_day -> fase=day, time_in_day=%.4f, visual_target_est=%.4f" % [time_in_day, visual_target])

func _cmd_set_night() -> void:
	if WorldTime == null:
		Debug.log("commands", "/set_night: WorldTime no disponible")
		return
	WorldTime.set_to_night_start()
	var time_in_day: float = WorldTime.get_time_in_day()
	var visual_target := _estimate_day_night_visual_target(time_in_day)
	Debug.log("commands", "/set_night -> fase=night, time_in_day=%.4f, visual_target_est=%.4f" % [time_in_day, visual_target])

func _estimate_day_night_visual_target(time_in_day: float) -> float:
	var controller := _get_day_night_controller()
	if controller == null:
		return -1.0
	if controller.has_method("_compute_target_night_amount"):
		return float(controller.call("_compute_target_night_amount", time_in_day))
	if controller.has_method("get_current_night_amount"):
		return float(controller.call("get_current_night_amount"))
	return -1.0

func _get_day_night_controller() -> Node:
	if _world != null:
		var direct := _world.get_node_or_null("DayNightController")
		if direct != null:
			return direct
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("day_night_controller")


func _cmd_summon_enemy(raw_args: Array) -> void:
	if ENEMY_SCENE == null or _world == null:
		Debug.log("commands", "No se pudo invocar enemy: escena o world no disponible")
		return

	var spawn_count := 1
	if raw_args.size() >= 1:
		if not String(raw_args[0]).is_valid_int():
			Debug.log("commands", "cantidad inválida: %s" % str(raw_args[0]))
			return
		spawn_count = maxi(1, String(raw_args[0]).to_int())

	var has_tile_offset := raw_args.size() >= 3
	var tile_offset := Vector2i.ZERO
	if has_tile_offset:
		if not String(raw_args[1]).is_valid_int() or not String(raw_args[2]).is_valid_int():
			Debug.log("commands", "offset inválido: usa enteros, ej. /summon enemy 2 3 -2")
			return
		tile_offset = Vector2i(String(raw_args[1]).to_int(), String(raw_args[2]).to_int())
	elif raw_args.size() == 2:
		Debug.log("commands", "faltó offset_y. Uso: /summon enemy [n] [offset_x] [offset_y]")
		return

	var spawned := 0
	for _i in spawn_count:
		if _summon_single_enemy(tile_offset if has_tile_offset else null):
			spawned += 1

	if has_tile_offset:
		Debug.log("commands", "Invocados %d enemy(s) con offset (%d, %d) tiles" % [spawned, tile_offset.x, tile_offset.y])
	else:
		Debug.log("commands", "Invocados %d enemy(s) cerca del jugador" % spawned)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _summon_single_enemy(tile_offset: Variant = null) -> bool:
	var enemy := ENEMY_SCENE.instantiate()
	if enemy == null:
		return false
	var spawn_pos := _get_spawn_position(tile_offset)
	_world.add_child(enemy)
	if enemy is Node2D:
		(enemy as Node2D).global_position = spawn_pos
	return true


func _get_spawn_position(tile_offset: Variant = null) -> Vector2:
	if _player != null and _player is Node2D:
		var player_pos := (_player as Node2D).global_position
		if tile_offset != null and tile_offset is Vector2i:
			var tile_size := _get_tile_size()
			var off := tile_offset as Vector2i
			return player_pos + Vector2(off.x * tile_size, off.y * tile_size)
		var angle := randf() * TAU
		var dist  := randf_range(COMMAND_SPAWN_MIN_DIST, COMMAND_SPAWN_MAX_DIST)
		return player_pos + Vector2.RIGHT.rotated(angle) * dist
	return Vector2.ZERO


func _get_tile_size() -> float:
	if _world == null:
		return DEFAULT_COMMAND_TILE_SIZE
	var world_tile_map := _world.get_node_or_null("WorldTileMap")
	if world_tile_map != null and world_tile_map is TileMapLayer:
		var tile_set := (world_tile_map as TileMapLayer).tile_set
		if tile_set != null:
			return float(tile_set.tile_size.x)
	return DEFAULT_COMMAND_TILE_SIZE


func _get_player_inventory() -> Node:
	if _player == null:
		return null
	return _player.get_node_or_null("InventoryComponent")


# ---------------------------------------------------------------------------
# Sentinel — summon y control de debug
# ---------------------------------------------------------------------------

## /summon sentinel — instancia un sentinel cerca del player para pruebas.
## Se parenta bajo EntitiesRoot (si existe) para respetar y_sort del mundo.
func _cmd_summon_sentinel() -> void:
	if _world == null:
		Debug.log("commands", "/summon sentinel: world no disponible")
		return
	var entity_root := _world.get_node_or_null("EntitiesRoot")
	var parent: Node = entity_root if entity_root != null else _world
	var sentinel := SENTINEL_SCENE.instantiate() as Sentinel
	var spawn_pos := _get_spawn_position(null)
	parent.add_child(sentinel)
	sentinel.global_position = spawn_pos
	sentinel.home_pos = spawn_pos
	Debug.log("commands", "Sentinel spawneado en %s (bajo '%s')" % [
		str(spawn_pos), parent.name
	])


## /sentinel warn|eject|subdue|return — envía órdenes de debug al primer sentinel.
func _cmd_sentinel(raw_args: Array) -> void:
	if raw_args.is_empty():
		Debug.log("commands", "Uso: /sentinel warn | eject | subdue | return")
		return
	var sentinel := _get_first_sentinel()
	if sentinel == null:
		Debug.log("commands", "/sentinel: no hay sentinel en escena — usa /summon sentinel primero")
		return
	var player_cb := _player as CharacterBody2D
	match String(raw_args[0]).to_lower():
		"warn":
			sentinel.debug_warn(player_cb)
		"eject":
			sentinel.debug_eject(player_cb)
		"subdue":
			sentinel.debug_subdue(player_cb)
		"return":
			sentinel.debug_return()
		_:
			Debug.log("commands", "/sentinel: subcomando desconocido '%s'. Usa: warn | eject | subdue | return" % raw_args[0])


func _get_first_sentinel() -> Sentinel:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("sentinel")
	if nodes.is_empty():
		return null
	return nodes[0] as Sentinel
