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

// Rayleigh phase (blue everywhere, strongest forward/back) and Henyey-Greenstein Mie phase.
float rayleigh_phase(float c) {
	return 0.75 * (1.0 + c * c);
}
float mie_phase(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * c, 1e-3), 1.5) * 0.0796;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sun_dir = normalize(sun_direction);
	float height = max(d.y, 0.0);
	float cosv = dot(d, sun_dir);
	float sun_angle = max(cosv, 0.0);
	float sun_elev = clamp(sun_dir.y, 0.0, 1.0);

	// Optical path grows toward the horizon -> reddening of the long sunlit path.
	float path = 1.0 / (height + 0.12);
	vec3 beta_r = vec3(0.20, 0.42, 1.0);               // relative Rayleigh coefficients
	vec3 extinction = exp(-beta_r * path * (0.040 + 0.10 * (1.0 - sun_elev)));

	vec3 zenith = sky_top_color.rgb;
	vec3 horizon = sky_horizon_color.rgb;
	vec3 gradient = mix(horizon, zenith, pow(height, 0.42));
	// Rayleigh in-scatter: deep blue overhead, sun-tinted toward the horizon.
	vec3 rayleigh = beta_r * rayleigh_phase(cosv) * 0.12 * mix(vec3(1.0), vec3(1.0, 0.86, 0.68), 1.0 - height);
	gradient += rayleigh * 0.55;
	// Golden-hour horizon haze, brightest toward the sun azimuth.
	float horizon_band = pow(1.0 - height, 4.0);
	vec3 haze = mix(vec3(0.74, 0.86, 0.98), vec3(1.0, 0.78, 0.50), pow(sun_angle, 3.0));
	gradient = mix(gradient, haze, horizon_band * (0.30 + 0.45 * pow(sun_angle, 2.0)));
	if (d.y < 0.0) {
		gradient = mix(sky_horizon_color.rgb, ground_bottom_color.rgb, pow(-d.y, 0.45));
	}

	// Mie forward scattering: wide golden aureole + tight core.
	float mie = mie_phase(cosv, 0.76);
	vec3 aureole = vec3(1.0, 0.80, 0.52) * mie * 0.55
		+ vec3(1.0, 0.90, 0.70) * pow(sun_angle, 40.0) * 0.55;
	vec3 scatter = aureole * mix(1.0, extinction.b + 0.25, 0.5) * atmosphere;
	vec3 space = vec3(0.0004, 0.0007, 0.0020);
	COLOR = space + gradient * atmosphere + scatter;

	if (!AT_CUBEMAP_PASS) {
		// Deep starfield with varied magnitude + color temperature; fades with atmosphere.
		float night = (1.0 - atmosphere) * (1.0 - atmosphere);
		vec3 stars = d * 380.0;
		vec3 cell = floor(stars);
		float r1 = hash(cell);
		float r2 = hash(cell + vec3(7.1, 3.3, 5.9));
		float point = 1.0 - smoothstep(0.05, 0.38, length(fract(stars) - 0.5));
		float mag = pow(smoothstep(0.985, 1.0, r1), 2.0);        // few bright, many faint
		vec3 star_col = mix(vec3(1.0, 0.72, 0.52), vec3(0.62, 0.76, 1.0), r2);
		star_col = mix(star_col, vec3(1.0), 0.35);
		COLOR += star_col * point * mag * night * 3.2;
		// Dense faint dust of tiny stars.
		vec3 fine = d * 900.0;
		float fr = hash(floor(fine) + 11.0);
		float fp = 1.0 - smoothstep(0.08, 0.34, length(fract(fine) - 0.5));
		COLOR += vec3(0.8, 0.88, 1.0) * fp * smoothstep(0.975, 1.0, fr) * night * 0.55;

		// Milky Way: tilted galactic band with dark dust lanes.
		vec3 axis = normalize(vec3(0.34, 0.82, -0.46));
		float band = 1.0 - abs(dot(d, axis));
		float core = smoothstep(0.80, 1.0, band);
		float wide = smoothstep(0.55, 1.0, band);
		vec2 nuv = vec2(atan(d.z, d.x) * 0.5, d.y * 1.6) + vec2(0.31, 0.17);
		float nebula = texture(noise_tex, nuv * 1.3).r;
		float dust = texture(noise_tex, nuv * 3.1 + 0.4).r;
		float milky = (wide * 0.35 + core * 0.9) * (0.45 + nebula * 0.9);
		milky *= 1.0 - smoothstep(0.50, 0.72, dust) * 0.55 * core;
		vec3 mw_col = mix(vec3(0.20, 0.26, 0.48), vec3(0.95, 0.78, 0.62), core * nebula);
		COLOR += mw_col * milky * 0.16 * night;

		if (atmosphere * ground_clouds > 0.0) {
			// Drifting high-altitude sunlit cirrus + cumulus wisps.
			vec2 weather = d.xz / max(0.18, height) * 0.14 + vec2(0.0012, 0.0004) * sky_time;
			float n = texture(noise_tex, weather).r;
			if (cloud_detail > 0.5) {
				n = n * 0.78 + texture(noise_tex, weather * 2.2 + vec2(0.17, 0.31)).r * 0.22;
			}
			if (cloud_detail > 1.5) {
				n += (texture(noise_tex, weather * 4.5).r - 0.5) * 0.08;
			}
			float clouds = smoothstep(0.50, 0.72, n) * smoothstep(0.08, 0.30, height);
			// Silver-lined edge: thin cloud toward the sun glows gold.
			float thin = 1.0 - smoothstep(0.50, 0.68, n);
			vec3 cloud_shadow = mix(vec3(0.52, 0.62, 0.78), vec3(0.86, 0.88, 0.94), pow(sun_angle, 2.0) * 0.5);
			vec3 cloud_lit = mix(vec3(1.0, 0.99, 0.97), vec3(1.0, 0.86, 0.62), pow(sun_angle, 2.5) * 0.8);
			vec3 cloud_color = mix(cloud_shadow, cloud_lit, smoothstep(0.52, 0.78, n));
			cloud_color += vec3(1.0, 0.84, 0.58) * thin * pow(sun_angle, 6.0) * 0.8;
			// Distant clouds sink into the horizon haze.
			cloud_color = mix(cloud_color, haze, horizon_band * 0.55);
			COLOR = mix(COLOR, cloud_color, clouds * atmosphere * ground_clouds * 0.78);
		}

		// Crisp radiant sun disc with HDR core (feeds bloom).
		float disc = smoothstep(0.99955, 0.99985, sun_angle);
		COLOR += vec3(1.0, 0.93, 0.76) * disc * 6.5 * max(atmosphere, 0.55);
	}
}
