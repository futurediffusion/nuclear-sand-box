extends Node
class_name OcclusionController

## Asigna SOLO los tilemaps de PAREDES aquí, NO el tilemap de suelo.
## Si se deja vacío busca automáticamente por nombre "StructureWallsMap".
@export var tilemaps: Array[NodePath] = []
@export var fade_radius: float = 120.0
@export var alpha_hidden: float = 0.4

var _materials: Array[ShaderMaterial] = []
var _tilemaps: Array[TileMap] = []
var _screen_size: Vector2 = Vector2(1920, 1080)
var _cadence_enabled: bool = false
var _material_cursor: int = 0

func _ready() -> void:
	call_deferred("_find_materials")

func configure_cadence(enabled: bool) -> void:
	_cadence_enabled = enabled
	set_process(not _cadence_enabled)

func _find_materials() -> void:
	_materials.clear()
	_tilemaps.clear()

	var vp := get_viewport()
	if vp != null:
		_screen_size = Vector2(vp.get_visible_rect().size)

	var candidates: Array[TileMap] = []

	# 1) NodePaths explícitos desde el Inspector
	for path in tilemaps:
		if path == NodePath(""):
			continue
		var tm := get_node_or_null(path) as TileMap
		if tm != null:
			candidates.append(tm)

	# 2) Fallback: buscar por nombre — SOLO mapas de paredes
	if candidates.is_empty():
		var wall_names := ["StructureWallsMap", "WallsTileMap", "WallMap", "Walls"]
		_collect_tilemaps_by_name(get_parent(), candidates, wall_names, 4)

	if candidates.is_empty():
		push_warning("[OcclusionController] No se encontró tilemap de paredes. Asigna 'tilemaps' en el Inspector con SOLO el mapa de paredes.")
		return

	for tm in candidates:
		var found_mat: ShaderMaterial = null
		if tm.material is ShaderMaterial:
			found_mat = tm.material as ShaderMaterial

		if found_mat != null:
			_tilemaps.append(tm)
			_materials.append(found_mat)
			found_mat.set_shader_parameter("screen_size", _screen_size)
			found_mat.set_shader_parameter("fade_radius", fade_radius)
			found_mat.set_shader_parameter("alpha_hidden", alpha_hidden)
			found_mat.set_shader_parameter("is_behind", true)
			print("[OcclusionController] OK (walls only): %s" % tm.get_path())
		else:
			push_warning("[OcclusionController] '%s' no tiene ShaderMaterial en CanvasItem.material" % tm.get_path())

	print("[OcclusionController] Materiales de pared encontrados: %d" % _materials.size())

func _collect_tilemaps_by_name(node: Node, out: Array[TileMap], names: Array, depth: int) -> void:
	if depth <= 0 or node == null:
		return
	for child in node.get_children():
		if child is TileMap and names.has(child.name):
			out.append(child as TileMap)
		_collect_tilemaps_by_name(child, out, names, depth - 1)

func _process(_delta: float) -> void:
	if _cadence_enabled:
		return
	_process_occlusion(1)

func tick_from_cadence(pulses: int, material_budget_per_pulse: int = -1) -> int:
	if pulses <= 0:
		return 0
	var max_updates: int = -1
	if material_budget_per_pulse > 0:
		max_updates = pulses * material_budget_per_pulse
	return _process_occlusion(max_updates)

func _process_occlusion(material_budget: int = -1) -> int:
	if _materials.is_empty():
		return 0

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return 0

	var player := players[0] as Node2D
	if player == null:
		return 0

	var vp := get_viewport()
	if vp == null:
		return 0

	var screen_pos: Vector2 = vp.get_canvas_transform() * player.global_position

	var current_size := Vector2(vp.get_visible_rect().size)
	var size_changed := not current_size.is_equal_approx(_screen_size)
	if size_changed:
		_screen_size = current_size

	var total_mats: int = _materials.size()
	if total_mats <= 0:
		return 0
	var updates: int = 0
	var limit: int = total_mats if material_budget <= 0 else mini(total_mats, material_budget)
	var start_index: int = _material_cursor
	for step in limit:
		var idx: int = (start_index + step) % total_mats
		var mat := _materials[idx]
		mat.set_shader_parameter("player_screen_pos", screen_pos)
		if size_changed:
			mat.set_shader_parameter("screen_size", _screen_size)
		updates += 1
	_material_cursor = (start_index + limit) % total_mats
	return updates
