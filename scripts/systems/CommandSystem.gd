extends Node
class_name CommandSystem

## Sistema de comandos de consola del juego.
## Maneja la UI de la barra de comandos y la ejecución de todos los comandos /xxx.
## Se instancia desde main.gd vía setup().

const ENEMY_SCENE: PackedScene      = preload("res://scenes/enemy.tscn")
const WORKBENCH_SCENE: PackedScene  = preload("res://scenes/placeables/workbench_world.tscn")

const COMMAND_PREFIX          := "/"
const COMMAND_BAR_HEIGHT      := 34.0
const COMMAND_SPAWN_MIN_DIST  := 56.0
const COMMAND_SPAWN_MAX_DIST  := 110.0
const DEFAULT_COMMAND_TILE_SIZE := 16.0
const COMMAND_HISTORY_LIMIT   := 10

var _player: Node        = null
var _world: Node         = null
var _ui_layer: CanvasLayer = null

var _command_container: Control = null
var _command_input: LineEdit    = null
var _command_open: bool         = false
var _command_history: Array[String] = []
var _command_history_index: int = -1


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
	_command_input.placeholder_text = "/give <item_id> <n>  |  /dog <n>  |  /summon enemy [n] [ox] [oy]  |  /spawn  |  /spawn_workbench"
	_command_input.clear_button_enabled = true
	_command_input.text_submitted.connect(_on_command_submitted)
	_command_input.gui_input.connect(_on_command_gui_input)
	_command_container.add_child(_command_input)


func _open_command_bar() -> void:
	if _command_container == null or _command_input == null:
		return
	_command_open = true
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
	_command_container.visible = false
	_command_input.text = ""
	_command_input.release_focus()


func _on_command_gui_input(event: InputEvent) -> void:
	if not _command_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_close_command_bar()
			_command_input.accept_event()
			return
		if key_event.keycode == KEY_UP:
			_navigate_command_history(-1)
			_command_input.accept_event()
			return
		if key_event.keycode == KEY_DOWN:
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
# Dispatcher de comandos
# ---------------------------------------------------------------------------
func _execute_command(command_text: String) -> void:
	if not command_text.begins_with(COMMAND_PREFIX):
		Debug.log("commands", "Comando inválido: falta '/' (%s)" % command_text)
		return

	var parts := command_text.substr(1).split(" ", false)
	if parts.size() == 0:
		return

	var base_command := String(parts[0]).to_lower()

	match base_command:
		"spawn":
			_cmd_spawn()
		"spawn_workbench":
			_cmd_spawn_workbench()
		"give":
			_cmd_give(parts.slice(1))
		"dog":
			_cmd_give_gold(parts.slice(1))
		"summon":
			if parts.size() >= 2 and String(parts[1]).to_lower() == "enemy":
				_cmd_summon_enemy(parts.slice(2))
			else:
				Debug.log("commands", "Uso: /summon enemy [cantidad] [offset_x_tiles] [offset_y_tiles]")
		_:
			Debug.log("commands", "Comando desconocido: %s" % base_command)


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

	if item_db.call("get_item", item_id) == null:
		Debug.log("commands", "Item no registrado en ItemDB: %s" % item_id)
		return

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


## /summon enemy [cantidad] [offset_x_tiles] [offset_y_tiles]
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
