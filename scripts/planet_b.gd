## the Moon: twelve finite Science Flags, four landing bays, rival raiders.
## Fernando scans flags (hold LMB, 5 s), anyone can carry them, E loads at the ship, T departs.
class_name PlanetB
extends Node3D

const ACCENT := Color("#f08a4b")
const CRYSTAL := Color("#6fe0e6")
const SHIP_POS := Vector3(0, 0, 58)
const HATCH := Vector3(0, 0, 42.5)
const RIVAL_AIM_TIME := 0.55
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")

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
var depart_confirm := 0.0
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
var reload_times := [0.0, 0.0, 0.0, 0.0]
var reload_t: float:
	get: return reload_times[g.sim.selected]
	set(value): reload_times[g.sim.selected] = value
var fire_cd := 0.0
var first_person_rig: Node3D
var first_person_models: Array = []
var bot_fire := [1.0, 1.0, 1.0, 1.0]
var rival_shot := [2.0, 2.0, 2.0, 2.0]
var tracers: Array = []
var carry_vis: Array = ["", "", "", ""]
var last_stage := {}
var blockers: Array = []
var rng := RandomNumberGenerator.new()
var fx_rng := RandomNumberGenerator.new()
var camera_obstacles: Array = []
var navigation := preload("res://scripts/arena_navigation.gd").new()
var priority_beacon: Node3D
var hatch_beacon: Label3D
var scan_beam: MeshInstance3D
var shield_bubble: MeshInstance3D
var scan_sfx_cd := 0.0
var sprint_dust_distance := 0.0
var dust_mesh: QuadMesh
var dust_fade: Gradient
var extract_ring: MeshInstance3D
var flag_state_prev := {}


func actor(i: int) -> Actor:
	return actors[i]


func setup(main) -> void:
	g = main
	name = "PlanetB"
	rng.seed = g.sim.match_seed + 99
	fx_rng.seed = g.sim.match_seed + 777
	# Editable terrain, lighting, landing pads and scenery are stored in a scene.
	var editable: Node3D = g.universe.planet_b.get_node("PlanetBEnvironment") as Node3D   # part of the one universe scene
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
	PlanetA.weather_pad(foundation, 26.0, 0.8)
	for floor_name in ["LaneFloor-26", "LaneFloor0", "LaneFloor26"]:
		PlanetA.weather_pad(arena.get_node(floor_name), 18.0, 0.45)
	for bay in editable.get_node("LandingBays").get_children():
		PlanetA.weather_pad(bay.get_node("LandingPlatform"), 14.0, 0.55)
	for x in [-4.5, 4.5]:
		for z in [43.0, 48.0]:
			PlanetA.add_apron_fixture(self, Vector3(x, 0.1, z), Color("#b1dded"))
	add_child(arena)
	for piece in arena.get_children():
		if piece.has_meta("arena_cover"):
			var dimensions: Vector3 = piece.get_meta("cover_size")
			blockers.append({"c": Vector2(piece.position.x, piece.position.z), "half": Vector2(dimensions.x, dimensions.z) * 0.5, "r": maxf(dimensions.x, dimensions.z) * 0.5, "cover": true, "center3": piece.position, "size3": dimensions})
	preload("res://scripts/model_detail.gd").batch(editable.get_node("Terrain/TerrainRocks"), [], 900.0)
	preload("res://scripts/model_detail.gd").surroundings(self, SHIP_POS + Vector3(10,0,0))
	_flags()
	_ships()
	_crew()
	_rival_actors()
	_build_first_person()
	navigation.build(blockers)
	g.sim.navigation = navigation
	beacon = Gfx.cyl(0.3, 40.0, ACCENT, Vector3.ZERO, 8)
	beacon.material_override = Gfx.unshaded(Color("#ffd29a"), 0.25)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)
	_build_waypoints()
	g.yaw = 0.0
	g.pitch = -0.18


func _build_waypoints() -> void:
	priority_beacon = Node3D.new()
	priority_beacon.name = "PriorityBeacon"
	var pbeam := Gfx.cyl(0.22, 32.0, UI.ACCENT, Vector3(0, 16, 0), 8)
	pbeam.material_override = Gfx.unshaded(UI.ACCENT, 0.22)
	pbeam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	priority_beacon.add_child(pbeam)
	var plab := Gfx.label("★ PRIORITY SAMPLE", UI.ACCENT, 44)
	plab.position = Vector3(0, 6.2, 0)
	priority_beacon.add_child(plab)
	priority_beacon.visible = false
	add_child(priority_beacon)

	hatch_beacon = Gfx.label("▲ SHIP LOAD RAMP", Color("#9cdeb1"), 46)
	hatch_beacon.name = "HatchBeacon"
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
	shield_bubble.material_override = Gfx.unshaded(Color("#38bdf8"), 0.16)
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
		var site = Sim.FLAG_SITES[f["site"]]
		var marker: Node3D = template.instantiate() as Node3D
		marker.name = "Flag%02d" % (int(f["id"]) + 1)
		marker.position = Vector3(site[0], 0, site[1])
		add_child(marker)
		var crystal: Node3D = marker.get_node("Crystal") as Node3D
		var gem: MeshInstance3D = marker.get_node("Crystal/Gem") as MeshInstance3D
		var pennant: MeshInstance3D = marker.get_node("Crystal/Pennant") as MeshInstance3D
		var ring: MeshInstance3D = marker.get_node("ScanRing") as MeshInstance3D
		var lab: Label3D = marker.get_node("FlagLabel") as Label3D
		blockers.append({"c": Vector2(site[0], site[1]), "r": 1.3})
		# Tension cue: a pulsing luminous halo that rides under whoever carries this flag.
		var aura := Gfx.ring(1.6, 0.16, CRYSTAL, 0.8)
		aura.name = "CarryAura"
		aura.material_override = Gfx.unshaded(CRYSTAL, 0.8).duplicate()
		aura.visible = false
		marker.add_child(aura)
		flag_nodes[f["id"]] = {"crystal": crystal, "gem": gem, "pennant": pennant, "ring": ring, "label": lab, "site": marker.position, "aura": aura}
		flag_state_prev[f["id"]] = f["state"]
	# Extraction zone at the load ramp lights up and throbs while our crew carries a flag.
	extract_ring = Gfx.ring(4.0, 0.22, ACCENT, 0.8)
	extract_ring.name = "ExtractRing"
	extract_ring.material_override = Gfx.unshaded(ACCENT, 0.8).duplicate()
	extract_ring.position = HATCH + Vector3(0, 0.12, 0)
	extract_ring.visible = false
	add_child(extract_ring)


func _ships() -> void:
	for i in 4:
		var bay = Sim.LANDING_BAYS[i]
		var pos := Vector3(bay[0], 0, bay[1])
		if i > 0:
			var approach := pos + (-pos).normalized() * 18.0
			g.sim.teams[i]["position"] = approach
			g.sim.teams[i]["bot_position"] = approach
		# Bay platforms and colored rings are now editable in the level scene.
		var ship := ShipModel.full(ACCENT if i == 0 else Sim.faction_color(i), g.sim.loadout if i == 0 else g.sim.teams[i]["loadout"])
		ship.position = pos
		if i != 0:
			ship.rotation.y = atan2(pos.x, pos.z)
		add_child(ship)
		var bounds := [null]
		Actor._aabb(ship, Transform3D.IDENTITY, bounds)
		if bounds[0] != null: camera_obstacles.append(bounds[0])
		var l := Gfx.label(Sim.FACTIONS[i]["name"] + (" · YOUR SHIP" if i == 0 else ""), Sim.faction_color(i), 70)
		l.position = pos + Vector3(0, 15, 0)
		add_child(l)
		rival_ships[i] = {"node": ship, "label": l}
		blockers.append({"c": Vector2(pos.x, pos.z - (2.5 * Sim.SHIP_K if i == 0 else 0.0)), "r": 9.5 * Sim.SHIP_K})
	# The load ramp and its instructions are in PlanetBEnvironment.tscn.


func _crew() -> void:
	for r in 4:
		var s = Sim.SPECIALISTS[r]
		var a := Actor.new()
		a.setup(s["model"], r, Sim.role_color(r), s["name"], Sim.role_color(r))
		a.position = HATCH + Vector3(-4.5 + r * 3.0, 0, -3.0)
		a.heading = 0.0
		add_child(a)
		actors.append(a)
		if r != 3: a.install_weapon(Sim.FIELD_WEAPONS[r]["model"])


func _rival_actors() -> void:
	for t in range(1, 4):
		var a := Actor.new()
		a.setup(Sim.SPECIALISTS[3]["model"], 3, Sim.faction_color(t), Sim.FACTIONS[t]["name"] + " · RAIDER", Sim.faction_color(t))
		a.visible = false
		add_child(a)
		var sight := Gfx.cyl(0.035, 1.0, Color("#ff654f"), Vector3.ZERO, 6)
		sight.name = "RivalAimSight%d" % t
		sight.material_override = Gfx.unshaded(Color("#ff654f"), 0.7)
		sight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sight.hide()
		add_child(sight)
		rivals[t] = {"actor": a, "hp": 100.0, "last": Vector3.ZERO, "sight": sight}


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
	p.x = clampf(p.x, -200, 200)
	p.z = clampf(p.z, -200, 200)
	return p


func tick(dt: float) -> void:
	var s: Sim = g.sim
	var r := s.selected
	var a: Actor = actors[r]
	for i in 4:
		if actors[i].name_tag:
			actors[i].name_tag.visible = i != r
	_cooldowns(dt)
	_tactics(dt)
	beacon.visible = false
	var work := ""
	if down_t > 0.0:
		sprint_dust_distance = 0.0
		g.hud.set_prompt("DOWNED", "Recovering at the ship · %.1f s" % down_t)
		g.follow_cam(a)
		a.animate(dt, 0.0, "down")
	else:
		var previous_position := a.position
		var speed: float = g.drive(a, dt, 12.0, (0.82 if s.carried_flag(0, r) != null else 1.0) * (1.45 if s.boost > 0.0 and r == 0 else 1.0))
		g.follow_cam(a)
		if a.weapon_drawn:
			a.face(Vector3(-sin(g.yaw), 0, -cos(g.yaw)), dt, 20.0)
			a.weapon_pitch = g.pitch
		work = _interact(r, a, dt)
		a.animate(dt, speed, work, s.carried_flag(0, r) != null)
		_surface_dust(a.position, previous_position, speed > 0.0 and g.held(KEY_SHIFT))
		var step := a.poll_step(dt, speed)
		if step != "":
			g.sfx_3d(step, a.global_position, -14)
	for i in 4:
		if i != r:
			if down_times[i] <= 0.0: _bot(i, dt)
			else: actors[i].animate(dt, 0.0, "down")
	_rivals_tick(dt)
	_visuals(dt)
	_first_person_tick()
	for i in 4: actors[i].set_health(suit_hp[i] if down_times[i] <= 0.0 else 0.0, down_times[i] > 0.0)


func _surface_dust(point: Vector3, previous: Vector3, sprinting: bool) -> void:
	if point.y > 0.0:
		sprint_dust_distance = 0.0
		return
	if previous.y > 0.0:
		_dust_puff(point, 22, 1.0)
		sprint_dust_distance = 0.0
	elif sprinting:
		sprint_dust_distance += point.distance_to(previous)
		if sprint_dust_distance >= 2.0:
			_dust_puff(point, 10, 0.65)
			sprint_dust_distance = fmod(sprint_dust_distance, 2.0)
	else:
		sprint_dust_distance = 0.0


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
	depart_confirm = maxf(0.0, depart_confirm - dt)
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
			actors[i].position = HATCH + Vector3(-3.0 + i * 2.0, 0, -3.5)
			preload("res://scripts/combat_fx.gd").impact(self, actors[i].position + Vector3.UP, Color("#75dec4"), 0.7, 12)
		last_hit[i] = maxf(0.0, last_hit[i] - dt)
		if reload_times[i] > 0.0:
			reload_times[i] = maxf(0.0, reload_times[i] - dt)
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


func _interact(r: int, a: Actor, dt: float) -> String:
	var s: Sim = g.sim
	var carried = s.carried_flag(0, r)
	var hatch_d: float = g.flat_dist(a.position, HATCH)
	var c := s.flag_counts(0)
	# Weapons for non-raiders.
	fire_cd -= dt
	if r != 3:
		if g.pressed(KEY_R) and a.weapon_ready() and ammo < 24 and reload_t <= 0.0:
			reload_t = 1.3
			a.weapon_reload = 1.3
			g.sfx("reload_click", -4)
		if g.lmb and a.weapon_ready() and fire_cd <= 0.0 and reload_t <= 0.0 and ammo > 0:
			fire_cd = Sim.FIELD_WEAPONS[r]["interval"] / (1.5 if s.overdrive > 0.0 else 1.0)
			a.recoil_weapon()
			ammo -= 1
			s.metrics["shots"] += 1
			var shot_sfx := "shot_scatter" if r == 1 else ("shot_sidearm" if r == 2 else "shot_carbine")
			g.sfx(shot_sfx, -11)
			_shoot()
			if ammo == 0:
				reload_t = 1.3
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
					g.hud.toast("Flag %d on board · loading does not score — bring it home." % (carried["id"] + 1))
				else:
					g.hud.toast("Cargo racks are full.")
		else:
			beacon.visible = true
			beacon.position = HATCH + Vector3(0, 20, 0)
			g.hud.set_prompt("RETURN TO YOUR SHIP", "Carrying Science Flag %d · %d m · G drops it" % [carried["id"] + 1, int(hatch_d)])
		return ""
	var ground = _nearest_flag(a.position, ["ground"])
	if ground != null and g.flat_dist(a.position, ground["position"]) <= 3.8:
		g.hud.set_prompt("E  RECOVER SCIENCE FLAG %d" % (ground["id"] + 1), "Loose flag on the ground")
		if g.pressed(KEY_E) and s.recover_flag(ground["id"], 0, r, g.flat_dist(a.position, ground["position"])):
			g.sfx("capture_tick", -4)
		return ""
	if r == 3:
		var f = _nearest_flag(a.position, ["site"])
		if f != null:
			var d: float = g.flat_dist(a.position, f["position"])
			if d <= 3.8:
				var to: Vector3 = f["position"] - a.position
				var fwd: Vector3 = g.cam_forward()
				var aligned := d < 2.0 or Vector2(fwd.x, fwd.z).normalized().dot(Vector2(to.x, to.z).normalized()) > 0.55
				var stage_names := ["SCAN", "STABILIZE", "EXTRACT"]
				var contested: bool = f["scanner"] != null and f["scanner"] != 0
				g.hud.set_prompt("HOLD LMB  %s" % ("SCAN → STABILIZE → EXTRACT" if f["stage"] == 0 and f["progress"] == 0.0 else stage_names[mini(2, f["stage"])]),
					("CONTESTED by %s — hold to override" % Sim.FACTIONS[f["scanner"]]["name"]) if contested else ("Face the flag" if not aligned else "Science Flag %d%s" % [f["id"] + 1, " · scanner boost" if s.scan_boost > 0.0 else ""]),
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
							g.hud.toast("Science Flag %d extracted — carry it to the ship" % (f["id"] + 1))
					a.face(to, dt)
					return "scan"
				return ""
	if hatch_d <= 6.0:
		if c["onboard"] > 0 or s.flags_at_sites() == 0:
			g.hud.set_prompt("T  DEPART FOR EARTH", "%d/%d flags on board · return leg 60 s" % [c["onboard"], s.cargo_capacity])
		else:
			g.hud.set_prompt("T  DEPART (EMPTY)", "No flags on board — departing now scores nothing.")
		if g.pressed(KEY_T):
			if c["carried"] > 0:
				g.hud.toast("Load or drop every carried flag before departure.")
			elif c["onboard"] == 0 and depart_confirm <= 0.0:
				depart_confirm = 4.0
				g.hud.toast("EMPTY CARGO · Press T again within 4 seconds to confirm departure.", 4.0)
			else:
				g.depart_planet_b()
		return ""
	if r == 3:
		var f = _nearest_flag(a.position, ["site"])
		if f != null:
			beacon.visible = true
			beacon.position = f["position"] + Vector3(0, 20, 0)
			g.hud.set_prompt("SCIENCE FLAG %d" % (f["id"] + 1), "%d m · hold LMB at the pedestal" % int(g.flat_dist(a.position, f["position"])))
		else:
			g.hud.set_prompt("NO FLAGS LEFT AT SITES", "Return to the ship and press T")
	else:
		var full: bool = c["onboard"] >= s.cargo_capacity
		g.hud.set_prompt("COVER THE RAIDER" if not full else "CARGO FULL — DEPART", "B equip" if not a.weapon_drawn else "LMB fire · R reload" if not full else "Return to the load ramp and press T")
	return ""


func _shoot() -> void:
	var actor_node: Actor = actors[g.sim.selected]
	var from: Vector3 = actor_node.weapon_muzzle.global_position if actor_node.weapon_muzzle else actor_node.position + Vector3.UP * 1.5
	var dir: Vector3 = (g.cam.global_position + g.cam_forward() * 120.0 - from).normalized()
	var hit_t := 120.0
	for b in blockers:
		if not b.get("cover", false): continue
		var cover_hit := _cover_ray(from, dir, b)
		if cover_hit > 0.0: hit_t = minf(hit_t, cover_hit)
	var hit_team := -1
	for t in rivals:
		var ra: Actor = rivals[t]["actor"]
		if not ra.visible or g.sim.teams[t]["stun"] > 0.0:
			continue
		var tt := Flight._ray_sphere(from, dir, ra.position + Vector3(0, 1.3, 0), 1.4)
		if tt > 0.0 and tt < hit_t:
			hit_t = tt
			hit_team = t
	var muzzle: Vector3 = from
	var role: int = g.sim.selected
	var end_pt: Vector3 = from + dir * hit_t
	var muzzle_col := Color("#38bdf8") if role == 1 else (Color("#f472b6") if role == 2 else Color(0.5, 0.8, 1.0))
	preload("res://scripts/combat_fx.gd").impact(self, muzzle, muzzle_col, 0.35, 6)
	if role == 1:
		_arc_beam(muzzle, end_pt, Color("#38bdf8"))
	elif role == 2:
		var side := dir.cross(Vector3.UP)
		side = side.normalized() * 0.09 if side.length() > 0.01 else Vector3(0.09, 0, 0)
		_tracer(muzzle + side, end_pt + side, Color("#f472b6"))
		_tracer(muzzle - side, end_pt - side, Color("#f472b6"))
	else:
		_tracer(muzzle, end_pt, Color("#ffd29a"))
	if hit_team > 0:
		var impact_point := end_pt
		var headshot: bool = impact_point.y - rivals[hit_team]["actor"].position.y > 1.9
		_damage_rival(hit_team, Sim.field_damage(role, hit_t, headshot) * (1.25 if g.sim.overdrive > 0.0 else 1.0))
		g.sim.metrics["hits"] += 1
		preload("res://scripts/combat_fx.gd").impact(self, end_pt, Sim.faction_color(hit_team), 0.65, 12)
	elif hit_t < 119.5:
		preload("res://scripts/combat_fx.gd").impact(self, end_pt, muzzle_col, 0.4, 8)


func _damage_rival(t: int, dmg: float) -> void:
	var s: Sim = g.sim
	var rv: Dictionary = rivals[t]
	if s.teams[t]["stun"] > 0.0 or dmg <= 0.0: return
	rv["hp"] -= dmg
	hit_flash = 0.16
	g.hud.confirm_hit()
	g.sfx("hitmarker", -6)
	rv["actor"].flash("hit", 0.4)
	if rv["hp"] <= 0.0:
		rv["hp"] = 100.0
		s.teams[t]["stun"] = 6.0
		preload("res://scripts/combat_fx.gd").impact(self, rv["actor"].position + Vector3.UP, Sim.faction_color(t), 1.3, 28)
		if s.drop_flag(t, 3, s.teams[t]["bot_position"]):
			g.hud.toast("%s raider stunned — dropped a Science Flag!" % Sim.FACTIONS[t]["name"])
		else:
			g.hud.toast("%s raider stunned" % Sim.FACTIONS[t]["name"], 1.5)
		s.score += 40
		s.metrics["stuns"] += 1


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
		_crew_walk(a, HATCH + Vector3(-4.5 + i * 3.0, 0, -3.0), dt, 6.0, 1.0)
		a.animate(dt, a.vel.length(), "", false)
		a.vel = Vector3.ZERO
		return
	if i == 3:
		var carried = s.carried_flag(0, 3)
		if carried != null:
			if _crew_walk(a, HATCH, dt, 5.5, 1.5) <= 4.5:
				s.load_flag(0, 3, 2.0)
		elif c["onboard"] + c["carried"] >= s.cargo_capacity:
			_crew_walk(a, HATCH + Vector3(3, 0, -2), dt, 5.5, 0.5)
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
				_crew_walk(a, HATCH + Vector3(3, 0, -2), dt, 5.5, 0.5)
	else:
		var sample = s.carried_flag(0, i)
		if sample != null:
			if _crew_walk(a, HATCH, dt, 5.5, 1.5) <= 4.5: s.load_flag(0, i, 2.0)
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
			for t in rivals:
				var ra: Actor = rivals[t]["actor"]
				if ra.visible and s.teams[t]["stun"] <= 0.0 and a.position.distance_to(ra.position) < best_rd:
					best_rd = a.position.distance_to(ra.position)
					watch_pos = ra.position
			a.face(watch_pos - a.position, dt, 3.0)
		bot_fire[i] -= dt
		if bot_fire[i] <= 0.0:
			bot_fire[i] = 1.3 if i == 2 else 2.2
			for t in rivals:
				var ra: Actor = rivals[t]["actor"]
				if ra.visible and s.teams[t]["stun"] <= 0.0 and a.position.distance_to(ra.position) < 24.0 and _line_clear(a.position + Vector3.UP * 1.6, ra.position + Vector3.UP * 1.3):
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
						_damage_rival(t, 25.0)
					a.face(ra.position - a.position, dt, 30.0)
					break
	var bstep := a.poll_step(dt, a.vel.length())
	if bstep != "" and a.position.distance_to(actors[s.selected].position) < 25.0:
		g.sfx_3d(bstep, a.global_position, -20)
	a.animate(dt, a.vel.length(), work, s.carried_flag(0, i) != null)
	a.vel = Vector3.ZERO


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
		if not vis:
			continue
		var p: Vector3 = team["bot_position"]
		var moved: Vector3 = p - rv["last"]
		rv["last"] = p
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
				_tracer(aim_start, aim_end + (Vector3.ZERO if hit else Vector3(rng.randf_range(-2, 2), 1.4, 0)), Sim.faction_color(t))
				if hit:
					if s.shield > 0.0:
						g.sfx("shield_hit", -8)
					else:
						last_hit[s.selected] = 6.0
						field_hp -= 9.0 * s.armor_mult * Sim.DIFFICULTY[s.difficulty]["damage"]
						me.flash("hit", 0.28)
						preload("res://scripts/combat_fx.gd").impact(self, me.position + Vector3.UP * 1.4, Color("#f56d65"), 0.6, 10)
						g.hud.hurt(0.3)
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


func _visuals(dt: float) -> void:
	var s: Sim = g.sim
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
				var stage_col: Color = [Color("#38bdf8"), Color("#f7ce59"), Color("#34d399")][mini(2, f["stage"])] if frac > 0.0 else CRYSTAL
				cr.position = Vector3(0, 2.6 + sin(t * 2.0 + f["id"]) * 0.15 + frac * 1.2, 0)
				cr.rotation.y += dt * (1.0 + frac * 8.0)
				fn["ring"].position = Vector3(0, 0.15, 0)
				fn["ring"].scale = Vector3(1.0 + frac * 1.5, 0.05, 1.0 + frac * 1.5)
				fn["ring"].material_override = Gfx.unshaded(stage_col, 0.75 if frac > 0.0 else 0.45)
				fn["label"].position = Vector3(0, 4.6, 0)
				fn["label"].modulate = stage_col
				fn["label"].text = "FLAG %d" % (f["id"] + 1) if frac <= 0.0 else "%s %d%%" % [["SCAN", "STABILIZE", "EXTRACT"][mini(2, f["stage"])], int(frac * 100)]
				if f["scanner"] != null:
					col = Sim.faction_color(f["scanner"]).lerp(CRYSTAL, 0.4)
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
				cr.position = f["position"] - site + Vector3(0, 0.7, 0)
				cr.rotation.y += dt * 2.0
				fn["label"].position = f["position"] - site + Vector3(0, 2.0, 0)
				fn["label"].modulate = Color("#ffffff")
				fn["label"].text = "◆ DROPPED FLAG %d" % (f["id"] + 1)
				col = Color("#ffffff")
			"carried":
				var flag_team: int = f["owner"]
				col = Sim.faction_color(flag_team)
				if flag_team == 0:
					cr.position = actors[f["carrier"]].position - site + Vector3(0, 3.4, 0)
				elif rivals.has(flag_team):
					cr.position = rivals[flag_team]["actor"].position - site + Vector3(0, 3.4, 0)
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
			hatch_beacon.text = "▲ READY TO DEPART [T] (%d/%d)" % [counts["onboard"], s.cargo_capacity] if counts["carried"] == 0 else "▲ LOAD SAMPLE [E] (%d/%d)" % [counts["onboard"], s.cargo_capacity]
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
		CombatFX.impact(self, HATCH + Vector3(0, 1.5, 0), ACCENT.lerp(Color.WHITE, 0.4), 2.2, 32)
		CombatFX.ring_pulse(self, HATCH + Vector3(0, 0.2, 0), ACCENT, 9.0, 0.55)
	elif st == "ground" and prev == "carried":
		CombatFX.impact(self, at, Color.WHITE, 1.2, 16)
		CombatFX.ring_pulse(self, Vector3(at.x, 0.2, at.z), Color.WHITE, 3.5, 0.35)

func hud_update(hud: Hud) -> void:
	var s: Sim = g.sim
	var c := s.flag_counts(0)
	var r := s.selected
	hud.title.text = "FRONTIER / MOON"
	hud.subtitle.text = "A STORAGE  ·  B REACTOR  ·  C RELAY"
	var cells := ""
	for slot in s.cargo_capacity: cells += "■ " if slot < c["onboard"] else "□ "
	hud.objectives.text = "[color=#eaa665]SAMPLES  %d / %d[/color]\n%s\n\n[color=#7cd8df]◆ %d available[/color]   ◇ %d loose" % [c["onboard"], s.cargo_capacity, cells, c["sites"], c["loose"]]
	hud.vitals_panel.visible = true
	var weap := "SCIENTIFIC SCANNER" if r == 3 else ("B  DRAW WEAPON · HANDS FREE" if not actors[r].weapon_drawn else "%s  %d / 24%s" % [Sim.SPECIALISTS[r]["weapon"].to_upper(), ammo, "  RELOADING" if reload_t > 0.0 else ""])
	hud.vitals.text = "[color=#b4a8c6]FIELD STATUS · %s[/color]\nSUIT [color=%s]%d%%[/color]   SHIELD %s\n%s\nSKILL Q %s · ULT F %d%%\nSHIP HULL %d%% · PROPELLANT %.1f kg" % [
		Sim.SPECIALISTS[r]["name"], "#ed7d8d" if field_hp < 35.0 else "#f3eef8", int(field_hp), "ON" if s.shield > 0.0 else "—", weap,
		"READY" if s.ability_cd[r] <= 0.0 else "%.0fs" % s.ability_cd[r], int(s.ultimate[r]), int(s.hull), s.propellant]
	hud.field_status(field_hp, ammo, reload_t, actors[r].weapon_drawn, r, s, down_t)
	hud.station_panel.visible = false
	hud.crosshair.visible = r == 3 or actors[r].weapon_drawn
	hud.footer.text = "B EQUIP    C ORDERS    Z PING    M MAP    H HELP"
	hud.radar_title.text = "MOON · SURFACE"
	for i in 4:
		var st := ("REGROUPING" if s.crew_order == "regroup" else ("EXTRACTING" if i == 3 else "ESCORTING"))
		if down_times[i] > 0.0: st = "RECOVERING"
		if s.carried_flag(0, i) != null:
			st = "CARRYING FLAG"
		hud.set_crew_status(i, st + (" · YOU" if i == r else " · BOT"), s.ultimate[i] / 100.0)
	var me: Actor = actors[r]
	var pts: Array = []
	var rot: float = g.yaw
	var add := func(p: Vector3, col: Color, size: float, ring: bool, label: String):
		var offset := p - me.position
		pts.append({"p": Vector2(offset.x, offset.z).rotated(rot), "c": col, "s": size,
			"ring": ring, "label": label, "dist": offset.length()})
	for i in 4:
		var bay = Sim.LANDING_BAYS[i]
		var label := "YOUR BAY" if i == 0 else "%s BAY" % Sim.FACTIONS[i]["name"]
		add.call(Vector3(bay[0], 0, bay[1]), Sim.faction_color(i), 6.0, true, label)
	if hatch_beacon.visible:
		add.call(HATCH, ACCENT, 4.5, true, "CARGO HATCH")
	for f in s.flags:
		if f["planet"] != "B":
			continue
		var label := "SAMPLE %02d" % (f["id"] + 1)
		if f["state"] == "site":
			add.call(f["position"], CRYSTAL, 3.0, false, label)
		elif f["state"] == "ground":
			add.call(f["position"], Color.WHITE, 3.5, true, label)
	for t in rivals:
		if rivals[t]["actor"].visible:
			add.call(rivals[t]["actor"].position, Sim.faction_color(t), 3.5, false, Sim.FACTIONS[t]["name"])
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
	hud.update_tactical(pts, "MOON · LIVE TACTICAL MAP", 95.0)
	if s.priority_flag >= 0:
		hud.advisor.text = "◆ Priority sample %02d" % (s.priority_flag + 1)


func _build_first_person() -> void:
	first_person_rig = Node3D.new()
	first_person_rig.name = "FirstPersonHands"
	add_child(first_person_rig)
	for role in 3:
		var holder := Node3D.new()
		first_person_rig.add_child(holder)
		var firearm: Node3D = actors[role].held_weapon.duplicate()
		firearm.visible = true
		var view_bounds := [null]
		Actor._aabb(firearm, Transform3D.IDENTITY, view_bounds)
		firearm.scale *= 0.8 / maxf(0.05, (view_bounds[0] as AABB).size.z)
		firearm.position = Vector3(0.22, -0.32, -0.78)
		holder.add_child(firearm)
		for side in [-1, 1]:
			var elbow := Vector3(side * 0.46, -0.76, -0.04)
			var hand := Vector3(0.25 if side > 0 else -0.03, -0.39, -0.62 if side > 0 else -0.93)
			var direction := hand - elbow
			var sleeve := Gfx.cyl(0.075, direction.length(), Color("#d1d9d8"), (elbow + hand) * 0.5, 10)
			var up := direction.normalized()
			var right := Vector3.RIGHT.cross(up).normalized()
			sleeve.basis = Basis(right, up, right.cross(up))
			holder.add_child(sleeve)
			var glove := Gfx.sphere(0.085, Color("#29383f"), hand, 0.0, 10)
			glove.scale = Vector3(0.8, 0.85, 1.25)
			holder.add_child(glove)
		first_person_models.append(holder)

func _first_person_tick() -> void:
	var role: int = g.sim.selected
	first_person_rig.visible = g.first_person and role != 3 and down_t <= 0.0
	if not first_person_rig.visible: return
	var a: Actor = actors[role]
	first_person_rig.global_transform = g.cam.global_transform
	for i in 3:
		first_person_models[i].visible = i == role and a.weapon_blend > 0.01
	var hands: Node3D = first_person_models[role]
	hands.position = Vector3(0, -(1.0 - smoothstep(0.0, 1.0, a.weapon_blend)) * 0.7, a.weapon_recoil)
	hands.rotation.z = sin(clampf(a.weapon_reload / 1.3, 0.0, 1.0) * PI) * -0.35
