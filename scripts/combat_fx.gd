class_name CombatFX
extends RefCounted

## A short billboard spark burst, with a fading flash instead of an expanding solid sphere.
const MAX_IDLE_BURSTS := 12

# The parent owns the pool, so changing worlds frees every retained node normally.
static func _acquire(parent: Node3D) -> CPUParticles3D:
	var pool: Node3D = parent.get_node_or_null("ImpactPool")
	if pool == null:
		pool = Node3D.new()
		pool.name = "ImpactPool"
		parent.add_child(pool)
	for child in pool.get_children():
		if not child.get_meta("busy", false):
			child.set_meta("busy", true)
			child.visible = true
			return child as CPUParticles3D
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.shadow_enabled = false
	particles.add_child(light)
	pool.add_child(particles)
	particles.set_meta("busy", true)
	return particles

static func _release(particles: CPUParticles3D) -> void:
	particles.emitting = false
	particles.visible = false
	particles.set_meta("busy", false)
	var idle := 0
	for child in particles.get_parent().get_children():
		if not child.get_meta("busy", false): idle += 1
	if idle > MAX_IDLE_BURSTS: particles.queue_free()

static func impact(parent: Node3D, at: Vector3, color: Color, size := 1.0, count := 18) -> void:
	var particles := _acquire(parent)
	particles.name = "ImpactSparks"
	particles.position = at
	preload("res://scripts/graphics_settings.gd").set_particle_count(particles, count)
	particles.lifetime = 0.45
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = size * 0.12
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.gravity = Vector3(0, -3.2, 0)
	particles.damping_min = size * 4.0
	particles.damping_max = size * 9.0
	particles.initial_velocity_min = size * 3.0
	particles.initial_velocity_max = size * 11.0
	particles.scale_amount_min = size * 0.06
	particles.scale_amount_max = size * 0.28
	# White-hot core that cools through a boosted tint so sparks pop on the dark regolith.
	var hot := Color(minf(color.r * 1.6 + 0.2, 1.0), minf(color.g * 1.6 + 0.2, 1.0), minf(color.b * 1.6 + 0.2, 1.0))
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.add_point(0.12, Color(1, 0.96, 0.82, 0.95))
	fade.add_point(0.4, Color(hot, 0.8))
	fade.set_color(1, Color(color, 0))
	particles.color_ramp = fade
	particles.mesh = preload("res://scripts/exhaust_fx.gd").soft_quad()
	particles.material_override = particles.mesh.material
	particles.restart()
	particles.emitting = true
	var light := particles.get_child(0) as OmniLight3D
	light.light_color = color
	light.light_energy = size * 4.0
	light.omni_range = size * 5.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	# Punchy flash: instant peak, sharp exponential falloff (retained pooled light, no new nodes).
	var tween := particles.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.5)
	tween.tween_callback(_release.bind(particles))


static func ring_pulse(parent: Node3D, at: Vector3, color: Color, radius := 6.0, duration := 0.45) -> void:
	if not is_instance_valid(parent) or UI.reduced_motion or not preload("res://scripts/graphics_settings.gd").motion_effects:
		return
	var ring := Gfx.ring(1.0, 0.14, color, 0.85)
	var mat := Gfx.unshaded(color, 0.85).duplicate() as StandardMaterial3D
	ring.material_override = mat
	ring.position = at
	ring.scale = Vector3(0.4, 0.05, 0.4)
	parent.add_child(ring)
	if not ring.is_inside_tree():
		ring.queue_free()
		return
	var tween := ring.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale", Vector3(radius, 0.05, radius), duration)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(ring.queue_free)
