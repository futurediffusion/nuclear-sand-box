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

# --- NUEVO: uso/consumibles ---
@export_group("Use")
@export var consumable: bool = false
@export var heal_hp: int = 0  # 1 = cura 1 corazón
