extends Node
class_name OcclusionController

@export var tilemaps: Array[NodePath] = []
@export var walls_layer: int = 2
@export var fade_radius: float = 96.0
@export var alpha_hidden: float = 0.35

var _materials: Array[ShaderMaterial] = []
var _tilemaps: Array[TileMap] = []

func _ready() -> void:
	call_deferred("_find_materials")

func _find_materials() -> void:
	_materials.clear()
	_tilemaps.clear()
	for path in tilemaps:
		var tm := get_node_or_null(path) as TileMap
		if tm == null:
			push_warning("[OcclusionController] tilemap no encontrado: %s" % path)
			continue
		var mat := tm.material as ShaderMaterial
		if mat == null:
			push_warning("[OcclusionController] sin ShaderMaterial en: %s" % path)
			continue
		_tilemaps.append(tm)
		_materials.append(mat)
	print("[OcclusionController] materiales encontrados: %d" % _materials.size())

func _process(_delta: float) -> void:
	if _materials.is_empty():
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player := players[0] as Node2D
	if player == null:
		return
	for i in range(_materials.size()):
		var tm: TileMap = _tilemaps[i]
		var mat: ShaderMaterial = _materials[i]
		var local_pos: Vector2 = tm.to_local(player.global_position)
		mat.set_shader_parameter("player_pos", local_pos)
		mat.set_shader_parameter("fade_radius", fade_radius)
		mat.set_shader_parameter("alpha_hidden", alpha_hidden)
		mat.set_shader_parameter("is_behind", true)
