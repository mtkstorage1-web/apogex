## Planet C (Moon arena)
## twelve finite Science Flags, four landing bays, rival raiders.
## Fernando scans flags (hold LMB, 5 s), anyone can carry them, E loads at the ship.
class_name PlanetB
extends Node3D

const WorldLabels := preload("res://scripts/ui/world_labels.gd")
const ArenaClashRules := preload("res://scripts/arena_clash_sim.gd")

const ACCENT := Color("#f08a4b")
const CRYSTAL := Color("#6fe0e6")
const SHIP_POS := Vector3(0, 0, 58)
const HATCH := SHIP_POS + Vector3(0, 0, -15.5) * ShipModel.VESSEL_SCALE
const RIVAL_AIM_TIME := 0.55
const RELOAD_SECONDS := 1.3
const RELOAD_RATCHET_REMAINING := 0.49
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const TexturedEnvironment = preload("res://scripts/textured_environment.gd")
const MUZZLE_LIGHT_TIME := 0.075

const EmpireLayer = preload("res://scripts/empire_world_layer.gd")
var empire_layer: EmpireLayer
var _golden_unlocked := false

const ARENA_SEARCH_INTERVAL := 0.3
const ARENA_DETAIL_RANGE_SQ := 32.0 * 32.0
var arena_actors: Dictionary = {}
var _arena_teams := {"planet_a": [], "planet_b": []}
var _arena_score := {}
var _arena_player_id := ""
var _arena_aboard := false

var g
var actors: Array = []
var rivals := {}
var flag_nodes := {}
var rival_ships := {}
var beacon: MeshInstance3D
var suit_hp := [100.0, 100.0, 100.0, 100.0]
var last_hit := [0.0, 0.0, 0.0, 0.0]
var field_hp: float:
	get: return suit_hp[g.sim.selected]
	set(value): suit_hp[g.sim.selected] = value
var materials := {}
var hit_flash := 0.0
var down_times := [0.0, 0.0, 0.0, 0.0]
var down_t: float:
	get: return down_times[g.sim.selected]
	set(value): down_times[g.sim.selected] = value
var magazines := [24, 24, 24, 24]
var ammo: int:
	get: return magazines[g.sim.selected]
	set(value): magazines[g.sim.selected] = value
var ko_streak := 0
var ko_streak_clock := 0.0
var reload_times := [0.0, 0.0, 0.0, 0.0]
var reload_t: float:
	get: return reload_times[g.sim.selected]
	set(value): reload_times[g.sim.selected] = value
var fire_cd := 0.0
var first_person_rig: Node3D
var first_person_models: Array = []
var bot_fire := [1.0, 1.0, 1.0, 1.0]
var rival_shot := [2.0, 2.0, 2.0, 2.0, 2.0]
var tracers: Array = []
var carry_vis: Array = ["", "", "", ""]
var last_stage := {}
var blockers: Array = []
var rng := RandomNumberGenerator.new()
const KB_MAX := 14.0
const KB_FRICTION := 4.5   # lunar regolith ground friction (1/s exponential decay)
const FLAG_DROP_GRAVITY := -3.8
const FLAG_REST_Y := 0.7
var fx_rng := RandomNumberGenerator.new()
var camera_obstacles: Array = []
var navigation := preload("res://scripts/arena_navigation.gd").new()
var priority_beacon: Node3D
var hatch_beacon: Label3D
var scan_beam: MeshInstance3D
var shield_bubble: MeshInstance3D
var scan_sfx_cd := 0.0
var dust_mesh: QuadMesh
var dust_fade: Gradient
var extract_ring: MeshInstance3D
var flag_state_prev := {}
var combat_hud: CombatHUD
var recoil_pitch := 0.0
var recoil_yaw := 0.0
var recoil_t := 0.0
var _recoil_role := -1
const RECOIL_RECOVER := 0.12
const HP_BAR_W := 1.1
const SQUAD_CALLSIGNS := ["VANGUARD", "MEDIC", "BREACHER"]   # roles 0-2 of the 4-player rival squad (leader = RAIDER)
const GRENADE_FUSE := 1.6
const GRENADE_RADIUS := 6.5
const MELEE_RANGE := 2.8
## Player's landed ship: the hull is sim.hull; the ship shield lives here (sim.shield is the personal suit shield).
const SHIP_SHIELD_MAX := 60.0
var ship_shield := SHIP_SHIELD_MAX
var ship_hit_t := 99.0               # seconds since the ship was last hit (shield recharges after 6 s)
const SHIP_SHIELD_RECHARGE_DELAY := 6.0
var ship_alert_cd := 0.0
var ship_smoke_t := 0.0
var ship_dome: MeshInstance3D
var ship_dome_flash := 0.0
var ship_status: Label3D
var ship_shot := {}                  # "t:k" -> ship fire cooldown
var squad_shot := {}                 # "t:k" -> fire cooldown
var crouching := false
var lean := 0.0                      # -1 left .. +1 right (smoothed)
var lean_target := 0
var melee_cd := 0.0
var grenade_cd := 0.0
var grenades := 3
var medkit_cd := 0.0
var medkits := 3
var live_grenades: Array = []
var _queued_actions := {}
var _action_prev := {}
var _touch_hooked := false
var _resupply_t := 0.0
var _crouch_amt := 0.0
var _lunar_environment: Environment
var _previous_camera_environment: Environment
var _lighting_camera: Camera3D
var _earthshine: DirectionalLight3D
var _muzzle_light: OmniLight3D
var _muzzle_light_t := 0.0


func actor(i: int) -> Actor:
	if g.arena_clash != null:
		return arena_actors.get("%s:%d" % [g.arena_clash.player_squad, i], {}).get("actor")
	return actors[i]


func setup(main) -> void:
	g = main
	name = "PlanetCMoon"
	ship_shield = SHIP_SHIELD_MAX
	ship_hit_t = 99.0
	_sync_flight_shield()
	rng.seed = g.sim.match_seed + 99
	fx_rng.seed = g.sim.match_seed + 777
	# Editable terrain, lighting, landing pads and scenery are stored in a scene.
	var editable: Node3D = g.universe.ensure_moon_environment()
	# Only nearby rocks tagged with a gameplay radius block movement.
	for rock in editable.get_node("Terrain/TerrainRocks").get_children():
		if rock.has_meta("gameplay_radius"):
			var pt: Vector3 = (rock as Node3D).position
			blockers.append({"c": Vector2(pt.x, pt.z), "r": float(rock.get_meta("gameplay_radius")), "cover": true})
	# Keep the old rocks as distant scenery; the combat space now uses authored cover.
	var rock_palette := [
		Gfx.terrain_mat(Color("#858078"), true), Gfx.terrain_mat(Color("#716d66"), true),
		Gfx.terrain_mat(Color("#998f82"), true),
	]
	for rock in editable.get_node("Terrain/TerrainRocks").get_children():
		if rock is MeshInstance3D:
			rock.material_override = rock_palette[rock.get_index() % rock_palette.size()]
			if not rock.has_meta("gameplay_radius") or absf(rock.position.x) < 43.0 and absf(rock.position.z) < 39.0:
				rock.hide()
	blockers = blockers.filter(func(b): return absf(b["c"].x) >= 43.0 or absf(b["c"].y) >= 39.0)
	var arena: Node3D = preload("res://scenes/levels/FrontierArena.tscn").instantiate()
	# Raise the foundation just above the flat terrain, below the lane floors.
	var foundation := arena.get_node("ArenaFoundation") as MeshInstance3D
	foundation.position.y += 0.017
	TexturedEnvironment.surface_arena(arena)
	for bay in editable.get_node("LandingBays").get_children():
		bay.scale *= Vector3(ShipModel.VESSEL_SCALE, 1.0, ShipModel.VESSEL_SCALE)
		PlanetA.weather_pad(bay.get_node("LandingPlatform"), 14.0, 0.55)
	var load_ramp := editable.get_node("LoadRamp") as Node3D
	load_ramp.position = HATCH
	for x in [-4.5, 4.5]:
		for offset in [0.5, 5.5]:
			PlanetA.add_apron_fixture(self, HATCH + Vector3(x, 0.1, offset), Color("#b1dded"))
	add_child(arena)
	for piece in arena.get_children():
		if piece.has_meta("arena_cover"):
			var dimensions: Vector3 = piece.get_meta("cover_size")
			blockers.append({"c": Vector2(piece.position.x, piece.position.z), "half": Vector2(dimensions.x, dimensions.z) * 0.5, "r": maxf(dimensions.x, dimensions.z) * 0.5, "cover": true, "center3": piece.position, "size3": dimensions})
	preload("res://scripts/model_detail.gd").batch(editable.get_node("Terrain/TerrainRocks"), [], 900.0)
	preload("res://scripts/model_detail.gd").surroundings(self, SHIP_POS + Vector3(10,0,0))
	if g.sim.empire != null:
		empire_layer = EmpireLayer.new()
		empire_layer.setup(g.sim.empire, g.sim.empire_enemy, false, g.sim.empire_squad, g.request_empire_action)
		add_child(empire_layer)
		g.sim.set_empire_vault_sites(EmpireLayer.FRONTIER_SITES.back())
	if g.arena_clash == null:
		_flags()
		_ships()
		_crew()
		_rival_actors()
		_build_first_person()
	navigation.build(blockers)
	g.sim.navigation = navigation
	beacon = Gfx.cyl(0.3, 40.0, ACCENT, Vector3.ZERO, 8)
	beacon.material_override = Gfx.unshaded(Color("#ffb347"), 0.3)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)
	if g.arena_clash == null:
		_build_waypoints()
	_build_crater_perimeter()
	_build_lunar_lighting()
	if g.arena_clash == null:
		_colour_pass()
	combat_hud = CombatHUD.new()
	combat_hud.name = "CombatHUD"
	add_child(combat_hud)
	g.yaw = 0.0
	g.pitch = -0.18


func _build_crater_perimeter() -> void:
	# Keep all footprints beyond the navigation grid (±84 m) and clear of the rival bays.
	var perimeter := Node3D.new()
	perimeter.name = "LunarCraterPerimeter"
	add_child(perimeter)
	BlenderVisualUpgrades.place(perimeter, "rocks/highland_granite_slab.glb", Vector3(-79, 0, -120), 34.0, 0.7)
	BlenderVisualUpgrades.place(perimeter, "rocks/highland_granite_slab.glb", Vector3(71, 0, -126), 25.0, -0.45)
	BlenderVisualUpgrades.place(perimeter, "rocks/basalt_boulder_a.glb", Vector3(107, 0, -41), 16.0, 0.3)
	BlenderVisualUpgrades.place(perimeter, "rocks/basalt_column_cluster.glb", Vector3(28, 0, -121), 26.0, -0.5)
	BlenderVisualUpgrades.place(perimeter, "rocks/iron_ore_outcrop.glb", Vector3(-103, 0, -19), 22.0, 0.7)
	BlenderVisualUpgrades.place(perimeter, "surface/mining_drill_tower.glb", Vector3(-38, 0, -117), 31.0, -0.5)
	BlenderVisualUpgrades.place(perimeter, "landmarks/relay_tower.glb", Vector3(62, 0, -115), 31.0, 0.25)
	BlenderVisualUpgrades.place(perimeter, "surface/hab_module_derelict.glb", Vector3(-11, 0, -106), 21.0, 0.3)
	BlenderVisualUpgrades.place(perimeter, "vehicles/cinder_dropship.glb", Vector3(101, 0, -73), 18.0, 0.7)
	BlenderVisualUpgrades.place(perimeter, "vehicles/cinder_rover.glb", Vector3(99, 0, -56), 7.0, -0.8)


func _build_lunar_lighting() -> void:
	_earthshine = DirectionalLight3D.new()
	_earthshine.name = "Earthshine"
	_earthshine.light_color = Color("#9bc3ff")
	_earthshine.light_energy = 0.095
	_earthshine.basis = Basis.looking_at(-Universe.EARTH_SKY_DIRECTION.normalized())
	_earthshine.hide()
	add_child(_earthshine)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.name = "FieldMuzzleLight"
	_muzzle_light.omni_range = 8.0
	_muzzle_light.omni_attenuation = 1.3
	_muzzle_light.hide()
	add_child(_muzzle_light)
	set_process(false)


func _apply_lunar_lighting() -> void:
	var source: Environment = g.universe.env
	if _lunar_environment == null:
		_lunar_environment = source.duplicate() as Environment
		_lunar_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_lunar_environment.ambient_light_color = Color("#8999b2")
		_lunar_environment.ambient_light_energy = 0.038
		_lunar_environment.ambient_light_sky_contribution = 0.0
		_lunar_environment.fog_enabled = false
		_lunar_environment.volumetric_fog_enabled = false
		_lunar_environment.ssil_enabled = false
	if _lighting_camera != g.cam:
		_release_lunar_lighting()
		_lighting_camera = g.cam
		_previous_camera_environment = _lighting_camera.environment
		_lighting_camera.environment = _lunar_environment
		_earthshine.show()
		set_process(true)
	_lunar_environment.ssr_enabled = source.ssr_enabled
	_lunar_environment.ssao_enabled = source.ssao_enabled
	_lunar_environment.ssao_intensity = source.ssao_intensity
	_lunar_environment.glow_enabled = source.glow_enabled
	_lunar_environment.glow_intensity = source.glow_intensity
	_lunar_environment.glow_bloom = source.glow_bloom
	_lunar_environment.adjustment_brightness = source.adjustment_brightness
	g.universe.sun.light_energy = 2.6
	g.universe.sun.light_color = Color("#fff7e9")


func _release_lunar_lighting() -> void:
	if is_instance_valid(_lighting_camera) and _lighting_camera.environment == _lunar_environment:
		_lighting_camera.environment = _previous_camera_environment
	_lighting_camera = null
	_previous_camera_environment = null
	if is_instance_valid(_earthshine):
		_earthshine.hide()
	if is_instance_valid(_muzzle_light):
		_muzzle_light.hide()
	_muzzle_light_t = 0.0


func _process(_dt: float) -> void:
	if g.world != self:
		_release_lunar_lighting()
		set_process(false)


## Vivid bioluminescent palette (cyan, amethyst, coral, amber) used by the lunar surface accents.
const VIVID := [Color("#22d3ee"), Color("#a855f7"), Color("#ff6b6b"), Color("#ffb020")]


## Visual-only colour pass: glowing crystal clusters, coloured fill lights and landmark accents.
func _colour_pass() -> void:
	var root := Node3D.new()
	root.name = "ColourAccents"
	add_child(root)
	# Crystal clusters + a coloured glow at every science flag site.
	for i in Sim.FLAG_SITES.size():
		var site = Sim.FLAG_SITES[i]
		var col: Color = VIVID[i % VIVID.size()]
		var base := Vector3(site[0], 0.0, site[1])
		_crystal_cluster(root, base + Vector3(1.9, 0, 1.2), col, i)
		_crystal_cluster(root, base + Vector3(-1.7, 0, -1.4), VIVID[(i + 2) % VIVID.size()], i + 5)
		var glow := OmniLight3D.new()
		glow.light_color = col
		glow.light_energy = 0.43
		glow.omni_range = 6.0
		glow.shadow_enabled = false
		glow.position = base + Vector3(0, 1.6, 0)
		root.add_child(glow)
	# Each landing bay gets a beacon mast and a bay-coloured under-glow.
	for i in Sim.LANDING_BAYS.size():
		var bay = Sim.LANDING_BAYS[i]
		var bp := Vector3(bay[0], 0.0, bay[1])
		var col: Color = VIVID[(i + 1) % VIVID.size()]
		for k in 3:
			var a := TAU * float(k) / 3.0 + 0.5
			_crystal_cluster(root, bp + Vector3(cos(a), 0, sin(a)) * 12.5 * ShipModel.VESSEL_SCALE, col, i * 3 + k)
		var under := OmniLight3D.new()
		under.light_color = col
		under.light_energy = 0.65
		under.omni_range = 9.0
		under.position = bp + Vector3(0, 2.0, 0)
		root.add_child(under)
		var mast_offset := Vector3.RIGHT * 8.5 * ShipModel.VESSEL_SCALE
		var mast := Gfx.cyl(0.12, 7.0, col, bp + mast_offset + Vector3.UP * 3.5, 6)
		mast.material_override = Gfx.mat(col, 0.3, 1.8)
		root.add_child(mast)
		var lamp := Gfx.sphere(0.4, col, bp + mast_offset + Vector3.UP * 7.2, 3.5, 10)
		root.add_child(lamp)
		var tw := lamp.create_tween().set_loops()
		tw.tween_property(lamp, "scale", Vector3.ONE * 1.5, 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_property(lamp, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_SINE)
	# Load-ramp landmark: warm amber/coral lamps flanking the hatch.
	for sx in [-1.0, 1.0]:
		var lamp_col := Color("#ffb020") if sx < 0.0 else Color("#ff6b6b")
		var lamp := Gfx.sphere(0.5, lamp_col, HATCH + Vector3(sx * 5.5, 2.4, 0), 3.2, 10)
		root.add_child(lamp)
		var l := OmniLight3D.new()
		l.light_color = lamp_col
		l.light_energy = 0.8
		l.omni_range = 8.0
		l.position = lamp.position
		root.add_child(l)
	# Scattered far crystal outcrops give the horizon colour.
	var cr := RandomNumberGenerator.new()
	cr.seed = g.sim.match_seed + 4242
	for n in 28:
		var ang := cr.randf() * TAU
		var d := cr.randf_range(52.0, 95.0)
		var p := Vector3(cos(ang) * d, 0.0, sin(ang) * d)
		_crystal_cluster(root, p, VIVID[n % VIVID.size()], n + 40)


func _crystal_cluster(parent: Node3D, pos: Vector3, col: Color, seed_i: int) -> void:
	var node := Node3D.new()
	node.position = pos
	node.rotation.y = float(seed_i) * 1.7
	parent.add_child(node)
	for k in 4:
		var h := 0.9 + float((seed_i * 7 + k * 5) % 9) * 0.22
		var shard := Gfx.cyl(0.26 - k * 0.03, h, col, Vector3(cos(k * 1.9) * 0.45, h * 0.5, sin(k * 1.9) * 0.45), 5, 0.0)
		shard.material_override = Gfx.mat(col, 0.2, 2.4)
		shard.rotation = Vector3(sin(k * 2.3) * 0.28, 0.0, cos(k * 1.3) * 0.28)
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(shard)


func _build_waypoints() -> void:
	priority_beacon = Node3D.new()
	priority_beacon.name = "PriorityBeacon"
	var pbeam := Gfx.cyl(0.22, 32.0, UI.ACCENT, Vector3(0, 16, 0), 8)
	pbeam.material_override = Gfx.unshaded(UI.ACCENT, 0.22)
	pbeam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	priority_beacon.add_child(pbeam)
	BlenderVisualUpgrades.place(priority_beacon, "combat/capture_beacon_node.glb", Vector3(0, -0.22, 0), 1.5)
	var plab := Gfx.label("★ PRIORITY SAMPLE", UI.ACCENT, 44)
	plab.position = Vector3(0, 6.2, 0)
	priority_beacon.add_child(plab)
	priority_beacon.visible = false
	add_child(priority_beacon)

	hatch_beacon = Gfx.label("▲ SHIP LOAD RAMP", Color("#9cdeb1"), 46)
	hatch_beacon.name = "HatchBeacon"
	hatch_beacon.add_to_group("station_labels")
	hatch_beacon.position = HATCH + Vector3(0, 4.2, 0)
	hatch_beacon.visible = false
	add_child(hatch_beacon)

	scan_beam = Gfx.cyl(0.06, 1.0, Color("#38bdf8"), Vector3.ZERO, 6)
	scan_beam.name = "ScanBeam"
	scan_beam.material_override = Gfx.unshaded(Color("#38bdf8"), 0.72)
	scan_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scan_beam.visible = false
	add_child(scan_beam)

	shield_bubble = Gfx.sphere(1.45, Color("#38bdf8"), Vector3(0, 1.3, 0), 0.3, 14)
	shield_bubble.name = "ShieldBubble"
	shield_bubble.material_override = Gfx.unshaded(Color("#22d3ee"), 0.18)
	shield_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield_bubble.visible = false
	add_child(shield_bubble)


## Your ship's pad model: hidden while the Flight carries the ship, shown again once it touches down.
func hide_ship() -> void:
	if rival_ships.has(0):
		(rival_ships[0]["node"] as Node3D).visible = false
		(rival_ships[0]["label"] as Node3D).visible = false


func arrive() -> void:
	if rival_ships.has(0):
		(rival_ships[0]["node"] as Node3D).visible = true
		(rival_ships[0]["label"] as Node3D).visible = true


func _near_bay(p: Vector3, r: float) -> bool:
	for b in Sim.LANDING_BAYS:
		if Vector2(p.x - b[0], p.z - b[1]).length() < r:
			return true
	for s in Sim.FLAG_SITES:
		if Vector2(p.x - s[0], p.z - s[1]).length() < 5.0:
			return true
	return false


func _flags() -> void:
	# All flag geometry lives in a reusable scene; per-flag state stays in the simulator.
	var template: PackedScene = preload("res://scenes/prefabs/FlagMarker.tscn")
	for f in g.sim.flags:
		var site: Vector3 = f.get("site_position", f["position"])
		var marker: Node3D = template.instantiate() as Node3D
		marker.name = "Flag%02d" % (int(f["id"]) + 1)
		marker.position = site
		add_child(marker)
		var crystal: Node3D = marker.get_node("Crystal") as Node3D
		var gem: MeshInstance3D = marker.get_node("Crystal/Gem") as MeshInstance3D
		var pennant: MeshInstance3D = marker.get_node("Crystal/Pennant") as MeshInstance3D
		var ring: MeshInstance3D = marker.get_node("ScanRing") as MeshInstance3D
		var lab: Label3D = marker.get_node("FlagLabel") as Label3D
		if f["id"] < Sim.FLAG_SITES.size():
			blockers.append({"c": Vector2(site.x, site.z), "r": 1.3})
		# Tension cue: a pulsing luminous halo that rides under whoever carries this flag.
		var aura := Gfx.ring(1.6, 0.16, CRYSTAL, 0.8)
		aura.name = "CarryAura"
		aura.material_override = Gfx.unshaded(CRYSTAL, 0.8).duplicate()
		aura.visible = false
		marker.add_child(aura)
		flag_nodes[f["id"]] = {"crystal": crystal, "gem": gem, "pennant": pennant, "ring": ring, "label": lab, "site": marker.position, "aura": aura}
		if f.get("golden", false):
			var gold := EmpireLayer.make_beacon(marker, "GoldenCoreBeacon", "2x GOLDEN CORE", EmpireLayer.GOLD_COLOR, 11.0)
			gold.hide()
			flag_nodes[f["id"]]["gold_beacon"] = gold
		flag_state_prev[f["id"]] = f["state"]
	# Extraction zone at the load ramp lights up and throbs while our crew carries a flag.
	extract_ring = Gfx.ring(4.0, 0.22, ACCENT, 0.8)
	extract_ring.name = "ExtractRing"
	extract_ring.material_override = Gfx.unshaded(ACCENT, 0.8).duplicate()
	extract_ring.position = HATCH + Vector3(0, 0.12, 0)
	extract_ring.visible = false
	add_child(extract_ring)
	for side in [-1.0, 1.0]:
		BlenderVisualUpgrades.place(extract_ring, "combat/capture_beacon_node.glb", Vector3(3.6 * side, -0.32, 0), 1.0, side * PI / 2.0)


func _ships() -> void:
	for i in g.sim.teams.size():
		var bay: Vector2 = g.sim.landing_bay(i)
		var pos := Vector3(bay[0], 0, bay[1])
		if i > 0:
			var approach := pos + (-pos).normalized() * 18.0
			g.sim.teams[i]["position"] = approach
			g.sim.teams[i]["bot_position"] = approach
		# Bay platforms and colored rings are now editable in the level scene.
		var ship := ShipModel.full(ACCENT if i == 0 else g.sim.field_color(i), g.sim.loadout if i == 0 else g.sim.teams[i]["loadout"], true)
		ship.scale = Vector3.ONE * ShipModel.VESSEL_SCALE
		ship.position = pos
		if i != 0:
			ship.rotation.y = atan2(pos.x, pos.z)
		add_child(ship)
		var bounds := [null]
		Actor._aabb(ship, Transform3D.IDENTITY, bounds)
		if bounds[0] != null: camera_obstacles.append(bounds[0])
		var l := Gfx.label(g.sim.teams[i]["name"] + (" · YOUR SHIP" if i == 0 else ""), g.sim.field_color(i), 70)
		l.position = pos + Vector3.UP * 15.0 * ShipModel.VESSEL_SCALE
		add_child(l)
		rival_ships[i] = {"node": ship, "label": l}
		blockers.append({"c": Vector2(pos.x, pos.z), "r": 9.5 * Sim.SHIP_K * ShipModel.VESSEL_SCALE})


func _crew() -> void:
	for r in 4:
		var s = Sim.SPECIALISTS[r]
		var a := Actor.new()
		a.setup(s["model"], r, Sim.role_color(r), s["name"], Sim.role_color(r))
		a.position = HATCH + Vector3(-4.5 + r * 3.0, 0, -3.0)
		a.heading = 0.0
		add_child(a)
		_apply_team_suit(a, 0)
		actors.append(a)
		if r != 3: a.install_weapon(Sim.FIELD_WEAPONS[r]["model"])


func _apply_team_suit(a: Actor, team: int) -> void:
	var team_color: Color = g.sim.field_color(team)
	var enemy := team != 0
	if a.has_method("apply_team_suit_color"):
		a.call("apply_team_suit_color", team_color, enemy)
		return
	for instance: MeshInstance3D in a.model.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var source := instance.get_active_material(surface)
			if source != null and not source is BaseMaterial3D:
				continue
			var tinted := source.duplicate() as BaseMaterial3D if source != null else StandardMaterial3D.new()
			tinted.albedo_color = team_color if enemy else tinted.albedo_color.lerp(team_color, 0.55)
			if instance.material_override != null:
				instance.material_override = tinted
				break
			instance.set_surface_override_material(surface, tinted)


func _make_bar(a: Actor, bar_name: String) -> Array:
	var bar := Node3D.new()
	bar.name = bar_name
	bar.position = Vector3(0, 2.4, 0)
	a.add_child(bar)
	var back := _bar_quad(Vector2(HP_BAR_W + 0.08, 0.16), Color("#1e293b"), 0.85)
	back.name = "Back"
	bar.add_child(back)
	var fill := _bar_quad(Vector2(HP_BAR_W, 0.1), Color("#4ade80"), 1.0)
	fill.name = "Fill"
	fill.material_override.render_priority = 1
	bar.add_child(fill)
	return [bar, fill]


func _spawn_field_actor(seat: int, col: Color, tag: String) -> Actor:
	var a := Actor.new()
	a.setup(Sim.SPECIALISTS[seat]["model"], seat, col, tag, col)
	a.hide()
	add_child(a)
	return a


func _rival_actors() -> void:
	for t in range(1, g.sim.teams.size()):
		var a := _spawn_field_actor(3, g.sim.field_color(t), g.sim.teams[t]["name"] + " · RAIDER")
		_apply_team_suit(a, t)
		var sight := Gfx.cyl(0.035, 1.0, Color("#ff654f"), Vector3.ZERO, 6)
		sight.name = "RivalAimSight%d" % t
		sight.material_override = Gfx.unshaded(Color("#ff654f"), 0.7)
		sight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sight.hide()
		add_child(sight)
		var parts := _make_bar(a, "RivalHealthBar%d" % t)
		var squad: Array = []
		for k in 3:
			var m := _spawn_field_actor(k, g.sim.field_color(t), g.sim.teams[t]["name"] + " · " + SQUAD_CALLSIGNS[k])
			_apply_team_suit(m, t)
			m.install_weapon(Sim.FIELD_WEAPONS[k]["model"])
			m.set_weapon_drawn(true)
			var mp := _make_bar(m, "SquadHealthBar%d_%d" % [t, k])
			squad.append({"actor": m, "role": k, "hp": 100.0, "max_hp": 100.0, "stun": 0.0, "last": Vector3.ZERO,
				"kb_vel": Vector3.ZERO, "bar": mp[0], "bar_fill": mp[1], "bar_frac": 1.0, "bar_flash": 0.0, "placed": false,
				"off": [Vector3(-4.0, 0, 3.0), Vector3(4.0, 0, 3.0), Vector3(0, 0, 6.5)][k]})
			squad_shot["%d:%d" % [t, k]] = 1.0 + 0.6 * k
		rivals[t] = {"actor": a, "hp": 100.0, "max_hp": 100.0, "last": Vector3.ZERO, "sight": sight,
			"bar": parts[0], "bar_fill": parts[1], "bar_frac": 1.0, "bar_flash": 0.0, "kb_vel": Vector3.ZERO, "squad": squad}


## Every live, visible enemy body: leaders (idx -1) and squad escorts.
func _foes() -> Array:
	var out: Array = []
	if g.arena_clash != null:
		var opponent := "planet_a" if g.home_alliance() == "planet_b" else "planet_b"
		for foe: Dictionary in _arena_teams[opponent]:
			if foe["actor"].visible:
				out.append(foe)
		return out
	for t in rivals:
		var rv: Dictionary = rivals[t]
		var ra: Actor = rv["actor"]
		if ra.visible and rv["hp"] > 0.0 and g.sim.teams[t]["stun"] <= 0.0:
			out.append({"team": t, "idx": -1, "actor": ra})
		for k in rv["squad"].size():
			var m: Dictionary = rv["squad"][k]
			if m["actor"].visible and m["stun"] <= 0.0 and m["hp"] > 0.0:
				out.append({"team": t, "idx": k, "actor": m["actor"]})
	return out


func _bar_quad(size: Vector2, col: Color, alpha: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := MeshInstance3D.new()
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col, alpha)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _rival_bars(dt: float) -> void:
	for t in rivals:
		for m in rivals[t]["squad"]:
			_update_bar(m, t, m["stun"] > 0.0 or m["hp"] <= 0.0, dt)
		_update_bar(rivals[t], t, rivals[t]["hp"] <= 0.0 or g.sim.teams[t]["stun"] > 0.0, dt)


func _update_bar(rv: Dictionary, t: int, ko: bool, dt: float) -> void:
	var bar: Node3D = rv["bar"]
	bar.visible = rv["actor"].visible and not ko
	if not bar.visible:
		rv["bar_frac"] = 1.0
		return
	var target := clampf(rv["hp"] / maxf(1.0, rv["max_hp"]), 0.0, 1.0)
	rv["bar_frac"] = lerpf(rv["bar_frac"], target, minf(1.0, dt * 14.0))
	rv["bar_flash"] = maxf(0.0, rv["bar_flash"] - dt)
	var frac: float = maxf(0.001, rv["bar_frac"])
	var fill: MeshInstance3D = rv["bar_fill"]
	var qm: QuadMesh = fill.mesh
	qm.size.x = HP_BAR_W * frac
	# Left-anchor the fill: billboard pivots at node origin, so shift the mesh center.
	qm.center_offset = Vector3(-HP_BAR_W * (1.0 - frac) * 0.5, 0, 0.002)
	var col := Color("#ef4444").lerp(Color("#4ade80"), frac).lerp(g.sim.field_color(t), 0.2)
	if rv["bar_flash"] > 0.0: col = Color.WHITE
	(fill.material_override as StandardMaterial3D).albedo_color = col


func _recoil_kick(role: int) -> void:
	if UI.reduced_motion or not GraphicsSettings.motion_effects: return
	# role 1 sidearm (light), role 2 scattergun (punchy), otherwise carbine (medium)
	var kick := 0.012 if role == 1 else (0.034 if role == 2 else 0.02)
	recoil_pitch = kick
	recoil_yaw = randf_range(-1.0, 1.0) * kick * 0.35
	recoil_t = RECOIL_RECOVER


func _apply_recoil(dt: float) -> void:
	if UI.reduced_motion or not GraphicsSettings.motion_effects:
		recoil_pitch = 0.0
		recoil_yaw = 0.0
		recoil_t = 0.0
		return
	if recoil_t <= 0.0: return
	var recovery := recoil_t / RECOIL_RECOVER
	var weight := recovery * recovery * (1.0 if g.first_person else 0.4)
	g.cam.rotation.x += recoil_pitch * weight
	g.cam.rotation.y += recoil_yaw * weight
	recoil_t = maxf(0.0, recoil_t - dt)



# ---------------------------------------------------------------------------
# Gameplay
# ---------------------------------------------------------------------------
func camera_position(target: Vector3, desired: Vector3) -> Vector3:
	var direction := (desired - target).normalized()
	var distance := desired.distance_to(target)
	for bounds: AABB in camera_obstacles:
		if bounds.has_point(target): continue
		var point: Variant = bounds.grow(0.25).intersects_ray(target, direction)
		if point != null: distance = minf(distance, maxf(0.45, target.distance_to(point) - 0.35))
	for obstacle in blockers:
		if not obstacle.get("cover", false): continue
		var hit := _cover_ray(target, direction, obstacle)
		if hit > 0.0: distance = minf(distance, maxf(0.45, hit - 0.35))
	return target + direction * distance


func collide(p: Vector3) -> Vector3:
	for b in blockers:
		var c: Vector2 = b["c"]
		if b.has("half"):
			var half: Vector2 = b["half"] + Vector2.ONE * 0.6
			var relative := Vector2(p.x, p.z) - c
			if absf(relative.x) < half.x and absf(relative.y) < half.y:
				if half.x - absf(relative.x) < half.y - absf(relative.y): p.x = c.x + half.x * (1.0 if relative.x >= 0 else -1.0)
				else: p.z = c.y + half.y * (1.0 if relative.y >= 0 else -1.0)
			continue
		var d := Vector2(p.x, p.z) - c
		var min_d: float = b["r"] + 0.6
		if d.length() < min_d:
			var n := d.normalized() if d.length() > 0.001 else Vector2(1, 0)
			var q := c + n * min_d
			p.x = q.x
			p.z = q.y
	var bounds := Rect2(-200.0, -200.0, 400.0, 400.0)
	if is_instance_valid(g.vessel) and g.sim.on_surface("planet_c"):
		var parked := _ship_pos()
		bounds = bounds.merge(Rect2(parked.x - 32.0, parked.z - 32.0, 64.0, 64.0))
	p.x = clampf(p.x, bounds.position.x, bounds.end.x)
	p.z = clampf(p.z, bounds.position.y, bounds.end.y)
	return p


func tick(dt: float) -> void:
	_apply_lunar_lighting()
	if _muzzle_light_t > 0.0:
		_muzzle_light_t = maxf(_muzzle_light_t - dt, 0.0)
		_muzzle_light.visible = _muzzle_light_t > 0.0
		_muzzle_light.light_energy = 4.0 * pow(_muzzle_light_t / MUZZLE_LIGHT_TIME, 2.0)
	if g.arena_clash != null:
		_tick_arena(dt)
		return
	var s: Sim = g.sim
	var r := s.selected
	var a: Actor = actors[r]
	if _recoil_role != r:
		recoil_t = 0.0
		_recoil_role = r
	for i in 4:
		if actors[i].name_tag:
			actors[i].name_tag.visible = i != r
	_hook_touch_actions()
	_cooldowns(dt)
	if empire_layer != null:
		empire_layer.tick_visuals(dt, a.position)
		_update_empire_defenders(dt)
	_tactics(dt)
	_grenades_tick(dt)
	beacon.visible = false
	var work := ""
	var speed := 0.0
	if down_t > 0.0:
		recoil_t = 0.0
		if empire_layer != null:
			empire_layer.tick_terminal(dt, a.global_position, false)
		g.hud.set_prompt("DOWNED", "Recovering at the ship · %.1f s" % down_t)
		g.follow_cam(a)
		a.animate(dt, 0.0, "down")
	else:
		_pubg_actions(r, a, dt)
		speed = g.drive(a, dt, 12.0, (0.82 if s.carried_flag(0, r) != null else 1.0) * (1.45 if s.boost > 0.0 and r == 0 else 1.0) * (0.55 if crouching else 1.0))
		g.follow_cam(a)
		_apply_pose(a, dt)
		if a.weapon_drawn:
			a.face(Vector3(-sin(g.yaw), 0, -cos(g.yaw)), dt, 20.0)
			a.weapon_pitch = g.pitch
		if empire_layer != null:
			empire_layer.tick_terminal(dt, a.global_position, not g.interior_active())
		work = _interact(r, a, dt)
		if g.world != self or g.piloting:
			return
		_apply_recoil(dt)
		a.animate(dt, speed, work, s.carried_flag(0, r) != null)
		_surface_dust(a)
	combat_hud.set_crosshair_visible(down_t <= 0.0 and r != 3 and a.weapon_drawn)
	var locked := false
	if down_t <= 0.0 and r != 3 and a.weapon_drawn:
		locked = not _aim_target(g.cam.global_position, g.cam_forward(), 3.5).is_empty()
	combat_hud.set_target_locked(locked)
	combat_hud.set_reload_progress(1.0 - reload_t / RELOAD_SECONDS if reload_t > 0.0 else 0.0)
	combat_hud.set_low_ammo(r != 3 and reload_t <= 0.0 and ammo <= 6)
	combat_hud.set_compass_markers(_compass_markers(r))
	if s.empire == null and combat_hud != null and combat_hud.has_method("set_team_scores"):
		var scores: Array = []
		for ti in s.teams.size():
			var fc := s.flag_counts(ti)
			scores.append({"name": g.sim.teams[ti]["name"], "color": g.sim.field_color(ti), "delivered": fc["delivered"], "onboard": fc["onboard"]})
		combat_hud.call("set_team_scores", scores)
	ko_streak_clock = maxf(0.0, ko_streak_clock - dt)
	if ko_streak_clock <= 0.0: ko_streak = 0
	for i in 4:
		if i != r:
			if down_times[i] <= 0.0: _bot(i, dt)
			else: actors[i].animate(dt, 0.0, "down")
	_rivals_tick(dt)
	if g.world != self:
		return
	_ship_status_tick(dt)
	_visuals(dt)
	_first_person_tick(dt, speed)
	for i in 4: actors[i].set_health(suit_hp[i] if down_times[i] <= 0.0 else 0.0, down_times[i] > 0.0)


func start_arena() -> void:
	var clash: ArenaClashRules = g.arena_clash
	_arena_player_id = "%s:%d" % [clash.player_squad, g.sim.selected]
	for id: String in clash.combatants:
		if arena_actors.has(id):
			continue
		var state := clash.combatant(id)
		var squad: String = state["squad_id"]
		var alliance: String = state["alliance"]
		var seat: int = state["seat_index"]
		var enemy := alliance == "planet_b"
		var col := Color.html(Sim.EMPIRE_COLORS[squad])
		var callsign := "%s-%s" % [squad, EmpireSim.SPECIALISTS[seat]["name"]]
		var a := _spawn_field_actor(seat, col, callsign)
		a.apply_team_suit_color(col, alliance != g.home_alliance())
		a.install_weapon(Sim.FIELD_WEAPONS[_arena_weapon(seat)]["model"])
		var squad_index: int = EmpireSim.ALLIANCE_SQUADS[alliance].find(squad)
		var x := (squad_index * 4 + seat % 2 - 6.5) * 4.0
		var z := (36.0 if seat < 2 else 32.0) * (-1.0 if enemy else 1.0)
		var spawn := collide(Vector3(x, 0, z))
		a.position = spawn
		var bonuses := clash.get_bonuses(squad)
		var index := arena_actors.size()
		var entry := {
			"id": id, "actor": a, "state": state, "spawn": spawn, "callsign": callsign,
			"color": col, "team": int(enemy), "idx": index, "target": "", "waypoint": spawn,
			"search": ARENA_SEARCH_INTERVAL * float(index) / 32.0, "fire": rng.randf_range(0.4, 1.4),
			"max_health": ArenaClashRules.BASE_HEALTH + bonuses["max_health"],
			"max_shield": ArenaClashRules.BASE_SHIELD + bonuses["shield"],
		}
		arena_actors[id] = entry
		_arena_teams[alliance].append(entry)
		_sync_arena_actor(entry)
	if first_person_rig != null or not arena_actors.has(_arena_player_id):
		return
	var player := actor(g.sim.selected)
	var entry: Dictionary = arena_actors[_arena_player_id]
	combat_hud.vitals_limits = Vector2(entry["max_health"], entry["max_shield"])
	combat_hud.primary_weapon_only = true
	player.name_tag.hide()
	first_person_rig = player.build_fpv_rig()
	add_child(first_person_rig)
	first_person_rig.hide()
	combat_hud.announce(Universe.C_LABEL, "First to %d eliminations" % clash.kill_target)


func set_arena_aboard(aboard: bool) -> void:
	_arena_aboard = aboard
	for entry: Dictionary in arena_actors.values():
		_sync_arena_actor(entry)
	if aboard and first_person_rig != null:
		first_person_rig.hide()


func _arena_weapon(seat: int) -> int:
	return seat if seat < Sim.FIELD_WEAPONS.size() else 0


func _sync_arena_actor(entry: Dictionary) -> void:
	var a: Actor = entry["actor"]
	var state: Dictionary = entry["state"]
	var alive: bool = state["alive"] and g.arena_clash.is_in_arena(state) and not (_arena_aboard and state["squad_id"] == g.arena_clash.player_squad)
	if alive != a.visible:
		a.visible = alive
		a.set_animation_detail(alive)
		if alive:
			a.position = entry["spawn"]
			a.move_vel = Vector3.ZERO
			a.vel = Vector3.ZERO
			a.vy = 0.0
			a.dash_t = 0.0
			a.dash_cd = 0.0
			a.face(Vector3.FORWARD if entry["team"] == 0 else Vector3.BACK, 1.0)
			a.set_weapon_drawn(true)
			if entry["id"] == _arena_player_id:
				ammo = 24
				reload_t = 0.0
				a.weapon_reload = 0.0
	if alive or a.displayed_hp > 0:
		a.set_health(100.0 * state["health"] / entry["max_health"], not alive)
	if not alive:
		a.set_animation_detail(false)


func _tick_arena(dt: float) -> void:
	start_arena()
	if not arena_actors.has(_arena_player_id):
		return
	for entry: Dictionary in arena_actors.values():
		_sync_arena_actor(entry)
	var player: Actor = actor(g.sim.selected)
	var player_state: Dictionary = arena_actors[_arena_player_id]["state"]
	var speed := 0.0
	if player_state["alive"]:
		if g.pressed(KEY_B):
			player.set_weapon_drawn(not player.weapon_drawn)
		speed = g.drive(player, dt, 12.0)
		if player.weapon_drawn:
			player.face(Vector3(-sin(g.yaw), 0, -cos(g.yaw)), dt, 20.0)
			player.weapon_pitch = g.pitch
		g.follow_cam(player)
		if reload_t > 0.0:
			reload_t = maxf(0.0, reload_t - dt)
			if reload_t <= 0.0:
				ammo = 24
				player.weapon_reload = 0.0
		fire_cd -= dt
		_tick_field_weapon(_arena_weapon(player.role), player)
		_apply_recoil(dt)
		player.animate(dt, speed)
		if g.cockpit_prompt(player.position):
			if g.piloting:
				return
		else:
			g.hud.set_prompt("")
	else:
		g.hud.set_prompt("RESPAWNING", "Next squad wave in %.1f s" % player_state["respawn_left"])
	for entry: Dictionary in arena_actors.values():
		if entry["id"] != _arena_player_id and entry["actor"].visible:
			_tick_arena_bot(entry, player.position, dt)
	first_person_rig.visible = player_state["alive"] and g.first_person and player.weapon_blend > 0.01
	if first_person_rig.visible:
		first_person_rig.global_transform = g.cam.global_transform
		first_person_rig.position += g.cam.basis * Vector3(-0.02, 0.05, -0.10)
	player.tick_fpv(dt, speed if first_person_rig.visible else 0.0)
	combat_hud.set_crosshair_visible(player_state["alive"] and player.weapon_drawn)
	combat_hud.set_reload_progress(1.0 - reload_t / RELOAD_SECONDS if reload_t > 0.0 else 0.0)


func _tick_arena_bot(entry: Dictionary, player_pos: Vector3, dt: float) -> void:
	var state: Dictionary = entry["state"]
	var a: Actor = entry["actor"]
	entry["search"] -= dt
	entry["fire"] -= dt
	var refresh: bool = entry["search"] <= 0.0
	if refresh:
		entry["search"] += ARENA_SEARCH_INTERVAL
		var opponent: String = "planet_b" if state["alliance"] == "planet_a" else "planet_a"
		var best := INF
		entry["target"] = ""
		for candidate: Dictionary in _arena_teams[opponent]:
			if not candidate["actor"].visible:
				continue
			var distance := a.position.distance_squared_to(candidate["actor"].position)
			if distance < best:
				best = distance
				entry["target"] = candidate["id"]
		a.set_animation_detail(a.position.distance_squared_to(player_pos) < ARENA_DETAIL_RANGE_SQ)
	var foe: Dictionary = arena_actors.get(entry["target"], {})
	if foe.is_empty() or not foe["actor"].visible:
		if a.animation_detail:
			a.animate(dt, 0.0)
		return
	var target: Actor = foe["actor"]
	var from := a.position + Vector3.UP * 1.5
	var aim := target.position + Vector3.UP * 1.3
	var distance := from.distance_squared_to(aim)
	var speed := 0.0
	if distance < 24.0 * 24.0 and _line_clear(from, aim):
		a.face(aim - from, dt)
		if entry["fire"] <= 0.0:
			entry["fire"] = rng.randf_range(0.8, 1.5)
			var hit := rng.randf() < 0.7
			CombatFX.tracer(self, from, aim + (Vector3.ZERO if hit else Vector3(1.6, 0.7, 0)), entry["color"], 0.05, 0.09)
			if a.position.distance_squared_to(player_pos) < ARENA_DETAIL_RANGE_SQ:
				g.sfx_3d("shot_carbine", a.global_position, -16.0)
			if hit:
				_arena_hit(entry["id"], foe["id"], 30.0)
	else:
		if refresh:
			entry["waypoint"] = navigation.next_point(entry["idx"], a.position, target.position)
		var previous := a.position
		a.walk_to(entry["waypoint"], dt, 6.5, 0.2)
		a.position = collide(a.position)
		speed = a.position.distance_to(previous) / maxf(dt, 0.001)
	if a.animation_detail:
		a.animate(dt, speed)


func _arena_hit(attacker_id: String, victim_id: String, amount: float) -> void:
	var clash: ArenaClashRules = g.arena_clash
	var victim := clash.combatant(victim_id)
	if victim.is_empty():
		return
	var before: float = victim["health"] + victim["shield"]
	var before_shield: float = victim["shield"]
	var result := clash.apply_damage(attacker_id, victim_id, amount)
	if before <= victim["health"] + victim["shield"]:
		return
	var attacker: Dictionary = arena_actors[attacker_id]
	var entry: Dictionary = arena_actors[victim_id]
	_sync_arena_actor(entry)
	if victim_id == _arena_player_id:
		combat_hud.trigger_damage_from(attacker["actor"].global_position, victim["shield"] < before_shield)
	if attacker_id == _arena_player_id:
		combat_hud.trigger_hitmarker(result["killed"])
	if result["killed"]:
		combat_hud.push_elimination(attacker["callsign"], attacker["color"], entry["callsign"], entry["color"])


# ---------------------------------------------------------------------------
# PUBG-style actions. Keys avoid the existing bindings (Q skill, F ultimate, C orders,
# G drop, H help, V camera): Crouch=Ctrl, Lean=[ / ], Melee=X, Grenade=J, Med kit=K.
# Each also honours an InputMap action of the same name and trigger_action() for HUD buttons.
# ---------------------------------------------------------------------------
const ACTION_KEYS := {"crouch": KEY_CTRL, "lean_left": KEY_BRACKETLEFT, "lean_right": KEY_BRACKETRIGHT,
	"melee": KEY_X, "grenade": KEY_J, "medkit": KEY_K}
const ACTION_ALIASES := {"throwable": "grenade", "frag": "grenade", "med": "medkit", "heal": "medkit", "shield_kit": "medkit",
	"quick_med": "medkit", "lean_l": "lean_left", "lean_r": "lean_right", "punch": "melee", "stance": "crouch", "prone": "crouch"}


## Entry point for on-screen buttons (mobile_controls / HUD). Unknown names are ignored.
func trigger_action(action_name: String) -> void:
	var n: String = ACTION_ALIASES.get(action_name, action_name)
	if ACTION_KEYS.has(n):
		_queued_actions[n] = true


func _hook_touch_actions() -> void:
	if _touch_hooked or g == null or g.hud == null:
		return
	var mc = g.hud.get("mobile_controls")
	if mc != null and mc.has_signal("action_pressed"):
		mc.action_pressed.connect(trigger_action)
		_touch_hooked = true


func _act(n: String) -> bool:
	if _queued_actions.has(n):
		_queued_actions.erase(n)
		return true
	if InputMap.has_action(n) and Input.is_action_just_pressed(n):
		return true
	var down: bool = Input.is_key_pressed(ACTION_KEYS[n])
	var was: bool = _action_prev.get(n, false)
	_action_prev[n] = down
	return down and not was


func _pubg_actions(r: int, a: Actor, dt: float) -> void:
	var s: Sim = g.sim
	melee_cd = maxf(0.0, melee_cd - dt)
	grenade_cd = maxf(0.0, grenade_cd - dt)
	medkit_cd = maxf(0.0, medkit_cd - dt)
	# Slow resupply so kits are never permanently gone.
	_resupply_t += dt
	if _resupply_t >= 30.0:
		_resupply_t = 0.0
		if grenades < 3: grenades += 1
		elif medkits < 3: medkits += 1
	if g.held(KEY_SHIFT):
		crouching = false          # sprint cancels crouch
	if _act("crouch"):
		crouching = not crouching
	var left_down: bool = Input.is_key_pressed(ACTION_KEYS["lean_left"]) or (InputMap.has_action("lean_left") and Input.is_action_pressed("lean_left"))
	var right_down: bool = Input.is_key_pressed(ACTION_KEYS["lean_right"]) or (InputMap.has_action("lean_right") and Input.is_action_pressed("lean_right"))
	if _queued_actions.has("lean_left"):   # HUD tap toggles
		_queued_actions.erase("lean_left")
		lean_target = 0 if lean_target == -1 else -1
	if _queued_actions.has("lean_right"):
		_queued_actions.erase("lean_right")
		lean_target = 0 if lean_target == 1 else 1
	var want := lean_target
	if left_down and not right_down: want = -1
	elif right_down and not left_down: want = 1
	elif left_down and right_down: want = 0
	if g.held(KEY_SHIFT): want = 0; lean_target = 0
	lean = move_toward(lean, float(want), dt * 7.0)
	if _act("melee"): _melee(a)
	if _act("grenade"): _throw_grenade(a)
	if _act("medkit"): _use_medkit(r, a)


func _apply_pose(a: Actor, dt: float) -> void:
	var crouch_t := 1.0 if crouching else 0.0
	_crouch_amt = move_toward(_crouch_amt, crouch_t, dt * 6.0)
	var holder: Node3D = a.get_node_or_null("Holder")
	if holder != null:
		holder.scale.y = lerpf(1.0, 0.72, _crouch_amt)
	g.cam.position.y = maxf(0.35, g.cam.position.y - 0.7 * _crouch_amt)
	if absf(lean) > 0.01:
		var right := Vector3(cos(g.yaw), 0, -sin(g.yaw))
		g.cam.position += right * lean * 0.75
		g.cam.rotation.z = -lean * 0.2
		a.weapon_pitch = g.pitch


func _melee(a: Actor) -> void:
	if melee_cd > 0.0: return
	melee_cd = 0.8
	var fwd := Vector3(-sin(g.yaw), 0, -cos(g.yaw))
	a.face(fwd, 0.1, 40.0)
	a.flash("hit", 0.2)
	var hit_any := false
	for foe in _foes():
		var to: Vector3 = foe["actor"].position - a.position
		to.y = 0.0
		if to.length() < MELEE_RANGE and to.normalized().dot(fwd) > 0.2:
			_damage_foe(foe["team"], foe["idx"], 32.0, foe["actor"].position + Vector3.UP * 1.3, a.position, 2)
			g.sim.metrics["hits"] += 1
			hit_any = true
	var swing := a.position + fwd * 1.4 + Vector3.UP * 1.2
	CombatFX.impact(self, swing, Color("#ffd866") if hit_any else Color("#cbd5e1"), 0.5, 8)
	g.sfx("hitmarker" if hit_any else "reload_click", -6)


func _throw_grenade(a: Actor) -> void:
	if grenade_cd > 0.0 or grenades <= 0:
		if grenades <= 0: g.hud.toast("No grenades left", 1.2)
		return
	grenades -= 1
	grenade_cd = 1.0
	var dir: Vector3 = g.cam_forward()
	var origin := a.position + Vector3.UP * 1.5 + Vector3(-sin(g.yaw), 0, -cos(g.yaw)) * 0.6
	var mesh := Gfx.sphere(0.16, Color("#9fb36b"), Vector3.ZERO, 0.6, 10)
	mesh.position = origin
	add_child(mesh)
	live_grenades.append({"node": mesh, "pos": origin, "vel": dir * 15.0 + Vector3.UP * 4.5, "fuse": GRENADE_FUSE})
	g.sfx("reload_click", -4, 0.2)
	g.hud.toast("GRENADE OUT · %d left" % grenades, 1.0)


func _grenades_tick(dt: float) -> void:
	for gr in live_grenades.duplicate():
		var prev: Vector3 = gr["pos"]
		var vel: Vector3 = gr["vel"]
		vel.y -= 16.0 * dt
		var next := prev + vel * dt
		var flat := collide(Vector3(next.x, 0.0, next.z))
		if flat.distance_to(Vector3(next.x, 0.0, next.z)) > 0.001:
			vel.x *= -0.3; vel.z *= -0.3          # rock / cover bounce
			next.x = prev.x; next.z = prev.z
		else:
			next.x = flat.x; next.z = flat.z
		if next.y < 0.16:
			next.y = 0.16
			vel.y = -vel.y * 0.35
			vel.x *= 0.6; vel.z *= 0.6
		gr["pos"] = next
		gr["vel"] = vel
		gr["fuse"] -= dt
		(gr["node"] as Node3D).position = next
		CombatFX.tracer(self, prev, next, Color("#fde68a"), 0.035, 0.4)   # visible arc trail
		if gr["fuse"] <= 0.0:
			_explode_grenade(next)
			(gr["node"] as Node3D).queue_free()
			live_grenades.erase(gr)


func _explode_grenade(at: Vector3) -> void:
	var s: Sim = g.sim
	CombatFX.ring_pulse(self, Vector3(at.x, 0.2, at.z), Color("#fb923c"), GRENADE_RADIUS, 0.5)
	CombatFX.impact(self, at + Vector3.UP * 0.4, Color("#fb923c"), 2.2, 40)
	g.sfx_3d("shot_scatter", at, 0)
	var me: Actor = actors[s.selected]
	for foe in _foes():
		var d: float = foe["actor"].position.distance_to(Vector3(at.x, foe["actor"].position.y, at.z))
		if d < GRENADE_RADIUS:
			_damage_foe(foe["team"], foe["idx"], 75.0 * (1.0 - 0.7 * d / GRENADE_RADIUS), foe["actor"].position + Vector3.UP * 1.2, at, 2)
			s.metrics["hits"] += 1
	if down_t <= 0.0 and me.position.distance_to(Vector3(at.x, me.position.y, at.z)) < GRENADE_RADIUS * 0.5 and s.shield <= 0.0:
		last_hit[s.selected] = 6.0
		field_hp -= 14.0
		g.hud.hurt(0.4)
		if field_hp <= 0.0: _downed()


func _use_medkit(r: int, a: Actor) -> void:
	if medkit_cd > 0.0: return
	if medkits <= 0:
		g.hud.toast("No med kits left", 1.2)
		return
	medkits -= 1
	medkit_cd = 2.5
	field_hp = minf(100.0, field_hp + 40.0)
	g.sim.shield = maxf(g.sim.shield, 4.0)
	CombatFX.ring_pulse(self, a.position + Vector3(0, 0.2, 0), Color("#4ade80"), 3.5, 0.5)
	g.sfx("shield_recharge", -6)
	g.hud.toast("MED KIT +40 HP · SHIELD 4 s · %d left" % medkits, 1.5)


func _compass_markers(r: int) -> Array:
	var s: Sim = g.sim
	var markers: Array = []
	var crew_carrying := false
	for f in s.flags:
		var st: String = f["state"]
		if st != "site" and st != "ground" and st != "carried":
			continue
		var pos: Vector3 = f["position"]
		var col := CRYSTAL
		if st == "carried":
			if f["owner"] != 0:
				continue
			crew_carrying = true
			pos = actors[f["carrier"]].position
			col = g.sim.field_color(0)
		elif st == "ground":
			col = Color("#ffd29a")
		markers.append({"pos": pos, "color": col, "label": "FLAG %02d" % (int(f["id"]) + 1), "priority": int(f["id"]) == s.priority_flag})
	if crew_carrying:
		for m in markers:
			if m["color"] == g.sim.field_color(0):
				m["priority"] = false
	markers.append({"pos": _cargo_hatch(), "color": ACCENT, "label": "RAMP", "priority": crew_carrying})
	return markers


func _surface_dust(a: Actor) -> void:
	if UI.reduced_motion:
		return
	if g.landing_impact > 0.0:
		var strength := clampf(g.landing_impact / 8.0, 0.3, 1.0)
		_dust_puff(a.position, roundi(22 * strength), lerpf(0.6, 1.0, strength))
	elif g.sprint_step:
		var right := Vector3(cos(a.heading), 0, -sin(a.heading))
		var foot := a.position + right * (0.26 if a.step_index % 2 == 0 else -0.26)
		_dust_puff(foot, 10, 0.65)


func _dust_puff(point: Vector3, count: int, size: float) -> void:
	if dust_mesh == null:
		var edge := Gradient.new()
		edge.set_color(0, Color.WHITE)
		edge.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = edge
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		dust_mesh = QuadMesh.new()
		dust_mesh.material = material
		dust_fade = Gradient.new()
		dust_fade.set_color(0, Color("#9c9183", 0.5))
		dust_fade.add_point(0.35, Color("#a69c8e", 0.3))
		dust_fade.set_color(1, Color("#a69c8e", 0.0))
	var dust := CPUParticles3D.new()
	dust.name = "RegolithPuff"
	dust.emitting = false
	dust.position = point + Vector3.UP * 0.17
	dust.mesh = dust_mesh
	dust.color_ramp = dust_fade
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.lifetime = 0.72
	dust.spread = 78.0
	dust.gravity = Vector3.DOWN * 1.62
	dust.initial_velocity_min = 0.55 * size
	dust.initial_velocity_max = 1.75 * size
	dust.scale_amount_min = 0.22 * size
	dust.scale_amount_max = 0.64 * size
	GraphicsSettings.set_particle_count(dust, count)
	dust.finished.connect(dust.queue_free)
	add_child(dust)
	dust.emitting = true


func _cover_ray(origin: Vector3, direction: Vector3, obstacle: Dictionary) -> float:
	if obstacle.has("center3"):
		var bounds := AABB(obstacle["center3"] - obstacle["size3"] * 0.5, obstacle["size3"])
		var point: Variant = bounds.intersects_ray(origin, direction)
		return origin.distance_to(point) if point != null else -1.0
	return Flight._ray_sphere(origin, direction, Vector3(obstacle["c"].x, 1.25, obstacle["c"].y), float(obstacle["r"]))


func _line_clear(start: Vector3, end: Vector3) -> bool:
	var delta := end - start
	var distance := delta.length()
	if distance < 0.01: return true
	for b in blockers:
		if not b.get("cover", false): continue
		var hit := _cover_ray(start, delta / distance, b)
		if hit > 0.05 and hit < distance - 0.4: return false
	return true

func _crew_walk(a: Actor, target: Vector3, dt: float, speed: float, stop := 1.5) -> float:
	var waypoint := navigation.next_point(a.get_instance_id(), a.position, target)
	if g.flat_dist(a.position, target) > stop: a.walk_to(waypoint, dt, speed, 0.2)
	a.position = collide(a.position)
	return g.flat_dist(a.position, target)


func _tactics(dt: float) -> void:
	var s: Sim = g.sim
	if g.pressed(KEY_B) and s.selected != 3:
		actors[s.selected].set_weapon_drawn(not actors[s.selected].weapon_drawn)
		g.sfx("reload_click", -10)
	hit_flash = maxf(0.0, hit_flash - dt)
	if g.pressed(KEY_C):
		s.cycle_order()
		g.hud.toast("CREW ORDER: " + s.crew_order.to_upper() + " · C changes order", 2.5)
		g.sfx("capture_tick", -12)
	if g.pressed(KEY_Z):
		var target = null
		var best := -INF
		for f in s.flags:
			if f["planet"] != "B" or not f["state"] in ["site", "ground"]: continue
			var to: Vector3 = f["position"] + Vector3(0, 2, 0) - g.cam.global_position
			var alignment: float = g.cam_forward().dot(to.normalized())
			if alignment > best:
				best = alignment
				target = f
		if target != null and s.set_priority(target["id"]):
			g.hud.toast("PRIORITY: FLAG %02d · Fernando will recover it. C regroups your crew." % (target["id"] + 1), 3.0)
			g.sfx("capture_tick", -8)
	for i in 4:
		var was_down: bool = down_times[i] > 0.0
		down_times[i] = maxf(0.0, down_times[i] - dt)
		if was_down and down_times[i] <= 0.0:
			actors[i].position = _cargo_hatch() + Vector3(-3.0 + i * 2.0, 0, -3.5)
			preload("res://scripts/combat_fx.gd").impact(self, actors[i].position + Vector3.UP, Color("#75dec4"), 0.7, 12)
		last_hit[i] = maxf(0.0, last_hit[i] - dt)
		var reload_before: float = reload_times[i]
		if reload_before > 0.0:
			reload_times[i] = maxf(0.0, reload_before - dt)
			if i == s.selected and down_times[i] <= 0.0 and reload_before > RELOAD_RATCHET_REMAINING \
					and reload_times[i] <= RELOAD_RATCHET_REMAINING:
				g.sfx("reload_ratchet", -5)
			if reload_times[i] <= 0.0: magazines[i] = 24
		if last_hit[i] <= 0.0 and down_times[i] <= 0.0:
			var medic_near: bool = i != 1 and down_times[1] <= 0.0 and actors[i].position.distance_to(actors[1].position) < 9.0
			suit_hp[i] = minf(100.0, suit_hp[i] + dt * (8.0 if medic_near else 4.0))
	if s.priority_flag >= 0 and not s.flags[s.priority_flag]["state"] in ["site", "ground"]:
		s.priority_flag = -1


func _cooldowns(dt: float) -> void:
	var s: Sim = g.sim
	s.scan_boost = maxf(0.0, s.scan_boost - dt)
	s.boost = maxf(0.0, s.boost - dt)
	s.overdrive = maxf(0.0, s.overdrive - dt)
	s.shield = maxf(0.0, s.shield - dt)
	for i in 4:
		s.ability_cd[i] = maxf(0.0, s.ability_cd[i] - dt)
		s.ultimate[i] = minf(100.0, s.ultimate[i] + dt * 0.8)
	if g.pressed(KEY_Q) and s.use_skill(s.selected, "q"):
		g.sfx("shield_recharge", -6)
		g.sfx("ability_cast", -6)
		if s.selected == 1:
			CombatFX.ring_pulse(self, actors[1].position + Vector3(0, 0.2, 0), Color("#75dec4"), 12.0, 0.5)
			for i in 4:
				if actors[i].position.distance_to(actors[1].position) < 12.0:
					suit_hp[i] = minf(100.0, suit_hp[i] + 25.0)
					CombatFX.impact(self, actors[i].position + Vector3.UP * 1.2, Color("#75dec4"), 0.7, 10)
		elif s.selected == 0:
			CombatFX.ring_pulse(self, actors[0].position + Vector3(0, 0.2, 0), Color("#38bdf8"), 4.5, 0.4)
		elif s.selected == 2:
			CombatFX.ring_pulse(self, actors[2].position + Vector3(0, 0.2, 0), Color("#fb7185"), 5.5, 0.45)
		else:
			CombatFX.ring_pulse(self, actors[3].position + Vector3(0, 0.2, 0), CRYSTAL, 5.5, 0.45)
		g.hud.toast(Sim.SPECIALISTS[s.selected]["skill"].to_upper(), 1.5)
	if g.pressed(KEY_F) and s.use_skill(s.selected, "f"):
		g.sfx("shield_recharge", -3)
		g.sfx("ability_cast", -4)
		CombatFX.ring_pulse(self, actors[s.selected].position + Vector3(0, 0.2, 0), Sim.role_color(s.selected), 8.0, 0.5)
		if s.selected == 3:
			field_hp = 100.0


func _nearest_flag(p: Vector3, states: Array) -> Variant:
	var best = null
	var bd := INF
	for f in g.sim.flags:
		if f["planet"] == "B" and f["state"] in states:
			var d: float = g.flat_dist(p, f["position"])
			if d < bd:
				bd = d
				best = f
	return best


func _start_reload(a: Actor) -> void:
	reload_t = RELOAD_SECONDS
	a.weapon_reload = RELOAD_SECONDS
	g.sfx("reload_click", -4)


func _flag_name(flag: Dictionary) -> String:
	if flag.get("golden", false):
		return "Golden Science Core · 2 points"
	return "Science Flag %d" % (flag["id"] + 1)


func _interact(r: int, a: Actor, dt: float) -> String:
	var s: Sim = g.sim
	var carried = s.carried_flag(0, r)
	var hatch_d: float = g.flat_dist(a.position, _cargo_hatch())
	var c := s.flag_counts(0)
	fire_cd -= dt
	if r != 3:
		_tick_field_weapon(r, a)
	if g.pressed(KEY_G) and carried != null:
		s.drop_flag(0, r, a.position)
		g.hud.toast("Flag dropped. It stays here until someone recovers it.", 2.0)
		return ""
	if carried != null:
		if hatch_d <= 4.5:
			g.hud.set_prompt("E  LOAD SCIENCE FLAG %d" % (carried["id"] + 1), "%d/%d on board" % [c["onboard"], s.cargo_capacity])
			if g.pressed(KEY_E):
				if s.load_flag(0, r, hatch_d):
					g.sfx("capture_tick", -2)
					g.sfx("flag_fanfare", -6, 0.0)
					g.hud.toast("Flag %d on board · loading does not score — bring it home." % (carried["id"] + 1))
					combat_hud.announce("FLAG EXTRACTED", "Science Flag %d loaded up the ramp" % (carried["id"] + 1), Color("#5fe3ff"))
					_feed("Science Flag %d extracted up the ramp" % (carried["id"] + 1), Color("#5fe3ff"))
				else:
					g.hud.toast("Cargo racks are full.")
		else:
			beacon.visible = true
			beacon.position = _cargo_hatch() + Vector3(0, 20, 0)
			g.hud.set_prompt("RETURN TO YOUR SHIP", "Carrying Science Flag %d · %d m · G drops it" % [carried["id"] + 1, int(hatch_d)])
		return ""
	if empire_layer != null:
		var terminal := empire_layer.nearest_interactable(a.global_position)
		if not terminal.is_empty():
			g.hud.set_prompt(terminal["prompt"].replace("[E]", "E"),
				"Stay near the terminal · Engineer sabotages twice as fast", empire_layer.sabotage_fraction())
			if g.pressed(KEY_E):
				var result := empire_layer.interact(a.global_position, r == 1)
				if not result.get("ok", false):
					g.hud.toast(str(result.get("reason", "Unavailable")).replace("_", " ").capitalize())
			return ""
	var ground = _nearest_flag(a.position, ["ground"])
	if ground != null and g.flat_dist(a.position, ground["position"]) <= 3.8:
		g.hud.set_prompt("E  RECOVER SCIENCE FLAG %d" % (ground["id"] + 1), "Loose flag on the ground")
		if g.pressed(KEY_E) and s.recover_flag(ground["id"], 0, r, g.flat_dist(a.position, ground["position"])):
			g.sfx("capture_tick", -4)
			g.sfx("flag_fanfare", -6, 0.0)
			combat_hud.announce("SCIENCE FLAG CAPTURED", "Flag %d recovered" % (ground["id"] + 1), Color("#ffd29a"))
			_feed("Science Flag %d picked up" % (ground["id"] + 1), Color("#ffd29a"))
		return ""
	if r == 3:
		var f = _nearest_flag(a.position, ["site"])
		if f != null:
			var d: float = g.flat_dist(a.position, f["position"])
			if d <= 3.8:
				if not s.empire_flag_available(f):
					g.hud.set_prompt("VAULT SHIELDED", "Disable the enemy Shield Generator to capture vault flags.")
					return ""
				var to: Vector3 = f["position"] - a.position
				var fwd: Vector3 = g.cam_forward()
				var aligned := d < 2.0 or Vector2(fwd.x, fwd.z).normalized().dot(Vector2(to.x, to.z).normalized()) > 0.55
				var stage_names := ["SCAN", "STABILIZE", "EXTRACT"]
				var contested: bool = f["scanner"] != null and f["scanner"] != 0
				g.hud.set_prompt("HOLD LMB  %s" % ("SCAN → STABILIZE → EXTRACT" if f["stage"] == 0 and f["progress"] == 0.0 else stage_names[mini(2, f["stage"])]),
					("CONTESTED by %s — hold to override" % g.sim.teams[f["scanner"]]["name"]) if contested else ("Face the flag" if not aligned else "%s%s" % [_flag_name(f), " · scanner boost" if s.scan_boost > 0.0 else ""]),
					s.scan_fraction(f))
				if g.lmb:
					s.scan_flag(f["id"], 0, 3, dt, d, aligned, s.scan_boost > 0.0)
					scan_sfx_cd -= dt
					if scan_sfx_cd <= 0.0:
						scan_sfx_cd = 0.45
						g.sfx("scan_hum", -12)
					var key: int = f["stage"]
					if last_stage.get(f["id"], 0) != key or f["state"] == "carried":
						g.sfx("capture_tick", -6)
						last_stage[f["id"]] = key
						if f["state"] == "carried":
							g.sfx("flag_fanfare", -6, 0.0)
							g.hud.toast("Science Flag %d extracted — carry it to the ship" % (f["id"] + 1))
							combat_hud.announce("SCIENCE FLAG CAPTURED", "Carry Flag %d to the ship" % (f["id"] + 1), Color("#ffd29a"))
							_feed("Science Flag %d picked up" % (f["id"] + 1), Color("#ffd29a"))
					a.face(to, dt)
					return "scan"
				return ""
	if g.cockpit_prompt(a.position):
		return ""
	if r == 3:
		var f = _nearest_flag(a.position, ["site"])
		if f != null:
			beacon.visible = true
			beacon.position = f["position"] + Vector3(0, 20, 0)
			g.hud.set_prompt(_flag_name(f).to_upper(), "%d m · hold LMB at the pedestal" % int(g.flat_dist(a.position, f["position"])))
		else:
			g.hud.set_prompt("NO FLAGS LEFT AT SITES", "Press E at the cockpit to board")
	else:
		var full: bool = c["onboard"] >= s.cargo_capacity
		g.hud.set_prompt("COVER THE RAIDER" if not full else "CARGO FULL — DEPART", "B equip" if not a.weapon_drawn else "LMB fire · R reload" if not full else "Press E at the cockpit to board")
	return ""


func _tick_field_weapon(weapon: int, a: Actor) -> void:
	if g.pressed(KEY_R) and a.weapon_ready() and ammo < 24 and reload_t <= 0.0:
		_start_reload(a)
	if g.lmb and a.weapon_ready() and fire_cd <= 0.0 and reload_t <= 0.0 and ammo > 0:
		fire_cd = Sim.FIELD_WEAPONS[weapon]["interval"] / (1.5 if g.sim.overdrive > 0.0 else 1.0)
		a.recoil_weapon()
		ammo -= 1
		g.sim.metrics["shots"] += 1
		var shot_sfx := "shot_scatter" if weapon == 1 else ("shot_sidearm" if weapon == 2 else "shot_carbine")
		g.sfx(shot_sfx, -11)
		_shoot()
		if ammo == 0:
			_start_reload(a)


## Best live rival within max_angle_deg of the aim ray and unobstructed by cover.
## Returns {} or {"team", "dir", "angle"}.
func _aim_target(origin: Vector3, dir: Vector3, max_angle_deg: float) -> Dictionary:
	var best := {}
	var best_ang := max_angle_deg
	for foe in _foes():
		var t: int = foe["team"]
		var ra: Actor = foe["actor"]
		var to: Vector3 = ra.position + Vector3(0, 1.3, 0) - origin
		var dist := to.length()
		if dist < 0.5 or dist > 120.0:
			continue
		var ang := rad_to_deg(dir.angle_to(to))
		if ang >= best_ang:
			continue
		var d := to / dist
		var blocked := false
		for b in blockers:
			if b.get("cover", false):
				var ch := _cover_ray(origin, d, b)
				if ch > 0.0 and ch < dist:
					blocked = true
					break
		if blocked:
			continue
		best_ang = ang
		best = {"team": t, "idx": foe["idx"], "dir": d, "angle": ang}
	return best


func _shoot() -> void:
	var actor_node: Actor = actor(g.sim.selected)
	var from: Vector3 = actor_node.weapon_muzzle.global_position if actor_node.weapon_muzzle else actor_node.global_position + Vector3.UP * 1.5
	var dir: Vector3 = (g.cam.global_position + g.cam_forward() * 120.0 - from).normalized()
	if g.arena_clash != null:
		from = to_local(from)
		dir = (global_basis.inverse() * dir).normalized()
	if g.hud != null and g.hud.has_method("touch_ui_visible") and g.hud.touch_ui_visible():
		var assist := _aim_target(from, dir, 6.5)
		if not assist.is_empty():
			dir = dir.slerp(assist["dir"], 0.6).normalized()
	var hit_t := 120.0
	for b in blockers:
		if not b.get("cover", false): continue
		var cover_hit := _cover_ray(from, dir, b)
		if cover_hit > 0.0: hit_t = minf(hit_t, cover_hit)
	var hit_team := -1
	var hit_idx := -1
	var hit_id := ""
	var hit_actor: Actor
	for foe in _foes():
		var ra: Actor = foe["actor"]
		var tt := Flight._ray_sphere(from, dir, ra.position + Vector3(0, 1.3, 0), 1.4)
		if tt > 0.0 and tt < hit_t:
			hit_t = tt
			hit_team = foe["team"]
			hit_idx = foe["idx"]
			hit_id = foe.get("id", "")
			hit_actor = ra
	var core_hit := {}
	if empire_layer != null:
		core_hit = empire_layer.ray_core(from, dir, hit_t)
		if not core_hit.is_empty():
			hit_t = core_hit["distance"]
			hit_team = -1
	var muzzle: Vector3 = from
	combat_hud.trigger_bloom(9.0)
	_recoil_kick(g.sim.selected)
	var role: int = g.sim.selected if g.arena_clash == null else _arena_weapon(g.sim.selected)
	actor_node.trigger_weapon_kick(0.7 if role == 1 else (1.5 if role == 2 else 1.0))
	var end_pt: Vector3 = from + dir * hit_t
	var muzzle_col := Color("#38bdf8") if role == 1 else (Color("#f472b6") if role == 2 else Color(0.5, 0.8, 1.0))
	if g.first_person:
		actor_node.set_fpv_flash_color(muzzle_col.lerp(Color("#ffc482"), 0.42))
	else:
		_muzzle_light.global_position = to_global(muzzle + dir * 0.12) if g.arena_clash != null else muzzle + dir * 0.12
		_muzzle_light.light_color = muzzle_col.lerp(Color("#ffc482"), 0.42)
		_muzzle_light.light_energy = 4.0
		_muzzle_light_t = MUZZLE_LIGHT_TIME
		_muzzle_light.show()
	preload("res://scripts/combat_fx.gd").impact(self, muzzle, muzzle_col, 0.35, 6)
	if role == 1:
		# Sidearm: crisp cyan bolt plus the arc crackle.
		_arc_beam(muzzle, end_pt, Color("#38bdf8"))
		CombatFX.tracer(self, muzzle, end_pt, Color("#67e8f9"), 0.05, 0.08)
	elif role == 2:
		# Scattergun: fan of bright orange pellet streaks.
		var side := dir.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		var up := side.cross(dir).normalized()
		var spread := hit_t * 0.035
		for p in [Vector2(0, 0), Vector2(1, 0.3), Vector2(-1, 0.2), Vector2(0.4, -0.8), Vector2(-0.5, 0.9)]:
			CombatFX.tracer(self, muzzle, end_pt + side * p.x * spread + up * p.y * spread, Color("#fb923c"), 0.04, 0.08)
	else:
		# Carbine: warm golden-amber streak.
		CombatFX.tracer(self, muzzle, end_pt, Color("#fbbf24"), 0.055, 0.09)
	if not core_hit.is_empty():
		var impact := empire_layer.hit_core(core_hit["slot_id"], role)
		if impact.get("ok", false):
			g.sim.metrics["hits"] += 1
		elif impact.get("reason") == "shielded":
			g.hud.toast("Vault shield absorbing fire")
	if hit_team > 0:
		var impact_point := end_pt
		var headshot: bool = impact_point.y - hit_actor.position.y > 1.9
		if not hit_id.is_empty():
			g.sim.metrics["hits"] += 1
			_arena_hit(_arena_player_id, hit_id, Sim.field_damage(role, hit_t, headshot))
			preload("res://scripts/combat_fx.gd").impact(self, end_pt, arena_actors[hit_id]["color"], 0.65, 8)
			return
		_damage_foe(hit_team, hit_idx, Sim.field_damage(role, hit_t, headshot) * (1.25 if g.sim.overdrive > 0.0 else 1.0), impact_point, actor_node.position, role)
		g.sim.metrics["hits"] += 1
		preload("res://scripts/combat_fx.gd").impact(self, end_pt, g.sim.field_color(hit_team), 0.65, 12)
	elif hit_t < 119.5:
		preload("res://scripts/combat_fx.gd").impact(self, end_pt, muzzle_col, 0.4, 8)


func _register_ko_streak() -> void:
	ko_streak = ko_streak + 1 if ko_streak_clock > 0.0 else 1
	ko_streak_clock = 12.0
	if ko_streak < 2:
		g.sfx("ko_chime", -6, 0.0)
		return
	g.sfx("streak_chord_%d" % clampi(ko_streak, 2, 4), -5, 0.0)
	var title := "DOUBLE KO!"
	var col := Color("#ffd866")
	if ko_streak == 3:
		title = "TRIPLE KO!"
		col = Color("#ff9d2e")
	elif ko_streak >= 4:
		title = "UNSTOPPABLE!"
		col = Color("#ff4a3a")
	combat_hud.announce(title, "%d knockouts in a row" % ko_streak, col)
	_feed(title, col)


func _damage_rival(t: int, dmg: float, hit_pos: Variant = null, from_pos: Variant = null, role := 0) -> void:
	var s: Sim = g.sim
	var rv: Dictionary = rivals[t]
	if s.teams[t]["stun"] > 0.0 or dmg <= 0.0: return
	rv["hp"] -= dmg
	rv["bar_flash"] = 0.10
	var lethal: bool = rv["hp"] <= 0.0
	# Knockback: horizontal shove away from the shooter (Scattergun hits hardest, KOs punch extra).
	var shooter: Vector3 = from_pos if from_pos is Vector3 else actors[s.selected].position
	var away: Vector3 = rv["actor"].position - shooter
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3(0, 0, 1)
	var impulse := 7.5 if role == 2 else (2.6 if role == 1 else 3.8)
	if lethal: impulse = impulse * 1.5 + 2.0
	rv["kb_vel"] = (rv["kb_vel"] as Vector3) + away * impulse
	if (rv["kb_vel"] as Vector3).length() > KB_MAX: rv["kb_vel"] = (rv["kb_vel"] as Vector3).normalized() * KB_MAX
	if combat_hud != null and combat_hud.has_method("spawn_damage_number"):
		var pos: Vector3 = hit_pos if hit_pos is Vector3 else rv["actor"].position + Vector3.UP * 1.6
		combat_hud.call("spawn_damage_number", pos, dmg, lethal, g.sim.field_color(t))
	hit_flash = 0.16
	g.hud.confirm_hit()
	combat_hud.trigger_hitmarker(rv["hp"] <= 0.0)
	g.sfx("hitmarker", -6)
	rv["actor"].flash("hit", 0.4)
	if rv["hp"] <= 0.0:
		rv["hp"] = 100.0
		s.teams[t]["stun"] = 6.0
		combat_hud.announce("RIVAL KNOCKED OUT", "%s raider stunned · +40" % g.sim.teams[t]["name"], g.sim.field_color(t))
		_feed("%s raider knocked out · +40" % g.sim.teams[t]["name"], g.sim.field_color(t))
		preload("res://scripts/combat_fx.gd").impact(self, rv["actor"].position + Vector3.UP, g.sim.field_color(t), 1.3, 28)
		if s.drop_flag(t, 3, s.teams[t]["bot_position"]):
			g.hud.toast("%s raider stunned — dropped a Science Flag!" % g.sim.teams[t]["name"])
		else:
			g.hud.toast("%s raider stunned" % g.sim.teams[t]["name"], 1.5)
		s.score += 40
		s.metrics["stuns"] += 1


func _damage_foe(t: int, idx: int, dmg: float, hit_pos: Variant = null, from_pos: Variant = null, role := 0) -> void:
	if idx < 0:
		_damage_rival(t, dmg, hit_pos, from_pos, role)
	else:
		_damage_squad(t, idx, dmg, hit_pos, from_pos, role)


func _damage_squad(t: int, k: int, dmg: float, hit_pos: Variant = null, from_pos: Variant = null, role := 0) -> void:
	var s: Sim = g.sim
	var m: Dictionary = rivals[t]["squad"][k]
	if m["stun"] > 0.0 or dmg <= 0.0: return
	m["hp"] -= dmg
	m["bar_flash"] = 0.10
	var lethal: bool = m["hp"] <= 0.0
	var shooter: Vector3 = from_pos if from_pos is Vector3 else actors[s.selected].position
	var away: Vector3 = m["actor"].position - shooter
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3(0, 0, 1)
	var impulse := 7.5 if role == 2 else (2.6 if role == 1 else 3.8)
	if lethal: impulse = impulse * 1.5 + 2.0
	m["kb_vel"] = ((m["kb_vel"] as Vector3) + away * impulse).limit_length(KB_MAX)
	if combat_hud != null and combat_hud.has_method("spawn_damage_number"):
		combat_hud.call("spawn_damage_number", hit_pos if hit_pos is Vector3 else m["actor"].position + Vector3.UP * 1.6, dmg, lethal, g.sim.field_color(t))
	hit_flash = 0.16
	g.hud.confirm_hit()
	combat_hud.trigger_hitmarker(lethal)
	g.sfx("hitmarker", -6)
	m["actor"].flash("hit", 0.4)
	if lethal:
		m["hp"] = 0.0
		m["stun"] = 6.0
		var who: String = "%s %s" % [g.sim.teams[t]["name"], SQUAD_CALLSIGNS[k]]
		combat_hud.announce("RIVAL KNOCKED OUT", "%s down · +15" % who, g.sim.field_color(t))
		_feed("%s knocked out · +15" % who, g.sim.field_color(t))
		preload("res://scripts/combat_fx.gd").impact(self, m["actor"].position + Vector3.UP, g.sim.field_color(t), 1.1, 22)
		s.score += 15
		s.metrics["stuns"] += 1
		_register_ko_streak()


func _arc_beam(a: Vector3, b: Vector3, color: Color) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.1:
		return
	var right := delta.normalized().cross(Vector3.UP)
	if right.length() < 0.01: right = Vector3.RIGHT
	else: right = right.normalized()
	var up := right.cross(delta.normalized()).normalized()
	var prev := a
	for seg in [0.33, 0.67, 1.0]:
		var nxt: Vector3 = a + delta * float(seg)
		if seg < 1.0:
			var jitter := minf(0.45, length * 0.04)
			nxt += right * fx_rng.randf_range(-jitter, jitter) + up * fx_rng.randf_range(-jitter * 0.6, jitter * 0.6)
		_tracer(prev, nxt, color)
		prev = nxt


func _tracer(a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var c := Gfx.cyl(0.04, length, color, Vector3.ZERO, 5)
	c.material_override = Gfx.unshaded(color, 0.9)
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(c)
	c.transform = _beam_transform(a, b, 1.0)
	tracers.append({"node": c, "life": 0.06})


func _beam_transform(start: Vector3, end: Vector3, height: float) -> Transform3D:
	var up := (end - start).normalized()
	var right := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	return Transform3D(Basis(right, up * height, right.cross(up)), (start + end) * 0.5)


func _bot(i: int, dt: float) -> void:
	var s: Sim = g.sim
	var a: Actor = actors[i]
	var work := ""
	var c := s.flag_counts(0)
	if i != 3: a.set_weapon_drawn(s.crew_order != "regroup" and down_times[i] <= 0.0)
	if s.crew_order == "regroup" and s.carried_flag(0, i) == null:
		_crew_walk(a, _cargo_hatch() + Vector3(-4.5 + i * 3.0, 0, -3.0), dt, 6.0, 1.0)
		a.animate(dt, a.vel.length(), "", false)
		a.vel = Vector3.ZERO
		return
	if i == 3:
		var carried = s.carried_flag(0, 3)
		if carried != null:
			if _crew_walk(a, _cargo_hatch(), dt, 5.5, 1.5) <= 4.5:
				s.load_flag(0, 3, 2.0)
		elif c["onboard"] + c["carried"] >= s.cargo_capacity:
			_crew_walk(a, _cargo_hatch() + Vector3(3, 0, -2), dt, 5.5, 0.5)
		else:
			var f = s.frontier_target(a.position)
			if f != null:
				var d: float = _crew_walk(a, f["position"], dt, 5.5, 1.6)
				if d <= 3.8:
					if f["state"] == "ground":
						s.recover_flag(f["id"], 0, 3, d)
					else:
						s.scan_flag(f["id"], 0, 3, dt * 0.8, d, true, s.scan_boost > 0.0)
						a.face(f["position"] - a.position, dt)
						work = "scan"
			else:
				_crew_walk(a, _cargo_hatch() + Vector3(3, 0, -2), dt, 5.5, 0.5)
	else:
		var sample = s.carried_flag(0, i)
		if sample != null:
			if _crew_walk(a, _cargo_hatch(), dt, 5.5, 1.5) <= 4.5: s.load_flag(0, i, 2.0)
			a.animate(dt, a.vel.length(), "", true)
			a.vel = Vector3.ZERO
			return
		if s.crew_order == "recover" and c["onboard"] + c["carried"] < s.cargo_capacity:
			var loose = _nearest_flag(a.position, ["ground"])
			if loose != null and (i == 0 or a.position.distance_to(loose["position"]) < 12.0):
				if _crew_walk(a, loose["position"], dt, 6.0, 1.6) < 2.5: s.recover_flag(loose["id"], 0, i, 2.0)
				a.animate(dt, a.vel.length(), "", false)
				a.vel = Vector3.ZERO
				return
		var lead: Actor = actors[3] if s.crew_order == "recover" and s.selected != 3 else actors[s.selected]
		var guard_pos: Vector3 = lead.position
		if s.crew_order == "escort" and s.selected != 3 and down_times[3] <= 0.0 and lead.position.distance_to(actors[3].position) < 18.0:
			var active_scan = _nearest_flag(actors[3].position, ["site"])
			if active_scan != null and active_scan["scanner"] == 0 and g.flat_dist(actors[3].position, active_scan["position"]) < 4.5:
				guard_pos = actors[3].position
		var slot: int = i if i < s.selected else i - 1
		var offsets := [Vector3(-4.5, 0, 0.5), Vector3(4.5, 0, 0.5), Vector3(-8.5, 0, 1.5)]
		var off: Vector3 = offsets[clampi(slot, 0, 2)].rotated(Vector3.UP, lead.heading)
		_crew_walk(a, guard_pos + off, dt, 6.0, 1.0)
		if a.vel.length() < 0.1:
			var watch_pos: Vector3 = guard_pos
			var best_rd := 26.0
			for foe in _foes():
				var ra: Actor = foe["actor"]
				if a.position.distance_to(ra.position) < best_rd:
					best_rd = a.position.distance_to(ra.position)
					watch_pos = ra.position
			a.face(watch_pos - a.position, dt, 3.0)
		bot_fire[i] -= dt
		if bot_fire[i] <= 0.0:
			bot_fire[i] = 1.3 if i == 2 else 2.2
			for foe in _foes():
				var t: int = foe["team"]
				var ra: Actor = foe["actor"]
				if a.position.distance_to(ra.position) < 24.0 and _line_clear(a.position + Vector3.UP * 1.6, ra.position + Vector3.UP * 1.3):
					var bot_end: Vector3 = ra.position + Vector3(0, 1.3, 0) + (Vector3.ZERO if rng.randf() < 0.55 else Vector3(rng.randf_range(-2, 2), 1.5, 0))
					var bot_from: Vector3 = a.position + Vector3(0, 1.6, 0)
					if i == 1:
						_arc_beam(bot_from, bot_end, Color("#38bdf8"))
						g.sfx_3d("shot_scatter", a.global_position, -16)
					elif i == 2:
						_tracer(bot_from, bot_end, Color("#f472b6"))
						g.sfx_3d("shot_sidearm", a.global_position, -16)
					else:
						_tracer(bot_from, bot_end, Color("#ffd29a"))
						g.sfx_3d("shot_carbine", a.global_position, -16)
					if rng.randf() < 0.55:
						_damage_foe(t, foe["idx"], 25.0, null, a.position, i)
					a.face(ra.position - a.position, dt, 30.0)
					break
	var bstep := a.poll_step(dt, a.vel.length())
	if bstep != "" and a.position.distance_to(actors[s.selected].position) < 25.0:
		g.sfx_3d(bstep, a.global_position, -20)
	a.animate(dt, a.vel.length(), work, s.carried_flag(0, i) != null)
	a.vel = Vector3.ZERO


func _update_empire_defenders(dt: float) -> void:
	var s: Sim = g.sim
	for index in range(1, s.teams.size()):
		var team: Dictionary = s.teams[index]
		var id: String = team["name"].to_lower()
		var squad: Dictionary = s.empire.squads[id]
		if squad["location"] != s.empire_enemy:
			team["planet"] = "space"
			continue
		var bay := s.landing_bay(index)
		if team["planet"] != "B" or team["phase"] != "surface":
			team["bot_position"] = Vector3(bay.x, 0, bay.y).move_toward(Vector3.ZERO, 18.0)
		team["planet"] = "B"
		team["phase"] = "surface"
		if team["stun"] > 0.0:
			team["stun"] = maxf(0.0, team["stun"] - dt)
			continue
		var patrol := Vector3(bay.x * 0.64, 0, bay.y * 0.64)
		patrol.x += 8.0 * sin(s.time * 0.13 + index)
		patrol.z += 7.0 * cos(s.time * 0.19 + index)
		s._move_bot(team, patrol, dt)


func _rivals_tick(dt: float) -> void:
	var s: Sim = g.sim
	var me: Actor = actors[s.selected]
	for t in rivals:
		var team = s.teams[t]
		var rv: Dictionary = rivals[t]
		var ra: Actor = rv["actor"]
		var sight: MeshInstance3D = rv["sight"]
		sight.hide()
		var vis: bool = team["planet"] == "B" and team["phase"] == "surface" and not team["eliminated"]
		ra.visible = vis
		ra.set_health(rv["hp"] if team["stun"] <= 0.0 else 0.0, team["stun"] > 0.0)
		rival_ships[t]["node"].visible = team["planet"] == "B" and not team["eliminated"]
		rival_ships[t]["label"].visible = rival_ships[t]["node"].visible
		_squad_tick(t, vis, dt)
		if not vis:
			continue
		var p: Vector3 = team["bot_position"]
		var kb: Vector3 = rv["kb_vel"]
		var kb_step := Vector3.ZERO
		if kb.length() > 0.05:
			var wanted := p + kb * dt
			var pushed := collide(wanted)  # rocks, cover and arena bounds stop the slide
			if pushed.distance_to(wanted) > 0.001:
				kb *= 0.35
			kb_step = pushed - p
			p = pushed
			team["bot_position"] = p
			kb *= exp(-KB_FRICTION * dt)
			rv["kb_vel"] = kb
		else:
			rv["kb_vel"] = Vector3.ZERO
		var moved: Vector3 = p - rv["last"] - kb_step
		rv["last"] = p - kb_step
		ra.position = Vector3(p.x, 0, p.z)
		var spd := moved.length() / maxf(dt, 0.001)
		if spd > 0.2:
			ra.face(moved, dt)
		var scanning := false
		if team["target"] != null:
			var f = s.flags[team["target"]]
			scanning = f["state"] == "site" and g.flat_dist(p, f["position"]) < 2.3
			if scanning:
				ra.face(f["position"] - p, dt)
		if team["stun"] > 0.0:
			ra.animate(dt, 0.0, "down")
		else:
			ra.animate(dt, spd, "scan" if scanning else "", team["carrying"] != null)
			var rstep := ra.poll_step(dt, spd)
			if rstep != "" and me.position.distance_to(ra.position) < 28.0:
				g.sfx_3d(rstep, ra.global_position, -20)
		# Return fire at the human when close.
		var aim_start := ra.position + Vector3.UP * 1.6
		var aim_end := me.position + Vector3.UP * 1.4
		if team["stun"] <= 0.0 and down_t <= 0.0 and me.position.distance_to(ra.position) < 20.0 and _line_clear(aim_start, aim_end):
			rival_shot[t] -= dt
			var aim_length := aim_start.distance_to(aim_end)
			if rival_shot[t] <= RIVAL_AIM_TIME and aim_length >= 0.1:
				sight.transform = _beam_transform(aim_start, aim_end, aim_length)
				sight.show()
			if rival_shot[t] <= 0.0:
				rival_shot[t] = 2.8 if s.difficulty == "cadet" else (1.8 if s.difficulty == "expert" else 2.4)
				var hit := rng.randf() < 0.5
				g.sfx_3d("shot_carbine", ra.global_position + Vector3(0, 1.5, 0), -10)
				CombatFX.tracer(self, aim_start, aim_end + (Vector3.ZERO if hit else Vector3(rng.randf_range(-2, 2), 1.4, 0)), g.sim.field_color(t), 0.05, 0.09)
				if hit:
					if s.shield > 0.0:
						g.sfx("shield_hit", -8)
						combat_hud.trigger_damage_from(ra.global_position, true)
					else:
						last_hit[s.selected] = 6.0
						field_hp -= 9.0 * s.armor_mult * Sim.DIFFICULTY[s.difficulty]["damage"]
						me.flash("hit", 0.28)
						preload("res://scripts/combat_fx.gd").impact(self, me.position + Vector3.UP * 1.4, Color("#f56d65"), 0.6, 10)
						g.hud.hurt(0.3)
						combat_hud.trigger_damage_from(ra.global_position, false)
						g.sfx("hurt", -8)
						if field_hp <= 0.0:
							_downed()


func _squad_tick(t: int, vis: bool, dt: float) -> void:
	var s: Sim = g.sim
	var rv: Dictionary = rivals[t]
	var lead_pos: Vector3 = s.teams[t]["bot_position"]
	var lead_head: float = (rv["actor"] as Actor).heading
	var me: Actor = actors[s.selected]
	for k in rv["squad"].size():
		var m: Dictionary = rv["squad"][k]
		var ma: Actor = m["actor"]
		ma.visible = vis
		if not vis:
			m["placed"] = false
			continue
		var slot_pos: Vector3 = lead_pos + (m["off"] as Vector3).rotated(Vector3.UP, lead_head)
		if not m["placed"]:
			ma.position = collide(Vector3(slot_pos.x, 0, slot_pos.z))
			m["placed"] = true
		ma.set_health(m["hp"] if m["stun"] <= 0.0 else 0.0, m["stun"] > 0.0)
		if m["stun"] > 0.0:
			m["stun"] -= dt
			ma.animate(dt, 0.0, "down")
			if m["stun"] <= 0.0:
				m["hp"] = 100.0
				ma.position = collide(Vector3(slot_pos.x, 0, slot_pos.z))
			continue
		var kb: Vector3 = m["kb_vel"]
		if kb.length() > 0.05:
			var wanted: Vector3 = ma.position + kb * dt
			var pushed := collide(wanted)
			if pushed.distance_to(wanted) > 0.001: kb *= 0.35
			ma.position = pushed
			m["kb_vel"] = kb * exp(-KB_FRICTION * dt)
		else:
			m["kb_vel"] = Vector3.ZERO
		var far: bool = g.flat_dist(ma.position, slot_pos) > 14.0
		_crew_walk(ma, slot_pos, dt, 9.0 if far else 5.8, 1.0)
		var spd: float = ma.vel.length()
		ma.vel = Vector3.ZERO
		var key := "%d:%d" % [t, k]
		var aim_from := ma.position + Vector3.UP * 1.6
		var aim_to := me.position + Vector3.UP * 1.4
		var in_range: bool = down_t <= 0.0 and me.position.distance_to(ma.position) < 22.0 and _line_clear(aim_from, aim_to)
		if in_range:
			ma.face(me.position - ma.position, dt, 8.0)
			squad_shot[key] -= dt
			if squad_shot[key] <= 0.0:
				squad_shot[key] = (3.6 if s.difficulty == "cadet" else (2.3 if s.difficulty == "expert" else 3.0)) + 0.4 * k
				var hit := rng.randf() < 0.4
				g.sfx_3d("shot_carbine", ma.global_position + Vector3(0, 1.5, 0), -12)
				CombatFX.tracer(self, aim_from, aim_to + (Vector3.ZERO if hit else Vector3(rng.randf_range(-2, 2), 1.4, 0)), g.sim.field_color(t), 0.05, 0.09)
				if hit: _hurt_player(ma, 7.0)
		elif spd > 0.2:
			ma.face(slot_pos - ma.position, dt)
		_squad_ship_attack(ma, t, k, key, in_range, dt)
		ma.animate(dt, spd, "")
		var mstep := ma.poll_step(dt, spd)
		if mstep != "" and me.position.distance_to(ma.position) < 28.0:
			g.sfx_3d(mstep, ma.global_position, -22)


func landing_zone() -> Vector3:
	var point: Vector2 = g.sim.landing_bay(0)
	if g.arena_clash != null:
		var index := 0 if g.home_alliance() == "planet_a" else 3
		point = Vector2(Sim.LANDING_BAYS[index][0], Sim.LANDING_BAYS[index][1])
	return Vector3(point.x, 0, point.y)


func _ship_pos() -> Vector3:
	return g.vessel.position - Universe.C_ORIGIN if is_instance_valid(g.vessel) and g.sim.on_surface("planet_c") else SHIP_POS


func _cargo_hatch() -> Vector3:
	if not is_instance_valid(g.vessel) or not g.sim.on_surface("planet_c"):
		return HATCH
	return _ship_pos() + g.vessel.basis * Vector3(0, 0, -15.5) * ShipModel.VESSEL_SCALE


func _ship_targetable() -> bool:
	if not rival_ships.has(0) or not is_instance_valid(rival_ships[0]["node"]):
		return false
	return not g.piloting and is_instance_valid(g.vessel) and g.vessel.grounded and not g.sim.teams[0]["eliminated"]


## Enemy squadmates near your landed ship (or crowding your bay) sometimes shoot it instead of you.
func _squad_ship_attack(ma: Actor, t: int, k: int, key: String, shooting_player: bool, dt: float) -> void:
	if not _ship_targetable() or shooting_player:
		return
	var sp := _ship_pos()
	var d: float = g.flat_dist(ma.position, sp)
	if d > 34.0:
		return
	var aim_from := ma.position + Vector3.UP * 1.6
	var aim_to := sp + Vector3(rng.randf_range(-3, 3), 4.0 + rng.randf_range(0, 3), rng.randf_range(-2, 2))
	ma.face(sp - ma.position, dt, 6.0)
	ship_shot[key] = float(ship_shot.get(key, 2.0 + k)) - dt
	if ship_shot[key] > 0.0:
		return
	var diff: Dictionary = Sim.DIFFICULTY[g.sim.difficulty]
	ship_shot[key] = (5.0 if g.sim.difficulty == "cadet" else (3.2 if g.sim.difficulty == "expert" else 4.0)) + 0.8 * k + rng.randf() * 1.5
	g.sfx_3d("shot_carbine", ma.global_position + Vector3(0, 1.5, 0), -12)
	CombatFX.tracer(self, aim_from, aim_to, g.sim.field_color(t), 0.06, 0.1)
	_damage_ship(5.0 * float(diff["damage"]), aim_to)


func _damage_ship(amount: float, at: Vector3) -> void:
	var s: Sim = g.sim
	ship_hit_t = 0.0
	ship_dome_flash = 1.0
	if ship_alert_cd <= 0.0:
		ship_alert_cd = 4.0
		combat_hud.announce("SHIP UNDER ATTACK!", "Defend your ship — raiders are firing on it", Color("#ff6a5c"))
		g.hud.toast("SHIP UNDER ATTACK!", 2.0)
	if ship_shield > 0.0:
		var absorbed := minf(ship_shield, amount)
		ship_shield -= absorbed
		amount -= absorbed
		g.sfx("shield_hit", -8)
		CombatFX.impact(self, at, Color("#7ae8ff"), 0.9, 12)
		if ship_shield <= 0.0:
			g.hud.toast("SHIP SHIELD DOWN!", 2.5)
			combat_hud.announce("SHIP SHIELD DOWN!", "Hull exposed", Color("#ffd27a"))
	_sync_flight_shield()
	if amount > 0.0:
		s.apply_hull_damage(amount)
		CombatFX.impact(self, at, Color("#ffb347"), 1.1, 16)
		g.sfx("hurt", -14)


## Mirror the landed ship's shield into the shared Flight pool the HUD reads (as a 0..SHIELD_MAX percentage),
## and expose the recharge lockout as Flight.under_fire so the HUD's "under fire" state matches the Moon.
func _sync_flight_shield() -> void:
	Flight.ship_shield = clampf(ship_shield / SHIP_SHIELD_MAX, 0.0, 1.0) * Flight.SHIELD_MAX
	Flight.under_fire = maxf(0.0, SHIP_SHIELD_RECHARGE_DELAY - ship_hit_t)


func _exit_tree() -> void:
	_release_lunar_lighting()
	# Leave the shared pool in a clean state for whatever comes next (return flight resets it again).
	Flight.ship_shield = Flight.SHIELD_MAX
	Flight.under_fire = 0.0


func _ship_status_tick(dt: float) -> void:
	var s: Sim = g.sim
	ship_alert_cd = maxf(0.0, ship_alert_cd - dt)
	ship_hit_t += dt
	if ship_dome == null:
		ship_dome = Gfx.sphere(14.0 * ShipModel.VESSEL_SCALE, Color("#38bdf8"), _ship_pos() + Vector3.UP * 4.0 * ShipModel.VESSEL_SCALE, 0.3, 24)
		ship_dome.name = "ShipShieldDome"
		ship_dome.material_override = BlenderVisualUpgrades.shield(Color("#22d3ee"), 0.08, 28.0 * ShipModel.VESSEL_SCALE)
		ship_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ship_dome)
		ship_status = Gfx.label("", UI.GOOD, 52)
		ship_status.add_to_group("station_labels")
		ship_status.position = _ship_pos() + Vector3.UP * 19.0 * ShipModel.VESSEL_SCALE
		add_child(ship_status)
	if not _ship_targetable():
		ship_dome.visible = false
		ship_status.visible = false
		_sync_flight_shield()
		return
	if ship_shield < SHIP_SHIELD_MAX and ship_hit_t >= SHIP_SHIELD_RECHARGE_DELAY:
		ship_shield = minf(SHIP_SHIELD_MAX, ship_shield + 8.0 * dt)
	_sync_flight_shield()
	ship_dome_flash = maxf(0.0, ship_dome_flash - dt * 2.5)
	ship_dome.position = _ship_pos() + Vector3.UP * 4.0 * ShipModel.VESSEL_SCALE
	ship_status.position = _ship_pos() + Vector3.UP * 19.0 * ShipModel.VESSEL_SCALE
	ship_dome.visible = ship_shield > 0.0
	var dm := ship_dome.material_override as ShaderMaterial
	dm.set_shader_parameter("field_color", Color.WHITE.lerp(Color("#22d3ee"), 1.0 - ship_dome_flash))
	dm.set_shader_parameter("dome_opacity", 0.06 + 0.4 * ship_dome_flash)
	ship_status.visible = true
	var hp_col := "#9cdeb1" if s.hull > 60.0 else ("#ffd27a" if s.hull > 30.0 else "#ff6a5c")
	ship_status.modulate = Color(hp_col)
	ship_status.text = "HULL %d%%  ·  SHIELD %d%%" % [int(s.hull), int(ship_shield / SHIP_SHIELD_MAX * 100.0)]
	# Damaged hull sparks and smokes.
	if s.hull < 60.0:
		ship_smoke_t -= dt
		if ship_smoke_t <= 0.0:
			ship_smoke_t = 0.35 if s.hull < 30.0 else 0.8
			var p := _ship_pos() + Vector3(rng.randf_range(-4, 4), 3.0 + rng.randf() * 3.0, rng.randf_range(-3, 3))
			CombatFX.dust_puff(self, p, Color("#3a3a40"), 1.6)
			if s.hull < 30.0:
				CombatFX.impact(self, p, Color("#ffb347"), 0.5, 6)


func _hurt_player(from_actor: Node3D, base: float) -> void:
	var s: Sim = g.sim
	var me: Actor = actors[s.selected]
	if s.shield > 0.0:
		g.sfx("shield_hit", -8)
		combat_hud.trigger_damage_from(from_actor.global_position, true)
		return
	last_hit[s.selected] = 6.0
	field_hp -= base * (0.6 if crouching else 1.0) * s.armor_mult * Sim.DIFFICULTY[s.difficulty]["damage"]
	me.flash("hit", 0.28)
	preload("res://scripts/combat_fx.gd").impact(self, me.position + Vector3.UP * 1.4, Color("#f56d65"), 0.6, 10)
	g.hud.hurt(0.3)
	combat_hud.trigger_damage_from(from_actor.global_position, false)
	g.sfx("hurt", -8)
	if field_hp <= 0.0:
		_downed()


func _downed() -> void:
	var s: Sim = g.sim
	var a: Actor = actors[s.selected]
	if s.drop_flag(0, s.selected, a.position):
		g.hud.toast("You were downed — your flag is on the ground.")
	else:
		g.hud.toast("You were downed.")
	s.metrics["downs"] += 1
	field_hp = 60.0
	last_hit[s.selected] = 3.0
	down_t = 3.0
	# Leave the body where it fell; respawn only after the knockout animation.
	actors[s.selected].set_weapon_drawn(false)


func _feed(msg: String, accent: Color) -> void:
	if combat_hud != null and combat_hud.has_method("push_feed"):
		combat_hud.call("push_feed", msg, accent)


func _visuals(dt: float) -> void:
	_rival_bars(dt)
	var s: Sim = g.sim
	if s.empire != null and s.empire.overdrive and not _golden_unlocked:
		_golden_unlocked = true
		EmpireLayer.play_feedback(self, "flag_fanfare", -10.0)
	var t := s.time
	var beam_active := false
	for f in s.flags:
		var fn: Dictionary = flag_nodes[f["id"]]
		var cr: Node3D = fn["crystal"]
		var site: Vector3 = fn["site"]
		var st: String = f["state"]
		var col := CRYSTAL
		fn["ring"].visible = st == "site" and f["planet"] == "B"
		fn["label"].visible = f["planet"] == "B" and (st == "site" or st == "ground")
		cr.visible = f["planet"] == "B" and st in ["site", "ground", "carried"]
		match st:
			"site":
				var frac := s.scan_fraction(f)
				var stage_col: Color = [Color("#38bdf8"), Color("#f7ce59"), Color("#34d399")][mini(2, f["stage"])] if frac > 0.0 else (Color("#ffd66b") if f.get("golden", false) else CRYSTAL)
				col = stage_col
				cr.position = Vector3(0, 2.6 + sin(t * 2.0 + f["id"]) * 0.15 + frac * 1.2, 0)
				cr.rotation.y += dt * (1.0 + frac * 8.0)
				fn["ring"].position = Vector3(0, 0.15, 0)
				fn["ring"].scale = Vector3(1.0 + frac * 1.5, 0.05, 1.0 + frac * 1.5)
				fn["ring"].material_override = Gfx.unshaded(stage_col, 0.75 if frac > 0.0 else 0.45)
				fn["label"].position = Vector3(0, 4.6, 0)
				fn["label"].modulate = stage_col
				fn["label"].text = ("FLAG %d" % (f["id"] + 1) if s.empire == null else _flag_name(f).to_upper()) if frac <= 0.0 else "%s %d%%" % [["SCAN", "STABILIZE", "EXTRACT"][mini(2, f["stage"])], int(frac * 100)]
				if f["scanner"] != null:
					col = g.sim.field_color(f["scanner"]).lerp(CRYSTAL, 0.4)
					if not beam_active and frac > 0.0 and is_instance_valid(scan_beam):
						var scanner_pos := Vector3.ZERO
						if f["scanner"] == 0:
							scanner_pos = actors[3].position + Vector3(0, 1.3, 0)
						elif rivals.has(f["scanner"]) and rivals[f["scanner"]]["actor"].visible:
							scanner_pos = rivals[f["scanner"]]["actor"].position + Vector3(0, 1.3, 0)
						var crystal_pos := site + cr.position
						var delta := crystal_pos - scanner_pos
						if scanner_pos != Vector3.ZERO and delta.length() > 0.1 and delta.length() < 8.0:
							beam_active = true
							scan_beam.visible = true
							scan_beam.position = (scanner_pos + crystal_pos) * 0.5
							var up := delta.normalized()
							var x := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
							scan_beam.basis = Basis(x, up, x.cross(up))
							scan_beam.scale = Vector3(1.0, delta.length(), 1.0)
							scan_beam.material_override = Gfx.unshaded(stage_col, 0.72)
			"ground":
				var base: Vector3 = f["position"] - site
				var off := Vector3.ZERO
				if fn.get("vs", st) == "carried":
					# Knockout drop: lob the crystal up and outward under lunar gravity.
					var ang := rng.randf() * TAU
					fn["drop"] = {"h": 2.7, "vh": 2.6, "off": Vector3(cos(ang), 0, sin(ang)) * 1.5, "bounces": 0}
				if fn.has("drop"):
					var d: Dictionary = fn["drop"]
					d["vh"] += FLAG_DROP_GRAVITY * dt
					d["h"] += d["vh"] * dt
					d["off"] = (d["off"] as Vector3).move_toward(Vector3.ZERO, 0.8 * dt)
					if d["h"] <= 0.0:
						d["h"] = 0.0
						CombatFX.dust_puff(self, site + base + d["off"], Color("#c9c5ba"), 0.8 if d["bounces"] == 0 else 0.5)
						if d["bounces"] == 0:
							d["bounces"] = 1
							d["vh"] = -d["vh"] * 0.3
						else:
							d["vh"] = 0.0
							d["off"] = Vector3.ZERO
					if d["bounces"] >= 1 and d["h"] == 0.0 and d["vh"] == 0.0 and (d["off"] as Vector3).length() < 0.01:
						fn.erase("drop")
					else:
						off = (d["off"] as Vector3) + Vector3(0, d["h"], 0)
				cr.position = base + Vector3(0, FLAG_REST_Y, 0) + off
				cr.rotation.y += dt * 2.0
				fn["label"].position = base + Vector3(0, 2.0, 0)
				fn["label"].modulate = Color("#ffffff")
				fn["label"].text = "◆ DROPPED FLAG %d" % (f["id"] + 1)
				col = Color("#ffffff")
			"carried":
				var flag_team: int = f["owner"]
				col = g.sim.field_color(flag_team)
				if flag_team == 0:
					cr.position = actors[f["carrier"]].position - site + Vector3(0, 3.4, 0)
				elif rivals.has(flag_team):
					cr.position = rivals[flag_team]["actor"].position - site + Vector3(0, 3.4, 0)
		if fn.has("gold_beacon"):
			var gold: Node3D = fn["gold_beacon"]
			gold.visible = _golden_unlocked and f["planet"] == "B" and st in ["site", "ground"]
			if gold.visible:
				gold.position = f["position"] - site if st == "ground" else Vector3.ZERO
				var beam := gold.get_node("Beam") as MeshInstance3D
				var caption := gold.get_node("Label") as Label3D
				var pulse := 0.5 + 0.5 * sin(t * 3.4 + f["id"])
				beam.transparency = 0.18 + 0.35 * pulse if not UI.reduced_motion else 0.18
				caption.modulate.a = 0.78 + 0.22 * pulse if not UI.reduced_motion else 1.0
				if st == "site" and s.scan_fraction(f) <= 0.0:
					fn["label"].hide()
		if st != "ground": fn.erase("drop")
		fn["vs"] = st
		var key := col.to_html()
		if not materials.has(key): materials[key] = [Gfx.mat(col, 0.2, 2.5), Gfx.mat(col, 0.6)]
		fn["gem"].material_override = materials[key][0]
		fn["pennant"].material_override = materials[key][1]
	if is_instance_valid(scan_beam) and not beam_active:
		scan_beam.visible = false
	if is_instance_valid(priority_beacon):
		var show_pri: bool = s.priority_flag >= 0 and s.flags[s.priority_flag]["planet"] == "B" and s.flags[s.priority_flag]["state"] in ["site", "ground"]
		priority_beacon.visible = show_pri
		if show_pri:
			priority_beacon.position = s.flags[s.priority_flag]["position"]
	if is_instance_valid(hatch_beacon):
		var counts := s.flag_counts(0)
		hatch_beacon.visible = counts["carried"] > 0 or counts["onboard"] >= s.cargo_capacity
		if hatch_beacon.visible:
			hatch_beacon.position = _cargo_hatch() + Vector3.UP * 4.2
			hatch_beacon.text = "▲ LOAD SAMPLE [E] (%d/%d)" % [counts["onboard"], s.cargo_capacity]
			hatch_beacon.visible = counts["carried"] > 0
	for i in 4:
		var ring_col := Sim.role_color(i)
		if i == 0 and s.boost > 0.0: ring_col = Color("#38bdf8")
		elif s.overdrive > 0.0: ring_col = Color("#fb7185")
		actors[i].set_ring_color(ring_col)
	if is_instance_valid(shield_bubble):
		shield_bubble.visible = s.shield > 0.0 and down_t <= 0.0
		if shield_bubble.visible:
			shield_bubble.position = actors[s.selected].position + Vector3(0, 1.3, 0)
	for shot_trace in tracers.duplicate():
		shot_trace["life"] -= dt
		if shot_trace["life"] <= 0.0:
			shot_trace["node"].queue_free()
			tracers.erase(shot_trace)


## Pulsing carry aura plus crisp flashes on pickup / delivery / drop transitions.
func _flag_tension(f: Dictionary, fn: Dictionary, col: Color, t: float) -> void:
	var st: String = f["state"]
	var on_moon: bool = f["planet"] == "B"
	var aura: MeshInstance3D = fn["aura"]
	aura.visible = on_moon and st == "carried"
	if aura.visible:
		var cr: Node3D = fn["crystal"]
		var beat := 0.5 + 0.5 * sin(t * 9.0 + float(f["id"]))
		aura.position = Vector3(cr.position.x, 0.14, cr.position.z)
		var sc := 1.0 + beat * 0.45
		aura.scale = Vector3(sc, 0.05, sc)
		(aura.material_override as StandardMaterial3D).albedo_color = Color(col.lerp(Color.WHITE, beat * 0.4), 0.4 + beat * 0.55)
	var prev: String = flag_state_prev.get(f["id"], st)
	if prev == st:
		return
	flag_state_prev[f["id"]] = st
	if not on_moon and st != "onboard":
		return
	var at: Vector3 = fn["site"] + (fn["crystal"] as Node3D).position
	if st == "carried":
		CombatFX.impact(self, at, col.lerp(Color.WHITE, 0.3), 1.6, 26)
		CombatFX.ring_pulse(self, Vector3(at.x, 0.2, at.z), col, 5.0, 0.4)
	elif st == "onboard":
		CombatFX.impact(self, _cargo_hatch() + Vector3(0, 1.5, 0), ACCENT.lerp(Color.WHITE, 0.4), 2.2, 32)
		CombatFX.ring_pulse(self, _cargo_hatch() + Vector3(0, 0.2, 0), ACCENT, 9.0, 0.55)
	elif st == "ground" and prev == "carried":
		CombatFX.impact(self, at, Color.WHITE, 1.2, 16)
		CombatFX.ring_pulse(self, Vector3(at.x, 0.2, at.z), Color.WHITE, 3.5, 0.35)

func update_station_labels(camera: Camera3D) -> void:
	var player := actor(g.sim.selected)
	if player == null:
		return
	var candidates: Array[Label3D] = []
	for label in [hatch_beacon, ship_status]:
		if is_instance_valid(label) and label.visible:
			candidates.append(label)
	WorldLabels.select_station(candidates, camera, player.global_position)


func _arena_hud_update(hud: Hud) -> void:
	var clash: ArenaClashRules = g.arena_clash
	hud.title.text = "ARENA CLASH · " + Universe.C_LABEL
	hud.visual_status.hide()
	hud.vitals_panel.hide()
	hud.station_panel.hide()
	hud.crosshair.hide()
	if not arena_actors.has(_arena_player_id):
		return
	hud.subtitle.text = ""
	hud.objectives.get_parent().get_parent().hide()
	var score: Dictionary = g.arena_clash.get_score()
	if score != _arena_score:
		_arena_score = score
		combat_hud.set_team_scores([
			{"name": "PLANET A", "color": Color.html(Sim.EMPIRE_COLORS["orange"]), "delivered": score["planet_a"], "target": g.arena_clash.kill_target},
			{"name": "PLANET B", "color": Color.html(Sim.EMPIRE_COLORS["crimson"]), "delivered": score["planet_b"], "target": g.arena_clash.kill_target},
		])
	hud.footer.text = "LMB FIRE    R RELOAD    B EQUIP    V VIEW    H HINTS"
	hud.radar_title.text = "MOON · ARENA"
	hud.radar.range_m = 64.0
	var me: Dictionary = arena_actors[_arena_player_id]
	var player: Actor = me["actor"]
	var points: Array = []
	for entry: Dictionary in arena_actors.values():
		var other: Actor = entry["actor"]
		if other == player or not other.visible:
			continue
		var offset := other.position - player.position
		points.append({"p": Vector2(offset.x, offset.z).rotated(g.yaw), "c": entry["color"], "s": 3.5})
	hud.radar.points = points
	hud.radar.request_redraw()
	var state: Dictionary = me["state"]
	combat_hud.set_vitals(state["health"], state["shield"], ammo, 24, state["alive"] and player.weapon_drawn)



func hud_update(hud: Hud) -> void:
	if g.arena_clash != null:
		_arena_hud_update(hud)
		return
	var s: Sim = g.sim
	var c := s.flag_counts(0)
	var r := s.selected
	hud.title.text = Universe.C_LABEL
	hud.subtitle.text = "A STORAGE  ·  B REACTOR  ·  C RELAY"
	var cells := ""
	for slot in s.cargo_capacity: cells += "■ " if slot < c["onboard"] else "□ "
	hud.objectives.text = "[color=#eaa665]SAMPLES  %d / %d[/color]\n%s\n\n[color=#7cd8df]◆ %d available[/color]   ◇ %d loose" % [c["onboard"], s.cargo_capacity, cells, c["sites"], c["loose"]]
	hud.field_status(field_hp, ammo, reload_t, actors[r].weapon_drawn, r, s, down_t)
	hud.station_panel.visible = false
	hud.crosshair.visible = r == 3 or actors[r].weapon_drawn
	hud.footer.text = "B EQUIP    C ORDERS    Z PING    M MAP    H HINTS"
	hud.radar_title.text = Universe.C_LABEL + " · SURFACE"
	for i in 4:
		var st := ("REGROUPING" if s.crew_order == "regroup" else ("EXTRACTING" if i == 3 else "ESCORTING"))
		if down_times[i] > 0.0: st = "RECOVERING"
		if s.carried_flag(0, i) != null:
			st = "CARRYING FLAG"
		hud.set_crew_status(i, st + (" · YOU" if i == r else " · BOT"), suit_hp[i] / 100.0)
	var me: Actor = actors[r]
	var pts: Array = []
	var rot: float = g.yaw
	var add := func(p: Vector3, col: Color, size: float, ring: bool, label: String):
		var offset := p - me.position
		pts.append({"p": Vector2(offset.x, offset.z).rotated(rot), "c": col, "s": size,
			"ring": ring, "label": label, "dist": offset.length()})
	for i in g.sim.teams.size():
		var bay: Vector2 = g.sim.landing_bay(i)
		var label := "YOUR BAY" if i == 0 else "%s BAY" % g.sim.teams[i]["name"]
		add.call(Vector3(bay[0], 0, bay[1]), g.sim.field_color(i), 6.0, true, label)
	if s.flag_counts(0)["carried"] > 0:
		add.call(_cargo_hatch(), ACCENT, 4.5, true, "CARGO HATCH")
	for f in s.flags:
		if f["planet"] != "B":
			continue
		var label := "SAMPLE %02d" % (f["id"] + 1)
		if f["state"] == "site":
			add.call(f["position"], CRYSTAL, 3.0, false, label)
		elif f["state"] == "ground":
			add.call(f["position"], Color.WHITE, 3.5, true, label)
	for foe in _foes():
		var ft: int = foe["team"]
		var fidx: int = foe["idx"]
		add.call(foe["actor"].position, g.sim.field_color(ft), 3.5 if fidx < 0 else 2.8, false, g.sim.teams[ft]["name"] if fidx < 0 else SQUAD_CALLSIGNS[fidx].left(3))
	for i in 4:
		if i != r:
			add.call(actors[i].position, Sim.role_color(i), 2.5, false, Sim.SPECIALISTS[i]["name"])
	if s.priority_flag >= 0:
		add.call(s.flags[s.priority_flag]["position"], UI.ACCENT, 7.0, true, "PRIORITY SAMPLE %02d" % (s.priority_flag + 1))
	hud.radar.points = pts
	hud.radar.range_m = 50.0
	hud.radar.request_redraw()
	var shapes: Array = []
	for obstacle in blockers:
		if not obstacle.has("half"): continue
		var corners: Array = []
		for sign_pair in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var point: Vector2 = obstacle["c"] + obstacle["half"] * sign_pair - Vector2(me.position.x, me.position.z)
			corners.append(point.rotated(rot))
		shapes.append(corners)
	hud.tactical_radar.cover_shapes = shapes
	hud.update_tactical(pts, Universe.C_LABEL + " · LIVE TACTICAL MAP", 95.0)
	if s.priority_flag >= 0:
		hud.advisor.text = "◆ Priority sample %02d" % (s.priority_flag + 1)


func _build_first_person() -> void:
	first_person_rig = Node3D.new()
	first_person_rig.name = "FirstPersonHands"
	first_person_rig.hide()
	add_child(first_person_rig)
	for role in 3:
		var a: Actor = actors[role]
		var rig := a.build_fpv_rig()
		first_person_rig.add_child(rig)
		# Keep both gloves inside the resting frustum with room for recoil and reload.
		rig.position = Vector3(-0.02, 0.05, -0.10)
		first_person_models.append(rig)

func _first_person_tick(dt: float, speed: float) -> void:
	var role: int = g.sim.selected
	var a: Actor = actors[role]
	first_person_rig.visible = g.first_person and role != 3 and down_t <= 0.0
	if role != 3:
		var view_speed := 0.0
		if not UI.reduced_motion and GraphicsSettings.motion_effects and first_person_rig.visible:
			view_speed = speed if g.held(KEY_SHIFT) and not a.dash_active() else minf(speed, 4.0)
		a.tick_fpv(dt, view_speed)
	if not first_person_rig.visible: return
	first_person_rig.global_transform = g.cam.global_transform
	for i in 3:
		first_person_models[i].visible = i == role and a.weapon_blend > 0.01
