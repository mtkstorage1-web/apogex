## Scripted playthrough used for verification: `Godot --path . -- --autotest`.
## Drives real input events through every phase and saves screenshots to res://shots/.
class_name Autotest
extends RefCounted

var g
var dir := ""
var fails: Array = []


func wait(t: float) -> void:
	await g.get_tree().create_timer(t, true, false, true).timeout


func shot(name: String) -> void:
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	var img: Image = g.get_viewport().get_texture().get_image()
	img.save_png(dir + "/" + name + ".png")
	print("SHOT ", name, " mode=", g.mode, " phase=", g.sim.phase if g.sim else "-")


func key(k: int, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func tap(k: int) -> void:
	key(k, true)
	await wait(0.08)
	key(k, false)
	await wait(0.05)


func hold_action(k: int, down := true) -> void:
	var action: String = g.KEY_ACTIONS[k]
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func until(cond: Callable, timeout: float, label: String) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await wait(0.2)
		t += 0.2
	fails.append("timeout: " + label)
	print("FAIL timeout ", label)
	return false


func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)


func thrust_to_approach(label: String) -> bool:
	var s: Sim = g.sim
	var flight: Flight = g.world
	var previous_role := s.selected
	s.selected = 0
	# Aim from the current position after any demonstration maneuvers.
	var initial_heading := (flight.path_b - flight.path_a).normalized()
	var heading := (flight.path_b - flight.position).normalized()
	g.yaw = atan2(-heading.x, -heading.z) - atan2(-initial_heading.x, -initial_heading.z)
	g.pitch = asin(heading.y)
	hold_action(KEY_W)
	var reached := await until(func(): return s.phase in ["landing", "docking"],
		30.0, label)
	hold_action(KEY_W, false)
	s.selected = previous_role
	return reached


func run(main) -> void:
	g = main
	dir = ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	print("AUTOTEST start ", dir)
	await wait(1.5)
	print("AUTOTEST waited")
	await shot("01_home")
	g.show_select()
	await wait(1.0)
	await shot("02_select")
	g.show_manifest()
	await wait(0.6)
	await shot("03_manifest")
	g.opts["fast"] = false
	g.start_match()
	await wait(2.0)
	await shot("04_intro")
	await until(func(): return g.mode == "play", 6.0, "intro ends")
	await wait(1.0)
	await shot("05_build")
	# Parts selection has its own runtime test. Confirm base parts here to drive the launch pad.
	var s: Sim = g.sim
	var w: PlanetA = g.world
	var a: Actor = w.actor(s.selected)
	for part in s.parts:
		s.buy_part(part["id"])
	check(s.all_parts_bought(), "confirm all parts")
	a.position = PlanetA.SHOP_DESK
	await wait(0.3)
	await tap(KEY_E)
	check(w.pad_stage == "build", "desk starts automated assembly")
	await shot("06_building")
	Engine.time_scale = 3.0
	var assembled := await until(func(): return w.pad_stage == "erect_wait", 20.0, "assembly and outfit")
	Engine.time_scale = 1.0
	if not assembled:
		g.get_tree().quit(1)
		return
	check(s.secured_count() == s.parts.size() and s.all_cargo_stowed(), "assemble ship and stow all cargo")
	await shot("07_outfit")
	await tap(KEY_E)
	await shot("08_erecting")
	Engine.time_scale = 3.0
	var ready := await until(func(): return w.pad_stage == "ready", 15.0, "erect and fit boosters")
	Engine.time_scale = 1.0
	if not ready:
		g.get_tree().quit(1)
		return
	a.position = PlanetA.LAUNCH_DESK
	await wait(0.3)
	await tap(KEY_E)
	check(g.mode == "route", "mission desk opens flight plan")
	await shot("09_route")
	g._choose_route("sheltered")
	await wait(0.5)
	await shot("10_gonogo")
	g.launch()
	await wait(2.5)
	await shot("11_launch")
	if not await until(func(): return g.world is Flight and g.mode == "play", PlanetA.LAUNCH_DURATION + 2.0, "launch to flight"):
		g.get_tree().quit(1)
		return
	g.sim.selected = 0
	hold_action(KEY_W)
	await wait(3.0)
	await shot("12_flight_pilot")
	hold_action(KEY_W, false)
	g.sim.selected = 2
	await wait(0.5)
	g.lmb = true
	await wait(1.0)
	await shot("13_flight_gunner")
	g.lmb = false
	g.sim.selected = 1
	await wait(0.8)
	await shot("14_flight_engineer")
	g.sim.selected = 3
	await wait(0.8)
	await shot("15_flight_raider")
	check(g.sim.hull > 0.0, "ship survives early flight")
	if not await thrust_to_approach("thrust to Moon approach"):
		g.get_tree().quit(1)
		return
	if not await until(func(): return g.world is PlanetB and g.mode == "play", 18.0, "landing on B"):
		g.get_tree().quit(1)
		return
	await wait(1.5)
	await shot("16_planet_b")
	# Raider scans flag 7 (index 6 at 6,-6) by holding LMB while facing it.
	var f = s.flags[6]
	var b = g.world
	var ra: Actor = b.actor(3)
	if f["state"] != "site":
		for x in s.flags:
			if x["state"] == "site":
				f = x
				break
	ra.position = f["position"] + Vector3(0, 0, 2.6)
	g.yaw = 0.0
	g.pitch = -0.3
	await wait(0.3)
	g.lmb = true
	await wait(2.5)
	await shot("17_scanning")
	await wait(3.5)
	g.lmb = false
	check(s.carried_flag(0, 3) != null, "extract a Science Flag")
	await shot("18_carrying")
	ra.position = PlanetB.HATCH + Vector3(0, 0, -1)
	await wait(0.3)
	await tap(KEY_E)
	check(s.flag_counts(0)["onboard"] >= 1, "load flag on board")
	g.sim.selected = 2
	var gun: Actor = b.actor(2)
	gun.position = Vector3(0, 0, 20)
	g.yaw = 0.0
	g.pitch = -0.05
	await tap(KEY_B)
	await wait(0.4)
	g.lmb = true
	await wait(0.8)
	await shot("19_blaster")
	g.lmb = false
	g.sim.selected = 3
	ra.position = PlanetB.HATCH + Vector3(0, 0, -1)
	await wait(0.3)
	await tap(KEY_T)
	if not await until(func(): return g.world is Flight, 3.0, "depart B"):
		g.get_tree().quit(1)
		return
	await wait(1.5)
	await shot("20_return_flight")
	if not await thrust_to_approach("thrust to Earth approach"):
		g.get_tree().quit(1)
		return
	if not await until(func(): return g.world is PlanetA and g.mode == "play", 18.0, "dock at A"):
		g.get_tree().quit(1)
		return
	await wait(1.0)
	var da: Actor = g.world.actor(g.sim.selected)
	da.position = Sim.DELIVERY_PAD + Vector3(0, 0, -2)
	await wait(0.3)
	await shot("21_delivery")
	hold_action(KEY_E)
	await until(func(): return s.phase == "delivered", 8.0, "deliver all flags")
	hold_action(KEY_E, false)
	check(s.teams[0]["delivered"] >= 1, "flag delivered scores")
	await wait(0.5)
	await shot("22_delivered")
	g.ff = 12.0
	Engine.time_scale = 3.0
	await until(func(): return g.mode == "debrief", 120.0, "match resolves")
	Engine.time_scale = 1.0
	await wait(0.8)
	await shot("23_debrief")
	print("AUTOTEST ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	g.get_tree().quit(0 if fails.is_empty() else 1)


# ---------------------------------------------------------------------------
# Single player + Mission Control: `Godot --path . -- --autotest-sp`
# ---------------------------------------------------------------------------
func run_sp(main) -> void:
	g = main
	dir = ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	await wait(1.0)
	g.show_campaign()
	await wait(0.6)
	await shot("sp01_campaign")
	g.show_briefing("orbital")
	await wait(0.4)
	await shot("sp02_briefing")
	g.show_design()
	await wait(0.4)
	await shot("sp03_design")
	g.start_workshop()
	await wait(1.5)
	await shot("sp04_workshop")
	var w = g.world
	await until(func(): return w.stage == "shopping", 8.0, "robots frame hull")
	var p: Actor = w.player
	p.position = Workshop.KIOSK + Vector3(0, 0, 3)
	for i in 7:
		await tap(KEY_E)
		await wait(0.15)
	check(w.items.filter(func(x): return x["state"] != "shop").size() == 7, "order seven pieces")
	await wait(1.2)
	await shot("sp05_robot_arm")
	await until(func(): return w.items[4]["state"] in ["deliver", "bolt"], 20.0, "crane starts")
	await wait(1.0)
	await shot("sp06_crane")
	await until(func(): return w.stage == "fairing", 40.0, "stack spacecraft")
	await shot("sp07_stacked")
	await tap(KEY_E)
	await until(func(): return w.stage == "ready", 12.0, "fairing closes")
	check(w.budget_left == w.evaluation["budget"] - w.evaluation["cost"], "budget spent matches design cost")
	p.position = Workshop.ELEVATOR
	await wait(0.3)
	await tap(KEY_E)
	await until(func(): return g.world is OrbitShip, 3.0, "board ship")
	await wait(1.0)
	await shot("sp08_interior")
	var c: Campaign = g.campaign
	Engine.time_scale = 3.0
	var shots := {"launch_a": false, "launch_b": false, "orbit": false, "eclipse": false}
	var t := 0.0
	while not c.terminal() and t < 400.0:
		if g.world is Workshop:
			if not shots["launch_a"] and g.world.launch_t > 6.0:
				shots["launch_a"] = true
				await shot("sp09_liftoff")
			if not shots["launch_b"] and g.world.launch_t > 12.0:
				shots["launch_b"] = true
				await shot("sp10_staging")
		elif g.world is OrbitShip and g.mode == "play":
			var o = g.world
			o.speed_mul = 4.0
			if not shots["orbit"] and c.phase == "commission":
				shots["orbit"] = true
				await shot("sp11_orbit")
			if not shots["eclipse"] and c.phase == "eclipse":
				shots["eclipse"] = true
				await shot("sp12_eclipse")
			if c.activity == null:
				await _sp_act(o, c)
		await wait(0.25)
		t += 0.25
	Engine.time_scale = 1.0
	check(c.phase == "complete", "campaign mission complete (%s)" % c.phase)
	await wait(1.0)
	await shot("sp13_report")
	g.show_mission_control()
	await wait(0.5)
	await shot("sp14_mission_control")
	g._mc_policy("conserve")
	g._mc_run(10)
	g._mc_policy("balanced")
	g._mc_run(0)
	await wait(0.5)
	check(g.mc_state["done"], "simulator runs to end")
	await shot("sp15_simulation")
	print("AUTOTEST ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	g.get_tree().quit(0 if fails.is_empty() else 1)


func _sp_act(o, c: Campaign) -> void:
	o.ctx["alignment"] = 50.0
	o.ctx["closure"] = 30.0
	o.ctx["calibration"] = 50.0
	for a in c.objectives():
		if a["id"] == "wait" or a["id"] == "optional" or (a["id"] == "observe" and c.observing):
			continue
		var room: String = a["room"]
		if room == "exterior":
			o.player.position = OrbitShip.TELESCOPE_BAY
		elif o.eva and room == "airlock":
			o.player.position = OrbitShip.AIRLOCK_OUTSIDE
		else:
			o.player.position = OrbitShip.STATIONS[room][0] + Vector3(-1.0 if room != "airlock" else 1.0, 0, 0)
		o.ctx["at_telescope"] = room == "exterior"
		o.ctx["at_airlock"] = o.eva and room == "airlock"
		if c.can_action(a["id"], room, o.ctx) != "":
			continue
		var here: Array = o._room_actions(room)
		o.action_idx = here.find(a)
		await tap(KEY_E)
		return


func run_mc(main) -> void:
	g = main
	dir = ProjectSettings.globalize_path("res://shots")
	await wait(1.0)
	g.show_mission_control()
	g._mc_policy("conserve")
	g._mc_run(20)
	g._mc_policy("balanced")
	g._mc_run(0)
	await wait(0.5)
	var sc: ScrollContainer = g.menu_root.find_children("*", "ScrollContainer", true, false)[0]
	sc.scroll_vertical = 520
	await wait(0.4)
	await shot("sp16_sim_chart")
	sc.scroll_vertical = 100000
	await wait(0.4)
	await shot("sp17_sim_report")
	g.get_tree().quit(0)


func run_launch(main) -> void:
	g = main
	dir = ProjectSettings.globalize_path("res://shots")
	await wait(0.5)
	g.campaign = Campaign.new("orbital", Campaign.DEFAULT_DESIGN)
	g.campaign.set_phase("launch")
	g.start_campaign_launch()
	for t in [3.0, 7.5, 11.5, 14.5, 18.5]:
		await until(func(): return g.world is Workshop and g.world.launch_t >= t, 25.0, "launch t")
		await shot("sp_launch_%02d" % int(t))
	await until(func(): return g.world is OrbitShip, 5.0, "orbit after launch")
	check(g.campaign.phase == "commission", "phase commission after launch")
	g.get_tree().quit(0)


## Scripted match demo: `Godot --path . -- --demo-ff`.
func run_demo(main) -> void:
	g = main
	Engine.time_scale = 3.0
	await wait(0.75)
	g.show_select()
	await wait(0.75)
	g.show_manifest()
	await wait(0.75)
	g.opts["fast"] = false
	g.start_match()
	if not await until(func(): return g.mode == "play", 12.0, "demo intro"):
		return
	await _demo_map("Earth")

	var s: Sim = g.sim
	var earth: PlanetA = g.world
	var crew: Actor = earth.actor(s.selected)
	for part in s.parts:
		s.buy_part(part["id"])
	crew.position = PlanetA.SHOP_DESK
	await wait(0.3)
	await tap(KEY_E)
	if not await until(func(): return earth.pad_stage == "erect_wait", 30.0, "demo assembly and outfit"):
		return
	await tap(KEY_E)
	if not await until(func(): return earth.pad_stage == "ready", 25.0, "demo launch pad ready"):
		return

	crew.position = PlanetA.LAUNCH_DESK
	await wait(0.3)
	await tap(KEY_E)
	if not await until(func(): return g.mode == "route", 3.0, "demo flight plan"):
		return
	await wait(0.75)
	g._choose_route("sheltered")
	await wait(0.75)
	g.launch()
	if not await until(func(): return g.world is Flight and g.mode == "play", PlanetA.LAUNCH_DURATION + 2.0, "demo launch to flight"):
		return

	s.selected = 0
	await _demo_map("Flight")
	var cruise_pitch: float = g.pitch
	hold_action(KEY_W)
	for strafe in [KEY_A, KEY_D]:
		hold_action(strafe)
		var direction := -1.0 if strafe == KEY_A else 1.0
		for step in 20:
			var turn := sin(PI * float(step + 1) / 20.0)
			g.yaw = direction * 0.4 * turn
			g.pitch = cruise_pitch + direction * 0.18 * turn
			await wait(0.05)
		hold_action(strafe, false)
	if not await thrust_to_approach("demo thrust to Moon approach"):
		return
	if not await until(func(): return g.world is PlanetB and g.mode == "play", 18.0, "demo Moon landing"):
		return

	s.selected = 3
	await _demo_map("Moon")
	var moon: PlanetB = g.world
	var raider: Actor = moon.actor(3)
	var flag = s.flags[6]
	if flag["state"] != "site":
		for candidate in s.flags:
			if candidate["state"] == "site":
				flag = candidate
				break
	raider.position = flag["position"] + Vector3(0, 0, 2.6)
	g.yaw = 0.0
	g.pitch = -0.3
	await wait(0.3)
	g.lmb = true
	var captured := await until(func(): return s.carried_flag(0, 3) != null, 10.0, "demo capture Science Flag")
	g.lmb = false
	if not captured:
		return
	check(captured, "demo Science Flag captured")
	await wait(0.75)

	raider.position = PlanetB.HATCH + Vector3(0, 0, -1)
	await wait(0.3)
	await tap(KEY_E)
	if not await until(func(): return s.flag_counts(0)["onboard"] > 0, 3.0, "demo load Science Flag"):
		return
	await tap(KEY_T)
	if not await until(func(): return g.world is Flight, 3.0, "demo depart Moon"):
		return
	if not await thrust_to_approach("demo thrust to Earth approach"):
		return
	if not await until(func(): return g.world is PlanetA and g.mode == "play", 18.0, "demo Earth docking"):
		return

	crew = g.world.actor(s.selected)
	crew.position = Sim.DELIVERY_PAD + Vector3(0, 0, -2)
	await wait(0.3)
	hold_action(KEY_E)
	var delivered := await until(func(): return s.phase == "delivered", 8.0, "demo deliver Science Flag")
	hold_action(KEY_E, false)
	if not delivered:
		return
	check(s.teams[0]["delivered"] > 0, "demo Science Flag scores")
	await wait(1.5)
	g.ff = 12.0
	if await until(func(): return g.mode == "debrief", 120.0, "demo match resolves"):
		print("DEMO ", "PASS" if fails.is_empty() else "FAIL " + str(fails))


func _demo_map(phase: String) -> void:
	await tap(KEY_M)
	check(g.hud.tactical_panel.visible, "demo %s tactical map open" % phase)
	await wait(1.5)
	await tap(KEY_M)
	check(not g.hud.tactical_panel.visible, "demo %s tactical map closed" % phase)
