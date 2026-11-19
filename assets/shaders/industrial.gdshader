shader_type spatial;
uniform vec4 paint : source_color = vec4(0.8,0.81,0.78,1.0);
uniform sampler2D panel_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float panel_detail = 0.35;
uniform float panel_scale = 0.5;
uniform float metal = 0.5;
uniform float finish = 0.42;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.25;
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

// Each result carries seam grime, exposed metal, and brushed scratches.
vec3 panel_weathering(vec2 panel_uv, vec2 object_uv, float wear) {
	vec2 edge = abs(fract(panel_uv + 0.5) - 0.5);
	vec2 pixel = max(fwidth(panel_uv), vec2(0.0001));
	vec2 groove = 1.0 - smoothstep(vec2(0.004), vec2(0.023) + pixel, edge);
	float dirt = mix(0.40, 1.0, surface_noise(panel_uv * 29.0));
	float grime = max(groove.x, groove.y) * dirt;

	float erosion = surface_noise(panel_uv * 75.0) * 0.75
		+ surface_noise(panel_uv * 220.0) * 0.25;
	float chip_threshold = mix(0.84, 0.38, wear);
	float chips = smoothstep(chip_threshold, chip_threshold + 0.10, erosion);
	float seam_edge = min(edge.x, edge.y);
	float shoulder = smoothstep(0.003, 0.009, seam_edge)
		* (1.0 - smoothstep(0.014, 0.034, seam_edge));

	vec2 scratch_uv = object_uv * vec2(23.0, 520.0);
	float scratch_fade = 1.0 - smoothstep(0.2, 0.7, length(fwidth(scratch_uv)));
	float scratches = smoothstep(0.70, 0.94, surface_noise(scratch_uv)) * scratch_fade * 0.75;
	return vec3(grime, shoulder * chips * smoothstep(0.0, 0.25, wear), scratches);
}

vec2 panel_slope(vec2 panel_uv) {
	// Godot normal textures can store just X and Y. Reconstruct Z before finding the slope.
	vec2 xy = texture(panel_normal, panel_uv).rg * 2.0 - 1.0;
	float z = sqrt(max(1.0 - dot(xy, xy), 0.04));
	return xy / z;
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
	vec3 weather = panel_weathering(panel_uv_x, object_x, wear) * weights.x
		+ panel_weathering(panel_uv_y, object_y, wear) * weights.y
		+ panel_weathering(panel_uv_z, object_z, wear) * weights.z;

	// Reorient each projection's tangent-plane slope into object space before blending.
	vec2 slope_x = panel_slope(panel_uv_x);
	vec2 slope_y = panel_slope(panel_uv_y);
	vec2 slope_z = panel_slope(panel_uv_z);
	vec3 slope = vec3(0.0, slope_x.x * face.x, slope_x.y) * weights.x
		+ vec3(slope_y.y, 0.0, slope_y.x * face.y) * weights.y
		+ vec3(slope_z.x * face.z, slope_z.y, 0.0) * weights.z;
	slope -= base_normal * dot(base_normal, slope);
	NORMAL = normalize(mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX * (base_normal + slope * detail));

	float grime = weather.x * detail;
	float exposed = weather.y * detail;
	float scratches = weather.z * wear;
	ALBEDO = mix(paint.rgb, vec3(0.56, 0.60, 0.65), exposed) * (1.0 - grime * 0.46);
	METALLIC = mix(metal, max(metal, 0.95), exposed);
	ROUGHNESS = clamp(mix(finish, min(finish * 0.75, 0.30), exposed)
		+ grime * 0.14 + scratches * 0.065, 0.10, 1.0);
	SPECULAR = 0.5 + scratches * 0.055;
}
