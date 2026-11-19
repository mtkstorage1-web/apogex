extends RefCounted

const WEATHER = preload("res://assets/textures/planets/weather_noise.tres")
const GROUND_SHADER = preload("res://assets/shaders/planet_terrain.gdshader")
const WIND_SHADER = preload("res://assets/shaders/pad_vegetation.gdshader")

# Centred outside the arena movement envelope and existing collision footprints.
const CRATERS := [
	Vector3(-190, -210, 58), Vector3(186, -170, 48), Vector3(250, 97, 59),
	Vector3(-162, 145, 44), Vector3(-310, -22, 70), Vector3(41, -345, 79),
	Vector3(365, -320, 81), Vector3(-390, 345, 106), Vector3(72, 300, 70),
	Vector3(510, 265, 105), Vector3(-495, -385, 128), Vector3(-122, -168, 16),
	Vector3(145, 142, 19), Vector3(120, -190, 21), Vector3(370, 130, 23),
]

const TIER_STEPS := [56, 100, 156]
static var _shared_meshes := {false: {}, true: {}}

var lunar: bool
var ground: MeshInstance3D
var terrain_material: ShaderMaterial
var wind_materials: Array[ShaderMaterial] = []
var scatter: Array[MultiMesh] = []
var meadow: MultiMesh
var trees: Array[MultiMesh] = []
var meshes := {}
var height_noise := FastNoiseLite.new()
var _last_tier := -1
var _last_ultra := -1
var _last_animate := -1


func _init(environment: Node3D, is_lunar: bool) -> void:
	lunar = is_lunar
	var terrain := environment.get_node("Terrain") as Node3D
	ground = terrain.get_node("Ground")
	height_noise.seed = 712 if lunar else 73
	height_noise.frequency = 0.007 if lunar else 0.0032
	height_noise.fractal_octaves = 4
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = GROUND_SHADER
	terrain_material.set_shader_parameter("weather_tex", WEATHER)
	terrain_material.set_shader_parameter("lunar", lunar)
	ground.material_override = terrain_material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_scatter(terrain, false)
	if not lunar:
		terrain.get_node("Rocks").hide()
		terrain.get_node("GasGiant").hide()
		terrain.get_node("Moon").hide()
		_scatter(terrain, true)
		_scatter(terrain, true, true)
		_trees(terrain)
		_launch_complex(environment)
	var shared: Dictionary = _shared_meshes[lunar]
	for tier in TIER_STEPS.size():
		if not shared.has(tier):
			shared[tier] = _terrain_mesh(TIER_STEPS[tier])
		meshes[tier] = shared[tier]
	apply_quality(1, 1, true)


func height_at(x: float, z: float) -> float:
	var dist_sq := x * x + z * z
	if dist_sq <= 112.0 * 112.0:
		return 0.0
	var distance := sqrt(dist_sq)
	var amplitude := smoothstep(112.0, 194.0, distance)
	var noise := height_noise.get_noise_2d(x, z)
	var curvature := dist_sq / 14000.0
	if lunar:
		var height := noise * 18.0 - curvature
		for crater: Vector3 in CRATERS:
			var dx: float = x - crater.x
			var dz: float = z - crater.y
			var r_sq: float = (dx * dx + dz * dz) / (crater.z * crater.z)
			if r_sq < 2.25:
				var r := sqrt(r_sq)
				var rim := (r - 1.0) * 6.9
				height += crater.z * (0.155 * exp(-rim * rim) - 0.25 * maxf(0.0, 1.0 - r_sq))
		return height * amplitude
	var foothills := pow(maxf(0.0, noise + 0.33), 1.4)
	var ridge := smoothstep(205.0, 1050.0, z + absf(x) * 1.24)
	var mountain := foothills * (18.0 + ridge * 530.0)
	var coastline := smoothstep(430.0, 790.0, -z + 150.0 * sin(x * 0.004))
	var inland := mountain - curvature * 0.66 - 1.9
	var ocean := -16.0 - maxf(0.0, distance - 620.0) * 0.034 - curvature * 0.54
	return lerpf(inland, ocean, coastline) * amplitude


const SCRUB_DENSITY := [0.29, 0.66, 1.0]
const TREE_DENSITY := [0.35, 0.70, 1.0]


func apply_quality(detail: int, lod: int, animate: bool, ultra: bool = false) -> void:
	var tier := clampi(mini(detail, lod), 0, TIER_STEPS.size() - 1)
	if ground.mesh != meshes[tier]:
		ground.mesh = meshes[tier]
	var ultra_flag := int(ultra)
	if tier != _last_tier or ultra_flag != _last_ultra:
		_last_tier = tier
		_last_ultra = ultra_flag
		terrain_material.set_shader_parameter("terrain_detail", 3 if ultra else tier)
		if meadow != null:
			var meadow_count := meadow.instance_count if ultra else (roundi(meadow.instance_count * 0.35) if tier >= 2 else 0)
			if meadow.visible_instance_count != meadow_count:
				meadow.visible_instance_count = meadow_count
		for material in wind_materials:
			material.set_shader_parameter("ultra_detail", ultra)
		var density: float = SCRUB_DENSITY[tier]
		for patch in scatter:
			var target_count := roundi(patch.instance_count * density)
			if patch.visible_instance_count != target_count:
				patch.visible_instance_count = target_count
		var tree_density: float = TREE_DENSITY[tier]
		for grove in trees:
			var grove_count := roundi(grove.instance_count * tree_density)
			if grove.visible_instance_count != grove_count:
				grove.visible_instance_count = grove_count
	var animate_flag := int(animate)
	if animate_flag != _last_animate:
		_last_animate = animate_flag
		terrain_material.set_shader_parameter("animate_water", animate)
		var wind := 1.0 if animate else 0.0
		for material in wind_materials:
			material.set_shader_parameter("wind_strength", wind)


func _terrain_mesh(steps: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var side := steps + 1
	var vertex_count := side * side
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	indices.resize(steps * steps * 6)
	# Put more samples where the operational area meets the terrain.
	var extent := 1550.0 if lunar else 2400.0
	var coords := PackedFloat32Array()
	coords.resize(side)
	for k in side:
		var t := 2.0 * k / steps - 1.0
		coords[k] = signf(t) * pow(absf(t), 1.65) * extent
	for j in side:
		var z: float = coords[j]
		var row: int = j * side
		for i in side:
			var x: float = coords[i]
			vertices[row + i] = Vector3(x, height_at(x, z), z)
	var write_idx := 0
	for j in side:
		var row: int = j * side
		var up_row: int = (j - 1 if j > 0 else 0) * side
		var down_row: int = (j + 1 if j < steps else steps) * side
		for i in side:
			var index: int = row + i
			var left: Vector3 = vertices[row + (i - 1 if i > 0 else 0)]
			var right: Vector3 = vertices[row + (i + 1 if i < steps else steps)]
			var back: Vector3 = vertices[up_row + i]
			var front: Vector3 = vertices[down_row + i]
			normals[index] = (front - back).cross(right - left).normalized()
			if j < steps and i < steps:
				indices[write_idx] = index
				indices[write_idx + 1] = index + 1
				indices[write_idx + 2] = index + side
				indices[write_idx + 3] = index + 1
				indices[write_idx + 4] = index + side + 1
				indices[write_idx + 5] = index + side
				write_idx += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _scatter(parent: Node3D, plants: bool, dense_meadow: bool = false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2247 if lunar else 81 + int(plants) + int(dense_meadow)
	var patch := MultiMesh.new()
	patch.transform_format = MultiMesh.TRANSFORM_3D
	patch.use_colors = true
	var material: Material
	if plants:
		if dense_meadow:
			patch.mesh = scatter.back().mesh
			material = wind_materials[0]
		else:
			patch.mesh = _grass_mesh()
			var wind := ShaderMaterial.new()
			wind.shader = WIND_SHADER
			wind_materials.append(wind)
			material = wind
	else:
		var example := Gfx.rock(1.0, Color.WHITE, rng)
		patch.mesh = example.mesh
		example.free()
		var stone := StandardMaterial3D.new()
		stone.vertex_color_use_as_albedo = true
		stone.roughness = 0.96
		material = stone
	patch.instance_count = 1330
	if plants:
		patch.instance_count = 3600
	if dense_meadow:
		patch.instance_count = 24000
	var i := 0
	while i < patch.instance_count:
		var angle := rng.randf_range(-PI, PI)
		var distance := rng.randf_range(77.0 if plants else 126.0, 460.0 if plants else 720.0)
		if dense_meadow:
			# Bias the extra tufts toward the pad while extending into the foothills.
			distance = lerpf(82.0, 550.0, pow(rng.randf(), 1.7))
		var x := cos(angle) * distance
		var z := sin(angle) * distance
		var y := height_at(x, z)
		if not lunar and z < -420.0 and y < -8.0:
			continue
		var size := rng.randf_range(0.30, 1.20) if plants else rng.randf_range(0.32, 2.10)
		if dense_meadow:
			if y < -13.0 or absf(height_at(x + 2.0, z) - y) + absf(height_at(x, z + 2.0) - y) > 1.6:
				continue
			y -= 0.07
		if lunar and i % 21 == 0:
			size *= 2.3
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * size)
		patch.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
		var palette := Color(0.16, 0.44, 0.11) if plants else (Color(0.35, 0.33, 0.30) if lunar else Color(0.42, 0.46, 0.49))
		patch.set_instance_color(i, palette * rng.randf_range(0.80, 1.25))
		i += 1
	var batch := MultiMeshInstance3D.new()
	batch.name = "CoastalScrub" if plants else "BoulderField"
	if dense_meadow:
		batch.name = "CoastalMeadow"
		patch.custom_aabb = patch.get_aabb().grow(1.0)
		patch.visible_instance_count = 0
		meadow = patch
	else:
		scatter.append(patch)
	batch.multimesh = patch
	batch.material_override = material
	if plants:
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(batch)


func _trees(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var count := 280
	var xforms: Array[Transform3D] = []
	var guard := 0
	while xforms.size() < count and guard < 20000:
		guard += 1
		var angle := rng.randf_range(-PI, PI)
		var distance := rng.randf_range(92.0, 460.0)
		var x := cos(angle) * distance
		var z := sin(angle) * distance
		var y := height_at(x, z)
		if y < -4.0 or (z < -420.0 and y < -6.0) or z < -420.0:
			continue
		var slope := absf(height_at(x + 3.0, z) - y) + absf(height_at(x, z + 3.0) - y)
		if slope > 2.2:
			continue
		var size := rng.randf_range(0.8, 1.45)
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(size, size * rng.randf_range(0.9, 1.15), size))
		xforms.append(Transform3D(basis, Vector3(x, y - 0.15, z)))
	var palette := [Color("#1d5824"), Color("#296e29"), Color("#38822e"), Color("#4a9635")]
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color("#5e4532")
	trunk_mat.roughness = 0.92
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.vertex_color_use_as_albedo = true
	canopy_mat.roughness = 0.85
	var parts := [["FoothillTrunks", _trunk_mesh(), trunk_mat, false], ["FoothillCanopies", _canopy_mesh(), canopy_mat, true]]
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = part[3]
		mm.mesh = part[1]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			if part[3]:
				mm.set_instance_color(i, palette[i % palette.size()] * rng.randf_range(0.92, 1.12))
		var batch := MultiMeshInstance3D.new()
		batch.name = part[0]
		batch.multimesh = mm
		batch.material_override = part[2]
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if part[3] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(batch)
		trees.append(mm)


func _trunk_mesh() -> ArrayMesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.34
	trunk.height = 2.6
	trunk.radial_segments = 6
	trunk.rings = 1
	var arrays := trunk.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in verts.size():
		verts[v].y += 1.3
	arrays[Mesh.ARRAY_VERTEX] = verts
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _canopy_mesh() -> ArrayMesh:
	# Three stacked faceted cones; flat per-face normals for a clean low-poly look.
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 7
	var tiers := [[1.9, 2.0, 2.6], [3.4, 1.55, 2.3], [4.8, 1.05, 2.0]]
	for tier in tiers:
		var base_y: float = tier[0]
		var radius: float = tier[1]
		var apex := Vector3(0, base_y + tier[2], 0)
		var shade := 1.0 - 0.08 * (2 - tiers.find(tier))
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var p0 := Vector3(cos(a0) * radius, base_y, sin(a0) * radius)
			var p1 := Vector3(cos(a1) * radius, base_y, sin(a1) * radius)
			var n := (p1 - apex).cross(p0 - apex).normalized()
			builder.set_color(Color(shade, shade, shade))
			for v in [apex, p0, p1]:
				builder.set_normal(n)
				builder.add_vertex(v)
			var c := Vector3(0, base_y, 0)
			builder.set_color(Color(shade * 0.7, shade * 0.7, shade * 0.7))
			for v in [c, p1, p0]:
				builder.set_normal(Vector3.DOWN)
				builder.add_vertex(v)
	return builder.commit()


func _grass_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 7:
		var angle := blade * TAU / 7.0
		var lean := Vector3(cos(angle), 0, sin(angle))
		var across := Vector3(lean.z, 0, -lean.x)
		var base := lean * (0.05 + (blade % 3) * 0.08)
		var height := 0.43 + (blade % 3) * 0.18
		var first := blade * 7
		for row in 4:
			var t := row / 3.0
			var center := base + lean * (0.32 * t * t) + Vector3.UP * (height * t)
			var width := 0.077 * (1.0 - t * t)
			builder.set_uv(Vector2(0.5 if row == 3 else 0.0, t))
			builder.add_vertex(center - across * width)
			if row < 3:
				builder.set_uv(Vector2(1.0, t))
				builder.add_vertex(center + across * width)
		for index in [0, 2, 1, 1, 2, 3, 2, 4, 3, 3, 4, 5, 4, 6, 5]:
			builder.add_index(first + index)
	builder.generate_normals()
	return builder.commit()


func _launch_complex(environment: Node3D) -> void:
	var complex := Node3D.new()
	complex.name = "CoastalLaunchComplex"
	environment.add_child(complex)
	var steel := Color("#474f52")
	var concrete := Color("#77776c")
	var paint := Color("#c3c7be")
	for x in [-47.0, 47.0]:
		var base := Vector3(x, 0, -35)
		for dx in [-1.5, 1.5]:
			for dz in [-1.5, 1.5]:
				complex.add_child(Gfx.box(Vector3(0.25, 27, 0.25), steel, base + Vector3(dx, 13.5, dz)))
		for level in 8:
			var y := 3.4 * level
			complex.add_child(Gfx.box(Vector3(3.7, 0.2, 3.7), steel, base + Vector3.UP * y))
			for dz in [-1.5, 1.5]:
				var brace := Gfx.box(Vector3(0.14, 4.5, 0.14), steel, base + Vector3(0, y + 1.7, dz))
				brace.rotation.z = 0.72 if level % 2 == 0 else -0.72
				complex.add_child(brace)
		complex.add_child(Gfx.box(Vector3(0.65, 0.25, 0.65), Color("#e34f23"), base + Vector3.UP * 27.0, 2.0))
		for z in [-49.0, -59.0]:
			var tank := Vector3(x, 0, z)
			complex.add_child(Gfx.cyl(2.7, 7.0, paint, tank + Vector3.UP * 3.6, 20))
			var cap := Gfx.sphere(2.69, paint, tank + Vector3.UP * 7.0, 0, 20)
			cap.scale.y = 0.35
			complex.add_child(cap)
			complex.add_child(Gfx.cyl(2.73, 0.28, steel, tank + Vector3.UP * 4.5))
		for offset in [0.0, 0.51]:
			complex.add_child(Gfx.box(Vector3(0.16, 0.19, 25.0), steel, base + Vector3(offset, 0.14, -12)))
		for segment in 17:
			var point := base + Vector3(signf(x) * 6.0, 0, 30 - segment * 3.6)
			complex.add_child(Gfx.box(Vector3(0.13, 2.25, 0.13), steel, point + Vector3.UP * 1.1))
			if segment < 16:
				for y in [0.42, 1.13, 1.94]:
					complex.add_child(Gfx.box(Vector3(0.025, 0.045, 3.6), steel, point + Vector3(0, y, -1.8)))
		var flag_base := Vector3(x * 0.71, 0, -18)
		complex.add_child(Gfx.cyl(0.065, 7.0, paint, flag_base + Vector3.UP * 3.5))
		_flag(complex, flag_base + Vector3.UP * 6.5)
	# A dark refractory channel and steel grating at the end of the launch apron.
	for i in 2:
		complex.add_child(Gfx.box(Vector3(0.37, 0.5, 13), concrete, Vector3(-32 + i * 5.6, 0.23, -51)))
	complex.add_child(Gfx.box(Vector3(5.2, 0.035, 12.8), Color("#22201d"), Vector3(-29.2, 0.021, -51)))
	for i in 12:
		complex.add_child(Gfx.box(Vector3(5.2, 0.12, 0.12), steel, Vector3(-29.2, 0.13, -57 + i * 1.06)))
	preload("res://scripts/model_detail.gd").batch(complex, [], 480.0)


func _flag(parent: Node3D, origin: Vector3) -> void:
	var mesh := PlaneMesh.new()
	mesh.orientation = PlaneMesh.FACE_Z
	mesh.size = Vector2(2.2, 0.9)
	mesh.center_offset = Vector3(1.1, 0, 0)
	mesh.subdivide_width = 12
	mesh.subdivide_depth = 4
	var flag := ShaderMaterial.new()
	flag.shader = WIND_SHADER
	flag.set_shader_parameter("flag", true)
	wind_materials.append(flag)
	var instance := Gfx.mesh(mesh, flag, origin, false)
	instance.name = "WindFlag"
	parent.add_child(instance)
