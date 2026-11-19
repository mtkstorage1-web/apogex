## Run with a rendering driver (not --headless): godot --path . -s tools/render_ship_families.gd
## Writes four PNGs and an editable, script-free five-family comparison scene.
extends SceneTree
const FAMILIES := ["lancer", "hauler", "halo", "bulwark"]

func _initialize() -> void:
	call_deferred("render_all")

func world() -> Node3D:
	var scene := Node3D.new()
	scene.name = "ShipFamiliesPreview"
	var environment := WorldEnvironment.new()
	environment.name = "StudioEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("111c2b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9dded")
	env.ambient_light_energy = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	scene.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "RimLight"
	fill.rotation_degrees = Vector3(-25, 130, 0)
	fill.light_color = Color("8fc5ff")
	fill.light_energy = 1.0
	scene.add_child(fill)
	return scene

func camera(scene: Node3D, p: Vector3, target: Vector3, size: float) -> Camera3D:
	var c := Camera3D.new()
	c.name = "PreviewCamera"
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.size = size
	c.position = p
	scene.add_child(c)
	c.look_at_from_position(p, target)
	c.current = true
	return c

func render_all() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/ship_families")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1400, 1100)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for family in FAMILIES:
		var scene := world()
		viewport.add_child(scene)
		var ship: Node3D = load("res://scenes/prefabs/ships/%s.tscn" % family).instantiate()
		scene.add_child(ship)
		camera(scene, Vector3(31, 29, -39), Vector3(0, 4, -1), 37)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "res://artifacts/ship_families/%s.png" % family
		assert(viewport.get_texture().get_image().save_png(path) == OK)
		print("Rendered ", path)
		scene.free()
	viewport.queue_free()
	var comparison := world()
	root.add_child(comparison)
	var names := ["kestrel", "lancer", "hauler", "halo", "bulwark"]
	for i in names.size():
		var path: String = "res://scenes/prefabs/Kestrel.tscn" if i == 0 else "res://scenes/prefabs/ships/%s.tscn" % names[i]
		var ship: Node3D = load(path).instantiate()
		comparison.add_child(ship)
		ship.position.x = (i - 2) * 22
		var label := Label3D.new()
		label.name = names[i].capitalize() + "Label"
		label.text = names[i].to_upper()
		label.position = Vector3(ship.position.x, 0, -18)
		label.font_size = 80
		label.pixel_size = .025
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		comparison.add_child(label)
	camera(comparison, Vector3(25, 88, -100), Vector3(0, 3, -1), 125)
	owners(comparison, comparison)
	var packed := PackedScene.new()
	assert(packed.pack(comparison) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/ShipFamiliesPreview.tscn") == OK)
	comparison.free()
	quit()

func owners(n: Node, scene: Node) -> void:
	for c in n.get_children():
		c.owner = scene
		owners(c, scene)
