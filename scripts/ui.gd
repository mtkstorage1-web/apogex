## APOGEX visual language: dark violet glass panels, warm orange accent, condensed uppercase labels.
class_name UI
extends RefCounted

const BG := Color("#1c1528")
const PANEL := Color(0.13, 0.10, 0.19, 0.84)
const PANEL_SOLID := Color("#2a2138")
const LINE := Color(1, 1, 1, 0.13)
const TEXT := Color("#f3eef8")
const MUTED := Color("#b4a8c6")
const DIM := Color("#7d7191")
const ACCENT := Color("#eaa665")
const ACCENT_DARK := Color("#26190f")
const GOOD := Color("#9cdeb1")
const BAD := Color("#ed7d8d")
const WARN := Color("#f7ce59")

const BG_DEEP := Color("#120d1b")
const PANEL_TACTICAL := Color(0.025, 0.045, 0.065, 0.98)
const PANEL_ADVICE := Color(0.035, 0.065, 0.09, 0.94)
const LINE_SUBTLE := Color(1, 1, 1, 0.07)
const LINE_STRONG := Color(1, 1, 1, 0.24)
const ACCENT_HOVER := Color("#f2bd89")
const ACCENT_PRESSED := Color("#d3955b")
const INFO_PWR := Color("#68cce2")
const INFO_AIR := Color("#aabfe4")
const INFO_CO2 := Color("#b6a7dc")
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
static var _styles := {}
static var _cards := {}
static var _fonts := {}
static var _caps_font: FontVariation
static var _theme: Theme

static func ramp_color(ratio: float, nominal := GOOD) -> Color:
	if ratio <= 0.10: return BAD
	if ratio <= 0.30: return WARN
	if ratio <= 0.60: return nominal.lerp(WARN, 0.35)
	return nominal

static func font(mono := false, path_override := "") -> FontVariation:
	var path := path_override if path_override != "" else ("res://assets/fonts/JetBrainsMono.ttf" if mono else "res://assets/fonts/SpaceGrotesk.ttf")
	if _fonts.has(path): return _fonts[path]
	var f := FontVariation.new()
	if ResourceLoader.exists(path):
		f.base_font = load(path)
		if f.base_font is FontFile and f.base_font != ThemeDB.fallback_font:
			f.base_font.multichannel_signed_distance_field = true
			f.base_font.generate_mipmaps = false
	elif path_override == "":
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["JetBrains Mono", "SF Mono", "Menlo", "Monaco", "Courier New"] if mono else ["Space Grotesk", "Avenir Next", "SF Pro Display", "Helvetica Neue", "Arial"])
		sf.fallbacks = [ThemeDB.fallback_font]
		f.base_font = sf
	else:
		f.base_font = ThemeDB.fallback_font
	_fonts[path] = f
	return f

static func mono_label(text: String, size := 15, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, align)
	l.add_theme_font_override("font", font(true))
	return l

static func component(name: String) -> StyleBoxFlat:
	if _styles.has(name): return _styles[name]
	var s: StyleBoxFlat
	match name:
		"toast": s = style(Color(0.12, 0.09, 0.17, 0.92), LINE, 4, 14); s.content_margin_top = 7; s.content_margin_bottom = 7
		"tooltip": s = style(Color(0.08, 0.06, 0.12, 0.96), LINE_STRONG, 4, 10); s.content_margin_top = 6; s.content_margin_bottom = 6
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


## Premium card: deep fill, hairline border, soft drop shadow, optional glow.
static func card_style(accent: Color, selected: bool) -> StyleBoxFlat:
	var key := str([accent, selected])
	if _cards.has(key): return _cards[key]
	var s := style(Color(0.105, 0.08, 0.155, 0.96) if not selected else Color(0.15, 0.115, 0.22, 0.98), accent if selected else Color(1, 1, 1, 0.09), 10, 16, 2 if selected else 1).duplicate()
	s.border_width_top = 4 if selected else 1
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.35) if selected else Color(0, 0, 0, 0.45)
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
	t.set_stylebox("normal", "Button", style(Color(0.16, 0.12, 0.22, 0.88), LINE))
	t.set_stylebox("hover", "Button", style(Color(0.24, 0.18, 0.32, 0.95), ACCENT))
	t.set_stylebox("pressed", "Button", style(Color(0.3, 0.22, 0.38, 0.95), ACCENT))
	t.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), ACCENT, 4, 12, 2))
	t.set_stylebox("disabled", "Button", style(Color(0.12, 0.1, 0.16, 0.6), Color(1, 1, 1, 0.05)))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := t.get_stylebox(state, "Button") as StyleBoxFlat
		box.content_margin_top = 8
		box.content_margin_bottom = 8
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_font_size("font_size", "Button", 14)
	t.set_stylebox("panel", "PanelContainer", style(PANEL, LINE, 6, 14))
	t.set_stylebox("panel", "Panel", style(PANEL, LINE, 6, 14))
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
	if size <= 12:
		if not _caps_font:
			_caps_font = FontVariation.new()
			_caps_font.base_font = font()
			_caps_font.spacing_glyph = 1
		l.add_theme_font_override("font", _caps_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	if size >= 18:
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0.07, 0.05, 0.11, 0.78))
	return l


static func heading(white: String, orange: String, size := 64) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("normal_font_size", size)
	r.text = "[b]%s[color=#eaa665]%s[/color][/b]" % [white, orange]
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


static func button(text: String, cb: Callable, primary := false, min_w := 0.0, min_h := 46.0) -> Button:
	var b := Button.new()
	b.text = text
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
	b.mouse_entered.connect(_hover.bind(b, true))
	b.mouse_exited.connect(_hover.bind(b, false))
	return b


static func toggle(text: String, on: bool, cb: Callable, min_w := 0.0) -> Button:
	var b := button(text, cb, false, min_w, 34)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if on:
		b.add_theme_stylebox_override("normal", style(Color(0.3, 0.24, 0.16, 0.9), ACCENT, 4, 12, 2))
	b.add_theme_font_size_override("font_size", 12)
	return b


static func panel(min_size := Vector2.ZERO, bg := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override("panel", style(bg, LINE, 6, 14))
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


static func _hover(b: Button, active: bool) -> void:
	var old = b.get_meta("hover_tween") if b.has_meta("hover_tween") else null
	if old is Tween: old.kill()
	var target := Color(1.06, 1.06, 1.06) if active else Color.WHITE
	if reduced_motion: b.modulate = target; return
	var tw := b.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "modulate", target, 0.10)
	b.set_meta("hover_tween", tw)
