## Shared APOGEX UI styles, typography, and motion.
class_name UI
extends RefCounted

const BG := Color("#101d40")
const PANEL := Color("#0f1b3dd1")
const PANEL_SOLID := Color("#17264c")
const LINE := Color(1, 1, 1, 0.22)
const TEXT := Color("#ffffff")
const MUTED := Color("#c7d2fe")
const DIM := Color("#7c86b8")
const HUD_YELLOW := Color("#facc15")
const ACCENT := HUD_YELLOW
const ACCENT_DARK := Color("#0a1024")
const GOOD := Color("#4ade80")
const BAD := Color("#f43f5e")
const WARN := Color("#fbbf24")

const BG_DEEP := Color("#0a1024")
const PANEL_TACTICAL := Color("#101d40fa")
const PANEL_ADVICE := Color("#152446f0")
const LINE_SUBTLE := Color(1, 1, 1, 0.07)
const LINE_STRONG := Color(1, 1, 1, 0.24)
const ACCENT_HOVER := Color("#ffe368")
const ACCENT_PRESSED := Color("#d9a900")
const INFO_PWR := Color("#38bdf8")
const HUD_CYAN := Color("#22d3ee")
const RADAR_TEAL := HUD_CYAN
const CYAN := HUD_CYAN
const MAGENTA := Color("#f472b6")
const CORAL := Color("#fb7185")
const GOLD := Color("#ffd34d")
const EMERALD := Color("#34d399")
const VIOLET := Color("#a78bfa")
const INDIGO_GLASS := PANEL
const INFO_AIR := Color("#93c5fd")
const INFO_CO2 := Color("#a78bfa")
const HUD_GLASS := Color("#0f1b3de0")
const HUD_EDGE := Color(HUD_CYAN, 0.46)
const FONT_XS := 10
const FONT_SM := 12
const FONT_MD := 14
const FONT_BASE := 15
const FONT_LG := 18
const FONT_XL := 24
const FONT_2XL := 40
const FONT_HERO := 54
const SP_2 := 2
const SP_4 := 4
const SP_6 := 6
const SP_8 := 8
const SP_12 := 12
const SP_16 := 16
const SP_20 := 20
const SP_24 := 24
const SP_32 := 32
const RAD_SM := 2
const RAD_MD := 4
const RAD_LG := 6
const RAD_CARD := 10
const RAD_PILL := 20
const BW_NONE := 0
const BW_HAIR := 1
const BW_ACTIVE := 2
const BW_CARD_TOP := 4
static var reduced_motion := false
static var on_hover_sfx: Callable = Callable()
static var _styles := {}
static var _cards := {}
static var _fonts := {}
const BODY_FONT_PATH := "res://assets/fonts/Nunito-ExtraBold.ttf"
const DISPLAY_FONT_PATH := "res://assets/fonts/LilitaOne-Regular.ttf"
static var _theme: Theme

static func ramp_color(ratio: float, nominal := GOOD) -> Color:
	if ratio <= 0.10: return BAD
	if ratio <= 0.30: return WARN
	if ratio <= 0.60: return nominal.lerp(WARN, 0.35)
	return nominal

static func font(mono := false, path_override := "") -> FontVariation:
	var path := path_override if path_override != "" else (DISPLAY_FONT_PATH if mono else BODY_FONT_PATH)
	if _fonts.has(path):
		return _fonts[path]
	var face := FontVariation.new()
	face.base_font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	_fonts[path] = face
	return face


static func mono_label(text: String, size := 15, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, align)
	l.add_theme_font_override("font", font(true))
	return l

static func component(name: String) -> StyleBoxFlat:
	if _styles.has(name): return _styles[name]
	var s: StyleBoxFlat
	match name:
		"toast": s = style(PANEL_SOLID, CYAN, 12, 14); s.content_margin_top = 7; s.content_margin_bottom = 7
		"tooltip": s = style(PANEL_SOLID, VIOLET, 10, 10); s.content_margin_top = 6; s.content_margin_bottom = 6
		"banner": s = style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0)
		_: s = style(PANEL)
	if name in ["toast", "tooltip"]:
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 8
		s.shadow_offset = Vector2(0, 4)
	_styles[name] = s
	return s

static func smooth_bar(b: ProgressBar, value: float) -> void:
	value = clampf(value, 0, 1)
	if b.get_meta("target", -1.0) == value: return
	b.set_meta("target", value)
	var old = b.get_meta("fill_tween") if b.has_meta("fill_tween") else null
	if old is Tween: old.kill()
	if reduced_motion or not b.is_inside_tree(): b.value = value; return
	var tw := b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "value", value, 0.14)
	b.set_meta("fill_tween", tw)


static func style(bg: Color, border := LINE, radius := 4, pad := 12, bw := 1) -> StyleBoxFlat:
	var key := str([bg, border, radius, pad, bw])
	if _styles.has(key): return _styles[key]
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	_styles[key] = s
	return s


## A single segment per corner gives the frame a straight bevel.
static func chamfered_style(bg: Color, border := HUD_EDGE, cut := 10, pad := 12, bw := 1, glow := 0) -> StyleBoxFlat:
	var key := str(["chamfer", bg, border, cut, pad, bw, glow])
	if _styles.has(key):
		return _styles[key]
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.corner_detail = 1
	box.set_corner_radius_all(cut)
	box.corner_radius_top_left = cut / 2
	box.corner_radius_bottom_right = cut / 2
	box.set_border_width_all(bw)
	box.border_width_top = bw + 1 if bg.a > 0.0 and bw > 0 else bw
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad * 0.7
	box.content_margin_bottom = pad * 0.7
	box.shadow_size = glow
	box.shadow_color = Color(border, border.a * 0.32)
	_styles[key] = box
	return box


static func chamfered_panel(min_size := Vector2.ZERO, bg := HUD_GLASS, accent := HUD_EDGE, pad := 12, cut := 10, glow := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override("panel", chamfered_style(bg, accent, cut, pad, 1, glow))
	p.draw.connect(func() -> void:
		var w := p.size.x
		var h := p.size.y
		var inset := float(cut) + 4.0
		if w <= inset * 2.0 or h < 14.0:
			return
		# A short highlight fades into the top edge of the glass.
		var shine := Color(0.79, 0.94, 1.0, 0.29)
		var span := (w - inset * 2.0) * 0.62
		for i in range(8):
			var x := inset + span * float(i) / 8.0
			p.draw_line(Vector2(x, 3.5), Vector2(x + span / 8.0, 3.5),
				Color(shine, shine.a * (1.0 - float(i) / 8.0)))
		var tick := minf(16.0, (w - inset * 2.0) * 0.24)
		var secondary := HUD_CYAN if accent.r > accent.b else HUD_YELLOW
		p.draw_polyline(PackedVector2Array([
			Vector2(inset - 5.0, 9.0), Vector2(inset, 4.0), Vector2(inset + tick, 4.0)
		]), Color(accent, minf(accent.a + 0.28, 1.0)), 1.0, true)
		p.draw_polyline(PackedVector2Array([
			Vector2(w - inset - tick, h - 4.0), Vector2(w - inset, h - 4.0),
			Vector2(w - inset + 5.0, h - 9.0)
		]), Color(secondary, accent.a * 0.72), 1.0, true))
	return p


static func animate_panel_in(ctrl: Control, slide_offset: Vector2 = Vector2(0, 14), duration: float = 0.22, delay: float = 0.0) -> void:
	if ctrl.has_meta("panel_entrance"):
		return
	if reduced_motion or duration <= 0.0:
		ctrl.modulate.a = 1.0
		return
	ctrl.set_meta("panel_entrance", true)
	ctrl.modulate.a = 0.0
	var start := func() -> void:
		if not ctrl.is_inside_tree():
			ctrl.modulate.a = 1.0
			ctrl.remove_meta("panel_entrance")
			return
		# Wait for containers to assign the control its layout position.
		var tween := ctrl.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var position_state := {"base": ctrl.position, "last": ctrl.position}
		var move := func(progress: float) -> void:
			if not ctrl.position.is_equal_approx(position_state["last"]):
				position_state["base"] = ctrl.position
			ctrl.position = position_state["base"] + slide_offset * (1.0 - progress)
			position_state["last"] = ctrl.position
			ctrl.modulate.a = progress
		move.call(0.0)
		tween.tween_method(move, 0.0, 1.0, duration).set_delay(maxf(0.0, delay))
		tween.finished.connect(ctrl.remove_meta.bind("panel_entrance"), CONNECT_ONE_SHOT)
	if ctrl.is_inside_tree():
		start.call_deferred()
	else:
		ctrl.tree_entered.connect(start.call_deferred, CONNECT_ONE_SHOT)


static func add_juice(ctrl: Control, accent: Color = Color("#38bdf8"), hover_scale: float = 1.04) -> void:
	if ctrl.has_meta("ui_juice"):
		return
	var state := {"hovered": false, "pressed": false, "tween": null}
	ctrl.set_meta("ui_juice", true)
	var center := func() -> void: ctrl.pivot_offset = ctrl.size * 0.5
	center.call()
	ctrl.resized.connect(center)
	var normal_tint := ctrl.self_modulate
	var glow := Color(1.08 + accent.r * 0.16, 1.08 + accent.g * 0.16, 1.08 + accent.b * 0.16)
	var button_ctrl := ctrl as BaseButton
	var refresh := func(release: bool = false) -> void:
		var previous = state["tween"]
		if previous is Tween:
			previous.kill()
		var hovered: bool = state["hovered"] and (button_ctrl == null or not button_ctrl.disabled)
		var pressing: bool = state["pressed"] and (button_ctrl == null or not button_ctrl.disabled)
		var target := Vector2.ONE * (0.96 if pressing else (hover_scale if hovered else 1.0))
		var tint := normal_tint * glow if hovered else normal_tint
		if reduced_motion or not ctrl.is_inside_tree():
			ctrl.scale = Vector2.ONE if reduced_motion else target
			ctrl.self_modulate = tint
			return
		var tween := ctrl.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(ctrl, "self_modulate", tint, 0.12)
		var scale_step := tween.tween_property(ctrl, "scale", target, 0.07 if pressing else 0.14)
		if release:
			scale_step.set_trans(Tween.TRANS_BACK)
		state["tween"] = tween

	ctrl.mouse_entered.connect(func() -> void:
		state["hovered"] = true
		refresh.call()
		if (button_ctrl == null or not button_ctrl.disabled) and on_hover_sfx.is_valid():
			on_hover_sfx.call())
	ctrl.mouse_exited.connect(func() -> void:
		state["hovered"] = false
		refresh.call())
	if button_ctrl != null:
		button_ctrl.button_down.connect(func() -> void:
			state["pressed"] = true
			refresh.call())
		button_ctrl.button_up.connect(func() -> void:
			state["pressed"] = false
			refresh.call(true))


## Premium card: deep fill, hairline border, soft drop shadow, optional glow.
static func card_style(accent: Color, selected: bool) -> StyleBoxFlat:
	var key := str([accent, selected])
	if _cards.has(key): return _cards[key]
	var s := style(PANEL_SOLID if not selected else PANEL_SOLID.lerp(accent, 0.19), accent if selected else Color(1, 1, 1, 0.09), 10, 16, 2 if selected else 1).duplicate()
	s.border_width_top = 4 if selected else 1
	s.shadow_color = Color(0, 0, 0, 0.55) if selected else Color(0, 0, 0, 0.45)
	s.shadow_size = 22 if selected else 8
	s.shadow_offset = Vector2(0, 6 if selected else 4)
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	_cards[key] = s
	return s


## Small pill used for stat deltas and tags.
static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := style(Color(color.r, color.g, color.b, 0.14), Color(color.r, color.g, color.b, 0.45), 20, 9)
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	p.add_child(label(text, 11, color))
	return p


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.set_font("font", "MonoLabel", font(true))
	t.set_type_variation("MonoLabel", "Label")
	t.set_stylebox("panel", "TooltipPanel", component("tooltip"))
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	for type in ["Label", "RichTextLabel"]:
		t.set_color("font_outline_color", type, BG_DEEP)
		t.set_constant("outline_size", type, 4)
	t.set_font("bold_font", "RichTextLabel", font())
	t.set_stylebox("normal", "Button", style(PANEL_SOLID, Color(CYAN, 0.32), 10))
	t.set_stylebox("hover", "Button", style(Color("#29488a"), CYAN, 10))
	t.set_stylebox("pressed", "Button", style(Color("#3459a5"), ACCENT, 10))
	t.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), ACCENT, 4, 12, 2))
	t.set_stylebox("disabled", "Button", style(Color(PANEL_SOLID, 0.6), LINE_SUBTLE, 10))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := t.get_stylebox(state, "Button") as StyleBoxFlat
		box.content_margin_top = 8
		box.content_margin_bottom = 8
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_font_size("font_size", "Button", 14)
	t.set_stylebox("panel", "PanelContainer", style(Color(PANEL, 0.9), LINE, 6, 14))
	t.set_stylebox("panel", "Panel", style(Color(PANEL, 0.9), LINE, 6, 14))
	t.set_stylebox("background", "ProgressBar", style(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 2, 0, 0))
	t.set_stylebox("fill", "ProgressBar", style(ACCENT, Color(0, 0, 0, 0), 2, 0, 0))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 14)
	t.set_font_size("bold_font_size", "RichTextLabel", 14)
	_theme = t
	return t


static func label(text: String, size := 15, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(size >= FONT_XL))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.add_theme_constant_override("outline_size", 5 if size >= FONT_XL else 4)
	l.add_theme_color_override("font_outline_color", BG_DEEP)
	return l


static func heading(white: String, orange: String, size := 64) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_override("bold_font", font(true))
	r.text = "[b]%s[color=#%s]%s[/color][/b]" % [white, ACCENT.to_html(false), orange]
	return r


static func rich(text: String, size := 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.text = text
	return r


## Minimum comfortable thumb target (px) on touch devices.
const TOUCH_MIN := 56.0

## True on iOS / Android / touchscreen devices (never on a plain desktop).
static func is_touch_platform() -> bool:
	return OS.has_feature("ios") or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


## Safe-area insets (left, top, right, bottom) in viewport pixels so HUD avoids
## rounded corners, notch and the home indicator. Zero on desktop.
static func safe_insets(vp: Viewport = null) -> Vector4:
	if not is_touch_platform():
		return Vector4.ZERO
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector4.ZERO
	var vsize := Vector2(win)
	if vp != null:
		vsize = vp.get_visible_rect().size
	var k := Vector2(vsize.x / win.x, vsize.y / win.y)
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or safe.size.x <= 0:
		return Vector4.ZERO
	var l := maxf(0.0, safe.position.x) * k.x
	var t := maxf(0.0, safe.position.y) * k.y
	var r := maxf(0.0, screen.x - safe.end.x) * k.x
	var b := maxf(0.0, screen.y - safe.end.y) * k.y
	# Even on square-cornered devices keep a small breathing margin from the glass edge.
	return Vector4(maxf(l, 8.0), maxf(t, 6.0), maxf(r, 8.0), maxf(b, 10.0))


static func button(text: String, cb: Callable, primary := false, min_w := 0.0, min_h := 46.0) -> Button:
	var b := Button.new()
	b.text = text
	if is_touch_platform():
		min_h = maxf(min_h, TOUCH_MIN)
		min_w = maxf(min_w, TOUCH_MIN) if min_w > 0.0 else min_w
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if primary:
		b.add_theme_stylebox_override("normal", style(ACCENT, ACCENT, 4))
		b.add_theme_stylebox_override("hover", style(ACCENT_HOVER, Color.WHITE, 4))
		b.add_theme_stylebox_override("pressed", style(ACCENT_PRESSED, Color.WHITE, 4))
		b.add_theme_color_override("font_color", ACCENT_DARK)
		b.add_theme_color_override("font_hover_color", ACCENT_DARK)
		b.add_theme_color_override("font_pressed_color", ACCENT_DARK)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_ALL
	add_juice(b, ACCENT if primary else CYAN)
	return b


static func toggle(text: String, on: bool, cb: Callable, min_w := 0.0) -> Button:
	var b := button(text, cb, false, min_w, 34)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if on:
		b.add_theme_stylebox_override("normal", style(Color(0.16, 0.16, 0.18, 0.9), ACCENT, 4, 12, 2))
	b.add_theme_font_size_override("font_size", 14 if is_touch_platform() else 12)
	return b


static func glass_style(bg := PANEL, pad := 10, edge := BG_DEEP) -> StyleBoxFlat:
	var key := str(["glass", bg, pad, edge])
	if not _styles.has(key):
		var box := style(bg, edge, 12, pad, 3).duplicate() as StyleBoxFlat
		box.shadow_color = Color(BG_DEEP, 0.56)
		box.shadow_size = 6
		box.shadow_offset = Vector2(0, 3)
		_styles[key] = box
	return _styles[key]


static func panel(min_size := Vector2.ZERO, bg := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override("panel", glass_style(bg, 14))
	p.draw.connect(func() -> void:
		var accent := CYAN
		var frame := p.get_theme_stylebox("panel") as StyleBoxFlat
		if frame != null and frame.border_color != BG_DEEP:
			accent = frame.border_color
		p.draw_line(Vector2(13, 5), Vector2(maxf(13, p.size.x - 13), 5), Color(accent, 0.38), 2.0, true))
	return p


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func bar(color: Color, value := 1.0, height := 6.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = 1.0
	b.step = 0.0
	b.value = value
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_stylebox_override("fill", style(color, Color(0, 0, 0, 0), 2, 0, 0))
	return b


static func scifi_gauge(title: String, pct: int, accent: Color = Color("#22d3ee")) -> Control:
	var percent := clampi(pct, 0, 100)
	var badge := chamfered_panel(Vector2(132, 0), HUD_GLASS, Color(accent, 0.62), 10, 7, 6)
	var content := vbox(5)
	badge.add_child(content)
	var caption := hbox(8)
	content.add_child(caption)
	var heading_label := label(title, 11, TEXT)
	heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_child(heading_label)
	caption.add_child(mono_label("%d%%" % percent, 13, accent, HORIZONTAL_ALIGNMENT_RIGHT))
	var meter := bar(accent, float(percent) / 100.0, 6.0)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_theme_stylebox_override("background", chamfered_style(Color(accent, 0.12), Color.TRANSPARENT, 2, 0, 0))
	meter.add_theme_stylebox_override("fill", chamfered_style(accent, Color.TRANSPARENT, 2, 0, 0, 3).duplicate())
	var fill := meter.get_theme_stylebox("fill") as StyleBoxFlat
	fill.shadow_color = Color(accent, 0.55)
	content.add_child(meter)
	return badge


static func spacer(h := 0.0, w := 0.0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func fmt_time(t: float) -> String:
	t = maxf(0.0, t)
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]


static func wrapped_label(text: String, font_size := 13, color := TEXT) -> Label:
	var result := label(text, font_size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


static func loadout_summary(sim: Sim) -> String:
	var s := ShipCatalog.loadout_stats(sim.loadout)
	var missing := sim.unconfirmed_slots()
	return "%s / %d CR / DESIGN %d CR\nTWR %.2f · Δv %.0f m/s · cargo %d · power %+.2f kW\nDamage taken ×%.2f · turret ×%.2f · scan ×%.2f\nHandling ×%.2f · wet mass %.0f kg\n%s\nUnbought: %s" % [str(s["design_name"]).to_upper(), sim.credits, s["cost"], s["twr"], s["dv"], s["cargo_capacity"], s["power_margin"], s["armor"], s["turret_damage_mult"], s["scan_mult"], s["handling"], s["wet_mass"], s["synergy"], ", ".join(missing) if missing.size() else "none — ready to build"]
