shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled;

uniform vec4 energy_color : source_color = vec4(0.08, 0.8, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 2.5;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 3.0);
	ALBEDO = mix(energy_color.rgb, vec3(0.98, 0.99, 1.0), core);
	EMISSION = ALBEDO * intensity * (0.45 + core);
	ALPHA = (0.28 + facing * 0.53) * min(intensity, 1.0);
}
