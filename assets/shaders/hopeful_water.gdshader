shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 sun_direction = vec3(-0.62, 0.42, 0.66);
uniform vec4 shallow_color : source_color = vec4(0.04, 0.24, 0.21, 1.0);
uniform vec4 deep_color : source_color = vec4(0.015, 0.10, 0.19, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.36, 0.58, 0.72, 1.0);
uniform vec4 sky_zenith_color : source_color = vec4(0.06, 0.26, 0.54, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.93, 0.74, 1.0);
uniform float wave_speed = 1.0;
uniform float water_clarity = 0.82;
uniform float pond_radius = 18.0;
uniform int water_quality = 2;

varying vec3 world_pos;

vec2 wave_slope(vec2 p, float t) {
	// Four smooth analytical directional wave octaves — silky ripples, zero grain.
	float w1 = sin(p.x * 0.72 + p.y * 0.45 + t * 1.15);
	float w2 = sin(p.x * -0.56 + p.y * 0.88 - t * 0.92);
	float w3 = sin(p.x * 1.45 - p.y * 1.02 + t * 1.55);
	float w4 = sin(p.x * 0.34 + p.y * -1.62 - t * 1.28);

	float c1 = cos(p.x * 0.72 + p.y * 0.45 + t * 1.15);
	float c2 = cos(p.x * -0.56 + p.y * 0.88 - t * 0.92);
	float c3 = cos(p.x * 1.45 - p.y * 1.02 + t * 1.55);
	float c4 = cos(p.x * 0.34 + p.y * -1.62 - t * 1.28);

	vec2 slope = vec2(0.0);
	slope += vec2(0.72, 0.45) * c1 * 0.068;
	slope += vec2(-0.56, 0.88) * c2 * 0.054;
	slope += vec2(1.45, -1.02) * c3 * 0.024;
	slope += vec2(0.34, -1.62) * c4 * 0.018;
	slope *= 0.88 + 0.12 * (w1 * w2 + w3 * w4 * 0.5);
	return slope;
}

float caustic_pattern(vec2 p, float t) {
	float a = sin(p.x * 1.65 + t * 0.85 + sin(p.y * 1.4 - t * 0.65));
	float b = sin(p.y * 1.85 - t * 0.72 + cos(p.x * 1.55 + t * 0.58));
	float ridge = 1.0 - abs(a + b) * 0.5;
	return pow(clamp(ridge, 0.0, 1.0), 4.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	// Organic shoreline outline so the pond feels natural instead of a rigid ellipse.
	float angle = atan(centered.y, centered.x);
	float shore_wobble = 0.055 * sin(angle * 3.0 + 0.7)
		+ 0.035 * cos(angle * 5.0 - 1.2)
		+ 0.02 * sin(angle * 7.0 + 2.1);
	float radial = length(centered) + shore_wobble;
	if (radial > 1.0) {
		discard;
	}

	float t = TIME * wave_speed;
	vec2 p = world_pos.xz;
	vec2 slope = vec2(0.0);
	if (water_quality >= 1) {
		slope = wave_slope(p, t) * (water_quality >= 3 ? 1.25 : (water_quality == 1 ? 0.55 : 1.0));
	}
	float edge_calm = 1.0 - smoothstep(0.76, 1.0, radial);
	slope *= mix(0.35, 1.0, edge_calm);

	vec3 world_n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 sun_dir = normalize(sun_direction);

	// Physical Schlick Fresnel for crisp sky reflection at grazing angles.
	float ndotv = clamp(dot(world_n, view_dir_world), 0.0, 1.0);
	float fresnel = clamp(0.05 + 0.95 * pow(1.0 - ndotv, 4.2), 0.0, 0.92);

	// Analytical reflection of the hopeful cerulean-to-warm-horizon sky.
	vec3 refl_dir = reflect(-view_dir_world, world_n);
	float refl_up = clamp(refl_dir.y, 0.0, 1.0);
	vec3 sky_refl = mix(sky_horizon_color.rgb, sky_zenith_color.rgb, pow(refl_up, 0.42));
	float refl_sun = max(dot(refl_dir, sun_dir), 0.0);
	sky_refl += sun_color.rgb * pow(refl_sun, 10.0) * 0.35;

	// Clear turquoise-emerald shallows deepening into rich cerulean-teal center.
	float depth_t = smoothstep(0.96, 0.25, radial);
	vec3 water_body = mix(shallow_color.rgb, deep_color.rgb, depth_t);

	// Subtle sunlit underwater caustics near the clear shallow edges (HIGH & ULTRA).
	if (water_quality >= 2) {
		float caustics = caustic_pattern(p * 0.55 + slope * 1.4, t);
		float shallow_mask = (1.0 - depth_t * 0.72) * water_clarity;
		float caustic_boost = water_quality >= 3 ? 0.72 : 0.42;
		water_body += vec3(0.20, 0.50, 0.42) * caustics * shallow_mask * caustic_boost;
	}

	// Combine refracted body and reflected sky, plus subtle dark bank reflection near edges.
	// Outer 35% mirrors deep emerald tree/bank silhouettes; a smooth analytic
	// canopy line (no noise) rises toward the shore and only fills low-angle rays.
	float bank_zone = smoothstep(0.65, 0.95, radial);
	float canopy_line = 0.16 + 0.05 * sin(angle * 9.0 + 0.4) + 0.03 * sin(angle * 17.0 - 1.3);
	float silhouette = (1.0 - smoothstep(canopy_line - 0.06, canopy_line + 0.06, refl_up)) * bank_zone;
	vec3 bank_tint = mix(vec3(0.015, 0.075, 0.04), vec3(0.05, 0.16, 0.07), smoothstep(0.0, canopy_line, refl_up));
	// Open center: crisp cerulean sky with golden sun sparkles riding the ripples.
	float sparkle = pow(refl_sun, 180.0) * (1.0 - bank_zone);
	vec3 center_refl = sky_refl + sun_color.rgb * vec3(1.0, 0.9, 0.62) * sparkle * 1.6;
	vec3 env_refl = mix(center_refl, bank_tint, clamp(silhouette * 0.85 + bank_zone * 0.2, 0.0, 0.9));
	vec3 color = mix(water_body, env_refl, fresnel * 0.78);

	// Bright, clean SEUS/BSL-style golden sun specular glint.
	vec3 half_vec = normalize(sun_dir + view_dir_world);
	float ndoth = max(dot(world_n, half_vec), 0.0);
	float sun_core = pow(ndoth, 320.0) * 2.8;
	float sun_sheen = pow(ndoth, 42.0) * 0.26;
	vec3 glint = sun_color.rgb * (sun_core + sun_sheen);

	// Soft luminous shoreline foam/shimmer.
	float foam = smoothstep(0.86, 0.97, radial) * (1.0 - smoothstep(0.97, 1.0, radial));
	color = mix(color, vec3(0.55, 0.78, 0.76), foam * 0.25);

	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	ALBEDO = color;
	ROUGHNESS = mix(0.12, 0.05, edge_calm);
	SPECULAR = 0.85;
	METALLIC = 0.06;
	EMISSION = glint * 0.55;
	ALPHA = smoothstep(1.0, 0.88, radial) * mix(0.82, 0.96, max(depth_t, fresnel));
}
