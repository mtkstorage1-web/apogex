## Live-rendered showcase recorder (Godot Movie Maker). Does not touch game scripts.
## Godot --path . --resolution 1280x720 --write-movie artifacts/showcase/raw.avi --fixed-fps 30 -s tools/record_showcase.gd
## Time jumps (fast-forwards) are edit cuts: they run inside a single rendered frame.
extends SceneTree

var g
var frame := 0

func _initialize() -> void:
	call_deferred("run")

func frames(n: int, step: Callable = Callable()) -> void:
	for i in n:
		if step.is_valid():
			step.call(i)
		await process_frame
		frame += 1

func mark(label: String) -> void:
	print("SHOWCASE ", label, " frame=", frame, " t=", frame / 30.0)

func hold(action: String, n: int, step: Callable = Callable()) -> void:
	Input.action_press(action)
	await frames(n, step)
	Input.action_release(action)

func press_e() -> void:
	g.pressed_now[KEY_E] = true

func ff(n: int, dt := 0.05) -> void:
	for i in n:
		g._process(dt)

func run() -> void:
	seed(47)
	g = load("res://main.tscn").instantiate()
	g.settings_path = "user://showcase-%d.cfg" % OS.get_process_id()
	root.add_child(g)
	g.autotest = true
	g.opts["seed"] = 47
	await frames(3)
	LobbyPages.play_mode = "practice"
	g.start_match()
	for p in g.sim.parts:
		g.sim.buy_part(p["id"])
	var w = g.world
	var role: int = g.sim.selected
	var a: Actor = w.actors[role]
	await frames(3)

	# 1. SHIP BUILDER HOLOGRAM (90 frames)
	mark("builder")
	g.open_picker(g.sim.parts[0]["id"])
	var n_var: int = maxi(1, g.picker.families.size())
	await frames(90, func(i):
		if i % 22 == 0:
			g.picker.highlight((i / 22) % n_var)
	)
	g.picker.close()
	await frames(2)

	# 2. CRANE ARM (150 frames)
	a.position = w._lift_seat(role)
	press_e()
	g.lmb = true
	await frames(1)
	ff(240)
	g.lmb = false
	if w.lift_state != PlanetA.LiftState.DECK:
		ff(240)
	a.position = w._crane_station(role)
	press_e()
	await frames(1)
	w.crane_enter_frame = -1
	for i in 1200:
		if w._gse_ready_part(role) != null:
			break
		w._tick_gse_delivery(0.05)
	var pickup = w._gse_ready_part(role)
	mark("crane")
	var arm: Dictionary = w.fx_arms[role]
	var bay: Vector3 = w._gse_point(role, 1.0)
	arm["target"] = Vector3(arm["base"].x, 12.0, arm["base"].z) + w._crane_arm_forward(role) * 12.0
	await frames(10)
	await hold("jump", 15)            # SPACE hoist up
	await hold("sprint", 15)          # SHIFT lower
	await hold("move_forward", 12)    # W
	await hold("move_right", 12)      # D
	await hold("move_left", 8)        # A
	if pickup != null:
		await frames(1, func(_i): arm["target"] = Vector3(bay.x + 2.0, 10.0, bay.z + 1.5))
		await frames(20)
		press_e()
		await frames(10)
		var grip: Vector3 = w._crane_placement_grip(pickup)
		await frames(40, func(_i): arm["target"] = Vector3(grip.x + 1.8, grip.y + 6.0, grip.z - 1.2))
		press_e()
		await frames(7)
	else:
		await frames(57)
	w.exit_crane_mode()

	# 3. HORIZONTAL SPACECRAFT AND COCKPIT BOARDING
	g.sim.auto_build["enabled"] = true
	g.sim.auto_assemble(Sim.AUTO_BUILD_SECONDS)
	a.position = w._lift_seat(role)
	press_e()
	ff(1)
	for i in 300:
		if w.lift_state == PlanetA.LiftState.PARKED:
			break
		g._process(0.05)
	a.position = g.cockpit_position()
	g.follow_cam(a)
	mark("boarding")
	await frames(30)
	press_e()
	await frames(5)
	mark("launch")
	Input.action_press("move_forward")
	Input.action_press("jump")
	await frames(70, func(_i): ff(6))
	Input.action_release("move_forward")
	Input.action_release("jump")
	var ship: Flight = g.vessel
	if not g.sim.in_space():
		g._swap_flight_location("space")
	ship.basis = Basis.looking_at((Universe.C_ORIGIN - ship.position).normalized())
	ship.throttle = 1.0
	mark("flight")
	await frames(50, func(_i): ff(6))

	# 5. MOON SURFACE FPV
	g._swap_flight_location("planet_c")
	ship.touch_down(ship.landing_zone)
	g.disembark_ship()
	await frames(10)
	var b: PlanetB = g.world
	g.sim.selected = 1
	var chip: Actor = b.actors[1]
	var rival_pos: Vector3 = (b.rivals[1]["actor"] as Actor).position
	var face := func():
		var d: Vector3 = rival_pos - chip.position
		g.yaw = atan2(-d.x, -d.z)
		g.pitch = -0.04
	var dir := (Vector3(rival_pos.x, 0, rival_pos.z) - Vector3(0, 0, 0)).normalized()
	chip.position = rival_pos + Vector3(32, 0, 14) if dir.length() > 0.0 else chip.position
	chip.set_weapon_drawn(true)
	chip.weapon_blend = 1.0
	g.first_person = true
	mark("moon")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await frames(60, func(_i):
		face.call()
		chip.set_weapon_drawn(true)
	)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await frames(60, func(i):   # aim + fire
		face.call()
		b.fire_cd = 0.0
		g.lmb = i % 9 == 2
	)
	g.lmb = false
	g.pressed_now[KEY_R] = true  # reload: mag drop / insert / rack
	await frames(60, func(_i): face.call())
	mark("done")

	g.first_person = false
	await frames(3)
	DirAccess.remove_absolute(g.settings_path)
	quit(0)
