class_name FacilityBuilderUtils
extends RefCounted
## Shared APOGEX industrial facility toolkit: PBR materials, solid-collision primitives, walkable
## interiors (doorways are real gaps), ground-penetrating foundations and Blender GLB loading with a
## multi-part procedural fallback.

const SURFACE_DIR := "res://assets/models/apogex/surface/"
const DOOR_W := 2.8
const DOOR_H := 3.2
const WALL_T := 0.4
const MODEL_EMBED := 0.4

## id -> {glb, size (w, h, d)}
const MODELS: Dictionary = {
	"extraction_spire_core": {"glb": "extraction_spire_core.glb", "size": Vector3(36, 205, 36)},
	"mining_drill_tower": {"glb": "mining_drill_tower.glb", "size": Vector3(16, 32, 16)},
	"ore_crusher_hopper": {"glb": "ore_crusher_hopper.glb", "size": Vector3(14, 12, 10)},
	"refinery_tower_cluster": {"glb": "refinery_tower_cluster.glb", "size": Vector3(18, 28, 14)},
	"storage_silo_bank": {"glb": "storage_silo_bank.glb", "size": Vector3(18, 14, 10)},
	"launch_service_tower": {"glb": "launch_service_tower.glb", "size": Vector3(14, 48, 14)},
	"hab_module_derelict": {"glb": "hab_module_derelict.glb", "size": Vector3(14, 5.5, 9)},
	"power_pylon_tower": {"glb": "power_pylon_tower.glb", "size": Vector3(6, 22, 6)},
}

static var _mats: Dictionary = {}
static var glb_loaded: Array[String] = []
static var procedural_used: Array[String] = []


# ---------------------------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------------------------

static func _std(key: String, color: Color, metallic: float, rough: float, emit: float = 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


static func steel() -> StandardMaterial3D:
	return _std("steel", Color(0.52, 0.54, 0.56), 0.85, 0.43)


static func dark_steel() -> StandardMaterial3D:
	return _std("dark_steel", Color(0.23, 0.24, 0.27), 0.8, 0.48)


static func truss() -> StandardMaterial3D:
	return _std("truss", Color(0.15, 0.16, 0.18), 0.7, 0.48)


static func concrete() -> StandardMaterial3D:
	return _std("concrete", Color(0.59, 0.58, 0.55), 0.0, 0.78)


static func dark_concrete() -> StandardMaterial3D:
	return _std("dark_concrete", Color(0.37, 0.37, 0.38), 0.0, 0.84)


static func rust() -> StandardMaterial3D:
	return _std("rust", Color(0.42, 0.22, 0.12), 0.4, 0.85)


static func glass() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.55, 0.7, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	_mats["glass"] = m
	return m


static func glow_amber() -> StandardMaterial3D:
	return _std("glow_amber", Color(1.0, 0.62, 0.14), 0.0, 0.4, 3.0)


static func glow_cyan() -> StandardMaterial3D:
	return _std("glow_cyan", Color(0.2, 0.85, 1.0), 0.0, 0.4, 3.0)


static func glow_red() -> StandardMaterial3D:
	return _std("glow_red", Color(1.0, 0.1, 0.08), 0.0, 0.4, 4.0)


static func hazard() -> StandardMaterial3D:
	if _mats.has("hazard"):
		return _mats["hazard"] as StandardMaterial3D
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var stripe: bool = (int((x + y) / 8.0) % 2) == 0
			img.set_pixel(x, y, Color(0.92, 0.7, 0.05) if stripe else Color(0.05, 0.05, 0.05))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.7
	m.metallic = 0.2
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	_mats["hazard"] = m
	return m


static func hologram_material(amber: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/hologram.gdshader") as Shader
	m.set_shader_parameter("amber_mix", amber)
	return m


static func forcefield_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/forcefield.gdshader") as Shader
	return m


static func conveyor_material(length: float, speed: float = 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/conveyor.gdshader") as Shader
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("rib_count", 1.0)
	return m


# ---------------------------------------------------------------------------------------------
# Primitives (solid StaticBody3D collision on layer 1)
# ---------------------------------------------------------------------------------------------

static func _body(nm: String, xf: Transform3D, shape: Shape3D) -> Node3D:
	var holder: Node3D
	if shape != null:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		sb.add_child(cs)
		holder = sb
	else:
		holder = Node3D.new()
	holder.name = nm
	holder.transform = xf
	return holder


static func box(parent: Node, nm: String, size: Vector3, pos: Vector3, mat: Material,
		collide: bool = true, basis: Basis = Basis.IDENTITY) -> Node3D:
	var shape: Shape3D = null
	if collide:
		var bs := BoxShape3D.new()
		bs.size = size
		shape = bs
	var holder: Node3D = _body(nm, Transform3D(basis, pos), shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	holder.add_child(mi)
	parent.add_child(holder)
	return holder


static func cyl(parent: Node, nm: String, r_top: float, r_bottom: float, height: float, pos: Vector3,
		mat: Material, collide: bool = true, basis: Basis = Basis.IDENTITY, segments: int = 16) -> Node3D:
	var shape: Shape3D = null
	if collide:
		var cs := CylinderShape3D.new()
		cs.radius = maxf(r_top, r_bottom) * 0.96
		cs.height = height
		shape = cs
	var holder: Node3D = _body(nm, Transform3D(basis, pos), shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	m.material = mat
	mi.mesh = m
	holder.add_child(mi)
	parent.add_child(holder)
	return holder


static func basis_y_to(dir: Vector3) -> Basis:
	var d: Vector3 = dir.normalized()
	if d.dot(Vector3.UP) > 0.9999:
		return Basis.IDENTITY
	if d.dot(Vector3.UP) < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, d))


## Basis with x along dir (horizontal-ish), y up.
static func basis_x_along(dir: Vector3) -> Basis:
	var x: Vector3 = dir.normalized()
	var z: Vector3 = x.cross(Vector3.UP)
	if z.length_squared() < 1.0e-6:
		return Basis.IDENTITY
	z = z.normalized()
	return Basis(x, z.cross(x), z)


## Cylinder strut/pipe between two points (visual only unless collide).
static func pipe(parent: Node, nm: String, a: Vector3, b: Vector3, radius: float, mat: Material,
		collide: bool = false, segments: int = 8) -> Node3D:
	var d: Vector3 = b - a
	return cyl(parent, nm, radius, radius, d.length(), (a + b) * 0.5, mat, collide, basis_y_to(d), segments)


## Box beam between two points (square section).
static func beam(parent: Node, nm: String, a: Vector3, b: Vector3, thick: float, mat: Material, collide: bool = false) -> Node3D:
	var d: Vector3 = b - a
	return box(parent, nm, Vector3(thick, d.length(), thick), (a + b) * 0.5, mat, collide, basis_y_to(d))


static func light_strip(parent: Node, nm: String, size: Vector3, pos: Vector3, mat: Material, basis: Basis = Basis.IDENTITY) -> Node3D:
	var n: Node3D = box(parent, nm, size, pos, mat, false, basis)
	(n.get_node("Mesh") as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


static func add_light(parent: Node, pos: Vector3, color: Color, energy: float, rng: float, shadow: bool = false, nm: String = "Light") -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = nm
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	parent.add_child(l)
	return l


# ---------------------------------------------------------------------------------------------
# Walls with real doorways, rooms, ramps, stairs
# ---------------------------------------------------------------------------------------------

## Wall from `start` along unit `dir` (horizontal). doors: [{c: centre along wall, w: width, h: height}].
## The wall is split around every door: nothing blocks the opening.
static func wall(parent: Node, nm: String, start: Vector3, dir: Vector3, length: float, height: float,
		doors: Array, mat: Material, thick: float = WALL_T) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	parent.add_child(holder)
	var bas: Basis = basis_x_along(dir)
	var d: Vector3 = dir.normalized()
	var sorted: Array = doors.duplicate()
	sorted.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["c"]) < float(q["c"]))
	var cursor: float = 0.0
	var idx: int = 0
	for door in sorted:
		var dd: Dictionary = door
		var w: float = float(dd.get("w", DOOR_W))
		var dh: float = float(dd.get("h", DOOR_H))
		var c0: float = float(dd["c"]) - w * 0.5
		var c1: float = float(dd["c"]) + w * 0.5
		if c0 > cursor + 0.01:
			_wall_piece(holder, "%s_seg%d" % [nm, idx], start, d, bas, cursor, c0, 0.0, height, thick, mat)
		if height > dh + 0.01:
			_wall_piece(holder, "%s_lintel%d" % [nm, idx], start, d, bas, c0, c1, dh, height, thick, mat)
		cursor = c1
		idx += 1
	if cursor < length - 0.01:
		_wall_piece(holder, "%s_seg%d" % [nm, idx], start, d, bas, cursor, length, 0.0, height, thick, mat)
	return holder


static func _wall_piece(parent: Node, nm: String, start: Vector3, d: Vector3, bas: Basis,
		s0: float, s1: float, y0: float, y1: float, thick: float, mat: Material) -> void:
	var pos: Vector3 = start + d * ((s0 + s1) * 0.5) + Vector3.UP * ((y0 + y1) * 0.5)
	box(parent, nm, Vector3(s1 - s0, y1 - y0, thick), pos, mat, true, bas)


## Rectangular room. size = inner (w along x, h, d along z); pos = floor-top centre.
## doors: [{side: "n"|"s"|"e"|"w", off: offset from wall centre, w, h}] (n = -Z, s = +Z).
static func room(parent: Node, nm: String, size: Vector3, pos: Vector3, doors: Array, wall_mat: Material,
		floor_mat: Material = null, roof_mat: Material = null, with_floor: bool = true, with_roof: bool = true) -> Node3D:
	var r := Node3D.new()
	r.name = nm
	r.position = pos
	parent.add_child(r)
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var t: float = WALL_T
	if with_floor:
		box(r, "Floor", Vector3(w + 2 * t, t, d + 2 * t), Vector3(0, -t * 0.5, 0), floor_mat if floor_mat != null else dark_concrete())
	if with_roof:
		box(r, "Roof", Vector3(w + 2 * t, t, d + 2 * t), Vector3(0, h + t * 0.5, 0), roof_mat if roof_mat != null else wall_mat)
	var by_side: Dictionary = {"n": [], "s": [], "e": [], "w": []}
	for door in doors:
		var dd: Dictionary = door
		var side: String = dd["side"]
		var half: float = (w * 0.5 + t) if (side == "n" or side == "s") else (d * 0.5)
		(by_side[side] as Array).append({"c": float(dd.get("off", 0.0)) + half, "w": dd.get("w", DOOR_W), "h": dd.get("h", DOOR_H)})
	wall(r, "WallN", Vector3(-(w * 0.5 + t), 0, -(d * 0.5 + t * 0.5)), Vector3.RIGHT, w + 2 * t, h, by_side["n"], wall_mat)
	wall(r, "WallS", Vector3(-(w * 0.5 + t), 0, d * 0.5 + t * 0.5), Vector3.RIGHT, w + 2 * t, h, by_side["s"], wall_mat)
	wall(r, "WallW", Vector3(-(w * 0.5 + t * 0.5), 0, -d * 0.5), Vector3.BACK, d, h, by_side["w"], wall_mat)
	wall(r, "WallE", Vector3(w * 0.5 + t * 0.5, 0, -d * 0.5), Vector3.BACK, d, h, by_side["e"], wall_mat)
	return r


## Walkable ramp (slope < 30 deg). Top surface runs exactly from `a` to `b`.
static func ramp(parent: Node, nm: String, a: Vector3, b: Vector3, width: float, mat: Material, thick: float = 0.4) -> Node3D:
	var dir: Vector3 = (b - a)
	var len: float = dir.length()
	var x: Vector3 = dir / len
	var z: Vector3 = x.cross(Vector3.UP).normalized()
	var y: Vector3 = z.cross(x)
	var bas := Basis(x, y, z)
	var centre: Vector3 = (a + b) * 0.5 - y * (thick * 0.5)
	return box(parent, nm, Vector3(len, thick, width), centre, mat, true, bas)


## Solid-block stairs climbing along `dir` (horizontal) from `base` (floor level of the first step's foot).
static func stairs(parent: Node, nm: String, base: Vector3, dir: Vector3, steps: int, rise: float, run: float,
		width: float, mat: Material) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	parent.add_child(holder)
	var d: Vector3 = dir.normalized()
	var bas: Basis = basis_x_along(d)
	for i in steps:
		var hgt: float = rise * float(i + 1)
		var centre: Vector3 = base + d * (run * (float(i) + 0.5)) + Vector3.UP * (hgt * 0.5)
		box(holder, "Step%d" % i, Vector3(run, hgt, width), centre, mat, true, bas)
	return holder


static func railing(parent: Node, nm: String, a: Vector3, b: Vector3, height: float = 1.1, mat: Material = null) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	parent.add_child(holder)
	var m: Material = mat if mat != null else hazard()
	pipe(holder, "TopRail", a + Vector3.UP * height, b + Vector3.UP * height, 0.05, m)
	pipe(holder, "MidRail", a + Vector3.UP * height * 0.5, b + Vector3.UP * height * 0.5, 0.04, steel())
	var n: int = maxi(2, int((b - a).length() / 3.0))
	for i in n + 1:
		var p: Vector3 = a.lerp(b, float(i) / float(n))
		pipe(holder, "Post%d" % i, p, p + Vector3.UP * height, 0.05, steel())
	return holder


## Console desk with a glowing screen. Faces +Z by default.
static func console(parent: Node, nm: String, pos: Vector3, yaw: float = 0.0, screen: Material = null) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	holder.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	parent.add_child(holder)
	box(holder, "Desk", Vector3(2.0, 0.9, 0.8), Vector3(0, 0.45, 0), dark_steel())
	box(holder, "Keys", Vector3(1.7, 0.08, 0.4), Vector3(0, 0.94, 0.12), steel(), false)
	light_strip(holder, "Screen", Vector3(1.7, 0.7, 0.06), Vector3(0, 1.4, -0.2),
			screen if screen != null else glow_cyan(), Basis(Vector3.RIGHT, -0.25))
	return holder


static func crate(parent: Node, nm: String, pos: Vector3, size: Vector3 = Vector3(1.2, 1.0, 1.2), yaw: float = 0.0) -> Node3D:
	return box(parent, nm, size, pos + Vector3(0, size.y * 0.5, 0), rust(), true, Basis(Vector3.UP, yaw))


## Spinning fan / rotor: returns the rotating node (blades along XZ, axis Y).
static func fan(parent: Node, nm: String, pos: Vector3, radius: float, blades: int = 4, basis: Basis = Basis.IDENTITY) -> Node3D:
	var rot := Node3D.new()
	rot.name = nm
	rot.transform = Transform3D(basis, pos)
	parent.add_child(rot)
	cyl(rot, "Hub", radius * 0.14, radius * 0.14, radius * 0.12, Vector3.ZERO, dark_steel(), false, Basis.IDENTITY, 10)
	for i in blades:
		var a: float = TAU * float(i) / float(blades)
		box(rot, "Blade%d" % i, Vector3(radius * 0.85, radius * 0.04, radius * 0.22),
				Vector3(cos(a), 0, sin(a)) * radius * 0.5, steel(), false, Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, 0.35))
	return rot


# ---------------------------------------------------------------------------------------------
# Foundations: always reach below the sampled terrain so nothing floats on slopes
# ---------------------------------------------------------------------------------------------

## ground: Callable(Vector3 local) -> float local terrain y (may be invalid -> flat fallback).
static func _depth_for(ground: Callable, pts: Array, top_y: float, min_depth: float, max_depth: float) -> float:
	var low: float = top_y
	if ground.is_valid():
		for p in pts:
			low = minf(low, float(ground.call(p)))
	return clampf(top_y - (low - 3.0), min_depth, max_depth)


static func prism_mesh(radius: float, sides: int, top_y: float, bottom_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops: Array[Vector3] = []
	var bots: Array[Vector3] = []
	for i in sides:
		var th: float = TAU * (float(i) + 0.5) / float(sides)
		tops.append(Vector3(cos(th) * radius, top_y, sin(th) * radius))
		bots.append(Vector3(cos(th) * radius, bottom_y, sin(th) * radius))
	for i in sides:
		var j: int = (i + 1) % sides
		for v in [Vector3(0, top_y, 0), tops[i], tops[j]]:
			st.add_vertex(v)
		for v in [tops[j], tops[i], bots[i]]:
			st.add_vertex(v)
		for v in [tops[j], bots[i], bots[j]]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Regular-polygon concrete slab with a skirt that extends below every sampled terrain point.
static func foundation(parent: Node, nm: String, radius: float, sides: int, top_y: float, ground: Callable,
		mat: Material = null, min_depth: float = 8.0, max_depth: float = 60.0) -> Node3D:
	var pts: Array = [Vector3.ZERO]
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		pts.append(Vector3(cos(a), 0, sin(a)) * radius)
		pts.append(Vector3(cos(a), 0, sin(a)) * radius * 0.5)
	var depth: float = _depth_for(ground, pts, top_y, min_depth, max_depth)
	var bottom: float = top_y - depth
	var verts := PackedVector3Array()
	for i in sides:
		var th: float = TAU * (float(i) + 0.5) / float(sides)
		verts.append(Vector3(cos(th) * radius, top_y, sin(th) * radius))
		verts.append(Vector3(cos(th) * radius, bottom, sin(th) * radius))
	var shape := ConvexPolygonShape3D.new()
	shape.points = verts
	var holder: Node3D = _body(nm, Transform3D.IDENTITY, shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = prism_mesh(radius, sides, top_y, bottom)
	mi.material_override = mat if mat != null else concrete()
	holder.add_child(mi)
	holder.set_meta("depth", depth)
	holder.set_meta("top_y", top_y)
	parent.add_child(holder)
	return holder


## Rectangular slab (centre x/z, size x/z) with a deep skirt.
static func foundation_box(parent: Node, nm: String, centre: Vector2, size: Vector2, top_y: float, ground: Callable,
		mat: Material = null, min_depth: float = 6.0, max_depth: float = 50.0) -> Node3D:
	var pts: Array = []
	for ix in 5:
		for iz in 5:
			pts.append(Vector3(centre.x + (float(ix) / 4.0 - 0.5) * size.x, 0, centre.y + (float(iz) / 4.0 - 0.5) * size.y))
	var depth: float = _depth_for(ground, pts, top_y, min_depth, max_depth)
	var n: Node3D = box(parent, nm, Vector3(size.x, depth, size.y), Vector3(centre.x, top_y - depth * 0.5, centre.y), mat if mat != null else concrete())
	n.set_meta("depth", depth)
	n.set_meta("top_y", top_y)
	return n


# ---------------------------------------------------------------------------------------------
# Conveyor belts (animated via shaders/conveyor.gdshader)
# ---------------------------------------------------------------------------------------------

## Belt from a to b (a and b are belt-surface endpoints). Returns holder; belt surface has a thin walkable collider.
static func conveyor(parent: Node, nm: String, a: Vector3, b: Vector3, width: float = 1.6, speed: float = 0.6) -> Node3D:
	var d: Vector3 = b - a
	var len: float = d.length()
	var x: Vector3 = d / len
	var z: Vector3 = x.cross(Vector3.UP).normalized()
	var y: Vector3 = z.cross(x)
	var holder: Node3D = _body(nm, Transform3D(Basis(x, y, z), (a + b) * 0.5 - y * 0.05), _flat_shape(len, width))
	var mi := MeshInstance3D.new()
	mi.name = "Belt"
	var q := ArrayMesh.new()
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	var hl: float = len * 0.5
	var hw: float = width * 0.5
	var tiles: float = maxf(len / 2.0, 1.0)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-hl, 0.05, -hw), Vector3(hl, 0.05, -hw), Vector3(hl, 0.05, hw), Vector3(-hl, 0.05, hw)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(0, tiles), Vector2(1, tiles), Vector2(1, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	q.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = q
	mi.material_override = conveyor_material(len, speed)
	holder.add_child(mi)
	# Side rails + supports.
	box(holder, "RailL", Vector3(len, 0.35, 0.12), Vector3(0, 0.12, -hw - 0.06), dark_steel(), false)
	box(holder, "RailR", Vector3(len, 0.35, 0.12), Vector3(0, 0.12, hw + 0.06), dark_steel(), false)
	var n: int = maxi(2, int(len / 6.0))
	for i in n + 1:
		var f: float = float(i) / float(n)
		var wp: Vector3 = a.lerp(b, f)
		if wp.y > 0.7:
			pipe(parent, "%s_Leg%d" % [nm, i], Vector3(wp.x, wp.y - 0.1, wp.z), Vector3(wp.x, 0.0, wp.z), 0.12, dark_steel())
	parent.add_child(holder)
	return holder


static func _flat_shape(len: float, width: float) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(len, 0.1, width)
	return s


# ---------------------------------------------------------------------------------------------
# Blender GLB loading + procedural fallback
# ---------------------------------------------------------------------------------------------

static func compute_aabb(node: Node3D, xf: Transform3D = Transform3D.IDENTITY) -> AABB:
	var out := AABB()
	var has: bool = false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out = xf * (node as MeshInstance3D).get_aabb()
		has = true
	for c in node.get_children():
		if c is Node3D:
			var child: Node3D = c
			var sub: AABB = compute_aabb(child, xf * child.transform)
			if sub.size != Vector3.ZERO:
				out = sub if not has else out.merge(sub)
				has = true
	return out if has else AABB()


static func has_glb(model_id: String) -> bool:
	return ResourceLoader.exists(SURFACE_DIR + (MODELS[model_id]["glb"] as String))


## Places a model whose base is embedded MODEL_EMBED below `pos` and centred on x/z, at the contract size.
## Always adds a StaticBody3D footprint box. meta "source" = "glb" | "procedural".
static func load_model(parent: Node, model_id: String, nm: String, pos: Vector3, yaw: float = 0.0,
		collide: bool = true, collider_scale: float = 0.85) -> Node3D:
	var data: Dictionary = MODELS[model_id]
	var size: Vector3 = data["size"]
	var holder := Node3D.new()
	holder.name = nm
	holder.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	parent.add_child(holder)
	var content := Node3D.new()
	content.name = "Content"
	holder.add_child(content)
	var path: String = SURFACE_DIR + (data["glb"] as String)
	var loaded: bool = false
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path) as PackedScene
		if ps != null:
			var inst: Node = ps.instantiate()
			if inst is Node3D:
				var n3: Node3D = inst
				var aabb: AABB = compute_aabb(n3)
				if aabb.size.y > 0.001:
					var s: float = size.y / aabb.size.y
					n3.scale = Vector3(s, s, s)
					n3.position = Vector3(-(aabb.position.x + aabb.size.x * 0.5) * s, -aabb.position.y * s - MODEL_EMBED,
							-(aabb.position.z + aabb.size.z * 0.5) * s)
					content.add_child(n3)
					loaded = true
				else:
					inst.free()
			else:
				inst.free()
	if loaded:
		holder.set_meta("source", "glb")
		if not glb_loaded.has(model_id):
			glb_loaded.append(model_id)
	else:
		content.position = Vector3(0, -MODEL_EMBED, 0)
		_proc_model(content, model_id, size)
		holder.set_meta("source", "procedural")
		if not procedural_used.has(model_id):
			procedural_used.append(model_id)
	holder.set_meta("height", size.y)
	holder.set_meta("model_id", model_id)
	if collide:
		var sb := StaticBody3D.new()
		sb.name = "Collision"
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var fp := Vector3(size.x * collider_scale, size.y, size.z * collider_scale)
		bs.size = fp
		cs.shape = bs
		cs.position = Vector3(0, fp.y * 0.5 - MODEL_EMBED, 0)
		sb.add_child(cs)
		holder.add_child(sb)
	return holder


static func _proc_model(root: Node3D, id: String, size: Vector3) -> void:
	var st: Material = steel()
	var dk: Material = dark_steel()
	var tr: Material = truss()
	var hz: Material = hazard()
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	match id:
		"extraction_spire_core":
			cyl(root, "BaseDrum", w * 0.5, w * 0.5, 14.0, Vector3(0, 7, 0), dark_concrete(), false, Basis.IDENTITY, 8)
			cyl(root, "Flare", w * 0.34, w * 0.5, 30.0, Vector3(0, 29, 0), st, false, Basis.IDENTITY, 8)
			var shaft_h: float = h * 0.78
			cyl(root, "Shaft", w * 0.07, w * 0.2, shaft_h, Vector3(0, 44 + shaft_h * 0.5 - 7, 0), st, false, Basis.IDENTITY, 8)
			for i in 6:
				var y: float = 40.0 + float(i) * (h * 0.72 / 6.0)
				var r: float = lerpf(w * 0.24, w * 0.09, float(i) / 6.0)
				cyl(root, "Ring%d" % i, r, r, 2.2, Vector3(0, y, 0), hz if i % 2 == 0 else dk, false, Basis.IDENTITY, 8)
			for i in 4:
				var a: float = TAU * float(i) / 4.0 + PI * 0.25
				var dirv := Vector3(cos(a), 0, sin(a))
				beam(root, "Buttress%d" % i, dirv * w * 0.46 + Vector3(0, 2, 0), dirv * w * 0.12 + Vector3(0, 95, 0), 2.6, tr)
			cyl(root, "Mast", 0.3, 1.2, h * 0.14, Vector3(0, h - h * 0.07, 0), st, false, Basis.IDENTITY, 6)
			var core := MeshInstance3D.new()
			core.name = "BeaconCore"
			var sph := SphereMesh.new()
			sph.radius = 2.4
			sph.height = 4.8
			sph.material = glow_amber()
			core.mesh = sph
			core.position = Vector3(0, h - 1.0, 0)
			root.add_child(core)
			add_light(root, Vector3(0, h - 1.0, 0), Color(1.0, 0.55, 0.2), 4.0, 120.0)
		"mining_drill_tower":
			for i in 4:
				var a2: float = TAU * float(i) / 4.0 + PI * 0.25
				var bot := Vector3(cos(a2), 0, sin(a2)) * w * 0.48
				var top := Vector3(cos(a2), 0, sin(a2)) * w * 0.16
				beam(root, "Leg%d" % i, bot, top + Vector3(0, h * 0.92, 0), 0.7, tr)
			for lv in 5:
				var f: float = (float(lv) + 0.5) / 5.0
				var y2: float = h * 0.92 * f
				var rr: float = lerpf(w * 0.48, w * 0.16, f) * 0.7071
				box(root, "Ring%d" % lv, Vector3(rr * 2.0, 0.4, rr * 2.0), Vector3(0, y2, 0), hz if lv % 2 == 0 else tr, false)
			box(root, "Crown", Vector3(w * 0.5, 2.6, w * 0.5), Vector3(0, h - 1.3, 0), dk, false)
			box(root, "Deck", Vector3(w * 0.9, 0.5, w * 0.9), Vector3(0, h * 0.35, 0), st, false)
			light_strip(root, "Beacon", Vector3(0.8, 0.8, 0.8), Vector3(0, h + 0.4, 0), glow_red())
		"ore_crusher_hopper":
			box(root, "Body", Vector3(w * 0.8, h * 0.45, d * 0.85), Vector3(0, h * 0.225, 0), dk, false)
			cyl(root, "Funnel", w * 0.42, w * 0.18, h * 0.4, Vector3(0, h * 0.45 + h * 0.2, 0), rust(), false, Basis.IDENTITY, 4)
			box(root, "Motor", Vector3(w * 0.3, h * 0.3, d * 0.3), Vector3(w * 0.38, h * 0.15, 0), st, false)
			for i in 3:
				box(root, "Hazard%d" % i, Vector3(w * 0.8 + 0.1, 0.5, d * 0.85 + 0.1), Vector3(0, 0.5 + float(i) * 1.6, 0), hz, false)
			box(root, "Chute", Vector3(w * 0.3, 0.8, d * 0.5), Vector3(-w * 0.4, h * 0.2, 0), dk, false, Basis(Vector3.BACK, 0.5))
		"refinery_tower_cluster":
			var heights: Array[float] = [h, h * 0.78, h * 0.6]
			var xs: Array[float] = [-w * 0.28, w * 0.2, 0.0]
			var zs: Array[float] = [-d * 0.1, d * 0.1, d * 0.34]
			for i in 3:
				var rad: float = [w * 0.17, w * 0.14, w * 0.11][i]
				cyl(root, "Tower%d" % i, rad, rad * 1.06, heights[i], Vector3(xs[i], heights[i] * 0.5, zs[i]), st, false, Basis.IDENTITY, 16)
				for b in 3:
					cyl(root, "Band%d_%d" % [i, b], rad * 1.08, rad * 1.08, 0.8, Vector3(xs[i], heights[i] * (0.25 + 0.25 * float(b)), zs[i]), hz, false, Basis.IDENTITY, 16)
			pipe(root, "Link0", Vector3(xs[0], h * 0.7, zs[0]), Vector3(xs[1], h * 0.6, zs[1]), 0.5, dk)
			pipe(root, "Link1", Vector3(xs[1], h * 0.45, zs[1]), Vector3(xs[2], h * 0.42, zs[2]), 0.45, rust())
			cyl(root, "Flare", 0.4, 0.4, h * 0.3, Vector3(xs[0] - w * 0.3, h * 0.15, zs[0]), dk, false, Basis.IDENTITY, 6)
			light_strip(root, "FlareTip", Vector3(0.9, 0.9, 0.9), Vector3(xs[0] - w * 0.3, h * 0.31, zs[0]), glow_amber())
		"storage_silo_bank":
			for i in 3:
				var cx: float = (float(i) - 1.0) * w * 0.34
				cyl(root, "Silo%d" % i, w * 0.15, w * 0.15, h * 0.78, Vector3(cx, h * 0.39, 0), st, false, Basis.IDENTITY, 20)
				cyl(root, "Cap%d" % i, 0.4, w * 0.15, h * 0.2, Vector3(cx, h * 0.78 + h * 0.1, 0), dk, false, Basis.IDENTITY, 20)
				cyl(root, "Band%d" % i, w * 0.155, w * 0.155, 0.7, Vector3(cx, h * 0.3, 0), hz, false, Basis.IDENTITY, 20)
			box(root, "Catwalk", Vector3(w * 0.95, 0.3, 1.4), Vector3(0, h * 0.7, d * 0.38), dk, false)
			box(root, "Frame", Vector3(w * 0.95, 1.2, d * 0.2), Vector3(0, 0.6, d * 0.4), dark_concrete(), false)
		"launch_service_tower":
			for i in 4:
				var a3: float = TAU * float(i) / 4.0 + PI * 0.25
				var dv := Vector3(cos(a3), 0, sin(a3))
				beam(root, "Leg%d" % i, dv * w * 0.34, dv * w * 0.2 + Vector3(0, h, 0), 0.8, tr)
			for lv in 8:
				var f2: float = (float(lv) + 0.5) / 8.0
				var rr2: float = lerpf(w * 0.34, w * 0.2, f2) * 0.7071
				box(root, "Ring%d" % lv, Vector3(rr2 * 2.0, 0.35, rr2 * 2.0), Vector3(0, h * f2, 0), hz if lv % 3 == 0 else tr, false)
			for lv in 4:
				box(root, "Platform%d" % lv, Vector3(w * 0.75, 0.4, w * 0.75), Vector3(0, h * (0.2 + 0.2 * float(lv)), 0), dk, false)
			box(root, "CraneArm", Vector3(w * 1.0, 1.4, 1.4), Vector3(w * 0.4, h - 1.0, 0), hz, false)
			pipe(root, "Umbilical", Vector3(w * 0.45, h * 0.8, 0), Vector3(w * 0.9, h * 0.3, 0), 0.25, rust())
			light_strip(root, "Beacon", Vector3(0.9, 0.9, 0.9), Vector3(0, h + 0.5, 0), glow_red())
		"hab_module_derelict":
			cyl(root, "Hull", d * 0.5, d * 0.5, w, Vector3(0, d * 0.5, 0), st, false, Basis(Vector3.BACK, PI * 0.5), 16)
			box(root, "Airlock", Vector3(3.0, h * 0.9, 3.0), Vector3(w * 0.5 + 1.0, h * 0.45, 0), dk, false)
			for i in 4:
				light_strip(root, "Window%d" % i, Vector3(1.2, 0.6, 0.1), Vector3(-w * 0.3 + float(i) * 2.0, d * 0.5 + 0.8, d * 0.5 - 0.12), glow_amber())
			box(root, "Skirt", Vector3(w * 0.9, 0.6, d * 0.9), Vector3(0, 0.3, 0), dark_concrete(), false)
		_:  # power_pylon_tower
			for i in 4:
				var a4: float = TAU * float(i) / 4.0 + PI * 0.25
				var dv2 := Vector3(cos(a4), 0, sin(a4))
				beam(root, "Leg%d" % i, dv2 * w * 0.42, dv2 * w * 0.1 + Vector3(0, h * 0.78, 0), 0.22, tr)
			for lv in 5:
				var f3: float = (float(lv) + 0.5) / 5.0 * 0.78
				var rr3: float = lerpf(w * 0.42, w * 0.1, f3 / 0.78) * 0.7071
				box(root, "Brace%d" % lv, Vector3(rr3 * 2.0, 0.15, rr3 * 2.0), Vector3(0, h * f3, 0), tr, false)
			for lv in 2:
				var yy: float = h * (0.82 + 0.1 * float(lv))
				box(root, "Arm%d" % lv, Vector3(w * 2.4, 0.3, 0.3), Vector3(0, yy, 0), st, false)
				for sgn in [-1.0, 1.0]:
					cyl(root, "Insulator%d_%d" % [lv, int(sgn)], 0.12, 0.12, 1.2, Vector3(w * 1.1 * float(sgn), yy - 0.7, 0), _std("insulator", Color(0.6, 0.65, 0.6), 0.1, 0.4), false, Basis.IDENTITY, 6)
			cyl(root, "Peak", 0.05, 0.25, h * 0.14, Vector3(0, h * 0.93, 0), st, false, Basis.IDENTITY, 6)


# ---------------------------------------------------------------------------------------------
# Animation helpers (driven by each facility's tick())
# ---------------------------------------------------------------------------------------------

## kinds: spin (axis, speed rad/s), piston (axis, amp, speed, base_pos), lift (amp, speed, base_pos), blink (period).
static func register_anim(list: Array, node: Node3D, kind: String, axis: Vector3 = Vector3.UP,
		speed: float = 1.0, amp: float = 1.0, phase: float = 0.0) -> void:
	list.append({"node": node, "kind": kind, "axis": axis, "speed": speed, "amp": amp, "phase": phase, "base": node.position})


static func tick_anims(list: Array, delta: float, time: float) -> void:
	for a in list:
		var dd: Dictionary = a
		var n: Node3D = dd["node"]
		if not is_instance_valid(n):
			continue
		var kind: String = dd["kind"]
		match kind:
			"spin":
				n.rotate_object_local(dd["axis"], float(dd["speed"]) * delta)
			"piston", "lift":
				var axis: Vector3 = dd["axis"]
				n.position = (dd["base"] as Vector3) + axis * (sin(time * float(dd["speed"]) + float(dd["phase"])) * float(dd["amp"]))
			"blink":
				n.visible = fmod(time + float(dd["phase"]), float(dd["speed"])) < float(dd["speed"]) * 0.5
			"flicker":
				var on: bool = sin(time * 23.0 + float(dd["phase"])) * sin(time * 7.3) > -0.4
				n.visible = on
