shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec4 crust_color : source_color = vec4(0.03, 0.02, 0.02, 1.0);
uniform vec4 magma_deep : source_color = vec4(0.9, 0.12, 0.02, 1.0);
uniform vec4 magma_hot : source_color = vec4(1.0, 0.55, 0.08, 1.0);
uniform vec4 magma_core : source_color = vec4(1.0, 0.9, 0.45, 1.0);
uniform float flow_speed : hint_range(0.0, 3.0) = 0.35;
uniform float crack_scale : hint_range(0.02, 3.0) = 0.35;
uniform float emission_strength : hint_range(0.0, 12.0) = 4.0;
uniform float pulse_speed : hint_range(0.0, 6.0) = 1.3;
uniform vec2 flow_dir = vec2(0.0, 1.0);

varying vec3 v_local;

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
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 p = v_local.xz * crack_scale;
	vec2 drift = flow_dir * TIME * flow_speed;
	// Domain warp makes the crust plates slide and tear.
	float warp = fbm(vec3(p * 0.7 + drift * 0.5, TIME * 0.05));
	vec2 q = p + drift + vec2(warp, -warp) * 0.8;
	float n = fbm(vec3(q, TIME * 0.04));
	float ridge = 1.0 - abs(2.0 * n - 1.0);
	float magma = smoothstep(0.78, 0.95, ridge);
	float glow = smoothstep(0.55, 0.8, ridge);

	float pulse = 0.88 + 0.12 * sin(TIME * pulse_speed + warp * 8.0);
	vec3 col = mix(magma_deep.rgb, magma_hot.rgb, smoothstep(0.0, 0.6, magma));
	col = mix(col, magma_core.rgb, smoothstep(0.7, 1.0, magma));

	ALBEDO = crust_color.rgb * (1.0 - glow * 0.7);
	ROUGHNESS = mix(0.9, 0.25, magma);
	SPECULAR = 0.3;
	EMISSION = col * emission_strength * (magma + glow * 0.3) * pulse;
}
