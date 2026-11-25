## Earth: launch pad, part racks, supply cases, systems consoles, delivery pad and rival pads.
## Home construction, spacecraft access, and flag delivery.
class_name PlanetA
extends Node3D

const CONSOLES := {"engine": Vector3(-12, 0, 4), "power": Vector3(12, 0, -3), "pressure": Vector3(12, 0, 6)}
const CONSOLE_PROPS := {"engine": "prop_dial_calibrator", "power": "prop_button_console", "pressure": "prop_valve_wheel"}
const Hardware = preload("res://scripts/industrial_hardware.gd")
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const ACCENT := Color("#f08a4b")
const SHOP := Vector3(0, 0, -30)
const SHOP_FOOTPRINT := Rect2(-17, SHOP.z - 11, 34, 24)
const DELIVERY_ROAD := Rect2(Sim.DELIVERY_PAD.x - 4.5, 20.7, 9, 41.1)
const SHOP_COMPUTER := Vector3(0, 0, SHOP.z - 8.2)
const CARGO_HATCH := Sim.CARGO_HATCH
const SHOP_DESK := Vector3(14, 0, -23) # parts confirmation status
const LAUNCH_DESK := Vector3(-14, 0, -23) # authored apron fixture
# --- Launch-complex layout (top-down XZ, ship at origin, nose -Z) -----------
# Pedestals sit inside the apron railing (r = APRON_RAILING_RADIUS), clear of
# the gantry posts (-17,-14)/(-17,8), and check consoles.
const CRANE_BASES := [Vector3(-13.5, 0, -11.5), Vector3(13.5, 0, -11.5), Vector3(-13.5, 0, 11.5), Vector3(13.5, 0, 11.5)]
# Operator elevator shafts stand outboard of the railing, between the racks and
# the GSE carousel bays, out of every crane arm's sweep line.
const ELEVATOR_SITES := [Vector3(-28, 0, -6), Vector3(28, 0, -6), Vector3(-28, 0, 12), Vector3(28, 0, 12)]
const ELEVATOR_HEIGHT := 12.0
const ELEVATOR_SIZE := Vector2(6.0, 5.0)
const CRANE_ALIGNMENT := 0.8
# Human crane operators get a forgiving capture radius; the claw then magnets
# onto the exact grip so modules still seat precisely.
const CRANE_GRAB_RADIUS := 3.5
const CRANE_MAGNET_SPEED := 14.0
const CRANE_MIN_RADIUS := 4.0
const CRANE_SPEED := 9.0
const CRANE_CLAMP := Rect2(-45.0, -42.0, 90.0, 68.0)
# Vertical hoist: SPACE raises the claw, SHIFT / C lowers it. The claw never
# drops below the active grip height and never rises above the hoist ceiling.
const CRANE_HOIST_SPEED := 6.0
const CRANE_HOIST_TOP := 18.0
const CRANE_HOIST_SPAN := 6.0
const CRANE_CLAW_DROP := 1.3   # tip node -> bottom of the jaws
const APRON_RAILING_RADIUS := 23.5
const SERVICE_TRAY_ORIGIN := Vector3(14, 0, 30)
# Each crane has its own Workshop dock so conveyor lanes never share or cross.
# Lanes run along X first, then along Z into the end of their carousel bay.
const GSE_DISPATCHES := [Vector3(-18.5, 1.25, -48), Vector3(18.5, 1.25, -48),
	Vector3(-21, 1.25, -14), Vector3(21, 1.25, -14)]
const GSE_PICKUPS := [Vector3(-36, 1.25, -35), Vector3(36, 1.25, -35),
	Vector3(-38, 1.25, 0), Vector3(38, 1.25, 0)]
const GSE_BAY_SIZE := Vector2(9.0, 21.0)   # carousel turned long-axis along Z (modules ride nose-first)
const GSE_ARCH_STATIONS := [0.12, 0.75]      # scanner arches along each lane's X run
const GSE_ARCH_SCALE := Vector3(1.0, 2.4, 2.0)
const GSE_LOAD_SPEED := 8.0
const CRANE_GRIP_CLEARANCE := 0.35
enum LiftState { GROUND, BOARDING, RISING, DECK, RETURN_BOARDING, LOWERING, PARKED }

var lift_state := LiftState.GROUND
var lift_progress := 0.0
var lifts: Array = []   # one {"platform","sign"} per crane arm / specialist
var crane_mode := false
var crane_role := 0
var crane_enter_frame := -1
var crane_view_meshes: Array[MeshInstance3D] = []
var crane_view_hidden := {}
var gse := {}
var gse_routes: Array[Curve3D] = []
var gse_modules := {}
var gse_loads := ["", "", "", ""]
var gse_progress := [0.0, 0.0, 0.0, 0.0]
var gse_dispatch_gap := 0.0
var crane_marker: MeshInstance3D          # vertical hoist drop-line under the claw
var crane_drop_foot: Node3D               # reticle where the drop-line meets the surface
var crane_height_label: Label3D           # live vertical distance readout
var crane_drop_material: StandardMaterial3D
var crane_drop_distance := 0.0            # claw height above the active grip point
var crane_target_marker: Node3D
var crane_target_material: StandardMaterial3D
var crane_ghost_material: StandardMaterial3D

var launch_desk_ring: MeshInstance3D
var launch_desk_label: Label3D

const EmpireLayer = preload("res://scripts/empire_world_layer.gd")
const DEFENSE_MAGAZINE := 24
const DEFENSE_RELOAD := 1.15
const DEFENSE_RANGE := 120.0
var empire_layer: EmpireLayer
var spaceport_perimeter: Node3D
var _defense_ammo := [24, 24, 24, 24]
var _defense_cooldown := [0.0, 0.0, 0.0, 0.0]

var g
var delivery := false
var actors: Array = []
var slot_nodes := {}
var shelf_nodes := {}
var cargo_nodes := {}
var carry_vis: Array = ["", "", "", ""]
var ghost: Node3D
var ghost_key := ""
var beacon: MeshInstance3D
var beacon_target := Vector3.ZERO
var beacon_label := ""
var ship_root: Node3D
var rival_ships: Array = []
var bots: Array = [{"t": 0.0}, {"t": 0.0}, {"t": 0.0}, {"t": 0.0}]

# Vertical crew boarding elevator: all 4 crew ride it to the hatch before the mission desk unlocks.
const BOARD_BASE := Vector3(8.0, 0, 4.0)
const BOARD_HATCH_Y := 7.0
const BOARD_RISE_TIME := 2.6
const BOARD_WALKWAY_REACH := 13.5
var board_rig: Node3D
var board_platform: Node3D
var board_label: Label3D
var board_hatch := Vector3(2.4, BOARD_HATCH_Y, BOARD_BASE.z)
var deliver_clock := 0.0
var blockers: Array = []   # Rect2 footprints on the ground plane
var intro_from := Vector3.ZERO
var shop_items: Array = []
var shop_kiosk_node: Node3D
var shop_desk_ring: MeshInstance3D
var shop_desk_label: Label3D
# Automated machine assembly (Iron-Man-style build sequence)
var climb_start := Vector3.ZERO
var pad_steam: CPUParticles3D
var fx_ready := false
var fx_base := {}          # part id -> original local position
var fx_orig_mats := {}     # MeshInstance3D -> original material_override
var fx_holo := {}          # part key -> true while holo-tinted
var fx_done := {}          # key -> true after the snap flash
var fx_arms: Array = []
var fx_sparks: Array = []
var _landing_nodes: Array[Node3D] = []
var _bolt_materials: Array[Material] = []
var fx_light: OmniLight3D
var pad_stage := "shop"    # Local workshop and crane status.
var fx_cargo_base := {}
var fx_shake := 0.0
var visual_loadout := {}
var apron_lights: Array[OmniLight3D] = []
var _pbr_cliff: Material
var _grass_multimesh: MultiMesh
var _grass_material: ShaderMaterial
var _water_material: ShaderMaterial
var _quality_key := -1
var _pbr_cladding: Material
var _pbr_dark_steel: Material
static var _weather_normal: NoiseTexture2D


func actor(i: int) -> Actor:
	return actors[i]


static func _optional_pbr_material(gfx_script: GDScript, kind: String, scale: float,
		tint: Color, metallic: float) -> Material:
	if gfx_script.has_method("create_pbr_mat"):
		return gfx_script.call("create_pbr_mat", kind, scale, tint, metallic) as Material
	return null


var home_alliance := "planet_a"
var planet_label := Universe.A_LABEL
var accent := ACCENT


func setup(main, p_delivery: bool, p_home_alliance := "planet_a") -> void:
	g = main
	delivery = p_delivery
	home_alliance = p_home_alliance
	var twin := home_alliance == "planet_b"
	name = "PlanetBEarth" if twin else "PlanetA"
	planet_label = Universe.B_LABEL if twin else Universe.A_LABEL
	if twin:
		var squad: String = g.sim.empire_squad if g.sim.empire_home == home_alliance else "crimson"
		accent = Color.html(Sim.EMPIRE_COLORS[squad])
	# The set dressing is now stored in an editable Godot scene, not generated on play.
	var editable: Node3D = g.universe.ensure_twin_environment() if twin else g.universe.ensure_earth_environment()
	var gfx_script := load("res://scripts/gfx.gd") as GDScript
	if gfx_script.has_method("apply_cinematic_atmosphere"):
		gfx_script.call("apply_cinematic_atmosphere", editable)
	_setup_materials(gfx_script)
	var terrain := editable.get_node_or_null("Terrain")
	if terrain != null:
		var ground := terrain.get_node_or_null("Ground") as MeshInstance3D
		if ground != null and not (ground.material_override is ShaderMaterial) and gfx_script.has_method("create_terrain_shader_mat"):
			ground.material_override = gfx_script.call("create_terrain_shader_mat")
		if gfx_script.has_method("create_cliff_shader_mat"):
			var cliff_material: Material = gfx_script.call("create_cliff_shader_mat")
			for descendant in terrain.find_children("*", "MeshInstance3D", true, false):
				if descendant != ground:
					(descendant as MeshInstance3D).material_override = cliff_material
		var rocks := terrain.get_node_or_null("Rocks")
		if rocks != null and _pbr_cliff != null:
			for rock in rocks.find_children("*", "MeshInstance3D", true, false):
				(rock as MeshInstance3D).material_override = _pbr_cliff
	var foundation := editable.get_node_or_null("LaunchPad/PadFoundation") as MeshInstance3D
	if foundation != null:
		foundation.scale *= Vector3(23.0 / 21.0, 1.0, 23.0 / 21.0)
		# Grounded smooth sunlit concrete pad — avoids noisy speckled gravel grain or blowout.
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = Color("#7e8c96")
		pad_material.roughness = 0.88
		pad_material.metallic = 0.04
		foundation.material_override = pad_material
	var gantry := editable.get_node_or_null("LaunchPad/Gantry") as Node3D
	if gantry != null:
		gantry.scale.y *= ShipModel.VESSEL_SCALE
	# Every launchpad structure is a node of PlanetAEnvironment.tscn: bind to it (no runtime duplicates).
	_bind_existing_layout(editable)
	_ensure_structures(editable)
	_cargo()
	if g.arena_clash == null:
		_rivals()
	if g.sim.empire != null and home_alliance == g.sim.empire_home:
		empire_layer = EmpireLayer.new()
		empire_layer.setup(g.sim.empire, g.sim.empire_home, true, g.sim.empire_squad, g.request_empire_action, editable)
		add_child(empire_layer)
	_build_spaceport_perimeter()
	_ship()
	_living_world()
	_grass_scatter()
	_crew()
	if not delivery and g.arena_clash == null:
		_create_crane_deck()
	_compact_billboard_labels(self)
	_compact_billboard_labels(editable)
	beacon = Gfx.cyl(0.35, 40.0, accent, Vector3.ZERO, 8)
	beacon.material_override = Gfx.unshaded(accent.lightened(0.45), 0.28)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)
	var banner := Gfx.label(planet_label, accent, 52)
	banner.name = "HomeBanner"
	banner.position = Vector3(0, 8, SHOP.z + 5)
	add_child(banner)
	var a: Actor = actors[g.sim.selected]
	intro_from = a.position + Vector3(0, 2.0, -5.5)
	if g != null and g.get("graphics") != null:
		apply_quality(g.graphics)


# ---------------------------------------------------------------------------
# Master-planned spaceport campus (Zones 2-4; Zone 1 = the untouched central apron + workshop).
# Every structure stands on its own paved slab (y = SLAB_TOP) with a road link, hazard striping and light bollards.
# All coordinates are audited by tests/planet_a_layout_and_interior_test.gd against the PlanetAEnvironment ponds, pads,
# rocks, shop and apron footprint.
# ---------------------------------------------------------------------------
const CAMPUS_TOWERS := [
	{"id": "NW", "pos": Vector2(-84, -45), "pad": Vector2(-58, -30)},
	{"id": "NE", "pos": Vector2(84, -15), "pad": Vector2(58, -30)},
	{"id": "N", "pos": Vector2(28, -66), "pad": Vector2(0, -62)},
]
const CAMPUS_TOWER_SIZE := 30.0
const CAMPUS_SLAB_HALF := Vector2(7, 7)
const WEST_AVENUE_X := -96.0
const WEST_AVENUE_Z := Vector2(5, 79)
const WEST_TRUNK_Z := 25.0
const EAST_AVENUE_X := 96.0
const EAST_AVENUE_Z := Vector2(-57, 57)
const EAST_TRUNK_Z := -53.5
const AVENUE_WIDTH := 8.0
const TRUNK_WIDTH := 6.0
const TANK_FARM := Vector2(-129, 70)
const TANK_FARM_HALF := Vector2(9, 6)
const MOTOR_POOL := Vector2(115, -34)
const MOTOR_POOL_HALF := Vector2(13, 9)
const CAMPUS_ACCENT := Color("#58e7ff")


func _build_spaceport_perimeter() -> void:
	# Scene-first: use the SpaceportCampus baked into PlanetAEnvironment.tscn; only build procedurally as a fallback.
	var campus: Node3D = null
	if editable_root != null:
		campus = editable_root.get_node_or_null("SpaceportCampus") as Node3D
	if campus != null and campus.get_child_count() > 0:
		spaceport_perimeter = campus
	else:
		spaceport_perimeter = build_campus(self)
	if editable_root != null:
		clear_site_props(editable_root, collect_footprints([spaceport_perimeter, editable_root.get_node_or_null("EmpireDistricts"), empire_layer]))


## Bakes the editable `SpaceportCampus` group under `root` (called by tools/bake_planet_a_scene.gd).
func bake_campus(root: Node3D) -> void:
	_bake_campus(root)


## Builds the campus under `parent` and returns it (the runtime fallback / layout test entry point).
static func build_campus(parent: Node3D) -> Node3D:
	return _bake_campus(parent)


static func _campus_group(parent: Node3D, group_name: String, pos := Vector3.ZERO) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	group.position = pos
	parent.add_child(group)
	return group


static func _bake_campus(parent: Node3D) -> Node3D:
	var campus := _campus_group(parent, "SpaceportCampus")
	# Zone 2 - one launch service tower per allied squad pad: footing + road link + tower, grouped and draggable.
	for site: Dictionary in CAMPUS_TOWERS:
		var pos: Vector2 = site["pos"]
		var pad: Vector2 = site["pad"]
		var group := _campus_group(campus, "AlliedTower_" + str(site["id"]), Vector3(pos.x, 0, pos.y))
		var slab := EmpireLayer.paved_slab(group, Vector3.ZERO, CAMPUS_SLAB_HALF, CAMPUS_ACCENT, "TowerSlab" + site["id"])
		var toward := (pad - pos).normalized()
		EmpireLayer.paved_road(group, (pad - toward * 17.4) - pos, Vector2.ZERO, 3.5, "LinkTower" + site["id"])
		var tower := BlenderVisualUpgrades.place(group, "surface/launch_service_tower.glb",
			Vector3(0, EmpireLayer.SLAB_TOP, 0), CAMPUS_TOWER_SIZE, atan2(pad.x - pos.x, pad.y - pos.y))
		_tag_model(tower, "LaunchTower" + site["id"], slab)
	# Zone 3 - tank farm (west industrial).
	var refinery_site: Vector3 = EmpireLayer.HOME_SITES[2]
	var farm_group := _campus_group(campus, "TankFarm", Vector3(TANK_FARM.x, 0, TANK_FARM.y))
	var farm := EmpireLayer.paved_slab(farm_group, Vector3.ZERO, TANK_FARM_HALF, Color("#ffac58"), "TankFarmSlab")
	EmpireLayer.paved_road(farm_group, Vector2(refinery_site.x, refinery_site.z) - TANK_FARM, Vector2.ZERO, 4.0, "LinkTankFarm")
	var silo := BlenderVisualUpgrades.place(farm_group, "surface/storage_silo_bank.glb",
		Vector3(0, EmpireLayer.SLAB_TOP, 0), 14.0, 0.0)
	_tag_model(silo, "PropellantSiloBank", farm)
	# Zone 4 - fleet motor pool.
	_campus_motor_pool(_campus_group(campus, "FleetMotorPool", Vector3(MOTOR_POOL.x, 0, MOTOR_POOL.y)))
	# Avenues + trunk roads (absolute coordinates inside each group; drag a group to shift the whole road).
	_campus_avenue(campus, WEST_AVENUE_X, WEST_AVENUE_Z, Vector2(-40, WEST_TRUNK_Z), "West", EmpireLayer.HOME_SITES.slice(0, 3))
	_campus_avenue(campus, EAST_AVENUE_X, EAST_AVENUE_Z, Vector2(38, EAST_TRUNK_Z), "East", EmpireLayer.HOME_SITES.slice(3, 6))
	return campus


static func _tag_model(model: Node3D, model_name: String, slab: Node3D) -> void:
	if model == null:
		return
	model.name = model_name
	model.set_meta("campus_model", true)
	model.set_meta("slab", slab.name)


## North-south avenue at x (WestAvenue/EastAvenue) with an east-west trunk road (WestTrunkRoad/EastTrunkRoad) linking it
## to the central apron edge, plus light bollards and one driveway per empire site.
static func _campus_avenue(parent: Node3D, x: float, zr: Vector2, apron_end: Vector2, tag: String, sites: Array) -> void:
	var avenue := _campus_group(parent, tag + "Avenue")
	EmpireLayer.paved_road(avenue, Vector2(x, zr.x), Vector2(x, zr.y), AVENUE_WIDTH, tag + "Avenue")
	_road_bollards(avenue, Vector2(x, zr.x), Vector2(x, zr.y), AVENUE_WIDTH * 0.5 + 0.4)
	for site: Vector3 in sites:
		EmpireLayer.paved_road(avenue, Vector2(x + signf(site.x - x) * AVENUE_WIDTH * 0.5, site.z),
			Vector2(site.x, site.z), 4.0, "Driveway%d" % int(site.z))
	var trunk := _campus_group(parent, tag + "TrunkRoad")
	var edge := x - signf(x) * AVENUE_WIDTH * 0.5
	EmpireLayer.paved_road(trunk, apron_end, Vector2(edge, apron_end.y), TRUNK_WIDTH, tag + "Trunk")
	_road_bollards(trunk, apron_end, Vector2(edge, apron_end.y), TRUNK_WIDTH * 0.5 + 0.4)


## Evenly spaced emissive light bollards along both edges of a road (two MultiMeshes: posts and glowing caps).
static func _road_bollards(parent: Node3D, from: Vector2, to: Vector2, offset: float) -> void:
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var count := int(floor(from.distance_to(to) / 14.0))
	if count < 1:
		return
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.12
	post_mesh.bottom_radius = 0.14
	post_mesh.height = 0.9
	post_mesh.radial_segments = 6
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.16
	cap_mesh.bottom_radius = 0.16
	cap_mesh.height = 0.1
	cap_mesh.radial_segments = 6
	var posts := MultiMesh.new()
	posts.transform_format = MultiMesh.TRANSFORM_3D
	posts.mesh = post_mesh
	posts.instance_count = count * 2
	var caps := MultiMesh.new()
	caps.transform_format = MultiMesh.TRANSFORM_3D
	caps.mesh = cap_mesh
	caps.instance_count = count * 2
	for i in count:
		var p := from + dir * (7.0 + i * 14.0)
		for k in 2:
			var q := p + side * offset * (1.0 if k == 0 else -1.0)
			posts.set_instance_transform(i * 2 + k, Transform3D(Basis.IDENTITY, Vector3(q.x, 0.45, q.y)))
			caps.set_instance_transform(i * 2 + k, Transform3D(Basis.IDENTITY, Vector3(q.x, 0.95, q.y)))
	var post_node := MultiMeshInstance3D.new()
	post_node.name = "RoadBollards"
	post_node.multimesh = posts
	post_node.material_override = Gfx.mat(Color("#2a2e34"), 0.7)
	post_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(post_node)
	var cap_node := MultiMeshInstance3D.new()
	cap_node.name = "RoadBollardLights"
	cap_node.multimesh = caps
	cap_node.material_override = Gfx.unshaded(Color("#ffd29a"), 0.95)
	cap_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cap_node)


## Fleet Support Motor Pool: marked parking bays, floodlight masts, a parked dropship and rover aligned in parallel.
static func _campus_motor_pool(parent: Node3D) -> void:
	var slab := EmpireLayer.paved_slab(parent, Vector3.ZERO, MOTOR_POOL_HALF, Color("#ffb768"), "MotorPoolSlab")
	var top := EmpireLayer.SLAB_TOP
	var line := Color("#e8ecef")
	# Bay centres (slab-local): large dropship bay west, rover bay east, both running along z.
	var bays := [[Vector2(-5.5, 0.0), Vector2(12.5, 16.0)], [Vector2(7.5, 0.0), Vector2(6.0, 9.0)]]
	for bay: Array in bays:
		var c: Vector2 = bay[0]
		var hs: Vector2 = bay[1] * 0.5
		for sz in [-1.0, 1.0]:
			slab.add_child(Gfx.box(Vector3(hs.x * 2.0, 0.012, 0.14), line, Vector3(c.x, top + 0.007, c.y + sz * hs.y)))
		for sx in [-1.0, 1.0]:
			slab.add_child(Gfx.box(Vector3(0.14, 0.012, hs.y * 2.0), line, Vector3(c.x + sx * hs.x, top + 0.007, c.y)))
	for sx in [-1.0, 1.0]:
		var mast := Node3D.new()
		mast.name = "FloodlightMast"
		mast.position = Vector3(sx * (MOTOR_POOL_HALF.x - 0.9), top, 0.0)
		slab.add_child(mast)
		mast.add_child(Gfx.cyl(0.14, 7.0, Color("#3a3f46"), Vector3(0, 3.5, 0), 8))
		var head := Gfx.box(Vector3(0.9, 0.35, 0.5), Color("#fff1c9"), Vector3(0, 7.1, 0), 1.6)
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mast.add_child(head)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(-sx * 0.6, 6.8, 0)
		lamp.light_color = Color("#fff1d0")
		lamp.light_energy = 0.8
		lamp.omni_range = 18.0
		lamp.shadow_enabled = false
		mast.add_child(lamp)
	var sign_label := Gfx.label("FLEET SUPPORT MOTOR POOL", Color("#ffb768"), 40, 6)
	sign_label.pixel_size = 0.012
	sign_label.position = Vector3(0, top + 3.2, -MOTOR_POOL_HALF.y + 0.6)
	slab.add_child(sign_label)
	var drop := BlenderVisualUpgrades.place(parent, "vehicles/helion_dropship.glb",
		Vector3(-5.5, top, 0.0), 14.0, 0.0)
	_tag_model(drop, "ParkedDropship", slab)
	var rover := BlenderVisualUpgrades.place(parent, "vehicles/helion_rover.glb",
		Vector3(7.5, top, 0.0), 6.0, 0.0)
	_tag_model(rover, "ParkedRover", slab)


## Axis-aligned/rotated paved rectangles (centre, half extents, yaw) of every slab and road under the given roots.
static func collect_footprints(roots: Array) -> Array:
	var out: Array = []
	for root in roots:
		if root == null:
			continue
		# Walk with accumulated transforms so slabs/roads inside positioned groups report their world-plan position.
		var stack: Array = [[root, Transform3D.IDENTITY if not (root is Node3D) else (root as Node3D).transform]]
		while not stack.is_empty():
			var item: Array = stack.pop_back()
			var n: Node = item[0]
			var xf: Transform3D = item[1]
			for child in n.get_children():
				stack.append([child, xf * (child as Node3D).transform if child is Node3D else xf])
			if not (n is Node3D):
				continue
			if n.has_meta("footprint_half"):
				var h: Vector2 = n.get_meta("footprint_half")
				out.append({"name": n.name, "center": Vector2(xf.origin.x, xf.origin.z), "half": h, "yaw": 0.0, "kind": "slab"})
			elif n.has_meta("road_half"):
				var c := Vector2(xf.origin.x, xf.origin.z)
				out.append({"name": n.name, "center": c, "half": n.get_meta("road_half"),
					"yaw": float(n.get_meta("yaw")) + xf.basis.get_euler().y - (n as Node3D).rotation.y, "kind": "road"})
	return out


## Pebbles (NearbyRock*) that fall on a paved footprint are nudged just outside it (construction-site clearing).
static func clear_site_props(scene_root: Node, footprints: Array) -> void:
	var rocks := scene_root.find_child("Rocks", true, false)
	if rocks == null:
		return
	for rock in rocks.get_children():
		if not (rock is MeshInstance3D) or not String(rock.name).begins_with("NearbyRock"):
			continue
		var radius := 1.0
		if rock.mesh != null:
			var box: AABB = rock.mesh.get_aabb()
			radius = maxf(box.size.x, box.size.z) * 0.5 * maxf(rock.scale.x, rock.scale.z) + 0.8
		for _pass in 3:
			for fp: Dictionary in footprints:
				var half: Vector2 = fp["half"]
				var rel: Vector2 = Vector2(rock.position.x, rock.position.z) - Vector2(fp["center"])
				var local: Vector2 = rel.rotated(float(fp["yaw"]))
				var gap := Vector2(half.x + radius - absf(local.x), half.y + radius - absf(local.y))
				if gap.x <= 0.0 or gap.y <= 0.0:
					continue
				var push_local := Vector2.ZERO
				if gap.x < gap.y:
					push_local.x = signf(local.x if local.x != 0.0 else 1.0) * gap.x
				else:
					push_local.y = signf(local.y if local.y != 0.0 else 1.0) * gap.y
				var push := push_local.rotated(-float(fp["yaw"]))
				rock.position.x += push.x
				rock.position.z += push.y


static func weather_pad(surface: MeshInstance3D, repeats: float, strength: float) -> void:
	if _weather_normal == null:
		_weather_normal = preload("res://assets/textures/planets/weather_noise.tres").duplicate() as NoiseTexture2D
		_weather_normal.as_normal_map = true
		_weather_normal.bump_strength = 5.0
	var original := surface.material_override as StandardMaterial3D
	var weathered := original.duplicate() as StandardMaterial3D
	weathered.normal_enabled = true
	weathered.normal_texture = _weather_normal
	weathered.normal_scale = strength
	weathered.uv1_scale = Vector3(repeats, repeats, repeats)
	weathered.roughness = 0.95
	surface.material_override = weathered


static func add_apron_fixture(parent: Node3D, point: Vector3, color: Color) -> OmniLight3D:
	var fixture := Gfx.box(Vector3(0.48, 0.12, 0.32), Color("#38383a"), point)
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fixture)
	var lens := Gfx.box(Vector3(0.36, 0.025, 0.21), color, Vector3.UP * 0.07)
	lens.material_override = Gfx.unshaded(color)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fixture.add_child(lens)
	var light := OmniLight3D.new()
	light.position.y = 0.32
	light.light_color = color
	light.light_energy = 0.18
	light.omni_range = 4.5
	fixture.add_child(light)
	return light


# ---------------------------------------------------------------------------
# Editable scene structures
# Every launchpad structure lives in scenes/levels/PlanetAEnvironment.tscn
# (baked by tools/bake_planet_a_scene.gd). setup() only BINDS to those nodes and
# reads their transforms, so dragging a piece in the Godot editor moves its
# gameplay point too. A group that is missing/empty is rebuilt in memory by the
# same _build_* function the bake tool uses (so there is exactly one builder).
# ---------------------------------------------------------------------------
var editable_root: Node3D
var bake_mode := false   # true while tools/bake_planet_a_scene.gd writes the scene
var shop_pos := SHOP
var shop_computer := SHOP_COMPUTER
var shop_desk := SHOP_DESK
var launch_desk := LAUNCH_DESK
var board_base := BOARD_BASE
var shop_footprint := SHOP_FOOTPRINT
var service_tray_origin := SERVICE_TRAY_ORIGIN
var crane_bases: Array = CRANE_BASES.duplicate()
var elevator_sites: Array = ELEVATOR_SITES.duplicate()
var gse_dispatches: Array = GSE_DISPATCHES.duplicate()
var gse_pickups: Array = GSE_PICKUPS.duplicate()
var rack_centers: Array = Sim.RACKS.duplicate(true)      # [x, z] per crew rack
var console_points: Dictionary = CONSOLES.duplicate()
var water_ponds: Array = WATER_PONDS.duplicate(true)     # [x, z, radius_x, radius_z]
var rival_points: Array = [null, null, null, null]


static func _add(parent: Node, child: Node, node_name: String) -> Node:
	child.name = node_name
	parent.add_child(child)
	return child


# Position of `node` expressed in `root` space (tree independent).
static func _node_pos(node: Node3D, root: Node) -> Vector3:
	var p := node.position
	var cur := node.get_parent()
	while cur != null and cur != root and cur is Node3D:
		p = (cur as Node3D).transform * p
		cur = cur.get_parent()
	return p


# Returns the group at `path` (creating empty Node3D parents if needed) and fills
# it with `builder` when it has no children yet.
func _ensure_group(root: Node3D, path: String, builder: Callable) -> Node3D:
	var grp := root.get_node_or_null(path) as Node3D
	if grp == null:
		grp = root
		for part in path.split("/"):
			var nxt := grp.get_node_or_null(part) as Node3D
			if nxt == null:
				nxt = Node3D.new()
				nxt.name = part
				grp.add_child(nxt)
			grp = nxt
	if grp.get_child_count() == 0:
		builder.call(grp)
	return grp


func _setup_materials(gfx_script: GDScript) -> void:
	_pbr_cliff = _optional_pbr_material(gfx_script, "cliff", 0.22, Color.WHITE, 0.0)
	_pbr_cladding = _optional_pbr_material(gfx_script, "metal", 0.35, Color("#e8ecef"), 0.38)
	_pbr_dark_steel = _optional_pbr_material(gfx_script, "metal", 0.55, Color("#3a424d"), 0.78)


# Existing hand-edited nodes (racks, consoles, gantry, rival pads): read their
# transforms and keep the collision footprint markers glued to them.
func _bind_existing_layout(editable: Node3D) -> void:
	var pairs := {
		"Rack0": "PartRacks/Rack0", "Rack1": "PartRacks/Rack1", "Rack2": "PartRacks/Rack2", "Rack3": "PartRacks/Rack3",
		"ConsoleEngine": "SystemCheckConsoles/EngineConsole", "ConsolePower": "SystemCheckConsoles/PowerConsole",
		"ConsolePressure": "SystemCheckConsoles/PressureConsole",
		"GantryPost0": "LaunchPad/Gantry/GantryPost0", "GantryPost1": "LaunchPad/Gantry/GantryPost1"}
	var footprints := editable.get_node_or_null("CollisionFootprints")
	for r in 4:
		var rack := editable.get_node_or_null("PartRacks/Rack%d" % r) as Node3D
		if rack != null:
			var rp := _node_pos(rack, editable)
			rack_centers[r] = [rp.x, rp.z]
	var console_nodes := {"engine": "EngineConsole", "power": "PowerConsole", "pressure": "PressureConsole"}
	for type in console_nodes:
		var console := editable.get_node_or_null("SystemCheckConsoles/" + console_nodes[type]) as Node3D
		if console != null:
			var cp := _node_pos(console, editable)
			console_points[type] = Vector3(cp.x, 0, cp.z)
	for i in range(1, 4):
		var pad := editable.get_node_or_null("RivalLandingPads/Rival%dPad" % i) as Node3D
		if pad != null:
			var pp := _node_pos(pad, editable)
			rival_points[i] = Vector3(pp.x, 0, pp.z)
			pad.scale *= Vector3(ShipModel.VESSEL_SCALE, 1.0, ShipModel.VESSEL_SCALE)
	if footprints == null:
		return
	for marker in footprints.get_children():
		var m := marker as Node3D
		var source: Node3D = null
		if pairs.has(String(marker.name)):
			source = editable.get_node_or_null(pairs[String(marker.name)]) as Node3D
		var pt: Vector3 = _node_pos(source, editable) if source != null else m.position
		var footprint: Vector2 = marker.get_meta("footprint", Vector2.ZERO)
		blockers.append(Rect2(pt.x - footprint.x * 0.5, pt.z - footprint.y * 0.5, footprint.x, footprint.y))


# Builds (or binds to) every structure group. Called by setup() and by the bake tool.
func _ensure_structures(editable: Node3D) -> void:
	editable_root = editable
	_ensure_group(editable, "Environment/ApronLights", _build_apron_lights)
	_ensure_group(editable, "Environment/SidePonds", _build_side_ponds)
	_ensure_group(editable, "Stations/Cargo", _build_cargo_station)
	if not delivery:
		_ensure_group(editable, "Buildings/PartsShop", _build_shop)
		_ensure_group(editable, "Cranes/Pedestals", _build_crane_pedestals)
		_ensure_group(editable, "Cranes/Elevators", _build_crane_elevators)
		_ensure_group(editable, "Cranes/Conveyors", _build_gse_conveyors)
		_ensure_group(editable, "Cranes/PickupBays", _build_gse_bays)
		_ensure_group(editable, "Cranes/ScannerArches", _build_gse_arches)
		_ensure_group(editable, "BoardingRig", _build_board_rig)
		_ensure_group(editable, "Stations/PropellantService", _build_propellant_service)
		_ensure_group(editable, "Stations/MissionDesk", _build_mission_desk)
	_bind_apron_lights(editable.get_node("Environment/ApronLights"))
	_bind_side_ponds(editable.get_node("Environment/SidePonds"))
	_bind_cargo_station(editable.get_node("Stations/Cargo"))
	for path in ["Buildings", "Cranes", "BoardingRig", "Stations/PropellantService"]:
		var group := editable.get_node_or_null(path) as Node3D
		if group != null:
			group.visible = not delivery
	if not delivery:
		_bind_shop(editable.get_node("Buildings/PartsShop"))
		_bind_crane_pedestals(editable.get_node("Cranes/Pedestals"))
		_bind_crane_elevators(editable.get_node("Cranes/Elevators"))
		_bind_gse(editable)
		_bind_board_rig(editable.get_node("BoardingRig"))
		_bind_mission_desk(editable.get_node("Stations/MissionDesk"))
		var tray := editable.get_node("Stations/PropellantService") as Node3D
		service_tray_origin = _node_pos(tray, editable)
	# The fence reads every footprint above, so it is built last.
	_ensure_group(editable, "Infrastructure/Fence", _build_apron_railing)


# ---------------------------------------------------------------- apron lights
func _build_apron_lights(grp: Node3D) -> void:
	for i in 8:
		var angle := (i + 0.5) * TAU / 8.0
		var light := add_apron_fixture(grp, Vector3(cos(angle) * 20.2, 0.18, sin(angle) * 20.2), Color("#ffd39a"))
		light.get_parent().name = "ApronLight%d" % i


func _bind_apron_lights(grp: Node3D) -> void:
	apron_lights.clear()
	for node in grp.find_children("*", "OmniLight3D", true, false):
		apron_lights.append(node as OmniLight3D)


# ---------------------------------------------------------------- side ponds
func _build_side_ponds(grp: Node3D) -> void:
	if not ResourceLoader.exists("res://assets/shaders/hopeful_water.gdshader"):
		return
	var water_mat := Gfx.create_hopeful_water_mat()
	var bank_mat := Gfx.mat(Color("#5a7e4a"), 0.90)
	var shore_mat := StandardMaterial3D.new()
	shore_mat.albedo_color = Color("#8f9466")
	shore_mat.roughness = 0.95
	var trunk_mat := Gfx.mat(Color("#6b4f36"), 0.9)
	var leaf_mat := Gfx.mat(Color("#2f9a52"), 0.85)
	for i in WATER_PONDS.size():
		var spec: Array = WATER_PONDS[i]
		var cx: float = spec[0]
		var cz: float = spec[1]
		var rx: float = spec[2]
		var rz: float = spec[3]
		var pond := Node3D.new()
		pond.name = "Pond%d" % i
		pond.position = Vector3(cx, 0, cz)
		pond.set_meta("radius", Vector2(rx, rz))   # gameplay water radius (x, z) in metres
		grp.add_child(pond)
		var water_mesh := PlaneMesh.new()
		water_mesh.size = Vector2(rx * 2.0, rz * 2.0)
		_add(pond, Gfx.mesh(water_mesh, water_mat, Vector3(0, 0.045, 0), false), "Water")
		var rim_mesh := CylinderMesh.new()
		rim_mesh.top_radius = 1.0
		rim_mesh.bottom_radius = 1.0
		rim_mesh.height = 0.02
		rim_mesh.radial_segments = 40
		var rim := Gfx.mesh(rim_mesh, shore_mat, Vector3(0, 0.02, 0), false)
		rim.scale = Vector3(rx * 1.12, 1.0, rz * 1.12)
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(pond, rim, "Shore")
		var away := Vector2(cx, cz).normalized()
		var base_a := atan2(away.y, away.x)
		for t in 3:
			var ta := base_a + (t - 1) * 0.45
			var tp := Vector3(cos(ta) * rx * 1.25, 0.0, sin(ta) * rz * 1.25)
			_lakeside_tree(pond, tp, 0.9 + 0.15 * t, trunk_mat, leaf_mat).name = "Tree%d" % t
		var rng := RandomNumberGenerator.new()
		rng.seed = 4100 + i * 97
		for s in 6:
			var a := rng.randf_range(0.0, TAU)
			var sx := cos(a) * rx * rng.randf_range(0.86, 0.98)
			var sz := sin(a) * rz * rng.randf_range(0.86, 0.98)
			var stone := Gfx.rock(rng.randf_range(0.45, 1.15), Color("#8fa0ab"), rng, 0.42)
			stone.material_override = bank_mat if s % 3 == 0 else Gfx.mat(Color("#8c9ca6"), 0.88)
			stone.position = Vector3(sx, 0.02, sz)
			stone.rotation.y = rng.randf_range(0.0, TAU)
			stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_add(pond, stone, "Stone%d" % s)


func _lakeside_tree(parent: Node3D, pos: Vector3, scale_f: float, trunk_mat: Material, leaf_mat: Material) -> Node3D:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * scale_f
	parent.add_child(tree)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.38
	trunk.height = 2.6
	_add(tree, Gfx.mesh(trunk, trunk_mat, Vector3(0, 1.3, 0), true), "Trunk")
	for tier in 2:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 2.1 - tier * 0.65
		cone.height = 2.6 - tier * 0.5
		cone.radial_segments = 10
		_add(tree, Gfx.mesh(cone, leaf_mat, Vector3(0, 3.0 + tier * 1.5, 0), true), "Foliage%d" % tier)
	return tree


func _bind_side_ponds(grp: Node3D) -> void:
	water_ponds.clear()
	var sun := Universe.SOLAR_VECTOR.normalized()
	for pond in grp.get_children():
		var node := pond as Node3D
		if node == null:
			continue
		var radius: Vector2 = node.get_meta("radius", Vector2(12.0, 12.0))
		var p := _node_pos(node, editable_root)
		water_ponds.append([p.x, p.z, radius.x * absf(node.scale.x), radius.y * absf(node.scale.z)])
		var water := node.get_node_or_null("Water") as MeshInstance3D
		if water != null and water.material_override is ShaderMaterial:
			_water_material = water.material_override as ShaderMaterial
			_water_material.set_shader_parameter("sun_direction", sun)


# ---------------------------------------------------------------- cargo hatch
func _build_cargo_station(grp: Node3D) -> void:
	var hatch := Gfx.ring(2.6, 0.3, Color("#9cdeb1"), 0.75)
	hatch.position = CARGO_HATCH + Vector3(0, 0.1, 0)
	_add(grp, hatch, "AftCargoHatch")
	var hl := Gfx.label("AFT CARGO HATCH", Color("#9cdeb1"), 40)
	hl.position = CARGO_HATCH + Vector3(0, 3.2, 0)
	_add(grp, hl, "HatchLabel")


func _bind_cargo_station(grp: Node3D) -> void:
	for path in ["AftCargoHatch", "HatchLabel"]:
		var marker := grp.get_node_or_null(path) as Node3D
		if marker != null:
			marker.position.z = CARGO_HATCH.z


# ---------------------------------------------------------------- propellant service tray
func _build_propellant_service(grp: Node3D) -> void:
	grp.position = SERVICE_TRAY_ORIGIN
	preload("res://scripts/model_detail.gd").surroundings(grp, Vector3.ZERO)
	var tray := grp.get_child(grp.get_child_count() - 1)
	tray.name = "Tray"


# ---------------------------------------------------------------- parts shop
func _build_shop(grp: Node3D) -> void:
	grp.position = SHOP
	var white := Color("#f8fafc")
	var slate := Color("#26364a")
	var cyan := Color("#35d5ed")
	_add(grp, Gfx.box(Vector3(34, 0.1, 24), Color("#f3f5f8"), Vector3(0, 0.05, 1)), "Floor")
	# Two batches share a low-profile box mesh size, one for each checkerboard color.
	var tile_size := Vector2(34.0 / 12.0, 24.0 / 8.0)
	for parity in 2:
		var tile := BoxMesh.new()
		tile.size = Vector3(tile_size.x - 0.04, 0.02, tile_size.y - 0.04)
		tile.material = Gfx.mat(Color("#e8edf3") if parity == 0 else white)
		var tiles := MultiMesh.new()
		tiles.transform_format = MultiMesh.TRANSFORM_3D
		tiles.mesh = tile
		tiles.instance_count = 48
		var index := 0
		for row in 8:
			for col in range((row + parity) % 2, 12, 2):
				var center := Vector3(-17 + (col + 0.5) * tile_size.x, 0.11, -11 + (row + 0.5) * tile_size.y)
				tiles.set_instance_transform(index, Transform3D(Basis.IDENTITY, center))
				index += 1
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = tiles
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(grp, batch, "FloorTiles%d" % parity)
	var cladding := Hardware.material(Color("#e2e8ee"), 0.08, 0.72)
	var frame := Hardware.material(Color("#3a4652"), 0.35, 0.6)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.14, 0.18, 0.38)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.65
	glass.roughness = 0.08
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var walls := shop_wall_rects()
	var wall_names := ["WallBack", "WallWest", "WallEast", "WallFrontLeft", "WallFrontRight"]
	var wall_positions := [PI, -PI / 2.0, PI / 2.0, 0.0, 0.0]
	for i in walls.size():
		var center := walls[i].get_center()
		var facade := Node3D.new()
		facade.position = Vector3(center.x, 0, center.y)
		facade.rotation.y = wall_positions[i]
		_add(grp, facade, wall_names[i])
		if i == 0:
			_shop_wall_panel(facade, Vector3(34, 10, 0.5), Vector3(0, 5, 0), white, cladding)
		elif i <= 2:
			_shop_window_wall(facade, 23.0, 1.0, 15.0, 6, white, cladding, glass, frame)
		else:
			_shop_window_wall(facade, 12.5, 0.5, 10.0, 4, white, cladding, glass, frame)
	var header := Node3D.new()
	header.position = Vector3(0, 8.25, 12.75)
	_add(grp, header, "FrontHeader")
	_shop_wall_panel(header, Vector3(9, 3.5, 0.5), Vector3.ZERO, white, cladding)
	_add(grp, Gfx.box(Vector3(34, 0.4, 24), Color.WHITE, Vector3(0, 10.2, 1)), "Roof")
	_shop_exterior_hardware(_add(grp, Node3D.new(), "ExteriorHardware") as Node3D, cladding, frame)
	for i in 3:
		var light := OmniLight3D.new()
		light.position = Vector3(-10 + i * 10, 8.8, 1)
		light.light_energy = 2.2
		light.omni_range = 18.0
		_add(grp, light, "ShopLight%d" % i)
	var signs := ["SignFront", "SignBack"]
	var sign_z := [13.0, -10.5]
	for k in 2:
		var sign := Gfx.label("PARTS SHOP · HOLOGRAPHIC BAY", slate, 64, 0)
		sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sign.pixel_size = 0.007
		sign.position = Vector3(0, 8.4, sign_z[k] + 0.03)
		_add(grp, sign, signs[k])
		_add(grp, Gfx.box(Vector3(8.6, 0.07, 0.04), cyan, Vector3(0, 7.9, sign_z[k] + 0.03), 0.8), signs[k] + "Accent")
	# Holographic terminal anchor: the kiosk is spawned here at runtime (live hologram).
	var terminal := Marker3D.new()
	terminal.position = SHOP_COMPUTER - SHOP
	_add(grp, terminal, "Terminal")
	var ring := Gfx.ring(2.5, 0.16, cyan)
	ring.position = Vector3(0, 0.15, 0)
	_add(terminal, ring, "Ring")
	var label := Gfx.label("HOLOGRAPHIC TERMINAL · PRESS E", cyan, 34, 6)
	label.position = Vector3(0, 5.7, 0)
	_add(terminal, label, "Label")
	# Desk pad that closes the shop and releases assembly.
	var desk := Marker3D.new()
	desk.position = SHOP_DESK - SHOP
	_add(grp, desk, "ShopDesk")
	var desk_ring := Gfx.ring(2.2, 0.35, Color("#9cdeb1"))
	desk_ring.position = Vector3(0, 0.15, 0)
	_add(desk, desk_ring, "Ring")
	var desk_label := Gfx.label("", Color("#9cdeb1"), 40, 8)
	desk_label.position = Vector3(0, 3.2, 0)
	_add(desk, desk_label, "Label")


# Wall footprints relative to the shop origin.
static func shop_wall_rects() -> Array[Rect2]:
	return [
		Rect2(-17, -11, 34, 0.5),
		Rect2(-17, -10.5, 1, 23),
		Rect2(16, -10.5, 1, 23),
		Rect2(-17, 12.5, 12.5, 0.5),
		Rect2(4.5, 12.5, 12.5, 0.5),
	]


func _bind_shop(grp: Node3D) -> void:
	shop_pos = _node_pos(grp, editable_root)
	shop_footprint = Rect2(shop_pos.x - 17.0, shop_pos.z - 11.0, 34.0, 24.0)
	var terminal := grp.get_node_or_null("Terminal") as Node3D
	shop_computer = shop_pos + (terminal.position if terminal != null else SHOP_COMPUTER - SHOP)
	var desk := grp.get_node_or_null("ShopDesk") as Node3D
	shop_desk = shop_pos + (desk.position if desk != null else SHOP_DESK - SHOP)
	if desk != null:
		shop_desk_ring = desk.get_node_or_null("Ring") as MeshInstance3D
		shop_desk_label = desk.get_node_or_null("Label") as Label3D
	if shop_desk_ring == null or shop_desk_label == null:
		shop_desk_ring = Gfx.ring(2.2, 0.35, Color("#9cdeb1"))
		shop_desk_ring.position = shop_desk + Vector3(0, 0.15, 0)
		add_child(shop_desk_ring)
		shop_desk_label = Gfx.label("", Color("#9cdeb1"), 40, 8)
		shop_desk_label.position = shop_desk + Vector3(0, 3.2, 0)
		add_child(shop_desk_label)
	for wall in shop_wall_rects():
		blockers.append(Rect2(shop_pos.x + wall.position.x, shop_pos.z + wall.position.y, wall.size.x, wall.size.y))
	if ResourceLoader.exists("res://scripts/shop_kiosk.gd"):
		var kiosk_script = load("res://scripts/shop_kiosk.gd")
		shop_kiosk_node = kiosk_script.build()
		shop_kiosk_node.position = shop_computer
		add_child(shop_kiosk_node)
		blockers.append(Rect2(shop_computer.x - 3.3, shop_computer.z - 1.4, 6.6, 2.8))


func _shop_wall_panel(parent: Node3D, size: Vector3, center: Vector3, white: Color,
		cladding: Material) -> void:
	var skin := 0.08
	_add(parent, Gfx.box(size - Vector3(0, 0, skin), white, center - Vector3(0, 0, skin * 0.5)), "Core")
	var panel := BoxMesh.new()
	panel.size = Vector3(size.x, size.y, skin)
	_add(parent, Gfx.mesh(panel, cladding, center + Vector3(0, 0, (size.z - skin) * 0.5)), "Skin")


func _shop_window_wall(parent: Node3D, width: float, depth: float, opening: float, columns: int,
		white: Color, cladding: Material, glass: Material, frame: Material) -> void:
	var sill := 2.2
	var lintel := 7.4
	var height := lintel - sill
	var midpoint := (lintel + sill) * 0.5
	var jamb := (width - opening) * 0.5
	var parts := _add(parent, Node3D.new(), "Panels") as Node3D
	_shop_wall_panel(_add(parts, Node3D.new(), "Sill") as Node3D, Vector3(width, sill, depth), Vector3(0, sill * 0.5, 0), white, cladding)
	_shop_wall_panel(_add(parts, Node3D.new(), "Lintel") as Node3D, Vector3(width, 10.0 - lintel, depth),
		Vector3(0, (10.0 + lintel) * 0.5, 0), white, cladding)
	for side in [-1.0, 1.0]:
		_shop_wall_panel(_add(parts, Node3D.new(), "Jamb") as Node3D, Vector3(jamb, height, depth),
			Vector3(side * (opening + jamb) * 0.5, midpoint, 0), white, cladding)
	var pane := QuadMesh.new()
	pane.size = Vector2(opening, height)
	_add(parent, Gfx.mesh(pane, glass, Vector3(0, midpoint, 0), false), "Glass")
	var horizontal := BoxMesh.new()
	horizontal.size = Vector3(opening + 0.14, 0.14, depth + 0.04)
	for y in [sill, midpoint, lintel]:
		_add(parent, Gfx.mesh(horizontal, frame, Vector3(0, y, 0)), "FrameRail")
	var vertical := BoxMesh.new()
	vertical.size = Vector3(0.14, height, depth + 0.04)
	for i in range(columns + 1):
		var x := lerpf(-opening * 0.5, opening * 0.5, float(i) / columns)
		_add(parent, Gfx.mesh(vertical, frame, Vector3(x, midpoint, 0)), "Mullion")


func _shop_exterior_hardware(parent: Node3D, cladding: Material, frame: Material) -> void:
	var steel_color := Color("#758087")
	var steel := _pbr_dark_steel if _pbr_dark_steel != null else Hardware.material(steel_color, 0.8, 0.35)
	var housing_material := _pbr_dark_steel if _pbr_dark_steel != null else cladding
	var west := -17.0
	# Run the conduit below the west windows, with risers beside the window bay.
	var pipe := Gfx.cyl(0.10, 19.0, steel_color, Vector3(west - 0.23, 1.55, 1), 12)
	pipe.rotation.x = PI / 2.0
	pipe.material_override = steel
	_add(parent, pipe, "Conduit")
	var bracket := BoxMesh.new()
	bracket.size = Vector3(0.42, 0.20, 0.24)
	for z in [-8.5, -4.0, 1.0, 6.0, 10.5]:
		_add(parent, Gfx.mesh(bracket, frame, Vector3(west - 0.14, 1.55, z)), "Bracket")
	for z in [-8.5, 10.5]:
		var riser := Gfx.cyl(0.10, 6.8, steel_color, Vector3(west - 0.23, 4.95, z), 12)
		riser.material_override = steel
		_add(parent, riser, "Riser")
		for y in [3.4, 5.5, 7.6]:
			_add(parent, Gfx.mesh(bracket, frame, Vector3(west - 0.14, y, z)), "RiserBracket")
	var housing := BoxMesh.new()
	housing.size = Vector3(3.6, 0.9, 2.55)
	var slat := BoxMesh.new()
	slat.size = Vector3(2.18, 0.065, 0.065)
	for x in [-8.0, 8.0]:
		var unit := _add(parent, Node3D.new(), "RoofFan") as Node3D
		unit.position = Vector3(x, 10.4, -3.5)
		_add(unit, Gfx.mesh(housing, housing_material, Vector3.UP * 0.45), "Housing")
		var fan := Gfx.cyl(0.97, 0.16, Color("#303b44"), Vector3.UP * 0.97, 24)
		fan.material_override = frame
		_add(unit, fan, "Fan")
		for i in range(-5, 6):
			_add(unit, Gfx.mesh(slat, steel, Vector3(0, 1.08, i * 0.19)), "Slat")


# ---------------------------------------------------------------- crane pedestals
func _build_crane_pedestals(grp: Node3D) -> void:
	for i in 4:
		var color := Sim.role_color(i)
		var pedestal := Node3D.new()
		pedestal.name = "Pedestal%d" % i
		pedestal.position = CRANE_BASES[i]
		grp.add_child(pedestal)
		Hardware.cylinder(pedestal, 2.0, .35, Vector3(0, .18, 0), Color("#303940")).name = "Footing"
		Hardware.cylinder(pedestal, .95, 6.6, Vector3(0, 3.5, 0), Color("#58636a")).name = "Column"
		Hardware.cylinder(pedestal, 1.5, .5, Vector3(0, 6.8, 0), color).name = "Collar"


func _bind_crane_pedestals(grp: Node3D) -> void:
	for i in 4:
		var pedestal := grp.get_node_or_null("Pedestal%d" % i) as Node3D
		if pedestal != null:
			var p := _node_pos(pedestal, editable_root)
			crane_bases[i] = Vector3(p.x, 0, p.z)
	_collect_crane_view_meshes(grp)


# ---------------------------------------------------------------- crane elevators
func _build_crane_elevators(grp: Node3D) -> void:
	var steel := Color("#394853")
	for i in 4:
		var color := Sim.role_color(i)
		var side := _crane_side(i)
		var site: Vector3 = ELEVATOR_SITES[i]
		var tower := Node3D.new()
		tower.name = "Elevator%d" % i
		tower.position = Vector3(site.x, 0, site.z)
		grp.add_child(tower)
		# Moving platform (rises to the cab at runtime; only its Y changes).
		var platform := _add(tower, Node3D.new(), "Platform") as Node3D
		_add(platform, Gfx.box(Vector3(ELEVATOR_SIZE.x, 0.38, ELEVATOR_SIZE.y), steel, Vector3(0, -0.19, 0)), "Deck")
		_add(platform, Gfx.box(Vector3(ELEVATOR_SIZE.x - 0.4, 0.08, 0.2), color, Vector3(0, 0.04, 0), 2.5), "Stripe")
		var sign_label := Gfx.label("%s\nCRANE ELEVATOR" % Sim.SPECIALISTS[i]["name"], color, 44)
		sign_label.position = Vector3(0, 3.2, 0)
		_add(platform, sign_label, "Sign")
		# Guide rails.
		var rails := _add(tower, Node3D.new(), "GuideRails") as Node3D
		for x in [-2.85, 2.85]:
			_add(rails, Gfx.box(Vector3(0.24, ELEVATOR_HEIGHT + 1.0, 0.24), steel, Vector3(x, ELEVATOR_HEIGHT * 0.5, 0)), "Rail")
			_add(rails, Gfx.box(Vector3(0.1, ELEVATOR_HEIGHT + 1.0, 0.1), color, Vector3(x * 1.04, ELEVATOR_HEIGHT * 0.5, 0), 2.0), "RailStrip")
		# Operator cab at the top of the shaft.
		var cab := _add(tower, Node3D.new(), "Cab") as Node3D
		cab.position = Vector3(0, ELEVATOR_HEIGHT, 0)
		_add(cab, Gfx.box(Vector3(ELEVATOR_SIZE.x, 0.45, ELEVATOR_SIZE.y), steel, Vector3(0, -0.225, 0)), "Deck")
		_add(cab, Gfx.box(Vector3(ELEVATOR_SIZE.x, 0.1, 0.2), color, Vector3(0, 0.05, ELEVATOR_SIZE.y * 0.5 - 0.1), 2.0), "Stripe")
		for x in [-2.8, 2.8]:
			_add(cab, Gfx.box(Vector3(0.12, 0.12, ELEVATOR_SIZE.y), steel, Vector3(x, 1.15, 0)), "TopRail")
			for z in [-2.3, 2.3]:
				_add(cab, Gfx.box(Vector3(0.18, 1.2, 0.18), steel, Vector3(x, 0.6, z)), "Post")
		for z in [-2.0, 2.0]:
			_add(cab, Gfx.box(Vector3(0.4, ELEVATOR_HEIGHT, 0.4), steel, Vector3(-side * 2.6, -ELEVATOR_HEIGHT * 0.5, z)), "Support")
		# Control console (faces the ship).
		var console := _add(tower, Node3D.new(), "ControlConsole") as Node3D
		console.position = Vector3(-side * 1.6, ELEVATOR_HEIGHT, 0)
		_add(console, Gfx.box(Vector3(0.9, 1.05, 1.65), steel, Vector3(-side * 0.85, 0.525, 0)), "Body")
		_add(console, Gfx.box(Vector3(0.7, 0.08, 1.35), color, Vector3(-side * 0.85, 1.09, 0), 2.0), "Top")
		var label := Gfx.label("%s\nCRANE %d" % [Sim.SPECIALISTS[i]["name"], i + 1], color, 44)
		label.position = Vector3(-side * 0.85, 2.3, 0)
		_add(console, label, "Label")


func _bind_crane_elevators(grp: Node3D) -> void:
	lifts.clear()
	for i in 4:
		var tower := grp.get_node_or_null("Elevator%d" % i) as Node3D
		if tower == null:
			continue
		var p := _node_pos(tower, editable_root)
		elevator_sites[i] = Vector3(p.x, 0, p.z)
		# The platform only moves in Y, so lift it to the group level where its
		# position is a world position (gameplay compares against it directly).
		var platform := tower.get_node_or_null("Platform") as Node3D
		if platform == null:
			platform = tower.get_meta("platform_ref", null) as Node3D
		elif platform.get_parent() == tower and not bake_mode:
			platform.name = "Platform%d" % i
			platform.reparent(grp, true)
			tower.set_meta("platform_ref", platform)
		if platform == null:
			continue
		platform.position = Vector3(p.x, 0, p.z)
		lifts.append({"platform": platform, "sign": platform.get_node("Sign") as Label3D})
	_collect_crane_view_meshes(grp)


# ---------------------------------------------------------------- GSE conveyor lanes / bays / arches
func _build_gse_conveyors(grp: Node3D) -> void:
	for role in GSE_PICKUPS.size():
		var dispatch: Vector3 = GSE_DISPATCHES[role]
		var pickup: Vector3 = GSE_PICKUPS[role]
		var lane := Node3D.new()
		lane.name = "Lane%d" % role
		grp.add_child(lane)
		var marker := Marker3D.new()
		marker.position = dispatch
		_add(lane, marker, "Dispatch")
		var pts: Array = Hardware._gse_route(dispatch, pickup)
		for i in range(pts.size() - 1):
			var before := lane.get_child_count()
			Hardware._gse_segment(lane, pts[i], pts[i + 1])
			if lane.get_child_count() > before:
				var seg := lane.get_child(lane.get_child_count() - 1)
				seg.name = "Segment%d" % i
				seg.set_meta("length", (pts[i + 1] - pts[i]).length())
		var total: float = Hardware._gse_length(pts)
		var n := maxi(int(total / Hardware.GSE_SLAT_PITCH), 2)
		for i in n:
			var slat: MeshInstance3D = Hardware._gse_box(lane, Vector3(0.9, 0.04, Hardware.GSE_BELT_W - 0.6), pts[0], Color("#15181c"), 0.05)
			slat.name = "Slat%02d" % i
			slat.set_meta("role", role)
			slat.set_meta("dist", i * total / n)
			slat.set_meta("total", total)


func _build_gse_bays(grp: Node3D) -> void:
	for role in GSE_PICKUPS.size():
		var before := grp.get_child_count()
		Hardware._gse_bay(grp, GSE_PICKUPS[role], role, [])
		if grp.get_child_count() > before:
			var bay := grp.get_child(grp.get_child_count() - 1) as Node3D
			bay.name = "Bay%d" % role
			bay.rotation.y = PI * 0.5   # long axis along Z: modules ride nose-first
			bay.set_meta("size", GSE_BAY_SIZE)


func _build_gse_arches(grp: Node3D) -> void:
	for role in GSE_PICKUPS.size():
		var dispatch: Vector3 = GSE_DISPATCHES[role]
		var pickup: Vector3 = GSE_PICKUPS[role]
		var heading := 0.0 if pickup.x >= dispatch.x else PI
		for k in GSE_ARCH_STATIONS.size():
			var station: float = GSE_ARCH_STATIONS[k]
			var at := Vector3(lerpf(dispatch.x, pickup.x, station), 0.0, dispatch.z)
			Hardware._gse_arch(grp, at, heading, Hardware.GSE_ROLE_COLORS[role % Hardware.GSE_ROLE_COLORS.size()])
			var arch := grp.get_child(grp.get_child_count() - 1) as Node3D
			arch.name = "Lane%d_Arch%d" % [role, k]
			arch.scale = GSE_ARCH_SCALE


func _bind_gse(editable: Node3D) -> void:
	gse.clear()
	gse_routes.clear()
	var conveyors := editable.get_node_or_null("Cranes/Conveyors")
	var bay_group := editable.get_node_or_null("Cranes/PickupBays")
	var arch_group := editable.get_node_or_null("Cranes/ScannerArches")
	var paths: Array = []
	var slats: Array = []
	var beacons: Array = []
	var centers: Array = []
	for role in GSE_PICKUPS.size():
		var lane := conveyors.get_node_or_null("Lane%d" % role) if conveyors != null else null
		var bay := bay_group.get_node_or_null("Bay%d" % role) as Node3D if bay_group != null else null
		var marker := lane.get_node_or_null("Dispatch") as Node3D if lane != null else null
		if marker != null:
			gse_dispatches[role] = _node_pos(marker, editable)
		if bay != null:
			var bp := _node_pos(bay, editable)
			gse_pickups[role] = Vector3(bp.x, (GSE_PICKUPS[role] as Vector3).y, bp.z)
		# Conveyor path follows the Segment nodes, so editing them re-routes the cargo.
		var pts: Array = []
		if lane != null:
			for seg in lane.get_children():
				if not String(seg.name).begins_with("Segment") or not seg.has_meta("length"):
					continue
				var s3 := seg as Node3D
				var half: float = float(seg.get_meta("length")) * 0.5
				var dir := Vector3(cos(s3.rotation.y), 0.0, -sin(s3.rotation.y))
				var c := _node_pos(s3, editable)
				if pts.is_empty():
					pts.append(c - dir * half)
				pts.append(c + dir * half)
		if pts.size() < 2:
			pts = Hardware._gse_route(gse_dispatches[role], gse_pickups[role])
		paths.append(pts)
		centers.append(Vector3(gse_pickups[role].x, Hardware.GSE_BELT_TOP, gse_pickups[role].z))
		var curve := Curve3D.new()
		for point in pts:
			curve.add_point(point)
		gse_routes.append(curve)
		if lane != null:
			for slat in lane.get_children():
				if slat is MeshInstance3D and slat.has_meta("role"):
					slats.append(slat)
	for group in [bay_group, arch_group]:
		if group != null:
			for node in group.find_children("*", "MeshInstance3D", true, false):
				if node.has_meta("base_energy"):
					beacons.append(node)
	if conveyors != null and not slats.is_empty():
		gse = {"root": conveyors, "paths": paths, "slats": slats, "beacons": beacons, "bay_centers": centers, "time": 0.0}
		Hardware.tick_gse_delivery(gse, 0.0)


# ---------------------------------------------------------------- mission desk
func _build_mission_desk(grp: Node3D) -> void:
	grp.position = LAUNCH_DESK
	var ring := Gfx.ring(2.2, 0.35, accent)
	ring.position = Vector3(0, 0.15, 0)
	_add(grp, ring, "Ring")
	var label := Gfx.label("MISSION DESK", accent, 40, 8)
	label.position = Vector3(0, 3.2, 0)
	_add(grp, label, "Label")


func _bind_mission_desk(grp: Node3D) -> void:
	var p := _node_pos(grp, editable_root)
	launch_desk = Vector3(p.x, 0, p.z)
	launch_desk_ring = grp.get_node_or_null("Ring") as MeshInstance3D
	launch_desk_label = grp.get_node_or_null("Label") as Label3D
	if launch_desk_ring == null or launch_desk_label == null:
		return
	if not bake_mode:
		launch_desk_ring.visible = false
		launch_desk_label.visible = false


# ---------------------------------------------------------------- boarding elevator
func _build_board_rig(grp: Node3D) -> void:
	grp.position = BOARD_BASE
	var steel := Color("#5b6672")
	var glow := Color("#9cdeb1")
	var tower := _add(grp, Node3D.new(), "Tower") as Node3D
	var post := 0
	for x in [-1.6, 1.6]:
		for z in [-1.6, 1.6]:
			_add(tower, Gfx.box(Vector3(0.3, BOARD_HATCH_Y + 1.5, 0.3), steel, Vector3(x, (BOARD_HATCH_Y + 1.5) * 0.5, z)), "Post%d" % post)
			post += 1
	_add(tower, Gfx.box(Vector3(3.8, 0.3, 3.8), steel, Vector3(0, BOARD_HATCH_Y + 1.5, 0)), "TopFrame")
	var platform := _add(grp, Node3D.new(), "Platform") as Node3D
	_add(platform, Gfx.box(Vector3(3.0, 0.3, 3.0), steel, Vector3(0, -0.15, 0)), "Deck")
	_add(platform, Gfx.box(Vector3(2.6, 0.06, 0.2), glow, Vector3(0, 0.03, 1.3), 2.5), "Stripe")
	# Gantry walkway from the tower top to the hatch on the hull.
	var length := BOARD_BASE.x - 2.4
	var walkway := _add(grp, Node3D.new(), "Walkway") as Node3D
	_add(walkway, Gfx.box(Vector3(length, 0.25, 1.8), steel, Vector3(-length * 0.5, BOARD_HATCH_Y - 0.12, 0)), "Deck")
	_add(walkway, Gfx.box(Vector3(length, 0.08, 0.1), glow, Vector3(-length * 0.5, BOARD_HATCH_Y + 0.95, 0.85), 2.0), "Stripe")
	var label := Gfx.label("CREW BOARDING ELEVATOR", glow, 40, 8)
	label.position = Vector3(0, BOARD_HATCH_Y + 3.2, 0)
	_add(grp, label, "Label")


func _bind_board_rig(grp: Node3D) -> void:
	board_rig = grp
	var p := _node_pos(grp, editable_root)
	board_base = Vector3(p.x, 0, p.z)
	board_hatch = Vector3(2.4, BOARD_HATCH_Y, board_base.z)
	board_platform = grp.get_node_or_null("Platform") as Node3D
	board_label = grp.get_node_or_null("Label") as Label3D
	if board_label == null:
		board_label = Gfx.label("CREW BOARDING ELEVATOR", Color("#9cdeb1"), 40, 8)
		board_rig.add_child(board_label)
	if not bake_mode:
		grp.visible = false   # revealed when boarding starts


# ---------------------------------------------------------------- apron fence
func _build_apron_railing(grp: Node3D) -> void:
	var gray := Color("#758087")
	var steel := _pbr_dark_steel if _pbr_dark_steel != null else Hardware.material(gray, 0.8, 0.35)
	var radius := APRON_RAILING_RADIUS
	# Measure from +Z, toward the road. The rear opening clears the shop frontage.
	var road_edge := asin((DELIVERY_ROAD.size.x * 0.5 + 0.15) / radius)
	var shop_edge := acos((shop_footprint.end.y + 0.15) / radius)
	var spans := ceili((shop_edge - road_edge) * radius / 2.4)
	# Walk-through gates facing every rack approach and crane elevator, plus a
	# gap wherever a structure footprint meets the fence line.
	var gate_points: Array[Vector2] = []
	for c in rack_centers:
		gate_points.append(Vector2(c[0], c[1]).normalized() * radius)
	var obstacles: Array[Rect2] = []
	if not delivery:
		for site: Vector3 in elevator_sites:
			gate_points.append(Vector2(site.x, site.z).normalized() * radius)
		var keepouts := layout_keepouts(elevator_sites, crane_bases, gse_dispatches, gse_pickups)
		for key in ["elevators", "lanes", "bays", "pedestals"]:
			for rect: Rect2 in keepouts[key]:
				obstacles.append(rect.grow(0.6))
	for blocker in blockers:
		obstacles.append((blocker as Rect2).grow(0.6))
	var post_count := 0
	var rail_count := 0
	for side in [-1.0, 1.0]:
		var previous := Vector3.ZERO
		var previous_post := false
		for i in range(spans + 1):
			var angle := lerpf(road_edge, shop_edge, float(i) / spans)
			var point := Vector3(side * sin(angle), 0, cos(angle)) * radius
			var open := i > 0 and _railing_span_blocked(previous, point, gate_points, obstacles)
			if i > 0 and not open:
				if not previous_post:
					_add(grp, _railing_post(previous, gray, steel), "Post%03d" % post_count)
					post_count += 1
				_add(grp, _railing_post(point, gray, steel), "Post%03d" % post_count)
				post_count += 1
				var span := point - previous
				for height in [0.48, 1.02]:
					var bar := Gfx.box(Vector3(span.length(), 0.065, 0.065), gray,
						(previous + point) * 0.5 + Vector3.UP * height)
					bar.rotation.y = -atan2(span.z, span.x)
					bar.material_override = steel
					_add(grp, bar, "Rail%03d" % rail_count)
					rail_count += 1
			previous_post = i > 0 and not open
			previous = point


# Bake-tool entry point: builds every structure group into `root` (see tools/bake_planet_a_scene.gd).
func bake_structures(root: Node3D) -> void:
	delivery = false
	bake_mode = true
	_setup_materials(load("res://scripts/gfx.gd") as GDScript)
	_bind_existing_layout(root)
	_ensure_structures(root)


# ---------------------------------------------------------------------------
# Construction of the scene
# ---------------------------------------------------------------------------
# Scenic sunlit reflecting ponds/coves flanking the launch complex (non-blocking).
# Each entry: [center_x, center_z, radius_x, radius_z]
# Side ponds sit beyond the GSE carousel bays (bay outer edge x = +/-42.5).
const WATER_PONDS := [
	[-60.0, 4.0, 12.5, 13.5],
	[60.0, 4.0, 13.0, 14.5],
	[-42.0, 48.0, 21.0, 15.0],
	[42.0, 48.0, 21.0, 15.0],
]




const WorldLabels := preload("res://scripts/ui/world_labels.gd")
var station_labels: Array[Label3D] = []

func _compact_billboard_labels(root: Node) -> void:
	if root == null:
		return
	for node in root.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		if label.billboard == BaseMaterial3D.BILLBOARD_DISABLED or label.font_size >= 70 or label.get_parent() is Actor:
			continue
		if station_labels.has(label):
			continue
		label.font = UI.font()
		label.font_size = 16
		label.outline_size = 4
		label.outline_modulate = UI.BG_DEEP
		label.fixed_size = false
		label.no_depth_test = false
		label.hide()
		label.add_to_group("station_labels")
		station_labels.append(label)


func update_station_labels(camera: Camera3D) -> void:
	if not actors.is_empty():
		WorldLabels.select_station(station_labels, camera, actors[g.sim.selected].global_position)


var _sky_birds: Array = []   # {root, lw, rw, angle, radius, height, speed, phase}
var _splash_cd := 0.0
var _chatter_t := 9.0
var _chatter_idx := 0
const CREW_CALLOUTS := [
	"FINN: Clear skies over the pad — perfect launch window!",
	"CHIP: Cryo propellant tanks pressurized and venting clean.",
	"BARBARA: Rival pads are already moving — let's beat 'em to orbit!",
	"FERNANDO: Grab our blueprint at the Parts Shop and let's roll!",
	"FINN: Wind is light across the meadow — green across the board.",
	"CHIP: Assembly gantry standing by whenever you confirm all 12 slots.",
]


func _living_world() -> void:
	var life := Node3D.new()
	life.name = "LivingWorld"
	add_child(life)

	# 1. Floating sunlit pollen / light motes drifting across the meadow & ponds.
	var motes := CPUParticles3D.new()
	motes.name = "SunlitMotes"
	motes.position = Vector3(0, 3.2, 10)
	motes.lifetime = 6.5
	motes.preprocess = 3.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(58, 2.8, 52)
	motes.direction = Vector3(0.4, 0.25, 0.2)
	motes.spread = 55.0
	motes.gravity = Vector3(0, 0.04, 0)
	motes.initial_velocity_min = 0.25
	motes.initial_velocity_max = 0.75
	# BILLBOARD_PARTICLES honours per-particle scale; plain BILLBOARD_ENABLED
	# discarded it and drew every mote as a full 1 m flat square.
	motes.scale_amount_min = 0.06
	motes.scale_amount_max = 0.14
	var mote_mesh := QuadMesh.new()
	mote_mesh.size = Vector2(1.0, 1.0)
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_mat.albedo_texture = _soft_dot_texture()
	mote_mat.albedo_color = Color(1.0, 0.96, 0.76, 0.45)
	mote_mesh.material = mote_mat
	motes.mesh = mote_mesh
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GraphicsSettings.set_particle_count(motes, 70)
	life.add_child(motes)

	# 2. Gentle cryogenic steam wisps rising from the launch complex propellant tanks.
	var steam_mat := StandardMaterial3D.new()
	steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam_mat.albedo_texture = _soft_dot_texture()
	steam_mat.albedo_color = Color(0.92, 0.97, 1.0, 0.26)
	var steam_mesh := QuadMesh.new()
	steam_mesh.size = Vector2(1.2, 1.2)
	steam_mesh.material = steam_mat
	for tx in [-47.0, 47.0]:
		var vent := CPUParticles3D.new()
		vent.position = Vector3(tx, 7.6, -49.0)
		vent.lifetime = 3.2
		vent.preprocess = 1.5
		vent.direction = Vector3(0.25, 1.0, 0.1)
		vent.spread = 18.0
		vent.gravity = Vector3(0.18, 0.25, 0)
		vent.initial_velocity_min = 1.1
		vent.initial_velocity_max = 2.0
		vent.scale_amount_min = 0.55
		vent.scale_amount_max = 1.75
		vent.mesh = steam_mesh
		vent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		GraphicsSettings.set_particle_count(vent, 14)
		life.add_child(vent)

	# 3. Stylized sunlit birds gliding in wide lazy circles above the spaceport.
	var bird_mat := Gfx.mat(Color("#f7f9fc"), 0.8)
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.85, 0.05, 0.24)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8081
	for i in 6:
		var root := Node3D.new()
		var lw := Gfx.mesh(wing_mesh, bird_mat, Vector3(-0.42, 0, 0), false)
		var rw := Gfx.mesh(wing_mesh, bird_mat, Vector3(0.42, 0, 0), false)
		root.add_child(lw)
		root.add_child(rw)
		life.add_child(root)
		_sky_birds.append({
			"root": root, "lw": lw, "rw": rw,
			"angle": rng.randf_range(0.0, TAU),
			"radius": rng.randf_range(38.0, 74.0),
			"height": rng.randf_range(24.0, 44.0),
			"speed": rng.randf_range(0.14, 0.24) * (1.0 if i % 2 == 0 else -1.0),
			"phase": rng.randf_range(0.0, TAU),
		})


static var _soft_dot: GradientTexture2D

# Radial soft-edged sprite so particles read as round glows, not hard quads.
static func _soft_dot_texture() -> GradientTexture2D:
	if _soft_dot == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.45, Color(1, 1, 1, 0.55))
		_soft_dot = GradientTexture2D.new()
		_soft_dot.gradient = gradient
		_soft_dot.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot.fill_from = Vector2(0.5, 0.5)
		_soft_dot.fill_to = Vector2(1.0, 0.5)
		_soft_dot.width = 32
		_soft_dot.height = 32
	return _soft_dot


func _tick_living_world(dt: float, player: Actor, speed: float) -> void:
	var motion_ok := GraphicsSettings.motion_effects and not UI.reduced_motion
	if motion_ok:
		for b in _sky_birds:
			b["angle"] += float(b["speed"]) * dt
			b["phase"] += dt * 5.2
			var a: float = b["angle"]
			var r: float = b["radius"]
			var root: Node3D = b["root"]
			root.position = Vector3(cos(a) * r, float(b["height"]) + sin(a * 2.0) * 2.2, sin(a) * r)
			root.rotation.y = -a + (0.0 if float(b["speed"]) > 0.0 else PI)
			var flap := sin(float(b["phase"])) * 0.42
			(b["lw"] as Node3D).rotation.z = flap
			(b["rw"] as Node3D).rotation.z = -flap

	# Reactive pond splash when moving through shallow pond edges.
	_splash_cd = maxf(0.0, _splash_cd - dt)
	if speed > 1.2 and _splash_cd <= 0.0 and player != null:
		var pt := Vector2(player.position.x, player.position.z)
		if _in_water_pond(pt, 0.8):
			_splash_cd = 0.28
			CombatFX.dust_puff(self, player.global_position, Color("#c8f4ff"), 0.85)
			g.sfx("splash", -12.0, 0.14)

	# Lively periodic crew radio callouts so the squad feels alive.
	_chatter_t -= dt
	if _chatter_t <= 0.0 and g != null and g.hud != null and not g.autotest:
		_chatter_t = 18.0
		g.hud.toast(CREW_CALLOUTS[_chatter_idx % CREW_CALLOUTS.size()])
		_chatter_idx += 1


func _in_water_pond(point: Vector2, pad := 0.0) -> bool:
	for spec: Array in water_ponds:
		var dx := (point.x - float(spec[0])) / maxf(float(spec[2]) + pad, 0.1)
		var dz := (point.y - float(spec[1])) / maxf(float(spec[3]) + pad, 0.1)
		if dx * dx + dz * dz < 1.0:
			return true
	return false


func _grass_scatter() -> void:
	# Lush curved 5-blade grass tuft with proper UV.y (0 root -> 1 tip) for wind & sunlit glow.
	var blade_surface := SurfaceTool.new()
	blade_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 5:
		var angle := blade * TAU / 5.0 + 0.25
		var lean := Vector3(cos(angle), 0.0, sin(angle))
		var across := Vector3(-lean.z, 0.0, lean.x)
		var base := lean * (0.04 + (blade % 2) * 0.055)
		var height := 0.40 + (blade % 3) * 0.13
		var first := blade * 7
		for row in 4:
			var t := row / 3.0
			var center := base + lean * (0.24 * t * t) + Vector3.UP * (height * t)
			var width := 0.068 * (1.0 - t * t)
			blade_surface.set_uv(Vector2(0.5 if row == 3 else 0.0, t))
			blade_surface.add_vertex(center - across * width)
			if row < 3:
				blade_surface.set_uv(Vector2(1.0, t))
				blade_surface.add_vertex(center + across * width)
		for idx in [0, 2, 1, 1, 2, 3, 2, 4, 3, 3, 4, 5, 4, 6, 5]:
			blade_surface.add_index(first + idx)
	blade_surface.generate_normals()

	var grass_material := ShaderMaterial.new()
	grass_material.shader = preload("res://assets/shaders/pad_vegetation.gdshader")
	grass_material.set_shader_parameter("wind_strength", 1.0)
	grass_material.set_shader_parameter("ultra_detail", false)

	var tufts := MultiMesh.new()
	tufts.transform_format = MultiMesh.TRANSFORM_3D
	tufts.use_colors = true
	tufts.mesh = blade_surface.commit()
	tufts.instance_count = 9000

	var exclusions: Array[Rect2] = [DELIVERY_ROAD.grow(0.25), shop_footprint.grow(0.25)]
	for rack in rack_centers:
		exclusions.append(Rect2(rack[0] - 3.6, rack[1] - 1.6, 7.2, 3.2).grow(0.25))
	for blocker in blockers:
		exclusions.append((blocker as Rect2).grow(0.25))
	if not delivery:
		var keepouts := layout_keepouts(elevator_sites, crane_bases, gse_dispatches, gse_pickups)
		for key in ["elevators", "lanes", "bays"]:
			for rect: Rect2 in keepouts[key]:
				exclusions.append(rect.grow(0.4))

	var rng := RandomNumberGenerator.new()
	rng.seed = 73429
	# Rich natural forest & meadow greens (SEUS/BSL Minecraft shader style).
	var deep_emerald := Color("#164617")
	var lush_meadow := Color("#215c1e")
	var sunlit_green := Color("#2e7424")
	var warm_clover := Color("#3e892a")
	var index := 0
	while index < tufts.instance_count:
		var point := Vector2(rng.randf_range(-74.0, 74.0), rng.randf_range(-74.0, 74.0))
		if point.length_squared() <= 22.75 * 22.75:
			continue
		if _in_water_pond(point, -1.2):
			continue
		if exclusions.any(func(footprint: Rect2) -> bool: return footprint.has_point(point)):
			continue
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var scale_factor := rng.randf_range(0.65, 1.42)
		# Taller lush reeds/grass near the pond shorelines.
		if _in_water_pond(point, 3.2):
			scale_factor *= 1.32
		basis = basis.scaled(Vector3.ONE * scale_factor)
		tufts.set_instance_transform(index, Transform3D(basis, Vector3(point.x, -0.02, point.y)))
		var shade := rng.randf_range(0.0, 3.0)
		var color: Color
		if shade < 1.0:
			color = deep_emerald.lerp(lush_meadow, shade)
		elif shade < 2.0:
			color = lush_meadow.lerp(sunlit_green, shade - 1.0)
		else:
			color = sunlit_green.lerp(warm_clover, shade - 2.0)
		tufts.set_instance_color(index, color)
		index += 1

	var grass := MultiMeshInstance3D.new()
	grass.name = "GrassScatter"
	grass.multimesh = tufts
	grass.material_override = grass_material
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)
	_grass_multimesh = tufts
	_grass_material = grass_material


const GRASS_TIER_FRACTION := [0.25, 0.55, 0.85, 1.0]


# Scale grass density/detail and vegetation/water motion to the graphics preset.
# Cached by a packed key so repeated calls with unchanged settings do no work.
func apply_quality(settings) -> void:
	if settings == null:
		return
	var vals: Dictionary = settings.values
	var tier: int = mini(int(vals.get("terrain", 2)), int(vals.get("lod", 2)))
	var ultra: bool = int(settings.quality) == 3 or int(vals.get("atmosphere", 0)) == 3
	if ultra:
		tier = 3
	var motion: bool = bool(vals.get("motion_effects", true)) and not UI.reduced_motion
	var key := tier * 2 + (1 if motion else 0)
	if key == _quality_key:
		return
	_quality_key = key
	var sway := 1.0 if motion else 0.0
	if _grass_multimesh != null:
		var target := int(_grass_multimesh.instance_count * GRASS_TIER_FRACTION[clampi(tier, 0, 3)])
		if _grass_multimesh.visible_instance_count != target:
			_grass_multimesh.visible_instance_count = target
	if _grass_material != null:
		_grass_material.set_shader_parameter("ultra_detail", ultra)
		_grass_material.set_shader_parameter("wind_strength", sway)
	if _water_material != null:
		_water_material.set_shader_parameter("wave_speed", sway)
		_water_material.set_shader_parameter("water_quality", clampi(tier, 0, 3))
	for light in apron_lights:
		if is_instance_valid(light):
			light.visible = tier >= 1
	var living := get_node_or_null("LivingWorld")
	if living != null:
		var motes := living.get_node_or_null("SunlitMotes")
		if motes != null:
			motes.visible = tier >= 1




func _railing_post(point: Vector3, gray: Color, steel: Material) -> MeshInstance3D:
	var post := Gfx.cyl(0.065, 1.1, gray, point + Vector3.UP * 0.55, 8)
	post.material_override = steel
	return post


static func _railing_span_blocked(a: Vector3, b: Vector3, gates: Array[Vector2], obstacles: Array[Rect2]) -> bool:
	var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
	for gate in gates:
		if mid.distance_to(gate) < 2.2:
			return true
	for rect in obstacles:
		for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var p := a.lerp(b, t)
			if rect.has_point(Vector2(p.x, p.z)):
				return true
	return false


func _terrain() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	add_child(Gfx.mesh(plane, Gfx.terrain_mat(Color("#5a4a7c"))))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 90:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(80, 260)
		var r := rng.randf_range(3, 13) * (1.0 + dist / 260.0)
		var rock := Gfx.rock(r, Color("#9f9cad") if i % 3 else Color("#7f7b91"), rng)
		rock.position = Vector3(cos(ang) * dist, r * 0.3, sin(ang) * dist)
		rock.rotation.y = rng.randf() * TAU
		if _pbr_cliff != null:
			rock.material_override = _pbr_cliff
		add_child(rock)
	for i in 30:
		var p := Vector3(rng.randf_range(-70, 70), 0, rng.randf_range(-70, 70))
		if p.length() < 48:
			continue
		var rock := Gfx.rock(rng.randf_range(0.6, 2.0), Color("#b9b3c8"), rng)
		rock.position = p
		if _pbr_cliff != null:
			rock.material_override = _pbr_cliff
		add_child(rock)
	var p1 := Gfx.planet(90, Color("#8d2c45"), Color("#a6475f"))
	p1.position = Vector3(-230, 170, -520)
	p1.rotation.z = 0.25
	add_child(p1)
	var moon := Gfx.sphere(38, Color("#c9d6dc"), Vector3(210, 120, -460), 0.1)
	add_child(moon)
	# Road dashes toward the delivery pad.
	for i in 8:
		var d := Gfx.box(Vector3(0.6, 0.03, 2.6), Color("#e9e4f2"), Vector3(0, 0.02, 22 + i * 5.5))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)


func _pad() -> void:
	add_child(Gfx.disc(21.0, Color("#463a64"), 0.14))
	var r1 := Gfx.ring(19.5, 0.35, Color("#e9e4f2"), 0.6)
	r1.position.y = 0.16
	add_child(r1)
	var r2 := Gfx.ring(9.0, 0.25, Color("#e9e4f2"), 0.35)
	r2.position.y = 0.16
	add_child(r2)
	for i in 24:
		var ang := i * TAU / 24.0
		var d := Gfx.box(Vector3(0.35, 0.03, 1.6), Color("#e9e4f2"), Vector3(cos(ang) * 17.5, 0.16, sin(ang) * 17.5))
		d.rotation.y = -ang
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
	# Orange launch gantry.
	var orange := Color("#d97a4a")
	for z in [-14.0, 8.0]:
		add_child(Gfx.box(Vector3(1.2, 26, 1.2), orange, Vector3(-17, 13, z)))
	add_child(Gfx.box(Vector3(1.0, 1.0, 23.2), orange, Vector3(-17, 25.5, -3)))
	add_child(Gfx.box(Vector3(9, 0.8, 0.8), orange, Vector3(-12.5, 18, -3)))
	blockers.append(Rect2(-17.8, -14.8, 1.6, 1.6))
	blockers.append(Rect2(-17.8, 7.2, 1.6, 1.6))


func _racks() -> void:
	for r in 4:
		var c = Sim.RACKS[r]
		var pos := Vector3(c[0], 0, c[1])
		var col := Sim.role_color(r)
		add_child(Gfx.box(Vector3(7, 1.1, 3), Color("#3a3156"), pos + Vector3(0, 0.55, 0)))
		add_child(Gfx.box(Vector3(7.2, 0.12, 3.2), col, pos + Vector3(0, 1.12, 0)))
		for sx in [-3.2, 3.2]:
			add_child(Gfx.box(Vector3(0.25, 4.2, 0.25), Color("#2a2340"), pos + Vector3(sx, 2.1, -1.3)))
		add_child(Gfx.box(Vector3(6.6, 0.9, 0.12), Color("#2a2340"), pos + Vector3(0, 3.9, -1.3)))
		var l := Gfx.label("%s · %s RACK" % [Sim.SPECIALISTS[r]["name"], Sim.SPECIALISTS[r]["role"]], col, 54)
		l.position = pos + Vector3(0, 5.0, -1.3)
		add_child(l)
		blockers.append(Rect2(pos.x - 3.6, pos.z - 1.6, 7.2, 3.2))


func _cargo() -> void:
	var cols := [Color("#f6a052"), Color("#9cdeb1"), Color("#edbd81"), Color("#b7a0f3")]
	for i in g.sim.cargo.size():
		var c = g.sim.cargo[i]
		var n := Node3D.new()
		n.add_child(Gfx.box(Vector3(1.6, 1.1, 1.1), Color("#e9e4f2"), Vector3(0, 0.55, 0)))
		n.add_child(Gfx.box(Vector3(1.64, 0.22, 1.14), cols[i], Vector3(0, 0.75, 0)))
		var l := Gfx.label(c["name"].to_upper(), Color("#f3eef8"), 36)
		l.position = Vector3(0, 2.2, 0)
		n.add_child(l)
		n.position = c["position"]
		add_child(n)
		cargo_nodes[c["id"]] = n


func _consoles() -> void:
	for type in CONSOLES:
		var pos: Vector3 = console_points[type]
		add_child(Gfx.box(Vector3(1.6, 1.2, 1.0), Color("#3a3156"), pos + Vector3(0, 0.6, 0)))
		var path := "res://assets/props/%s.glb" % CONSOLE_PROPS[type]
		if ResourceLoader.exists(path):
			var prop: Node3D = load(path).instantiate()
			prop.scale = Vector3.ONE * 2.6
			prop.position = pos + Vector3(0, 1.2, 0)
			add_child(prop)
		var role: int = Sim.CHECK_ROLE[type]
		var l := Gfx.label("%s CHECK · %s" % [type.to_upper(), Sim.SPECIALISTS[role]["name"]], Sim.role_color(role), 38)
		l.position = pos + Vector3(0, 3.4, 0)
		add_child(l)
		blockers.append(Rect2(pos.x - 0.9, pos.z - 0.6, 1.8, 1.2))


func _delivery_pad() -> void:
	var p := Sim.DELIVERY_PAD
	var d := Gfx.disc(4.2, Color("#3b2f55"), 0.1)
	d.position = p
	add_child(d)
	var r := Gfx.ring(4.0, 0.3, Color("#eaa665"), 0.9)
	r.position = p + Vector3(0, 0.14, 0)
	add_child(r)
	var l := Gfx.label("SCIENCE DELIVERY", Color("#eaa665"), 30)
	l.position = p + Vector3(0, 3.0, 0)
	add_child(l)


func _rivals() -> void:
	for i in range(1, 4):
		var bay = Sim.LANDING_BAYS[i]
		var pos: Vector3 = rival_points[i] if rival_points[i] != null else Vector3(bay[0], 0, bay[1])
		# Rival landing surfaces are inside PlanetAEnvironment.tscn.
		var squad: Dictionary = _pad_squad(i)
		var ship := ShipModel.full(squad["color"], g.sim.teams[i]["loadout"], true)
		ship.scale = Vector3.ONE * ShipModel.VESSEL_SCALE
		ship.position = pos
		ship.rotation.y = atan2(pos.x, pos.z) + PI
		add_child(ship)
		var l := Gfx.label(squad["label"], squad["color"], 80)
		l.position = pos + Vector3(0, 16, 0) * ShipModel.VESSEL_SCALE
		add_child(l)
		rival_ships.append({"node": ship, "label": l, "team": i, "pos": pos, "empire_squad": squad.get("id", "")})
		var half := 6.0 * Sim.SHIP_K * ShipModel.VESSEL_SCALE
		blockers.append(Rect2(pos.x - half, pos.z - half, half * 2.0, half * 2.0))


func _pad_squad(index: int) -> Dictionary:
	var s: Sim = g.sim
	if s.empire == null and home_alliance == "planet_a":
		return {"label": Sim.FACTIONS[index]["name"], "color": Sim.faction_color(index)}
	var allies: Array = Sim.EmpireRules.ALLIANCE_SQUADS[home_alliance].duplicate()
	allies.erase(s.empire_squad if s.empire != null and s.empire_home == home_alliance else allies[0])
	var id: String = allies[index - 1]
	return {"id": id, "label": "%s · ALLY\n%s COALITION" % [
		id.to_upper(), home_alliance.to_upper().replace("_", " ")], "color": Color.html(Sim.EMPIRE_COLORS[id])}


func _ship() -> void:
	# Each of the 12 buildable spacecraft modules now exists in Kestrel.tscn.
	ship_root = ShipModel.full(accent, g.sim.loadout, true)
	ship_root.scale = Vector3.ONE * ShipModel.VESSEL_SCALE
	_landing_nodes.clear()
	for child in ship_root.get_children():
		if String(child.name).begins_with("Landing"): _landing_nodes.append(child)
	if _bolt_materials.is_empty():
		for i in 6:
			_bolt_materials.append(Gfx.mat(Color("#ed7d8d").lerp(Color("#f7ce59"), i * 0.2), 0.6, 1.5))
		_bolt_materials.append(Gfx.mat(Color("#9cdeb1"), 0.6, 1.5))
	visual_loadout = g.sim.loadout.duplicate(true)
	ship_root.name = "Kestrel"
	add_child(ship_root)
	for p in g.sim.parts:
		var node: Node3D = ship_root.get_node(p["id"]) as Node3D
		if not delivery and g.arena_clash == null:
			_create_gse_module(p["id"], node)
		var bolts := []
		for k in 3:
			var b := Gfx.sphere(0.32, Color("#ed7d8d"), Vector3(-p["dims"].x * 0.3 + k * p["dims"].x * 0.3, p["dims"].y * 0.5 + 0.2, 0), 1.5, 10)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(b)
			bolts.append(b)
		slot_nodes[p["id"]] = {"node": node, "bolts": bolts}
		var preview := ShipModel.preview(p["id"], str(g.sim.loadout.get(p["id"], "kestrel")), accent)
		preview.position = Vector3.ZERO
		add_child(preview)
		shelf_nodes[p["id"]] = preview


func _crew() -> void:
	for r in 4:
		var s = Sim.SPECIALISTS[r]
		var a := Actor.new()
		var tag_color := Sim.role_color(r)
		if g.arena_clash != null:
			tag_color = Color.html(Sim.EMPIRE_COLORS[g.arena_clash.player_squad])
		elif g.sim.empire != null:
			tag_color = Color.html(Sim.EMPIRE_COLORS[g.sim.empire_squad])
		a.setup(s["model"], r, Sim.role_color(r), s["name"], tag_color)
		add_child(a)
		if delivery:
			a.position = Vector3(-6 + r * 4, 0, 24)
		else:
			# Spawn on the open apron between the crane pedestals and gantry posts.
			var c = rack_centers[r]
			a.position = Vector3(c[0] * 0.6, 0, c[1] * 0.5)
		a.heading = atan2(a.position.x, a.position.z)
		a.rotation.y = a.heading
		actors.append(a)


# ---------------------------------------------------------------------------
# 3D parts shop with a holographic ship builder terminal.
# ---------------------------------------------------------------------------








func _crane_side(role: int) -> float:
	return -1.0 if role % 2 == 0 else 1.0


func _cab_center(role: int) -> Vector3:
	var site: Vector3 = elevator_sites[role]
	return Vector3(site.x, ELEVATOR_HEIGHT, site.z)


# Ground footprints of every crane-deck / GSE structure, derived from the layout
# constants so grass, railing gates and audits agree before any node exists.
static func layout_keepouts(sites: Array = ELEVATOR_SITES, bases: Array = CRANE_BASES, dispatches: Array = GSE_DISPATCHES, pickups: Array = GSE_PICKUPS) -> Dictionary:
	var out := {"elevators": [], "lanes": [], "bays": [], "pedestals": []}
	for site: Vector3 in sites:
		out["elevators"].append(Rect2(site.x - ELEVATOR_SIZE.x * 0.5, site.z - ELEVATOR_SIZE.y * 0.5,
			ELEVATOR_SIZE.x, ELEVATOR_SIZE.y))
	for base: Vector3 in bases:
		out["pedestals"].append(Rect2(base.x - 2.0, base.z - 2.0, 4.0, 4.0))
	var half_belt := 1.75
	for role in pickups.size():
		var a: Vector3 = dispatches[role]
		var b: Vector3 = pickups[role]
		out["lanes"].append(Rect2(minf(a.x, b.x) - half_belt, a.z - half_belt, absf(b.x - a.x) + half_belt * 2.0, half_belt * 2.0))
		out["lanes"].append(Rect2(b.x - half_belt, minf(a.z, b.z) - half_belt, half_belt * 2.0, absf(b.z - a.z) + half_belt * 2.0))
		out["bays"].append(Rect2(b.x - GSE_BAY_SIZE.x * 0.5, b.z - GSE_BAY_SIZE.y * 0.5, GSE_BAY_SIZE.x, GSE_BAY_SIZE.y))
	return out


func _create_crane_deck() -> void:
	var light := Color("#82e6ff")
	_create_crane_arms()
	# Pedestals, elevator towers, cabs, conveyors, bays and arches are scene nodes
	# bound by _ensure_structures(); only the animated arms are created here.
	for i in 4:
		_collect_crane_view_meshes(actor(i).get_node("Holder"))
		for key in ["upper", "lower", "shoulder", "elbow"]:
			_collect_crane_view_meshes(fx_arms[i][key])
	# Vertical hoist drop-line: a thin cable/laser hanging straight down from the
	# claw to the surface below, plus square alignment reticles (no rings).
	crane_drop_material = Gfx.unshaded(light, 0.8).duplicate() as StandardMaterial3D
	crane_drop_material.no_depth_test = true
	var cable := CylinderMesh.new()
	cable.top_radius = 0.045
	cable.bottom_radius = 0.045
	cable.height = 1.0
	cable.radial_segments = 6
	cable.rings = 1
	crane_marker = Gfx.mesh(cable, crane_drop_material, Vector3.ZERO, false)
	crane_marker.name = "CraneHoistDropLine"
	crane_marker.visible = false
	add_child(crane_marker)
	crane_drop_foot = _crane_reticle(0.9, crane_drop_material)
	crane_drop_foot.name = "CraneHoistFoot"
	crane_drop_foot.visible = false
	add_child(crane_drop_foot)
	crane_height_label = Gfx.label("", light, 40)
	crane_height_label.name = "CraneHoistHeight"
	crane_height_label.no_depth_test = true
	crane_height_label.visible = false
	add_child(crane_height_label)
	crane_target_material = Gfx.unshaded(light, 0.55).duplicate() as StandardMaterial3D
	crane_target_material.no_depth_test = true
	crane_target_marker = _crane_reticle(1.6, crane_target_material, true)
	crane_target_marker.name = "CraneTargetReticle"
	crane_target_marker.visible = false
	add_child(crane_target_marker)


# Flat square alignment reticle: four corner brackets plus a centre cross.
func _crane_reticle(half: float, material: Material, cross := false) -> Node3D:
	var root := Node3D.new()
	var t := 0.09
	var arm := half * 0.45
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := Vector3(sx * half, 0, sz * half)
			_reticle_bar(root, material, Vector3(arm, 0.03, t), corner - Vector3(sx * arm * 0.5, 0, 0))
			_reticle_bar(root, material, Vector3(t, 0.03, arm), corner - Vector3(0, 0, sz * arm * 0.5))
	var c := half * (0.55 if cross else 0.35)
	_reticle_bar(root, material, Vector3(c, 0.03, t * 0.7), Vector3.ZERO)
	_reticle_bar(root, material, Vector3(t * 0.7, 0.03, c), Vector3.ZERO)
	return root


func _reticle_bar(parent: Node3D, material: Material, size: Vector3, pos: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = size
	parent.add_child(Gfx.mesh(b, material, pos, false))


func _create_gse_module(id: String, installed: Node3D) -> void:
	var wrapper := Node3D.new()
	wrapper.name = "GSEModule_" + id
	var model := installed.duplicate() as Node3D
	model.basis = ship_root.basis * installed.basis
	model.position = Vector3.ZERO
	wrapper.add_child(model)
	var bounds := [null]
	Actor._aabb(model, Transform3D.IDENTITY, bounds)
	var box: AABB = bounds[0] if bounds[0] != null else AABB()
	var grip := box.get_center()
	grip.y = box.end.y + CRANE_GRIP_CLEARANCE
	model.position = -grip
	wrapper.visible = false
	add_child(wrapper)
	gse_modules[id] = {"node": wrapper, "grip": grip, "height": grip.y - box.position.y}








func _gse_point(role: int, progress: float) -> Vector3:
	if not gse.is_empty():
		var hardware_script: GDScript = Hardware
		return hardware_script.call("sample_gse_path", gse, role, progress)
	var route := gse_routes[role]
	return route.sample_baked(progress * route.get_baked_length())


func _gse_pickup_grip(role: int, id: String) -> Vector3:
	return _gse_point(role, 1.0) + Vector3.UP * float(gse_modules[id]["height"])


func _crane_placement_grip(part: Dictionary) -> Vector3:
	return to_local(_crane_slot(part)) + (gse_modules[part["id"]]["grip"] as Vector3)


func _gse_ready_part(role: int) -> Variant:
	if gse_progress[role] < 1.0 or gse_loads[role].is_empty():
		return null
	var part = g.sim.part_by_id(gse_loads[role])
	return part if part != null and part["stage"] == "shelf" and part["purchased"] else null


func _process(dt: float) -> void:
	if gse_routes.is_empty():
		return
	if is_crane_camera_active() and g.world == self:
		_update_crane_view_clearance()
	else:
		for mesh in crane_view_hidden:
			mesh.show()
		crane_view_hidden.clear()
	if g.world == self and g.mode == "play":
		_tick_gse_delivery(dt)


func _tick_gse_delivery(dt: float) -> void:
	if not gse.is_empty():
		var hardware_script: GDScript = Hardware
		hardware_script.call("tick_gse_delivery", gse, dt)
	var s: Sim = g.sim
	if g.arena_clash != null or not _construction_here():
		for load in gse_modules.values():
			(load["node"] as Node3D).hide()
		return
	gse_dispatch_gap = maxf(0.0, gse_dispatch_gap - dt)
	for role in gse_routes.size():
		var id: String = gse_loads[role]
		var part = s.part_by_id(id) if not id.is_empty() else null
		if part == null or part["stage"] != "shelf" or not part["purchased"]:
			gse_loads[role] = ""
			gse_progress[role] = 0.0
		if gse_loads[role].is_empty() and gse_dispatch_gap == 0.0:
			for candidate in s.parts:
				if candidate["owner"] == role and candidate["stage"] == "shelf" and candidate["purchased"]:
					gse_loads[role] = candidate["id"]
					# Space loads on the shared Workshop apron before branching.
					gse_dispatch_gap = 3.5
					break
		if not gse_loads[role].is_empty():
			var length := gse_routes[role].get_baked_length()
			gse_progress[role] = minf(1.0, gse_progress[role] + GSE_LOAD_SPEED * dt / length)
	for part in s.parts:
		var id: String = part["id"]
		var role: int = part["owner"]
		var load: Dictionary = gse_modules[id]
		var node: Node3D = load["node"]
		var on_belt: bool = gse_loads[role] == id
		var held_by_crane: bool = lift_state == LiftState.DECK and part["stage"] == "carried" and s.carry[role] == id
		node.visible = on_belt or held_by_crane
		if on_belt:
			var progress: float = gse_progress[role]
			var span := 4.0 / gse_routes[role].get_baked_length()
			var direction := _gse_point(role, minf(1.0, progress + span)) - _gse_point(role, maxf(0.0, progress - span))
			node.rotation.y = atan2(direction.x, direction.z)
			node.position = _gse_point(role, progress) + Vector3.UP * float(load["height"])
		elif held_by_crane:
			node.position = (fx_arms[role]["tip"] as Node3D).position
			node.rotation.y = lerp_angle(node.rotation.y, 0.0, 1.0 - exp(-8.0 * dt))


func _lift_node(role: int) -> Node3D:
	return lifts[role]["platform"] as Node3D


func _on_elevator(at: Vector3, role: int) -> bool:
	var offset := at - _lift_node(role).position
	return absf(offset.x) < ELEVATOR_SIZE.x * 0.5 - 0.25 and absf(offset.z) < ELEVATOR_SIZE.y * 0.5 - 0.25 and absf(offset.y) < 0.5


func _crane_station(role: int) -> Vector3:
	var c := _cab_center(role)
	return c + Vector3(-_crane_side(role) * 1.6, 0, 0)


func _lift_seat(role: int) -> Vector3:
	return _lift_node(role).position + Vector3(_crane_side(role) * 0.8, 0, 0)


func exit_crane_mode() -> void:
	crane_mode = false


func is_crane_camera_active() -> bool:
	return crane_mode and lift_state == LiftState.DECK and fx_arms.size() == 4


# Arm-mounted "front view": the lens rides just behind and beside the boom,
# low over the claw, looking forward along the arm at the claw tip and the
# work point (GSE bay or ship slot) beyond it. Steering axes follow this view.
func crane_camera_pose() -> Dictionary:
	var role := clampi(crane_role, 0, 3)
	var claw: Vector3 = fx_arms[role]["target"]
	var forward := _crane_arm_forward(role)
	var side := forward.cross(Vector3.UP).normalized()
	var pos := claw - forward * 9.0 + side * _crane_side(role) * 2.2
	pos.y = clampf(claw.y + 4.5, 5.5, ELEVATOR_HEIGHT + 4.0)
	var target := claw + forward * 7.0
	target.y = maxf(0.5, claw.y - 3.0)
	return {"pos": to_global(pos), "target": to_global(target), "label": "CRANE ARM VIEW"}


# Horizontal direction the boom points (pedestal -> claw); falls back to the
# current work point when the claw sits over the pedestal.
func _crane_arm_forward(role: int) -> Vector3:
	var base: Vector3 = fx_arms[role]["base"]
	var claw: Vector3 = fx_arms[role]["target"]
	var flat := Vector3(claw.x - base.x, 0, claw.z - base.z)
	if flat.length() < 1.0:
		var part: Variant = _crane_active_part(role)
		var work := _crane_placement_grip(part) if part != null else _gse_point(role, 1.0)
		flat = Vector3(work.x - base.x, 0, work.z - base.z)
	return flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD


func _collect_crane_view_meshes(root: Node) -> void:
	if root is MeshInstance3D and root.mesh != null:
		crane_view_meshes.append(root)
	for child in root.get_children():
		_collect_crane_view_meshes(child)


func _update_crane_view_clearance() -> void:
	var camera_position: Vector3 = g.cam.global_position
	var claw: Vector3 = fx_arms[crane_role]["target"]
	var bay := _gse_point(crane_role, 1.0)
	var ready: Variant = _gse_ready_part(crane_role)
	if ready != null:
		bay = _gse_pickup_grip(crane_role, ready["id"])
	var pad := Vector3(0, 4, 0)
	var part: Variant = _crane_active_part(crane_role)
	if part != null:
		pad = _crane_placement_grip(part)
	var work_points := [to_global(claw - Vector3.UP), to_global(bay), to_global(pad)]
	for mesh in crane_view_meshes:
		if not mesh.visible and not crane_view_hidden.has(mesh):
			continue
		var inverse := mesh.global_transform.affine_inverse()
		var origin := inverse * camera_position
		var bounds := mesh.get_aabb()
		var blocks_view := false
		# Temporarily hide only hardware or crew meshes crossing a work sightline.
		for point in work_points:
			if bounds.intersects_segment(origin, inverse * point):
				blocks_view = true
				break
		if blocks_view:
			mesh.hide()
			crane_view_hidden[mesh] = true
		elif crane_view_hidden.erase(mesh):
			mesh.show()


func _apply_crane_camera() -> void:
	if not is_crane_camera_active():
		return
	var pose := crane_camera_pose()
	g.cam.global_position = pose["pos"]
	g.cam.look_at(pose["target"])


func _snap_crane_camera() -> void:
	if is_crane_camera_active() and g.world == self:
		_apply_crane_camera()
		_update_crane_view_clearance()


func _tick_crane_deck(dt: float, role: int) -> float:
	var s: Sim = g.sim
	var player := actor(role)
	var speed := 0.0
	var operating := false
	if fx_light != null:
		_fx_sparks_tick(dt)
	crane_target_marker.visible = false
	if crane_mode and (lift_state != LiftState.DECK or crane_role != role):
		crane_mode = false
	match lift_state:
		LiftState.BOARDING, LiftState.RETURN_BOARDING:
			var boarding_up := lift_state == LiftState.BOARDING
			g.hud.set_prompt("CREW BOARDING", "Each specialist rides their own crane elevator.")
			var all_aboard := true
			for i in 4:
				var crew := actor(i)
				var seat := _lift_seat(i)
				var distance := crew.walk_to(seat, dt, 8.0, 0.14)
				crew.position.y = seat.y
				crew.move_vel = Vector3.ZERO
				crew.vy = 0.0
				crew.animate(dt, crew.vel.length(), "", false)
				all_aboard = all_aboard and distance <= 0.14
			if all_aboard:
				lift_state = LiftState.RISING if boarding_up else LiftState.LOWERING
		LiftState.RISING, LiftState.LOWERING:
			var rising := lift_state == LiftState.RISING
			var goal := 1.0 if rising else 0.0
			lift_progress = move_toward(lift_progress, goal, dt / 3.5)
			for i in 4:
				_lift_node(i).position.y = ELEVATOR_HEIGHT * smoothstep(0.0, 1.0, lift_progress)
				actor(i).position = _lift_seat(i)
				actor(i).animate(dt, 0.0, "", false)
			g.hud.set_prompt("ASCENDING TO CRANE CONTROL" if rising else "RETURNING TO THE ASSEMBLY PAD")
			if lift_progress == goal:
				lift_state = LiftState.DECK if rising else LiftState.PARKED
				if not rising:
					pad_stage = "ready"
		LiftState.DECK:
			var complete := s.secured_count() == s.confirmed_count()
			var cab := _cab_center(role)
			var station := _crane_station(role)
			if complete:
				crane_mode = false
			if crane_mode:
				operating = true
				player.move_vel = Vector3.ZERO
				player.position = Vector3(station.x, ELEVATOR_HEIGHT, station.z)
				player.face(Vector3(-_crane_side(role), 0, 0), dt)
				if g.pressed(KEY_Q):
					exit_crane_mode()
					operating = false
				elif crane_enter_frame != Engine.get_process_frames():
					_player_crane(role, dt)
			else:
				speed = g.drive(player, dt, 0.0)
				player.position = Vector3(clampf(player.position.x, cab.x - 2.7, cab.x + 2.7), ELEVATOR_HEIGHT,
					clampf(player.position.z, cab.z - 2.2, cab.z + 2.2))
				player.vy = 0.0
				if s.flight_capable() and _on_elevator(player.position, role):
					g.hud.set_prompt("E  RIDE ELEVATOR DOWN", "Ship is flight-capable")
					if g.pressed(KEY_E):
						lift_state = LiftState.RETURN_BOARDING
				elif complete:
					g.hud.set_prompt("RETURN TO YOUR CRANE ELEVATOR", "Ship is flight-capable")
				elif _construction_here() and g.flat_dist(player.position, station) <= 1.6:
					g.hud.set_prompt("E  USE CRANE", "%s · WASD steers · E grab / place · Q quit crane" % Sim.SPECIALISTS[role]["name"])
					if g.pressed(KEY_E):
						crane_mode = true
						crane_role = role
						crane_enter_frame = Engine.get_process_frames()
						# Main eases camera transitions after tick; snap straight to the arm view on entry.
						_snap_crane_camera.call_deferred()
				else:
					g.hud.set_prompt("GO TO YOUR CRANE CONSOLE", "%s · Stand at the console and tap E" % Sim.SPECIALISTS[role]["name"])
			player.animate(dt, speed, "work" if operating else "", false)
			for i in 4:
				if i == role:
					continue
				var crew := actor(i)
				var at_station := crew.walk_to(_crane_station(i), dt, 5.0, 0.25) <= 0.25
				if at_station and _construction_here():
					crew.face(Vector3(-_crane_side(i), 0, 0), dt)
					_bot_crane(i, dt)
				crew.animate(dt, crew.vel.length(), "work" if at_station and not complete else "", false)
	if is_crane_camera_active():
		_apply_crane_camera()
	else:
		g.follow_cam(player)
	var show_drop := operating and crane_mode
	crane_marker.visible = show_drop
	crane_drop_foot.visible = show_drop
	crane_height_label.visible = show_drop
	return speed


func _crane_active_part(role: int) -> Variant:
	var s: Sim = g.sim
	return s.part_by_id(s.carry[role]) if s.carry[role] != null else _first_part(role, "positioned")


func _crane_slot(part: Dictionary) -> Vector3:
	return (slot_nodes[part["id"]]["node"] as Node3D).global_position


func _crane_move(role: int, target: Vector3, dt: float) -> void:
	var arm: Dictionary = fx_arms[role]
	arm["target"] = (arm["target"] as Vector3).move_toward(target, CRANE_SPEED * dt)
	_fx_arm_pose(arm, arm["target"])


func _crane_lock(role: int, part: Dictionary, human: bool) -> void:
	var s: Sim = g.sim
	var id: String = part["id"]
	if part["stage"] == "carried":
		s.rotation[role] = part["angle"]
		if not s.place_part(role, 0.0):
			return
	for bolt in 3:
		s.fasten_bolt(id, bolt, role, 0.7, 0.0, true, human)
	(gse_modules[id]["node"] as Node3D).hide()
	_fx_snap(_crane_slot(part))
	g.sfx("reload_ratchet" if g.streams.has("reload_ratchet") else "reload_click", -3 if human else -11)
	if human:
		g.hud.toast("%s secured · %d/12" % [part["name"], s.secured_count()])


func _player_crane(role: int, dt: float) -> void:
	var s: Sim = g.sim
	var arm: Dictionary = fx_arms[role]
	var at: Vector3 = arm["target"]
	var motion := Vector2(float(g.held(KEY_D)) - float(g.held(KEY_A)), float(g.held(KEY_S)) - float(g.held(KEY_W)))
	var touch: MobileControls = g.touch_ui()
	if touch != null and touch.move_vector() != Vector2.ZERO:
		motion = touch.move_vector()
	var step := motion.limit_length() * CRANE_SPEED * dt
	# W pushes the claw out along the boom, A/D slew it left/right in the arm view.
	var forward := _crane_arm_forward(role)
	var right := forward.cross(Vector3.UP).normalized()
	at += right * step.x - forward * step.y
	at.x = clampf(at.x, CRANE_CLAMP.position.x, CRANE_CLAMP.end.x)
	at.z = clampf(at.z, CRANE_CLAMP.position.y, CRANE_CLAMP.end.y)
	var base: Vector3 = arm["base"]
	var reach := Vector2(at.x - base.x, at.z - base.z)
	if reach.length() < CRANE_MIN_RADIUS:
		reach = Vector2(forward.x, forward.z) * CRANE_MIN_RADIUS
	reach = reach.limit_length(float(arm["reach"]) - 2.0)
	at.x = base.x + reach.x
	at.z = base.z + reach.y
	# Vertical hoist: SPACE up, SHIFT / C down, clamped between the active grip
	# height (lowest safe claw position) and the hoist ceiling.
	var hoist := _crane_hoist_axis()
	at.y += hoist * CRANE_HOIST_SPEED * dt
	var part: Variant = _crane_active_part(role)
	var aligned := false
	var low_y := 2.0          # lowest claw height for the current job
	var surface_y := 0.05     # surface the drop-line lands on
	var keys := "WASD move · SPACE hoist up · SHIFT/C lower · Q quit"
	if part != null:
		var grip := _crane_placement_grip(part)
		aligned = g.flat_dist(at, grip) <= CRANE_GRAB_RADIUS
		var slot_height := to_local(_crane_slot(part)).y
		low_y = grip.y
		_mark_crane_target(Vector3(grip.x, slot_height + 0.15, grip.z), aligned)
		if aligned:
			surface_y = slot_height + 0.15
			if motion == Vector2.ZERO:
				at = _crane_magnet(at, grip, dt)
		g.hud.set_prompt("PRESS E TO SNAP & LOCK %s" % part["name"].to_upper() if aligned else
			"STEER CLAW OVER THE HIGHLIGHTED SHIP SLOT", "%s · E place · %s" % [keys, part["name"]])
		if aligned and g.pressed(KEY_E):
			# Forgiving: E snaps the claw straight down onto the slot at any hoist height.
			at = grip
			_crane_lock(role, part, true)
	else:
		var pickup: Variant = _gse_ready_part(role)
		var bay := _gse_point(role, 1.0)
		var over_bay: bool = pickup != null and _claw_over_bay(at, bay)
		aligned = over_bay
		if pickup != null:
			low_y = _gse_pickup_grip(role, pickup["id"]).y
			_mark_crane_target(bay + Vector3.UP * 0.1, over_bay)
			if over_bay:
				surface_y = bay.y + 0.1
				if motion == Vector2.ZERO:
					at = _crane_magnet(at, bay, dt)
			g.hud.set_prompt("PRESS E TO PICK UP %s" % pickup["name"].to_upper() if over_bay else
				"STEER CLAW OVER YOUR GSE BAY", "%s · E grab · %s" % [keys, pickup["name"]])
			if over_bay and g.pressed(KEY_E) and s.pickup_part_with_crane(role, pickup["id"]):
				# Forgiving: E drops the claw straight down onto the module and lifts it.
				at = _gse_pickup_grip(role, pickup["id"])
				g.sfx("reload_click", -4)
				g.hud.toast("%s picked up · hoist up (SPACE) and steer to the ship slot" % pickup["name"])
		elif _first_part(role, "shelf") != null:
			_mark_crane_target(bay + Vector3.UP * 0.1, false)
			g.hud.set_prompt("AWAITING GSE DELIVERY", "Your next module is coming from the Workshop.")
		else:
			g.hud.set_prompt("YOUR MODULES ARE SECURED", "The crew is finishing their modules · Switch roles with 1–4")
	# Bounds ease rather than teleport when the active job changes height.
	var bounded := clampf(at.y, low_y, maxf(CRANE_HOIST_TOP, low_y + CRANE_HOIST_SPAN))
	at.y = move_toward(at.y, bounded, CRANE_HOIST_SPEED * 2.0 * dt)
	arm["target"] = at
	_fx_arm_pose(arm, at)
	_update_crane_drop(at, surface_y, at.y - low_y, aligned, role)


# +1 raises the claw (SPACE), -1 lowers it (SHIFT or C), 0 holds height.
func _crane_hoist_axis() -> float:
	var up: bool = bool(g.held(KEY_SPACE))
	var down: bool = bool(g.held(KEY_SHIFT)) or bool(g.held(KEY_C))
	return float(up) - float(down)


# Vertical cable straight down from the claw jaws to the surface below, a
# reticle where it lands, and a live readout of the remaining drop distance.
func _update_crane_drop(at: Vector3, surface_y: float, drop: float, aligned: bool, role: int) -> void:
	crane_drop_distance = maxf(0.0, drop)
	var top := at.y - CRANE_CLAW_DROP
	var bottom := minf(surface_y, top - 0.05)
	var length := top - bottom
	crane_marker.position = Vector3(at.x, (top + bottom) * 0.5, at.z)
	crane_marker.scale = Vector3(1, length, 1)
	crane_drop_foot.position = Vector3(at.x, bottom + 0.04, at.z)
	var at_grip := crane_drop_distance <= 0.15
	var color := Color("#64ff78") if aligned else Sim.role_color(role)
	color.a = 0.95 if aligned else 0.8
	crane_drop_material.albedo_color = color
	crane_height_label.position = Vector3(at.x, top - minf(length * 0.5, 2.0), at.z) + _crane_arm_side(role) * 1.1
	crane_height_label.modulate = Color("#64ff78") if aligned else Color("#e8f4ff")
	crane_height_label.text = ("GRIP HEIGHT" if at_grip else "DROP %.1f m" % crane_drop_distance) + \
		("\nPRESS E" if aligned else "")


func _crane_arm_side(role: int) -> Vector3:
	return _crane_arm_forward(role).cross(Vector3.UP).normalized()


# Forgiving pickup zone: anywhere over the carousel bay footprint, or within
# the grab radius of the module resting at the end of the lane.
func _claw_over_bay(at: Vector3, bay: Vector3) -> bool:
	if g.flat_dist(at, bay) <= CRANE_GRAB_RADIUS:
		return true
	return absf(at.x - bay.x) <= GSE_BAY_SIZE.x * 0.5 and absf(at.z - bay.z) <= GSE_BAY_SIZE.y * 0.5


func _crane_magnet(at: Vector3, point: Vector3, dt: float) -> Vector3:
	var flat := Vector2(at.x, at.z).move_toward(Vector2(point.x, point.z), CRANE_MAGNET_SPEED * dt)
	return Vector3(flat.x, at.y, flat.y)


func _mark_crane_target(point: Vector3, aligned: bool) -> void:
	crane_target_marker.position = point
	crane_target_marker.visible = true
	var color := Color("#64ff78") if aligned else Color("#82e6ff")
	color.a = (0.9 if aligned else 0.55) + sin(Time.get_ticks_msec() * 0.008) * 0.12
	crane_target_material.albedo_color = color


func _bot_crane(role: int, dt: float) -> void:
	var s: Sim = g.sim
	var part: Variant = _crane_active_part(role)
	var pickup := part == null
	if pickup:
		part = _gse_ready_part(role)
	if part == null:
		return
	var target := _gse_pickup_grip(role, part["id"]) if pickup else _crane_placement_grip(part)
	var claw: Vector3 = fx_arms[role]["target"]
	if g.flat_dist(claw, target) > 0.12:
		var travel_height := maxf(12.0, target.y + 4.0)
		if not pickup and claw.y < travel_height - 0.12:
			_crane_move(role, Vector3(claw.x, travel_height, claw.z), dt)
			return
		_crane_move(role, Vector3(target.x, travel_height, target.z), dt)
		return
	_crane_move(role, target, dt)
	if (fx_arms[role]["target"] as Vector3).distance_to(target) > 0.12:
		return
	if pickup:
		s.pickup_part_with_crane(role, part["id"])
	else:
		_crane_lock(role, part, false)


func _shop_visuals(_dt: float) -> void:
	var s: Sim = g.sim
	g.hud.update_shop(s)
	if not is_instance_valid(shop_desk_ring):
		return
	var all_bought := s.construction_supplied()
	for i in lifts.size():
		(lifts[i]["sign"] as Label3D).text = "%s\n%s" % [Sim.SPECIALISTS[i]["name"],
			"BOARD CRANE ELEVATOR" if all_bought and lift_state == LiftState.GROUND else "CRANE ELEVATOR"]
	shop_desk_ring.visible = s.shop_open and lift_state == LiftState.GROUND
	shop_desk_label.visible = shop_desk_ring.visible
	shop_desk_label.text = "BOARD CRANE ELEVATOR" if all_bought else "CONFIRM REACTOR, ENGINE AND BRIDGE\n%d / 12" % s.confirmed_count()
	shop_desk_label.modulate = Color("#9cdeb1") if all_bought else Color("#f7ce59")


func _shop_interact(a: Actor) -> String:
	if pad_stage != "shop" and g.arena_clash == null:
		return ""
	if is_instance_valid(shop_kiosk_node) and g.flat_dist(a.position, shop_computer) < 3.6:
		g.hud.set_prompt("E  OPEN HOLOGRAPHIC SHIP BUILDER")
		if g.pressed(KEY_E):
			g.open_ship_builder()
		return ""
	var s: Sim = g.sim
	if s.construction_supplied() and lifts.size() == 4:
		var my_lift := _lift_node(s.selected).position
		_point_beacon(my_lift, "BOARD YOUR CRANE ELEVATOR")
		if _on_elevator(a.position, s.selected):
			g.hud.set_prompt("E  BOARD CRANE ELEVATOR", "Your crew rides their own elevators up to their crane arms.")
			if g.pressed(KEY_E):
				refresh_ship_loadout()
				s.shop_open = false
				s.auto_build["enabled"] = false
				pad_stage = "build"
				lift_state = LiftState.BOARDING
		else:
			g.hud.set_prompt("BOARD CRANE ELEVATOR", "%d m · Flight modules confirmed" % int(g.flat_dist(a.position, my_lift)))
		return ""
	if g.flat_dist(a.position, shop_desk) < 3.2:
		g.hud.set_prompt("CONFIRM REACTOR, ENGINE AND BRIDGE", "%d / 12 bought" % s.confirmed_count())
		return ""
	_point_beacon(shop_pos, "SHOP")
	g.hud.set_prompt("GO TO THE PARTS SHOP", "Open the ship builder with E · %d m · %d / 12 bought" % [int(g.flat_dist(a.position, shop_pos)), s.confirmed_count()])
	return ""


# ---------------------------------------------------------------------------
# Gameplay
# ---------------------------------------------------------------------------
func collide(p: Vector3) -> Vector3:
	if g.interior_active():
		return p   # the spacecraft interior has its own walls
	if lift_state == LiftState.DECK and p.y >= ELEVATOR_HEIGHT - 0.1:
		return p
	var rad := 0.6
	var rects := blockers.duplicate()
	for part in g.sim.parts:
		if part["stage"] == "secured" and ship_root.visible and ship_root.position.y < 1.0:
			var c := to_local(_crane_slot(part))
			var d: Vector3 = part["dims"] * ShipModel.VESSEL_SCALE
			rects.append(Rect2(c.x - d.x * 0.5, c.z - d.z * 0.5, d.x, d.z))
	for r in rects:
		var e: Rect2 = (r as Rect2).grow(rad)
		if e.has_point(Vector2(p.x, p.z)):
			var left := p.x - e.position.x
			var right := e.end.x - p.x
			var top := p.z - e.position.y
			var bottom := e.end.y - p.z
			var m := minf(minf(left, right), minf(top, bottom))
			if m == left: p.x = e.position.x
			elif m == right: p.x = e.end.x
			elif m == top: p.z = e.position.y
			else: p.z = e.end.y
	return p


func tick(dt: float) -> void:
	if g.arena_clash != null:
		_tick_arena_home(dt)
		return
	var s: Sim = g.sim
	if visual_loadout != s.loadout: refresh_ship_loadout()
	var r := s.selected
	var a: Actor = actors[r]
	if empire_layer != null:
		empire_layer.tick_raid(dt, _raid_authority())
		empire_layer.tick_visuals(dt, a.position)
		if empire_layer.raid_groups.is_empty() or not _can_defend(r):
			a.set_weapon_drawn(false)
	for i in 4:
		if actors[i].name_tag:
			actors[i].name_tag.visible = i != r
	var speed := 0.0
	beacon.visible = false
	if lift_state > LiftState.GROUND and lift_state < LiftState.PARKED:
		speed = _tick_crane_deck(dt, r)
	else:
		speed = g.drive(a, dt)
		g.follow_cam(a)
		_tick_defense_weapon(r, a, dt)
		var work := _interact(r, a, dt)
		if g.piloting:
			return
		a.animate(dt, speed, work, s.carry[r] != null)
		for i in 4:
			if i != r:
				_bot(i, dt)
				s.rescue_stalled_crew(i, dt)
	_tick_living_world(dt, a, speed)
	_visuals(dt)
	for light in apron_lights:
		light.light_energy = 0.55 if not delivery and pad_stage != "shop" else 0.18
	_shop_visuals(dt)


func _raid_authority() -> bool:
	return g.net == null or g.net.mode != "CLIENT"


func _can_defend(role: int) -> bool:
	var a := actor(role)
	var in_shop: bool = g.sim.shop_open and shop_footprint.grow(3.0).has_point(Vector2(a.position.x, a.position.z))
	return g.mode == "play" and not g.interior_active() \
		and (lift_state == LiftState.GROUND or lift_state == LiftState.PARKED) \
		and not in_shop and g.sim.carry[role] == null \
		and a.visible


func _defense_weapon_role(role: int) -> int:
	return mini(role, Sim.FIELD_WEAPONS.size() - 1)


func _draw_defense_weapon(a: Actor, role: int) -> void:
	if a.held_weapon == null:
		a.install_weapon(Sim.FIELD_WEAPONS[_defense_weapon_role(role)]["model"])
	a.set_weapon_drawn(true)


func _reload_defense_weapon(role: int, a: Actor) -> void:
	a.weapon_reload = DEFENSE_RELOAD
	_defense_ammo[role] = DEFENSE_MAGAZINE
	g.sfx("reload_click", -9)


func _tick_defense_weapon(role: int, a: Actor, dt: float) -> void:
	if empire_layer == null or empire_layer.raid_groups.is_empty() or not _can_defend(role):
		return
	if bots[role].get("defending", false):
		bots[role]["defending"] = false
		a.set_weapon_drawn(false)
	if g.pressed(KEY_B):
		if a.weapon_drawn:
			a.set_weapon_drawn(false)
		else:
			_draw_defense_weapon(a, role)
		g.sfx("reload_click", -10)
	if not a.weapon_drawn:
		return
	a.face(g.cam_forward(), dt, 20.0)
	a.weapon_pitch = g.pitch
	_defense_cooldown[role] = maxf(0.0, _defense_cooldown[role] - dt)
	if g.pressed(KEY_R) and a.weapon_ready() and _defense_ammo[role] < DEFENSE_MAGAZINE:
		_reload_defense_weapon(role, a)
	if not g.lmb or not a.weapon_ready() or _defense_cooldown[role] > 0.0:
		return
	var weapon_role := _defense_weapon_role(role)
	_defense_cooldown[role] = Sim.FIELD_WEAPONS[weapon_role]["interval"]
	_defense_ammo[role] -= 1
	g.sim.metrics["shots"] += 1
	a.recoil_weapon()
	a.trigger_weapon_kick()
	g.sfx(["shot_carbine", "shot_scatter", "shot_sidearm"][weapon_role], -11)
	var view_origin: Vector3 = g.cam.global_position
	var view_dir: Vector3 = g.cam_forward()
	var view_limit := _defense_cover_distance(view_origin, view_dir, DEFENSE_RANGE)
	var aim := _defense_ray(view_origin, view_dir, view_limit)
	var muzzle := EmpireLayer.actor_muzzle(a)
	var end := view_origin + view_dir * float(aim.get("distance", view_limit))
	# Aim from the camera, then resolve the actual muzzle ray so cover still blocks the shot.
	var direction := (end - muzzle).normalized()
	var limit := _defense_cover_distance(muzzle, direction, DEFENSE_RANGE)
	var hit := _defense_ray(muzzle, direction, limit)
	CombatFX.tracer(empire_layer, muzzle, muzzle + direction * float(hit.get("distance", limit)),
		Color("#ffd184"), 0.06, 0.10)
	if not hit.is_empty() and _raid_authority():
		g.sim.metrics["hits"] += 1
		g.hud.hit_time = 0.15
		var bounty := empire_layer.damage_raider(hit["actor"], Sim.field_damage(weapon_role, hit["distance"]), true)
		if bounty > 0:
			g.hud.toast("RAIDER ELIMINATED · +%d ALLIANCE CR" % bounty)
	if _defense_ammo[role] == 0:
		_reload_defense_weapon(role, a)


func _defense_ray(from: Vector3, direction: Vector3, limit: float) -> Dictionary:
	var hit := {}
	for raid: Dictionary in empire_layer.raid_groups.values():
		for raider: Actor in raid["units"]:
			var distance := Flight._ray_sphere(from, direction, EmpireLayer.raider_center(raider), raider.visual_height * 0.43)
			if distance > 0.0 and distance < limit:
				limit = distance
				hit = {"actor": raider, "distance": distance}
	return hit


func _defense_cover_distance(from: Vector3, direction: Vector3, limit: float) -> float:
	var origin := to_local(from)
	var end := to_local(from + direction * limit)
	for footprint: Rect2 in blockers:
		var cover := AABB(Vector3(footprint.position.x, 0.0, footprint.position.y),
			Vector3(footprint.size.x, 3.2, footprint.size.y))
		if cover.has_point(origin):
			continue
		var impact: Variant = cover.intersects_segment(origin, end)
		if impact != null:
			limit = minf(limit, origin.distance_to(impact))
	return limit


func _bot_defend(role: int, a: Actor, dt: float, idle: bool) -> void:
	var state: Dictionary = bots[role]
	var target: Actor
	if idle and empire_layer != null and not empire_layer.raid_groups.is_empty() and _can_defend(role):
		target = empire_layer.nearest_raider(a.global_position, 85.0)
	if target == null:
		if state.get("defending", false):
			a.set_weapon_drawn(false)
			state["defending"] = false
		return
	var aim := EmpireLayer.raider_center(target)
	var start := EmpireLayer.actor_muzzle(a)
	var direction := (aim - start).normalized()
	var distance := start.distance_to(aim)
	if _defense_cover_distance(start, direction, distance) < distance - 0.1:
		return
	_draw_defense_weapon(a, role)
	state["defending"] = true
	a.face(aim - a.global_position, dt, 18.0)
	state["defense_cd"] = maxf(0.0, float(state.get("defense_cd", 0.0)) - dt)
	if a.weapon_ready() and state["defense_cd"] <= 0.0:
		state["defense_cd"] = 1.8 + role * 0.13
		a.trigger_weapon_kick()
		empire_layer.fire_raid_bolt(start, aim, EmpireLayer.DEFENSE_COLOR)
		if _raid_authority():
			empire_layer.damage_raider(target, 5.0)


func sync_arena_build() -> void:
	var changed := false
	var built: Array = g.arena_clash.squads[g.arena_clash.player_squad]["built"]
	for slot: String in built:
		var part: Dictionary = g.sim.part_by_id(slot)
		if part["stage"] != "secured":
			part["stage"] = "secured"
			part["bolts"] = [1.0, 1.0, 1.0]
			changed = true
	if changed and is_instance_valid(g.vessel):
		g.vessel.sync_modules()


func _tick_arena_home(dt: float) -> void:
	var a: Actor = actors[g.sim.selected]
	beacon.hide()
	if a.name_tag != null:
		a.name_tag.hide()
	var speed: float = g.drive(a, dt)
	g.follow_cam(a)
	a.animate(dt, speed)
	_tick_living_world(dt, a, speed)
	_visuals(dt)
	_shop_visuals(dt)
	if g.cockpit_prompt(a.position):
		return
	if home_alliance == g.home_alliance():
		if g.flat_dist(a.position, shop_computer) < 3.6 and is_instance_valid(shop_kiosk_node):
			_shop_interact(a)
		else:
			var target: Vector3 = g.cockpit_position() if g.sim.flight_capable() else shop_computer
			_point_beacon(target, "BOARDING RAMP" if g.sim.flight_capable() else "PARTS SHOP")
			g.hud.set_prompt(beacon_label, "%d m" % int(g.flat_dist(a.position, target)))
	else:
		g.hud.set_prompt("")


func _first_part(assigned_role: int, stage: String) -> Variant:
	for p in g.sim.parts:
		if p["owner"] == assigned_role and p["stage"] == stage:
			return p
	return null


func _part_dist(a: Actor, p) -> float:
	return g.footprint_distance(a.position, to_local(_crane_slot(p)), p["dims"] * ShipModel.VESSEL_SCALE)


func _rack_point(r: int) -> Vector3:
	var c = rack_centers[r]
	return Vector3(c[0], 0, c[1] + (2.6 if c[1] < 0 else -2.6))


func _point_beacon(p: Vector3, label: String) -> void:
	beacon_target = p
	beacon_label = label
	beacon.visible = true
	beacon.position = Vector3(p.x, 20, p.z)


func _construction_here() -> bool:
	return home_alliance == g.home_alliance() and not is_instance_valid(g.vessel)


func _interact(r: int, a: Actor, dt: float) -> String:
	var s: Sim = g.sim
	var c = s.carry[r]
	if empire_layer != null and c == null:
		var terminal := empire_layer.nearest_interactable(a.global_position)
		if not terminal.is_empty():
			g.hud.set_prompt(terminal["prompt"].replace("[E]", "E"), "Alliance Treasury · %d CR" % int(s.empire.treasury[s.empire_home]))
			if g.pressed(KEY_E):
				var result := empire_layer.interact(a.global_position, r == 1)
				if not result.get("ok", false):
					g.hud.toast(str(result.get("reason", "Unavailable")).replace("_", " ").capitalize())
			return ""
	if c == null and g.cockpit_prompt(a.position):
		return ""
	var onboard: int = s.flag_counts(0)["onboard"]
	if onboard > 0 and home_alliance == g.home_alliance():
		var distance: float = g.flat_dist(a.position, Sim.DELIVERY_PAD)
		if distance <= 5.0:
			g.hud.set_prompt("HOLD E  DELIVER SCIENCE FLAGS", "%d on board" % onboard, deliver_clock / 0.8)
			if g.held(KEY_E):
				_deliver_step(dt, distance)
				return "work"
		else:
			_point_beacon(Sim.DELIVERY_PAD, "DELIVERY")
			g.hud.set_prompt("HOME DELIVERY PAD", "%d flags on board" % onboard)
		return ""
	if not _construction_here():
		g.hud.set_prompt("")
		return ""
	if s.flight_capable() and c == null:
		_point_beacon(g.cockpit_position(), "BOARDING RAMP")
		g.hud.set_prompt("BOARDING RAMP", "%d m · walk up the ramp to board" % int(g.flat_dist(a.position, g.cockpit_position())))
		return ""
	if s.shop_open or (pad_stage == "shop" and s.construction_supplied()):
		return _shop_interact(a)
	if s.auto_build["enabled"]:
		g.hud.set_prompt("FAST ASSEMBLY", "Robotic arms are fetching, setting and bolting every module · %d/12 secured" % s.secured_count(), s.auto_build["t"] / Sim.AUTO_BUILD_SECONDS)
		return ""
	if c != null:
		var p = s.part_by_id(c)
		var d := _part_dist(a, p)
		_point_beacon(to_local(_crane_slot(p)), p["name"])
		if g.pressed(KEY_R):
			s.rotate_carried(r)
			g.sfx("reload_click", -6)
		var ok: bool = s.rotation[r] == p["angle"]
		if d <= 3.0:
			if ok:
				g.hud.set_prompt("E  SET %s IN SLOT" % p["name"].to_upper(), "Orientation matches the marked slot.")
			else:
				g.hud.set_prompt("R  ROTATE MODULE  (%d/4)" % (s.rotation[r] + 1), "Orientation must match the marked slot — the ghost turns green.")
			if g.pressed(KEY_E):
				if s.place_part(r, d):
					g.sfx("reload_ratchet" if g.streams.has("reload_ratchet") else "reload_click")
					g.hud.toast(p["lesson"], 4.0)
				else:
					g.hud.toast("Rotate the module until the ghost turns green.")
		else:
			g.hud.set_prompt("CARRY %s TO THE SHIP" % p["name"].to_upper(), "Follow the beacon · %d m · R rotates" % int(d))
		return ""
	var pos = null
	var best := 3.5
	for p in s.parts:
		if p["owner"] == r and p["stage"] == "positioned":
			var d := _part_dist(a, p)
			if d <= best:
				best = d
				pos = p
	if pos != null:
		var bolt: int = pos["bolts"].find_custom(func(b): return b < 1.0)
		var prog: float = (pos["bolts"][0] + pos["bolts"][1] + pos["bolts"][2]) / 3.0
		g.hud.set_prompt("HOLD LMB  FASTEN BOLT %d/3" % (bolt + 1), pos["name"], prog)
		if g.lmb and not a.weapon_drawn:
			var before: String = pos["stage"]
			s.fasten_bolt(pos["id"], bolt, r, dt, best)
			if pos["stage"] == "secured" and before != "secured":
				g.sfx("capture_tick", -4)
				g.hud.toast("%s secured · %d/12" % [pos["name"], s.secured_count()])
			return "work"
		return ""
	var waiting = _first_part(r, "positioned")
	if waiting != null:
		_point_beacon(to_local(_crane_slot(waiting)), waiting["name"])
		g.hud.set_prompt("FASTEN %s" % waiting["name"].to_upper(), "Walk to the beacon and hold LMB on its bolts.")
		return ""
	var next = _first_part(r, "shelf")
	if next != null:
		var rp := _rack_point(r)
		if g.flat_dist(a.position, rp) <= 4.5:
			g.hud.set_prompt("E  PICK UP %s" % next["name"].to_upper(), "BOUGHT AT THE PARTS SHOP" if next["purchased"] else "%d CREDITS · %d available" % [next["price"], s.credits])
			if g.pressed(KEY_E):
				if s.pick_part(next["id"], r):
					g.sfx("reload_click", -4)
				else:
					g.hud.toast("Not enough credits for this module.")
		else:
			_point_beacon(rp, "%s RACK" % Sim.SPECIALISTS[r]["name"].to_upper())
			g.hud.set_prompt("GO TO YOUR RACK", "Next module: %s · %d m" % [next["name"], int(g.flat_dist(a.position, rp))])
		return ""
	g.hud.set_prompt("YOUR MODULES ARE SECURED", "The crew is finishing theirs. Switch roles with 1–4 to help.")
	return ""


func _deliver_step(dt: float, d: float) -> void:
	deliver_clock += dt
	if deliver_clock >= 0.8:
		deliver_clock = 0.0
		if g.sim.deliver_flag(0, d):
			g.sfx("capture_tick", -2)
			if g.sim.empire != null and g.sim.flag_counts(0)["onboard"] == 0:
				g.sim.service_empire_ship()


func _approach(p, from: Vector3) -> Vector3:
	var slot := to_local(_crane_slot(p))
	var dims: Vector3 = p["dims"] * ShipModel.VESSEL_SCALE
	var sgn := signf(slot.x) if absf(slot.x) > 0.5 else (signf(from.x) if absf(from.x) > 0.01 else 1.0)
	var edge := maxf(Sim.SHIP_SCALE * ShipModel.VESSEL_SCALE, absf(slot.x) + dims.x * 0.5)
	return Vector3(sgn * (edge + 1.1), 0, slot.z)


func _bot(i: int, dt: float) -> void:
	var s: Sim = g.sim
	var a: Actor = actors[i]
	var b: Dictionary = bots[i]
	b["t"] -= dt
	var work := ""
	var speed := 4.4
	if _construction_here():
		if s.shop_open or s.auto_build["enabled"] or (pad_stage == "shop" and s.construction_supplied()):
			a.walk_to(Vector3(-8 + i * 5, 0, 26), dt, speed, 0.5)
		else:
			var c = s.carry[i]
			if c != null:
				var p = s.part_by_id(c)
				if a.walk_to(_approach(p, a.position), dt, speed) < 0.5 and b["t"] <= 0.0:
					if s.rotation[i] != p["angle"]:
						s.rotate_carried(i)
						b["t"] = 0.3
					else:
						s.place_part(i, _part_dist(a, p))
						b["t"] = 0.4
			else:
				var p = _first_part(i, "positioned")
				if p != null:
					if a.walk_to(_approach(p, a.position), dt, speed) < 0.6:
						var bolt: int = p["bolts"].find_custom(func(x): return x < 1.0)
						s.fasten_bolt(p["id"], bolt, i, dt * 0.9, _part_dist(a, p), true, false)
						a.face(p["slot"] - a.position, dt)
						work = "work"
				else:
					p = _first_part(i, "shelf")
					if p != null:
						if a.walk_to(_rack_point(i), dt, speed) < 0.6:
							if b.get("arrived", false) == false:
								b["arrived"] = true
								b["t"] = 0.6
							elif b["t"] <= 0.0:
								s.pick_part(p["id"], i)
								b["arrived"] = false
					else:
						a.walk_to(Vector3(-8 + i * 5, 0, 26), dt, speed, 0.5)
	elif home_alliance == g.home_alliance() and s.flag_counts(0)["onboard"] > 0:
		a.walk_to(Sim.DELIVERY_PAD + Vector3(-6 + i * 4, 0, -5), dt, speed, 0.5)
	_bot_defend(i, a, dt, work.is_empty())
	a.animate(dt, a.vel.length(), work, s.carry[i] != null)
	a.vel = Vector3.ZERO


func _visuals(dt: float) -> void:
	var s: Sim = g.sim
	var manual := lift_state > LiftState.GROUND and lift_state < LiftState.PARKED
	var shelf_index := [0, 0, 0, 0]
	var on_gse := not gse_routes.is_empty() and (manual or pad_stage == "shop")
	for p in s.parts:
		var sn: Dictionary = slot_nodes[p["id"]]
		var node: Node3D = sn["node"]
		var preview: Node3D = shelf_nodes[p["id"]]
		var st: String = p["stage"]
		node.visible = st in ["positioned", "secured"]
		preview.visible = st == "shelf" and p["purchased"] and not on_gse
		if st == "shelf" and not on_gse:
			var assigned_role: int = p["owner"]
			var c = rack_centers[assigned_role]
			var k: int = shelf_index[assigned_role]
			shelf_index[assigned_role] += 1
			preview.position = Vector3(c[0] - 2.2 + k * 2.2, 1.95, c[1])
			preview.rotation.y += dt * 0.4
		for bi in 3:
			var bolt: MeshInstance3D = sn["bolts"][bi]
			bolt.visible = st == "positioned"
			bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bolt.material_override = _bolt_materials[6 if p["bolts"][bi] >= 1.0 else clampi(roundi(p["bolts"][bi] / 0.2), 0, 5)]
	for x in s.cargo:
		cargo_nodes[x["id"]].visible = not x["stowed"] and not s.carry.has("cargo:" + x["id"])
	for i in 4:
		var key := str(null if manual else s.carry[i])
		if key != carry_vis[i]:
			carry_vis[i] = key
			var n: Node3D = null
			if not manual and s.carry[i] != null:
				if key.begins_with("cargo:"):
					n = Gfx.box(Vector3(1.2, 0.8, 0.8), Color("#e9e4f2"))
				else:
					var p = s.part_by_id(s.carry[i])
					n = ShipModel.preview(p["id"], str(g.sim.loadout.get(p["id"], "kestrel")), accent)

			actors[i].set_carry(n)
		var sock: Node3D = actors[i].carry_socket
		if sock.get_child_count() > 0 and not key.begins_with("cargo:"):
			sock.get_child(0).rotation.y = s.rotation[i] * PI * 0.5 - actors[i].rotation.y
	# The selected claw's target stays at the actual module transform.
	var r := s.selected
	var part = null
	if _construction_here() and s.carry[r] != null:
		part = s.part_by_id(s.carry[r])
	elif manual and crane_marker.visible and _construction_here():
		part = _first_part(r, "positioned")
	var want := ""
	if part != null:
		want = str(part["id"]) if manual else "%s:%d" % [part["id"], s.rotation[r]]
	if want != ghost_key:
		ghost_key = want
		if ghost:
			ghost.queue_free()
			ghost = null
		if part != null:
			ghost = ShipModel.module(part["id"], str(s.loadout.get(part["id"], "kestrel")), accent, true)
			if manual:
				crane_ghost_material = Gfx.unshaded(Color("#82e6ff"), 0.35).duplicate() as StandardMaterial3D
				_tint(ghost, crane_ghost_material)
				add_child(ghost)
				ghost.global_transform = (slot_nodes[part["id"]]["node"] as Node3D).global_transform
			else:
				var ok: bool = s.rotation[r] == part["angle"]
				_tint(ghost, Gfx.unshaded(Color("#9cdeb1") if ok else Color("#ed7d8d"), 0.28))
				add_child(ghost)
				ghost.global_transform = (slot_nodes[part["id"]]["node"] as Node3D).global_transform
				ghost.rotate_y((s.rotation[r] - part["angle"]) * PI * 0.5)
	if manual and ghost != null and part != null:
		var aligned: bool = g.flat_dist(fx_arms[r]["target"], _crane_placement_grip(part)) <= CRANE_GRAB_RADIUS
		var color := Color("#64ff78") if aligned else Color("#82e6ff")
		color.a = (0.62 if aligned else 0.32) + sin(Time.get_ticks_msec() * 0.008) * 0.14
		crane_ghost_material.albedo_color = color
	# Rival pads on Earth.
	for rs in rival_ships:
		var t = s.teams[rs["team"]]
		var node: Node3D = rs["node"]
		var on_a: bool = t["planet"] == "A" and not t["eliminated"]
		if s.empire != null:
			var squad: Dictionary = s.empire.squads[rs["empire_squad"]]
			node.visible = squad["location"] == s.empire_home
			rs["label"].visible = true
			continue
		node.visible = on_a
		rs["label"].visible = on_a
		if not on_a:
			continue
		var shown := 12
		if t["phase"] == "building":
			shown = int(clampf(t["progress"] / 0.3, 0.0, 1.0) * 12.0)
		var idx := 0
		for ch in node.get_children():
			if ch.name in ["keel", "port", "bridge", "reactor", "battery", "coolant", "cargo", "scrubber", "stores", "engine", "thruster", "antenna"]:
				ch.visible = idx < shown
				idx += 1
		var rp: Vector3 = rs["pos"]
		node.position.x = rp.x
		node.position.z = rp.z


func _tint(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_tint(c, m)


# ---------------------------------------------------------------------------
# Automated machine assembly: holographic modules streak in, robot arms weld them on.
# ---------------------------------------------------------------------------
func _fx_init() -> void:
	fx_ready = true
	for p in g.sim.parts:
		var node: Node3D = slot_nodes[p["id"]]["node"]
		fx_base[p["id"]] = node.position
		for m in node.find_children("*", "MeshInstance3D", true, false):
			fx_orig_mats[m] = (m as MeshInstance3D).material_override
	if fx_arms.is_empty():
		_create_crane_arms()


func _create_crane_arms() -> void:
	# Four gantry arms around the ship.
	var bases := crane_bases
	for i in bases.size():
		var b: Vector3 = bases[i]
		var color := Sim.role_color(i)
		var arm := {"base": b, "reach": 50.0}
		arm["base"] = b + Vector3(0, 7.0, 0)
		arm["upper"] = _fx_link(Color("#ece7f4"), 0.8)
		arm["lower"] = _fx_link(color, 0.6)
		var tip := Hardware.tool()
		for sign in [-1.0, 1.0]:
			var jaw := Gfx.box(Vector3(0.19, 0.85, 0.38), color, Vector3(sign * 0.66, -0.91, 0))
			jaw.rotation.z = -sign * 0.28
			tip.add_child(jaw)
		add_child(tip)
		arm["tip"] = tip
		arm["shoulder"] = Hardware.joint(1.1)
		arm["elbow"] = Hardware.joint(.9)
		add_child(arm["shoulder"])
		add_child(arm["elbow"])
		arm["target"] = b + Vector3(0, 12, 0)
		fx_arms.append(arm)
		_fx_arm_pose(arm, arm["target"])


func _fx_link(col: Color, r: float) -> Node3D:
	var pivot := Hardware.link(col, r)
	add_child(pivot)
	return pivot


func _fx_place_link(link: Node3D, a: Vector3, b: Vector3) -> void:
	var length := maxf(.05, a.distance_to(b))
	var up := Vector3.UP if absf((b-a).normalized().y) < .99 else Vector3.RIGHT
	link.look_at_from_position(a, b, up)
	link.scale = Vector3(1,1,length/15.0)


func _fx_arm_pose(arm: Dictionary, target: Vector3) -> void:
	var base: Vector3 = arm["base"]
	var d := target - base
	var dist := clampf(d.length(), 0.05, arm["reach"])
	var dir := d.normalized() if d.length_squared() > 0.0 else Vector3.UP
	var half_span := dist * 0.5
	var link_length := clampf(dist * 0.57, 3.0, 25.2)
	var h := sqrt(maxf(0.0, link_length * link_length - half_span * half_span))
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var pole := side.cross(dir).normalized()
	if pole.y < 0.0:
		pole = -pole
	var elbow := base + dir * half_span + pole * h
	var tip := base + dir * dist
	_fx_place_link(arm["upper"], base, elbow)
	_fx_place_link(arm["lower"], elbow, tip)
	(arm["tip"] as Node3D).position = tip
	(arm["shoulder"] as Node3D).position = base
	(arm["elbow"] as Node3D).position = elbow
	(arm["shoulder"] as Node3D).rotation.y = atan2(dir.x,dir.z)
	(arm["elbow"] as Node3D).rotation.y = atan2(dir.x,dir.z)


func _fx_spark(at: Vector3, col := Color("#ffd27a")) -> void:
	var sp := Gfx.box(Vector3(.035,.035,.20), col, at, 3.0)
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sp)
	fx_sparks.append({"node": sp, "v": Vector3(randf_range(-6, 6), randf_range(3, 9), randf_range(-6, 6)), "life": randf_range(0.3, 0.7)})


func _fx_snap(world_pos: Vector3, big := 1.0) -> void:
	if fx_light == null:
		fx_light = OmniLight3D.new()
		fx_light.omni_range = 40.0
		add_child(fx_light)
	fx_light.global_position = world_pos
	fx_light.light_color = Color("#ffb76b")
	fx_light.light_energy = 2.0 * big
	for i in 6:
		_fx_spark(world_pos, Color("#ffc278"))


func _fx_holo(node: Node3D, _on: bool, key: String, _flicker: float) -> void:
	# Physical hardware keeps its finish throughout handling and fastening.
	if fx_holo.get(key, false):
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			if fx_orig_mats.has(mi):
				(mi as MeshInstance3D).material_override = fx_orig_mats[mi]
	fx_holo[key] = false


func _build_fx(_k_total: float, dt: float) -> void:
	var s: Sim = g.sim
	if not fx_ready:
		_fx_init()
	var t: float = s.auto_build["t"]
	var n := s.parts.size()
	var w := 2.5
	var gap := (Sim.AUTO_BUILD_SECONDS - w) / float(n - 1)
	var active_world: Array = []
	var flick := 1.0 if int(Time.get_ticks_msec() / 70.0) % 2 == 0 else 0.0
	for i in n:
		var part: Dictionary = s.parts[i]
		var id: String = part["id"]
		var sn: Dictionary = slot_nodes[id]
		var node: Node3D = sn["node"]
		for b in sn["bolts"]:
			(b as Node3D).visible = false
		var k: float = (t - i * gap) / w
		node.visible = k > 0.0
		if k <= 0.0:
			continue
		var base: Vector3 = fx_base[id]
		var ang := float(i) * 2.399
		var from := Vector3(cos(ang) * 9.0, 6.0, sin(ang) * 9.0)
		if k < 0.5:
			var e := smoothstep(0.0, 1.0, k / 0.5)
			var lag := pow(1.0 - e, 2.0)
			node.position = base + from * lag
			node.rotation = Vector3.ZERO
			node.scale = Vector3.ONE
			_fx_holo(node, true, id, flick)
			active_world.append(node.global_position)
		elif k < 0.85:
			node.position = base
			node.rotation = Vector3.ZERO
			node.scale = Vector3.ONE
			_fx_holo(node, true, id, flick)
			active_world.append(node.global_position)
			if randf() < dt * 40.0:
				_fx_spark(node.global_position + Vector3(randf_range(-2, 2), randf_range(-1, 2), randf_range(-3, 3)))
		else:
			node.position = base
			node.rotation = Vector3.ZERO
			node.scale = Vector3.ONE
			_fx_holo(node, false, id, flick)
			if not fx_done.get(id, false):
				fx_done[id] = true
				_fx_snap(node.global_position)
				g.sfx("reload_ratchet" if g.streams.has("reload_ratchet") else "reload_click", -3)
	# Arms reach for the active pieces; idle ones hover over the ship.
	for ai in fx_arms.size():
		var arm: Dictionary = fx_arms[ai]
		var goal: Vector3 = Vector3(arm["base"].x * 0.2, 14.0, arm["base"].z * 0.2)
		if not active_world.is_empty():
			goal = active_world[ai % active_world.size()]
		arm["target"] = (arm["target"] as Vector3).lerp(goal, clampf(dt * 6.0, 0.0, 1.0))
		_fx_arm_pose(arm, arm["target"])
		if not active_world.is_empty() and randf() < dt * 25.0:
			_fx_spark((arm["tip"] as Node3D).position)
	# Sparks + flash decay.
	for sp in fx_sparks.duplicate():
		sp["life"] -= dt
		sp["v"].y -= 14.0 * dt
		(sp["node"] as Node3D).position += sp["v"] * dt
		if sp["life"] <= 0.0:
			(sp["node"] as Node3D).queue_free()
			fx_sparks.erase(sp)
	if fx_light != null:
		fx_light.light_energy = maxf(0.0, fx_light.light_energy - dt * 30.0)


## Machines carry the cargo crates to the hatch and run the systems checks by themselves.
func _outfit_fx(k: float, dt: float) -> void:
	var s: Sim = g.sim
	if not fx_ready:
		_fx_init()
	var t := k * 6.5
	var hatch := CARGO_HATCH + Vector3(0, 3.0, 0)
	var active: Array = []
	for i in s.cargo.size():
		var c: Dictionary = s.cargo[i]
		var node: Node3D = cargo_nodes[c["id"]]
		if not fx_cargo_base.has(c["id"]):
			fx_cargo_base[c["id"]] = node.position
		var base: Vector3 = fx_cargo_base[c["id"]]
		var e := clampf((t - i * 1.0) / 2.0, 0.0, 1.0)
		var pos := base.lerp(hatch, smoothstep(0.0, 1.0, e)) + Vector3(0, sin(e * PI) * 10.0, 0)
		node.position = pos
		node.scale = Vector3.ONE * lerpf(1.0, 0.4, e)
		node.visible = e < 1.0
		_fx_holo(node, e > 0.0 and e < 1.0, "cargo" + str(i), 1.0 if int(Time.get_ticks_msec() / 70.0) % 2 == 0 else 0.0)
		if e > 0.0 and e < 1.0:
			active.append(pos)
		elif e >= 1.0 and not fx_done.get("cargo" + str(i), false):
			fx_done["cargo" + str(i)] = true
			_fx_snap(hatch, 0.6)
	# Console rings pulse as each check completes.
	var ci := 0
	for type in CONSOLES.keys():
		var key: String = "check" + str(type)
		if t > 3.0 + ci * 0.9 and not fx_done.get(key, false):
			fx_done[key] = true
			var cp: Vector3 = console_points[type]
			var r := Gfx.ring(1.2, 0.4, Color("#9cdeb1"), 0.95)
			r.position = cp + Vector3(0, 0.3, 0)
			add_child(r)
			var tw := create_tween()
			tw.tween_property(r, "scale", Vector3(6, 0.05, 6), 0.9)
			tw.tween_callback(r.queue_free)
			g.sfx("reload_click", -4)
		ci += 1
	for ai in fx_arms.size():
		var arm: Dictionary = fx_arms[ai]
		var goal := Vector3(arm["base"].x * 0.2, 14.0, arm["base"].z * 0.2)
		if not active.is_empty():
			goal = active[ai % active.size()]
		arm["target"] = (arm["target"] as Vector3).lerp(goal, clampf(dt * 6.0, 0.0, 1.0))
		_fx_arm_pose(arm, arm["target"])
	_fx_sparks_tick(dt)


func _fx_sparks_tick(dt: float) -> void:
	for sp in fx_sparks.duplicate():
		sp["life"] -= dt
		sp["v"].y -= 14.0 * dt
		(sp["node"] as Node3D).position += sp["v"] * dt
		if sp["life"] <= 0.0:
			(sp["node"] as Node3D).queue_free()
			fx_sparks.erase(sp)
	if fx_light != null:
		fx_light.light_energy = maxf(0.0, fx_light.light_energy - dt * 30.0)


func _fx_finish() -> void:
	for mi in fx_orig_mats.keys():
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_override = fx_orig_mats[mi]
	for arm in fx_arms:
		for key in ["upper", "lower", "shoulder", "elbow"]:
			(arm[key] as Node3D).visible = false
		(arm["tip"] as Node3D).visible = false


func cine(kind: String, k: float, dt: float) -> void:
	match kind:
		"build":
			_build_fx(k, dt)
		"outfit":
			_outfit_fx(k, dt)




## Warm dynamic engine light that floods the pad and towers during liftoff, fading as the ship climbs away.
func arrive_home(pad_position := Vector3.ZERO) -> void:
	delivery = true
	ship_root.transform = Transform3D(Basis.from_scale(Vector3.ONE * ShipModel.VESSEL_SCALE), pad_position)
	ship_root.visible = true
	for c in _landing_nodes:
		c.visible = true
	for r in 4:
		var a: Actor = actors[r]
		a.visible = true
		a.position = Vector3(-6 + r * 4, 0, 24)
		a.heading = atan2(a.position.x, a.position.z)
		a.rotation.y = a.heading


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func hud_update(hud: Hud) -> void:
	var s: Sim = g.sim
	var a: Actor = actors[s.selected]
	var counts := s.flag_counts(0)
	hud.title.text = planet_label
	if counts["onboard"] > 0 and home_alliance == g.home_alliance():
		hud.subtitle.text = "%d FLAGS ON BOARD · %d DELIVERED" % [counts["onboard"], counts["delivered"]]
		hud.objectives.text = "HOLD E AT THE DELIVERY PAD"
	elif s.flight_capable():
		hud.subtitle.text = "SHIP READY"
		hud.objectives.text = "E AT THE COCKPIT TO BOARD"
	else:
		hud.subtitle.text = "%d MODULES SECURED · %d CR" % [s.secured_count(), s.credits]
		hud.objectives.text = "BUILD REACTOR, ENGINE AND BRIDGE"
	hud.vitals_panel.visible = false
	hud.station_panel.visible = false
	var defending := empire_layer != null and not empire_layer.raid_groups.is_empty() and _can_defend(s.selected)
	hud.crosshair.visible = defending and a.weapon_drawn
	hud.footer.text = "WASD MOVE · SHIFT SPRINT · SPACE JUMP · V VIEW · 1–4 ROLES · E INTERACT · R ROTATE · LMB FASTEN · M MAP · H HINTS · ESC MENU"
	if defending:
		var weapon_status := "RELOADING" if a.weapon_reload > 0.0 else "%d/%d" % [_defense_ammo[s.selected], DEFENSE_MAGAZINE]
		hud.footer.text = "B HOLSTER · LMB FIRE · R RELOAD · %s     E INTERACT" % weapon_status if a.weapon_drawn \
			else "B DRAW BLASTER     E INTERACT · LMB FASTEN · R ROTATE · M MAP"
	hud.radar_title.text = planet_label
	for i in 4:
		var owned := s.parts.filter(func(p): return p["owner"] == i)
		var done := owned.filter(func(p): return p["stage"] == "secured").size()
		var status := "READY" if s.flight_capable() else "%d/%d SECURED" % [done, owned.size()]
		hud.set_crew_status(i, status + (" · YOU" if i == s.selected else " · BOT"), float(done) / maxf(1.0, owned.size()))
	var pts: Array = []
	var origin := a.position
	var rot: float = g.yaw
	var add := func(p: Vector3, col: Color, size: float, ring: bool, label: String):
		var offset := p - origin
		pts.append({"p": Vector2(offset.x, offset.z).rotated(rot), "c": col, "s": size,
			"ring": ring, "label": label, "dist": offset.length()})
	add.call(Vector3.ZERO, Color("#ece7f4"), 6.0, true, "PAD")
	if not beacon.visible or beacon_target != shop_pos:
		add.call(shop_pos, Color("#ffd29a"), 4.5, true, "SHOP")
	for i in 4:
		var specialist: String = Sim.SPECIALISTS[i]["name"]
		add.call(_rack_point(i), Sim.role_color(i), 3.0, true, "%s RACK" % specialist.to_upper())
		if i != s.selected:
			add.call(actors[i].position, Sim.role_color(i), 3.0, false, specialist)
	for x in s.cargo:
		if not x["stowed"]:
			add.call(x["position"], Color("#e9e4f2"), 2.5, false, x["name"])
	add.call(Sim.DELIVERY_PAD, Color("#eaa665"), 4.0, true, "DELIVERY")
	if beacon.visible:
		add.call(beacon_target, Color("#ffd29a"), 4.5, false, beacon_label)
	hud.radar.points = pts
	hud.radar.range_m = 60.0
	hud.radar.request_redraw()
	hud.tactical_radar.cover_shapes.clear()
	hud.update_tactical(pts, planet_label + " · LIVE TACTICAL MAP")


# ===========================================================================
# Menu showcase hangar
# ===========================================================================
class Showcase extends Node3D:
	const PAD_COLORS := [Color("#ec4899"), Color("#84cc16"), Color("#0ea5e9"), Color("#f59e0b")]
	const SEL_POSES := ["celebrate", "wave", "work", "scan"]
	var g
	var actors: Array = []
	var kind := "home"
	var sel := 3
	var t := 0.0
	var focus := "PLAY"

	var podium_rings: Array = []
	var lobby_ships: Array = []   # {node, speed, y, z, x_min, x_max}
	var lobby_planet: Node3D
	var planet_pivot: Node3D
	var planet_base := Vector3.ZERO
	var planet_rim: MeshInstance3D
	var rim_mat: StandardMaterial3D
	var lobby_moon: Node3D
	var kiosk_holos: Array = []   # floating holo bits {node, y, phase}
	var pads: Array = []          # {root, core, beam, uplight, rim, ring_mat, core_mat, beam_mat}
	var sel_blend: Array = [0.0, 0.0, 0.0, 0.0]
	var dim_cache: Array = [-1.0, -1.0, -1.0, -1.0]
	var actor_meshes: Array = [null, null, null, null]
	var cam_pos := Vector3(0.0, 2.05, 10.6)
	var cam_look := Vector3(0.0, 1.15, -1.0)
	var cam_ready := false
	var world_env: WorldEnvironment
	var cam_attr: CameraAttributesPractical
	var home_spaceport: Node3D
	var hangar_props: Array = []   # select-only props (PLAY console)
	var console_mat: StandardMaterial3D
	var console_light: OmniLight3D
	var console_holo: Node3D
	var tab_holos: Dictionary = {}  # tab name -> {mat, base_a, light, base_e}

	func set_focus(tab: String) -> void:
		focus = tab

	func _focus_target() -> Array:
		match focus:
			"SHOP", "LEADERBOARD", "GUIDE":
				# Selected specialist framed in the LEFT third; camera shifted right, looking past them.
				var bx := -5.4 + sel * 3.6
				return [Vector3(bx + 1.5, 1.9, 6.4), Vector3(bx + 2.6, 1.45, 0.8)]
			"PROFILE":
				return [Vector3(3.4, 2.7, 1.8), Vector3(8.0, 3.0, -6.6)]
		var pbx := -5.4 + sel * 3.6
		return [Vector3(pbx * 0.24 + sin(t * 0.14) * 0.28, 2.05, 10.6), Vector3(pbx * 0.36, 1.35, -1.5)]

	func _meshes_of(n: Node, out: Array) -> void:
		if n is GeometryInstance3D:
			out.append(n)
		for c in n.get_children():
			_meshes_of(c, out)

	func tick(dt: float) -> void:
		t += dt
		var k := clampf(dt * 3.0, 0.0, 1.0)
		for i in actors.size():
			var a: Actor = actors[i]
			var is_sel := kind == "select" and i == sel
			sel_blend[i] = lerpf(sel_blend[i], 1.0 if is_sel else 0.0, clampf(dt * 3.5, 0.0, 1.0))
			var sb: float = sel_blend[i]
			# Lively staggered idle emotes; the selected specialist holds a role-specific pose.
			var cycle := fmod(t + i * 2.1, 7.5)
			var act := ""
			if kind == "select":
				if is_sel:
					act = SEL_POSES[i % SEL_POSES.size()] if sb > 0.55 else ""
				elif cycle > 5.8:
					act = "wave"
				elif cycle > 3.4 and cycle < 4.4:
					act = "scan"
			a.animate(dt, 0.0, act)
			if kind == "select":
				var base_x := -5.4 + i * 3.6
				var back_z := 0.15 if i % 2 == 1 else -0.35
				var base_z := lerpf(back_z - 0.35, 1.25, sb)
				a.position = Vector3(base_x, 0.0, base_z)
				var glance := sin(t * (0.9 + i * 0.17) + i * 1.4) * lerpf(0.30, 0.10, sb)
				a.rotation.y = PI + glance
				var breathe := 1.0 + sin(t * 2.1 + i * 1.3) * 0.012
				var s_target := lerpf(0.94, 1.1, sb)
				a.scale = Vector3(1.0, breathe, 1.0) * s_target
				# Darken/fade the unselected specialists into the backdrop.
				var fade := snappedf((1.0 - sb) * 0.38, 0.02)
				if absf(fade - float(dim_cache[i])) > 0.001:
					dim_cache[i] = fade
					if actor_meshes[i] == null:
						var arr: Array = []
						_meshes_of(a, arr)
						actor_meshes[i] = arr
					for m in actor_meshes[i]:
						if is_instance_valid(m):
							(m as GeometryInstance3D).transparency = fade
				if i < podium_rings.size():
					var ring: MeshInstance3D = podium_rings[i]
					ring.position = Vector3(base_x, 0.13, 0.0)
					var pulse := 1.0 + (0.04 + 0.05 * sb) * sin(t * 3.4 + i)
					ring.scale = Vector3(pulse, 0.05, pulse) * lerpf(0.94, 1.2, sb)
				if i < pads.size():
					var p: Dictionary = pads[i]
					var pc: Color = PAD_COLORS[i]
					(p["uplight"] as OmniLight3D).light_energy = lerpf(0.5, 3.6, sb) * (1.0 + 0.1 * sin(t * 4.0 + i))
					(p["rim"] as SpotLight3D).light_energy = lerpf(0.5, 9.0, sb)
					# Warm overhead pad spot: high-contrast focal light on the selected specialist.
					(p["spot"] as SpotLight3D).light_energy = lerpf(0.35, 11.0, sb)
					(p["core_mat"] as StandardMaterial3D).emission_energy_multiplier = lerpf(0.6, 3.2, sb) * (1.0 + 0.15 * sin(t * 5.0 + i))
					(p["beam_mat"] as StandardMaterial3D).albedo_color = Color(pc.r, pc.g, pc.b, lerpf(0.05, 0.26, sb))
					var beam: MeshInstance3D = p["beam"]
					beam.scale = Vector3(1.0, lerpf(0.7, 1.0, sb), 1.0)
		# Cinematic DoF only in the lobby so the selected specialist stays crisp.
		_update_dof()
		# PLAY console + tab holo projections pulse; the focused one glows brightest.
		if console_mat != null:
			var play_on := focus == "PLAY"
			console_mat.emission_energy_multiplier = (2.8 if play_on else 1.4) + 0.5 * sin(t * 2.6)
			console_light.light_energy = (2.4 if play_on else 1.0) + 0.3 * sin(t * 2.6)
			if console_holo != null:
				console_holo.position.y = 1.15 + sin(t * 1.5) * 0.04
		for key in tab_holos:
			var th: Dictionary = tab_holos[key]
			var on: bool = focus == key or (key == "LEADERBOARD" and focus == "GUIDE")
			var tgt_a: float = float(th["base_a"]) * (2.2 if on else 0.8)
			var tgt_e: float = float(th["base_e"]) * (2.0 if on else 0.7)
			var pm_: StandardMaterial3D = th["mat"]
			pm_.albedo_color.a = lerpf(pm_.albedo_color.a, tgt_a, clampf(dt * 4.0, 0.0, 1.0))
			var tl: OmniLight3D = th["light"]
			tl.light_energy = lerpf(tl.light_energy, tgt_e, clampf(dt * 4.0, 0.0, 1.0))
		# Planet: axial tilt (pivot), steady spin, orbiting moon, rim pulse, parallax.
		if lobby_planet != null:
			lobby_planet.rotation.y += dt * 0.05
		if planet_pivot != null:
			planet_pivot.position = planet_base + Vector3(-g.cam.position.x * 0.35, g.cam.position.y * -0.15, 0.0)
		if planet_rim != null:
			planet_rim.scale = Vector3.ONE * (1.0 + 0.012 * sin(t * 1.3))
			rim_mat.albedo_color.a = 0.16 + 0.07 * sin(t * 1.3)
		if lobby_moon != null:
			var ang := t * 0.12
			lobby_moon.position = planet_base + Vector3(cos(ang) * 23.0, sin(ang * 0.7) * 4.0 + 2.0, sin(ang) * 9.0)
			lobby_moon.rotation.y += dt * 0.1
		for h in kiosk_holos:
			var hn: Node3D = h["node"]
			hn.position.y = float(h["y"]) + sin(t * 1.4 + float(h["phase"])) * 0.12
			hn.rotation.y += dt * 0.8
		for sh in lobby_ships:
			var n: Node3D = sh["node"]
			n.position.x += float(sh["speed"]) * dt
			n.position.y = float(sh["y"]) + sin(t * 0.9 + float(sh["phase"])) * 0.45
			if float(sh["speed"]) > 0.0 and n.position.x > float(sh["x_max"]):
				n.position.x = float(sh["x_min"])
			elif float(sh["speed"]) < 0.0 and n.position.x < float(sh["x_min"]):
				n.position.x = float(sh["x_max"])
		if kind == "home":
			g.cam.position = Vector3(-0.6 + sin(t * 0.15) * 0.2, 2.9, 6.0)
			g.cam.look_at(Vector3(1.9, 1.55, 0))
			cam_ready = false
		else:
			var ft := _focus_target()
			if not cam_ready:
				cam_pos = ft[0]
				cam_look = ft[1]
				cam_ready = true
			cam_pos = cam_pos.lerp(ft[0], clampf(dt * 2.6, 0.0, 1.0))
			cam_look = cam_look.lerp(ft[1], clampf(dt * 2.6, 0.0, 1.0))
			g.cam.position = cam_pos
			g.cam.look_at(cam_look)

	func _update_dof() -> void:
		var want := kind == "select"
		if world_env != null and world_env.camera_attributes is CameraAttributesPractical:
			(world_env.camera_attributes as CameraAttributesPractical).dof_blur_far_enabled = want
		if g == null or g.cam == null:
			return
		if not want:
			if g.cam.attributes != null:
				g.cam.attributes = null
			return
		if cam_attr == null:
			cam_attr = CameraAttributesPractical.new()
		if g.cam.attributes != cam_attr:
			g.cam.attributes = cam_attr
		var d := 11.0
		if sel >= 0 and sel < actors.size():
			d = g.cam.position.distance_to((actors[sel] as Node3D).global_position) + 0.6
		cam_attr.dof_blur_far_enabled = true
		cam_attr.dof_blur_far_distance = d
		cam_attr.dof_blur_far_transition = 2.6
		cam_attr.dof_blur_amount = 0.14

	func _exit_tree() -> void:
		if g != null and is_instance_valid(g.cam) and g.cam.attributes == cam_attr:
			g.cam.attributes = null

	func layout(p_kind: String, p_sel: int) -> void:
		kind = p_kind
		sel = p_sel
		for i in actors.size():
			var a: Actor = actors[i]
			if kind == "home":
				a.visible = i == sel
				a.position = Vector3(3.2, 0, 0)
				a.rotation.y = PI - 0.35
				a.scale = Vector3.ONE * 1.08
				for m in (actor_meshes[i] if actor_meshes[i] != null else []):
					if is_instance_valid(m):
						(m as GeometryInstance3D).transparency = 0.0
				dim_cache[i] = -1.0
			else:
				a.visible = true
				var base_z := 0.85 if i == sel else (0.15 if i % 2 == 1 else -0.35)
				a.position = Vector3(-5.4 + i * 3.6, 0, base_z)
				a.rotation.y = PI
			if i < podium_rings.size():
				(podium_rings[i] as Node3D).visible = kind == "select"
			if i < pads.size():
				(pads[i]["root"] as Node3D).visible = kind == "select"
				(pads[i]["spot"] as Node3D).visible = kind == "select"
		home_spaceport.visible = kind == "home"
		planet_pivot.scale = Vector3.ONE * (0.75 if kind == "home" else 1.0)
		planet_base = Vector3(13.5, 12.0 if kind == "home" else 9.5, -36.0)
		for hp in hangar_props:
			(hp as Node3D).visible = kind == "select"
		if kind != "select":
			focus = "PLAY"


static func showcase(main) -> Node3D:
	var s := Showcase.new()
	s.g = main
	# Deep orbital galaxy & starfield space sky visible through the panoramic hangar windows.
	var we: WorldEnvironment = Gfx.environment(Color("#030612"), Color("#0e1d3a"), Color("#02040a"), 0.28, Color("#1d4d8f"), 0.006)
	var env: Environment = we.environment
	# Cool blue ambient bounce from the giant planet outside + subtle haze/glow.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#2b5ea8")
	env.ambient_light_energy = 0.55
	env.fog_sky_affect = 0.0
	env.glow_intensity = 0.7
	env.glow_bloom = 0.1
	var cattr := CameraAttributesPractical.new()
	cattr.dof_blur_far_enabled = false
	cattr.dof_blur_far_distance = 13.0
	cattr.dof_blur_far_transition = 9.0
	cattr.dof_blur_amount = 0.12
	we.camera_attributes = cattr
	s.world_env = we
	s.add_child(we)

	# Dramatic lighting: low ambient, one hard directional key, faint cool backlight.
	var galaxy_back := OmniLight3D.new()
	galaxy_back.light_color = Color("#70c4ff")
	galaxy_back.light_energy = 1.2
	galaxy_back.omni_range = 30.0
	galaxy_back.position = Vector3(0, 5.5, -9.5)
	s.add_child(galaxy_back)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffe8c8")
	key.light_energy = 1.7
	key.shadow_enabled = true
	key.transform = Transform3D(Basis.looking_at(Vector3(-0.55, -0.75, -0.45)), Vector3(5, 8, 7))
	s.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color("#5eb8ff")
	fill.light_energy = 0.35
	fill.omni_range = 22.0
	fill.position = Vector3(-7, 4.5, 6)
	s.add_child(fill)

	# Brushed dark-steel hangar deck floor.
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color("#252d3a")
	deck_mat.roughness = 0.48
	deck_mat.metallic = 0.35
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(90, 90)
	s.add_child(Gfx.mesh(floor_mesh, deck_mat))

	# Hangar interior architecture: steel window mullions, side bulkheads & glowing cyan consoles.
	var steel_mat := Gfx.mat(Color("#2d3645"), 0.55)
	var trim_mat := Gfx.mat(Color("#475569"), 0.45)
	# Panoramic window frame posts (wide open center showing space, planets & cruising ships).
	for wx in [-13.5, -7.2, 0.0, 7.2, 13.5]:
		var post := Gfx.box(Vector3(0.55, 16.0, 0.9), Color("#2a3342"), Vector3(wx, 8.0, -9.5))
		post.material_override = steel_mat
		s.add_child(post)
	var sill := Gfx.box(Vector3(32.0, 1.4, 1.2), Color("#242c38"), Vector3(0, 0.7, -9.5))
	sill.material_override = trim_mat
	s.add_child(sill)
	var header := Gfx.box(Vector3(32.0, 1.2, 1.4), Color("#242c38"), Vector3(0, 14.5, -9.5))
	header.material_override = steel_mat
	s.add_child(header)
	# Side hangar walls & glowing holographic console desks.
	for side in [-1.0, 1.0]:
		var wall := Gfx.box(Vector3(1.2, 16.0, 20.0), Color("#232b36"), Vector3(side * 14.2, 8.0, -1.0))
		wall.material_override = steel_mat
		s.add_child(wall)
		var desk := Gfx.box(Vector3(2.2, 1.1, 3.6), Color("#2c3748"), Vector3(side * 11.4, 0.55, -4.5))
		s.add_child(desk)
		var screen := Gfx.box(Vector3(0.12, 1.1, 2.8), Color("#38bdf8"), Vector3(side * 10.6, 1.65, -4.5), 1.8)
		s.add_child(screen)
		# Holographic terminal: left = SHOP kiosk (gold), right = COMMAND / leaderboard (cyan).
		var hc := Color("#facc15") if side < 0.0 else Color("#22d3ee")
		var term := Node3D.new()
		term.position = Vector3(side * 10.2, 0.0, -4.5)
		s.add_child(term)
		if side > 0.0:
			s.hangar_props.append_array([wall, desk, screen, term])
		var holo_pane := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(3.0, 2.0)
		holo_pane.mesh = qm
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		pm.albedo_color = Color(hc.r, hc.g, hc.b, 0.22)
		holo_pane.material_override = pm
		holo_pane.position = Vector3(0, 2.6, 0)
		# Quad faces +Z; turn it toward the room centre.
		holo_pane.rotation.y = PI * 0.5 if side < 0.0 else -PI * 0.5
		term.add_child(holo_pane)
		for fy in [1.6, 3.6]:
			var bar := Gfx.box(Vector3(0.1, 0.1, 3.2), hc, Vector3(0, fy, 0), 2.5)
			term.add_child(bar)
		for fz in [-1.55, 1.55]:
			var post2 := Gfx.box(Vector3(0.1, 2.1, 0.1), hc, Vector3(0, 2.6, fz), 2.5)
			term.add_child(post2)
		# Content bars on the holo screen so it reads as a UI.
		for r in 4:
			var w := 2.0 - r * 0.35
			var line := Gfx.box(Vector3(0.04, 0.14, w), hc, Vector3(side * -0.06, 3.2 - r * 0.42, -(2.0 - w) * 0.5), 2.2)
			term.add_child(line)
		var term_light := OmniLight3D.new()
		term_light.light_color = hc
		term_light.light_energy = 1.8
		term_light.omni_range = 7.0
		term_light.position = Vector3(-side * 1.2, 2.6, 0)
		term.add_child(term_light)
		s.tab_holos["SHOP" if side < 0.0 else "LEADERBOARD"] = {"mat": pm, "base_a": 0.22, "light": term_light, "base_e": 1.8}
		# Cyan accent trim around the holo projection base.
		var acc := Color("#22d3ee")
		for az in [-1.6, 1.6]:
			term.add_child(Gfx.box(Vector3(0.14, 0.14, 0.5), acc, Vector3(0, 1.15, az), 3.0))
		term.add_child(Gfx.box(Vector3(0.1, 0.08, 3.4), acc, Vector3(0, 0.7, 0), 2.4))
		# Floating holo elements: gold coin/gem on the shop, data orb on the command side.
		for h in 2:
			var bit: MeshInstance3D
			if side < 0.0:
				bit = Gfx.box(Vector3(0.32, 0.32, 0.32), hc, Vector3.ZERO, 3.0)
			else:
				bit = Gfx.sphere(0.2, hc, Vector3.ZERO, 3.0, 12)
			bit.position = Vector3(-side * 0.5, 1.7 + h * 0.5, -0.7 + h * 1.4)
			term.add_child(bit)
			s.kiosk_holos.append({"node": bit, "y": bit.position.y, "phase": float(h) * 2.0 + side})

	# PROFILE holo terminal: elevated, angled console near the back-right, magenta + cyan.
	var mag := Color("#e879f9")
	var cy := Color("#22d3ee")
	var pterm := Node3D.new()
	pterm.position = Vector3(8.0, 0.0, -6.6)
	pterm.rotation.y = deg_to_rad(28.0)
	s.add_child(pterm)
	s.hangar_props.append(pterm)
	pterm.add_child(Gfx.box(Vector3(2.4, 1.6, 1.2), Color("#2c3748"), Vector3(0, 0.8, 0)))
	pterm.add_child(Gfx.box(Vector3(2.5, 0.08, 1.3), mag, Vector3(0, 1.62, 0), 2.6))
	var ppane := MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(2.6, 1.8)
	ppane.mesh = pq
	var ppm := StandardMaterial3D.new()
	ppm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ppm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ppm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ppm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ppm.albedo_color = Color(mag.r, mag.g, mag.b, 0.24)
	ppane.material_override = ppm
	ppane.position = Vector3(0, 2.9, 0.1)
	ppane.rotation.x = deg_to_rad(-12.0)
	pterm.add_child(ppane)
	for fx in [-1.35, 1.35]:
		pterm.add_child(Gfx.box(Vector3(0.08, 1.9, 0.08), cy, Vector3(fx, 2.9, 0.1), 2.6))
	pterm.add_child(Gfx.box(Vector3(2.8, 0.08, 0.08), cy, Vector3(0, 3.85, 0.1), 2.6))
	pterm.add_child(Gfx.box(Vector3(2.8, 0.08, 0.08), mag, Vector3(0, 1.95, 0.1), 2.6))
	# Avatar silhouette + stat bars on the profile hologram.
	pterm.add_child(Gfx.sphere(0.22, cy, Vector3(-0.8, 3.4, 0.2), 3.0, 12))
	pterm.add_child(Gfx.box(Vector3(0.5, 0.5, 0.06), cy, Vector3(-0.8, 2.85, 0.2), 2.4))
	for r in 3:
		var bw := 1.3 - r * 0.3
		pterm.add_child(Gfx.box(Vector3(bw, 0.12, 0.05), mag, Vector3(0.45 + (bw - 1.3) * 0.5, 3.4 - r * 0.38, 0.2), 2.4))
	var plight := OmniLight3D.new()
	plight.light_color = mag
	plight.light_energy = 1.6
	plight.omni_range = 7.0
	plight.position = Vector3(-0.4, 3.0, 1.4)
	pterm.add_child(plight)
	s.tab_holos["PROFILE"] = {"mat": ppm, "base_a": 0.24, "light": plight, "base_e": 1.6}
	var orb := Gfx.sphere(0.2, mag, Vector3(0.9, 2.2, 0.9), 3.0, 12)
	pterm.add_child(orb)
	s.kiosk_holos.append({"node": orb, "y": 2.2, "phase": 1.3})

	# Subtle flat floor accent line in front of the lineup (no bulky console, never clips or steals focus).
	var accent := Gfx.box(Vector3(7.0, 0.01, 0.04), Color("#22d3ee"), Vector3(0.0, 0.012, 3.6), 0.9)
	accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(accent)
	s.hangar_props.append(accent)

	# Ambient floating dust drifting through the hangar air.
	var dust := CPUParticles3D.new()
	dust.amount = 90
	dust.lifetime = 12.0
	dust.preprocess = 12.0
	dust.position = Vector3(0, 3.5, 0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(12.0, 3.5, 7.0)
	dust.direction = Vector3(1, 0.2, 0.2)
	dust.spread = 180.0
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.22
	dust.gravity = Vector3.ZERO
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.4
	var dm := SphereMesh.new()
	dm.radius = 0.03
	dm.height = 0.06
	dm.radial_segments = 6
	dm.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dmat.albedo_color = Color("#bfdcff", 0.35)
	dm.material = dmat
	dust.mesh = dm
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(dust)

	# Giant glowing planet + distant moon outside the panoramic hangar window.
	var pivot := Node3D.new()
	pivot.position = Vector3(13.5, 9.5, -36.0)
	pivot.rotation.z = 0.41   # axial tilt
	s.add_child(pivot)
	var planet := Gfx.planet(14.5, Color("#245994"), Color("#70c4ff"))
	pivot.add_child(planet)
	s.lobby_planet = planet
	s.planet_pivot = pivot
	s.planet_base = pivot.position
	# Atmospheric rim shell (additive, pulsing).
	var rim_m := StandardMaterial3D.new()
	rim_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rim_m.cull_mode = BaseMaterial3D.CULL_FRONT
	rim_m.albedo_color = Color("#70c4ff", 0.2)
	var rim_mesh := SphereMesh.new()
	rim_mesh.radius = 15.4
	rim_mesh.height = 30.8
	var rim := MeshInstance3D.new()
	rim.mesh = rim_mesh
	rim.material_override = rim_m
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(rim)
	s.planet_rim = rim
	s.rim_mat = rim_m
	var moon_orb := Gfx.sphere(2.2, Color("#cbd5e1"), Vector3(-11.0, 11.0, -32.0), 0.15, 24)
	s.add_child(moon_orb)
	s.lobby_moon = moon_orb

	# The Home camera looks through the right-hand windows onto the launch complex.
	s.home_spaceport = Node3D.new()
	s.home_spaceport.name = "HomeSpaceport"
	s.add_child(s.home_spaceport)
	# Orbital deck terrace: one paved, hazard-trimmed slab; every building has its own marked footing, nothing overlaps.
	var terrace_top := EmpireLayer.SLAB_TOP
	var terrace := EmpireLayer.paved_slab(s.home_spaceport, Vector3(31.0, 0.0, -22.0), Vector2(23.0, 14.0), CAMPUS_ACCENT, "OrbitalDeckTerrace")
	terrace.set_meta("home_showcase", true)
	var showcase := [
		["surface/launch_service_tower.glb", Vector3(14.0, terrace_top, -26.0), 10.5, 0.35],
		["surface/storage_silo_bank.glb", Vector3(24.0, terrace_top, -30.0), 10.0, 0.0],
		["surface/refinery_tower_cluster.glb", Vector3(36.0, terrace_top, -30.0), 13.0, 0.0],
		["landmarks/relay_tower.glb", Vector3(46.0, terrace_top, -30.0), 16.0, 0.0],
		["vehicles/helion_dropship.glb", Vector3(24.0, terrace_top, -16.0), 7.7, 0.0],
	]
	for item: Array in showcase:
		var prop := BlenderVisualUpgrades.place(s.home_spaceport, item[0], item[1], item[2], item[3])
		if prop != null:
			prop.set_meta("home_showcase", true)

	# Cruising spacecraft outside the panoramic window.
	var hull_mat := Gfx.mat(Color("#334155"), 0.44).duplicate() as StandardMaterial3D
	hull_mat.metallic = 0.72
	var wing_mat := Gfx.mat(Color("#1e293b"), 0.5).duplicate() as StandardMaterial3D
	wing_mat.metallic = 0.65
	var glow_cyan := Gfx.mat(Color("#3787a0"), 0.45, 0.65)
	var glow_amber := Gfx.mat(Color("#a77343"), 0.45, 0.6)
	var ship_specs := [
		[-14.0, 5.2, -20.0, 2.4, 0.9, glow_cyan],
		[15.0, 7.8, -24.0, -1.9, 1.15, glow_amber],
		[-18.0, 3.6, -27.0, 1.5, 0.75, glow_cyan],
		[12.0, 9.4, -29.0, -2.6, 0.85, glow_cyan],
	]
	for idx in ship_specs.size():
		var sp: Array = ship_specs[idx]
		var craft := Node3D.new()
		craft.rotation.y = 0.0 if float(sp[3]) > 0.0 else PI
		var fuselage := Gfx.cyl(0.38, 1.85, hull_mat.albedo_color, Vector3(-0.14, 0, 0), 8, 0.31)
		fuselage.rotation.z = -PI / 2.0
		fuselage.scale.x = 0.72
		fuselage.material_override = hull_mat
		craft.add_child(fuselage)
		var nose := Gfx.cyl(0.31, 0.85, hull_mat.albedo_color, Vector3(1.21, 0, 0), 8, 0.04)
		nose.rotation.z = -PI / 2.0
		nose.scale.x = 0.72
		nose.material_override = hull_mat
		craft.add_child(nose)
		for side in [-1.0, 1.0]:
			var wing := Gfx.box(Vector3(0.76, 0.09, 1.18), wing_mat.albedo_color, Vector3(-0.45, -0.05, side * 0.75))
			wing.rotation.y = -side * 0.48
			wing.material_override = wing_mat
			craft.add_child(wing)
		var fin := Gfx.box(Vector3(0.55, 0.48, 0.10), wing_mat.albedo_color, Vector3(-0.72, 0.31, 0))
		fin.rotation.z = 0.36
		fin.material_override = wing_mat
		craft.add_child(fin)
		var engine := Gfx.sphere(0.15, Color("#3787a0"), Vector3(-1.08, 0, 0), 0.0, 10)
		engine.material_override = sp[5]
		craft.add_child(engine)
		craft.scale = Vector3.ONE * float(sp[4])
		craft.position = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
		s.add_child(craft)
		s.lobby_ships.append({
			"node": craft, "speed": float(sp[3]), "y": float(sp[1]), "z": float(sp[2]),
			"x_min": -26.0, "x_max": 26.0, "phase": float(idx) * 1.7,
		})

	# 4 teleportation pads: podium + emissive core + pulsing ring + holo beam + uplight + coloured rim spot.
	for i in 4:
		var base_x := -5.4 + i * 3.6
		var pc: Color = Showcase.PAD_COLORS[i]
		var podium := Gfx.disc(1.52, Color("#334155"), 0.14)
		podium.position = Vector3(base_x, 0, 0)
		s.add_child(podium)
		var ring := Gfx.ring(1.54, 0.14, pc, 0.95)
		ring.position = Vector3(base_x, 0.15, 0)
		s.add_child(ring)
		s.podium_rings.append(ring)
		var root := Node3D.new()
		root.position = Vector3(base_x, 0, 0)
		s.add_child(root)
		var core_m: StandardMaterial3D = Gfx.mat(pc, 0.3, 1.0).duplicate()
		var core := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.15
		cm.bottom_radius = 1.15
		cm.height = 0.04
		core.mesh = cm
		core.material_override = core_m
		core.position = Vector3(0, 0.17, 0)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(core)
		var beam_m := StandardMaterial3D.new()
		beam_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam_m.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam_m.albedo_color = Color(pc.r, pc.g, pc.b, 0.1)
		var beam := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.9
		bm.bottom_radius = 1.2
		bm.height = 4.2
		bm.cap_top = false
		bm.cap_bottom = false
		beam.mesh = bm
		beam.material_override = beam_m
		beam.position = Vector3(0, 2.25, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)
		var up := OmniLight3D.new()
		up.light_color = pc
		up.omni_range = 5.0
		up.light_energy = 1.0
		up.position = Vector3(0, 0.5, 0.6)
		root.add_child(up)
		var rim_l := SpotLight3D.new()
		rim_l.light_color = pc
		rim_l.spot_range = 12.0
		rim_l.spot_angle = 38.0
		rim_l.light_energy = 3.0
		var rp := Vector3(base_x, 5.0, -3.2)
		rim_l.transform = Transform3D(Basis.looking_at(Vector3(base_x, 1.3, 0.3) - rp), rp)
		s.add_child(rim_l)
		var warm := SpotLight3D.new()
		warm.light_color = Color("#ffd27a")
		warm.spot_range = 11.0
		warm.spot_angle = 24.0
		warm.light_energy = 2.0
		var wp := Vector3(base_x, 7.5, 0.6)
		warm.transform = Transform3D(Basis.looking_at(Vector3(base_x, 0.0, 0.5) - wp), wp)
		s.add_child(warm)
		s.pads.append({"root": root, "core": core, "beam": beam, "uplight": up, "rim": rim_l, "spot": warm, "core_mat": core_m, "beam_mat": beam_m})
	var hero := Gfx.disc(1.9, Color("#334155"), 0.14)
	hero.position = Vector3(3.2, 0, 0)
	s.add_child(hero)
	for i in 4:
		var sp = Sim.SPECIALISTS[i]
		var a := Actor.new()
		a.setup(sp["model"], i, Sim.role_color(i))
		s.add_child(a)
		s.actors.append(a)
	return s


func refresh_ship_loadout() -> void:
	if visual_loadout == g.sim.loadout: return
	var pose := ship_root.transform
	var was_visible := ship_root.visible
	remove_child(ship_root)
	ship_root.free()
	for preview in shelf_nodes.values():
		remove_child(preview)
		preview.free()
	shelf_nodes.clear()
	for module in gse_modules.values():
		remove_child(module["node"])
		module["node"].free()
	gse_modules.clear()
	slot_nodes.clear()
	_ship()
	ship_root.transform = pose
	ship_root.visible = was_visible
	if is_instance_valid(shop_kiosk_node):
		preload("res://scripts/shop_kiosk.gd").update_hologram(shop_kiosk_node, g.sim.loadout)
