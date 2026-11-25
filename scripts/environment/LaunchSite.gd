class_name LaunchSite
extends Node3D
## SOUTHERN / Ashen Wastes: octagonal launch pad with recessed flame trench + angled blast deflectors,
## 48 m launch service tower, two auxiliary landing pads, fuel silo farm with pipes, an explorable
## Vehicle Assembly Bay (gantry crane) and a reinforced Control Bunker with observation slit windows.
## Local frame: +Y up, +Z south (entrance side).

const FBU = preload("res://scripts/environment/FacilityBuilderUtils.gd")
const PAD_RADIUS := 60.0
const F := 0.15
const PAD_TOP := 3.0
const INTERIOR_SPAWN := Vector3(6.0, 1.4, 36.0)
const INTERIOR_LOOK := Vector3(0.0, 0.0, -1.0)
const ENTRANCE_STANDOFF := 75.0

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
	FBU.foundation(self, "LaunchApron", PAD_RADIUS, 8, 0.0, ground_h)
	_build_launch_pad()
	_build_aux_pads()
	_build_fuel_farm()
	_build_hangar()
	_build_bunker()


func get_interior_floor_points() -> Array[Vector3]:
	return _floor_points


func get_entrance_local() -> Vector3:
	return Vector3(6.0, 0.0, 45.0)


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


func _build_launch_pad() -> void:
	var pad := Node3D.new()
	pad.name = "MainLaunchPad"
	add_child(pad)
	# Two raised pad halves with a 5 m flame trench between them (trench floor = foundation slab).
	for s in [-1.0, 1.0]:
		FBU.box(pad, "PadHalf", Vector3(13.5, PAD_TOP, 32.0), Vector3(9.25 * s, PAD_TOP * 0.5, -10.0), FBU.dark_concrete())
		FBU.box(pad, "PadTrim", Vector3(13.7, 0.12, 32.2), Vector3(9.25 * s, PAD_TOP + 0.02, -10.0), FBU.hazard(), false)
		FBU.railing(pad, "TrenchRail", Vector3(2.7 * s, PAD_TOP, -26.0), Vector3(2.7 * s, PAD_TOP, 6.0))
	FBU.box(pad, "MountBridge", Vector3(6.0, 0.8, 3.0), Vector3(0, PAD_TOP - 0.4, -10.0), FBU.steel())
	FBU.cyl(pad, "MountRing", 2.4, 2.4, 0.3, Vector3(0, PAD_TOP + 0.15, -10.0), FBU.hazard(), false, Basis.IDENTITY, 16)
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + 0.78
		FBU.cyl(pad, "HoldDown%d" % i, 0.35, 0.45, 1.6, Vector3(cos(a) * 2.0, PAD_TOP + 0.9, -10.0 + sin(a) * 2.0), FBU.dark_steel(), false)
	# Angled concrete blast deflectors at the trench exit and along the trench flanks.
	FBU.box(pad, "DeflectorNorth", Vector3(5.0, 0.8, 9.0), Vector3(0, 2.0, -29.0), FBU.concrete(), true, Basis(Vector3.RIGHT, 0.6))
	for s in [-1.0, 1.0]:
		FBU.box(pad, "DeflectorFlank", Vector3(0.8, 3.2, 10.0), Vector3(3.6 * s, 1.0, -22.0), FBU.concrete(), false, Basis(Vector3.BACK, 0.5 * s))
	FBU.ramp(pad, "PadRampW", Vector3(-9, 0, 14), Vector3(-9, PAD_TOP, 6), 4.0, FBU.concrete())
	FBU.ramp(pad, "PadRampE", Vector3(9, 0, 14), Vector3(9, PAD_TOP, 6), 4.0, FBU.concrete())
	for i in 6:
		FBU.light_strip(pad, "PadLight%d" % i, Vector3(0.4, 0.08, 0.4), Vector3(-14.0 + float(i) * 5.6, PAD_TOP + 0.08, 4.5), FBU.glow_amber())
	var tower: Node3D = _model("launch_service_tower", "ServiceTower", Vector3(24, 0, -10))
	# Swing arm reaching toward the launch mount, and a rotating radar on the tower top.
	var arm: Node3D = FBU.box(self, "SwingArm", Vector3(16.0, 1.2, 1.2), Vector3(14.0, 30.0, -10.0), FBU.hazard(), false)
	FBU.register_anim(_anims, arm, "piston", Vector3(1, 0, 0), 0.5, 0.8)
	var beacon: Node3D = FBU.light_strip(self, "TowerBeacon", Vector3(1.0, 1.0, 1.0), Vector3(24, 48.8, -10), FBU.glow_red())
	FBU.register_anim(_anims, beacon, "blink", Vector3.UP, 1.4)
	FBU.add_light(self, Vector3(18, 14, -10), Color(1.0, 0.85, 0.6), 2.0, 26.0)
	tower.set_meta("is_service_tower", true)


func _build_aux_pads() -> void:
	var centres: Array[Vector3] = [Vector3(-38, 0, -20), Vector3(-38, 0, 3)]
	for i in 2:
		var c: Vector3 = centres[i]
		var pad := Node3D.new()
		pad.name = "AuxPad%d" % (i + 1)
		pad.position = c
		add_child(pad)
		FBU.cyl(pad, "Plate", 9.0, 9.0, 0.3, Vector3(0, 0.15, 0), FBU.dark_concrete(), true, Basis.IDENTITY, 24)
		FBU.cyl(pad, "RingMarking", 8.2, 8.2, 0.06, Vector3(0, 0.33, 0), FBU.hazard(), false, Basis.IDENTITY, 24)
		FBU.cyl(pad, "InnerDisc", 7.3, 7.3, 0.08, Vector3(0, 0.34, 0), FBU.dark_concrete(), false, Basis.IDENTITY, 24)
		FBU.light_strip(pad, "H_Left", Vector3(0.5, 0.05, 4.6), Vector3(-1.4, 0.4, 0), FBU.glow_cyan())
		FBU.light_strip(pad, "H_Right", Vector3(0.5, 0.05, 4.6), Vector3(1.4, 0.4, 0), FBU.glow_cyan())
		FBU.light_strip(pad, "H_Bar", Vector3(3.3, 0.05, 0.5), Vector3(0, 0.4, 0), FBU.glow_cyan())
		for k in 5:
			FBU.light_strip(pad, "Approach%d" % k, Vector3(1.4, 0.05, 0.3), Vector3(11.0 + float(k) * 2.2, 0.1, 0), FBU.glow_amber())
		for k in 3:
			var a: float = TAU * float(k) / 3.0 + 0.5
			var p := Vector3(cos(a), 0, sin(a)) * 9.6
			FBU.pipe(pad, "FloodPole%d" % k, p, p + Vector3(0, 9, 0), 0.15, FBU.dark_steel(), true)
			FBU.light_strip(pad, "Floodlamp%d" % k, Vector3(1.0, 0.3, 0.5), p + Vector3(0, 9.1, 0), FBU.glow_amber())
			if k == 0:
				FBU.add_light(pad, p + Vector3(0, 9.0, 0), Color(1.0, 0.95, 0.85), 1.8, 22.0)


func _build_fuel_farm() -> void:
	_model("storage_silo_bank", "FuelSilos1", Vector3(42, 0, 8), 0.0)
	_model("storage_silo_bank", "FuelSilos2", Vector3(42, 0, -14), 0.0)
	var runs: Array = [
		[Vector3(34, 1.2, 8), Vector3(34, 1.2, -10), Vector3(30.5, 1.2, -10)],
		[Vector3(34, 1.8, -14), Vector3(34, 1.8, -10)],
		[Vector3(35.5, 3.2, 8), Vector3(35.5, 3.2, -14), Vector3(30.5, 3.2, -11)],
	]
	var idx: int = 0
	for run in runs:
		var pts: Array = run
		for k in pts.size() - 1:
			FBU.pipe(self, "FuelPipe%d_%d" % [idx, k], pts[k], pts[k + 1], 0.32, FBU.rust(), false, 10)
			FBU.pipe(self, "FuelBand%d_%d" % [idx, k], (pts[k] as Vector3).lerp(pts[k + 1], 0.5) - Vector3(0, 0, 0), (pts[k] as Vector3).lerp(pts[k + 1], 0.5) + (pts[k + 1] - pts[k]).normalized() * 0.6, 0.36, FBU.hazard(), false, 10)
			var mid: Vector3 = (pts[k] as Vector3).lerp(pts[k + 1], 0.25)
			FBU.pipe(self, "FuelSupport%d_%d" % [idx, k], Vector3(mid.x, 0.0, mid.z), mid, 0.12, FBU.dark_steel(), true)
		idx += 1


func _build_hangar() -> void:
	var hg: Node3D = FBU.room(self, "VehicleAssemblyBay", Vector3(24, 13, 26), Vector3(-24, F, 28),
			[{"side": "s", "off": 0.0, "w": 8.0, "h": 8.0}, {"side": "e", "off": -4.0}], FBU.concrete(), FBU.dark_concrete(), FBU.dark_steel())
	FBU.box(hg, "BayStripe", Vector3(8.0, 0.03, 12.0), Vector3(0, 0.02, 7.0), FBU.hazard(), false)
	# Gantry crane: wall rails + bridge + animated trolley with hook.
	for s in [-1.0, 1.0]:
		FBU.box(hg, "CraneRail", Vector3(0.5, 0.5, 25.0), Vector3(11.4 * s, 10.6, 0), FBU.truss(), false)
	var bridge: Node3D = FBU.box(hg, "CraneBridge", Vector3(23.0, 1.0, 1.2), Vector3(0, 10.6, 0), FBU.hazard(), false)
	var trolley := Node3D.new()
	trolley.name = "CraneTrolley"
	trolley.position = Vector3(0, 9.6, 0)
	hg.add_child(trolley)
	FBU.box(trolley, "Block", Vector3(1.6, 0.8, 1.6), Vector3.ZERO, FBU.dark_steel(), false)
	FBU.pipe(trolley, "Cable", Vector3(0, -0.4, 0), Vector3(0, -5.0, 0), 0.04, FBU.steel())
	FBU.box(trolley, "Hook", Vector3(0.5, 0.6, 0.5), Vector3(0, -5.3, 0), FBU.rust(), false)
	FBU.register_anim(_anims, trolley, "piston", Vector3(1, 0, 0), 0.5, 8.0)
	bridge.set_meta("crane", true)
	# Rocket stage on stands + support equipment.
	FBU.cyl(hg, "StageBody", 1.6, 1.6, 12.0, Vector3(-3.0, 2.3, -6.0), FBU.steel(), true, Basis(Vector3.BACK, PI * 0.5), 20)
	FBU.cyl(hg, "StageBand", 1.65, 1.65, 0.8, Vector3(-3.0, 2.3, -6.0), FBU.hazard(), false, Basis(Vector3.BACK, PI * 0.5), 20)
	for sx in [-7.0, 1.0]:
		FBU.box(hg, "StageStand", Vector3(1.2, 1.4, 3.4), Vector3(sx, 0.7, -6.0), FBU.dark_steel())
	FBU.crate(hg, "Crate0", Vector3(8.0, 0, -9.0), Vector3(1.6, 1.4, 1.6), 0.4)
	FBU.console(hg, "BayConsole", Vector3(9.0, 0, 3.0), -PI * 0.5)
	for lx in [-6.0, 6.0]:
		FBU.add_light(hg, Vector3(lx, 11.8, 0), Color(1.0, 0.95, 0.85), 2.0, 22.0)
		FBU.light_strip(hg, "HangarStrip", Vector3(0.4, 0.08, 20.0), Vector3(lx, 12.9, 0), FBU.glow_amber())
	_floor_points.append(Vector3(-24, F, 32.0))
	_floor_points.append(Vector3(-18, F, 34.0))
	_floor_points.append(Vector3(-31, F, 33.0))


func _build_bunker() -> void:
	var bk := Node3D.new()
	bk.name = "ControlBunker"
	add_child(bk)
	var cx: float = 6.0
	var cz: float = 36.0
	var w: float = 14.0
	var d: float = 9.0
	var h: float = 4.2
	var t: float = 1.0
	FBU.box(bk, "Floor", Vector3(w + 2 * t, 0.4, d + 2 * t), Vector3(cx, F - 0.2, cz), FBU.dark_concrete())
	FBU.box(bk, "Roof", Vector3(w + 2 * t, 1.0, d + 2 * t), Vector3(cx, h + 0.5, cz), FBU.concrete())
	FBU.wall(bk, "WallW", Vector3(cx - w * 0.5 - t * 0.5, 0, cz - d * 0.5 - t), Vector3.BACK, d + 2 * t, h, [], FBU.concrete(), t)
	FBU.wall(bk, "WallE", Vector3(cx + w * 0.5 + t * 0.5, 0, cz - d * 0.5 - t), Vector3.BACK, d + 2 * t, h, [], FBU.concrete(), t)
	FBU.wall(bk, "WallS", Vector3(cx - w * 0.5, 0, cz + d * 0.5 + t * 0.5), Vector3.RIGHT, w, h, [{"c": w * 0.5, "w": 2.8, "h": 3.2}], FBU.concrete(), t)
	# North wall with real observation slit windows (gaps between sill and lintel).
	var nz: float = cz - d * 0.5 - t * 0.5
	FBU.box(bk, "SillN", Vector3(w, 1.5, t), Vector3(cx, 0.75, nz), FBU.concrete())
	FBU.box(bk, "LintelN", Vector3(w, h - 2.1, t), Vector3(cx, 2.1 + (h - 2.1) * 0.5, nz), FBU.concrete())
	for i in 5:
		var px: float = cx - w * 0.5 + 1.4 + float(i) * (w - 2.8) / 4.0
		FBU.box(bk, "SlitPost%d" % i, Vector3(1.2, 0.6, t), Vector3(px, 1.8, nz), FBU.concrete())
		if i < 4:
			FBU.box(bk, "SlitGlass%d" % i, Vector3(1.6, 0.6, 0.05), Vector3(px + (w - 2.8) / 8.0, 1.8, nz), FBU.glass(), false)
	for k in 3:
		FBU.console(bk, "Console%d" % k, Vector3(cx - 4.0 + float(k) * 4.0, 0.15, nz + 1.4), 0.0)
	FBU.box(bk, "StatusWall", Vector3(5.0, 1.4, 0.08), Vector3(cx + 3.0, 2.6, cz + d * 0.5 - 0.05), FBU.glow_amber(), false)
	FBU.box(bk, "TacticalTable", Vector3(2.6, 0.9, 1.6), Vector3(cx - 4.0, 0.6, cz + 1.5), FBU.dark_steel())
	var holo := MeshInstance3D.new()
	holo.name = "PadHologram"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 0.9
	cm.radial_segments = 8
	holo.mesh = cm
	holo.material_override = FBU.hologram_material(0.0)
	holo.position = Vector3(cx - 4.0, 1.6, cz + 1.5)
	bk.add_child(holo)
	FBU.register_anim(_anims, holo, "spin", Vector3.UP, 0.8)
	FBU.add_light(bk, Vector3(cx, 3.6, cz), Color(1.0, 0.8, 0.5), 1.4, 11.0)
	FBU.add_light(bk, Vector3(cx + 4, 3.4, cz + 2), Color(0.5, 0.85, 1.0), 0.9, 8.0)
	_floor_points.append(Vector3(cx, F, cz))
	_floor_points.append(Vector3(cx + 4.0, F, cz + 1.0))
