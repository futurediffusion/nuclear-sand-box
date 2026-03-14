shader_type canvas_item;

uniform float sway_speed: hint_range(0.5, 5.0) = 1.5;
uniform float sway_amount: hint_range(0.0, 12.0) = 3.0;
// world_phase: set from script to give each tree a unique offset
uniform float world_phase = 0.0;

void vertex() {
	// UV.y == 0 is the top of the sprite, 1 is the bottom.
	// Leaves sway more at the top and barely at the bottom.
	float strength = 1.0 - UV.y;
	float sway = sin(TIME * sway_speed + world_phase) * sway_amount * strength;
	// Secondary harmonic for a more natural look
	sway += sin(TIME * sway_speed * 1.7 + world_phase + 1.2) * sway_amount * 0.3 * strength;
	VERTEX.x += sway;
}
