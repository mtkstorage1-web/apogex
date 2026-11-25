extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")

func check_header(dimensions: Vector2i, touch_layout: bool) -> void:
	root.content_scale_size = dimensions
	root.size = dimensions
	var hud := Hud.new(touch_layout)
	root.add_child(hud)
	hud.title.text = "DESIGN YOUR SPACECRAFT."
	hud.subtitle.text = "12/12 SLOTS CONFIRMED · CREDITS 10000"
	await process_frame
	await process_frame

	var brand_row := hud.get_node("MissionHeader/BrandRow") as HBoxContainer
	var icon := brand_row.get_node("GameIcon") as TextureRect
	var wordmark := brand_row.get_node("Wordmark") as RichTextLabel
	var objectives_panel := hud.objectives.get_parent().get_parent() as Control
	var location_panel := hud.get_node("LocationClock") as Control
	var context := " at %s (touch: %s)" % [dimensions, touch_layout]
	check(icon.texture != null and icon.texture.resource_path == "res://icon.png", "HUD game icon" + context)
	check(wordmark.get_content_width() > 0 and wordmark.size.x >= wordmark.get_content_width(), "HUD wordmark fits" + context)
	check(icon.get_global_rect().end.x + 8 <= wordmark.get_global_rect().position.x, "HUD icon-to-wordmark gap" + context)
	check(wordmark.get_global_rect().end.x + 8 <= hud.touch_toggle.get_global_rect().position.x, "HUD wordmark-to-toggle gap" + context)
	check(brand_row.get_global_rect().end.y + 4 <= hud.title.get_global_rect().position.y, "HUD brand-to-title gap" + context)
	check(hud.title.get_global_rect().end.y + 4 <= hud.subtitle.get_global_rect().position.y, "HUD title-to-subtitle gap" + context)
	check(hud.subtitle.get_global_rect().end.y + 4 <= objectives_panel.get_global_rect().position.y, "HUD subtitle-to-objectives gap" + context)
	check(brand_row.get_global_rect().end.x < location_panel.get_global_rect().position.x, "HUD location clock clearance" + context)
	hud.free()

func check_crane_layout(dimensions: Vector2i, touch_layout: bool) -> void:
	root.content_scale_size = dimensions
	root.size = dimensions
	var hud := Hud.new(touch_layout)
	root.add_child(hud)
	hud.set_touch_ui(touch_layout)
	hud.tick(0.0)
	var context := " at %s (touch: %s)" % [dimensions, touch_layout]
	var normal_prompt_y := hud.prompt_panel.position.y
	hud.set_prompt("STEER CLAW TO YOUR GSE BAY", "WASD / move · Command Module")
	hud.prompt_panel.size.y = 650.0
	hud.set_crane_mode(true)
	for expanded in [false, true]:
		if expanded:
			hud.set_prompt("E PICK UP COMMAND MODULE", "Align the claw over the highlighted pickup point and keep the module clear of the nearby support structure before lifting it out of the bay.", 0.5)
		await process_frame
		await process_frame
		var prompt_rect := hud.prompt_panel.get_global_rect()
		var crane_rect := hud.crane_mode_panel.get_global_rect()
		var roles_rect := hud.roles_box.get_global_rect()
		check(hud.prompt_panel.visible and hud.crane_mode_panel.visible and hud.roles_box.visible, "Crane HUD elements are visible" + context)
		check(prompt_rect.size.y <= 72.0, "Crane prompt stays compact (%s px)" % prompt_rect.size.y + context)
		check(prompt_rect.end.y + 10.0 <= crane_rect.position.y, "Prompt clears crane banner" + context)
		check(crane_rect.end.y + 10.0 <= roles_rect.position.y, "Crane banner clears role bar" + context)
		check(prompt_rect.position.y >= 0.0 and roles_rect.end.y <= dimensions.y, "Crane stack stays on screen" + context)
	hud.set_crane_mode(false)
	check(not hud.crane_mode_panel.visible and is_equal_approx(hud.prompt_panel.position.y, normal_prompt_y), "Leaving crane mode restores normal prompt position" + context)
	hud.free()

func check_combat_layout(dimensions: Vector2i, touch_layout: bool) -> void:
	root.content_scale_size = dimensions
	root.size = dimensions
	var hud := Hud.new(touch_layout)
	root.add_child(hud)
	hud.set_touch_ui(touch_layout)
	hud.footer.text = "B EQUIP    C ORDERS    Z PING    M MAP    H HELP"
	var combat := CombatHUD.new()
	root.add_child(combat)
	combat.set_vitals(100.0, 50.0, 24, 24, true)
	await process_frame
	hud.tick(0.0)
	await process_frame
	var context := " at %s (touch: %s)" % [dimensions, touch_layout]
	hud.set_prompt("E OPEN PARTS SHOP")
	combat.announce("ELIMINATION", "Planet A scores")
	hud.show_banner("EXPEDITION READY")
	hud.tick(0.0)
	check(not hud.prompt_panel.get_global_rect().intersects(combat.vitals_rect()), "Interaction prompt clears loadout" + context)
	check(not combat.banner_rect().intersects(combat.vitals_rect()), "Combat ribbon clears loadout" + context)
	check(not hud.banner.get_global_rect().intersects(combat.vitals_rect()), "HUD banner clears loadout" + context)
	var roles_rect := hud.roles_box.get_global_rect()
	var combat_rect := combat.vitals_rect()
	check(hud.roles_box.visible and combat_rect.has_area(), "Combat cluster and role bar are visible" + context)
	check(combat_rect.end.y + 10.0 <= roles_rect.position.y, "Combat cluster clears role bar" + context)
	check(combat_rect.position.y >= 0.0 and roles_rect.end.y <= dimensions.y, "Combat stack stays on screen" + context)
	if touch_layout:
		check(not hud.footer.visible, "Keyboard hints stay hidden in touch mode" + context)
	else:
		check(hud.footer.visible and roles_rect.end.y + 10.0 <= hud.footer.get_global_rect().position.y, "Keyboard hints clear role bar" + context)
		hud.tick(7.9)
		check(hud.footer.visible, "Hints remain visible before eight seconds" + context)
		hud.tick(0.2)
		check(not hud.footer.visible, "Hints auto-hide after eight seconds" + context)
		hud.show_control_hints()
		check(hud.footer.visible, "Hints can be shown again" + context)
	combat.free()
	hud.free()

func check_flight_footer(dimensions: Vector2i, touch_layout: bool) -> void:
	root.content_scale_size = dimensions
	root.size = dimensions
	var hud := Hud.new(touch_layout)
	root.add_child(hud)
	hud.set_touch_ui(touch_layout)
	hud.set_prompt("PILOT · DODGE THE DEBRIS", "MOUSE AIM · W THRUST · S BRAKE · A/D STRAFE", 0.5)
	hud.set_flight_footer()
	await process_frame
	hud.tick(0.0)
	await process_frame
	var context := " at %s (touch: %s)" % [dimensions, touch_layout]
	check(hud.footer.text.contains("LIFT") and hud.footer.text.contains("LAND"), "Flight footer advertises lift and landing" + context)
	check(hud.footer.visible == not touch_layout, "Flight footer follows keyboard visibility" + context)
	for interior in [false, true]:
		if interior:
			hud.footer.text = "WASD MOVE · E OPERATE · V VIEW · [I] / TAB EXTERIOR FLIGHT VIEW · 1–4 ROLES · ESC MENU"
			hud.set_prompt("E · RETURN TO PILOT VIEW", "Back to the exterior flight view · or press [I]")
			await process_frame
			hud.tick(0.0)
			await process_frame
		if hud.footer.visible:
			var rect := hud.footer.get_global_rect()
			check(rect.position.x >= 0 and rect.end.x <= dimensions.x and rect.end.y <= dimensions.y,
				"Flight footer fits inside the viewport" + context)
			var roles := hud.roles_box.get_global_rect()
			var prompt := hud.prompt_panel.get_global_rect()
			check(roles.end.y + 10.0 <= rect.position.y and prompt.end.y + 10.0 <= rect.position.y,
				"Flight footer %s clears prompt %s and role bar %s" % [rect, prompt, roles] + context)
	hud.free()

func check_world_labels() -> void:
	var world_labels := preload("res://scripts/ui/world_labels.gd")
	var game = preload("res://main.tscn").instantiate()
	var settings_path := "user://hud_style_%d.cfg" % Time.get_ticks_usec()
	game.settings_path = settings_path
	root.add_child(game)
	game.set_process(false)
	game.autotest = true
	var previous := LobbyPages.play_mode
	LobbyPages.play_mode = "arena_clash"
	game.start_match()
	var earth := game.world as PlanetA
	game.hud.tick(8.1)
	game.pressed_now[KEY_H] = true
	game._process(0.05)
	check(game.hud.footer.visible, "H restores the hints through the live input path")
	check(earth != null and earth.station_labels.size() > 1, "Planet A contains multiple authored stations")
	if earth != null and not earth.station_labels.is_empty():
		var station: Label3D
		for label in earth.station_labels:
			if not label.text.is_empty() and label.get_parent().is_visible_in_tree():
				station = label
				break
		check(station != null, "An authored station is available to inspect")
		if station != null:
			var camera: Camera3D = game.cam
			earth.actor(game.sim.selected).global_position = station.global_position
			camera.global_position = station.global_position + Vector3(0, 0, 4)
			camera.look_at(station.global_position)
			earth.update_station_labels(camera)
			var visible := earth.station_labels.filter(func(label: Label3D) -> bool: return label.is_visible_in_tree())
			check(visible.size() == 1 and visible[0] == station, "Planet A frame only shows its nearest station")
			var actor := earth.actor((game.sim.selected + 1) % 4)
			var tag := actor.name_tag
			tag.show()
			camera.global_position = tag.global_position + Vector3(0, 0, 0.5)
			camera.look_at(tag.global_position)
			actor._process(0)
			var height := tag.font.get_height(tag.font_size) + tag.outline_size
			var pixels := world_labels.pixels_per_meter(camera, tag.global_position) * height * tag.pixel_size
			pixels *= maxf(1.0, root.get_stretch_transform().get_scale().y) * tag.global_basis.get_scale().y
			check(pixels > 0.0 and pixels <= 22.1, "Real crew nameplate is clamped at close camera range")
			camera.global_position += Vector3(0, 0, 45)
			actor._process(0)
			check(tag.modulate.a == 0.0, "Crew nameplate fades beyond forty meters")
	game.queue_free()
	await process_frame
	LobbyPages.play_mode = previous
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))


func run() -> void:
	for color in [UI.ACCENT, UI.GOOD, UI.BAD, UI.HUD_CYAN]:
		check(color.s > 0.4, "Saturated HUD token %s" % color)
	check(UI.font().base_font.resource_path == UI.BODY_FONT_PATH, "Nunito loads")
	check(UI.font(true).base_font.resource_path == UI.DISPLAY_FONT_PATH, "Lilita One loads")
	check(UI.font().base_font.get_font_weight() >= 700, "Nunito uses a bold weight")
	for ratio in [0.0, 0.10, 0.30, 0.60, 1.0]:
		check(UI.ramp_color(ratio) == (UI.BAD if ratio <= 0.1 else UI.WARN if ratio <= 0.3 else UI.GOOD.lerp(UI.WARN,0.35) if ratio <= 0.6 else UI.GOOD), "ramp threshold")
	check(UI.theme() == UI.theme(), "theme cached")
	check(UI.font(false,"res://missing-font.ttf").base_font != null, "missing font fallback")
	check(UI.font().base_font != null and UI.font(true).base_font != null, "configured fonts")
	check(UI.card_style(UI.ACCENT,true) == UI.card_style(UI.ACCENT,true), "cards cached")
	check(UI.theme().get_stylebox("focus","Button").border_width_left == 2, "focus border")
	var source := FileAccess.get_file_as_string("res://scripts/hud.gd")
	var tick := source.get_slice("func tick",1).get_slice("func update_common",0)
	check(not "add_theme_" in tick and not "StyleBox" in tick and not ".bind(" in tick, "tick allocation contract")
	var view := SubViewport.new()
	view.size = Vector2i(640,480)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for i in HudIcons.NAMES.size():
		var icon := HudIcon.new(HudIcons.NAMES[i],UI.TEXT,24)
		icon.position = Vector2((i%12)*32,(i/12)*32)
		view.add_child(icon)
		check(icon.custom_minimum_size == Vector2(24,24), "icon minimum size")
	# Headless dummy renderer may skip _draw; geometry is also exercised explicitly below.
	var hud := Hud.new()
	root.add_child(hud)
	check(hud.location_label.get_theme_constant("outline_size") >= 4 and hud.objectives.get_theme_constant("outline_size") >= 4, "HUD text has dark outlines")
	hud.show_banner("EXPEDITION READY", "ALL SYSTEMS NOMINAL")
	hud.toast("Samples secured")
	hud.hurt()
	var sim := Sim.new()
	for dimensions in [Vector2i(1280,720),Vector2i(3004,1805)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		sim.set_location("space")
		hud.update_common(sim,0)
		await process_frame
		await process_frame
		for c in [hud.crosshair,hud.visual_status,hud.radar.get_parent().get_parent(),hud.board.get_parent(),hud.get_node("CrewAdvisor"),hud.roles_box,hud.tactical_panel,hud.banner]:
			var rect: Rect2 = c.get_global_rect()
			check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= dimensions.x+1 and rect.end.y <= dimensions.y+1, "HUD fits %s: %s %s" % [dimensions,c.name,rect])
	for icon in view.get_children(): check(icon.draw_count > 0, "icon draw smoke: " + icon.icon)
	UI.reduced_motion = true
	hud.hurt()
	check(hud.damage_flash.color.a == 0, "reduced motion damage")
	UI.reduced_motion = false
	hud.free()
	await check_header(Vector2i(1600, 900), false)
	await check_header(Vector2i(1366, 1024), true)
	await check_crane_layout(Vector2i(1600, 900), false)
	await check_crane_layout(Vector2i(1366, 1024), true)
	await check_crane_layout(Vector2i(3004, 1805), true)
	await check_combat_layout(Vector2i(1600, 900), false)
	await check_combat_layout(Vector2i(1366, 1024), true)
	await check_combat_layout(Vector2i(1366, 1024), false)
	await check_combat_layout(Vector2i(3004, 1805), true)
	await check_flight_footer(Vector2i(1280, 720), false)
	await check_flight_footer(Vector2i(1366, 1024), true)
	await check_world_labels()
	view.free()
	await process_frame
	print("HUD_STYLE_RESULT: %d/%d checks passed (%d failures)" % [checks - failures, checks, failures])
	quit(1 if failures else 0)
