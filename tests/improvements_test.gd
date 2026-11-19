extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)

	# 1. Audio streams & 3D audio pool
	var expected_sfx := [
		"shot_carbine", "shot_scatter", "shot_sidearm", "hitmarker", "capture_tick",
		"explosion", "hurt", "shield_recharge", "shield_hit", "shield_break",
		"reload_click", "reload_ratchet", "step_0", "step_1", "step_2", "step_3",
		"ui_click", "ui_hover", "ui_buy", "ui_error", "alarm_warn", "scan_hum", "ability_cast",
	]
	for clip in expected_sfx:
		check(g.streams.has(clip) and g.streams[clip] is AudioStream, "audio stream loaded: " + clip)
	check(g.players.size() == 8 and g.players_3d.size() == 8, "2D and 3D audio player pools initialized")
	g.sfx_3d("explosion", Vector3(1, 2, 3), -6.0)
	var played_3d := false
	for p3 in g.players_3d:
		if p3.stream != null:
			played_3d = true
			p3.stop()
			p3.stream = null
	check(played_3d, "sfx_3d assigns positional stream when autotest is false")

	# Switch to autotest mode for deterministic non-captured headless runtime checks
	g.autotest = true
	g.opts["seed"] = 4545
	g.quick_deploy()

	# 2. Flight stations, loadout color & overlay
	check(g.world is Flight, "quick deploy enters Flight")
	var fl: Flight = g.world
	check(is_instance_valid(fl.turret_rig) and is_instance_valid(fl.turret_head), "Flight builds dorsal turret rig")
	check(fl.plate_nodes.size() == 3 and fl.system_nodes.size() == 4, "Flight builds 3 hull plates and 4 system beacons")
	check(is_instance_valid(fl.shield_dome) and is_instance_valid(fl.overlay), "Flight builds shield dome and tactical overlay")
	g.sim.loadout["engine"] = "lancer"
	check(fl._turret_color() == Color("#22d3ee"), "Flight turret color reflects Lancer engine loadout")
	g.sim.ultimate[0] = 100.0
	g.sim.selected = 0
	g.pressed_now[KEY_F] = true
	g._process(0.05)
	check(fl.shield_dome.visible, "Flight shield dome appears when shield is active")
	for role in [1, 2, 3, 0]:
		g.sim.selected = role
		g._process(0.05)
	check(fl.overlay != null and fl.overlay_layer.visible, "Flight overlay ticks cleanly across all 4 roles")

	var idle_position := fl.position
	var idle_time: float = g.sim.flight_time
	for step in 20:
		g._process(0.05)
	check(fl.position.is_equal_approx(idle_position), "Flight holds position without thrust")
	check(is_equal_approx(g.sim.flight_time, idle_time), "Flight time holds without thrust")

	var forward_action: String = g.KEY_ACTIONS[KEY_W]
	Input.action_press(forward_action)
	for step in 40:
		g._process(0.05)
	var outbound_position := fl.position
	var outbound_moon_distance := outbound_position.distance_to(Universe.B_ORIGIN)
	var outbound_distance := outbound_position.distance_to(fl.path_b)
	check(outbound_position.z < idle_position.z and outbound_distance < idle_position.distance_to(fl.path_b),
		"W drives Flight forward and closer to the Moon approach")

	g.yaw = PI
	for step in 20:
		g._process(0.05)
	Input.action_release(forward_action)
	check(fl.position.distance_to(Universe.B_ORIGIN) > outbound_moon_distance,
		"W after a 180-degree turn flies away from the Moon")
	check(fl.position.distance_to(Universe.A_ORIGIN) < outbound_position.distance_to(Universe.A_ORIGIN),
		"W after a 180-degree turn flies closer to Earth")

	# 3. Planet B waypoints, distinct weapons, abilities & steps
	g.sim.phase = "landing"
	g._end_cine("landing")
	check(g.world is PlanetB, "landing transitions to PlanetB")
	var pb: PlanetB = g.world
	check(is_instance_valid(pb.priority_beacon) and is_instance_valid(pb.hatch_beacon) and is_instance_valid(pb.scan_beam) and is_instance_valid(pb.shield_bubble), "PlanetB builds 3D beacons, scan beam, and shield bubble")
	g.pressed_now[KEY_Z] = true
	g._process(0.05)
	check(pb.priority_beacon.visible, "Z reveals 3D priority sample beacon")
	for r in [0, 1, 2]:
		g.sim.selected = r
		pb.tracers.clear()
		var tpool := pb.get_node_or_null("TracerPool")
		if tpool:
			for t in tpool.get_children():
				t.visible = false
		pb.fire_cd = 0.0
		pb.actors[r].set_weapon_drawn(true)
		pb.actors[r].weapon_blend = 1.0
		pb.actors[r].weapon_reload = 0.0
		g.lmb = true
		g._process(0.05)
		g.lmb = false
		var min_tracers := 3 if r == 1 else (2 if r == 2 else 1)
		var tracer_count := pb.tracers.size()
		if tpool == null:
			tpool = pb.get_node_or_null("TracerPool")
		if tpool:
			for t in tpool.get_children():
				if t.visible:
					tracer_count += 1
		check(tracer_count >= min_tracers, "role %d weapon spawns distinct tracer profile (%d)" % [r, tracer_count])
	g.sim.selected = 1
	pb.suit_hp[0] = 60.0
	pb.actors[0].position = pb.actors[1].position + Vector3(2.0, 0.0, 0.0)
	g.pressed_now[KEY_Q] = true
	g._process(0.05)
	check(pb.suit_hp[0] > 60.0, "Chip Q heals nearby ally with ring pulse")
	g.sim.ultimate[0] = 100.0
	g.sim.selected = 0
	g.pressed_now[KEY_F] = true
	g._process(0.05)
	check(pb.shield_bubble.visible, "F ultimate activates 3D shield bubble on PlanetB")
	var step_clip: String = pb.actors[0].poll_step(0.4, 5.4)
	check(step_clip.begins_with("step_"), "Actor.poll_step emits footstep clip name")

	# 4. Typography, InputMap, HUD layout bounds & MissionControlUI
	var sans := UI.font(false)
	var mono := UI.font(true)
	check(sans.base_font != null and mono.base_font != null and sans.base_font != mono.base_font, "UI.font loads distinct sans and mono fonts")
	check(UI.font(false, "res://missing-font.ttf").base_font != null, "UI.font falls back cleanly on missing path override")
	for key in g.KEY_ACTIONS:
		check(InputMap.has_action(g.KEY_ACTIONS[key]), "InputMap registered action: " + g.KEY_ACTIONS[key])
	g.rebind_action("interact", KEY_J)
	var rebound_has_j := false
	for ev in InputMap.action_get_events("interact"):
		if ev is InputEventKey and ev.keycode == KEY_J:
			rebound_has_j = true
	check(rebound_has_j, "rebind_action updates InputMap key event")
	Input.action_press("interact")
	check(g.held(KEY_E), "g.held delegates through rebound InputMap action")
	Input.action_release("interact")
	g.rebind_action("interact", KEY_E)
	g._rebound_actions.clear()

	# Verify HUD still fits inside 1280x720 and 3004x1805 with SystemFont
	for dimensions in [Vector2i(1280, 720), Vector2i(3004, 1805)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		g.sim.phase = "flight"
		g.hud.update_common(g.sim, 0)
		await process_frame
		await process_frame
		for c in [g.hud.crosshair, g.hud.visual_status, g.hud.radar.get_parent().get_parent(), g.hud.board.get_parent(), g.hud.get_node("CrewAdvisor"), g.hud.roles_box, g.hud.tactical_panel, g.hud.banner]:
			var rect: Rect2 = c.get_global_rect()
			check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= dimensions.x + 1 and rect.end.y <= dimensions.y + 1, "HUD fits %s with updated fonts: %s" % [dimensions, c.name])

	g.show_mission_control()
	g._mc_policy("conserve")
	g._mc_run(10)
	g._mc_policy("balanced")
	g._mc_run(0)
	check(g.mc_state.get("done", false), "MissionControlUI runs simulation to completion")
	var found_chart := false
	for node in g.menu_root.find_children("*", "Control", true, false):
		if node is MissionControlUI.SimChart:
			found_chart = true
			break
	check(found_chart, "MissionControlUI renders SimChart control")

	# Clean teardown
	for p in g.players:
		p.stop()
		p.stream = null
	for p3 in g.players_3d:
		p3.stop()
		p3.stream = null
	g.streams.clear()
	await create_timer(0.1).timeout
	g.queue_free()
	pb = null
	fl = null
	g = null
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("IMPROVEMENTS_TEST_RESULT: %d failures" % failures)
	quit(1 if failures else 0)
