extends Camera2D

@export var look_distance: float = 60.0
@export var smooth_speed: float = 7.0

# --- SHAKE ---
@export var shake_decay: float = 8.0
var shake_strength: float = 0.0

# --- IMPULSE SHAKE (muerte fuerte) ---
var impulse_time_left: float = 0.0
var impulse_duration: float = 0.0
var impulse_magnitude: float = 0.0

func _process(delta: float) -> void:
	# -------------------
	# LOOK AHEAD MOUSE
	# -------------------
	var mouse_pos := get_global_mouse_position()
	var to_mouse: Vector2 = mouse_pos - global_position

	var dist := to_mouse.length()
	var target_offset := Vector2.ZERO

	if dist > 0.001:
		var dir := to_mouse / dist
		var t: float = clamp(dist / 350.0, 0.0, 1.0)
		target_offset = dir * look_distance * t

	# suavizado del look-ahead
	var final_offset := offset.lerp(target_offset, delta * smooth_speed)

	# -------------------
	# SHAKE normal (golpes)
	# -------------------
	if shake_strength > 0.0:
		final_offset += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_strength
		shake_strength = lerp(shake_strength, 0.0, delta * shake_decay)

	# -------------------
	# SHAKE por impulso (muerte)
	# -------------------
	if impulse_time_left > 0.0:
		impulse_time_left = max(impulse_time_left - delta, 0.0)
		var normalized_time: float = impulse_time_left / maxf(impulse_duration, 0.001)
		var impulse_strength: float = impulse_magnitude * normalized_time * normalized_time
		final_offset += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * impulse_strength

	offset = final_offset

func shake(amount: float) -> void:
	shake_strength = max(shake_strength, amount)

func shake_impulse(duration: float, magnitude: float) -> void:
	impulse_duration = max(duration, 0.01)
	impulse_time_left = impulse_duration
	impulse_magnitude = max(impulse_magnitude, magnitude)
