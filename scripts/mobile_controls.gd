class_name MobileControls
extends Control
## PUBG / Mobile Legends style touch overlay: left virtual joystick, right arc
## action cluster around a big FIRE button, and right-half drag-to-look.
## Root ignores GUI mouse picking; touches are read in _unhandled_input so any
## modal / menu Control above still receives its clicks first.

signal action_pressed(action_name: String)

const DEADZONE := 0.12
const SPRINT_EDGE := 0.85
const JOY_RADIUS := 100.0
const NUB_RADIUS := 42.0
const FIRE_RADIUS := 70.0
const SAT_RADIUS := 34.0   # 68px diameter >= 64px thumb target
const ARC_RADIUS := 152.0
const LOOK_SCALE := 1.0
const CMD_RADIUS := 30.0   # 60px diameter
const MIN_SCALE := 0.7
const MAX_SCALE := 1.5
const NORM_MIN := 0.03
const NORM_MAX := 0.97
const CUSTOM_PRESET := "CUSTOM"
## Every placeable touch control: id -> action emitted, icon glyph, base radius (px), caption.
const CONTROL_IDS := ["joystick", "sprint", "fire", "scope", "jump", "crouch", "lean_l", "lean_r", "reload", "interact",
	"gun", "melee", "throwable", "medkit", "inventory", "radar", "dash", "cmd", "ping", "cam"]
const CONTROL_DEFS := {
	"joystick": {"action": "", "icon": "joystick", "radius": JOY_RADIUS, "label": "MOVE"},
	"sprint": {"action": "sprint", "icon": "sprint", "radius": SAT_RADIUS, "label": "SPRINT"},
	"fire": {"action": "fire", "icon": "fire", "radius": FIRE_RADIUS, "label": "FIRE"},
	"scope": {"action": "scope", "icon": "scope", "radius": SAT_RADIUS, "label": "SCOPE"},
	"jump": {"action": "jump", "icon": "jump", "radius": SAT_RADIUS, "label": "JUMP"},
	"crouch": {"action": "crouch", "icon": "crouch", "radius": SAT_RADIUS, "label": "CROUCH"},
	"lean_l": {"action": "lean_l", "icon": "lean_l", "radius": SAT_RADIUS, "label": "LEAN L"},
	"lean_r": {"action": "lean_r", "icon": "lean_r", "radius": SAT_RADIUS, "label": "LEAN R"},
	"reload": {"action": "reload", "icon": "reload", "radius": SAT_RADIUS, "label": "RELOAD"},
	"interact": {"action": "interact", "icon": "interact", "radius": SAT_RADIUS, "label": "TAP"},
	"gun": {"action": "weapon", "icon": "weapon", "radius": SAT_RADIUS, "label": "GUN"},
	"melee": {"action": "melee", "icon": "melee", "radius": SAT_RADIUS, "label": "MELEE"},
	"throwable": {"action": "throwable", "icon": "throwable", "radius": SAT_RADIUS, "label": "THROW"},
	"medkit": {"action": "medkit", "icon": "medkit", "radius": SAT_RADIUS, "label": "MED"},
	"inventory": {"action": "inventory", "icon": "inventory", "radius": SAT_RADIUS, "label": "PACK"},
	"radar": {"action": "map", "icon": "map", "radius": SAT_RADIUS, "label": "RADAR"},
	"dash": {"action": "dash", "icon": "dash", "radius": CMD_RADIUS, "label": "DASH"},
	"cmd": {"action": "order", "icon": "order", "radius": CMD_RADIUS, "label": "CMD"},
	"ping": {"action": "priority", "icon": "priority", "radius": CMD_RADIUS, "label": "PING"},
	"cam": {"action": "camera_view", "icon": "cam", "radius": SAT_RADIUS, "label": "VIEW"},
}
## Built-in ergonomic layouts: id -> [x, y, scale] with x,y normalized to the screen.
const PRESET_NAMES := ["2-FINGER", "4-FINGER", "5-FINGER", "6-FINGER"]
const PRESETS := {
	# Thumbs only: stick + sprint/lean/crouch left, FIRE + stance arc right, loadout row on top.
	"2-FINGER": {
		"joystick": [0.13, 0.72, 1.0], "sprint": [0.26, 0.50, 1.0], "crouch": [0.30, 0.80, 1.0],
		"lean_l": [0.06, 0.34, 1.0], "lean_r": [0.17, 0.34, 1.0],
		"fire": [0.88, 0.70, 1.0], "scope": [0.76, 0.58, 1.0], "jump": [0.76, 0.82, 1.0],
		"reload": [0.88, 0.46, 1.0], "interact": [0.65, 0.66, 1.0],
		"gun": [0.54, 0.30, 1.0], "melee": [0.61, 0.30, 1.0], "throwable": [0.68, 0.30, 1.0],
		"medkit": [0.75, 0.30, 1.0], "inventory": [0.82, 0.30, 1.0], "radar": [0.89, 0.30, 1.0],
		"dash": [0.58, 0.46, 1.0], "cmd": [0.50, 0.58, 1.0], "ping": [0.95, 0.58, 1.0], "cam": [0.42, 0.30, 1.0],
	},
	# 4-finger claw: left index FIRE + SCOPE (top-left), right index JUMP/TAP/RELOAD (top-right).
	"4-FINGER": {
		"joystick": [0.13, 0.72, 1.0], "sprint": [0.28, 0.62, 1.0], "crouch": [0.30, 0.84, 1.0],
		"lean_l": [0.07, 0.46, 1.0], "lean_r": [0.19, 0.46, 1.0],
		"fire": [0.10, 0.24, 1.0], "scope": [0.24, 0.24, 1.0],
		"jump": [0.92, 0.20, 1.0], "interact": [0.82, 0.20, 1.0], "reload": [0.72, 0.20, 1.0],
		"gun": [0.92, 0.42, 1.0], "melee": [0.82, 0.42, 1.0], "throwable": [0.72, 0.42, 1.0],
		"medkit": [0.92, 0.62, 1.0], "inventory": [0.82, 0.62, 1.0], "radar": [0.72, 0.62, 1.0],
		"dash": [0.92, 0.82, 1.0], "cmd": [0.82, 0.82, 1.0], "ping": [0.72, 0.82, 1.0], "cam": [0.45, 0.20, 1.0],
	},
	# 5-finger claw: adds a left middle finger on SPRINT / lean.
	"5-FINGER": {
		"joystick": [0.13, 0.74, 1.0], "sprint": [0.26, 0.44, 1.0], "crouch": [0.30, 0.86, 1.0],
		"lean_l": [0.05, 0.46, 1.0], "lean_r": [0.14, 0.46, 1.0],
		"fire": [0.08, 0.20, 1.0], "scope": [0.22, 0.20, 1.0],
		"jump": [0.93, 0.18, 1.0], "interact": [0.83, 0.18, 1.0], "reload": [0.73, 0.18, 1.0],
		"gun": [0.93, 0.40, 1.0], "melee": [0.83, 0.40, 1.0], "throwable": [0.73, 0.40, 1.0],
		"medkit": [0.93, 0.60, 1.0], "inventory": [0.83, 0.60, 1.0], "radar": [0.73, 0.60, 1.0],
		"dash": [0.93, 0.80, 1.0], "cmd": [0.83, 0.80, 1.0], "ping": [0.73, 0.80, 1.0], "cam": [0.45, 0.18, 1.0],
	},
	# 6-finger iPad claw: both hands spread over upper / mid / bottom zones.
	"6-FINGER": {
		"joystick": [0.12, 0.76, 1.0], "sprint": [0.27, 0.52, 1.0], "crouch": [0.30, 0.86, 1.0],
		"lean_l": [0.05, 0.46, 1.0], "lean_r": [0.15, 0.40, 1.0],
		"fire": [0.08, 0.20, 1.0], "scope": [0.22, 0.20, 1.0],
		"jump": [0.93, 0.18, 1.0], "interact": [0.83, 0.14, 1.0], "reload": [0.93, 0.42, 1.0],
		"gun": [0.81, 0.40, 1.0], "melee": [0.71, 0.14, 1.0], "throwable": [0.71, 0.40, 1.0],
		"medkit": [0.93, 0.62, 1.0], "inventory": [0.81, 0.62, 1.0], "radar": [0.35, 0.14, 1.0],
		"dash": [0.93, 0.82, 1.0], "cmd": [0.81, 0.82, 1.0], "ping": [0.71, 0.82, 1.0], "cam": [0.50, 0.14, 1.0],
	},
}
const MOUSE_POINTER := 1000

# Monochrome black & white palette (matte black plates, white/silver linework).
const SLATE := UI.PANEL
const SLATE_EDGE := UI.CYAN
const AMBER := UI.CYAN
const AMBER_GLOW := Color(UI.GOLD, 0.20)
const FIRE_CORE := UI.PANEL_SOLID
const ICON_WHITE := Color(1, 1, 1, 0.94)

var touch_enabled := false
var haptics_enabled := true
var active := true   # main.gd gates this to gameplay so menus never see touch state
var move_vec := Vector2.ZERO
var sprint_active := false
var look_delta := Vector2.ZERO
var firing := false
var sprint_lock := false   # SPRINT button: auto-run toggle

var _joy_pointer := -1
var _joy_center := Vector2.ZERO
var _nub := Vector2.ZERO
var _fire_pointer := -1
var _look_pointers := {}
var _button_pointers := {}   # pointer -> action name
var interact_action := "interact"
var flight_mode := false
const FLIGHT_CONTROLS := ["joystick", "fire", "jump", "crouch", "interact"]
var _pressed_flash := {}     # action -> seconds of press-scale feedback
var _font: Font
var _primary_label := "FIRE"
var preview_mode := false    # layout editor: draw every control, ignore input
var current_preset := "2-FINGER"
var _layout := {}            # id -> {"pos": Vector2 (0..1), "scale": float}
var _ripples: Array = []     # {pos, t, r} expanding tap rings
const RIPPLE_TIME := 0.32


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UI.font()
	_layout = _preset_layout("2-FINGER")


func _ready() -> void:
	set_touch_visible(DisplayServer.is_touchscreen_available() or OS.has_feature("ios") or OS.has_feature("mobile"))


# ---------------------------------------------------------------- public API
func set_flight_mode(on: bool) -> void:
	if flight_mode == on:
		return
	flight_mode = on
	interact_action = "land" if on else "interact"
	_reset()
	queue_redraw()


func flight_held(action: String) -> bool:
	return _live() and _button_pointers.values().has(action)


func move_vector() -> Vector2:
	return move_vec if _live() else Vector2.ZERO


func consume_look_delta() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d if _live() else Vector2.ZERO


func is_firing() -> bool:
	return firing and _live()


func is_sprinting() -> bool:
	return (sprint_active or sprint_lock) and _live()


## SCOPE button is held to aim down sights.
func is_aiming() -> bool:
	return _live() and _button_pointers.values().has("scope")


func is_interacting() -> bool:
	return _live() and _button_pointers.values().has("interact")


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
func _insets() -> Vector4:
	return UI.safe_insets(get_viewport() if is_inside_tree() else null)


func joy_home() -> Vector2:
	return control_center("joystick")


func fire_center() -> Vector2:
	return control_center("fire")


func joy_radius() -> float:
	return control_radius("joystick")


# ---------------------------------------------------------------- custom layout
static func _preset_layout(preset: String) -> Dictionary:
	var out := {}
	var src: Dictionary = PRESETS.get(preset, PRESETS["2-FINGER"])
	for id in CONTROL_IDS:
		var e: Array = src[id]
		out[id] = {"pos": Vector2(float(e[0]), float(e[1])), "scale": float(e[2])}
	return out


static func _sanitize(layout: Dictionary) -> Dictionary:
	var out := _preset_layout("2-FINGER")
	for id in CONTROL_IDS:
		var e: Variant = layout.get(id)
		if not (e is Dictionary):
			continue
		var p: Variant = e.get("pos", out[id]["pos"])
		if p is Array and p.size() >= 2:
			p = Vector2(float(p[0]), float(p[1]))
		if p is Vector2:
			out[id]["pos"] = Vector2(clampf(p.x, NORM_MIN, NORM_MAX), clampf(p.y, NORM_MIN, NORM_MAX))
		out[id]["scale"] = clampf(float(e.get("scale", 1.0)), MIN_SCALE, MAX_SCALE)
	return out


func _same_layout(a: Dictionary, b: Dictionary) -> bool:
	for id in CONTROL_IDS:
		if a[id]["pos"].distance_to(b[id]["pos"]) > 0.002 or absf(a[id]["scale"] - b[id]["scale"]) > 0.01:
			return false
	return true


func apply_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		return
	_layout = _preset_layout(preset_name)
	current_preset = preset_name
	_reset()


## Deep copy: {id: {"pos": Vector2, "scale": float}}; safe to store in a ConfigFile.
func get_layout() -> Dictionary:
	var out := {}
	for id in CONTROL_IDS:
		out[id] = {"pos": _layout[id]["pos"], "scale": _layout[id]["scale"]}
	return out


## Accepts partial / malformed data (missing controls fall back to 2-FINGER).
## The preset name is auto-detected when the layout matches a built-in one.
func set_layout(layout: Dictionary, preset_name := "") -> void:
	_layout = _sanitize(layout)
	current_preset = preset_name if preset_name != "" else detect_preset()
	_reset()


func reset_layout() -> void:
	apply_preset("2-FINGER")


func detect_preset() -> String:
	for n in PRESET_NAMES:
		if _same_layout(_layout, _preset_layout(n)):
			return n
	return CUSTOM_PRESET


func set_preview(on: bool) -> void:
	preview_mode = on
	if on:
		visible = true
		modulate.a = 1.0
	_reset()


func control_norm(id: String) -> Vector2:
	return _layout[id]["pos"]


func control_scale(id: String) -> float:
	return _layout[id]["scale"]


func set_control_norm(id: String, p: Vector2) -> void:
	if _layout.has(id):
		_layout[id]["pos"] = Vector2(clampf(p.x, NORM_MIN, NORM_MAX), clampf(p.y, NORM_MIN, NORM_MAX))
		current_preset = CUSTOM_PRESET
		queue_redraw()


func set_control_scale(id: String, s: float) -> void:
	if _layout.has(id):
		_layout[id]["scale"] = clampf(s, MIN_SCALE, MAX_SCALE)
		current_preset = CUSTOM_PRESET
		queue_redraw()


func control_radius(id: String) -> float:
	return float(CONTROL_DEFS[id]["radius"]) * float(_layout[id]["scale"])


## Pixel centre, clamped so the whole control stays inside the safe area.
func control_center(id: String) -> Vector2:
	var ins := _insets()
	var r := control_radius(id)
	var p: Vector2 = _layout[id]["pos"] * size
	var lo := Vector2(ins.x + r, ins.y + r)
	var hi := Vector2(size.x - ins.z - r, size.y - ins.w - r)
	hi = Vector2(maxf(hi.x, lo.x), maxf(hi.y, lo.y))
	return Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))


## Topmost control under `pos` (nearest centre wins); "" when none.
func control_at(pos: Vector2, include_joystick := false, slop := 1.2) -> String:
	var best := ""
	var best_k := INF
	for id in (FLIGHT_CONTROLS if flight_mode else CONTROL_IDS):
		if id == "joystick" and not include_joystick:
			continue
		var k := pos.distance_to(control_center(id)) / control_radius(id)
		if k <= slop and k < best_k:
			best = id
			best_k = k
	return best


func _joy_on_left() -> bool:
	return control_norm("joystick").x < 0.5


func _in_joy_zone(pos: Vector2) -> bool:
	return pos.x < size.x * 0.45 if _joy_on_left() else pos.x > size.x * 0.55


func set_primary_label(text: String) -> void:
	if text == _primary_label:
		return
	_primary_label = text
	queue_redraw()


func primary_label() -> String:
	return _primary_label


## Edge of the action cluster facing the stick (HUD keeps clear of it): leftmost
## right-half control, or rightmost left-half control when the stick is on the right.
func cluster_left_edge() -> float:
	var edge := size.x
	for id in CONTROL_IDS:
		if id == "joystick" or control_norm(id).x < 0.5:
			continue
		edge = minf(edge, control_center(id).x - control_radius(id))
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
	sprint_lock = false
	look_delta = Vector2.ZERO
	firing = false
	queue_redraw()


func _haptic(ms: int) -> void:
	if haptics_enabled and (OS.has_feature("ios") or OS.has_feature("mobile")):
		Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- input
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset()


func _button_pointer(e: InputEvent) -> int:
	if e is InputEventScreenTouch:
		return e.index
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.is_emulated_from_touch():
		return MOUSE_POINTER
	return -1


## The HUD claims the press through GUI input. Track it alongside overlay buttons.
func press_prompt(e: InputEvent, action: String) -> bool:
	var p := _button_pointer(e)
	if p == -1 or not _live() or not e.is_pressed() or _owns(p):
		return false
	_button_pointers[p] = action
	action_pressed.emit(action)
	_haptic(14)
	queue_redraw()
	return true


func _input(e: InputEvent) -> void:
	# Release a claimed button even when a panel or modal is under the pointer.
	var p := _button_pointer(e)
	if p != -1 and (not e.is_pressed() or e.is_canceled()) and _button_pointers.erase(p):
		queue_redraw()
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if preview_mode or not _live():
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


## Keep the inventory button's keyboard shortcut.
func _tap_key(keycode: int) -> void:
	if not is_inside_tree():
		return
	_send_key(keycode, true)
	get_tree().create_timer(0.08).timeout.connect(_send_key.bind(keycode, false))


func _send_key(keycode: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode as Key
	ev.physical_keycode = keycode as Key
	ev.pressed = down
	Input.parse_input_event(ev)


func _owns(p: int) -> bool:
	return p == _joy_pointer or p == _fire_pointer or _look_pointers.has(p) or _button_pointers.has(p)


func _touch(p: int, pos: Vector2, down: bool) -> void:
	if down:
		var hit := control_at(pos)
		if hit == "fire":
			_fire_pointer = p
			firing = true
			_pressed_flash["fire"] = 0.12
			_haptic(18)
			_ripple(fire_center(), control_radius("fire"))
		elif hit != "":
			var act: String = CONTROL_DEFS[hit]["action"]
			if act == "interact":
				act = interact_action
			_button_pointers[p] = act
			_pressed_flash[act] = 0.16
			_ripple(control_center(hit), control_radius(hit))
			if act == "sprint":
				sprint_lock = not sprint_lock
			elif act == "inventory":
				_tap_key(KEY_I)
			action_pressed.emit(act)
			_haptic(14)
		elif _in_joy_zone(pos):
			if _joy_pointer == -1:
				_joy_pointer = p
				# Floating base: re-centres under the thumb inside the stick's zone.
				var ins := _insets()
				var jr := joy_radius()
				_joy_center = pos if pos.distance_to(joy_home()) > jr else joy_home()
				if _joy_on_left():
					_joy_center.x = clampf(_joy_center.x, ins.x + jr * 0.5, size.x * 0.45)
				else:
					_joy_center.x = clampf(_joy_center.x, size.x * 0.55, size.x - ins.z - jr * 0.5)
				_joy_center.y = clampf(_joy_center.y, jr, size.y - ins.w - jr * 0.5)
				_update_joy(pos)
		else:
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
	var jr := joy_radius()
	var off := (pos - _joy_center).limit_length(jr)
	_nub = off
	var v := off / jr
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
	if not preview_mode and not _live():
		return
	for id in (FLIGHT_CONTROLS if flight_mode else CONTROL_IDS):
		if id == "joystick":
			_draw_joystick()
		elif id == "fire":
			_draw_fire()
		else:
			_draw_button(id)
	# Tap ripples: crisp expanding translucent rings.
	for rp in _ripples:
		var k: float = rp["t"] / RIPPLE_TIME
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		var rad: float = rp["r"] * (1.0 + 0.7 * ease_k)
		var a := (1.0 - k) * 0.75
		draw_arc(rp["pos"], rad, 0, TAU, 56, Color(1.0, 0.9, 0.65, a), 3.0 * (1.0 - k) + 1.0, true)
		draw_circle(rp["pos"], rad, Color(1.0, 0.8, 0.45, a * 0.18))


func _draw_joystick() -> void:
	var jr := joy_radius()
	var sc := control_scale("joystick")
	var c := _joy_center if _joy_pointer != -1 else joy_home()
	draw_circle(c, jr, SLATE)
	draw_arc(c, jr, 0, TAU, 64, SLATE_EDGE, 2.0, true)
	if not flight_mode:
		draw_arc(c, jr * SPRINT_EDGE, 0, TAU, 64, Color(1, 1, 1, 0.08), 1.0, true)
	var nub_col := Color(1.0, 0.85, 0.45, 1.0) if sprint_active and not flight_mode else AMBER
	draw_circle(c + _nub, (NUB_RADIUS + 10.0) * sc, AMBER_GLOW)
	draw_circle(c + _nub, NUB_RADIUS * sc, Color(nub_col, 0.82))
	draw_arc(c + _nub, NUB_RADIUS * sc, 0, TAU, 40, Color(0, 0, 0, 0.85), 2.0, true)


func _draw_fire() -> void:
	var fc := fire_center()
	var fr := control_radius("fire")
	var fs := 0.9 if firing else 1.0
	draw_circle(fc, fr * 1.22 * fs, AMBER_GLOW)
	draw_circle(fc, fr * fs, UI.GOLD if firing else FIRE_CORE)
	draw_arc(fc, fr * fs, 0, TAU, 64, UI.GOLD, 3.0, true)
	var ink := UI.BG_DEEP if firing else UI.GOLD
	_icon("fire", fc - Vector2(0, fr * 0.12), fr * 0.40 * fs, ink)
	_label(fc + Vector2(0, fr * 0.52), "BOOST" if flight_mode else _primary_label, int(fr * 0.29), ink)



func _draw_button(id: String) -> void:
	var def: Dictionary = CONTROL_DEFS[id]
	var act: String = def["action"]
	if act == "interact":
		act = interact_action
	var bc := control_center(id)
	var latched := act == "sprint" and sprint_lock
	var down := not preview_mode and (_button_pointers.values().has(act) or _pressed_flash.has(act) or latched)
	var r := control_radius(id) * (0.88 if down else 1.0)
	var accent := UI.CYAN
	if id in ["jump", "crouch", "sprint", "dash"]:
		accent = UI.EMERALD
	elif id in ["gun", "melee", "throwable", "reload"]:
		accent = UI.CORAL
	elif id in ["interact", "medkit"]:
		accent = UI.GOLD
	draw_circle(bc, r * 1.15, Color(UI.BG_DEEP, 0.8))
	draw_circle(bc, r, accent if down else SLATE)
	draw_arc(bc, r, 0, TAU, 40, accent, 3.0 if down else 2.0, true)
	var ink := UI.BG_DEEP if down else ICON_WHITE
	var caption: String = def["label"]
	if flight_mode:
		caption = "LIFT" if id == "jump" else ("DOWN" if id == "crouch" else ("LAND" if act == "land" else "EXIT"))
	_icon(def["icon"], bc - Vector2(0, r * 0.12), r * 0.38, ink)
	_label(bc + Vector2(0, r * 0.53), caption, maxi(8, int(r * 0.31)), ink)



func _label(center: Vector2, text: String, fsize: int, col: Color) -> void:
	if _font == null:
		return
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(_font, center + Vector2(-w * 0.5, fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## Crisp vector glyphs (s = half-extent) replacing text labels on action buttons.
func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.22)
	match id:
		"jump":   # bold upward double chevron
			for dy in [-0.32, 0.38]:
				var y: float = c.y + s * dy
				draw_polyline(PackedVector2Array([Vector2(c.x - s * 0.8, y + s * 0.4), Vector2(c.x, y - s * 0.4), Vector2(c.x + s * 0.8, y + s * 0.4)]), col, w * 1.3, true)
		"interact":   # touch ring + action bolt
			draw_arc(c, s * 0.95, 0, TAU, 32, Color(col, 0.7), w * 0.6, true)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 0.15, -s * 0.75), c + Vector2(-s * 0.45, s * 0.1), c + Vector2(-s * 0.02, s * 0.1),
				c + Vector2(-s * 0.15, s * 0.75), c + Vector2(s * 0.45, -s * 0.15), c + Vector2(s * 0.02, -s * 0.15)]), col)
		"fire":   # tactical reticle
			draw_arc(c, s * 0.62, 0, TAU, 32, col, w, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * s * 0.38, c + d * s * 1.05, col, w, true)
			draw_circle(c, w * 0.9, col)
		"reload":   # circular refresh arrows
			for a0 in [0.35, PI + 0.35]:
				draw_arc(c, s * 0.7, a0, a0 + PI * 0.72, 16, col, w, true)
				var e := c + Vector2.from_angle(a0 + PI * 0.72) * s * 0.7
				var t := Vector2.from_angle(a0 + PI * 0.72 + PI * 0.5)
				var n := t.orthogonal()
				draw_colored_polygon(PackedVector2Array([e + t * s * 0.38, e + n * s * 0.3, e - n * s * 0.3]), col)
		"weapon":   # blaster silhouette
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, -s * 0.4), c + Vector2(s, -s * 0.4), c + Vector2(s, s * 0.05),
				c + Vector2(-s * 0.1, s * 0.05), c + Vector2(-s * 0.1, s * 0.3), c + Vector2(-s * 0.35, s * 0.3),
				c + Vector2(-s * 0.4, s * 0.05), c + Vector2(-s, s * 0.05)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.05), c + Vector2(-s * 0.35, s * 0.05), c + Vector2(-s * 0.45, s * 0.95), c + Vector2(-s * 0.8, s * 0.95)]), col)
		"map":   # radar sweep
			draw_arc(c, s * 0.95, 0, TAU, 32, col, w * 0.7, true)
			draw_arc(c, s * 0.5, 0, TAU, 24, Color(col, 0.7), w * 0.6, true)
			draw_line(c, c + Vector2.from_angle(-0.9) * s * 0.95, col, w, true)
			draw_circle(c + Vector2(s * 0.3, s * 0.25), w * 0.8, col)
		"sprint":   # runner chevrons (auto-sprint lock)
			for dx in [-0.55, 0.0, 0.55]:
				var x: float = c.x + s * dx
				draw_polyline(PackedVector2Array([Vector2(x - s * 0.3, c.y - s * 0.75), Vector2(x + s * 0.3, c.y), Vector2(x - s * 0.3, c.y + s * 0.75)]), col, w * 1.2, true)
		"scope":   # ADS scope: ring, cross-hair ticks, centre dot
			draw_arc(c, s * 0.8, 0, TAU, 32, col, w, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * s * 0.5, c + d * s * 1.1, col, w * 0.8, true)
			draw_circle(c, w * 0.8, col)
		"crouch":   # crouched figure + down chevron
			draw_circle(c + Vector2(-s * 0.15, -s * 0.55), s * 0.2, col)
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.15, -s * 0.3), c + Vector2(-s * 0.35, s * 0.15), c + Vector2(s * 0.3, s * 0.15), c + Vector2(s * 0.3, s * 0.65)]), col, w * 1.1, true)
			draw_polyline(PackedVector2Array([c + Vector2(s * 0.55, -s * 0.55), c + Vector2(s * 0.8, -s * 0.2), c + Vector2(s * 1.05, -s * 0.55)]), col, w, true)
		"lean_l", "lean_r":   # tilted body leaning away from a wall edge
			var sg := -1.0 if id == "lean_l" else 1.0
			draw_circle(c + Vector2(sg * s * 0.45, -s * 0.6), s * 0.2, col)
			draw_line(c + Vector2(sg * s * 0.3, -s * 0.3), c + Vector2(-sg * s * 0.2, s * 0.7), col, w * 1.4, true)
			draw_line(c + Vector2(sg * s * 0.25, -s * 0.2), c + Vector2(sg * s * 0.8, s * 0.15), col, w, true)
			draw_line(c + Vector2(-sg * s * 0.95, -s * 0.9), c + Vector2(-sg * s * 0.95, s * 0.9), Color(col, 0.6), w * 0.8, true)
		"melee":   # tactical blade
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.85, -s * 0.9), c + Vector2(s * 0.15, 0.0), c + Vector2(-s * 0.05, -s * 0.2)]), col)
			draw_line(c + Vector2(-s * 0.15, -s * 0.05), c + Vector2(s * 0.25, s * 0.35), col, w * 1.3, true)
			draw_line(c + Vector2(0.0, s * 0.15), c + Vector2(-s * 0.7, s * 0.85), col, w * 1.6, true)
		"throwable":   # frag grenade
			draw_circle(c + Vector2(0, s * 0.2), s * 0.62, col)
			draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.65), Vector2(s * 0.4, s * 0.3)), col)
			draw_arc(c + Vector2(s * 0.35, -s * 0.7), s * 0.35, PI, PI * 1.9, 12, col, w * 0.9, true)
		"medkit":   # med cross in a ring
			draw_arc(c, s * 0.95, 0, TAU, 32, col, w * 0.7, true)
			draw_rect(Rect2(c - Vector2(s * 0.18, s * 0.6), Vector2(s * 0.36, s * 1.2)), col)
			draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.18), Vector2(s * 1.2, s * 0.36)), col)
		"inventory":   # backpack
			draw_arc(c + Vector2(0, -s * 0.55), s * 0.35, PI, TAU, 12, col, w, true)
			draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.55), Vector2(s * 1.4, s * 1.5)), col)
			draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.15), Vector2(s * 0.8, s * 0.4)), Color(0.0, 0.0, 0.0, 0.55))
		"dash":   # forward speed chevrons
			for dx in [-0.45, 0.2]:
				var x: float = c.x + s * dx
				draw_polyline(PackedVector2Array([Vector2(x, c.y - s * 0.7), Vector2(x + s * 0.55, c.y), Vector2(x, c.y + s * 0.7)]), col, w * 1.3, true)
		"order":   # flag / command
			draw_line(c + Vector2(-s * 0.5, s * 0.9), c + Vector2(-s * 0.5, -s * 0.9), col, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.9), c + Vector2(s * 0.8, -s * 0.4), c + Vector2(-s * 0.5, s * 0.1)]), col)
		"priority":   # ping beacon
			draw_circle(c, w * 0.9, col)
			draw_arc(c, s * 0.5, 0, TAU, 24, Color(col, 0.85), w * 0.7, true)
			draw_arc(c, s * 0.95, 0, TAU, 32, Color(col, 0.5), w * 0.6, true)
		"cam":   # eye: almond outline + iris + pupil (FPV / third-person switch)
			var eye := PackedVector2Array()
			for i in range(0, 17):
				var t := float(i) / 16.0
				eye.append(c + Vector2(lerpf(-s, s, t), -sin(t * PI) * s * 0.62))
			for i in range(16, -1, -1):
				var t2 := float(i) / 16.0
				eye.append(c + Vector2(lerpf(-s, s, t2), sin(t2 * PI) * s * 0.62))
			draw_polyline(eye, col, w, true)
			draw_arc(c, s * 0.34, 0, TAU, 20, col, w * 0.9, true)
			draw_circle(c, s * 0.14, col)
		_:
			_label(c, id.to_upper().left(3), 12, col)
