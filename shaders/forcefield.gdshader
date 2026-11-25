shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Translucent hexagonal energy containment shield: Fresnel edge intensity + animated pulse.
uniform vec4 field_color : source_color = vec4(0.15, 0.7, 1.0, 1.0);
uniform float hex_scale = 6.0;
uniform float edge_width : hint_range(0.01, 0.4) = 0.08;
uniform float fresnel_power = 2.2;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.08;
// Optional opacity control for gameplay domes driven by the existing shield pulse/flash.
uniform float dome_opacity = -1.0;
uniform float pulse_speed = 1.4;
uniform float intensity : hint_range(0.0, 6.0) = 2.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

// Distance-to-hex-edge: returns 0 at the cell border, ~0.5 at the centre.
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec4 h = vec4(a, b);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void fragment() {
	vec2 p = local_pos.xy * hex_scale * 0.25 + local_pos.zy * hex_scale * 0.1 + vec2(local_pos.z * 0.05, 0.0);
	float e = hex_edge(p);
	float grid = 1.0 - smoothstep(0.0, edge_width, e);
	float wave = 0.5 + 0.5 * sin(local_pos.y * 0.9 - TIME * pulse_speed * 3.0 + local_pos.x * 0.6);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float pulse = 0.65 + 0.35 * sin(TIME * pulse_speed * 2.0);
	float a = base_alpha + grid * (0.35 + 0.65 * wave) * pulse + fres * 0.55;
	ALBEDO = field_color.rgb * intensity * (0.4 + grid + fres);
	ALPHA = clamp(a, 0.0, 1.0);
	if (dome_opacity >= 0.0) {
		// Filter subpixel hex edges along the dome's silhouette.
		float aa = fwidth(e);
		grid = (1.0 - smoothstep(edge_width * 0.5, edge_width + aa, e))
			* (1.0 - smoothstep(0.15, 0.45, aa));
		ALPHA = dome_opacity;
		ALBEDO = field_color.rgb * intensity * (0.16 + 1.45 * grid + 0.50 * fres);
	}
}
