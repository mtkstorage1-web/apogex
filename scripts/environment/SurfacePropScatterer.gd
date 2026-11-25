class_name SurfacePropScatterer
extends Node3D
## Deterministic MultiMesh rock scatter around every biome. Uses the Blender GLB rocks when they are
## imported (ResourceLoader.exists) and falls back to well-proportioned procedural meshes otherwise.

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")

const ROCK_DIR := "res://assets/models/apogex/rocks/"
## Props are embedded this far into the ground so nothing ever floats.
const EMBED_DEPTH := 0.3
const MIN_NATURAL_FACTOR := 0.995
const BASE_COUNT_PER_SITE := 220

## Per-kind data: glb file, target height range (m) the mesh is normalised to, procedural fallback id.
const KINDS: Dictionary = {
	"basalt_boulder": {"glb": "basalt_boulder_a.glb", "height": Vector2(1.4, 4.8), "proc": "boulder", "color": Color(0.17, 0.15, 0.14)},
	"basalt_column": {"glb": "basalt_column_cluster.glb", "height": Vector2(3.0, 9.0), "proc": "columns", "color": Color(0.1, 0.1, 0.12)},
	"obsidian_crystal": {"glb": "obsidian_crystal_cluster.glb", "height": Vector2(2.0, 6.5), "proc": "crystals", "color": Color(0.05, 0.04, 0.09)},
	"crimson_pillar": {"glb": "crimson_strata_pillar.glb", "height": Vector2(4.0, 14.0), "proc": "strata", "color": Color(0.5, 0.16, 0.09)},
	"iron_outcrop": {"glb": "iron_ore_outcrop.glb", "height": Vector2(1.6, 5.0), "proc": "outcrop", "color": Color(0.45, 0.22, 0.12)},
	"granite_slab": {"glb": "highland_granite_slab.glb", "height": Vector2(2.0, 7.0), "proc": "slab", "color": Color(0.62, 0.6, 0.57)},
}

## name, lat, lon (deg), scatter radius (m), kind list
const SITES: Array = [
	{"name": "Terminus Basin", "lat": 0.0, "lon": 0.0, "radius": 1000.0, "kinds": ["iron_outcrop", "basalt_boulder"]},
	{"name": "Crimson Canyons N", "lat": 10.0, "lon": -13.0, "radius": 1100.0, "kinds": ["crimson_pillar", "basalt_boulder"]},
	{"name": "Crimson Canyons S", "lat": -10.0, "lon": 13.0, "radius": 1100.0, "kinds": ["crimson_pillar", "basalt_boulder"]},
	{"name": "Obsidian Fields", "lat": 0.0, "lon": -20.0, "radius": 1100.0, "kinds": ["basalt_column", "obsidian_crystal"]},
	{"name": "Iron Desert", "lat": 0.0, "lon": 20.0, "radius": 1100.0, "kinds": ["iron_outcrop", "basalt_boulder"]},
	{"name": "Fractured Highlands", "lat": 18.0, "lon": 0.0, "radius": 1000.0, "kinds": ["granite_slab", "basalt_boulder"]},
	{"name": "Ashen Wastes", "lat": -18.0, "lon": 0.0, "radius": 1100.0, "kinds": ["basalt_boulder", "basalt_column"]},
]

const DENSITY := {"LOW": 0.25, "MEDIUM": 0.55, "HIGH": 1.0, "ULTRA": 1.8}

static var _mesh_cache: Dictionary = {}

var noise: TerrainNoiseStack
var world_cfg: WorldConfig
var quality_preset: String = "HIGH"
var current_origin: Vector3 = Vector3.ZERO
var glb_kinds_loaded: Array[String] = []
var _groups: Array[Dictionary] = []   # {node, anchor(planet pos)}
var _placements: PackedVector3Array = PackedVector3Array()
var _instance_total: int = 0


func setup(p_noise: TerrainNoiseStack, p_world_cfg: WorldConfig) -> void:
	noise = p_noise
	world_cfg = p_world_cfg
	quality_preset = p_world_cfg.quality_preset.to_upper()
	rebuild()


func set_quality_preset(preset: String) -> void:
	quality_preset = preset.to_upper()
	rebuild()


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	for g in _groups:
		(g["node"] as Node3D).position = (g["anchor"] as Vector3) - current_origin


func get_instance_count() -> int:
	return _instance_total


func get_placements() -> PackedVector3Array:
	return _placements


func rebuild() -> void:
	for g in _groups:
		var n: Node = g["node"]
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_groups.clear()
	_placements = PackedVector3Array()
	_instance_total = 0
	glb_kinds_loaded.clear()
	if noise == null:
		return
	var density: float = DENSITY.get(quality_preset, 1.0)
	var per_site: int = int(BASE_COUNT_PER_SITE * density)
	for s in SITES.size():
		var site: Dictionary = SITES[s]
		var kinds: Array = site["kinds"]
		var center_dir: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(site["lat"] as float), deg_to_rad(site["lon"] as float))
		var anchor: Vector3 = noise.sample_surface_position(center_dir)
		var tb: Basis = Transforms.surface_tangent_basis(center_dir)
		for k in kinds.size():
			var kind: String = kinds[k]
			var count: int = int(per_site * (0.65 if k == 0 else 0.35))
			_build_group(s, kind, count, center_dir, anchor, tb, site["radius"] as float)


func _build_group(site_idx: int, kind: String, count: int, center_dir: Vector3, anchor: Vector3, tb: Basis, radius_m: float) -> void:
	if count <= 0:
		return
	var info: Dictionary = get_prop_mesh(kind)
	var mesh: Mesh = info["mesh"]
	var aabb: AABB = info["aabb"]
	if info["source"] == "glb" and not glb_kinds_loaded.has(kind):
		glb_kinds_loaded.append(kind)
	var kdata: Dictionary = KINDS[kind]
	var hr: Vector2 = kdata["height"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_cfg.world_seed, site_idx, kind])
	var pr: float = noise.sample_surface_radius(center_dir)
	var radius_unit: float = radius_m / pr
	var xforms: Array[Transform3D] = []
	var attempts: int = 0
	while xforms.size() < count and attempts < count * 4:
		attempts += 1
		var ang: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * radius_unit
		var dir: Vector3 = (center_dir + (tb.x * cos(ang) + tb.z * sin(ang)) * dist).normalized()
		# Never block landing pads / industrial platforms.
		if _natural_factor(dir) < MIN_NATURAL_FACTOR:
			continue
		var surf: Vector3 = noise.sample_surface_position(dir)
		var normal: Vector3 = noise.sample_surface_normal(dir)
		if normal.dot(dir) < 0.72:
			continue
		var up: Vector3 = (dir + normal * 0.6).normalized()
		var h_target: float = lerpf(hr.x, hr.y, pow(rng.randf(), 2.2))
		var s: float = h_target / maxf(aabb.size.y, 0.001)
		var yaw: float = rng.randf() * TAU
		var east: Vector3 = Vector3.UP.cross(up)
		if east.length_squared() < 1.0e-8:
			east = Vector3.RIGHT
		east = east.normalized()
		var basis := Basis(east, up, east.cross(up).normalized()).rotated(up, yaw)
		var squash: float = rng.randf_range(0.85, 1.25)
		basis = basis.scaled_local(Vector3(s * squash, s, s * squash))
		# Base of the mesh sits at -EMBED_DEPTH below the sampled terrain surface.
		var foot: Vector3 = surf - up * EMBED_DEPTH
		var origin: Vector3 = foot - basis.y * (aabb.position.y)
		xforms.append(Transform3D(basis, origin - anchor))
		_placements.append(foot)
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_%s" % [(SITES[site_idx]["name"] as String).replace(" ", ""), kind]
	mmi.multimesh = mm
	mmi.visibility_range_end = 2600.0
	mmi.visibility_range_end_margin = 200.0
	mmi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if quality_preset == "HIGH" or quality_preset == "ULTRA"
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(mmi)
	mmi.position = anchor - current_origin
	_groups.append({"node": mmi, "anchor": anchor})
	_instance_total += xforms.size()


func _natural_factor(dir: Vector3) -> float:
	return noise._biomes.get_exclusion_factor(dir)


# ---------------------------------------------------------------------------------------------
# Shared mesh helpers (also used by LandmarkManager)
# ---------------------------------------------------------------------------------------------

## Returns {mesh, aabb, source: "glb"|"procedural"} for a rock kind. Never fails.
static func get_prop_mesh(kind: String) -> Dictionary:
	var kdata: Dictionary = KINDS[kind]
	var glb_path: String = ROCK_DIR + (kdata["glb"] as String)
	var key: String = glb_path + ("|glb" if ResourceLoader.exists(glb_path) else "|proc")
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var result: Dictionary = {}
	if ResourceLoader.exists(glb_path):
		result = extract_glb_mesh(glb_path)
	if result.is_empty():
		var m: Mesh = build_procedural_rock(kdata["proc"] as String, kdata["color"] as Color)
		result = {"mesh": m, "aabb": m.get_aabb(), "source": "procedural"}
	_mesh_cache[key] = result
	return result


## Loads a GLB PackedScene and flattens every MeshInstance3D into a single ArrayMesh (one surface per
## source surface, with transforms baked and materials kept). Returns {} if the file is not usable yet.
static func extract_glb_mesh(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var res: Resource = load(path)
	if not (res is PackedScene):
		return {}
	var inst: Node = (res as PackedScene).instantiate()
	if inst == null:
		return {}
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(inst, meshes)
	if meshes.is_empty():
		inst.free()
		return {}
	var combined := ArrayMesh.new()
	for mi in meshes:
		var xf: Transform3D = _transform_relative_to(mi, inst)
		var src: Mesh = mi.mesh
		for s in src.get_surface_count():
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(src, s, xf)
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.material_override if mi.material_override != null else src.surface_get_material(s)
			if mat != null:
				st.set_material(mat)
			st.commit(combined)
	inst.free()
	if combined.get_surface_count() == 0:
		return {}
	return {"mesh": combined, "aabb": combined.get_aabb(), "source": "glb"}


## Instances a GLB scene directly (for landmarks). Returns null when the file is not available.
static func instantiate_glb(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if not (res is PackedScene):
		return null
	var inst: Node = (res as PackedScene).instantiate()
	if inst is Node3D:
		return inst as Node3D
	if inst != null:
		inst.free()
	return null


## Merged AABB of every MeshInstance3D under root, in root's local space.
static func compute_scene_aabb(root: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)
	var out := AABB()
	var first := true
	for mi in meshes:
		var box: AABB = _transform_relative_to(mi, root) * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


static func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect_mesh_instances(c, out)


static func _transform_relative_to(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Accumulates primitive-mesh pieces (with per-piece vertex colour) into one flat-shaded ArrayMesh.
class ProcMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var tris := PackedInt32Array()

	func add_arrays(arrays: Array, xf: Transform3D, color: Color, jitter: FastNoiseLite = null, jitter_amt: float = 0.0) -> void:
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base: int = verts.size()
		for p in v:
			var q: Vector3 = p
			if jitter != null:
				q += p.normalized() * jitter.get_noise_3dv(p * 3.0) * jitter_amt
			verts.append(xf * q)
			colors.append(color)
		for i in idx:
			tris.append(base + i)

	func add_prim(prim: Mesh, xf: Transform3D, color: Color, jitter: FastNoiseLite = null, jitter_amt: float = 0.0) -> void:
		add_arrays(prim.surface_get_arrays(0), xf, color, jitter, jitter_amt)

	func add_cylinder(bottom_r: float, top_r: float, height: float, sides: int, xf: Transform3D, color: Color, capped: bool = true) -> void:
		var c := CylinderMesh.new()
		c.bottom_radius = bottom_r
		c.top_radius = top_r
		c.height = height
		c.radial_segments = sides
		c.rings = 1
		c.cap_top = capped
		c.cap_bottom = capped
		# Cylinder is centred; lift so its base sits on the local origin.
		add_prim(c, xf * Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0)), color)

	func add_box(size: Vector3, xf: Transform3D, color: Color) -> void:
		var b := BoxMesh.new()
		b.size = size
		add_prim(b, xf * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5, 0)), color)

	func finish() -> ArrayMesh:
		var fv := PackedVector3Array()
		var fn := PackedVector3Array()
		var fc := PackedColorArray()
		var i: int = 0
		while i + 2 < tris.size():
			var a: Vector3 = verts[tris[i]]
			var b: Vector3 = verts[tris[i + 1]]
			var c: Vector3 = verts[tris[i + 2]]
			var n: Vector3 = (b - a).cross(c - a)
			if n.length_squared() > 1.0e-12:
				n = n.normalized()
				fv.append(a)
				fv.append(b)
				fv.append(c)
				fn.append(n)
				fn.append(n)
				fn.append(n)
				fc.append(colors[tris[i]])
				fc.append(colors[tris[i + 1]])
				fc.append(colors[tris[i + 2]])
			i += 3
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = fv
		arrays[Mesh.ARRAY_NORMAL] = fn
		arrays[Mesh.ARRAY_COLOR] = fc
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, SurfacePropScatterer.make_vertex_color_material())
		return mesh


static func make_vertex_color_material(roughness: float = 0.92, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.metallic = metallic
	return m


## Origin sits at the base of the mesh; heights are roughly 1 m so scatter can rescale freely.
static func build_procedural_rock(proc: String, base_color: Color) -> ArrayMesh:
	var pm := ProcMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(proc)
	var jitter := FastNoiseLite.new()
	jitter.seed = hash(proc) & 0xffff
	jitter.frequency = 1.1
	match proc:
		"boulder":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 9
			s.rings = 5
			pm.add_prim(s, Transform3D(Basis.IDENTITY.scaled(Vector3(1.25, 0.8, 1.05)), Vector3(0, 0.38, 0)), base_color, jitter, 0.28)
			var s2 := SphereMesh.new()
			s2.radius = 0.3
			s2.height = 0.6
			s2.radial_segments = 7
			s2.rings = 4
			pm.add_prim(s2, Transform3D(Basis.IDENTITY.scaled(Vector3(1.1, 0.8, 1.0)), Vector3(0.55, 0.2, 0.3)), base_color.darkened(0.2), jitter, 0.22)
		"columns":
			for i in 7:
				var a: float = TAU * float(i) / 7.0 + rng.randf() * 0.5
				var d: float = 0.18 + rng.randf() * 0.34 if i > 0 else 0.0
				var h: float = 0.55 + rng.randf() * 0.5 if i > 0 else 1.0
				var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.07, 0.07)).rotated(Vector3.UP, a)
				var col: Color = base_color.lightened(rng.randf() * 0.12)
				pm.add_cylinder(0.11, 0.1, h, 6, Transform3D(tilt, Vector3(cos(a) * d, -0.05, sin(a) * d)), col)
		"crystals":
			for i in 6:
				var a: float = TAU * float(i) / 6.0 + rng.randf()
				var d: float = 0.1 + rng.randf() * 0.25 if i > 0 else 0.0
				var h: float = 0.5 + rng.randf() * 0.55 if i > 0 else 1.0
				var lean := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, rng.randf_range(0.0, 0.35))
				var col: Color = base_color.lerp(Color(0.2, 0.08, 0.3), rng.randf() * 0.4)
				pm.add_cylinder(0.1, 0.0, h, 5, Transform3D(lean, Vector3(cos(a) * d, -0.04, sin(a) * d)), col)
		"strata":
			var y: float = 0.0
			var layers: int = 6
			var colors: Array[Color] = [base_color, base_color.darkened(0.3), base_color.lightened(0.15), Color(0.62, 0.35, 0.2), base_color.darkened(0.45), base_color.lightened(0.05)]
			for i in layers:
				var t: float = float(i) / float(layers)
				var r: float = lerpf(0.34, 0.2, t) * (1.0 + 0.18 * sin(float(i) * 2.4))
				var h2: float = 1.0 / float(layers)
				pm.add_cylinder(r * 1.04, r, h2, 7, Transform3D(Basis(Vector3.UP, float(i) * 0.4), Vector3(0.03 * sin(float(i) * 1.7), y - 0.02, 0.03 * cos(float(i) * 1.3))), colors[i % colors.size()])
				y += h2
		"outcrop":
			var s3 := SphereMesh.new()
			s3.radius = 0.5
			s3.height = 1.0
			s3.radial_segments = 8
			s3.rings = 4
			pm.add_prim(s3, Transform3D(Basis.IDENTITY.scaled(Vector3(1.3, 0.9, 0.95)), Vector3(0, 0.36, 0)), base_color, jitter, 0.3)
			for i in 3:
				var a2: float = rng.randf() * TAU
				pm.add_box(Vector3(0.45, 0.12, 0.2), Transform3D(Basis(Vector3.UP, a2), Vector3(cos(a2) * 0.18, 0.55 + 0.1 * i, sin(a2) * 0.18)), Color(0.65, 0.4, 0.2))
		"slab":
			var tilt2 := Basis(Vector3.FORWARD, 0.18) * Basis(Vector3.UP, 0.4)
			pm.add_box(Vector3(1.1, 1.0, 0.32), Transform3D(tilt2, Vector3(0, -0.04, 0)), base_color)
			pm.add_box(Vector3(0.7, 0.55, 0.28), Transform3D(Basis(Vector3.UP, -0.5), Vector3(0.6, -0.04, 0.25)), base_color.darkened(0.12))
		_:
			pm.add_box(Vector3(1, 1, 1), Transform3D.IDENTITY, base_color)
	return pm.finish()
