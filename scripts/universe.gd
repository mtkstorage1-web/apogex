## Persistent world with a local frame at the active pad or flight rig.
class_name Universe
extends Node3D

const DIST := 30000.0
const CRUISE_ALT := 2800.0
const A_ORIGIN := Vector3.ZERO
const B_ORIGIN := Vector3(DIST, 0, -DIST * 0.5)
const C_ORIGIN := Vector3(0, 0, -DIST)
const A_LABEL := "PLANET A · EARTH"
const B_LABEL := "PLANET B"
const C_LABEL := "PLANET C · MOON"
const PLANETS := {
	"planet_a": {"origin": A_ORIGIN, "label": A_LABEL},
	"planet_b": {"origin": B_ORIGIN, "label": B_LABEL},
	"planet_c": {"origin": C_ORIGIN, "label": C_LABEL},
}
# The transfer and launch duration use the existing compressed world coordinates.
const ATMOSPHERE_METERS_PER_UNIT := 40.0
const EARTH_TILT := 23.44
const SKY_DISK_DISTANCE := 18000.0
const EARTH_SKY_DIRECTION := Vector3(0.44, 0.18, 1.0)
const SOLAR_VECTOR := Vector3(-0.62, 0.42, 0.66)
const WEATHER = preload("res://assets/textures/planets/weather_noise.tres")
const SURFACE = preload("res://assets/shaders/earth_moon.gdshader")
const CLOUDS = preload("res://assets/shaders/earth_clouds.gdshader")
const ATMOSPHERE = preload("res://assets/shaders/planet_atmosphere.gdshader")
const TexturedEnvironment = preload("res://scripts/textured_environment.gd")
const Landscape = preload("res://scripts/planet_landscape.gd")
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const DUST_PARTICLES := 175
const ATMOSPHERE_SEGMENTS := [32, 64, 96, 128]
const CLOUD_SEGMENTS := [48, 80, 112]
const STAR_COLOURS := [Color("#7fe9ff"), Color("#ffd166"), Color("#ff8fb1"), Color("#6aa7ff"), Color("#ffffff"), Color("#c4a3ff")]
const NEBULA_COLOURS := [Color("#7c3aed"), Color("#e11d74"), Color("#0ea5c9"), Color("#2563eb")]
const RIM_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
uniform vec4 rim_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float power = 3.0;
uniform float strength = 1.4;
void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	ALBEDO = rim_color.rgb * strength;
	ALPHA = clamp(f, 0.0, 1.0);
}
"""

static var _shell_meshes := {}

var g
var scene: Node3D
var planet_a: Node3D
var planet_b: Node3D
var planet_c: Node3D
var body_a: MeshInstance3D
var body_b: MeshInstance3D
var body_c: MeshInstance3D
var shell_b: MeshInstance3D
var twin_cloud_shell: MeshInstance3D
var shell_a: MeshInstance3D
var cloud_shell: MeshInstance3D
var atmosphere_meshes: Array[SphereMesh]
var cloud_meshes: Array[SphereMesh]
var earth_in_sky: MeshInstance3D
var earth_landscape: Landscape
var twin_landscape: Landscape
var moon_landscape: Landscape
var moon_dust: CPUParticles3D
var _surface_dust := {}
var earth_environment: Node3D
var twin_environment: Node3D
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
var deep_space: Node3D
var earth_rim: MeshInstance3D
var moon_rim: MeshInstance3D


func setup(main) -> void:
	g = main
	name = "Universe"
	scene = preload("res://scenes/levels/UniverseEnvironment.tscn").instantiate()
	add_child(scene)
	planet_a = scene.get_node("PlanetA")
	planet_b = scene.get_node("PlanetB")
	planet_c = scene.get_node("PlanetC")
	planet_a.position = A_ORIGIN
	planet_b.position = B_ORIGIN
	planet_c.position = C_ORIGIN
	body_a = planet_a.get_node("BodyA")
	body_b = planet_b.get_node("BodyB")
	body_c = planet_c.get_node("BodyC")
	for body in [body_a, body_b, body_c]:
		body.material_override = body.material_override.duplicate()
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_c.rotation.y = -PI * 0.5
	var radius := (body_a.mesh as SphereMesh).radius
	var atmosphere_radius := radius + 94.0
	var cloud_radius := radius + 33.0
	atmosphere_meshes = _prepare_shell_meshes(atmosphere_radius, ATMOSPHERE_SEGMENTS)
	cloud_meshes = _prepare_shell_meshes(cloud_radius, CLOUD_SEGMENTS)
	shell_a = _body_layer(body_a, "Atmosphere", atmosphere_meshes[_atmosphere_detail], ATMOSPHERE)
	(shell_a.material_override as ShaderMaterial).set_shader_parameter("inner_ratio", radius / atmosphere_radius)
	cloud_shell = _body_layer(body_a, "Clouds", cloud_meshes[1], CLOUDS)
	(cloud_shell.material_override as ShaderMaterial).set_shader_parameter("weather_tex", WEATHER)
	shell_b = _body_layer(body_b, "Atmosphere", atmosphere_meshes[_atmosphere_detail], ATMOSPHERE)
	(shell_b.material_override as ShaderMaterial).set_shader_parameter("inner_ratio", radius / atmosphere_radius)
	twin_cloud_shell = _body_layer(body_b, "Clouds", cloud_meshes[1], CLOUDS)
	(twin_cloud_shell.material_override as ShaderMaterial).set_shader_parameter("weather_tex", WEATHER)
	earth_in_sky = _distant_disk(planet_c, body_a, "EarthInSky", EARTH_SKY_DIRECTION, 2.0)
	(earth_in_sky.material_override as ShaderMaterial).set_shader_parameter("surface_clouds", true)
	var surfaces := {"planet_a": planet_a, "planet_b": planet_b, "planet_c": planet_c}
	for planet: String in surfaces:
		var lunar := planet == "planet_c"
		var dust := _make_dust(Color("#c3a9d9") if lunar else Color("#b5a797"))
		surfaces[planet].add_child(dust)
		_surface_dust[planet] = dust
	moon_dust = _surface_dust["planet_c"]
	var world_environment := scene.get_node("WorldEnvironment") as WorldEnvironment
	env = world_environment.environment
	sky_mat = env.sky.sky_material as ShaderMaterial
	sun = scene.get_node("Sun")
	sun.basis = Basis.looking_at(-SOLAR_VECTOR.normalized())
	g.cam.far = 120000.0
	_colour_pass()


func ensure_earth_environment() -> Node3D:
	if earth_environment == null:
		earth_environment = preload("res://scenes/levels/PlanetAEnvironment.tscn").instantiate()
		planet_a.add_child(earth_environment)
		earth_landscape = Landscape.new(earth_environment, false)
		apply_quality(g.graphics)
	return earth_environment


func ensure_moon_environment() -> Node3D:
	if moon_environment == null:
		moon_environment = preload("res://scenes/levels/PlanetBEnvironment.tscn").instantiate()
		planet_c.add_child(moon_environment)
		moon_landscape = Landscape.new(moon_environment, true)
		apply_quality(g.graphics)
	return moon_environment


func body_radius(planet: String) -> float:
	var body := body_a if planet == "planet_a" else (body_b if planet == "planet_b" else body_c)
	return (body.mesh as SphereMesh).radius


func surface_height(planet: String, point: Vector3) -> float:
	var landscape := earth_landscape if planet == "planet_a" else (twin_landscape if planet == "planet_b" else moon_landscape)
	if landscape == null:
		return 0.0
	return landscape.height_at(point.x, point.z)


func ensure_twin_environment() -> Node3D:
	if twin_environment == null:
		twin_environment = preload("res://scenes/levels/PlanetAEnvironment.tscn").instantiate()
		planet_b.add_child(twin_environment)
		TexturedEnvironment.apply_surfaces(twin_environment)
		preload("res://scripts/model_detail.gd").environment(twin_environment)
		twin_landscape = Landscape.new(twin_environment, false)
		apply_quality(g.graphics)
	return twin_environment


## Colourful deep space: tinted stars, nebula veils and vivid planetary rim glows (visual only).
func _colour_pass() -> void:
	deep_space = Node3D.new()
	deep_space.name = "DeepSpaceColour"
	deep_space.top_level = true
	scene.add_child(deep_space)
	var rr := RandomNumberGenerator.new()
	rr.seed = 20260
	# Coloured stars: one multimesh of unshaded glowing points.
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 1.0
	star_mesh.height = 2.0
	star_mesh.radial_segments = 6
	star_mesh.rings = 3
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.vertex_color_use_as_albedo = true
	star_mesh.material = star_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = star_mesh
	mm.instance_count = 320
	for i in mm.instance_count:
		var dir := Vector3(rr.randfn(0, 1), rr.randfn(0, 1), rr.randfn(0, 1)).normalized()
		var size := rr.randf_range(40.0, 140.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * 80000.0))
		var c: Color = STAR_COLOURS[rr.randi() % STAR_COLOURS.size()]
		mm.set_instance_color(i, c.lerp(Color.WHITE, rr.randf_range(0.0, 0.25)))
	var stars := MultiMeshInstance3D.new()
	stars.name = "ColourStars"
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deep_space.add_child(stars)
	# Soft nebula veils: big additive radial sprites in violet / rose / cyan / blue.
	var glow := GradientTexture2D.new()
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	glow.gradient = ramp
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	for i in 9:
		var veil := Sprite3D.new()
		veil.texture = glow
		veil.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		veil.shaded = false
		veil.double_sided = true
		veil.transparent = true
		veil.modulate = Color(NEBULA_COLOURS[i % NEBULA_COLOURS.size()], 0.22)
		var d := Vector3(rr.randfn(0, 1), rr.randf_range(-0.6, 0.9), rr.randfn(0, 1)).normalized()
		veil.position = d * 90000.0
		veil.pixel_size = rr.randf_range(300.0, 520.0)
		veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		deep_space.add_child(veil)
	# Planetary rim glows.
	var radius := (body_a.mesh as SphereMesh).radius
	earth_rim = _rim_shell(body_a, "EarthRim", radius + 14.0, Color("#38bdf8"), 3.2, 1.5)
	_rim_shell(body_b, "EarthRim", radius + 14.0, Color("#38bdf8"), 3.2, 1.5)
	moon_rim = _rim_shell(body_c, "MoonRim", (body_c.mesh as SphereMesh).radius + 10.0, Color("#b794f6"), 3.6, 1.1)


func _rim_shell(body: MeshInstance3D, label: String, shell_radius: float, color: Color, power: float, strength: float) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = shell_radius
	sphere.height = shell_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var shader := Shader.new()
	shader.code = RIM_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("rim_color", color)
	m.set_shader_parameter("power", power)
	m.set_shader_parameter("strength", strength)
	var shell := Gfx.mesh(sphere, m, Vector3.ZERO, false)
	shell.name = label
	body.add_child(shell)
	return shell


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
	for landscape in [earth_landscape, twin_landscape, moon_landscape]:
		if landscape != null:
			landscape.apply_quality(terrain, values["lod"], _motion, ultra)
	if shell_a.mesh != atmosphere_meshes[_atmosphere_detail]:
		shell_a.mesh = atmosphere_meshes[_atmosphere_detail]
		shell_b.mesh = shell_a.mesh
	if clouds != _cloud_detail:
		cloud_shell.mesh = cloud_meshes[clouds]
		twin_cloud_shell.mesh = cloud_shell.mesh
		_cloud_detail = clouds
		for mesh in [body_a, body_b, cloud_shell, twin_cloud_shell, earth_in_sky]:
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
	deep_space.global_position = camera
	var location: String = g.sim.location if g.sim != null else "planet_a"
	var space := location == "space"
	for body in [body_a, body_b, body_c]:
		body.position.y = 0.0 if space else -(body.mesh as SphereMesh).radius - 0.6
	body_a.visible = space or location == "planet_b"
	body_b.visible = space or location != "planet_b"
	body_c.visible = space or location != "planet_c"
	earth_in_sky.visible = location == "planet_c"
	if earth_environment != null:
		earth_environment.visible = location == "planet_a"
	if twin_environment != null:
		twin_environment.visible = location == "planet_b"
	if moon_environment != null:
		moon_environment.visible = location == "planet_c"
	if is_instance_valid(g.world_a):
		g.world_a.visible = location == "planet_a"
	if is_instance_valid(g.world_planet_b):
		g.world_planet_b.visible = location == "planet_b"
	if is_instance_valid(g.world_b):
		g.world_b.visible = location == "planet_c"
	var alt_a := camera.distance_to(body_a.global_position) - body_radius("planet_a")
	var alt_b := camera.distance_to(body_b.global_position) - body_radius("planet_b")
	var visual_altitude := 110000.0
	if location == "planet_a":
		visual_altitude = maxf(0.0, alt_a) * ATMOSPHERE_METERS_PER_UNIT
	elif location == "planet_b":
		visual_altitude = maxf(0.0, alt_b) * ATMOSPHERE_METERS_PER_UNIT
	shell_a.visible = body_a.visible and alt_a > 96.0
	cloud_shell.visible = body_a.visible and alt_a > 34.0
	var strength := [0.48, 0.72, 0.90, 1.0][_atmosphere_detail] as float
	(shell_a.material_override as ShaderMaterial).set_shader_parameter("observer_fade", strength * smoothstep(96.0, 335.0, alt_a))
	(cloud_shell.material_override as ShaderMaterial).set_shader_parameter("observer_fade", smoothstep(34.0, 180.0, alt_a))
	shell_b.visible = body_b.visible and alt_b > 96.0
	twin_cloud_shell.visible = body_b.visible and alt_b > 34.0
	(shell_b.material_override as ShaderMaterial).set_shader_parameter("observer_fade", strength * smoothstep(96.0, 335.0, alt_b))
	(twin_cloud_shell.material_override as ShaderMaterial).set_shader_parameter("observer_fade", smoothstep(34.0, 180.0, alt_b))
	if _motion and not UI.reduced_motion:
		_age += dt
	body_a.basis = Basis(Vector3.FORWARD, deg_to_rad(EARTH_TILT)) * Basis(Vector3.UP, -0.87 + _age * 0.011)
	body_b.basis = body_a.basis * Basis(Vector3.UP, 1.7)
	if earth_in_sky.visible:
		_update_distant_disk(earth_in_sky, body_a, EARTH_SKY_DIRECTION, 0.0)
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
		for mesh in [body_a, body_b, body_c, shell_a, shell_b, cloud_shell, twin_cloud_shell, earth_in_sky]:
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
		for mesh in [body_a, body_b, cloud_shell, twin_cloud_shell, earth_in_sky]:
			(mesh.material_override as ShaderMaterial).set_shader_parameter("weather_time", _age)
	# Local haze falls off faster than the visible atmospheric scattering.
	env.fog_density = 0.0010 * exp(-visual_altitude / 5600.0)
	env.fog_light_color = Color("#8fb8e6").lerp(Color("#ffd7a8"), 0.25 * atmosphere)
	env.fog_enabled = env.fog_density > 0.000008
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = env.fog_density * 0.18
	env.ambient_light_energy = lerpf(0.10, 0.34, atmosphere)
	env.ambient_light_color = Color("#8a86d8").lerp(Color("#86b4ee"), atmosphere)
	sun.light_color = Color("#fff3dc").lerp(Color("#ffe3ba"), atmosphere)
	sun.light_energy = lerpf(1.6, 2.05, atmosphere)


func _make_dust(tint: Color) -> CPUParticles3D:
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
	mist.albedo_color = tint
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
	var flight: Flight = g.vessel
	for planet: String in _surface_dust:
		var dust: CPUParticles3D = _surface_dust[planet]
		var active: bool = g.sim != null and g.sim.on_surface(planet) and g.piloting \
			and is_instance_valid(flight) and not flight.grounded and flight.vertical_thrust >= 6.0
		if active:
			var plume := flight.position - (PLANETS[planet]["origin"] as Vector3)
			var height := surface_height(planet, plume)
			active = plume.y - height < 28.0
			if active:
				dust.position = Vector3(plume.x, height + 0.17, plume.z)
		dust.emitting = active
