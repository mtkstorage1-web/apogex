## Run with a real renderer: Godot --path . --script tools/capture_ship_builder.gd
extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func _capture(path: String) -> void:
	for _frame in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Failed to save %s (error %d)" % [path, error])
		quit(1)
	else:
		print("SAVED ", ProjectSettings.globalize_path(path))


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	LobbyPages.play_mode = "practice"
	g.start_match()
	g.open_ship_builder()
	await _capture("res://shots/ship_builder_default.png")
	g.picker.select_variant("port", "lancer")
	g.picker.select_variant("bridge", "halo")
	g.picker.select_variant("cargo", "bulwark")
	await _capture("res://shots/ship_builder_changed.png")
	g.free()
	await process_frame
	quit(0)
