shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;

uniform vec3 cool_shadow_tint : source_color = vec3(0.40, 0.54, 0.90);
uniform float shadow_desaturation : hint_range(0.0, 1.0) = 0.62;
uniform float highlight_protection : hint_range(0.0, 1.0) = 0.10;

uniform float shadow_mask_pow : hint_range(0.2, 4.0) = 1.75;
uniform float shadow_smooth_start : hint_range(0.0, 1.0) = 0.14;
uniform float shadow_smooth_end : hint_range(0.0, 1.0) = 0.66;
uniform float night_curve_pow : hint_range(0.2, 3.0) = 1.35;
uniform float shadow_darken : hint_range(0.0, 1.0) = 0.55;
uniform float midtone_darken : hint_range(0.0, 1.0) = 0.30;

uniform vec3 global_night_tint : source_color = vec3(0.72, 0.80, 0.96);
uniform float global_blue_strength : hint_range(0.0, 1.0) = 0.22;
uniform float overall_darken : hint_range(0.0, 0.5) = 0.14;

uniform bool vignette_enabled = true;
uniform float vignette_strength : hint_range(0.0, 0.35) = 0.18;
uniform float vignette_inner : hint_range(0.0, 1.2) = 0.68;
uniform float vignette_outer : hint_range(0.1, 2.0) = 1.05;

void fragment() {
	vec3 src = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

	float luma = dot(src, vec3(0.2126, 0.7152, 0.0722));
	float shadow_mask = 1.0 - smoothstep(shadow_smooth_start, shadow_smooth_end, luma);
	shadow_mask = pow(clamp(shadow_mask, 0.0, 1.0), shadow_mask_pow);

	float night = clamp(night_amount, 0.0, 1.0);

	float desat_mix = clamp(shadow_mask * shadow_desaturation * night, 0.0, 1.0);
	vec3 desaturated = mix(src, vec3(luma), desat_mix);

	float tint_mix = clamp(shadow_mask * night, 0.0, 1.0);
	vec3 tinted = mix(desaturated, desaturated * cool_shadow_tint, tint_mix);

	float highlights = smoothstep(0.62, 1.0, luma);
	float shadow_darken_mask = shadow_mask * night;
	float midtone_mask = clamp((1.0 - highlights) * (1.0 - shadow_mask), 0.0, 1.0) * night;
	float darken = clamp(shadow_darken_mask * shadow_darken + midtone_mask * midtone_darken, 0.0, 1.0);
	vec3 darkened = tinted * (1.0 - darken);

	float moonlight = clamp(highlights * highlight_protection * night, 0.0, 1.0);
	vec3 recovered = mix(darkened, src, moonlight);

	float global_tint_mix = clamp(global_blue_strength * night, 0.0, 1.0);
	vec3 globally_tinted = mix(recovered, recovered * global_night_tint, global_tint_mix);
	float global_darken = clamp(overall_darken * night, 0.0, 1.0);
	vec3 night_graded = globally_tinted * (1.0 - global_darken);

	float blend_curve = smoothstep(0.0, 1.0, pow(night, night_curve_pow));
	vec3 result = mix(src, night_graded, blend_curve);

	if (vignette_enabled) {
		vec2 p = SCREEN_UV * 2.0 - 1.0;
		float d = length(p);
		float vig = smoothstep(vignette_inner, vignette_outer, d);
		float vig_dark = 1.0 - vig * vignette_strength * blend_curve;
		result *= clamp(vig_dark, 0.0, 1.0);
	}

	COLOR = vec4(result, 1.0);
}
