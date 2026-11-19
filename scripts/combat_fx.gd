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


## Pooled glowing tracer beam + brief muzzle flash. Idle beams are reused (no per-shot allocation).
const MAX_TRACERS := 48

static func _acquire_tracer(world: Node3D) -> MeshInstance3D:
	var pool: Node3D = world.get_node_or_null("TracerPool")
	if pool == null:
		pool = Node3D.new()
		pool.name = "TracerPool"
		world.add_child(pool)
	var oldest: MeshInstance3D = null
	for child in pool.get_children():
		if not child.get_meta("busy", false):
			return child as MeshInstance3D
		if oldest == null: oldest = child as MeshInstance3D
	if oldest != null and pool.get_child_count() >= MAX_TRACERS:
		# Cap reached: recycle the oldest live beam instead of growing.
		var old_tw: Tween = oldest.get_meta("tween", null)
		if old_tw != null and old_tw.is_valid(): old_tw.kill()
		pool.move_child(oldest, -1)
		return oldest
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	beam.mesh = box
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = mat
	var light := OmniLight3D.new()
	light.shadow_enabled = false
	light.omni_attenuation = 1.6
	pool.add_child(beam)
	beam.add_child(light)
	return beam

static func _release_tracer(beam: MeshInstance3D) -> void:
	if not is_instance_valid(beam): return
	beam.visible = false
	beam.set_meta("busy", false)
	beam.set_meta("tween", null)

static func tracer(world: Node3D, from: Vector3, to: Vector3, color: Color, width := 0.055, duration := 0.09) -> void:
	if not is_instance_valid(world) or not world.is_inside_tree():
		return
	var beam := _acquire_tracer(world)
	beam.set_meta("busy", true)
	beam.visible = true
	var delta := to - from
	var length := delta.length()
	var light := beam.get_child(0) as OmniLight3D
	var mat := beam.material_override as StandardMaterial3D
	var hot := color.lerp(Color.WHITE, 0.35)
	mat.albedo_color = Color(hot, 1.0)
	if length < 0.01:
		# Degenerate shot: no beam, just the flash.
		beam.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), from)
	else:
		var fwd := delta / length
		var ref := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var x := ref.cross(fwd).normalized()
		var y := fwd.cross(x).normalized()
		beam.global_transform = Transform3D(Basis(x, y, fwd), from + delta * 0.5)
		beam.scale = Vector3(width, width, length)
	# Flash light sits at the muzzle regardless of beam orientation/scale.
	light.top_level = true
	light.global_position = from
	light.light_color = color
	light.light_energy = 3.5
	light.omni_range = 4.0
	light.visible = true
	var full := beam.scale
	var thin := Vector3(full.x * 0.1, full.y * 0.1, full.z)
	var tw := beam.create_tween().set_parallel()
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.tween_property(beam, "scale", thin, duration)
	tw.tween_property(light, "light_energy", 0.0, 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_release_tracer.bind(beam))
	beam.set_meta("tween", tw)
