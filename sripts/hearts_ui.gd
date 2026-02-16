extends HBoxContainer

@export var max_hearts: int = 3
@export var full_tex: Texture2D
@export var empty_tex: Texture2D

func _ready() -> void:
	_ensure_heart_slots()
	set_hearts(max_hearts)

func set_hearts(current_hp: int) -> void:
	_ensure_heart_slots()
	var clamped_hp := clamp(current_hp, 0, max_hearts)
	for i in range(get_child_count()):
		var heart := get_child(i) as TextureRect
		if heart == null:
			continue

		heart.texture = full_tex if i < clamped_hp else empty_tex

func _ensure_heart_slots() -> void:
	var target_count := maxi(max_hearts, 0)

	while get_child_count() < target_count:
		var heart := TextureRect.new()
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.custom_minimum_size = Vector2(16, 16)
		add_child(heart)

	while get_child_count() > target_count:
		var extra := get_child(get_child_count() - 1)
		extra.queue_free()
