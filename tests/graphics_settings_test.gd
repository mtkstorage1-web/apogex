## Run with --headless, or with the native display to also verify window modes.
extends SceneTree

const MainScene := preload("res://main.tscn")
const Graphics := preload("res://scripts/graphics_settings.gd")

var path := "user://graphics-test-%d.cfg" % OS.get_process_id()
var failures := 0
var checks := 0
var main: Node


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _mount_main() -> void:
	main = MainScene.instantiate()
	main.settings_path = path
	root.add_child(main)


func _press(text: String) -> void:
	for button in main.menu_root.find_children("*", "Button", true, false):
		if button.text == text:
			button.pressed.emit()
			return
	check(false, "Missing button: " + text)


func _settle_graphics() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while main._graphics_applying and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not main._graphics_applying, "Graphics transition settled")


func _check_applied() -> void:
	var graphics: RefCounted = main.graphics
	var values: Dictionary = graphics.values
	var viewport: Viewport = main.get_viewport()
	var upscaler: int = graphics.effective("upscaler")
	var aa: int = graphics.effective("aa") if upscaler != Viewport.SCALING_3D_MODE_FSR2 else 0
	check(Engine.max_fps == values["fps_limit"], "FPS limit applied")
	check(viewport.scaling_3d_mode == upscaler, "Upscaler applied")
	check(is_equal_approx(viewport.scaling_3d_scale, values["render_scale"] / 100.0), "Render scale applied")
	check(viewport.positional_shadow_atlas_size == mini(4096, Graphics.SHADOW_SIZES[values["shadows"]]), "Positional shadow atlas applied")
	check(viewport.msaa_3d == [0, 0, 1, 2, 3, 0][aa], "MSAA applied")
	check(viewport.screen_space_aa == int(aa == 1) and viewport.use_taa == (aa == 5), "FXAA/TAA applied")
	check(is_equal_approx(viewport.mesh_lod_threshold, [4.0, 2.0, 1.0][values["lod"]]), "Mesh LOD applied")
	check(viewport.anisotropic_filtering_level == [0, 2, 4][values["lod"]], "Anisotropy applied")
	check(main.fps_counter.visible == values["fps_counter"], "FPS overlay visibility applied")
	check(Graphics.motion_effects == values["motion_effects"], "Motion effects setting applied")
	var env: Environment = main.world.find_children("*", "WorldEnvironment", true, false)[0].environment
	check(env.ssao_enabled == graphics.effective("ssao"), "SSAO applied")
	check(env.ssil_enabled == graphics.effective("ssil"), "SSIL applied")
	check(env.ssr_enabled == graphics.effective("ssr"), "SSR applied")
	check(env.glow_enabled == values["glow"], "Glow applied")
	check(env.volumetric_fog_enabled == graphics.effective("volumetric_fog"), "Volumetric fog applied")
	check(env.adjustment_enabled and is_equal_approx(env.adjustment_brightness, values["brightness"] / 100.0), "Brightness applied")
	var sun: DirectionalLight3D = main.world.find_children("*", "DirectionalLight3D", true, false)[0]
	check(sun.shadow_enabled == (values["shadows"] > 0), "Directional shadows applied")
	check(is_equal_approx(sun.directional_shadow_max_distance, Graphics.SHADOW_DISTANCES[values["shadows"]]), "Shadow distance applied")
	var steam := ExhaustFX.pad_cloud()
	check(steam.amount == roundi(120 * values["particles"] / 100.0), "New particle emitters honor density")
	steam.free()


func _check_display() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor() or root.is_embedded():
		return
	var expected: int = main.graphics.values["window_mode"]
	var deadline := Time.get_ticks_msec() + 5000
	while (main.graphics._fullscreen_transition or DisplayServer.window_get_mode() != expected) and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	check(DisplayServer.window_get_mode() == expected, "Native window mode %d applied (actual %d)" % [expected, DisplayServer.window_get_mode()])
	if expected == DisplayServer.WINDOW_MODE_WINDOWED:
		var size: Vector2i = main.graphics.effective("resolution")
		if size != Vector2i.ZERO:
			while DisplayServer.window_get_size() != size and Time.get_ticks_msec() < deadline:
				await create_timer(0.03).timeout
			check(DisplayServer.window_get_size() == size, "Windowed resolution %s applied (actual %s)" % [size, DisplayServer.window_get_size()])
	check(DisplayServer.window_get_vsync_mode() == main.graphics.effective("vsync"), "Native VSync applied")


func _run() -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("graphics", "quality", Graphics.HIGH)
	legacy.set_value("graphics", "fps_limit", 144)
	legacy.set_value("accessibility", "reduced_motion", true)
	check(legacy.save(path) == OK, "Wrote isolated legacy config")
	_mount_main()
	await _settle_graphics()
	var graphics: RefCounted = main.graphics
	print("Graphics test renderer=%s display=%s driver=%s" % [graphics.renderer(), DisplayServer.get_name(), RenderingServer.get_current_rendering_driver_name()])
	check(Engine.max_fps == 144 and graphics.values["render_scale"] == 100, "Migrated legacy FPS and preset")
	main.show_settings()
	_press("GRAPHICS")
	check(main.graphics_open, "Graphics opens from home Settings")
	_press("BACK")
	check(not main.graphics_open and main.mode == "menu", "Back returns to home Settings")
	main.mode = "play"
	main.pause()
	_press("GRAPHICS")
	check(main.graphics_open and main.paused_from == "play", "Graphics opens from Pause")
	_press("BACK")
	check(main.mode == "paused" and main.paused_from == "play", "Back returns to Pause")
	_press("GRAPHICS")
	_press("RESET GRAPHICS TO DEFAULT")
	await _settle_graphics()
	_check_applied()

	for preset in [3, 0, 1, 2]:
		main.graphics_buttons["quality"].pressed.emit()
		check(graphics.quality == preset, "Preset cycles to %d" % preset)
		for key in Graphics.OPTIONS:
			check(graphics.values[key] == Graphics.OPTIONS[key][2][preset], "Preset sets " + key)
		await _settle_graphics()
		_check_applied()

	for key in Graphics.OPTIONS:
		var button: Button = main.graphics_buttons[key]
		var choices: Array = graphics.available(key)
		check(button.disabled == (choices.size() <= 1), "Availability reflected in UI for " + key)
		if button.disabled:
			continue
		for step in choices.size():
			var expected: Variant = choices[(choices.find(graphics.effective(key)) + 1) % choices.size()]
			button.pressed.emit()
			check(graphics.values[key] == expected and graphics.quality == Graphics.CUSTOM,
				"Button cycles to %s and marks CUSTOM for %s" % [expected, key])
			check(main.graphics_buttons["quality"].text == "PRESET: CUSTOM", "Preset label updated")
			await _settle_graphics()
			var config := ConfigFile.new()
			check(config.load(path) == OK, "Saved settings are readable")
			var reloaded := Graphics.new()
			reloaded.load_config(config)
			check(reloaded.quality == Graphics.CUSTOM and reloaded.values == graphics.values, "Saved all settings after cycling " + key)
			main._load_settings()
			await _settle_graphics()
			check(graphics.values[key] == expected, "Reload preserved " + key)
			_check_applied()
			if key in ["window_mode", "resolution", "vsync"]:
				await _check_display()
			if DisplayServer.get_name() != "headless":
				await process_frame

	if DisplayServer.get_name() != "headless":
		# Queued window settings still apply when clicked during a native transition.
		for step in 3:
			main.graphics_buttons["window_mode"].pressed.emit()
			await process_frame
		await _settle_graphics()
		await _check_display()

	# Leave several non-default settings in the file and exercise a fresh startup.
	for key in ["render_scale", "brightness", "fps_limit", "fps_counter"]:
		main.graphics_buttons[key].pressed.emit()
	await _settle_graphics()
	var saved: Dictionary = graphics.values.duplicate()
	main.free()
	await process_frame
	_mount_main()
	await _settle_graphics()
	check(main.graphics.values == saved and main.graphics.quality == Graphics.CUSTOM, "Fresh startup restores CUSTOM settings")
	check(UI.reduced_motion and main.graphics.option_text("motion_effects", UI.reduced_motion).contains("REDUCED MOTION"),
		"Reduced motion persists and takes precedence over motion effects")
	_check_applied()
	await process_frame
	check(main.fps_counter.text.contains("FPS") and main.fps_counter.text.contains("ms"), "Overlay reports FPS and milliseconds")

	main.ensure_universe()
	var universe: Universe = main.universe
	check(universe.env.glow_enabled == main.graphics.values["glow"], "Graphics settings apply when the universe is created")
	check(universe.earth_landscape.meshes.has(0) and universe.moon_landscape.meshes.has(0),
		"All terrain LOD tiers are pre-built for Earth and Moon")
	check(int(universe.moon_dust.get_meta("base_particle_count", 0)) == Universe.DUST_PARTICLES,
		"Moon dust preserves base particle count metadata")
	main.show_graphics()
	main.graphics_buttons["atmosphere"].pressed.emit()
	await _settle_graphics()
	var sphere := universe.shell_a.mesh as SphereMesh
	check(sphere.radial_segments == [32, 64, 96, 128][main.graphics.values["atmosphere"]], "Atmosphere detail changes shell geometry")
	_press("RESET GRAPHICS TO DEFAULT")
	for preset in [3, 0, 1, 2]:
		main.graphics_buttons["quality"].pressed.emit()
		await _settle_graphics()
		var tier: int = mini(main.graphics.values["terrain"], main.graphics.values["lod"])
		check(main.graphics.quality == preset, "Universe active preset cycles to %d" % preset)
		check(universe.earth_landscape.ground.mesh == universe.earth_landscape.meshes[tier]
			and universe.moon_landscape.ground.mesh == universe.moon_landscape.meshes[tier],
			"Universe terrain mesh switches cleanly for preset %d" % preset)
		check(universe.moon_dust.amount == roundi(Universe.DUST_PARTICLES * main.graphics.values["particles"] / 100.0),
			"Moon dust amount matches particle density for preset %d" % preset)
		_check_applied()
	_press("LOW")
	await _settle_graphics()
	check(main.graphics.quality == 0, "Direct LOW selection transitions from HIGH")
	_check_applied()
	var low: Dictionary = main.graphics.values.duplicate()
	main._select_graphics_preset(0)
	for invalid in [-1, Graphics.CUSTOM, 99]:
		main._select_graphics_preset(invalid)
	check(main.graphics.quality == 0 and main.graphics.values == low and not main._graphics_applying,
		"Active and invalid selections leave settings and apply queue unchanged")
	var native_size := root.size
	var content_scale := root.content_scale_size
	main.graphics_buttons["quality"].grab_focus()
	for step in 8:
		var press := InputEventKey.new()
		press.keycode = KEY_ENTER
		press.pressed = true
		root.push_input(press)
		var release := InputEventKey.new()
		release.keycode = KEY_ENTER
		root.push_input(release)
		check(main.graphics.quality == (step + 1) % Graphics.CUSTOM, "Rapid keyboard press cycles preset")
	check(main.graphics.quality == 0 and main._graphics_applying, "Rapid cycles wrap twice before rendering")
	await _settle_graphics()
	_check_applied()
	_press("HIGH")
	await _settle_graphics()
	check(main.graphics.quality == Graphics.HIGH, "Direct HIGH selection transitions from LOW")
	_check_applied()
	var atlas: int = Graphics._directional_atlas_size
	for step in 3:
		main._apply_graphics(false)
	await _settle_graphics()
	_check_applied()
	check(Graphics._directional_atlas_size == atlas, "Repeated apply preserves directional atlas size")
	check(root.size == native_size and root.content_scale_size == content_scale,
		"Preset changes preserve native size and content scale")
	main._select_graphics_preset(0)
	await process_frame
	await process_frame
	main._select_graphics_preset(Graphics.HIGH)
	await _settle_graphics()
	_check_applied()
	check(main.graphics.quality == Graphics.HIGH, "New request supersedes an in-flight transition")

	var detached_main := MainScene.instantiate()
	detached_main._apply_graphics()
	check(not detached_main._graphics_applying, "Detached main skips viewport and window work")
	detached_main.free()
	var detached := SubViewport.new()
	main.graphics.apply_viewport(detached)
	detached.free()
	main.graphics.apply_viewport(detached)
	main.graphics.apply_viewport(null)
	main.graphics.apply_display(null)
	var detached_window := Window.new()
	main.graphics.apply_display(detached_window)
	detached_window.free()
	main.graphics.apply_display(detached_window)
	var embedded_window := Window.new()
	var embed_subwindows := root.gui_embed_subwindows
	root.gui_embed_subwindows = true
	root.add_child(embedded_window)
	var embedded_size := embedded_window.size
	var embedded_mode := embedded_window.mode
	await main.graphics.apply_display(embedded_window)
	check(embedded_window.is_embedded() and embedded_window.size == embedded_size
		and embedded_window.mode == embedded_mode, "Embedded window keeps its size and mode")
	embedded_window.free()
	root.gui_embed_subwindows = embed_subwindows
	var scene := Node3D.new()
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	scene.add_child(light)
	main.graphics.apply_scene(scene)
	light.free()
	main.graphics.apply_scene(scene)
	scene.free()
	main.graphics.apply_scene(scene)
	main.graphics.apply_scene(null)
	var defaults := Graphics.new()
	defaults.set_preset(Graphics.HIGH)
	check(main.graphics.quality == Graphics.HIGH and main.graphics.values == defaults.values, "Reset restores all HIGH values")
	check(UI.reduced_motion, "Graphics reset preserves accessibility settings")
	var config := ConfigFile.new()
	check(config.load(path) == OK and config.get_value("graphics", "quality") == Graphics.HIGH, "Reset is saved")
	main.free()
	DirAccess.remove_absolute(path)
	print("GRAPHICS_SETTINGS_RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
