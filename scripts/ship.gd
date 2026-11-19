## The Kestrel: one spacecraft assembled from the twelve PARTS, used on the pad, in flight and on Planet B.
class_name ShipModel
extends RefCounted

const Hardware = preload("res://scripts/industrial_hardware.gd")
const HULL := Color("#e4e6e1")
const MARKING := Color("#c8372d")
const GUNMETAL := Color("#2b3138")
const STEEL := Color("#7b858e")
const VENT_SLOTS := ["reactor", "engine", "port", "coolant", "thruster", "keel"]
const DARK := Color("#3a3358")
const GLASS := Color("#7fd8e6")


## A single part mesh centred on its own origin, at full ship scale.
static func part_mesh(type: String, dims: Vector3, accent: Color) -> Node3D:
	var n := Node3D.new()
	match type:
		"hull":
			var cap := CapsuleMesh.new()
			cap.radius = dims.y * 0.5
			cap.height = dims.z
			cap.radial_segments = 20
			cap.rings = 6
			var mi := Gfx.mesh(cap, Gfx.mat(HULL, 0.55))
			mi.rotation.x = PI / 2
			mi.scale = Vector3(dims.x / dims.y, 1, 1)
			n.add_child(mi)
			var band := Gfx.box(Vector3(dims.x * 1.02, dims.y * 0.22, dims.z * 0.08), accent, Vector3(0, 0, dims.z * 0.18))
			n.add_child(band)
			var band2 := Gfx.box(Vector3(dims.x * 1.02, dims.y * 0.22, dims.z * 0.05), accent, Vector3(0, 0, -dims.z * 0.12))
			n.add_child(band2)
			for i in 5:
				n.add_child(Gfx.box(Vector3(dims.x * 1.01, dims.y * 0.12, dims.z * 0.04), GLASS, Vector3(0, dims.y * 0.18, -dims.z * 0.3 + i * dims.z * 0.13), 0.4))
		"engine":
			var r := minf(dims.x, dims.y) * 0.5
			var body := Gfx.cyl(r, dims.z * 0.8, accent, Vector3(0, 0, -dims.z * 0.1))
			body.rotation.x = PI / 2
			n.add_child(body)
			var noz := Gfx.cyl(r * 0.6, dims.z * 0.25, DARK, Vector3(0, 0, dims.z * 0.38), 16, r * 0.9)
			noz.rotation.x = -PI / 2
			n.add_child(noz)
			var cone := Gfx.cyl(0.05, dims.z * 0.2, HULL, Vector3(0, 0, -dims.z * 0.58), 16, r)
			cone.rotation.x = -PI / 2
			n.add_child(cone)
		"bridge":
			n.add_child(Gfx.box(dims, HULL))
			n.add_child(Gfx.box(Vector3(dims.x * 0.8, dims.y * 0.45, 0.1), GLASS, Vector3(0, dims.y * 0.1, -dims.z * 0.5), 0.6))
		"power":
			n.add_child(Gfx.box(dims, Color("#6c5bc4")))
			n.add_child(Gfx.cyl(dims.x * 0.25, dims.y * 1.1, Color("#b7a0f3"), Vector3.ZERO, 12))
			n.get_child(1).material_override = Gfx.mat(Color("#b7a0f3"), 0.4, 2.0)
		"battery":
			n.add_child(Gfx.box(dims, DARK))
			n.add_child(Gfx.box(Vector3(dims.x * 1.02, dims.y * 0.15, dims.z * 1.02), Color("#f7ce59")))
		"radiator":
			n.add_child(Gfx.box(dims, Color("#dfe7f0")))
			for i in 6:
				n.add_child(Gfx.box(Vector3(dims.x * 0.95, dims.y * 1.2, 0.08), Color("#a9b5c9"), Vector3(0, 0, -dims.z * 0.4 + i * dims.z * 0.16)))
		"cargo", "life", "stores":
			var c: Color = {"cargo": Color("#f7a28f"), "life": Color("#9cdeb1"), "stores": Color("#edbd81")}[type]
			n.add_child(Gfx.box(dims, c))
			n.add_child(Gfx.box(Vector3(dims.x * 1.02, dims.y * 0.1, dims.z * 0.9), DARK, Vector3(0, dims.y * 0.2, 0)))
		"turret":
			n.add_child(Gfx.cyl(dims.x * 0.45, dims.y * 0.5, DARK, Vector3(0, -dims.y * 0.2, 0)))
			n.add_child(Gfx.box(Vector3(dims.x * 0.7, dims.y * 0.55, dims.z * 0.55), HULL, Vector3(0, dims.y * 0.2, 0)))
			for sx in [-1, 1]:
				var b := Gfx.cyl(0.13, dims.z * 0.8, accent, Vector3(sx * dims.x * 0.18, dims.y * 0.2, -dims.z * 0.55))
				b.rotation.x = PI / 2
				n.add_child(b)
		"antenna":
			n.add_child(Gfx.cyl(0.12, dims.y * 1.6, HULL, Vector3(0, dims.y * 0.3, 0)))
			var dish := Gfx.cyl(dims.x * 0.5, 0.15, HULL, Vector3(0, dims.y * 1.1, 0), 20, dims.x * 0.22)
			dish.rotation.x = deg_to_rad(-35)
			n.add_child(dish)
			n.add_child(Gfx.sphere(0.18, accent, Vector3(0, dims.y * 1.3, -0.2), 1.5, 10))
		_:
			n.add_child(Gfx.box(dims, HULL))
	return n


## Whole ship (all twelve parts). Origin on the ground under the ship.
static var _scenes := {}
static var _glass_material: StandardMaterial3D
static var _thruster_material: StandardMaterial3D

static func prefab(family: String) -> PackedScene:
	if not ShipCatalog.FAMILIES.has(family): family = "kestrel"
	if not _scenes.has(family):
		_scenes[family] = load(ShipCatalog.FAMILIES[family]["prefab_path"])
	return _scenes[family]


static func module(slot: String, family: String, accent: Color) -> Node3D:
	var donor: Node3D = prefab(family).instantiate()
	var part: Node3D = donor.get_node(slot)
	donor.remove_child(part)
	part.set_meta("ship_family", family)
	donor.free()
	_recolor(part, accent)
	_add_greebles(part, slot)
	return part


static func _is_glass(id: String) -> bool:
	return id == "Glass" or id.contains("Cockpit")


static func _is_thruster(id: String) -> bool:
	return id in ["NozzleGlow", "ThrusterGlow"]


static func _marking_color(accent: Color) -> Color:
	if accent in [Color.WHITE, Color.ORANGE, Color("#f08a4b"), Color("#eaa665"), Color("#f79442")]:
		return MARKING
	return MARKING.lerp(accent, 0.7)


static func _recolor(node: Node, accent: Color) -> void:
	if node is MeshInstance3D:
		var id := String(node.name)
		if node.mesh and node.mesh.get_aabb().size.length() < 1.5:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = 60
			node.visibility_range_end_margin = 8
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if _is_glass(id):
			if _glass_material == null:
				_glass_material = StandardMaterial3D.new()
				_glass_material.albedo_color = Color(0.025, 0.05, 0.09, 1.0)
				_glass_material.metallic = 0.88
				_glass_material.roughness = 0.03
				_glass_material.clearcoat_enabled = true
				_glass_material.clearcoat = 1.0
				_glass_material.clearcoat_roughness = 0.02
				_glass_material.rim_enabled = true
				_glass_material.rim = 0.5
			node.material_override = _glass_material
		elif _is_thruster(id):
			if _thruster_material == null:
				_thruster_material = StandardMaterial3D.new()
				_thruster_material.albedo_color = Color("#66fcf1")
				_thruster_material.emission_enabled = true
				_thruster_material.emission = Color("#00e5ff")
				_thruster_material.emission_energy_multiplier = 4.5
			node.material_override = _thruster_material
		elif id.begins_with("Stripe") or id.begins_with("LandingFoot") or id in ["EngineBody", "Cannon0", "Cannon1", "Tip", "SlotAccent"]:
			node.material_override = Hardware.material(_marking_color(accent), 0.35, 0.48)
		elif id == "ServiceDetail":
			node.material_override = Hardware.material(STEEL, 0.65, 0.45)
		else:
			var old := node.material_override as StandardMaterial3D
			if old and not old.emission_enabled and old.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				var paint := old.albedo_color
				if paint.v >= 0.72 and paint.s < 0.24:
					paint = paint.lerp(HULL, 0.8)
				node.material_override = Hardware.material(paint, old.metallic, clampf(old.roughness, 0.45, 0.58))
	for child in node.get_children():
		_recolor(child, accent)


static func _protected_bounds(node: Node, xf: Transform3D, bounds: Array[AABB]) -> void:
	if node is Node3D:
		xf *= (node as Node3D).transform
	if node is MeshInstance3D and node.mesh and (_is_glass(String(node.name)) or _is_thruster(String(node.name))):
		bounds.append(xf * node.mesh.get_aabb())
	for child in node.get_children():
		_protected_bounds(child, xf, bounds)


static func _append_greeble(surface: SurfaceTool, mesh: PrimitiveMesh, xf: Transform3D, envelope: AABB, keep_clear: Array[AABB]) -> bool:
	var bounds := xf * mesh.get_aabb()
	if not envelope.encloses(bounds):
		return false
	for protected in keep_clear:
		if protected.intersects(bounds):
			return false
	surface.append_from(mesh, 0, xf)
	return true


static func _add_greebles(part: Node3D, slot: String) -> void:
	if part.has_meta("_greebled"):
		return
	var boxes := [null]
	var keep_clear: Array[AABB] = []
	for child in part.get_children():
		Actor._aabb(child, Transform3D.IDENTITY, boxes)
		_protected_bounds(child, Transform3D.IDENTITY, keep_clear)
	if boxes[0] == null:
		return
	var envelope: AABB = boxes[0]
	# Use the housing for placement so pylons, masts and barrels do not set the pipe length.
	var housing_name: String = {
		"keel": "HullBody", "bridge": "Body", "port": "NacelleShell",
		"thruster": "NacelleShell", "reactor": "PowerBlock", "coolant": "Radiator",
		"engine": "TurretBody", "scrubber": "Module", "cargo": "Module",
		"stores": "Module", "battery": "Battery", "antenna": "Base",
	}.get(slot, "")
	var housing := part.get_node_or_null(NodePath(housing_name))
	if housing == null:
		var index := 2 if slot == "engine" else int(slot == "bridge")
		housing = part.get_child(index)
		if housing.name == "Nacelle":
			housing = housing.get_child(0)
	var shell := [null]
	var parent_xf := Transform3D.IDENTITY
	if housing.get_parent() != part:
		parent_xf = (housing.get_parent() as Node3D).transform
	Actor._aabb(housing, parent_xf, shell)
	var body: AABB = shell[0] if shell[0] != null else envelope
	var center := body.get_center()
	var radius := minf(0.09, minf(body.size.x, body.size.y) * 0.065)
	var run := body.size.z * 0.62
	var flank := -1.0 if slot == "port" else 1.0
	var pipe_center := center + Vector3(flank * (body.size.x * 0.48 - radius), -body.size.y * 0.14, 0)
	var along_z := Basis(Vector3.RIGHT, PI * 0.5)
	var pipe := CylinderMesh.new()
	pipe.radial_segments = 12
	pipe.rings = 0
	pipe.top_radius = radius
	pipe.bottom_radius = radius
	pipe.height = run

	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_pipe := _append_greeble(steel, pipe, Transform3D(along_z, pipe_center), envelope, keep_clear)

	var gunmetal := SurfaceTool.new()
	gunmetal.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collar := TorusMesh.new()
	collar.inner_radius = radius * 0.8
	collar.outer_radius = radius * 1.45
	collar.rings = 12
	collar.ring_segments = 8
	var has_trim := false
	if has_pipe:
		for end in [-1.0, 1.0]:
			var pos := pipe_center + Vector3(0, 0, end * run * 0.48)
			if _append_greeble(gunmetal, collar, Transform3D(along_z, pos), envelope, keep_clear):
				has_trim = true

	if slot in VENT_SLOTS:
		var fin := BoxMesh.new()
		fin.size = Vector3(radius * 2.0, body.size.y * 0.24, run * 0.045)
		for i in 7:
			var pos := pipe_center + Vector3(0, body.size.y * 0.24, run * (i - 3) * 0.105)
			if _append_greeble(gunmetal, fin, Transform3D(Basis.IDENTITY, pos), envelope, keep_clear):
				has_trim = true

	# Batch the hardware by material to stay within the existing per-family mesh budget.
	var mesh := ArrayMesh.new()
	if has_pipe:
		steel.set_material(Hardware.material(STEEL, 0.65, 0.5))
		steel.commit(mesh)
	if has_trim:
		gunmetal.set_material(Hardware.material(GUNMETAL, 0.65, 0.5))
		gunmetal.commit(mesh)
	if mesh.get_surface_count() > 0:
		var detail := Gfx.mesh(mesh, null, Vector3.ZERO, false)
		detail.name = "GreebleHardware"
		part.add_child(detail)
		part.set_meta("_greebled", true)


static func full(accent: Color, loadout: Dictionary = {}) -> Node3D:
	var root: Node3D = prefab("kestrel").instantiate()
	for slot in ShipCatalog.VARIANTS:
		var family := str(loadout.get(slot, "kestrel"))
		if not ShipCatalog.FAMILIES.has(family): family = "kestrel"
		if family != "kestrel":
			var old := root.get_node(slot)
			root.remove_child(old)
			old.free()
			root.add_child(module(slot, family, accent))
		root.get_node(slot).set_meta("ship_family", family)
	if root.get_node("keel").get_meta("ship_family") != "kestrel":
		for child in root.get_children():
			if String(child.name).begins_with("Landing"):
				root.remove_child(child)
				child.free()
	_recolor(root, accent)
	for slot in ShipCatalog.VARIANTS:
		var part := root.get_node(slot) as Node3D
		if part.get_meta("ship_family") == "kestrel":
			_add_greebles(part, slot)
	return root


static func add_landing_legs(root: Node3D, accent: Color) -> void:
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := Gfx.box(Vector3(0.5, 2.2, 0.5), DARK, Vector3(sx * 4.6, 1.1, sz * 6.5 - 2.0))
			leg.rotation.z = sx * 0.25
			root.add_child(leg)
			root.add_child(Gfx.cyl(0.9, 0.2, accent, Vector3(sx * 5.0, 0.1, sz * 6.5 - 2.0)))


## Exhaust positions are resolved from the actual edited vessel, never the old design sheet.
static func flame(length := 6.0, vessel: Node3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "EngineExhaust"
	for id in ["port", "thruster"]:
		var source: Node3D = vessel.get_node_or_null(id) if vessel else null
		var fx := preload("res://scripts/exhaust_fx.gd").create(0.75, length * 0.65)
		if source:
			var nozzle: Node3D = source.get_node_or_null("NozzleGlow")
			fx.position = source.transform * (nozzle.position if nozzle else Vector3(0, 0, 4.7)) + Vector3(0, 0, 0.12)
		else:
			fx.position = Vector3(-5.68 if id == "port" else 6.19, 3.856, 10.82)
		root.add_child(fx)
	return root


## Centred, uniformly fitted miniature of the real module geometry.
static func preview(slot: String, family: String, accent: Color, extent := 1.7) -> Node3D:
	var wrapper := Node3D.new()
	var part := module(slot, family, accent)
	part.transform = Transform3D.IDENTITY
	wrapper.add_child(part)
	var boxes := [null]
	Actor._aabb(part, Transform3D.IDENTITY, boxes)
	if boxes[0] != null:
		var box: AABB = boxes[0]
		var k := extent / maxf(box.size.x, maxf(box.size.y, box.size.z))
		part.position = -box.get_center() * k
		part.scale = Vector3.ONE * k
	return wrapper
