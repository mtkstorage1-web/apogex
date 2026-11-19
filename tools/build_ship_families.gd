## Deterministic editable primitive spacecraft. Run with godot --headless --path . -s tools/build_ship_families.gd
extends SceneTree

const IDS := ["keel", "port", "bridge", "reactor", "battery", "coolant", "cargo", "scrubber", "stores", "engine", "antenna", "thruster"]
const FAMILIES := ["lancer", "hauler", "halo", "bulwark"]
var body: StandardMaterial3D
var trim: StandardMaterial3D
var dark: StandardMaterial3D
var light: StandardMaterial3D
var glass: StandardMaterial3D
var family: String
var serial := 0

func _initialize() -> void:
	var reference: Node3D = load("res://scenes/prefabs/Kestrel.tscn").instantiate()
	DirAccess.make_dir_recursive_absolute("res://scenes/prefabs/ships")
	for f in FAMILIES:
		family = f
		serial = 0
		palette()
		var ship := Node3D.new()
		ship.name = f.capitalize()
		for id in IDS:
			var n := Node3D.new()
			n.name = id
			n.transform = reference.get_node(id).transform
			ship.add_child(n)
			match id:
				"keel": hull(n)
				"port", "thruster": drive(n)
				"bridge": bridge(n)
				"coolant": radiator(n)
				"engine": turret(n)
				"antenna": antenna(n)
				_: utility(n, id)
			# Each module has an explicit structural interface, included in its envelope.
			if id in ["port", "thruster"]:
				var side := -signf(n.position.x)
				box(n, "MountFlange", Vector3(1.4, .22, .72), Vector3(side * .8, 0, -.15), trim)
				box(n, "MountBrace", Vector3(1.25, .12, .15), Vector3(side * .65, -.22, -.15), dark, Vector3(0, 0, side * 18))
			else:
				box(n, "MountFlange", Vector3(.65, .18, .7), Vector3(0, -.75, 0), dark)
				cylinder(n, "MountCollar", .27, .36, .18, Vector3(0, -.64, 0), trim)
			fit(n, bounds(reference.get_node(id)))
			if id == "keel": gear(n, reference)
		owners(ship, ship)
		var packed := PackedScene.new()
		assert(packed.pack(ship) == OK)
		var path := "res://scenes/prefabs/ships/%s.tscn" % f
		assert(ResourceSaver.save(packed, path) == OK)
		# Godot 4.7 assigns random editor node IDs at packing time. They are
		# optional in text scenes; omit them to keep regeneration byte-stable.
		var text := FileAccess.get_file_as_string(path)
		var random_ids := RegEx.new()
		random_ids.compile(" unique_id=[0-9]+")
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(random_ids.sub(text, "", true))
		file.close()
		print("Saved ", path, " (", count_meshes(ship), " editable meshes)")
		ship.free()
	reference.free()
	quit()

func material(color: String, metal := .35, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_scene_unique_id = "Material_" + color
	m.albedo_color = Color(color)
	m.metallic = metal
	m.roughness = .38
	if emission > 0:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = emission
	return m

func palette() -> void:
	var colors: Array = {
		"lancer": ["a71938", "f2efea", "252837", "ff576b", "63cbe3"],
		"hauler": ["dfa82c", "77818c", "30373e", "ffd56e", "80bfd0"],
		"halo": ["e1ede7", "269b98", "244550", "65ffe1", "4098ab"],
		"bulwark": ["495360", "e7872e", "202934", "ffb24d", "e6a34d"]}[family]
	body = material(colors[0])
	trim = material(colors[1])
	dark = material(colors[2], .6)
	light = material(colors[3], .25, 2)
	glass = material(colors[4], .65, .35)

func mesh(n: Node3D, label: String, shape: PrimitiveMesh, p: Vector3, m: Material, r := Vector3.ZERO, s := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	serial += 1
	shape.resource_scene_unique_id = "Mesh_%04d" % serial
	mi.name = label if label in ["MountFlange", "MountBrace", "MountCollar", "NozzleGlow"] else "%s_%03d" % [label, serial]
	mi.mesh = shape
	mi.material_override = m
	mi.position = p
	mi.rotation_degrees = r
	mi.scale = s
	n.add_child(mi)
	return mi

func box(n: Node3D, label: String, size: Vector3, p: Vector3, m: Material, r := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(n, label, b, p, m, r)

func prism(n: Node3D, label: String, size: Vector3, p: Vector3, m: Material, r := Vector3.ZERO) -> MeshInstance3D:
	var b := PrismMesh.new()
	b.size = size
	return mesh(n, label, b, p, m, r)

func cylinder(n: Node3D, label: String, rt: float, rb: float, h: float, p: Vector3, m: Material, r := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 24
	return mesh(n, label, c, p, m, r)

func orb(n: Node3D, label: String, p: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = .5
	s.height = 1
	s.radial_segments = 32
	s.rings = 16
	return mesh(n, label, s, p, m, Vector3.ZERO, size)

func capsule(n: Node3D, label: String, p: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = .5
	c.height = 2
	c.radial_segments = 32
	return mesh(n, label, c, p, m, Vector3(90, 0, 0), Vector3(size.x, size.z / 2, size.y))

func ring(n: Node3D, label: String, radius: float, tube: float, p: Vector3, m: Material, r := Vector3.ZERO, s := Vector3.ONE) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = radius - tube
	t.outer_radius = radius + tube
	t.rings = 32
	t.ring_segments = 8
	return mesh(n, label, t, p, m, r, s)

func hull(n: Node3D) -> void:
	match family:
		"lancer":
			prism(n, "NeedleForebody", Vector3(.85, 2.5, 1.0), Vector3(0, 0, -.55), body, Vector3(-90, 0, 0))
			box(n, "Spine", Vector3(.65, .65, 2.2), Vector3(0, 0, .4), body)
			for side in [-1, 1]:
				prism(n, "SweptDelta", Vector3(1.7, .16, 1.8), Vector3(side * .7, -.15, .25), trim, Vector3(0, side * -22, 0))
				box(n, "WingLeadingEdge", Vector3(.055, .07, 1.6), Vector3(side * .95, -.03, .12), body, Vector3(0, side * 30, 0))
				prism(n, "TailBlade", Vector3(.12, .7, .65), Vector3(side * .38, .35, 1.1), body, Vector3(0, 0, side * 22))
			cylinder(n, "NoseLance", .015, .12, 1, Vector3(0, 0, -1.8), trim, Vector3(90, 0, 0))
		"hauler":
			box(n, "FreightSpine", Vector3(1.15, .75, 3.2), Vector3.ZERO, body)
			for z in [-1.05, 0.0, 1.05]:
				box(n, "StructuralBulkhead", Vector3(1.85, 1.05, .13), Vector3(0, 0, z), dark)
				for side in [-1, 1]:
					box(n, "ExternalContainer", Vector3(.56, .8, .85), Vector3(side * .68, .05, z), body)
					box(n, "ContainerLatch", Vector3(.08, 1.0, .15), Vector3(side * .99, .05, z), trim)
		"halo":
			capsule(n, "PearlPressureHull", Vector3.ZERO, Vector3(1.35, .9, 3.5), body)
			for z in [-1.05, -.35, .35, 1.05]:
				ring(n, "ExoskeletonHoop", .77, .045, Vector3(0, 0, z), trim, Vector3(90, 0, 0), Vector3(1, 1, .72))
			for side in [-1, 1]:
				capsule(n, "SideSponson", Vector3(side * .77, -.1, .1), Vector3(.25, .3, 2.3), trim)
		"bulwark":
			prism(n, "WedgeCitadel", Vector3(1.85, 3.3, 1), Vector3.ZERO, body, Vector3(-90, 0, 0))
			box(n, "ArmoredSpine", Vector3(.65, .55, 2.8), Vector3(0, .17, .1), dark)
			for side in [-1, 1]:
				for z in [-1.1, -.35, .4, 1.15]:
					box(n, "OverlappingArmor", Vector3(.7, .2, .62), Vector3(side * .55, .42, z), body, Vector3(0, 0, side * 15))
					for x in [.3, .8]:
						orb(n, "ArmorRivet", Vector3(side * x, .54, z), Vector3(.055, .055, .055), trim)
	for i in 9:
		box(n, "SpinePanelSeam", Vector3(.35, .025, .018), Vector3(0, .51, -1.2 + i * .3), dark)
	for side in [-1, 1]:
		box(n, "NavigationLight", Vector3(.08, .06, .36), Vector3(side * .7, .3, -.85), light)

func drive(n: Node3D) -> void:
	var side := signf(n.position.x)
	var assembly := Node3D.new()
	assembly.name = "Nacelle"
	n.add_child(assembly)
	match family:
		"lancer":
			assembly.rotation_degrees.z = side * 12
			assembly.rotation_degrees.y = side * -5
			prism(assembly, "StreamlinedCowl", Vector3(.86, 2.5, .86), Vector3(0, 0, -.25), body, Vector3(-90, 0, 0))
			cylinder(assembly, "Turbine", .42, .42, 2, Vector3.ZERO, dark, Vector3(90, 0, 0))
			for i in 4:
				box(assembly, "CoolingBlade", Vector3(.08, .7, .6), Vector3((i - 1.5) * .2, .15, .45), trim)
		"hauler":
			cylinder(assembly, "FatDriveDrum", .66, .66, 2.3, Vector3(0, 0, -.1), body, Vector3(90, 0, 0))
			for z in [-.9, -.3, .3, .9]:
				ring(assembly, "HeavyBand", .68, .07, Vector3(0, 0, z), trim, Vector3(90, 0, 0))
			for side_x in [-1, 1]:
				box(assembly, "ServiceRail", Vector3(.12, .16, 2.4), Vector3(side_x * .6, .4, 0), dark)
		"halo":
			capsule(assembly, "IonCore", Vector3(0, 0, -.3), Vector3(.65, .65, 2.7), body)
			for z in [-.9, -.3, .3, .9]:
				ring(assembly, "IonLens", .56, .055, Vector3(0, 0, z), light, Vector3(90, 0, 0))
			for side_x in [-1, 1]:
				box(assembly, "LensRail", Vector3(.06, .1, 2.4), Vector3(side_x * .5, 0, 0), trim)
		"bulwark":
			box(assembly, "ArmoredDrive", Vector3(1.05, .9, 2.15), Vector3(0, 0, -.15), body)
			for z in [-.8, -.25, .3]:
				box(assembly, "BlastCollar", Vector3(1.15, 1.02, .15), Vector3(0, 0, z), dark)
			for side_x in [-1, 1]:
				prism(assembly, "BlastCheek", Vector3(.3, .8, 1.4), Vector3(side_x * .55, 0, 0), trim)
	cylinder(assembly, "NozzleBell", .48, .32, .5, Vector3(0, 0, 1.15), dark, Vector3(90, 0, 0))
	ring(assembly, "NozzleRim", .46, .045, Vector3(0, 0, 1.4), trim, Vector3(90, 0, 0))
	# Direct child: ShipModel.flame resolves the position without walking nested transforms.
	var tip: Vector3 = assembly.transform * Vector3(0, 0, 1.405)
	var glow := cylinder(n, "NozzleGlow", .35, .35, .018, tip, light, Vector3(90, 0, 0))
	glow.basis = assembly.basis * glow.basis
	for i in 4:
		box(assembly, "IntakeGrille", Vector3(.68, .055, .04), Vector3(0, -.24 + i * .16, -1.22), dark)

func bridge(n: Node3D) -> void:
	box(n, "BridgeSill", Vector3(1.7, .3, 1.75), Vector3(0, -.4, 0), body)
	match family:
		"lancer":
			orb(n, "BubbleCanopy", Vector3(0, .03, -.1), Vector3(1.48, 1.1, 1.95), glass)
			for side in [-1, 1]:
				box(n, "CanopyRail", Vector3(.07, .07, 1.6), Vector3(side * .67, -.04, 0), trim)
		"hauler":
			box(n, "ControlCab", Vector3(1.65, .85, 1.5), Vector3(0, .1, 0), body)
			box(n, "CabGlazing", Vector3(1.5, .45, .025), Vector3(0, .2, -.76), glass)
			for x in [-.5, 0, .5]:
				box(n, "WindowMullion", Vector3(.065, .5, .05), Vector3(x, .2, -.79), dark)
		"halo":
			orb(n, "ObservationDome", Vector3(0, -.03, 0), Vector3(1.65, 1.2, 1.75), glass)
			ring(n, "DomeEquator", .86, .05, Vector3(0, -.1, 0), trim)
			ring(n, "ZenithCrown", .36, .035, Vector3(0, .51, 0), body)
		"bulwark":
			prism(n, "BridgeBunker", Vector3(1.8, 1.8, 1.1), Vector3(0, .05, 0), body, Vector3(-90, 0, 0))
			box(n, "SlitWindow", Vector3(1.4, .12, .04), Vector3(0, .13, -.76), glass)
			box(n, "BlastVisor", Vector3(1.6, .15, .4), Vector3(0, .33, -.8), dark)
	for side in [-1, 1]:
		for z in [-.55, 0, .55]:
			box(n, "BridgePanel", Vector3(.13, .12, .3), Vector3(side * .86, -.26, z), trim)
		box(n, "DockingLamp", Vector3(.12, .1, .04), Vector3(side * .64, -.35, -.92), light)

func radiator(n: Node3D) -> void:
	# Thinness and underside drop match Kestrel's unusually wide belly radiator.
	box(n, "ThermalManifold", Vector3(.25, .25, 1.85), Vector3.ZERO, body)
	for side in [-1, 1]:
		match family:
			"lancer":
				for i in 5:
					prism(n, "BladeRadiator", Vector3(1.4, .055, .23), Vector3(side * .75, 0, -.75 + i * .37), trim, Vector3(0, side * -18, 0))
			"hauler":
				box(n, "SquareRadiatorPlate", Vector3(1.3, .14, 1.8), Vector3(side * .77, 0, 0), trim)
				for z in [-.75, -.45, -.15, .15, .45, .75]:
					box(n, "HeatChannel", Vector3(1.2, .1, .045), Vector3(side * .77, .11, z), dark)
			"halo":
				for k in 3:
					var x: float = side * (.36 + k * .43)
					box(n, "FoldingSolarLeaf", Vector3(.4, .045, 1.85), Vector3(x, .05, 0), glass)
					for z in [-.8, -.4, 0, .4, .8]:
						box(n, "SolarCellBus", Vector3(.38, .012, .018), Vector3(x, .08, z), trim)
					cylinder(n, "FoldingHinge", .045, .045, 1.9, Vector3(x + side * .21, .05, 0), body, Vector3(90, 0, 0))
			"bulwark":
				for k in 4:
					box(n, "ArmoredThermalLouver", Vector3(1.35, .13, .38), Vector3(side * .78, .02, -.66 + k * .44), body, Vector3(12, 0, 0))
				box(n, "ThermalGuard", Vector3(.12, .24, 1.9), Vector3(side * 1.45, 0, 0), trim)
		box(n, "MountOutrigger", Vector3(1.3, .12, .16), Vector3(side * .67, -.15, 0), dark)
		for z in [-.7, .7]:
			cylinder(n, "UndersidePipe", .035, .035, .65, Vector3(side * .9, -.43, z), trim)
		box(n, "ThermalStatus", Vector3(.15, .025, .07), Vector3(side * .35, .15, -.7), light)

func utility(n: Node3D, id: String) -> void:
	match family:
		"lancer":
			prism(n, "AerodynamicFairing", Vector3(1.3, 1.9, 1), Vector3.ZERO, body, Vector3(-90, 0, 0))
			for side in [-1, 1]:
				box(n, "WhiteFairingRail", Vector3(.1, .16, 1.7), Vector3(side * .55, .25, 0), trim)
		"hauler":
			if id == "stores":
				for z in [-.52, .52]:
					orb(n, "SphericalReservoir", Vector3(0, .1, z), Vector3(1.2, 1.35, 1.1), body)
					ring(n, "TankBelt", .61, .045, Vector3(0, .1, z), trim, Vector3(90, 0, 0))
			else:
				for y in [-.28, .3]:
					box(n, "StackedContainer", Vector3(1.3, .5, 1.8), Vector3(0, y, 0), body)
			for z in [-.8, 0, .8]:
				box(n, "ExternalClamp", Vector3(1.42, 1.3, .1), Vector3(0, .05, z), dark)
		"halo":
			capsule(n, "PressureVessel", Vector3.ZERO, Vector3(1.2, 1.0, 1.9), body)
			for z in [-.65, 0, .65]:
				ring(n, "VesselFrame", .63, .04, Vector3(0, 0, z), trim, Vector3(90, 0, 0), Vector3(1, 1, .85))
		"bulwark":
			box(n, "SealedArmoredCase", Vector3(1.2, 1, 1.75), Vector3.ZERO, dark)
			for side in [-1, 1]:
				box(n, "ArmorCheek", Vector3(.18, 1.1, 1.9), Vector3(side * .62, 0, 0), body, Vector3(0, 0, side * 9))
			for z in [-.6, 0, .6]:
				box(n, "HazardBand", Vector3(1.3, .04, .12), Vector3(0, .56, z), trim, Vector3(0, 20, 0))
	match id:
		"reactor":
			cylinder(n, "ReactorCap", .35, .4, .35, Vector3(0, .6, 0), trim)
			ring(n, "ContainmentGlow", .35, .035, Vector3(0, .8, 0), light)
			for side in [-1, 1]:
				cylinder(n, "CoolantFeed", .065, .065, 1.55, Vector3(side * .45, .4, 0), dark, Vector3(90, 0, 0))
		"battery":
			for z in [-.55, -.18, .18, .55]:
				box(n, "CellSeparator", Vector3(1.1, .06, .04), Vector3(0, .54, z), trim)
			for x in [-.3, .3]:
				cylinder(n, "PowerTerminal", .08, .08, .22, Vector3(x, .65, 0), light)
		"cargo":
			box(n, "CargoHatch", Vector3(.85, .65, .07), Vector3(0, 0, -.94), trim)
			for x in [-.3, .3]:
				box(n, "HatchHandle", Vector3(.065, .35, .08), Vector3(x, 0, -1), dark)
		"scrubber":
			cylinder(n, "FilterFace", .42, .42, .06, Vector3(0, .05, -.96), dark, Vector3(90, 0, 0))
			for a in 6:
				box(n, "FilterGrille", Vector3(.75, .025, .035), Vector3(0, .05, -1), trim, Vector3(0, 0, a * 30))
			cylinder(n, "OxygenChimney", .12, .12, .5, Vector3(.3, .7, .2), trim)
		"stores":
			for x in [-.3, .3]:
				cylinder(n, "TankValve", .085, .085, .25, Vector3(x, .7, .35), dark)
				box(n, "ValveHandle", Vector3(.25, .06, .06), Vector3(x, .85, .35), trim)
	# Raised seams, inspection lamps and fasteners are geometry, not texture maps.
	for z in [-.65, -.2, .2, .65]:
		box(n, "PanelSeam", Vector3(.035, .65, .055), Vector3(.67, -.02, z), dark)
		orb(n, "Fastener", Vector3(-.64, .4, z), Vector3(.065, .065, .065), trim)
	box(n, "ServiceLamp", Vector3(.28, .09, .035), Vector3(0, .28, -1.01), light)

func turret(n: Node3D) -> void:
	cylinder(n, "TraverseBearing", .65, .75, .28, Vector3(0, -.5, .25), dark)
	ring(n, "TraverseLight", .66, .035, Vector3(0, -.35, .25), light)
	if family == "halo":
		orb(n, "SurveyDefenseDome", Vector3(0, -.03, .2), Vector3(1.2, .8, 1.2), body)
	elif family == "lancer":
		prism(n, "LowProfileTurret", Vector3(1.1, .65, 1.15), Vector3(0, -.05, .2), body)
	else:
		box(n, "GunHouse", Vector3(1.25, .7, 1.25), Vector3(0, -.03, .2), body)
	for side in [-1, 1]:
		var radius := .14 if family == "bulwark" else .07
		cylinder(n, "CannonBarrel", radius, radius, 1.65, Vector3(side * .34, .07, -.95), trim, Vector3(90, 0, 0))
		cylinder(n, "RecoilSleeve", radius * 1.6, radius * 1.6, .55, Vector3(side * .34, .07, -.5), dark, Vector3(90, 0, 0))
		cylinder(n, "MuzzleBrake", radius * 1.45, radius * 1.45, .18, Vector3(side * .34, .07, -1.8), dark, Vector3(90, 0, 0))
		box(n, "TurretCheek", Vector3(.13, .5, .8), Vector3(side * .62, 0, .25), trim)
		for z in [0, .3, .6]:
			orb(n, "TurretBolt", Vector3(side * .7, .1, z), Vector3(.07, .07, .07), dark)
	box(n, "TargetOptic", Vector3(.2, .14, .08), Vector3(0, .35, -.35), light)

func antenna(n: Node3D) -> void:
	cylinder(n, "GimbalBase", .48, .58, .25, Vector3(0, -.5, 0), dark)
	cylinder(n, "SensorMast", .07, .12, 1.6, Vector3(0, .2, 0), trim)
	match family:
		"halo":
			for side in [-1, 1]:
				orb(n, "SurveyDish", Vector3(side * .42, .55, -.1), Vector3(.9, .3, .95), body)
				ring(n, "DishRim", .46, .03, Vector3(side * .42, .64, -.1), trim)
				cylinder(n, "DishFeed", .035, .035, .5, Vector3(side * .42, .85, -.1), dark)
		"lancer":
			for side in [-1, 1]:
				prism(n, "BladeAerial", Vector3(.15, 1.25, .5), Vector3(side * .5, .4, 0), body, Vector3(0, 0, side * -20))
		"hauler":
			box(n, "RadarFrame", Vector3(1.65, .65, .15), Vector3(0, .7, 0), body)
			for x in [-.65, -.32, 0, .32, .65]:
				box(n, "RadarSlot", Vector3(.12, .45, .025), Vector3(x, .7, -.09), dark)
		"bulwark":
			box(n, "ArmoredRadar", Vector3(1.4, .55, .4), Vector3(0, .7, 0), body)
			box(n, "RadarAperture", Vector3(1.2, .3, .025), Vector3(0, .7, -.21), glass)
	for side in [-1, 1]:
		cylinder(n, "WhipAerial", .015, .025, 1.3, Vector3(side * .62, .35, .2), dark)
		orb(n, "Beacon", Vector3(side * .62, 1.02, .2), Vector3(.1, .1, .1), light)
		box(n, "MountGusset", Vector3(.12, .35, .4), Vector3(side * .25, -.24, 0), body)
	for z in [-.3, 0, .3]:
		box(n, "PedestalRib", Vector3(.8, .08, .06), Vector3(0, -.4, z), trim)

# Bounds are in the given node's local space, including arbitrary nested transforms.
func bounds(n: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	collect(n, Transform3D.IDENTITY, boxes)
	assert(not boxes.is_empty())
	var result := boxes[0]
	for b in boxes: result = result.merge(b)
	return result

func collect(n: Node3D, t: Transform3D, boxes: Array[AABB]) -> void:
	if n is MeshInstance3D and n.mesh:
		boxes.append(t * n.get_aabb())
	for c in n.get_children():
		if c is Node3D: collect(c, t * c.transform, boxes)

func fit(n: Node3D, target: AABB) -> void:
	var source := bounds(n)
	var factor := target.size / source.size
	var mapping := Transform3D(Basis.from_scale(factor), target.position - source.position * factor)
	for c in n.get_children(): c.transform = mapping * c.transform

func gear(keel: Node3D, reference: Node3D) -> void:
	# Gear belongs to the keel; retain the reference's ground contact footprint.
	for suffix in ["00", "01", "10", "11"]:
		var p: Vector3 = keel.transform.affine_inverse() * reference.get_node("LandingLeg" + suffix).position
		var foot: Vector3 = keel.transform.affine_inverse() * reference.get_node("LandingFoot" + suffix).position
		var leg := cylinder(keel, "LandingLeg" + suffix, .3, .39, 3.6, p, dark)
		leg.name = "LandingLeg" + suffix
		leg.rotation = reference.get_node("LandingLeg" + suffix).rotation
		var pad := box(keel, "LandingFoot" + suffix, Vector3(2.2, .33, 2), foot, trim) if family in ["hauler", "bulwark"] else cylinder(keel, "LandingFoot" + suffix, 1.05, 1.425, .33, foot, trim)
		pad.name = "LandingFoot" + suffix
		var anchor := Vector3(0, -.8, p.z)
		var leg_top := p + Vector3(0, 1.5, 0)
		var brace := cylinder(keel, "LandingSupport", .14, .2, anchor.distance_to(leg_top), (anchor + leg_top) / 2, body)
		brace.name = "LandingSupport" + suffix
		brace.quaternion = Quaternion(Vector3.UP, (leg_top - anchor).normalized())
		# Hydraulic cuff and piston sit within the existing strut envelope.
		var cuff := cylinder(keel, "LandingCuff", .4, .4, .5, p + Vector3(0, .65, 0), body)
		cuff.name = "LandingCuff" + suffix

func owners(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		owners(c, root_node)

func count_meshes(n: Node) -> int:
	var count := 1 if n is MeshInstance3D else 0
	for c in n.get_children(): count += count_meshes(c)
	return count
