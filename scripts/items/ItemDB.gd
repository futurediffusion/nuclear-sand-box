extends Node

@export var item_list: Array[ItemData] = []

var items: Dictionary = {}

func _ready() -> void:
	for data in item_list:
		register_item(data)

	_auto_register_from_folder("res://data/items")

	if items.is_empty():
		print("[ItemDB] ready with 0 items")
	else:
		for id in items.keys():
			var data: ItemData = items[id]
			print("[ItemDB] registered id=", id, " display=", data.display_name, " max_stack=", data.max_stack)

func register_item(data: ItemData) -> void:
	if data == null:
		push_warning("[ItemDB] register_item recibió null")
		return

	if data.id.strip_edges() == "":
		push_warning("[ItemDB] item sin id: " + str(data.resource_path))
		return

	if items.has(data.id):
		push_warning("[ItemDB] id duplicado: " + data.id + " (sobrescribiendo)")

	items[data.id] = data

func get_item(id: String) -> ItemData:
	if id == "":
		return null
	return items.get(id, null) as ItemData

func get_max_stack(id: String, fallback: int) -> int:
	var data := get_item(id)
	if data == null:
		return fallback
	return maxi(1, data.max_stack)

func get_icon(id: String) -> Texture2D:
	var data := get_item(id)
	if data == null:
		return null
	return data.icon

func get_buy_price(id: String, fallback: int = 0) -> int:
	var data := get_item(id)
	if data == null:
		return fallback
	return data.buy_price

func get_sell_price(id: String, fallback: int = 0) -> int:
	var data := get_item(id)
	if data == null:
		return fallback
	return data.sell_price

func get_display_name(id: String, fallback: String = "") -> String:
	var data := get_item(id)
	if data == null:
		return fallback
	return data.display_name

func _auto_register_from_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[ItemDB] no se pudo abrir carpeta: " + path)
		return

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue

		var full_path := path.path_join(file_name)
		var res := load(full_path)
		if res is ItemData:
			register_item(res as ItemData)
	dir.list_dir_end()
