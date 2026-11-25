extends Control
## Fullscreen drag-and-drop editor for the touch HUD. Works with mouse and touch.
## A preview MobileControls draws every control at its live position; dragging a
## control moves it, the toolbar picks presets / scale and saves or cancels.

signal layout_saved(layout: Dictionary, preset: String)
signal closed()

const PRESET_BUTTONS := [["2F", "2-FINGER"], ["4F", "4-FINGER"], ["5F", "5-FINGER"], ["6F", "6-FINGER"]]
const GRID_STEP := 0.05
const POINTER_MOUSE := -2

var preview: MobileControls
var selected := "fire"
var _drag_pointer := -1
var _grab_offset := Vector2.ZERO
var _original: Dictionary
var _original_preset := ""
var _panel: PanelContainer
var _preset_buttons := {}
var _scale_slider: HSlider
var _scale_label: Label
var _name_label: Label
var _status_label: Label
var _tool_pointer := -1
var _pulse := 0.0


## `layout` / `preset` are the currently saved values (CANCEL restores them).
func _init(layout: Dictionary = {}, preset := "") -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	preview = MobileControls.new()
	_original = layout.duplicate(true)
	_original_preset = preset


func _ready() -> void:
	add_child(preview)
	preview.set_preview(true)
	if not _original.is_empty():
		preview.set_layout(_original, _original_preset)
	_build_toolbar()
	_sync_toolbar()
	resized.connect(_place_toolbar)
	_place_toolbar.call_deferred()


func _process(dt: float) -> void:
	_pulse += dt
	queue_redraw()


# ---------------------------------------------------------------- toolbar
func _build_toolbar() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.style(Color(0.06, 0.05, 0.14, 0.94), Color(UI.CYAN, 0.7), 12, 10, 2))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var v := UI.vbox(6)
	_panel.add_child(v)
	var touch := UI.is_touch_platform()
	var bh := 48.0 if touch else 38.0

	# Row 1: drag grip + presets.
	var r1 := UI.hbox(6)
	v.add_child(r1)
	var grip := UI.label("⠿ HUD LAYOUT", 14, UI.CYAN)
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_DRAG
	grip.tooltip_text = "Drag to move this toolbar"
	grip.gui_input.connect(_on_grip_input)
	grip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(grip)
	for pb in PRESET_BUTTONS:
		var b := UI.button(pb[0], _on_preset.bind(pb[1]), false, 56.0, bh)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = pb[1]
		r1.add_child(b)
		_preset_buttons[pb[1]] = b

	# Row 2: selected control + scale.
	var r2 := UI.hbox(8)
	v.add_child(r2)
	_name_label = UI.label("FIRE", 14, UI.GOLD)
	_name_label.custom_minimum_size = Vector2(70, 0)
	r2.add_child(_name_label)
	_scale_slider = HSlider.new()
	_scale_slider.min_value = MobileControls.MIN_SCALE
	_scale_slider.max_value = MobileControls.MAX_SCALE
	_scale_slider.step = 0.05
	_scale_slider.custom_minimum_size = Vector2(170, bh * 0.6)
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scale_slider.value_changed.connect(_on_scale)
	r2.add_child(_scale_slider)
	_scale_label = UI.label("1.0×", 14, UI.TEXT)
	_scale_label.custom_minimum_size = Vector2(46, 0)
	r2.add_child(_scale_label)

	# Row 3: actions.
	var r3 := UI.hbox(6)
	v.add_child(r3)
	_status_label = UI.label("", 12, UI.MUTED)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r3.add_child(_status_label)
	var reset := UI.button("RESET", _on_reset, false, 84.0, bh)
	var cancel := UI.button("CANCEL", _on_cancel, false, 92.0, bh)
	var save := UI.button("SAVE", _on_save, true, 92.0, bh)
	for b in [reset, cancel, save]:
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		r3.add_child(b)


func _place_toolbar() -> void:
	if _panel == null:
		return
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.size.x) * 0.5, maxf(8.0, UI.safe_insets(get_viewport() if is_inside_tree() else null).y + 6.0))
	_clamp_toolbar()


func _clamp_toolbar() -> void:
	_panel.position = Vector2(
		clampf(_panel.position.x, 0.0, maxf(0.0, size.x - _panel.size.x)),
		clampf(_panel.position.y, 0.0, maxf(0.0, size.y - _panel.size.y)))


func _on_grip_input(e: InputEvent) -> void:
	if e is InputEventScreenDrag:
		_panel.position += e.relative
		_clamp_toolbar()
	elif e is InputEventMouseMotion and not e.is_emulated_from_touch() and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_panel.position += e.relative
		_clamp_toolbar()


func _sync_toolbar() -> void:
	for k in _preset_buttons:
		var b: Button = _preset_buttons[k]
		var on: bool = k == preview.current_preset
		var accent := UI.CYAN
		b.add_theme_stylebox_override("normal", UI.style(Color(accent, 0.92) if on else Color(accent, 0.10), accent if on else Color(accent, 0.4), 8, 8, 2))
		b.add_theme_stylebox_override("hover", UI.style(Color(accent, 0.95 if on else 0.3), accent, 8, 8, 2))
		b.add_theme_color_override("font_color", Color("#10101c") if on else accent)
		b.add_theme_color_override("font_hover_color", Color("#10101c") if on else Color.WHITE)
	_name_label.text = MobileControls.CONTROL_DEFS[selected]["label"]
	_scale_slider.set_value_no_signal(preview.control_scale(selected))
	_scale_label.text = "%.2f×" % preview.control_scale(selected)
	_status_label.text = "LAYOUT: " + preview.current_preset


func _on_preset(preset: String) -> void:
	preview.apply_preset(preset)
	_sync_toolbar()


func _on_scale(v: float) -> void:
	preview.set_control_scale(selected, v)
	_sync_toolbar()


func _on_reset() -> void:
	preview.reset_layout()
	_sync_toolbar()


func _on_cancel() -> void:
	closed.emit()
	queue_free()


func _on_save() -> void:
	layout_saved.emit(preview.get_layout(), preview.current_preset)
	closed.emit()
	queue_free()


# ---------------------------------------------------------------- dragging
func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_press(e.index, e.position, e.pressed)
	elif e is InputEventScreenDrag:
		_move(e.index, e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.is_emulated_from_touch():
		_press(POINTER_MOUSE, e.position, e.pressed)
	elif e is InputEventMouseMotion and not e.is_emulated_from_touch() and _drag_pointer == POINTER_MOUSE:
		_move(POINTER_MOUSE, e.position)
	accept_event()


func _press(p: int, pos: Vector2, down: bool) -> void:
	if down:
		if _drag_pointer != -1:
			return
		var hit := preview.control_at(pos, true, 1.15)
		if hit == "":
			return
		selected = hit
		_drag_pointer = p
		_grab_offset = preview.control_center(hit) - pos
		_sync_toolbar()
	elif p == _drag_pointer:
		_drag_pointer = -1


func _move(p: int, pos: Vector2) -> void:
	if p != _drag_pointer or size.x <= 0.0 or size.y <= 0.0:
		return
	var c := pos + _grab_offset
	preview.set_control_norm(selected, Vector2(c.x / size.x, c.y / size.y))
	_sync_toolbar()


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.08, 0.93))
	# Subtle grid, brighter on the centre lines.
	var gx := GRID_STEP
	while gx < 1.0:
		var major := is_equal_approx(gx, 0.5)
		draw_line(Vector2(size.x * gx, 0), Vector2(size.x * gx, size.y), Color(UI.CYAN, 0.16 if major else 0.05), 1.0)
		gx += GRID_STEP
	var gy := GRID_STEP
	while gy < 1.0:
		var majory := is_equal_approx(gy, 0.5)
		draw_line(Vector2(0, size.y * gy), Vector2(size.x, size.y * gy), Color(UI.CYAN, 0.16 if majory else 0.05), 1.0)
		gy += GRID_STEP
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.CYAN, 0.25), false, 2.0)
	if preview == null:
		return
	var font := ThemeDB.fallback_font
	# Captions under every control (drawn here; preview draws the icons on top of this layer).
	for id in MobileControls.CONTROL_IDS:
		var c := preview.control_center(id)
		var r := preview.control_radius(id)
		var text: String = MobileControls.CONTROL_DEFS[id]["label"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, c + Vector2(-w * 0.5, r + 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UI.TEXT, 0.7))
	# Glowing selection ring.
	if preview.control_scale(selected) > 0.0:
		var sc := preview.control_center(selected)
		var sr := preview.control_radius(selected)
		var glow := 0.5 + 0.5 * sin(_pulse * 4.0)
		draw_arc(sc, sr + 14.0, 0, TAU, 64, Color(UI.GOLD, 0.12 + 0.12 * glow), 12.0, true)
		draw_arc(sc, sr + 9.0, 0, TAU, 64, Color(UI.GOLD, 0.55 + 0.4 * glow), 3.0, true)
	draw_string(font, Vector2(16, size.y - 14), "Drag any button to place it · tap to select · slider resizes the selected button",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UI.MUTED, 0.9))
