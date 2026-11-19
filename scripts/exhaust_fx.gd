## Transparent, animated nozzle-local exhaust, shared by spacecraft and launcher.
class_name ExhaustFX
extends Node3D

var intensity := 1.0
var plume_materials: Array = []
var emitters: Array = []
var lights: Array = []
var age := 0.0
static var _soft_quad: QuadMesh

static func create(radius: float, plume_length: float, warm := false) -> ExhaustFX:
	var fx := ExhaustFX.new()
	fx.name = "AnimatedExhaust"
	for layer in 2:
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = radius * (0.55 if layer == 0 else 0.95)
		mesh.top_radius = radius * (0.04 if layer == 0 else 0.12)
		mesh.height = plume_length * (0.65 if layer == 0 else 1.0)
		mesh.radial_segments = 32
		mesh.rings = 14
		mesh.cap_top = false
		mesh.cap_bottom = false
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/shaders/exhaust.gdshader")
		material.set_shader_parameter("plume_length", mesh.height)
		material.set_shader_parameter("phase", float(layer) * 3.1)
		material.set_shader_parameter("hot_color", (Color(1.0, 0.91, 0.68) if warm else Color(0.65, 0.87, 1.0)) if layer == 0 else (Color(1.0, 0.58, 0.16) if warm else Color(0.18, 0.55, 1.0)))
		material.set_shader_parameter("tail_color", Color(1.0, 0.22, 0.035) if warm else Color(0.11, 0.24, 0.75))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material
		mi.rotation.x = PI / 2.0
		mi.position.z = mesh.height * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fx.add_child(mi)
		fx.plume_materials.append(material)
	var particles := CPUParticles3D.new()
	particles.name = "ExhaustWisps"
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preload("res://scripts/graphics_settings.gd").set_particle_count(particles, 32)
	particles.lifetime = 0.45
	particles.preprocess = 0.35
	particles.local_coords = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * 0.55
	particles.direction = Vector3.BACK
	particles.spread = 9.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = plume_length * 1.1
	particles.initial_velocity_max = plume_length * 1.7
	particles.scale_amount_min = radius * 0.22
	particles.scale_amount_max = radius * 0.65
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.65, 0.25, 0.18) if warm else Color(0.45, 0.75, 1.0, 0.3))
	fade.add_point(0.35, Color(0.75, 0.28, 0.06, 0.09) if warm else Color(0.1, 0.4, 1.0, 0.13))
	fade.set_color(1, Color(0.08, 0.15, 0.4, 0.0))
	particles.color_ramp = fade
	particles.mesh = soft_quad()
	particles.material_override = particles.mesh.material
	fx.add_child(particles)
	fx.emitters.append(particles)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.48, 0.12) if warm else Color(0.2, 0.6, 1.0)
	if warm: light.set_meta("base_color", light.light_color)
	light.light_energy = 0.55
	light.omni_range = radius * 4.0
	light.position.z = radius
	light.shadow_enabled = false
	fx.add_child(light)
	fx.lights.append(light)
	return fx

static func soft_quad() -> QuadMesh:
	if _soft_quad != null: return _soft_quad
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/soft_particle.gdshader")
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = material
	_soft_quad = mesh
	return mesh

func _process(dt: float) -> void:
	age += dt
	var power := intensity * (0.94 + 0.06 * sin(age * 27.0))
	for material in plume_materials: material.set_shader_parameter("intensity", power)
	for emitter in emitters: emitter.emitting = is_visible_in_tree() and intensity > 0.02
	# Warm golden-amber ignition flicker: layered fast sines + small random crackle.
	var flicker := 0.82 + 0.1 * sin(age * 31.0) + 0.06 * sin(age * 57.0 + 1.3) + 0.08 * randf()
	var lit := is_visible_in_tree() and intensity > 0.02
	for light in lights:
		light.light_energy = power * 0.62 * flicker if lit else 0.0
		if lit and light.has_meta("base_color"):
			light.light_color = (light.get_meta("base_color") as Color).lerp(Color(1.0, 0.72, 0.28), clampf(0.25 + 0.2 * sin(age * 19.0), 0.0, 0.45))


## World-space steam/dust stays at the launch mount as the vehicle clears it.
static func pad_cloud() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "LaunchMountSteam"
	preload("res://scripts/graphics_settings.gd").set_particle_count(p, 120)
	p.lifetime = 4.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 82.0
	p.gravity = Vector3(0,.4,0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.5
	var ramp := Gradient.new()
	ramp.set_color(0,Color(.75,.74,.70,0))
	ramp.add_point(.13,Color(.83,.82,.77,.45))
	ramp.add_point(.6,Color(.68,.68,.66,.25))
	ramp.set_color(1,Color(.6,.61,.61,0))
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0,.3))
	curve.add_point(Vector2(1,1))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/launch_smoke.gdshader")
	quad.material = mat
	p.mesh = quad
	p.emitting = false
	return p
