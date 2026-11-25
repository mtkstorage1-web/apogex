shader_type spatial;
uniform vec4 paint : source_color = vec4(0.8,0.81,0.78,1.0);
uniform sampler2D panel_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float panel_detail = 0.35;
uniform float panel_scale = 0.5;
uniform float metal = 0.5;
uniform float finish = 0.42;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.25;
uniform bool arena_surface = false;
uniform bool concrete = false;
uniform bool hazard = false;
uniform float status_emission = 0.0;
varying vec3 local_position;
varying vec3 local_normal;

float hash_cell(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float surface_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(point));
	return mix(
		mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0)), blend.x),
		blend.y
	);
}

vec4 panel_weathering(vec2 panel_uv, vec2 object_uv, float wear) {
	panel_uv += vec2(0.28, 0.37);
	vec2 tile = fract(panel_uv);
	vec2 edge = min(tile, 1.0 - tile);
	vec2 pixel = max(fwidth(panel_uv), vec2(0.0001));
	float seam_width = concrete ? 0.009 : 0.016;
	vec2 groove = 1.0 - smoothstep(vec2(seam_width), vec2(seam_width) + pixel + 0.01, edge);
	float joint = max(groove.x, groove.y) * (1.0 - smoothstep(0.07, 0.35, length(pixel)));
	float dirt = mix(0.40, 1.0, surface_noise(panel_uv * 29.0));
	float streak = surface_noise(object_uv * vec2(6.0, 0.8)) * surface_noise(object_uv * 1.3);
	float grime = joint * dirt + smoothstep(0.25, 0.72, streak) * 0.48;

	float erosion = surface_noise(panel_uv * 75.0) * 0.75
		+ surface_noise(panel_uv * 220.0) * 0.25;
	float chip_threshold = mix(0.84, 0.38, wear);
	float chips = smoothstep(chip_threshold, chip_threshold + 0.10, erosion);
	float seam_edge = min(edge.x, edge.y);
	float shoulder = smoothstep(seam_width, seam_width + 0.009, seam_edge)
		* (1.0 - smoothstep(seam_width + 0.014, seam_width + 0.032, seam_edge));

	vec2 scratch_uv = object_uv * (concrete ? vec2(94.0) : vec2(121.0, 8.0));
	float scratch_fade = 1.0 - smoothstep(0.2, 0.7, length(fwidth(scratch_uv)));
	float scratches = smoothstep(0.70, 0.94, surface_noise(scratch_uv)) * scratch_fade * 0.75;
	float exposed = concrete ? 0.0 : shoulder * chips * smoothstep(0.0, 0.25, wear);
	float height = -joint * 0.031 + scratches * 0.0022;
	if (arena_surface && !concrete) {
		float radius = length((edge - vec2(0.067)) * vec2(1.0, 0.68));
		float aa = length(pixel) * 0.55;
		float socket = (1.0 - smoothstep(0.024, 0.025 + aa, radius));
		float bolt = (1.0 - smoothstep(0.015, 0.016 + aa, radius));
		float slot = (1.0 - smoothstep(0.0025, 0.004 + aa, abs(edge.y - 0.067 + (edge.x - 0.067) * 0.48))) * bolt;
		float fade = 1.0 - smoothstep(0.009, 0.06, length(pixel));
		grime = max(grime, (socket - bolt + slot * 0.7) * fade);
		exposed = max(exposed, (bolt - slot * 0.85) * fade * 0.83);
		height += (bolt * 0.013 - socket * 0.008 - slot * 0.004) * fade;
	}
	return vec4(clamp(grime, 0.0, 1.0), exposed, scratches, height);
}

vec2 panel_slope(vec2 panel_uv) {
	// Godot normal textures can store just X and Y. Reconstruct Z before finding the slope.
	vec2 xy = texture(panel_normal, panel_uv).rg * 2.0 - 1.0;
	float z = sqrt(max(1.0 - dot(xy, xy), 0.04));
	return xy / z;
}

float hazard_stripe(vec2 point) {
	float phase = (point.x + point.y) * 1.25;
	float stripe = sin(phase * TAU);
	float aa = min(0.95, fwidth(phase) * PI);
	return mix(smoothstep(-0.025 - aa, 0.025 + aa, stripe), 0.5, smoothstep(0.25, 0.75, fwidth(phase)));
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 base_normal = normalize(local_normal);
	vec3 weights = pow(abs(base_normal), vec3(4.0));
	weights /= dot(weights, vec3(1.0));
	vec3 face = step(vec3(0.0), base_normal) * 2.0 - 1.0;
	vec2 object_x = local_position.yz * vec2(face.x, 1.0);
	vec2 object_y = local_position.zx * vec2(face.y, 1.0);
	vec2 object_z = local_position.xy * vec2(face.z, 1.0);
	vec2 panel_uv_x = object_x * panel_scale;
	vec2 panel_uv_y = object_y * panel_scale;
	vec2 panel_uv_z = object_z * panel_scale;

	float wear = clamp(wear_amount, 0.0, 1.0);
	float detail = clamp(panel_detail, 0.0, 1.0);
	vec4 weather = panel_weathering(panel_uv_x, object_x, wear) * weights.x
		+ panel_weathering(panel_uv_y, object_y, wear) * weights.y
		+ panel_weathering(panel_uv_z, object_z, wear) * weights.z;

	// Reorient each projection's tangent-plane slope into object space before blending.
	vec3 slope = vec3(0.0);
	if (!arena_surface) {
		vec2 slope_x = panel_slope(panel_uv_x);
		vec2 slope_y = panel_slope(panel_uv_y);
		vec2 slope_z = panel_slope(panel_uv_z);
		slope = vec3(0.0, slope_x.x * face.x, slope_x.y) * weights.x
			+ vec3(slope_y.y, 0.0, slope_y.x * face.y) * weights.y
			+ vec3(slope_z.x * face.z, slope_z.y, 0.0) * weights.z;
		slope -= base_normal * dot(base_normal, slope);
	}
	vec3 normal = normalize(mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX * (base_normal + slope * detail));
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 across_x = cross(dy, normal);
	vec3 across_y = cross(normal, dx);
	float det = dot(dx, across_x);
	vec3 bump = (across_x * dFdx(weather.w) + across_y * dFdy(weather.w)) * sign(det) / max(abs(det), 0.000001);
	NORMAL = normalize(normal - bump * detail / max(1.0, length(bump) * 1.4));

	float grime = weather.x * detail;
	float exposed = weather.y * detail;
	float scratches = weather.z * wear;
	vec3 coating = paint.rgb;
	if (hazard) {
		float stripe = dot(weights, vec3(hazard_stripe(object_x.yx), hazard_stripe(object_y), hazard_stripe(object_z)));
		coating = mix(coating * 0.075, coating, stripe);
	}
	float panel_tone = dot(weights, vec3(hash_cell(floor(panel_uv_x + vec2(0.28, 0.37))),
		hash_cell(floor(panel_uv_y + vec2(0.28, 0.37))), hash_cell(floor(panel_uv_z + vec2(0.28, 0.37)))));
	ALBEDO = mix(coating * mix(0.79, 1.14, panel_tone), vec3(0.48, 0.52, 0.56), exposed) * (1.0 - grime * 0.62);
	METALLIC = mix(metal, max(metal, 0.95), exposed);
	ROUGHNESS = clamp(mix(finish, min(finish * 0.75, 0.30), exposed)
		+ grime * 0.14 + scratches * 0.065, 0.10, 1.0);
	SPECULAR = 0.5 + scratches * 0.055;
	AO = 1.0 - grime * 0.36;
	EMISSION = paint.rgb * status_emission * (1.0 - grime * 0.72);
}
