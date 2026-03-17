extends Resource
class_name ItemData

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export var max_stack: int = 10
@export var buy_price: int = 0
@export var sell_price: int = 0
@export var tags: Array[String] = []
@export var weight: float = 0.0
@export var pickup_sfx: AudioStream

@export_group("Placement")
@export var placement_mode: String = ""
@export_file("*.tscn") var placement_scene_path: String = ""
@export var repeat_place: bool = false
@export var drag_paintable: bool = false
@export var can_share_tile_with: Array[String] = []
@export var ignore_collision_groups_when_placing: Array[String] = []

# --- NUEVO: uso/consumibles ---
@export_group("Use")
@export var consumable: bool = false
@export var heal_hp: int = 0  # 1 = cura 1 corazón
