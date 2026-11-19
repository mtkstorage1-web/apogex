## Capture restyled shop modal states, A/D browse frame sequence, and workshop kiosk view.
## Run without --headless: Godot --path . -s tools/capture_shop.gd
extends SceneTree

const OUT_DIR := "res://shots/shop"
const FRAMES_DIR := "res://shots/shop/_frames"


func _initialize() -> void:
	call_deferred("run")


func _settle(frames := 20) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _save_shot(path: String) -> void:
	var err := get_root().get_texture().get_image().save_png(path)
	if err != OK:
		push_error("Failed to save screenshot: %s (err=%d)" % [path, err])
	else:
		print("SAVED ", ProjectSettings.globalize_path(path))


func _tap_key(keycode: int) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	get_root().push_input(down)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	get_root().push_input(up)
	await process_frame


func _encode_gif() -> void:
	var out_abs := ProjectSettings.globalize_path(OUT_DIR)
	var frames_abs := ProjectSettings.globalize_path(FRAMES_DIR)
	var gif_abs := out_abs + "/browse.gif"
	var ffmpeg_bin := "/opt/homebrew/bin/ffmpeg" if FileAccess.file_exists("/opt/homebrew/bin/ffmpeg") else "ffmpeg"
	var args := PackedStringArray([
		"-y",
		"-framerate", "12",
		"-i", frames_abs + "/frame_%03d.png",
		"-vf", "fps=12,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5",
		gif_abs
	])
	var output := []
	var code := OS.execute(ffmpeg_bin, args, output, true)
	if code != 0:
		push_error("ffmpeg failed (exit %d): %s" % [code, "\n".join(output)])
	else:
		print("SAVED ", gif_abs)
	var dir := DirAccess.open(frames_abs)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				dir.remove(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(frames_abs)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAMES_DIR))

	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	g.start_match()
	g._end_cine("intro")
	g._refresh_hud()
	g.hud.banner_time = 0.0
	g.hud.tick(0.1)

	# (a) 01_picker_default.png — default opened state on "port" slot
	g.open_picker("port")
	await _settle(24)
	_save_shot(OUT_DIR + "/01_picker_default.png")

	# (c) Record A/D browse frames across cards while 3D preview rotates
	var frame_idx := 0
	var seq := [KEY_D, KEY_D, KEY_D, KEY_D, KEY_A, KEY_A, KEY_A, KEY_A]
	for hold in 6:
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/frame_%03d.png" % [FRAMES_DIR, frame_idx])
		frame_idx += 1
	for k in seq:
		await _tap_key(k)
		for hold in 6:
			await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/frame_%03d.png" % [FRAMES_DIR, frame_idx])
			frame_idx += 1
	_encode_gif()

	# (a) 02_picker_other_card.png — another card highlighted via A/D browse
	await _tap_key(KEY_D)
	await _tap_key(KEY_D)
	await _settle(16)
	_save_shot(OUT_DIR + "/02_picker_other_card.png")

	# (a) 03_picker_unaffordable.png — unaffordable state (as in tests/shop_picker_runtime_test.gd)
	g.picker.highlight(0)
	g.picker.buy()
	g.sim.credits = 0
	g.picker.highlight(3)
	await _settle(16)
	_save_shot(OUT_DIR + "/03_picker_unaffordable.png")
	g.picker.close()
	g.free()
	await process_frame

	# (b) 04_kiosk_workshop.png — PARTS SHOP kiosk in the workshop from the player side (modeled on --autotest-sp)
	var g_sp = load("res://main.tscn").instantiate()
	root.add_child(g_sp)
	g_sp.set_process(false)
	g_sp.start_workshop()
	var w = g_sp.world
	for step in 70:
		w._machines(0.05)
	g_sp.hud.banner_time = 0.0
	g_sp.hud.toast_time = 0.0
	g_sp.hud.tick(0.1)
	w.player.position = Workshop.KIOSK + Vector3(0, 0, 3.2)
	w.player.heading = 0.0
	w.player.rotation.y = 0.0
	g_sp.yaw = 0.0
	g_sp.pitch = -0.12
	g_sp.first_person = false
	g_sp.follow_cam(w.player, 5.8)
	w._interact()
	w.hud_update(g_sp.hud)
	if w.find_child("ShopKiosk", true, false) == null:
		push_warning("Workshop.setup() did not instantiate ShopKiosk (scripts/shop_kiosk.gd is only referenced in unused Workshop._workshop_building()); WorkshopEnvironment.tscn still shows legacy PartsShopKiosk.")
	await _settle(24)
	_save_shot(OUT_DIR + "/04_kiosk_workshop.png")

	g_sp.free()
	await process_frame
	quit(0)
