shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://assets/shaders/planet_weather.gdshaderinc"

uniform float observer_fade = 1.0;
varying vec3 sphere_position;

void vertex() {
	sphere_position = VERTEX;
}

void fragment() {
	vec3 p = normalize(sphere_position);
	vec3 n = normalize((MODEL_MATRIX * vec4(p, 0.0)).xyz);
	float daylight = dot(n, sun_direction);
	float twilight = smoothstep(-0.16, 0.15, daylight);
	float cover = cloud_cover(p);
	// Volumetric look: dense cores self-shadow blue-grey, thin edges catch warm sun.
	float dense = smoothstep(0.55, 1.0, cover);
	vec3 shadow_col = vec3(0.30, 0.38, 0.55);
	vec3 lit_col = mix(vec3(0.94, 0.96, 1.0), vec3(1.0, 0.90, 0.74), (1.0 - twilight) * 0.8 + pow(max(daylight, 0.0), 0.2) * 0.0);
	vec3 color = mix(shadow_col, lit_col, mix(0.55, 1.0, 1.0 - dense * 0.45) * cover + (1.0 - cover) * 0.5)
		* (0.035 + 0.50 * twilight + 0.55 * max(0.0, daylight));
	color += vec3(1.0, 0.78, 0.52) * (1.0 - cover) * cover * 0.6 * twilight;
	ALPHA = cover * observer_fade * 0.88;
	ALBEDO = OUTPUT_IS_SRGB ? pow(max(color, vec3(0.0)), vec3(1.0 / 2.2)) : color;
}
