class_name AbandonedSettlement
extends Node3D
## WESTERN / Obsidian Fields: atmospheric derelict colony. Hab module wrecks, two explorable open-interior
## habitat modules (flickering amber emergency lights), damaged geothermal station with sparking conduit,
## crashed rovers, broken solar arrays, collapsed comms mast and an empty industrial plaza.
## Local frame: +Y up, +Z south (entrance side).

const FBU = preload("res://scripts/environment/FacilityBuilderUtils.gd")
const PAD_RADIUS := 50.0
const F := 0.15
const INTERIOR_SPAWN := Vector3(-26.0, 1.4, 6.0)
const INTERIOR_LOOK := Vector3(0.0, 0.0, 1.0)
const ENTRANCE_STANDOFF := 65.0

var ground_h: Callable
var built: bool = false
var model_nodes: Array[Node3D] = []
var _floor_points: Array[Vector3] = []
var _anims: Array = []
var _time: float = 0.0


func _ready() -> void:
	build()


func build() -> void:
	if built:
		return
	built = true
	FBU.foundation(self, "SettlementSlab", PAD_RADIUS, 8, 0.0, ground_h, FBU.dark_concrete())
	_build_hab_modules()
	_build_geothermal()
	_build_wreckage()
	_build_plaza()


func get_interior_floor_points() -> Array[Vector3]:
	return _floor_points


func get_entrance_local() -> Vector3:
	return Vector3(-26.0, 0.0, 12.0)


func tick(delta: float) -> void:
	_time += delta
	FBU.tick_anims(_anims, delta, _time)


func get_summary() -> Dictionary:
	var src: Array[String] = []
	for m in model_nodes:
		src.append(str(m.get_meta("source")))
	return {"models": src, "anims": _anims.size(), "floor_points": _floor_points.size()}


func _model(id: String, nm: String, pos: Vector3, yaw: float = 0.0, tilt: float = 0.0) -> Node3D:
	var n: Node3D = FBU.load_model(self, id, nm, pos, yaw)
	if tilt != 0.0:
		n.basis = n.basis * Basis(Vector3.BACK, tilt)
	model_nodes.append(n)
	return n


func _flicker_light(parent: Node, pos: Vector3, phase: float, range_m: float = 8.0) -> void:
	var l: OmniLight3D = FBU.add_light(parent, pos, Color(1.0, 0.55, 0.15), 1.4, range_m, false, "EmergencyLight")
	FBU.register_anim(_anims, l, "flicker", Vector3.UP, 1.0, 1.0, phase)
	var lamp: Node3D = FBU.light_strip(parent, "EmergencyLamp", Vector3(0.5, 0.12, 0.2), pos + Vector3(0, 0.25, 0), FBU.glow_amber())
	FBU.register_anim(_anims, lamp, "flicker", Vector3.UP, 1.0, 1.0, phase)


func _build_hab_modules() -> void:
	# GLB hab wrecks (solid exteriors), two half-buried and tilted.
	_model("hab_module_derelict", "HabWreck1", Vector3(-6, 0, -10), 0.3)
	_model("hab_module_derelict", "HabWreck2", Vector3(16, 0, -14), -0.5)
	_model("hab_module_derelict", "HabWreck3", Vector3(36, 0, -2), 1.2, 0.12)
	_model("hab_module_derelict", "HabWreck4", Vector3(-34, 0, -22), 0.8, -0.1)
	# Two explorable open-interior habitat modules.
	var specs: Array = [
		{"name": "HabInteriorA", "pos": Vector3(-26, F, 6), "pts": [Vector3(0, 0, 0), Vector3(3.5, 0, 1.0), Vector3(-3.0, 0, 0.5)]},
		{"name": "HabInteriorB", "pos": Vector3(22, F, 10), "pts": [Vector3(0, 0, 0.5), Vector3(4.0, 0, -0.5)]},
	]
	var phase: float = 0.0
	for sp in specs:
		var sd: Dictionary = sp
		var pos: Vector3 = sd["pos"]
		var hab: Node3D = FBU.room(self, sd["name"], Vector3(12, 4.4, 7), pos,
				[{"side": "s", "off": 0.0}, {"side": "e", "off": 1.0, "w": 5.0, "h": 3.2}], FBU.steel(), FBU.dark_steel(), FBU.dark_steel())
		FBU.box(hab, "HullBand", Vector3(12.9, 0.4, 0.15), Vector3(0, 4.0, 3.9), FBU.rust(), false)
		for i in 3:
			FBU.light_strip(hab, "Window%d" % i, Vector3(1.4, 0.7, 0.08), Vector3(-3.5 + float(i) * 3.5, 2.4, -3.45), FBU.glow_amber())
		# Damaged consoles (tilted), bunks, supply crates.
		FBU.console(hab, "DamagedConsole0", Vector3(-4.5, 0, -2.8), 0.2)
		var broken: Node3D = FBU.console(hab, "DamagedConsole1", Vector3(-1.5, 0, -2.9), -0.15)
		broken.basis = broken.basis * Basis(Vector3.BACK, 0.18)
		FBU.box(hab, "Bunk0", Vector3(2.0, 0.8, 0.9), Vector3(5.0, 0.4, -2.8), FBU.dark_steel())
		FBU.box(hab, "Bunk1", Vector3(2.0, 0.8, 0.9), Vector3(5.0, 1.4, -2.8), FBU.dark_steel())
		FBU.crate(hab, "Supply0", Vector3(-5.2, 0, 2.2), Vector3(1.2, 0.9, 1.2), 0.4)
		FBU.crate(hab, "Supply1", Vector3(-4.2, 0, 2.6), Vector3(0.8, 0.7, 0.8), -0.3)
		_flicker_light(hab, Vector3(-3.0, 3.9, 0.0), phase)
		_flicker_light(hab, Vector3(3.5, 3.9, 0.0), phase + 1.7)
		phase += 2.9
		for lp in sd["pts"]:
			_floor_points.append(pos + (lp as Vector3))


func _build_geothermal() -> void:
	var gs := Node3D.new()
	gs.name = "GeothermalStation"
	gs.position = Vector3(-4, 0, -28)
	add_child(gs)
	FBU.box(gs, "Foundation", Vector3(16, 0.4, 12), Vector3(0, 0.2, 0), FBU.dark_concrete())
	FBU.box(gs, "TurbineHall", Vector3(12, 6.0, 8), Vector3(-1, 3.4, 0), FBU.rust())
	# Collapsed roof section.
	FBU.box(gs, "BrokenRoof", Vector3(7.0, 0.4, 8.4), Vector3(2.5, 5.6, 0), FBU.dark_steel(), true, Basis(Vector3.BACK, -0.45))
	for i in 3:
		FBU.cyl(gs, "SteamPipe%d" % i, 0.5, 0.5, 9.0 - float(i), Vector3(-6.5 + float(i) * 1.6, 4.5, 5.0), FBU.rust(), false, Basis.IDENTITY, 10)
	FBU.cyl(gs, "CoolingStack", 1.6, 2.0, 14.0, Vector3(6.5, 7.0, 4.5), FBU.dark_concrete(), true, Basis.IDENTITY, 14)
	# Sparking electrical conduit: dangling cable plus flickering spark emitters + light.
	FBU.pipe(gs, "Conduit", Vector3(-7.0, 6.0, -4.2), Vector3(-7.0, 2.2, -5.5), 0.1, FBU.truss())
	FBU.pipe(gs, "ConduitHang", Vector3(-7.0, 2.2, -5.5), Vector3(-5.8, 0.6, -6.5), 0.08, FBU.truss())
	var spark := Node3D.new()
	spark.name = "SparkEmitter"
	spark.position = Vector3(-5.8, 0.7, -6.5)
	gs.add_child(spark)
	for i in 4:
		FBU.light_strip(spark, "Spark%d" % i, Vector3(0.06, 0.06, 0.3), Vector3(cos(float(i)) * 0.25, 0.1 * float(i), sin(float(i)) * 0.25), FBU.glow_cyan(), Basis(Vector3.RIGHT, float(i)))
	var sl: OmniLight3D = FBU.add_light(spark, Vector3(0, 0.3, 0), Color(0.5, 0.85, 1.0), 2.5, 9.0, false, "SparkLight")
	FBU.register_anim(_anims, spark, "flicker", Vector3.UP, 1.0, 1.0, 0.0)
	sl.visible = true
	FBU.add_light(gs, Vector3(-1, 4.0, 0), Color(1.0, 0.5, 0.15), 1.0, 12.0)


func _build_wreckage() -> void:
	# Crashed utility rover hulls.
	for i in 2:
		var rv := Node3D.new()
		rv.name = "CrashedRover%d" % i
		rv.position = Vector3(10.0 - float(i) * 38.0, 0, 28.0 - float(i) * 12.0)
		rv.rotation = Vector3(0.1 * float(i + 1), 0.7 + float(i), 0.22 * float(1 - 2 * i))
		add_child(rv)
		FBU.box(rv, "Hull", Vector3(4.6, 1.5, 2.4), Vector3(0, 1.0, 0), FBU.rust())
		FBU.box(rv, "Cab", Vector3(1.8, 1.0, 2.0), Vector3(1.2, 2.2, 0), FBU.dark_steel(), false)
		for k in 4:
			var wx: float = -1.6 + float(k % 2) * 3.2
			var wz: float = -1.35 + float(k / 2) * 2.7
			FBU.cyl(rv, "Wheel%d" % k, 0.55, 0.55, 0.4, Vector3(wx, 0.55 + float(k) * 0.12, wz), FBU.truss(), false, Basis(Vector3.RIGHT, PI * 0.5 + 0.3 * float(k)), 10)
	# Broken, tilted solar arrays.
	for i in 3:
		var sa := Node3D.new()
		sa.name = "BrokenSolarArray%d" % i
		sa.position = Vector3(26.0 + float(i) * 6.0, 0, -26.0 + float(i) * 5.0)
		add_child(sa)
		FBU.pipe(sa, "Post", Vector3.ZERO, Vector3(0, 2.4, 0), 0.15, FBU.dark_steel(), true)
		var panel: Node3D = FBU.box(sa, "Panel", Vector3(5.0, 0.12, 3.0), Vector3(0, 2.6, 0), _solar_mat(), true,
				Basis(Vector3.UP, 0.4 * float(i)) * Basis(Vector3.BACK, 0.5 + 0.35 * float(i)) * Basis(Vector3.RIGHT, 0.25))
		panel.set_meta("broken", true)
	# Collapsed communications mast lying across the pad.
	var mast := Node3D.new()
	mast.name = "CollapsedCommsMast"
	mast.position = Vector3(-14, 0, -34)
	mast.rotation.y = 0.5
	add_child(mast)
	FBU.box(mast, "BaseStub", Vector3(2.0, 3.0, 2.0), Vector3(0, 1.5, 0), FBU.dark_concrete())
	FBU.pipe(mast, "FallenSection", Vector3(1.0, 2.8, 0), Vector3(16.0, 0.5, 2.0), 0.3, FBU.steel(), true)
	FBU.pipe(mast, "FallenSection2", Vector3(16.0, 0.5, 2.0), Vector3(22.0, 0.4, 5.0), 0.2, FBU.rust(), true)
	for j in 4:
		FBU.box(mast, "Crossbar%d" % j, Vector3(0.1, 2.0, 0.1), Vector3(3.0 + float(j) * 3.5, 0.9, 0.3 + float(j) * 0.2), FBU.rust(), false, Basis(Vector3.BACK, 0.3))


func _solar_mat() -> StandardMaterial3D:
	return FBU._std("solar", Color(0.07, 0.12, 0.26), 0.6, 0.25)


func _build_plaza() -> void:
	var pl := Node3D.new()
	pl.name = "IndustrialPlaza"
	add_child(pl)
	FBU.box(pl, "Paving", Vector3(26, 0.08, 18), Vector3(0, 0.08, 26), FBU.dark_concrete(), false)
	for i in 5:
		FBU.box(pl, "Stripe%d" % i, Vector3(0.3, 0.09, 18), Vector3(-10.0 + float(i) * 5.0, 0.09, 26), FBU.hazard(), false)
	for i in 4:
		var lp := Vector3(-10.0 + float(i) * 6.7, 0, 18.0)
		FBU.pipe(pl, "LampPost%d" % i, lp, lp + Vector3(0, 6.0, 0), 0.12, FBU.dark_steel(), true)
		if i % 2 == 0:
			_flicker_light(pl, lp + Vector3(0, 5.8, 0), float(i) * 1.3, 11.0)
		else:
			FBU.light_strip(pl, "DeadLamp%d" % i, Vector3(0.5, 0.12, 0.25), lp + Vector3(0, 6.0, 0), FBU.truss())
	FBU.box(pl, "Bench0", Vector3(2.4, 0.5, 0.6), Vector3(-6, 0.3, 30), FBU.rust(), true, Basis(Vector3.UP, 0.2))
	FBU.box(pl, "Bench1", Vector3(2.4, 0.5, 0.6), Vector3(6, 0.3, 32), FBU.rust(), true, Basis(Vector3.UP, -0.4))
	FBU.crate(pl, "Debris0", Vector3(2, 0, 24), Vector3(1.4, 0.9, 1.0), 0.8)
