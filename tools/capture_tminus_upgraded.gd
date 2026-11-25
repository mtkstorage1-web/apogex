extends SceneTree
## Godot --path . --rendering-method forward_plus --rendering-driver metal --audio-driver Dummy --script tools/capture_tminus_upgraded.gd
## Uses the shipping scene and stages cameras and actors for repeatable live captures.

const SIZE := Vector2i(1280, 720)
const OUTPUT := "res://artifacts/tminus_upgraded"
const STEP := 1.0 / 30.0

var game
var directory: String
var settings_path: String


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if not _require(DisplayServer.get_name() != "headless"
			and RenderingServer.get_current_rendering_method() == "forward_plus"
			and RenderingServer.get_current_rendering_driver_name() == "metal", "Metal Forward+ is required"):
		return
	directory = ProjectSettings.globalize_path(OUTPUT)
	if not _require(DirAccess.make_dir_recursive_absolute(directory) == OK, "Could not create the capture directory"):
		return

	root.size = SIZE
	var config := ConfigFile.new()
	config.set_value("audio", "muted", true)
	config.set_value("controls", "touch_mode", "off")
	config.set_value("graphics", "resolution", SIZE)
	settings_path = "user://tminus-capture-%d.cfg" % OS.get_process_id()
	if not _require(config.save(settings_path) == OK, "Could not save capture settings"):
		return
	game = preload("res://main.tscn").instantiate()
	game.settings_path = settings_path
	root.add_child(game)
	current_scene = game
	game.autotest = true # Keep the pointer free while the capture driver steps gameplay.
	game.set_process(false)
	if not _require(game.mode == "menu" and _menu_has(game.menu_root, "COMPETITIVE / OFFLINE PRACTICE")
			and not _menu_has(game.menu_root, "SINGLE PLAYER CAMPAIGN"), "Classic Home menu did not open"):
		return
	_step_for(0.5)
	if not await _save("tminus01_home.png"):
		return

	game.show_select()
	if not _require(game.showcase.kind == "select", "Crew select did not open"):
		return
	await create_timer(0.55).timeout
	game.opts["seed"] = 47
	game.new_sim()
	LobbyPages.play_mode = "practice"
	game.start_match()
	_step_for(4.1)
	var earth := game.world as PlanetA
	var sim: Sim = game.sim
	for part in sim.parts:
		sim.buy_part(part["id"])
	var crew := earth.actor(sim.selected)
	crew.position = earth._lift_seat(sim.selected)
	_tap(KEY_E)
	if not _require(earth.pad_stage == "build" and _until(func() -> bool: return earth.lift_state == PlanetA.LiftState.DECK, 8.0), "Crew could not start assembly"):
		return
	# Stage a few installed modules using the simulator's existing assembly path.
	sim.manual_crane_build = false
	sim.auto_build["enabled"] = true
	sim.auto_assemble(6.0)
	sim.manual_crane_build = true
	_step_for(0.5)
	_camera(Vector3(38, 30, 68), Vector3(3, 5, -13), 63.0)
	if not await _save("tminus02_earth_build.png"):
		return

	sim.auto_build["enabled"] = true
	sim.auto_assemble(Sim.AUTO_BUILD_SECONDS)
	crew.position = earth._lift_seat(sim.selected)
	_tap(KEY_E)
	if not _require(_until(func() -> bool: return earth.pad_stage == "ready", 16.0), "Could not complete assembly and outfit"):
		return
	crew.position = game.cockpit_position()
	_tap(KEY_E)
	if not _require(game.piloting and _fly_to_space(), "Manual takeoff did not reach free flight"):
		return
	var flight: Flight = game.vessel
	flight.basis = Basis.looking_at((Universe.C_ORIGIN - flight.position).normalized())
	_step_for(2.5)
	if not await _save("tminus03_free_flight.png"):
		return
	if not _require(_land("planet_c"), "Flight did not land on the Moon"):
		return
	sim.selected = 3
	sim.set_priority(6)
	_step_for(0.6)
	game.hud.tick(3.5)
	_camera(Vector3(41, 37, 120), Vector3(0, 5, -2), 58.0)
	if not await _save("tminus04_moon_flags.png"):
		return

	# Exercise the flag transaction and the normal departure and return handovers.
	for duration in Sim.SCAN_DURATIONS:
		sim.scan_flag(6, 0, 3, duration / sim.scan_mult + 0.1, 1.0)
	if not _require(sim.load_flag(0, 3, 1.0), "Could not capture and load the Science Flag"):
		return
	if not _require(game.board_ship() and _fly_to_space() and _land("planet_a"), "Flag carrier did not return to Earth"):
		return
	if not _require(sim.deliver_flag(0, 1.0) and sim.teams[0]["delivered"] == 1, "Delivered flag did not score"):
		return
	print("T-MINUS Metal Forward+ capture and return loop PASS")
	_finish(0)


func _fly_to_space() -> bool:
	Input.action_press("move_forward")
	Input.action_press("jump")
	var reached := _until(func() -> bool: return game.sim.in_space() and game._travel_destination == "", 25.0)
	Input.action_release("move_forward")
	Input.action_release("jump")
	return reached


func _land(planet: String) -> bool:
	var vessel: Flight = game.vessel
	var origin: Vector3 = Universe.PLANETS[planet]["origin"]
	vessel.basis = Basis.looking_at((origin - vessel.position).normalized())
	if not _until(func() -> bool: return vessel.arrival == planet, 90.0):
		return false
	game.pressed_now[KEY_L] = true
	if not _until(func() -> bool: return game.sim.on_surface(planet) and vessel.grounded, 12.0):
		return false
	_tap(KEY_E)
	return not game.piloting


func _step_for(seconds: float) -> void:
	for frame in ceili(seconds / STEP):
		game._process(STEP)


func _until(condition: Callable, seconds: float) -> bool:
	for frame in ceili(seconds / STEP):
		if condition.call():
			return true
		game._process(STEP)
	return condition.call()


func _tap(key: int) -> void:
	game.pressed_now[key] = true
	game._process(STEP)


func _camera(at: Vector3, target: Vector3, fov: float) -> void:
	game.cam.position = at
	game.cam.look_at(target, Vector3.UP)
	game.cam.fov = fov


func _menu_has(node: Node, text: String) -> bool:
	if node is Button and node.text.to_upper().contains(text):
		return true
	for child in node.get_children():
		if _menu_has(child, text):
			return true
	return false


func _save(filename: String) -> bool:
	for frame in 42:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not _require(image != null and image.get_size() == SIZE, "Unexpected framebuffer dimensions for " + filename):
		return false
	if not _require(image.save_png(directory.path_join(filename)) == OK, "Could not save " + filename):
		return false
	print("Saved ", filename)
	return true


func _require(ok: bool, message: String) -> bool:
	if not ok:
		printerr(message)
		_finish(1)
	return ok


func _finish(status: int) -> void:
	if is_instance_valid(game):
		game.queue_free()
		for frame in 4:
			await process_frame
	if not settings_path.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	quit(status)
