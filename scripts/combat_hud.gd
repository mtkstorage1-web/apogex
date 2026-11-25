extends CanvasLayer
class_name CombatHUD
## Procedural combat feedback overlay: tactical crosshair with bloom, X-hitmarker,
## screen-edge damage vignette and a top-center event banner. Never blocks input.

const HIT_TIME := 0.16
const DAMAGE_TIME := 0.28
const BANNER_TIME := 2.6
# Top-center vertical stack (no overlap): phase strip 10-50, crew cards 58-110 (hud.gd),
# score strip 114-138, compass 142-168, announce banner from 174.
const SCORE_Y := 114.0
const SCORE_H := 24.0
const COMPASS_W := 360.0
const COMPASS_H := 26.0
const COMPASS_Y := 142.0
const SCORE_PULSE := 0.6
const COMPASS_HALF_FOV := 90.0  # degrees visible each side of center
const SHIELD_COL := UI.CYAN
const HULL_COL := UI.BAD
const THRUST_COL := UI.GOOD
const RELOAD_COL := UI.WARN
const AMMO_WARN_COL := UI.CORAL

var canvas: Control
var crosshair_visible := false
var target_locked := false
var bloom := 0.0          # extra gap in px, recovers toward 0
var hit_t := 0.0
var hit_col := Color.WHITE
var dmg_t := 0.0
var dmg_col := HULL_COL
var banner_t := 0.0
var banner_title := ""
var banner_sub := ""
var banner_accent := UI.GOLD
var _font: Font

const VITALS_W := 340.0
const VITALS_BOTTOM := 16.0
const VITALS_GAP := 12.0
const VITALS_CARD := 44.0
const VITALS_BARS := 48.0
var hud_opacity := 1.0
var _vitals_above := INF
var _vitals_safe_bottom := 0.0
var _vitals_touch := UI.is_touch_platform()
var vitals_limits := Vector2(100, 100)
var primary_weapon_only := false
var _vitals_on := false
var _hp := 100.0
var _shield := 0.0
var _shown_hp := 100.0
var _shown_shield := 0.0
var _ammo := 0
var _ammo_max := 24
var _drawn := false
var _equip: Dictionary = {}
const POPUP_MAX := 24
const POPUP_LIFE := 0.75
const LETHAL_COL := UI.CYAN
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
var _reduced_motion := false
var _compass_markers: Array = []  # {pos, color, label, priority}
var _team_scores: Array = []      # {name, color, delivered, onboard, pulse, gain}


func _ready() -> void:
	layer = 6
	canvas = Control.new()
	canvas.name = "CombatCanvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_overlay)
	add_child(canvas)
	_font = UI.font()
	add_to_group("combat_hud")


func spawn_damage_number(world_pos: Vector3, amount: float, is_lethal: bool = false, accent: Color = Color.WHITE) -> void:
	if _popups.size() >= POPUP_MAX:
		_popups.pop_front()
	var txt := ("-%d KO!" if is_lethal else "-%d") % roundi(amount)
	_popups.append({"pos": world_pos, "text": txt, "age": 0.0,
		"vx": randf_range(-22.0, 22.0), "vy": randf_range(52.0, 70.0),
		"col": LETHAL_COL if is_lethal else accent, "lethal": is_lethal})
	canvas.queue_redraw()


func push_feed(text: String, accent: Color = UI.GOLD) -> void:
	_feed.push_front({"text": text, "accent": accent, "age": 0.0})
	if _feed.size() > FEED_MAX:
		_feed.resize(FEED_MAX)
	canvas.queue_redraw()


func push_elimination(attacker: String, attacker_color: Color, victim: String, victim_color: Color) -> void:
	push_feed("%s eliminated %s" % [attacker, victim], attacker_color)
	_feed[0]["attacker"] = attacker.to_upper()
	_feed[0]["victim"] = victim.to_upper()
	_feed[0]["victim_color"] = victim_color


## Bottom-center vitals and loadout cluster.
func set_vitals(hp: float, shield: float, ammo: int, ammo_max: int, drawn: bool, equip_ready := {}) -> void:
	var changed := not _vitals_on or absf(hp - _hp) > 0.4 or absf(shield - _shield) > 0.4 or ammo != _ammo or drawn != _drawn or equip_ready != _equip
	if not _vitals_on or UI.reduced_motion:
		_shown_hp = hp
		_shown_shield = shield
	_vitals_on = true
	_hp = hp
	_shield = shield
	_ammo = ammo
	_ammo_max = maxi(1, ammo_max)
	_drawn = drawn
	_equip = equip_ready
	if changed and canvas != null:
		canvas.queue_redraw()


func set_hud_opacity(v: float) -> void:
	v = clampf(v, 0.35, 1.0)
	if is_equal_approx(v, hud_opacity):
		return
	hud_opacity = v
	if canvas != null:
		canvas.queue_redraw()


## Touch/mobile gets a ~1.35x vitals cluster; desktop keeps the original size.
func _vscale() -> float:
	return 1.35 if _vitals_touch else 1.0


func set_vitals_layout(above_y: float, safe_bottom: float, touch: bool) -> void:
	if above_y == _vitals_above and safe_bottom == _vitals_safe_bottom and touch == _vitals_touch:
		return
	_vitals_above = above_y
	_vitals_safe_bottom = safe_bottom
	_vitals_touch = touch
	canvas.queue_redraw()


func vitals_rect() -> Rect2:
	if not _vitals_on or canvas == null:
		return Rect2()
	var scale_factor := _vscale()
	var width := minf(VITALS_W * scale_factor, canvas.size.x - 24.0)
	var height := (VITALS_CARD + VITALS_BARS) * scale_factor
	var bottom := minf(canvas.size.y - _vitals_safe_bottom - VITALS_BOTTOM * scale_factor, _vitals_above - VITALS_GAP)
	return Rect2((canvas.size.x - width) * 0.5, bottom - height, width, height)


func hide_vitals() -> void:
	if _vitals_on:
		_vitals_on = false
		if canvas != null:
			canvas.queue_redraw()


func set_crosshair_visible(v: bool) -> void:
	if v != crosshair_visible:
		crosshair_visible = v
		canvas.queue_redraw()


func set_target_locked(locked: bool) -> void:
	if locked != target_locked:
		target_locked = locked
		canvas.queue_redraw()


func trigger_bloom(amount := 9.0) -> void:
	bloom = minf(bloom + amount, 30.0)
	canvas.queue_redraw()


func trigger_hitmarker(is_kill_or_break: bool) -> void:
	hit_t = HIT_TIME
	hit_col = UI.MAGENTA if is_kill_or_break else UI.CYAN
	canvas.queue_redraw()


func trigger_damage(is_shield: bool) -> void:
	if UI.reduced_motion:
		return
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


## Each score takes name, color, delivered, and optional onboard or target values.
func set_team_scores(scores: Array) -> void:
	var changed := scores.size() != _team_scores.size()
	var next: Array = []
	for i in scores.size():
		var s: Dictionary = scores[i]
		var d := int(s.get("delivered", 0))
		var o := int(s.get("onboard", 0))
		var target := int(s.get("target", 0))
		var entry := {"name": str(s.get("name", "")), "color": s.get("color", Color.WHITE),
			"delivered": d, "onboard": o, "target": target, "pulse": 0.0, "gain": 0}
		if i < _team_scores.size():
			var old: Dictionary = _team_scores[i]
			entry["pulse"] = old["pulse"]
			entry["gain"] = old["gain"]
			var gain := maxi(d - int(old["delivered"]), 0) + maxi(o - int(old["onboard"]), 0)
			if gain > 0:
				entry["pulse"] = SCORE_PULSE
				entry["gain"] = gain
			if d != old["delivered"] or o != old["onboard"] or entry["name"] != old["name"] or target != old["target"]:
				changed = true
		next.append(entry)
	_team_scores = next
	if changed:
		canvas.queue_redraw()


func announce(title: String, subtitle := "", accent := UI.GOLD) -> void:
	banner_title = title
	banner_sub = subtitle
	banner_accent = accent
	banner_t = BANNER_TIME
	canvas.queue_redraw()


func _process(dt: float) -> void:
	if _reduced_motion != UI.reduced_motion:
		_reduced_motion = UI.reduced_motion
		if _reduced_motion:
			dmg_t = 0.0
		canvas.queue_redraw()
	var pulsing := not _reduced_motion and ((crosshair_visible and low_ammo and reload_ratio <= 0.0)
		or (_vitals_on and (_hp < vitals_limits.x * 0.3 or _shield < vitals_limits.y * 0.3 or (_drawn and _ammo < _ammo_max * 0.3))))
	var animating := bloom > 0.0 or hit_t > 0.0 or dmg_t > 0.0 or banner_t > 0.0 or not _popups.is_empty() or not _feed.is_empty() or not _threats.is_empty() or pulsing
	for t in _team_scores:
		if t["pulse"] > 0.0:
			t["pulse"] = maxf(0.0, t["pulse"] - dt)
			animating = true
	if _vitals_on and (_shown_hp != _hp or _shown_shield != _shield):
		var blend := 1.0 if UI.reduced_motion else 1.0 - exp(-19.0 * dt)
		_shown_hp = _hp if absf(_shown_hp - _hp) < 0.1 else lerpf(_shown_hp, _hp, blend)
		_shown_shield = _shield if absf(_shown_shield - _shield) < 0.1 else lerpf(_shown_shield, _shield, blend)
		animating = true
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
	if dmg_t > 0.0 and not UI.reduced_motion:
		_draw_vignette(size, dmg_t / DAMAGE_TIME)
	if crosshair_visible:
		var gap := 6.0 + bloom
		var col := UI.MAGENTA if target_locked else Color(UI.CYAN.lerp(Color.WHITE, 0.55), 0.95)
		var shadow := Color(0, 0, 0, 0.45)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var a: Vector2 = c + d * gap
			var b: Vector2 = c + d * (gap + 9.0)
			canvas.draw_line(a, b, shadow, 4.0)
			canvas.draw_line(a, b, Color(col, 0.28), 5.0)
			canvas.draw_line(a, b, col, 2.0)
		canvas.draw_circle(c, 3.5, Color(col, 0.25))
		canvas.draw_circle(c, 1.5, col)
	if not _threats.is_empty():
		_draw_threats(c)
	if crosshair_visible:
		_draw_reload_and_ammo(c)
	if hit_t > 0.0:
		var k := hit_t / HIT_TIME
		var hc := Color(hit_col, k)
		var r0 := 7.0 + 7.0 * k if not UI.reduced_motion else 9.0
		var r1 := r0 + 8.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			canvas.draw_line(c + n * r0, c + n * r1, hc, 2.5)
	if _vitals_on:
		_draw_vitals()
	if not _team_scores.is_empty() and int(_team_scores[0]["target"]) == 0:
		_draw_score_strip(size)
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
		canvas.draw_string_outline(_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85 * a))
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
		canvas.draw_colored_polygon(pill, Color(UI.INDIGO_GLASS, 0.78 * a))
		var strip := PackedVector2Array([Vector2(x0 + slant, y), Vector2(x0 + slant + 4.0, y), Vector2(x0 + 4.0, y + h), Vector2(x0, y + h)])
		canvas.draw_colored_polygon(strip, Color(acc, a))
		if e.has("victim"):
			var name_width := (w - 72.0) * 0.5
			canvas.draw_string(_font, Vector2(x0 + 18.0, y + 18.0), e["attacker"], HORIZONTAL_ALIGNMENT_LEFT, name_width, 13, Color(acc, a))
			_equip_glyph("gun", Vector2(x0 + w * 0.5, y + h * 0.5), 8.0, Color(UI.TEXT, a))
			canvas.draw_string(_font, Vector2(x0 + w * 0.5 + 18.0, y + 18.0), e["victim"], HORIZONTAL_ALIGNMENT_LEFT, name_width, 13, Color(e["victim_color"], a))
		else:
			canvas.draw_string(_font, Vector2(x0 + 18.0, y + 18.0), e["text"], HORIZONTAL_ALIGNMENT_LEFT, w - 30.0, 14, Color(UI.TEXT, a))

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


func _draw_score_strip(size: Vector2) -> void:
	if not _font:
		return
	var n := _team_scores.size()
	var chip_w := 140.0 if int(_team_scores[0]["target"]) > 0 else 84.0
	var gap := 4.0
	var pad := 8.0
	var w := n * chip_w + (n - 1) * gap + pad * 2.0
	var x0 := (size.x - w) * 0.5
	var y0 := SCORE_Y
	var slant := 8.0
	var glass := PackedVector2Array([Vector2(x0 + slant, y0), Vector2(x0 + w - slant, y0), Vector2(x0 + w, y0 + SCORE_H), Vector2(x0, y0 + SCORE_H)])
	canvas.draw_colored_polygon(glass, Color(UI.INDIGO_GLASS, 0.8))
	for i in n:
		var t: Dictionary = _team_scores[i]
		var col: Color = t["color"]
		var cx := x0 + pad + i * (chip_w + gap)
		var k: float = t["pulse"] / SCORE_PULSE
		if k > 0.0:
			canvas.draw_rect(Rect2(cx, y0 + 2.0, chip_w, SCORE_H - 4.0), Color(col, 0.35 * k))
		var dot_r := 4.0 + 1.5 * k
		canvas.draw_circle(Vector2(cx + 8.0, y0 + SCORE_H * 0.5), dot_r, col)
		var nm: String = t["name"].left(3).to_upper()
		var txt := "%s %d" % [nm, t["delivered"]]
		if t["target"] > 0:
			txt = "%s %d/%d" % [t["name"], t["delivered"], t["target"]]
		elif t["onboard"] > 0:
			txt += "+%d" % t["onboard"]
		canvas.draw_string(_font, Vector2(cx + 17.0, y0 + 16.0), txt, HORIZONTAL_ALIGNMENT_LEFT, chip_w - 18.0, 12, Color(1, 1, 1, 0.95))
		if k > 0.0:
			var rise := (1.0 - k) * 8.0
			canvas.draw_string(_font, Vector2(cx + chip_w - 22.0, y0 + 14.0 - rise), "+%d" % t["gain"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col.lightened(0.3), k))
	canvas.draw_line(Vector2(x0 + slant, y0 + SCORE_H), Vector2(x0 + w, y0 + SCORE_H), Color(UI.VIOLET, 0.8), 2.0)


func banner_rect() -> Rect2:
	if canvas == null:
		return Rect2()
	var width := minf(460.0, canvas.size.x - 32.0)
	var height := 62.0 if not banner_sub.is_empty() else 46.0
	var y := canvas.size.y * 0.65 - height * 0.5
	if _vitals_on:
		y = minf(y, vitals_rect().position.y - height - 18.0)
	return Rect2((canvas.size.x - width) * 0.5, y, width, height)


func _draw_banner(_size: Vector2) -> void:
	var life := BANNER_TIME - banner_t
	var enter := clampf(life / 0.24, 0.0, 1.0)
	var alpha := minf(1.0 if UI.reduced_motion else enter, banner_t / 0.3)
	var bounds := banner_rect()
	var zoom := 1.0 if UI.reduced_motion else lerpf(0.88, 1.0, Tween.interpolate_value(0.0, 1.0, enter, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT))
	canvas.draw_set_transform(bounds.get_center(), 0.0, Vector2.ONE * zoom)
	bounds.position = -bounds.size * 0.5
	var x := bounds.position.x
	var y := bounds.position.y
	var w := bounds.size.x
	var h := bounds.size.y
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(x + 16, y), Vector2(x + w, y), Vector2(x + w - 16, y + h), Vector2(x, y + h)]), Color(UI.BG_DEEP, 0.94 * alpha))
	canvas.draw_line(Vector2(x + 16, y + 2), Vector2(x + w - 3, y + 2), Color(banner_accent, alpha), 4.0, true)
	canvas.draw_string(UI.font(true), Vector2(x, y + 34), banner_title, HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color(UI.TEXT, alpha))
	if not banner_sub.is_empty():
		canvas.draw_string(_font, Vector2(x, y + 53), banner_sub, HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(banner_accent, alpha))
	canvas.draw_set_transform(Vector2.ZERO)


func _vital_color(ratio: float, nominal: Color) -> Color:
	var alpha := hud_opacity
	if ratio < 0.3 and not UI.reduced_motion:
		alpha *= 0.74 + 0.26 * sin(Time.get_ticks_msec() * 0.009)
	return Color(UI.ramp_color(ratio, nominal), alpha)


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
		var base: Color = SHIELD_COL if t["shield"] else UI.CORAL
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
		canvas.draw_arc(c, rr, 0.0, TAU, 40, Color(UI.INDIGO_GLASS, 0.7), 4.0, true)
		canvas.draw_arc(c, rr, -PI / 2.0, -PI / 2.0 + TAU * reload_ratio, 40, RELOAD_COL, 2.5, true)
		var txt := "RELOADING"
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		canvas.draw_string(_font, Vector2(c.x - w * 0.5, c.y + rr + 16.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, RELOAD_COL)
	elif low_ammo:
		var pulse := 1.0 if UI.reduced_motion else 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.012)
		var txt := "LOW AMMO"
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var rect := Rect2(c.x - w * 0.5 - 8.0, c.y + 28.0, w + 16.0, 16.0)
		var amber := AMMO_WARN_COL
		canvas.draw_rect(rect, Color(0.08, 0.08, 0.09, 0.6 * pulse), true)
		canvas.draw_rect(rect, Color(amber, 0.8 * pulse), false, 1.0)
		canvas.draw_string(_font, Vector2(rect.position.x + 8.0, rect.position.y + 12.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(amber, pulse))


## Stacked health + shield bars over a 5-card loadout strip: gun (+ammo), melee, throwable, medkit, pack.
func _draw_vitals() -> void:
	var k := _vscale()
	var o := hud_opacity
	var bounds := vitals_rect()
	var w := bounds.size.x
	var x0 := bounds.position.x
	var card := VITALS_CARD * k
	var reserved := 87.0 * k if _drawn and not primary_weapon_only else 0.0
	var gap := (w - reserved - card * 5.0) / 4.0
	var y_cards := bounds.end.y - card
	var ink := Color(UI.BG_DEEP, o)
	var bar_h := 11.0 * k
	var y_shield := y_cards - 10.0 * k - bar_h
	var y_health := y_shield - 6.0 * k - bar_h
	canvas.draw_style_box(UI.glass_style(Color(UI.PANEL, UI.PANEL.a * o)), Rect2(x0 - 9.0, y_health - 7.0, w + 18.0, y_shield + bar_h - y_health + 14.0))
	var hp_max := maxf(1.0, vitals_limits.x)
	var shield_max := maxf(1.0, vitals_limits.y)
	_vital_bar(x0, y_health, w, bar_h, _shown_hp / hp_max, _vital_color(_hp / hp_max, UI.GOOD), ink, "%d" % roundi(_hp), "hp")
	_vital_bar(x0, y_shield, w, bar_h, _shown_shield / shield_max, _vital_color(_shield / shield_max, UI.CYAN), ink, "%d" % roundi(_shield), "shield")
	var ids := ["gun", "melee", "throwable", "medkit", "pack"]
	var keys := ["B", "X", "J", "K", "I"]
	var slot_left := x0 + (w - card) * 0.5 if primary_weapon_only else x0
	var slot_count := 1 if primary_weapon_only else ids.size()
	for i in slot_count:
		var r := Rect2(slot_left + i * (card + gap), y_cards, card, card)
		var on: bool = _equip.get(ids[i], true) as bool
		var active: bool = i == 0 and _drawn
		var edge := UI.ACCENT if active else (UI.CYAN if on else UI.DIM)
		canvas.draw_style_box(UI.glass_style(Color(UI.PANEL, o), 0), r)
		canvas.draw_line(r.position + Vector2(8, 4), Vector2(r.end.x - 8, r.position.y + 4), Color(edge, 0.8 * o), 2.0, true)
		var fg := Color(edge if active else UI.TEXT, (1.0 if on else 0.42) * o)
		_equip_glyph(ids[i], r.get_center() + Vector2(0, -2.0 * k), 9.0 * k, fg)
		canvas.draw_string(_font, Vector2(r.position.x, r.end.y - 4.0 * k), keys[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(10 * k), fg)
	if _drawn:
		var ammo_x := slot_left + card + 10.0 if primary_weapon_only else x0 + w - 77.0 * k
		var ammo_bounds := Rect2(ammo_x, y_cards, 77.0 * k, card)
		canvas.draw_style_box(UI.glass_style(Color(UI.PANEL, o), 0), ammo_bounds)
		var ammo_ink := _vital_color(float(_ammo) / maxf(1.0, _ammo_max), UI.GOLD)
		canvas.draw_string(UI.font(true), ammo_bounds.position + Vector2(8, 30) * k, "%02d" % _ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, int(27 * k), ammo_ink)
		canvas.draw_string(_font, ammo_bounds.position + Vector2(43, 30) * k, "/ %d" % _ammo_max, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * k), Color(UI.MUTED, o))



func _vital_bar(x: float, y: float, w: float, h: float, ratio: float, fill: Color, back: Color, text: String, icon := "") -> void:
	var ks := _vscale()
	var label_w := 52.0 * ks
	var bw := w - label_w
	canvas.draw_rect(Rect2(x, y, bw, h), back, true)
	var segs := 10
	var sw := (bw - 2.0) / segs
	var lit := clampf(ratio, 0.0, 1.0) * segs
	for i in segs:
		var k := clampf(lit - i, 0.0, 1.0)
		if k > 0.0:
			canvas.draw_rect(Rect2(x + 1.0 + i * sw, y + 1.0, (sw - 1.5) * k, h - 2.0), fill, true)
	canvas.draw_rect(Rect2(x, y, bw, h), Color(1, 1, 1, 0.55 * hud_opacity), false, 1.0)
	# Icon glyph (cross / shield) + bare number instead of 'HP'/'SH' captions.
	var ic := Vector2(x + bw + 9.0 * ks, y + h * 0.5)
	if icon == "hp":
		_equip_glyph("medkit", ic, 4.5 * ks, fill)
	else:
		canvas.draw_arc(ic - Vector2(0, 1.5 * ks), 4.0 * ks, PI, TAU, 8, fill, 2.0 * ks)
		canvas.draw_rect(Rect2(ic + Vector2(-4.0 * ks, -1.5 * ks), Vector2(8.0 * ks, 5.5 * ks)), fill)
	canvas.draw_string(_font, Vector2(x + bw + 18.0 * ks, y + h + 1.0 * ks), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * ks), fill)


func _equip_glyph(id: String, c: Vector2, s: float, col: Color) -> void:
	match id:
		"gun":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.4), c + Vector2(s, -s * 0.4), c + Vector2(s, s * 0.05),
				c + Vector2(-s * 0.1, s * 0.05), c + Vector2(-s * 0.15, s * 0.7), c + Vector2(-s * 0.55, s * 0.7), c + Vector2(-s * 0.5, s * 0.05), c + Vector2(-s, s * 0.05)]), col)
		"melee":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s, -s), c + Vector2(s * 0.1, s * 0.05), c + Vector2(-s * 0.1, -s * 0.2)]), col)
			canvas.draw_line(c + Vector2(-s * 0.2, s * 0.1), c + Vector2(s * 0.3, s * 0.4), col, 2.0)
			canvas.draw_line(c + Vector2(0, s * 0.2), c + Vector2(-s * 0.7, s * 0.9), col, 3.0)
		"throwable":
			canvas.draw_circle(c + Vector2(0, s * 0.25), s * 0.7, col)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.25, -s * 0.8), Vector2(s * 0.5, s * 0.35)), col)
		"medkit":
			canvas.draw_rect(Rect2(c - Vector2(s * 0.2, s * 0.8), Vector2(s * 0.4, s * 1.6)), col)
			canvas.draw_rect(Rect2(c - Vector2(s * 0.8, s * 0.2), Vector2(s * 1.6, s * 0.4)), col)
		_:
			canvas.draw_arc(c + Vector2(0, -s * 0.6), s * 0.4, PI, TAU, 10, col, 2.0)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.6), Vector2(s * 1.6, s * 1.7)), col)


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
	canvas.draw_colored_polygon(glass, Color(UI.INDIGO_GLASS, 0.75))
	canvas.draw_line(Vector2(x0 + 4, y0 + COMPASS_H), Vector2(x0 + COMPASS_W - 4, y0 + COMPASS_H), Color(UI.CYAN, 0.55), 1.5)
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
					var col := UI.GOLD if nm == "N" else Color(UI.CYAN.lerp(Color.WHITE, 0.5), (0.95 if cardinal else 0.6) * edge_a)
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
		canvas.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color(0, 0, 0, 0.8 * a), 1.2)
		if i == nearest and _font:
			var txt := "%dm" % roundi(nearest_d)
			var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var tx := clampf(mx - w * 0.5, x0, x0 + COMPASS_W - w)
			canvas.draw_string_outline(_font, Vector2(tx, y0 + COMPASS_H + 12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.85))
			canvas.draw_string(_font, Vector2(tx, y0 + COMPASS_H + 12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(mc, 1.0))
	# Center amber pointer notch.
	var amber := UI.GOLD
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, y0 - 3), Vector2(cx + 5, y0 - 3), Vector2(cx, y0 + 5)]), amber)
	canvas.draw_line(Vector2(cx, y0 + 5), Vector2(cx, y0 + COMPASS_H), Color(amber, 0.55), 1.5)
