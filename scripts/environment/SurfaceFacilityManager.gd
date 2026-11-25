class_name SurfaceFacilityManager
extends Node3D
## Instantiates the five APOGEX surface facilities + the InfrastructureNetwork, anchors each pad to the
## spherical terrain (tangent basis, foundation 0.4 m below pad-centre terrain, deep skirts), drives the
## machinery animations and re-bases everything on floating-origin shifts.

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const InfraScript = preload("res://scripts/environment/InfrastructureNetwork.gd")

const SCENE_DIR := "res://scenes/surface/"
const PAD_EMBED := 0.4
## Pad-centre terrain is flat to ~0.26 m; the slab top sits PAD_LIFT above the embedded base (0.1 m proud of
## the centre terrain) so interior floors are never buried, while the 8 m+ skirt keeps it fully anchored.
const PAD_LIFT := 0.5

const FACILITIES: Array = [
	{"key": "extraction", "scene": "ExtractionComplex.tscn", "lat": 0.0, "lon": 0.0, "label": "Extraction Complex"},
	{"key": "mining", "scene": "MiningFacility.tscn", "lat": 18.0, "lon": 0.0, "label": "Mining Facility"},
	{"key": "refinery", "scene": "Refinery.tscn", "lat": 0.0, "lon": 20.0, "label": "Refinery"},
	{"key": "launch", "scene": "LaunchSite.tscn", "lat": -18.0, "lon": 0.0, "label": "Launch Site"},
	{"key": "settlement", "scene": "AbandonedSettlement.tscn", "lat": 0.0, "lon": -20.0, "label": "Abandoned Settlement"},
]

var noise: TerrainNoiseStack
var world_cfg: WorldConfig
var current_origin: Vector3 = Vector3.ZERO
var infrastructure: Node3D
## key -> {node, base, basis, unit_dir, surface}
var facilities: Dictionary = {}
var tick_count: int = 0


func setup(p_noise: TerrainNoiseStack, p_world_cfg: WorldConfig) -> void:
	noise = p_noise
	world_cfg = p_world_cfg
	rebuild()


## Pad placement shared with LandmarkManager: base is PAD_EMBED below the sampled pad-centre terrain,
## origin (slab top) is PAD_LIFT above base.
static func pad_transform(p_noise: TerrainNoiseStack, lat_deg: float, lon_deg: float) -> Dictionary:
	var u: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(lat_deg), deg_to_rad(lon_deg))
	var surface: Vector3 = p_noise.sample_surface_position(u)
	var base: Vector3 = surface - u * PAD_EMBED
	return {"unit_dir": u, "surface": surface, "base": base, "origin": base + u * PAD_LIFT, "basis": Transforms.surface_tangent_basis(u)}


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	facilities.clear()
	infrastructure = null
	if noise == null:
		return
	for def in FACILITIES:
		var d: Dictionary = def
		var pt: Dictionary = pad_transform(noise, float(d["lat"]), float(d["lon"]))
		var ps: PackedScene = load(SCENE_DIR + (d["scene"] as String)) as PackedScene
		var node: Node3D = ps.instantiate() as Node3D
		node.name = d["scene"].get_basename()
		var base: Vector3 = pt["origin"]
		var tb: Basis = pt["basis"]
		node.set("ground_h", func(local: Vector3) -> float: return _ground_local(base, tb, local))
		node.transform = Transform3D(tb, base - current_origin)
		add_child(node)  # _ready() builds the facility with the terrain sampler in place
		facilities[d["key"]] = {"node": node, "base": pt["base"], "origin": base, "basis": tb, "unit_dir": pt["unit_dir"], "surface": pt["surface"]}
	infrastructure = InfraScript.new()
	infrastructure.name = "InfrastructureNetwork"
	add_child(infrastructure)
	infrastructure.current_origin = current_origin
	infrastructure.setup(noise, world_cfg.planet_radius)


func _ground_local(base: Vector3, tb: Basis, local: Vector3) -> float:
	var p: Vector3 = base + tb * Vector3(local.x, 0.0, local.z)
	var s: Vector3 = noise.sample_surface_position(p.normalized())
	return (tb.inverse() * (s - base)).y


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	for k in facilities:
		var f: Dictionary = facilities[k]
		var n: Node3D = f["node"]
		if is_instance_valid(n):
			n.position = (f["origin"] as Vector3) - current_origin
	if infrastructure != null:
		infrastructure.apply_origin(new_origin)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	tick_count += 1
	for k in facilities:
		var n: Node3D = (facilities[k] as Dictionary)["node"]
		if is_instance_valid(n) and n.has_method("tick"):
			n.call("tick", delta)


func get_facility(key: String) -> Node3D:
	if not facilities.has(key):
		return null
	return (facilities[key] as Dictionary)["node"]


func get_facility_info(key: String) -> Dictionary:
	return facilities.get(key, {})


func get_facility_keys() -> Array:
	return facilities.keys()


func get_diagnostics() -> Dictionary:
	var d: Dictionary = {"facility_count": facilities.size(), "ticks": tick_count}
	if infrastructure != null:
		d["infrastructure"] = infrastructure.call("get_summary")
	return d
