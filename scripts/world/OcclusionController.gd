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
    _material = tilemap.get_layer_material(walls_layer) as ShaderMaterial
    if _material == null:
        push_warning("[OcclusionController] no hay ShaderMaterial en layer %d" % walls_layer)

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
