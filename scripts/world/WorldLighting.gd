class_name WorldLighting
extends Node3D
## Warm unstable red-orange star light + deep-space sky / ACES environment whose fog, sky and ambient
## adapt to the camera's altitude above Vesper-9.

const SPACE_TOP := Color("02040A")
const SPACE_HORIZON := Color("040712")
const SURFACE_TOP := Color(0.26, 0.15, 0.14)
const SURFACE_HORIZON := Color(0.55, 0.3, 0.2)
const SURFACE_FOG := Color(0.5, 0.28, 0.2)

var world_cfg: WorldConfig
var light: DirectionalLight3D
var world_env: WorldEnvironment
var environment: Environment
var sky_material: ProceduralSkyMaterial
var quality_preset: String = "HIGH"
var atmosphere_factor: float = 1.0
var _flicker_time: float = 0.0
var _base_energy: float = 2.3


func setup(p_world_cfg: WorldConfig) -> void:
	world_cfg = p_world_cfg
	light = get_node_or_null("StarLight") as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = "StarLight"
		add_child(light)
	world_env = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		add_child(world_env)
	light.light_color = Color(1.0, 0.62, 0.38)
	light.light_energy = _base_energy
	light.light_angular_distance = 0.9
	light.shadow_enabled = true
	light.shadow_bias = 0.04
	light.shadow_blur = 1.2
	set_star_direction(world_cfg.star_direction)

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_curve = 0.18
	sky_material.sun_angle_max = 6.0
	sky_material.sun_curve = 0.2
	sky_material.use_debanding = true
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.fog_enabled = true
	environment.fog_light_color = SURFACE_FOG
	world_env.environment = environment
	set_quality(world_cfg.quality_preset)
	update_for_altitude(world_cfg.atmosphere_radius - world_cfg.planet_radius)


func set_star_direction(dir: Vector3) -> void:
	var d: Vector3 = dir.normalized()
	var up: Vector3 = Vector3.UP if absf(d.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	# Light travels FROM the star: its -Z axis must point away from the star.
	light.basis = Basis.looking_at(-d, up)


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()
	match quality_preset:
		"LOW":
			light.shadow_enabled = false
			environment.glow_enabled = false
			environment.ssao_enabled = false
		"MEDIUM":
			light.shadow_enabled = true
			light.directional_shadow_max_distance = 250.0
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			environment.glow_enabled = true
			environment.ssao_enabled = false
		"HIGH":
			light.shadow_enabled = true
			light.directional_shadow_max_distance = 450.0
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			environment.glow_enabled = true
			environment.ssao_enabled = false
		_:
			light.shadow_enabled = true
			light.directional_shadow_max_distance = 800.0
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			environment.glow_enabled = true
			environment.glow_intensity = 0.7
			environment.ssao_enabled = DisplayServer.get_name() != "headless"


## altitude is metres above the reference sphere. Fog/sky/ambient fade to vacuum above the atmosphere.
func update_for_altitude(altitude: float) -> void:
	var thickness: float = maxf(world_cfg.atmosphere_radius - world_cfg.planet_radius, 1.0)
	atmosphere_factor = 1.0 - smoothstep(thickness * 0.05, thickness * 1.2, altitude)
	var f: float = atmosphere_factor
	sky_material.sky_top_color = SPACE_TOP.lerp(SURFACE_TOP, f)
	sky_material.sky_horizon_color = SPACE_HORIZON.lerp(SURFACE_HORIZON, f)
	sky_material.ground_horizon_color = SPACE_HORIZON.lerp(SURFACE_HORIZON.darkened(0.4), f)
	sky_material.ground_bottom_color = SPACE_TOP.lerp(Color(0.1, 0.06, 0.05), f)
	sky_material.sky_energy_multiplier = lerpf(1.0, 0.9, f)
	environment.fog_density = lerpf(0.0, 0.00028, f) * lerpf(1.0, 0.45, smoothstep(0.0, thickness * 0.4, altitude))
	environment.fog_sun_scatter = 0.25 * f
	environment.fog_sky_affect = 0.5 * f
	environment.ambient_light_energy = lerpf(0.28, 0.50, f)
	environment.ambient_light_color = Color(0.22, 0.25, 0.30).lerp(Color(0.56, 0.51, 0.46), f)


## Slow unstable-star flicker.
func _process(delta: float) -> void:
	if light == null:
		return
	_flicker_time += delta
	var wobble: float = 1.0 + 0.035 * sin(_flicker_time * 0.9) + 0.02 * sin(_flicker_time * 2.7 + 1.3)
	light.light_energy = _base_energy * wobble
