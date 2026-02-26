extends Node
class_name OcclusionController

@export var tilemap: TileMap
@export var walls_layer: int = 2
@export var fade_radius: float = 96.0
@export var alpha_hidden: float = 0.35

var _material: ShaderMaterial = null

func _ready() -> void:
	if tilemap == null:
		push_warning("[OcclusionController] tilemap no asignado")
		return
	# En Godot 4, el material del layer se setea como ShaderMaterial
	# directamente en el TileMap y se accede via get_material()
	# si el material fue asignado en el inspector al nodo TileMap completo.
	# Usamos call_deferred para asegurarnos que el tilemap terminó su _ready.
	call_deferred("_find_material")

func _find_material() -> void:
	if tilemap == null:
		return
	# Intentar leer el material del layer via tile_set o via el nodo
	var mat = tilemap.get_layer_modulate(walls_layer)  # solo para verificar que el layer existe
	# El ShaderMaterial se asigna en el inspector al TileMap directamente
	_material = tilemap.material as ShaderMaterial
	if _material == null:
		push_warning("[OcclusionController] asigna un ShaderMaterial al nodo WorldTileMap en el inspector")

func _process(_delta: float) -> void:
	if _material == null:
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player := players[0] as Node2D
	if player == null:
		return
	var local_pos: Vector2 = tilemap.to_local(player.global_position)
	_material.set_shader_parameter("player_pos", local_pos)
	_material.set_shader_parameter("fade_radius", fade_radius)
	_material.set_shader_parameter("alpha_hidden", alpha_hidden)
