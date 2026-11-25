extends SceneTree
## Run with Godot's graphical display and the Metal Forward+ renderer.

const WorldScene := preload("res://scenes/world/WorldRoot.tscn")
const SIZE := Vector2i(1280, 720)
const OUTPUT := "res://artifacts/apogex_showcase/ui"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus" or RenderingServer.get_current_rendering_driver_name() != "metal":
		printerr("Frontend capture requires a graphical display with Metal Forward+.")
		quit(1)
		return
	var directory := ProjectSettings.globalize_path(OUTPUT)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("Unable to create ", directory)
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var world := WorldScene.instantiate() as WorldRoot
	viewport.add_child(world)
	world.set_quality_preset("HIGH")
	if world.get_frontend_state() != "MAIN_MENU":
		printerr("Graphical startup did not open the main menu.")
		quit(1)
		return
	if not await _save(viewport, directory, "ui01_main_menu.png", 40):
		return
	world.open_lobby()
	if not await _save(viewport, directory, "ui02_lobby_16v16.png"):
		return
	if not world.frontend_ui.launch_lobby():
		printerr("Could not launch the showcase lobby.")
		quit(1)
		return
	if not await _save(viewport, directory, "ui03_spawn_screen.png"):
		return
	if not world.deploy_from_frontend("alpha", "helion", "assault"):
		printerr("Could not stage the showcase deployment.")
		quit(1)
		return
	for frame in 20:
		await process_frame
	world.open_pause_menu()
	if not await _save(viewport, directory, "ui04_pause_menu.png"):
		return
	viewport.queue_free()
	await process_frame
	print("APOGEX frontend showcase PASS")
	quit()


func _save(viewport: SubViewport, directory: String, filename: String, frames: int = 12) -> bool:
	for frame in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.get_size() != SIZE or image.save_png(directory.path_join(filename)) != OK:
		printerr("Could not save ", filename, " at 1280×720.")
		quit(1)
		return false
	print("Saved ", filename)
	return true
