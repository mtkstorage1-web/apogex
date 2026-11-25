extends Control
## Tabbed, colour-coded, touch-friendly Settings screen.
## Pure presentation: every value lives on Main (`host`), which also applies and
## persists it. Tabs rebuild lazily, so only the visible page owns live widgets.

const GraphicsSettings = preload("res://scripts/graphics_settings.gd")

const TABS := [
	{"id": "graphics", "label": "GRAPHICS", "color": UI.CYAN},
	{"id": "controls", "label": "CONTROLS", "color": UI.GOLD},
	{"id": "game", "label": "GAME", "color": UI.EMERALD},
	{"id": "audio", "label": "AUDIO", "color": UI.MAGENTA},
]
const GRAPHICS_GROUPS := [
	["DISPLAY", ["window_mode", "resolution", "render_scale", "upscaler", "vsync", "brightness"]],
	["LIGHTING & SHADOWS", ["shadows", "ssao", "ssil", "ssr", "glow", "volumetric_fog", "aa"]],
	["EFFECTS", ["motion_effects", "particles", "atmosphere", "clouds", "terrain"]],
	["PERFORMANCE", ["lod", "fps_limit", "fps_counter"]],
]
const KEYBINDS := [
	["WASD", "Move"], ["SHIFT", "Sprint"], ["SPACE", "Jump"], ["E", "Interact / pick up"],
	["LMB", "Fire / hold to work"], ["R", "Rotate / reload"], ["1-4", "Switch crew role"],
	["Q / F", "Skill / ultimate"], ["C / Z", "Tactics / mark flag"], ["M", "Tactical map"],
	["V", "Camera"], ["H", "Field manual"], ["ESC", "Pause"], ["F9", "Touch controls"],
]

var host: Node
var tab := "graphics"
var _content: VBoxContainer
var _tab_buttons := {}
var _slider_icon: ImageTexture
var _live := {}   # widget key -> refresh callback


func _init(main_node: Node = null, start_tab := "graphics") -> void:
	host = main_node
	tab = start_tab
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build_frame()
	_show_tab(tab)


# ------------------------------------------------------------------ frame
func _accent() -> Color:
	for t in TABS:
		if t["id"] == tab:
			return t["color"]
	return UI.CYAN


func _build_frame() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ins := UI.safe_insets(get_viewport())
	margin.add_theme_constant_override("margin_left", int(maxf(28.0, ins.x + 16.0)))
	margin.add_theme_constant_override("margin_top", int(maxf(20.0, ins.y + 10.0)))
	margin.add_theme_constant_override("margin_right", int(maxf(28.0, ins.z + 16.0)))
	margin.add_theme_constant_override("margin_bottom", int(maxf(20.0, ins.w + 10.0)))
	add_child(margin)
	var root := UI.vbox(10)
	margin.add_child(root)

	var head := UI.hbox(14)
	root.add_child(head)
	head.add_child(UI.heading("SETTINGS", "", 44))
	head.add_child(UI.spacer(0, 0, true))
	if GraphicsSettings.is_mobile_gpu():
		var apple := OS.get_name() == "iOS"
		head.add_child(UI.chip("APPLE SILICON · METAL" if apple else "MOBILE GPU · TILE RENDERER", UI.EMERALD))
	else:
		head.add_child(UI.chip(String(RenderingServer.get_current_rendering_method()).to_upper(), UI.VIOLET))

	var tabs := UI.hbox(8)
	root.add_child(tabs)
	for t in TABS:
		var b := UI.button(t["label"], _show_tab.bind(t["id"]), false, 0.0, 56.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 17)
		tabs.add_child(b)
		_tab_buttons[t["id"]] = b

	var card := PanelContainer.new()
	card.name = "SettingsCard"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.set_meta("card", true)
	root.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(scroll)
	_content = UI.vbox(10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	var foot := UI.hbox(12)
	root.add_child(foot)
	foot.add_child(UI.button("BACK", host._close_settings, false, 160, 56.0))


func _style_tabs() -> void:
	for t in TABS:
		var b: Button = _tab_buttons[t["id"]]
		var c: Color = t["color"]
		var on: bool = t["id"] == tab
		var fill := Color(c.r, c.g, c.b, 0.95) if on else Color(c.r, c.g, c.b, 0.10)
		var hover := Color(c.r, c.g, c.b, 0.95 if on else 0.28)
		b.add_theme_stylebox_override("normal", UI.style(fill, c if on else Color(c.r, c.g, c.b, 0.45), 8, 12, 2))
		b.add_theme_stylebox_override("hover", UI.style(hover, c, 8, 12, 2))
		b.add_theme_stylebox_override("pressed", UI.style(hover, Color.WHITE, 8, 12, 2))
		var text_col := Color("#10101c") if on else c
		for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(n, text_col if (on or n != "font_hover_color") else Color.WHITE)
	var card := find_child("SettingsCard", true, false)
	if card != null:
		var accent := _accent()
		var s := UI.style(UI.INDIGO_GLASS, Color(accent.r, accent.g, accent.b, 0.7), 12, 18, 2).duplicate() as StyleBoxFlat
		s.border_width_top = 4
		s.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
		s.shadow_size = 14
		card.add_theme_stylebox_override("panel", s)


func _show_tab(id: String) -> void:
	tab = id
	host.settings_tab = id
	host.graphics_open = id == "graphics"
	host.graphics_buttons.clear()
	_live.clear()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_style_tabs()
	match id:
		"graphics": _build_graphics()
		"controls": _build_controls()
		"game": _build_game()
		"audio": _build_audio()
	if id == "graphics":
		host._refresh_graphics_buttons()
	refresh()


## Re-sync live widgets after a value changed elsewhere (reset, reduced motion...).
func refresh() -> void:
	for cb: Callable in _live.values():
		if cb.is_valid():
			cb.call()


# ------------------------------------------------------------------ widgets
func _section(text: String) -> void:
	var accent := _accent()
	var row := UI.hbox(10)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(5, 20)
	row.add_child(bar)
	row.add_child(UI.label(text, 15, accent))
	_content.add_child(row)


func _row_card() -> HBoxContainer:
	var p := PanelContainer.new()
	var s := UI.style(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.09), 8, 12, 1)
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(p)
	var h := UI.hbox(12)
	p.add_child(h)
	return h


func _name_block(h: HBoxContainer, title: String, hint := "") -> void:
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(UI.label(title, 16, UI.TEXT))
	if hint != "":
		v.add_child(UI.label(hint, 12, UI.MUTED))
	h.add_child(v)


func _accent_button(b: Button, on: bool) -> void:
	var c := _accent()
	var fill := Color(c.r, c.g, c.b, 0.92) if on else Color(c.r, c.g, c.b, 0.10)
	b.add_theme_stylebox_override("normal", UI.style(fill, c if on else Color(c.r, c.g, c.b, 0.4), 8, 12, 2))
	b.add_theme_stylebox_override("hover", UI.style(Color(c.r, c.g, c.b, 0.95 if on else 0.3), c, 8, 12, 2))
	b.add_theme_stylebox_override("pressed", UI.style(Color(c.r, c.g, c.b, 0.95), Color.WHITE, 8, 12, 2))
	var tc := Color("#10101c") if on else c
	b.add_theme_color_override("font_color", tc)
	b.add_theme_color_override("font_pressed_color", Color("#10101c"))
	b.add_theme_color_override("font_hover_color", tc if on else Color.WHITE)


func _toggle_row(title: String, hint: String, getter: Callable, setter: Callable, enabled := true) -> void:
	var h := _row_card()
	_name_block(h, title, hint)
	var b := UI.button("", func():
		setter.call(not getter.call())
		refresh(), false, 128.0, 56.0 if UI.is_touch_platform() else 46.0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.disabled = not enabled
	h.add_child(b)
	_live["toggle:" + title] = func():
		var on: bool = getter.call()
		b.text = "ON" if on else "OFF"
		_accent_button(b, on)


func _segment_row(title: String, hint: String, options: Array, getter: Callable, setter: Callable) -> void:
	var h := _row_card()
	_name_block(h, title, hint)
	var seg := UI.hbox(6)
	h.add_child(seg)
	var buttons: Array = []
	for opt in options:
		var b := UI.button(String(opt), func():
			setter.call(String(opt))
			refresh(), false, 84.0, 56.0 if UI.is_touch_platform() else 46.0)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		seg.add_child(b)
		buttons.append(b)
	_live["seg:" + title] = func():
		for i in buttons.size():
			_accent_button(buttons[i], String(options[i]) == String(getter.call()))


func _make_slider_icon(c: Color) -> ImageTexture:
	var size := 36
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(Vector2(mid, mid))
			if d <= 16.0:
				var col := Color.WHITE if d > 12.0 else c
				col.a = clampf(17.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _slider_row(title: String, hint: String, lo: float, hi: float, step: float,
		getter: Callable, setter: Callable, fmt: Callable) -> void:
	var c := _accent()
	var h := _row_card()
	_name_block(h, title, hint)
	var touch_h := 56.0 if UI.is_touch_platform() else 44.0
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(240, touch_h)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.scrollable = false   # wheel/drag over the page must scroll, not change values
	var track := UI.style(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 5, 0, 0).duplicate() as StyleBoxFlat
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := UI.style(c, Color(0, 0, 0, 0), 5, 0, 0).duplicate() as StyleBoxFlat
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var icon := _make_slider_icon(c)
	slider.add_theme_icon_override("grabber", icon)
	slider.add_theme_icon_override("grabber_highlight", icon)
	slider.add_theme_icon_override("grabber_disabled", icon)
	var value_label := UI.label("", 17, c, HORIZONTAL_ALIGNMENT_RIGHT)
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var minus := UI.button("−", func(): slider.value = clampf(slider.value - step, lo, hi), false, touch_h, touch_h)
	var plus := UI.button("+", func(): slider.value = clampf(slider.value + step, lo, hi), false, touch_h, touch_h)
	for sb in [minus, plus]:
		sb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_accent_button(sb, false)
	var ctl := UI.hbox(8)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.size_flags_stretch_ratio = 1.4
	h.add_child(ctl)
	ctl.add_child(minus)
	ctl.add_child(slider)
	ctl.add_child(plus)
	ctl.add_child(value_label)
	slider.value_changed.connect(func(v: float):
		setter.call(v)
		value_label.text = fmt.call(getter.call()))
	_live["slider:" + title] = func():
		slider.set_value_no_signal(float(getter.call()))
		value_label.text = fmt.call(getter.call())


func _action_button(text: String, cb: Callable, width := 0.0) -> Button:
	var b := UI.button(text, cb, false, width, 56.0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_accent_button(b, false)
	return b


# ------------------------------------------------------------------ pages
func _build_graphics() -> void:
	var g: RefCounted = host.graphics
	_section("QUALITY PRESET")
	var top := _row_card()
	var preset := UI.button("", host._cycle_graphics_quality, false, 0.0, 56.0 if UI.is_touch_platform() else 46.0)
	preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset.size_flags_stretch_ratio = 0.8
	_accent_button(preset, false)
	top.add_child(preset)
	host.graphics_buttons["quality"] = preset
	# Direct picks avoid forcing a stop at ULTRA (multi-second Metal shader stall) when going HIGH -> LOW.
	var picks := UI.hbox(6)
	picks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(picks)
	for level in GraphicsSettings.CUSTOM:
		var pick := UI.button(GraphicsSettings.QUALITY_NAMES[level], host._select_graphics_preset.bind(level), false, 90.0, 56.0 if UI.is_touch_platform() else 46.0)
		pick.toggle_mode = true
		pick.alignment = HORIZONTAL_ALIGNMENT_CENTER
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picks.add_child(pick)
		host.graphics_buttons["preset_%d" % level] = pick
		var c := _accent()
		pick.add_theme_stylebox_override("pressed", UI.style(Color(c.r, c.g, c.b, 0.92), Color.WHITE, 8, 12, 2))
		pick.add_theme_stylebox_override("hover_pressed", UI.style(Color(c.r, c.g, c.b, 0.92), Color.WHITE, 8, 12, 2))
		pick.add_theme_color_override("font_pressed_color", Color("#10101c"))
		pick.add_theme_color_override("font_hover_pressed_color", Color("#10101c"))
	var placed := {}
	for group in GRAPHICS_GROUPS:
		for key in group[1]:
			placed[key] = true
	var extras: Array = []
	for key in GraphicsSettings.OPTIONS:
		if not placed.has(key):
			extras.append(key)
	for group in GRAPHICS_GROUPS:
		_section(group[0])
		var keys: Array = group[1].duplicate()
		if group[0] == "PERFORMANCE":
			keys.append_array(extras)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		_content.add_child(grid)
		for key in keys:
			if not GraphicsSettings.OPTIONS.has(key):
				continue
			var option := UI.button("", host._cycle_graphics_option.bind(key), false, 0.0, 56.0 if UI.is_touch_platform() else 46.0)
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(option)
			host.graphics_buttons[key] = option
	var actions := UI.hbox(10)
	_content.add_child(actions)
	actions.add_child(_action_button("RESET GRAPHICS TO DEFAULT", host._reset_graphics, 330.0))
	if g.renderer() == &"gl_compatibility":
		actions.add_child(UI.chip("COMPATIBILITY RENDERER · SOME EFFECTS UNAVAILABLE", UI.WARN))


func _build_controls() -> void:
	_section("LOOK")
	_slider_row("LOOK SENSITIVITY", "Mouse and touch camera speed", 0.4, 2.5, 0.1,
		func(): return host.sens,
		func(v: float): host.set_look_sensitivity(v),
		func(v): return "%.1f×" % v)
	_toggle_row("INVERT Y-AXIS", "Push up to look down",
		func(): return host.invert_y, func(on: bool): host.set_invert_y(on))
	_section("TOUCH")
	_segment_row("INPUT MODE", "Keyboard & mouse, or on-screen touch controls", ["KBM", "TOUCH"],
		func(): return "TOUCH" if host.touch_mode == "on" else "KBM",
		func(m: String): host.set_touch_mode("on" if m == "TOUCH" else "off"))
	_slider_row("TOUCH OPACITY", "On-screen stick and buttons", 40.0, 100.0, 5.0,
		func(): return host.touch_opacity * 100.0,
		func(v: float): host.set_touch_opacity(v / 100.0),
		func(v): return "%d%%" % roundi(v))
	_toggle_row("HAPTIC FEEDBACK", "Vibration on taps (iOS / mobile only)",
		func(): return host.haptics, func(on: bool): host.set_haptics(on), UI.is_touch_platform())
	_section("HUD LAYOUT")
	var lh := _row_card()
	_name_block(lh, "CUSTOMIZE HUD LAYOUT", "Play 2, 4, 5 or 6 fingers · drag every button wherever you like")
	var chip_slot := UI.hbox(0)
	chip_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lh.add_child(chip_slot)
	var customize := UI.button("CUSTOMIZE HUD LAYOUT", host.open_hud_layout_editor, true, 260.0, 56.0 if UI.is_touch_platform() else 46.0)
	customize.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_accent_button(customize, true)
	lh.add_child(customize)
	_live["hud_layout_chip"] = func():
		for c in chip_slot.get_children():
			chip_slot.remove_child(c)
			c.queue_free()
		chip_slot.add_child(UI.chip(host.hud_preset, UI.CYAN))
	_section("CONTROLS REFERENCE")
	var ref := PanelContainer.new()
	ref.add_theme_stylebox_override("panel", UI.style(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.09), 8, 14, 1))
	_content.add_child(ref)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	ref.add_child(grid)
	for bind in KEYBINDS:
		var cell := UI.hbox(10)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key_chip := UI.chip(bind[0], _accent())
		key_chip.custom_minimum_size = Vector2(84, 0)
		cell.add_child(key_chip)
		cell.add_child(UI.label(bind[1], 14, UI.TEXT))
		grid.add_child(cell)
	_content.add_child(UI.label("Touch: left stick moves · drag right side to look · hold FIRE to act", 13, UI.MUTED))


func _build_game() -> void:
	_section("ACCESSIBILITY")
	_toggle_row("REDUCED MOTION", "Calmer HUD, no shake or flash",
		func(): return UI.reduced_motion, func(on: bool): host.set_reduced_motion(on))
	_section("HUD")
	_slider_row("HUD OPACITY", "See-through HUD panels", 35.0, 100.0, 5.0,
		func(): return host.hud_opacity * 100.0,
		func(v: float): host.set_hud_opacity(v / 100.0),
		func(v): return "%d%%" % roundi(v))
	_toggle_row("SHOW FPS COUNTER", "Frame rate and frame time overlay",
		func(): return host.graphics.values["fps_counter"], func(on: bool): host.set_fps_counter(on))
	_toggle_row("ADVISOR HINTS", "Crew advisor tips during missions",
		func(): return host.advisor_hints, func(on: bool): host.set_advisor_hints(on))
	_section("DATA")
	var row := _row_card()
	_name_block(row, "RESET ALL DEFAULTS", "Restores graphics, controls, game and audio settings")
	var reset := UI.button("RESET ALL DEFAULTS", host.reset_all_settings, false, 260.0, 56.0)
	reset.alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset.add_theme_stylebox_override("normal", UI.style(Color(UI.BAD.r, UI.BAD.g, UI.BAD.b, 0.14), UI.BAD, 8, 12, 2))
	reset.add_theme_stylebox_override("hover", UI.style(Color(UI.BAD.r, UI.BAD.g, UI.BAD.b, 0.35), UI.BAD, 8, 12, 2))
	reset.add_theme_color_override("font_color", UI.BAD)
	row.add_child(reset)


func _build_audio() -> void:
	_section("VOLUME")
	_slider_row("MASTER VOLUME", "Effects, ambience and crew callouts", 0.0, 100.0, 5.0,
		func(): return host.volume_percent(),
		func(v: float): host.set_volume_percent(v),
		func(v): return "%d%%" % roundi(v))
	_toggle_row("MUTE AUDIO", "Silences the master bus",
		func(): return host.audio_muted, func(on: bool): host.set_audio_muted(on))
