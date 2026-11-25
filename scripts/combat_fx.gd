class_name CombatFX
extends RefCounted

## A short billboard spark burst, with a fading flash instead of an expanding solid sphere.
const MAX_IDLE_BURSTS := 12

## Soft additive glow for thin rings / beams / halos. Alpha feathers toward the silhouette (surface normal
## perpendicular to the view), so thin geometry resolves as a smooth glow instead of a stair-stepped hard
## edge when MSAA is off (LOW / MEDIUM tiers). Additive blend keeps it luminous against dark space.
const SOFT_GLOW_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float alpha = 1.0;
uniform float edge_softness = 0.85;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float feather = edge_softness > 0.001 ? smoothstep(0.0, edge_softness, facing) : 1.0;
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(glow_color.a * alpha * feather, 0.0, 1.0);
}
"""
static var _soft_glow_shader: Shader


## New (unshared) soft-glow material; callers may tween "shader_parameter/alpha".
static func soft_glow(color: Color, alpha := 1.0, softness := 0.85) -> ShaderMaterial:
	if _soft_glow_shader == null:
		_soft_glow_shader = Shader.new()
		_soft_glow_shader.code = SOFT_GLOW_CODE
	var m := ShaderMaterial.new()
	m.shader = _soft_glow_shader
	m.set_shader_parameter("glow_color", color)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("edge_softness", softness)
	return m


## True when the 3D viewport renders without MSAA (LOW / MEDIUM presets, or FSR2): thin geometry should be
## widened slightly so it never drops below a pixel and shimmers.
static func hardware_aa_off() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return true
	return tree.root.msaa_3d == Viewport.MSAA_DISABLED


## Thickness multiplier for thin lines / halos on tiers without hardware AA.
static func thin_line_scale() -> float:
	return 1.6 if hardware_aa_off() else 1.0

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
	fade.add_point(0.12, Color(1, 0.97, 0.78, 0.95))
	fade.add_point(0.26, Color(1.0, 0.45, 0.7, 0.9))
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


## Pooled jump-land dust ring. Capped DustPool of reusable emitters (no per-puff allocation once warm).
const MAX_DUST := 16
const DUST_LIFETIME := 0.45

static func _acquire_dust(world: Node3D) -> CPUParticles3D:
	var pool: Node3D = world.get_node_or_null("DustPool")
	if pool == null:
		pool = Node3D.new()
		pool.name = "DustPool"
		world.add_child(pool)
	var now := Time.get_ticks_msec()
	var oldest: CPUParticles3D = null
	for child in pool.get_children():
		if now >= int(child.get_meta("free_at", 0)):
			return child as CPUParticles3D
		if oldest == null or int(child.get_meta("free_at", 0)) < int(oldest.get_meta("free_at", 0)):
			oldest = child as CPUParticles3D
	if pool.get_child_count() >= MAX_DUST and oldest != null:
		return oldest
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.add_child(particles)
	return particles


static func dust_puff(world: Node3D, pos: Vector3, color := Color("#c9c5ba"), scale := 1.0) -> void:
	if not is_instance_valid(world) or not world.is_inside_tree():
		return
	var particles := _acquire_dust(world)
	particles.name = "DustPuff"
	particles.set_meta("free_at", Time.get_ticks_msec() + int(DUST_LIFETIME * 1000.0) + 60)
	particles.position = pos + Vector3(0, 0.05, 0)
	preload("res://scripts/graphics_settings.gd").set_particle_count(particles, 11)
	particles.lifetime = DUST_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = 0.28 * scale
	particles.emission_ring_inner_radius = 0.18 * scale
	particles.emission_ring_height = 0.02
	particles.direction = Vector3(0, 0.25, 0)
	particles.spread = 25.0
	particles.gravity = Vector3(0, -0.4, 0)
	particles.radial_accel_min = 1.2 * scale
	particles.radial_accel_max = 2.0 * scale
	particles.damping_min = 2.5
	particles.damping_max = 4.0
	particles.initial_velocity_min = 0.4 * scale
	particles.initial_velocity_max = 1.1 * scale
	particles.scale_amount_min = 0.14 * scale
	particles.scale_amount_max = 0.3 * scale
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 0.55))
	fade.set_color(1, Color(color, 0.0))
	particles.color_ramp = fade
	if particles.mesh == null:
		particles.mesh = preload("res://scripts/exhaust_fx.gd").soft_quad()
		particles.material_override = particles.mesh.material
	particles.restart()
	particles.emitting = true


static func ring_pulse(parent: Node3D, at: Vector3, color: Color, radius := 6.0, duration := 0.45) -> void:
	if not is_instance_valid(parent) or UI.reduced_motion or not preload("res://scripts/graphics_settings.gd").motion_effects:
		return
	var ring := Gfx.ring(1.0, 0.14 * thin_line_scale(), color, 0.85)
	# Low softness: the flattened ring is often seen at a grazing angle, so only feather true silhouettes.
	var mat := soft_glow(color, 0.85, 0.3)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = at
	ring.scale = Vector3(0.4, 0.05, 0.4)
	parent.add_child(ring)
	if not ring.is_inside_tree():
		ring.queue_free()
		return
	var tween := ring.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale", Vector3(radius, 0.05, radius), duration)
	tween.tween_property(mat, "shader_parameter/alpha", 0.0, duration)
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
	# Unit cylinder along +Y (diameter 1): round cross-section + soft-glow rim feather = no hard box edges.
	var tube := CylinderMesh.new()
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	tube.radial_segments = 8
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	beam.mesh = tube
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.material_override = soft_glow(Color.WHITE, 1.0, 0.7)
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
	var mat := beam.material_override as ShaderMaterial
	var hot := color.lerp(Color.WHITE, 0.55)
	mat.set_shader_parameter("glow_color", Color(hot, 1.0))
	mat.set_shader_parameter("alpha", 1.0)
	# The feathered tube reads ~35% thinner than a hard box; compensate, and widen further without MSAA.
	width *= 1.35 * thin_line_scale()
	if length < 0.01:
		# Degenerate shot: no beam, just the flash.
		beam.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), from)
	else:
		var fwd := delta / length
		var ref := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var x := ref.cross(fwd).normalized()
		var z := x.cross(fwd).normalized()
		beam.global_transform = Transform3D(Basis(x, fwd, z), from + delta * 0.5)
		beam.scale = Vector3(width, length, width)
	# Flash light sits at the muzzle regardless of beam orientation/scale.
	light.top_level = true
	light.global_position = from
	light.light_color = color
	light.light_energy = 3.5
	light.omni_range = 4.0
	light.visible = true
	var full := beam.scale
	var thin := Vector3(full.x * 0.1, full.y, full.z * 0.1)
	var tw := beam.create_tween().set_parallel()
	tw.tween_property(mat, "shader_parameter/alpha", 0.0, duration)
	tw.tween_property(beam, "scale", thin, duration)
	tw.tween_property(light, "light_energy", 0.0, 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_release_tracer.bind(beam))
	beam.set_meta("tween", tw)
