extends SceneTree

const STEP := 0.05
var game
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	failures += int(not ok)


func run() -> void:
	var old_mode := LobbyPages.play_mode
	var old_home := LobbyPages.arena_home
	var old_preset := LobbyPages.arena_preset
	game = load("res://main.tscn").instantiate()
	var settings_file := "user://open-world-flight-%d.cfg" % OS.get_process_id()
	game.settings_path = settings_file
	root.add_child(game)
	game.autotest = true
	game.set_process(false)
	game.set_touch_mode("off")
	LobbyPages.play_mode = "arena_clash"
	LobbyPages.arena_home = "planet_a"
	LobbyPages.arena_preset = "standard"
	game.opts["selected"] = 0
	game.start_match()
	await process_frame
	check(game.sim.on_surface("planet_a") and game.world_b == null and game.world_planet_b == null
		and game.universe.moon_environment == null, "Start on Planet A with other surfaces unloaded")
	var strip_found := false
	for label: Label in game.hud.find_children("*", "Label", true, false):
		strip_found = strip_found or label.text in ["BUILD", "OUTFIT", "ROUTE", "DELIVER"]
	check(not strip_found and game.hud.get_node_or_null("PhaseBar") == null
		and game.hud.location_label.text == Universe.A_LABEL and game.hud.clock.text == "08:00", "HUD has a location and match clock without a phase bar")
	var earth: PlanetA = game.world
	earth.actor(0).position = game.cockpit_position()
	tap(KEY_E)
	check(not game.piloting, "Unbuilt ship cannot be boarded")
	for slot: String in ArenaClashSim.FLIGHT_PARTS:
		check(game.sim.buy_part(slot), "Order and install " + slot)
	game._process(ArenaClashSim.BUILD_SECONDS)
	check(game.sim.flight_capable() and game.sim.secured_count() == 3, "Three installed modules enable flight")
	check(board_via_ramp(earth.actor(0), true) and game.vessel.grounded and game.vessel.engine_power == 0.0
		and earth.actors.all(func(crew: Actor) -> bool: return not crew.visible), "Walking up the ramp boards the whole crew with a horizontal ship")
	check_family_pivots()
	if game.piloting and check_vtol():
		check_surface_controls()
		check_surface_sweep()
		if take_off():
			check_space_controls()
			transfer("planet_c", false)
	if game.sim.in_space() and reach("planet_c", false, true):
		var moon: PlanetB = game.world
		check(moon == game.world_b and game.vessel.grounded and game.sim.hull == 100.0
			and game.vessel.position.is_equal_approx(Universe.C_ORIGIN + PlanetB.SHIP_POS), "Manual lunar touchdown stops undamaged in the coalition bay")
		tap(KEY_E)
		check(not game.piloting and game.player_actor() != null and game.player_actor().visible
			and game.arena_clash.combatant("orange:0").get("alive", false), "E exits and the player is an active arena combatant")
		check(board_via_ramp(game.player_actor(), false) and game.vessel.grounded, "E on the Moon ramp climbs aboard again")
		if game.piloting and game.vessel.grounded:
			check_touch_lift()
		if game.piloting and take_off() and reach("planet_b", true):
			check(game.world == game.world_planet_b and game.vessel.position.is_equal_approx(Universe.B_ORIGIN)
				and game.vessel.grounded and game.sim.hull == 100.0, "Planet B loads and auto-touchdown stops on its pad")
			tap(KEY_E)
			check(game.player_actor() != null and game.player_actor().visible and game.hud.location_label.text == Universe.B_LABEL,
				"The Earth twin is walkable and labeled")
			check(game._ensure_world_planet_b() == game.world_planet_b and game.world_b == moon, "Landed worlds are cached")
	Input.action_release("move_forward")
	Input.action_release("jump")
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(settings_file)
	LobbyPages.play_mode = old_mode
	LobbyPages.arena_home = old_home
	LobbyPages.arena_preset = old_preset
	print("Open world flight: %d/%d checks passed" % [checks - failures, checks])
	quit(int(failures > 0))


## Real boarding path: E at the ramp walks the player up through the hatch, then E at the cockpit seat.
func board_via_ramp(crew: Actor, from_foot: bool) -> bool:
	for i in 30:
		if game._ramp_live():
			break
		game._process(STEP)
	if from_foot:
		crew.position = game.cockpit_position()
	tap(KEY_E)
	for i in 200:
		if game.interior_active():
			break
		game._process(STEP)
	if not game.interior_active():
		return false
	game.interior.actor(game.sim.selected).position = preload("res://scripts/ship_interior.gd").STATION_POS["cockpit"]
	tap(KEY_E)
	return game.piloting and not game.interior_active()


func tap(key: int) -> void:
	game.pressed_now[key] = true
	game._process(STEP)


func check_family_pivots() -> void:
	for family: String in ShipCatalog.FAMILIES:
		var loadout := {"engine": family, "port": family, "thruster": family, "keel": family}
		var model := ShipModel.full(Color.ORANGE, loadout, true)
		var parked := true
		for slot: String in ShipModel.DRIVE_SLOTS:
			var pivot := model.get_node_or_null("%s/EnginePivot" % slot) as Node3D
			parked = parked and pivot != null and is_equal_approx(pivot.rotation.x, PI * 0.5)
			if pivot != null:
				var nozzle: Vector3 = pivot.get_meta("nozzle_exit")
				parked = parked and (pivot.get_parent().transform * pivot.transform * nozzle).y > 0.0
		check(parked, "%s parks all three drives at 90 degrees with nozzle clearance" % family)
		model.free()


func check_vtol() -> bool:
	var flight: Flight = game.vessel
	var origin := flight.position
	Input.action_press("move_forward")
	for frame in 10:
		game._process(STEP)
	Input.action_release("move_forward")
	check(flight.grounded and flight.position.is_equal_approx(origin), "W alone leaves the ship on its pad")

	Input.action_press("jump")
	var rises := true
	for frame in 24:
		var before := flight.position.y
		game._process(STEP)
		rises = rises and flight.position.y > before
	Input.action_release("jump")
	check(not flight.grounded and rises and flight.flight_speed < 0.1
		and flight.altitude > 15.0 and absf(rad_to_deg(flight.engine_tilt) - 90.0) < 0.5,
		"Holding Space lifts vertically from the pad with engines at 90 degrees")
	var hover_height := flight.altitude
	var max_error := 0.0
	for frame in 60:
		game._process(STEP)
		max_error = maxf(max_error, absf(flight.altitude - hover_height))
	check(max_error < 3.0 and absf(flight.vertical_speed) < 0.5,
		"Released Space holds altitude for three seconds (maximum drift %.2f m)" % max_error)
	var gear := flight.ship.find_children("LandingFoot*", "MeshInstance3D", true, false)
	check(not gear.is_empty() and gear.all(func(foot: Node3D) -> bool: return not foot.visible),
		"Landing gear retracts above 15 m")
	tap(KEY_SPACE)
	for frame in 23:
		game._process(STEP)
	check(flight.altitude > hover_height + 0.5, "A single Space tap raises the hover point")

	var before_speed := flight.flight_speed
	var mounts: Array[Vector3] = []
	for pivot in flight.engine_pivots:
		mounts.append(pivot.position)
	var previous := rad_to_deg(flight.engine_tilt)
	var smooth := true
	var pitch_valid := true
	Input.action_press("move_forward")
	for frame in 45:
		game._process(STEP)
		var angle := rad_to_deg(flight.engine_tilt)
		smooth = smooth and angle <= previous and previous - angle < 10.0
		previous = angle
		pitch_valid = pitch_valid and absf((flight.basis * flight.ship.basis).orthonormalized().get_euler().x) < PI / 4.0
	Input.action_release("move_forward")
	check(smooth and previous < 2.0 and flight.flight_speed > before_speed + 20.0,
		"W smoothly rotates the engines toward cruise and builds forward speed")
	var exhaust_attached := flight.engine_pivots.size() == 3
	for i in flight.engine_pivots.size():
		var pivot := flight.engine_pivots[i]
		var plume := pivot.get_node_or_null("AnimatedExhaust") as ExhaustFX
		exhaust_attached = exhaust_attached and plume != null and plume.get_parent() == pivot \
			and plume.position.is_equal_approx(pivot.get_meta("nozzle_exit")) and pivot.position == mounts[i]
	check(exhaust_attached, "Exhaust follows each rotating nozzle and the hinge position stays fixed")

	for sign_y in [-1.0, 1.0]:
		flight.steer(Vector2(0, sign_y * 2000.0))
		game._process(STEP)
		pitch_valid = pitch_valid and absf((flight.basis * flight.ship.basis).orthonormalized().get_euler().x) < PI / 4.0
	check(pitch_valid, "Surface ship body pitch stays below 45 degrees")
	flight.basis = Basis(Vector3.UP, flight.basis.get_euler().y)
	return not flight.grounded


func take_off() -> bool:
	var flight: Flight = game.vessel
	var origin: Vector3 = Universe.PLANETS[game.sim.location]["origin"]
	Input.action_press("jump")
	for frame in 500:
		game._process(STEP)
		if game._travel_destination == "space":
			break
	Input.action_release("jump")
	var departure_height := flight.position.y - origin.y
	var heading := flight.forward()
	var speed := flight.flight_speed
	for frame in 12:
		game._process(STEP)
		if game._travel_destination == "":
			break
	var reached: bool = game.sim.in_space()
	check(reached and game.world == flight and game.hud.location_label.text == "SPACE"
		and departure_height >= Flight.SURFACE_CEILING and departure_height < Flight.SURFACE_CEILING + 3.0,
		"Climbing past 650 m changes to the space map")
	check(reached and flight.forward().is_equal_approx(heading) and is_equal_approx(flight.flight_speed, speed)
		and flight.global_position.length() < 0.01, "Departure preserves heading and speed in the rebased frame")
	return reached


func check_surface_controls() -> void:
	var flight: Flight = game.vessel
	flight.position = Universe.A_ORIGIN + Vector3.UP * 100.0
	flight.vertical_speed = 0.0
	flight.basis = Basis.IDENTITY
	flight._surface_velocity = flight.forward() * Flight.SURFACE_SPEED
	var heading := flight.basis
	Input.action_press("move_forward")
	game._process(STEP)
	var approach_limit := lerpf(140.0, 1400.0, flight.altitude / 600.0)
	check(flight.altitude < 150.0 and absf(flight.flight_speed - approach_limit) < 1.0,
		"Surface approach caps speed at %.0f m/s at %.0f m AGL" % [flight.flight_speed, flight.altitude])
	var camera_before: Basis = game.cam.global_basis
	Input.action_press("move_right")
	var course_ok := true
	for frame in 20:
		var from := flight.position
		game._process(STEP)
		var displacement := flight.position - from
		displacement.y = 0.0
		course_ok = course_ok and displacement.angle_to(flight.forward()) < deg_to_rad(1.0)
	Input.action_release("move_right")
	var camera_bank := camera_before.get_rotation_quaternion().angle_to(game.cam.global_basis.get_rotation_quaternion())
	var body_bank := flight.ship.basis.x.angle_to(Vector3.RIGHT)
	check(course_ok and flight.basis.is_equal_approx(heading) and is_equal_approx(flight.roll, PI / 3.0)
		and absf(body_bank - PI / 3.0) < deg_to_rad(1.0),
		"Surface D rolls the ship body to 60 degrees without changing heading or horizontal course")
	check(absf(rad_to_deg(camera_bank) - 12.0) < 0.5, "Surface chase camera follows 20 percent of ship roll")
	game._process(STEP)
	var easing := flight.roll > 0.0 and flight.roll < PI / 3.0
	for frame in 19:
		game._process(STEP)
	check(easing and is_zero_approx(flight.roll), "Surface bank smoothly auto-levels after release")
	Input.action_release("move_forward")

	Input.action_press("move_back")
	var stopped := false
	for frame in 32:
		game._process(STEP)
		stopped = stopped or absf(flight.flight_speed) < Flight.STOP_EPSILON
	Input.action_release("move_back")
	check(stopped and is_equal_approx(flight.flight_speed, -210.0),
		"Surface S stops the ship, then reverses at 210 m/s")
	var prior_mouse := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var arrow := InputEventKey.new()
	arrow.keycode = KEY_LEFT
	arrow.pressed = true
	Input.parse_input_event(arrow)
	Input.flush_buffered_events()
	game._process(STEP)
	var release := arrow.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	Input.mouse_mode = prior_mouse
	check(flight.forward().angle_to(-heading.z) > deg_to_rad(1.0) and is_zero_approx(flight.roll),
		"Left arrow yaws with a free cursor")


func check_surface_sweep() -> void:
	var flight: Flight = game.vessel
	var start := Vector3(-1300, 0, 750)
	var end := Vector3(1300, 0, 750)
	var endpoints: float = maxf(game.universe.surface_height("planet_a", start), game.universe.surface_height("planet_a", end))
	var peak := endpoints
	for x in range(-1300, 1301, 5):
		peak = maxf(peak, game.universe.surface_height("planet_a", Vector3(x, 0, 750)))
	start.y = (endpoints + peak) * 0.5
	end.y = start.y
	var contact := flight._sweep_surface("planet_a", start, end)
	check(peak > endpoints and contact.x > start.x and contact.x < end.x
		and is_equal_approx(contact.y, game.universe.surface_height("planet_a", contact)),
		"Terrain sweep catches a ridge with both movement endpoints above ground")
	contact = flight._sweep_surface("planet_a", Vector3(0, 20, 0), Vector3(0, -20, 0))
	check(contact.is_equal_approx(Vector3.ZERO), "Vertical sweep hits the landing pad at ground level")


func check_space_controls() -> void:
	var flight: Flight = game.vessel
	var departure := flight.transform
	var departure_speed := flight.flight_speed
	flight.position = Vector3(13000, 12000, 5000)
	flight.basis = Basis.IDENTITY
	flight.roll = 0.0
	flight.flight_speed = 0.0
	Input.action_press("move_forward")
	for frame in 210:
		game._process(STEP)
	check(flight.flight_speed >= 4500.0 and flight.flight_speed <= Flight.CRUISE_SPEED,
		"Space cruise measures %.0f m/s" % flight.flight_speed)
	Input.action_press("sprint")
	for frame in 36:
		game._process(STEP)
	Input.action_release("sprint")
	check(is_equal_approx(flight.flight_speed, 6200.0), "Space boost measures %.0f m/s" % flight.flight_speed)
	var heading := flight.basis
	var course_ok := true
	var largest_roll := 0.0
	Input.action_press("move_right")
	for frame in 90:
		var from := flight.position
		game._process(STEP)
		largest_roll = maxf(largest_roll, absf(flight.roll))
		course_ok = course_ok and (flight.position - from).angle_to(-heading.z) < deg_to_rad(1.0)
	Input.action_release("move_right")
	var right_roll := flight.roll
	Input.action_press("move_left")
	for frame in 20:
		var from := flight.position
		game._process(STEP)
		course_ok = course_ok and (flight.position - from).angle_to(-heading.z) < deg_to_rad(1.0)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	var left_roll := flight.roll
	check(course_ok and flight.basis.is_equal_approx(heading) and largest_roll > deg_to_rad(170.0)
		and absf(right_roll - left_roll - PI / 2.0) < 0.01,
		"Space A/D roll in opposite directions through a full turn while heading and course stay within 1 degree")
	for frame in 4:
		game._process(STEP)
	check(is_equal_approx(flight.roll, left_roll), "Space roll holds after release")
	Input.action_press("move_back")
	var stopped := false
	for frame in 150:
		game._process(STEP)
		stopped = stopped or absf(flight.flight_speed) < Flight.STOP_EPSILON
	Input.action_release("move_back")
	check(stopped and is_equal_approx(flight.flight_speed, -720.0),
		"Space S stops the ship, then reverses at 720 m/s")

	flight.flight_speed = 0.0
	flight.roll = PI / 3.0
	var up := flight.body_basis().y
	var from := flight.position
	Input.action_press("jump")
	for frame in 12:
		game._process(STEP)
	Input.action_release("jump")
	var lift := flight.position - from
	check(lift.length() > 5.0 and lift.angle_to(up) < deg_to_rad(1.0), "Space lifts along rolled ship up")
	from = flight.position
	Input.action_press("flight_trim_down")
	for frame in 32:
		game._process(STEP)
	Input.action_release("flight_trim_down")
	var descent := flight.position - from
	check(descent.length() > 5.0 and descent.angle_to(-up) < deg_to_rad(1.0), "Ctrl descends along rolled ship down")

	check_space_sweep()
	flight.transform = departure
	flight.flight_speed = departure_speed
	flight.roll = 0.0
	flight.enter_space()
	flight.arrival = ""
	flight.engine_tilt = ShipModel.PARKED_TILT


func check_space_sweep() -> void:
	var flight: Flight = game.vessel
	var radius: float = game.universe.body_radius("planet_c")
	var approach_offset := Vector3.UP * (radius + 800.0)
	var start := Universe.C_ORIGIN + approach_offset + Vector3.LEFT * 20000.0
	var end := Universe.C_ORIGIN + approach_offset + Vector3.RIGHT * 20000.0
	var next := flight._sweep_space(start, end, STEP)
	check(next.is_equal_approx(end) and flight.arrival == "planet_c",
		"Space sweep detects an arrival crossing with both endpoints outside the arrival radius")
	start -= approach_offset
	end -= approach_offset
	flight.flight_speed = Flight.BOOST_SPEED
	next = flight._sweep_space(start, end, STEP)
	check(next.x < Universe.C_ORIGIN.x and next.distance_to(Universe.C_ORIGIN) >= radius + Flight.BODY_CLEARANCE
		and flight.flight_speed == 0.0 and game.sim.hull == 100.0, "Space sweep stops a through-body segment undamaged")


func check_touch_lift() -> void:
	var flight: Flight = game.vessel
	game.set_touch_mode("on")
	game._process(STEP)
	var mobile: MobileControls = game.hud.mobile_controls
	var lift := mobile.control_center("jump")
	mobile._touch(9, lift, true)
	game._process(STEP)
	mobile._touch(9, lift, false)
	game.set_touch_mode("off")
	check(not flight.grounded and flight.altitude > 1.0 and flight.flight_speed < 0.1,
		"Touch LIFT takes off vertically from the Moon pad")
	var gear := flight.ship.find_children("LandingFoot*", "MeshInstance3D", true, false)
	check(flight.altitude < 15.0 and not gear.is_empty() and gear.all(func(foot: Node3D) -> bool: return foot.visible),
		"Landing gear stays deployed during low hover")


func transfer(planet: String, boosting: bool) -> bool:
	var flight: Flight = game.vessel
	var departure := flight.transform
	var departure_speed := flight.flight_speed
	var departure_tilt := flight.engine_tilt
	var target: Vector3 = Universe.PLANETS[planet]["origin"]
	var radius: float = game.universe.body_radius(planet)
	var direction := flight.basis.inverse() * (target - flight.position).normalized()
	var mouse_y := -asin(direction.y) / 0.0022 * (-1.0 if game.invert_y else 1.0)
	flight.steer(Vector2(-atan2(-direction.x, -direction.z) / 0.0026, mouse_y) / float(game.sens))
	var elapsed := 0.0
	var safe := true
	var rebased := true
	Input.action_press("move_forward")
	if boosting:
		Input.action_press("sprint")
	while flight.arrival != planet and elapsed < 35.0:
		game._process(STEP)
		elapsed += STEP
		safe = safe and flight.position.distance_to(target) >= radius + Flight.BODY_CLEARANCE
		rebased = rebased and flight.global_position.length() < 0.01
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var prompted: bool = flight.arrival == planet and game.hud._prompt_text == "PRESS L TO LAND · " + Universe.PLANETS[planet]["label"]
	var mode := "boost" if boosting else "cruise"
	check(prompted and safe and elapsed < 35.0,
		"%s landing prompt after %.2f seconds at %s with no body penetration" % [planet, elapsed, mode])
	check(rebased, "Floating origin stays centered throughout %s transfer" % mode)
	if prompted:
		check(absf(flight.flight_speed) <= Flight.SPACE_APPROACH_SPEED + 1.0,
			"Arrival speed is capped to the safe approach speed")
	if planet == "planet_c" and not boosting:
		flight.transform = departure
		flight.flight_speed = departure_speed
		flight.engine_tilt = departure_tilt
		flight.enter_space()
		flight.arrival = ""
	return prompted


func reach(planet: String, auto := false, boosting := false) -> bool:
	var flight: Flight = game.vessel
	if not transfer(planet, boosting):
		return false
	flight.roll = PI / 3.0
	tap(KEY_L)
	check(is_zero_approx(flight.roll), "Requesting a landing levels space roll")
	for frame in 12:
		game._process(STEP)
		if game._travel_destination == "":
			break
	check(game.sim.on_surface(planet) and game.piloting and not flight.grounded, "L fades to a piloted surface approach")
	var mobile: MobileControls = game.hud.mobile_controls
	if auto:
		game.set_touch_mode("on")
		game._process(STEP)
		mobile._touch(8, mobile.control_center("crouch"), true)
	else:
		Input.action_press("flight_trim_down")
	for frame in 180:
		if auto and game.hud._prompt_text == "PRESS L FOR AUTO-TOUCHDOWN":
			check(game.hud._prompt_action == "land" and game.hud.prompt_title.text.begins_with("TAP"),
				"Touch UI exposes the near-pad landing action")
			mobile._touch(8, mobile.control_center("crouch"), false)
			var point := mobile.control_center("interact")
			mobile._touch(7, point, true)
			game._process(STEP)
			mobile._touch(7, point, false)
			break
		if flight.grounded:
			break
		game._process(STEP)
	Input.action_release("flight_trim_down")
	mobile._touch(8, Vector2.ZERO, false)
	game.set_touch_mode("off")
	return game.sim.on_surface(planet)
