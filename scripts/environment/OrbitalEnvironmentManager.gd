class_name OrbitalEnvironmentManager
extends Node3D
## Part 10.4 orbital structures (Abandoned Research Station, Broken Orbital Refinery, Satellite Network,
## Navigation Beacon Array, Orbital Docking & Relay Hub) + the Part 10.3 debris field, all in low / mid orbit
## (1,800 - 3,200 m above the reference radius). Each structure loads its Blender GLB when imported and
## otherwise builds a multi-part procedural fallback with the exact GLB bounding dimensions.

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const SCENE_DIR := "res://scenes/orbital/"
const MODEL_DIR := "res://assets/models/apogex/orbital/"

## Model id -> {glb, size}. Sizes are the exported GLB bounds (centred, zero-G).
const MODELS: Dictionary = {
	"broken_satellite": {"glb": "broken_satellite.glb", "size": Vector3(14, 6, 8)},
	"solar_array_fragment": {"glb": "solar_array_fragment.glb", "size": Vector3(12, 1.2, 5)},
	"rocket_stage_hulk": {"glb": "rocket_stage_hulk.glb", "size": Vector3(6, 6, 22)},
	"hull_wreckage_slab": {"glb": "hull_wreckage_slab.glb", "size": Vector3(16, 4, 10)},
	"abandoned_research_station": {"glb": "abandoned_research_station.glb", "size": Vector3(85, 60, 85)},
	"broken_orbital_refinery": {"glb": "broken_orbital_refinery.glb", "size": Vector3(95, 55, 70)},
	"nav_beacon_array": {"glb": "nav_beacon_array.glb", "size": Vector3(12, 24, 12)},
	"orbital_docking_hub": {"glb": "orbital_docking_hub.glb", "size": Vector3(48, 28, 48)},
}

## Fixed (non-satellite) placements. rate = rad/s of the gentle deterministic spin.
const SITES: Dictionary = {
	"debris": {"lat": -3.0, "lon": 12.0, "alt": 2500.0, "label": "Orbital Debris Field", "radius": 420.0, "rate": 0.0},
	"station": {"lat": 14.0, "lon": 10.0, "alt": 2600.0, "label": "Abandoned Research Station", "model": "abandoned_research_station", "scene": "ResearchStation.tscn", "rate": 0.006},
	"refinery": {"lat": -14.0, "lon": -10.0, "alt": 2900.0, "label": "Broken Orbital Refinery", "model": "broken_orbital_refinery", "scene": "", "rate": -0.004},
	"beacon": {"lat": 4.0, "lon": -16.0, "alt": 1900.0, "label": "Navigation Beacon Array", "model": "nav_beacon_array", "scene": "", "rate": 0.02},
	"hub": {"lat": -4.0, "lon": 16.0, "alt": 3200.0, "label": "Orbital Docking Hub", "model": "orbital_docking_hub", "scene": "", "rate": 0.008},
}
const SATELLITE_COUNT := 6
const SAT_VISIBLE := {"LOW": 3, "MEDIUM": 4, "HIGH": 6, "ULTRA": 6}

# Procedural parts: [kind, size, pos, rot_deg, color, emissive(0 none, 1 steady, 2 strobe)]
const HULL := Color(0.38, 0.39, 0.42)
const DARK := Color(0.16, 0.17, 0.2)
const RUST := Color(0.42, 0.26, 0.18)
const PANEL := Color(0.08, 0.12, 0.24)
const GLOW := Color(1.0, 0.45, 0.15)
const PARTS: Dictionary = {
	"broken_satellite": [
		["box", Vector3(4, 3.6, 6), Vector3.ZERO, Vector3.ZERO, HULL, 0],
		["box", Vector3(4.5, 0.15, 4), Vector3(4.75, 0.2, 0), Vector3(0, 0, 8), PANEL, 0],
		["box", Vector3(4.5, 0.15, 4), Vector3(-4.75, -0.4, 0), Vector3(0, 0, -22), PANEL, 0],
		["box", Vector3(1, 0.1, 0.1), Vector3(2.5, 0, 0), Vector3.ZERO, DARK, 0],
		["box", Vector3(1, 0.1, 0.1), Vector3(-2.5, 0, 0), Vector3.ZERO, DARK, 0],
		["cyl", Vector3(1.5, 0.3, 0), Vector3(0, 2.2, 0), Vector3(20, 0, 0), RUST, 0],
		["box", Vector3(0.2, 2.4, 0.2), Vector3(0, 1.8, 0), Vector3.ZERO, DARK, 0],
	],
	"solar_array_fragment": [
		["box", Vector3(4, 0.12, 5), Vector3(-4, 0, 0), Vector3(0, 0, 3), PANEL, 0],
		["box", Vector3(3.5, 0.12, 4.4), Vector3(0.2, 0, 0.3), Vector3(0, 8, -2), PANEL, 0],
		["box", Vector3(3.2, 0.12, 5), Vector3(4.4, 0, -0.2), Vector3(0, -5, 6), PANEL, 0],
		["box", Vector3(12, 0.25, 0.2), Vector3(0, 0.5, 2.3), Vector3.ZERO, DARK, 0],
		["box", Vector3(12, 1.2, 0.15), Vector3(0, 0, -2.4), Vector3.ZERO, DARK, 0],
	],
	"rocket_stage_hulk": [
		["cyl", Vector3(3, 15, 0), Vector3(0, 0, 3), Vector3(90, 0, 0), HULL, 0],
		["cyl", Vector3(3.05, 1.0, 0), Vector3(0, 0, -4), Vector3(90, 0, 0), RUST, 0],
		["cyl", Vector3(2.0, 4.0, 0), Vector3(0, 0, -9), Vector3(90, 0, 0), DARK, 0],
		["cyl", Vector3(1.0, 3.0, 0), Vector3(0, 0, 9.5), Vector3(90, 0, 0), DARK, 0],
		["box", Vector3(5.5, 0.4, 0.4), Vector3(0, 0, 6), Vector3.ZERO, DARK, 0],
	],
	"hull_wreckage_slab": [
		["box", Vector3(16, 0.8, 10), Vector3(0, -1.0, 0), Vector3.ZERO, HULL, 0],
		["box", Vector3(14, 0.6, 0.6), Vector3(0, 0.3, -3), Vector3.ZERO, DARK, 0],
		["box", Vector3(14, 0.6, 0.6), Vector3(0, 0.3, 3), Vector3.ZERO, DARK, 0],
		["box", Vector3(0.6, 3.0, 8), Vector3(-6, 0.5, 0), Vector3(0, 0, 8), RUST, 0],
		["box", Vector3(5, 3.2, 0.3), Vector3(3, 1.2, 4.6), Vector3(14, 0, 6), HULL, 0],
	],
	"abandoned_research_station": [
		["cyl", Vector3(7, 44, 0), Vector3.ZERO, Vector3.ZERO, HULL, 0],
		["cyl", Vector3(30, 3, 0), Vector3(0, 6, 0), Vector3.ZERO, DARK, 0],
		["cyl", Vector3(30, 3, 0), Vector3(0, -6, 0), Vector3.ZERO, DARK, 0],
		["box", Vector3(70, 3, 3), Vector3.ZERO, Vector3.ZERO, DARK, 0],
		["box", Vector3(3, 3, 70), Vector3.ZERO, Vector3.ZERO, DARK, 0],
		["cyl", Vector3(8, 14, 0), Vector3(35, 0, 0), Vector3(0, 0, 90), HULL, 0],
		["cyl", Vector3(8, 14, 0), Vector3(-35, 0, 0), Vector3(0, 0, 90), RUST, 0],
		["cyl", Vector3(8, 14, 0), Vector3(0, 0, 35), Vector3(90, 0, 0), HULL, 0],
		["cyl", Vector3(8, 14, 0), Vector3(0, 0, -35), Vector3(90, 0, 0), HULL, 0],
		["box", Vector3(0.3, 50, 18), Vector3(40, 4, 28), Vector3(0, 0, 0), PANEL, 0],
		["box", Vector3(0.3, 50, 18), Vector3(-40, -4, -28), Vector3.ZERO, PANEL, 0],
		["sph", Vector3(5, 0, 0), Vector3(0, 28, 0), Vector3.ZERO, RUST, 0],
		["cyl", Vector3(0.3, 8, 0), Vector3(0, -26, 0), Vector3.ZERO, DARK, 0],
		["sph", Vector3(0.6, 0, 0), Vector3(0, 30, 0), Vector3.ZERO, GLOW, 1],
	],
	"broken_orbital_refinery": [
		["cyl", Vector3(12, 30, 0), Vector3(-25, 0, 10), Vector3.ZERO, HULL, 0],
		["cyl", Vector3(10, 24, 0), Vector3(-5, -8, 14), Vector3.ZERO, RUST, 0],
		["sph", Vector3(14, 0, 0), Vector3(20, 4, -8), Vector3.ZERO, HULL, 0],
		["box", Vector3(90, 3, 3), Vector3(0, 12, 0), Vector3.ZERO, DARK, 0],
		["box", Vector3(3, 50, 3), Vector3(35, 0, 10), Vector3(0, 0, 14), DARK, 0],
		["box", Vector3(3, 36, 3), Vector3(40, 8, -16), Vector3(12, 0, -30), RUST, 0],
		["cyl", Vector3(1.5, 70, 0), Vector3(0, -14, -20), Vector3(0, 0, 90), DARK, 0],
		["box", Vector3(30, 4, 20), Vector3(-10, -22, -10), Vector3.ZERO, HULL, 0],
		["sph", Vector3(1.0, 0, 0), Vector3(-25, 16, 10), Vector3.ZERO, GLOW, 1],
	],
	"nav_beacon_array": [
		["cyl", Vector3(0.6, 24, 0), Vector3.ZERO, Vector3.ZERO, DARK, 0],
		["box", Vector3(12, 0.4, 0.4), Vector3(0, 6, 0), Vector3.ZERO, HULL, 0],
		["box", Vector3(0.4, 0.4, 12), Vector3(0, -2, 0), Vector3.ZERO, HULL, 0],
		["sph", Vector3(0.8, 0, 0), Vector3(6, 6, 0), Vector3.ZERO, Color(1, 0.2, 0.1), 2],
		["sph", Vector3(0.8, 0, 0), Vector3(-6, 6, 0), Vector3.ZERO, Color(0.2, 1, 0.4), 2],
		["sph", Vector3(0.8, 0, 0), Vector3(0, -2, 6), Vector3.ZERO, Color(0.4, 0.7, 1), 2],
		["sph", Vector3(0.8, 0, 0), Vector3(0, 12, 0), Vector3.ZERO, Color(1, 1, 1), 2],
		["cyl", Vector3(2.0, 0.5, 0), Vector3(0, 11, 0), Vector3.ZERO, HULL, 0],
	],
	"orbital_docking_hub": [
		["cyl", Vector3(9, 20, 0), Vector3.ZERO, Vector3.ZERO, HULL, 0],
		["cyl", Vector3(20, 2, 0), Vector3(0, 0, 0), Vector3.ZERO, DARK, 0],
		["cyl", Vector3(4, 14, 0), Vector3(17, 0, 0), Vector3(0, 0, 90), HULL, 0],
		["cyl", Vector3(4, 14, 0), Vector3(-17, 0, 0), Vector3(0, 0, 90), HULL, 0],
		["cyl", Vector3(4, 14, 0), Vector3(0, 0, 17), Vector3(90, 0, 0), HULL, 0],
		["cyl", Vector3(4, 14, 0), Vector3(0, 0, -17), Vector3(90, 0, 0), HULL, 0],
		["cyl", Vector3(5.2, 1.5, 0), Vector3(23, 0, 0), Vector3(0, 0, 90), RUST, 0],
		["cyl", Vector3(5.2, 1.5, 0), Vector3(-23, 0, 0), Vector3(0, 0, 90), RUST, 0],
		["cyl", Vector3(5.2, 1.5, 0), Vector3(0, 0, 23), Vector3(90, 0, 0), RUST, 0],
		["cyl", Vector3(5.2, 1.5, 0), Vector3(0, 0, -23), Vector3(90, 0, 0), RUST, 0],
		["box", Vector3(0.4, 12, 0.4), Vector3(0, 18, 0), Vector3.ZERO, DARK, 0],
		["sph", Vector3(0.7, 0, 0), Vector3(0, 24, 0), Vector3.ZERO, Color(0.3, 0.9, 1), 2],
		["sph", Vector3(0.5, 0, 0), Vector3(24, 0, 0), Vector3.ZERO, GLOW, 1],
		["sph", Vector3(0.5, 0, 0), Vector3(-24, 0, 0), Vector3.ZERO, GLOW, 1],
	],
}

var world_cfg: WorldConfig
var structures: Dictionary = {}          # key -> {node, base_pos, unit_dir, rate, angle0, kind}
var debris_field: Node3D
var current_origin: Vector3 = Vector3.ZERO
var quality_preset: String = "HIGH"
var tick_count: int = 0
var orbital_time: float = 0.0
var strobe_state: bool = false
var glb_loaded: Array[String] = []
var procedural_used: Array[String] = []
var _strobe_mats: Array[StandardMaterial3D] = []


func setup(p_world_cfg: WorldConfig) -> void:
	world_cfg = p_world_cfg
	quality_preset = world_cfg.quality_preset.to_upper()
	rebuild()


# ---------------------------------------------------------------------------------------------
# Static placement / model helpers
# ---------------------------------------------------------------------------------------------

## Planet-space placement for a fixed site key. {origin, unit_dir, size, standoff, altitude, label}.
static func placement(key: String, planet_radius: float) -> Dictionary:
	var s: Dictionary = SITES[key]
	var u: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(float(s["lat"])), deg_to_rad(float(s["lon"])))
	var size: Vector3
	if key == "debris":
		size = Vector3.ONE * float(s["radius"]) * 2.0
	else:
		size = MODELS[s["model"]]["size"]
	return {"origin": u * (planet_radius + float(s["alt"])), "unit_dir": u, "size": size,
		"standoff": maxf(size.x, maxf(size.y, size.z)) * 1.9 + 40.0, "altitude": float(s["alt"]), "label": s["label"]}


## Deterministic satellite placement (low-mid orbit ring around the planet).
static func satellite_placement(index: int, world_seed: int, planet_radius: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "satellite", index]) & 0x7fffffff
	var lat: float = rng.randf_range(-35.0, 35.0)
	var lon: float = -150.0 + float(index) * 60.0 + rng.randf_range(-12.0, 12.0)
	var alt: float = rng.randf_range(1800.0, 3000.0)
	var u: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(lat), deg_to_rad(lon))
	return {"origin": u * (planet_radius + alt), "unit_dir": u, "altitude": alt, "angle0": rng.randf() * TAU,
		"rate": rng.randf_range(0.015, 0.05)}


## Builds the visual for a model id: Blender GLB when imported, multi-part procedural fallback otherwise.
## Returns a Node3D whose metadata "glb" says which. Optional single bounding-box collision body.
static func build_visual(model: String, with_collision: bool = false, strobe_out: Array = []) -> Node3D:
	var info: Dictionary = MODELS[model]
	var size: Vector3 = info["size"]
	var root := Node3D.new()
	root.name = model
	var path: String = MODEL_DIR + String(info["glb"])
	var visual: Node3D = null
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path) as PackedScene
		if ps != null:
			var inst: Node = ps.instantiate()
			if inst is Node3D:
				visual = inst as Node3D
				visual.name = "GLB"
			else:
				inst.free()
	root.set_meta("glb", visual != null)
	if visual == null:
		visual = Node3D.new()
		visual.name = "Procedural"
		for part in PARTS[model]:
			_add_part(visual, part, strobe_out)
	root.add_child(visual)
	root.set_meta("size", size)
	if with_collision:
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		body.add_child(cs)
		root.add_child(body)
	return root


static func _add_part(parent: Node3D, part: Array, strobe_out: Array) -> void:
	var kind: String = part[0]
	var sz: Vector3 = part[1]
	var mi := MeshInstance3D.new()
	match kind:
		"box":
			var m := BoxMesh.new()
			m.size = sz
			mi.mesh = m
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = sz.x
			c.bottom_radius = sz.x
			c.height = sz.y
			c.radial_segments = 16
			c.rings = 1
			mi.mesh = c
		_:
			var s := SphereMesh.new()
			s.radius = sz.x
			s.height = sz.x * 2.0
			s.radial_segments = 12
			s.rings = 6
			mi.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = part[4]
	mat.roughness = 0.75
	mat.metallic = 0.5
	if int(part[5]) > 0:
		mat.emission_enabled = true
		mat.emission = part[4]
		mat.emission_energy_multiplier = 2.5
		if int(part[5]) == 2:
			strobe_out.append(mat)
	mi.material_override = mat
	mi.position = part[2]
	mi.rotation_degrees = part[3]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)


# ---------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------

func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	structures.clear()
	_strobe_mats.clear()
	glb_loaded.clear()
	procedural_used.clear()
	debris_field = null
	if world_cfg == null:
		return
	var radius: float = world_cfg.planet_radius
	for key in ["station", "refinery", "beacon", "hub"]:
		var site: Dictionary = SITES[key]
		var pl: Dictionary = placement(key, radius)
		var node: Node3D
		var scene_name: String = site["scene"]
		if scene_name != "":
			node = (load(SCENE_DIR + scene_name) as PackedScene).instantiate() as Node3D
		else:
			node = Node3D.new()
		node.name = String(site["label"]).replace(" ", "")
		var strobes: Array = []
		var visual: Node3D = build_visual(site["model"], true, strobes)
		node.add_child(visual)
		_track_model(site["model"], visual)
		for m in strobes:
			_strobe_mats.append(m)
		_register(key, node, pl["origin"], pl["unit_dir"], site["rate"], 0.0, "structure")
	for i in SATELLITE_COUNT:
		var sp: Dictionary = satellite_placement(i, world_cfg.world_seed, radius)
		var sat: Node3D = (load(SCENE_DIR + "Satellite.tscn") as PackedScene).instantiate() as Node3D
		sat.name = "Satellite%d" % i
		var vis: Node3D = build_visual("broken_satellite", true)
		sat.add_child(vis)
		_track_model("broken_satellite", vis)
		_register("satellite_%d" % i, sat, sp["origin"], sp["unit_dir"], sp["rate"], sp["angle0"], "satellite")
	var dpl: Dictionary = placement("debris", radius)
	var field: Node3D = (load(SCENE_DIR + "DebrisField.tscn") as PackedScene).instantiate() as Node3D
	field.name = "DebrisField"
	add_child(field)
	field.call("setup", world_cfg.world_seed, quality_preset, dpl["origin"], dpl["unit_dir"], float(SITES["debris"]["radius"]))
	field.call("apply_origin", current_origin)
	debris_field = field
	set_quality(quality_preset)
	apply_origin(current_origin)


func _track_model(model: String, visual: Node3D) -> void:
	var list: Array[String] = glb_loaded if visual.get_meta("glb", false) else procedural_used
	if not list.has(model):
		list.append(model)


func _register(key: String, node: Node3D, origin: Vector3, unit_dir: Vector3, rate: float, angle0: float, kind: String) -> void:
	add_child(node)
	structures[key] = {"node": node, "base_pos": origin, "unit_dir": unit_dir, "rate": rate, "angle0": angle0, "kind": kind}
	_pose(structures[key])


func _pose(entry: Dictionary) -> void:
	var node: Node3D = entry["node"]
	var tb: Basis = Transforms.surface_tangent_basis(entry["unit_dir"])
	var ang: float = float(entry["angle0"]) + float(entry["rate"]) * orbital_time
	node.basis = tb * Basis(Vector3.UP, ang)
	node.position = (entry["base_pos"] as Vector3) - current_origin


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()
	var n_vis: int = SAT_VISIBLE.get(quality_preset, 6)
	for i in SATELLITE_COUNT:
		var e: Dictionary = structures.get("satellite_%d" % i, {})
		if not e.is_empty():
			(e["node"] as Node3D).visible = i < n_vis
	if debris_field != null:
		debris_field.call("set_quality", quality_preset)


## Floating-origin re-base: render position = planet position - origin.
func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	for key in structures:
		var e: Dictionary = structures[key]
		if is_instance_valid(e["node"]):
			(e["node"] as Node3D).position = (e["base_pos"] as Vector3) - current_origin
	if debris_field != null and is_instance_valid(debris_field):
		debris_field.call("apply_origin", new_origin)


func _process(delta: float) -> void:
	tick(delta)


## Gentle deterministic orbital rotation + navigation beacon strobes.
func tick(delta: float) -> void:
	tick_count += 1
	orbital_time += delta
	for key in structures:
		var e: Dictionary = structures[key]
		if is_instance_valid(e["node"]):
			_pose(e)
	strobe_state = fposmod(orbital_time * 0.8, 1.0) < 0.18
	for i in _strobe_mats.size():
		var phase: bool = fposmod(orbital_time * 0.8 + float(i) * 0.25, 1.0) < 0.18
		_strobe_mats[i].emission_energy_multiplier = 6.0 if phase else 0.25
	if debris_field != null and is_instance_valid(debris_field):
		debris_field.call("tick", delta)


func get_structure(key: String) -> Node3D:
	var e: Dictionary = structures.get(key, {})
	return e.get("node", null)


## Planet-space centre of a structure (or the debris field).
func get_planet_position(key: String) -> Vector3:
	if key == "debris":
		return placement("debris", world_cfg.planet_radius)["origin"]
	var e: Dictionary = structures.get(key, {})
	return e.get("base_pos", Vector3.ZERO)


func get_structure_count() -> int:
	return structures.size()


func get_diagnostics() -> Dictionary:
	var named: int = 0
	for key in structures:
		if not String(key).begins_with("satellite_"):
			named += 1
	var d: Dictionary = {"structures": structures.size(), "named_structures": named, "satellites": SATELLITE_COUNT,
		"glb_loaded": glb_loaded.size(), "procedural": procedural_used.size(), "strobe_on": strobe_state}
	if debris_field != null:
		d["debris"] = debris_field.call("get_tier_counts")
	return d
