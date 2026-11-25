class_name LoadingScreen
extends Control
## Fortnite-style fullscreen loading screen. ZERO buttons; driven only by set_progress().

const TIPS := [
	"TIP  Confirm all 12 rocket parts at the white Parts Shop (E), then start assembly at the Desk.",
	"TIP  Boosting early out of the atmosphere beats slow cruising. Watch rival launches!",
	"TIP  Left Alt Dash dodges Scattergun fire better than backpedaling.",
	"TIP  Delivering 2-3 flags early is safer than hoarding 6 and risking an ambush.",
	"TIP  Press B to draw your weapon and escort Fernando [4] to extract Science Flags.",
]

var _pct := 0.0
var _shown_pct := 0.0
var _time := 0.0
var _status := "Initializing..."
var _tip_idx := 0
var _bar_fill: ColorRect
var _bar_glow: ColorRect
var _bar_head: ColorRect
var _pct_label: Label
var _status_label: Label
var _tip_label: Label
var _stars: Array = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4000
	process_mode = Node.PROCESS_MODE_ALWAYS


func _lbl(text: String, fsize: int, col: Color) -> Label:
	var l := UI.label(text, fsize, col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 140:
		_stars.append({"p": Vector2(rng.randf(), rng.randf()), "s": rng.randf_range(0.5, 2.6), "ph": rng.randf() * TAU,
			"c": [Color("#a78bfa"), Color("#22d3ee"), Color("#f472b6"), Color("#ffffff")][rng.randi() % 4]})

	# Title badge (top-left, Fortnite style)
	var t1 := _lbl("T-MINUS", 64, Color("#ffffff"))
	t1.add_theme_color_override("font_outline_color", Color("#7c3aed"))
	t1.add_theme_constant_override("outline_size", 10)
	t1.position = Vector2(80, 56)
	var t2 := _lbl("SPACE RACE", 20, Color("#22d3ee"))
	t2.position = Vector2(86, 138)

	# Bottom-left tip + status
	_tip_label = _lbl(TIPS[0], 18, Color("#fde68a"))
	_tip_label.anchor_top = 1.0
	_tip_label.anchor_bottom = 1.0
	_tip_label.anchor_right = 1.0
	_tip_label.offset_left = 80
	_tip_label.offset_right = -80
	_tip_label.offset_top = -150
	_tip_label.offset_bottom = -116
	_status_label = _lbl("", 14, Color("#c4b5fd"))
	_status_label.anchor_top = 1.0
	_status_label.anchor_bottom = 1.0
	_status_label.offset_left = 80
	_status_label.offset_right = 600
	_status_label.offset_top = -76
	_status_label.offset_bottom = -52
	_pct_label = _lbl("0%", 28, Color("#facc15"))
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct_label.anchor_left = 1.0
	_pct_label.anchor_right = 1.0
	_pct_label.anchor_top = 1.0
	_pct_label.anchor_bottom = 1.0
	_pct_label.offset_left = -240
	_pct_label.offset_right = -80
	_pct_label.offset_top = -84
	_pct_label.offset_bottom = -46

	# Full-width sleek bar pinned to the bottom edge
	var track := ColorRect.new()
	track.name = "Track"
	track.color = Color(0.1, 0.07, 0.22, 0.95)
	track.anchor_top = 1.0
	track.anchor_bottom = 1.0
	track.anchor_right = 1.0
	track.offset_top = -14
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(track)
	_bar_glow = ColorRect.new()
	_bar_glow.color = Color(0.9, 0.3, 0.9, 0.3)
	_bar_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_bar_glow)
	_bar_fill = ColorRect.new()
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_bar_fill)
	_bar_head = ColorRect.new()
	_bar_head.color = Color(1, 1, 1, 0.95)
	_bar_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_bar_head)

	resized.connect(queue_redraw)
	track.resized.connect(_update_bar)
	if UI.reduced_motion:
		_shown_pct = _pct
	else:
		var tip_timer := Timer.new()
		tip_timer.wait_time = 2.5
		tip_timer.autostart = true
		tip_timer.timeout.connect(func() -> void:
			_tip_idx = (_tip_idx + 1) % TIPS.size()
			_tip_label.text = TIPS[_tip_idx])
		add_child(tip_timer)
	_refresh()
	set_process(not UI.reduced_motion)


func set_progress(pct: float, status: String = "") -> void:
	_pct = clampf(pct, 0.0, 100.0)
	if status != "":
		_status = status
	if UI.reduced_motion:
		_shown_pct = _pct
	_refresh()


func get_progress() -> float:
	return _pct


func _refresh() -> void:
	if _pct_label == null:
		return
	_pct_label.text = "%d%%" % int(round(_shown_pct))
	_status_label.text = _status
	_update_bar()


func _update_bar() -> void:
	var track := _bar_fill.get_parent() as Control
	var f := clampf(_shown_pct, 0.0, 100.0) / 100.0
	var w := track.size.x * f
	var h := track.size.y
	_bar_fill.position = Vector2.ZERO
	_bar_fill.size = Vector2(w, h)
	_bar_glow.position = Vector2(0, -10)
	_bar_glow.size = Vector2(w, h + 10)
	_bar_head.position = Vector2(maxf(w - 4.0, 0.0), -3)
	_bar_head.size = Vector2(4, h + 3)
	_bar_fill.color = Color("#6366f1").lerp(Color("#f472b6"), f)


func _process(delta: float) -> void:
	_time += delta
	_shown_pct = move_toward(_shown_pct, _pct, 120.0 * delta)
	_refresh()
	queue_redraw()


func _draw() -> void:
	var sz := size
	# Deep vertical gradient backdrop
	var top := Color("#05030f")
	var mid := Color("#150a3a")
	var bot := Color("#2a0f4d")
	var steps := 48
	for i in steps:
		var t := float(i) / float(steps - 1)
		var c := top.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(bot, (t - 0.5) * 2.0)
		draw_rect(Rect2(0, sz.y * float(i) / steps, sz.x, sz.y / steps + 1.0), c)
	for s in _stars:
		var a := 0.3 + 0.7 * (0.5 + 0.5 * sin(_time * 1.6 + float(s["ph"])))
		var sc: Color = s["c"]
		sc.a = a
		draw_circle(Vector2(float(s["p"].x) * sz.x, float(s["p"].y) * sz.y), float(s["s"]), sc)
	# Orbital rings with orbiting dots
	var ctr := Vector2(sz.x * 0.72, sz.y * 0.42)
	for k in 4:
		var r := sz.y * (0.18 + 0.11 * k)
		var col := Color(0.55, 0.4, 1.0, 0.35 - 0.05 * k)
		draw_arc(ctr, r, 0.0, TAU, 96, col, 2.0)
		var ang := _time * (0.4 + 0.15 * k) * (1.0 if k % 2 == 0 else -1.0) + k
		draw_circle(ctr + Vector2(cos(ang), sin(ang)) * r, 5.0, Color(0.13, 0.83, 0.93, 0.9))
	draw_circle(ctr, sz.y * 0.07, Color(0.65, 0.35, 1.0, 0.25))
	draw_circle(ctr, sz.y * 0.04, Color(0.95, 0.6, 1.0, 0.5))
	# Diagonal geometric accents
	for k in 6:
		var x := fmod(float(k) * sz.x * 0.22 + _time * 18.0, sz.x + 200.0) - 100.0
		draw_line(Vector2(x, sz.y), Vector2(x + 140.0, sz.y * 0.55), Color(0.13, 0.83, 0.93, 0.08), 2.0)
	# Bottom dark band behind tip/status
	draw_rect(Rect2(0, sz.y - 170.0, sz.x, 170.0), Color(0, 0, 0, 0.35))
