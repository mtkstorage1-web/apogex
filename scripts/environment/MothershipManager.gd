class_name MothershipManager
extends Node3D
## Places the HELION and CINDER motherships in opposing low orbits above Vesper-9, keeps them re-based on
## floating-origin shifts, ticks their animations and answers "which ship interior is this point in?"
## (used by the Explorer for artificial ship gravity).

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const SCENE_DIR := "res://scenes/mothership/"

## Both ships sit 2,200 m above the reference radius; their bow (+Z: hangar mouth + bridge windows) points at the planet.
const SHIPS: Dictionary = {
	"helion": {"scene": "HelionMothership.tscn", "lat": 8.0, "lon": -6.0, "alt": 2200.0, "label": "Helion Mothership"},
	"cinder": {"scene": "CinderMothership.tscn", "lat": -8.0, "lon": 6.0, "alt": 2200.0, "label": "Cinder Mothership"},
}

var world_cfg: WorldConfig
var ships: Dictionary = {}
var current_origin: Vector3 = Vector3.ZERO
var hangar_doors_open: bool = true
var tick_count: int = 0


func setup(p_world_cfg: WorldConfig) -> void:
	world_cfg = p_world_cfg
	rebuild()


## Planet-space placement: ship centre + basis (Z = toward the planet centre, Y = tangent "up").
static func ship_placement(key: String, planet_radius: float) -> Dictionary:
	var d: Dictionary = SHIPS[key]
	var u: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(float(d["lat"])), deg_to_rad(float(d["lon"])))
	var origin: Vector3 = u * (planet_radius + float(d["alt"]))
	var fwd: Vector3 = -u
	var up: Vector3 = Vector3.UP - fwd * Vector3.UP.dot(fwd)
	if up.length_squared() < 1.0e-6:
		up = Vector3.RIGHT - fwd * Vector3.RIGHT.dot(fwd)
	up = up.normalized()
	var right: Vector3 = up.cross(fwd).normalized()
	return {"origin": origin, "basis": Basis(right, up, fwd), "unit_dir": u}


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	ships.clear()
	if world_cfg == null:
		return
	for key in SHIPS:
		var ps: PackedScene = load(SCENE_DIR + (SHIPS[key]["scene"] as String)) as PackedScene
		var node: Node3D = ps.instantiate() as Node3D
		add_child(node)   # _ready() builds hull + interior
		ships[key] = node
		node.call("place", ship_origin(key), ship_basis(key), current_origin)
		(node.get("interior") as Node).call("set_hangar_doors_open", hangar_doors_open)


## Re-applies placement (e.g. after world regeneration) without rebuilding the ship geometry.
func refresh_placement() -> void:
	for key in ships:
		var n: Node3D = ships[key]
		if is_instance_valid(n):
			n.call("place", ship_origin(key), ship_basis(key), current_origin)


func ship_origin(key: String) -> Vector3:
	return ship_placement(key, world_cfg.planet_radius)["origin"]


func ship_basis(key: String) -> Basis:
	return ship_placement(key, world_cfg.planet_radius)["basis"]


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	for key in ships:
		var n: Node3D = ships[key]
		if is_instance_valid(n):
			n.call("apply_origin", new_origin)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	tick_count += 1
	for key in ships:
		var n: Node3D = ships[key]
		if is_instance_valid(n):
			n.call("tick", delta)


func get_ship(key: String) -> Node3D:
	return ships.get(key, null)


func get_ship_keys() -> Array:
	return SHIPS.keys()


## Ship whose interior volume contains the planet-space point (null when outside every ship).
func find_ship_containing(planet_pos: Vector3) -> Node3D:
	for key in ships:
		var n: Node3D = ships[key]
		if is_instance_valid(n) and n.call("contains_planet_point_in_interior", planet_pos):
			return n
	return null


## Planet-space point of a named room spawn (floor + 1 m).
func get_room_planet_point(key: String, room: String) -> Vector3:
	var n: Node3D = get_ship(key)
	if n == null:
		return Vector3.ZERO
	var spawns: Dictionary = (n.get("interior") as Node).call("get_room_spawn_points")
	return n.call("local_to_planet", spawns[room])


func set_hangar_doors_open(open: bool) -> void:
	hangar_doors_open = open
	for key in ships:
		var n: Node3D = ships[key]
		if is_instance_valid(n):
			(n.get("interior") as Node).call("set_hangar_doors_open", open)


func toggle_hangar_doors() -> void:
	set_hangar_doors_open(not hangar_doors_open)


func is_hangar_doors_open() -> bool:
	return hangar_doors_open


func get_diagnostics() -> Dictionary:
	var d: Dictionary = {"doors_open": hangar_doors_open, "ships": {}}
	for key in ships:
		var n: Node3D = ships[key]
		if is_instance_valid(n):
			d["ships"][key] = n.call("get_diagnostics")
	return d
