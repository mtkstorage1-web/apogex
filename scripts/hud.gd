## In-match HUD: phase strip + clock, crew cards, objectives, radar, faction board, prompt, vitals, toasts.
class_name Hud
extends Control

const STEPS := ["BUILD", "OUTFIT", "ROUTE", "FLIGHT", "MOON", "DELIVER"]


class Radar extends Control:
	var _redraw_elapsed := 0.05
	var _vertices := PackedVector2Array()
	var _chevron := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var sweep := 0.0

	func _process(dt: float) -> void:
		_redraw_elapsed += dt
		sweep = fmod(sweep + dt * PI / 2.0, TAU)

	func request_redraw() -> void:
		if _redraw_elapsed >= 0.05:
			_redraw_elapsed = fmod(_redraw_elapsed, 0.05)
			queue_redraw()

	var points: Array = []   # {p: Vector2 (relative xz in meters), c: Color, s: float, ring: bool, optional dist: float}
	var range_m := 60.0
	var title := "EARTH"
	var cover_shapes: Array = []
	var show_labels := false

	static func point_distance(point: Dictionary) -> float:
		return point.get("dist", point["p"].length())

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var c := size * 0.5
		var font := UI.font()
		draw_circle(c, r, Color(0.08, 0.06, 0.12, 0.8))
		draw_arc(c, r, 0, TAU, 64, UI.LINE_STRONG, 1.5)
		draw_arc(c, r * 0.5, 0, TAU, 48, UI.LINE_SUBTLE, 1.0)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(1, 1, 1, 0.06))
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(1, 1, 1, 0.06))
		for shape in cover_shapes:
			_vertices.resize(shape.size())
			for i in shape.size(): _vertices[i] = c + shape[i] / range_m * r
			draw_colored_polygon(_vertices, Color(0.3, 0.5, 0.56, 0.22))
		for fraction: float in [0.5, 1.0]:
			var label_pos := c + Vector2(0.6, -0.8) * r * fraction
			draw_string(font, label_pos + Vector2(4, 0), "%dm" % roundi(range_m * fraction), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.TEXT)
		var scale_start := Vector2(6, size.y - 7)
		var scale_end := scale_start + Vector2(r * 0.5, 0)
		draw_line(scale_start, scale_end, UI.MUTED, 1.0)
		for endpoint: Vector2 in [scale_start, scale_end]:
			draw_line(endpoint - Vector2(0, 3), endpoint + Vector2(0, 3), UI.MUTED, 1.0)
		draw_string(font, scale_start - Vector2(0, 5), "0–%dm" % roundi(range_m * 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.MUTED)
		var label_rects: Array[Rect2] = []
		for p in points:
			var v: Vector2 = p["p"] / range_m * r
			if v.length() > r - 3.0:
				v = v.normalized() * (r - 3.0)
			if p.get("ring", false):
				draw_arc(c + v, p["s"], 0, TAU, 16, p["c"], 2.0)
				if p["s"] >= 7.0: draw_arc(c + v, p["s"] + 2.0 + fmod(sweep, 1.0) * 4.0, 0, TAU, 24, UI.ACCENT, 1.5)
			else:
				draw_circle(c + v, p["s"], p["c"])
			var label: String = p.get("label", "")
			if show_labels or p.get("ring", false) or p.get("priority", false) or label != "":
				var meters := "%dm" % roundi(point_distance(p))
				var caption := "%s · %s" % [label, meters] if show_labels and label != "" else meters
				var font_size := 12 if show_labels else 10
				var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				var pos := c + v + Vector2(float(p["s"]) + 3.0, -3.0)
				if pos.x + width > size.x:
					pos.x = maxf(0.0, c.x + v.x - float(p["s"]) - 3.0 - width)
				var ascent := font.get_ascent(font_size)
				var label_size := Vector2(width, font.get_height(font_size))
				pos.y = clampf(pos.y, ascent, size.y - font.get_descent(font_size))
				var bounds := Rect2(pos - Vector2(0.0, ascent), label_size).grow(2.0)
				var start_y := bounds.position.y
				for direction: float in [-1.0, 1.0]:
					bounds.position.y = start_y
					var index := 0
					while index < label_rects.size():
						var previous := label_rects[index]
						if bounds.intersects(previous):
							bounds.position.y = previous.position.y - bounds.size.y if direction < 0.0 else previous.end.y
							index = 0
						else:
							index += 1
					if bounds.position.y >= -2.0 and bounds.end.y <= size.y + 2.0:
						break
				if bounds.end.y > size.y + 2.0:
					continue
				pos.y += bounds.position.y - start_y
				label_rects.append(bounds)
				draw_string_outline(font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, UI.BG_DEEP)
				draw_string(font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, p["c"])
		# Player chevron.
		_chevron[0] = c + Vector2(0, -8)
		_chevron[1] = c + Vector2(5, 5)
		_chevron[2] = c + Vector2(-5, 5)
		draw_colored_polygon(_chevron, UI.ACCENT)
		if not UI.reduced_motion: draw_arc(c, r * 0.96, sweep - PI / 9, sweep, 10, Color(0.92, 0.65, 0.40, 0.09), 3, true)


var phase_labels: Array = []
var clock: Label
var crew_cards: Array = []
var title: Label
var subtitle: Label
var objectives: RichTextLabel
var radar: Radar
var radar_title: Label
var board: VBoxContainer
var board_rows: Array = []
var prompt_panel: PanelContainer
var prompt_title: Label
var prompt_detail: Label
var prompt_bar: ProgressBar
var toast_label: Label
var toast_time := 0.0
var _toast_tween: Tween
var _banner_tween: Tween
var _damage_tween: Tween
var _pulse_tween: Tween
var _pulse_band := -1
var _toast_out := false
var _banner_out := false
var banner: Label
var banner_sub: Label
var banner_time := 0.0
var vitals_panel: PanelContainer
var vitals: RichTextLabel
var station_panel: PanelContainer
var station: RichTextLabel
var roles_box: HBoxContainer
var role_buttons: Array = []
var crosshair: Label
var footer: Label
var damage_flash: ColorRect
var advisor: Label
var orders_label: Label
var tactical_panel: PanelContainer
var tactical_radar: Radar
var tactical_heading: Label
var tactical_distance: Label
var hit_time := 0.0
var toast_queue: Array = []
var style_selected := -1
var style_phase := -1
var visual_status: PanelContainer
var status_rows := {}
var ammo_counter: Label
var weapon_caption: Label
var mobile_controls: MobileControls
var touch_toggle: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.theme()
	_build()


func _ignore_all(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_all(c)


## Dark translucent pill so small HUD text stays readable over bright sky / grass.
static func _pill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.14, 0.72)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _build() -> void:
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.9, 0.1, 0.2, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(damage_flash)

	# Brand (compact top-left).
	var brand := UI.rich("[b]APOG[color=#eaa665]EX[/color][/b]", 20)
	brand.add_theme_constant_override("outline_size", 5)
	brand.add_theme_color_override("font_outline_color", Color(0.07, 0.05, 0.11, 0.8))
	brand.position = Vector2(16, 10)
	brand.size = Vector2(140, 28)
	add_child(brand)

	# Compact phase strip + clock.
	var strip := UI.panel(Vector2(0, 30), Color(0.08, 0.07, 0.13, 0.84))
	strip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	strip.position = Vector2(-260, 8)
	strip.custom_minimum_size = Vector2(520, 30)
	add_child(strip)
	var sh := UI.hbox(7)
	strip.add_child(sh)
	for i in STEPS.size():
		var l := UI.label(STEPS[i], 11, UI.DIM)
		phase_labels.append(l)
		sh.add_child(l)
		if i < STEPS.size() - 1:
			sh.add_child(UI.label("·", 11, Color(1, 1, 1, 0.2)))
	sh.add_child(UI.spacer(0, 4, true))
	clock = UI.mono_label("14:00", 16, UI.TEXT)
	sh.add_child(clock)

	# Slim crew cards.
	var cards := UI.hbox(5)
	cards.set_anchors_preset(Control.PRESET_CENTER_TOP)
	cards.position = Vector2(-257, 42)
	add_child(cards)
	for i in 4:
		var p := UI.panel(Vector2(124, 38), Color(0.08, 0.07, 0.13, 0.80))
		var v := UI.vbox(1)
		p.add_child(v)
		var top_row := UI.hbox(4)
		var n := UI.label(Sim.SPECIALISTS[i]["name"], 11, Sim.role_color(i))
		var r := UI.label(Sim.SPECIALISTS[i]["role"].left(3).to_upper(), 9, UI.MUTED)
		top_row.add_child(n)
		top_row.add_child(UI.spacer(0, 2, true))
		top_row.add_child(r)
		var s := UI.label("STARTING", 9, UI.TEXT)
		var b := UI.bar(Sim.role_color(i), 0.0, 2)
		v.add_child(top_row)
		v.add_child(s)
		v.add_child(b)
		cards.add_child(p)
		crew_cards.append({"panel": p, "status": s, "bar": b, "name": n})

	# Compact title + objectives.
	title = UI.label("PREPARE EXPEDITION", 13, UI.TEXT)
	title.position = Vector2(16, 38)
	add_child(title)
	subtitle = UI.label("", 10, UI.TEXT)
	subtitle.position = Vector2(14, 58)
	subtitle.add_theme_stylebox_override("normal", _pill_style())
	add_child(subtitle)
	var op := UI.panel(Vector2(228, 0), Color(0.08, 0.07, 0.13, 0.76))
	op.position = Vector2(14, 86)
	add_child(op)
	objectives = UI.rich("", 12)
	objectives.custom_minimum_size = Vector2(204, 0)
	var objective_box := UI.vbox(2)
	objective_box.add_child(HudIcon.new("objective", UI.ACCENT, 13))
	objective_box.add_child(objectives)
	op.add_child(objective_box)

	# Compact radar + faction board.
	var right := UI.vbox(6)
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-180, 10)
	add_child(right)
	var rp := UI.panel(Vector2(168, 0), Color(0.08, 0.07, 0.13, 0.80))
	right.add_child(rp)
	var rv := UI.vbox(3)
	rp.add_child(rv)
	radar_title = UI.label("EARTH · BUILD", 10, UI.MUTED)
	var radar_row := UI.hbox(4)
	radar_row.add_child(HudIcon.new("radar", UI.MUTED, 12))
	radar_row.add_child(radar_title)
	rv.add_child(radar_row)
	radar = Radar.new()
	radar.custom_minimum_size = Vector2(144, 144)
	rv.add_child(radar)
	var bp := UI.panel(Vector2(168, 0), Color(0.08, 0.07, 0.13, 0.80))
	right.add_child(bp)
	board = UI.vbox(2)
	bp.add_child(board)
	board.add_child(UI.label("FLAGS · DELIVERED", 9, UI.MUTED))
	for i in 4:
		var row := UI.hbox(4)
		var dot := UI.label(Sim.FACTIONS[i]["symbol"] + " " + Sim.FACTIONS[i]["name"].left(6), 10, Sim.faction_color(i))
		dot.custom_minimum_size = Vector2(68, 0)
		var ph := UI.label("build", 9, UI.MUTED)
		ph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.custom_minimum_size.x = 34
		var sc := UI.mono_label("0", 14, UI.TEXT)
		row.add_child(dot)
		row.add_child(ph)
		row.add_child(sc)
		board.add_child(row)
		board_rows.append({"phase": ph, "score": sc})
	var pool := UI.label("", 9, UI.MUTED)
	pool.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pool.custom_minimum_size.x = 148
	board.add_child(pool)
	board_rows.append({"pool": pool})

	# Prompt.
	prompt_panel = UI.panel(Vector2(420, 0), Color(0.1, 0.08, 0.14, 0.9))
	prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_panel.position = Vector2(-210, -150)
	add_child(prompt_panel)
	var pv := UI.vbox(4)
	prompt_panel.add_child(pv)
	prompt_title = UI.label("", 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_detail = UI.label("", 12, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_bar = UI.bar(UI.ACCENT, 0.0, 5)
	pv.add_child(prompt_title)
	pv.add_child(prompt_detail)
	pv.add_child(prompt_bar)

	# Toast + banner.
	toast_label = UI.label("", 14, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-400, 240)
	toast_label.size = Vector2(800, 30)
	toast_label.add_theme_stylebox_override("normal", UI.component("toast"))
	add_child(toast_label)
	banner = UI.label("", 54, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.position = Vector2(-600, -110)
	banner.add_theme_constant_override("outline_size", 6)
	banner.add_theme_color_override("font_outline_color", Color("#120d1bcc"))
	banner.size = Vector2(1200, 70)
	add_child(banner)
	banner_sub = UI.label("", 16, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	banner_sub.position = Vector2(-600, -36)
	banner_sub.size = Vector2(1200, 30)
	add_child(banner_sub)

	# Vitals (flight / surface).
	vitals_panel = UI.panel(Vector2(250, 0), Color(0.1, 0.08, 0.14, 0.88))
	vitals_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	vitals_panel.position = Vector2(-270, -250)
	add_child(vitals_panel)
	vitals = UI.rich("", 13)
	vitals.custom_minimum_size = Vector2(225, 0)
	vitals_panel.add_child(vitals)

	# Station panel (engineer / raider consoles in flight).
	station_panel = UI.panel(Vector2(300, 0), Color(0.1, 0.08, 0.14, 0.9))
	station_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	station_panel.position = Vector2(20, 40)
	add_child(station_panel)
	station = UI.rich("", 14)
	station.custom_minimum_size = Vector2(280, 0)
	station_panel.add_child(station)

	# Compact role bar.
	roles_box = UI.hbox(5)
	roles_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	roles_box.position = Vector2(-200, -54)
	add_child(roles_box)
	for i in 4:
		var l := UI.label("%d %s" % [i + 1, Sim.SPECIALISTS[i]["name"]], 11, UI.TEXT)
		l.add_theme_stylebox_override("normal", UI.style(Color(0.08, 0.07, 0.13, 0.82), UI.LINE, 4, 8))
		l.custom_minimum_size = Vector2(96, 32)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		roles_box.add_child(l)
		role_buttons.append(l)

	crosshair = UI.label("+", 26, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-20, -20)
	crosshair.size = Vector2(40, 40)
	add_child(crosshair)

	footer = UI.label("", 11, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	footer.position = Vector2(-500, -28)
	footer.size = Vector2(1000, 22)
	footer.add_theme_stylebox_override("normal", _pill_style())
	add_child(footer)
	# Persistent next-action guidance sits above the role bar.
	var advice_panel := UI.panel(Vector2(340, 0), Color(0.035, 0.065, 0.09, 0.94))
	advice_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	advice_panel.position = Vector2(20, -150)
	add_child(advice_panel)
	var advice_box := UI.vbox(5)
	advice_panel.add_child(advice_box)
	orders_label = UI.label("CREW LINK / OFFLINE", 10, UI.ACCENT)
	var orders_row := UI.hbox(6)
	orders_row.add_child(HudIcon.new("warning", UI.ACCENT, 14))
	orders_row.add_child(orders_label)
	advice_box.add_child(orders_row)
	advisor = UI.label("", 12, UI.TEXT)
	advisor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advisor.custom_minimum_size = Vector2(310, 36)
	advice_box.add_child(advisor)
	advice_panel.name = "CrewAdvisor"
	tactical_panel = UI.panel(Vector2(520, 520), Color(0.025, 0.045, 0.065, 0.98))
	tactical_panel.set_anchors_preset(Control.PRESET_CENTER)
	tactical_panel.position = Vector2(-260, -260)
	tactical_panel.z_index = 20
	add_child(tactical_panel)
	var tactical_box := Control.new()
	tactical_box.custom_minimum_size = Vector2(480, 480)
	tactical_panel.add_child(tactical_box)
	tactical_heading = UI.label("LIVE TACTICAL MAP", 18, UI.ACCENT)
	tactical_box.add_child(tactical_heading)
	tactical_distance = UI.label("", 12, UI.TEXT)
	tactical_distance.position.y = 24
	tactical_box.add_child(tactical_distance)
	tactical_radar = Radar.new()
	tactical_radar.show_labels = true
	tactical_radar.position = Vector2(38, 38)
	tactical_radar.size = Vector2(404, 404)
	tactical_box.add_child(tactical_radar)
	var legend := UI.wrapped_label("▲ YOU · SOLID: SAMPLES / CREW · RINGS: SHIPS / LOOSE SAMPLES", 10, UI.TEXT)
	legend.position = Vector2(0, 444)
	legend.size.x = 480
	tactical_box.add_child(legend)
	var map_help := UI.label("C crew order · Z priority · M close · Match remains live", 10, UI.MUTED)
	map_help.position = Vector2(0, 470)
	tactical_box.add_child(map_help)
	tactical_panel.visible = false
	visual_status = UI.panel(Vector2(250, 0), Color(0.025, 0.045, 0.065, 0.94))
	visual_status.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	visual_status.position = Vector2(-280, -330)
	add_child(visual_status)
	var status_box := UI.vbox(7)
	visual_status.add_child(status_box)
	weapon_caption = UI.label("VESSEL", 11, UI.MUTED)
	ammo_counter = UI.mono_label("100", 40, UI.TEXT)
	var weapon_row := UI.hbox(6)
	weapon_row.add_child(HudIcon.new("ammo", UI.TEXT, 16))
	weapon_row.add_child(weapon_caption)
	status_box.add_child(weapon_row)
	status_box.add_child(ammo_counter)
	for metric in [["health", "HP", "#91dfbd"], ["energy", "PWR", "#68cce2"], ["heat", "HEAT", "#eca262"], ["pressure", "AIR", "#aabfe4"], ["co2", "CO₂", "#b6a7dc"], ["food", "CREW", "#a3d199"], ["fuel", "FUEL", "#eaa665"], ["ammo", "MAG", "#f3eef8"]]:
		var row := UI.hbox(6)
		var ids := {"health": "health", "energy": "power", "heat": "heat", "pressure": "pressure", "co2": "co2", "food": "crew", "fuel": "fuel", "ammo": "ammo"}
		row.add_child(HudIcon.new(ids[metric[0]], Color(metric[2]), 14))
		var label := UI.label(metric[1], 10, UI.MUTED)
		label.custom_minimum_size.x = 35
		row.add_child(label)
		var fill := UI.bar(Color(metric[2]), 1.0, 6)
		fill.custom_minimum_size = Vector2(108, 6)
		fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(fill)
		var reading := UI.mono_label("100", 11, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		reading.custom_minimum_size.x = 36
		row.add_child(reading)
		status_box.add_child(row)
		status_rows[metric[0]] = {"row": row, "label": label, "fill": fill, "reading": reading, "nominal": Color(metric[2])}
	visual_status.visible = false
	_ignore_all(self)
	_build_touch()


## Touch overlay sits inside the HUD layer (above the 3D world, below menu_layer modals).
func _build_touch() -> void:
	mobile_controls = MobileControls.new()
	add_child(mobile_controls)
	touch_toggle = Button.new()
	touch_toggle.text = "TOUCH UI"
	touch_toggle.toggle_mode = true
	touch_toggle.focus_mode = Control.FOCUS_NONE
	touch_toggle.add_theme_font_size_override("font_size", 11)
	var sb := _pill_style()
	sb.border_color = Color(0.92, 0.65, 0.4, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		touch_toggle.add_theme_stylebox_override(st, sb)
	# Right of the APOGEX wordmark, left of the centred phase strip: clear of the
	# title (y58), the slots pill (y92) and the strip (centre ±330).
	touch_toggle.position = Vector2(150, 22)
	touch_toggle.size = Vector2(84, 24)
	touch_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	touch_toggle.toggled.connect(set_touch_ui)
	add_child(touch_toggle)
	touch_toggle.set_pressed_no_signal(mobile_controls.is_touch_visible())


func set_touch_ui(on: bool) -> void:
	mobile_controls.set_touch_visible(on)
	touch_toggle.set_pressed_no_signal(on)
	footer.visible = not on


func touch_ui_visible() -> bool:
	return mobile_controls != null and mobile_controls.is_touch_visible()


## Single-player: reuse the phase strip for mission steps and hide the competitive widgets.
func set_sp_steps(names: Array, idx: int) -> void:
	for i in phase_labels.size():
		var l: Label = phase_labels[i]
		l.text = names[i] if i < names.size() else ""
		if i == idx:
			l.add_theme_color_override("font_color", UI.ACCENT_DARK)
			l.add_theme_stylebox_override("normal", UI.style(UI.ACCENT, UI.ACCENT, 10, 8))
		else:
			l.add_theme_color_override("font_color", UI.TEXT if i < idx else UI.DIM)
			l.remove_theme_stylebox_override("normal")


func set_mode(sp: bool) -> void:
	for c in crew_cards:
		c["panel"].get_parent().visible = not sp
	board.get_parent().visible = not sp
	roles_box.visible = not sp
	get_node("CrewAdvisor").visible = not sp
	close_tactical()
	visual_status.visible = false
	style_selected = -1
	style_phase = -1
	if not sp:
		for i in phase_labels.size():
			phase_labels[i].text = STEPS[i]


func set_prompt(t: String, detail := "", progress := -1.0) -> void:
	prompt_panel.visible = t != ""
	prompt_title.text = t
	prompt_detail.text = detail
	prompt_detail.visible = detail != ""
	prompt_bar.visible = progress >= 0.0
	prompt_bar.value = maxf(0.0, progress)


func toast(t: String, seconds := 3.2) -> void:
	if toast_time > 0.0:
		if toast_queue.size() >= 5: toast_queue.pop_front()
		toast_queue.append({"text": t, "duration": seconds})
		return
	toast_label.text = "  " + t + "  "
	toast_time = seconds
	_toast_out = false
	toast_label.visible = true
	if _toast_tween: _toast_tween.kill()
	toast_label.modulate.a = 1.0 if UI.reduced_motion else 0.0
	if not UI.reduced_motion:
		toast_label.position.y = 248
		_toast_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.18)
		_toast_tween.tween_property(toast_label, "position:y", 240.0, 0.18)

func confirm_hit() -> void:
	hit_time = 0.18

func toggle_tactical() -> void:
	tactical_panel.visible = not tactical_panel.visible

func close_tactical() -> void:
	if tactical_panel: tactical_panel.visible = false

func update_tactical(points: Array, heading: String, radius := 95.0) -> void:
	tactical_heading.text = heading
	tactical_radar.points = points
	tactical_radar.range_m = radius
	var nearest := INF
	for point in points:
		nearest = minf(nearest, Radar.point_distance(point))
	var nearest_text := "%dm" % roundi(nearest) if is_finite(nearest) else "—"
	tactical_distance.text = "RANGE %dm  ·  NEAREST %s" % [roundi(radius), nearest_text]
	if tactical_panel.visible: tactical_radar.request_redraw()



func show_banner(t: String, sub := "", seconds := 2.6) -> void:
	banner.text = t
	banner_sub.text = sub
	banner_time = seconds
	_banner_out = false
	if _banner_tween: _banner_tween.kill()
	banner.modulate.a = 1
	banner_sub.modulate.a = 1
	banner.scale = Vector2.ONE
	if not UI.reduced_motion:
		banner.modulate.a = 0
		banner.scale = Vector2.ONE * 0.96
		_banner_tween = create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.25)
		_banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.25)


func hurt(amount := 0.35) -> void:
	if _damage_tween: _damage_tween.kill()
	damage_flash.color.a = 0.0 if UI.reduced_motion else minf(0.35, amount)
	if not UI.reduced_motion:
		_damage_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_damage_tween.tween_property(damage_flash, "color:a", 0.0, 0.30)


var _common_elapsed := 0.1
var _crosshair_hit := false
var _shop_sim: Sim
var _shop_refresh: Callable
var _summary_loadout := {}
var _summary_missing: Array = []
var _summary_credits := -1

func tick(dt: float) -> void:
	_layout_roles()
	_common_elapsed += dt
	# Keybind bar is desktop-only; keep it hidden while touch controls are up.
	var want_footer := not touch_ui_visible()
	if footer.visible != want_footer:
		footer.visible = want_footer
	hit_time = maxf(0.0, hit_time - dt)
	# On the Moon CombatHUD draws its own blooming 4-tick crosshair; mute the legacy '+'.
	var combat_active := is_inside_tree() and get_tree().get_first_node_in_group("combat_hud") != null
	crosshair.self_modulate.a = 0.0 if combat_active else 1.0
	var hit := hit_time > 0.0
	if hit != _crosshair_hit:
		_crosshair_hit = hit
		crosshair.text = "×" if hit else "+"
		crosshair.modulate = UI.ACCENT if hit else Color.WHITE
	toast_time -= dt
	if toast_time <= 0 and not _toast_out:
		_toast_out = true
		if _toast_tween: _toast_tween.kill()
		_toast_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.0 if UI.reduced_motion else 0.22)
	if toast_time <= -0.22 and not toast_queue.is_empty():
		var message: Dictionary = toast_queue.pop_front()
		toast(message["text"], message["duration"])
	banner_time -= dt
	if banner_time <= 0.50 and not _banner_out:
		_banner_out = true
		if _banner_tween: _banner_tween.kill()
		_banner_tween = create_tween().set_parallel()
		_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.0 if UI.reduced_motion else 0.50)
		_banner_tween.tween_property(banner_sub, "modulate:a", 0.0, 0.0 if UI.reduced_motion else 0.50)



func update_common(sim: Sim, selected: int) -> void:
	if mobile_controls != null:
		mobile_controls.set_primary_label("FIRE" if sim.phase in ["flight", "surface"] else "ACTION")
	if sim.phase == "flight":
		ammo_counter.text = "%d%%" % roundi(sim.hull)
		_status("health", sim.hull / 100.0, str(roundi(sim.hull)))
	if _common_elapsed < 0.1 and style_selected == selected and style_phase == sim.strip_index(): return
	_common_elapsed = fmod(_common_elapsed, 0.1)
	update_shop(sim)
	advisor.text = _short_advice(sim)
	visual_status.visible = sim.phase in ["flight", "surface"]
	if visual_status.visible: vitals_panel.visible = false
	status_rows["ammo"]["row"].visible = sim.phase == "surface"
	status_rows["co2"]["row"].visible = sim.phase == "flight"
	status_rows["food"]["row"].visible = sim.phase == "flight"
	_status("fuel", sim.propellant / Sim.BASE_PROPELLANT, "%.0f" % sim.propellant)
	if sim.phase == "flight":
		weapon_caption.text = str(ShipCatalog.loadout_stats(sim.loadout)["design_name"]).to_upper() + " / HULL"
		ammo_counter.text = "%d%%" % roundi(sim.hull)
		_status("health", sim.hull / 100.0, str(roundi(sim.hull)))
		_status("energy", sim.power / sim.power_capacity, "%.1f" % sim.power)
		_status("heat", sim.temperature / 110.0, "%d°" % sim.temperature)
		_status("pressure", sim.pressure / 101.3, str(roundi(sim.pressure)))
		_status("co2", sim.co2 / 5000.0, str(roundi(sim.co2)))
		_status("food", sim.crew_nutrition / 100.0, "%d%%" % sim.crew_nutrition)
		status_rows["energy"]["label"].text = "PWR"
		status_rows["heat"]["label"].text = "HEAT"
		status_rows["pressure"]["label"].text = "AIR"

	orders_label.text = "%s  /  C ORDER · Z PING · M MAP" % sim.crew_order.to_upper() if sim.phase == "surface" else "MISSION ADVISOR / " + sim.phase.to_upper()
	if sim.phase != "surface": update_tactical(radar.points, "LIVE RADAR · " + sim.phase.to_upper(), radar.range_m * 1.6)
	var idx := sim.strip_index()
	if idx != style_phase:
		style_phase = idx
		for i in phase_labels.size():
			var l: Label = phase_labels[i]
			if i == idx:
				l.add_theme_color_override("font_color", UI.ACCENT_DARK)
				l.add_theme_stylebox_override("normal", UI.style(UI.ACCENT, UI.ACCENT, 10, 8))
			else:
				l.add_theme_color_override("font_color", UI.TEXT if i < idx else UI.DIM)
				l.remove_theme_stylebox_override("normal")
	clock.text = UI.fmt_time(sim.limit - sim.time)
	var clock_bad := sim.limit - sim.time < 60.0
	if not clock.has_meta("bad") or clock.get_meta("bad") != clock_bad:
		clock.set_meta("bad", clock_bad)
		clock.add_theme_color_override("font_color", UI.BAD if clock_bad else UI.TEXT)
	if selected != style_selected:
		style_selected = selected
		for i in 4:
			var crew_card = crew_cards[i]
			var sb: StyleBoxFlat = UI.style(Color(0.1, 0.08, 0.14, 0.85), UI.ACCENT if i == selected else UI.LINE, 4, 10, 2 if i == selected else 1)
			crew_card["panel"].add_theme_stylebox_override("panel", sb)
			var rb: Label = role_buttons[i]
			rb.add_theme_stylebox_override("normal", UI.style(Color(0.3, 0.22, 0.14, 0.9) if i == selected else Color(0.1, 0.08, 0.14, 0.85), UI.ACCENT if i == selected else UI.LINE, 4, 10))
	for i in 4:
		var t = sim.teams[i]
		var row = board_rows[i]
		row["phase"].text = t["phase"].to_upper()
		row["score"].text = str(t["delivered"]) + ("  +%d" % t["onboard"] if t["onboard"] > 0 else "")
	var chud := get_tree().get_first_node_in_group("combat_hud") if is_inside_tree() else null
	if chud != null and chud.has_method("set_team_scores"):
		var scores: Array = []
		for i in 4:
			var ft: Dictionary = Sim.FACTIONS[i]
			scores.append({"name": ft["name"], "color": Color(ft["color"]), "delivered": sim.teams[i]["delivered"], "onboard": sim.teams[i]["onboard"]})
		chud.set_team_scores(scores)
	var flag_counts := sim.flag_counts(0)
	board_rows[4]["pool"].text = "AT SITES %d · LOOSE %d · ONBOARD %d/%d" % [flag_counts["sites"], flag_counts["loose"], flag_counts["onboard"], sim.cargo_capacity]


func set_crew_status(i: int, status: String, progress: float) -> void:
	crew_cards[i]["status"].text = status
	crew_cards[i]["bar"].value = progress


func _status(id: String, value: float, text: String) -> void:
	var row: Dictionary = status_rows[id]
	UI.smooth_bar(row["fill"], value)
	var color := UI.ramp_color(value, row["nominal"])
	if row.get("color") != color:
		row["color"] = color
		row["fill"].add_theme_stylebox_override("fill", UI.style(color, Color.TRANSPARENT, 2, 0, 0))
		row["reading"].add_theme_color_override("font_color", color)
	if id == "health": _pulse(value)
	status_rows[id]["reading"].text = text

func field_status(hp: float, ammo: int, reloading: float, drawn: bool, role: int, sim: Sim, down: float) -> void:
	visual_status.visible = true
	status_rows["ammo"]["row"].visible = drawn
	_status("ammo", float(ammo) / 24.0, str(ammo))
	vitals_panel.visible = false
	weapon_caption.text = "SCANNER" if role == 3 else ("RELOADING" if reloading > 0.0 else (Sim.SPECIALISTS[role]["weapon"].to_upper() + " / B" if drawn else "HANDS FREE / B DRAW"))
	var ammo_color := UI.ramp_color(float(ammo) / 24.0, UI.TEXT) if drawn and role != 3 else UI.ramp_color(hp / 100.0)
	if ammo_counter.get_meta("color", Color.TRANSPARENT) != ammo_color:
		ammo_counter.set_meta("color", ammo_color)
		ammo_counter.add_theme_color_override("font_color", ammo_color)
	ammo_counter.text = "%.1fs" % down if down > 0.0 else ("%d%%" % hp if role == 3 or not drawn else "%02d / 24" % ammo)
	_status("health", 0.0 if down > 0.0 else hp / 100.0, "DOWN" if down > 0.0 else str(roundi(hp)))
	status_rows["energy"]["label"].text = "Q"
	_status("energy", 1.0 - sim.ability_cd[role] / 12.0, "RDY" if sim.ability_cd[role] <= 0.0 else "%.0fs" % sim.ability_cd[role])
	status_rows["heat"]["label"].text = "F"
	_status("heat", sim.ultimate[role] / 100.0, "%d%%" % sim.ultimate[role])
	status_rows["pressure"]["label"].text = "CARGO"
	_status("pressure", float(sim.flag_counts(0)["onboard"]) / sim.cargo_capacity, "%d/%d" % [sim.flag_counts(0)["onboard"], sim.cargo_capacity])

func _short_advice(sim: Sim) -> String:
	match sim.phase:
		"surface":
			if sim.flag_counts(0)["carried"] > 0: return "Escort samples → ship ramp"
			if sim.flag_counts(0)["onboard"] >= sim.cargo_capacity: return "Cargo full → south gate → T depart"
			if sim.limit - sim.time < 95.0: return "Return window closing → T at ship"
			return "Secure samples · Raider [4] extracts"
		"flight":
			if sim.fault != null or sim.co2 > 2000.0 or sim.temperature > 70.0 or sim.power < 0.6: return "⚠ Systems → Engineer [2]"
			for panel in sim.panels:
				if panel["health"] < 60: return "⚠ Damaged plate → Raider [4]"
			return "Pilot [1] evade · Gunner [3] defend"
		"assembly": return "Shop → choose variants → confirm all 12 → desk" if sim.shop_open else "Shop → your rack → build slots"
		"outfit": return "Stow cargo → finish systems checks"
		"route": return "Choose route · protect return fuel"
		"delivery": return "Delivery pad → hold E"
	return "Bring your crew home"


var shop_summary: Label
var shop_panel: PanelContainer

func update_shop(sim: Sim) -> void:
	if _shop_sim != sim:
		if is_instance_valid(_shop_sim): _shop_sim.shop_changed.disconnect(_shop_refresh)
		_shop_sim = sim
		_shop_refresh = update_shop.bind(sim)
		sim.shop_changed.connect(_shop_refresh)
		_summary_credits = -1
	if not sim.shop_open and not is_instance_valid(shop_panel): return
	if not is_instance_valid(shop_panel):
		# Ultra-compact 2-line ship summary pill docked neatly under the left objectives card.
		shop_panel = UI.panel(Vector2(228, 0), Color(0.08, 0.07, 0.13, 0.78))
		shop_panel.position = Vector2(14, 178)
		shop_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shop_summary = UI.wrapped_label("", 11)
		shop_summary.custom_minimum_size.x = 204
		shop_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shop_box := UI.vbox(2)
		shop_box.add_child(shop_summary)
		shop_panel.add_child(shop_box)
		add_child(shop_panel)
	shop_panel.visible = sim.shop_open
	var missing := sim.unconfirmed_slots()
	if _summary_loadout != sim.loadout or _summary_credits != sim.credits or _summary_missing != missing:
		_summary_loadout = sim.loadout.duplicate(true)
		_summary_missing = missing.duplicate()
		_summary_credits = sim.credits
		var s := ShipCatalog.loadout_stats(sim.loadout)
		shop_summary.text = "%s · %d CR · TWR %.2f · Δv %.0f\n%s" % [
			str(s["design_name"]).to_upper(), s["cost"], s["twr"], s["dv"],
			"%d slots left (E at shop)" % missing.size() if missing.size() > 0 else "Ready — E at desk to build"
		]


func _pulse(ratio: float) -> void:
	var band := 0 if UI.reduced_motion or ratio > 0.30 else (2 if ratio <= 0.10 else 1)
	if band == _pulse_band: return
	_pulse_band = band
	if _pulse_tween: _pulse_tween.kill()
	visual_status.modulate.a = 1
	if band == 0: return
	var duration := 0.55 if band == 2 else 0.90
	_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(visual_status, "modulate:a", 0.45, duration / 2)
	_pulse_tween.tween_property(visual_status, "modulate:a", 1.0, duration / 2)


## Touch mode: compact role buttons centred in the gap between the joystick and
## the right action cluster; desktop: original centred bar.
func _layout_roles() -> void:
	if roles_box == null:
		return
	var touch := touch_ui_visible()
	var bw := 84.0 if touch else 104.0
	for rb in role_buttons:
		(rb as Label).custom_minimum_size.x = bw
	var w := bw * 4.0 + 18.0
	var mid := size.x * 0.5
	if touch:
		var left := mobile_controls.joy_home().x + MobileControls.JOY_RADIUS + 12.0
		var right := mobile_controls.cluster_left_edge() - 12.0
		mid = (left + right) * 0.5
	roles_box.size = Vector2(w, 40)
	roles_box.position = Vector2(mid - w * 0.5, size.y - 62.0)
