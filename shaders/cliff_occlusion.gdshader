shader_type canvas_item;

// Copia exacta de wall_occlusion.gdshader — mismo comportamiento visual
uniform vec2 player_screen_pos = vec2(960.0, 540.0);
uniform float fade_radius = 120.0;
uniform float alpha_hidden = 0.4;
uniform bool is_behind = false;
uniform vec2 screen_size = vec2(1920.0, 1080.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    vec2 screen_pixel = SCREEN_UV * screen_size;

    float dist = distance(screen_pixel, player_screen_pos);
    float t = smoothstep(0.0, fade_radius, dist);
    float alpha_factor = mix(alpha_hidden, 1.0, t);

    tex.a *= mix(1.0, alpha_factor, float(is_behind));

    COLOR = tex;
}
