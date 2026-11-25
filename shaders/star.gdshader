shader_type spatial;
render_mode cull_back, specular_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform vec4 cool_color : source_color = vec4(0.65, 0.12, 0.03, 1.0);
uniform float turbulence_speed : hint_range(0.0, 2.0) = 0.12;
uniform float turbulence_scale : hint_range(0.5, 12.0) = 3.0;
uniform float limb_darkening : hint_range(0.0, 1.0) = 0.65;
uniform float flare_strength : hint_range(0.0, 4.0) = 1.4;
uniform float hdr_strength : hint_range(0.0, 16.0) = 3.0;
uniform float instability : hint_range(0.0, 2.0) = 0.8;

varying vec3 v_dir;

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
		p = p * 2.07 + vec3(11.3, 5.9, 2.1);
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	float t = TIME * turbulence_speed;
	vec3 d = normalize(v_dir);
	// Two counter-flowing domain-warped plasma layers.
	vec3 w = vec3(fbm(d * turbulence_scale + vec3(t, 0.0, 0.0)),
		fbm(d * turbulence_scale + vec3(0.0, t, 3.1)),
		fbm(d * turbulence_scale + vec3(2.7, 0.0, t)));
	float plasma = fbm(d * turbulence_scale * 1.5 + (w - 0.5) * 2.0 * instability + vec3(0.0, -t * 1.7, 0.0));
	float granules = fbm(d * turbulence_scale * 4.0 - (w - 0.5) * 1.5 + vec3(t * 2.0));

	// Bright flare filaments: thin ridges that flicker.
	float rid = 1.0 - abs(2.0 * fbm(d * turbulence_scale * 2.2 + (w - 0.5) * 3.0 + vec3(t * 0.8)) - 1.0);
	float flare = smoothstep(0.88, 0.985, rid) * (0.6 + 0.4 * sin(TIME * 2.3 + plasma * 12.0));

	vec3 col = mix(cool_color.rgb, core_color.rgb, smoothstep(0.25, 0.65, plasma));
	col = mix(col, hot_color.rgb, smoothstep(0.55, 0.85, plasma * 0.6 + granules * 0.5));
	col += hot_color.rgb * flare * flare_strength;

	float mu = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float limb = mix(1.0, pow(mu, 0.6), limb_darkening);
	col *= limb;
	col = mix(col, cool_color.rgb * 0.5, (1.0 - mu) * limb_darkening * 0.4);

	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = col * hdr_strength * (0.9 + 0.2 * granules);
}
