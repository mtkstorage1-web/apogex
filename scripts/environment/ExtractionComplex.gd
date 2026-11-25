class_name ExtractionComplex
extends Node3D
## CENTRAL / Terminus Basin: octagonal foundation ring, 205 m Extraction Spire, four radial arms and an
## explorable Base Extraction Control Facility (airlock -> monitoring hall -> reactor + elevator vestibule).
## Local frame: +Y up, +Z south (entrance side), origin = pad centre (0.4 m below sampled terrain).

const FBU = preload("res://scripts/environment/FacilityBuilderUtils.gd")
const PAD_RADIUS := 55.0
const WALL_APOTHEM := 48.0
const FLOOR_Y := 1.2
## Explorer spawn inside the airlock (looking north into the hall).
const INTERIOR_SPAWN := Vector3(0.0, 2.3, 40.0)
const INTERIOR_LOOK := Vector3(0.0, 0.0, -1.0)
const ENTRANCE_STANDOFF := 70.0

var ground_h: Callable
var built: bool = false
var spire_node: Node3D
var _floor_points: Array[Vector3] = []
var _anims: Array = []
var _time: float = 0.0


func _ready() -> void:
	build()


func build() -> void:
	if built:
		return
	built = true
	FBU.foundation(self, "FoundationRing", PAD_RADIUS, 8, 0.0, ground_h)
	FBU.cyl(self, "SpireBaseRing", 23.0, 23.0, 0.3, Vector3(0, 0.15, 0), FBU.hazard(), false, Basis.IDENTITY, 8)
	spire_node = FBU.load_model(self, "extraction_spire_core", "ExtractionSpire", Vector3.ZERO)
	_build_blast_walls()
	_build_arms()
	_build_control_facility()
	_build_machinery()


func get_spire_height() -> float:
	var a: AABB = FBU.compute_aabb(spire_node)
	return a.size.y if a.size.y > 1.0 else float(spire_node.get_meta("height"))


func get_interior_floor_points() -> Array[Vector3]:
	return _floor_points


func get_entrance_local() -> Vector3:
	return Vector3(0, 0, 49.0)


func tick(delta: float) -> void:
	_time += delta
	FBU.tick_anims(_anims, delta, _time)


func get_summary() -> Dictionary:
	return {"spire_height": get_spire_height(), "spire_source": spire_node.get_meta("source"), "anims": _anims.size(), "floor_points": _floor_points.size()}


# ---------------------------------------------------------------------------------------------

func _build_blast_walls() -> void:
	var walls := Node3D.new()
	walls.name = "BlastWalls"
	add_child(walls)
	var edge: float = 2.0 * WALL_APOTHEM * tan(PI / 8.0) + 1.6
	for k in 8:
		var a: float = TAU * float(k) / 8.0
		var n := Vector3(sin(a), 0, cos(a))
		var t: Vector3 = Vector3.UP.cross(n)
		var doors: Array = []
		if k == 0:
			doors = [{"c": edge * 0.5 - 14.0, "w": 12.0, "h": 6.5}, {"c": edge * 0.5, "w": 3.6, "h": 3.4}]
		elif k == 4:
			doors = [{"c": edge * 0.5, "w": 10.0, "h": 6.0}]
		FBU.wall(walls, "BlastWall%d" % k, n * WALL_APOTHEM - t * (edge * 0.5), t, edge, 7.0, doors, FBU.concrete(), 1.6)
		# Hazard cap strip.
		FBU.box(walls, "WallCap%d" % k, Vector3(edge, 0.4, 2.0), n * WALL_APOTHEM + Vector3(0, 7.2, 0), FBU.hazard(), false, FBU.basis_x_along(t))
	# Energy shield across the vehicle gate (visual only: no collision, never blocks the doorway).
	var shield := MeshInstance3D.new()
	shield.name = "GateShield"
	var qm := BoxMesh.new()
	qm.size = Vector3(11.6, 6.4, 0.08)
	shield.mesh = qm
	shield.material_override = FBU.forcefield_material()
	shield.position = Vector3(-14.0, 3.2, WALL_APOTHEM)
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield)
	# Communications antennas on the wall corners.
	for i in 3:
		var ang: float = TAU * (float(i) + 0.5) / 8.0 * 2.0 + 0.4
		var base := Vector3(cos(ang), 0, sin(ang)) * 44.0
		var mast := Node3D.new()
		mast.name = "Antenna%d" % i
		mast.position = base
		add_child(mast)
		FBU.pipe(mast, "Mast", Vector3.ZERO, Vector3(0, 30.0 + float(i) * 3.0, 0), 0.3, FBU.steel(), true)
		for j in 3:
			FBU.box(mast, "Yagi%d" % j, Vector3(4.0, 0.12, 0.12), Vector3(0, 14.0 + float(j) * 5.0, 0), FBU.steel(), false, Basis(Vector3.UP, float(j) * 0.9))
		var beacon: Node3D = FBU.light_strip(mast, "Beacon", Vector3(0.5, 0.5, 0.5), Vector3(0, 30.5 + float(i) * 3.0, 0), FBU.glow_red())
		FBU.register_anim(_anims, beacon, "blink", Vector3.UP, 1.3, 1.0, float(i) * 0.4)


func _build_arms() -> void:
	var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0.7071, 0, -0.7071), Vector3(-0.7071, 0, -0.7071)]
	var names: Array[String] = ["East", "West", "NorthEast", "NorthWest"]
	var deck_top: float = 4.0
	for i in 4:
		var d: Vector3 = dirs[i]
		var arm := Node3D.new()
		arm.name = "Arm" + names[i]
		add_child(arm)
		var bas: Basis = FBU.basis_x_along(d)
		FBU.box(arm, "Walkway", Vector3(18.0, 0.4, 3.2), d * 27.0 + Vector3(0, deck_top - 0.2, 0), FBU.steel(), true, bas)
		FBU.box(arm, "Platform", Vector3(10.0, 0.5, 10.0), d * 41.0 + Vector3(0, deck_top - 0.25, 0), FBU.dark_steel(), true, bas)
		FBU.box(arm, "PlatformTrim", Vector3(10.2, 0.2, 10.2), d * 41.0 + Vector3(0, deck_top - 0.55, 0), FBU.hazard(), false, bas)
		var t := Vector3(-d.z, 0, d.x)
		for r in [22.0, 30.0, 35.5]:
			FBU.pipe(arm, "Leg", d * r + Vector3(0, deck_top - 0.4, 0), d * r, 0.35, FBU.truss(), true)
		for s in [-1.0, 1.0]:
			FBU.pipe(arm, "Pier", d * 41.0 + t * 4.3 * s + Vector3(0, deck_top - 0.5, 0), d * 41.0 + t * 4.3 * s, 0.45, FBU.truss(), true)
			FBU.railing(arm, "Rail", d * 18.0 + t * 1.6 * s + Vector3(0, deck_top, 0), d * 36.0 + t * 1.6 * s + Vector3(0, deck_top, 0))
			FBU.railing(arm, "PlatRail", d * 36.0 + t * 5.0 * s + Vector3(0, deck_top, 0), d * 46.0 + t * 5.0 * s + Vector3(0, deck_top, 0))
		FBU.railing(arm, "EndRail", d * 46.0 - t * 5.0 + Vector3(0, deck_top, 0), d * 46.0 + t * 5.0 + Vector3(0, deck_top, 0))
		# Access stairs down from the platform side to the pad.
		FBU.stairs(arm, "Stairs", d * 41.0 + t * 11.0, -t, 20, 0.2, 0.3, 2.0, FBU.concrete())
		FBU.crate(arm, "Cargo0", d * 41.0 + Vector3(0, deck_top, 0) + t * -2.0, Vector3(1.6, 1.2, 1.6), 0.4)
		FBU.crate(arm, "Cargo1", d * 43.0 + Vector3(0, deck_top, 0) + t * 2.0, Vector3(1.2, 1.0, 2.2), -0.3)
		FBU.light_strip(arm, "PlatformGlow", Vector3(9.4, 0.08, 0.12), d * 36.4 + Vector3(0, deck_top + 0.05, 0), FBU.glow_amber(), bas * Basis(Vector3.UP, PI * 0.5))
		FBU.add_light(arm, d * 41.0 + Vector3(0, deck_top + 4.5, 0), Color(1.0, 0.8, 0.5), 1.4, 14.0)


func _build_control_facility() -> void:
	var cf := Node3D.new()
	cf.name = "ControlFacility"
	add_child(cf)
	var f: float = FLOOR_Y
	FBU.box(cf, "Podium", Vector3(48.4, f, 26.2), Vector3(-1.9, f * 0.5, 30.9), FBU.concrete())
	FBU.ramp(cf, "EntryRamp", Vector3(0, 0, 49.0), Vector3(0, f, 43.5), 4.0, FBU.concrete())
	FBU.light_strip(cf, "RampGlow", Vector3(0.12, 0.05, 5.2), Vector3(-2.1, 0.5, 46.3), FBU.glow_amber(), Basis(Vector3.RIGHT, -0.21))
	FBU.light_strip(cf, "RampGlow2", Vector3(0.12, 0.05, 5.2), Vector3(2.1, 0.5, 46.3), FBU.glow_amber(), Basis(Vector3.RIGHT, -0.21))
	var wm: Material = FBU.concrete()
	# Airlock.
	var air: Node3D = FBU.room(cf, "Airlock", Vector3(6, 4.4, 6), Vector3(0, f, 40), [{"side": "s", "off": 0.0}, {"side": "n", "off": 0.0}], FBU.dark_steel(), FBU.dark_steel(), FBU.dark_steel(), false)
	FBU.light_strip(air, "AirlockStripe", Vector3(5.8, 0.06, 0.3), Vector3(0, 0.05, -2.9), FBU.hazard(), Basis.IDENTITY)
	FBU.add_light(air, Vector3(0, 3.8, 0), Color(1.0, 0.7, 0.35), 1.2, 9.0)
	# Main Monitoring Hall.
	var hall: Node3D = FBU.room(cf, "MonitoringHall", Vector3(26, 8, 18), Vector3(0, f, 27.6),
			[{"side": "s", "off": 0.0}, {"side": "w", "off": 0.0}, {"side": "e", "off": 0.0}], wm, FBU.dark_concrete(), FBU.dark_steel(), false)
	FBU.cyl(hall, "HoloPedestal", 1.5, 1.7, 0.9, Vector3(0, 0.45, 0), FBU.dark_steel())
	var holo := Node3D.new()
	holo.name = "TacticalHologram"
	holo.position = Vector3(0, 3.2, 0)
	hall.add_child(holo)
	var cone := MeshInstance3D.new()
	cone.name = "SpireProjection"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.9
	cm.height = 3.6
	cm.radial_segments = 8
	cone.mesh = cm
	cone.material_override = FBU.hologram_material(0.0)
	holo.add_child(cone)
	var disc := MeshInstance3D.new()
	disc.name = "TerrainDisc"
	var dm := CylinderMesh.new()
	dm.top_radius = 2.4
	dm.bottom_radius = 2.4
	dm.height = 0.08
	dm.radial_segments = 24
	disc.mesh = dm
	disc.position = Vector3(0, -1.9, 0)
	disc.material_override = FBU.hologram_material(1.0)
	holo.add_child(disc)
	FBU.register_anim(_anims, holo, "spin", Vector3.UP, 0.7)
	FBU.add_light(hall, Vector3(0, 2.4, 0), Color(0.3, 0.8, 1.0), 1.8, 10.0)
	for sx in [-6.0, 6.0]:
		FBU.add_light(hall, Vector3(sx, 7.3, -2.0), Color(0.85, 0.92, 1.0), 1.6, 16.0)
		FBU.light_strip(hall, "CeilingStrip", Vector3(0.3, 0.06, 14.0), Vector3(sx, 7.9, 0), FBU.glow_cyan())
	for cx in [-9.0, -5.5]:
		FBU.console(hall, "Console", Vector3(cx, 0, -8.6), 0.0)
	# Mezzanine + stairs (north-east corner of the hall).
	FBU.box(hall, "MezzanineDeck", Vector3(9.6, 0.3, 4.2), Vector3(7.8, 2.85, -6.7), FBU.steel())
	FBU.stairs(hall, "MezzStairs", Vector3(-1.5, 0, -6.7), Vector3.RIGHT, 15, 0.2, 0.3, 2.6, FBU.concrete())
	FBU.railing(hall, "MezzRail", Vector3(3.0, 3.0, -4.6), Vector3(12.6, 3.0, -4.6))
	FBU.console(hall, "MezzConsole", Vector3(10.0, 3.0, -8.2), 0.0)
	# Reactor / power distribution.
	var rx: Node3D = FBU.room(cf, "ReactorRoom", Vector3(12, 6, 12), Vector3(-19.4, f, 27.6), [{"side": "e", "off": 0.0}], wm, FBU.dark_concrete(), FBU.dark_steel(), false)
	FBU.cyl(rx, "ReactorCore", 1.6, 1.6, 5.0, Vector3(0, 2.5, 0), FBU.steel())
	FBU.cyl(rx, "CoreGlow", 1.65, 1.65, 0.5, Vector3(0, 3.2, 0), FBU.glow_cyan(), false)
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + 0.78
		FBU.pipe(rx, "Coolant%d" % i, Vector3(cos(a), 5.0, sin(a)) * 1.4, Vector3(cos(a), 5.6, sin(a)) * 4.8, 0.22, FBU.rust())
	for i in 4:
		FBU.box(rx, "Cabinet%d" % i, Vector3(0.9, 2.2, 1.6), Vector3(-5.3, 1.1, -4.2 + float(i) * 2.8), FBU.dark_steel())
		FBU.light_strip(rx, "CabinetLED%d" % i, Vector3(0.05, 0.4, 0.9), Vector3(-4.8, 1.7, -4.2 + float(i) * 2.8), FBU.glow_amber() if i % 2 == 0 else FBU.glow_cyan())
	FBU.add_light(rx, Vector3(0, 4.6, 0), Color(0.3, 0.85, 1.0), 2.0, 11.0)
	FBU.add_light(rx, Vector3(-4.0, 3.0, 3.0), Color(1.0, 0.6, 0.2), 0.9, 7.0)
	# Elevator vestibule.
	var ev: Node3D = FBU.room(cf, "ElevatorVestibule", Vector3(8, 6, 10), Vector3(17.4, f, 27.6), [{"side": "w", "off": 0.0}], wm, FBU.dark_concrete(), FBU.dark_steel(), false)
	FBU.box(ev, "ShaftBackWall", Vector3(0.3, 5.6, 4.4), Vector3(3.7, 2.8, 0), FBU.dark_steel(), false)
	FBU.box(ev, "ShaftFrameL", Vector3(0.3, 5.8, 0.3), Vector3(3.2, 2.9, -2.2), FBU.hazard(), false)
	FBU.box(ev, "ShaftFrameR", Vector3(0.3, 5.8, 0.3), Vector3(3.2, 2.9, 2.2), FBU.hazard(), false)
	var car := Node3D.new()
	car.name = "ElevatorCarriage"
	car.position = Vector3(3.2, 0.8, 0)
	ev.add_child(car)
	FBU.box(car, "Platform", Vector3(1.6, 0.2, 4.0), Vector3.ZERO, FBU.steel(), false)
	FBU.light_strip(car, "Lamp", Vector3(0.1, 0.1, 3.4), Vector3(0.6, 2.6, 0), FBU.glow_amber())
	FBU.box(car, "CarGlass", Vector3(0.06, 2.4, 3.8), Vector3(0.7, 1.3, 0), FBU.glass(), false)
	FBU.register_anim(_anims, car, "lift", Vector3.UP, 0.9, 1.6)
	FBU.console(ev, "CallPanel", Vector3(0.0, 0, 4.4), PI)
	FBU.add_light(ev, Vector3(0, 4.8, 0), Color(1.0, 0.85, 0.6), 1.4, 9.0)
	# Walkable floor sample points (local space, every one verified against real collision).
	_floor_points = [
		Vector3(0, f, 40.0), Vector3(0, f, 33.0), Vector3(-8, f, 27.6), Vector3(8, f, 31.0),
		Vector3(-8, f, 22.5), Vector3(0, f, 23.5), Vector3(8, f + 3.0, 20.9),
		Vector3(-16.0, f, 31.5), Vector3(-22.0, f, 23.5), Vector3(15.5, f, 30.5), Vector3(0, 0.6, 46.3),
	]


func _build_machinery() -> void:
	# Spinning turbine in its housing (horizontal axis along X).
	var tb := Basis(Vector3.BACK, -PI * 0.5)
	FBU.box(self, "TurbineFrame", Vector3(2.0, 7.0, 9.0), Vector3(-36.5, 3.5, 12.0), FBU.dark_steel())
	FBU.cyl(self, "TurbineHousing", 4.4, 4.4, 1.4, Vector3(-34.9, 4.2, 12.0), FBU.steel(), false, tb, 20)
	var rotor: Node3D = FBU.fan(self, "TurbineRotor", Vector3(-34.2, 4.2, 12.0), 4.0, 6, tb)
	FBU.register_anim(_anims, rotor, "spin", Vector3.UP, 4.5)
	FBU.light_strip(self, "TurbineGlow", Vector3(0.1, 0.4, 8.0), Vector3(-35.4, 0.4, 12.0), FBU.glow_amber())
	# Rotating radar dish on the hall roof.
	FBU.cyl(self, "RadarMast", 0.4, 0.5, 1.8, Vector3(6.0, FLOOR_Y + 8.4 + 0.9, 25.0), FBU.steel(), false)
	var pivot := Node3D.new()
	pivot.name = "RadarDish"
	pivot.position = Vector3(6.0, FLOOR_Y + 8.4 + 2.4, 25.0)
	add_child(pivot)
	var bowl := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.4
	sm.height = 4.8
	sm.radial_segments = 16
	sm.rings = 6
	sm.material = FBU.steel()
	bowl.mesh = sm
	bowl.scale = Vector3(1.0, 0.18, 0.45)
	bowl.position = Vector3(0, 0.6, 0)
	bowl.rotation.z = 0.35
	pivot.add_child(bowl)
	FBU.pipe(pivot, "Feed", Vector3(0, 0.5, 0), Vector3(-0.9, 1.9, 0), 0.06, FBU.dark_steel())
	FBU.register_anim(_anims, pivot, "spin", Vector3.UP, 0.8)
