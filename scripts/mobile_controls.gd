class_name MobileControls
extends Control
## PUBG / Mobile Legends style touch overlay: left virtual joystick, right arc
## action cluster around a big FIRE button, and right-half drag-to-look.
## Root ignores GUI mouse picking; touches are read in _unhandled_input so any
## modal / menu Control above still receives its clicks first.

signal action_pressed(action_name: String)

const DEADZONE := 0.12
const SPRINT_EDGE := 0.85
const JOY_RADIUS := 92.0
const NUB_RADIUS := 38.0
const FIRE_RADIUS := 64.0
const SAT_RADIUS := 31.0
const ARC_RADIUS := 138.0
const LOOK_SCALE := 1.0
## name, label, arc angle in degrees (screen space: 180 = left, 270 = up).
const SATELLITES := [
	["jump", "JUMP", 180.0],
	["interact", "E", 202.5],
	["reload", "R", 225.0],
	["weapon", "B", 247.5],
	["map", "MAP", 270.0],
]
## Squad quick-command buttons above the arc: name, label, x offset from FIRE.
const CMD_BUTTONS := [
	["order", "CMD", -34.0],
	["priority", "PING", 34.0],
]
const CMD_RADIUS := 27.0
const CMD_RISE := 222.0
const MOUSE_POINTER := 1000

const SLATE := Color(0.08, 0.1, 0.16, 0.42)
const SLATE_EDGE := Color(0.62, 0.68, 0.82, 0.38)
const AMBER := Color(1.0, 0.72, 0.32, 0.92)
const AMBER_GLOW := Color(1.0, 0.62, 0.22, 0.28)
const FIRE_CORE := Color(0.98, 0.56, 0.18, 0.86)

var touch_enabled := false
var active := true   # main.gd gates this to gameplay so menus never see touch state
var move_vec := Vector2.ZERO
var sprint_active := false
var look_delta := Vector2.ZERO
var firing := false

var _joy_pointer := -1
var _joy_center := Vector2.ZERO
var _nub := Vector2.ZERO
var _fire_pointer := -1
var _look_pointers := {}
var _button_pointers := {}   # pointer -> action name
var _pressed_flash := {}     # action -> seconds of press-scale feedback
var _font: Font
var _primary_label := "FIRE"
var _ripples: Array = []     # {pos, t, r} expanding tap rings
const RIPPLE_TIME := 0.32


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _ready() -> void:
	set_touch_visible(DisplayServer.is_touchscreen_available())


# ---------------------------------------------------------------- public API
func move_vector() -> Vector2:
	return move_vec if _live() else Vector2.ZERO


func consume_look_delta() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d if _live() else Vector2.ZERO


func is_firing() -> bool:
	return firing and _live()


func is_sprinting() -> bool:
	return sprint_active and _live()


func is_touch_visible() -> bool:
	return touch_enabled


func set_touch_visible(enabled: bool) -> void:
	touch_enabled = enabled
	visible = enabled
	_reset()


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if not on:
		_reset()
	queue_redraw()


# ---------------------------------------------------------------- layout
func joy_home() -> Vector2:
	return Vector2(170.0, size.y - 170.0)


func fire_center() -> Vector2:
	return Vector2(size.x - 150.0, size.y - 160.0)


func satellite_center(i: int) -> Vector2:
	var a := deg_to_rad(float(SATELLITES[i][2]))
	return fire_center() + Vector2(cos(a), sin(a)) * ARC_RADIUS


func cmd_center(i: int) -> Vector2:
	return fire_center() + Vector2(float(CMD_BUTTONS[i][2]), -CMD_RISE)


func set_primary_label(text: String) -> void:
	if text == _primary_label:
		return
	_primary_label = text
	queue_redraw()


func primary_label() -> String:
	return _primary_label


## Leftmost x reached by the action cluster (outermost satellite at 180°).
func cluster_left_edge() -> float:
	var edge := fire_center().x - ARC_RADIUS - SAT_RADIUS
	for i in CMD_BUTTONS.size():
		edge = minf(edge, cmd_center(i).x - CMD_RADIUS)
	return edge


func _ripple(pos: Vector2, radius: float) -> void:
	_ripples.append({"pos": pos, "t": 0.0, "r": radius})


func _live() -> bool:
	return touch_enabled and active


func _reset() -> void:
	_joy_pointer = -1
	_fire_pointer = -1
	_look_pointers.clear()
	_button_pointers.clear()
	_ripples.clear()
	move_vec = Vector2.ZERO
	sprint_active = false
	look_delta = Vector2.ZERO
	firing = false
	queue_redraw()


# ---------------------------------------------------------------- input
func _unhandled_input(e: InputEvent) -> void:
	if not _live():
		return
	if e is InputEventScreenTouch:
		_touch(e.index, e.position, e.pressed)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		_drag(e.index, e.position, e.relative)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.is_emulated_from_touch():
		# Desktop test mode: the mouse acts as one finger.
		_touch(MOUSE_POINTER, e.position, e.pressed)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and not e.is_emulated_from_touch() and _owns(MOUSE_POINTER):
		_drag(MOUSE_POINTER, e.position, e.relative)
		get_viewport().set_input_as_handled()


func _owns(p: int) -> bool:
	return p == _joy_pointer or p == _fire_pointer or _look_pointers.has(p) or _button_pointers.has(p)


func _touch(p: int, pos: Vector2, down: bool) -> void:
	if down:
		if pos.distance_to(fire_center()) <= FIRE_RADIUS * 1.15:
			_fire_pointer = p
			firing = true
			_pressed_flash["fire"] = 0.12
			_ripple(fire_center(), FIRE_RADIUS)
		else:
			var hit := ""
			for i in SATELLITES.size():
				if pos.distance_to(satellite_center(i)) <= SAT_RADIUS * 1.3:
					hit = SATELLITES[i][0]
					break
			if hit != "":
				_button_pointers[p] = hit
				_pressed_flash[hit] = 0.16
				_ripple(satellite_center(SATELLITES.map(func(x): return x[0]).find(hit)), SAT_RADIUS)
				action_pressed.emit(hit)
			elif pos.x < size.x * 0.45 and _joy_pointer == -1:
				_joy_pointer = p
				# Floating base: re-centres under the thumb inside the left zone.
				_joy_center = pos if pos.distance_to(joy_home()) > JOY_RADIUS else joy_home()
				_update_joy(pos)
			elif pos.x >= size.x * 0.45:
				_look_pointers[p] = true
	else:
		if p == _joy_pointer:
			_joy_pointer = -1
			move_vec = Vector2.ZERO
			sprint_active = false
			_nub = Vector2.ZERO
		if p == _fire_pointer:
			_fire_pointer = -1
			firing = false
		_look_pointers.erase(p)
		_button_pointers.erase(p)
	queue_redraw()


func _drag(p: int, pos: Vector2, rel: Vector2) -> void:
	if p == _joy_pointer:
		_update_joy(pos)
	elif _look_pointers.has(p) or p == _fire_pointer:
		# PUBG style: dragging off the fire button also steers the aim.
		look_delta += rel * LOOK_SCALE
	queue_redraw()


func _update_joy(pos: Vector2) -> void:
	var off := (pos - _joy_center).limit_length(JOY_RADIUS)
	_nub = off
	var v := off / JOY_RADIUS
	var l := v.length()
	if l < DEADZONE:
		move_vec = Vector2.ZERO
		sprint_active = false
	else:
		move_vec = v.normalized() * inverse_lerp(DEADZONE, 1.0, l)
		sprint_active = l > SPRINT_EDGE


func _process(dt: float) -> void:
	if _pressed_flash.is_empty() and _ripples.is_empty():
		return
	for rp in _ripples:
		rp["t"] += dt
	_ripples = _ripples.filter(func(rp): return rp["t"] < RIPPLE_TIME)
	for k in _pressed_flash.keys():
		_pressed_flash[k] -= dt
		if _pressed_flash[k] <= 0.0 and not (k == "fire" and firing):
			_pressed_flash.erase(k)
	queue_redraw()


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not _live():
		return
	# Joystick.
	var c := _joy_center if _joy_pointer != -1 else joy_home()
	draw_circle(c, JOY_RADIUS, SLATE)
	draw_arc(c, JOY_RADIUS, 0, TAU, 64, SLATE_EDGE, 2.0, true)
	draw_arc(c, JOY_RADIUS * SPRINT_EDGE, 0, TAU, 64, Color(1, 1, 1, 0.08), 1.0, true)
	var nub_col := AMBER if not sprint_active else Color(1.0, 0.85, 0.45, 1.0)
	draw_circle(c + _nub, NUB_RADIUS + 10.0, AMBER_GLOW)
	draw_circle(c + _nub, NUB_RADIUS, nub_col)
	if sprint_active:
		_label(c + Vector2(0, -JOY_RADIUS - 14.0), "SPRINT", 12, AMBER)
	# Fire button.
	var fc := fire_center()
	var fs := 0.9 if firing else 1.0
	draw_circle(fc, FIRE_RADIUS * 1.22 * fs, AMBER_GLOW)
	draw_circle(fc, FIRE_RADIUS * fs, FIRE_CORE if not firing else Color(1.0, 0.75, 0.3, 0.95))
	draw_arc(fc, FIRE_RADIUS * fs, 0, TAU, 64, Color(1.0, 0.9, 0.6, 0.9), 3.0, true)
	_label(fc, _primary_label, 18 if _primary_label.length() <= 4 else 15, Color(0.12, 0.06, 0.02, 0.95))
	# Satellites.
	for i in SATELLITES.size():
		var id: String = SATELLITES[i][0]
		var sc := satellite_center(i)
		var held := _button_pointers.values().has(id)
		var r := SAT_RADIUS * (0.86 if held or _pressed_flash.has(id) else 1.0)
		draw_circle(sc, r, SLATE if not held else Color(0.3, 0.2, 0.1, 0.6))
		draw_arc(sc, r, 0, TAU, 40, AMBER if held else SLATE_EDGE, 2.0, true)
		_label(sc, SATELLITES[i][1], 12, Color(1, 0.95, 0.88, 0.95))
	# Squad quick-command buttons.
	for i in CMD_BUTTONS.size():
		var cid: String = CMD_BUTTONS[i][0]
		var cc := cmd_center(i)
		var cheld := _button_pointers.values().has(cid)
		var cr := CMD_RADIUS * (0.86 if cheld or _pressed_flash.has(cid) else 1.0)
		draw_circle(cc, cr, SLATE if not cheld else Color(0.3, 0.2, 0.1, 0.6))
		draw_arc(cc, cr, 0, TAU, 40, AMBER if cheld else SLATE_EDGE, 2.0, true)
		_label(cc, CMD_BUTTONS[i][1], 11, Color(1, 0.95, 0.88, 0.95))
	# Tap ripples: crisp expanding translucent rings.
	for rp in _ripples:
		var k: float = rp["t"] / RIPPLE_TIME
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		var rad: float = rp["r"] * (1.0 + 0.7 * ease_k)
		var a := (1.0 - k) * 0.75
		draw_arc(rp["pos"], rad, 0, TAU, 56, Color(1.0, 0.9, 0.65, a), 3.0 * (1.0 - k) + 1.0, true)
		draw_circle(rp["pos"], rad, Color(1.0, 0.8, 0.45, a * 0.18))


func _label(center: Vector2, text: String, fsize: int, col: Color) -> void:
	if _font == null:
		return
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(_font, center + Vector2(-w * 0.5, fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
