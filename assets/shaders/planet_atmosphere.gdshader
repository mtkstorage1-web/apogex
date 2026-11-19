shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 sun_direction = vec3(0.45, 0.7, 0.55);
uniform float observer_fade : hint_range(0.0, 1.0) = 1.0;
uniform float inner_ratio = 0.985;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 view = normalize(CAMERA_POSITION_WORLD - world_position);
	vec3 normal = normalize(world_normal);
	float facing = abs(dot(view, normal));
	float max_chord = sqrt(1.0 - inner_ratio * inner_ratio);
	float depth = clamp(facing / max_chord, 0.0, 1.0);
	vec3 tangent = normalize(normal - dot(normal, view) * view);
	float daylight = dot(tangent, sun_direction);
	float day = smoothstep(-0.14, 0.25, daylight);
	float sunset = exp(-abs(daylight - 0.015) * 9.0);
	vec3 blue = vec3(0.09, 0.37, 1.0);
	vec3 amber = vec3(1.0, 0.27, 0.06);
	vec3 color = mix(blue, amber, sunset * 0.75);
	ALPHA = (0.025 + 0.68 * day + 0.36 * sunset) * depth * depth * observer_fade;
	ALBEDO = OUTPUT_IS_SRGB ? pow(max(color, vec3(0.0)), vec3(1.0 / 2.2)) : color;
}
