## Scripted playthrough used for verification: `Godot --path . -- --autotest`.
## Drives the flight controls and captures screenshots to res://shots/.
class_name Autotest
extends RefCounted

var g
var dir := ""
var fails: Array = []


func wait(t: float) -> void:
	await g.get_tree().create_timer(t, true, false, true).timeout


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	var img: Image = g.get_viewport().get_texture().get_image()
	img.save_png(dir + "/" + name + ".png")
	print("SHOT ", name, " mode=", g.mode, " location=", g.sim.location if g.sim else "-")


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


func run(main) -> void:
	g = main
	dir = ProjectSettings.globalize_path("res://shots")
	LobbyPages.play_mode = "practice"
	g.quick_deploy()
	check(g.piloting and g.sim.on_surface("planet_a"), "Quick Deploy seats the pilot on the pad")
	await shot("01_boarded")
	if await fly_to("planet_c"):
		await shot("03_moon")
		await tap(KEY_E)
		check(g.player_actor() != null and not g.piloting, "Exited on the Moon")
	g.get_tree().quit(int(not fails.is_empty()))


func run_demo(main) -> void:
	await run(main)


func fly_to(planet: String) -> bool:
	hold_action(KEY_W)
	key(KEY_SPACE)
	var departed := await until(func(): return g.sim.in_space(), 20.0, "climb to space")
	key(KEY_SPACE, false)
	hold_action(KEY_W, false)
	if not departed:
		return false
	var vessel: Flight = g.vessel
	var destination: Vector3 = Universe.PLANETS[planet]["origin"]
	vessel.basis = Basis.looking_at((destination - vessel.position).normalized())
	await shot("02_space")
	if not await until(func(): return vessel.arrival == planet, 100.0, "fly to " + planet):
		return false
	await tap(KEY_L)
	if not await until(func(): return g.sim.on_surface(planet) and g._travel_destination == "", 3.0, "load " + planet):
		return false
	return await until(func(): return vessel.grounded, 12.0, "touchdown")
