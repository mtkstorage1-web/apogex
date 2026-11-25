class_name LandmarkManager
extends Node3D
## Registers the named Vesper-9 landmarks, builds each one (Blender GLB when imported, procedural
## fallback otherwise), embeds it firmly into the terrain and exposes safe explorer teleport data.

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const Scatter = preload("res://scripts/environment/SurfacePropScatterer.gd")
const FacilityMgr = preload("res://scripts/environment/SurfaceFacilityManager.gd")
const Infra = preload("res://scripts/environment/InfrastructureNetwork.gd")
const ShipMgr = preload("res://scripts/environment/MothershipManager.gd")
const ShipInterior = preload("res://scripts/environment/MothershipInterior.gd")

const LANDMARK_DIR := "res://assets/models/apogex/landmarks/"
const TERRAIN_SCENE_DIR := "res://scenes/terrain/"
## Foundation top sits this far below the sampled terrain height: zero floating.
const FOUNDATION_EMBED := 0.5
const ORBIT_ALTITUDE := 5500.0
const TELEPORT_STANDOFF := 52.0
## Explorer capsule centre height above ground when teleported (capsule is 1.8 m tall).
const TELEPORT_CLEARANCE := 1.05

## Model id -> {glb, height (m, normalised), proc}
const MODELS: Dictionary = {
	"spire": {"glb": "extraction_beacon_spire.glb", "height": 52.0},
	"relay_tower": {"glb": "relay_tower.glb", "height": 42.0},
	"vent_chimney": {"glb": "thermal_vent_chimney.glb", "height": 20.0},
	"pylon": {"glb": "industrial_pylon.glb", "height": 12.0},
}

## index order matters (F6 cycles through it).
const DEFS: Array = [
	{"name": "Low Vesper-9 Orbit", "biome": "Terminus Basin", "lat": 0.0, "lon": 0.0, "orbit": true},
	{"name": "Terminus Basin - Extraction Complex", "biome": "Terminus Basin", "lat": 0.0, "lon": 0.0,
		"facility": "extraction", "standoff": 70.0, "main": "", "pylons": 0, "ring": 0.0, "scene": "", "accents": []},
	{"name": "Crimson Canyons - Red Gorge Arch", "biome": "Crimson Canyons", "lat": 10.0, "lon": -13.0,
		"main": "", "pylons": 0, "ring": 0.0, "scene": "Canyon.tscn", "accents": ["crimson_pillar"]},
	{"name": "Obsidian Fields - Derelict Settlement", "biome": "Obsidian Fields", "lat": 0.0, "lon": -20.0,
		"facility": "settlement", "standoff": 65.0, "main": "", "pylons": 0, "ring": 0.0, "scene": "", "accents": []},
	{"name": "Iron Desert - Ore Refinery", "biome": "Iron Desert", "lat": 0.0, "lon": 20.0,
		"facility": "refinery", "standoff": 70.0, "main": "", "pylons": 0, "ring": 0.0, "scene": "", "accents": []},
	{"name": "Fractured Highlands - Mining Facility", "biome": "Fractured Highlands", "lat": 18.0, "lon": 0.0,
		"facility": "mining", "standoff": 70.0, "main": "", "pylons": 0, "ring": 0.0, "scene": "", "accents": []},
	{"name": "Ashen Wastes - Launch Site", "biome": "Ashen Wastes", "lat": -18.0, "lon": 0.0,
		"facility": "launch", "standoff": 75.0, "main": "", "pylons": 0, "ring": 0.0, "scene": "", "accents": []},
	{"name": "Crimson Canyons South - Canyon Overlook", "biome": "Crimson Canyons", "lat": -10.0, "lon": 13.0,
		"main": "", "pylons": 3, "ring": 22.0, "scene": "Canyon.tscn", "accents": []},
	# Interior / infrastructure previews (appended: indices 8+ never disturb the original order).
	{"name": "Terminus Basin - Control Facility Interior", "biome": "Terminus Basin", "lat": 0.0, "lon": 0.0,
		"interior": "extraction", "local": Vector3(0.0, 2.3, 40.0), "look": Vector3(0, 0, -1)},
	{"name": "Fractured Highlands - Maintenance Building", "biome": "Fractured Highlands", "lat": 18.0, "lon": 0.0,
		"interior": "mining", "local": Vector3(-20.0, 1.4, 28.5), "look": Vector3(0, 0, -1)},
	{"name": "Iron Desert - Transport Tunnel Portal", "biome": "Iron Desert", "lat": 0.0, "lon": 20.0,
		"interior": "refinery", "local": Vector3(18.0, 1.4, -6.0), "look": Vector3(1, 0, 0)},
	{"name": "Ashen Wastes - Control Bunker", "biome": "Ashen Wastes", "lat": -18.0, "lon": 0.0,
		"interior": "launch", "local": Vector3(6.0, 1.4, 36.0), "look": Vector3(0, 0, -1)},
	{"name": "Obsidian Fields - Habitat Module", "biome": "Obsidian Fields", "lat": 0.0, "lon": -20.0,
		"interior": "settlement", "local": Vector3(-26.0, 1.4, 6.0), "look": Vector3(0, 0, 1)},
	{"name": "Crimson Canyon Bridge Alpha", "biome": "Crimson Canyons", "lat": 10.0, "lon": -13.8, "bridge": 0},
	# Orbiting motherships (850 m hulls; interiors are walkable under artificial ship gravity).
	{"name": "Helion Mothership - Exterior Approach", "biome": "Low Orbit", "ship": "helion", "view": "approach"},
	{"name": "Helion Mothership - Main Hangar", "biome": "Low Orbit", "ship": "helion", "view": "hangar"},
	{"name": "Helion Mothership - Command Bridge", "biome": "Low Orbit", "ship": "helion", "view": "bridge"},
	{"name": "Cinder Mothership - Exterior Approach", "biome": "Low Orbit", "ship": "cinder", "view": "approach"},
	{"name": "Cinder Mothership - Main Hangar", "biome": "Low Orbit", "ship": "cinder", "view": "hangar"},
	{"name": "Cinder Mothership - Reactor Chamber", "biome": "Low Orbit", "ship": "cinder", "view": "reactor"},
	# Orbital structures (Wave 5): debris field, research station, refinery, docking hub.
	{"name": "Orbital Debris Field", "biome": "Low Orbit", "orbital": "debris"},
	{"name": "Abandoned Research Station", "biome": "Low Orbit", "orbital": "station"},
	{"name": "Broken Orbital Refinery", "biome": "Low Orbit", "orbital": "refinery"},
	{"name": "Orbital Docking Hub", "biome": "Low Orbit", "orbital": "hub"},
]

## Ship-local vantage points (interior views stand on the room spawn, facing `look`).
const SHIP_VIEWS: Dictionary = {
	"approach": {"local": Vector3(520, 60, -300), "target": Vector3(0, 0, 100), "walk": false},
	"hangar": {"local": Vector3(0, 1, 330), "look": Vector3(0, 0, 1), "walk": true},
	"bridge": {"local": Vector3(90, 9, 180), "look": Vector3(0.72, 0, 0.69), "walk": true},
	"reactor": {"local": Vector3(-70, 1, -100), "look": Vector3(-1, 0, 0), "walk": true},
}

var noise: TerrainNoiseStack
var world_cfg: WorldConfig
var landmarks: Array[Dictionary] = []
var current_index: int = 0
var current_origin: Vector3 = Vector3.ZERO
var glb_models_loaded: Array[String] = []
var _nodes: Array[Node3D] = []


func setup(p_noise: TerrainNoiseStack, p_world_cfg: WorldConfig) -> void:
	noise = p_noise
	world_cfg = p_world_cfg
	rebuild()


func get_count() -> int:
	return landmarks.size()


func get_landmark(index: int) -> Dictionary:
	if landmarks.is_empty():
		return {}
	return landmarks[posmod(index, landmarks.size())]


func next_index() -> int:
	return posmod(current_index + 1, maxi(landmarks.size(), 1))


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	for lm in landmarks:
		if lm.has("node") and is_instance_valid(lm["node"]):
			(lm["node"] as Node3D).position = (lm["base_pos"] as Vector3) - current_origin


func rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_nodes.clear()
	landmarks.clear()
	glb_models_loaded.clear()
	if noise == null:
		return
	for i in DEFS.size():
		var def: Dictionary = DEFS[i]
		var lm: Dictionary = _make_landmark(i, def)
		landmarks.append(lm)


func _make_landmark(index: int, def: Dictionary) -> Dictionary:
	if def.has("ship"):
		return _make_ship_landmark(index, def)
	if def.has("orbital"):
		return _make_orbital_landmark(index, def)
	var unit_dir: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(def["lat"] as float), deg_to_rad(def["lon"] as float))
	var lm: Dictionary = {
		"index": index,
		"name": def["name"],
		"biome_name": def["biome"],
		"unit_dir": unit_dir,
		"is_orbit": def.get("orbit", false),
	}
	if lm["is_orbit"]:
		# Camera sits south-west of the basin, 5.5 km up, looking back over Terminus Basin and the sunlit limb.
		var view_dir: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(-7.0), deg_to_rad(-9.0))
		var surf_r: float = noise.sample_surface_radius(view_dir)
		var cam: Vector3 = view_dir * (world_cfg.planet_radius + ORBIT_ALTITUDE)
		var target: Vector3 = noise.sample_surface_position(unit_dir) + unit_dir * 600.0
		lm["surface_pos"] = noise.sample_surface_position(unit_dir)
		lm["base_pos"] = lm["surface_pos"]
		lm["planet_pos"] = cam
		lm["look_dir"] = (target - cam).normalized()
		lm["terrain_radius"] = surf_r
		return lm

	if def.has("interior") or def.has("bridge"):
		return _make_preview_landmark(lm, def, unit_dir)

	var surface: Vector3 = noise.sample_surface_position(unit_dir)
	var base: Vector3 = surface - unit_dir * FOUNDATION_EMBED
	var tb: Basis = Transforms.surface_tangent_basis(unit_dir)
	lm["surface_pos"] = surface
	lm["base_pos"] = base
	lm["terrain_radius"] = surface.length()
	lm["basis"] = tb

	# Safe teleport spot: stand-off to the south (+Z), facing north (-Z) toward the landmark.
	var standoff: float = def.get("standoff", TELEPORT_STANDOFF)
	var stand_dir: Vector3 = (unit_dir + tb.z * (standoff / surface.length())).normalized()
	var stand_surface: Vector3 = noise.sample_surface_position(stand_dir)
	lm["planet_pos"] = stand_surface + stand_dir * TELEPORT_CLEARANCE
	var to_target: Vector3 = (surface - stand_surface)
	to_target -= stand_dir * to_target.dot(stand_dir)
	lm["look_dir"] = to_target.normalized() if to_target.length_squared() > 0.01 else -tb.z

	var root := Node3D.new()
	root.name = "Landmark%d_%s" % [index, (def["biome"] as String).replace(" ", "")]
	root.basis = tb
	add_child(root)
	root.position = base - current_origin
	_nodes.append(root)
	lm["node"] = root
	_build_contents(root, lm, def, unit_dir, tb)
	return lm


## Mothership vantage: planet-space pose derived from the ship's deterministic orbital placement.
func _make_ship_landmark(index: int, def: Dictionary) -> Dictionary:
	var pl: Dictionary = ShipMgr.ship_placement(def["ship"], world_cfg.planet_radius)
	var ship_basis: Basis = pl["basis"]
	var origin: Vector3 = pl["origin"]
	var view: Dictionary = SHIP_VIEWS[def["view"]]
	var local: Vector3 = view["local"]
	var look_local: Vector3 = (view["target"] - local) if view.has("target") else view["look"]
	var surface: Vector3 = noise.sample_surface_position(pl["unit_dir"])
	return {
		"index": index, "name": def["name"], "biome_name": def["biome"],
		"unit_dir": pl["unit_dir"], "is_orbit": true, "is_mothership": true,
		"walk": view["walk"], "ship": def["ship"],
		"surface_pos": surface, "base_pos": surface, "terrain_radius": surface.length(),
		"planet_pos": origin + ship_basis * local,
		"look_dir": (ship_basis * look_local).normalized(),
		"basis": ship_basis,
	}


## Orbital structure vantage: stand-off beside the structure/field, looking at its centre.
func _make_orbital_landmark(index: int, def: Dictionary) -> Dictionary:
	var pl: Dictionary = OrbitalEnvironmentManager.placement(def["orbital"], world_cfg.planet_radius)
	var origin: Vector3 = pl["origin"]
	var u: Vector3 = pl["unit_dir"]
	var tb: Basis = Transforms.surface_tangent_basis(u)
	var cam: Vector3 = origin + (tb.z * 0.8 + tb.y * 0.25 + tb.x * 0.3).normalized() * float(pl["standoff"])
	var surface: Vector3 = noise.sample_surface_position(u)
	return {
		"index": index, "name": def["name"], "biome_name": def["biome"],
		"unit_dir": u, "is_orbit": true, "is_orbital_structure": true, "orbital": def["orbital"],
		"surface_pos": surface, "base_pos": surface, "terrain_radius": surface.length(),
		"planet_pos": cam, "look_dir": (origin - cam).normalized(), "basis": tb,
	}


## Interior spawn / bridge deck vantage: teleport-only landmark (no node of its own).
func _make_preview_landmark(lm: Dictionary, def: Dictionary, unit_dir: Vector3) -> Dictionary:
	var pos: Vector3
	var look: Vector3
	var tb: Basis
	if def.has("bridge"):
		var lay: Dictionary = Infra.compute_bridge_layout(noise, world_cfg.planet_radius, int(def["bridge"]))
		tb = lay["tb"]
		var deck: Vector3 = lay["center"]
		var up: Vector3 = deck.normalized()
		pos = deck + up * (TELEPORT_CLEARANCE + 0.25)
		look = tb.x
		lm["surface_pos"] = noise.sample_surface_position(lay["center_dir"])
		lm["unit_dir"] = lay["center_dir"]
	else:
		var pt: Dictionary = FacilityMgr.pad_transform(noise, float(def["lat"]), float(def["lon"]))
		tb = pt["basis"]
		pos = (pt["origin"] as Vector3) + tb * (def["local"] as Vector3)
		look = tb * (def["look"] as Vector3)
		lm["surface_pos"] = pt["surface"]
	lm["base_pos"] = lm["surface_pos"]
	lm["planet_pos"] = pos
	lm["look_dir"] = look.normalized()
	lm["terrain_radius"] = (lm["surface_pos"] as Vector3).length()
	lm["basis"] = tb
	lm["is_preview"] = true
	return lm


func _build_contents(root: Node3D, lm: Dictionary, def: Dictionary, unit_dir: Vector3, tb: Basis) -> void:
	var base: Vector3 = lm["base_pos"]
	if def.has("facility"):
		# The SurfaceFacilityManager owns the real structure: keep only a deeply buried collision anchor.
		var anchor := StaticBody3D.new()
		anchor.name = "FoundationCollision"
		anchor.collision_layer = 1
		anchor.collision_mask = 0
		var acs := CollisionShape3D.new()
		var abox := BoxShape3D.new()
		abox.size = Vector3(12.0, 4.0, 12.0)
		acs.shape = abox
		acs.position = Vector3(0, -9.0, 0)
		anchor.add_child(acs)
		root.add_child(anchor)
		lm["facility"] = def["facility"]
		return
	# Solid foundation: a concrete drum buried deep enough to hide any slope gap, plus collision.
	var foundation_r: float = 9.0 if def.get("main", "") != "" else 7.0
	var fb := StaticBody3D.new()
	fb.name = "FoundationCollision"
	fb.collision_layer = 1
	fb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = foundation_r
	cyl.height = 4.0
	cs.shape = cyl
	cs.position = Vector3(0, FOUNDATION_EMBED - 2.0 + 0.0, 0)
	fb.add_child(cs)
	root.add_child(fb)
	var drum := MeshInstance3D.new()
	drum.name = "FoundationDrum"
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = foundation_r
	drum_mesh.bottom_radius = foundation_r * 1.04
	drum_mesh.height = 4.0
	drum_mesh.radial_segments = 24
	drum.mesh = drum_mesh
	drum.material_override = Scatter.make_vertex_color_material(0.8)
	(drum.material_override as StandardMaterial3D).vertex_color_use_as_albedo = false
	(drum.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.3, 0.32)
	drum.position = Vector3(0, FOUNDATION_EMBED - 2.0, 0)
	root.add_child(drum)

	var main_id: String = def.get("main", "")
	if main_id != "":
		var main_node: Node3D = _make_model(main_id)
		main_node.name = "MainStructure"
		# Top surface of the drum is FOUNDATION_EMBED above the root origin... keep the base on it.
		main_node.position += Vector3(0, FOUNDATION_EMBED, 0)
		root.add_child(main_node)
	var scene_name: String = def.get("scene", "")
	if scene_name != "":
		var path: String = TERRAIN_SCENE_DIR + scene_name
		if ResourceLoader.exists(path):
			var ps: PackedScene = load(path) as PackedScene
			if ps != null:
				var feature: Node = ps.instantiate()
				if feature is Node3D:
					feature.name = "TerrainFeature"
					root.add_child(feature)
				else:
					feature.free()
	var pylons: int = def.get("pylons", 0)
	for p in pylons:
		var ang: float = TAU * float(p) / float(pylons) + 0.3
		_place_on_ground(root, lm, tb, _make_model("pylon"), unit_dir, Vector2(cos(ang), sin(ang)) * (def["ring"] as float), "Pylon%d" % p)
	var accents: Array = def.get("accents", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_cfg.world_seed, lm["index"]])
	for a in accents:
		for k in 5:
			var ang2: float = rng.randf() * TAU
			var dist: float = rng.randf_range(38.0, 90.0)
			var node: Node3D = _make_accent(a as String, rng)
			_place_on_ground(root, lm, tb, node, unit_dir, Vector2(cos(ang2), sin(ang2)) * dist, "Accent_%s_%d" % [a, k])


## Positions a node on the terrain at an east/north offset (m) from the landmark; embedded 0.3 m.
func _place_on_ground(root: Node3D, lm: Dictionary, tb: Basis, node: Node3D, unit_dir: Vector3, offset_en: Vector2, node_name: String) -> void:
	var r: float = (lm["surface_pos"] as Vector3).length()
	var dir: Vector3 = (unit_dir + (tb.x * offset_en.x + tb.z * offset_en.y) / r).normalized()
	var surf: Vector3 = noise.sample_surface_position(dir)
	var local: Vector3 = tb.inverse() * (surf - (lm["base_pos"] as Vector3)) - Vector3(0, 0.3, 0)
	node.name = node_name
	# Orient the node to its own local up while keeping the landmark's heading.
	var up_local: Vector3 = tb.inverse() * dir
	var basis := Basis(Quaternion(Vector3.UP, up_local))
	node.transform = Transform3D(basis, local)
	root.add_child(node)


func _make_accent(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var info: Dictionary = Scatter.get_prop_mesh(kind)
	var aabb: AABB = info["aabb"]
	var hr: Vector2 = (Scatter.KINDS[kind] as Dictionary)["height"]
	var s: float = rng.randf_range(hr.y * 0.7, hr.y * 1.4) / maxf(aabb.size.y, 0.001)
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = info["mesh"]
	mi.scale = Vector3(s, s, s)
	mi.rotation.y = rng.randf() * TAU
	mi.position = Vector3(0, -aabb.position.y * s, 0)
	holder.add_child(mi)
	return holder


## Builds a landmark model: Blender GLB (normalised to its target height, base on y=0) or fallback.
func _make_model(model_id: String) -> Node3D:
	var data: Dictionary = MODELS[model_id]
	var glb_path: String = LANDMARK_DIR + (data["glb"] as String)
	var target_h: float = data["height"]
	var holder := Node3D.new()
	var inst: Node3D = Scatter.instantiate_glb(glb_path)
	if inst != null:
		var aabb: AABB = Scatter.compute_scene_aabb(inst)
		if aabb.size.y > 0.001:
			var s: float = target_h / aabb.size.y
			inst.scale = Vector3(s, s, s)
			inst.position = Vector3(-(aabb.position.x + aabb.size.x * 0.5) * s, -aabb.position.y * s, -(aabb.position.z + aabb.size.z * 0.5) * s)
		holder.add_child(inst)
		if not glb_models_loaded.has(model_id):
			glb_models_loaded.append(model_id)
		holder.set_meta("source", "glb")
		return holder
	_build_procedural_model(holder, model_id, target_h)
	holder.set_meta("source", "procedural")
	return holder


func _build_procedural_model(holder: Node3D, model_id: String, h: float) -> void:
	var pm := Scatter.ProcMesh.new()
	var steel := Color(0.34, 0.36, 0.38)
	var dark := Color(0.14, 0.15, 0.17)
	var warn := Color(0.85, 0.42, 0.12)
	var glow_pos := Vector3.ZERO
	var glow_color := Color(1.0, 0.45, 0.12)
	var glow_r: float = 0.6
	match model_id:
		"spire":
			pm.add_cylinder(8.0, 7.0, 1.2, 8, Transform3D.IDENTITY, dark)
			pm.add_cylinder(3.6, 1.1, h * 0.86, 8, Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0)), steel)
			for i in 4:
				var y: float = 1.2 + h * (0.14 + 0.19 * i)
				var r: float = lerpf(3.4, 1.4, float(i) / 4.0) + 0.9
				pm.add_cylinder(r, r, 0.9, 8, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), warn if i % 2 == 0 else dark)
			for i in 4:
				var a: float = float(i) * TAU / 4.0 + PI / 4.0
				pm.add_box(Vector3(0.8, h * 0.28, 2.6), Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 4.2, 1.2, sin(a) * 4.2)), dark)
			pm.add_cylinder(0.5, 0.0, h * 0.14, 6, Transform3D(Basis.IDENTITY, Vector3(0, 1.2 + h * 0.86, 0)), steel)
			glow_pos = Vector3(0, 1.2 + h * 0.9, 0)
			glow_r = 1.1
			glow_color = Color(1.0, 0.35, 0.1)
		"relay_tower":
			pm.add_box(Vector3(9.0, 1.0, 9.0), Transform3D.IDENTITY, dark)
			for i in 4:
				var a2: float = float(i) * TAU / 4.0 + PI / 4.0
				var lean := Basis(Vector3.UP, a2) * Basis(Vector3.RIGHT, -0.095)
				pm.add_box(Vector3(0.5, h * 0.82, 0.5), Transform3D(lean, Vector3(cos(a2) * 3.0, 1.0, sin(a2) * 3.0)), steel)
			for i in 3:
				var y2: float = h * (0.2 + 0.22 * float(i))
				var w: float = lerpf(5.2, 2.2, y2 / h)
				pm.add_box(Vector3(w, 0.35, w), Transform3D(Basis.IDENTITY, Vector3(0, y2, 0)), warn if i == 1 else dark)
			pm.add_cylinder(0.4, 0.4, h * 0.2, 6, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.8, 0)), steel)
			var dish := SphereMesh.new()
			dish.radius = 3.0
			dish.height = 2.4
			dish.radial_segments = 14
			dish.rings = 5
			pm.add_prim(dish, Transform3D(Basis(Vector3.RIGHT, -0.7).scaled_local(Vector3(1, 0.35, 1)), Vector3(0, h * 0.95, 0)), Color(0.8, 0.8, 0.82))
			glow_pos = Vector3(0, h * 1.02, 0)
			glow_r = 0.55
			glow_color = Color(1.0, 0.15, 0.1)
		"vent_chimney":
			pm.add_cylinder(6.2, 2.6, h, 9, Transform3D.IDENTITY, Color(0.12, 0.1, 0.1))
			pm.add_cylinder(3.0, 3.2, h * 0.12, 9, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.94, 0)), Color(0.22, 0.12, 0.08))
			pm.add_cylinder(7.6, 6.4, 1.4, 9, Transform3D.IDENTITY, Color(0.09, 0.08, 0.08))
			glow_pos = Vector3(0, h * 1.0, 0)
			glow_r = 2.1
			glow_color = Color(1.0, 0.35, 0.05)
		_:  # pylon
			pm.add_box(Vector3(1.6, 0.5, 1.6), Transform3D.IDENTITY, dark)
			pm.add_cylinder(0.32, 0.18, h * 0.9, 6, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), steel)
			pm.add_box(Vector3(3.2, 0.22, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.78, 0)), warn)
			pm.add_box(Vector3(0.8, 0.5, 0.8), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.92, 0)), dark)
			glow_pos = Vector3(0, h * 0.97, 0)
			glow_r = 0.28
			glow_color = Color(1.0, 0.6, 0.2)
	var mi := MeshInstance3D.new()
	mi.name = "ProceduralBody"
	mi.mesh = pm.finish()
	holder.add_child(mi)
	var glow := MeshInstance3D.new()
	glow.name = "Beacon"
	var sphere := SphereMesh.new()
	sphere.radius = glow_r
	sphere.height = glow_r * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	glow.mesh = sphere
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = glow_color
	gm.emission_enabled = true
	gm.emission = glow_color
	gm.emission_energy_multiplier = 3.0
	glow.material_override = gm
	glow.position = glow_pos
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(glow)
	if model_id != "pylon":
		var light := OmniLight3D.new()
		light.light_color = glow_color
		light.light_energy = 2.5
		light.omni_range = 60.0
		light.shadow_enabled = false
		light.position = glow_pos
		holder.add_child(light)
