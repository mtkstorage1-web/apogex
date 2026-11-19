shader_type spatial;
render_mode cull_disabled;

uniform bool flag = false;
uniform bool ultra_detail = false;
uniform float wind_strength = 1.0;
varying vec4 tint;
varying float gust_sheen;

void vertex() {
	vec2 world_xz = MODEL_MATRIX[3].xz;
	gust_sheen = 0.0;
	if (flag) {
		float phase = dot(world_xz, vec2(0.13, 0.19));
		VERTEX.z += sin(TIME * 4.1 - VERTEX.x * 3.0 + phase) * max(VERTEX.x, 0.0) * 0.22 * wind_strength;
	} else if (wind_strength > 0.0) {
		float tip = UV.y;
		vec2 wind = vec2(0.86, 0.51);
		float swell = sin(dot(world_xz, wind) * 0.14 - TIME * 2.1);
		float breeze = sin(dot(world_xz, vec2(-0.32, 0.24)) - TIME * 1.45) * 0.35;
		vec2 bend = wind * (0.08 + (swell + breeze) * 0.11);
		gust_sheen = smoothstep(0.05, 0.72, 0.55 * swell + 0.35 * breeze) * wind_strength;
		if (ultra_detail) {
			vec2 crosswind = vec2(-wind.y, wind.x);
			float gust = sin(dot(world_xz, vec2(0.20, -0.30)) - TIME * 3.2 + swell * 0.5);
			bend += wind * (0.07 + 0.12 * gust) + crosswind * (0.09 * gust);
			gust_sheen = smoothstep(0.05, 0.62, 0.42 * swell + 0.34 * gust) * wind_strength;
		}
		// Project the world wind onto the tuft's local ground plane.
		vec3 world_bend = vec3(bend.x, 0.0, bend.y);
		vec2 local_bend = vec2(dot(world_bend, normalize(MODEL_MATRIX[0].xyz)),
			dot(world_bend, normalize(MODEL_MATRIX[2].xyz)));
		float magnitude = length(local_bend);
		vec2 direction = local_bend / max(magnitude, 0.0001);
		// Integrate the bent centerline as a circular arc with the original blade length.
		float angle = max(2.0 * magnitude * tip * wind_strength, 0.0001);
		float half_sine = sin(angle * 0.5);
		float bend_sine = sin(angle);
		float bend_cosine = cos(angle);
		float height = VERTEX.y;
		VERTEX.xz += direction * (height * 2.0 * half_sine * half_sine / angle);
		VERTEX.y = height * bend_sine / angle;
		float along_wind = dot(NORMAL.xz, direction);
		NORMAL.xz += direction * (along_wind * (bend_cosine - 1.0) + NORMAL.y * bend_sine);
		NORMAL.y = NORMAL.y * bend_cosine - along_wind * bend_sine;
	}
	tint = COLOR;
}

void fragment() {
	if (flag) {
		ALBEDO = mix(vec3(0.04, 0.26, 0.56), vec3(0.95, 0.97, 0.99), step(0.68, UV.y));
		ROUGHNESS = 0.88;
	} else {
		float tip = UV.y;
		float exposed = smoothstep(0.15, 0.95, tip);
		// Deep shaded emerald root blending into lush meadow-green and warm sunlit tips.
		vec3 root_col = tint.rgb * vec3(0.24, 0.30, 0.26);
		vec3 mid_col = tint.rgb * vec3(0.68, 0.82, 0.58);
		vec3 tip_col = tint.rgb * vec3(0.95, 1.02, 0.56);
		vec3 blade = mix(root_col, mid_col, smoothstep(0.0, 0.58, tip));
		blade = mix(blade, tip_col, smoothstep(0.56, 1.0, tip));
		blade *= 1.0 + gust_sheen * exposed * 0.10;

		ALBEDO = blade;
		// Subtle warm sunlit subsurface translucency (BSL/SEUS feel without neon wash).
		float sss_boost = ultra_detail ? 0.36 : 0.24;
		BACKLIGHT = blade * exposed * vec3(0.72, 0.84, 0.30) * sss_boost;
		ROUGHNESS = mix(0.90, 0.62, exposed) - gust_sheen * exposed * 0.08;
		SPECULAR = mix(0.20, 0.42 + gust_sheen * 0.10, exposed);
	}
}
