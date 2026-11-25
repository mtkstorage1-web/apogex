shader_type spatial;
// Render on a sphere mesh of radius atmosphere_radius (backface shell).
render_mode unshaded, blend_add, cull_front, depth_draw_never, fog_disabled;

uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 12000.0;
uniform float atmosphere_radius = 12700.0;
uniform vec3 star_direction = vec3(0.7, 0.3, 0.4); // direction TOWARD the star
uniform vec3 rayleigh_coeff = vec3(0.00045, 0.0010, 0.0024);
uniform float mie_coeff = 0.0009;
uniform vec2 scale_heights = vec2(180.0, 70.0); // x rayleigh, y mie
uniform float mie_g : hint_range(0.0, 0.99) = 0.76;
uniform float sun_brightness = 22.0;
uniform vec3 atmospheric_tint : source_color = vec3(1.0, 0.88, 0.82);
uniform int scattering_quality : hint_range(2, 24) = 10;
uniform float terminator_softness : hint_range(0.01, 1.0) = 0.18;
uniform float rim_glow : hint_range(0.0, 4.0) = 0.6;
uniform vec3 rim_color : source_color = vec3(1.0, 0.45, 0.25);
uniform float exposure = 1.0;

varying vec3 v_wpos;

vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float h = b * b - c;
	if (h < 0.0) {
		return vec2(-1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 sun = normalize(star_direction);
	vec3 ro = CAMERA_POSITION_WORLD - planet_center;
	vec3 rd = normalize(v_wpos - CAMERA_POSITION_WORLD);

	vec2 ta = ray_sphere(ro, rd, atmosphere_radius);
	vec3 col = vec3(0.0);
	if (ta.y > 0.0) {
		float t0 = max(ta.x, 0.0);
		float t1 = ta.y;
		vec2 tp = ray_sphere(ro, rd, planet_radius);
		if (tp.y > 0.0 && tp.x > 0.0) {
			t1 = min(t1, tp.x);
		} else if (tp.y > 0.0 && tp.x <= 0.0) {
			t1 = t0; // camera below the surface
		}

		int steps = scattering_quality;
		float dt = (t1 - t0) / float(steps);
		float od_r = 0.0;
		float od_m = 0.0;
		vec3 sum_r = vec3(0.0);
		vec3 sum_m = vec3(0.0);

		for (int i = 0; i < 24; i++) {
			if (i >= steps) {
				break;
			}
			vec3 pos = ro + rd * (t0 + (float(i) + 0.5) * dt);
			float plen = length(pos);
			float h = max(plen - planet_radius, 0.0);
			float dr = exp(-h / scale_heights.x) * dt;
			float dm = exp(-h / scale_heights.y) * dt;
			od_r += dr;
			od_m += dm;

			vec3 up = pos / plen;
			float mu = dot(up, sun);
			vec2 tl = ray_sphere(pos, sun, atmosphere_radius);
			float ls = max(tl.y, 0.0);
			float eff_r = min(ls, scale_heights.x / max(abs(mu), 0.04));
			float eff_m = min(ls, scale_heights.y / max(abs(mu), 0.04));
			float lod_r = exp(-h / scale_heights.x) * eff_r;
			float lod_m = exp(-h / scale_heights.y) * eff_m;

			// Smooth day/night terminator (planet shadow).
			float perp = plen * sqrt(max(1.0 - mu * mu, 0.0));
			float lit = 1.0;
			if (mu < 0.0) {
				lit = smoothstep(planet_radius * 0.985, planet_radius * (1.0 + terminator_softness * 0.12), perp);
			}

			vec3 tau = rayleigh_coeff * (od_r + lod_r) + vec3(mie_coeff * 1.1) * (od_m + lod_m);
			vec3 atten = exp(-tau);
			sum_r += dr * atten * lit;
			sum_m += dm * atten * lit;
		}

		float cosv = dot(rd, sun);
		float pr = 3.0 / (16.0 * PI) * (1.0 + cosv * cosv);
		float g = mie_g;
		float pm = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + cosv * cosv))
			/ ((2.0 + g * g) * pow(max(1.0 + g * g - 2.0 * g * cosv, 0.0001), 1.5));
		col = sun_brightness * (sum_r * rayleigh_coeff * pr + sum_m * mie_coeff * pm) * atmospheric_tint;

		// Orbital rim glow around the limb, strongest on the sunlit side.
		float tc = max(dot(-ro, rd), 0.0);
		vec3 closest = ro + rd * tc;
		float alt = max(length(closest) - planet_radius, 0.0);
		float rim = exp(-alt / (scale_heights.x * 0.6));
		float side = smoothstep(-0.15, 0.35, dot(normalize(closest), sun));
		col += rim_color * rim * side * rim_glow * 0.15;

		col = vec3(1.0) - exp(-col * exposure);
	} else {
		discard;
	}
	ALBEDO = col;
	ALPHA = 1.0;
}
