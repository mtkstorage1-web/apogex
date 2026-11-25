extends SceneTree

const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const Interior := preload("res://scripts/ship_interior.gd")

var failures := 0

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.autotest = true
	g.set_process(false)
	g.opts["seed"] = 4545
	var old_mode := LobbyPages.play_mode
	LobbyPages.play_mode = "practice"
	g.quick_deploy()
	check(g.piloting and g.sim.on_surface("planet_a") and g.mode == "play", "quick deploy seats the crew on the pad")
	check(g.sim.all_parts_bought() and g.sim.secured_count() == 12, "quick deploy completes the paid build")
	g._swap_flight_location("space")
	for i in 100: g._process(0.05)
	check(g.sim.flight_time > 4.0 and g.sim.hull > 0.0, "flight sim and HUD run")
	g._swap_flight_location("planet_c")
	g.vessel.touch_down(g.vessel.landing_zone)
	g.disembark_ship()
	var b: PlanetB = g.world
	var ramp: Node3D = g.universe.planet_c.get_node("PlanetBEnvironment/LoadRamp")
	var player_ship: Node3D = g.vessel.ship
	check(b.to_local(ramp.global_position).is_equal_approx(PlanetB.HATCH)
		and b.to_local(player_ship.to_global(Vector3(0, 0, -15.5))).is_equal_approx(PlanetB.HATCH)
		and b.collide(PlanetB.HATCH).is_equal_approx(PlanetB.HATCH),
		"lunar ramp marker and clear interaction point follow the scaled ship")
	_check_suit_colors(b)
	g.sim.selected = 1
	var chip: Actor = b.actors[1]
	var starting_ammo: int = b.ammo
	g.lmb = true
	g._process(0.05)
	check(b.ammo == starting_ammo and not chip.weapon_drawn, "holstered weapon cannot fire")
	g.lmb = false
	g.pressed_now[KEY_B] = true
	g._process(0.05)
	for i in 30:
		g._process(0.02)
		await process_frame
	check(chip.weapon_ready(), "B completes the draw animation")
	check(chip.weapon_grip.get_parent() is BoneAttachment3D, "weapon attached to the real hand bone")
	check(chip.held_weapon.rotation.y == 0.0 and chip.weapon_muzzle.position.z < -0.5, "barrel and muzzle point forward away from the character")
	var minimum_foot := INF
	for foot in chip.ground_feet: minimum_foot = minf(minimum_foot, (chip._transform_from_actor(chip.skeleton) * chip.skeleton.get_bone_global_pose(foot).origin).y)
	check(absf(minimum_foot - 0.06) < 0.04, "Chip animated feet stay grounded")
	var reduced_motion := UI.reduced_motion
	var motion_effects := GraphicsSettings.motion_effects
	UI.reduced_motion = false
	GraphicsSettings.motion_effects = true
	_check_surface_camera(g, b, chip)
	g.lmb = true
	g._process(0.05)
	g.lmb = false
	check(b.ammo < starting_ammo and g.sim.metrics["shots"] > 0, "drawn gun consumes ammo when fired")
	check(g.cam.rotation.x > g.pitch, "weapon recoil kicks the camera on the firing frame")
	for player in g.players:
		player.stop()
		player.stream = null
	g.pressed_now[KEY_R] = true
	g._process(0.05)
	check(_played_stream(g, "reload_click") and not _played_stream(g, "reload_ratchet"), "reload starts with the mag-out click")
	for i in 18: g._process(0.05)
	check(b.reload_t > 0.0 and _played_stream(g, "reload_ratchet"), "mag-in ratchet plays before the reload completes")
	for i in 12: g._process(0.05)
	check(b.ammo == 24, "reload completes and restores magazine")
	check(is_equal_approx(g.cam.rotation.x, g.pitch), "recoil returns to the aim pitch")
	UI.reduced_motion = true
	b.ammo = 1
	g.lmb = true
	g._process(0.05)
	g.lmb = false
	check(b.ammo == 0 and is_equal_approx(b.reload_t, 1.3) and chip.weapon_reload > 0.0,
		"the last round starts the same timed reload and animation")
	check(is_equal_approx(g.cam.rotation.x, g.pitch), "reduced motion suppresses firing camera recoil")
	for i in 30: g._process(0.05)
	UI.reduced_motion = reduced_motion
	GraphicsSettings.motion_effects = motion_effects
	g.pressed_now[KEY_B] = true
	g._process(0.05)
	for i in 12: g._process(0.05)
	check(not chip.weapon_drawn and chip.weapon_blend <= 0.0, "B returns to empty hands")
	b._damage_rival(1, 48.0)
	check(is_equal_approx(b.rivals[1]["hp"], 52.0), "shots reduce rival health")
	b._damage_rival(1, 60.0)
	check(g.sim.teams[1]["stun"] > 0.0 and g.sim.metrics["stuns"] > 0, "lethal damage knocks the rival out")
	b._downed()
	g._process(0.05)
	check(chip.is_downed and b.down_t > 0.0, "player knockout starts a grounded collapse")
	for i in 65: g._process(0.05)
	check(b.down_t <= 0.0 and not chip.is_downed, "player recovers at the ramp after the knockout")
	g.sim.selected = 0
	g.pressed_now[KEY_C] = true
	g._process(0.05)
	check(g.sim.crew_order == "recover", "C orders real teammates")
	g.pressed_now[KEY_Z] = true
	g._process(0.05)
	check(g.sim.priority_flag >= 0, "Z assigns a priority sample")
	g.pressed_now[KEY_M] = true
	g._process(0.05)
	check(g.hud.tactical_panel.visible, "M opens tactical overlay")
	check(b.get_node("FrontierArena").get_child_count() > 100, "tactical arena instantiated with real cover")
	check(not b._line_clear(Vector3(-5, 1.25, 0), Vector3(5, 1.25, 0)) if _cover_fixture(b) else false, "rock cover blocks fire")
	b.blockers.pop_back()
	b.suit_hp[0] = 40.0
	b.last_hit[0] = 0.0
	b._tactics(1.0)
	check(b.suit_hp[0] > 40.0, "suit recovers out of combat")
	g.sim.selected = 1
	b.field_hp = 55.0
	g.sim.selected = 0
	check(b.field_hp != 55.0, "role switching preserves independent suit health")
	g.sim.selected = 0
	g.sim.priority_flag = 10
	for i in 900: g._process(0.05)
	check(g.sim.metrics["loads"] > 0, "AI raider navigates out, extracts, and returns a sample to the ship")
	check(g.sim.metrics["captures"] > 0, "AI raider extracts a sample during the live simulation")
	for frame in 14000:
		if g.sim.teams.slice(1).any(func(team): return team["delivered"] > 0):
			break
		g._process(0.05)
	check(g.sim.teams[1]["delivered"] + g.sim.teams[2]["delivered"] + g.sim.teams[3]["delivered"] > 0, "rivals navigate the arena, load samples, return, and score")
	g.pause()
	check(not g.hud.tactical_panel.visible and g.mode == "paused", "pause closes tactical overlay")
	g.resume()
	check(g.mode == "play", "resume restores gameplay")
	g.sim.finish_match("Runtime test complete")
	g.show_debrief()
	check(g.mode == "debrief", "debrief renders crew telemetry")
	var previous_seed: int = g.sim.match_seed
	g.rematch()
	check(g.sim.match_seed == previous_seed and g.piloting and g.sim.on_surface("planet_a"), "same-seed rematch reseats the pilot on the pad")
	_check_planet_b_stop(g)
	for player in g.players:
		player.stop()
		player.stream = null
	g.streams.clear()
	await create_timer(0.1).timeout
	g.queue_free()
	chip = null
	b = null
	g = null
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	LobbyPages.play_mode = old_mode
	print("Crew match runtime: %d failures" % failures)
	quit(failures)

func _check_planet_b_stop(g) -> void:
	g._swap_flight_location("space")
	g._swap_flight_location("planet_b")
	g.vessel.touch_down(g.vessel.landing_zone)
	var twin: PlanetA = g.world_planet_b
	check(g.world == twin and g.vessel.ship.visible and g.sim.on_surface("planet_b"),
		"Flight lands at the walkable Planet B spaceport")
	g.disembark_ship()
	check(_board_via_ramp(g, twin.actor(g.sim.selected)) and g.sim.on_surface("planet_b"),
		"Ramp boarding and cockpit E seat the pilot in the parked ship on Planet B")


func _board_via_ramp(g, crew: Actor) -> bool:
	for i in 40:
		if g.boarding_ramp != null and g.boarding_ramp.is_deployed():
			break
		g._process(0.05)
	crew.position = g.cockpit_position()
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	if not g._boarding_auto:
		return false
	for i in 160:
		if g.interior_active():
			break
		g._process(0.05)
	if not g.piloting or not g.interior_active():
		return false
	g.interior.actor(g.sim.selected).position = Interior.STATION_POS["cockpit"]
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	return g.piloting and not g.interior_active()


func _check_suit_colors(b: PlanetB) -> void:
	var leader_colors := {}
	for team in range(1, 4):
		var rival: Dictionary = b.rivals[team]
		var colors := _suit_albedos(rival["actor"])
		var matching := _has_team_hue(colors, Sim.faction_color(team))
		for member in rival["squad"]:
			matching = _has_team_hue(_suit_albedos(member["actor"]), Sim.faction_color(team)) and matching
		check(matching, "%s leader and escorts wear their team color" % Sim.FACTIONS[team]["name"])
		for color in colors:
			if _has_team_hue([color], Sim.faction_color(team)):
				leader_colors[color] = true
				break
	check(leader_colors.size() == 3, "rival suit material colors are distinct")
	check(_has_team_hue(_suit_albedos(b.actors[3]), Sim.faction_color(0)), "player suit carries ORANGE team color")

func _suit_albedos(a: Actor) -> Array[Color]:
	var colors: Array[Color] = []
	for instance: MeshInstance3D in a.model.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as BaseMaterial3D
			if material != null:
				colors.append(material.albedo_color)
	return colors

func _has_team_hue(colors: Array, team_color: Color) -> bool:
	for color: Color in colors:
		if color.s > 0.16 and absf(wrapf(color.h - team_color.h, -0.5, 0.5)) < 0.06:
			return true
	return false

func _check_surface_camera(g, b: PlanetB, chip: Actor) -> void:
	var original_position := chip.position
	var original_yaw: float = g.yaw
	chip.position = Vector3(70, 0, 62)
	g.yaw = 0.0
	g._process(0.05)
	var base_fov: float = g.cam.fov
	var base_near: float = g.cam.near
	g.first_person = true
	g._process(0.05)
	var hands: Node3D = b.first_person_models[1]
	check(g.cam.near < base_near and not chip.get_node("Holder").visible and not chip.holstered_weapon.visible,
		"FPV uses close clipping and hides the third-person body and holster")
	check(hands.is_visible_in_tree() and g.cam.is_position_in_frustum(hands.get_node("Sway/LeftHand").global_position) \
		and g.cam.is_position_in_frustum(hands.get_node("Sway/RightHand").global_position) \
		and g.cam.is_position_in_frustum(hands.get_node("Sway/Rifle/Muzzle").global_position),
		"FPV rifle and both gloves stay inside the view")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var saw_step := false
	var saw_roll := false
	for i in 18:
		g._process(0.05)
		saw_step = saw_step or g.sprint_step
		saw_roll = saw_roll or absf(g.cam.rotation.z) > 0.005
	check(g.cam.fov - base_fov > 6.0 and g.cam.fov - base_fov < 8.0 and saw_step and saw_roll,
		"sprinting applies cadence-driven roll and widens the FOV by seven degrees")
	UI.reduced_motion = true
	g._process(0.05)
	check(is_equal_approx(g.cam.fov, base_fov) and is_zero_approx(g.cam.rotation.z), "reduced motion disables sprint camera effects")
	UI.reduced_motion = false
	for i in 18: g._process(0.05)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	g._process(0.05)
	var returning_fov: float = g.cam.fov
	for i in 20: g._process(0.05)
	check(returning_fov > base_fov and absf(g.cam.fov - base_fov) < 0.01, "sprint FOV eases back after releasing sprint")
	var resting_height: float = g.cam.position.y
	chip.position.y = 0.1
	chip.vy = -7.0
	g._process(0.05)
	check(g.landing_impact > 0.0 and g.cam.position.y < resting_height - 0.08, "touchdown causes an immediate camera dip")
	for i in 6: g._process(0.05)
	chip.position = original_position
	g.yaw = original_yaw
	g.first_person = false
	g._process(0.05)
	check(is_equal_approx(g.cam.near, base_near) and chip.get_node("Holder").visible and not b.first_person_rig.visible,
		"third-person view restores clipping and the crew body")

func _played_stream(g, clip: String) -> bool:
	for player in g.players:
		if player.stream == g.streams[clip]:
			return true
	return false

func _cover_fixture(b: PlanetB) -> bool:
	b.blockers.append({"c": Vector2.ZERO, "r": 2.0, "cover": true})
	return true
