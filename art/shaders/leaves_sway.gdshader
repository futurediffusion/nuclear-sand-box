shader_type canvas_item;

uniform float sway_speed: hint_range(0.5, 5.0) = 1.5;
uniform float sway_amount: hint_range(0.0, 12.0) = 3.0;
// Portion of the lower sprite locked in place (0.0 = none, 0.5 = lower half fixed)
uniform float sway_base_lock: hint_range(0.0, 0.8) = 0.0;
// world_phase: set from script to give each tree a unique offset
uniform float world_phase = 0.0;
// Optional touch impulse (used by grass tufts). Keep at 0 for normal sway.
uniform float touch_offset: hint_range(-24.0, 24.0) = 0.0;
uniform float touch_profile_exp: hint_range(1.0, 5.0) = 2.0;

void vertex() {
	// UV.y == 0 is the top of the sprite, 1 is the bottom.
	// Leaves sway at the top while keeping the lower/root area stable.
	float height = clamp(1.0 - UV.y, 0.0, 1.0);
	float strength = smoothstep(sway_base_lock, 1.0, height);
	float sway = sin(TIME * sway_speed + world_phase) * sway_amount * strength;
	// Secondary harmonic for a more natural look
	sway += sin(TIME * sway_speed * 1.7 + world_phase + 1.2) * sway_amount * 0.3 * strength;
	// Touch bend: stronger at the top, near zero at the base.
	sway += touch_offset * pow(strength, touch_profile_exp);
	VERTEX.x += sway;
}
