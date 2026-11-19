## Run on a native rendering backend with --script res://tools/capture_planets.gd.
extends SceneTree

var output := "res://assets/reference/"
var game
var universe: Universe
var craft: Node3D
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = preload("res://main.tscn").instantiate()
	game.settings_path = "user://planet-capture-%d.cfg" % OS.get_process_id()
	root.add_child(game)
	game.set_process(false)
	game.graphics.set_preset(1)
	game._apply_graphics(false)
	game.start_match()
	game.capture_mouse(false)
	game.clear_menu()
	game.hud.hide()
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440, 900)
	universe = game.universe
	game.world_a.ship_root.hide()
	craft = ShipModel.full(Color("#f08a4b"), game.sim.loadout)
	universe.add_child(craft)
	var exhaust := ShipModel.flame(9.0, craft)
	craft.add_child(exhaust)
	exhaust.hide()
	craft.position = Vector3(0, 0.15, 0)
	await _shot("earth-pad-ground", Vector3(43, 11, 41), Vector3(0, 10, -53), 65)
	for altitude in [5000.0, 100000.0]:
		var height: float = altitude / Universe.ATMOSPHERE_METERS_PER_UNIT
		var camera_z := 280.0 if altitude < 10000.0 else 800.0
		var radius := (universe.body_a.mesh as SphereMesh).radius
		var camera_y := sqrt(pow(radius + height, 2.0) - camera_z * camera_z) + universe.body_a.position.y
		var camera := Vector3(0.0, camera_y, camera_z)
		craft.position = camera + Vector3(-14, -7.0 if altitude < 10000.0 else -35.0, -57)
		craft.rotation.x = 1.0
		exhaust.show()
		var view_y := -16.0 if altitude < 10000.0 else -79.0
		await _shot("earth-ascent-%d-km" % int(altitude / 1000), camera, camera + Vector3(0, view_y, -110), 63)
	craft.hide()
	var center := universe.body_a.position
	await _shot("earth-orbit", center + Vector3(12900, 3900, 11200), center, 60)
	center = Universe.B_ORIGIN + universe.body_b.position
	await _shot("moon-orbit", center + Vector3(-1900, 2600, 15600), center, 59)
	var moon := PlanetB.new()
	moon.setup(game)
	moon.position = Universe.B_ORIGIN
	universe.add_child(moon)
	game.graphics.apply_scene(moon)
	await _shot("moon-surface", Universe.B_ORIGIN + Vector3(-23, 12.5, 27),
		Universe.B_ORIGIN + Vector3(36, 23, 150), 53)
	game.queue_free()
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	quit(1 if failed else 0)


func _shot(label: String, point: Vector3, target: Vector3, fov: float) -> void:
	game.cam.global_position = point
	game.cam.look_at(target)
	game.cam.fov = fov
	var headless := DisplayServer.get_name() == "headless"
	for frame in (3 if headless else 22):
		universe.tick(1.0 / 60.0)
		await process_frame
	if headless:
		print("LOADED ", label)
		return
	await RenderingServer.frame_post_draw
	var path := output + label + ".png"
	var result := root.get_texture().get_image().save_png(path)
	if result == OK:
		print("CAPTURED ", path)
	else:
		failed = true
		push_error("Screenshot %s failed: %s" % [path, error_string(result)])
