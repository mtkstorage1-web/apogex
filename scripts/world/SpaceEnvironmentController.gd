class_name SpaceEnvironmentController
extends Node3D
## Deterministic starfield + nebula tint + distant exoplanet silhouette. The whole node follows the
## camera and is scaled to ~80% of the far plane, so everything sits at effectively infinite distance.

const STAR_COUNT := {"LOW": 1800, "MEDIUM": 3600, "HIGH": 5400, "ULTRA": 7500}
const MAX_STARS := 7500
const DOME_RADIUS := 0.78   # fraction of camera far plane

var world_cfg: WorldConfig
var starfield: MultiMeshInstance3D
var star_material: StandardMaterial3D
var nebula_root: Node3D
var exoplanet: MeshInstance3D
var exoplanet_ring: MeshInstance3D
var galactic_haze: Node3D
var visibility: float = 1.0
var quality_preset: String = "HIGH"
var current_origin: Vector3 = Vector3.ZERO
var _soft_texture: GradientTexture2D


func setup(p_world_cfg: WorldConfig) -> void:
	world_cfg = p_world_cfg
	quality_preset = world_cfg.quality_preset.to_upper()
	_soft_texture = _make_soft_texture()
	_build_starfield()
	_build_nebulae()
	_build_exoplanet()
	_build_galactic_haze()
	set_quality(quality_preset)


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()
	if starfield != null:
		starfield.multimesh.visible_instance_count = mini(STAR_COUNT.get(quality_preset, 5400), MAX_STARS)
	if galactic_haze != null:
		var keep: int = {"LOW": 3, "MEDIUM": 6, "HIGH": 9, "ULTRA": 12}.get(quality_preset, 9)
		for i in galactic_haze.get_child_count():
			(galactic_haze.get_child(i) as Node3D).visible = i < keep


## Called every frame with the camera's render-space position and far plane.
func track_camera(cam_render_pos: Vector3, far_plane: float) -> void:
	global_position = cam_render_pos
	var s: float = far_plane * DOME_RADIUS
	scale = Vector3(s, s, s)


## 1 in vacuum, 0 on the surface where the sky hides the stars.
func set_star_visibility(v: float) -> void:
	visibility = clampf(v, 0.0, 1.0)
	if star_material != null:
		star_material.albedo_color = Color(1, 1, 1, visibility)
	if starfield != null:
		starfield.visible = visibility > 0.01
	if nebula_root != null:
		nebula_root.visible = visibility > 0.05
	if galactic_haze != null:
		galactic_haze.visible = visibility > 0.05


## Space background is camera-relative, so a floating-origin shift only needs to be recorded.
func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin


func _make_soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _additive_material(tex: Texture2D, vertex_colors: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = vertex_colors
	m.disable_fog = true
	m.disable_receive_shadows = true
	return m


func _build_starfield() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_cfg.world_seed, "starfield"]) & 0x7fffffff
	# Non-uniform: a handful of dense clusters plus a faint galactic band plus uniform background.
	var clusters: Array[Vector3] = []
	for i in 14:
		clusters.append(_rand_dir(rng))
	var band_normal: Vector3 = Vector3(0.28, 0.9, -0.33).normalized()
	var band_u: Vector3 = band_normal.cross(Vector3.RIGHT).normalized()
	var band_v: Vector3 = band_normal.cross(band_u).normalized()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	star_material = _additive_material(_soft_texture, true)
	quad.material = star_material
	mm.mesh = quad
	mm.instance_count = MAX_STARS
	for i in MAX_STARS:
		var roll: float = rng.randf()
		var dir: Vector3
		if roll < 0.45:
			dir = _rand_dir(rng)
		elif roll < 0.75:
			var a: float = rng.randf() * TAU
			var lift: float = rng.randfn(0.0, 0.14)
			dir = (band_u * cos(a) + band_v * sin(a) + band_normal * lift).normalized()
		else:
			var c: Vector3 = clusters[rng.randi() % clusters.size()]
			dir = (c + Vector3(rng.randfn(0, 0.11), rng.randfn(0, 0.11), rng.randfn(0, 0.11))).normalized()
		var bright: float = pow(rng.randf(), 3.2)
		var size: float = lerpf(0.0024, 0.0095, bright)
		var temp: float = rng.randf()
		var col: Color
		if temp < 0.3:
			col = Color(0.65, 0.78, 1.0)
		elif temp < 0.62:
			col = Color(1.0, 0.97, 0.92)
		elif temp < 0.85:
			col = Color(1.0, 0.85, 0.55)
		else:
			col = Color(1.0, 0.52, 0.34)
		col.a = lerpf(0.25, 1.0, bright)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(size, size, size)), dir))
		mm.set_instance_color(i, col)
	starfield = MultiMeshInstance3D.new()
	starfield.name = "Starfield"
	starfield.multimesh = mm
	starfield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	starfield.extra_cull_margin = 4.0
	add_child(starfield)


func _build_nebulae() -> void:
	nebula_root = Node3D.new()
	nebula_root.name = "Nebulae"
	add_child(nebula_root)
	var defs: Array = [
		{"dir": Vector3(-0.55, 0.42, -0.72), "size": 0.9, "color": Color(0.35, 0.12, 0.45, 0.16)},
		{"dir": Vector3(0.62, -0.3, -0.72), "size": 0.7, "color": Color(0.1, 0.28, 0.4, 0.13)},
		{"dir": Vector3(-0.2, 0.75, 0.62), "size": 0.8, "color": Color(0.5, 0.16, 0.1, 0.12)},
	]
	for d in defs:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		q.mesh = qm
		var mat: StandardMaterial3D = _additive_material(_soft_texture, false)
		mat.albedo_color = d["color"]
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s: float = d["size"]
		q.scale = Vector3(s, s * 0.6, s)
		q.position = (d["dir"] as Vector3).normalized() * 0.97
		nebula_root.add_child(q)


func _build_exoplanet() -> void:
	exoplanet = MeshInstance3D.new()
	exoplanet.name = "DistantExoplanet"
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	sphere.radial_segments = 48
	sphere.rings = 24
	exoplanet.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.035, 0.05)
	m.roughness = 1.0
	m.rim_enabled = true
	m.rim = 0.9
	m.rim_tint = 0.3
	exoplanet.material_override = m
	exoplanet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	exoplanet.position = Vector3(-0.42, 0.34, -0.78).normalized() * 0.92
	add_child(exoplanet)
	# Soft halo behind the silhouette.
	var halo := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(0.34, 0.34)
	halo.mesh = hq
	var hm: StandardMaterial3D = _additive_material(_soft_texture, false)
	hm.albedo_color = Color(0.9, 0.35, 0.2, 0.12)
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = exoplanet.position * 1.01
	add_child(halo)


## Subtle galactic nebula haze: overlapping soft additive quads along the galactic band (deterministic).
func _build_galactic_haze() -> void:
	galactic_haze = Node3D.new()
	galactic_haze.name = "GalacticHaze"
	add_child(galactic_haze)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_cfg.world_seed, "galactic_haze"]) & 0x7fffffff
	var band_normal: Vector3 = Vector3(0.28, 0.9, -0.33).normalized()
	var band_u: Vector3 = band_normal.cross(Vector3.RIGHT).normalized()
	var band_v: Vector3 = band_normal.cross(band_u).normalized()
	for i in 12:
		var a: float = (float(i) / 12.0) * TAU + rng.randf_range(-0.15, 0.15)
		var dir: Vector3 = (band_u * cos(a) + band_v * sin(a) + band_normal * rng.randfn(0.0, 0.06)).normalized()
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		q.mesh = qm
		var mat: StandardMaterial3D = _additive_material(_soft_texture, false)
		mat.albedo_color = Color(0.22 + rng.randf() * 0.12, 0.2, 0.34 + rng.randf() * 0.12, 0.055)
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s: float = rng.randf_range(0.5, 0.9)
		q.scale = Vector3(s, s * 0.55, s)
		q.position = dir * 0.96
		galactic_haze.add_child(q)
	# Thin ring around the distant exoplanet.
	exoplanet_ring = MeshInstance3D.new()
	exoplanet_ring.name = "ExoplanetRing"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.105
	ring.outer_radius = 0.125
	ring.rings = 48
	ring.ring_segments = 6
	exoplanet_ring.mesh = ring
	exoplanet_ring.scale = Vector3(1.0, 0.04, 1.0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.22, 0.14, 0.12)
	rm.roughness = 1.0
	exoplanet_ring.material_override = rm
	exoplanet_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	exoplanet_ring.position = exoplanet.position
	exoplanet_ring.rotation = Vector3(0.5, 0.0, 0.35)
	add_child(exoplanet_ring)


func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z: float = rng.randf_range(-1.0, 1.0)
	var a: float = rng.randf() * TAU
	var r: float = sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))
