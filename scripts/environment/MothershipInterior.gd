class_name MothershipInterior
extends Node3D
## Explorable 7-room mothership interior (ship-local coordinates: +Z = bow / toward Vesper-9, +Y = deck up,
## main deck floor at y = 0). All rooms are physically connected by walkable corridors, a ramp, stairs and
## open doorways. Identical layout for HELION and CINDER; only palette + dressing differ.

const K = preload("res://scripts/environment/ModularKitBuilder.gd")
const FORCEFIELD_SHADER := "res://shaders/forcefield.gdshader"
const HOLOGRAM_SHADER := "res://shaders/hologram.gdshader"
const CONVEYOR_SHADER := "res://shaders/conveyor.gdshader"

const ROOM_NAMES: PackedStringArray = [
	"Main Hangar", "Command Bridge", "Reactor Chamber", "Engineering Workshop",
	"Cargo Bay", "Crew Facility", "External Docking Area",
]
## Ship-local walkable spawn points (floor + 1.0 m).
const ROOM_SPAWNS: Dictionary = {
	"Main Hangar": Vector3(0, 1, 300),
	"Command Bridge": Vector3(92, 9, 200),
	"Reactor Chamber": Vector3(-70, 1, -100),
	"Engineering Workshop": Vector3(-30, 1, -130),
	"Cargo Bay": Vector3(60, 1, 70),
	"Crew Facility": Vector3(32, 1, -168),
	"External Docking Area": Vector3(-100, 1, 140),
}
const ROOM_FLOOR_Y: Dictionary = {
	"Main Hangar": 0.0, "Command Bridge": 8.0, "Reactor Chamber": 0.0, "Engineering Workshop": 0.0,
	"Cargo Bay": 0.0, "Crew Facility": 0.0, "External Docking Area": 0.0,
}
const ROOM_NODES: Dictionary = {
	"Main Hangar": "MainHangar", "Command Bridge": "CommandBridge", "Reactor Chamber": "ReactorChamber",
	"Engineering Workshop": "EngineeringWorkshop", "Cargo Bay": "CargoBay", "Crew Facility": "CrewFacility",
	"External Docking Area": "ExternalDocking",
}
const INTERIOR_AABB := AABB(Vector3(-152, -12, -258), Vector3(304, 72, 683))

const HANGAR_Z0 := 265.0
const HANGAR_Z1 := 425.0
const HANGAR_HALF_W := 45.0
const HANGAR_H := 40.0
const DOOR_Z := 421.5
const DOOR_TIME := 5.0

@export var faction: String = "helion"
## "" = whole interior; "hangar" | "bridge" | "reactor" | "corridor" = standalone room scenes.
@export var room_filter: String = ""

var built: bool = false
var rooms: Dictionary = {}
var _p: Dictionary = {}
var _lights: Array[OmniLight3D] = []
var _pulse: Array = []
var _rotors: Array = []
var _swayers: Array = []
var _leaves: Array[Node3D] = []
var _forcefield: MeshInstance3D
var _door_open: bool = true
var _door_t: float = 1.0
var _time: float = 0.0
var _filter_rooms: Array = []


func _ready() -> void:
	if not built:
		build()


# ---------------------------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------------------------

func get_room_spawn_points() -> Dictionary:
	var out: Dictionary = {}
	for r in ROOM_SPAWNS:
		if rooms.has(r):
			out[r] = ROOM_SPAWNS[r]
	return out


func get_room_floor_y(room: String) -> float:
	return float(ROOM_FLOOR_Y.get(room, 0.0))


func get_interior_aabb() -> AABB:
	return INTERIOR_AABB


## Straight segments (ship-local, eye height 1.2 m above the local floor) that must be free of collision.
func get_walkable_path_segments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var bridge: Array = [
		["Hangar -> aft door -> main corridor", Vector3(0, 1.2, 300), Vector3(0, 1.2, 200)],
		["Main corridor -> bridge corridor", Vector3(0, 1.2, 200), Vector3(44, 1.2, 200)],
		["Observation ramp", Vector3(44, 1.2, 200), Vector3(76, 9.2, 200)],
		["Ramp top -> bridge doorway -> bridge deck", Vector3(76, 9.2, 200), Vector3(98, 9.2, 200)],
	]
	var reactor: Array = [
		["Hangar -> main corridor (aft run)", Vector3(0, 1.2, 300), Vector3(0, 1.2, -100)],
		["Engineering corridor -> reactor doorway", Vector3(0, 1.2, -100), Vector3(-70, 1.2, -100)],
	]
	for s in bridge:
		out.append({"route": "bridge", "name": s[0], "from": s[1], "to": s[2]})
	for s in reactor:
		out.append({"route": "reactor", "name": s[0], "from": s[1], "to": s[2]})
	return out


func set_hangar_doors_open(open: bool) -> void:
	_door_open = open
	_apply_door_collision()


func toggle_hangar_doors() -> void:
	set_hangar_doors_open(not _door_open)


func is_hangar_doors_open() -> bool:
	return _door_open


func get_door_progress() -> float:
	return _door_t


func get_hangar_door_leaves() -> Array[Node3D]:
	return _leaves


func set_lights_active(on: bool) -> void:
	for l in _lights:
		if is_instance_valid(l):
			l.visible = on


func get_light_count() -> int:
	return _lights.size()


func get_diagnostics() -> Dictionary:
	return {
		"faction": faction, "rooms": rooms.size(), "lights": _lights.size(),
		"doors_open": _door_open, "door_progress": _door_t,
	}


func tick(delta: float) -> void:
	_time += delta
	var target: float = 1.0 if _door_open else 0.0
	if not is_equal_approx(_door_t, target):
		_door_t = move_toward(_door_t, target, delta / DOOR_TIME)
		_apply_door_pose()
	for r in _rotors:
		var n: Node3D = r["node"]
		if is_instance_valid(n):
			n.rotate(r["axis"], float(r["speed"]) * delta)
	for pm in _pulse:
		var m: StandardMaterial3D = pm["mat"]
		m.emission_energy_multiplier = float(pm["base"]) * (0.6 + 0.4 * sin(_time * float(pm["speed"]) + float(pm["phase"])))
	for sw in _swayers:
		var n2: Node3D = sw["node"]
		if is_instance_valid(n2):
			n2.rotation.y = float(sw["base"]) + float(sw["amp"]) * sin(_time * float(sw["speed"]) + float(sw["phase"]))


# ---------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------

func build() -> void:
	if built:
		return
	built = true
	_p = K.palette(faction)
	if faction == "helion":
		_p = _p.duplicate()
		_p["floor"] = Color("758391")
		_p["hull"] = Color("EBF1F7")
	match room_filter.to_lower():
		"hangar": _filter_rooms = ["Main Hangar"]
		"bridge": _filter_rooms = ["Command Bridge"]
		"reactor": _filter_rooms = ["Reactor Chamber"]
		"corridor": _filter_rooms = ["Crew Facility"]
		_: _filter_rooms = []
	if _wants("Main Hangar"):
		_build_hangar()
	if _wants("Command Bridge"):
		_build_bridge()
	if _wants("Reactor Chamber"):
		_build_reactor()
	if _wants("Engineering Workshop"):
		_build_workshop()
	if _wants("Cargo Bay"):
		_build_cargo()
	if _wants("Crew Facility"):
		_build_crew()
	if _wants("External Docking Area"):
		_build_docking()
	if _filter_rooms.is_empty():
		_build_spine()
	_apply_door_pose()
	_apply_door_collision()


func _wants(room: String) -> bool:
	return _filter_rooms.is_empty() or _filter_rooms.has(room)


func _room(room: String) -> Node3D:
	var n := Node3D.new()
	n.name = ROOM_NODES[room]
	n.set_meta("room", room)
	add_child(n)
	rooms[room] = n
	return n


# --- helpers ----------------------------------------------------------------------------------

func _mat(key: String, metallic: float = 0.4, rough: float = 0.5, emis: float = 0.0) -> StandardMaterial3D:
	return K.material(_p[key], metallic, rough, emis)


func _pulse_mat(color: Color, base: float, speed: float = 2.0, phase: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = base
	_pulse.append({"mat": m, "base": base, "speed": speed, "phase": phase})
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, key: String = "hull", collide: bool = true, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n: Node3D = K.box(parent, size, pos, _mat(key, 0.4, 0.5), collide)
	if rot_deg != Vector3.ZERO:
		n.rotation_degrees = rot_deg
	return n


func _glow(parent: Node3D, size: Vector3, pos: Vector3, key: String = "accent", energy: float = 2.5, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n: Node3D = K.box(parent, size, pos, _mat(key, 0.0, 0.4, energy), false)
	if rot_deg != Vector3.ZERO:
		n.rotation_degrees = rot_deg
	return n


func _module(parent: Node3D, module_name: String, pos: Vector3, rot_deg: float = 0.0) -> Node3D:
	var m: Node3D = K.build_module(module_name, faction)
	m.position = pos
	m.rotation_degrees.y = rot_deg
	parent.add_child(m)
	return m


func _prop(parent: Node3D, key: String, pos: Vector3, rot_deg: float = 0.0, collision: String = "box") -> Node3D:
	var n: Node3D = K.build_prop(key, faction, collision)
	n.position = pos
	n.rotation_degrees.y = rot_deg
	parent.add_child(n)
	return n


func _light(parent: Node3D, pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)
	_lights.append(l)
	return l


func _door(parent: Node3D, center: Vector3, rot_deg: float, w: float, h: float) -> Node3D:
	var d: Node3D = K.build_door(w, h, faction, "Door_Large" if w >= 8.0 else "Door_Small")
	d.position = center
	d.rotation_degrees.y = rot_deg
	parent.add_child(d)
	return d


func _slab(parent: Node3D, center: Vector3, size: Vector3, key: String = "floor") -> Node3D:
	var roughness: float = 0.40 if faction == "helion" and key == "floor" else 0.45
	return K.box(parent, size, center, _mat(key, 0.5, roughness), true)


## Wall run along "x" (fixed z) or "z" (fixed x). gaps: [[from, to, gap_height]] along the run.
func _wall(parent: Node3D, axis: String, fixed: float, a: float, b: float, y0: float, h: float, gaps: Array = [], thick: float = 1.0, strip: bool = true) -> void:
	var sorted: Array = gaps.duplicate()
	sorted.sort_custom(func(g1: Array, g2: Array) -> bool: return g1[0] < g2[0])
	var cursor: float = a
	for g in sorted:
		if float(g[0]) > cursor + 0.01:
			_wall_seg(parent, axis, fixed, cursor, float(g[0]), y0, h, thick, strip)
		var gh: float = float(g[2])
		if gh < h - 0.01:
			_wall_seg(parent, axis, fixed, float(g[0]), float(g[1]), y0 + gh, h - gh, thick, false)
		cursor = float(g[1])
	if b > cursor + 0.01:
		_wall_seg(parent, axis, fixed, cursor, b, y0, h, thick, strip)


func _wall_seg(parent: Node3D, axis: String, fixed: float, from: float, to: float, y0: float, h: float, thick: float, strip: bool) -> void:
	var length: float = to - from
	var mid: float = (from + to) * 0.5
	var size: Vector3 = Vector3(length, h, thick) if axis == "x" else Vector3(thick, h, length)
	var pos: Vector3 = Vector3(mid, y0 + h * 0.5, fixed) if axis == "x" else Vector3(fixed, y0 + h * 0.5, mid)
	K.box(parent, size, pos, _mat("hull", 0.35, 0.55), true)
	if strip and length > 6.0 and h > 4.0:
		var sz: Vector3 = Vector3(length * 0.8, 0.1, thick + 0.06) if axis == "x" else Vector3(thick + 0.06, 0.1, length * 0.8)
		K.box(parent, sz, Vector3(pos.x, y0 + minf(h * 0.45, 3.4), pos.z), _mat("accent", 0.0, 0.4, 1.8), false)


## Room shell: floor + ceiling slabs. Walls are added by the caller.
func _shell(parent: Node3D, x0: float, x1: float, z0: float, z1: float, y0: float, h: float, ceiling: bool = true) -> void:
	var c := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var sx: float = x1 - x0
	var sz: float = z1 - z0
	_slab(parent, Vector3(c.x, y0 - 0.5, c.z), Vector3(sx, 1.0, sz), "floor")
	if ceiling:
		_slab(parent, Vector3(c.x, y0 + h + 0.5, c.z), Vector3(sx + 2.0, 1.0, sz + 2.0), "hull")
	_glow(parent, Vector3(sx * 0.5, 0.03, 0.25), Vector3(c.x, y0 + 0.02, z0 + 1.2), "warn", 1.2)


func _outline_rect(parent: Node3D, center: Vector3, w: float, d: float, key: String = "accent", energy: float = 1.6) -> void:
	_glow(parent, Vector3(w, 0.03, 0.25), center + Vector3(0, 0, d * 0.5), key, energy)
	_glow(parent, Vector3(w, 0.03, 0.25), center - Vector3(0, 0, d * 0.5), key, energy)
	_glow(parent, Vector3(0.25, 0.03, d), center + Vector3(w * 0.5, 0, 0), key, energy)
	_glow(parent, Vector3(0.25, 0.03, d), center - Vector3(w * 0.5, 0, 0), key, energy)


func _rail(parent: Node3D, pos: Vector3, length: float, along_z: bool, collision_height: float = -1.0) -> void:
	var r: Node3D = K.build_rail(length, 1.2, faction, collision_height)
	r.position = pos
	if along_z:
		r.rotation_degrees.y = 90.0
	parent.add_child(r)


func _rotor(node: Node3D, speed: float, axis: Vector3 = Vector3.UP) -> void:
	_rotors.append({"node": node, "speed": speed, "axis": axis})


func _torus_ring(parent: Node3D, radius: float, tube: float, pos: Vector3, nodules: int, speed: float, key: String = "accent") -> Node3D:
	var ring := Node3D.new()
	ring.position = pos
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - tube
	tm.outer_radius = radius + tube
	tm.rings = 32
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = _mat("metal", 0.8, 0.3)
	ring.add_child(mi)
	for i in nodules:
		var a: float = TAU * float(i) / float(nodules)
		K.box(ring, Vector3(0.9, 0.7, 0.9), Vector3(cos(a) * radius, 0, sin(a) * radius), _pulse_mat(_p[key], 2.8, 1.6, float(i)), false)
	parent.add_child(ring)
	_rotor(ring, speed)
	return ring


func _shader_mat(path: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load(path) as Shader
	return sm


# ---------------------------------------------------------------------------------------------
# Spine (main corridor) + engineering / bridge / cargo / airlock spurs
# ---------------------------------------------------------------------------------------------

func _corridor(parent: Node3D, axis: String, fixed: float, a: float, b: float, gaps_lo: Array, gaps_hi: Array, y0: float = 0.0, h: float = 6.0, ceiling: bool = true) -> void:
	var mid: float = (a + b) * 0.5
	var length: float = b - a
	if axis == "z":
		_slab(parent, Vector3(fixed, y0 - 0.5, mid), Vector3(8.0, 1.0, length), "floor")
		if ceiling:
			_slab(parent, Vector3(fixed, y0 + h + 0.5, mid), Vector3(8.0, 1.0, length), "hull")
		_wall(parent, "z", fixed - 4.0, a, b, y0, h, gaps_lo, 0.6, false)
		_wall(parent, "z", fixed + 4.0, a, b, y0, h, gaps_hi, 0.6, false)
	else:
		_slab(parent, Vector3(mid, y0 - 0.5, fixed), Vector3(length, 1.0, 8.0), "floor")
		if ceiling:
			_slab(parent, Vector3(mid, y0 + h + 0.5, fixed), Vector3(length, 1.0, 8.0), "hull")
		_wall(parent, "x", fixed - 4.0, a, b, y0, h, gaps_lo, 0.6, false)
		_wall(parent, "x", fixed + 4.0, a, b, y0, h, gaps_hi, 0.6, false)
	# Ceiling light modules + cable tray + floor guide strip.
	var count: int = maxi(1, int(length / 24.0))
	for i in count:
		var t: float = a + (float(i) + 0.5) * length / float(count)
		var lm: Node3D = K.build_light_module(faction, false)
		lm.position = Vector3(fixed, y0 + h - 0.12, t) if axis == "z" else Vector3(t, y0 + h - 0.12, fixed)
		lm.rotation_degrees.y = 90.0 if axis == "z" else 0.0
		parent.add_child(lm)
	if axis == "z":
		_glow(parent, Vector3(0.18, 0.02, length), Vector3(fixed - 2.4, y0 + 0.02, mid), "accent", 1.4)
		_glow(parent, Vector3(0.18, 0.02, length), Vector3(fixed + 2.4, y0 + 0.02, mid), "accent", 1.4)
		_box(parent, Vector3(0.6, 0.12, length), Vector3(fixed - 3.4, y0 + h - 1.0, mid), "trim", false)
	else:
		_glow(parent, Vector3(length, 0.02, 0.18), Vector3(mid, y0 + 0.02, fixed - 2.4), "accent", 1.4)
		_glow(parent, Vector3(length, 0.02, 0.18), Vector3(mid, y0 + 0.02, fixed + 2.4), "accent", 1.4)
		_box(parent, Vector3(length, 0.12, 0.6), Vector3(mid, y0 + h - 1.0, fixed - 3.4), "trim", false)


func _build_spine() -> void:
	var c := Node3D.new()
	c.name = "Corridors"
	add_child(c)
	# Spine along Z at x = 0, from the crew hub (z = -204) to the hangar aft door (z = 265).
	_corridor(c, "z", 0.0, -204.0, 265.0,
		[[-104.0, -96.0, 6.0], [136.0, 144.0, 6.0]],   # west: engineering corridor, airlock corridor
		[[66.0, 74.0, 6.0], [196.0, 204.0, 6.0]])      # east: cargo access, bridge corridor
	# Engineering corridor (x -50 .. -4 at z = -100): workshop door on the south wall.
	_corridor(c, "x", -100.0, -49.0, -3.7, [[-34.0, -26.0, 6.0]], [])
	# Cargo access corridor (x 4 .. 44 at z = 70) with a heavy bulkhead door mid-run.
	_corridor(c, "x", 70.0, 3.7, 44.0, [], [])
	_door(c, Vector3(24.0, 0, 70.0), 90.0, 8.0, 6.0)
	# Bridge corridor (x 4 .. 44 at z = 200) leading to the observation ramp.
	_corridor(c, "x", 200.0, 3.7, 44.0, [], [])
	# Airlock corridor (x -44 .. -4 at z = 140).
	_corridor(c, "x", 140.0, -44.0, -3.7, [], [])
	_light(c, Vector3(0, 5.2, 230), _p["accent"].lerp(Color.WHITE, 0.6), 1.0, 30.0)
	_light(c, Vector3(0, 5.2, 100), _p["accent"].lerp(Color.WHITE, 0.6), 1.0, 30.0)
	_light(c, Vector3(0, 5.2, -30), _p["accent"].lerp(Color.WHITE, 0.6), 1.0, 30.0)
	# Pipes + vents along the spine ceiling for dressing.
	for i in 8:
		var z: float = 240.0 - float(i) * 56.0
		_module(c, "Vent_Unit", Vector3(2.4, 5.2, z), 0.0)
		_module(c, "Pipe_Straight", Vector3(-3.3, 4.6, z - 20.0), 90.0)


# ---------------------------------------------------------------------------------------------
# Room 1: MAIN HANGAR (90 x 160 x 40 m)
# ---------------------------------------------------------------------------------------------

func _build_hangar() -> void:
	var r: Node3D = _room("Main Hangar")
	var zc: float = (HANGAR_Z0 + HANGAR_Z1) * 0.5
	_shell(r, -HANGAR_HALF_W, HANGAR_HALF_W, HANGAR_Z0, HANGAR_Z1, 0.0, HANGAR_H)
	_wall(r, "z", -HANGAR_HALF_W - 0.5, HANGAR_Z0, HANGAR_Z1, 0.0, HANGAR_H + 1.0)
	_wall(r, "z", HANGAR_HALF_W + 0.5, HANGAR_Z0, HANGAR_Z1, 0.0, HANGAR_H + 1.0)
	_wall(r, "x", HANGAR_Z0 + 0.5, -HANGAR_HALF_W - 1.0, HANGAR_HALF_W + 1.0, 0.0, HANGAR_H + 1.0, [[-4.0, 4.0, 12.0]])
	_door(r, Vector3(0, 0, HANGAR_Z0 + 0.5), 0.0, 8.0, 12.0)
	_glow(r, Vector3(8.0, 0.3, 0.2), Vector3(0, 12.8, HANGAR_Z0 + 1.0), "warn", 3.0)

	# --- Hangar door housings (leaves slide into the thick bow walls) + animated leaves + forcefield ---
	for side in [-1.0, 1.0]:
		K.box(r, Vector3(50.0, HANGAR_H + 1.0, 7.0), Vector3(side * 70.0, (HANGAR_H + 1.0) * 0.5, 421.5), _mat("trim", 0.6, 0.45), true)
	_glow(r, Vector3(90.0, 0.4, 0.3), Vector3(0, 0.25, 424.2), "warn", 2.5)
	var door: Node3D = K.build_hangar_door(HANGAR_HALF_W * 2.0, HANGAR_H, faction)
	door.position = Vector3(0, 0, DOOR_Z)
	r.add_child(door)
	_leaves.clear()
	for nm in ["LeafL", "LeafR"]:
		_leaves.append(door.get_node(nm) as Node3D)
	_forcefield = MeshInstance3D.new()
	_forcefield.name = "AtmosphereForcefield"
	var qm := QuadMesh.new()
	qm.size = Vector2(HANGAR_HALF_W * 2.0, HANGAR_H)
	_forcefield.mesh = qm
	var ff: ShaderMaterial = _shader_mat(FORCEFIELD_SHADER)
	ff.set_shader_parameter("field_color", Color(0.15, 0.7, 1.0) if faction == "helion" else Color(1.0, 0.45, 0.1))
	_forcefield.material_override = ff
	_forcefield.position = Vector3(0, HANGAR_H * 0.5, 424.4)
	r.add_child(_forcefield)

	# --- Lane markings + parking bays ---
	for sx in [-12.0, 12.0]:
		_glow(r, Vector3(0.3, 0.03, 128.0), Vector3(sx, 0.02, 345.0), "warn", 1.8)
	_glow(r, Vector3(24.0, 0.03, 0.4), Vector3(0, 0.02, 290.0), "warn", 1.8)
	for bx in [-22.0, 22.0]:
		_outline_rect(r, Vector3(bx, 0.02, 350.0), 26.0, 26.0, "accent", 1.8)
		_prop(r, "shuttle", Vector3(bx, 0.0, 350.0), 0.0, "box")
		_prop(r, "gantry_crane", Vector3(bx, 0.0, 350.0), 0.0, "legs")
		_glow(r, Vector3(8.0, 0.03, 0.6), Vector3(bx, 0.02, 335.0), "warn", 2.0)

	# --- Overhead crane rails + bridge beam + hoist ---
	for rx in [-34.0, 34.0]:
		_box(r, Vector3(1.4, 1.6, 140.0), Vector3(rx, 33.0, 345.0), "trim", false)
	var span := Node3D.new()
	span.name = "OverheadCrane"
	r.add_child(span)
	_box(span, Vector3(70.0, 1.8, 2.4), Vector3(0, 33.0, 0), "metal", false)
	_box(span, Vector3(3.0, 1.4, 3.0), Vector3(0, 31.4, 0), "warn", false)
	K.cylinder(span, 0.1, 12.0, Vector3(0, 24.5, 0), _mat("metal", 0.8, 0.3), false)
	span.position = Vector3(0, 0, 330.0)

	# --- Service / tool stations (west wall), fuel pipes + tanks, cargo stacks ---
	for i in 3:
		var z: float = 285.0 + float(i) * 22.0
		_box(r, Vector3(2.4, 1.1, 6.0), Vector3(-43.4, 0.55, z), "trim")
		_box(r, Vector3(0.3, 2.0, 5.0), Vector3(-44.4, 2.1, z), "dark", false)
		_glow(r, Vector3(0.1, 1.2, 3.6), Vector3(-44.2, 2.4, z), "accent", 2.2)
	for i in 8:
		_module(r, "Pipe_Straight", Vector3(-43.6, 0.05, 345.0 + float(i) * 4.0), 90.0)
	_module(r, "Pipe_Elbow", Vector3(-43.6, 0.05, 377.0), 0.0)
	for tz in [392.0, 404.0]:
		K.cylinder(r, 2.4, 7.0, Vector3(-40.0, 3.5, tz), _mat("metal", 0.7, 0.4), true)
		K.cylinder(r, 2.45, 0.5, Vector3(-40.0, 5.6, tz), _mat("warn", 0.0, 0.5, 1.5), false)
	for i in 6:
		var cx: float = 37.0 + float(i % 2) * 3.4
		var cz: float = 330.0 + float(i / 2) * 3.6
		_box(r, Vector3(3.2, 3.0, 3.2), Vector3(cx, 1.5, cz), "alt" if i % 3 == 0 else "trim")
	_box(r, Vector3(3.2, 3.0, 3.2), Vector3(38.7, 4.5, 331.8), "hull")

	# --- Elevated observation walkway (east) with stairs + railings ---
	_slab(r, Vector3(41.0, 13.7, 365.0), Vector3(8.0, 0.6, 100.0), "metal")
	_glow(r, Vector3(0.2, 0.03, 100.0), Vector3(37.4, 14.02, 365.0), "accent", 2.0)
	_rail(r, Vector3(37.1, 14.0, 365.0), 100.0, true)
	_rail(r, Vector3(41.0, 14.0, 415.0), 8.0, false)
	for cz in [330.0, 365.0, 400.0]:
		var col: Node3D = K.build_column(13.4, faction)
		col.position = Vector3(37.6, 0.0, cz)
		r.add_child(col)
	var st: Node3D = K.build_stairs(14.0, 28.0, 6.0, faction)
	st.position = Vector3(42.0, 0.0, 287.0)
	r.add_child(st)

	# --- Ceiling lighting + lights (budgeted: 4 shadowless omnis) ---
	for i in 6:
		for sx in [-24.0, 24.0]:
			var lm: Node3D = K.build_light_module(faction, false)
			lm.position = Vector3(sx, HANGAR_H - 0.1, 280.0 + float(i) * 28.0)
			r.add_child(lm)
			_glow(r, Vector3(6.0, 0.1, 2.4), Vector3(sx, HANGAR_H - 0.2, 280.0 + float(i) * 28.0), "accent", 1.6)
	var warm: Color = Color(1.0, 0.95, 0.85)
	_light(r, Vector3(-22, 32, 310), warm, 3.55, 65.0)
	_light(r, Vector3(22, 32, 310), warm, 3.55, 65.0)
	_light(r, Vector3(-22, 32, 385), warm, 3.55, 65.0)
	_light(r, Vector3(22, 32, 385), _p["accent"].lerp(Color.WHITE, 0.5), 3.55, 65.0)


# ---------------------------------------------------------------------------------------------
# Room 2: COMMAND BRIDGE (raised deck, y = 8) + observation ramp
# ---------------------------------------------------------------------------------------------

func _build_bridge() -> void:
	var r: Node3D = _room("Command Bridge")
	var x0: float = 76.0
	var x1: float = 140.0
	var z0: float = 160.0
	var z1: float = 245.0
	var fy: float = 8.0
	var h: float = 16.0
	_slab(r, Vector3(108.0, 3.5, 202.5), Vector3(64.0, 7.0, 85.0), "trim")      # plinth under the raised deck
	_shell(r, x0, x1, z0, z1, fy, h)
	_wall(r, "z", x0 - 0.5, z0, z1, fy, h, [[196.0, 204.0, 12.0]])
	_wall(r, "z", x1 + 0.5, z0, z1, fy, h)
	_wall(r, "x", z0 - 0.5, x0, x1, fy, h)
	_door(r, Vector3(x0 - 0.5, fy, 200.0), 90.0, 8.0, 12.0)

	# Panoramic windows toward Vesper-9 (+Z) : 8 x Window_Module (8 x 14 m).
	for i in 8:
		var wnd: Node3D = K.build_window(8.0, 14.0, faction)
		wnd.position = Vector3(x0 + 4.0 + float(i) * 8.0, fy, z1 + 0.5)
		r.add_child(wnd)
	_box(r, Vector3(64.0, 2.0, 1.0), Vector3(108.0, fy + 15.0, z1 + 0.5), "trim")

	# Holotable + hologram planet projection.
	var tcenter := Vector3(116.0, fy, 205.0)
	_prop(r, "holotable", tcenter, 0.0, "box")
	var holo := Node3D.new()
	holo.name = "HologramPlanet"
	holo.position = tcenter + Vector3(0, 1.6 + 3.2, 0)
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.6
	sm.height = 5.2
	sm.radial_segments = 32
	sm.rings = 16
	sphere.mesh = sm
	var hm: ShaderMaterial = _shader_mat(HOLOGRAM_SHADER)
	hm.set_shader_parameter("amber_mix", 0.0 if faction == "helion" else 1.0)
	sphere.material_override = hm
	holo.add_child(sphere)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.3
	tm.outer_radius = 3.45
	ring.mesh = tm
	ring.material_override = _pulse_mat(_p["accent"], 2.5, 1.2)
	ring.rotation_degrees = Vector3(18, 0, 0)
	holo.add_child(ring)
	r.add_child(holo)
	_rotor(holo, 0.35)
	_light(r, tcenter + Vector3(0, 6.0, 0), _p["accent"], 1.4, 25.0)

	# Officer consoles along the south wall.
	for i in 5:
		var cx: float = 84.0 + float(i) * 12.0
		_box(r, Vector3(6.0, 1.1, 2.0), Vector3(cx, fy + 0.55, z0 + 1.5), "trim")
		_glow(r, Vector3(5.2, 0.08, 1.4), Vector3(cx, fy + 1.2, z0 + 1.5), "accent", 2.4, Vector3(-28, 0, 0))
		_glow(r, Vector3(5.0, 2.0, 0.1), Vector3(cx, fy + 3.3, z0 + 0.3), "accent", 1.6)
	# Pilot seats facing the windows.
	for sx in [96.0, 108.0, 120.0, 132.0]:
		_box(r, Vector3(1.4, 0.6, 1.4), Vector3(sx, fy + 0.3, 232.0), "alt")
		_box(r, Vector3(1.4, 1.5, 0.3), Vector3(sx, fy + 1.3, 231.2), "alt", false)
		_box(r, Vector3(3.0, 1.0, 1.0), Vector3(sx, fy + 0.5, 235.5), "trim")
		_glow(r, Vector3(2.6, 0.08, 0.8), Vector3(sx, fy + 1.05, 235.5), "accent", 2.4, Vector3(-25, 0, 0))
	# Overhead status monitors + emergency lighting.
	for i in 4:
		var mx: float = 88.0 + float(i) * 16.0
		K.box(r, Vector3(7.0, 2.4, 0.3), Vector3(mx, fy + 12.5, 214.0), _pulse_mat(_p["accent"], 1.6, 1.0, float(i)), false)
		_box(r, Vector3(7.4, 2.8, 0.2), Vector3(mx, fy + 12.5, 214.2), "dark", false)
	var emerg: Color = Color(1.0, 0.18, 0.1) if faction == "helion" else Color(1.0, 0.5, 0.1)
	for i in 6:
		K.box(r, Vector3(1.2, 0.2, 0.2), Vector3(x0 + 2.0 + float(i) * 12.0, fy + h - 0.6, z0 + 1.0), _pulse_mat(emerg, 2.2, 3.0, float(i) * 0.7), false)
	_light(r, Vector3(96, fy + 13, 185), Color(0.9, 0.95, 1.0), 2.6, 52.0)
	_light(r, Vector3(124, fy + 13, 228), Color(0.9, 0.95, 1.0), 2.6, 52.0)

	# Observation ramp (32 m long, +8 m) from the bridge corridor up to the bridge doorway.
	var ramp: Node3D = K.build_ramp(32.0, 8.0, 8.0, faction)
	ramp.position = Vector3(44.0, 0.0, 200.0)
	ramp.rotation_degrees.y = 90.0
	r.add_child(ramp)
	_wall(r, "x", 195.5, 44.0, 76.0, 0.0, 22.0, [], 1.0, false)
	_wall(r, "x", 204.5, 44.0, 76.0, 0.0, 22.0, [], 1.0, false)
	_slab(r, Vector3(60.0, 22.5, 200.0), Vector3(32.0, 1.0, 10.0), "hull")
	# Stairs alongside the ramp (south side of the bridge deck): bridge floor <-> dais.
	var dais: Node3D = K.build_stairs(4.0, 8.0, 6.0, faction)
	dais.position = Vector3(108.0, fy, 168.0)
	r.add_child(dais)
	_slab(r, Vector3(108.0, fy + 3.5, 181.0), Vector3(24.0, 1.0, 10.0), "trim")
	_glow(r, Vector3(24.0, 0.03, 0.2), Vector3(108.0, fy + 4.03, 176.2), "accent", 2.0)


# ---------------------------------------------------------------------------------------------
# Room 3: REACTOR CHAMBER (100 x 100 x 40 m, two levels)
# ---------------------------------------------------------------------------------------------

func _build_reactor() -> void:
	var r: Node3D = _room("Reactor Chamber")
	var cx: float = -100.0
	var cz: float = -100.0
	_shell(r, -150.0, -50.0, -150.0, -50.0, 0.0, 40.0)
	_wall(r, "z", -49.5, -150.0, -50.0, 0.0, 40.0, [[-104.0, -96.0, 6.0]])
	_wall(r, "z", -150.5, -150.0, -50.0, 0.0, 40.0)
	_wall(r, "x", -150.5, -150.0, -50.0, 0.0, 40.0)
	_wall(r, "x", -49.5, -150.0, -50.0, 0.0, 40.0)
	_door(r, Vector3(-49.5, 0, -100.0), 90.0, 8.0, 6.0)

	_prop(r, "reactor_core", Vector3(cx, 0.0, cz), 0.0, "box")
	# Animated containment rings + pulsing energy conduits.
	_torus_ring(r, 11.0, 0.35, Vector3(cx, 6.0, cz), 8, 0.5)
	_torus_ring(r, 12.6, 0.4, Vector3(cx, 16.5, cz), 10, -0.35)
	_torus_ring(r, 10.0, 0.3, Vector3(cx, 25.0, cz), 6, 0.7)
	for i in 4:
		var a: float = float(i) * PI * 0.5 + PI * 0.25
		var dir := Vector3(cos(a), 0, sin(a))
		var cm: StandardMaterial3D = _pulse_mat(_p["accent"], 3.0, 2.4, float(i) * 1.3)
		var cond := K.cylinder(r, 0.45, 34.0, Vector3(cx, 0.45, cz) + dir * 25.0, cm, false, "z")
		cond.basis = Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	# Upper catwalk ring (y = 12) with railings + corner support columns.
	var cy: float = 11.7
	_slab(r, Vector3(cx, cy, cz + 18.0), Vector3(44.0, 0.6, 8.0), "metal")
	_slab(r, Vector3(cx, cy, cz - 18.0), Vector3(44.0, 0.6, 8.0), "metal")
	_slab(r, Vector3(cx + 18.0, cy, cz), Vector3(8.0, 0.6, 28.0), "metal")
	_slab(r, Vector3(cx - 18.0, cy, cz), Vector3(8.0, 0.6, 28.0), "metal")
	_rail(r, Vector3(cx, 12.0, cz + 14.0), 28.0, false)
	_rail(r, Vector3(cx, 12.0, cz - 14.0), 28.0, false)
	_rail(r, Vector3(cx + 14.0, 12.0, cz), 28.0, true)
	_rail(r, Vector3(cx - 14.0, 12.0, cz), 28.0, true)
	_rail(r, Vector3(cx, 12.0, cz + 22.0), 44.0, false)
	_rail(r, Vector3(cx + 22.0, 12.0, cz), 44.0, true)
	_rail(r, Vector3(cx - 22.0, 12.0, cz), 44.0, true)
	_rail(r, Vector3(cx - 15.0, 12.0, cz - 22.0), 14.0, false)   # south outer rail, split around the stairs
	_rail(r, Vector3(cx + 10.0, 12.0, cz - 22.0), 24.0, false)
	for sx in [-20.0, 20.0]:
		for sz in [-20.0, 20.0]:
			var col: Node3D = K.build_column(11.4, faction)
			col.position = Vector3(cx + sx, 0.0, cz + sz)
			r.add_child(col)
	var stair: Node3D = K.build_stairs(12.0, 24.0, 6.0, faction)
	stair.position = Vector3(cx - 5.0, 0.0, cz - 46.0)
	r.add_child(stair)
	# Cooling pipes, vertical + overhead, and warning panels.
	for px in [-147.0, -53.0]:
		for pz in [-147.0, -53.0]:
			K.cylinder(r, 0.7, 38.0, Vector3(px, 19.0, pz), _mat("metal", 0.8, 0.35), true)
			K.cylinder(r, 0.75, 0.6, Vector3(px, 12.0, pz), _mat("warn", 0.0, 0.5, 1.5), false)
	for i in 5:
		_module(r, "Pipe_Straight", Vector3(-148.0 + float(i) * 4.0 + 8.0, 36.0, -147.0), 0.0)
		_module(r, "Pipe_Straight", Vector3(-148.0 + float(i) * 4.0 + 8.0, 36.0, -53.0), 0.0)
	for i in 6:
		var wz: float = -140.0 + float(i) * 18.0
		_glow(r, Vector3(0.15, 2.4, 6.0), Vector3(-149.9, 5.0, wz), "warn", 2.0)
		_glow(r, Vector3(0.15, 0.6, 5.0), Vector3(-149.8, 6.5, wz), "dark", 0.0)
	_light(r, Vector3(cx, 10.0, cz), _p["accent"], 4.0, 48.0)
	_light(r, Vector3(-125, 33, -75), Color(0.95, 0.97, 1.0), 2.0, 50.0)
	_light(r, Vector3(-75, 33, -125), Color(0.95, 0.97, 1.0), 2.0, 50.0)


# ---------------------------------------------------------------------------------------------
# Room 4: ENGINEERING WORKSHOP
# ---------------------------------------------------------------------------------------------

func _build_workshop() -> void:
	var r: Node3D = _room("Engineering Workshop")
	_shell(r, -48.0, -12.0, -146.0, -104.0, 0.0, 12.0)
	_wall(r, "z", -48.5, -146.0, -104.0, 0.0, 12.0)
	_wall(r, "z", -11.5, -146.0, -104.0, 0.0, 12.0)
	_wall(r, "x", -146.5, -48.0, -12.0, 0.0, 12.0)
	_door(r, Vector3(-30.0, 0, -104.0), 0.0, 8.0, 6.0)
	_prop(r, "fabrication_rig", Vector3(-39.0, 0.0, -116.0), 90.0)
	_prop(r, "fabrication_rig", Vector3(-39.0, 0.0, -130.0), 90.0)
	# Assembly bay.
	_outline_rect(r, Vector3(-22.0, 0.02, -126.0), 14.0, 16.0, "warn", 1.8)
	K.cylinder(r, 2.0, 2.2, Vector3(-22.0, 1.1, -126.0), _mat("metal", 0.8, 0.35), true)
	K.cylinder(r, 2.05, 0.3, Vector3(-22.0, 2.0, -126.0), _mat("accent", 0.0, 0.4, 2.0), false)
	_box(r, Vector3(5.0, 0.6, 3.0), Vector3(-22.0, 0.3, -134.0), "trim")
	# Component storage racks (south wall) + crates.
	for i in 3:
		var rx: float = -42.0 + float(i) * 12.0
		_box(r, Vector3(9.0, 0.2, 1.6), Vector3(rx, 0.9, -144.8), "metal", false)
		_box(r, Vector3(9.0, 0.2, 1.6), Vector3(rx, 2.4, -144.8), "metal", false)
		_box(r, Vector3(9.0, 3.4, 1.6), Vector3(rx, 1.7, -144.8), "trim", true)
		for j in 3:
			_box(r, Vector3(1.8, 1.0, 1.2), Vector3(rx - 3.0 + float(j) * 3.0, 3.3, -144.2), "alt" if j == 1 else "hull", false)
	# Power tool panels on the east wall.
	for i in 4:
		var pz: float = -138.0 + float(i) * 9.0
		_box(r, Vector3(0.5, 2.6, 4.0), Vector3(-12.4, 2.0, pz), "dark", false)
		_glow(r, Vector3(0.1, 1.6, 3.0), Vector3(-12.7, 2.2, pz), "accent", 2.0)
	# Overhead vent units.
	for i in 3:
		_module(r, "Vent_Unit", Vector3(-30.0 + float(i) * 10.0 - 10.0, 11.2, -125.0), 0.0)
	_light(r, Vector3(-30, 10, -125), Color(1.0, 0.96, 0.9), 2.4, 34.0)


# ---------------------------------------------------------------------------------------------
# Room 5: CARGO AND LOGISTICS BAY
# ---------------------------------------------------------------------------------------------

func _build_cargo() -> void:
	var r: Node3D = _room("Cargo Bay")
	_shell(r, 44.0, 134.0, 20.0, 120.0, 0.0, 20.0)
	_wall(r, "z", 43.5, 20.0, 120.0, 0.0, 20.0, [[66.0, 74.0, 8.0]])
	_wall(r, "z", 134.5, 20.0, 120.0, 0.0, 20.0)
	_wall(r, "x", 19.5, 44.0, 134.0, 0.0, 20.0)
	_wall(r, "x", 120.5, 44.0, 134.0, 0.0, 20.0)
	_door(r, Vector3(43.5, 0, 70.0), 90.0, 8.0, 8.0)
	for i in 4:
		_prop(r, "cargo_rack", Vector3(62.0 + float(i) * 16.0, 0.0, 115.0), 0.0)
	# Cargo lift platform (flush deck plate in a frame) + conveyor belt.
	_outline_rect(r, Vector3(110.0, 0.02, 40.0), 12.0, 12.0, "warn", 2.0)
	_glow(r, Vector3(11.0, 0.04, 11.0), Vector3(110.0, 0.03, 40.0), "warn", 0.5)
	for sx in [-6.0, 6.0]:
		for sz in [-6.0, 6.0]:
			var lc: Node3D = K.build_column(19.4, faction)
			lc.position = Vector3(110.0 + sx, 0.0, 40.0 + sz)
			r.add_child(lc)
	_box(r, Vector3(14.0, 1.0, 1.0), Vector3(110.0, 19.0, 34.0), "warn", false)
	_box(r, Vector3(14.0, 1.0, 1.0), Vector3(110.0, 19.0, 46.0), "warn", false)
	K.cylinder(r, 0.12, 12.0, Vector3(110.0, 13.0, 40.0), _mat("metal", 0.8, 0.3), false)
	var belt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 0.9, 60.0)
	belt.mesh = bm
	var cm: ShaderMaterial = _shader_mat(CONVEYOR_SHADER)
	cm.set_shader_parameter("rib_count", 30.0)
	cm.set_shader_parameter("hazard_yellow", _p["warn"])
	belt.material_override = cm
	var belt_body := StaticBody3D.new()
	belt_body.name = "ConveyorBelt"
	belt_body.collision_layer = 1
	belt_body.collision_mask = 0
	var bcs := CollisionShape3D.new()
	var bbs := BoxShape3D.new()
	bbs.size = bm.size
	bcs.shape = bbs
	belt_body.add_child(bcs)
	belt_body.add_child(belt)
	belt_body.position = Vector3(126.0, 0.45, 70.0)
	r.add_child(belt_body)
	for z in [40.0, 62.0, 84.0, 100.0]:
		_box(r, Vector3(4.2, 0.9, 0.5), Vector3(126.0, 0.45, z), "trim", false)
	# Loose crates for scale.
	for i in 5:
		_box(r, Vector3(3.0, 2.6, 3.0), Vector3(54.0 + float(i % 2) * 3.4, 1.3, 28.0 + float(i / 2) * 3.4), "alt" if i % 2 == 0 else "trim")
	_light(r, Vector3(80, 17, 50), Color(1.0, 0.95, 0.85), 2.6, 55.0)
	_light(r, Vector3(112, 17, 92), Color(1.0, 0.95, 0.85), 2.6, 55.0)


# ---------------------------------------------------------------------------------------------
# Room 6: CREW FACILITY (modular corridor hub + bunks, medical bay, lockers)
# ---------------------------------------------------------------------------------------------

func _cell(parent: Node3D, kind: String, opens: Array, pos: Vector3) -> void:
	var c: Node3D = K.build_corridor(kind, opens, faction)
	c.position = pos
	parent.add_child(c)


func _build_crew() -> void:
	var r: Node3D = _room("Crew Facility")
	# ModularCorridor network (opens order: N(+z), E(+x), S(-z), W(-x)).
	_cell(r, "Corridor_Cross", [true, true, true, true], Vector3(0, 0, -208))
	_cell(r, "Corridor_Straight", [false, true, false, true], Vector3(8, 0, -208))
	_cell(r, "Corridor_Straight", [false, true, false, true], Vector3(16, 0, -208))
	_cell(r, "Corridor_Corner", [true, false, false, true], Vector3(24, 0, -208))
	_cell(r, "Corridor_Straight", [true, false, true, false], Vector3(24, 0, -200))
	_cell(r, "Corridor_Straight", [true, false, true, false], Vector3(24, 0, -192))
	_cell(r, "Corridor_Straight", [false, true, false, true], Vector3(-8, 0, -208))
	_cell(r, "Corridor_Straight", [false, true, false, true], Vector3(-16, 0, -208))
	_cell(r, "Corridor_TJunction", [true, true, true, false], Vector3(-24, 0, -208))
	_cell(r, "Corridor_Straight", [true, false, true, false], Vector3(-24, 0, -200))
	_cell(r, "Corridor_Straight", [true, false, true, false], Vector3(-24, 0, -192))
	_cell(r, "Corridor_Straight", [true, false, true, false], Vector3(-24, 0, -216))
	_cell(r, "Corridor_Straight", [true, false, true, false], Vector3(0, 0, -216))
	_cell(r, "Corridor_Straight", [true, false, false, false], Vector3(0, 0, -224))   # dead-end alcove
	_light(r, Vector3(0, 5.0, -208), _p["accent"].lerp(Color.WHITE, 0.6), 1.2, 26.0)

	# --- Rest bunks chamber (x 8..56, z -188..-152) ---
	_shell(r, 8.0, 56.0, -188.0, -152.0, 0.0, 10.0)
	_wall(r, "x", -188.5, 8.0, 56.0, 0.0, 10.0, [[20.0, 28.0, 6.0]])
	_wall(r, "x", -151.5, 8.0, 56.0, 0.0, 10.0)
	_wall(r, "z", 7.5, -188.0, -152.0, 0.0, 10.0)
	_wall(r, "z", 56.5, -188.0, -152.0, 0.0, 10.0)
	_door(r, Vector3(24.0, 0, -188.5), 0.0, 8.0, 6.0)
	for i in 4:
		_bunk(r, Vector3(11.0, 0, -182.0 + float(i) * 8.0))
		_bunk(r, Vector3(53.0, 0, -182.0 + float(i) * 8.0))
	_glow(r, Vector3(6.0, 0.03, 0.3), Vector3(32.0, 0.02, -160.0), "accent", 1.6)
	_light(r, Vector3(32, 8.5, -168), Color(1.0, 0.85, 0.7), 1.6, 34.0)

	# --- Medical bay (x -52..-8, z -188..-152) with a glowing scanner bed ---
	_shell(r, -52.0, -8.0, -188.0, -152.0, 0.0, 10.0)
	_wall(r, "x", -188.5, -52.0, -8.0, 0.0, 10.0, [[-28.0, -20.0, 6.0]])
	_wall(r, "x", -151.5, -52.0, -8.0, 0.0, 10.0)
	_wall(r, "z", -52.5, -188.0, -152.0, 0.0, 10.0)
	_wall(r, "z", -7.5, -188.0, -152.0, 0.0, 10.0)
	_door(r, Vector3(-24.0, 0, -188.5), 0.0, 8.0, 6.0)
	_box(r, Vector3(2.2, 0.9, 5.0), Vector3(-30.0, 0.45, -168.0), "hull")
	var scan_m: StandardMaterial3D = _pulse_mat(_p["accent"], 3.0, 1.8)
	K.box(r, Vector3(1.8, 0.12, 4.4), Vector3(-30.0, 0.96, -168.0), scan_m, false)
	var arch := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.5
	tm.outer_radius = 1.75
	arch.mesh = tm
	arch.material_override = scan_m
	arch.position = Vector3(-30.0, 1.4, -168.0)
	arch.rotation_degrees = Vector3(0, 0, 90)
	r.add_child(arch)
	for i in 2:
		_box(r, Vector3(2.0, 0.8, 4.0), Vector3(-44.0, 0.4, -178.0 + float(i) * 9.0), "hull")
		_glow(r, Vector3(1.6, 0.05, 0.1), Vector3(-44.0, 0.85, -176.0 + float(i) * 9.0), "accent", 2.0)
	_box(r, Vector3(6.0, 3.0, 1.2), Vector3(-15.0, 1.5, -156.0), "trim")
	_light(r, Vector3(-30, 8.5, -168), Color(0.85, 0.95, 1.0), 2.0, 34.0)

	# --- Crew lockers (x -40..-8, z -250..-220) ---
	_shell(r, -40.0, -8.0, -250.0, -220.0, 0.0, 8.0)
	_wall(r, "x", -219.5, -40.0, -8.0, 0.0, 8.0, [[-28.0, -20.0, 6.0]])
	_wall(r, "x", -250.5, -40.0, -8.0, 0.0, 8.0)
	_wall(r, "z", -40.5, -250.0, -220.0, 0.0, 8.0)
	_wall(r, "z", -7.5, -250.0, -220.0, 0.0, 8.0)
	_door(r, Vector3(-24.0, 0, -219.5), 0.0, 8.0, 6.0)
	for i in 8:
		var lx: float = -38.0 + float(i) * 3.4
		_box(r, Vector3(3.0, 3.2, 1.0), Vector3(lx, 1.6, -249.4), "trim" if i % 2 == 0 else "alt")
		_glow(r, Vector3(0.2, 0.9, 0.06), Vector3(lx + 0.8, 2.2, -248.85), "accent", 2.0)
	_box(r, Vector3(14.0, 0.5, 1.4), Vector3(-24.0, 0.5, -238.0), "metal")
	_light(r, Vector3(-24, 6.5, -236), Color(1.0, 0.95, 0.9), 1.4, 28.0)


func _bunk(parent: Node3D, pos: Vector3) -> void:
	_box(parent, Vector3(2.2, 2.4, 4.4), pos + Vector3(0, 1.2, 0), "trim")
	for lvl in 2:
		K.box(parent, Vector3(2.0, 0.3, 4.2), pos + Vector3(0, 0.7 + float(lvl) * 1.2, 0), _mat("alt", 0.1, 0.8), false)
	_glow(parent, Vector3(0.1, 0.1, 1.4), pos + Vector3(0, 2.0, 2.2), "accent", 2.0)


# ---------------------------------------------------------------------------------------------
# Room 7: EXTERNAL DOCKING AREA (airlock + open maintenance deck, west side)
# ---------------------------------------------------------------------------------------------

func _build_docking() -> void:
	var r: Node3D = _room("External Docking Area")
	# Airlock pressure chamber (x -60..-44, z 130..150).
	_shell(r, -60.0, -44.0, 130.0, 150.0, 0.0, 8.0)
	_wall(r, "x", 129.5, -60.0, -44.0, 0.0, 8.0)
	_wall(r, "x", 150.5, -60.0, -44.0, 0.0, 8.0)
	_wall(r, "z", -43.5, 130.0, 150.0, 0.0, 8.0, [[136.0, 144.0, 6.0]])
	_wall(r, "z", -60.5, 130.0, 150.0, 0.0, 8.0, [[136.0, 144.0, 6.0]])
	_door(r, Vector3(-43.5, 0, 140.0), 90.0, 8.0, 6.0)
	_door(r, Vector3(-60.5, 0, 140.0), 90.0, 8.0, 6.0)
	for z in [133.0, 147.0]:
		_glow(r, Vector3(0.2, 2.5, 0.2), Vector3(-52.0, 3.0, z), "warn", 3.0)
	_glow(r, Vector3(12.0, 0.03, 0.8), Vector3(-52.0, 0.02, 140.0), "warn", 2.4)
	_light(r, Vector3(-52, 6.8, 140), _p["warn"].lerp(Color.WHITE, 0.4), 1.4, 18.0)

	# Open space-facing maintenance deck (x -150..-60, z 120..160), no ceiling.
	var cx: float = -105.0
	_slab(r, Vector3(cx, -0.5, 140.0), Vector3(90.0, 1.0, 40.0), "floor")
	_glow(r, Vector3(90.0, 0.03, 0.3), Vector3(cx, 0.02, 156.0), "warn", 2.0)
	_glow(r, Vector3(90.0, 0.03, 0.3), Vector3(cx, 0.02, 124.0), "warn", 2.0)
	_outline_rect(r, Vector3(-110.0, 0.02, 140.0), 30.0, 24.0, "accent", 2.0)
	# Guardrails along the open edges (collision 4 m tall so nobody can hop over).
	_rail(r, Vector3(cx, 0.0, 160.0), 90.0, false, 4.0)
	_rail(r, Vector3(cx, 0.0, 120.0), 90.0, false, 4.0)
	_rail(r, Vector3(-150.0, 0.0, 140.0), 40.0, true, 4.0)
	# External docking bridge gantry: trusses + overhead span.
	for gx in [-85.0, -135.0]:
		for gz in [123.0, 157.0]:
			var gc: Node3D = K.build_column(14.0, faction)
			gc.position = Vector3(gx, 0.0, gz)
			r.add_child(gc)
		_box(r, Vector3(1.2, 1.4, 36.0), Vector3(gx, 14.4, 140.0), "trim", false)
	_box(r, Vector3(52.0, 1.0, 1.0), Vector3(-110.0, 15.0, 123.0), "metal", false)
	_box(r, Vector3(52.0, 1.0, 1.0), Vector3(-110.0, 15.0, 157.0), "metal", false)
	# Vessel clamp arms (gently articulated).
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ClampArm"
		arm.position = Vector3(-110.0, 0.0, 140.0 + side * 15.5)
		_box(arm, Vector3(2.0, 3.0, 2.0), Vector3(0, 1.5, 0), "metal")
		_box(arm, Vector3(1.0, 1.0, 9.0), Vector3(0, 3.0, -side * 4.5), "trim", false)
		_glow(arm, Vector3(0.6, 0.6, 1.2), Vector3(0, 3.0, -side * 9.4), "warn", 2.6)
		r.add_child(arm)
		_swayers.append({"node": arm, "base": 0.0, "amp": 0.05, "speed": 0.6, "phase": side})
	_light(r, Vector3(-90, 9, 140), Color(0.9, 0.95, 1.0), 2.2, 50.0)
	_light(r, Vector3(-130, 9, 140), _p["accent"].lerp(Color.WHITE, 0.5), 2.2, 50.0)


# ---------------------------------------------------------------------------------------------
# Hangar doors
# ---------------------------------------------------------------------------------------------

func _apply_door_pose() -> void:
	var e: float = smoothstep(0.0, 1.0, _door_t)
	var half: float = HANGAR_HALF_W
	if _leaves.size() >= 2:
		if is_instance_valid(_leaves[0]):
			_leaves[0].position.x = -(half * 0.5 + half * e)
		if is_instance_valid(_leaves[1]):
			_leaves[1].position.x = half * 0.5 + half * e
	if _forcefield != null:
		_forcefield.visible = _door_t > 0.02


func _apply_door_collision() -> void:
	for leaf in _leaves:
		if not is_instance_valid(leaf):
			continue
		for ch in leaf.get_children():
			if ch is CollisionShape3D:
				(ch as CollisionShape3D).disabled = _door_open
