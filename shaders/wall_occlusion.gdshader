shader_type canvas_item;

// Posición del player en SCREEN SPACE (píxeles de pantalla, 0,0 = esquina superior izquierda)
// Se pasa desde OcclusionController usando get_viewport().get_camera_2d() o get_viewport_transform()
uniform vec2 player_screen_pos = vec2(960.0, 540.0);

// Radio en píxeles de PANTALLA dentro del cual las paredes se vuelven transparentes
uniform float fade_radius = 120.0;

// Opacidad mínima cuando el player está justo detrás de la pared
uniform float alpha_hidden = 0.4;

uniform bool is_behind = true;

// Resolución de la pantalla (necesaria para convertir SCREEN_UV a píxeles)
uniform vec2 screen_size = vec2(1920.0, 1080.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // SCREEN_UV va de (0,0) a (1,1) — multiplicamos por screen_size para obtener píxeles
    vec2 screen_pixel = SCREEN_UV * screen_size;

    float dist = distance(screen_pixel, player_screen_pos);
    float t = smoothstep(0.0, fade_radius, dist);
    float alpha_factor = mix(alpha_hidden, 1.0, t);

    tex.a *= mix(1.0, alpha_factor, float(is_behind));

    COLOR = tex;
}
