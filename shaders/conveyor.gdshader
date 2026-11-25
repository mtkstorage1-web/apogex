shader_type spatial;
render_mode cull_disabled;

// Industrial conveyor belt: scrolling ribbed metallic treads + directional hazard chevrons along UV.y.
// UV.x spans the belt width (0..1); UV.y runs along the belt (already scaled in tile units).
uniform vec4 belt_color : source_color = vec4(0.1, 0.1, 0.11, 1.0);
uniform vec4 tread_color : source_color = vec4(0.42, 0.44, 0.46, 1.0);
uniform vec4 hazard_yellow : source_color = vec4(0.95, 0.72, 0.05, 1.0);
uniform vec4 hazard_black : source_color = vec4(0.04, 0.04, 0.04, 1.0);
uniform float speed = 0.6;
uniform float rib_count = 1.0;
uniform float edge_width : hint_range(0.02, 0.3) = 0.12;
uniform float chevron_scale = 3.0;

void fragment() {
	float v = UV.y * rib_count - TIME * speed;
	vec2 uv = vec2(UV.x, v);
	float rib = smoothstep(0.35, 0.5, abs(fract(uv.y * 4.0) - 0.5));
	float edge = min(uv.x, 1.0 - uv.x);
	vec3 col = mix(belt_color.rgb, tread_color.rgb, rib * 0.85);
	float metal = mix(0.2, 0.85, rib);
	float rough = mix(0.8, 0.35, rib);
	if (edge < edge_width) {
		float side = uv.x < 0.5 ? 1.0 : -1.0;
		float d = (uv.y * chevron_scale + edge * chevron_scale * 3.0 * side);
		float stripe = step(0.5, fract(abs(d)));
		col = mix(hazard_black.rgb, hazard_yellow.rgb, stripe);
		metal = 0.1;
		rough = 0.6;
	}
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
}
