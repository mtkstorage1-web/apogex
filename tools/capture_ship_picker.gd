## Run without --headless for rendered Part C review artifacts.
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	g.start_match()
	g._end_cine("intro")
	var families := ["lancer", "hauler", "halo", "bulwark", "kestrel"]
	var i := 0
	for p in g.sim.parts:
		g.sim.set_variant(p["id"], families[i % 5])
		i += 1
	g.world.refresh_ship_loadout()
	g.world._visuals(0)
	g.world._shop_visuals(0)
	g._refresh_hud()
	g.hud.banner_time = 0
	g.hud.tick(.1)
	g.cam.position = Vector3(0, 7, -13)
	g.cam.look_at(Vector3(0, 3, -32))
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://artifacts/part_c/shop_hud.png")
	g.open_picker("port")
	g.picker.highlight(3)
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://artifacts/part_c/shop_picker.png")
	g.picker.close()
	g.hud.visible = false
	for p in g.sim.parts:
		g.world.slot_nodes[p["id"]]["node"].visible = true
		for bolt in g.world.slot_nodes[p["id"]]["bolts"]: bolt.visible = false
	g.cam.position = Vector3(27, 22, 32)
	g.cam.look_at(Vector3(0, 4, 0))
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://artifacts/part_c/mixed_ship.png")
	g.free()
	quit()
