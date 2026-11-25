class_name ModularKitBuilder
extends RefCounted
## APOGEX mothership modular kit: the 23 reusable Part 7.2 pieces on a 4 m snapping grid, faction palettes
## (HELION / CINDER), solid StaticBody3D collision (layer 1) and GLB-or-procedural prop loading.

const GRID := 4.0
const CORRIDOR_W := 8.0
const CORRIDOR_H := 6.0

const CATALOG: PackedStringArray = [
	"Wall_2m", "Wall_4m", "Wall_8m", "Floor_4x4", "Floor_8x8", "Ceiling_4x4",
	"Corridor_Straight", "Corridor_Corner", "Corridor_TJunction", "Corridor_Cross",
	"Door_Small", "Door_Large", "Hangar_Door", "Support_Column", "Pipe_Straight", "Pipe_Elbow",
	"Cable_Tray", "Vent_Unit", "Lighting_Module", "Rail_Module", "Stair_Module", "Ramp_Module", "Window_Module",
]

const MODEL_DIR := "res://assets/models/apogex/mothership/"
## key -> {glb, size (x, y=height, z)} : exact Blender export dimensions, grounded at Y=0.
const PROPS: Dictionary = {
	"reactor_core": {"glb": "reactor_core_assembly.glb", "size": Vector3(16, 22, 16)},
	"holotable": {"glb": "command_holotable.glb", "size": Vector3(8, 1.6, 5)},
	"gantry_crane": {"glb": "hangar_gantry_crane.glb", "size": Vector3(26, 14, 8)},
	"shuttle": {"glb": "spacecraft_docked_shuttle.glb", "size": Vector3(12, 5.2, 18)},
	"fabrication_rig": {"glb": "fabrication_rig.glb", "size": Vector3(6, 4.2, 4)},
	"cargo_rack": {"glb": "cargo_container_rack.glb", "size": Vector3(10, 5.8, 4.5)},
}

const PALETTES: Dictionary = {
	"helion": {
		"hull": Color("E6EBF0"), "trim": Color("162A4A"), "metal": Color("8C97A4"), "accent": Color("22E5FF"),
		"floor": Color("5E6A78"), "warn": Color("22E5FF"), "dark": Color("0D1626"), "alt": Color("162A4A"),
	},
	"cinder": {
		"hull": Color("1D2024"), "trim": Color("484C52"), "metal": Color("484C52"), "accent": Color("FF6A1A"),
		"floor": Color("2A2D32"), "warn": Color("C85216"), "dark": Color("101214"), "alt": Color("8C1D18"),
	},
}

static var glb_loaded: Array[String] = []
static var procedural_used: Array[String] = []
static var _mat_cache: Dictionary = {}


static func palette(faction: String) -> Dictionary:
	return PALETTES.get(faction.to_lower(), PALETTES["helion"])


static func material(color: Color, metallic: float = 0.3, rough: float = 0.6, emission: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s_%.2f_%.2f_%.2f" % [color.to_html(true), metallic, rough, emission]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mat_cache[key] = m
	return m


static func glass_material(tint: Color, alpha: float = 0.16) -> StandardMaterial3D:
	var key: String = "glass_%s_%.2f" % [tint.to_html(true), alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.1
	m.roughness = 0.05
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m


# ---------------------------------------------------------------------------------------------
# Primitive helpers (shared with MothershipInterior / MothershipController)
# ---------------------------------------------------------------------------------------------

## Box with optional StaticBody3D collision (layer 1). Returns the holder node (StaticBody3D or Node3D).
static func box(parent: Node, size: Vector3, pos: Vector3, mat: Material, collide: bool = true, node_name: String = "") -> Node3D:
	var holder: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		holder = body
	else:
		holder = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	holder.add_child(mi)
	holder.position = pos
	if node_name != "":
		holder.name = node_name
	parent.add_child(holder)
	return holder


## Cylinder along Y (axis = "y"), X or Z. Collision is a matching cylinder / box.
static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, mat: Material, collide: bool = true, axis: String = "y", node_name: String = "") -> Node3D:
	var holder: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		body.add_child(cs)
		holder = body
	else:
		holder = Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	holder.add_child(mi)
	holder.position = pos
	if axis == "x":
		holder.rotation = Vector3(0, 0, PI * 0.5)
	elif axis == "z":
		holder.rotation = Vector3(PI * 0.5, 0, 0)
	if node_name != "":
		holder.name = node_name
	parent.add_child(holder)
	return holder


static func wedge(parent: Node, width: float, run: float, rise: float, mat: Material, node_name: String = "") -> Node3D:
	## Solid wedge climbing toward +Z (x centred): collision is one convex hull so walking never snags on steps.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var hw: float = width * 0.5
	var pts := PackedVector3Array([
		Vector3(-hw, 0, 0), Vector3(hw, 0, 0), Vector3(-hw, 0, run), Vector3(hw, 0, run),
		Vector3(-hw, rise, run), Vector3(hw, rise, run),
		Vector3(-hw, -0.3, 0), Vector3(hw, -0.3, 0), Vector3(-hw, -0.3, run), Vector3(hw, -0.3, run),
	])
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	body.add_child(cs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri: Array = [
		[0, 5, 1], [0, 4, 5], # slope (top)  (placeholder winding fixed by cull_disabled)
		[0, 2, 4], [1, 5, 3], # sides
		[2, 3, 5], [2, 5, 4], # back
		[0, 1, 3], [0, 3, 2], # bottom
	]
	for t in tri:
		for idx in t:
			st.add_vertex(pts[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var wm := StandardMaterial3D.new()
	wm.albedo_color = (mat as StandardMaterial3D).albedo_color if mat is StandardMaterial3D else Color.GRAY
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = wm
	mi.visible = false  # hidden under the visible steps; only the collision hull is active
	body.add_child(mi)
	if node_name != "":
		body.name = node_name
	parent.add_child(body)
	return body


static func _tag(n: Node3D, module_name: String, faction: String, size: Vector3) -> Node3D:
	n.name = module_name
	n.set_meta("module", module_name)
	n.set_meta("faction", faction)
	n.set_meta("size", size)
	return n


# ---------------------------------------------------------------------------------------------
# Public factory
# ---------------------------------------------------------------------------------------------

static func build_module(module_name: String, faction: String) -> Node3D:
	match module_name:
		"Wall_2m": return build_wall(2.0, 4.0, faction, "Wall_2m")
		"Wall_4m": return build_wall(4.0, 4.0, faction, "Wall_4m")
		"Wall_8m": return build_wall(8.0, 4.0, faction, "Wall_8m")
		"Floor_4x4": return build_floor(4.0, faction, "Floor_4x4")
		"Floor_8x8": return build_floor(8.0, faction, "Floor_8x8")
		"Ceiling_4x4": return build_ceiling(4.0, 4.0, faction)
		"Corridor_Straight": return build_corridor("Corridor_Straight", [true, false, true, false], faction)
		"Corridor_Corner": return build_corridor("Corridor_Corner", [true, true, false, false], faction)
		"Corridor_TJunction": return build_corridor("Corridor_TJunction", [true, true, false, true], faction)
		"Corridor_Cross": return build_corridor("Corridor_Cross", [true, true, true, true], faction)
		"Door_Small": return build_door(4.0, 4.0, faction, "Door_Small")
		"Door_Large": return build_door(8.0, 6.0, faction, "Door_Large")
		"Hangar_Door": return build_hangar_door(90.0, 40.0, faction)
		"Support_Column": return build_column(8.0, faction)
		"Pipe_Straight": return build_pipe(4.0, faction)
		"Pipe_Elbow": return build_pipe_elbow(faction)
		"Cable_Tray": return build_cable_tray(4.0, faction)
		"Vent_Unit": return build_vent(faction)
		"Lighting_Module": return build_light_module(faction, false)
		"Rail_Module": return build_rail(4.0, 1.2, faction)
		"Stair_Module": return build_stairs(4.0, 8.0, 4.0, faction)
		"Ramp_Module": return build_ramp(8.0, 2.0, 4.0, faction)
		"Window_Module": return build_window(4.0, 4.0, faction)
	push_warning("ModularKitBuilder: unknown module '%s'" % module_name)
	return null


# ---------------------------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------------------------

static func build_wall(length: float, height: float, faction: String, module_name: String = "Wall") -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	box(root, Vector3(length, height, 0.4), Vector3(0, height * 0.5, 0), material(p["hull"], 0.35, 0.55), true, "Panel")
	box(root, Vector3(length, 0.3, 0.46), Vector3(0, 0.15, 0), material(p["trim"], 0.5, 0.5), false, "Skirting")
	box(root, Vector3(length * 0.8, 0.08, 0.46), Vector3(0, height * 0.7, 0), material(p["accent"], 0.0, 0.4, 2.0), false, "Strip")
	return _tag(root, module_name, faction, Vector3(length, height, 0.4))


static func build_floor(size: float, faction: String, module_name: String = "Floor") -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	box(root, Vector3(size, 0.4, size), Vector3(0, -0.2, 0), material(p["floor"], 0.5, 0.45), true, "Slab")
	box(root, Vector3(size, 0.02, 0.12), Vector3(0, 0.01, size * 0.5 - 0.1), material(p["warn"], 0.0, 0.5, 1.2), false, "LaneEdge")
	box(root, Vector3(0.12, 0.02, size), Vector3(0, 0.012, 0), material(p["trim"], 0.4, 0.5), false, "Seam")
	return _tag(root, module_name, faction, Vector3(size, 0.4, size))


static func build_ceiling(sx: float, sz: float, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	box(root, Vector3(sx, 0.4, sz), Vector3(0, 4.2, 0), material(p["hull"], 0.4, 0.5), true, "Slab")
	box(root, Vector3(sx * 0.6, 0.04, 0.4), Vector3(0, 3.98, 0), material(p["accent"], 0.0, 0.4, 2.5), false, "LightStrip")
	return _tag(root, "Ceiling_4x4", faction, Vector3(sx, 4.4, sz))


## Openings order: [N(+z), E(+x), S(-z), W(-x)]. 8 m wide, 6 m tall cells, floor top at y = 0.
static func build_corridor(module_name: String, opens: Array, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	var hw: float = CORRIDOR_W * 0.5
	box(root, Vector3(CORRIDOR_W, 0.4, CORRIDOR_W), Vector3(0, -0.2, 0), material(p["floor"], 0.5, 0.45), true, "Floor")
	box(root, Vector3(CORRIDOR_W, 0.4, CORRIDOR_W), Vector3(0, CORRIDOR_H + 0.2, 0), material(p["hull"], 0.4, 0.5), true, "Ceiling")
	var dirs: Array = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]
	for i in 4:
		var d: Vector3 = dirs[i]
		var along_x: bool = absf(d.z) > 0.5
		if not opens[i]:
			var size: Vector3 = Vector3(CORRIDOR_W, CORRIDOR_H, 0.4) if along_x else Vector3(0.4, CORRIDOR_H, CORRIDOR_W)
			box(root, size, d * (hw - 0.2) + Vector3(0, CORRIDOR_H * 0.5, 0), material(p["hull"], 0.35, 0.55), true, "Wall%d" % i)
			var sstrip: Vector3 = Vector3(CORRIDOR_W * 0.7, 0.1, 0.46) if along_x else Vector3(0.46, 0.1, CORRIDOR_W * 0.7)
			box(root, sstrip, d * (hw - 0.2) + Vector3(0, 3.4, 0), material(p["accent"], 0.0, 0.4, 2.0), false, "Strip%d" % i)
	# Corner pillars + ceiling light strip.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(root, Vector3(0.7, CORRIDOR_H, 0.7), Vector3(sx * (hw - 0.35), CORRIDOR_H * 0.5, sz * (hw - 0.35)), material(p["trim"], 0.5, 0.5), true, "Pillar")
	box(root, Vector3(1.0, 0.05, CORRIDOR_W * 0.7), Vector3(0, CORRIDOR_H - 0.03, 0), material(p["accent"], 0.0, 0.4, 3.0), false, "CeilLight")
	return _tag(root, module_name, faction, Vector3(CORRIDOR_W, CORRIDOR_H, CORRIDOR_W))


## Door frame (opening stays clear: the leaf is parked in a side pocket). Node "Leaf" can be animated.
static func build_door(width: float, height: float, faction: String, module_name: String = "Door") -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	var fm: Material = material(p["trim"], 0.6, 0.4)
	var post: float = 0.6
	box(root, Vector3(post, height + post, 0.9), Vector3(-(width * 0.5 + post * 0.5), (height + post) * 0.5, 0), fm, true, "PostL")
	box(root, Vector3(post, height + post, 0.9), Vector3(width * 0.5 + post * 0.5, (height + post) * 0.5, 0), fm, true, "PostR")
	box(root, Vector3(width + post * 2.0, post, 0.9), Vector3(0, height + post * 0.5, 0), fm, true, "Lintel")
	box(root, Vector3(width, 0.08, 0.95), Vector3(0, height - 0.1, 0), material(p["accent"], 0.0, 0.4, 2.5), false, "StatusStrip")
	var leaf: Node3D = box(root, Vector3(width * 0.5, height, 0.25), Vector3(-(width * 0.5 + post + width * 0.25), height * 0.5, 0.0), material(p["hull"], 0.5, 0.4), true, "Leaf")
	leaf.set_meta("parked", true)
	return _tag(root, module_name, faction, Vector3(width + post * 2.0, height + post, 0.9))


## Two sliding leaves (each half of the opening) + frame. Leaves are named LeafL / LeafR (StaticBody3D);
## the owner animates them along X and toggles their CollisionShape3D.
static func build_hangar_door(width: float, height: float, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	var half: float = width * 0.5
	for side in [-1, 1]:
		var leaf: Node3D = box(root, Vector3(half, height, 3.0), Vector3(side * half * 0.5, height * 0.5, 0), material(p["hull"], 0.55, 0.4), true, "LeafL" if side < 0 else "LeafR")
		box(leaf, Vector3(half * 0.9, 0.5, 3.12), Vector3(0, height * 0.1, 0), material(p["warn"], 0.0, 0.5, 1.5), false, "HazardBand")
		box(leaf, Vector3(0.4, height, 3.2), Vector3(-side * half * 0.5 + side * 0.2, 0, 0), material(p["trim"], 0.6, 0.4), false, "EdgeBeam")
	box(root, Vector3(width + 4.0, 2.0, 4.0), Vector3(0, height + 1.0, 0), material(p["trim"], 0.6, 0.4), false, "HeaderBeam")
	return _tag(root, "Hangar_Door", faction, Vector3(width, height, 3.0))


static func build_column(height: float, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	cylinder(root, 0.6, height, Vector3(0, height * 0.5, 0), material(p["metal"], 0.7, 0.4), true, "y", "Shaft")
	cylinder(root, 0.95, 0.4, Vector3(0, 0.2, 0), material(p["trim"], 0.6, 0.5), false, "y", "Base")
	cylinder(root, 0.95, 0.4, Vector3(0, height - 0.2, 0), material(p["trim"], 0.6, 0.5), false, "y", "Cap")
	cylinder(root, 0.62, 0.12, Vector3(0, height * 0.5, 0), material(p["accent"], 0.0, 0.4, 2.0), false, "y", "Band")
	return _tag(root, "Support_Column", faction, Vector3(1.9, height, 1.9))


static func build_pipe(length: float, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	cylinder(root, 0.25, length, Vector3(0, 0.3, 0), material(p["metal"], 0.8, 0.35), true, "x", "Tube")
	for fx in [-length * 0.5 + 0.2, length * 0.5 - 0.2]:
		cylinder(root, 0.34, 0.2, Vector3(fx, 0.3, 0), material(p["trim"], 0.6, 0.4), false, "x", "Flange")
	cylinder(root, 0.26, 0.3, Vector3(0, 0.3, 0), material(p["warn"], 0.0, 0.5, 1.0), false, "x", "Marker")
	return _tag(root, "Pipe_Straight", faction, Vector3(length, 0.7, 0.7))


static func build_pipe_elbow(faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	var m: Material = material(p["metal"], 0.8, 0.35)
	cylinder(root, 0.25, 2.0, Vector3(-1.0, 0.3, 0), m, true, "x", "ArmX")
	cylinder(root, 0.25, 2.0, Vector3(0, 1.3, 0), m, true, "y", "ArmY")
	var joint := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.34
	sm.height = 0.68
	joint.mesh = sm
	joint.material_override = material(p["trim"], 0.6, 0.4)
	joint.position = Vector3(0, 0.3, 0)
	root.add_child(joint)
	return _tag(root, "Pipe_Elbow", faction, Vector3(2.0, 2.3, 0.7))


static func build_cable_tray(length: float, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	box(root, Vector3(length, 0.1, 0.8), Vector3(0, 0.05, 0), material(p["trim"], 0.6, 0.5), true, "Tray")
	box(root, Vector3(length, 0.3, 0.08), Vector3(0, 0.2, 0.4), material(p["trim"], 0.6, 0.5), false, "WallA")
	box(root, Vector3(length, 0.3, 0.08), Vector3(0, 0.2, -0.4), material(p["trim"], 0.6, 0.5), false, "WallB")
	var cols: Array = [p["accent"], p["warn"], p["metal"]]
	for i in 3:
		cylinder(root, 0.07, length * 0.96, Vector3(0, 0.2, (float(i) - 1.0) * 0.2), material(cols[i], 0.3, 0.6, 0.8 if i == 0 else 0.0), false, "x", "Cable%d" % i)
	return _tag(root, "Cable_Tray", faction, Vector3(length, 0.4, 0.8))


static func build_vent(faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	box(root, Vector3(2.0, 0.8, 2.0), Vector3(0, 0.4, 0), material(p["metal"], 0.7, 0.45), true, "Housing")
	for i in 5:
		box(root, Vector3(1.7, 0.05, 0.1), Vector3(0, 0.82, -0.7 + float(i) * 0.35), material(p["dark"], 0.3, 0.7), false, "Slat%d" % i)
	box(root, Vector3(0.3, 0.06, 0.3), Vector3(0.8, 0.83, 0.8), material(p["accent"], 0.0, 0.4, 2.0), false, "StatusLED")
	return _tag(root, "Vent_Unit", faction, Vector3(2.0, 0.8, 2.0))


## Emissive panel (optionally with ONE shadowless OmniLight3D).
static func build_light_module(faction: String, with_light: bool = false) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	box(root, Vector3(2.0, 0.12, 0.6), Vector3(0, 0, 0), material(p["trim"], 0.5, 0.5), true, "Housing")
	box(root, Vector3(1.8, 0.04, 0.45), Vector3(0, -0.07, 0), material(Color(1, 1, 1).lerp(p["accent"], 0.35), 0.0, 0.4, 3.0), false, "Emitter")
	if with_light:
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color(1, 1, 1).lerp(p["accent"], 0.3)
		l.light_energy = 1.2
		l.omni_range = 16.0
		l.shadow_enabled = false
		l.position = Vector3(0, -0.6, 0)
		root.add_child(l)
	return _tag(root, "Lighting_Module", faction, Vector3(2.0, 0.2, 0.6))


## Guard rail along X: posts + top rail + mid rail. Collision is `collision_height` tall (>= visible height).
static func build_rail(length: float, height: float, faction: String, collision_height: float = -1.0) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	var metal: Material = material(p["metal"], 0.7, 0.4)
	var count: int = maxi(2, int(ceil(length / 2.0)) + 1)
	for i in count:
		var x: float = -length * 0.5 + length * float(i) / float(count - 1)
		box(root, Vector3(0.1, height, 0.1), Vector3(x, height * 0.5, 0), metal, false, "Post%d" % i)
	box(root, Vector3(length, 0.08, 0.1), Vector3(0, height, 0), material(p["accent"], 0.2, 0.4, 1.2), false, "TopRail")
	box(root, Vector3(length, 0.05, 0.05), Vector3(0, height * 0.5, 0), metal, false, "MidRail")
	var ch: float = collision_height if collision_height > 0.0 else height
	var body := StaticBody3D.new()
	body.name = "RailCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, ch, 0.2)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(0, ch * 0.5, 0)
	root.add_child(body)
	return _tag(root, "Rail_Module", faction, Vector3(length, height, 0.2))


## Stairs climbing toward +Z (x centred, start at origin). Visible steps; one convex wedge for collision.
static func build_stairs(rise: float, run: float, width: float, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	var steps: int = maxi(2, int(round(rise / 0.25)))
	var step_h: float = rise / float(steps)
	var step_d: float = run / float(steps)
	var tread: Material = material(p["metal"], 0.6, 0.5)
	for i in steps:
		var h: float = step_h * float(i + 1)
		box(root, Vector3(width, step_h, step_d), Vector3(0, h - step_h * 0.5, step_d * (float(i) + 0.5)), tread, false, "Step%d" % i)
	box(root, Vector3(width, 0.04, 0.12), Vector3(0, rise + 0.02, run - 0.06), material(p["accent"], 0.0, 0.4, 2.0), false, "TopNosing")
	wedge(root, width, run, rise, tread, "StairCollision")
	for sx in [-1.0, 1.0]:
		var stringer := Node3D.new()
		stringer.name = "Stringer"
		root.add_child(stringer)
		var sb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.15, 0.3, sqrt(run * run + rise * rise))
		sb.mesh = bm
		sb.material_override = material(p["trim"], 0.6, 0.5)
		stringer.add_child(sb)
		stringer.position = Vector3(sx * (width * 0.5 + 0.075), rise * 0.5 - 0.1, run * 0.5)
		stringer.rotation.x = -atan2(rise, run)
	return _tag(root, "Stair_Module", faction, Vector3(width, rise, run))


## Ramp climbing toward +Z (x centred, start at origin), solid wedge + surface strips.
static func build_ramp(length: float, rise: float, width: float, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	wedge(root, width, length, rise, material(p["floor"], 0.5, 0.45), "RampCollision")
	var slope: float = sqrt(length * length + rise * rise)
	var surf := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.2, slope)
	surf.mesh = bm
	surf.material_override = material(p["floor"], 0.5, 0.45)
	surf.position = Vector3(0, rise * 0.5 - 0.1, length * 0.5)
	surf.rotation.x = -atan2(rise, length)
	root.add_child(surf)
	for sx in [-1.0, 1.0]:
		var edge := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.14, 0.05, slope)
		edge.mesh = em
		edge.material_override = material(p["warn"], 0.0, 0.5, 1.8)
		edge.position = Vector3(sx * (width * 0.5 - 0.2), rise * 0.5 + 0.01, length * 0.5)
		edge.rotation.x = -atan2(rise, length)
		root.add_child(edge)
	return _tag(root, "Ramp_Module", faction, Vector3(width, rise, length))


## Window wall piece: frame + glass pane (collides, so nobody walks out into space).
static func build_window(width: float, height: float, faction: String) -> Node3D:
	var p: Dictionary = palette(faction)
	var root := Node3D.new()
	var fm: Material = material(p["trim"], 0.6, 0.4)
	box(root, Vector3(width, 0.25, 0.5), Vector3(0, 0.125, 0), fm, true, "Sill")
	box(root, Vector3(width, 0.25, 0.5), Vector3(0, height - 0.125, 0), fm, true, "Head")
	box(root, Vector3(0.25, height, 0.5), Vector3(-width * 0.5 + 0.125, height * 0.5, 0), fm, true, "MullionL")
	box(root, Vector3(0.25, height, 0.5), Vector3(width * 0.5 - 0.125, height * 0.5, 0), fm, true, "MullionR")
	box(root, Vector3(width - 0.4, height - 0.4, 0.08), Vector3(0, height * 0.5, 0), glass_material(p["accent"], 0.12), true, "Glass")
	return _tag(root, "Window_Module", faction, Vector3(width, height, 0.5))


# ---------------------------------------------------------------------------------------------
# Props: GLB when imported, multi-part procedural fallback otherwise (identical bounds)
# ---------------------------------------------------------------------------------------------

## collision: "box" (solid footprint), "legs" (two end legs, walk-under) or "none".
static func build_prop(key: String, faction: String, collision: String = "box") -> Node3D:
	var def: Dictionary = PROPS[key]
	var size: Vector3 = def["size"]
	var path: String = MODEL_DIR + (def["glb"] as String)
	var root := Node3D.new()
	root.name = key
	var visual: Node3D = null
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path) as PackedScene
		if ps != null:
			var inst: Node = ps.instantiate()
			if inst is Node3D:
				visual = inst as Node3D
				visual.name = "GLB"
				glb_loaded.append(key)
			else:
				inst.free()
	if visual == null:
		visual = Node3D.new()
		visual.name = "Procedural"
		_fallback_prop(visual, key, size, faction)
		procedural_used.append(key)
	root.add_child(visual)
	root.set_meta("size", size)
	root.set_meta("source", "glb" if visual.name == "GLB" else "procedural")
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	if collision == "box":
		_collider(body, size, Vector3(0, size.y * 0.5, 0))
	elif collision == "legs":
		for sx in [-1.0, 1.0]:
			_collider(body, Vector3(1.6, size.y, size.z), Vector3(sx * (size.x * 0.5 - 0.8), size.y * 0.5, 0))
	return root


static func _collider(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


static func _fallback_prop(root: Node3D, key: String, size: Vector3, faction: String) -> void:
	var p: Dictionary = palette(faction)
	var hull: Material = material(p["hull"], 0.5, 0.45)
	var trim: Material = material(p["trim"], 0.6, 0.45)
	var metal: Material = material(p["metal"], 0.75, 0.35)
	var glow: Material = material(p["accent"], 0.0, 0.4, 3.0)
	var warn: Material = material(p["warn"], 0.0, 0.5, 1.2)
	match key:
		"reactor_core":
			cylinder(root, 7.6, 1.6, Vector3(0, 0.8, 0), trim, false, "y", "Plinth")
			cylinder(root, 4.6, size.y - 3.0, Vector3(0, size.y * 0.5, 0), metal, false, "y", "Vessel")
			cylinder(root, 2.0, size.y - 1.0, Vector3(0, size.y * 0.5, 0), glow, false, "y", "CoreRod")
			cylinder(root, 5.4, 1.4, Vector3(0, size.y - 1.0, 0), trim, false, "y", "Cap")
			for i in 4:
				var a: float = float(i) * PI * 0.5 + PI * 0.25
				box(root, Vector3(1.0, size.y - 3.0, 1.0), Vector3(cos(a) * 6.4, size.y * 0.5, sin(a) * 6.4), hull, false, "Buttress%d" % i)
		"holotable":
			cylinder(root, 2.5, 0.9, Vector3(0, 0.45, 0), trim, false, "y", "Pedestal")
			box(root, Vector3(size.x, 0.35, size.z), Vector3(0, size.y - 0.55, 0), hull, false, "Top")
			box(root, Vector3(size.x - 0.6, 0.06, size.z - 0.6), Vector3(0, size.y - 0.35, 0), glow, false, "Panel")
			cylinder(root, 1.1, 0.12, Vector3(0, size.y - 0.3, 0), warn, false, "y", "ProjectorDisc")
		"gantry_crane":
			for sx in [-1.0, 1.0]:
				box(root, Vector3(1.6, size.y, size.z * 0.8), Vector3(sx * (size.x * 0.5 - 0.8), size.y * 0.5, 0), hull, false, "Leg")
				box(root, Vector3(2.2, 0.8, size.z), Vector3(sx * (size.x * 0.5 - 0.8), 0.4, 0), trim, false, "Foot")
			box(root, Vector3(size.x, 1.6, size.z * 0.8), Vector3(0, size.y - 0.8, 0), trim, false, "Bridge")
			box(root, Vector3(3.0, 1.2, 3.0), Vector3(0, size.y - 2.4, 0), metal, false, "Trolley")
			cylinder(root, 0.08, 6.0, Vector3(0, size.y - 6.0, 0), metal, false, "y", "Cable")
			box(root, Vector3(1.2, 0.8, 1.2), Vector3(0, size.y - 9.2, 0), warn, false, "Hook")
		"shuttle":
			box(root, Vector3(size.x * 0.5, 2.6, size.z * 0.8), Vector3(0, 2.2, 0), hull, false, "Fuselage")
			box(root, Vector3(size.x * 0.34, 1.8, 4.0), Vector3(0, 2.6, size.z * 0.5 - 2.0), glow, false, "Cockpit")
			box(root, Vector3(size.x, 0.4, 5.0), Vector3(0, 1.7, -2.5), trim, false, "Wings")
			box(root, Vector3(0.4, 2.2, 3.0), Vector3(0, 4.1, -size.z * 0.5 + 2.0), trim, false, "TailFin")
			for sx in [-1.0, 1.0]:
				cylinder(root, 0.9, 3.0, Vector3(sx * (size.x * 0.42), 1.5, -size.z * 0.5 + 1.5), metal, false, "z", "Engine")
				box(root, Vector3(0.3, 1.2, 0.3), Vector3(sx * 2.2, 0.6, 3.0), metal, false, "LandingLeg")
				box(root, Vector3(0.3, 1.2, 0.3), Vector3(sx * 2.2, 0.6, -4.0), metal, false, "LandingLeg")
		"fabrication_rig":
			box(root, Vector3(size.x, 0.9, size.z), Vector3(0, 0.45, 0), trim, false, "Bench")
			box(root, Vector3(size.x - 0.4, 0.15, size.z - 0.4), Vector3(0, 0.98, 0), metal, false, "WorkTop")
			box(root, Vector3(0.5, size.y - 1.0, 0.5), Vector3(-size.x * 0.4, size.y * 0.5 + 0.4, -size.z * 0.35), hull, false, "ArmPost")
			box(root, Vector3(size.x * 0.7, 0.4, 0.5), Vector3(-size.x * 0.05, size.y - 0.5, -size.z * 0.35), hull, false, "ArmBeam")
			box(root, Vector3(0.2, 1.4, 0.2), Vector3(size.x * 0.1, size.y - 1.3, -size.z * 0.35), warn, false, "Tool")
			box(root, Vector3(1.2, 0.8, 0.1), Vector3(size.x * 0.3, 1.5, size.z * 0.45), glow, false, "Screen")
		"cargo_rack":
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					box(root, Vector3(0.3, size.y, 0.3), Vector3(sx * (size.x * 0.5 - 0.15), size.y * 0.5, sz * (size.z * 0.5 - 0.15)), trim, false, "Upright")
			for lvl in 3:
				var y: float = 0.4 + float(lvl) * (size.y - 0.6) / 3.0
				box(root, Vector3(size.x, 0.2, size.z), Vector3(0, y, 0), metal, false, "Shelf%d" % lvl)
				var col: Material = hull if lvl % 2 == 0 else material(p["alt"], 0.4, 0.55)
				box(root, Vector3(size.x * 0.42, 1.4, size.z * 0.8), Vector3(-size.x * 0.24, y + 0.8, 0), col, false, "CrateA")
				box(root, Vector3(size.x * 0.42, 1.4, size.z * 0.8), Vector3(size.x * 0.24, y + 0.8, 0), warn if lvl == 1 else hull, false, "CrateB")
