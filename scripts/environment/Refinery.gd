class_name Refinery
extends Node3D
## EASTERN / Iron Desert: automated ore refinery. Twin refinery tower clusters, crusher, two silo banks,
## conveyor bridges, rotating ventilation fans, reciprocating pistons, cargo apron, a 28 m buried transport
## tunnel (walkable, ribbed, emergency lit) and an explorable Refinery Control Building.
## Local frame: +Y up, +Z south (entrance side).

const FBU = preload("res://scripts/environment/FacilityBuilderUtils.gd")
const PAD_RADIUS := 55.0
const F := 0.15
const TUNNEL_Z := -6.0
const TUNNEL_X0 := 24.0
const TUNNEL_FLOOR := 2.2
const TUNNEL_LEN := 28.0
const INTERIOR_SPAWN := Vector3(-20.0, 1.4, 25.0)
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
	FBU.foundation(self, "RefineryPad", PAD_RADIUS, 8, 0.0, ground_h)
	_build_process()
	_build_machinery()
	_build_apron()
	_build_control_building()
	_build_tunnel()


func get_interior_floor_points() -> Array[Vector3]:
	return _floor_points


func get_entrance_local() -> Vector3:
	return Vector3(-23.0, 0.0, 33.0)


func get_tunnel_length() -> float:
	return TUNNEL_LEN


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


func _build_process() -> void:
	_model("refinery_tower_cluster", "TowerCluster1", Vector3(-8, 0, -22))
	_model("refinery_tower_cluster", "TowerCluster2", Vector3(14, 0, -22), 0.5)
	_model("ore_crusher_hopper", "OreCrusher", Vector3(-30, 0, -10))
	_model("storage_silo_bank", "SiloBank1", Vector3(6, 0, 8))
	_model("storage_silo_bank", "SiloBank2", Vector3(30, 0, 12), 0.3)
	FBU.conveyor(self, "ConveyorBridge1", Vector3(-23.5, 4.0, -10), Vector3(-14.5, 9.0, -18), 1.6, 0.7)
	FBU.conveyor(self, "ConveyorBridge2", Vector3(1.5, 11.0, -22), Vector3(5.0, 11.0, -22), 1.6, 0.7)
	FBU.conveyor(self, "ConveyorBridge3", Vector3(10.0, 2.5, -12), Vector3(8.0, 5.5, 4.0), 1.6, 0.9)
	FBU.add_light(self, Vector3(3, 14, -22), Color(1.0, 0.75, 0.45), 1.8, 26.0)
	FBU.add_light(self, Vector3(-30, 9, -10), Color(1.0, 0.8, 0.5), 1.4, 18.0)


func _build_machinery() -> void:
	# Rotating ventilation fans on three vent housings.
	for i in 3:
		var x: float = -10.0 + float(i) * 10.0
		FBU.box(self, "VentHousing%d" % i, Vector3(5.0, 3.0, 5.0), Vector3(x, 1.5, -2.0), FBU.dark_steel())
		FBU.box(self, "VentGrate%d" % i, Vector3(4.4, 0.1, 4.4), Vector3(x, 3.05, -2.0), FBU.truss(), false)
		var rot: Node3D = FBU.fan(self, "VentFan%d" % i, Vector3(x, 3.2, -2.0), 2.0, 5)
		FBU.register_anim(_anims, rot, "spin", Vector3.UP, 5.0 + float(i))
	# Reciprocating processing pistons.
	FBU.box(self, "PistonBlock", Vector3(10.0, 2.2, 3.0), Vector3(-30, 1.1, -27), FBU.dark_steel())
	for i in 4:
		var px: float = -33.0 + float(i) * 2.0
		var rod := Node3D.new()
		rod.name = "PistonRod%d" % i
		rod.position = Vector3(px, 3.4, -27)
		add_child(rod)
		FBU.cyl(rod, "Rod", 0.3, 0.3, 2.4, Vector3.ZERO, FBU.steel(), false, Basis.IDENTITY, 10)
		FBU.cyl(rod, "Cap", 0.45, 0.45, 0.3, Vector3(0, 1.3, 0), FBU.hazard(), false, Basis.IDENTITY, 10)
		FBU.register_anim(_anims, rod, "piston", Vector3.UP, 3.0, 0.7, float(i) * 1.57)
	FBU.light_strip(self, "PistonGlow", Vector3(9.0, 0.08, 0.12), Vector3(-30, 2.25, -25.4), FBU.glow_amber())


func _build_apron() -> void:
	FBU.box(self, "CargoApron", Vector3(30, 0.06, 14), Vector3(2, 0.04, 40), FBU.dark_concrete(), false)
	for i in 6:
		FBU.box(self, "ApronStripe%d" % i, Vector3(0.3, 0.07, 14), Vector3(-12.0 + float(i) * 6.0, 0.05, 40), FBU.hazard(), false)
	FBU.box(self, "Container0", Vector3(6.0, 2.6, 2.4), Vector3(8, 1.3, 38), FBU.rust())
	FBU.box(self, "Container1", Vector3(6.0, 2.6, 2.4), Vector3(8, 3.9, 38), FBU.dark_steel())
	FBU.box(self, "Container2", Vector3(2.4, 2.6, 6.0), Vector3(16, 1.3, 42), FBU.steel())
	for sx in [-10.0, 20.0]:
		FBU.pipe(self, "Floodpole", Vector3(sx, 0, 46), Vector3(sx, 11, 46), 0.2, FBU.dark_steel(), true)
		FBU.add_light(self, Vector3(sx, 11, 46), Color(1.0, 0.95, 0.8), 1.6, 20.0)
		FBU.light_strip(self, "Floodlamp", Vector3(1.2, 0.3, 0.6), Vector3(sx, 11.2, 46), FBU.glow_amber())


func _build_control_building() -> void:
	var cb: Node3D = FBU.room(self, "ControlBuilding", Vector3(16, 5.2, 11), Vector3(-20, F, 24),
			[{"side": "s", "off": -3.0}, {"side": "e", "off": 0.0, "w": 2.8, "h": 3.2}], FBU.concrete(), FBU.dark_concrete(), FBU.dark_steel())
	for cx in [-4.0, 0.0, 4.0]:
		FBU.console(cb, "Console", Vector3(cx, 0, -4.8), 0.0)
	FBU.box(cb, "ProcessWindow", Vector3(10.0, 1.4, 0.08), Vector3(0, 3.3, -5.55), FBU.glass(), false)
	FBU.box(cb, "ProcessTable", Vector3(3.0, 0.9, 1.8), Vector3(4.5, 0.45, 1.5), FBU.dark_steel())
	var holo := MeshInstance3D.new()
	holo.name = "ProcessHologram"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.6
	cm.height = 1.2
	cm.radial_segments = 8
	holo.mesh = cm
	holo.material_override = FBU.hologram_material(1.0)
	holo.position = Vector3(4.5, 1.7, 1.5)
	cb.add_child(holo)
	FBU.register_anim(_anims, holo, "spin", Vector3.UP, 0.9)
	FBU.light_strip(cb, "StatusBoard", Vector3(5.0, 1.2, 0.08), Vector3(-5.0, 3.0, 5.45), FBU.glow_amber())
	FBU.add_light(cb, Vector3(-2, 4.5, 0), Color(1.0, 0.9, 0.75), 1.6, 12.0)
	FBU.add_light(cb, Vector3(5, 4.5, 0), Color(0.6, 0.85, 1.0), 1.0, 9.0)
	_floor_points = [Vector3(-20, F, 25.0), Vector3(-24, F, 22.0), Vector3(-26, F, 26.0)]


func _build_tunnel() -> void:
	var t := Node3D.new()
	t.name = "TransportTunnel"
	add_child(t)
	var x0: float = TUNNEL_X0
	var x1: float = TUNNEL_X0 + TUNNEL_LEN
	var zc: float = TUNNEL_Z
	var tf: float = TUNNEL_FLOOR
	var top: float = tf + 4.4
	# Solid plinth + floor (tunnel mouth rises out of the pad; sits above the coarse terrain collision rim).
	FBU.box(t, "Floor", Vector3(TUNNEL_LEN, tf, 5.4), Vector3((x0 + x1) * 0.5, tf * 0.5, zc), FBU.dark_concrete())
	FBU.ramp(t, "PortalRamp", Vector3(x0 - 10.0, F, zc), Vector3(x0 + 0.5, tf, zc), 4.4, FBU.dark_concrete())
	FBU.wall(t, "WallN", Vector3(x0, tf, zc - 2.45), Vector3.RIGHT, TUNNEL_LEN, 4.4, [], FBU.concrete(), 0.5)
	FBU.wall(t, "WallS", Vector3(x0, tf, zc + 2.45), Vector3.RIGHT, TUNNEL_LEN, 4.4, [], FBU.concrete(), 0.5)
	FBU.box(t, "Roof", Vector3(TUNNEL_LEN, 0.6, 5.4), Vector3((x0 + x1) * 0.5, top + 0.3, zc), FBU.dark_concrete())
	FBU.box(t, "EndBlastDoor", Vector3(0.5, 4.4, 4.4), Vector3(x1 + 0.25, tf + 2.2, zc), FBU.dark_steel())
	FBU.light_strip(t, "EndDoorGlow", Vector3(0.1, 0.3, 3.6), Vector3(x1 - 0.05, tf + 2.4, zc), FBU.glow_red())
	# Portal headwall: split around the tunnel mouth (4.4 m wide, open from the ground up to the roof line).
	FBU.wall(t, "PortalHeadwall", Vector3(x0 - 0.75, 0, zc - 8.0), Vector3.BACK, 16.0, top + 4.0, [{"c": 8.0, "w": 4.4, "h": top}], FBU.concrete(), 1.5)
	FBU.box(t, "PortalHazard", Vector3(1.6, 0.4, 16.0), Vector3(x0 - 0.75, top + 4.2, zc), FBU.hazard(), false)
	# Overburden mound over the tunnel (buried look).
	FBU.box(t, "Overburden", Vector3(TUNNEL_LEN - 1.0, 3.0, 9.0), Vector3((x0 + x1) * 0.5 + 0.5, top + 2.1, zc), FBU.rust())
	# Interior ribs + emergency lighting.
	var n: int = int(TUNNEL_LEN / 4.0)
	for i in n:
		var rx: float = x0 + 2.0 + float(i) * 4.0
		FBU.box(t, "Rib%d" % i, Vector3(0.35, 4.3, 4.35), Vector3(rx, tf + 2.2, zc), FBU.steel(), false)
		FBU.light_strip(t, "EmergencyN%d" % i, Vector3(0.4, 0.12, 0.08), Vector3(rx, tf + 3.6, zc - 2.15), FBU.glow_red() if i % 2 == 0 else FBU.glow_amber())
		FBU.light_strip(t, "EmergencyS%d" % i, Vector3(0.4, 0.12, 0.08), Vector3(rx, tf + 3.6, zc + 2.15), FBU.glow_amber())
	for lx in [x0 + 6.0, x0 + 15.0, x0 + 24.0]:
		FBU.add_light(t, Vector3(lx, tf + 3.6, zc), Color(1.0, 0.4, 0.2), 1.1, 9.0, false, "Emergency")
	_floor_points.append(Vector3(x0 + 4.0, tf, zc))
	_floor_points.append(Vector3(x0 + 14.0, tf, zc))
	_floor_points.append(Vector3(x0 + 24.0, tf, zc))
