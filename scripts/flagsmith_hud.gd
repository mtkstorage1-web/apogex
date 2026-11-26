extends CanvasLayer

# Toggleable Flagsmith Experiment Inspector (F9 or corner ⚑ FLAGS button)

var _panel: PanelContainer
var _status_label: Label
var _key_input: LineEdit
var _connect_btn: Button
var _meta_label: Label
var _flags_box: VBoxContainer
var _telemetry_label: RichTextLabel
var _error_label: Label

func _ready() -> void:
	layer = 100
	_build_ui()
	if has_node("/root/FlagsmithManager"):
		var mgr = get_node("/root/FlagsmithManager")
		mgr.flags_updated.connect(_render)
		_render(mgr.get_snapshot())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var toggle_btn := Button.new()
	toggle_btn.text = "⚑ FLAGS (F9)"
	toggle_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	toggle_btn.offset_left = 18
	toggle_btn.offset_right = 154
	toggle_btn.offset_top = -52
	toggle_btn.offset_bottom = -18
	toggle_btn.pressed.connect(func(): _panel.visible = not _panel.visible)
	add_child(toggle_btn)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.position = Vector2(18, 96)
	_panel.custom_minimum_size = Vector2(420, 460)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "TOGGLE WARS · FLAGSMITH INSPECTOR"
	root.add_child(title)

	_status_label = Label.new()
	root.add_child(_status_label)

	var key_row := HBoxContainer.new()
	root.add_child(key_row)

	_key_input = LineEdit.new()
	_key_input.placeholder_text = "Paste Flagsmith Client Environment Key..."
	_key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_row.add_child(_key_input)

	_connect_btn = Button.new()
	_connect_btn.text = "Connect"
	_connect_btn.pressed.connect(_on_connect_pressed)
	key_row.add_child(_connect_btn)

	_error_label = Label.new()
	_error_label.modulate = Color(1.0, 0.45, 0.5)
	_error_label.visible = false
	root.add_child(_error_label)

	_meta_label = Label.new()
	root.add_child(_meta_label)

	_flags_box = VBoxContainer.new()
	_flags_box.add_theme_constant_override("separation", 6)
	root.add_child(_flags_box)

	var tel_header := Label.new()
	tel_header.text = "LIVE A/B CONVERSION TELEMETRY"
	root.add_child(tel_header)

	_telemetry_label = RichTextLabel.new()
	_telemetry_label.custom_minimum_size = Vector2(380, 110)
	_telemetry_label.fit_content = false
	root.add_child(_telemetry_label)

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
	if _status_label == null:
		return
	var m := str(snap.get("mode", "fallback"))
	_status_label.text = "Status: " + ("LIVE FLAGSMITH CLOUD" if m == "live" else ("SYNCING..." if m == "connecting" else "LOCAL FALLBACK MODE"))
	_connect_btn.text = "Refresh" if bool(snap.get("has_key", false)) else "Connect"
	if _key_input.text.is_empty() and not str(snap.get("environment_key", "")).is_empty():
		_key_input.text = str(snap["environment_key"])

	var err_msg := str(snap.get("last_error", ""))
	_error_label.visible = not err_msg.is_empty()
	_error_label.text = err_msg

	var tr: Dictionary = snap.get("traits", {})
	_meta_label.text = "ID: %s | Mode: %s | Delivered: %s" % [
		str(snap.get("identity", "")),
		str(tr.get("mode", "arena_clash")),
		str(tr.get("flags_delivered", 0)),
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
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var opt := OptionButton.new()
		opt.disabled = is_live
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
		chk.button_pressed = bool(flags_dict.get(flag_name, {}).get("enabled", def["enabled"]))
		chk.disabled = is_live
		chk.toggled.connect(func(pressed: bool):
			mgr.set_local_override(flag_name, pressed, null)
		)
		_flags_box.add_child(chk)

	var tel: Array = snap.get("telemetry", [])
	if tel.is_empty():
		_telemetry_label.text = "Play a match or deliver Science Flags to record A/B conversions."
	else:
		var lines: PackedStringArray = []
		for t in tel:
			var total := int(t.get("wins", 0)) + int(t.get("losses", 0))
			var wr := ("%d%%" % int(round(float(t.get("wins", 0)) * 100.0 / float(total)))) if total > 0 else "—"
			lines.append("%s | runs:%d | flags:%d | win:%s" % [
				str(t.get("variant", "")),
				int(t.get("starts", 0)),
				int(t.get("deliveries", 0)),
				wr,
			])
		_telemetry_label.text = "\n".join(lines)
