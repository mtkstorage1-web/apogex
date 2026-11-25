extends SceneTree
## Run with a graphical Godot display: godot --path . --script tools/capture_apogex_showcase.gd

const Infrastructure = preload("res://scripts/environment/InfrastructureNetwork.gd")
const WorldScene = preload("res://scenes/world/WorldRoot.tscn")
const SIZE := Vector2i(1280, 720)
const OUTPUT := "res://artifacts/apogex_showcase"
const DEPLOYABLES := [
	"helion_defense_turret", "cinder_defense_turret", "deployable_shield_gen",
	"supply_ammo_pod", "orbital_strike_beacon", "mothership_turret_battery",
]
var _preview_models: Array[PackedScene] = []

const VIEWS := [
	[0, "01_orbit_vesper9.png"],
	[1, "02_terminus_spire_battle.png"],
	[15, "03_helion_hangar_fighters.png"],
	[16, "04_command_bridge.png"],
	[3, "05_obsidian_fissure_settlement.png"],
	[13, "06_crimson_canyon_bridge.png"],
]


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Showcase capture requires a graphical Godot display.")
		quit(1)
		return
	if "--raw-deployables" in OS.get_cmdline_user_args():
		_preview_models = cache_unimported_deployables()
	var absolute := ProjectSettings.globalize_path(OUTPUT)
	var status := DirAccess.make_dir_recursive_absolute(absolute)
	if status != OK:
		printerr("Unable to create showcase directory: ", error_string(status))
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.name = "ApogexShowcase"
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	root.add_child(viewport)
	var world := WorldScene.instantiate() as WorldRoot
	viewport.add_child(world)
	world.set_quality_preset("HIGH")
	world.explorer.input_enabled = false
	world.explorer.set_mouse_captured(false)
	world.explorer.set_physics_process(false)
	for element in world.get_children():
		if element is CanvasLayer:
			element.hide()
	world.player_combat.set_physics_process(false)
	world.player_combat.viewmodel.hide()
	for entry in VIEWS:
		var landmark: int = entry[0]
		world.teleport_to_landmark(landmark)
		var fill := await _stage(world, landmark)
		for frame in 25:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.get_size() != SIZE:
			printerr("Could not read the 1280×720 viewport for ", entry[1])
			quit(1)
			return
		status = image.save_png(absolute.path_join(entry[1]))
		if status != OK:
			printerr("Unable to save ", entry[1], ": ", error_string(status))
			quit(1)
			return
		print("Saved ", entry[1])
		if fill != null:
			fill.queue_free()
	viewport.queue_free()
	await process_frame
	print("APOGEX showcase PASS")
	quit()



## Resolve the same production resource paths in memory for asset QA while the editor import is pending.
static func cache_unimported_deployables() -> Array[PackedScene]:
	var models: Array[PackedScene] = []
	for filename in DEPLOYABLES:
		var path: String = "res://assets/models/apogex/deployables/" + filename + ".glb"
		if ResourceLoader.exists(path) or not FileAccess.file_exists(path):
			continue
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) != OK:
			continue
		var scene := document.generate_scene(state)
		if scene == null:
			continue
		var packed := PackedScene.new()
		if packed.pack(scene) == OK:
			packed.take_over_path(path)
			models.append(packed)
		scene.free()
	return models


func _stage(world: WorldRoot, landmark: int) -> OmniLight3D:
	match landmark:
		1:
			var objective := world.capture_objectives[0]
			var focus: Vector3 = objective.planet_position
			var frame := objective.global_basis
			var eye := focus + frame * Vector3(-37, 19, 22)
			_pose(world, eye, focus + frame.y * 10.0)
			await physics_frame
			await physics_frame
			for entry in [["turret", Vector3(-10, 1, 8)], ["shield", Vector3(6, 1, 5)], ["supply", Vector3(-2, 1, 12)]]:
				world.engineering_build_manager.deploy(entry[0], "helion", focus + frame * entry[1])
			world.commander_system.execute("cinder", "strike", "alpha")
		15:
			var ship: Node3D = world.mothership_manager.get_ship("helion")
			_pose(world, ship.local_to_planet(Vector3(-32, 9, 327)), ship.local_to_planet(Vector3(5, 4, 395)))
			return _fill(world, ship.local_to_planet(Vector3(-20, 16, 353)), Color("#bdd9ff"), 2.2)
		16:
			var ship: Node3D = world.mothership_manager.get_ship("helion")
			_pose(world, ship.local_to_planet(Vector3(90, 13, 179)), ship.local_to_planet(Vector3(119, 12, 216)))
			return _fill(world, ship.local_to_planet(Vector3(104, 18, 198)), Color("#b4ddff"), 1.45)
		3:
			var location := world.landmark_manager.get_landmark(landmark)
			var eye: Vector3 = location.planet_pos + location.unit_dir * 19.0
			var focus: Vector3 = location.base_pos + location.unit_dir * 5.0
			_pose(world, eye, focus)
		13:
			var bridge := Infrastructure.compute_bridge_layout(world.planet.noise_stack, world.world_config.planet_radius, 0)
			var frame: Basis = bridge.tb
			var center: Vector3 = bridge.center
			var eye := center + frame * Vector3(-38, 22, 36)
			var floor_radius := world.planet.get_surface_radius(eye.normalized())
			if eye.length() < floor_radius + 12.0:
				eye = eye.normalized() * (floor_radius + 12.0)
			_pose(world, eye, center + frame.x * 22.0)
	return null


func _fill(world: WorldRoot, point: Vector3, color: Color, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 85.0
	world.combat_effects.add_child(light)
	light.global_position = world.floating_origin.planet_to_render(point)
	return light


func _pose(world: WorldRoot, eye: Vector3, focus: Vector3) -> void:
	world.floating_origin.check_and_shift(eye)
	world.explorer.teleport_to(eye, (focus - eye).normalized())
	var camera := world.explorer.get_camera()
	camera.look_at(world.floating_origin.planet_to_render(focus), world.explorer.global_basis.y)
