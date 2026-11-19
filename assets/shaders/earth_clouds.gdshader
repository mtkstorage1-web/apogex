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
	vec3 color = mix(vec3(0.30, 0.40, 0.58), vec3(0.86, 0.91, 0.96), cover)
		* (0.035 + 0.54 * twilight + 0.45 * max(0.0, daylight));
	ALPHA = cover * observer_fade * 0.88;
	ALBEDO = OUTPUT_IS_SRGB ? pow(max(color, vec3(0.0)), vec3(1.0 / 2.2)) : color;
}
