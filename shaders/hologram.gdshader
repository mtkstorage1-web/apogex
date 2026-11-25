shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Tactical sci-fi hologram: scanlines, Fresnel rim glow, subtle flicker. Cyan by default, amber via amber_mix.
uniform vec4 cyan_color : source_color = vec4(0.1, 0.85, 1.0, 1.0);
uniform vec4 amber_color : source_color = vec4(1.0, 0.62, 0.12, 1.0);
uniform float amber_mix : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 6.0) = 1.8;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.22;
uniform float scan_density = 6.0;
uniform float scan_speed = 0.35;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.55;
uniform float fresnel_power = 2.4;
uniform float rim_strength = 2.2;
uniform float flicker_speed = 11.0;
uniform float flicker_amount : hint_range(0.0, 0.5) = 0.08;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 col = mix(cyan_color.rgb, amber_color.rgb, amber_mix);
	float scan = 0.5 + 0.5 * sin(local_pos.y * scan_density * 6.2831853 - TIME * scan_speed * 6.2831853);
	scan = mix(1.0, scan, scan_strength);
	float fine = 0.85 + 0.15 * sin(FRAGCOORD.y * 1.7);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float flick = 1.0 - flicker_amount * (0.5 + 0.5 * sin(TIME * flicker_speed + sin(TIME * 3.7) * 4.0));
	float glitch = step(0.985, fract(sin(floor(TIME * 7.0) * 12.9898) * 43758.5453));
	float a = (base_alpha * scan * fine + fres * rim_strength * 0.5) * flick * (1.0 - glitch * 0.6);
	ALBEDO = col * intensity * (0.35 + fres * rim_strength);
	ALPHA = clamp(a, 0.0, 1.0);
}
