## Shared, dimensioned aerospace hardware. +Y is the engine / tank axis.
extends RefCounted

static var _materials: Dictionary = {}

static func material(color: Color, metal := 0.55, rough := 0.38) -> ShaderMaterial:
	var key := "%s|%s|%s" % [color.to_html(), metal, rough]
	if _materials.has(key): return _materials[key]
	var m := preload("res://assets/materials/metal.tres").duplicate() as ShaderMaterial
	m.set_shader_parameter("panel_normal", ProcTex.metal_panel_normal())
	_materials[key] = m
	m.shader = preload("res://assets/shaders/industrial.gdshader")
	m.set_shader_parameter("paint", color)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("finish", rough)
	return m

static func part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, metal := 0.55) -> MeshInstance3D:
	var mi := Gfx.mesh(mesh, material(color, metal), pos)
	parent.add_child(mi)
	return mi

static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 64
	return part(parent, m, pos, color)

## Revolved profile supports rounded ogives and a genuinely open engine bell.
static func link(color: Color, radius: float, length := 15.0) -> Node3D:
	var root := Node3D.new()
	root.name = "ServoLink"
	for side in [-1,1]:
		var beam := Gfx.box(Vector3(radius*.5,radius*.95,length*.88),color,Vector3(side*radius*.65,0,-length*.5))
		beam.material_override = material(color,.42,.44)
		root.add_child(beam)
		var rail := cylinder(root,radius*.13,length*.70,Vector3(side*radius*.66,radius*.65,-length*.48),Color("#929da3"))
		rail.rotation.x = PI/2
		var sleeve := cylinder(root,radius*.24,length*.34,Vector3(side*radius*.66,radius*.65,-length*.68),Color("#424c54"))
		sleeve.rotation.x = PI/2
	for z in [-length*.12,-length*.88]:
		root.add_child(Gfx.box(Vector3(radius*1.9,radius*1.2,radius*.6),Color("#30383e"),Vector3(0,0,z)))
	# Repeated protective hose clamps and service studs move with the link.
	for z in [-length*.2,-length*.4,-length*.6,-length*.8]:
		root.add_child(Gfx.box(Vector3(radius*1.7,.07,.10),Color("#727f86"),Vector3(0,-radius*.65,z)))
		for side in [-1,1]:
			root.add_child(Gfx.sphere(.045,Color("#d3b367"),Vector3(side*radius*.65,radius*.5,z),0,6))
	# Protected hydraulic hoses follow the link; never stretch across its joints.
	for x in [-.22,.22]:
		var hose := cylinder(root,radius*.12,length*.78,Vector3(x,-radius*.6,-length*.5),Color("#171e23"))
		hose.rotation.x = PI/2
	preload("res://scripts/model_detail.gd").batch(root, [], 60.0, 1.5)
	return root

static func joint(radius: float) -> Node3D:
	var root := Node3D.new()
	for side in [-1,1]:
		var hub := cylinder(root,radius,radius*.35,Vector3(side*radius*.65,0,0),Color("#343e46"))
		hub.rotation.z = PI/2
		var cap := cylinder(root,radius*.7,radius*.08,Vector3(side*radius*.86,0,0),Color("#abb5b9"))
		cap.rotation.z = PI/2
		for i in 8:
			var a := i*TAU/8.0
			var bolt := cylinder(root,radius*.055,radius*.1,Vector3(side*radius*.92,cos(a)*radius*.51,sin(a)*radius*.51),Color("#414a51"))
			bolt.rotation.z = PI/2
	preload("res://scripts/model_detail.gd").batch(root, [], 60.0, 1.5)
	return root

static func tool() -> Node3D:
	var root := joint(.52)
	root.name = "TorqueAndWeldHead"
	cylinder(root,.23,.9,Vector3(0,-.38,0),Color("#5c656d"))
	cylinder(root,.10,.35,Vector3(0,-.95,0),Color("#c4a17b"))
	for side in [-1,1]:
		root.add_child(Gfx.box(Vector3(.12,.65,.18),Color("#313c43"),Vector3(side*.38,-.5,0)))
	preload("res://scripts/model_detail.gd").batch(root, [], 60.0, 1.5)
	return root


# ---------------------------------------------------------------------------
# Manual crane arm API. A crane robot is a Node3D named "IndustrialAssemblyRobot*"
# with the joint chain CraneYaw > CraneBoom > CraneForearm > CraneClaw > CraneTip.
# build_crane_robot() makes a conforming one; the helpers below also accept any
# robot that exposes nodes with those names (found recursively).
# ---------------------------------------------------------------------------
const CRANE_BOOM_LEN := 6.0
const CRANE_FORE_LEN := 5.0
const CRANE_TURN_RATE := 6.0

static func build_crane_robot(index := 0) -> Node3D:
	var robot := Node3D.new()
	robot.name = "IndustrialAssemblyRobot%d" % index
	var steel := Color("#6d777c")
	var dark := Color("#242b30")
	var accent := Color("#d9a441")
	cylinder(robot, 0.9, 0.5, Vector3(0, 0.25, 0), dark)
	var yaw := Node3D.new()
	yaw.name = "CraneYaw"
	yaw.position = Vector3(0, 0.5, 0)
	robot.add_child(yaw)
	cylinder(yaw, 0.6, 1.2, Vector3(0, 0.6, 0), steel)
	var boom := Node3D.new()
	boom.name = "CraneBoom"
	boom.position = Vector3(0, 1.3, 0)
	yaw.add_child(boom)
	part(boom, _beam(0.35, CRANE_BOOM_LEN), Vector3(0, 0, -CRANE_BOOM_LEN * 0.5), accent)
	var fore := Node3D.new()
	fore.name = "CraneForearm"
	fore.position = Vector3(0, 0, -CRANE_BOOM_LEN)
	boom.add_child(fore)
	part(fore, _beam(0.26, CRANE_FORE_LEN), Vector3(0, 0, -CRANE_FORE_LEN * 0.5), steel)
	var claw := Node3D.new()
	claw.name = "CraneClaw"
	claw.position = Vector3(0, 0, -CRANE_FORE_LEN)
	fore.add_child(claw)
	cylinder(claw, 0.22, 0.5, Vector3(0, 0, -0.25), dark).rotation.x = PI / 2
	for side in [-1, 1]:
		var finger := Node3D.new()
		finger.name = "ClawFinger%s" % ("L" if side < 0 else "R")
		finger.position = Vector3(side * 0.22, 0, -0.5)
		claw.add_child(finger)
		part(finger, _beam(0.1, 0.7), Vector3(0, 0, -0.35), steel)
	var tip := Marker3D.new()
	tip.name = "CraneTip"
	tip.position = Vector3(0, 0, -1.0)
	claw.add_child(tip)
	var lamp := Gfx.sphere(0.09, accent, Vector3(0, 0.18, -0.3), 0, 8)
	lamp.name = "GripLamp"
	claw.add_child(lamp)
	return robot

static func _beam(width: float, length: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(width, width, length)
	return m

static func _crane_node(robot: Node3D, node_name: String) -> Node3D:
	if robot == null or not is_instance_valid(robot):
		return null
	return robot.find_child(node_name, true, false) as Node3D

## Smoothly turns base yaw, boom, forearm and claw so the claw tip hangs over target_world_pos.
static func aim_crane_at(robot: Node3D, target_world_pos: Vector3, dt: float) -> void:
	var yaw := _crane_node(robot, "CraneYaw")
	var boom := _crane_node(robot, "CraneBoom")
	var fore := _crane_node(robot, "CraneForearm")
	var claw := _crane_node(robot, "CraneClaw")
	if yaw == null or boom == null or fore == null or claw == null:
		return
	var k := 1.0 - exp(-CRANE_TURN_RATE * maxf(0.0, dt))
	var t := yaw.get_parent_node_3d().to_local(target_world_pos) - yaw.position
	# Aim the claw socket (not the wrist) at the target: reach shortens by the claw length.
	var reach_h := Vector2(t.x, t.z).length()
	yaw.rotation.y = lerp_angle(yaw.rotation.y, atan2(-t.x, -t.z) if reach_h > 0.01 else yaw.rotation.y, k)
	var l1 := absf(fore.position.z)
	var l2 := absf(claw.position.z)
	var tip := _crane_node(robot, "CraneTip")
	var claw_len := absf(tip.position.z) if tip != null else 1.0
	var v := t.y - boom.position.y + claw_len   # wrist hovers one claw-length above the target
	var d := clampf(Vector2(reach_h, v).length(), absf(l1 - l2) + 0.05, l1 + l2 - 0.05)
	var a := atan2(v, reach_h)
	var shoulder := a + acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var interior := acos(clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0))
	var elbow := -(PI - interior)
	boom.rotation.x = lerp_angle(boom.rotation.x, shoulder, k)
	fore.rotation.x = lerp_angle(fore.rotation.x, elbow, k)
	# Keep the claw pointing straight down regardless of arm pose.
	claw.rotation.x = lerp_angle(claw.rotation.x, -PI / 2.0 - (boom.rotation.x + fore.rotation.x), k)

static func get_crane_tip(robot: Node3D) -> Node3D:
	var tip := _crane_node(robot, "CraneTip")
	return tip if tip != null else _crane_node(robot, "CraneClaw")

static func get_crane_tip_pos(robot: Node3D) -> Vector3:
	var tip := get_crane_tip(robot)
	return tip.global_position if tip != null else (robot.global_position if robot != null else Vector3.ZERO)

## Opens/closes the claw fingers and lights the grip lamp.
static func set_crane_gripping(robot: Node3D, gripping: bool) -> void:
	var claw := _crane_node(robot, "CraneClaw")
	if claw == null:
		return
	claw.set_meta("gripping", gripping)
	for side in [-1, 1]:
		var f := claw.get_node_or_null("ClawFinger%s" % ("L" if side < 0 else "R")) as Node3D
		if f != null:
			f.position.x = side * (0.12 if gripping else 0.30)
	var lamp := claw.get_node_or_null("GripLamp") as MeshInstance3D
	if lamp != null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#42ff7a") if gripping else Color("#d9a441")
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 2.5 if gripping else 0.4
		lamp.material_override = m


# ---------------------------------------------------------------------------
# Ground Support Equipment: conveyor + baggage-carousel delivery machine
# ---------------------------------------------------------------------------
const GSE_BELT_W := 3.4
const GSE_BELT_TOP := 1.25
const GSE_LEG_SPACING := 4.0
const GSE_SLAT_PITCH := 1.2
const GSE_SPEED := 2.2
const GSE_ROLE_COLORS := [Color("#ff5a4a"), Color("#42d6ff"), Color("#ffc23a"), Color("#6dff8a")]

static func _gse_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, metal := 0.55) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return part(parent, m, pos, color, metal)

static func _gse_glow(color: Color, energy := 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

static func _gse_route(a: Vector3, b: Vector3) -> Array:
	# Dog-leg: run along X to the target column, then along Z, at belt-top height.
	var y := GSE_BELT_TOP
	var p0 := Vector3(a.x, y, a.z)
	var p3 := Vector3(b.x, y, b.z)
	var p1 := Vector3(b.x, y, a.z)
	var pts: Array = [p0]
	for p in [p1, p3]:
		if p.distance_to(pts[pts.size() - 1]) > 0.01:
			pts.append(p)
	if pts.size() < 2:
		pts.append(p3 + Vector3(0.1, 0, 0))
	return pts

## Straight conveyor segment between two belt-top waypoints.
static func _gse_segment(root: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.05:
		return
	var seg := Node3D.new()
	seg.position = (a + b) * 0.5
	seg.rotation.y = atan2(-d.z, d.x)  # local +X runs along the segment
	root.add_child(seg)
	var steel := Color("#3b424a")
	var dark := Color("#1d2126")
	var yellow := Color("#f2c200")
	# Bed frame + rubber belt surface
	_gse_box(seg, Vector3(len, 0.22, GSE_BELT_W), Vector3(0, -0.2, 0), steel)
	_gse_box(seg, Vector3(len, 0.06, GSE_BELT_W - 0.5), Vector3(0, -0.04, 0), dark, 0.1)
	# Side guardrails: dark-steel posts + hazard-yellow top rails
	for s in [-1, 1]:
		var z: float = s * (GSE_BELT_W * 0.5 + 0.05)
		_gse_box(seg, Vector3(len, 0.1, 0.1), Vector3(0, 0.55, z), yellow)
		_gse_box(seg, Vector3(len, 0.08, 0.1), Vector3(0, 0.1, z), steel)
		var n := int(len / 1.5) + 1
		for i in n:
			var x := -len * 0.5 + (i + 0.5) * len / n
			_gse_box(seg, Vector3(0.08, 0.7, 0.08), Vector3(x, 0.25, z), dark)
	# Motorized roller drums at both ends
	for e in [-1, 1]:
		var drum := CylinderMesh.new()
		drum.top_radius = 0.2
		drum.bottom_radius = 0.2
		drum.height = GSE_BELT_W - 0.3
		drum.radial_segments = 24
		var mi := part(seg, drum, Vector3(e * (len * 0.5 - 0.2), -0.1, 0), Color("#8a9199"), 0.8)
		mi.rotation.x = PI * 0.5
	# Support legs, floor to bed underside
	var legs := int(len / GSE_LEG_SPACING) + 2
	var leg_h := GSE_BELT_TOP - 0.4
	for i in legs:
		var x := -len * 0.5 + i * len / (legs - 1)
		for s in [-1, 1]:
			_gse_box(seg, Vector3(0.18, leg_h, 0.18), Vector3(x, -GSE_BELT_TOP + leg_h * 0.5 - 0.0 - 0.0, s * (GSE_BELT_W * 0.5 - 0.2)) + Vector3(0, 0.0, 0), dark)
		_gse_box(seg, Vector3(0.14, 0.14, GSE_BELT_W - 0.3), Vector3(x, -GSE_BELT_TOP + 0.25, 0), steel)

## Overhead GSE dispatch/scanner arch with status lights. Returns the light meshes.
static func _gse_arch(root: Node3D, pos: Vector3, yaw: float, color: Color) -> Array:
	var arch := Node3D.new()
	arch.position = Vector3(pos.x, 0, pos.z)
	arch.rotation.y = yaw
	root.add_child(arch)
	var lights: Array = []
	var h := 3.6
	for s in [-1, 1]:
		_gse_box(arch, Vector3(0.3, h, 0.3), Vector3(0, h * 0.5, s * (GSE_BELT_W * 0.5 + 0.35)), Color("#2a2f36"))
	_gse_box(arch, Vector3(0.5, 0.45, GSE_BELT_W + 1.0), Vector3(0, h, 0), Color("#f2c200"))
	_gse_box(arch, Vector3(0.12, 0.1, GSE_BELT_W - 0.4), Vector3(0, h - 0.3, 0), Color("#42d6ff"), 0.2)
	for i in 3:
		var l := _gse_box(arch, Vector3(0.22, 0.22, 0.22), Vector3(0.3, h, (i - 1) * 1.0), color)
		l.material_override = _gse_glow(Color("#42d6ff") if i != 1 else Color("#ffb020"))
		l.set_meta("base_energy", 2.5)
		l.set_meta("phase", i * 0.9)
		lights.append(l)
	return lights

## Baggage-carousel turnaround bay: looped (stadium-shaped) transfer bed with bumpers + beacon.
static func _gse_bay(root: Node3D, center: Vector3, role: int, beacons: Array) -> void:
	var color: Color = GSE_ROLE_COLORS[role % GSE_ROLE_COLORS.size()]
	var bay := Node3D.new()
	bay.position = Vector3(center.x, 0, center.z)
	root.add_child(bay)
	var half_l := 6.0  # 12 m x 9 m bed: holds a full-size module
	var half_w := 4.5
	_gse_box(bay, Vector3(half_l * 2, 0.3, half_w * 2), Vector3(0, GSE_BELT_TOP - 0.2, 0), Color("#3b424a"))
	_gse_box(bay, Vector3(half_l * 2 - 1, 0.05, half_w * 2 - 1), Vector3(0, GSE_BELT_TOP - 0.03, 0), Color("#1d2126"), 0.1)
	# Curved ends (carousel turnarounds) from half-cylinders
	for e in [-1, 1]:
		var cap := CylinderMesh.new()
		cap.top_radius = half_w
		cap.bottom_radius = half_w
		cap.height = 0.3
		cap.radial_segments = 48
		part(bay, cap, Vector3(e * half_l, GSE_BELT_TOP - 0.2, 0), Color("#3b424a"))
		var disc := CylinderMesh.new()
		disc.top_radius = half_w - 0.5
		disc.bottom_radius = half_w - 0.5
		disc.height = 0.05
		disc.radial_segments = 48
		part(bay, disc, Vector3(e * half_l, GSE_BELT_TOP - 0.03, 0), Color("#1d2126"), 0.1)
		var ring := TorusMesh.new()
		ring.inner_radius = half_w - 0.12
		ring.outer_radius = half_w + 0.12
		ring.rings = 48
		ring.ring_segments = 8
		part(bay, ring, Vector3(e * half_l, GSE_BELT_TOP + 0.2, 0), Color("#f2c200"))
	# Bumper rails along long sides
	for s in [-1, 1]:
		_gse_box(bay, Vector3(half_l * 2, 0.25, 0.25), Vector3(0, GSE_BELT_TOP + 0.2, s * half_w), Color("#f2c200"))
	# Support piers
	for x in [-half_l, 0.0, half_l]:
		for s in [-1, 1]:
			_gse_box(bay, Vector3(0.4, GSE_BELT_TOP - 0.35, 0.4), Vector3(x, (GSE_BELT_TOP - 0.35) * 0.5, s * (half_w - 0.4)), Color("#1d2126"))
	# Role-colored beacon mast
	_gse_box(bay, Vector3(0.2, 3.0, 0.2), Vector3(-half_l, 1.5 + GSE_BELT_TOP, half_w + 0.4), Color("#2a2f36"))
	var b := _gse_box(bay, Vector3(0.6, 0.6, 0.6), Vector3(-half_l, 3.3 + GSE_BELT_TOP, half_w + 0.4), color)
	b.material_override = _gse_glow(color, 3.0)
	b.set_meta("base_energy", 3.0)
	b.set_meta("phase", role * 1.3)
	beacons.append(b)

static func build_gse_delivery_system(workshop_origin: Vector3, crane_pickups: Array) -> Dictionary:
	var root := Node3D.new()
	root.name = "GSEDeliverySystem"
	var paths: Array = []
	var slats: Array = []
	var beacons: Array = []
	var bay_centers: Array = []
	for role in crane_pickups.size():
		var pick: Vector3 = crane_pickups[role]
		var pts := _gse_route(workshop_origin, pick)
		paths.append(pts)
		bay_centers.append(Vector3(pick.x, GSE_BELT_TOP, pick.z))
		var lane := Node3D.new()
		lane.name = "Lane%d" % role
		root.add_child(lane)
		for i in range(pts.size() - 1):
			_gse_segment(lane, pts[i], pts[i + 1])
		# Dispatch scanner arch near the workshop end and a second at mid-run
		var first_dir: Vector3 = (pts[1] - pts[0])
		var yaw := atan2(-first_dir.z, first_dir.x)
		for f in [0.12, 0.6]:
			var wp := _gse_sample_pts(pts, f)
			beacons.append_array(_gse_arch(lane, wp, yaw, GSE_ROLE_COLORS[role % GSE_ROLE_COLORS.size()]))
		_gse_bay(lane, pick, role, beacons)
		# Moving rubber slats along the lane
		var total := _gse_length(pts)
		var n := maxi(int(total / GSE_SLAT_PITCH), 2)
		for i in n:
			var s := _gse_box(lane, Vector3(0.9, 0.04, GSE_BELT_W - 0.6), pts[0], Color("#15181c"), 0.05)
			s.set_meta("role", role)
			s.set_meta("dist", i * total / n)
			s.set_meta("total", total)
			slats.append(s)
	var gse := {"root": root, "paths": paths, "slats": slats, "beacons": beacons, "bay_centers": bay_centers, "time": 0.0}
	tick_gse_delivery(gse, 0.0)
	return gse

static func _gse_length(pts: Array) -> float:
	var l := 0.0
	for i in range(pts.size() - 1):
		l += (pts[i + 1] - pts[i]).length()
	return l

static func _gse_sample_pts(pts: Array, t: float) -> Vector3:
	if pts.is_empty():
		return Vector3.ZERO
	var total := _gse_length(pts)
	return _gse_sample_dist(pts, clampf(t, 0.0, 1.0) * total)

static func _gse_sample_dist(pts: Array, dist: float) -> Vector3:
	var rem := dist
	for i in range(pts.size() - 1):
		var l: float = (pts[i + 1] - pts[i]).length()
		if rem <= l or i == pts.size() - 2:
			return (pts[i] as Vector3).lerp(pts[i + 1], clampf(rem / maxf(l, 0.0001), 0.0, 1.0))
		rem -= l
	return pts[pts.size() - 1]

static func tick_gse_delivery(gse: Dictionary, dt: float) -> void:
	if gse.is_empty():
		return
	gse["time"] = float(gse.get("time", 0.0)) + dt
	var paths: Array = gse.get("paths", [])
	for s in gse.get("slats", []):
		var mi := s as Node3D
		if mi == null or not is_instance_valid(mi):
			continue
		var role: int = mi.get_meta("role")
		if role >= paths.size():
			continue
		var total: float = mi.get_meta("total")
		var d := fposmod(float(mi.get_meta("dist")) + GSE_SPEED * dt, total)
		mi.set_meta("dist", d)
		var pts: Array = paths[role]
		var p := _gse_sample_dist(pts, d)
		var ahead := _gse_sample_dist(pts, minf(d + 0.3, total))
		var behind := _gse_sample_dist(pts, maxf(d - 0.3, 0.0))
		var dir := ahead - behind
		mi.position = p + Vector3(0, 0.02, 0)
		if dir.length() > 0.001:
			mi.rotation.y = atan2(-dir.z, dir.x)
	var t: float = gse["time"]
	for b in gse.get("beacons", []):
		var mi := b as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		var m := mi.material_override as StandardMaterial3D
		if m != null:
			var base: float = mi.get_meta("base_energy", 2.5)
			m.emission_energy_multiplier = base * (0.65 + 0.35 * sin(t * 3.0 + float(mi.get_meta("phase", 0.0))))

static func sample_gse_path(gse: Dictionary, role: int, t: float) -> Vector3:
	var paths: Array = gse.get("paths", [])
	if role < 0 or role >= paths.size():
		return Vector3.ZERO
	return _gse_sample_pts(paths[role], t)
