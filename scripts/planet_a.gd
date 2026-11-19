## Earth: launch pad, part racks, supply cases, systems consoles, delivery pad and rival pads.
## Hosts the BUILD and OUTFIT phases, the launch cinematic and (after docking) the DELIVER phase.
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
# Measured Kestrel.tscn HullBody: half-width 3.592729, local keel centre
# (0, 3.856, -2.52), nose -Z. Mount ahead of the engine pods, clear of them.
const BOOSTER_X := 11.0
const BOOSTER_MOUNT_Z := -3.0
const BOOSTER_Y := 1.0 + 16.3 - BOOSTER_MOUNT_Z
const BOOSTER_PAD_Z := 3.856 - 5.8
const BOOSTER_BURN_TIME := 20.0
const LAUNCH_DURATION := BOOSTER_BURN_TIME + 3.0
const LAUNCH_ALTITUDE := 2600.0
const LAUNCH_DOWNRANGE := 900.0
const SHOP_DESK := Vector3(14, 0, -23) # stand here to close the shop and start assembly
const LAUNCH_DESK := Vector3(-14, 0, -23) # stand here to plan the route and launch
var launch_desk_ring: MeshInstance3D
var launch_desk_label: Label3D

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
var flame: Node3D
var rival_ships: Array = []
var bots: Array = [{"t": 0.0}, {"t": 0.0}, {"t": 0.0}, {"t": 0.0}]
var deliver_clock := 0.0
var blockers: Array = []   # Rect2 footprints on the ground plane
var intro_from := Vector3.ZERO
var shop_items: Array = []
var shop_kiosk_node: Node3D
var shop_desk_ring: MeshInstance3D
var shop_desk_label: Label3D
# Automated machine assembly (Iron-Man-style build sequence)
var launch_base_set := false
var pad_steam: CPUParticles3D
var launch_base := Transform3D.IDENTITY
var fx_ready := false
var fx_base := {}          # part id -> original local position
var fx_orig_mats := {}     # MeshInstance3D -> original material_override
var fx_holo := {}          # part/booster key -> true while holo-tinted
var fx_done := {}          # key -> true after the snap flash
var fx_arms: Array = []
var fx_sparks: Array = []
var _landing_nodes: Array[Node3D] = []
var _bolt_materials: Array[Material] = []
var booster_gantry: Node3D
var fx_boosters: Array = []   # {node, start}
var fx_light: OmniLight3D
var pad_stage := "shop"    # shop -> build -> outfit -> erect_wait -> erecting -> boosters -> ready
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


func setup(main, p_delivery: bool) -> void:
	g = main
	delivery = p_delivery
	name = "PlanetA"
	# The set dressing is now stored in an editable Godot scene, not generated on play.
	var editable: Node3D = g.universe.planet_a.get_node("PlanetAEnvironment") as Node3D   # part of the one universe scene
	var gfx_script := load("res://scripts/gfx.gd") as GDScript
	if gfx_script.has_method("apply_cinematic_atmosphere"):
		gfx_script.call("apply_cinematic_atmosphere", editable)
	_pbr_cliff = _optional_pbr_material(gfx_script, "cliff", 0.22, Color.WHITE, 0.0)
	_pbr_cladding = _optional_pbr_material(gfx_script, "metal", 0.35, Color("#e8ecef"), 0.38)
	_pbr_dark_steel = _optional_pbr_material(gfx_script, "metal", 0.55, Color("#3a424d"), 0.78)
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
		# Grounded smooth sunlit concrete pad — avoids noisy speckled gravel grain or blowout.
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = Color("#7e8c96")
		pad_material.roughness = 0.88
		pad_material.metallic = 0.04
		foundation.material_override = pad_material
	for i in 8:
		var angle := (i + 0.5) * TAU / 8.0
		var point := Vector3(cos(angle) * 20.2, 0.18, sin(angle) * 20.2)
		apron_lights.append(add_apron_fixture(self, point, Color("#ffd39a")))
	# Gameplay footprints are editor-visible Marker3D nodes with a Vector2 footprint.
	for marker in editable.get_node("CollisionFootprints").get_children():
		var footprint: Vector2 = marker.get_meta("footprint", Vector2.ZERO)
		var pt: Vector3 = (marker as Node3D).position
		blockers.append(Rect2(pt.x - footprint.x * 0.5, pt.z - footprint.y * 0.5, footprint.x, footprint.y))
	preload("res://scripts/model_detail.gd").surroundings(self, Vector3(24,0,0))
	_cargo()
	_rivals()
	_ship()
	_shop()
	_water_features()
	_living_world()
	_grass_scatter()
	_apron_railing()
	_crew()
	_compact_billboard_labels()
	beacon = Gfx.cyl(0.35, 40.0, ACCENT, Vector3.ZERO, 8)
	beacon.material_override = Gfx.unshaded(Color("#ffd29a"), 0.28)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)
	var a: Actor = actors[g.sim.selected]
	intro_from = a.position + Vector3(0, 2.0, -5.5)
	if g != null and g.get("graphics") != null:
		apply_quality(g.graphics)


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
# Construction of the scene
# ---------------------------------------------------------------------------
# Scenic sunlit reflecting ponds/coves flanking the launch complex (non-blocking).
# Each entry: [center_x, center_z, radius_x, radius_z]
const WATER_PONDS := [
	[-52.0, 4.0, 18.0, 13.5],
	[54.0, 4.0, 19.0, 14.5],
	[-42.0, 48.0, 21.0, 15.0],
	[42.0, 48.0, 21.0, 15.0],
]


func _water_features() -> void:
	if not ResourceLoader.exists("res://assets/shaders/hopeful_water.gdshader"):
		return
	var water_root := Node3D.new()
	water_root.name = "WaterFeatures"
	add_child(water_root)
	var water_mat := Gfx.create_hopeful_water_mat()
	_water_material = water_mat as ShaderMaterial
	water_mat.set_shader_parameter("sun_direction", Universe.SOLAR_VECTOR.normalized())
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
		var water_mesh := PlaneMesh.new()
		water_mesh.size = Vector2(rx * 2.0, rz * 2.0)
		var pond := Gfx.mesh(water_mesh, water_mat, Vector3(cx, 0.045, cz), false)
		pond.name = "SunlitPond%d" % i
		water_root.add_child(pond)
		# Soft mossy-sand rim so the water blends into the meadow.
		var rim_mesh := CylinderMesh.new()
		rim_mesh.top_radius = 1.0
		rim_mesh.bottom_radius = 1.0
		rim_mesh.height = 0.02
		rim_mesh.radial_segments = 40
		var rim := Gfx.mesh(rim_mesh, shore_mat, Vector3(cx, 0.02, cz), false)
		rim.scale = Vector3(rx * 1.12, 1.0, rz * 1.12)
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rim.name = "PondShore%d" % i
		water_root.add_child(rim)
		# Lakeside trees on the far side of the pond, facing away from the pad.
		var away := Vector2(cx, cz).normalized()
		var base_a := atan2(away.y, away.x)
		for t in 3:
			var ta := base_a + (t - 1) * 0.45
			var tp := Vector3(cx + cos(ta) * rx * 1.25, 0.0, cz + sin(ta) * rz * 1.25)
			_lakeside_tree(water_root, tp, 0.9 + 0.15 * t, trunk_mat, leaf_mat)
		# Gentle shoreline stones around parts of the pond edge for Minecraft-shader charm.
		var rng := RandomNumberGenerator.new()
		rng.seed = 4100 + i * 97
		for s in 6:
			var a := rng.randf_range(0.0, TAU)
			var sx := cx + cos(a) * rx * rng.randf_range(0.86, 0.98)
			var sz := cz + sin(a) * rz * rng.randf_range(0.86, 0.98)
			var stone := Gfx.rock(rng.randf_range(0.45, 1.15), Color("#8fa0ab"), rng, 0.42)
			stone.material_override = bank_mat if s % 3 == 0 else Gfx.mat(Color("#8c9ca6"), 0.88)
			stone.position = Vector3(sx, 0.02, sz)
			stone.rotation.y = rng.randf_range(0.0, TAU)
			stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			water_root.add_child(stone)


# Keep floating billboard labels screen-sized so nearby racks never fill the view.
func _compact_billboard_labels() -> void:
	for node in find_children("*", "Label3D", true, false):
		var l := node as Label3D
		if l.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
			continue
		l.fixed_size = true
		l.pixel_size = 0.00065


func _lakeside_tree(parent: Node3D, pos: Vector3, scale_f: float, trunk_mat: Material, leaf_mat: Material) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * scale_f
	parent.add_child(tree)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.38
	trunk.height = 2.6
	tree.add_child(Gfx.mesh(trunk, trunk_mat, Vector3(0, 1.3, 0), true))
	for tier in 2:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 2.1 - tier * 0.65
		cone.height = 2.6 - tier * 0.5
		cone.radial_segments = 10
		tree.add_child(Gfx.mesh(cone, leaf_mat, Vector3(0, 3.0 + tier * 1.5, 0), true))


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
	motes.scale_amount_min = 0.04
	motes.scale_amount_max = 0.09
	var mote_mesh := QuadMesh.new()
	mote_mesh.size = Vector2(1.0, 1.0)
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_mat.albedo_color = Color(1.0, 0.96, 0.76, 0.55)
	mote_mesh.material = mote_mat
	motes.mesh = mote_mesh
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GraphicsSettings.set_particle_count(motes, 70)
	life.add_child(motes)

	# 2. Gentle cryogenic steam wisps rising from the launch complex propellant tanks.
	var steam_mat := StandardMaterial3D.new()
	steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	for spec: Array in WATER_PONDS:
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

	var exclusions: Array[Rect2] = [DELIVERY_ROAD.grow(0.25), SHOP_FOOTPRINT.grow(0.25)]
	for rack in Sim.RACKS:
		exclusions.append(Rect2(rack[0] - 3.6, rack[1] - 1.6, 7.2, 3.2).grow(0.25))
	for blocker in blockers:
		exclusions.append((blocker as Rect2).grow(0.25))

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


func _apron_railing() -> void:
	var railing := Node3D.new()
	railing.name = "ApronRailing"
	add_child(railing)
	var gray := Color("#758087")
	var steel := _pbr_dark_steel if _pbr_dark_steel != null else Hardware.material(gray, 0.8, 0.35)
	var radius := 21.3
	# Measure from +Z, toward the road. The rear opening clears the shop frontage.
	var road_edge := asin((DELIVERY_ROAD.size.x * 0.5 + 0.15) / radius)
	var shop_edge := acos((SHOP_FOOTPRINT.end.y + 0.15) / radius)
	var spans := ceili((shop_edge - road_edge) * radius / 2.4)
	for side in [-1.0, 1.0]:
		var previous := Vector3.ZERO
		for i in range(spans + 1):
			var angle := lerpf(road_edge, shop_edge, float(i) / spans)
			var point := Vector3(side * sin(angle), 0, cos(angle)) * radius
			var post := Gfx.cyl(0.065, 1.1, gray, point + Vector3.UP * 0.55, 8)
			post.material_override = steel
			railing.add_child(post)
			if i > 0:
				var span := point - previous
				for height in [0.48, 1.02]:
					var bar := Gfx.box(Vector3(span.length(), 0.065, 0.065), gray,
						(previous + point) * 0.5 + Vector3.UP * height)
					bar.rotation.y = -atan2(span.z, span.x)
					bar.material_override = steel
					railing.add_child(bar)
			previous = point


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
	var hatch := Gfx.ring(2.6, 0.3, Color("#9cdeb1"), 0.75)
	hatch.position = Sim.CARGO_HATCH + Vector3(0, 0.1, 0)
	add_child(hatch)
	var hl := Gfx.label("AFT CARGO HATCH", Color("#9cdeb1"), 40)
	hl.position = Sim.CARGO_HATCH + Vector3(0, 3.2, 0)
	add_child(hl)


func _consoles() -> void:
	for type in CONSOLES:
		var pos: Vector3 = CONSOLES[type]
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
		var pos := Vector3(bay[0], 0, bay[1])
		# Rival landing surfaces are inside PlanetAEnvironment.tscn.
		var ship := ShipModel.full(Sim.faction_color(i), g.sim.teams[i]["loadout"])
		ship.position = pos
		ship.rotation.y = atan2(pos.x, pos.z) + PI
		add_child(ship)
		var l := Gfx.label(Sim.FACTIONS[i]["name"], Sim.faction_color(i), 80)
		l.position = pos + Vector3(0, 16, 0)
		add_child(l)
		rival_ships.append({"node": ship, "label": l, "team": i, "pos": pos})
		blockers.append(Rect2(pos.x - 6 * Sim.SHIP_K, pos.z - 6 * Sim.SHIP_K, 12 * Sim.SHIP_K, 12 * Sim.SHIP_K))


func _ship() -> void:
	# Each of the 12 buildable spacecraft modules now exists in Kestrel.tscn.
	ship_root = ShipModel.full(ACCENT, g.sim.loadout)
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
		var bolts := []
		for k in 3:
			var b := Gfx.sphere(0.32, Color("#ed7d8d"), Vector3(-p["dims"].x * 0.3 + k * p["dims"].x * 0.3, p["dims"].y * 0.5 + 0.2, 0), 1.5, 10)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(b)
			bolts.append(b)
		slot_nodes[p["id"]] = {"node": node, "bolts": bolts}
		var preview := ShipModel.preview(p["id"], str(g.sim.loadout.get(p["id"], "kestrel")), ACCENT)
		preview.position = Vector3.ZERO
		add_child(preview)
		shelf_nodes[p["id"]] = preview
	flame = ShipModel.flame(9.0, ship_root)
	flame.visible = false
	ship_root.add_child(flame)


func _crew() -> void:
	for r in 4:
		var s = Sim.SPECIALISTS[r]
		var a := Actor.new()
		a.setup(s["model"], r, Sim.role_color(r), s["name"], Sim.role_color(r))
		add_child(a)
		if delivery:
			a.position = Vector3(-6 + r * 4, 0, 24)
		else:
			var c = Sim.RACKS[r]
			a.position = Vector3(c[0] * 0.8, 0, c[1] * 0.6)
		a.heading = atan2(a.position.x, a.position.z)
		a.rotation.y = a.heading
		actors.append(a)


# ---------------------------------------------------------------------------
# 3D parts shop with a holographic ship builder terminal.
# ---------------------------------------------------------------------------
func _shop() -> void:
	if delivery:
		return
	var white := Color("#f8fafc")
	var slate := Color("#26364a")
	var cyan := Color("#35d5ed")
	add_child(Gfx.box(Vector3(34, 0.1, 24), Color("#f3f5f8"), SHOP + Vector3(0, 0.05, 1)))

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
				var center := SHOP + Vector3(-17 + (col + 0.5) * tile_size.x, 0.11, -11 + (row + 0.5) * tile_size.y)
				tiles.set_instance_transform(index, Transform3D(Basis.IDENTITY, center))
				index += 1
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = tiles
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)

	# Clean sunlit aerospace cladding instead of noisy PBR metal on the shop shell.
	var cladding := Hardware.material(Color("#e2e8ee"), 0.08, 0.72)
	var frame := Hardware.material(Color("#3a4652"), 0.35, 0.6)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.14, 0.18, 0.38)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.65
	glass.roughness = 0.08
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Keep the full actor collision footprints across the window openings.
	var walls: Array[Rect2] = [
		Rect2(-17, SHOP.z - 11, 34, 0.5),
		Rect2(-17, SHOP.z - 10.5, 1, 23),
		Rect2(16, SHOP.z - 10.5, 1, 23),
		Rect2(-17, SHOP.z + 12.5, 12.5, 0.5),
		Rect2(4.5, SHOP.z + 12.5, 12.5, 0.5),
	]
	for wall in walls:
		blockers.append(wall)
	var wall_positions := [PI, -PI / 2.0, PI / 2.0, 0.0, 0.0]
	for i in walls.size():
		var wall := walls[i]
		var center := wall.get_center()
		var facade := Node3D.new()
		facade.position = Vector3(center.x, 0, center.y)
		facade.rotation.y = wall_positions[i]
		add_child(facade)
		if i == 0:
			_shop_wall_panel(facade, Vector3(34, 10, 0.5), Vector3(0, 5, 0), white, cladding)
		elif i <= 2:
			_shop_window_wall(facade, 23.0, 1.0, 15.0, 6, white, cladding, glass, frame)
		else:
			_shop_window_wall(facade, 12.5, 0.5, 10.0, 4, white, cladding, glass, frame)
	_shop_wall_panel(self, Vector3(9, 3.5, 0.5), SHOP + Vector3(0, 8.25, 12.75), white, cladding)
	add_child(Gfx.box(Vector3(34, 0.4, 24), Color.WHITE, SHOP + Vector3(0, 10.2, 1)))
	_shop_exterior_hardware(cladding, frame)
	for x in [-10, 0, 10]:
		var light := OmniLight3D.new()
		light.position = SHOP + Vector3(x, 8.8, 1)
		light.light_energy = 2.2
		light.omni_range = 18.0
		add_child(light)

	for z in [13.0, -10.5]:
		var sign := Gfx.label("PARTS SHOP · HOLOGRAPHIC BAY", slate, 64, 0)
		sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sign.pixel_size = 0.007
		sign.position = SHOP + Vector3(0, 8.4, z + 0.03)
		add_child(sign)
		add_child(Gfx.box(Vector3(8.6, 0.07, 0.04), cyan, SHOP + Vector3(0, 7.9, z + 0.03), 0.8))

	if ResourceLoader.exists("res://scripts/shop_kiosk.gd"):
		var kiosk_script = load("res://scripts/shop_kiosk.gd")
		shop_kiosk_node = kiosk_script.build()
		shop_kiosk_node.position = SHOP_COMPUTER
		add_child(shop_kiosk_node)
		blockers.append(Rect2(SHOP_COMPUTER.x - 3.3, SHOP_COMPUTER.z - 1.4, 6.6, 2.8))
		var ring := Gfx.ring(2.5, 0.16, cyan)
		ring.position = SHOP_COMPUTER + Vector3(0, 0.15, 0)
		add_child(ring)
		var label := Gfx.label("HOLOGRAPHIC TERMINAL · PRESS E", cyan, 34, 6)
		label.position = SHOP_COMPUTER + Vector3(0, 5.7, 0)
		add_child(label)

	# Desk pad that closes the shop and releases assembly.
	shop_desk_ring = Gfx.ring(2.2, 0.35, Color("#9cdeb1"))
	shop_desk_ring.position = SHOP_DESK + Vector3(0, 0.15, 0)
	add_child(shop_desk_ring)
	shop_desk_label = Gfx.label("", Color("#9cdeb1"), 40, 8)
	shop_desk_label.position = SHOP_DESK + Vector3(0, 3.2, 0)
	add_child(shop_desk_label)


func _shop_wall_panel(parent: Node3D, size: Vector3, center: Vector3, white: Color,
		cladding: Material) -> void:
	var skin := 0.08
	parent.add_child(Gfx.box(size - Vector3(0, 0, skin), white, center - Vector3(0, 0, skin * 0.5)))
	var panel := BoxMesh.new()
	panel.size = Vector3(size.x, size.y, skin)
	parent.add_child(Gfx.mesh(panel, cladding, center + Vector3(0, 0, (size.z - skin) * 0.5)))


func _shop_window_wall(parent: Node3D, width: float, depth: float, opening: float, columns: int,
		white: Color, cladding: Material, glass: Material, frame: Material) -> void:
	var sill := 2.2
	var lintel := 7.4
	var height := lintel - sill
	var midpoint := (lintel + sill) * 0.5
	var jamb := (width - opening) * 0.5
	_shop_wall_panel(parent, Vector3(width, sill, depth), Vector3(0, sill * 0.5, 0), white, cladding)
	_shop_wall_panel(parent, Vector3(width, 10.0 - lintel, depth),
		Vector3(0, (10.0 + lintel) * 0.5, 0), white, cladding)
	for side in [-1.0, 1.0]:
		_shop_wall_panel(parent, Vector3(jamb, height, depth),
			Vector3(side * (opening + jamb) * 0.5, midpoint, 0), white, cladding)

	var pane := QuadMesh.new()
	pane.size = Vector2(opening, height)
	parent.add_child(Gfx.mesh(pane, glass, Vector3(0, midpoint, 0), false))
	var horizontal := BoxMesh.new()
	horizontal.size = Vector3(opening + 0.14, 0.14, depth + 0.04)
	for y in [sill, midpoint, lintel]:
		parent.add_child(Gfx.mesh(horizontal, frame, Vector3(0, y, 0)))
	var vertical := BoxMesh.new()
	vertical.size = Vector3(0.14, height, depth + 0.04)
	for i in range(columns + 1):
		var x := lerpf(-opening * 0.5, opening * 0.5, float(i) / columns)
		parent.add_child(Gfx.mesh(vertical, frame, Vector3(x, midpoint, 0)))


func _shop_exterior_hardware(cladding: Material, frame: Material) -> void:
	var steel_color := Color("#758087")
	var steel := _pbr_dark_steel if _pbr_dark_steel != null else Hardware.material(steel_color, 0.8, 0.35)
	var housing_material := _pbr_dark_steel if _pbr_dark_steel != null else cladding
	var west := SHOP_FOOTPRINT.position.x
	# Run the conduit below the west windows, with risers beside the window bay.
	var pipe := Gfx.cyl(0.10, 19.0, steel_color, SHOP + Vector3(west - 0.23, 1.55, 1), 12)
	pipe.rotation.x = PI / 2.0
	pipe.material_override = steel
	add_child(pipe)
	var bracket := BoxMesh.new()
	bracket.size = Vector3(0.42, 0.20, 0.24)
	for z in [-8.5, -4.0, 1.0, 6.0, 10.5]:
		add_child(Gfx.mesh(bracket, frame, SHOP + Vector3(west - 0.14, 1.55, z)))
	for z in [-8.5, 10.5]:
		var riser := Gfx.cyl(0.10, 6.8, steel_color, SHOP + Vector3(west - 0.23, 4.95, z), 12)
		riser.material_override = steel
		add_child(riser)
		for y in [3.4, 5.5, 7.6]:
			add_child(Gfx.mesh(bracket, frame, SHOP + Vector3(west - 0.14, y, z)))

	var housing := BoxMesh.new()
	housing.size = Vector3(3.6, 0.9, 2.55)
	var slat := BoxMesh.new()
	slat.size = Vector3(2.18, 0.065, 0.065)
	for x in [-8.0, 8.0]:
		var origin := SHOP + Vector3(x, 10.4, -3.5)
		add_child(Gfx.mesh(housing, housing_material, origin + Vector3.UP * 0.45))
		var fan := Gfx.cyl(0.97, 0.16, Color("#303b44"), origin + Vector3.UP * 0.97, 24)
		fan.material_override = frame
		add_child(fan)
		for i in range(-5, 6):
			add_child(Gfx.mesh(slat, steel, origin + Vector3(0, 1.08, i * 0.19)))


func _shop_visuals(_dt: float) -> void:
	var s: Sim = g.sim
	g.hud.update_shop(s)
	if not is_instance_valid(shop_desk_ring):
		return
	var all_bought := s.all_parts_bought()
	shop_desk_ring.visible = s.shop_open
	shop_desk_label.visible = s.shop_open
	shop_desk_label.text = "START BUILDING\nE" if all_bought else "CONFIRM ALL 12 SLOTS FIRST\n%d / 12" % s.confirmed_count()
	shop_desk_label.modulate = Color("#9cdeb1") if all_bought else Color("#f7ce59")


func _shop_interact(a: Actor) -> String:
	if pad_stage != "shop" or g.pad_sequence_active():
		return ""
	if is_instance_valid(shop_kiosk_node) and g.flat_dist(a.position, SHOP_COMPUTER) < 3.6:
		g.hud.set_prompt("E  OPEN HOLOGRAPHIC SHIP BUILDER")
		if g.pressed(KEY_E):
			g.open_ship_builder()
		return ""
	var s: Sim = g.sim
	if g.flat_dist(a.position, SHOP_DESK) < 3.2:
		if s.all_parts_bought():
			g.hud.set_prompt("E  START AUTOMATED BUILD", "Robotic arms assemble the whole spacecraft and its boosters in 15 seconds.")
			if g.pressed(KEY_E):
				refresh_ship_loadout()
				pad_stage = "build"
				s.shop_open = false
				s.auto_build["enabled"] = true
				s.auto_build["t"] = 0.0
				g.sfx("reload_ratchet" if g.streams.has("reload_ratchet") else "reload_click")
				g.hud.set_prompt("")
				g.begin_cine("build", Sim.AUTO_BUILD_SECONDS + 0.8)
		else:
			g.hud.set_prompt("CONFIRM ALL 12 SLOTS FIRST", "%d / 12 bought" % s.confirmed_count())
		return ""
	_point_beacon(SHOP, "SHOP")
	g.hud.set_prompt("GO TO THE PARTS SHOP", "Open the ship builder with E · %d m · %d / 12 bought" % [int(g.flat_dist(a.position, SHOP)), s.confirmed_count()])
	return ""


# ---------------------------------------------------------------------------
# Gameplay
# ---------------------------------------------------------------------------
func collide(p: Vector3) -> Vector3:
	var rad := 0.6
	var rects := blockers.duplicate()
	for part in g.sim.parts:
		if part["stage"] == "secured" and ship_root.position.y < 1.0:
			var c: Vector3 = part["slot"]
			var d: Vector3 = part["dims"]
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
	var s: Sim = g.sim
	if visual_loadout != s.loadout: refresh_ship_loadout()
	var r := s.selected
	var a: Actor = actors[r]
	for i in 4:
		if actors[i].name_tag:
			actors[i].name_tag.visible = i != r
	var speed: float = g.drive(a, dt)
	g.follow_cam(a)
	beacon.visible = false
	var work := _interact(r, a, dt)
	a.animate(dt, speed, work, s.carry[r] != null)
	_tick_living_world(dt, a, speed)
	for i in 4:
		if i != r:
			_bot(i, dt)
			s.rescue_stalled_crew(i, dt)
	_visuals(dt)
	for light in apron_lights:
		light.light_energy = 0.55 if not delivery and pad_stage != "shop" else 0.18
	_shop_visuals(dt)
	if pad_stage == "erect_wait" and g.mode == "play" and not g.pad_sequence_active():
		g.hud.set_prompt("E  ERECT THE SPACECRAFT", "Hydraulic arms lift it upright and align it on the launch pad.")
		if g.pressed(KEY_E):
			pad_stage = "erecting"
			g.sfx("reload_ratchet" if g.streams.has("reload_ratchet") else "reload_click")
			g.begin_cine("erect", 7.0)
	if s.phase == "route" and pad_stage == "ready":
		_launch_desk_tick(a)


## Mission desk: walk to it and press E to plan the route and launch. No separate menu scene.
func _launch_desk_tick(a: Actor) -> void:
	if launch_desk_ring == null:
		launch_desk_ring = Gfx.ring(2.2, 0.35, ACCENT)
		launch_desk_ring.position = LAUNCH_DESK + Vector3(0, 0.15, 0)
		add_child(launch_desk_ring)
		launch_desk_label = Gfx.label("MISSION DESK", ACCENT, 40, 8)
		launch_desk_label.position = LAUNCH_DESK + Vector3(0, 3.2, 0)
		add_child(launch_desk_label)
	if g.mode != "play":
		return
	if g.flat_dist(a.position, LAUNCH_DESK) < 3.2:
		g.hud.set_prompt("E  OPEN FLIGHT PLAN", "Pick the route, run the go / no-go poll and launch.")
		if g.pressed(KEY_E):
			g.on_route_ready()
	else:
		_point_beacon(LAUNCH_DESK, "MISSION DESK")
		g.hud.set_prompt("GO TO THE MISSION DESK", "Spacecraft is ready on the pad · %d m" % int(g.flat_dist(a.position, LAUNCH_DESK)))


func _first_part(assigned_role: int, stage: String) -> Variant:
	for p in g.sim.parts:
		if p["owner"] == assigned_role and p["stage"] == stage:
			return p
	return null


func _part_dist(a: Actor, p) -> float:
	return g.footprint_distance(a.position, p["slot"], p["dims"])


func _rack_point(r: int) -> Vector3:
	var c = Sim.RACKS[r]
	return Vector3(c[0], 0, c[1] + (2.6 if c[1] < 0 else -2.6))


func _point_beacon(p: Vector3, label: String) -> void:
	beacon_target = p
	beacon_label = label
	beacon.visible = true
	beacon.position = Vector3(p.x, 20, p.z)


func _interact(r: int, a: Actor, dt: float) -> String:
	var s: Sim = g.sim
	var c = s.carry[r]
	match s.phase:
		"assembly":
			if s.shop_open:
				return _shop_interact(a)
			if s.auto_build["enabled"]:
				g.hud.set_prompt("FAST ASSEMBLY", "Robotic arms are fetching, setting and bolting every module · %d/12 secured" % s.secured_count(), s.auto_build["t"] / Sim.AUTO_BUILD_SECONDS)
				return ""
			if c != null:
				var p = s.part_by_id(c)
				var d := _part_dist(a, p)
				_point_beacon(p["slot"], p["name"])
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
				if g.lmb:
					var before: String = pos["stage"]
					s.fasten_bolt(pos["id"], bolt, r, dt, best)
					if pos["stage"] == "secured" and before != "secured":
						g.sfx("capture_tick", -4)
						g.hud.toast("%s secured · %d/12" % [pos["name"], s.secured_count()])
					return "work"
				return ""
			var waiting = _first_part(r, "positioned")
			if waiting != null:
				_point_beacon(waiting["slot"], waiting["name"])
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
		"outfit":
			if c != null and String(c).begins_with("cargo:"):
				var d: float = g.flat_dist(a.position, Sim.CARGO_HATCH)
				if d <= 3.0:
					g.hud.set_prompt("E  STOW SUPPLY CASE", "Aft cargo hatch")
					if g.pressed(KEY_E) and s.stow_cargo(r, d):
						g.sfx("capture_tick", -6)
						var cid := String(c).substr(6)
						for x in s.cargo:
							if x["id"] == cid:
								g.hud.toast(x["lesson"], 4.0)
				else:
					_point_beacon(Sim.CARGO_HATCH, "CARGO HATCH")
					g.hud.set_prompt("CARRY TO THE AFT CARGO HATCH", "%d m" % int(d))
				return ""
			if not s.all_cargo_stowed():
				var near = null
				var mine = null
				for x in s.cargo:
					if x["stowed"] or s.carry.has("cargo:" + x["id"]):
						continue
					if g.flat_dist(a.position, x["position"]) <= 3.0:
						near = x
					if x["owner"] == r:
						mine = x
				if near != null:
					g.hud.set_prompt("E  PICK UP %s" % near["name"].to_upper(), "Supply case")
					if g.pressed(KEY_E):
						s.pick_cargo(near["id"], r)
				elif mine != null:
					_point_beacon(mine["position"], mine["name"])
					g.hud.set_prompt("FETCH %s" % mine["name"].to_upper(), "Carry it to the aft cargo hatch.")
				else:
					g.hud.set_prompt("OUTFIT THE SHIP", "Teammates are carrying their supply cases.")
				return ""
			for type in ["engine", "power", "pressure"]:
				if Sim.CHECK_ROLE[type] != r or s.checks[type] >= 1.0:
					continue
				var cp: Vector3 = CONSOLES[type]
				var d: float = g.flat_dist(a.position, cp)
				if d > 3.2:
					_point_beacon(cp, "%s CONSOLE" % type.to_upper())
					g.hud.set_prompt("RUN THE %s CHECK" % type.to_upper(), "Walk to the console · %d m" % int(d))
					return ""
				var band = Sim.CHECK_RANGES[type]
				s.check_readings[type] = clampf(s.check_readings[type] + g.wheel * 2.5, 0.0, 130.0)
				if g.held(KEY_Q): s.check_readings[type] = maxf(0.0, s.check_readings[type] - dt * 20.0)
				if g.held(KEY_F): s.check_readings[type] = minf(130.0, s.check_readings[type] + dt * 20.0)
				var reading: float = s.check_readings[type]
				var inside: bool = reading >= band[0] and reading <= band[1]
				g.hud.set_prompt("HOLD LMB  RUN %s CHECK" % type.to_upper(), "Reading %.0f · GO band %d–%d · wheel or Q/F adjusts %s" % [reading, band[0], band[1], "· IN BAND" if inside else ""], s.checks[type])
				if g.lmb:
					s.run_check(type, r, dt, reading)
					return "work"
				return ""
			g.hud.set_prompt("SYSTEMS TEST UNDER WAY", "Chip and Finn are running the pressure, power and engine checks.")
		"delivery":
			var onboard: int = s.flag_counts(0)["onboard"]
			if onboard == 0:
				_finish_delivery()
				return ""
			var d: float = g.flat_dist(a.position, Sim.DELIVERY_PAD)
			if d <= 5.0:
				g.hud.set_prompt("HOLD E  DELIVER SCIENCE FLAGS", "%d on board" % onboard, fmod(deliver_clock, 0.8) / 0.8)
				if g.held(KEY_E):
					_deliver_step(dt, d)
					return "work"
			else:
				_point_beacon(Sim.DELIVERY_PAD, "DELIVERY")
				g.hud.set_prompt("BRING IT HOME", "Walk to the delivery pad · %d flags on board" % onboard)
		"delivered", "spectator":
			g.hud.set_prompt("EXPEDITION COMPLETE" if s.phase == "delivered" else "CREW ELIMINATED", "Waiting for the other crews · F5 fast-forward")
			return "celebrate" if s.phase == "delivered" else ""
	return ""


func _deliver_step(dt: float, d: float) -> void:
	deliver_clock += dt
	if deliver_clock >= 0.8:
		deliver_clock = 0.0
		if g.sim.deliver_flag(0, d):
			g.sfx("capture_tick", -2)


func _finish_delivery() -> void:
	var s: Sim = g.sim
	if s.phase != "delivery":
		return
	var t = s.teams[0]
	t["phase"] = "delivered"
	t["finished"] = true
	t["progress"] = 1.0
	s.phase = "delivered"
	g.hud.show_banner("FLAGS DELIVERED", "%d Science Flags on Earth · F5 fast-forwards to the result" % t["delivered"], 4.0)


func _approach(p, from: Vector3) -> Vector3:
	var slot: Vector3 = p["slot"]
	var dims: Vector3 = p["dims"]
	var sgn := signf(slot.x) if absf(slot.x) > 0.5 else (signf(from.x) if absf(from.x) > 0.01 else 1.0)
	var edge := maxf(Sim.SHIP_SCALE, absf(slot.x) + dims.x * 0.5)
	return Vector3(sgn * (edge + 1.1), 0, slot.z)


func _bot(i: int, dt: float) -> void:
	var s: Sim = g.sim
	var a: Actor = actors[i]
	var b: Dictionary = bots[i]
	b["t"] -= dt
	var work := ""
	var speed := 4.4
	match s.phase:
		"assembly":
			if s.shop_open or s.auto_build["enabled"]:
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
		"outfit":
			var c = s.carry[i]
			if c != null and String(c).begins_with("cargo:"):
				if a.walk_to(Sim.CARGO_HATCH + Vector3(i - 1.5, 0, 0), dt, speed) < 0.6:
					s.stow_cargo(i, g.flat_dist(a.position, Sim.CARGO_HATCH))
			else:
				var mine = null
				for x in s.cargo:
					if x["owner"] == i and not x["stowed"] and not s.carry.has("cargo:" + x["id"]):
						mine = x
				if mine != null:
					if a.walk_to(mine["position"], dt, speed, 1.2) < 1.5:
						s.pick_cargo(mine["id"], i)
				elif s.all_cargo_stowed():
					var did := false
					for type in ["engine", "power", "pressure"]:
						if Sim.CHECK_ROLE[type] == i and s.checks[type] < 1.0:
							var cp: Vector3 = CONSOLES[type]
							if a.walk_to(cp + Vector3(-1.6 if cp.x > 0 else 1.6, 0, 0), dt, speed) < 0.6:
								var band = Sim.CHECK_RANGES[type]
								s.run_check(type, i, dt, (band[0] + band[1]) * 0.5)
								a.face(cp - a.position, dt)
								work = "work"
							did = true
							break
					if not did:
						a.walk_to(Vector3(-8 + i * 5, 0, 26), dt, speed, 0.5)
				else:
					a.walk_to(Vector3(-8 + i * 5, 0, 26), dt, speed, 0.5)
		"delivery":
			a.walk_to(Sim.DELIVERY_PAD + Vector3(-6 + i * 4, 0, -5), dt, speed, 0.5)
			if i == 3 and s.selected != 3 and g.flat_dist(a.position, Sim.DELIVERY_PAD + Vector3(6, 0, -5)) < 6.5:
				if s.flag_counts(0)["onboard"] > 0:
					_deliver_step(dt * 0.6, 4.0)
					work = "work"
				else:
					_finish_delivery()
		"delivered":
			work = "celebrate"
		_:
			pass
	a.animate(dt, a.vel.length(), work, s.carry[i] != null)
	a.vel = Vector3.ZERO


func _visuals(dt: float) -> void:
	var s: Sim = g.sim
	var shelf_index := [0, 0, 0, 0]
	for p in s.parts:
		var sn: Dictionary = slot_nodes[p["id"]]
		var node: Node3D = sn["node"]
		var preview: Node3D = shelf_nodes[p["id"]]
		var st: String = p["stage"]
		node.visible = st == "positioned" or st == "secured"
		preview.visible = st == "shelf" and p["purchased"]
		if st == "shelf":
			var assigned_role: int = p["owner"]
			var c = Sim.RACKS[assigned_role]
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
		var key := str(s.carry[i])
		if key != carry_vis[i]:
			carry_vis[i] = key
			var n: Node3D = null
			if s.carry[i] != null:
				if key.begins_with("cargo:"):
					n = Gfx.box(Vector3(1.2, 0.8, 0.8), Color("#e9e4f2"))
				else:
					var p = s.part_by_id(s.carry[i])
					n = ShipModel.preview(p["id"], str(g.sim.loadout.get(p["id"], "kestrel")), ACCENT)

			actors[i].set_carry(n)
		var sock: Node3D = actors[i].carry_socket
		if sock.get_child_count() > 0 and not key.begins_with("cargo:"):
			sock.get_child(0).rotation.y = s.rotation[i] * PI * 0.5 - actors[i].rotation.y
	# Placement ghost for the human's carried module.
	var r := s.selected
	var want := ""
	if s.phase == "assembly" and s.carry[r] != null:
		want = "%s:%d" % [s.carry[r], s.rotation[r]]
	if want != ghost_key:
		ghost_key = want
		if ghost:
			ghost.queue_free()
			ghost = null
		if want != "":
			var p = s.part_by_id(s.carry[r])
			ghost = ShipModel.module(p["id"], str(g.sim.loadout.get(p["id"], "kestrel")), ACCENT)
			var ok: bool = s.rotation[r] == p["angle"]
			_tint(ghost, Gfx.unshaded(Color("#9cdeb1") if ok else Color("#ed7d8d"), 0.28))
			ghost.position = p["slot"]
			ghost.rotation.y = (s.rotation[r] - p["angle"]) * PI * 0.5
			add_child(ghost)
	# Rival pads on Earth.
	for rs in rival_ships:
		var t = s.teams[rs["team"]]
		var node: Node3D = rs["node"]
		var on_a: bool = t["planet"] == "A" and not t["eliminated"]
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
		node.position.y = pow(t["phase_time"] / 6.0, 2.0) * 200.0 if t["phase"] == "launching" else 0.0
		node.position.x = rp.x
		node.position.z = rp.z


func _tint(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_tint(c, m)


# ---------------------------------------------------------------------------
# Automated machine assembly: holographic modules streak in, robot arms weld them on, boosters rise on.
# ---------------------------------------------------------------------------
func _fx_init() -> void:
	fx_ready = true
	fx_light = OmniLight3D.new()
	fx_light.light_color = Color("#9fe8ff")
	fx_light.omni_range = 40.0
	fx_light.light_energy = 0.0
	add_child(fx_light)
	for p in g.sim.parts:
		var node: Node3D = slot_nodes[p["id"]]["node"]
		fx_base[p["id"]] = node.position
		for m in node.find_children("*", "MeshInstance3D", true, false):
			fx_orig_mats[m] = (m as MeshInstance3D).material_override
	# Four gantry arms around the ship.
	var bases := [Vector3(-16, 0, -12), Vector3(16, 0, -12), Vector3(-16, 0, 12), Vector3(16, 0, 12)]
	for b in bases:
		var arm := {"base": b, "l1": 15.0, "l2": 15.0}
		var pedestal := Node3D.new()
		pedestal.position = b
		add_child(pedestal)
		Hardware.cylinder(pedestal, 2.0, .35, Vector3(0,.18,0), Color("#303940"))
		Hardware.cylinder(pedestal, .95, 6.6, Vector3(0,3.5,0), Color("#58636a"))
		Hardware.cylinder(pedestal, 1.5, .5, Vector3(0,6.8,0), Color("#bc743d"))
		arm["base"] = b + Vector3(0, 7.0, 0)
		arm["upper"] = _fx_link(Color("#ece7f4"), 0.8)
		arm["lower"] = _fx_link(Color("#f08a4b"), 0.6)
		var tip := Hardware.tool()
		add_child(tip)
		arm["tip"] = tip
		arm["shoulder"] = Hardware.joint(1.1)
		arm["elbow"] = Hardware.joint(.9)
		add_child(arm["shoulder"])
		add_child(arm["elbow"])
		arm["target"] = b + Vector3(0, 12, 0)
		fx_arms.append(arm)
	booster_gantry = Node3D.new()
	booster_gantry.name = "BoosterHandlingGantry"
	add_child(booster_gantry)
	for x in [-24,24]:
		booster_gantry.add_child(Gfx.box(Vector3(1.2,39,1.5),Color("#515c64"),Vector3(x,19.5,0)))
		booster_gantry.add_child(Gfx.box(Vector3(4,.5,6),Color("#303940"),Vector3(x,.25,0)))
	for z in [-1,1]:
		booster_gantry.add_child(Gfx.box(Vector3(50,1.2,.5),Color("#b08440"),Vector3(0,39,z)))
	# Two rocket boosters, placed beside the upright spacecraft once it stands on the pad.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var b := Hardware.booster(1.5, 16.0, "B%02d" % (i+1))
		# The historical booster origin is its tank midpoint.
		for child in b.get_children():
			(child as Node3D).position.y -= 8.0
		for y in [-3.0, 3.0]:
			# Ray/triangle measurements of the actual HullBody at ship y=3.856:
			# booster y=-3 -> ship z=0; booster y=+3 -> ship z=-6.
			var hull_x := 3.589821 if y < 0.0 else 3.461435
			# Bury both ends 0.1 m into the hull and the 1.5 m booster tank.
			var inner := hull_x - 0.1
			var outer := BOOSTER_X - 1.4
			var strut := Hardware.cylinder(b, .18, outer - inner,
				Vector3(-side * (BOOSTER_X - (inner + outer) * .5), y, 0), Color("#657078"))
			strut.rotation.z = PI/2
		var exhaust := ExhaustFX.create(1.05, 12.0, true)
		exhaust.name = "BoosterExhaust"
		exhaust.position.y = -9.65
		exhaust.rotation.x = PI/2
		exhaust.visible = false
		b.add_child(exhaust)
		b.position = Vector3(side * BOOSTER_X, BOOSTER_Y, BOOSTER_PAD_Z)
		b.visible = false
		add_child(b)
		var hoist := Node3D.new()
		hoist.name = "BoosterHoist"
		add_child(hoist)
		hoist.visible = false
		hoist.add_child(Gfx.box(Vector3(2,.6,2.8),Color("#aa7934")))
		var wire := Hardware.cylinder(hoist,.035,1.0,Vector3.ZERO,Color("#59636b"))
		fx_boosters.append({"node": b, "start": i * 1.6, "base": b.position,"hoist":hoist,"wire":wire})


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
	var l1: float = arm["l1"]
	var l2: float = arm["l2"]
	var d := target - base
	var dist := clampf(d.length(), 2.0, l1 + l2 - 0.5)
	var dir := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var pole := side.cross(dir).normalized()
	if pole.y < 0.0:
		pole = -pole
	var elbow := base + dir * a + pole * h
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
	fx_light.light_energy = maxf(0.0, fx_light.light_energy - dt * 30.0)


## Machines carry the cargo crates to the hatch and run the systems checks by themselves.
func _outfit_fx(k: float, dt: float) -> void:
	var s: Sim = g.sim
	if not fx_ready:
		_fx_init()
	var t := k * 6.5
	var hatch := Sim.CARGO_HATCH + Vector3(0, 3.0, 0)
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
			var cp: Vector3 = CONSOLES[type]
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
	fx_light.light_energy = maxf(0.0, fx_light.light_energy - dt * 30.0)


func _ship_erect(e: float) -> void:
	# Hinge on the tail: the hull pivots from horizontal to vertical while sliding onto the pad centre.
	var h := Vector3(0, 5.8, 16.3)
	var hw := h.lerp(Vector3(0, 1.0, 0.0), smoothstep(0.0, 1.0, e))
	var ship_basis := Basis(Vector3.RIGHT, deg_to_rad(90.0) * smoothstep(0.0, 1.0, e))
	ship_root.transform = Transform3D(ship_basis, hw - ship_basis * h)
	for c in _landing_nodes:
		c.visible = e < 0.02


## E was tapped: hydraulic arms lift the spacecraft upright and align it on the pad.
func _erect_fx(k: float, dt: float) -> void:
	if not fx_ready:
		_fx_init()
	_ship_erect(k)
	var mid := ship_root.to_global(Vector3(0, 5.8, -3.0))
	var tail := ship_root.to_global(Vector3(0, 5.8, 16.3))
	for ai in fx_arms.size():
		var arm: Dictionary = fx_arms[ai]
		var goal := mid.lerp(tail, 0.35) if ai % 2 == 0 else mid
		arm["target"] = (arm["target"] as Vector3).lerp(goal, clampf(dt * 5.0, 0.0, 1.0))
		_fx_arm_pose(arm, arm["target"])
		if k > .95 and randf() < dt * 10.0:
			_fx_spark((arm["tip"] as Node3D).position)
	if k > .95 and randf() < dt * 10.0:
		_fx_spark(tail + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), Color("#e9e4f2"))
	if k >= 0.97 and not fx_done.get("erected", false):
		fx_done["erected"] = true
		_fx_snap(Vector3(0, 1.0, 0), 2.2)
		g.sfx("reload_ratchet" if g.streams.has("reload_ratchet") else "reload_click", -2)
	_fx_sparks_tick(dt)


## Boosters are lowered beside the upright spacecraft and clamped on.
func _booster_fx(k: float, dt: float) -> void:
	if not fx_ready:
		_fx_init()
	var t := k * 7.0
	var flick := 1.0 if int(Time.get_ticks_msec() / 70.0) % 2 == 0 else 0.0
	var active: Array = []
	for bi in fx_boosters.size():
		var bd: Dictionary = fx_boosters[bi]
		var bn: Node3D = bd["node"]
		var kk := clampf((t - float(bd["start"])) / 4.0, 0.0, 1.0)
		var key := "booster%d" % bi
		bn.visible = kk > 0.0
		if kk <= 0.0:
			continue
		var side := -1.0 if bi == 0 else 1.0
		var base: Vector3 = bd["base"]
		if kk < 0.65:
			var e := smoothstep(0.0, 1.0, kk / 0.65)
			bn.position = base + Vector3(side * 5.0 * (1.0 - e), 10.0 * (1.0 - e), 0)
			_fx_holo(bn, true, key, flick)
			active.append(bn.global_position)
		else:
			bn.position = base
			_fx_holo(bn, kk < 0.9, key, flick)
			if kk >= 0.9 and not fx_done.get(key, false):
				fx_done[key] = true
				_fx_snap(bn.global_position, 1.8)
				g.sfx("reload_ratchet" if g.streams.has("reload_ratchet") else "reload_click", -3)
			elif kk < 0.9:
				active.append(bn.global_position)
				if randf() < dt * 40.0:
					_fx_spark(bn.global_position + Vector3(randf_range(-2, 2), randf_range(-6, 6), randf_range(-1, 1)))
		var hoist: Node3D = bd["hoist"]
		hoist.visible = kk > 0.0 and kk < .90
		hoist.position = Vector3(bn.position.x,39,bn.position.z)
		var wire: Node3D = bd["wire"]
		var length := maxf(.05,39.0-(bn.position.y+12.05))
		wire.position.y = -length*.5
		wire.scale.y = length
	for ai in fx_arms.size():
		var arm: Dictionary = fx_arms[ai]
		var goal := Vector3(arm["base"].x * 0.2, 20.0, arm["base"].z * 0.2)
		if not active.is_empty():
			goal = active[ai % active.size()]
		arm["target"] = (arm["target"] as Vector3).lerp(goal, clampf(dt * 5.0, 0.0, 1.0))
		_fx_arm_pose(arm, arm["target"])
	_fx_sparks_tick(dt)


func _fx_finish() -> void:
	for mi in fx_orig_mats.keys():
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_override = fx_orig_mats[mi]
	for arm in fx_arms:
		for key in ["upper", "lower", "shoulder", "elbow"]:
			(arm[key] as Node3D).visible = false
		(arm["tip"] as Node3D).visible = false


func cine(kind: String, k: float, dt: float) -> void:
	var s: Sim = g.sim
	var a: Actor = actors[s.selected]
	# Pad FX run after tick(); it already updates actors and world visuals.
	if kind not in ["build", "outfit", "erect", "boosters"]:
		for i in 4:
			actors[i].animate(dt, 0.0, "wave" if kind == "intro" and k < 0.5 else "", false)
		_visuals(dt)
	match kind:
		"build":
			_build_fx(k, dt)
		"outfit":
			_outfit_fx(k, dt)
		"erect":
			_erect_fx(k, dt)
		"boosters":
			_booster_fx(k, dt)
		"intro":
			g.follow_cam(a)
			var target_pos: Vector3 = g.cam.position
			var target_rot: Vector3 = g.cam.rotation
			var e := smoothstep(0.0, 1.0, k)
			g.cam.position = intro_from.lerp(target_pos, e)
			g.cam.look_at(a.position + Vector3(0, 1.8, 0))
			if k > 0.85:
				g.cam.rotation = target_rot
		"launch":
			for light in apron_lights:
				light.light_energy = lerpf(0.8, 0.18, smoothstep(0.05, 0.4, k))
			_launch_ascent(k)



const LAUNCH_HINGE := Vector3(0, 5.8, 16.3)   # tail hinge used by _ship_erect


## One continuous ascent inside the universe: lift-off, boosters shed, gravity turn to level flight.
## The sky and stars come from the shared universe environment; Flight takes over from the final pose.
func _launch_ascent(k: float) -> void:
	if not launch_base_set:
		launch_base_set = true
		launch_base = ship_root.transform
		for bd in fx_boosters:
			bd["launch_local"] = launch_base.affine_inverse() * (bd["node"] as Node3D).transform
			bd.erase("shed_from")
	flame.visible = true
	for i in 4:
		actors[i].visible = false
	var alt := k * k * LAUNCH_ALTITUDE
	var turn := smoothstep(0.38, 0.89, k)
	var angle := deg_to_rad(90.0) * (1.0 - turn)
	var fwd := -turn * turn * LAUNCH_DOWNRANGE
	var hinge_w := Vector3(0, 1.0 + alt, fwd)
	var ship_basis := Basis(Vector3.RIGHT, angle)
	ship_root.transform = Transform3D(ship_basis, hinge_w - ship_basis * LAUNCH_HINGE)
	# +Y on each booster follows the ship's nose direction (-Z in ship space).
	# Both nodes share this parent, so these transforms also preserve world alignment.
	var shed: bool = g.cine["t"] >= BOOSTER_BURN_TIME
	var launch_shed_t := maxf(0.0, g.cine["t"] - BOOSTER_BURN_TIME)
	for bi in fx_boosters.size():
		var bd: Dictionary = fx_boosters[bi]
		var bn: Node3D = bd["node"]
		var side := -1.0 if bi == 0 else 1.0
		var attached: Transform3D = ship_root.transform * (bd["launch_local"] as Transform3D)
		if not shed:
			bn.transform = attached
		else:
			if not bd.has("shed_from"):
				# Capture the attachment pose on the staging frame.
				bd["shed_from"] = attached
			var from: Transform3D = bd["shed_from"]
			bn.transform = Transform3D(
				Basis(Vector3.FORWARD, side * launch_shed_t * .9) * from.basis,
				from.origin + Vector3(side * 5.0 * launch_shed_t, -13.0 * launch_shed_t * launch_shed_t, 0))
		bn.get_node("BoosterExhaust").visible = not shed
	# Camera: side view from the pad, easing into Flight's pilot chase camera.
	var ref := ship_root.position
	var side_cam := Vector3(36, 8 + alt * 0.94, 62)
	var side_look := hinge_w + Vector3(0, 12, 0)
	var chase_cam := ref + Vector3(23, 13, 43)
	var chase_look := ref + Vector3(0, 5, -8)
	var e := smoothstep(0.25, 0.64, k)
	g.cam.position = side_cam.lerp(chase_cam, e)
	g.cam.look_at(side_look.lerp(chase_look, e), Vector3.UP)
	if k > 0.12 and k < 0.5:
		g.cam.position += Vector3(randf() - 0.5, randf() - 0.5, 0) * 0.4


## Flight has landed the ship back at home: stand it on the pad again and switch to the delivery run.
func arrive_home() -> void:
	delivery = true
	ship_root.transform = Transform3D(Basis.IDENTITY, Flight.A_LAND)
	ship_root.visible = true
	flame.visible = false
	for c in _landing_nodes:
		c.visible = true
	for bd in fx_boosters:
		(bd["node"] as Node3D).visible = false
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
	match s.phase:
		"assembly":
			hud.title.text = "BUILD BEFORE THEY LAUNCH."
			hud.subtitle.text = "%d/12 MODULES · CREDITS %d" % [s.secured_count(), s.credits]
		"outfit":
			hud.title.text = "EVERY MODULE HAS A COST."
			hud.subtitle.text = "STOW SUPPLIES · RUN SYSTEMS CHECKS"
		"delivery", "delivered":
			hud.title.text = "BRING IT HOME."
			hud.subtitle.text = "%d FLAGS DELIVERED" % s.teams[0]["delivered"]
		_:
			hud.title.text = "STAND BY."
	var lines := PackedStringArray()
	if s.phase == "assembly" and s.shop_open:
		hud.title.text = "DESIGN YOUR SPACECRAFT."
		hud.subtitle.text = "%d/12 SLOTS CONFIRMED · CREDITS %d" % [s.confirmed_count(), s.credits]
		# Compact summary while walking; full per-slot detail lives in the Ship Builder terminal.
		var next_slot := ""
		for p in s.parts:
			if not s.slot_confirmed(p["id"]):
				next_slot = str(p["id"]).to_upper()
				break
		lines.append("[color=#eaa665][b]%d/12 MODULES CONFIRMED[/b][/color]" % s.confirmed_count())
		if next_slot != "":
			lines.append("[color=#b4a8c6]Next: %s · E at the holo terminal to open the builder[/color]" % next_slot)
		else:
			lines.append("[color=#9cdeb1]All slots set · E at the desk starts assembly[/color]")
	elif s.phase == "assembly":
		lines.append("[color=#eaa665][b]%d/12 MODULES SECURED[/b][/color]" % s.secured_count())
		var mine := ""
		for p in s.parts:
			if p["owner"] == s.selected and p["stage"] != "secured":
				mine = str(p["name"])
				break
		if mine != "":
			lines.append("[color=#b4a8c6]Your next: %s · E pick up · R rotate · hold LMB to bolt[/color]" % mine)
		else:
			lines.append("[color=#9cdeb1]Your modules are secured · help the crew[/color]")
	elif s.phase == "outfit":
		lines.append("[color=#eaa665][b]OUTFIT · SUPPLIES & CHECKS[/b][/color]")
		for x in s.cargo:
			lines.append("%s %s [color=#7d7191]%s[/color]" % ["[color=#9cdeb1]✓[/color]" if x["stowed"] else "○", x["name"], Sim.SPECIALISTS[x["owner"]]["name"]])
		for type in ["pressure", "power", "engine"]:
			lines.append("%s %s check %d%% [color=#7d7191]%s[/color]" % ["[color=#9cdeb1]✓[/color]" if s.checks[type] >= 1.0 else "○", type.capitalize(), int(s.checks[type] * 100), Sim.SPECIALISTS[Sim.CHECK_ROLE[type]]["name"]])
	else:
		var c := s.flag_counts(0)
		lines.append("[color=#eaa665][b]DELIVERY[/b][/color]")
		lines.append("On board: %d · Delivered: %d" % [c["onboard"], c["delivered"]])
		lines.append("[color=#b4a8c6]Only flags transferred to Earth score.[/color]")
	hud.objectives.text = "\n".join(lines)
	hud.vitals_panel.visible = false
	hud.station_panel.visible = false
	hud.crosshair.visible = false
	hud.footer.text = "WASD MOVE · SHIFT SPRINT · SPACE JUMP · V VIEW · 1–4 ROLES · E INTERACT · R ROTATE · LMB FASTEN · M MAP · H MANUAL · ESC MENU"
	hud.radar_title.text = "EARTH · " + ("BUILD" if s.phase == "assembly" else ("OUTFIT" if s.phase == "outfit" else "DELIVER"))
	for i in 4:
		var owned := s.parts.filter(func(p): return p["owner"] == i)
		var done := owned.filter(func(p): return p["stage"] == "secured").size()
		var st := ""
		if s.phase == "assembly":
			st = "BUILDING %d/%d" % [done, owned.size()] if done < owned.size() else "READY"
		elif s.phase == "outfit":
			st = "CARRYING" if s.carry[i] != null else "OUTFITTING"
		else:
			st = "HOME"
		hud.set_crew_status(i, st + (" · YOU" if i == s.selected else " · BOT"), float(done) / maxf(1.0, owned.size()) if s.phase == "assembly" else 1.0)
	var pts: Array = []
	var origin := a.position
	var rot: float = g.yaw
	var add := func(p: Vector3, col: Color, size: float, ring: bool, label: String):
		var offset := p - origin
		pts.append({"p": Vector2(offset.x, offset.z).rotated(rot), "c": col, "s": size,
			"ring": ring, "label": label, "dist": offset.length()})
	add.call(Vector3.ZERO, Color("#ece7f4"), 6.0, true, "PAD")
	if not beacon.visible or beacon_target != SHOP:
		add.call(SHOP, Color("#ffd29a"), 4.5, true, "SHOP")
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
	hud.update_tactical(pts, "EARTH · LIVE TACTICAL MAP")


# ===========================================================================
# Menu showcase hangar
# ===========================================================================
class Showcase extends Node3D:
	var g
	var actors: Array = []
	var kind := "home"
	var sel := 3
	var t := 0.0

	var podium_rings: Array = []
	var lobby_ships: Array = []   # {node, speed, y, z, x_min, x_max}
	var lobby_planet: Node3D

	func tick(dt: float) -> void:
		t += dt
		for i in actors.size():
			var a: Actor = actors[i]
			# Lively Fortnite-style staggered idle emotes, weight shifts, and glances (never stiff!).
			var cycle := fmod(t + i * 2.1, 7.5)
			var act := "wave" if (kind == "select" and (i == sel and cycle < 2.2 or i != sel and cycle > 5.8)) else ""
			a.animate(dt, 0.0, act)
			if kind == "select":
				var base_x := -5.4 + i * 3.6
				var base_z := 0.85 if i == sel else (0.15 if i % 2 == 1 else -0.35)
				a.position = Vector3(base_x, 0.0, base_z)
				var glance := sin(t * (0.9 + i * 0.17) + i * 1.4) * 0.22
				a.rotation.y = PI + glance
				if i < podium_rings.size():
					var ring: MeshInstance3D = podium_rings[i]
					ring.position = Vector3(base_x, 0.13, base_z)
					var pulse := 1.0 + 0.04 * sin(t * 3.4 + i)
					ring.scale = Vector3(pulse, 0.05, pulse) * (1.18 if i == sel else 0.94)
		# Animate distant spacecraft cruising outside the orbital hangar viewport + rotating planet.
		if lobby_planet != null:
			lobby_planet.rotation.y += dt * 0.04
		for sh in lobby_ships:
			var n: Node3D = sh["node"]
			n.position.x += float(sh["speed"]) * dt
			n.position.y = float(sh["y"]) + sin(t * 0.9 + float(sh["phase"])) * 0.45
			if float(sh["speed"]) > 0.0 and n.position.x > float(sh["x_max"]):
				n.position.x = float(sh["x_min"])
			elif float(sh["speed"]) < 0.0 and n.position.x < float(sh["x_min"]):
				n.position.x = float(sh["x_max"])
		if kind == "home":
			g.cam.position = Vector3(-0.6 + sin(t * 0.15) * 0.2, 1.9, 6.0)
			g.cam.look_at(Vector3(1.9, 1.5, 0))
		else:
			g.cam.position = Vector3(0.0 + sin(t * 0.14) * 0.28, 2.05, 10.6)
			g.cam.look_at(Vector3(0.0, 1.15, -1.0))

	func layout(p_kind: String, p_sel: int) -> void:
		kind = p_kind
		sel = p_sel
		for i in actors.size():
			var a: Actor = actors[i]
			if kind == "home":
				a.visible = i == sel
				a.position = Vector3(3.2, 0, 0)
				a.rotation.y = PI - 0.35
			else:
				a.visible = true
				var base_z := 0.85 if i == sel else (0.15 if i % 2 == 1 else -0.35)
				a.position = Vector3(-5.4 + i * 3.6, 0, base_z)
				a.rotation.y = PI
			a.scale = Vector3.ONE * (1.08 if i == sel else 0.96)
			if i < podium_rings.size():
				(podium_rings[i] as Node3D).visible = kind == "select"


static func showcase(main) -> Node3D:
	var s := Showcase.new()
	s.g = main
	# Deep orbital galaxy & starfield space sky visible through the panoramic hangar windows.
	s.add_child(Gfx.environment(Color("#040814"), Color("#12264a"), Color("#03060f"), 0.55))

	# Dramatic orbital hangar lighting: cool blue galaxy backlight + warm golden deck rim lights.
	var galaxy_back := OmniLight3D.new()
	galaxy_back.light_color = Color("#70c4ff")
	galaxy_back.light_energy = 3.2
	galaxy_back.omni_range = 34.0
	galaxy_back.position = Vector3(0, 5.5, -9.5)
	s.add_child(galaxy_back)
	var key := OmniLight3D.new()
	key.light_color = Color("#ffebd0")
	key.light_energy = 2.4
	key.omni_range = 24.0
	key.position = Vector3(5, 6, 7)
	s.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color("#5eb8ff")
	fill.light_energy = 1.6
	fill.omni_range = 26.0
	fill.position = Vector3(-7, 4.5, 6)
	s.add_child(fill)
	s.add_child(Gfx.sun(Vector3(-28, 22, 0), Color("#ffe4b8"), 0.95))

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

	# Giant glowing planet + distant moon outside the panoramic hangar window.
	var planet := Gfx.planet(14.5, Color("#245994"), Color("#70c4ff"))
	planet.position = Vector3(13.5, 9.5, -36.0)
	s.add_child(planet)
	s.lobby_planet = planet
	var moon_orb := Gfx.sphere(2.8, Color("#cbd5e1"), Vector3(-11.0, 11.0, -32.0), 0.15, 24)
	s.add_child(moon_orb)

	# 4 moving spacecraft cruising across the starfield outside the viewport!
	var hull_mat := Gfx.mat(Color("#cbd5e1"), 0.45)
	var glow_cyan := Gfx.mat(Color("#38bdf8"), 0.2, 3.0)
	var glow_amber := Gfx.mat(Color("#f59e0b"), 0.2, 3.0)
	var ship_specs := [
		[-14.0, 5.2, -18.0, 2.4, 0.9, glow_cyan],
		[15.0, 7.8, -22.0, -1.9, 1.15, glow_amber],
		[-18.0, 3.6, -25.0, 1.5, 0.75, glow_cyan],
		[12.0, 9.4, -27.0, -2.6, 0.85, glow_cyan],
	]
	for idx in ship_specs.size():
		var sp: Array = ship_specs[idx]
		var craft := Node3D.new()
		var body := Gfx.box(Vector3(2.4, 0.55, 0.95), Color("#cbd5e1"), Vector3.ZERO)
		body.material_override = hull_mat
		var wing := Gfx.box(Vector3(0.9, 0.14, 2.5), Color("#94a3b8"), Vector3(-0.2, 0, 0))
		var thruster_x := -1.35 if float(sp[3]) > 0.0 else 1.35
		var engine := Gfx.sphere(0.28, Color("#38bdf8"), Vector3(thruster_x, 0, 0), 2.5, 10)
		engine.material_override = sp[5]
		craft.add_child(body)
		craft.add_child(wing)
		craft.add_child(engine)
		craft.scale = Vector3.ONE * float(sp[4])
		craft.position = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
		s.add_child(craft)
		s.lobby_ships.append({
			"node": craft, "speed": float(sp[3]), "y": float(sp[1]), "z": float(sp[2]),
			"x_min": -26.0, "x_max": 26.0, "phase": float(idx) * 1.7,
		})

	# 4 sci-fi metallic pedestals with glowing cyan/gold rims.
	for i in 4:
		var base_x := -5.4 + i * 3.6
		var podium := Gfx.disc(1.52, Color("#334155"), 0.14)
		podium.position = Vector3(base_x, 0, 0)
		s.add_child(podium)
		var ring := Gfx.ring(1.54, 0.14, Color("#67e8f9"), 0.95)
		ring.position = Vector3(base_x, 0.15, 0)
		s.add_child(ring)
		s.podium_rings.append(ring)
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
	remove_child(ship_root)
	ship_root.free()
	for preview in shelf_nodes.values():
		remove_child(preview)
		preview.free()
	shelf_nodes.clear()
	slot_nodes.clear()
	_ship()
	ship_root.transform = pose
	if is_instance_valid(shop_kiosk_node):
		preload("res://scripts/shop_kiosk.gd").update_hologram(shop_kiosk_node, g.sim.loadout)
