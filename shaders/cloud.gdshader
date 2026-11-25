shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

uniform vec3 star_direction = vec3(0.6, 0.5, 0.3);
uniform float wind_speed : hint_range(0.0, 0.2) = 0.01;
uniform float cloud_scale : hint_range(0.5, 12.0) = 3.0;
uniform float coverage : hint_range(0.0, 1.0) = 0.5;
uniform float softness : hint_range(0.01, 0.5) = 0.18;
uniform float density : hint_range(0.0, 1.0) = 0.9;
uniform float band_frequency = 9.0;
uniform float band_strength : hint_range(0.0, 2.0) = 0.8;
uniform float wisp_amount : hint_range(0.0, 1.0) = 0.45;
uniform float high_amount : hint_range(0.0, 1.5) = 1.0;
uniform float storm_amount : hint_range(0.0, 1.5) = 1.0;
uniform float plume_amount : hint_range(0.0, 1.5) = 1.0;
uniform float plume_radius : hint_range(0.02, 0.5) = 0.16;
uniform vec3 plume_dir_a = vec3(0.0, 0.0, 1.0);
uniform vec3 plume_dir_b = vec3(0.0, 0.0, 1.0);
uniform vec3 ash_tint : source_color = vec3(0.16, 0.12, 0.11);
uniform vec3 day_tint : source_color = vec3(0.92, 0.84, 0.78);
uniform vec3 night_tint : source_color = vec3(0.03, 0.035, 0.05);
uniform vec3 twilight_color : source_color = vec3(1.0, 0.45, 0.22);

varying vec3 v_dir;
varying vec3 v_wn;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float fbm(vec3 p) {
	float amp = 0.5;
	float sum = 0.0;
	for (int i = 0; i < 5; i++) {
		sum += amp * vnoise(p);
		p = p * 2.02 + vec3(7.3, 1.9, 4.1);
		amp *= 0.5;
	}
	return sum;
}

vec3 rot_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

void vertex() {
	v_dir = normalize(VERTEX);
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 d = normalize(v_dir);
	// Wind drift: mid layer and high layer rotate at different speeds.
	vec3 dm = rot_y(d, TIME * wind_speed);
	vec3 dh = rot_y(d, TIME * wind_speed * 1.7);

	float warp = fbm(dm * cloud_scale * 0.6);
	float base = fbm(dm * cloud_scale + vec3(warp * 1.2));
	// Storm bands: latitude-dependent modulation.
	float bands = 0.5 + 0.5 * sin(d.y * band_frequency + fbm(dm * 2.0) * 3.0);
	float cov = base + (bands - 0.5) * band_strength * 0.35;
	float mid = smoothstep(coverage - softness, coverage + softness, cov);

	// Wispy high clouds: stretched along latitude lines.
	vec3 wp = vec3(dh.x * 6.0, dh.y * 28.0, dh.z * 6.0);
	float wisp = smoothstep(0.55, 0.85, fbm(wp + vec3(warp * 2.0))) * wisp_amount * high_amount;

	// Formation 2: broad mid-altitude storm bands.
	float storm = mid * density * storm_amount;

	// Formation 3: localized volcanic ash plumes over Obsidian Fields and Terminus Basin.
	float pa = acos(clamp(dot(d, normalize(plume_dir_a)), -1.0, 1.0));
	float pb = acos(clamp(dot(d, normalize(plume_dir_b)), -1.0, 1.0));
	float pf = max(1.0 - smoothstep(0.0, plume_radius, pa), 1.0 - smoothstep(0.0, plume_radius * 0.7, pb));
	float billow = fbm(rot_y(d, TIME * wind_speed * 0.6) * 22.0 + vec3(warp));
	float plume = pf * smoothstep(0.25, 0.65, billow + pf * 0.35) * plume_amount;

	float a = clamp(max(max(storm, wisp), plume), 0.0, 1.0);

	// Day/night attenuation with warm twilight band.
	float ndl = dot(normalize(v_wn), normalize(star_direction));
	float day = smoothstep(-0.12, 0.25, ndl);
	float tw = exp(-pow(ndl * 5.0, 2.0));
	vec3 col = mix(night_tint, day_tint, day) + twilight_color * tw * 0.35 * mid;

	col = mix(col, ash_tint * mix(0.25, 1.0, day), clamp(plume / max(a, 0.001), 0.0, 1.0) * 0.85);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	ALPHA = a * mix(0.55, 1.0, day);
}
