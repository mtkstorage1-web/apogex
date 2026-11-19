extends CanvasLayer
class_name CombatHUD
## Procedural combat feedback overlay: tactical crosshair with bloom, X-hitmarker,
## screen-edge damage vignette and a top-center event banner. Never blocks input.

const HIT_TIME := 0.16
const DAMAGE_TIME := 0.28
const BANNER_TIME := 2.6
const BANNER_TOP := 134.0  # below the top phase bar and the compass ribbon
const COMPASS_W := 360.0
const COMPASS_H := 26.0
const COMPASS_Y := 96.0
const COMPASS_HALF_FOV := 90.0  # degrees visible each side of center
const SHIELD_COL := Color("#5fe3ff")
const HULL_COL := Color("#ff3b4e")

var canvas: Control
var crosshair_visible := false
var bloom := 0.0          # extra gap in px, recovers toward 0
var hit_t := 0.0
var hit_col := Color.WHITE
var dmg_t := 0.0
var dmg_col := HULL_COL
var banner_t := 0.0
var banner_title := ""
var banner_sub := ""
var banner_accent := Color("#ffd29a")
var _font: Font

const POPUP_MAX := 24
const POPUP_LIFE := 0.75
const LETHAL_COL := Color("#ffd866")
const FEED_MAX := 4
const FEED_LIFE := 4.5
var _popups: Array = []   # {pos, text, age, vx, vy, col, lethal}
var _feed: Array = []     # {text, accent, age}
const THREAT_MAX := 6
const THREAT_LIFE := 0.85
const THREAT_RADIUS := 92.0
var _threats: Array = []  # {pos, shield, age}
var reload_ratio := 0.0
var low_ammo := false
var _compass_markers: Array = []  # {pos, color, label, priority}


func _ready() -> void:
	layer = 6
	canvas = Control.new()
	canvas.name = "CombatCanvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_overlay)
	add_child(canvas)
	_font = ThemeDB.fallback_font
	add_to_group("combat_hud")


func spawn_damage_number(world_pos: Vector3, amount: float, is_lethal: bool = false, accent: Color = Color.WHITE) -> void:
	if _popups.size() >= POPUP_MAX:
		_popups.pop_front()
	var txt := ("-%d KO!" if is_lethal else "-%d") % roundi(amount)
	_popups.append({"pos": world_pos, "text": txt, "age": 0.0,
		"vx": randf_range(-22.0, 22.0), "vy": randf_range(52.0, 70.0),
		"col": LETHAL_COL if is_lethal else accent, "lethal": is_lethal})
	canvas.queue_redraw()


func push_feed(text: String, accent: Color = Color("#ffb347")) -> void:
	_feed.push_front({"text": text, "accent": accent, "age": 0.0})
	if _feed.size() > FEED_MAX:
		_feed.resize(FEED_MAX)
	canvas.queue_redraw()


func set_crosshair_visible(v: bool) -> void:
	if v != crosshair_visible:
		crosshair_visible = v
		canvas.queue_redraw()


func trigger_bloom(amount := 9.0) -> void:
	bloom = minf(bloom + amount, 30.0)
	canvas.queue_redraw()


func trigger_hitmarker(is_kill_or_break: bool) -> void:
	hit_t = HIT_TIME
	hit_col = Color("#ffcf3f") if is_kill_or_break else Color.WHITE
	canvas.queue_redraw()


func trigger_damage(is_shield: bool) -> void:
	dmg_t = DAMAGE_TIME
	dmg_col = SHIELD_COL if is_shield else HULL_COL
	canvas.queue_redraw()


func trigger_damage_from(attacker_world_pos: Vector3, is_shield: bool = false) -> void:
	trigger_damage(is_shield)
	if _threats.size() >= THREAT_MAX:
		_threats.pop_front()
	_threats.append({"pos": attacker_world_pos, "shield": is_shield, "age": 0.0})
	canvas.queue_redraw()


func set_reload_progress(ratio: float) -> void:
	var r := clampf(ratio, 0.0, 1.0)
	if not is_equal_approx(r, reload_ratio):
		reload_ratio = r
		canvas.queue_redraw()


func set_low_ammo(is_low: bool) -> void:
	if is_low != low_ammo:
		low_ammo = is_low
		canvas.queue_redraw()


func set_compass_markers(markers: Array) -> void:
	var had := not _compass_markers.is_empty()
	_compass_markers = markers
	if had or not markers.is_empty():
		canvas.queue_redraw()


func announce(title: String, subtitle := "", accent := Color("#ffd29a")) -> void:
	banner_title = title
	banner_sub = subtitle
	banner_accent = accent
	banner_t = BANNER_TIME
	canvas.queue_redraw()


func _process(dt: float) -> void:
	var animating := bloom > 0.0 or hit_t > 0.0 or dmg_t > 0.0 or banner_t > 0.0 or not _popups.is_empty() or not _feed.is_empty() or not _threats.is_empty() or low_ammo
	if not animating:
		return
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i]["age"] += dt
		if _popups[i]["age"] >= POPUP_LIFE:
			_popups.remove_at(i)
	for i in range(_feed.size() - 1, -1, -1):
		_feed[i]["age"] += dt
		if _feed[i]["age"] >= FEED_LIFE:
			_feed.remove_at(i)
	for i in range(_threats.size() - 1, -1, -1):
		_threats[i]["age"] += dt
		if _threats[i]["age"] >= THREAT_LIFE:
			_threats.remove_at(i)
	bloom = maxf(0.0, bloom - dt * maxf(40.0, bloom * 12.0))
	hit_t = maxf(0.0, hit_t - dt)
	dmg_t = maxf(0.0, dmg_t - dt)
	banner_t = maxf(0.0, banner_t - dt)
	canvas.queue_redraw()


func _draw_overlay() -> void:
	var size := canvas.size
	var c := size * 0.5
	if dmg_t > 0.0:
		_draw_vignette(size, dmg_t / DAMAGE_TIME)
	if crosshair_visible:
		var gap := 6.0 + bloom
		var col := Color(1, 1, 1, 0.9)
		var shadow := Color(0, 0, 0, 0.45)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var a: Vector2 = c + d * gap
			var b: Vector2 = c + d * (gap + 9.0)
			canvas.draw_line(a, b, shadow, 4.0)
			canvas.draw_line(a, b, col, 2.0)
		canvas.draw_circle(c, 1.5, col)
	if not _threats.is_empty():
		_draw_threats(c)
	if crosshair_visible:
		_draw_reload_and_ammo(c)
	if hit_t > 0.0:
		var k := hit_t / HIT_TIME
		var hc := Color(hit_col, k)
		var r0 := 7.0 + (1.0 - k) * 3.0
		var r1 := r0 + 8.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			canvas.draw_line(c + n * r0, c + n * r1, hc, 2.5)
	if not _compass_markers.is_empty():
		_draw_compass(size)
	if banner_t > 0.0:
		_draw_banner(size)
	if not _popups.is_empty():
		_draw_popups()
	if not _feed.is_empty():
		_draw_feed(size)


func _draw_popups() -> void:
	if not _font or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for p in _popups:
		var wp: Vector3 = p["pos"]
		if cam.is_position_behind(wp):
			continue
		var age: float = p["age"]
		var k := age / POPUP_LIFE
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		var sp := cam.unproject_position(wp) + Vector2(p["vx"] * ease_k, -p["vy"] * ease_k - 18.0)
		var pop := 1.0 + 0.45 * maxf(0.0, 1.0 - age / 0.12)
		var a := clampf((1.0 - k) / 0.4, 0.0, 1.0)
		var fs := roundi((24.0 if p["lethal"] else 18.0) * pop)
		var txt: String = p["text"]
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := sp - Vector2(w * 0.5, 0.0)
		canvas.draw_string_outline(_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.02, 0.03, 0.06, 0.85 * a))
		canvas.draw_string(_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(p["col"], a))


func _draw_feed(size: Vector2) -> void:
	if not _font:
		return
	# Right side, below the minimap/score panel; scales with viewport height.
	var w := 300.0
	var h := 26.0
	var x := size.x - w - 18.0
	var y := clampf(size.y * 0.40, 250.0, size.y - 4.0 * (h + 6.0) - 140.0)
	var slant := 10.0
	for e in _feed:
		var age: float = e["age"]
		var a := clampf(minf(age / 0.18, (FEED_LIFE - age) / 0.5), 0.0, 1.0)
		var off := (1.0 - clampf(age / 0.18, 0.0, 1.0)) * 30.0
		var x0 := x + off
		var acc: Color = e["accent"]
		var pill := PackedVector2Array([Vector2(x0 + slant, y), Vector2(x0 + w, y), Vector2(x0 + w - slant, y + h), Vector2(x0, y + h)])
		canvas.draw_colored_polygon(pill, Color(0.03, 0.05, 0.09, 0.72 * a))
		var strip := PackedVector2Array([Vector2(x0 + slant, y), Vector2(x0 + slant + 4.0, y), Vector2(x0 + 4.0, y + h), Vector2(x0, y + h)])
		canvas.draw_colored_polygon(strip, Color(acc, a))
		canvas.draw_line(Vector2(x0 + 6.0, y + h * 0.5), Vector2(x0 + 18.0, y + h * 0.5), Color(acc, 0.25 * a), 6.0)
		canvas.draw_string(_font, Vector2(x0 + 18.0, y + 18.0), e["text"], HORIZONTAL_ALIGNMENT_LEFT, w - 30.0, 14, Color(1, 1, 1, 0.95 * a))
		y += h + 6.0


func _draw_vignette(size: Vector2, k: float) -> void:
	# Four gradient edge strips: opaque at the screen edge, clear toward the center.
	var edge := Color(dmg_col, 0.55 * k)
	var clear := Color(dmg_col, 0.0)
	var w := size.x * 0.16
	var h := size.y * 0.18
	var rects := [
		[Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x - w, h), Vector2(w, h)],
		[Vector2(0, size.y), Vector2(size.x, size.y), Vector2(size.x - w, size.y - h), Vector2(w, size.y - h)],
		[Vector2(0, 0), Vector2(0, size.y), Vector2(w, size.y - h), Vector2(w, h)],
		[Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - w, size.y - h), Vector2(size.x - w, h)],
	]
	for q in rects:
		canvas.draw_polygon(PackedVector2Array(q), PackedColorArray([edge, edge, clear, clear]))


func _draw_banner(size: Vector2) -> void:
	var life := BANNER_TIME - banner_t
	var a := clampf(minf(life / 0.22, banner_t / 0.35), 0.0, 1.0)
	var slide := (1.0 - clampf(life / 0.22, 0.0, 1.0)) * -24.0
	var bw := 440.0
	var bh := 58.0 if banner_sub != "" else 42.0
	var x := (size.x - bw) * 0.5
	var y := BANNER_TOP + slide
	var slant := 18.0
	var glass := PackedVector2Array([Vector2(x + slant, y), Vector2(x + bw, y), Vector2(x + bw - slant, y + bh), Vector2(x, y + bh)])
	canvas.draw_colored_polygon(glass, Color(0.03, 0.05, 0.09, 0.78 * a))
	var bar := PackedVector2Array([Vector2(x + slant, y), Vector2(x + bw, y), Vector2(x + bw - 1.0, y + 3.0), Vector2(x + slant - 1.0, y + 3.0)])
	canvas.draw_colored_polygon(bar, Color(banner_accent, a))
	canvas.draw_line(Vector2(x + 8, y + bh + 2), Vector2(x + bw - slant - 8, y + bh + 2), Color(banner_accent, 0.35 * a), 2.0)
	if _font:
		canvas.draw_string(_font, Vector2(x, y + 28), banner_title, HORIZONTAL_ALIGNMENT_CENTER, bw, 22, Color(1, 1, 1, a))
		if banner_sub != "":
			canvas.draw_string(_font, Vector2(x, y + 48), banner_sub, HORIZONTAL_ALIGNMENT_CENTER, bw, 14, Color(banner_accent, 0.9 * a))


func _draw_threats(c: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	fwd.y = 0.0
	right.y = 0.0
	if fwd.length() < 0.001 or right.length() < 0.001:
		return
	fwd = fwd.normalized()
	right = right.normalized()
	for t in _threats:
		var to: Vector3 = t["pos"] - cam.global_position
		to.y = 0.0
		if to.length() < 0.01:
			continue
		to = to.normalized()
		var ang := atan2(to.dot(right), to.dot(fwd))  # 0 = ahead, + = right
		var k: float = 1.0 - float(t["age"]) / THREAT_LIFE
		var base: Color = SHIELD_COL if t["shield"] else Color("#ff2640")
		var dir := Vector2(sin(ang), -cos(ang))
		var perp := Vector2(-dir.y, dir.x)
		var tip := c + dir * (THREAT_RADIUS + 10.0)
		var back := c + dir * (THREAT_RADIUS - 8.0)
		var pts := PackedVector2Array([tip, back + perp * 11.0, back - perp * 11.0])
		canvas.draw_colored_polygon(pts, Color(base, 0.35 * k))
		canvas.draw_arc(c, THREAT_RADIUS, ang - PI / 2.0 - 0.4, ang - PI / 2.0 + 0.4, 20, Color(base, 0.9 * k), 5.0, true)
		canvas.draw_polyline(PackedVector2Array([back + perp * 11.0, tip, back - perp * 11.0]), Color(1, 1, 1, 0.8 * k), 2.0, true)


func _draw_reload_and_ammo(c: Vector2) -> void:
	if reload_ratio > 0.0:
		var rr := 24.0
		canvas.draw_arc(c, rr, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 4.0, true)
		canvas.draw_arc(c, rr, -PI / 2.0, -PI / 2.0 + TAU * reload_ratio, 40, Color("#ffd29a"), 2.5, true)
		var txt := "RELOADING"
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		canvas.draw_string(_font, Vector2(c.x - w * 0.5, c.y + rr + 16.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffd29a"))
	elif low_ammo:
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.012)
		var txt := "LOW AMMO"
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var rect := Rect2(c.x - w * 0.5 - 8.0, c.y + 28.0, w + 16.0, 16.0)
		var amber := Color("#ffb020")
		canvas.draw_rect(rect, Color(0.1, 0.06, 0.0, 0.55 * pulse), true)
		canvas.draw_rect(rect, Color(amber, 0.8 * pulse), false, 1.0)
		canvas.draw_string(_font, Vector2(rect.position.x + 8.0, rect.position.y + 12.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(amber, pulse))


func _bearing_deg(v: Vector3) -> float:
	# Compass bearing, N = -Z, E = +X, clockwise.
	return rad_to_deg(atan2(v.x, -v.z))


func _draw_compass(size: Vector2) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _compass_markers.is_empty():
		return
	var fwd := -cam.global_transform.basis.z
	var cam_b := _bearing_deg(fwd)
	var px := COMPASS_W / (COMPASS_HALF_FOV * 2.0)  # px per degree
	var x0 := (size.x - COMPASS_W) * 0.5
	var y0 := COMPASS_Y
	var cx := x0 + COMPASS_W * 0.5
	var my := y0 + COMPASS_H * 0.5
	var glass := PackedVector2Array([Vector2(x0 + 8, y0), Vector2(x0 + COMPASS_W - 8, y0), Vector2(x0 + COMPASS_W, y0 + COMPASS_H), Vector2(x0, y0 + COMPASS_H)])
	canvas.draw_colored_polygon(glass, Color(0.03, 0.05, 0.09, 0.62))
	canvas.draw_line(Vector2(x0 + 4, y0 + COMPASS_H), Vector2(x0 + COMPASS_W - 4, y0 + COMPASS_H), Color(1, 1, 1, 0.12), 1.0)
	# Ticks every 15 degrees; labelled cardinals / intercardinals every 45.
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var first := int(floor((cam_b - COMPASS_HALF_FOV) / 15.0)) * 15
	var deg := first
	while deg <= cam_b + COMPASS_HALF_FOV + 15:
		var x := cx + (float(deg) - cam_b) * px
		if x >= x0 + 6 and x <= x0 + COMPASS_W - 6:
			var wrapped := posmod(deg, 360)
			var edge_a := clampf(minf(x - x0, x0 + COMPASS_W - x) / 40.0, 0.0, 1.0)
			if wrapped % 45 == 0:
				var nm: String = names[wrapped / 45]
				var cardinal := wrapped % 90 == 0
				canvas.draw_line(Vector2(x, y0 + COMPASS_H - 6), Vector2(x, y0 + COMPASS_H - 1), Color(1, 1, 1, 0.7 * edge_a), 1.5)
				if _font:
					var fs := 14 if cardinal else 11
					var w := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					var col := Color("#ffd29a") if nm == "N" else Color(1, 1, 1, (0.95 if cardinal else 0.65) * edge_a)
					canvas.draw_string(_font, Vector2(x - w * 0.5, y0 + 15), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			else:
				canvas.draw_line(Vector2(x, y0 + COMPASS_H - 4), Vector2(x, y0 + COMPASS_H - 1), Color(1, 1, 1, 0.3 * edge_a), 1.0)
		deg += 15
	# Markers.
	var cam_pos := cam.global_position
	var nearest := -1
	var nearest_d := INF
	var best_pri := false
	for i in _compass_markers.size():
		var m: Dictionary = _compass_markers[i]
		var d: float = Vector2(m["pos"].x - cam_pos.x, m["pos"].z - cam_pos.z).length()
		var pri: bool = m.get("priority", false)
		if (pri and not best_pri) or (pri == best_pri and d < nearest_d):
			nearest = i
			nearest_d = d
			best_pri = pri
	for i in _compass_markers.size():
		var m: Dictionary = _compass_markers[i]
		var to: Vector3 = m["pos"] - cam_pos
		var rel := wrapf(_bearing_deg(to) - cam_b, -180.0, 180.0)
		var clamped := absf(rel) > COMPASS_HALF_FOV - 6.0
		var mx := cx + clampf(rel, -(COMPASS_HALF_FOV - 6.0), COMPASS_HALF_FOV - 6.0) * px
		var mc: Color = m["color"]
		var big: bool = m.get("priority", false)
		var r := 6.5 if big else 5.0
		var a := 0.6 if clamped else 1.0
		var dia := PackedVector2Array([Vector2(mx, my - r), Vector2(mx + r, my), Vector2(mx, my + r), Vector2(mx - r, my)])
		canvas.draw_circle(Vector2(mx, my), r + 4.0, Color(mc, 0.22 * a))
		canvas.draw_colored_polygon(dia, Color(mc, a))
		canvas.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color(0.02, 0.03, 0.06, 0.8 * a), 1.2)
		if i == nearest and _font:
			var txt := "%dm" % roundi(nearest_d)
			var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var tx := clampf(mx - w * 0.5, x0, x0 + COMPASS_W - w)
			canvas.draw_string_outline(_font, Vector2(tx, y0 + COMPASS_H + 12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0.02, 0.03, 0.06, 0.85))
			canvas.draw_string(_font, Vector2(tx, y0 + COMPASS_H + 12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(mc, 1.0))
	# Center amber pointer notch.
	var amber := Color("#ffb347")
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, y0 - 3), Vector2(cx + 5, y0 - 3), Vector2(cx, y0 + 5)]), amber)
	canvas.draw_line(Vector2(cx, y0 + 5), Vector2(cx, y0 + COMPASS_H), Color(amber, 0.55), 1.5)
