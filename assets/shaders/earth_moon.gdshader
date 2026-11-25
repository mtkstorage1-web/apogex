shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;

#include "res://assets/shaders/planet_weather.gdshaderinc"

uniform sampler2D surface_map : filter_linear_mipmap, repeat_enable;
uniform bool lunar = false;
uniform bool surface_clouds = false;
varying vec3 sphere_position;
varying vec3 world_position;

void vertex() {
	sphere_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 geographic_uv(vec3 p) {
	return vec2(atan(p.z, p.x) / TAU + 0.5, acos(clamp(p.y, -1.0, 1.0)) / PI);
}

vec3 earth_color(vec3 p, vec3 n, vec3 view, vec3 local_sun) {
	vec2 uv = geographic_uv(p);
	float regional = planet_noise(p * 7.1);
	float fine = planet_noise(p * 35.0 + vec3(0.07, 0.2, 0.8));
	vec2 erosion = vec2(regional - 0.5, fine - 0.5) * 0.013;
	float coast = clamp(texture(surface_map, uv + erosion).r + (fine - 0.5) * 0.15, 0.0, 1.0);
	float land = smoothstep(0.47, 0.55, coast);
	float latitude = abs(p.y);
	float moisture = planet_noise(p * 2.1 + vec3(0.4, 0.8, 0.1));
	float desert = smoothstep(0.15, 0.85,
		(1.0 - smoothstep(0.05, 0.38, abs(latitude - 0.47))) * (1.6 - 1.65 * moisture));
	vec3 ocean = mix(vec3(0.006, 0.046, 0.155), vec3(0.012, 0.29, 0.34),
		pow(smoothstep(0.05, 0.49, coast), 3.0));
	ocean *= mix(0.88, 1.28, regional);
	vec3 biome = mix(vec3(0.016, 0.087, 0.037), vec3(0.095, 0.23, 0.045), fine);
	biome = mix(biome, vec3(0.62, 0.41, 0.20) * mix(0.68, 1.12, regional), desert);
	biome = mix(biome, vec3(0.31, 0.30, 0.22), smoothstep(0.67, 0.8, regional) * 0.8);
	float ice = smoothstep(0.897, 0.967, latitude + (regional - 0.5) * 0.13 + land * 0.026);
	vec3 surface = mix(mix(ocean, biome, land), vec3(0.76, 0.86, 0.92) * (0.77 + 0.23 * fine), ice);
	float daylight = dot(n, sun_direction);
	float terminator = smoothstep(-0.10, 0.15, daylight);
	float glint = pow(max(0.0, dot(n, normalize(view + sun_direction))), 105.0);
	float clouds = cloud_cover(p);
	vec3 light_tangent = local_sun - p * dot(local_sun, p);
	float shadow = cloud_cover(normalize(p + light_tangent * 0.022));
	float town = smoothstep(0.51, 0.69, regional * 0.62 + fine * 0.38);
	float points = smoothstep(0.53, 0.72, planet_noise(p * 133.0));
	float population = land * (1.0 - ice) * (1.0 - desert * 0.77)
		* max(town, 0.55 * (1.0 - smoothstep(0.56, 0.8, coast))) * points;
	vec3 lights = vec3(1.0, 0.51, 0.13) * population * (1.0 - terminator) * 2.6;
	vec3 result = surface * (0.04 + terminator * (0.28 + max(daylight, 0.0) * 0.82))
		* (1.0 - 0.31 * shadow);
	result += vec3(0.62, 0.78, 1.0) * glint * terminator * (1.0 - land)
		* (1.0 - ice) * (1.0 - shadow) * 1.55;
	if (surface_clouds) {
		result = mix(result, vec3(0.84, 0.91, 0.99) * (0.06 + 0.96 * terminator),
			clouds * 0.84);
	}
	return result + lights * (1.0 - clouds * 0.8);
}

vec3 moon_color(vec3 p, vec3 n, mat3 orientation) {
	vec2 uv = geographic_uv(p);
	vec3 terrain = texture(surface_map, uv).rgb;
	float coarse = planet_noise(p * 6.0);
	float gravel = planet_noise(p * 63.0);
	float a = texture(surface_map, geographic_uv(normalize(p + vec3(0.0011, 0.0, 0.0)))).g;
	float b = texture(surface_map, geographic_uv(normalize(p + vec3(0.0, 0.0011, 0.0)))).g;
	float c = texture(surface_map, geographic_uv(normalize(p + vec3(0.0, 0.0, 0.0011)))).g;
	vec3 slope = (vec3(a, b, c) - terrain.g) * 2.8;
	slope -= p * dot(p, slope);
	vec3 shaded_normal = normalize(orientation * (p - slope));
	float light = max(dot(shaded_normal, sun_direction), 0.0);
	float maria = smoothstep(0.12, 0.8, terrain.r + (coarse - 0.48) * 1.18 + (gravel - 0.5) * 0.37);
	float stone = mix(0.40, 0.13, maria) * mix(0.67, 1.27, coarse);
	stone += (terrain.g - 0.53) * 0.29 + (gravel - 0.48) * 0.14 + terrain.b * 0.40;
	float daylight = dot(n, sun_direction);
	vec3 direct = vec3(1.0, 0.97, 0.92) * pow(light, 0.78) * 1.30 * smoothstep(-0.016, 0.025, daylight);
	vec3 earthshine = vec3(0.006, 0.009, 0.015) * (1.0 - smoothstep(-0.2, 0.1, daylight));
	return max(stone, 0.0) * (direct + earthshine);
}

void fragment() {
	vec3 p = normalize(sphere_position);
	vec3 n = normalize((MODEL_MATRIX * vec4(p, 0.0)).xyz);
	vec3 view = normalize(CAMERA_POSITION_WORLD - world_position);
	vec3 color = lunar ? moon_color(p, n, mat3(MODEL_MATRIX)) : earth_color(p, n, view, normalize(sun_direction * mat3(MODEL_MATRIX)));
	ALBEDO = OUTPUT_IS_SRGB ? pow(max(color, vec3(0.0)), vec3(1.0 / 2.2)) : color;
}
