## Rebuilds the contents of scenes/prefabs/Kestrel.tscn (new exterior design + furnished interior).
## Keeps the 12 module group nodes, their names and their transforms; only their children change.
## Run: Godot --headless --path . -s tools/build_kestrel.gd
extends SceneTree

const PATH := "res://scenes/prefabs/Kestrel.tscn"

const HULL := Color("#ece7f4")
const HULL2 := Color("#cfc8de")
const DARK := Color("#3a3358")
const DARKER := Color("#26213b")
const GLASS := Color("#7fd8e6")
const AMBER := Color("#f7ce59")
const PURPLE := Color("#6c5bc4")
const VIOLET := Color("#b7a0f3")
const ACCENT := Color("#f08a4b")

## Whole-ship scale vs. the original model. Matches Sim.SHIP_K so a 1.75 m crew (2.5 units tall) fits inside.
const K := 1.5

## Module/leg positions at K = 1 (these are multiplied by K when written).
const BASE_POS := {
	"keel": Vector3(0.0, 3.856, -2.52),
	"port": Vector3(-5.68, 3.856, 6.0),
	"bridge": Vector3(0.0, 6.016, -7.2),
	"reactor": Vector3(0.0, 6.016, 1.08),
	"battery": Vector3(3.06, 2.956, 6.48),
	"coolant": Vector3(0.1411, 1.7639, -0.6191),
	"cargo": Vector3(-2.7, 2.596, -0.72),
	"scrubber": Vector3(2.88, 2.776, -0.72),
	"stores": Vector3(-2.7, 2.956, 6.12),
	"engine": Vector3(0.0, 8.1532, 1.08),
	"antenna": Vector3(0.0, 6.2853, 5.76),
	"LandingLeg00": Vector3(-3.7627, 1.1, -9.0117),
	"LandingFoot00": Vector3(-4.1016, 0.1, -8.9568),
	"LandingLeg01": Vector3(-3.9858, 1.1, 4.3948),
	"LandingFoot01": Vector3(-4.2639, 0.1, 4.3697),
	"LandingLeg10": Vector3(4.0233, 1.1, -9.012),
	"LandingFoot10": Vector3(4.3397, 0.1, -9.0299),
	"LandingLeg11": Vector3(4.5314, 1.1, 4.9614),
	"LandingFoot11": Vector3(5.0, 0.0252, 4.9496),
	"thruster": Vector3(6.19, 3.856, 6.0),
}
const PANEL := Color("#d9d3e6")

var ship: Node3D


func _initialize() -> void:
	var packed: PackedScene = load(PATH)
	ship = packed.instantiate()
	for nm in BASE_POS:
		ship.get_node(nm).position = BASE_POS[nm] * K
	for g in ["keel", "port", "thruster", "bridge", "reactor", "battery", "coolant", "cargo", "scrubber", "stores", "engine", "antenna"]:
		var n := ship.get_node(g)
		for c in n.get_children():
			n.remove_child(c)
			c.free()
	_keel(ship.get_node("keel"))
	_engine_pod(ship.get_node("port"))
	_engine_pod(ship.get_node("thruster"))
	_bridge(ship.get_node("bridge"))
	_reactor(ship.get_node("reactor"))
	_battery(ship.get_node("battery"))
	_coolant(ship.get_node("coolant"))
	_module(ship.get_node("cargo"), Color("#f7a28f"), "cargo")
	_module(ship.get_node("scrubber"), Color("#9cdeb1"), "scrubber")
	_module(ship.get_node("stores"), Color("#edbd81"), "stores")
	_turret(ship.get_node("engine"))
	_antenna(ship.get_node("antenna"))
	_legs()
	_set_owner(ship, ship)
	var out := PackedScene.new()
	out.pack(ship)
	var err := ResourceSaver.save(out, PATH)
	print("saved Kestrel: ", error_string(err))
	quit(0 if err == OK else 1)


# ---------------------------------------------------------------- helpers
func _set_owner(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_set_owner(c, o)


func mat(c: Color, rough := 0.5, metal := 0.0, glow := 0.0, alpha := 1.0, double := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func add(parent: Node, nm: String, mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos * K
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func box(parent: Node, nm: String, size: Vector3, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size * K
	return add(parent, nm, b, m, pos, rot)


func cyl(parent: Node, nm: String, r_top: float, r_bot: float, h: float, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, seg := 24) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top * K
	c.bottom_radius = r_bot * K
	c.height = h * K
	c.radial_segments = seg
	return add(parent, nm, c, m, pos, rot)


func sphere(parent: Node, nm: String, r: float, m: Material, pos := Vector3.ZERO, scl := Vector3.ONE, hemi := false, rot := Vector3.ZERO) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r * K
	s.height = r * K * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 28
	s.rings = 14
	return add(parent, nm, s, m, pos, rot, scl)


func ring(parent: Node, nm: String, radius: float, tube: float, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = (radius - tube) * K
	t.outer_radius = (radius + tube) * K
	t.rings = 32
	t.ring_segments = 10
	return add(parent, nm, t, m, pos, rot, scl)


## Smooth cosine interpolation of a [z, a, b, c] section table at z.
func _sec(tab: Array, z: float) -> Array:
	if z <= tab[0][0]:
		return tab[0].slice(1)
	for i in tab.size() - 1:
		var a: Array = tab[i]
		var b: Array = tab[i + 1]
		if z <= b[0]:
			var t: float = (z - a[0]) / (b[0] - a[0])
			t = 0.5 - 0.5 * cos(t * PI)
			var out := []
			for k in range(1, a.size()):
				out.append(lerpf(a[k], b[k], t))
			return out
	return tab[tab.size() - 1].slice(1)


## Lofted shell. Cross-section at angle a: (wx*cos a, yc - hy*sin a). z samples from table [z, wx, hy, yc].
func loft(tab: Array, a0: float, a1: float, nz := 40, na := 28, grow := 0.0, z0 := NAN, z1 := NAN) -> ArrayMesh:
	var zs: float = tab[0][0] if is_nan(z0) else z0
	var ze: float = tab[tab.size() - 1][0] if is_nan(z1) else z1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in nz:
		var za := lerpf(zs, ze, float(i) / nz)
		var zb := lerpf(zs, ze, float(i + 1) / nz)
		var sa := _sec(tab, za)
		var sb := _sec(tab, zb)
		for j in na:
			var aa := lerpf(a0, a1, float(j) / na)
			var ab := lerpf(a0, a1, float(j + 1) / na)
			var p00 := Vector3((sa[0] + grow) * cos(aa), sa[2] - (sa[1] + grow) * sin(aa), za)
			var p01 := Vector3((sa[0] + grow) * cos(ab), sa[2] - (sa[1] + grow) * sin(ab), za)
			var p10 := Vector3((sb[0] + grow) * cos(aa), sb[2] - (sb[1] + grow) * sin(aa), zb)
			var p11 := Vector3((sb[0] + grow) * cos(ab), sb[2] - (sb[1] + grow) * sin(ab), zb)
			for p in [p00, p10, p01, p01, p10, p11]:
				st.add_vertex(p * K)
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- hull + interior
func _keel(n: Node3D) -> void:
	# [z, half-width, half-height, centre-y]
	var tab := [
		[-10.4, 0.5, 0.45, -0.45], [-9.6, 1.3, 0.85, -0.35], [-8.2, 2.3, 1.2, -0.2], [-6.0, 3.1, 1.5, -0.05],
		[-3.0, 3.5, 1.62, 0.0], [3.0, 3.6, 1.62, 0.0], [7.0, 3.4, 1.55, 0.0], [9.4, 2.9, 1.35, 0.0], [10.4, 2.4, 1.1, 0.0]]
	var hull_m := mat(HULL, 0.42, 0.15, 0.0, 1.0, true)
	var glass_m := mat(GLASS, 0.05, 0.0, 0.2, 0.2, true)
	var tex := mat(HULL2, 0.5, 0.2)
	add(n, "HullBody", loft(tab, -0.35, PI + 0.35), hull_m)
	add(n, "Canopy", loft(tab, PI + 0.35, TAU - 0.35, 40, 20, 0.0, -9.0, 9.4), glass_m)
	# Rim beam where the glazing meets the lower hull, both sides.
	for sx in [-1, 1]:
		var rim := loft(tab, (-0.35 if sx > 0 else PI + 0.35) - 0.06, (-0.35 if sx > 0 else PI + 0.35) + 0.06, 40, 1, 0.06, -9.0, 9.4)
		add(n, "Rim%s" % ("R" if sx > 0 else "L"), rim, tex)
	# Canopy ribs.
	for i in 9:
		var z := -8.4 + i * 2.1
		add(n, "Rib%d" % i, loft(tab, PI + 0.3, TAU - 0.3, 1, 20, 0.07, z - 0.09, z + 0.09), tex)
	box(n, "Spine", Vector3(0.22, 0.14, 17.0), tex, Vector3(0, 1.66, 0.4))
	# Exterior accent stripes (recoloured by ShipModel.full).
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		box(n, "Stripe%d" % i, Vector3(0.12, 0.5, 15.0), mat(ACCENT, 0.7), Vector3(sx * 3.6, -0.25, 0.8))
	# Belly keel fin + nose probe.
	box(n, "BellyFin", Vector3(0.3, 0.55, 14.0), tex, Vector3(0, -1.75, 0.5))
	cyl(n, "NoseProbe", 0.05, 0.12, 2.4, mat(DARK, 0.4, 0.5), Vector3(0, -0.45, -11.5), Vector3(90, 0, 0), 10)
	# --- interior ---
	var floor_m := mat(Color("#8c86a3"), 0.7)
	var dark := mat(DARK, 0.6, 0.2)
	box(n, "Deck", Vector3(5.2, 0.12, 16.8), floor_m, Vector3(0, -0.98, 0.6))
	box(n, "DeckRunner", Vector3(1.2, 0.13, 16.0), mat(DARKER, 0.8), Vector3(0, -0.97, 0.6))
	for sx in [-1, 1]:
		box(n, "DeckLight%s" % sx, Vector3(0.1, 0.14, 15.0), mat(GLASS, 0.3, 0.0, 2.2), Vector3(sx * 1.55, -0.96, 0.6))
		box(n, "CeilLight%s" % sx, Vector3(0.22, 0.06, 15.0), mat(Color("#fff2c9"), 0.3, 0.0, 3.0), Vector3(sx * 0.9, 1.5, 0.4))
	# Bulkheads with doorways at z=-4.6 and z=3.0.
	for bz in [-4.6, 3.0]:
		for sx in [-1, 1]:
			box(n, "Bulkhead", Vector3(1.55, 2.4, 0.16), tex, Vector3(sx * 1.75, 0.29, bz))
		box(n, "Lintel", Vector3(2.0, 0.5, 0.16), tex, Vector3(0, 1.25, bz))
		box(n, "DoorFrame", Vector3(2.0, 0.07, 0.2), mat(GLASS, 0.3, 0.0, 1.5), Vector3(0, 0.99, bz))
	# Crew quarters (aft): bunks both sides.
	for sx in [-1, 1]:
		for k in 2:
			var z := 5.0 + k * 2.6
			box(n, "BunkFrame", Vector3(1.5, 0.12, 2.3), dark, Vector3(sx * 2.4, -0.55, z))
			box(n, "BunkMatt", Vector3(1.4, 0.2, 2.1), mat(Color("#7f77c9"), 0.9), Vector3(sx * 2.4, -0.42, z))
			box(n, "BunkUpper", Vector3(1.4, 0.2, 2.1), mat(Color("#9cdeb1"), 0.9), Vector3(sx * 2.4, 0.52, z))
			box(n, "BunkPost", Vector3(0.1, 1.5, 0.1), dark, Vector3(sx * 1.72, -0.2, z - 1.05))
	# Mess area: table + benches.
	cyl(n, "TablePost", 0.12, 0.18, 0.8, dark, Vector3(0, -0.55, -1.0), Vector3.ZERO, 12)
	cyl(n, "TableTop", 0.95, 0.95, 0.08, mat(PANEL, 0.5), Vector3(0, -0.1, -1.0), Vector3.ZERO, 28)
	for sx in [-1, 1]:
		box(n, "Bench", Vector3(0.5, 0.35, 2.2), mat(Color("#7f77c9"), 0.9), Vector3(sx * 1.55, -0.72, -1.0))
	# Forward: engineering lockers + tool wall, hatch up to the bridge.
	for sx in [-1, 1]:
		box(n, "Locker", Vector3(0.6, 1.8, 2.4), dark, Vector3(sx * 2.85, -0.05, -7.0))
		box(n, "LockerStripe", Vector3(0.02, 0.2, 2.2), mat(AMBER, 0.4, 0.0, 0.8), Vector3(sx * 2.54, 0.2, -7.0))
	box(n, "ForwardWall", Vector3(5.6, 2.0, 0.2), tex, Vector3(0, 0.0, -8.6))
	box(n, "NavScreen", Vector3(2.4, 0.9, 0.06), mat(GLASS, 0.2, 0.0, 2.5), Vector3(0, 0.25, -8.46))
	# Ceiling hatch ring above the bridge access.
	ring(n, "BridgeHatch", 0.95, 0.07, mat(AMBER, 0.4, 0.3, 0.6), Vector3(0, 1.55, -6.6))
	# Overhead pipes.
	for sx in [-1, 1]:
		cyl(n, "Pipe", 0.07, 0.07, 14.0, mat(HULL2, 0.4, 0.5), Vector3(sx * 2.7, 1.0, 0.6), Vector3(90, 0, 0), 10)


# ---------------------------------------------------------------- engines
func _engine_pod(n: Node3D) -> void:
	var dirn := -signf(n.position.x)  # toward the hull
	var r := 1.35
	var hull := mat(HULL, 0.4, 0.3)
	var dark := mat(DARK, 0.45, 0.5)
	# Pylon to the hull.
	box(n, "Pylon", Vector3(3.2, 0.5, 3.4), hull, Vector3(dirn * 2.0, 0.0, -0.4))
	box(n, "PylonStripe", Vector3(3.2, 0.52, 0.5), mat(ACCENT, 0.6), Vector3(dirn * 2.0, 0.0, 0.8))
	# Nacelle body (accent recoloured by ShipModel.full).
	add(n, "EngineBody", _capsule(r, 6.2), mat(ACCENT, 0.4, 0.3), Vector3(0, 0, -0.4), Vector3(90, 0, 0))
	for i in 3:
		ring(n, "Band%d" % i, r + 0.02, 0.07, hull, Vector3(0, 0, -2.2 + i * 1.5), Vector3(90, 0, 0))
	add(n, "ForwardCone", _capsule(0.95, 2.6), hull, Vector3(0, 0, -4.2), Vector3(90, 0, 0))
	ring(n, "Intake", r * 0.82, 0.12, mat(DARKER, 0.5), Vector3(0, 0, -3.35), Vector3(90, 0, 0))
	# Rear bell.
	cyl(n, "EngineNozzle", r * 1.15, r * 0.7, 2.0, dark, Vector3(0, 0, 3.7), Vector3(90, 0, 0), 28)
	cyl(n, "NozzleLip", r * 1.2, r * 1.2, 0.12, mat(AMBER, 0.4, 0.5, 0.5), Vector3(0, 0, 4.7), Vector3(90, 0, 0), 28)
	cyl(n, "NozzleGlow", r * 0.85, r * 0.85, 0.05, mat(Color("#ffb347"), 0.2, 0.0, 3.5), Vector3(0, 0, 4.45), Vector3(90, 0, 0), 28)
	# Stabiliser fins.
	for a in [0.0, 120.0, 240.0]:
		var d := Vector3(sin(deg_to_rad(a)), cos(deg_to_rad(a)), 0)
		box(n, "Fin", Vector3(0.12, 0.9, 1.6), hull, d * (r + 0.35) + Vector3(0, 0, 2.2)).rotation_degrees = Vector3(0, 0, -a)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r * K
	c.height = h * K
	c.radial_segments = 28
	c.rings = 8
	return c


# ---------------------------------------------------------------- bridge
func _bridge(n: Node3D) -> void:
	var hull := mat(HULL, 0.4, 0.2)
	var dark := mat(DARK, 0.55, 0.2)
	var glass := mat(GLASS, 0.05, 0.0, 0.25, 0.28, true)
	# Tub + nose wedge.
	box(n, "Body", Vector3(5.04, 0.9, 5.76), hull, Vector3(0, -0.75, 0))
	box(n, "Chin", Vector3(3.6, 0.7, 1.6), hull, Vector3(0, -0.55, -3.2), Vector3(-12, 0, 0))
	# Glass canopy dome.
	sphere(n, "Glass", 1.0, glass, Vector3(0, -0.3, -0.1), Vector3(2.45, 1.45, 2.85), true)
	for i in 3:
		ring(n, "Arch%d" % i, 1.0, 0.025, hull, Vector3(0, -0.3, -1.6 + i * 1.6), Vector3(90, 0, 0), Vector3(2.35 - abs(i - 1) * 0.85, 1.0, 1.4 - abs(i - 1) * 0.35))
	box(n, "RoofBeam", Vector3(0.14, 0.12, 4.8), hull, Vector3(0, 1.15, -0.1))
	# Consoles, seats, controls.
	box(n, "Dash", Vector3(4.0, 0.55, 0.9), dark, Vector3(0, -0.1, -1.95), Vector3(-18, 0, 0))
	for k in 3:
		box(n, "Screen%d" % k, Vector3(1.0, 0.45, 0.04), mat(GLASS if k != 1 else AMBER, 0.2, 0.0, 2.2), Vector3(-1.3 + k * 1.3, 0.04, -1.8), Vector3(-18, 0, 0))
	for sx in [-0.95, 0.95]:
		box(n, "SeatBase", Vector3(0.9, 0.3, 0.95), dark, Vector3(sx, -0.55, 0.5))
		box(n, "SeatBack", Vector3(0.9, 1.0, 0.2), dark, Vector3(sx, 0.05, 1.0), Vector3(12, 0, 0))
		box(n, "Headrest", Vector3(0.5, 0.3, 0.18), mat(ACCENT, 0.8), Vector3(sx, 0.7, 1.12))
		cyl(n, "Yoke", 0.05, 0.05, 0.6, hull, Vector3(sx, -0.25, -0.5), Vector3(-40, 0, 0), 8)
	box(n, "Overhead", Vector3(2.2, 0.12, 0.9), dark, Vector3(0, 1.0, -0.5))
	for k in 4:
		box(n, "Switch", Vector3(0.12, 0.05, 0.12), mat(Color("#ed7d8d"), 0.3, 0.0, 2.0), Vector3(-0.5 + k * 0.33, 0.94, -0.5))
	# Antenna nubs.
	for sx in [-1, 1]:
		cyl(n, "Sensor", 0.06, 0.06, 0.8, dark, Vector3(sx * 2.6, -0.2, -2.7), Vector3(0, 0, 0), 8)


# ---------------------------------------------------------------- power / battery / coolant
func _reactor(n: Node3D) -> void:
	var purple := mat(PURPLE, 0.5, 0.3)
	var dark := mat(DARK, 0.5, 0.4)
	box(n, "PowerBlock", Vector3(3.96, 1.2, 4.32), purple, Vector3(0, -0.55, 0))
	box(n, "PowerDeck", Vector3(3.5, 0.14, 3.9), dark, Vector3(0, 0.06, 0))
	add(n, "GlowingCore", _capsule(0.8, 2.2), mat(VIOLET, 0.3, 0.0, 3.0), Vector3(0, 0.1, 0))
	for i in 3:
		ring(n, "Coil%d" % i, 1.05, 0.09, dark, Vector3(0, -0.35 + i * 0.55, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			cyl(n, "Strut", 0.08, 0.08, 1.9, dark, Vector3(sx * 1.3, 0.2, sz * 1.5), Vector3.ZERO, 8)
	box(n, "VentL", Vector3(0.1, 0.6, 3.2), mat(DARKER, 0.7), Vector3(-2.0, -0.55, 0))
	box(n, "VentR", Vector3(0.1, 0.6, 3.2), mat(DARKER, 0.7), Vector3(2.0, -0.55, 0))
	cyl(n, "Conduit", 0.18, 0.18, 0.5, mat(AMBER, 0.4, 0.3, 0.5), Vector3(0, -1.3, 0), Vector3.ZERO, 10)


func _battery(n: Node3D) -> void:
	var dark := mat(DARK, 0.55, 0.3)
	box(n, "Battery", Vector3(2.88, 1.9, 3.6), dark, Vector3(0, -0.2, 0))
	box(n, "BatteryTrim", Vector3(2.94, 0.3, 3.66), mat(AMBER, 0.5, 0.2, 0.2), Vector3(0, 0.45, 0))
	for k in 4:
		box(n, "Cell%d" % k, Vector3(2.5, 1.5, 0.07), mat(Color("#4a4177"), 0.5), Vector3(0, -0.25, -1.35 + k * 0.9))
	for sx in [-0.7, 0.7]:
		cyl(n, "Terminal", 0.14, 0.14, 0.35, mat(HULL, 0.3, 0.7), Vector3(sx, 1.0, 0.0), Vector3.ZERO, 12)
	for k in 5:
		box(n, "Gauge", Vector3(0.1, 0.1, 0.1), mat(Color("#9cdeb1"), 0.3, 0.0, 2.5), Vector3(1.47, 0.0 + k * 0.0 - 0.1, -1.4 + k * 0.7))


func _coolant(n: Node3D) -> void:
	var panel := mat(Color("#dfe7f0"), 0.45, 0.3)
	var fin := mat(Color("#a9b5c9"), 0.4, 0.5)
	box(n, "Radiator", Vector3(12.6, 0.4, 9.0), panel, Vector3.ZERO)
	for i in 6:
		box(n, "Fin%02d" % i, Vector3(12.0, 0.9, 0.18), fin, Vector3(0, 0.3, -3.6 + i * 1.44))
	for sx in [-1, 1]:
		box(n, "Spar%d" % sx, Vector3(0.35, 0.35, 9.2), mat(DARK, 0.5, 0.4), Vector3(sx * 6.0, 0, 0))
	box(n, "PipeCore", Vector3(12.8, 0.14, 0.28), mat(ACCENT, 0.5, 0.2, 0.3), Vector3(0, 0.25, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			cyl(n, "Strut", 0.12, 0.12, 2.6, mat(DARK, 0.5, 0.4), Vector3(sx * 5.4, -1.2, sz * 3.6), Vector3(0, 0, sx * 28), 8)


# ---------------------------------------------------------------- cargo pods
func _module(n: Node3D, col: Color, kind: String) -> void:
	var body := mat(col, 0.55, 0.15)
	var dark := mat(DARK, 0.6, 0.2)
	box(n, "Module", Vector3(2.52, 2.1, 4.68), body, Vector3(0, -0.05, 0))
	box(n, "ModuleTrim", Vector3(2.58, 0.28, 4.74), dark, Vector3(0, 0.45, 0))
	for k in 3:
		box(n, "Rib%d" % k, Vector3(2.6, 2.14, 0.14), dark, Vector3(0, -0.05, -1.7 + k * 1.7))
	box(n, "Skid", Vector3(1.8, 0.2, 4.2), dark, Vector3(0, -1.2, 0))
	match kind:
		"cargo":
			box(n, "Hatch", Vector3(1.4, 1.1, 0.06), mat(AMBER, 0.5, 0.2), Vector3(0, -0.15, -2.36))
			for s in [-1, 1]:
				cyl(n, "Handle", 0.05, 0.05, 0.9, mat(HULL, 0.3, 0.7), Vector3(s * 0.45, -0.15, -2.45), Vector3.ZERO, 8)
			for k in 3:
				box(n, "Strap", Vector3(2.6, 0.12, 0.2), mat(Color("#ed7d8d"), 0.8), Vector3(0, 1.05, -1.4 + k * 1.4))
		"scrubber":
			cyl(n, "Fan", 0.8, 0.8, 0.08, dark, Vector3(0, 0.0, -2.38), Vector3(90, 0, 0), 24)
			for k in 4:
				box(n, "Blade%d" % k, Vector3(1.5, 0.08, 0.04), mat(HULL, 0.4, 0.5), Vector3(0, 0, -2.44), Vector3(0, 0, k * 45))
			cyl(n, "Duct", 0.3, 0.3, 1.6, mat(HULL2, 0.4, 0.5), Vector3(0.5, 1.4, 0.5), Vector3.ZERO, 10)
			box(n, "O2Light", Vector3(0.3, 0.3, 0.06), mat(Color("#9cdeb1"), 0.3, 0.0, 3.0), Vector3(-0.8, 0.55, -2.36))
		"stores":
			for sx in [-0.62, 0.62]:
				cyl(n, "Tank", 0.5, 0.5, 3.6, mat(HULL, 0.35, 0.4), Vector3(sx, 1.35, 0), Vector3(90, 0, 0), 20)
			box(n, "Label", Vector3(0.9, 0.5, 0.06), mat(Color("#7fd8e6"), 0.4, 0.0, 1.0), Vector3(0, 0.0, -2.36))


# ---------------------------------------------------------------- turret + antenna
func _turret(n: Node3D) -> void:
	var hull := mat(HULL, 0.4, 0.3)
	var dark := mat(DARK, 0.45, 0.5)
	cyl(n, "TurretPivot", 1.1, 1.3, 0.55, dark, Vector3(0, -0.5, 0), Vector3.ZERO, 24)
	ring(n, "TurretRing", 1.2, 0.07, mat(AMBER, 0.4, 0.4, 0.5), Vector3(0, -0.25, 0))
	box(n, "TurretBody", Vector3(2.1, 0.95, 2.3), hull, Vector3(0, 0.2, 0))
	sphere(n, "TurretDome", 0.55, mat(GLASS, 0.1, 0.0, 0.7, 0.8), Vector3(0, 0.75, 0.2), Vector3.ONE, true)
	for i in 2:
		var sx := -0.62 if i == 0 else 0.62
		cyl(n, "Cannon%d" % i, 0.13, 0.17, 3.6, mat(ACCENT, 0.4, 0.4), Vector3(sx, 0.25, -2.0), Vector3(90, 0, 0), 14)
		cyl(n, "Shroud%d" % i, 0.28, 0.28, 1.0, dark, Vector3(sx, 0.25, -1.0), Vector3(90, 0, 0), 14)
		cyl(n, "Muzzle%d" % i, 0.2, 0.2, 0.25, dark, Vector3(sx, 0.25, -3.7), Vector3(90, 0, 0), 14)


func _antenna(n: Node3D) -> void:
	var hull := mat(HULL, 0.4, 0.3)
	var dark := mat(DARK, 0.5, 0.4)
	cyl(n, "Base", 0.5, 0.65, 0.35, dark, Vector3(0, -0.45, 0), Vector3.ZERO, 16)
	cyl(n, "Mast", 0.12, 0.17, 1.6, hull, Vector3(0, 0.45, 0), Vector3.ZERO, 12)
	sphere(n, "Dish", 1.15, hull, Vector3(0, 1.4, -0.1), Vector3(1, 0.55, 1), true, Vector3(-125, 0, 0))
	cyl(n, "FeedArm", 0.04, 0.04, 1.3, dark, Vector3(0, 1.75, -0.7), Vector3(-35, 0, 0), 8)
	sphere(n, "Tip", 0.16, mat(ACCENT, 0.3, 0.0, 1.5), Vector3(0, 2.15, -1.1))


# ---------------------------------------------------------------- landing gear
func _legs() -> void:
	var dark := mat(DARK, 0.5, 0.4)
	var pad := mat(ACCENT, 0.7)
	for nm in ["00", "01", "10", "11"]:
		var leg := ship.get_node("LandingLeg" + nm) as MeshInstance3D
		var foot := ship.get_node("LandingFoot" + nm) as MeshInstance3D
		var c := CylinderMesh.new()
		c.top_radius = 0.2 * K
		c.bottom_radius = 0.26 * K
		c.height = 2.4 * K
		c.radial_segments = 12
		leg.mesh = c
		leg.material_override = dark
		var f := CylinderMesh.new()
		f.top_radius = 0.7 * K
		f.bottom_radius = 0.95 * K
		f.height = 0.22 * K
		f.radial_segments = 20
		foot.mesh = f
		foot.material_override = pad
