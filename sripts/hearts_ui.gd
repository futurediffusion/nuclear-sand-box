extends HBoxContainer

@export var max_hearts: int = 3
@export var full_tex: Texture2D
@export var empty_tex: Texture2D

func _ready() -> void:
	set_hearts(max_hearts)

func set_hearts(current_hp: int) -> void:
	var clamped_hp := clamp(current_hp, 0, max_hearts)
	for i in range(get_child_count()):
		var heart := get_child(i) as TextureRect
		if heart == null:
			continue

		heart.texture = full_tex if i < clamped_hp else empty_tex
