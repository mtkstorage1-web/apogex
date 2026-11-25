shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D weather_tex : filter_linear_mipmap, repeat_enable;
uniform bool lunar = false;
uniform int terrain_detail = 1;
uniform bool animate_water = true;
varying vec3 ground_position;
varying vec3 surface_position;
varying vec3 surface_normal;

void vertex() {
	ground_position = VERTEX;
	surface_position = mat3(MODEL_MATRIX) * VERTEX;
	surface_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

float triplanar_noise(vec3 point, vec3 weights) {
	return dot(weights, vec3(texture(weather_tex, point.zy).r,
		texture(weather_tex, point.xz).r, texture(weather_tex, point.xy).r));
}

float surface_fbm(vec3 point, vec3 weights, int detail) {
	float value = triplanar_noise(point, weights) * 0.56;
	value += triplanar_noise(point * 2.13 + vec3(0.24, 0.51, 0.63), weights) * 0.29;
	return value + (detail >= 1 ? triplanar_noise(point * 4.37 + vec3(0.63, 0.21, 0.37), weights) : 0.5) * 0.15;
}

float regolith_pits(vec2 point) {
	vec2 cell = floor(point);
	vec3 seed = fract(vec3(cell.xyx) * vec3(0.1031, 0.1030, 0.0973));
	seed += dot(seed, seed.yzx + 33.33);
	vec2 center = vec2(0.5) + (fract((seed.xy + seed.yz) * seed.zx) - 0.5) * 0.30;
	float radius = mix(0.13, 0.32, fract(seed.x * seed.y));
	float distance_to_rim = length(fract(point) - center) / radius;
	float bowl = 1.0 - smoothstep(0.0, 0.95, distance_to_rim);
	float rim = smoothstep(0.72, 0.96, distance_to_rim) * (1.0 - smoothstep(0.96, 1.08, distance_to_rim));
	return (rim * 0.32 - bowl) * (1.0 - smoothstep(0.12, 0.45, length(fwidth(point))));
}

vec3 relief_normal(vec3 point, vec3 normal, float height) {
	vec3 dx = dFdx(point);
	vec3 dy = dFdy(point);
	vec3 across_x = cross(dy, normal);
	vec3 across_y = cross(normal, dx);
	float det = dot(dx, across_x);
	vec3 gradient = (across_x * dFdx(height) + across_y * dFdy(height)) * sign(det) / max(abs(det), 0.000001);
	return normalize(normal - gradient / max(1.0, length(gradient) * 1.6));
}

void fragment() {
	vec2 p = ground_position.xz;
	vec3 point = surface_position;
	vec3 base_normal = normalize(surface_normal);
	vec3 weights = pow(abs(base_normal), vec3(4.0));
	weights /= dot(weights, vec3(1.0));
	float macro_a = triplanar_noise(point * 0.012, weights);
	float macro_b = triplanar_noise(point * 0.052 + vec3(0.37, 0.83, 0.19), weights);
	float soft_blend = macro_a * 0.64 + macro_b * 0.36;
	float relief = 1.0 - max(0.0, base_normal.y);
	float grain = surface_fbm(point * (lunar ? 1.85 : 1.18), weights, terrain_detail);
	float aggregate = triplanar_noise(point * 0.31, weights);
	float height = (grain - 0.5) * (lunar ? 0.022 : 0.027);

	vec3 soil;
	if (lunar) {
		vec2 ejecta = p - vec2(-190.0, -210.0);
		float angle = atan(ejecta.y, ejecta.x);
		float ray = pow(max(0.0, sin(angle * 19.0) + 0.35 * sin(angle * 27.0)), 5.0);
		ray *= smoothstep(24.0, 72.0, length(ejecta)) * (1.0 - smoothstep(65.0, 320.0, length(ejecta)));
		float pits = regolith_pits(p * 0.74 + vec2(0.33, 0.87));
		if (terrain_detail >= 1) {
			pits += 0.28 * regolith_pits(p * 3.1 + vec2(0.79, 0.41));
		}
		float dust = smoothstep(0.32, 0.72, soft_blend + (aggregate - 0.5) * 0.36);
		soil = mix(vec3(0.071, 0.067, 0.064), vec3(0.28, 0.26, 0.23), dust);
		soil *= 0.89 + grain * 0.22 + pits * 0.22;
		soil += vec3(0.09) * min(ray, 1.0) * macro_b;
		height += pits * 0.033;
		float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0);
		float flecks = smoothstep(0.64, 0.83, grain) * grazing;
		ROUGHNESS = mix(0.74, 0.92, dust) - flecks * 0.18;
		SPECULAR = 0.25 + flecks * 0.32;
		AO = 1.0 + min(pits, 0.0) * 0.34;
	} else {
		// Rich, grounded emerald & sunlit meadow greens (SEUS/BSL Minecraft shader palette).
		vec3 deep_meadow = vec3(0.032, 0.105, 0.022);
		vec3 sunlit_meadow = vec3(0.072, 0.175, 0.036);
		vec3 clover_patch = vec3(0.048, 0.140, 0.028);
		vec3 grass_col = mix(deep_meadow, sunlit_meadow, smoothstep(0.24, 0.78, soft_blend));
		grass_col = mix(grass_col, clover_patch, smoothstep(0.42, 0.84, macro_b) * 0.40);

		// Warm mossy earth on gentle slopes, crisp blue-slate stone on steep mountain ridges.
		vec3 warm_earth = vec3(0.11, 0.088, 0.048);
		vec3 mountain_stone = vec3(0.11, 0.145, 0.18);
		vec3 sunlit_peak = vec3(0.19, 0.23, 0.27);
		float dry = smoothstep(0.51, 0.72, macro_b + (aggregate - 0.5) * 0.37);
		float moss = smoothstep(0.53, 0.76, macro_a) * (1.0 - dry);
		grass_col = mix(grass_col, vec3(0.24, 0.19, 0.075), dry * 0.77);
		grass_col = mix(grass_col, vec3(0.16, 0.22, 0.047), moss * 0.82);
		float soil_mask = smoothstep(0.08, 0.28, relief + (aggregate - 0.5) * 0.23);
		soil_mask = max(soil_mask, smoothstep(0.57, 0.75, macro_b * 0.72 + aggregate * 0.28));
		float slope_rock = smoothstep(0.18, 0.43, relief + (aggregate - 0.5) * 0.13);
		float gravel = smoothstep(0.53, 0.72, grain + (aggregate - 0.5) * 0.23);
		float bedding = point.y * 1.55 + point.x * 0.19 + (aggregate - 0.5) * 1.6;
		float strata_fade = 1.0 - smoothstep(0.15, 0.65, fwidth(bedding));
		float strata = (smoothstep(0.14, 0.54, sin(bedding)) - 0.36) * strata_fade;
		vec3 rock_col = mix(mountain_stone, sunlit_peak, smoothstep(0.35, 0.75, macro_a));
		rock_col = rock_col * (1.0 + strata * 0.39) + vec3(0.075, 0.055, 0.025) * gravel;
		soil = mix(grass_col, warm_earth * (0.80 + gravel * 0.78), soil_mask);
		soil = mix(soil, rock_col, slope_rock) * (0.76 + grain * 0.48);
		height += gravel * soil_mask * 0.013 + slope_rock * (strata * 0.027 + (aggregate - 0.5) * 0.085);

		// Luminous turquoise-to-cerulean coastal ocean with smooth ripples and soft shoreline foam.
		float coast = smoothstep(450.0, 660.0, -p.y);
		float water = (1.0 - smoothstep(-15.8, -14.1, ground_position.y)) * coast;
		float t = animate_water ? TIME : 0.0;
		float surf_a = texture(weather_tex, p * vec2(0.018, 0.048) + vec2(0.028, -0.008) * t).r;
		float surf_b = texture(weather_tex, p * vec2(0.032, 0.022) - vec2(0.014, 0.020) * t).r;
		float surf = surf_a * 0.6 + surf_b * 0.4;
		vec3 shallow_teal = vec3(0.06, 0.44, 0.46);
		vec3 deep_cerulean = vec3(0.02, 0.20, 0.38);
		vec3 ocean = mix(deep_cerulean, shallow_teal, smoothstep(0.25, 0.78, surf));
		float foam = smoothstep(0.66, 0.82, surf) * (1.0 - smoothstep(660.0, 960.0, -p.y));
		ocean += vec3(0.36, 0.58, 0.64) * foam * 0.55;
		soil = mix(soil, ocean, water);

		float land_roughness = mix(0.66 + dry * 0.19, 0.92, soil_mask);
		land_roughness = mix(land_roughness, mix(0.45, 0.85, aggregate), slope_rock);
		ROUGHNESS = mix(clamp(land_roughness + (grain - 0.5) * 0.13, 0.45, 0.92), 0.10, water);
		SPECULAR = mix(0.32, 0.78, water);
		height = mix(height, (surf - 0.5) * 0.039, water);

		if (terrain_detail >= 3) {
			float wet_edge = coast * (1.0 - smoothstep(-14.4, -11.4, ground_position.y));
			float damp = wet_edge * (1.0 - water);
			soil *= 1.0 - 0.18 * damp;
			ROUGHNESS = mix(ROUGHNESS, 0.45, damp);
			SPECULAR = mix(SPECULAR, 0.55, damp);

			float turf = (1.0 - slope_rock) * (1.0 - max(wet_edge, water));
			float cloud = texture(weather_tex, p * 0.0026 - vec2(0.009, 0.005) * t).r;
			soil *= 1.0 - 0.12 * turf * smoothstep(0.45, 0.72, cloud);
		}
	}

	vec3 color = soil * (0.92 + soft_blend * 0.16);
	NORMAL = normalize(mat3(VIEW_MATRIX) * relief_normal(point, base_normal, height));
	ALBEDO = OUTPUT_IS_SRGB ? pow(max(color, vec3(0.0)), vec3(1.0 / 2.2)) : color;
}
