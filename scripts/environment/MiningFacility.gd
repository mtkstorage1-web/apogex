class_name MiningFacility
extends Node3D
## NORTHERN / Fractured Highlands: terraced excavation, twin drill towers with spinning heads, crusher,
## scrolling conveyors, silo bank, transformer yard, elevated landing platform and an explorable
## Mining Operations & Maintenance Building (ops room with observation loft + vehicle bay).
## Local frame: +Y up, +Z south (entrance side).

const FBU = preload("res://scripts/environment/FacilityBuilderUtils.gd")
const PAD_RADIUS := 52.0
const F := 0.15
const INTERIOR_SPAWN := Vector3(-20.0, 1.4, 28.5)
const INTERIOR_LOOK := Vector3(0.0, 0.0, -1.0)
const ENTRANCE_STANDOFF := 70.0

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
	FBU.foundation(self, "ExcavationPad", PAD_RADIUS, 8, 0.0, ground_h)
	_build_terraces()
	_build_process_line()
	_build_yards()
	_build_maintenance_building()


func get_interior_floor_points() -> Array[Vector3]:
	return _floor_points


func get_entrance_local() -> Vector3:
	return Vector3(-18.0, 0.0, 33.0)


func tick(delta: float) -> void:
	_time += delta
	FBU.tick_anims(_anims, delta, _time)


func get_summary() -> Dictionary:
	var src: Array[String] = []
	for m in model_nodes:
		src.append(str(m.get_meta("source")))
	return {"models": src, "anims": _anims.size(), "floor_points": _floor_points.size()}


func _model(id: String, nm: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var n: Node3D = FBU.load_model(self, id, nm, pos, yaw)
	model_nodes.append(n)
	return n


func _build_terraces() -> void:
	FBU.box(self, "Terrace1", Vector3(36, 2.0, 10), Vector3(0, 1.0, -35), FBU.dark_concrete())
	FBU.box(self, "Terrace2", Vector3(28, 2.0, 6), Vector3(0, 3.0, -41), FBU.concrete())
	FBU.box(self, "TerraceTrim1", Vector3(36.2, 0.2, 0.3), Vector3(0, 2.05, -30.1), FBU.hazard(), false)
	FBU.box(self, "TerraceTrim2", Vector3(28.2, 0.2, 0.3), Vector3(0, 4.05, -37.9), FBU.hazard(), false)
	FBU.ramp(self, "TerraceRamp", Vector3(-27, 0, -35), Vector3(-18, 2.0, -35), 3.0, FBU.concrete())
	FBU.stairs(self, "TerraceStairs", Vector3(10, 2.0, -35.0), Vector3(0, 0, -1), 10, 0.2, 0.3, 2.0, FBU.concrete())
	FBU.railing(self, "TerraceRail", Vector3(-14, 4.0, -38.0), Vector3(14, 4.0, -38.0))
	# Elevated landing platform.
	var lp := Node3D.new()
	lp.name = "LandingPlatform"
	add_child(lp)
	FBU.box(lp, "Deck", Vector3(12, 0.5, 12), Vector3(30, 5.75, -30), FBU.dark_steel())
	FBU.box(lp, "DeckTrim", Vector3(12.2, 0.2, 12.2), Vector3(30, 5.4, -30), FBU.hazard(), false)
	for sx in [-5.0, 5.0]:
		for sz in [-5.0, 5.0]:
			FBU.pipe(lp, "Leg", Vector3(30 + sx, 5.5, -30 + sz), Vector3(30 + sx, 0, -30 + sz), 0.4, FBU.truss(), true)
	FBU.stairs(lp, "Stairs", Vector3(30, 0, -15.0), Vector3(0, 0, -1), 30, 0.2, 0.3, 2.2, FBU.concrete())
	FBU.railing(lp, "RailW", Vector3(24, 6.0, -36), Vector3(24, 6.0, -24))
	FBU.railing(lp, "RailE", Vector3(36, 6.0, -36), Vector3(36, 6.0, -24))
	FBU.railing(lp, "RailN", Vector3(24, 6.0, -36), Vector3(36, 6.0, -36))
	for i in 4:
		var a: float = TAU * float(i) / 4.0
		FBU.light_strip(lp, "PadLight%d" % i, Vector3(0.5, 0.1, 0.5), Vector3(30 + cos(a) * 3.5, 6.02, -30 + sin(a) * 3.5), FBU.glow_amber())
	FBU.add_light(lp, Vector3(30, 9.0, -30), Color(1.0, 0.8, 0.5), 1.8, 18.0)


func _build_process_line() -> void:
	var heads: Array[Vector3] = [Vector3(-24, 0, -8), Vector3(18, 0, -14)]
	for i in 2:
		var p: Vector3 = heads[i]
		_model("mining_drill_tower", "DrillTower%d" % (i + 1), p, 0.0 if i == 0 else 0.6)
		# Animated rotating drill head inside the derrick.
		var rod := Node3D.new()
		rod.name = "DrillHead%d" % (i + 1)
		rod.position = p + Vector3(0, 9.0, 0)
		add_child(rod)
		FBU.cyl(rod, "Rod", 0.3, 0.3, 6.0, Vector3(0, 3.0, 0), FBU.steel(), false, Basis.IDENTITY, 8)
		FBU.cyl(rod, "Bit", 1.4, 0.15, 2.4, Vector3(0, -0.6, 0), FBU.dark_steel(), false, Basis.IDENTITY, 6)
		for b in 3:
			FBU.box(rod, "Cutter%d" % b, Vector3(1.8, 0.2, 0.3), Vector3(0, 0.4, 0), FBU.hazard(), false, Basis(Vector3.UP, float(b) * 1.047))
		FBU.register_anim(_anims, rod, "spin", Vector3.UP, 5.0 + float(i) * 1.7)
		FBU.light_strip(self, "DrillGlow%d" % i, Vector3(1.4, 0.1, 1.4), p + Vector3(0, 0.06, 0), FBU.glow_amber())
	_model("ore_crusher_hopper", "OreCrusher", Vector3(0, 0, -14))
	_model("storage_silo_bank", "SiloBank", Vector3(30, 0, 8))
	FBU.conveyor(self, "ConveyorDrill1", Vector3(-17, 1.4, -8), Vector3(-6.8, 3.6, -14), 1.6, 0.7)
	FBU.conveyor(self, "ConveyorDrill2", Vector3(11.5, 1.4, -14), Vector3(7.2, 3.0, -14), 1.6, 0.7)
	FBU.conveyor(self, "ConveyorSilo", Vector3(7.0, 2.0, -11), Vector3(24.5, 6.5, 5), 1.8, 0.8)
	FBU.add_light(self, Vector3(0, 11, -14), Color(1.0, 0.8, 0.5), 1.6, 22.0)


func _build_yards() -> void:
	# Power transformer yard (fenced).
	var yard := Node3D.new()
	yard.name = "TransformerYard"
	yard.position = Vector3(-34, 0, 14)
	add_child(yard)
	FBU.box(yard, "Pad", Vector3(14, 0.3, 12), Vector3(0, 0.15, 0), FBU.dark_concrete())
	for i in 3:
		var x: float = -4.5 + float(i) * 4.5
		FBU.box(yard, "Transformer%d" % i, Vector3(2.8, 3.2, 2.6), Vector3(x, 1.9, 0), FBU.dark_steel())
		for k in 3:
			FBU.cyl(yard, "Insulator%d_%d" % [i, k], 0.15, 0.15, 1.4, Vector3(x - 0.9 + float(k) * 0.9, 4.2, 0), FBU._std("insulator", Color(0.6, 0.65, 0.6), 0.1, 0.4), false, Basis.IDENTITY, 6)
		var lamp: Node3D = FBU.light_strip(yard, "Status%d" % i, Vector3(0.3, 0.3, 0.1), Vector3(x, 2.4, 1.35), FBU.glow_cyan())
		FBU.register_anim(_anims, lamp, "flicker", Vector3.UP, 1.0, 1.0, float(i))
	for s in [-1.0, 1.0]:
		FBU.box(yard, "FenceZ", Vector3(14, 2.0, 0.1), Vector3(0, 1.0, 6.0 * s), FBU.truss(), true)
		FBU.box(yard, "FenceX", Vector3(0.1, 2.0, 12), Vector3(7.0 * s, 1.0, 0), FBU.truss(), true)
	FBU.add_light(yard, Vector3(0, 5.5, 0), Color(0.5, 0.8, 1.0), 1.2, 12.0)


func _build_maintenance_building() -> void:
	var mb := Node3D.new()
	mb.name = "MaintenanceBuilding"
	add_child(mb)
	var ops: Node3D = FBU.room(mb, "OperationsRoom", Vector3(12, 7.4, 10), Vector3(-20, F, 26),
			[{"side": "s", "off": 2.0}, {"side": "e", "off": 0.0}], FBU.concrete(), FBU.dark_concrete(), FBU.dark_steel())
	FBU.box(ops, "LoftDeck", Vector3(12, 0.3, 4.5), Vector3(0, 3.25, -2.75), FBU.steel())
	FBU.stairs(ops, "LoftStairs", Vector3(-4.5, 0, 4.6), Vector3(0, 0, -1), 17, 0.2, 0.3, 2.0, FBU.concrete())
	FBU.railing(ops, "LoftRail", Vector3(-3.0, 3.4, -0.5), Vector3(5.8, 3.4, -0.5))
	FBU.console(ops, "LoftConsole", Vector3(1.5, 3.4, -4.4), 0.0)
	FBU.box(ops, "ObsWindow", Vector3(8.0, 1.6, 0.1), Vector3(0, 4.4, -5.05), FBU.glass(), false)
	for cx in [-1.0, 2.0]:
		FBU.console(ops, "OpsConsole", Vector3(cx, 0, -4.5), 0.0)
	FBU.box(ops, "MapTable", Vector3(2.4, 0.9, 1.4), Vector3(2.5, 0.45, 2.2), FBU.dark_steel())
	FBU.add_light(ops, Vector3(0, 2.8, 1.0), Color(1.0, 0.85, 0.6), 1.5, 11.0)
	FBU.add_light(ops, Vector3(0, 6.6, -1.5), Color(0.6, 0.85, 1.0), 1.0, 9.0)
	var bay: Node3D = FBU.room(mb, "VehicleBay", Vector3(12, 6, 14), Vector3(-7.6, F, 26),
			[{"side": "s", "off": 0.0, "w": 6.0, "h": 4.5}, {"side": "w", "off": 0.0}], FBU.concrete(), FBU.dark_concrete(), FBU.dark_steel())
	FBU.box(bay, "UtilityTruck", Vector3(2.4, 1.6, 5.0), Vector3(3.2, 1.0, -3.5), FBU.rust())
	FBU.box(bay, "TruckCab", Vector3(2.2, 1.2, 1.6), Vector3(3.2, 2.2, -1.6), FBU.dark_steel(), false)
	FBU.crate(bay, "Crate0", Vector3(-4.5, 0, -5.5), Vector3(1.4, 1.2, 1.4), 0.3)
	FBU.crate(bay, "Crate1", Vector3(-4.2, 0, -3.8), Vector3(1.0, 0.8, 1.0), -0.2)
	FBU.box(bay, "BayStripe", Vector3(6.0, 0.03, 0.4), Vector3(0, 0.02, 6.4), FBU.hazard(), false)
	FBU.add_light(bay, Vector3(-2, 5.4, 0), Color(1.0, 0.9, 0.7), 1.5, 14.0)
	FBU.add_light(bay, Vector3(2, 5.4, -3), Color(1.0, 0.9, 0.7), 1.2, 12.0)
	_floor_points = [Vector3(-20, F, 28.5), Vector3(-18, F + 3.4, 23.0), Vector3(-7.6, F, 29.5), Vector3(-8.0, F, 22.0)]
