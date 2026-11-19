extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(UI.BG_DEEP == Color("#120d1b") and UI.INFO_PWR == Color("#68cce2"), "tokens")
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
	hud.show_banner("EXPEDITION READY", "ALL SYSTEMS NOMINAL")
	hud.toast("Samples secured")
	hud.hurt()
	var sim := Sim.new()
	for dimensions in [Vector2i(1280,720),Vector2i(3004,1805)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		sim.phase = "flight"
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
	view.free()
	await process_frame
	print("HUD_STYLE_RESULT: %d failures" % failures)
	quit(1 if failures else 0)
