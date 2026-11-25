## Graphics building blocks shared by every scene.
class_name Gfx
extends RefCounted

const TRIPLANAR_SHADER := """
shader_type spatial;

uniform sampler2D pbr_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D pbr_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D pbr_roughness : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D pbr_ao : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

float hash_cell(vec3 cell) {
	cell = fract(cell * 0.1031);
	cell += dot(cell, cell.yzx + 33.33);
	return fract((cell.x + cell.y) * cell.z);
}

float value_noise(vec3 position) {
	vec3 cell = floor(position);
	vec3 blend = fract(position);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float x00 = mix(hash_cell(cell), hash_cell(cell + vec3(1, 0, 0)), blend.x);
	float x10 = mix(hash_cell(cell + vec3(0, 1, 0)), hash_cell(cell + vec3(1, 1, 0)), blend.x);
	float x01 = mix(hash_cell(cell + vec3(0, 0, 1)), hash_cell(cell + vec3(1, 0, 1)), blend.x);
	float x11 = mix(hash_cell(cell + vec3(0, 1, 1)), hash_cell(cell + vec3(1, 1, 1)), blend.x);
	return mix(mix(x00, x10, blend.y), mix(x01, x11, blend.y), blend.z);
}

float fractal_noise(vec3 position) {
	return 0.55 * value_noise(position)
		+ 0.27 * value_noise(position * 2.03 + vec3(17.0))
		+ 0.12 * value_noise(position * 4.17 + vec3(31.0))
		+ 0.06 * value_noise(position * 8.31 + vec3(47.0));
}

vec3 triplanar_weights(vec3 normal) {
	vec3 weights = pow(abs(normal), vec3(4.0));
	return weights / dot(weights, vec3(1.0));
}

vec3 triplanar_color(sampler2D map, vec3 uvw, vec3 weights) {
	return texture(map, uvw.zy).rgb * weights.x
		+ texture(map, uvw.xz).rgb * weights.y
		+ texture(map, uvw.xy).rgb * weights.z;
}

vec2 normal_slope(vec2 encoded) {
	vec2 xy = encoded * 2.0 - 1.0;
	return xy / sqrt(max(1.0 - dot(xy, xy), 0.0625));
}

vec3 triplanar_slope(vec3 uvw, vec3 weights) {
	vec2 x = normal_slope(texture(pbr_normal, uvw.zy).rg);
	vec2 y = normal_slope(texture(pbr_normal, uvw.xz).rg);
	vec2 z = normal_slope(texture(pbr_normal, uvw.xy).rg);
	// Convert each projection's normal perturbation to its world-space UV axes.
	return vec3(0.0, -x.y, x.x) * weights.x
		+ vec3(y.x, 0.0, -y.y) * weights.y
		+ vec3(z.x, -z.y, 0.0) * weights.z;
}

mat3 surface_basis(vec3 normal) {
	vec3 axis = abs(normal.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
	vec3 tangent = normalize(cross(axis, normal));
	return mat3(tangent, cross(normal, tangent), normal);
}

vec3 encode_normal_map(vec3 normal, vec3 slope, mat3 basis) {
	slope -= normal * dot(slope, normal);
	vec3 bumped = normalize(normal + slope);
	return (transpose(basis) * bumped) * 0.5 + 0.5;
}
"""

const TERRAIN_FRAGMENT := """
void fragment() {
	vec3 normal = normalize(world_normal);
	vec3 weights = triplanar_weights(normal);
	vec3 coarse = world_position * 0.055;
	vec3 fine = world_position * 0.13 + vec3(13.7, 5.2, 8.6);
	float patches = fractal_noise(world_position * 0.045);
	float detail = mix(0.25, 0.75, smoothstep(0.25, 0.75, patches));
	float rock = smoothstep(0.32, 0.72, 1.0 - max(normal.y, 0.0));
	// Smooth, lush emerald meadow greens with gentle macro variation — zero grain.
	vec3 tex_col = mix(triplanar_color(pbr_albedo, coarse, weights),
		triplanar_color(pbr_albedo, fine, weights), detail);
	float tex_luma = clamp(dot(tex_col, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	vec3 meadow_deep = vec3(0.11, 0.32, 0.075);
	vec3 meadow_bright = vec3(0.22, 0.48, 0.12);
	vec3 meadow = mix(meadow_deep, meadow_bright, smoothstep(0.22, 0.78, patches * 0.75 + tex_luma * 0.25));
	vec3 stone = vec3(0.30, 0.36, 0.41) * (0.88 + tex_luma * 0.24);
	ALBEDO = mix(meadow, stone, rock);
	ROUGHNESS = mix(0.88, 0.84, rock);
	AO = mix(0.85, 1.0, triplanar_color(pbr_ao, coarse, weights).r);

	vec3 slope = mix(triplanar_slope(coarse, weights), triplanar_slope(fine, weights), detail) * 0.20;
	mat3 basis = surface_basis(normal);
	mat3 view_basis = mat3(VIEW_MATRIX) * basis;
	TANGENT = view_basis[0];
	BINORMAL = view_basis[1];
	NORMAL = view_basis[2];
	NORMAL_MAP = encode_normal_map(normal, slope, basis);
}
"""

const CLIFF_FRAGMENT := """
uniform sampler2D moss_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;

void fragment() {
	vec3 normal = normalize(world_normal);
	vec3 weights = triplanar_weights(normal);
	vec3 rock_uv = world_position * 0.085;
	float weathering = fractal_noise(world_position * 0.09);
	float moss_cover = smoothstep(0.34, 0.74, normal.y) * smoothstep(0.22, 0.62, weathering);
	vec3 raw_rock = triplanar_color(pbr_albedo, rock_uv, weights);
	float rock_luma = clamp(dot(raw_rock, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	// Crisp sunlit blue-slate mountain stone with lush emerald moss caps.
	vec3 rock = mix(vec3(0.12, 0.16, 0.20), vec3(0.22, 0.27, 0.32), smoothstep(0.20, 0.82, rock_luma * 0.55 + weathering * 0.45));
	vec3 moss = mix(vec3(0.036, 0.115, 0.026), vec3(0.075, 0.18, 0.038), weathering);
	ALBEDO = mix(rock, moss, moss_cover);
	ROUGHNESS = mix(0.84, 0.90, moss_cover);
	AO = mix(0.82, 1.0, triplanar_color(pbr_ao, rock_uv, weights).r);

	vec3 slope = triplanar_slope(rock_uv, weights) * mix(0.26, 0.10, moss_cover);
	mat3 basis = surface_basis(normal);
	mat3 view_basis = mat3(VIEW_MATRIX) * basis;
	TANGENT = view_basis[0];
	BINORMAL = view_basis[1];
	NORMAL = view_basis[2];
	NORMAL_MAP = encode_normal_map(normal, slope, basis);
}
"""

static var _mats := {}


static func mat(color: Color, rough := 0.85, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), rough, emission, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func terrain_mat(color: Color, rock_detail := false) -> StandardMaterial3D:
	var key := "terrain|%s|%s" % [color.to_html(), rock_detail]
	if _mats.has(key): return _mats[key]
	var template: StandardMaterial3D = load("res://assets/materials/rock.tres" if rock_detail else "res://assets/materials/ground.tres")
	var m := template.duplicate() as StandardMaterial3D
	m.albedo_color = color
	m.albedo_texture = ProcTex.rock_albedo(color) if rock_detail else ProcTex.ground_albedo(color)
	m.normal_texture = ProcTex.rock_normal() if rock_detail else ProcTex.ground_normal()
	if rock_detail: m.uv1_scale = Vector3.ONE * 0.3
	_mats[key] = m
	return m


static func _pbr_texture(folder: String, map: String) -> Texture2D:
	return load("res://assets/pbr/%s/%s.jpg" % [folder, map]) as Texture2D


static func create_pbr_mat(folder: String, uv_scale := 0.25, tint := Color.WHITE, metallic := 0.0) -> StandardMaterial3D:
	var key := ["pbr", folder, uv_scale, tint, metallic]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _pbr_texture(folder, "albedo")
	m.normal_texture = _pbr_texture(folder, "normal")
	m.roughness_texture = _pbr_texture(folder, "roughness")
	m.ao_texture = _pbr_texture(folder, "ao")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	m.normal_enabled = true
	m.ao_enabled = true
	m.metallic = metallic
	m.albedo_color = tint
	_mats[key] = m
	return m


static func create_terrain_shader_mat() -> ShaderMaterial:
	return _create_triplanar_material(TERRAIN_FRAGMENT, "ground")


static func create_cliff_shader_mat() -> ShaderMaterial:
	var m := _create_triplanar_material(CLIFF_FRAGMENT, "cliff")
	m.set_shader_parameter("moss_albedo", _pbr_texture("ground", "albedo"))
	return m


static func create_hopeful_water_mat() -> ShaderMaterial:
	var key := "hopeful_water"
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/hopeful_water.gdshader")
	_mats[key] = m
	return m


static func _create_triplanar_material(fragment: String, folder: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = TRIPLANAR_SHADER + fragment
	var m := ShaderMaterial.new()
	m.shader = shader
	for map in ["albedo", "normal", "roughness", "ao"]:
		m.set_shader_parameter("pbr_" + map, _pbr_texture(folder, map))
	return m


static func planet_mat(base: Color, band: Color) -> ShaderMaterial:
	var key := "planet|%s|%s" % [base.to_html(), band.to_html()]
	if _mats.has(key): return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/planet.gdshader")
	m.set_shader_parameter("noise_tex", ProcTex.noise("rock"))
	m.set_shader_parameter("palette_a", base)
	m.set_shader_parameter("palette_b", band)
	m.set_shader_parameter("palette_c", base.lightened(0.35))
	_mats[key] = m
	return m

static func textured_sky(sky: Sky, space := false) -> ShaderMaterial:
	var old := sky.sky_material as ProceduralSkyMaterial
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/sky_space.gdshader")
	m.set_shader_parameter("noise_tex", ProcTex.noise("sky"))
	if old:
		m.set_shader_parameter("sky_top_color", old.sky_top_color)
		m.set_shader_parameter("sky_horizon_color", old.sky_horizon_color)
		m.set_shader_parameter("ground_bottom_color", old.ground_bottom_color)
	m.set_shader_parameter("atmosphere", 0.0 if space else 1.0)
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	return m


static func flat_mat(color: Color) -> StandardMaterial3D:
	var key := "flat|" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[key] = m
	return m


static func unshaded(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var key := "unshaded|%s|%s" % [color.to_html(), alpha]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func mesh(m: Mesh, material: Material, pos := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func box(size: Vector3, color: Color, pos := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(b, mat(color, 0.8, emission), pos)


static func cyl(radius: float, height: float, color: Color, pos := Vector3.ZERO, segments := 16, top := -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius if top < 0.0 else top
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return mesh(c, mat(color), pos)


static func sphere(radius: float, color: Color, pos := Vector3.ZERO, emission := 0.0, segments := 24) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = segments / 2
	return mesh(s, mat(color, 0.9, emission), pos)


## Faceted low-poly rock: an icosphere-like sphere with jittered vertices and flat normals.
static func rock(radius: float, color: Color, rng: RandomNumberGenerator, squash := 0.75) -> MeshInstance3D:
	var src := SphereMesh.new()
	src.radius = 1.0
	src.height = 2.0
	src.radial_segments = 7
	src.rings = 4
	var arrays := src.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var jitter := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		var v: Vector3 = verts[i]
		var key := Vector3i(roundi(v.x * 100), roundi(v.y * 100), roundi(v.z * 100))
		if not jitter.has(key):
			jitter[key] = 1.0 + rng.randf_range(-0.22, 0.22)
		var p: Vector3 = v * float(jitter[key]) * radius
		p.y *= squash
		st.add_vertex(p)
	st.generate_normals(false)
	var arr := st.commit()
	var mi := mesh(arr, terrain_mat(color, true))
	return mi


static func label(text: String, color := Color.WHITE, size := 48, outline := 8) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.font = UI.font()
	l.font_size = size
	l.outline_size = outline
	l.outline_modulate = UI.BG_DEEP
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.pixel_size = 0.01
	return l


static func ring(radius: float, width: float, color: Color, alpha := 0.85) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = radius - width * 0.5
	t.outer_radius = radius + width * 0.5
	t.rings = 48
	t.ring_segments = 4
	var mi := mesh(t, unshaded(color, alpha), Vector3.ZERO, false)
	mi.scale = Vector3(1, 0.05, 1)
	return mi


static func disc(radius: float, color: Color, height := 0.12, segments := 48) -> MeshInstance3D:
	return cyl(radius, height, color, Vector3(0, height * 0.5, 0), segments)


static func environment(sky_top: Color, horizon: Color, ground: Color, energy := 1.0, fog := Color(0, 0, 0, 0), fog_density := 0.0) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = sky_top
	sm.sky_horizon_color = horizon
	sm.ground_horizon_color = horizon
	sm.ground_bottom_color = ground
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	textured_sky(sky, sky_top.get_luminance() < 0.12)
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = energy
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = not _mobile_gpu()
	env.ssao_intensity = 1.6
	env.ssao_radius = 1.0
	env.ssao_detail = 0.1
	if fog_density > 0.0:
		env.fog_enabled = true
		env.fog_light_color = fog
		env.fog_density = fog_density
		env.fog_sky_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_multi_level_glow(env)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.18
	we.environment = env
	return we


static func sun(rot_deg: Vector3, color := Color(1, 0.96, 0.9), energy := 1.2) -> DirectionalLight3D:
	var d := DirectionalLight3D.new()
	d.rotation_degrees = rot_deg
	d.light_color = color
	d.light_energy = energy
	_configure_sun_shadows(d, 90.0)
	return d


## iOS / mobile Metal: avoid desktop-only SSAO and keep cascades light.
static func _mobile_gpu() -> bool:
	return OS.has_feature("ios") or OS.has_feature("mobile")


## Rich multi-level HDR bloom: wide soft halos plus tight highlights.
static func _multi_level_glow(env: Environment) -> void:
	var levels := [0.0, 0.6, 1.0, 0.8, 0.5, 0.2, 0.0] if not _mobile_gpu() else [0.0, 0.8, 1.0, 0.5, 0.0, 0.0, 0.0]
	for i in levels.size():
		env.set_glow_level(i, levels[i])


static func _configure_sun_shadows(light: DirectionalLight3D, max_distance: float) -> void:
	light.shadow_enabled = true
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 1.2
	light.shadow_blur = 1.1
	light.directional_shadow_split_1 = 0.06
	light.directional_shadow_split_2 = 0.16
	light.directional_shadow_split_3 = 0.42
	light.directional_shadow_fade_start = 0.85
	light.directional_shadow_max_distance = max_distance
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if _mobile_gpu() else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_blend_splits = true


## Apply the outdoor preset to the first WorldEnvironment and sun in the subtree.
static func apply_cinematic_atmosphere(root_node: Node) -> void:
	if root_node == null:
		return
	var world := root_node as WorldEnvironment
	var light := root_node as DirectionalLight3D
	if world == null:
		var worlds := root_node.find_children("*", "WorldEnvironment", true, false)
		if not worlds.is_empty():
			world = worlds[0] as WorldEnvironment
	if light == null:
		var lights := root_node.find_children("*", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			light = lights[0] as DirectionalLight3D

	if light != null:
		# Golden hour: low warm sun (~26 deg) with high energy for long, carving shadows.
		light.light_color = Color("#ffe3ba")
		light.light_energy = 2.05
		light.rotation_degrees = Vector3(-26, -42, 0)
		light.light_angular_distance = 0.6
		_configure_sun_shadows(light, 180.0)

	if world != null:
		# Keep edits local when multiple nodes share an Environment resource.
		var env := Environment.new()
		if world.environment != null:
			env = world.environment.duplicate() as Environment
		var sky := Sky.new()
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color("#0f63e0")
		sm.sky_horizon_color = Color("#8fe0ff")
		sm.ground_horizon_color = Color("#8fe0ff")
		sm.ground_bottom_color = Color("#24803f")
		sky.sky_material = sm
		textured_sky(sky, false)
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		# Cool blue sky bounce at LOWER flat ambient so shadows keep real depth.
		env.ambient_light_color = Color("#8fb8ec")
		env.ambient_light_energy = 0.34
		env.ambient_light_sky_contribution = 0.75
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.0
		env.tonemap_white = 6.0
		# Keep heavy/grainy screen-space GI/SSR/volumetrics off for crisp high-FPS rendering.
		env.sdfgi_enabled = false
		env.ssr_enabled = false
		env.ssil_enabled = false
		env.volumetric_fog_enabled = false
		env.ssao_enabled = not _mobile_gpu()
		env.ssao_intensity = 1.1
		env.ssao_radius = 0.8
		env.ssao_detail = 0.1
		env.glow_enabled = true
		env.glow_intensity = 0.42
		env.glow_bloom = 0.10
		env.glow_hdr_threshold = 1.05
		env.glow_hdr_scale = 2.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		_multi_level_glow(env)
		# Aerial perspective: distant ranges recede into sunlit golden-blue mist.
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color("#9cc6ee")
		env.fog_sun_scatter = 0.65
		env.fog_density = 0.0011
		env.fog_aerial_perspective = 0.75
		env.fog_sky_affect = 0.35
		env.volumetric_fog_albedo = Color("#d8e6f5")
		env.volumetric_fog_emission = Color("#ffcf99")
		env.volumetric_fog_emission_energy = 0.0
		env.volumetric_fog_anisotropy = 0.7
		env.volumetric_fog_length = 120.0
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.10
		env.adjustment_saturation = 1.16
		world.environment = env


## A gas-giant style planet with banded stripes, hung in the sky.
static func planet(radius: float, base: Color, band: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(sphere(radius, base, Vector3.ZERO, 0.15, 32))
	root.get_child(0).material_override = planet_mat(base, band)
	return root
