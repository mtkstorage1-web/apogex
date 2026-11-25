class_name InfrastructureNetwork
extends Node3D
## Deterministic, terrain-sampled infrastructure across VESPER-9: industrial highways between the five
## facilities, two Crimson Canyon viaducts, elevated pipelines and a high-voltage power corridor.
## Everything is placed in planet space and re-based on floating origin shifts via apply_origin().

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const FBU = preload("res://scripts/environment/FacilityBuilderUtils.gd")

const ROAD_WIDTH := 8.0
const ROAD_CROWN := 0.12
const SKIRT_DEPTH := 3.5
const ROAD_STEP := 12.0
const ROAD_CHUNK := 16
const PAD_CLEARANCE := 62.0
const PIPE_STEP := 24.0
const PIPE_HEIGHT := 3.0
const PYLON_SPACING := 150.0

## lat/lon (deg) of each facility pad.
const SITES: Dictionary = {
	"extraction": Vector2(0.0, 0.0), "mining": Vector2(18.0, 0.0), "refinery": Vector2(0.0, 20.0),
	"launch": Vector2(-18.0, 0.0), "settlement": Vector2(0.0, -20.0),
}
const BRIDGES: Array = [
	{"name": "Crimson Canyon Bridge Alpha", "lat": 10.0, "lon": -13.8, "length": 160.0},
	{"name": "Crimson Canyon Bridge Beta", "lat": -10.0, "lon": 13.8, "length": 160.0},
]

var noise: TerrainNoiseStack
var planet_radius: float = 12000.0
var current_origin: Vector3 = Vector3.ZERO
var roads: Array[Dictionary] = []
var bridges: Array[Dictionary] = []
var pipelines: Array[Dictionary] = []
var power_lines: Array[Dictionary] = []
var pylon_count: int = 0
var pillar_count: int = 0
var road_sample_points: Array[Vector3] = []
var bridge_test_points: Array[Vector3] = []
## {bottom: planet pos of pier foot, ground: sampled terrain pos below it}
var pier_records: Array[Dictionary] = []
var _anchored: Array[Dictionary] = []
var _road_mat: StandardMaterial3D
var _skirt_mat: StandardMaterial3D
var _cable_mat: StandardMaterial3D


func setup(p_noise: TerrainNoiseStack, p_radius: float) -> void:
	noise = p_noise
	planet_radius = p_radius
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_anchored.clear()
	roads.clear()
	bridges.clear()
	pipelines.clear()
	power_lines.clear()
	road_sample_points.clear()
	bridge_test_points.clear()
	pier_records.clear()
	pylon_count = 0
	pillar_count = 0
	if noise == null:
		return
	_make_materials()
	_build_roads()
	for i in BRIDGES.size():
		_build_bridge(i)
	_build_pipelines()
	_build_power_lines()


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	for a in _anchored:
		var n: Node3D = a["node"]
		if is_instance_valid(n):
			n.position = (a["base"] as Vector3) - current_origin


func get_bridge_test_points() -> Array[Vector3]:
	return bridge_test_points


func get_road_sample_points() -> Array[Vector3]:
	return road_sample_points


func get_summary() -> Dictionary:
	return {"roads": roads.size(), "bridges": bridges.size(), "pipelines": pipelines.size(), "power_lines": power_lines.size(),
			"pylons": pylon_count, "pillars": pillar_count, "road_samples": road_sample_points.size(), "bridge_points": bridge_test_points.size()}


static func site_dir(key: String) -> Vector3:
	var ll: Vector2 = SITES[key]
	return Transforms.lat_lon_to_unit_dir(deg_to_rad(ll.x), deg_to_rad(ll.y))


## Deterministic viaduct geometry. deck[i] = planet position of the deck top centreline.
static func compute_bridge_layout(p_noise: TerrainNoiseStack, radius: float, idx: int) -> Dictionary:
	var def: Dictionary = BRIDGES[idx]
	var uc: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(float(def["lat"])), deg_to_rad(float(def["lon"])))
	var tb: Basis = Transforms.surface_tangent_basis(uc)
	var length: float = def["length"]
	var n: int = int(ceil(length / 8.0))
	var dirs: Array[Vector3] = []
	var surf: Array[Vector3] = []
	var line_r := PackedFloat32Array()
	for i in n + 1:
		var off: float = (float(i) / float(n) - 0.5) * length
		var u: Vector3 = (uc + tb.x * (off / radius)).normalized()
		dirs.append(u)
		surf.append(p_noise.sample_surface_position(u))
	var r0: float = surf[0].length()
	var r1: float = surf[n].length()
	var shift: float = 0.0
	for i in n + 1:
		var t: float = float(i) / float(n)
		var rl: float = lerpf(r0, r1, t)
		line_r.append(rl)
		shift = maxf(shift, surf[i].length() + 2.2 - rl)
	var deck: Array[Vector3] = []
	for i in n + 1:
		deck.append(dirs[i] * (line_r[i] + shift))
	return {"name": def["name"], "count": n, "dirs": dirs, "surface": surf, "deck": deck, "center": deck[n / 2], "tb": tb, "center_dir": uc}


func _make_materials() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var c := Color(0.11, 0.11, 0.12)
			if x < 2 or x > 61:
				c = Color(0.85, 0.85, 0.8)
			elif (x == 31 or x == 32) and (y % 32) < 18:
				c = Color(0.95, 0.72, 0.1)
			elif ((x * 7 + y * 13) % 11) == 0:
				c = Color(0.15, 0.15, 0.16)
			img.set_pixel(x, y, c)
	_road_mat = StandardMaterial3D.new()
	_road_mat.albedo_texture = ImageTexture.create_from_image(img)
	_road_mat.roughness = 0.92
	_road_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_skirt_mat = StandardMaterial3D.new()
	_skirt_mat.albedo_color = Color(0.3, 0.27, 0.25)
	_skirt_mat.roughness = 1.0
	_skirt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cable_mat = StandardMaterial3D.new()
	_cable_mat.albedo_color = Color(0.05, 0.05, 0.06)
	_cable_mat.metallic = 0.6
	_cable_mat.roughness = 0.5
	_cable_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


# ---------------------------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------------------------

static func _slerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	var th: float = a.angle_to(b)
	if th < 1.0e-6:
		return a
	return (a * sin((1.0 - t) * th) + b * sin(t * th)) / sin(th)


## Unit directions along the great circle a->b, skipping `start_m` / `end_m` metres at the ends.
func _arc_dirs(a: Vector3, b: Vector3, start_m: float, end_m: float, step: float) -> Array[Vector3]:
	var th: float = a.angle_to(b)
	var arc: float = th * planet_radius
	var s0: float = start_m
	var s1: float = arc - end_m
	var n: int = maxi(1, int(ceil((s1 - s0) / step)))
	var out: Array[Vector3] = []
	for k in n + 1:
		var s: float = lerpf(s0, s1, float(k) / float(n))
		out.append(_slerp(a, b, s / arc).normalized())
	return out


func _frame(dirs: Array[Vector3], i: int) -> Array[Vector3]:
	var u: Vector3 = dirs[i]
	var t: Vector3 = (dirs[mini(i + 1, dirs.size() - 1)] - dirs[maxi(i - 1, 0)])
	t -= u * t.dot(u)
	t = t.normalized()
	return [t, u, t.cross(u).normalized()]


func _offset_dir(dirs: Array[Vector3], i: int, lateral: float) -> Vector3:
	var fr: Array[Vector3] = _frame(dirs, i)
	return (dirs[i] + fr[2] * (lateral / planet_radius)).normalized()


func _chunk_node(nm: String, base: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = base - current_origin
	add_child(n)
	_anchored.append({"node": n, "base": base})
	return n


func _tri(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, up: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	for v in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(up)
		st.set_uv(v[1])
		st.add_vertex(v[0])
	faces.append(a)
	faces.append(b)
	faces.append(c)


# ---------------------------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------------------------

func _build_roads() -> void:
	var ex: Vector3 = site_dir("extraction")
	var layout: Array = [
		["NorthHighway", ex, site_dir("mining"), PAD_CLEARANCE, PAD_CLEARANCE],
		["EastHighway", ex, site_dir("refinery"), PAD_CLEARANCE, PAD_CLEARANCE],
		["SouthHighway", ex, site_dir("launch"), PAD_CLEARANCE, PAD_CLEARANCE],
		["WestHighway", ex, site_dir("settlement"), PAD_CLEARANCE, PAD_CLEARANCE],
	]
	for l in layout:
		var dirs: Array[Vector3] = _arc_dirs(l[1], l[2], l[3], l[4], ROAD_STEP)
		_build_road(l[0], dirs)
	# Canyon-crossing branch: Terminus Basin -> Bridge Alpha (east abutment), plus a stub past the west end.
	var bl: Dictionary = compute_bridge_layout(noise, planet_radius, 0)
	var bdirs: Array[Vector3] = bl["dirs"]
	var east_end: Vector3 = bdirs[bdirs.size() - 1]
	var west_end: Vector3 = bdirs[0]
	_build_road("CanyonBranch", _arc_dirs(ex, east_end, PAD_CLEARANCE, 16.0, ROAD_STEP))
	var stub_end: Vector3 = (west_end + Transforms.surface_tangent_basis(west_end).x * (-160.0 / planet_radius)).normalized()
	_build_road("CanyonStub", _arc_dirs(west_end, stub_end, 16.0, 0.0, ROAD_STEP))


func _build_road(nm: String, dirs: Array[Vector3]) -> void:
	var n: int = dirs.size()
	var cs: Array[Vector3] = []
	var ls: Array[Vector3] = []
	var rs: Array[Vector3] = []
	var los: Array[Vector3] = []
	var ros: Array[Vector3] = []
	var half: float = ROAD_WIDTH * 0.5
	for i in n:
		var fr: Array[Vector3] = _frame(dirs, i)
		var u: Vector3 = fr[1]
		var rt: Vector3 = fr[2]
		var c: Vector3 = noise.sample_surface_position(u) + u * ROAD_CROWN
		var l: Vector3 = noise.sample_surface_position(_offset_dir(dirs, i, -half)) + u * ROAD_CROWN
		var r: Vector3 = noise.sample_surface_position(_offset_dir(dirs, i, half)) + u * ROAD_CROWN
		cs.append(c)
		ls.append(l)
		rs.append(r)
		los.append(l - rt * 1.2 - u * SKIRT_DEPTH)
		ros.append(r + rt * 1.2 - u * SKIRT_DEPTH)
		road_sample_points.append(c)
	var chunk_i: int = 0
	var i0: int = 0
	var total_faces: int = 0
	while i0 < n - 1:
		var i1: int = mini(i0 + ROAD_CHUNK, n - 1)
		var base: Vector3 = cs[i0]
		var node: Node3D = _chunk_node("%s_%d" % [nm, chunk_i], base)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sk := SurfaceTool.new()
		sk.begin(Mesh.PRIMITIVE_TRIANGLES)
		var faces := PackedVector3Array()
		for j in range(i0, i1):
			var up: Vector3 = dirs[j]
			var v0: float = float(j) * ROAD_STEP / 8.0
			var v1: float = float(j + 1) * ROAD_STEP / 8.0
			var L0: Vector3 = ls[j] - base
			var C0: Vector3 = cs[j] - base
			var R0: Vector3 = rs[j] - base
			var L1: Vector3 = ls[j + 1] - base
			var C1: Vector3 = cs[j + 1] - base
			var R1: Vector3 = rs[j + 1] - base
			_tri(st, faces, L0, C0, C1, up, Vector2(0, v0), Vector2(0.5, v0), Vector2(0.5, v1))
			_tri(st, faces, L0, C1, L1, up, Vector2(0, v0), Vector2(0.5, v1), Vector2(0, v1))
			_tri(st, faces, C0, R0, R1, up, Vector2(0.5, v0), Vector2(1, v0), Vector2(1, v1))
			_tri(st, faces, C0, R1, C1, up, Vector2(0.5, v0), Vector2(1, v1), Vector2(0.5, v1))
			var LO0: Vector3 = los[j] - base
			var LO1: Vector3 = los[j + 1] - base
			var RO0: Vector3 = ros[j] - base
			var RO1: Vector3 = ros[j + 1] - base
			_tri(sk, faces, LO0, L0, L1, up, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			_tri(sk, faces, LO0, L1, LO1, up, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			_tri(sk, faces, R0, RO0, RO1, up, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			_tri(sk, faces, R0, RO1, R1, up, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var mesh := ArrayMesh.new()
		st.commit(mesh)
		sk.commit(mesh)
		mesh.surface_set_material(0, _road_mat)
		mesh.surface_set_material(1, _skirt_mat)
		var mi := MeshInstance3D.new()
		mi.name = "Ribbon"
		mi.mesh = mesh
		node.add_child(mi)
		var sb := StaticBody3D.new()
		sb.name = "RoadCollision"
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cshape := ConcavePolygonShape3D.new()
		cshape.backface_collision = true
		cshape.set_faces(faces)
		var col := CollisionShape3D.new()
		col.shape = cshape
		sb.add_child(col)
		node.add_child(sb)
		total_faces += faces.size() / 3
		chunk_i += 1
		i0 = i1
	roads.append({"name": nm, "stations": n, "chunks": chunk_i, "length": float(n - 1) * ROAD_STEP, "triangles": total_faces})


# ---------------------------------------------------------------------------------------------
# Bridges
# ---------------------------------------------------------------------------------------------

func _build_bridge(idx: int) -> void:
	var lay: Dictionary = compute_bridge_layout(noise, planet_radius, idx)
	var n: int = lay["count"]
	var deck: Array[Vector3] = lay["deck"]
	var surf: Array[Vector3] = lay["surface"]
	var dirs: Array[Vector3] = lay["dirs"]
	var tb: Basis = lay["tb"]
	var base: Vector3 = lay["center"]
	var inv: Basis = tb.inverse()
	var root := Node3D.new()
	root.name = "Bridge%d" % idx
	root.transform = Transform3D(tb, base - current_origin)
	add_child(root)
	_anchored.append({"node": root, "base": base})
	var steel: Material = FBU.steel()
	var conc: Material = FBU.concrete()
	var loc: Array[Vector3] = []
	for i in n + 1:
		loc.append(inv * (deck[i] - base))
		bridge_test_points.append(deck[i])
	var deck_w: float = 9.0
	for i in n:
		var a: Vector3 = loc[i]
		var b: Vector3 = loc[i + 1]
		var d: Vector3 = b - a
		var bas: Basis = FBU.basis_x_along(d)
		var mid: Vector3 = (a + b) * 0.5
		var seg: Node3D = FBU.box(root, "Deck%d" % i, Vector3(d.length() + 0.12, 1.0, deck_w), mid - bas.y * 0.5, FBU.dark_concrete(), true, bas)
		seg.set_meta("bridge_deck", true)
		bridge_test_points.append(base + tb * mid)
		for s in [-1.0, 1.0]:
			FBU.box(root, "Guardrail%d_%d" % [i, int(s)], Vector3(d.length(), 1.1, 0.25), mid + bas.z * (deck_w * 0.5 - 0.15) * s + bas.y * 0.55, FBU.hazard() if i % 2 == 0 else steel, true, bas)
			FBU.box(root, "TrussTop%d_%d" % [i, int(s)], Vector3(d.length(), 0.3, 0.3), mid + bas.z * (deck_w * 0.5 + 0.1) * s + bas.y * 4.2, steel, false, bas)
			FBU.box(root, "TrussPost%d_%d" % [i, int(s)], Vector3(0.3, 3.2, 0.3), a + bas.z * (deck_w * 0.5 + 0.1) * s + bas.y * 2.4, steel, false, bas)
			var off_z: Vector3 = bas.z * (deck_w * 0.5 + 0.1) * s
			var p0: Vector3 = a + off_z + bas.y * (0.8 if i % 2 == 0 else 4.0)
			var p1: Vector3 = b + off_z + bas.y * (4.0 if i % 2 == 0 else 0.8)
			FBU.beam(root, "Diagonal%d_%d" % [i, int(s)], p0, p1, 0.22, steel, false)
		FBU.box(root, "Girder%d" % i, Vector3(d.length(), 0.8, 1.0), mid - bas.y * 1.4, steel, false, bas)
	# Piers: from the deck underside all the way into the ground below (never floating).
	for i in n + 1:
		if i % 3 != 0 and i != n:
			continue
		var gp: Vector3 = inv * (surf[i] - base)
		var top_y: float = loc[i].y - 1.0
		var bottom_y: float = gp.y - 3.0
		var hgt: float = top_y - bottom_y
		if hgt < 1.0:
			continue
		FBU.box(root, "Pier%d" % i, Vector3(2.6, hgt, 6.0), Vector3(loc[i].x, bottom_y + hgt * 0.5, loc[i].z), conc)
		FBU.box(root, "PierFoot%d" % i, Vector3(4.2, 1.4, 7.6), Vector3(loc[i].x, bottom_y + 0.7, loc[i].z), FBU.dark_concrete())
		FBU.box(root, "PierCap%d" % i, Vector3(3.4, 0.8, 8.4), Vector3(loc[i].x, top_y - 0.4, loc[i].z), steel, false)
		pier_records.append({"bottom": base + tb * Vector3(loc[i].x, bottom_y, loc[i].z), "ground": surf[i], "deck": deck[i]})
	# Approach ramps down to the surrounding terrain at both ends.
	for end in [0, n]:
		var sgn: float = -1.0 if end == 0 else 1.0
		var e: Vector3 = loc[end]
		var far_dir: Vector3 = (dirs[end] + tb.x * sgn * (14.0 / planet_radius)).normalized()
		var far_loc: Vector3 = inv * (noise.sample_surface_position(far_dir) - base) + Vector3(0, 0.12, 0)
		if e.y - far_loc.y > 0.3:
			FBU.ramp(root, "Approach%d" % end, far_loc, e, deck_w - 1.0, FBU.dark_concrete())
	bridges.append({"name": lay["name"], "spans": n, "deck_points": n + 1, "piers": pier_records.size()})


# ---------------------------------------------------------------------------------------------
# Pipelines (MultiMesh)
# ---------------------------------------------------------------------------------------------

func _build_pipelines() -> void:
	var ex: Vector3 = site_dir("extraction")
	_build_pipeline("RefineryPipeline", ex, site_dir("refinery"), 11.0)
	_build_pipeline("MiningPipeline", ex, site_dir("mining"), 11.0)


func _build_pipeline(nm: String, a: Vector3, b: Vector3, lateral: float) -> void:
	var dirs: Array[Vector3] = _arc_dirs(a, b, PAD_CLEARANCE + 6.0, PAD_CLEARANCE + 6.0, PIPE_STEP)
	var n: int = dirs.size()
	var tops: Array[Vector3] = []
	var feet: Array[Vector3] = []
	var ups: Array[Vector3] = []
	for i in n:
		var u: Vector3 = _offset_dir(dirs, i, lateral)
		var s: Vector3 = noise.sample_surface_position(u)
		ups.append(u)
		feet.append(s - u * 1.5)
		tops.append(s + u * PIPE_HEIGHT)
	var base: Vector3 = tops[0]
	var node: Node3D = _chunk_node(nm, base)
	var pipe_xf: Array[Transform3D] = []
	var band_xf: Array[Transform3D] = []
	var pillar_xf: Array[Transform3D] = []
	for i in n:
		var hgt: float = (tops[i] - feet[i]).length()
		var pb: Basis = FBU.basis_y_to(ups[i]) * Basis.from_scale(Vector3(0.9, hgt, 0.9))
		pillar_xf.append(Transform3D(pb, (feet[i] + tops[i]) * 0.5 - base))
		if i < n - 1:
			var d: Vector3 = tops[i + 1] - tops[i]
			var pbasis: Basis = FBU.basis_y_to(d) * Basis.from_scale(Vector3(1, d.length(), 1))
			pipe_xf.append(Transform3D(pbasis, (tops[i] + tops[i + 1]) * 0.5 - base))
			var bb: Basis = FBU.basis_y_to(d) * Basis.from_scale(Vector3(1, 1, 1))
			band_xf.append(Transform3D(bb, (tops[i] + tops[i + 1]) * 0.5 - base))
			if i % 5 == 2:
				# Expansion loop: up, across, down.
				var up: Vector3 = ups[i]
				var mid: Vector3 = (tops[i] + tops[i + 1]) * 0.5
				var h2: float = 3.2
				var side: Vector3 = d.normalized() * 3.0
				var pts: Array[Vector3] = [mid - side, mid - side + up * h2, mid + side + up * h2, mid + side]
				for k in 3:
					var dd: Vector3 = pts[k + 1] - pts[k]
					var lb: Basis = FBU.basis_y_to(dd) * Basis.from_scale(Vector3(1, dd.length(), 1))
					pipe_xf.append(Transform3D(lb, (pts[k] + pts[k + 1]) * 0.5 - base))
	pillar_count += n
	_add_multimesh(node, "Pipes", _unit_cylinder(0.55, 1.0), FBU.steel(), pipe_xf)
	_add_multimesh(node, "HazardBands", _unit_cylinder(0.68, 0.9), FBU.hazard(), band_xf)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_add_multimesh(node, "Pillars", bm, FBU.concrete(), pillar_xf)
	pipelines.append({"name": nm, "pillars": n, "segments": pipe_xf.size()})


func _unit_cylinder(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 1
	return m


func _add_multimesh(parent: Node3D, nm: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)


# ---------------------------------------------------------------------------------------------
# Power lines
# ---------------------------------------------------------------------------------------------

func _build_power_lines() -> void:
	var ex: Vector3 = site_dir("extraction")
	_build_power_line("SettlementPowerLine", site_dir("settlement"), ex, -15.0)
	_build_power_line("LaunchPowerLine", site_dir("launch"), ex, -15.0)


func _build_power_line(nm: String, a: Vector3, b: Vector3, lateral: float) -> void:
	var dirs: Array[Vector3] = _arc_dirs(a, b, PAD_CLEARANCE + 10.0, PAD_CLEARANCE + 10.0, PYLON_SPACING)
	var n: int = dirs.size()
	var node_bases: Array[Vector3] = []
	var attach: Array = []
	var line_root := Node3D.new()
	line_root.name = nm
	add_child(line_root)
	for i in n:
		var u: Vector3 = _offset_dir(dirs, i, lateral)
		var fr: Array[Vector3] = _frame(dirs, i)
		var surf: Vector3 = noise.sample_surface_position(u)
		var bas := Basis(fr[2], u, fr[2].cross(u).normalized())
		var holder := Node3D.new()
		holder.name = "PylonAnchor%d" % i
		line_root.add_child(holder)
		var base: Vector3 = surf - u * 0.3
		holder.transform = Transform3D(bas, base - current_origin)
		_anchored.append({"node": holder, "base": base})
		FBU.load_model(holder, "power_pylon_tower", "Pylon%d" % i, Vector3.ZERO)
		node_bases.append(base)
		var pts: Array[Vector3] = []
		for lvl in [16.7, 18.9]:
			for s in [-1.0, 1.0]:
				pts.append(base + bas * Vector3(6.6 * s, lvl, 0))
		attach.append({"pts": pts, "up": u})
		pylon_count += 1
	# Catenary cables as one merged mesh.
	var cbase: Vector3 = (attach[0]["pts"] as Array)[0]
	var cnode: Node3D = _chunk_node(nm + "_Cables", cbase)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spans: int = 0
	for i in n - 1:
		var pa: Array = attach[i]["pts"]
		var pb: Array = attach[i + 1]["pts"]
		var up: Vector3 = attach[i]["up"]
		for c in 4:
			var prev: Vector3 = (pa[c] as Vector3) - cbase
			for j in range(1, 9):
				var t: float = float(j) / 8.0
				var p: Vector3 = ((pa[c] as Vector3).lerp(pb[c], t)) - up * (4.0 * 4.0 * t * (1.0 - t)) - cbase
				_cable_quad(st, prev, p, up)
				prev = p
		spans += 1
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _cable_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Cables"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cnode.add_child(mi)
	power_lines.append({"name": nm, "pylons": n, "spans": spans})


func _cable_quad(st: SurfaceTool, a: Vector3, b: Vector3, up: Vector3) -> void:
	var d: Vector3 = (b - a).normalized()
	var side: Vector3 = d.cross(up).normalized() * 0.07
	var v: Vector3 = up * 0.07
	for pair in [[side, -side], [v, -v]]:
		var o1: Vector3 = pair[0]
		var o2: Vector3 = pair[1]
		for p in [a + o1, a + o2, b + o2, a + o1, b + o2, b + o1]:
			st.set_normal(up)
			st.add_vertex(p)
