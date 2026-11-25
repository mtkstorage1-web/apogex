class_name SurfaceEffectsController
extends Node3D
## Camera-following GPU particles (dust / ash / embers) tuned per biome and faded out with altitude.

const FADE_START_AGL := 250.0
const FADE_END_AGL := 1400.0
const AMOUNT := {"LOW": 150, "MEDIUM": 320, "HIGH": 600, "ULTRA": 1000}

## Biome id order matches TerrainBiomeSampler.BiomeId.
const BIOME_FX := [
	{"name": "ash", "color": Color(0.55, 0.5, 0.48, 0.5), "gravity": -0.5, "speed": 1.2, "size": 0.14, "life": 9.0, "spread": 0.9},
	{"name": "red dust", "color": Color(0.78, 0.3, 0.16, 0.38), "gravity": -0.1, "speed": 2.6, "size": 0.22, "life": 8.0, "spread": 0.5},
	{"name": "embers", "color": Color(1.0, 0.42, 0.1, 0.9), "gravity": 1.1, "speed": 1.4, "size": 0.09, "life": 6.0, "spread": 0.6},
	{"name": "rust dust", "color": Color(0.7, 0.36, 0.18, 0.36), "gravity": -0.05, "speed": 3.0, "size": 0.24, "life": 8.0, "spread": 0.4},
	{"name": "pale dust", "color": Color(0.8, 0.76, 0.7, 0.28), "gravity": -0.15, "speed": 1.8, "size": 0.18, "life": 8.0, "spread": 0.6},
	{"name": "fine dust", "color": Color(0.75, 0.6, 0.5, 0.26), "gravity": -0.1, "speed": 1.0, "size": 0.16, "life": 8.0, "spread": 0.7},
]

var particles: GPUParticles3D
var process_mat: ParticleProcessMaterial
var quality_preset: String = "HIGH"
var current_biome: int = -1
var intensity: float = 0.0
var fx_name: String = ""


func setup(preset: String) -> void:
	quality_preset = preset.to_upper()
	particles = GPUParticles3D.new()
	particles.name = "BiomeParticles"
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_mat = ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(34, 14, 34)
	process_mat.direction = Vector3(1, 0, 0)
	process_mat.spread = 180.0
	process_mat.initial_velocity_min = 0.2
	process_mat.initial_velocity_max = 1.5
	process_mat.turbulence_enabled = true
	process_mat.turbulence_noise_strength = 0.6
	process_mat.turbulence_noise_scale = 6.0
	particles.process_material = process_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _soft_dot()
	mat.disable_receive_shadows = true
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.lifetime = 8.0
	particles.amount = AMOUNT.get(quality_preset, 600)
	particles.emitting = false
	add_child(particles)


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()
	if particles != null:
		particles.amount = AMOUNT.get(quality_preset, 600)


## Called every frame. cam_render_pos is the camera in render space; agl is height above local terrain.
func follow(cam_render_pos: Vector3, planet_up: Vector3, biome_id: int, agl: float) -> void:
	if particles == null:
		return
	global_position = cam_render_pos
	var east: Vector3 = Vector3.UP.cross(planet_up)
	if east.length_squared() < 1.0e-8:
		east = Vector3.RIGHT
	east = east.normalized()
	global_basis = Basis(east, planet_up, east.cross(planet_up).normalized())
	intensity = 1.0 - smoothstep(FADE_START_AGL, FADE_END_AGL, agl)
	if quality_preset == "LOW":
		intensity *= 0.6
	particles.emitting = intensity > 0.02
	particles.amount_ratio = clampf(intensity, 0.05, 1.0)
	if biome_id != current_biome and biome_id >= 0 and biome_id < BIOME_FX.size():
		current_biome = biome_id
		_apply_biome(BIOME_FX[biome_id])
	if current_biome >= 0:
		# Gravity is world-space; keep it aligned with the local planet-down direction.
		var fx: Dictionary = BIOME_FX[current_biome]
		process_mat.gravity = -planet_up * (fx["gravity"] as float)


func _apply_biome(fx: Dictionary) -> void:
	fx_name = fx["name"]
	process_mat.color = fx["color"]
	process_mat.initial_velocity_max = fx["speed"]
	process_mat.scale_min = (fx["size"] as float) * 3.0
	process_mat.scale_max = (fx["size"] as float) * 8.0
	process_mat.turbulence_noise_strength = fx["spread"]
	particles.lifetime = fx["life"]


func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t
