extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "Apogex-tests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var user_dir := ProjectSettings.globalize_path("user://")
	if DirAccess.make_dir_recursive_absolute(user_dir) != OK:
		push_error("Could not create isolated test settings directory")
		quit(1)
		return
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	g.start_match()
	check(g.mode == "cine", "intro keeps cinematic mode")
	g._end_cine("intro")
	var w = g.world
	for p in g.sim.parts: g.sim.buy_part(p["id"])
	var a: Actor = w.actors[g.sim.selected]
	a.position = w.SHOP_DESK
	g.pressed_now[KEY_E] = true
	g.lmb = true
	w._shop_interact(a)
	g.pressed_now.clear()
	check(w.pad_stage == "build" and g.mode == "play" and g.pad_sequence_active(), "desk starts build in play mode")
	check(g.lmb, "starting pad sequence does not release mouse controls")
	g._process(0.05)
	var elapsed: float = g.cine["t"]
	g.pressed_now[KEY_E] = true
	w._shop_interact(a)
	g.pressed_now.clear()
	check(g.cine["t"] == elapsed, "shop cannot restart active build")
	check(g.sim.auto_build["t"] > 0.0, "auto assembly advances in play mode")
	for kind in ["build", "outfit", "erect", "boosters"]:
		g.yaw = 0.7
		g.pitch = -0.3
		g.follow_cam(a)
		var camera_before: Transform3D = g.cam.transform
		g.hud.set_prompt("UNRELATED INTERACTION")
		w.cine(kind, 0.3, 0.05)
		check(g.cam.transform.is_equal_approx(camera_before), kind + " preserves player camera")
		check(a.visible, kind + " preserves actor visibility")
		check(g.hud.prompt_title.text == "UNRELATED INTERACTION", kind + " preserves unrelated prompts")
	for i in 470: g._process(0.05)
	check(w.pad_stage == "erect_wait" and not g.pad_sequence_active(), "build and outfit finish without blocking play")
	check(g.sim.secured_count() == 12 and g.sim.all_cargo_stowed(), "automated assembly and outfit complete")
	g.pressed_now[KEY_SPACE] = true
	g._process(0.05)
	check(a.position.y > 0.0, "player can jump between sequences")
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	check(w.pad_stage == "erecting" and g.mode == "play", "E starts erect from play mode")
	g.pressed_now[KEY_V] = true
	g._process(0.05)
	check(g.first_person, "view controls work during erect")
	a.position.y = 0.0
	g.pressed_now[KEY_SPACE] = true
	g._process(0.05)
	check(a.position.y > 0.0, "player can jump during erect")
	g.pause()
	var paused_t: float = g.cine["t"]
	g._process(0.05)
	check(g.cine["t"] == paused_t, "pause freezes pad sequence")
	g.resume()
	for i in 285: g._process(0.05)
	check(w.pad_stage == "ready" and g.sim.phase == "route" and g.mode == "play", "erect and boosters finish ready for mission desk")
	check(not g.pad_sequence_active(), "completed sequence stops ticking")
	a.position = w.LAUNCH_DESK
	g.pressed_now[KEY_E] = true
	g._process(0.05)
	check(g.mode == "route", "mission desk opens ROUTE after build")
	g._choose_route("sheltered")
	check(g.mode == "gonogo", "route selection opens GO/NO-GO")
	var expected_fuel: float = g.sim.propellant
	g.launch()
	check(g.mode == "cine" and g.cine["kind"] == "launch", "launch enters cinematic")
	expected_fuel -= g.sim.route["outbound"] + g.sim.route["slow_climb"]
	check(is_equal_approx(g.sim.propellant, expected_fuel), "launch charges the route budget once")

	var u: Universe = g.universe
	check(u.shell_a.get_parent() == u.body_a and u.shell_a.mesh.radius > u.body_a.mesh.radius
		and u.shell_a.material_override is ShaderMaterial, "Earth has a larger concentric atmosphere shell")
	check(not u.body_b.has_node("Atmosphere"), "Moon has no atmosphere shell")
	check(u.body_a.global_position.distance_to(u.body_b.global_position) == Universe.DIST, "planet centers are 30,000 m apart")
	g._tick_launch(g.launch_tick_usec + 10000)
	var start_a: float = g.cam.global_position.distance_to(u.body_a.global_position)
	var start_b: float = g.cam.global_position.distance_to(u.body_b.global_position)
	Engine.time_scale = 2.0
	g._tick_launch(g.launch_tick_usec + 19980000)
	check(is_equal_approx(g.cine["t"], 19.99), "ascent clock advances in unscaled play seconds")
	for booster in w.fx_boosters:
		var node: Node3D = booster["node"]
		var attached: Transform3D = w.ship_root.transform * booster["launch_local"]
		check(not booster.has("shed_from") and node.transform.is_equal_approx(attached)
			and node.is_visible_in_tree() and node.get_node("BoosterExhaust").is_visible_in_tree(),
			"%s remains attached and firing at 19.99 s" % node.name)
	g.pause()
	g._process(2.0)
	check(is_equal_approx(g.cine["t"], 19.99), "pausing does not consume booster burn time")
	await check_settings(g)
	g.resume()
	g._tick_launch(g.launch_tick_usec + 20000)
	Engine.time_scale = 1.0
	for booster in w.fx_boosters:
		var node: Node3D = booster["node"]
		check(booster.has("shed_from") and node.is_visible_in_tree() and not node.get_node("BoosterExhaust").visible,
			"%s separates and stops firing at 20.01 s" % node.name)
	g._tick_launch(g.launch_tick_usec + 50000)
	u.tick(0.05)
	for booster in w.fx_boosters:
		var node: Node3D = booster["node"]
		var release: Transform3D = booster["shed_from"]
		check(node.position.distance_to(release.origin) > 0.2, "%s falls away after release" % node.name)
	var clearance_a: float = g.cam.global_position.distance_to(u.body_a.global_position) - u.body_a.mesh.radius
	var clearance_b: float = g.cam.global_position.distance_to(u.body_b.global_position) - u.body_b.mesh.radius
	check(clearance_a > g.cam.near and clearance_b > g.cam.near, "both bodies clear the camera near plane")
	var ship: Vector3 = w.ship_root.global_position
	check(u.body_a.global_position.y < ship.y and u.body_a.global_position.z > ship.z
		and u.body_b.global_position.z < ship.z, "A is below and behind the ship and B is ahead")
	check(g.cam.global_position.distance_to(u.body_a.global_position) > start_a, "A recedes during ascent")
	check(not u.env.fog_enabled, "launch fog clears at altitude")
	check(w.ship_root.is_visible_in_tree(), "the launch vehicle remains visible after the ground fades")
	print("LAUNCH PLANETS: A=%s B=%s camera clearance=%.1f m / %.1f m" % [
		u.body_a.global_position, u.body_b.global_position, clearance_a, clearance_b])
	var remaining_launch: float = g.cine["dur"] - g.cine["t"]
	g._tick_launch(g.launch_tick_usec + ceili((remaining_launch + 0.05) * 1000000.0))
	check(g.world is Flight and g.mode == "play", "ascent hands off to playable Flight")
	check(is_equal_approx(g.sim.propellant, expected_fuel), "staging does not charge the route a second time")
	var f: Flight = g.world
	g.sim.flight_time = g.sim.flight_duration() * 0.5
	f._update_world(0.05)
	f._camera(0.05)
	var closer_b: float = g.cam.global_position.distance_to(u.body_b.global_position)
	var angular_start := asin(u.body_b.mesh.radius / start_b)
	var angular_closer := asin(u.body_b.mesh.radius / closer_b)
	check(angular_closer > angular_start, "Moon grows in angular size with approach")
	print("MOON: angular diameter %.2f° at launch, %.2f° at mid-flight" % [
		rad_to_deg(2.0 * angular_start), rad_to_deg(2.0 * angular_closer)])
	g.sim.flight_time = g.sim.flight_duration()
	f._update_world(0.05)
	f.cine("landing", 0.84, 0.05)
	u.tick(0.05)
	check(u.moon_dust.emitting and not u.env.fog_enabled, "lunar descent raises local regolith without atmospheric fog")
	f.cine("landing", 0.98, 0.05)
	u.tick(0.05)
	check(not u.moon_dust.emitting, "lunar thruster dust stops emitting when the flame cuts off")
	g.free()
	DirAccess.remove_absolute("user://settings.cfg")
	DirAccess.remove_absolute(user_dir)
	print("PAD_SEQUENCE_RESULT: %d failures" % failures)
	quit(1 if failures else 0)


func click_setting(g, prefix: String) -> bool:
	for child in g.menu_root.find_children("*", "Button", true, false):
		if child.text.begins_with(prefix):
			child.pressed.emit()
			return true
	return false


func settle_graphics(g) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while g._graphics_applying and Time.get_ticks_msec() < deadline:
		await process_frame
	if g._graphics_applying:
		check(false, "graphics apply completes within 10 seconds")


func check_settings(g) -> void:
	await settle_graphics(g)
	check(g.graphics.quality == 2 and Engine.max_fps == 60, "first launch defaults to High and 60 FPS")
	check(click_setting(g, "GRAPHICS"), "pause opens Graphics")
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
	check(click_setting(g, "BACK"), "graphics returns to pause")
	check(click_setting(g, "MOUSE SENSITIVITY"), "pause sensitivity can be changed")
	check(click_setting(g, "AUDIO VOLUME"), "pause volume can be changed")
	check(click_setting(g, "REDUCED MOTION"), "pause motion setting can be changed")
	check(g.mode == "paused" and g.paused_from == "cine", "cycling keeps the ascent paused")
	var reload = load("res://main.tscn").instantiate()
	root.add_child(reload)
	await settle_graphics(reload)
	check(reload.graphics.quality == 4 and reload.graphics.values["fps_limit"] == 120 and Engine.max_fps == 120,
		"new Main loads saved graphics and FPS from user settings")
	check(reload.sens == 1.5 and reload.master_volume_db == -6.0 and UI.reduced_motion,
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
