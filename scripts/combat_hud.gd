extends CanvasLayer
class_name CombatHUD
## Procedural combat feedback overlay: tactical crosshair with bloom, X-hitmarker,
## screen-edge damage vignette and a top-center event banner. Never blocks input.

const HIT_TIME := 0.16
const DAMAGE_TIME := 0.28
const BANNER_TIME := 2.6
const BANNER_TOP := 96.0   # sits below the HUD's top phase bar
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


func announce(title: String, subtitle := "", accent := Color("#ffd29a")) -> void:
	banner_title = title
	banner_sub = subtitle
	banner_accent = accent
	banner_t = BANNER_TIME
	canvas.queue_redraw()


func _process(dt: float) -> void:
	var animating := bloom > 0.0 or hit_t > 0.0 or dmg_t > 0.0 or banner_t > 0.0 or not _popups.is_empty() or not _feed.is_empty()
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
	if hit_t > 0.0:
		var k := hit_t / HIT_TIME
		var hc := Color(hit_col, k)
		var r0 := 7.0 + (1.0 - k) * 3.0
		var r1 := r0 + 8.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			canvas.draw_line(c + n * r0, c + n * r1, hc, 2.5)
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
