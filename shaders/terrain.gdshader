shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// APOGEX VESPER-9 terrain: slope-aware, world-space triplanar procedural PBR.
// Vertex COLOR = color_weights (r rust/crimson, g volcanic heat, b mineral/obsidian, a crater ejecta)
// UV  = (industrial, moisture_erosion)
// UV2 = (biome_id / 5, canyon_strata)

uniform vec3 star_direction = vec3(0.6, 0.5, 0.3);
uniform vec3 planet_center = vec3(0.0);
uniform bool lod_debug_enabled = false;
uniform float detail_scale : hint_range(0.01, 2.0) = 0.12;
uniform float bump_strength : hint_range(0.0, 3.0) = 0.7;
uniform float quality : hint_range(0.0, 1.0) = 0.75;
uniform float lava_threshold : hint_range(0.0, 1.0) = 0.65;
uniform float lava_emission : hint_range(0.0, 12.0) = 3.0;
instance uniform float patch_lod_norm : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_wpos;
varying vec3 v_wnormal;

const vec3 LOD_COLORS[6] = vec3[](
	vec3(0.95, 0.12, 0.10),
	vec3(0.98, 0.55, 0.10),
	vec3(0.95, 0.90, 0.15),
	vec3(0.20, 0.85, 0.25),
	vec3(0.15, 0.80, 0.95),
	vec3(0.45, 0.30, 0.95)
);

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

float fbm(vec3 p, int oct) {
	float amp = 0.5;
	float sum = 0.0;
	for (int i = 0; i < oct; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}

// Triplanar multi-octave noise: three planar projections blended by normal weights.
float tri_fbm(vec3 p, vec3 w, int oct) {
	float x = fbm(vec3(p.y, p.z, 3.1), oct);
	float y = fbm(vec3(p.x, p.z, 7.7), oct);
	float z = fbm(vec3(p.x, p.y, 11.3), oct);
	return x * w.x + y * w.y + z * w.z;
}

float bump_field(vec3 p) {
	return fbm(p * 0.8, 3) * 0.7 + fbm(p * 4.0, 2) * 0.3;
}

float bw(float biome, float k) {
	return clamp(1.0 - abs(biome - k), 0.0, 1.0);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (lod_debug_enabled) {
		int idx = int(clamp(floor(patch_lod_norm * 5.0 + 0.5), 0.0, 5.0));
		vec3 c = LOD_COLORS[idx];
		ALBEDO = c;
		EMISSION = c * 0.35;
		ROUGHNESS = 0.9;
		METALLIC = 0.0;
	} else {
		vec3 n_w = normalize(v_wnormal);
		vec3 radial = v_wpos - planet_center;
		vec3 up = normalize(radial);
		float slope = clamp(1.0 - dot(n_w, up), 0.0, 1.0);
		float steep = smoothstep(0.08, 0.35, slope);

		vec3 tw = pow(abs(n_w), vec3(4.0));
		tw /= (tw.x + tw.y + tw.z + 0.0001);

		int oct = 2 + int(round(quality * 2.0));
		vec3 p = v_wpos * detail_scale;
		float g_lo = tri_fbm(p * 0.05, tw, 2);
		float g_mid = tri_fbm(p, tw, oct);
		float g_hi = vnoise(v_wpos * 1.7);

		float rust_w = COLOR.r;
		float heat = COLOR.g;
		float mineral = COLOR.b;
		float ejecta = COLOR.a;
		float industrial = UV.x;
		float erosion = UV.y;
		float biome = UV2.x * 5.0;
		float strata = UV2.y;

		// Raw material weights (10 categories).
		float w_basalt = 0.25 + bw(biome, 2.0) * 0.5 + bw(biome, 5.0) * 0.3 + steep * 0.2;
		float w_rust = rust_w * 1.4 + bw(biome, 1.0) * 0.9;
		float w_crust = heat * 0.9 * smoothstep(0.35, 0.7, g_mid);
		float w_metal = mineral * 0.8 * (1.0 - bw(biome, 2.0)) + bw(biome, 3.0) * 0.7;
		float w_pale = erosion * 0.8 + bw(biome, 4.0) * 0.7 + steep * strata * 0.5;
		float w_obs = (bw(biome, 2.0) * 0.8 * smoothstep(0.45, 0.7, g_lo)) + mineral * bw(biome, 2.0) * 0.6;
		float w_ejecta = ejecta * 1.5;
		float w_ind = industrial * 1.5 + bw(biome, 5.0) * 0.3;
		float w_crack = heat * 0.8 * smoothstep(0.3, 0.6, 1.0 - g_mid);
		float w_ash = bw(biome, 0.0) * 1.0 + 0.15;

		float wsum = w_basalt + w_rust + w_crust + w_metal + w_pale + w_obs + w_ejecta + w_ind + w_crack + w_ash;
		float inv = 1.0 / max(wsum, 0.0001);

		// Canyon strata banding, driven by radial height.
		float radial_h = length(radial);
		float band = smoothstep(0.35, 0.65, fract(radial_h * 0.35 + g_lo * 2.0));
		float band_mod = 1.0 + (band - 0.5) * 0.6 * strata;

		vec3 c_basalt = vec3(0.075, 0.07, 0.075);
		vec3 c_rust = vec3(0.46, 0.17, 0.08) * band_mod;
		vec3 c_crust = vec3(0.035, 0.028, 0.028);
		vec3 c_metal = vec3(0.34, 0.29, 0.27);
		vec3 c_pale = vec3(0.60, 0.52, 0.45) * band_mod;
		vec3 c_obs = vec3(0.012, 0.012, 0.018);
		vec3 c_ejecta = vec3(0.72, 0.68, 0.60);
		vec3 c_ind = vec3(0.17, 0.18, 0.165);
		vec3 c_crack = vec3(0.20, 0.09, 0.05);
		vec3 c_ash = vec3(0.30, 0.29, 0.30);

		vec3 albedo = c_basalt * w_basalt + c_rust * w_rust + c_crust * w_crust + c_metal * w_metal
			+ c_pale * w_pale + c_obs * w_obs + c_ejecta * w_ejecta + c_ind * w_ind
			+ c_crack * w_crack + c_ash * w_ash;
		albedo *= inv;

		float rough = (0.92 * w_basalt + 0.95 * w_rust + 0.8 * w_crust + 0.45 * w_metal + 0.9 * w_pale
			+ 0.15 * w_obs + 0.95 * w_ejecta + 0.55 * w_ind + 0.85 * w_crack + 0.98 * w_ash) * inv;
		float metal = (0.6 * w_metal + 0.4 * w_ind + 0.1 * w_obs) * inv;

		// Multi-frequency tint breakup, no tiling.
		float tint = 0.75 + 0.5 * g_mid;
		tint *= 0.92 + 0.16 * g_hi;
		albedo *= tint;

		// Volcanic lava veins.
		vec3 emis = vec3(0.0);
		float mask = smoothstep(lava_threshold, lava_threshold + 0.15, heat);
		if (mask > 0.001) {
			float rid = 1.0 - abs(2.0 * fbm(v_wpos * 0.045 + vec3(g_lo * 2.0), 3) - 1.0);
			float veins = smoothstep(0.82, 0.96, rid);
			float pulse = 0.85 + 0.15 * sin(TIME * 1.7 + g_lo * 20.0);
			vec3 hot = mix(vec3(1.0, 0.18, 0.03), vec3(1.0, 0.7, 0.2), veins);
			emis = hot * veins * mask * lava_emission * pulse;
			albedo = mix(albedo, c_crust, veins * mask);
			rough = mix(rough, 0.35, veins * mask);
		}

		// Procedural bump from finite differences, faded with distance.
		float fade = 1.0 - smoothstep(60.0, 450.0, length(VERTEX));
		if (fade > 0.01 && bump_strength > 0.0) {
			float e = 0.15;
			float h0 = bump_field(v_wpos);
			vec3 g = vec3(
				bump_field(v_wpos + vec3(e, 0.0, 0.0)) - h0,
				bump_field(v_wpos + vec3(0.0, e, 0.0)) - h0,
				bump_field(v_wpos + vec3(0.0, 0.0, e)) - h0) / e;
			vec3 gv = (VIEW_MATRIX * vec4(g, 0.0)).xyz;
			vec3 tang = gv - dot(gv, NORMAL) * NORMAL;
			NORMAL = normalize(NORMAL - bump_strength * fade * tang);
		}

		// Lava glows stronger on the night side.
		float night = 1.0 - smoothstep(-0.1, 0.2, dot(up, normalize(star_direction)));
		emis *= 1.0 + night * 0.8;

		ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
		ROUGHNESS = clamp(rough, 0.05, 1.0);
		METALLIC = clamp(metal, 0.0, 1.0);
		SPECULAR = 0.4;
		EMISSION = emis;
	}
}
