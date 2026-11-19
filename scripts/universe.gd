## Persistent world with a local frame at the active pad or flight rig.
class_name Universe
extends Node3D

const DIST := 30000.0
const CRUISE_ALT := 2800.0
const A_ORIGIN := Vector3.ZERO
const B_ORIGIN := Vector3(0, 0, -DIST)
# The transfer and launch duration use the existing compressed world coordinates.
const ATMOSPHERE_METERS_PER_UNIT := 40.0
const EARTH_TILT := 23.44
const SKY_DISK_DISTANCE := 18000.0
const EARTH_SKY_DIRECTION := Vector3(0.44, 0.18, 1.0)
const MOON_SKY_DIRECTION := Vector3(-0.22, 0.25, -1.0)
const SOLAR_VECTOR := Vector3(-0.62, 0.42, 0.66)
const WEATHER = preload("res://assets/textures/planets/weather_noise.tres")
const SURFACE = preload("res://assets/shaders/earth_moon.gdshader")
const CLOUDS = preload("res://assets/shaders/earth_clouds.gdshader")
const ATMOSPHERE = preload("res://assets/shaders/planet_atmosphere.gdshader")
const Landscape = preload("res://scripts/planet_landscape.gd")
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const DUST_PARTICLES := 175
const ATMOSPHERE_SEGMENTS := [32, 64, 96, 128]
const CLOUD_SEGMENTS := [48, 80, 112]

static var _shell_meshes := {}

var g
var scene: Node3D
var planet_a: Node3D
var planet_b: Node3D
var body_a: MeshInstance3D
var body_b: MeshInstance3D
var shell_a: MeshInstance3D
var cloud_shell: MeshInstance3D
var atmosphere_meshes: Array[SphereMesh]
var cloud_meshes: Array[SphereMesh]
var earth_in_sky: MeshInstance3D
var moon_in_sky: MeshInstance3D
var earth_landscape: Landscape
var moon_landscape: Landscape
var moon_dust: CPUParticles3D
var earth_environment: Node3D
var moon_environment: Node3D
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var atmosphere := 1.0
var _sky_atmosphere := -1.0
var _sky_clouds := -1.0
var _age := 0.0
var _atmosphere_detail := 1
var _cloud_detail := -1
var _motion := true
var _last_weather_step := -1
var _last_sun := Vector3.ZERO


func setup(main) -> void:
	g = main
	name = "Universe"
	scene = preload("res://scenes/levels/UniverseEnvironment.tscn").instantiate()
	add_child(scene)
	planet_a = scene.get_node("PlanetA")
	planet_b = scene.get_node("PlanetB")
	body_a = planet_a.get_node("BodyA")
	body_b = planet_b.get_node("BodyB")
	for body in [body_a, body_b]:
		body.material_override = body.material_override.duplicate()
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_b.rotation.y = -PI * 0.5
	var radius := (body_a.mesh as SphereMesh).radius
	var atmosphere_radius := radius + 94.0
	var cloud_radius := radius + 33.0
	atmosphere_meshes = _prepare_shell_meshes(atmosphere_radius, ATMOSPHERE_SEGMENTS)
	cloud_meshes = _prepare_shell_meshes(cloud_radius, CLOUD_SEGMENTS)
	shell_a = _body_layer(body_a, "Atmosphere", atmosphere_meshes[_atmosphere_detail], ATMOSPHERE)
	(shell_a.material_override as ShaderMaterial).set_shader_parameter("inner_ratio", radius / atmosphere_radius)
	cloud_shell = _body_layer(body_a, "Clouds", cloud_meshes[1], CLOUDS)
	(cloud_shell.material_override as ShaderMaterial).set_shader_parameter("weather_tex", WEATHER)
	earth_in_sky = _distant_disk(planet_b, body_a, "EarthInSky", EARTH_SKY_DIRECTION, 2.0)
	moon_in_sky = _distant_disk(planet_a, body_b, "MoonInSky", MOON_SKY_DIRECTION, 0.52)
	(earth_in_sky.material_override as ShaderMaterial).set_shader_parameter("surface_clouds", true)
	earth_environment = planet_a.get_node("PlanetAEnvironment")
	moon_environment = planet_b.get_node("PlanetBEnvironment")
	earth_landscape = Landscape.new(earth_environment, false)
	moon_landscape = Landscape.new(moon_environment, true)
	moon_dust = _make_dust()
	planet_b.add_child(moon_dust)
	var world_environment := scene.get_node("WorldEnvironment") as WorldEnvironment
	env = world_environment.environment
	sky_mat = env.sky.sky_material as ShaderMaterial
	sun = scene.get_node("Sun")
	sun.basis = Basis.looking_at(-SOLAR_VECTOR.normalized())
	g.cam.far = 120000.0


func _prepare_shell_meshes(radius: float, segments: Array) -> Array[SphereMesh]:
	var meshes: Array[SphereMesh] = []
	for count: int in segments:
		var key := Vector2(radius, count)
		if not _shell_meshes.has(key):
			var sphere := SphereMesh.new()
			sphere.radius = radius
			sphere.height = radius * 2.0
			sphere.radial_segments = count
			sphere.rings = count / 2
			# PrimitiveMesh builds lazily. Materialize each surface before a live switch.
			sphere.get_rid()
			_shell_meshes[key] = sphere
		meshes.append(_shell_meshes[key])
	return meshes


func _body_layer(parent: Node3D, label: String, sphere: SphereMesh, shader: Shader) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = shader
	var layer := Gfx.mesh(sphere, material, Vector3.ZERO, false)
	layer.name = label
	parent.add_child(layer)
	return layer


func _distant_disk(parent: Node3D, source: MeshInstance3D, label: String, direction: Vector3, angle: float) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = SKY_DISK_DISTANCE * tan(deg_to_rad(angle * 0.5))
	sphere.height = sphere.radius * 2.0
	var disk := _body_layer(parent, label, sphere, SURFACE)
	disk.material_override = source.material_override.duplicate()
	disk.position = direction.normalized() * SKY_DISK_DISTANCE
	disk.hide()
	return disk


func apply_quality(settings) -> void:
	var values: Dictionary = settings.values
	_atmosphere_detail = values["atmosphere"]
	_motion = values["motion_effects"]
	var terrain: int = values["terrain"]
	var clouds: int = values["clouds"]
	var ultra: bool = settings.quality == 3 or _atmosphere_detail == 3
	for landscape in [earth_landscape, moon_landscape]:
		landscape.apply_quality(terrain, values["lod"], _motion, ultra)
	if shell_a.mesh != atmosphere_meshes[_atmosphere_detail]:
		shell_a.mesh = atmosphere_meshes[_atmosphere_detail]
	if clouds != _cloud_detail:
		cloud_shell.mesh = cloud_meshes[clouds]
		_cloud_detail = clouds
		for mesh in [body_a, cloud_shell, earth_in_sky]:
			(mesh.material_override as ShaderMaterial).set_shader_parameter("cloud_detail", clouds)
		sky_mat.set_shader_parameter("cloud_detail", float(clouds))


func focus_xf(world_xf: Transform3D) -> void:
	var new_u := world_xf.affine_inverse()
	var d := new_u * transform.affine_inverse()
	g.cam.global_transform = d * g.cam.global_transform
	transform = new_u


func focus(local: Vector3) -> void:
	focus_xf(Transform3D(Basis.IDENTITY, local))


func tick(dt: float) -> void:
	var camera: Vector3 = g.cam.global_position
	var alt_a := camera.distance_to(body_a.global_position) - (body_a.mesh as SphereMesh).radius
	var alt_b := camera.distance_to(body_b.global_position) - (body_b.mesh as SphereMesh).radius
	var visual_altitude := maxf(0.0, alt_a) * ATMOSPHERE_METERS_PER_UNIT
	var earth_ground := alt_a < 77.0
	var moon_ground := alt_b < 84.0
	var near_earth := alt_a < 650.0
	var near_moon := alt_b < 560.0
	body_a.visible = not (earth_ground or near_moon)
	body_b.visible = not (moon_ground or near_earth)
	earth_in_sky.visible = near_moon
	moon_in_sky.visible = near_earth
	earth_environment.visible = alt_a < 650.0
	moon_environment.visible = alt_b < 510.0
	var launching: bool = g.cine.get("kind") == "launch" and (
		g.mode == "cine" or (g.mode == "paused" and g.paused_from == "cine"))
	if is_instance_valid(g.world_a):
		g.world_a.visible = alt_a < 360.0 or launching
	if is_instance_valid(g.world_b):
		g.world_b.visible = alt_b < 360.0
	shell_a.visible = body_a.visible and alt_a > 96.0
	cloud_shell.visible = body_a.visible and alt_a > 34.0
	var strength := [0.48, 0.72, 0.90, 1.0][_atmosphere_detail] as float
	(shell_a.material_override as ShaderMaterial).set_shader_parameter("observer_fade", strength * smoothstep(96.0, 335.0, alt_a))
	(cloud_shell.material_override as ShaderMaterial).set_shader_parameter("observer_fade", smoothstep(34.0, 180.0, alt_a))
	if _motion and not UI.reduced_motion:
		_age += dt
	body_a.basis = Basis(Vector3.FORWARD, deg_to_rad(EARTH_TILT)) * Basis(Vector3.UP, -0.87 + _age * 0.011)
	if near_moon:
		_update_distant_disk(earth_in_sky, body_a, EARTH_SKY_DIRECTION, smoothstep(170.0, 560.0, alt_b))
	if near_earth:
		_update_distant_disk(moon_in_sky, body_b, MOON_SKY_DIRECTION, smoothstep(215.0, 650.0, alt_a))
	_update_sky(visual_altitude)
	_update_dust()


func _update_distant_disk(disk: MeshInstance3D, body: MeshInstance3D, direction: Vector3, blend: float) -> void:
	var parent := disk.get_parent() as Node3D
	var nearby_position := parent.to_local(body.global_position)
	disk.position = (direction.normalized() * SKY_DISK_DISTANCE).lerp(nearby_position, blend)
	var scale_factor := lerpf(1.0, (body.mesh as SphereMesh).radius / (disk.mesh as SphereMesh).radius, blend)
	disk.basis = body.basis.scaled(Vector3.ONE * scale_factor)


func _update_sky(visual_altitude: float) -> void:
	var direction := sun.global_basis.z.normalized()
	if not direction.is_equal_approx(_last_sun):
		_last_sun = direction
		for mesh in [body_a, body_b, shell_a, cloud_shell, earth_in_sky, moon_in_sky]:
			(mesh.material_override as ShaderMaterial).set_shader_parameter("sun_direction", direction)
		sky_mat.set_shader_parameter("sun_direction", direction)
	atmosphere = exp(-visual_altitude / 27000.0) * (1.0 - smoothstep(70000.0, 104000.0, visual_altitude))
	var ground_clouds := 1.0 - smoothstep(3200.0, 12500.0, visual_altitude)
	if absf(atmosphere - _sky_atmosphere) > 0.007 or (atmosphere == 0.0 and _sky_atmosphere != 0.0):
		_sky_atmosphere = atmosphere
		sky_mat.set_shader_parameter("atmosphere", atmosphere)
	if absf(ground_clouds - _sky_clouds) > 0.015 or (ground_clouds == 0.0 and _sky_clouds != 0.0):
		_sky_clouds = ground_clouds
		sky_mat.set_shader_parameter("ground_clouds", ground_clouds)
	var step := int(_age * 5.0)
	if step != _last_weather_step:
		_last_weather_step = step
		if ground_clouds > 0.0:
			sky_mat.set_shader_parameter("sky_time", _age)
		for mesh in [body_a, cloud_shell, earth_in_sky]:
			(mesh.material_override as ShaderMaterial).set_shader_parameter("weather_time", _age)
	# Local haze falls off faster than the visible atmospheric scattering.
	env.fog_density = 0.00048 * exp(-visual_altitude / 5600.0)
	env.fog_enabled = env.fog_density > 0.000008
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = env.fog_density * 0.18
	env.ambient_light_energy = lerpf(0.14, 0.54, atmosphere)
	env.ambient_light_color = Color("#c5c8d1").lerp(Color("#9ecbf5"), atmosphere)
	sun.light_color = Color("#fff6e8").lerp(Color("#ffe2b4"), atmosphere)
	sun.light_energy = lerpf(1.25, 1.42, atmosphere)


func _make_dust() -> CPUParticles3D:
	var dust := CPUParticles3D.new()
	dust.name = "ThrusterRegolith"
	GraphicsSettings.set_particle_count(dust, DUST_PARTICLES)
	dust.emitting = false
	dust.lifetime = 1.9
	dust.direction = Vector3.UP
	dust.spread = 86.0
	dust.flatness = 0.0
	dust.initial_velocity_min = 2.2
	dust.initial_velocity_max = 9.0
	dust.gravity = Vector3(0, -1.62, 0)
	dust.scale_amount_min = 0.22
	dust.scale_amount_max = 1.25
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE
	var mist := StandardMaterial3D.new()
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mist.vertex_color_use_as_albedo = true
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.albedo_color = Color("#a29c91")
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.40), Color(1, 1, 1, 0)])
	dust.color_ramp = ramp
	var sprite := GradientTexture2D.new()
	var profile := Gradient.new()
	profile.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	sprite.gradient = profile
	sprite.fill = GradientTexture2D.FILL_RADIAL
	sprite.fill_from = Vector2(0.5, 0.5)
	sprite.fill_to = Vector2(1.0, 0.5)
	mist.albedo_texture = sprite
	puff.material = mist
	dust.mesh = puff
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return dust


func _update_dust() -> void:
	var active := false
	var flight := g.world as Flight if is_instance_valid(g.world) else null
	if flight != null and not flight.is_queued_for_deletion() and flight.flame.is_visible_in_tree():
		var plume := planet_b.to_local(flight.ship.global_position)
		if absf(plume.z - Flight.B_LAND.z) < 64.0 and absf(plume.x) < 45.0:
			var ground_height := moon_landscape.height_at(plume.x, plume.z)
			var height := plume.y - ground_height
			active = height >= -1.0 and height < 28.0
			if active:
				moon_dust.position = Vector3(plume.x, ground_height + 0.17, plume.z)
	if moon_dust.emitting != active:
		moon_dust.emitting = active
