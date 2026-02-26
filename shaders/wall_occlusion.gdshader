shader_type canvas_item;

uniform vec2 player_pos = vec2(0.0);
uniform float fade_radius = 96.0;
uniform float alpha_hidden = 0.35;
uniform bool is_behind = false;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    if (is_behind) {
        vec2 world_px = (CANVAS_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
        float dist = distance(world_px, player_pos);
        float t = smoothstep(fade_radius * 0.5, fade_radius, dist);
        tex.a *= mix(alpha_hidden, 1.0, t);
    }
    COLOR = tex;
}
