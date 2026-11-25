shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled;

uniform vec4 plasma_color : source_color = vec4(0.09, 0.8, 1.0, 1.0);
uniform float throttle : hint_range(0.0, 2.0) = 0.0;
uniform float plume_length = 1.0;
varying vec3 plume_position;

void vertex() {
	plume_position = VERTEX;
	float phase = TIME * 31.0 + VERTEX.y * 6.0;
	VERTEX.xz *= 1.0 + sin(phase) * 0.075 * throttle;
}

void fragment() {
	float tail = plume_position.y / max(plume_length, 0.01) + 0.5;
	float falloff = pow(clamp(tail, 0.0, 1.0), 1.5);
	float turbulence = 0.79 + 0.13 * sin(TIME * 47.0 + plume_position.y * 11.0)
		+ 0.08 * sin(TIME * 73.0 + UV.x * 51.0 + plume_position.y * 19.0);
	float rim = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.7);
	ALBEDO = mix(plasma_color.rgb, vec3(0.87, 0.96, 1.0), falloff * 0.66);
	EMISSION = ALBEDO * (0.7 + throttle * 2.3) * falloff;
	ALPHA = clamp(throttle * falloff * turbulence * (0.27 + 0.55 * rim), 0.0, 1.0);
}
