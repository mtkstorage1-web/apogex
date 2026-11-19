shader_type sky;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 sky_top_color : source_color = vec4(0.10, 0.42, 0.84, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.62, 0.84, 0.97, 1.0);
uniform vec4 ground_bottom_color : source_color = vec4(0.14, 0.36, 0.24, 1.0);
uniform float atmosphere = 0.0;
uniform float cloud_detail = 1.0;
uniform float sky_time = 0.0;
uniform float ground_clouds = 1.0;
uniform vec3 sun_direction = vec3(-0.62, 0.42, 0.66);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.13, 0.31, 0.53)) * 19.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sun_dir = normalize(sun_direction);
	float height = max(d.y, 0.0);
	float sun_angle = max(dot(d, sun_dir), 0.0);

	// Hopeful cerulean zenith -> airy cyan-blue -> warm sunlit horizon glow.
	vec3 gradient = mix(sky_horizon_color.rgb, sky_top_color.rgb, pow(height, 0.38));
	float horizon_band = pow(1.0 - height, 3.6);
	vec3 warm_horizon = vec3(1.0, 0.93, 0.80);
	gradient = mix(gradient, warm_horizon, horizon_band * (0.22 + 0.36 * pow(sun_angle, 2.0)));
	if (d.y < 0.0) {
		gradient = mix(sky_horizon_color.rgb, ground_bottom_color.rgb, pow(-d.y, 0.45));
	}

	// Soft golden Mie sun halo + luminous atmospheric scatter.
	vec3 mie_wide = vec3(1.0, 0.90, 0.70) * pow(sun_angle, 6.0) * 0.22;
	vec3 mie_core = vec3(1.0, 0.94, 0.80) * pow(sun_angle, 48.0) * 0.45;
	vec3 scatter = (mie_wide + mie_core) * atmosphere;
	vec3 space = vec3(0.0006, 0.001, 0.0026);
	COLOR = space + gradient * atmosphere + scatter;

	if (!AT_CUBEMAP_PASS) {
		vec3 stars = d * 420.0;
		float random = hash(floor(stars));
		float point = (1.0 - smoothstep(0.10, 0.40, length(fract(stars) - 0.5)));
		COLOR += vec3(0.68, 0.79, 1.0) * point * smoothstep(0.992, 1.0, random)
			* (1.0 - atmosphere) * (1.0 - atmosphere) * 2.0;

		if (atmosphere * ground_clouds > 0.0) {
			// Soft, luminous, sunlit wispy clouds without harsh noise.
			vec2 weather = d.xz / max(0.18, height) * 0.14 + vec2(0.0012, 0.0004) * sky_time;
			float n = texture(noise_tex, weather).r;
			if (cloud_detail > 0.5) {
				n = n * 0.80 + texture(noise_tex, weather * 2.2 + vec2(0.17, 0.31)).r * 0.20;
			}
			if (cloud_detail > 1.5) {
				n += (texture(noise_tex, weather * 4.5).r - 0.5) * 0.06;
			}
			float clouds = smoothstep(0.52, 0.72, n) * smoothstep(0.12, 0.36, height);
			vec3 cloud_shadow = mix(vec3(0.68, 0.82, 0.94), vec3(0.92, 0.95, 0.98), pow(sun_angle, 2.0) * 0.5);
			vec3 cloud_lit = mix(vec3(0.98, 0.99, 1.0), vec3(1.0, 0.96, 0.88), pow(sun_angle, 3.0) * 0.65);
			vec3 cloud_color = mix(cloud_shadow, cloud_lit, smoothstep(0.54, 0.74, n));
			COLOR = mix(COLOR, cloud_color, clouds * atmosphere * ground_clouds * 0.68);
		}

		// Clean radiant sun disc.
		COLOR += vec3(1.0, 0.94, 0.78) * smoothstep(0.99945, 0.99985, sun_angle) * 3.6 * max(atmosphere, 0.55);
	}
}
