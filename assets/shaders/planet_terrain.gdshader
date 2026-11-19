shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D weather_tex : filter_linear_mipmap, repeat_enable;
uniform bool lunar = false;
uniform int terrain_detail = 1;
uniform bool animate_water = true;
varying vec3 ground_position;

void vertex() {
	ground_position = VERTEX;
}

void fragment() {
	vec2 p = ground_position.xz;
	// Smooth macro-scale variation only — zero high-frequency grain or dFdx noise.
	float macro_a = texture(weather_tex, p * 0.0038).r;
	float macro_b = texture(weather_tex, p * 0.014 + vec2(0.37, 0.19)).r;
	float soft_blend = clamp(macro_a * 0.68 + macro_b * 0.32, 0.0, 1.0);
	float relief = 1.0 - max(0.0, dot(normalize(NORMAL), normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)));

	vec3 soil;
	if (lunar) {
		vec2 ejecta = p - vec2(-190.0, -210.0);
		float angle = atan(ejecta.y, ejecta.x);
		float ray = pow(max(0.0, sin(angle * 19.0) + 0.35 * sin(angle * 27.0)), 5.0);
		ray *= smoothstep(24.0, 72.0, length(ejecta)) * (1.0 - smoothstep(65.0, 320.0, length(ejecta)));
		soil = mix(vec3(0.12, 0.12, 0.115), vec3(0.32, 0.30, 0.28), soft_blend);
		soil += vec3(0.09) * min(ray, 1.0) * macro_b;
		ROUGHNESS = 0.94;
		SPECULAR = 0.22;
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
		float slope_earth = smoothstep(0.14, 0.34, relief) * (1.0 - smoothstep(0.36, 0.56, relief));
		float slope_rock = smoothstep(0.28, 0.56, relief);
		soil = mix(grass_col, warm_earth, slope_earth * 0.42);
		vec3 rock_col = mix(mountain_stone, sunlit_peak, smoothstep(0.35, 0.80, macro_a));
		soil = mix(soil, rock_col, slope_rock);

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

		ROUGHNESS = mix(0.88, 0.10, water);
		SPECULAR = mix(0.22, 0.78, water);

		if (terrain_detail >= 3) {
			// Gentle drifting cloud shadow dapples across the sunlit meadow — smooth, no micro-grain.
			float wet_edge = coast * (1.0 - smoothstep(-14.4, -11.4, ground_position.y));
			float damp = wet_edge * (1.0 - water);
			soil *= 1.0 - 0.18 * damp;
			ROUGHNESS = mix(ROUGHNESS, 0.32, damp);
			SPECULAR = mix(SPECULAR, 0.55, damp);

			float turf = (1.0 - slope_rock) * (1.0 - max(wet_edge, water));
			float cloud = texture(weather_tex, p * 0.0026 - vec2(0.009, 0.005) * t).r;
			soil *= 1.0 - 0.12 * turf * smoothstep(0.45, 0.72, cloud);
		}
	}

	vec3 color = soil * (0.92 + soft_blend * 0.16);
	ALBEDO = OUTPUT_IS_SRGB ? pow(max(color, vec3(0.0)), vec3(1.0 / 2.2)) : color;
}
