class_name RegionStreamingController
extends Node
## Strategic world regions with an explicit chunk state machine and enter/exit hysteresis.
##   UNLOADED -> REQUESTED -> LOADING -> READY -> ACTIVE -> RETIRING -> UNLOADED
## Regions are tracked in planet space. Enter uses a velocity-biased lookahead point, exit uses the real focus,
## and at most `max_activations_per_frame` regions may become ACTIVE per update.

enum ChunkState { UNLOADED, REQUESTED, LOADING, READY, ACTIVE, RETIRING }

signal region_state_changed(id: StringName, old_state: int, new_state: int)
signal region_activated(id: StringName)
signal region_retired(id: StringName)

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const LOOKAHEAD_SECONDS := 3.0
const MIN_LOAD_UPDATES := 2

## id -> {name, lat, lon, alt, enter, exit, mb}. enter < exit * 0.8 for every region.
const REGION_DEFS: Array = [
	{"id": &"central_terminus", "name": "Central Terminus", "lat": 0.0, "lon": 0.0, "alt": 0.0, "enter": 2400.0, "exit": 3200.0, "mb": 120.0},
	{"id": &"north_highlands", "name": "North Highlands", "lat": 18.0, "lon": 0.0, "alt": 0.0, "enter": 2400.0, "exit": 3200.0, "mb": 90.0},
	{"id": &"east_iron_desert", "name": "East Iron Desert", "lat": 0.0, "lon": 20.0, "alt": 0.0, "enter": 2400.0, "exit": 3200.0, "mb": 90.0},
	{"id": &"west_obsidian", "name": "West Obsidian", "lat": 0.0, "lon": -20.0, "alt": 0.0, "enter": 2400.0, "exit": 3200.0, "mb": 90.0},
	{"id": &"south_ashen", "name": "South Ashen", "lat": -18.0, "lon": 0.0, "alt": 0.0, "enter": 2400.0, "exit": 3200.0, "mb": 90.0},
	{"id": &"helion_orbit", "name": "Helion Orbit", "lat": 8.0, "lon": -6.0, "alt": 2200.0, "enter": 1400.0, "exit": 1900.0, "mb": 160.0},
	{"id": &"cinder_orbit", "name": "Cinder Orbit", "lat": -8.0, "lon": 6.0, "alt": 2200.0, "enter": 1400.0, "exit": 1900.0, "mb": 160.0},
	{"id": &"orbital_debris_belt", "name": "Orbital Debris Belt", "lat": -3.0, "lon": 12.0, "alt": 2500.0, "enter": 1600.0, "exit": 2150.0, "mb": 60.0},
]

var max_activations_per_frame: int = 2
var transitions_count: int = 0
var planet_radius: float = 12000.0
var _regions: Dictionary = {}     # id -> region dict (state, center, enter, exit, mb, load_ticks, chunk_path)
var _order: Array[StringName] = []
var _activations_this_frame: int = 0
var _budget_check: Callable = Callable()


func setup(p_planet_radius: float) -> void:
	planet_radius = p_planet_radius
	_regions.clear()
	_order.clear()
	for def in REGION_DEFS:
		var u: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(float(def["lat"])), deg_to_rad(float(def["lon"])))
		_regions[def["id"]] = {
			"id": def["id"], "name": def["name"], "state": ChunkState.UNLOADED,
			"center": u * (planet_radius + float(def["alt"])),
			"enter": float(def["enter"]), "exit": float(def["exit"]), "mb": float(def["mb"]),
			"load_ticks": 0, "chunk_path": "",
		}
		_order.append(def["id"])


## Optional hook: Callable(mb: float) -> bool telling whether the residency budget can take this region.
func set_budget_check(c: Callable) -> void:
	_budget_check = c


func get_region_ids() -> Array[StringName]:
	return _order


func get_region(id: StringName) -> Dictionary:
	return _regions.get(id, {})


func get_state(id: StringName) -> int:
	return _regions[id]["state"] if _regions.has(id) else ChunkState.UNLOADED


func bind_chunk_path(id: StringName, path: String) -> void:
	if _regions.has(id):
		_regions[id]["chunk_path"] = path


func get_count(state: int) -> int:
	var n: int = 0
	for id in _order:
		if _regions[id]["state"] == state:
			n += 1
	return n


func _set_state(id: StringName, ns: int) -> void:
	var r: Dictionary = _regions[id]
	var old: int = r["state"]
	if old == ns:
		return
	r["state"] = ns
	transitions_count += 1
	region_state_changed.emit(id, old, ns)
	if ns == ChunkState.ACTIVE:
		region_activated.emit(id)
	elif ns == ChunkState.RETIRING:
		region_retired.emit(id)


## `loader_ready(path) -> bool` lets the manager report threaded-load completion for bound chunk paths.
func update(focus: Vector3, velocity: Vector3, camera_forward: Vector3, loader_ready: Callable = Callable()) -> void:
	_activations_this_frame = 0
	var bias: Vector3 = velocity * LOOKAHEAD_SECONDS
	if velocity.length() < 1.0:
		bias = camera_forward.normalized() * 150.0
	var ahead: Vector3 = focus + bias
	for id in _order:
		var r: Dictionary = _regions[id]
		var d_focus: float = focus.distance_to(r["center"])
		var d_enter: float = minf(d_focus, ahead.distance_to(r["center"]))
		match int(r["state"]):
			ChunkState.UNLOADED:
				if d_enter < r["enter"]:
					r["load_ticks"] = 0
					_set_state(id, ChunkState.REQUESTED)
			ChunkState.REQUESTED:
				if d_focus > r["exit"]:
					_set_state(id, ChunkState.UNLOADED)
				else:
					_set_state(id, ChunkState.LOADING)
			ChunkState.LOADING:
				if d_focus > r["exit"]:
					_set_state(id, ChunkState.UNLOADED)
				else:
					r["load_ticks"] += 1
					var done: bool = r["load_ticks"] >= MIN_LOAD_UPDATES
					if r["chunk_path"] != "" and loader_ready.is_valid():
						done = done and bool(loader_ready.call(r["chunk_path"]))
					if done:
						_set_state(id, ChunkState.READY)
			ChunkState.READY:
				if d_focus > r["exit"]:
					_set_state(id, ChunkState.RETIRING)
				elif _activations_this_frame < max_activations_per_frame and (not _budget_check.is_valid() or bool(_budget_check.call(r["mb"]))):
					_activations_this_frame += 1
					_set_state(id, ChunkState.ACTIVE)
			ChunkState.ACTIVE:
				if d_focus > r["exit"]:
					_set_state(id, ChunkState.RETIRING)
			ChunkState.RETIRING:
				_set_state(id, ChunkState.UNLOADED)


func get_activations_this_frame() -> int:
	return _activations_this_frame


## Region whose centre is nearest to `pos` (for diagnostics).
func get_nearest_region(pos: Vector3) -> StringName:
	var best: StringName = &""
	var bd: float = INF
	for id in _order:
		var d: float = pos.distance_to(_regions[id]["center"])
		if d < bd:
			bd = d
			best = id
	return best
