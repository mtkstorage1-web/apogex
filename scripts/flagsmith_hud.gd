extends CanvasLayer

# Sleek, APOGEX-styled Flagsmith Experiment Inspector (F9 or bottom-left ⚑ FLAGS pill)

const COL_BG := Color(0.055, 0.075, 0.14, 0.94)
const COL_CARD := Color(0.09, 0.12, 0.21, 0.92)
const COL_BORDER := Color(0.29, 0.84, 0.96, 0.35)
const COL_CYAN := Color(0.30, 0.84, 0.96, 1.0)
const COL_GOLD := Color(0.95, 0.79, 0.30, 1.0)
const COL_GREEN := Color(0.45, 0.90, 0.62, 1.0)
const COL_MUTED := Color(0.65, 0.72, 0.84, 1.0)
const COL_TEXT := Color(0.95, 0.97, 1.0, 1.0)

var _panel: PanelContainer
var _status_pill: Label
var _key_input: LineEdit
var _connect_btn: Button
var _meta_label: Label
var _flags_box: VBoxContainer
var _telemetry_box: VBoxContainer
var _error_label: Label

func _ready() -> void:
	layer = 100
	_build_ui()
	if has_node("/root/FlagsmithManager"):
		var mgr = get_node("/root/FlagsmithManager")
		mgr.flags_updated.connect(_render)
		_render(mgr.get_snapshot())
	if OS.get_cmdline_user_args().has("--demo-record"):
		_run_demo_choreography()

func _run_demo_choreography() -> void:
	var mgr = get_node_or_null("/root/FlagsmithManager")
	if mgr == null:
		return
	var main_node = get_tree().current_scene
	if main_node:
		if "graphics" in main_node and main_node.graphics != null and main_node.graphics.has_method("set_preset"):
			main_node.graphics.set_preset(3) # ULTRA
			if main_node.has_method("apply_graphics"):
				main_node.apply_graphics()

	# 1. Squad Lobby + Flagsmith Inspector (0s - 8.5s)
	await get_tree().create_timer(2.2, true, false, true).timeout
	_panel.visible = true
	await get_tree().create_timer(1.8, true, false, true).timeout
	mgr.set_local_override("exp_extraction_balance", true, "fast_blitz")
	await get_tree().create_timer(1.2, true, false, true).timeout
	mgr.set_local_override("exp_combat_pacing", true, "turbo_clash")
	await get_tree().create_timer(1.2, true, false, true).timeout
	mgr.set_local_override("feature_moon_low_gravity", true, null)
	await get_tree().create_timer(1.6, true, false, true).timeout

	# 2. Earth Spaceport: Build Spacecraft & Board Cockpit (8.5s - 13.5s)
	_panel.visible = false
	main_node = get_tree().current_scene
	if main_node and main_node.has_method("quick_deploy"):
		main_node.quick_deploy()
	Engine.time_scale = 2.0
	await get_tree().create_timer(5.0, true, false, true).timeout

	# 3. Launch into Space Transit (13.5s - 19.0s)
	if main_node and main_node.has_method("_begin_travel"):
		main_node._begin_travel("space")
	await get_tree().create_timer(5.5, true, false, true).timeout

	# 4. Land on Planet C · Moon — Frontier Arena & Science Flags (19.0s - 27.0s)
	if main_node and main_node.has_method("_begin_travel"):
		main_node._begin_travel("planet_c")
	await get_tree().create_timer(8.0, true, false, true).timeout

	# 5. Return to Earth & Show Updated Flagsmith A/B Telemetry (27.0s - 36.0s)
	if main_node and main_node.has_method("_begin_travel"):
		main_node._begin_travel("planet_a")
	Engine.time_scale = 1.0
	await get_tree().create_timer(3.0, true, false, true).timeout
	mgr.track_event("flag_delivered", {"count": 3})
	mgr.track_event("match_ended", {"won": true})
	_panel.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()

func _make_box(bg: Color, border: Color, radius: int = 10, pad_x: int = 14, pad_y: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s

func _build_ui() -> void:
	# Sleek bottom-left toggle pill
	var toggle_btn := Button.new()
	toggle_btn.text = "⚑  FLAGS · F9"
	toggle_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	toggle_btn.offset_left = 20
	toggle_btn.offset_right = 156
	toggle_btn.offset_top = -54
	toggle_btn.offset_bottom = -18
	toggle_btn.add_theme_font_size_override("font_size", 13)
	toggle_btn.add_theme_color_override("font_color", COL_GOLD)
	toggle_btn.add_theme_stylebox_override("normal", _make_box(COL_BG, COL_GOLD * Color(1, 1, 1, 0.55), 8, 12, 6))
	toggle_btn.add_theme_stylebox_override("hover", _make_box(COL_CARD, COL_GOLD, 8, 12, 6))
	toggle_btn.add_theme_stylebox_override("pressed", _make_box(COL_CARD, COL_CYAN, 8, 12, 6))
	toggle_btn.pressed.connect(func(): _panel.visible = not _panel.visible)
	add_child(toggle_btn)

	# Clean floating dark-glass card anchored bottom-left above the pill
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 20
	_panel.offset_right = 410
	_panel.offset_top = -520
	_panel.offset_bottom = -64
	_panel.add_theme_stylebox_override("panel", _make_box(COL_BG, COL_BORDER, 12, 16, 14))
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)

	# Header row
	var head := HBoxContainer.new()
	root.add_child(head)

	var title := Label.new()
	title.text = "FLAGSMITH"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COL_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	_status_pill = Label.new()
	_status_pill.add_theme_font_size_override("font_size", 11)
	head.add_child(_status_pill)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", COL_MUTED)
	close_btn.pressed.connect(func(): _panel.visible = false)
	head.add_child(close_btn)

	# Compact Environment Key bar
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 6)
	root.add_child(key_row)

	_key_input = LineEdit.new()
	_key_input.placeholder_text = "Flagsmith Environment Key (optional)"
	_key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_input.add_theme_font_size_override("font_size", 12)
	_key_input.add_theme_stylebox_override("normal", _make_box(COL_CARD, Color(1, 1, 1, 0.12), 6, 8, 5))
	key_row.add_child(_key_input)

	_connect_btn = Button.new()
	_connect_btn.text = "Sync"
	_connect_btn.add_theme_font_size_override("font_size", 12)
	_connect_btn.add_theme_color_override("font_color", Color(0.05, 0.08, 0.14))
	_connect_btn.add_theme_stylebox_override("normal", _make_box(COL_CYAN, COL_CYAN, 6, 10, 5))
	_connect_btn.add_theme_stylebox_override("hover", _make_box(COL_GOLD, COL_GOLD, 6, 10, 5))
	_connect_btn.pressed.connect(_on_connect_pressed)
	key_row.add_child(_connect_btn)

	_error_label = Label.new()
	_error_label.add_theme_font_size_override("font_size", 11)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.5))
	_error_label.visible = false
	root.add_child(_error_label)

	_meta_label = Label.new()
	_meta_label.add_theme_font_size_override("font_size", 11)
	_meta_label.add_theme_color_override("font_color", COL_MUTED)
	root.add_child(_meta_label)

	var sep1 := HSeparator.new()
	sep1.modulate = Color(1, 1, 1, 0.15)
	root.add_child(sep1)

	# Experiments & Flags list
	_flags_box = VBoxContainer.new()
	_flags_box.add_theme_constant_override("separation", 6)
	root.add_child(_flags_box)

	var sep2 := HSeparator.new()
	sep2.modulate = Color(1, 1, 1, 0.15)
	root.add_child(sep2)

	var tel_title := Label.new()
	tel_title.text = "A/B TELEMETRY"
	tel_title.add_theme_font_size_override("font_size", 11)
	tel_title.add_theme_color_override("font_color", COL_CYAN)
	root.add_child(tel_title)

	_telemetry_box = VBoxContainer.new()
	_telemetry_box.add_theme_constant_override("separation", 3)
	root.add_child(_telemetry_box)

func _on_connect_pressed() -> void:
	if not has_node("/root/FlagsmithManager"):
		return
	var mgr = get_node("/root/FlagsmithManager")
	var k := _key_input.text.strip_edges()
	if k == mgr.environment_key and not k.is_empty():
		mgr.sync_flags()
	else:
		mgr.set_environment_key(k)

func _render(snap: Dictionary) -> void:
	if _status_pill == null:
		return
	var m := str(snap.get("mode", "fallback"))
	if m == "live":
		_status_pill.text = "● LIVE CLOUD"
		_status_pill.add_theme_color_override("font_color", COL_GREEN)
	elif m == "connecting":
		_status_pill.text = "● SYNCING"
		_status_pill.add_theme_color_override("font_color", COL_CYAN)
	else:
		_status_pill.text = "● LOCAL FALLBACK"
		_status_pill.add_theme_color_override("font_color", COL_GOLD)

	_connect_btn.text = "Refresh" if bool(snap.get("has_key", false)) else "Connect"
	if _key_input.text.is_empty() and not str(snap.get("environment_key", "")).is_empty():
		_key_input.text = str(snap["environment_key"])

	var err_msg := str(snap.get("last_error", ""))
	_error_label.visible = not err_msg.is_empty()
	_error_label.text = err_msg

	var tr: Dictionary = snap.get("traits", {})
	_meta_label.text = "%s  ·  %s  ·  %d flags" % [
		str(snap.get("identity", "")),
		str(tr.get("mode", "arena_clash")).to_upper(),
		int(tr.get("flags_delivered", 0)),
	]

	for c in _flags_box.get_children():
		c.queue_free()

	var mgr = get_node("/root/FlagsmithManager")
	var flags_dict: Dictionary = snap.get("flags", {})
	var is_live: bool = (m == "live")

	for exp_name in mgr.EXPERIMENT_DEFINITIONS.keys():
		var def: Dictionary = mgr.EXPERIMENT_DEFINITIONS[exp_name]
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = str(def["label"])
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", COL_TEXT)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var opt := OptionButton.new()
		opt.disabled = is_live
		opt.add_theme_font_size_override("font_size", 12)
		opt.add_theme_color_override("font_color", COL_CYAN)
		opt.add_theme_stylebox_override("normal", _make_box(COL_CARD, COL_BORDER, 6, 8, 3))
		var current := str(flags_dict.get(exp_name, {}).get("value", def["default"]))
		var variants: Array = def["variants"]
		for i in range(variants.size()):
			opt.add_item(str(variants[i]), i)
			if str(variants[i]) == current:
				opt.select(i)
		opt.item_selected.connect(func(idx: int):
			mgr.set_local_override(exp_name, true, str(variants[idx]))
		)
		row.add_child(opt)
		_flags_box.add_child(row)

	for flag_name in mgr.BOOLEAN_FLAG_DEFAULTS.keys():
		var def: Dictionary = mgr.BOOLEAN_FLAG_DEFAULTS[flag_name]
		var chk := CheckButton.new()
		chk.text = str(def["label"])
		chk.add_theme_font_size_override("font_size", 12)
		chk.add_theme_color_override("font_color", COL_MUTED)
		chk.button_pressed = bool(flags_dict.get(flag_name, {}).get("enabled", def["enabled"]))
		chk.disabled = is_live
		chk.toggled.connect(func(pressed: bool):
			mgr.set_local_override(flag_name, pressed, null)
		)
		_flags_box.add_child(chk)

	for c in _telemetry_box.get_children():
		c.queue_free()

	var tel: Array = snap.get("telemetry", [])
	if tel.is_empty():
		var empty := Label.new()
		empty.text = "No runs recorded yet."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", COL_MUTED)
		_telemetry_box.add_child(empty)
	else:
		for t in tel.slice(0, 4):
			var total := int(t.get("wins", 0)) + int(t.get("losses", 0))
			var wr := ("%d%%" % int(round(float(t.get("wins", 0)) * 100.0 / float(total)))) if total > 0 else "—"
			var row := HBoxContainer.new()
			var name_lbl := Label.new()
			name_lbl.text = str(t.get("variant", ""))
			name_lbl.add_theme_font_size_override("font_size", 11)
			name_lbl.add_theme_color_override("font_color", COL_TEXT)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)

			var stats_lbl := Label.new()
			stats_lbl.text = "%d runs · %d flags · %s" % [int(t.get("starts", 0)), int(t.get("deliveries", 0)), wr]
			stats_lbl.add_theme_font_size_override("font_size", 11)
			stats_lbl.add_theme_color_override("font_color", COL_GREEN)
			row.add_child(stats_lbl)
			_telemetry_box.add_child(row)
