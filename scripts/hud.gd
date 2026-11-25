## In-match HUD: phase strip + clock, crew cards, objectives, radar, faction board, prompt, vitals, toasts.
class_name Hud
extends Control

const ROLE_ACCENTS := [UI.CYAN, UI.MAGENTA, UI.VIOLET, UI.CORAL]
static func _accent_card(accent: Color, selected: bool, bg := UI.PANEL) -> StyleBoxFlat:
	return UI.glass_style(bg.lerp(accent, 0.14 if selected else 0.05), 8, accent if selected else UI.BG_DEEP)


class Radar extends Control:
	var _redraw_elapsed := 0.05
	var _vertices := PackedVector2Array()
	var _chevron := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var sweep := 0.0
	var heading := 0.0

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
		var teal := UI.RADAR_TEAL
		var pulse := 0.5 + 0.5 * sin(sweep * 2.0)
		draw_circle(c, r, Color(0.02, 0.02, 0.025, 0.9))
		draw_circle(c, r * 0.55, Color(1, 1, 1, 0.04))
		# Multi-ring grid.
		for k in 4:
			draw_arc(c, r * (k + 1) / 4.0, 0, TAU, 56, Color(teal, 0.16 + 0.04 * k), 1.0, true)
		draw_arc(c, r, 0, TAU, 96, Color(teal, 0.85), 1.8, true)
		draw_arc(c, r + 2.0, 0, TAU, 96, Color(UI.VIOLET, 0.35), 1.0, true)
		# Radial sector lines every 45 degrees.
		for k in 8:
			var a := k * PI / 4.0
			var d := Vector2(sin(a), -cos(a))
			draw_line(c + d * r * 0.08, c + d * r, Color(teal, 0.16 if k % 2 == 0 else 0.08), 1.0)
		# Perimeter degree ticks.
		for k in 72:
			var a2 := k * TAU / 72.0
			var d2 := Vector2(sin(a2), -cos(a2))
			var tick_len := 7.0 if k % 6 == 0 else (4.5 if k % 2 == 0 else 2.5)
			draw_line(c + d2 * (r - tick_len), c + d2 * r, Color(teal, 0.75 if k % 6 == 0 else 0.4), 1.0)
		# Cardinal markers.
		var cardinals := [["N", Vector2(0, -1), UI.CORAL], ["E", Vector2(1, 0), UI.GOLD], ["S", Vector2(0, 1), UI.EMERALD], ["W", Vector2(-1, 0), UI.MAGENTA]]
		for card in cardinals:
			var direction: Vector2 = card[1]
			var cp := c + direction.rotated(heading) * (r - 15.0)
			draw_circle(cp, 8.0, Color(card[2], 0.16 + 0.1 * pulse))
			draw_circle(cp, 5.0, Color(card[2], 0.22))
			var cs := font.get_string_size(card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string(font, cp + Vector2(-cs.x * 0.5, 4.0), card[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, card[2])
		# Cover shapes: translucent fill + crisp outline.
		for shape in cover_shapes:
			_vertices.resize(shape.size())
			for i in shape.size(): _vertices[i] = c + shape[i] / range_m * r
			draw_colored_polygon(_vertices, Color(1, 1, 1, 0.12))
			var outline := _vertices.duplicate()
			if outline.size() > 0: outline.append(outline[0])
			if outline.size() > 1:
				draw_polyline(outline, Color(UI.INFO_PWR, 0.35), 3.0, true)
				draw_polyline(outline, Color(1, 1, 1, 0.95), 1.2, true)
		# Sweep wedge with phosphor trail.
		if not UI.reduced_motion:
			for k in 14:
				var f := 1.0 - float(k) / 14.0
				var a3 := sweep - k * 0.05
				draw_line(c, c + Vector2(sin(a3), -cos(a3)) * r * 0.97, Color(teal, 0.2 * f * f), 3.0)
			var tip := Vector2(sin(sweep), -cos(sweep))
			draw_line(c, c + tip * r * 0.97, Color(UI.INFO_PWR, 0.85), 1.5, true)
			draw_circle(c + tip * r * 0.97, 2.5, Color(1, 1, 1, 0.8))
		var label_rects: Array[Rect2] = []
		for p in points:
			var v: Vector2 = p["p"] / range_m * r
			if v.length() > r - 3.0:
				v = v.normalized() * (r - 3.0)
			var pc: Color = p["c"]
			var ps: float = p["s"]
			var bp := c + v
			var halo := 0.5 + 0.5 * sin(sweep * 3.0 + v.x * 0.1)
			if UI.reduced_motion: halo = 0.5
			if p.get("ring", false):
				draw_circle(bp, ps + 4.0, Color(pc, 0.10 + 0.08 * halo))
				draw_arc(bp, ps, 0, TAU, 20, pc, 2.0, true)
				# Diamond marker for objectives.
				var dm := ps * 0.45
				draw_colored_polygon(PackedVector2Array([bp + Vector2(0, -dm), bp + Vector2(dm, 0), bp + Vector2(0, dm), bp + Vector2(-dm, 0)]), Color(pc, 0.9))
				if ps >= 7.0:
					draw_arc(bp, ps + 2.0 + (0.0 if UI.reduced_motion else fmod(sweep, 1.0) * 4.0), 0, TAU, 24, UI.ACCENT, 1.5, true)
					for q in 4:
						var qa := q * PI / 2.0 + PI / 4.0
						var qd := Vector2(sin(qa), -cos(qa))
						draw_line(bp + qd * (ps + 6.0), bp + qd * (ps + 9.0), Color(pc, 0.9), 1.5)
			else:
				draw_circle(bp, ps + 5.0, Color(pc, 0.08 + 0.07 * halo))
				draw_circle(bp, ps + 2.5, Color(pc, 0.22))
				draw_circle(bp, ps, pc)
				draw_circle(bp, maxf(ps * 0.35, 0.8), Color(1, 1, 1, 0.8))
			var label: String = p.get("label", "")
			if show_labels and label != "" or (label != "" and p.get("priority", false)):
				var caption := label
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
				draw_string(font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, pc)
		# Heading cone + player chevron.
		var cone := PackedVector2Array([c, c + Vector2(-r * 0.2, -r * 0.42), c + Vector2(r * 0.2, -r * 0.42)])
		draw_colored_polygon(cone, Color(UI.ACCENT, 0.10 + 0.04 * pulse))
		draw_line(c, cone[1], Color(UI.ACCENT, 0.35), 1.0)
		draw_line(c, cone[2], Color(UI.ACCENT, 0.35), 1.0)
		draw_circle(c, 11.0, Color(UI.ACCENT, 0.14))
		_chevron[0] = c + Vector2(0, -9)
		_chevron[1] = c + Vector2(6, 6)
		_chevron[2] = c + Vector2(0, 3)
		draw_colored_polygon(_chevron, UI.ACCENT)
		_chevron[1] = c + Vector2(0, 3)
		_chevron[2] = c + Vector2(-6, 6)
		draw_colored_polygon(_chevron, UI.ACCENT_HOVER)


var location_label: Label
var clock: Label
var match_sides: Array[Dictionary] = []
var match_target: Label
var crew_stack: GridContainer
var flight_panel: PanelContainer
var flight_speed_label: Label
var flight_readings: Label
var flight_mode_label: Label
var flight_throttle: ProgressBar
var tilt_gauge: Control
var _tilt := 0.0
var _hint_time := 8.0
var _combat_top := INF
var _hint_text := ""
var _hint_tokens := RegEx.create_from_string(" *(?:·| {2,}) *")
var crew_cards: Array = []
var title: Label
var subtitle: Label
var objectives: RichTextLabel
var radar: Radar
var radar_title: Label
var board: VBoxContainer
var board_rows: Array = []
var prompt_panel: PanelContainer
var crane_mode_panel: PanelContainer
var crane_mode_label: Label
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
var advisor_hints := true:
	set(v):
		advisor_hints = v
		var n := get_node_or_null("CrewAdvisor")
		if n != null and not v:
			n.visible = false
var orders_label: Label
var alliance_bar: PanelContainer
var alliance_score: Label
var alliance_treasury: Label
var alliance_alert: Label
var _empire_alert_text := ""
var strategic_overview: HBoxContainer
var strategic_contacts: Array[Label] = []
var tactical_legend: Label
var tactical_help: Label

var tactical_panel: PanelContainer
var tactical_radar: Radar
var tactical_heading: Label
var tactical_distance: Label
var hit_time := 0.0
var toast_queue: Array = []
var style_selected := -1
var visual_status: PanelContainer
var status_rows := {}
var ammo_counter: Label
var weapon_caption: Label
var ship_status_label: Label
var mobile_controls: MobileControls
var touch_toggle: Button
var menu_button: MenuIcon
var _safe_items: Array = []        # {node, base, x (-1 left/+1 right/0), y (-1 top/+1 bottom/0)}
var _safe_applied := Vector4(-1, -1, -1, -1)
var _prompt_hint: Label
var _prompt_key: Label
var _prompt_text := ""
var _prompt_description := ""
var _prompt_action := ""
var _prompt_prefix := RegEx.create_from_string("(?i)^\\s*(?:(press|tap|hold)\\s+)?\\[?(E|L|F|R|SPACE)\\b\\]?\\s*[·:\\-]?\\s*")
var _prompt_detail_keys := RegEx.create_from_string("(?i)(?:press|tap)\\s+\\[?(?:E|T|F|SPACE)\\b\\]?|\\[(?:E|T)\\]")
const PROMPT_ACTIONS := {"L": "land", "E": "interact", "F": "ultimate", "R": "reload", "SPACE": "jump"}
var hud_opacity := 1.0
var _t := 1.0   # touch scale (1.0 desktop)

signal role_tapped(index: int)
signal prompt_tapped
signal radar_tapped
signal menu_tapped
signal touch_ui_toggled(on: bool)

## Hamburger MENU button: vector-drawn, glowing, with press feedback.
class MenuIcon extends Control:
	var down := false
	var hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hover = true; queue_redraw())
		mouse_exited.connect(func(): hover = false; down = false; queue_redraw())

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var col := UI.CYAN
		draw_circle(c, r, Color(col, 0.30 if down else 0.12 if hover else 0.05))
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color(0.04, 0.04, 0.05, 0.72), true)
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color(col, 1.0 if down or hover else 0.8), false, 2.0)
		var w := r * 0.9
		var gap := r * 0.38
		var th := maxf(2.0, r * 0.12)
		for i in 3:
			var y := c.y + (i - 1) * gap
			draw_line(Vector2(c.x - w * 0.5, y), Vector2(c.x + w * 0.5, y), Color(1, 1, 1, 0.98 if not down else 0.8), th, true)



## Register a node whose position is nudged away from screen edges by the safe-area insets.
func _safe(n: Control, x: int, y: int) -> void:
	_safe_items.append({"node": n, "base": n.position, "x": x, "y": y})


func _apply_safe_area() -> void:
	var ins := UI.safe_insets(get_viewport() if is_inside_tree() else null)
	if ins == _safe_applied:
		return
	_safe_applied = ins
	for it in _safe_items:
		var n: Control = it["node"]
		var base: Vector2 = it["base"]
		var dx := ins.x if it["x"] < 0 else (-ins.z if it["x"] > 0 else 0.0)
		var dy := ins.y if it["y"] < 0 else (-ins.w if it["y"] > 0 else 0.0)
		# Desktop (zero-ish insets) keeps the original layout untouched.
		if not UI.is_touch_platform():
			dx = 0.0
			dy = 0.0
		n.position = base + Vector2(dx, dy)


## Turn a HUD control into a tappable button that runs `cb` (touch or mouse).
func _make_tappable(c: Control, cb: Callable) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(func(e: InputEvent) -> void:
		var tap: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
		if tap:
			cb.call()
			c.accept_event())


## Synthesise a real key press so tapping HUD widgets reuses the keyboard code paths.
func _tap_key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	get_tree().create_timer(0.06).timeout.connect(func(): Input.parse_input_event(up))


func _init(touch_layout := UI.is_touch_platform()) -> void:
	_t = 1.3 if touch_layout else 1.0
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
	sb.bg_color = UI.PANEL
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _build_header() -> void:
	var header := UI.vbox(6)
	header.name = "MissionHeader"
	header.position = Vector2(16, 10)
	add_child(header)
	_safe(header, -1, -1)

	var row := UI.hbox(10)
	row.name = "BrandRow"
	header.add_child(row)
	var icon := TextureRect.new()
	icon.name = "GameIcon"
	icon.texture = preload("res://icon.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.custom_minimum_size = Vector2(34, 34) * _t
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var brand := UI.heading("T-MINUS", "", int(22 * _t))
	brand.name = "Wordmark"
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand.add_theme_constant_override("outline_size", 5)
	brand.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand)

	var touch_layout := _t > 1.0
	touch_toggle = Button.new()
	touch_toggle.text = "TOUCH UI"
	touch_toggle.toggle_mode = true
	touch_toggle.focus_mode = Control.FOCUS_NONE
	touch_toggle.add_theme_font_size_override("font_size", 14 if touch_layout else 11)
	touch_toggle.custom_minimum_size = Vector2(112, UI.TOUCH_MIN * 0.8) if touch_layout else Vector2(84, 24)
	touch_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := _pill_style()
	sb.border_color = Color(1, 1, 1, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		touch_toggle.add_theme_stylebox_override(st, sb)
	row.add_child(touch_toggle)

	title = UI.label("PREPARE EXPEDITION", int(13 * _t), UI.CYAN)
	header.add_child(title)
	subtitle = UI.label("", int(10 * _t), UI.TEXT)
	subtitle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	subtitle.add_theme_stylebox_override("normal", _pill_style())
	header.add_child(subtitle)

	var op := UI.panel(Vector2(228 * _t, 0), Color(0.05, 0.05, 0.06, 0.64))
	op.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	op.add_theme_stylebox_override("panel", _accent_card(UI.MAGENTA, true))
	header.add_child(op)
	objectives = UI.rich("", int(12 * _t))
	objectives.custom_minimum_size = Vector2(204 * _t, 0)
	var objective_box := UI.vbox(2)
	objective_box.add_child(HudIcon.new("objective", UI.MAGENTA, int(16 * _t)))
	objective_box.add_child(objectives)
	op.add_child(objective_box)


func _build() -> void:
	damage_flash = ColorRect.new()
	damage_flash.color = Color(UI.BAD, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(damage_flash)

	_build_header()
	_build_alliance_bar()

	var location_panel := UI.panel(Vector2(304 * _t, 0), UI.PANEL)
	location_panel.name = "LocationClock"
	location_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	location_panel.position = Vector2(-152 * _t, 10)
	_safe(location_panel, 0, -1)
	add_child(location_panel)
	var location_box := UI.vbox(2)
	location_panel.add_child(location_box)
	var match_row := UI.hbox(9)
	match_row.alignment = BoxContainer.ALIGNMENT_CENTER
	location_box.add_child(match_row)
	clock = UI.mono_label("08:00", int(27 * _t), UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	clock.custom_minimum_size.x = 86 * _t
	var center := UI.vbox(1)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(clock)
	match_target = UI.label("", int(10 * _t), UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	match_target.hide()
	center.add_child(match_target)
	for i in 2:
		var color := Color.html(Sim.EMPIRE_COLORS["orange" if i == 0 else "crimson"])
		var side := UI.vbox(1)
		var score := UI.mono_label("0", int(27 * _t), color, HORIZONTAL_ALIGNMENT_CENTER)
		var caption := UI.label("PLANET A" if i == 0 else "PLANET B", int(12 * _t), color, HORIZONTAL_ALIGNMENT_CENTER)
		var pips := Control.new()
		pips.custom_minimum_size = Vector2(74 * _t, 6 * _t)
		pips.draw.connect(_draw_match_pips.bind(pips, color))
		side.add_child(caption)
		side.add_child(score)
		side.add_child(pips)
		match_row.add_child(side)
		if i == 0:
			match_row.add_child(center)
		side.hide()
		match_sides.append({"node": side, "score": score, "pips": pips})
	location_label = UI.label(Universe.A_LABEL, int(12 * _t), UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	location_label.name = "Location"
	location_box.add_child(location_label)

	crew_stack = GridContainer.new()
	crew_stack.columns = 2
	crew_stack.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	crew_stack.position = Vector2(16, -116 if _t == 1.0 else -276)
	_safe(crew_stack, -1, 1)
	add_child(crew_stack)

	for i in 4:
		var p := UI.panel(Vector2(134 * _t, 42 * _t))
		p.add_theme_stylebox_override("panel", _accent_card(ROLE_ACCENTS[i], false))
		var v := UI.vbox(1)
		p.add_child(v)
		var top_row := UI.hbox(4)
		var n := UI.label(Sim.SPECIALISTS[i]["name"].to_upper(), int(12 * _t), UI.TEXT)
		var r := UI.label(Sim.SPECIALISTS[i]["role"].left(3).to_upper(), int(9 * _t), Color(ROLE_ACCENTS[i], 0.75))
		top_row.add_child(HudIcon.new(["ship", "wrench", "flag", "objective"][i], ROLE_ACCENTS[i], int(14 * _t)))
		top_row.add_child(n)
		top_row.add_child(UI.spacer(0, 2, true))
		top_row.add_child(r)
		var s := UI.label("…", int(9 * _t), UI.TEXT)
		s.clip_text = true
		var b := UI.bar(UI.GOOD, 1.0, 4)
		v.add_child(top_row)
		v.add_child(s)
		v.add_child(b)
		crew_stack.add_child(p)
		crew_cards.append({"panel": p, "status": s, "bar": b, "name": n})

	# Compact radar + faction board.
	var right := UI.vbox(6)
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_right = -12
	right.offset_left = -(168 * _t + 12)
	right.position.y = 10
	_safe(right, 1, -1)
	add_child(right)
	var rp := UI.panel(Vector2(168 * _t, 0), UI.INDIGO_GLASS)
	rp.add_theme_stylebox_override("panel", _accent_card(UI.CYAN, false, UI.INDIGO_GLASS))
	right.add_child(rp)
	var rv := UI.vbox(3)
	rp.add_child(rv)
	radar_title = UI.label("EARTH", int(10 * _t), UI.CYAN)
	var radar_row := UI.hbox(4)
	radar_row.add_child(HudIcon.new("radar", UI.CYAN, int(14 * _t)))
	radar_row.add_child(radar_title)
	rv.add_child(radar_row)
	radar = Radar.new()
	radar.custom_minimum_size = Vector2(144, 144) * _t
	rv.add_child(radar)
	var bp := UI.panel(Vector2(168 * _t, 0), UI.INDIGO_GLASS)
	bp.add_theme_stylebox_override("panel", _accent_card(UI.GOLD, false, UI.INDIGO_GLASS))
	right.add_child(bp)
	board = UI.vbox(2)
	bp.add_child(board)
	var board_head := UI.hbox(4)
	board_head.add_child(HudIcon.new("flag", UI.GOLD, int(14 * _t)))
	board.add_child(board_head)
	for i in 4:
		var row := UI.hbox(4)
		var dot := UI.label(Sim.FACTIONS[i]["symbol"] + " " + Sim.FACTIONS[i]["name"].left(6), int(10 * _t), Sim.faction_color(i))
		dot.custom_minimum_size = Vector2(68 * _t, 0)
		var ph := UI.label("", int(9 * _t), UI.MUTED)
		ph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.custom_minimum_size.x = 34
		var sc := UI.mono_label("0", int(14 * _t), UI.TEXT)
		row.add_child(dot)
		row.add_child(ph)
		row.add_child(sc)
		board.add_child(row)
		board_rows.append({"team": dot, "phase": ph, "score": sc})
	var pool := UI.label("", int(9 * _t), UI.MUTED)
	pool.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pool.custom_minimum_size.x = 148 * _t
	board.add_child(pool)
	board_rows.append({"pool": pool})

	# Prompt.
	prompt_panel = UI.panel(Vector2(420 * _t, 0), UI.INDIGO_GLASS)
	prompt_panel.add_theme_stylebox_override("panel", _accent_card(UI.CYAN, true, UI.INDIGO_GLASS))
	add_child(prompt_panel)
	var pv := UI.vbox(1)
	prompt_panel.add_child(pv)
	prompt_title = UI.label("", int(19 * _t), UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_detail = UI.label("", int(13 * _t), UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	prompt_bar = UI.bar(UI.EMERALD, 0.0, 5)
	var prompt_row := UI.hbox(8)
	prompt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_key = UI.label("", 14, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_key.add_theme_stylebox_override("normal", UI.style(UI.PANEL_SOLID, UI.CYAN, 5, 8, 2))
	_prompt_key.hide()
	prompt_row.add_child(_prompt_key)
	prompt_row.add_child(prompt_title)
	pv.add_child(prompt_row)
	pv.add_child(prompt_detail)
	pv.add_child(prompt_bar)
	# The prompt advertises its touch gesture when it has an action.
	_prompt_hint = UI.label("TAP", int(11 * _t), UI.EMERALD, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_hint.visible = false
	pv.add_child(_prompt_hint)
	prompt_panel.custom_minimum_size.y = 56.0 if UI.is_touch_platform() else 0.0

	# Toast + banner.
	toast_label = UI.label("", 14, Color("#ffffff"), HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-400, 208)
	toast_label.size = Vector2(800, 30)
	toast_label.add_theme_stylebox_override("normal", UI.component("toast"))
	add_child(toast_label)
	banner = UI.label("", 54, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.position = Vector2(-600, 18)
	banner.add_theme_constant_override("outline_size", 6)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	banner.add_theme_color_override("font_color", Color("#ffffff"))
	banner.add_theme_color_override("font_shadow_color", Color(UI.MAGENTA, 0.55))
	banner.add_theme_constant_override("shadow_offset_y", 3)
	banner.size = Vector2(500, 64)
	banner.position.x = -250
	banner.clip_text = true
	add_child(banner)
	banner_sub = UI.label("", 16, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	banner_sub.add_theme_color_override("font_shadow_color", Color(UI.VIOLET, 0.7))
	banner_sub.add_theme_constant_override("shadow_offset_y", 2)
	banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	banner_sub.position = Vector2(-600, 80)
	banner_sub.size = Vector2(500, 28)
	banner_sub.position.x = -250
	banner_sub.clip_text = true
	add_child(banner_sub)

	# Vitals (flight / surface).
	vitals_panel = UI.panel(Vector2(250, 0), UI.INDIGO_GLASS)
	vitals_panel.add_theme_stylebox_override("panel", _accent_card(UI.EMERALD, false, UI.INDIGO_GLASS))
	vitals_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	vitals_panel.position = Vector2(-270, -250)
	_safe(vitals_panel, 1, 1)
	add_child(vitals_panel)
	vitals = UI.rich("", 13)
	vitals.custom_minimum_size = Vector2(225, 0)
	vitals_panel.add_child(vitals)

	# Station panel (engineer / raider consoles in flight).
	station_panel = UI.panel(Vector2(300, 0), UI.INDIGO_GLASS)
	station_panel.add_theme_stylebox_override("panel", _accent_card(UI.VIOLET, true, UI.INDIGO_GLASS))
	station_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	station_panel.position = Vector2(20, 40)
	_safe(station_panel, -1, 0)
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
		var l := UI.label("%d %s" % [i + 1, Sim.SPECIALISTS[i]["name"]], int(11 * _t), UI.TEXT)
		l.add_theme_stylebox_override("normal", UI.style(Color(0.05, 0.05, 0.06, 0.64), UI.LINE, 4, 8))
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
	footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_theme_color_override("font_color", Color.TRANSPARENT)
	footer.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	footer.custom_minimum_size.y = 24
	footer.draw.connect(_draw_hints)
	add_child(footer)
	# Persistent next-action guidance sits above the role bar.
	var advice_panel := UI.panel(Vector2(340, 0), Color(0.04, 0.04, 0.05, 0.70))
	advice_panel.add_theme_stylebox_override("panel", _accent_card(UI.EMERALD, true, Color(0.04, 0.04, 0.05, 0.70)))
	advice_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	advice_panel.position = Vector2(20, -198)
	add_child(advice_panel)
	var advice_box := UI.vbox(5)
	advice_panel.add_child(advice_box)
	orders_label = UI.label("", int(10 * _t), UI.EMERALD)
	var orders_row := UI.hbox(6)
	orders_row.add_child(HudIcon.new("warning", UI.GOLD, int(16 * _t)))
	orders_row.add_child(orders_label)
	advice_box.add_child(orders_row)
	advisor = UI.label("", int(12 * _t), UI.TEXT)
	advisor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advisor.custom_minimum_size = Vector2(310 * _t, 36 * _t)
	advice_box.add_child(advisor)
	advice_panel.name = "CrewAdvisor"
	tactical_panel = UI.panel(Vector2(520, 520), Color(0.02, 0.02, 0.025, 0.98))
	var tactical_sb := (tactical_panel.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	tactical_sb.border_color = UI.RADAR_TEAL
	tactical_sb.border_width_left = 3
	tactical_sb.border_width_top = 3
	tactical_sb.border_width_right = 1
	tactical_sb.border_width_bottom = 1
	tactical_sb.shadow_color = Color(UI.RADAR_TEAL, 0.25)
	tactical_sb.shadow_size = 14
	tactical_panel.add_theme_stylebox_override("panel", tactical_sb)
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
	var legend := UI.wrapped_label("▲ YOU · ● SAMPLES / CREW · ◈ RINGS: SHIPS / OBJECTIVES · N coral · E gold · S emerald · W magenta", 10, UI.TEXT)
	tactical_legend = legend
	legend.position = Vector2(0, 444)
	legend.size.x = 480
	tactical_box.add_child(legend)
	var map_help := UI.label("C crew order · Z priority · M close · Match remains live", 10, UI.MUTED)
	tactical_help = map_help
	map_help.position = Vector2(0, 470)
	tactical_box.add_child(map_help)
	_build_strategic_overview(tactical_box)
	tactical_panel.visible = false
	visual_status = UI.panel(Vector2(250 * _t, 0), UI.INDIGO_GLASS)
	visual_status.add_theme_stylebox_override("panel", _accent_card(UI.CYAN, true, UI.INDIGO_GLASS))
	visual_status.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	visual_status.position = Vector2(-(250 * _t + 30), -(330 + 60 * (_t - 1.0)) * 1.0)
	_safe(visual_status, 1, 1)
	add_child(visual_status)
	var status_box := UI.vbox(7)
	visual_status.add_child(status_box)
	weapon_caption = UI.label("", int(11 * _t), UI.MAGENTA)
	ammo_counter = UI.mono_label("100", int(40 * _t), UI.TEXT)
	var weapon_row := UI.hbox(6)
	weapon_row.add_child(HudIcon.new("ammo", UI.MAGENTA, int(18 * _t)))
	weapon_row.add_child(weapon_caption)
	status_box.add_child(weapon_row)
	status_box.add_child(ammo_counter)
	ship_status_label = UI.mono_label("", int(11 * _t), Color.WHITE)
	status_box.add_child(ship_status_label)
	for metric in [["health", "HP", "#35e6a0"], ["energy", "PWR", "#4fe3ff"], ["heat", "HEAT", "#ff7a6b"], ["pressure", "AIR", "#8fb4ff"], ["co2", "CO₂", "#8a6bff"], ["food", "CREW", "#a8f06a"], ["fuel", "FUEL", "#ffd447"], ["ammo", "MAG", "#ff5fd2"]]:
		var row := UI.hbox(6)
		var ids := {"health": "health", "energy": "power", "heat": "heat", "pressure": "pressure", "co2": "co2", "food": "crew", "fuel": "fuel", "ammo": "ammo"}
		row.add_child(HudIcon.new(ids[metric[0]], Color(metric[2]), int(16 * _t)))
		var label := UI.label(metric[1], int(10 * _t), Color(metric[2]).lerp(Color.WHITE, 0.25))
		label.custom_minimum_size.x = 35
		label.visible = _t == 1.0   # touch: icon-only rows
		row.add_child(label)
		var fill := UI.bar(Color(metric[2]), 1.0, 6)
		fill.custom_minimum_size = Vector2(108 * _t, 6 * _t)
		fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(fill)
		var reading := UI.mono_label("100", int(11 * _t), UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		reading.custom_minimum_size.x = 36 * _t
		row.add_child(reading)
		status_box.add_child(row)
		status_rows[metric[0]] = {"row": row, "label": label, "fill": fill, "reading": reading, "nominal": Color(metric[2])}
	visual_status.visible = false
	crane_mode_panel = PanelContainer.new()
	crane_mode_panel.add_theme_stylebox_override("panel", _accent_card(UI.CYAN, true, UI.INDIGO_GLASS))
	add_child(crane_mode_panel)
	crane_mode_label = UI.mono_label("", 12, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	crane_mode_panel.add_child(crane_mode_label)
	set_crane_mode(false)

	_build_flight_panel()
	_ignore_all(self)
	_build_touch()
	resized.connect(_layout_crane_prompt)
	roles_box.item_rect_changed.connect(_layout_crane_prompt)
	prompt_panel.resized.connect(_layout_crane_prompt)
	crane_mode_panel.resized.connect(_layout_crane_prompt)


## Touch overlay sits inside the HUD layer (above the 3D world, below menu_layer modals).
func _build_touch() -> void:
	mobile_controls = MobileControls.new()
	add_child(mobile_controls)
	touch_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	touch_toggle.toggled.connect(func(on: bool) -> void: touch_ui_toggled.emit(on))
	_build_menu_button()
	touch_toggle.set_pressed_no_signal(mobile_controls.is_touch_visible())
	# Tappable HUD widgets (the HUD root ignores the mouse; opt these back in).
	for i in role_buttons.size():
		var idx := i
		_make_tappable(role_buttons[i], func():
			role_tapped.emit(idx)
			_tap_key(KEY_1 + idx))
	prompt_panel.gui_input.connect(_prompt_gui_input)
	var radar_panel := radar.get_parent().get_parent() as Control
	_make_tappable(radar_panel, func():
		radar_tapped.emit()
		toggle_tactical())
	_apply_safe_area()


## Always-visible MENU button left of the radar column (top-right); opens Pause/Settings via ESC.
func _build_menu_button() -> void:
	var d := 64.0 if UI.is_touch_platform() else 34.0
	menu_button = MenuIcon.new()
	menu_button.name = "MenuButton"
	menu_button.anchor_left = 1.0
	menu_button.anchor_right = 1.0
	var rx := 168.0 * _t + 20.0
	menu_button.offset_left = -rx - d
	menu_button.offset_right = -rx
	menu_button.offset_top = 10.0
	menu_button.offset_bottom = 10.0 + d
	menu_button.gui_input.connect(func(e: InputEvent) -> void:
		var pressed_ev: bool = (e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT))
		if not pressed_ev:
			return
		menu_button.down = e.pressed
		menu_button.queue_redraw()
		if e.pressed:
			menu_tapped.emit()
			_tap_key(KEY_ESCAPE)
		menu_button.accept_event())
	add_child(menu_button)
	_safe(menu_button, 1, -1)


func set_touch_ui(on: bool) -> void:
	if mobile_controls.is_touch_visible() != on:
		mobile_controls.set_touch_visible(on)
	touch_toggle.set_pressed_no_signal(on)
	footer.visible = not on and _hint_time > 0.0
	_refresh_prompt()


## Live HUD transparency: fades the glass panels only (crosshair, banner, toast stay crisp).
func set_hud_opacity(v: float) -> void:
	hud_opacity = clampf(v, 0.35, 1.0)
	for n in _opacity_nodes():
		if n != null:
			n.modulate.a = hud_opacity
	var chud := get_tree().get_first_node_in_group("combat_hud") if is_inside_tree() else null
	if chud != null and chud.has_method("set_hud_opacity"):
		chud.set_hud_opacity(hud_opacity)


func _opacity_nodes() -> Array:
	var out: Array = [roles_box, prompt_panel, vitals_panel, station_panel, tactical_panel, shop_panel, get_node_or_null("CrewAdvisor")]
	if radar != null: out.append(radar.get_parent().get_parent())
	if board != null: out.append(board.get_parent())
	for c in crew_cards: out.append(c["panel"].get_parent())
	out.append(get_node("LocationClock"))
	out.append(flight_panel)
	if objectives != null: out.append(objectives.get_parent().get_parent())
	if visual_status != null and _pulse_band <= 0: out.append(visual_status)
	return out


func touch_ui_visible() -> bool:
	return mobile_controls != null and mobile_controls.is_touch_visible()


func set_mode(sp: bool) -> void:
	match_target.visible = sp
	for side in match_sides:
		side["node"].visible = sp
	board.get_parent().visible = not sp
	roles_box.visible = not sp
	get_node("CrewAdvisor").visible = not sp and advisor_hints
	close_tactical()
	visual_status.visible = false
	style_selected = -1


func _prompt_gui_input(e: InputEvent) -> void:
	if _prompt_action != "" and mobile_controls.press_prompt(e, _prompt_action):
		prompt_tapped.emit()
		prompt_panel.accept_event()


func _refresh_prompt() -> void:
	var title_text := _prompt_text
	var prefix := _prompt_prefix.search(title_text)
	_prompt_key.hide()
	if prefix != null and not touch_ui_visible() and not crane_mode_panel.visible:
		var key := prefix.get_string(2).to_upper()
		_prompt_key.text = key
		_prompt_key.visible = key in ["E", "L"]
		if key == "E":
			title_text = title_text.substr(prefix.get_end())
		elif key == "L" and title_text.begins_with("PRESS L TO LAND · "):
			title_text = "LAND ON " + title_text.trim_prefix("PRESS L TO LAND · ").get_slice(" · ", 0)
	var detail_text := _prompt_description
	var gesture := "TAP"
	_prompt_action = ""
	if touch_ui_visible():
		if prefix != null:
			var key := prefix.get_string(2).to_upper()
			var action_text := title_text.substr(prefix.get_end()).trim_prefix("TO ").trim_prefix("FOR ")
			_prompt_action = PROMPT_ACTIONS[key]
			if prefix.get_string(1).nocasecmp_to("hold") == 0:
				gesture = "HOLD"
			title_text = "%s · %s" % [gesture, action_text]
		detail_text = _prompt_detail_keys.sub(detail_text, "tap", true)
	if mobile_controls != null:
		mobile_controls.interact_action = "land" if mobile_controls.flight_mode and _prompt_action != "interact" else "interact"
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_STOP if _prompt_action != "" else Control.MOUSE_FILTER_IGNORE
	_prompt_hint.text = gesture
	_prompt_hint.visible = _prompt_action != "" and not crane_mode_panel.visible
	prompt_title.text = title_text
	prompt_detail.text = detail_text
	prompt_detail.visible = detail_text != ""


func set_crane_mode(active: bool, crane_label: String = "") -> void:
	if active:
		var view_label := "CRANE ARM VIEW"
		if not crane_label.is_empty() and crane_label != view_label:
			view_label += " · " + crane_label
		crane_mode_label.text = view_label + "\nWASD MOVE CLAW · SPACE/SHIFT UP/DOWN · E PICK/PLACE · Q QUIT CRANE"
	crane_mode_panel.visible = active
	_refresh_prompt()
	_prompt_hint.visible = _prompt_action != "" and not active
	_layout_crane_prompt()


func _layout_crane_prompt() -> void:
	var prompt_top := size.y - 150.0 - 20.0 * (_t - 1.0) - maxf(_safe_applied.w, 0.0)
	prompt_panel.reset_size()
	prompt_top = minf(prompt_top, _combat_top - prompt_panel.size.y - 14.0)
	if crane_mode_panel.visible:
		crane_mode_panel.reset_size()
		var gap := 12.0
		var crane_top := roles_box.position.y - gap - crane_mode_panel.size.y
		crane_mode_panel.position = Vector2((size.x - crane_mode_panel.size.x) * 0.5, crane_top)
		prompt_top = crane_top - gap - prompt_panel.size.y
	prompt_panel.position = Vector2((size.x - prompt_panel.size.x) * 0.5, prompt_top)


func set_prompt(t: String, detail := "", progress := -1.0) -> void:
	_prompt_text = t
	_prompt_description = detail
	_refresh_prompt()
	prompt_panel.visible = t != ""
	prompt_bar.visible = progress >= 0.0
	prompt_bar.value = maxf(0.0, progress)


func show_control_hints() -> void:
	_hint_time = 8.0
	footer.visible = not touch_ui_visible() and not footer.text.is_empty()


func _draw_hints() -> void:
	var parts := _hint_tokens.sub(footer.text, "|", true).split("|", false)
	var font := UI.font()
	var x := 0.0
	var widths := PackedFloat32Array()
	for part in parts:
		var caption := part.strip_edges()
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 22.0
		widths.append(width)
		x += width
	x = maxf(0.0, (footer.size.x - x) * 0.5)
	for i in parts.size():
		var part := parts[i].strip_edges()
		if x + widths[i] > footer.size.x:
			break
		var key := part.get_slice(" ", 0)
		var key_width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0
		footer.draw_style_box(UI.glass_style(), Rect2(x, 0, widths[i] - 4.0, 24))
		footer.draw_style_box(UI.style(UI.PANEL_SOLID.lightened(0.12), UI.CYAN, 5, 0), Rect2(x + 4.0, 4, key_width, 16))
		footer.draw_string(font, Vector2(x + 9.0, 16), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.TEXT)
		footer.draw_string(font, Vector2(x + key_width + 8.0, 16), part.substr(key.length()).strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.MUTED)
		x += widths[i]


func set_match_score(left: int, right: int, target: int) -> void:
	match_target.text = "FIRST TO %d" % target
	for i in 2:
		var side := match_sides[i]
		var value := left if i == 0 else right
		var score: Label = side["score"]
		var pips: Control = side["pips"]
		if score.text != str(value) and not UI.reduced_motion:
			var previous = score.get_meta("score_tween") if score.has_meta("score_tween") else null
			if previous is Tween:
				previous.kill()
			score.pivot_offset = score.size * 0.5
			score.scale = Vector2.ONE * 1.25
			var tween := score.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(score, "scale", Vector2.ONE, 0.28)
			score.set_meta("score_tween", tween)
		if score.text != str(value) or int(pips.get_meta("target", 0)) != target:
			score.text = str(value)
			pips.set_meta("score", value)
			pips.set_meta("target", target)
			pips.queue_redraw()


func _draw_match_pips(pips: Control, color: Color) -> void:
	var target := int(pips.get_meta("target", 0))
	if target <= 0:
		return
	var count := mini(20, target)
	var segment := pips.size.x / count
	var filled := clampf(float(pips.get_meta("score", 0)) * count / target, 0.0, float(count))
	for i in count:
		var rect := Rect2(i * segment, 1, segment - 1, 4)
		pips.draw_rect(rect, Color(color, 0.20))
		rect.size.x *= clampf(filled - i, 0.0, 1.0)
		if rect.size.x > 0.0:
			pips.draw_rect(rect, color)


func _build_flight_panel() -> void:
	flight_panel = UI.panel(Vector2(196 * _t, 0))
	flight_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	flight_panel.position = Vector2(16, -60)
	_safe(flight_panel, -1, 0)
	add_child(flight_panel)
	var column := UI.vbox(4)
	flight_panel.add_child(column)
	flight_speed_label = UI.mono_label("", 36, UI.TEXT)
	column.add_child(flight_speed_label)
	flight_readings = UI.label("", 12, UI.MUTED)
	column.add_child(flight_readings)
	var mode_row := UI.hbox(8)
	tilt_gauge = Control.new()
	tilt_gauge.custom_minimum_size = Vector2(32, 32)
	tilt_gauge.draw.connect(_draw_tilt)
	mode_row.add_child(tilt_gauge)
	flight_mode_label = UI.label("", 13, UI.CYAN)
	mode_row.add_child(flight_mode_label)
	column.add_child(mode_row)
	column.add_child(UI.label("THROTTLE", 10, UI.MUTED))
	flight_throttle = UI.bar(UI.GOLD, 0.0, 8)
	column.add_child(flight_throttle)
	flight_panel.hide()


func _draw_tilt() -> void:
	var origin := Vector2(5, 27)
	tilt_gauge.draw_arc(origin, 21, -PI * 0.5, 0.0, 18, UI.DIM, 3.0, true)
	tilt_gauge.draw_line(origin, origin + Vector2.RIGHT.rotated(-_tilt) * 22.0, UI.CYAN, 3.0, true)


func set_flight_instruments(speed: float, altitude: float, vertical: float, tilt: float, power: float, in_space: bool) -> void:
	flight_panel.show()
	flight_speed_label.text = "%d m/s" % roundi(absf(speed))
	flight_readings.visible = not in_space
	flight_readings.text = "ALT %d m   ·   V/S %+.1f" % [roundi(altitude), vertical]
	flight_mode_label.text = "%s  %d°" % ["VTOL" if tilt >= 80.0 else ("CRUISE" if tilt <= 10.0 else "TRANSITION"), roundi(tilt)]
	if not is_equal_approx(_tilt, deg_to_rad(tilt)):
		_tilt = deg_to_rad(tilt)
		tilt_gauge.queue_redraw()
	UI.smooth_bar(flight_throttle, power)


func set_flight_footer() -> void:
	footer.text = "W THROTTLE · S BRAKE · A/D ROLL · SPACE LIFT · CTRL DOWN · L LAND · H HINTS" if not touch_ui_visible() else "STICK ↑ FORWARD · ↓ BRAKE/REVERSE · ←/→ ROLL · DRAG TO STEER · BOOST · LIFT / DOWN · LAND"


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
		toast_label.position.y = 216
		_toast_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.18)
		_toast_tween.tween_property(toast_label, "position:y", 208.0, 0.18)

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
	tactical_distance.text = "%d CONTACTS" % points.size()
	if tactical_panel.visible: tactical_radar.request_redraw()



func show_banner(t: String, sub := "", seconds := 2.6) -> void:
	banner.text = t
	banner.add_theme_stylebox_override("normal", UI.glass_style(UI.HUD_GLASS, 0, UI.ACCENT))
	banner.pivot_offset = banner.size * 0.5
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
	_apply_safe_area()
	_hint_time = maxf(0.0, _hint_time - dt)
	footer.visible = _hint_time > 0.0 and not touch_ui_visible() and not footer.text.is_empty()
	if _hint_text != footer.text:
		_hint_text = footer.text
		footer.queue_redraw()
	_layout_roles()
	_common_elapsed += dt
	hit_time = maxf(0.0, hit_time - dt)
	# On the Moon CombatHUD draws its own blooming 4-tick crosshair; mute the legacy '+'.
	var combat: CombatHUD
	if is_inside_tree():
		for overlay in get_tree().get_nodes_in_group("combat_hud"):
			if overlay.visible and (overlay.vitals_rect().has_area() or overlay.crosshair_visible):
				combat = overlay
				break
	if combat != null:
		var lower_bar_top := roles_box.position.y if roles_box.visible else (footer.position.y if footer.visible else INF)
		if touch_ui_visible():
			lower_bar_top = minf(lower_bar_top, mobile_controls.joy_home().y - 20.0)
		combat.set_vitals_layout(lower_bar_top, maxf(_safe_applied.w, 0.0), touch_ui_visible())
	_combat_top = combat.vitals_rect().position.y if combat != null and combat.vitals_rect().has_area() else INF
	_layout_crane_prompt()
	crosshair.self_modulate.a = 0.0 if combat != null and combat.crosshair_visible else 1.0
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
	banner.position.y = size.y * 0.65 - 38.0
	if combat != null and combat.vitals_rect().has_area():
		banner.position.y = minf(banner.position.y, combat.vitals_rect().position.y - 114.0)
	banner_sub.position.y = banner.position.y + 64.0
	banner_time -= dt
	if banner_time <= 0.50 and not _banner_out:
		_banner_out = true
		if _banner_tween: _banner_tween.kill()
		_banner_tween = create_tween().set_parallel()
		_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.0 if UI.reduced_motion else 0.50)
		_banner_tween.tween_property(banner_sub, "modulate:a", 0.0, 0.0 if UI.reduced_motion else 0.50)



## Monochrome ship readout: hull %, shield %, and a state tag.
func _ship_status_text(sim: Sim) -> String:
	var hull := roundi(sim.hull)
	var shield_pct := 100 if sim.shield > 0.0 else roundi(Flight.ship_shield)
	var tag := "SHIELDED"
	if Flight.under_fire > 0.0:
		tag = "UNDER ATTACK"
	elif hull <= 25:
		tag = "CRITICAL"
	elif hull < 100 or shield_pct <= 0:
		tag = "DAMAGED"
	return "SHIP  HULL %d%%  SHIELD %d%%\n[ %s ]" % [hull, shield_pct, tag]


func update_common(sim: Sim, selected: int) -> void:
	ammo_counter.show()
	status_rows["health"]["row"].show()
	if ship_status_label != null and (sim.in_space() or sim.on_surface("planet_c")):
		ship_status_label.text = _ship_status_text(sim)
	if mobile_controls != null:
		mobile_controls.set_primary_label("FIRE" if (sim.in_space() or sim.on_surface("planet_c")) else "ACTION")
	if sim.in_space():
		ammo_counter.text = "%d%%" % roundi(sim.hull)
		_status("health", sim.hull / 100.0, str(roundi(sim.hull)))
	if _common_elapsed < 0.1 and style_selected == selected: return
	_common_elapsed = fmod(_common_elapsed, 0.1)
	update_shop(sim)
	advisor.text = _short_advice(sim)
	visual_status.visible = (sim.in_space() or sim.on_surface("planet_c"))
	if visual_status.visible: vitals_panel.visible = false
	status_rows["ammo"]["row"].visible = sim.on_surface("planet_c")
	status_rows["co2"]["row"].visible = sim.in_space()
	status_rows["food"]["row"].visible = sim.in_space()
	_status("fuel", sim.propellant / Sim.BASE_PROPELLANT, "%.0f" % sim.propellant)
	if sim.in_space():
		weapon_caption.text = str(ShipCatalog.loadout_stats(sim.loadout)["design_name"]).to_upper()
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

	orders_label.text = sim.crew_order.to_upper() if sim.on_surface("planet_c") else ""
	clock.text = UI.fmt_time(sim.limit - sim.time)
	var clock_bad := sim.limit - sim.time < 60.0
	if not clock.has_meta("bad") or clock.get_meta("bad") != clock_bad:
		clock.set_meta("bad", clock_bad)
		clock.add_theme_color_override("font_color", UI.BAD if clock_bad else UI.CYAN)
	if selected != style_selected:
		style_selected = selected
		for i in 4:
			var crew_card = crew_cards[i]
			crew_card["panel"].add_theme_stylebox_override("panel", _accent_card(UI.ACCENT if i == selected else ROLE_ACCENTS[i], i == selected))
			var rb: Label = role_buttons[i]
			rb.add_theme_stylebox_override("normal", _accent_card(ROLE_ACCENTS[i], i == selected))
			rb.add_theme_color_override("font_color", ROLE_ACCENTS[i] if i == selected else UI.TEXT)
	for i in 4:
		var t = sim.teams[i]
		var row = board_rows[i]
		if sim.empire != null:
			var ally_ids: Array = Sim.EmpireRules.ALLIANCE_SQUADS[sim.empire_home].duplicate()
			ally_ids.erase(sim.empire_squad)
			var id: String = sim.empire_squad if i == 0 else ally_ids[i - 1]
			var squad: Dictionary = sim.empire.squads[id]
			row["team"].text = id.to_upper() + (" · YOU" if i == 0 else " · ALLY")
			row["team"].add_theme_color_override("font_color", Color.html(Sim.EMPIRE_COLORS[id]))
			row["phase"].text = squad["phase"].to_upper()
			row["score"].text = str(squad["deliveries"])
		else:
			row["team"].text = Sim.FACTIONS[i]["symbol"] + " " + Sim.FACTIONS[i]["name"].left(6)
			row["team"].add_theme_color_override("font_color", Sim.faction_color(i))
			row["phase"].text = t["phase"].to_upper()
			row["score"].text = str(t["delivered"]) + ("  +%d" % t["onboard"] if t["onboard"] > 0 else "")
	var chud := get_tree().get_first_node_in_group("combat_hud") if is_inside_tree() else null
	if sim.empire == null and chud != null and chud.has_method("set_team_scores"):
		var scores: Array = []
		for i in 4:
			var ft: Dictionary = Sim.FACTIONS[i]
			scores.append({"name": ft["name"], "color": Color(ft["color"]), "delivered": sim.teams[i]["delivered"], "onboard": sim.teams[i]["onboard"]})
		chud.set_team_scores(scores)
	var flag_counts := sim.flag_counts(0)
	board_rows[4]["pool"].text = "%d · %d · %d/%d" % [flag_counts["sites"], flag_counts["loose"], flag_counts["onboard"], sim.cargo_capacity]


func set_crew_status(i: int, status: String, progress: float) -> void:
	crew_cards[i]["status"].text = status
	UI.smooth_bar(crew_cards[i]["bar"], progress)


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
	weapon_caption.text = "SCANNER" if role == 3 else ("RELOAD" if reloading > 0.0 else (Sim.SPECIALISTS[role]["weapon"].to_upper() if drawn else "B DRAW"))
	var ammo_color := UI.ramp_color(float(ammo) / 24.0, UI.TEXT) if drawn and role != 3 else UI.ramp_color(hp / 100.0)
	if ammo_counter.get_meta("color", Color.TRANSPARENT) != ammo_color:
		ammo_counter.set_meta("color", ammo_color)
		ammo_counter.add_theme_color_override("font_color", ammo_color)
	ammo_counter.text = "%.1fs" % down if down > 0.0 else ("%d%%" % hp if role == 3 or not drawn else "%02d / 24" % ammo)
	_status("health", 0.0 if down > 0.0 else hp / 100.0, "DOWN" if down > 0.0 else str(roundi(hp)))
	var chud := get_tree().get_first_node_in_group("combat_hud") if is_inside_tree() else null
	if chud != null and chud.has_method("set_vitals"):
		chud.set_hud_opacity(hud_opacity)
		chud.set_vitals(0.0 if down > 0.0 else hp, clampf(sim.shield, 0.0, 100.0), ammo, 24, drawn)
		ammo_counter.visible = down > 0.0
		status_rows["health"]["row"].hide()
		status_rows["ammo"]["row"].hide()
	status_rows["energy"]["label"].text = "Q"
	_status("energy", 1.0 - sim.ability_cd[role] / 12.0, "RDY" if sim.ability_cd[role] <= 0.0 else "%.0fs" % sim.ability_cd[role])
	status_rows["heat"]["label"].text = "F"
	_status("heat", sim.ultimate[role] / 100.0, "%d%%" % sim.ultimate[role])
	status_rows["pressure"]["label"].text = "BAY"
	_status("pressure", float(sim.flag_counts(0)["onboard"]) / sim.cargo_capacity, "%d/%d" % [sim.flag_counts(0)["onboard"], sim.cargo_capacity])

func _short_advice(sim: Sim) -> String:
	return sim.objective_advice()


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
		shop_panel = UI.panel(Vector2(228, 0), Color(0.05, 0.05, 0.06, 0.64))
		shop_panel.add_theme_stylebox_override("panel", _accent_card(UI.GOLD, false))
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
		shop_summary.text = UI.loadout_summary(sim)


func _pulse(ratio: float) -> void:
	var band := 0 if UI.reduced_motion or ratio > 0.30 else (2 if ratio <= 0.10 else 1)
	if band == _pulse_band: return
	_pulse_band = band
	if _pulse_tween: _pulse_tween.kill()
	visual_status.modulate.a = hud_opacity
	if band == 0: return
	var duration := 0.55 if band == 2 else 0.90
	_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(visual_status, "modulate:a", 0.45 * hud_opacity, duration / 2)
	_pulse_tween.tween_property(visual_status, "modulate:a", hud_opacity, duration / 2)


## Touch mode: compact role buttons centred in the gap between the joystick and
## the right action cluster; desktop: original centred bar.
func _layout_roles() -> void:
	if roles_box == null:
		return
	var touch := touch_ui_visible()
	var bw := 92.0 if touch else 104.0
	var bh := UI.TOUCH_MIN if touch else 32.0
	for rb in role_buttons:
		(rb as Label).custom_minimum_size = Vector2(bw, bh)
	var w := bw * 4.0 + 18.0
	var mid := size.x * 0.5
	if touch:
		var left := mobile_controls.joy_home().x + MobileControls.JOY_RADIUS + 12.0
		var right := mobile_controls.cluster_left_edge() - 12.0
		mid = (left + right) * 0.5
	var ins := UI.safe_insets(get_viewport() if is_inside_tree() else null)
	roles_box.size = Vector2(w, bh + 8.0)
	footer.size.x = clampf(size.x - ins.x - ins.z - 24.0, 0.0, 1000.0)
	footer.position.x = (size.x + ins.x - ins.z - footer.size.x) * 0.5
	footer.position.y = size.y - ins.w - 8.0 - footer.size.y
	var roles_top := size.y - 62.0 - (bh - 32.0) - ins.w
	if footer.visible:
		roles_top = minf(roles_top, footer.position.y - 12.0 - roles_box.size.y)
	roles_box.position = Vector2(mid - roles_box.size.x * 0.5, roles_top)



func _build_alliance_bar() -> void:
	alliance_bar = UI.panel(Vector2(360, 0), Color("#182a40e8"))
	alliance_bar.name = "AllianceScore"
	alliance_bar.add_theme_stylebox_override("panel", _accent_card(UI.CYAN, false, Color("#121e30e8")))
	var stack := UI.vbox(1)
	alliance_bar.add_child(stack)
	alliance_score = UI.label("", 14, UI.TEXT)
	alliance_treasury = UI.label("", 10, UI.CYAN)
	alliance_alert = UI.label("", 10, Color("#ffc171"))
	alliance_alert.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for label in [alliance_score, alliance_treasury, alliance_alert]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(label)
	add_child(alliance_bar)
	alliance_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	alliance_bar.offset_left = -180
	alliance_bar.offset_right = 180
	# Sit below the phase strip and the crew-card row (cards end ~46*_t below their top).
	alliance_bar.offset_top = 42 + 30 * (_t - 1.0) + 54.0 * _t
	_safe(alliance_bar, 0, -1)
	alliance_bar.hide()


func _build_strategic_overview(parent: Control) -> void:
	strategic_overview = UI.hbox(5)
	strategic_overview.name = "StrategicOverview"
	strategic_overview.position = Vector2(0, 428)
	strategic_overview.size.x = 480
	parent.add_child(strategic_overview)
	var names := ["PLANET A EMPIRE", "SPACE CORRIDOR", "PLANET B EMPIRE"]
	for i in names.size():
		var tint: Color = [UI.CYAN, UI.TEXT, Color("#ff896e")][i]
		var panel := UI.panel(Vector2(145, 0), Color("#172333"))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strategic_overview.add_child(panel)
		var stack := UI.vbox(1)
		panel.add_child(stack)
		var title_label := UI.label(names[i], 10, tint)
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(title_label)
		var contacts := UI.label("", 11, tint)
		contacts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(contacts)
		strategic_contacts.append(contacts)
	strategic_overview.hide()


func update_empire(sim: Sim) -> void:
	var empire := sim.empire
	var active := empire != null
	alliance_bar.visible = active
	strategic_overview.visible = active
	tactical_legend.visible = not active
	tactical_help.visible = not active
	if not active:
		tactical_radar.position = Vector2(38, 38)
		tactical_radar.size = Vector2(404, 404)
		return
	var remaining := ceili(empire.duration - empire.elapsed)
	var act: String = ["I", "II", "III", "IV"][empire.act_number - 1]
	alliance_score.text = "PLANET A %d  |  %02d:%02d · ACT %s  |  %d PLANET B" % [
		empire.scores["planet_a"], remaining / 60, remaining % 60, act, empire.scores["planet_b"]]
	alliance_treasury.text = "ALLIANCE TREASURY · %d CR" % int(empire.treasury[sim.empire_home])
	var alerts := PackedStringArray()
	for alliance: String in ["planet_a", "planet_b"]:
		if (alliance != "planet_a" or empire.act_number >= 2) and not empire.get_active_invaders(alliance).is_empty():
			alerts.append("%s UNDER ATTACK" % alliance.to_upper().replace("_", " "))
	if empire.overdrive:
		alerts.append("OVERDRIVE · 2× GOLDEN CORES")
	_empire_alert_text = "  /  ".join(alerts)
	alliance_alert.text = _empire_alert_text
	alliance_alert.visible = not alerts.is_empty()
	if not tactical_panel.visible:
		return
	tactical_radar.position = Vector2(46, 38)
	tactical_radar.size = Vector2(388, 388)
	_strategic_tiers(empire.structures["planet_a"], strategic_contacts[0])
	_strategic_tiers(empire.structures["planet_b"], strategic_contacts[2])
	var a_count := 0
	var b_count := 0
	for ship: Dictionary in empire.get_space_traffic():
		if ship["alliance"] == "planet_a":
			a_count += 1
		else:
			b_count += 1
	strategic_contacts[1].text = "%s  │  %s" % ["●".repeat(a_count) + "·".repeat(4 - a_count), "◆".repeat(b_count) + "·".repeat(4 - b_count)]
	strategic_contacts[1].tooltip_text = "%d Planet A ships · %d Planet B ships" % [a_count, b_count]


func set_flight_contacts(escort: float, intercept: float) -> void:
	var callouts := PackedStringArray()
	if is_finite(escort):
		callouts.append("ESCORT %d m" % roundi(escort))
	if is_finite(intercept):
		callouts.append("INTERCEPT FLAG CARRIER %d m" % roundi(intercept))
	if not _empire_alert_text.is_empty():
		callouts.append(_empire_alert_text)
	alliance_alert.text = "  /  ".join(callouts)
	alliance_alert.visible = not callouts.is_empty()


func _strategic_tiers(structures: Dictionary, label: Label) -> void:
	var dots := PackedStringArray()
	var tooltip := PackedStringArray()
	for id: String in Sim.EmpireRules.BUILDABLE_SLOT_IDS:
		var structure: Dictionary = structures[id]
		var tier: int = structure["tier"]
		var symbol: String = ["○", "◔", "◑", "●"][tier]
		if tier > 0 and (structure["hp"] <= 0.0 or structure["sabotage_timer"] > 0.0):
			symbol = "×"
		dots.append(symbol)
		tooltip.append("%s · T%d" % [Sim.EmpireRules.EMPIRE_SLOTS[id]["name"], tier])
	label.text = "  ".join(dots)
	label.tooltip_text = "\n".join(tooltip)
