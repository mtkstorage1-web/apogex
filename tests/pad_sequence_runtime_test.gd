extends SceneTree

const Interior := preload("res://scripts/ship_interior.gd")

var failures := 0
var settings_path := "user://pad-sequence-test-%d.cfg" % OS.get_process_id()

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

# Manual crane: E pickup from the GSE bay (forgiving radius), E place on the
# ship slot, and an arm-mounted front camera instead of a sky view.
func _check_manual_crane(g, w, a: Actor) -> void:
	var role: int = g.sim.selected
	a.position = w._crane_station(role)
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	g.pressed_now.clear()
	check(w.crane_mode and w.crane_role == role, "E at the console enters crane mode")
	w.crane_enter_frame = -1
	for i in 1200:
		if w._gse_ready_part(role) != null:
			break
		w._tick_gse_delivery(0.05)
	var pickup = w._gse_ready_part(role)
	check(pickup != null, "GSE delivers a module to the crane bay")
	if pickup == null:
		return
	var arm: Dictionary = w.fx_arms[role]
	var bay: Vector3 = w._gse_point(role, 1.0)
	_check_crane_hoist_and_wasd(g, w, role, arm, pickup)
	# Park the claw high and 2.5 m off the bay centre: what a player sees as "over the bay".
	arm["target"] = Vector3(bay.x + 2.0, 10.0, bay.z + 1.5)
	g._process(0.05)
	check(g.hud.prompt_title.text.begins_with("PRESS E TO PICK UP"), "claw near the bay shows PRESS E TO PICK UP")
	var pose: Dictionary = w.crane_camera_pose()
	var cam_local: Vector3 = w.to_local(pose["pos"])
	var claw: Vector3 = arm["target"]
	var forward: Vector3 = w._crane_arm_forward(role)
	var look: Vector3 = w.to_local(pose["target"]) - cam_local
	check(cam_local.y <= PlanetA.ELEVATOR_HEIGHT + 4.0 and Vector2(cam_local.x - claw.x, cam_local.z - claw.z).length() <= 12.0,
		"crane camera is a low arm-mounted front view near the claw (not sky-high)")
	check(Vector2(look.x, look.z).normalized().dot(Vector2(forward.x, forward.z)) > 0.8 and look.y < 0.0,
		"crane camera looks forward along the arm toward the claw")
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	g.pressed_now.clear()
	check(g.sim.carry[role] == pickup["id"] and pickup["stage"] == "carried", "E grabs the module from the GSE bay")
	var claw_tip: Node3D = arm["tip"]
	check(claw_tip.position.is_equal_approx(w._gse_pickup_grip(role, pickup["id"])),
		"claw meets the scaled module at its pickup grip")
	var grip: Vector3 = w._crane_placement_grip(pickup)
	arm["target"] = Vector3(grip.x + 1.8, grip.y + 6.0, grip.z - 1.2)
	for i in 20:
		g._process(0.05)
	check(g.hud.prompt_title.text.begins_with("PRESS E TO SNAP & LOCK"), "claw near the ship slot shows PRESS E TO SNAP & LOCK")
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	g.pressed_now.clear()
	check(g.sim.carry[role] == null and pickup["stage"] in ["positioned", "secured"], "E places the module on the ship slot")
	var installed: Node3D = w.slot_nodes[pickup["id"]]["node"]
	var carried: Node3D = w.gse_modules[pickup["id"]]["node"].get_child(0)
	check(claw_tip.position.is_equal_approx(grip)
		and carried.basis.is_equal_approx(installed.global_basis)
		and w.to_global(grip - (w.gse_modules[pickup["id"]]["grip"] as Vector3)).is_equal_approx(installed.global_position),
		"claw snaps the full-size module onto the scaled slot")
	w.exit_crane_mode()

func _hold(action: String, g, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		g._process(0.05)
	Input.action_release(action)


func _has_torus(root: Node) -> bool:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh is TorusMesh:
		return true
	for child in root.get_children():
		if _has_torus(child):
			return true
	return false


# Vertical hoist (SPACE up / SHIFT down) and WASD horizontal steering, with a
# straight-down drop-line visual instead of a circular ring.
func _check_crane_hoist_and_wasd(g, w, role: int, arm: Dictionary, pickup) -> void:
	var low: float = w._gse_pickup_grip(role, pickup["id"]).y
	# Start away from the bay so the pickup magnet doesn't pull the claw sideways.
	arm["target"] = Vector3(arm["base"].x, 12.0, arm["base"].z) + w._crane_arm_forward(role) * 12.0
	g._process(0.05)
	check(not w._claw_over_bay(arm["target"], w._gse_point(role, 1.0)), "hoist test starts clear of the GSE bay")
	check(w.crane_marker.visible and w.crane_drop_foot.visible and w.crane_height_label.visible,
		"crane mode shows the vertical hoist drop-line, foot reticle and height readout")
	check(not (w.crane_marker.mesh is TorusMesh) and not _has_torus(w.crane_target_marker) and not _has_torus(w.crane_drop_foot),
		"crane pickup visuals no longer use circular ring markers")
	var claw: Vector3 = arm["target"]
	var line: Vector3 = w.crane_marker.position
	check(is_equal_approx(line.x, claw.x) and is_equal_approx(line.z, claw.z) and line.y < claw.y and w.crane_marker.scale.y > 1.0,
		"drop-line hangs straight down from the claw")
	var y0: float = claw.y
	_hold("jump", g, 10)
	var y1: float = (arm["target"] as Vector3).y
	check(y1 > y0 + 1.0, "SPACE hoists the claw UP (%.2f -> %.2f)" % [y0, y1])
	check(is_equal_approx((arm["target"] as Vector3).x, claw.x) and is_equal_approx((arm["target"] as Vector3).z, claw.z),
		"hoisting is purely vertical")
	var drop_hi: float = w.crane_drop_distance
	_hold("sprint", g, 10)
	var y2: float = (arm["target"] as Vector3).y
	check(y2 < y1 - 1.0 and w.crane_drop_distance < drop_hi, "SHIFT lowers the claw DOWN and the drop readout shrinks")
	_hold("sprint", g, 200)
	check((arm["target"] as Vector3).y >= low - 0.01, "claw can't be lowered below the safe grip height")
	_hold("jump", g, 400)
	check((arm["target"] as Vector3).y <= maxf(PlanetA.CRANE_HOIST_TOP, low + PlanetA.CRANE_HOIST_SPAN) + 0.01,
		"claw can't be hoisted above the ceiling")
	var before: Vector3 = arm["target"]
	var forward: Vector3 = w._crane_arm_forward(role)
	_hold("move_forward", g, 6)
	var after: Vector3 = arm["target"]
	var delta := Vector2(after.x - before.x, after.z - before.z)
	check(delta.length() > 0.5 and delta.normalized().dot(Vector2(forward.x, forward.z).normalized()) > 0.8
		and is_equal_approx(after.y, before.y), "W extends the claw horizontally along the boom without changing height")
	before = after
	_hold("move_right", g, 6)
	after = arm["target"]
	check(Vector2(after.x - before.x, after.z - before.z).length() > 0.5 and is_equal_approx(after.y, before.y),
		"D slews the claw sideways in the XZ plane")


func _board_via_ramp(g, crew: Actor) -> bool:
	for i in 40:
		if g.boarding_ramp != null and g.boarding_ramp.is_deployed():
			break
		g._process(0.05)
	crew.position = g.cockpit_position()
	crew.move_vel = Vector3.ZERO
	crew.vy = 0.0
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


func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var g = load("res://main.tscn").instantiate()
	g.settings_path = settings_path
	root.add_child(g)
	g.set_process(false)
	var old_mode := LobbyPages.play_mode
	LobbyPages.play_mode = "practice"
	g.start_match()
	check(g.mode == "play", "Match starts with direct control at the pad")
	var w = g.world
	for p in g.sim.parts: g.sim.buy_part(p["id"])
	var a: Actor = w.actors[g.sim.selected]
	a.position = w._lift_seat(g.sim.selected)
	g.pressed_now[KEY_E] = true
	g.lmb = true
	w._shop_interact(a)
	g.pressed_now.clear()
	check(w.lift_state == PlanetA.LiftState.BOARDING and w.pad_stage == "build"
		and g.mode == "play", "crane elevator starts assembly in play mode")
	check(g.lmb, "boarding the crane elevator preserves mouse controls")
	for i in 240:
		if w.lift_state == PlanetA.LiftState.DECK:
			break
		g._process(0.05)
	check(w.lift_state == PlanetA.LiftState.DECK, "crew reaches the crane deck")
	_check_manual_crane(g, w, a)
	# Finish the modules through the sim's bulk assembly path so this test can focus on pad sequences.
	g.sim.auto_build["enabled"] = true
	check(g.sim.auto_assemble(Sim.AUTO_BUILD_SECONDS) and g.sim.secured_count() == 12,
		"assembly fixture secures all modules")
	a.position = w._lift_seat(g.sim.selected)
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	check(w.lift_state == PlanetA.LiftState.RETURN_BOARDING, "completed crew can board the elevator down")
	for i in 240:
		if w.lift_state == PlanetA.LiftState.PARKED:
			break
		g._process(0.05)
	check(w.pad_stage == "ready" and g.mode == "play",
		"returning to the pad makes the ship ready for boarding")
	for kind in ["build", "outfit"]:
		g.yaw = 0.7
		g.pitch = -0.3
		g.follow_cam(a)
		var camera_before: Transform3D = g.cam.transform
		g.hud.set_prompt("UNRELATED INTERACTION")
		w.cine(kind, 0.3, 0.05)
		check(g.cam.transform.is_equal_approx(camera_before), kind + " preserves player camera")
		check(a.visible, kind + " preserves actor visibility")
		check(g.hud.prompt_title.text == "UNRELATED INTERACTION", kind + " preserves unrelated prompts")
	g.pressed_now[KEY_SPACE] = true
	g._process(0.05)
	check(a.position.y > 0.0, "player can jump on the finished pad")
	g.pressed_now[KEY_V] = true
	g._process(0.05)
	check(g.first_person, "view controls work on the ready pad")
	check(w.ship_root.transform.is_equal_approx(Transform3D(Basis.from_scale(Vector3.ONE * 1.45), Vector3.ZERO)),
		"Fully built ship stays horizontal on the pad at its original scale")
	check(g.universe.find_children("FlightBooster*", "", true, false).is_empty(), "Full build creates no FlightBooster nodes")
	var hull: Node3D = w.ship_root.get_node("keel")
	check(hull.is_visible_in_tree(), "Pad ship has its exterior hull before boarding")
	var boarded := _board_via_ramp(g, a)
	check(boarded and g.mode == "play" and g.vessel.grounded and not hull.is_visible_in_tree()
		and g.vessel.ship.get_node("keel").is_visible_in_tree(),
		"Ramp boarding and cockpit E transfer control to the grounded ship and restore its exterior hull")
	if not boarded:
		_finish(g, old_mode)
		return
	var flight: Flight = g.vessel
	var u: Universe = g.universe
	check(u.shell_a.get_parent() == u.body_a and u.shell_a.mesh.radius > u.body_a.mesh.radius
		and u.shell_a.material_override is ShaderMaterial, "Earth has a larger concentric atmosphere shell")
	check(not u.body_c.has_node("Atmosphere"), "Moon has no atmosphere shell")
	g._swap_flight_location("space")
	check(u.body_a.global_position.distance_to(u.body_c.global_position) == Universe.DIST,
		"Planet centers are 30,000 m apart")
	check(u.body_a.visible and u.body_b.visible and u.body_c.visible and not u.env.fog_enabled,
		"All three bodies are visible in space without atmospheric fog")
	check(flight.ship.scale.is_equal_approx(Vector3.ONE * 1.45) and flight.ship.is_visible_in_tree(),
		"The spacecraft remains visible with the same uniform scale")
	var clearance_a: float = g.cam.global_position.distance_to(u.body_a.global_position) - (u.body_a.mesh as SphereMesh).radius
	var clearance_c: float = g.cam.global_position.distance_to(u.body_c.global_position) - (u.body_c.mesh as SphereMesh).radius
	check(clearance_a > g.cam.near and clearance_c > g.cam.near, "Both bodies clear the camera near plane")
	var paused_at := flight.position
	g.pause()
	g._process(2.0)
	check(flight.position == paused_at, "Pausing freezes the ship")
	await check_settings(g)
	g.resume()
	await _check_flight_interior(g)

	var initial_distance := flight.position.distance_to(Universe.C_ORIGIN)
	flight.basis = Basis.looking_at((Universe.C_ORIGIN - flight.position).normalized())
	_hold("move_forward", g, 120)
	check(flight.position.distance_to(Universe.C_ORIGIN) < initial_distance, "Moon grows in angular size with approach")
	g._swap_flight_location("planet_c")
	flight.position = Universe.C_ORIGIN + flight.landing_zone + Vector3.UP * 15.0
	# Sample the fast VTOL before it climbs beyond the regolith emission zone.
	_hold("jump", g, 1)
	u.tick(0.05)
	check(u.moon_dust.emitting and not u.env.fog_enabled, "Vertical thrust raises local regolith without atmospheric fog")
	flight.touch_down(flight.landing_zone)
	u.tick(0.05)
	check(not u.moon_dust.emitting, "Lunar thruster dust stops on touchdown")
	_finish(g, old_mode)


func _finish(g, old_mode: String) -> void:
	LobbyPages.play_mode = old_mode
	g.free()
	DirAccess.remove_absolute(settings_path)
	print("PAD_SEQUENCE_RESULT: %d failures" % failures)
	quit(1 if failures else 0)


func _check_cabin_geometry(interior: Node3D) -> void:
	var constants: Dictionary = interior.get_script().get_script_constant_map()
	check(is_equal_approx(constants["CABIN_W"], 9.2) and is_equal_approx(constants["CABIN_H"], 4.6)
		and is_equal_approx(constants["Z_AFT"] - constants["Z_NOSE"], 24.0)
		and interior.global_basis.get_scale().is_equal_approx(Vector3.ONE),
		"cabin measures 9.2 m by 4.6 m by 24 m at human scale")
	for facility in ["PilotSeat", "FlightYoke", "PilotDashboard", "GunnerSeat", "ShootingConsole", "GunnerComputers",
			"ReactorConsole", "ScienceHolotable", "WorkshopBench", "EngineConsole"]:
		check(interior.find_child(facility, true, false) != null, "cabin facility present: " + facility)
	var ceiling := false
	var forward_panes := 0
	var angled_panes := 0
	for node in interior.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var bounds := mesh.get_aabb()
		var cabin_transform := interior.global_transform.affine_inverse() * mesh.global_transform
		var center := cabin_transform * bounds.get_center()
		var material := mesh.get_active_material(0)
		if center.y >= 4.6 and bounds.size.x >= 9.2 and bounds.size.z >= 24.0:
			ceiling = ceiling or (material is ShaderMaterial
				and material.shader == preload("res://assets/shaders/industrial.gdshader")) \
				or (material is BaseMaterial3D and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
		if center.z < -14.0 and material is BaseMaterial3D \
				and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and material.albedo_color.a < 0.5 and bounds.size.y >= 1.0:
			forward_panes += 1
			if absf(cabin_transform.basis.x.z) > 0.3:
				angled_panes += 1
	check(ceiling, "an opaque ceiling spans the enclosed cabin")
	check(forward_panes >= 3 and angled_panes >= 2, "the cockpit has transparent center and angled panoramic window panes")


# [I] / Tab steps inside the live spacecraft during flight; room tasks change real sim state; the cockpit returns outside.
# Advances frames while keeping the short test flight from reaching its destination.
func _run(g, frames: int) -> void:
	for i in frames:
		g._process(0.05)


func _check_flight_interior(g) -> void:
	var s: Sim = g.sim
	var hull: Node3D = g.world.ship.get_node("keel")
	var sel: int = s.selected
	var ft0: float = s.flight_time
	g.pressed_now[KEY_I] = true
	g._process(0.05)
	check(g.interior_active(), "[I] steps inside the spacecraft during flight")
	check(not hull.is_visible_in_tree(), "flight interior cuts away the exterior hull")
	_check_cabin_geometry(g.interior)
	check(g.interior.stations.size() == 7 and g.interior.stations.has("gunnery"), "Authored interior retains its seven stations")
	_run(g, 20)
	check(s.flight_time > ft0 and g.world is Flight, "flight keeps simulating while the player is inside")
	var st: Dictionary = g.interior.STATION_POS
	var pl: Actor = g.interior.crew[sel]
	g.yaw = 0.0
	_hold("move_forward", g, 14)
	var cockpit_z := pl.position.z
	_hold("move_back", g, 94)
	check(g.player_actor() == pl and pl.visible and pl.position.z - cockpit_z > 14.0
		and g.interior.room_at(pl.position) == "engine_bay", "movement input walks from the cockpit to the engine bay")
	var hull0 := 40.0
	s.hull = hull0
	pl.position = st["workshop"] + Vector3(0, 0, 0.4)
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	_run(g, 90)
	check(s.hull > hull0 + 10.0 and g.interior.stations["workshop"]["cd"] > 0.0, "Workshop task patches the hull")
	s.reactor = 40.0
	pl.position = st["power_room"] + Vector3(0, 0, 0.4)
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	_run(g, 70)
	check(s.reactor > 45.0, "Power Room task boosts the reactor")
	s.co2 = 3000.0
	pl.position = st["life_support"] + Vector3(0, 0, 0.4)
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	_run(g, 70)
	check(s.co2 < 2500.0, "Life Support task scrubs CO2")
	pl.position = st["engine_bay"] + Vector3(0, 0, 0.4)
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	_run(g, 80)
	check(s.boost > 0.0, "Engine Bay task grants a temporary speed boost")
	Flight.ship_shield = 10.0
	pl.position = st["lab"] + Vector3(0, 0, 0.4)
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	_run(g, 80)
	check(Flight.ship_shield >= Flight.SHIELD_MAX - 1.0, "Lab task overcharges the shields")
	pl.position = st["cockpit"] + Vector3(0, 0, -0.4)
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	check(not g.interior_active() and g.world is Flight, "Cockpit E returns to the exterior flight view")
	check(hull.is_visible_in_tree(), "leaving the flight cabin restores the exterior hull")
	g.pressed_now[KEY_TAB] = true
	g._process(0.05)
	check(g.interior_active(), "TAB steps back inside")
	g.pressed_now[KEY_I] = true
	g._process(0.05)
	check(not g.interior_active(), "[I] returns to the exterior flight view")
	check(hull.is_visible_in_tree(), "reopening and closing the cabin restores the hull again")


func click_setting(g, prefix: String) -> bool:
	for child in g.menu_root.find_children("*", "Button", true, false):
		if child.text.begins_with(prefix):
			child.pressed.emit()
			return true
	return false


func setting_control(g, title: String, control_type: String) -> Control:
	for label in g.menu_root.find_children("*", "Label", true, false):
		if label.text == title:
			var row: Node = label.get_parent().get_parent()
			var controls := row.find_children("*", control_type, true, false)
			if not controls.is_empty():
				return controls[0]
	return null


func settle_graphics(g) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while g._graphics_applying and Time.get_ticks_msec() < deadline:
		await process_frame
	if g._graphics_applying:
		check(false, "graphics apply completes within 10 seconds")


func check_settings(g) -> void:
	await settle_graphics(g)
	check(g.graphics.quality == 2 and Engine.max_fps == 60, "first launch defaults to High and 60 FPS")
	check(click_setting(g, "ALL SETTINGS") and g.settings_open, "pause opens Settings")
	check(click_setting(g, "GRAPHICS") and g.graphics_open, "pause Settings opens Graphics")
	var renderer: StringName = g.graphics.renderer()
	var supports_fxaa := renderer != &"gl_compatibility"
	var supports_taa := renderer == &"forward_plus" and OS.get_name() != "macOS"
	for preset: int in [3, 0, 1, 2, 3]:
		var clicked := click_setting(g, "PRESET")
		await settle_graphics(g)
		var expect_fxaa := supports_fxaa and (preset == 1 or (preset == 3 and not supports_taa))
		check(clicked and g.graphics.quality == preset
			and root.msaa_3d == (Viewport.MSAA_4X if preset == 2 else Viewport.MSAA_DISABLED)
			and root.screen_space_aa == (Viewport.SCREEN_SPACE_AA_FXAA if expect_fxaa else Viewport.SCREEN_SPACE_AA_DISABLED)
			and root.use_taa == (preset == 3 and supports_taa)
			and is_equal_approx(root.scaling_3d_scale, [0.67, 0.85, 1.0, 1.0][preset])
			and g.universe.sun.shadow_enabled == (preset >= 1) and g.universe.env.glow_enabled == (preset >= 1),
			"pause quality button applies preset %d" % preset)
	for limit in [120, 144, 0, 30, 60, 120]:
		var clicked := click_setting(g, "FPS LIMIT")
		await settle_graphics(g)
		check(clicked and g.graphics.values["fps_limit"] == limit
			and g.graphics.quality == 4 and Engine.max_fps == limit, "pause FPS button applies %d" % limit)
	check(click_setting(g, "CONTROLS") and g.settings_tab == "controls", "pause Settings opens Controls")
	var sensitivity := setting_control(g, "LOOK SENSITIVITY", "HSlider") as HSlider
	check(sensitivity != null, "Controls contains the look sensitivity slider")
	if sensitivity:
		sensitivity.value = 1.5
	check(click_setting(g, "AUDIO") and g.settings_tab == "audio", "pause Settings opens Audio")
	var volume := setting_control(g, "MASTER VOLUME", "HSlider") as HSlider
	check(volume != null, "Audio contains the master volume slider")
	if volume:
		volume.value = 50.0
	check(click_setting(g, "GAME") and g.settings_tab == "game", "pause Settings opens Game")
	var motion := setting_control(g, "REDUCED MOTION", "Button") as Button
	check(motion != null, "Game contains the reduced motion toggle")
	if motion:
		motion.pressed.emit()
	await process_frame
	check(click_setting(g, "BACK") and not g.settings_open, "Back closes Settings and returns to Pause")
	check(g.mode == "paused" and g.paused_from == "play", "cycling keeps free flight paused")
	var reload = load("res://main.tscn").instantiate()
	reload.settings_path = settings_path
	root.add_child(reload)
	await settle_graphics(reload)
	check(reload.graphics.quality == 4 and reload.graphics.values["fps_limit"] == 120 and Engine.max_fps == 120,
		"new Main loads saved graphics and FPS from user settings")
	check(is_equal_approx(reload.sens, 1.5) and reload.volume_percent() == 50.0 and UI.reduced_motion,
		"new Main loads existing controls, audio and motion settings")
	check(click_setting(reload, "SETTINGS"), "home opens Settings")
	check(click_setting(reload, "GRAPHICS"), "home Settings opens Graphics")
	var clicked_preset := click_setting(reload, "PRESET")
	await settle_graphics(reload)
	check(clicked_preset and reload.graphics.quality == 0 and Engine.max_fps == 60,
		"home settings cycles CUSTOM to LOW and resets the FPS limit")
	var clicked_fps := click_setting(reload, "FPS LIMIT")
	await settle_graphics(reload)
	check(clicked_fps and reload.graphics.values["fps_limit"] == 120 and Engine.max_fps == 120,
		"home settings cycles FPS")
	reload.free()
	g._load_settings()
	await settle_graphics(g)
