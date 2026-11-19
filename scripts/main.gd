## T-MINUS / APOGEX — offline crew match (Godot port).
## Flow: home -> crew select -> build manifest -> Earth build/outfit -> route -> GO/NO-GO -> launch
## -> flight -> the Moon -> return flight -> dock -> deliver -> debrief.
extends Node3D

const SETTINGS_PATH := "user://settings.cfg"
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")

const SFX := ["shot_carbine", "shot_scatter", "shot_sidearm", "hitmarker", "capture_tick", "explosion", "hurt", "shield_recharge", "shield_hit", "shield_break", "reload_click", "reload_ratchet", "step_0", "step_1", "step_2", "step_3"]
const KEY_ACTIONS := {
	KEY_W: "move_forward", KEY_S: "move_back", KEY_A: "move_left", KEY_D: "move_right",
	KEY_SPACE: "jump", KEY_SHIFT: "sprint", KEY_E: "interact", KEY_R: "reload",
	KEY_B: "holster", KEY_Q: "skill", KEY_F: "ultimate", KEY_C: "orders",
	KEY_Z: "ping", KEY_M: "tactical_map", KEY_V: "camera_view", KEY_T: "depart",
	KEY_G: "drop_flag", KEY_H: "help", KEY_1: "role_1", KEY_2: "role_2",
	KEY_3: "role_3", KEY_4: "role_4",
}
const GAMEPAD_BUTTONS := {
	"jump": JOY_BUTTON_A, "interact": JOY_BUTTON_X, "reload": JOY_BUTTON_B,
	"holster": JOY_BUTTON_Y, "skill": JOY_BUTTON_LEFT_SHOULDER, "ultimate": JOY_BUTTON_RIGHT_SHOULDER,
}
var _rebound_actions := {}

var sim: Sim
var opts := {"difficulty": "standard", "length": "standard", "fast": false, "selected": 3, "upgrades": []}
var picker: Control
var mode := "menu"            # menu | play | route | gonogo | cine | paused | debrief
var paused_from := ""
var menu_layer: CanvasLayer
var menu_root: Control
var hud_layer: CanvasLayer
var hud: Hud
var world = null
var cam: Camera3D
var yaw := 0.0
var pitch := -0.2
var first_person := false
var sens := 1.0
var settings_path := SETTINGS_PATH
var graphics := GraphicsSettings.new()
var _graphics_applying := false
var _graphics_pending := false
var _graphics_display_pending := false
var _graphics_save_pending := false
var graphics_open := false
var graphics_buttons := {}
var fps_counter: Label
var autotest := false
var pressed_now := {}
var lmb := false
var touch_pressed := {}
const TOUCH_ACTION_KEYS := {"jump": KEY_SPACE, "interact": KEY_E, "reload": KEY_R, "weapon": KEY_B, "map": KEY_M, "order": KEY_C, "priority": KEY_Z, "dash": KEY_ALT}
var rmb := false
var wheel := 0
var event_index := 0
var cine := {"kind": "", "t": 0.0, "dur": 0.0}
var launch_tick_usec := 0
var ff := 1.0
var players: Array = []
var players_3d: Array = []
var ambient_player: AudioStreamPlayer
var _ambient_kind := ""
var master_volume_db := 0.0
var streams := {}
var chosen_route := "balanced"
var showcase = null
var universe: Universe          # one persistent scene: Earth, space, the Moon
var world_a: PlanetA
var world_b: PlanetB
var ad_runner
var runner: Autotest
var sp_mission := "orbital"
var sp_design := {"battery": "reserve", "array": "standard", "instrument": "camera", "radio": "standard"}
var campaign: Campaign = null
var mc_plan := {}
var mc_state := {}
var mc_policy := "balanced"


func _ready() -> void:
	randomize()
	_setup_input_map()
	var stats_layer := CanvasLayer.new()
	stats_layer.layer = 11
	add_child(stats_layer)
	fps_counter = UI.label("", 14, Color.WHITE)
	fps_counter.position = Vector2(12, 8)
	fps_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_counter.add_theme_color_override("font_shadow_color", Color.BLACK)
	fps_counter.add_theme_constant_override("shadow_offset_y", 1)
	stats_layer.add_child(fps_counter)
	_load_settings()
	# Editor-visible camera. Its FOV and clipping range can now be adjusted visually.
	cam = get_node("GameCamera") as Camera3D
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = Hud.new()
	hud.visible = false
	hud_layer.add_child(hud)
	hud.mobile_controls.action_pressed.connect(_on_touch_action)
	for n in SFX:
		for ext in ["ogg", "wav"]:
			var path := "res://assets/audio/%s.%s" % [n, ext]
			if ResourceLoader.exists(path):
				streams[n] = load(path)
				break
	var gen_streams := SfxGen.build_all()
	for k in gen_streams:
		if not streams.has(k):
			streams[k] = gen_streams[k]
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		players.append(p)
		var p3 := AudioStreamPlayer3D.new()
		p3.volume_db = -4.0
		p3.max_distance = 95.0
		p3.unit_size = 14.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		players_3d.append(p3)
	ambient_player = AudioStreamPlayer.new()
	ambient_player.volume_db = -18.0
	add_child(ambient_player)
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	show_home()
	if args.has("--demo-ff"):
		_select_graphics_preset(3)
		DisplayServer.window_move_to_foreground()
		autotest = true
		Engine.time_scale = 3.0
		runner = Autotest.new()
		runner.run_demo(self)
	elif args.has("--ad"):
		autotest = true
		ad_runner = preload("res://scripts/ad_capture.gd").new()
		ad_runner.run(self)
	elif args.has("--autotest-launch"):
		autotest = true
		runner = Autotest.new()
		runner.run_launch(self)
	elif args.has("--autotest-mc"):
		autotest = true
		runner = Autotest.new()
		runner.run_mc(self)
	elif args.has("--autotest-sp"):
		autotest = true
		runner = Autotest.new()
		runner.run_sp(self)
	elif autotest:
		runner = Autotest.new()
		runner.run(self)


# ============================================================================
# Utilities
# ============================================================================
func _update_ambient() -> void:
	if ambient_player == null:
		return
	var want := ""
	if not autotest and mode == "play" and sim != null:
		match sim.phase:
			"flight": want = "ambient_flight"
			"surface": want = "ambient_moon"
			_: want = "ambient_earth"
	if want == _ambient_kind:
		return
	_ambient_kind = want
	if want == "" or not streams.has(want):
		if ambient_player.playing:
			ambient_player.stop()
		return
	ambient_player.stream = streams[want]
	ambient_player.play()


func sfx(name: String, vol := -8.0, pitch_var := 0.08) -> void:
	if not streams.has(name):
		return
	for p in players:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = vol + master_volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return


func sfx_3d(name: String, world_pos: Vector3, vol := -4.0, pitch_var := 0.08) -> void:
	if autotest or not streams.has(name):
		return
	for p in players_3d:
		if not p.playing:
			p.global_position = world_pos
			p.stream = streams[name]
			p.volume_db = vol + master_volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return
	sfx(name, vol - 4.0, pitch_var)


func _setup_input_map() -> void:
	for key in KEY_ACTIONS:
		var action: String = KEY_ACTIONS[key]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.keycode = key
			InputMap.action_add_event(action, ev)
		if GAMEPAD_BUTTONS.has(action):
			var has_joy := false
			for e in InputMap.action_get_events(action):
				if e is InputEventJoypadButton:
					has_joy = true
					break
			if not has_joy:
				var j := InputEventJoypadButton.new()
				j.button_index = GAMEPAD_BUTTONS[action]
				InputMap.action_add_event(action, j)


func rebind_action(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action).duplicate():
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var key_ev := InputEventKey.new()
	key_ev.keycode = keycode
	InputMap.action_add_event(action, key_ev)
	_rebound_actions[action] = keycode


func _on_touch_action(action_name: String) -> void:
	if TOUCH_ACTION_KEYS.has(action_name):
		touch_pressed[TOUCH_ACTION_KEYS[action_name]] = true


func touch_ui() -> MobileControls:
	return hud.mobile_controls if hud != null and hud.touch_ui_visible() else null


func pressed(key: int) -> bool:
	if touch_pressed.has(key):
		return true
	var action: String = KEY_ACTIONS.get(key, "")
	if pressed_now.has(key) and not _rebound_actions.has(action):
		return true
	if action != "" and InputMap.has_action(action):
		return Input.is_action_just_pressed(action)
	return pressed_now.has(key)


func held(key: int) -> bool:
	var t := touch_ui()
	if t != null:
		var mv := t.move_vector()
		if (key == KEY_SHIFT and t.is_sprinting()) or (key == KEY_W and mv.y < -0.5) \
				or (key == KEY_S and mv.y > 0.5) or (key == KEY_A and mv.x < -0.5) or (key == KEY_D and mv.x > 0.5):
			return true
	var action: String = KEY_ACTIONS.get(key, "")
	if action != "" and InputMap.has_action(action):
		if _rebound_actions.has(action):
			return Input.is_action_pressed(action)
		return Input.is_action_pressed(action) or Input.is_key_pressed(key)
	return Input.is_key_pressed(key)


func set_world(w: Node3D) -> void:
	var managed: bool = universe != null and is_instance_valid(universe) and w != null and w.get_parent() == universe
	if world and is_instance_valid(world) and world != w:
		# Planets persist inside the universe; only flights and non-universe scenes are retired.
		if world is Flight or world.get_parent() != universe:
			world.queue_free()
	if not managed:
		drop_universe()
	world = w
	if w and w.get_parent() == null:
		add_child(w)
	if is_instance_valid(world):
		graphics.apply_scene(world)


func ensure_universe() -> void:
	if universe == null or not is_instance_valid(universe):
		universe = Universe.new()
		add_child(universe)
		universe.setup(self)
		graphics.apply_scene(universe)
		universe.apply_quality(graphics)


func drop_universe() -> void:
	for p in players_3d:
		if is_instance_valid(p):
			p.stop()
	if universe != null and is_instance_valid(universe):
		universe.queue_free()
	universe = null
	world_a = null
	world_b = null


## Puts a world into the universe at `xf` and makes it the active one without any scene swap.
func enter_world(w: Node3D, xf: Transform3D) -> void:
	ensure_universe()
	if w.get_parent() == null:
		universe.add_child(w)
	w.transform = xf
	universe.focus_xf(xf)
	set_world(w)


func clear_menu() -> void:
	graphics_open = false
	graphics_buttons.clear()
	if hud: hud.close_tactical()
	if menu_root:
		menu_root.queue_free()
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = UI.theme()
	menu_layer.add_child(menu_root)


func capture_mouse(on: bool) -> void:
	if not on:
		lmb = false
		rmb = false
	if autotest:
		return
	if on and touch_ui() != null:
		return   # touch mode keeps the cursor free for the on-screen controls
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func cam_forward() -> Vector3:
	return -cam.global_transform.basis.z


func player_actor() -> Actor:
	if world and world.has_method("actor"):
		return world.actor(sim.selected)
	return null


# ============================================================================
# Input
# ============================================================================
func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.keycode == KEY_F9 and e.pressed and not e.echo:
		toggle_touch_ui()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.keycode == KEY_F5 and e.pressed and not e.echo:
		match Engine.time_scale:
			1.0: ff = 2.0
			2.0: ff = 4.0
			4.0: ff = 8.0
			_: ff = 1.0
		Engine.time_scale = ff
		hud.toast("FAST FORWARD · %d×" % int(ff), 1.5)
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if is_instance_valid(picker): return
	if e is InputEventKey and e.pressed and not e.echo:
		pressed_now[e.keycode] = true
		if e.keycode == KEY_ESCAPE:
			if graphics_open:
				_close_graphics()
			elif mode == "play" or mode == "cine":
				pause()
			elif mode == "paused":
				resume()
		if mode == "cine" and (e.keycode == KEY_ENTER or e.keycode == KEY_SPACE) and cine["kind"] == "intro":
			cine["t"] = cine["dur"]
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.0026 * sens
		pitch = clampf(pitch - e.relative.y * 0.0022 * sens, -1.25, 0.95)
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			lmb = e.pressed
			if e.pressed and mode == "play" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				capture_mouse(true)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			rmb = e.pressed
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel += 1
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel -= 1


func toggle_touch_ui() -> void:
	var on := not hud.touch_ui_visible()
	hud.set_touch_ui(on)
	lmb = false
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif mode == "play" and not autotest:
		capture_mouse(true)
	hud.toast("TOUCH CONTROLS %s · F9" % ("ON" if on else "OFF"), 1.4)


func _tick_touch() -> void:
	hud.mobile_controls.set_active(mode == "play" and not is_instance_valid(picker))
	var t := touch_ui()
	if t == null:
		return
	var d := t.consume_look_delta()
	if d != Vector2.ZERO:
		yaw -= d.x * 0.0052 * sens
		pitch = clampf(pitch - d.y * 0.0044 * sens, -1.25, 0.95)
	lmb = t.is_firing()


func _process(dt: float) -> void:
	_update_ambient()
	_tick_touch()
	if is_instance_valid(fps_counter) and fps_counter.visible:
		var fps := Engine.get_frames_per_second()
		var caption := "%d FPS · %.1f ms" % [fps, 1000.0 / maxf(1.0, fps)]
		if fps_counter.text != caption:
			fps_counter.text = caption
	var frame_dt := dt
	# Limit wall-clock frame spikes without flattening the selected play speed.
	dt = minf(dt, 0.05 * (ff if ff == Engine.time_scale else 1.0))
	hud.tick(dt)
	if is_instance_valid(picker):
		pressed_now.clear()
		touch_pressed.clear()
		return
	if universe != null and is_instance_valid(universe):
		universe.tick(dt)
	if showcase and is_instance_valid(showcase) and showcase.has_method("tick"):
		showcase.tick(dt)
	match mode:
		"play":
			_play_common(dt)
			if world and world.has_method("tick"):
				world.tick(dt)
			if sim != null:
				_tick_sim(dt)
			elif world and world.has_method("hud_update"):
				world.hud_update(hud)
			if mode == "play" and pad_sequence_active():
				_tick_cine(dt)
		"route", "gonogo":
			# Flight plan is opened at the pad desk: the world keeps running behind it.
			if world and world.has_method("tick"):
				world.tick(dt)
			_tick_sim(dt)
		"cine":
			if cine["kind"] == "launch":
				if ad_runner != null:
					# Movie Maker advances on its fixed frame clock.
					_tick_cine(frame_dt / Engine.time_scale)
				else:
					_tick_launch(Time.get_ticks_usec())
			else:
				_tick_cine(dt)
			_tick_sim(dt)
	pressed_now.clear()
	touch_pressed.clear()
	wheel = 0


func _tick_sim(dt: float) -> void:
	if sim == null:
		return
	# Manual fast-forward is already applied to dt by the engine.
	var steps := 1 if ff == Engine.time_scale else int(ff)
	for i in maxi(1, steps):
		sim.tick_rivals(dt)
	if mode == "play" or mode == "cine" or mode == "route" or mode == "gonogo":
		_refresh_hud()
	while event_index < sim.events.size():
		var ev = sim.events[event_index]
		event_index += 1
		hud.toast(ev["text"])
	if sim.over and mode != "debrief":
		show_debrief()


func _play_common(dt: float) -> void:
	if sim != null and pressed(KEY_M):
		hud.toggle_tactical()
	if sim == null:
		if pressed(KEY_V):
			first_person = not first_person
		return
	for i in 4:
		if pressed(KEY_1 + i) and sim.phase != "spectator":
			if sim.selected != i:
				sim.selected = i
				hud.toast("Now playing %s / %s" % [Sim.SPECIALISTS[i]["name"], Sim.SPECIALISTS[i]["role"]], 1.8)
				if world and world.has_method("on_role_changed"):
					world.on_role_changed()
	if pressed(KEY_V):
		first_person = not first_person
	if pressed(KEY_H):
		show_help()


func _refresh_hud() -> void:
	hud.update_common(sim, sim.selected)
	if world and world.has_method("hud_update"):
		world.hud_update(hud)
	if sim.phase in ["surface", "flight"]: hud.vitals_panel.visible = false


# ============================================================================
# Shared character control + camera
# ============================================================================
func drive(a: Actor, dt: float, gravity := 22.0, speed_mul := 1.0) -> float:
	if mode == "route" or mode == "gonogo":
		return 0.0   # plan panel open: crew stands by
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := Vector3.ZERO
	var tmv := touch_ui().move_vector() if touch_ui() != null else Vector2.ZERO
	if tmv != Vector2.ZERO:
		# Analog thumbstick: direction and magnitude both carry through.
		dir = (f * -tmv.y + r * tmv.x).limit_length(1.0)
	else:
		if held(KEY_W): dir += f
		if held(KEY_S): dir -= f
		if held(KEY_D): dir += r
		if held(KEY_A): dir -= r
		if dir.length() > 0.0:
			dir = dir.normalized()
	var speed := (8.4 if held(KEY_SHIFT) else 5.4) * speed_mul
	a.tick_motion(dt)
	if pressed(KEY_ALT) and sim != null and sim.phase == "surface":
		if a.trigger_dash(dir):
			sfx("reload_click", -4.0, 0.15)
			hud.toast("DASH", 0.5)
	if a.dash_active():
		a.move_vel = a.dash_dir * Actor.DASH_SPEED
	else:
		var want := dir * speed
		var rate := Actor.ACCEL if want.length() > a.move_vel.length() * 0.98 or want.length() > 0.01 else Actor.DECEL
		a.move_vel = a.move_vel.move_toward(want, rate * dt)
	a.position += a.move_vel * dt
	var grounded := a.position.y <= 0.001
	if grounded:
		a.coyote_t = Actor.COYOTE_TIME
	if pressed(KEY_SPACE):
		a.jump_buf_t = Actor.JUMP_BUFFER_TIME
	if a.jump_buf_t > 0.0 and (grounded or a.coyote_t > 0.0) and a.vy <= 0.001:
		a.vy = 8.0
		a.jump_buf_t = 0.0
		a.coyote_t = 0.0
	a.vy -= gravity * dt
	a.position.y = maxf(0.0, a.position.y + a.vy * dt)
	if a.position.y <= 0.0:
		a.vy = 0.0
	if world and world.has_method("collide"):
		a.position = world.collide(a.position)
	if first_person:
		a.heading = yaw
		a.rotation.y = yaw
	elif dir.length() > 0.0:
		a.face(dir, dt, 12.0)
	return Vector2(a.move_vel.x, a.move_vel.z).length()


func follow_cam(a: Actor, dist := 6.8) -> void:
	cam.rotation = Vector3(pitch, yaw, 0)
	var fwd := -cam.transform.basis.z
	var holder: Node3D = a.get_node("Holder")
	if first_person:
		holder.visible = false
		cam.position = a.position + Vector3(0, a.visual_height * 0.9, 0) + Vector3(-sin(yaw), 0, -cos(yaw)) * 0.35
	else:
		holder.visible = true
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var target := a.position + Vector3(0, a.visual_height * 0.9 + 0.15, 0) + right * 0.6
		var p := target - fwd * dist
		p.y = maxf(p.y, 0.5)
		if world and world.has_method("camera_position"): p = world.camera_position(target, p)
		cam.position = p


## Distance from a point to an axis-aligned footprint on the ground plane.
static func footprint_distance(p: Vector3, center: Vector3, dims: Vector3) -> float:
	var dx := maxf(absf(p.x - center.x) - dims.x * 0.5, 0.0)
	var dz := maxf(absf(p.z - center.z) - dims.z * 0.5, 0.0)
	return Vector2(dx, dz).length()


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ============================================================================
# Match lifecycle
# ============================================================================
func new_sim() -> void:
	sim = Sim.new(int(opts.get("seed", 0)), opts["difficulty"], opts["length"])
	sim.selected = opts["selected"]
	for id in opts["upgrades"]:
		sim.set_upgrade(id, true)
	event_index = 0
	if ff != Engine.time_scale:
		ff = 1.0


func start_match() -> void:
	if sim == null:
		new_sim()
	sim.selected = opts["selected"]
	sim.auto_build["enabled"] = opts["fast"]
	sim.shop_open = not sim.all_parts_bought()   # modules are bought in the 3D parts shop
	clear_menu()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	showcase = null
	drop_universe()
	ensure_universe()
	var a := PlanetA.new()
	world_a = a
	a.setup(self, false)
	enter_world(a, Transform3D.IDENTITY)
	hud.visible = true
	hud.set_mode(false)
	yaw = PI * 0.15
	pitch = -0.25
	begin_cine("intro", 4.0)


func quick_deploy() -> void:
	new_sim()
	sim.quick_deploy = true
	for p in sim.parts:
		sim.buy_part(p["id"])
	sim.shop_open = false
	sim.auto_build["enabled"] = true
	sim.auto_assemble(Sim.AUTO_BUILD_SECONDS)
	sim.auto_outfit()
	chosen_route = "balanced"
	if not sim.launch_flight(chosen_route):
		chosen_route = "sheltered"
		if not sim.launch_flight(chosen_route):
			show_manifest()
			return
	# Every crew starts the transfer together: no free head start for skipping construction.
	for i in range(1, 4):
		var team = sim.teams[i]
		team["phase"] = "outbound"
		team["planet"] = "space"
		team["phase_time"] = 0.0
		team["travel_duration"] = sim.flight_duration() + float(i - 2) * 5.0
	clear_menu()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	showcase = null
	drop_universe()
	ensure_universe()
	world_a = PlanetA.new()
	world_a.setup(self, false)
	world_a.ship_root.visible = false
	universe.add_child(world_a)
	hud.visible = true
	hud.set_mode(false)
	_begin_flight(Transform3D(Basis.IDENTITY, Vector3(0, 900, -150) - Flight.SHIP_OFFSET))
	hud.toast("QUICK DEPLOY · All four crews launched. Build and checks completed by the ground crew.", 5.0)


func rematch() -> void:
	var seed_value: int = sim.match_seed
	var quick: bool = sim.quick_deploy
	opts["seed"] = seed_value
	if quick: quick_deploy()
	else: new_sim(); start_match()
	opts["seed"] = 0


func pad_sequence_active() -> bool:
	return cine.get("pad", false)


func begin_cine(kind: String, dur: float) -> void:
	var pad := kind in ["build", "outfit", "erect", "boosters"]
	if pad and pad_sequence_active():
		return
	cine = {"kind": kind, "t": 0.0, "dur": dur, "pad": pad}
	if not pad:
		mode = "cine"
		capture_mouse(false)
		hud.set_prompt("")
	match kind:
		"intro":
			var s = Sim.SPECIALISTS[sim.selected]
			hud.show_banner("%s / %s" % [s["name"], s["role"]], "Walk to the PARTS SHOP. Choose and confirm a variant for all 12 slots.", dur)
		"build", "outfit", "erect", "boosters":
			pass   # silent machine sequences: no centre-screen text
		"launch":
			launch_tick_usec = Time.get_ticks_usec()
			hud.show_banner("%s: LAUNCHING" % Sim.FACTIONS[0]["name"], sim.route["name"].to_upper(), dur)
		"landing":
			hud.show_banner("MOON", "Capture the frontier. Only delivered flags score.", dur)
		"docking":
			hud.show_banner("EARTH", "Bring it home. Deliver every flag on board.", dur)


func _tick_launch(now_usec: int) -> void:
	# Use the launch wall clock, with the speed chosen through the play control.
	var elapsed := (now_usec - launch_tick_usec) / 1000000.0
	launch_tick_usec = now_usec
	_tick_cine(elapsed * (ff if ff == Engine.time_scale else 1.0))


func _tick_cine(dt: float) -> void:
	cine["t"] += dt
	var k: float = clampf(cine["t"] / cine["dur"], 0.0, 1.0)
	if world and world.has_method("cine"):
		world.cine(cine["kind"], k, dt)
	if cine["t"] >= cine["dur"]:
		_end_cine(cine["kind"])


func _end_cine(kind: String) -> void:
	if kind in ["build", "outfit", "erect", "boosters"]:
		cine.clear()
	match kind:
		"build":
			world.pad_stage = "outfit"
			begin_cine("outfit", 6.5)
		"outfit":
			sim.auto_outfit()
			world.pad_stage = "erect_wait"
		"erect":
			world.pad_stage = "boosters"
			begin_cine("boosters", 7.0)
		"boosters":
			world._fx_finish()
			world.pad_stage = "ready"
		"intro":
			mode = "play"
			capture_mouse(true)
		"launch":
			# The Flight picks up exactly where the pad ascent ends: same ship, camera and sky.
			var ref: Vector3 = world_a.ship_root.position
			world_a.ship_root.visible = false
			for bd in world_a.fx_boosters:
				(bd["node"] as Node3D).visible = false
			_begin_flight(Transform3D(Basis.IDENTITY, ref - Flight.SHIP_OFFSET))
		"landing":
			sim.phase = "surface"
			sim.teams[0]["phase"] = "surface"
			sim.teams[0]["planet"] = "B"
			sim.teams[0]["phase_time"] = 0.0
			world_b.arrive()
			enter_world(world_b, Transform3D(Basis.IDENTITY, Universe.B_ORIGIN))
			mode = "play"
			capture_mouse(true)
			hud.show_banner("CAPTURE THE FRONTIER.", "Raider: hold LMB at a flag · E load at ship · T depart", 3.0)
		"docking":
			sim.phase = "delivery"
			world_a.arrive_home()
			enter_world(world_a, Transform3D(Basis.IDENTITY, Universe.A_ORIGIN))
			mode = "play"
			capture_mouse(true)
			hud.show_banner("BRING IT HOME.", "Hold E on the delivery pad", 3.0)


func _begin_flight(start: Transform3D) -> void:
	ensure_universe()
	if sim.flight_leg == "outbound" and world_b == null:
		world_b = PlanetB.new()
		world_b.setup(self)
		world_b.position = Universe.B_ORIGIN
		universe.add_child(world_b)
		world_b.hide_ship()
	var f := Flight.new()
	f.setup(self, start)
	universe.add_child(f)
	universe.focus_xf(start)
	set_world(f)
	mode = "play"
	capture_mouse(true)
	hud.show_banner("FLY. DEFEND. KEEP IT ALIVE.", "1 Pilot · 2 Engineer · 3 Gunner · 4 Raider", 3.0)


## Offline competitive launch: same staged ascent as the single-player pad, then on to the flight.
func competitive_launch_finished() -> void:
	_begin_flight(Transform3D(Basis.IDENTITY, Vector3(0, 900, -150) - Flight.SHIP_OFFSET))


func on_route_ready() -> void:
	mode = "route"
	capture_mouse(false)
	show_route()


func launch() -> void:
	if not sim.launch_flight(chosen_route):
		hud.toast("Route is NO-GO: not enough propellant.")
		return
	clear_menu()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Launch the spacecraft that was built and outfitted on the Earth pad (no separate scene).
	if world is PlanetA:
		begin_cine("launch", PlanetA.LAUNCH_DURATION)
	else:
		_begin_flight(Transform3D(Basis.IDENTITY, Vector3(0, 900, -150) - Flight.SHIP_OFFSET))


func flight_finished(result: String) -> void:
	match result:
		"landing":
			begin_cine("landing", 9.0)
		"docking":
			begin_cine("docking", 9.0)
		"lost":
			hud.show_banner("CREW LOST", "Return reserve exhausted.", 4.0)
			sim.phase = "spectator"
			ff = 12.0


func depart_planet_b() -> void:
	if not sim.depart_frontier(0):
		return
	sim.flight_leg = "return"
	sim.phase = "flight"
	sim.flight_time = 0.0
	# The ship lifts off the the Moon pad where it stands: its pad model becomes the flying ship.
	world_b.hide_ship()
	_begin_flight(Transform3D(Basis.IDENTITY, Universe.B_ORIGIN + Flight.B_LAND - Flight.SHIP_OFFSET))
	hud.show_banner("BRING IT HOME.", "Return leg · 60 s", 2.5)


func crew_eliminated() -> void:
	hud.show_banner("CREW ELIMINATED", "Ship destroyed. Flags on board are exposed. F5 fast-forwards.", 5.0)
	sim.phase = "spectator"


# ============================================================================
# Menus
# ============================================================================
func _ensure_showcase() -> void:
	if showcase == null or not is_instance_valid(showcase):
		showcase = PlanetA.showcase(self)
		set_world(showcase)


func show_home() -> void:
	mode = "menu"
	hud.visible = false
	capture_mouse(false)
	sim = null
	campaign = null
	_ensure_showcase()
	showcase.layout("home", opts["selected"])
	clear_menu()
	var root := UI.vbox(14)
	root.position = Vector2(56, 120)
	root.custom_minimum_size = Vector2(620, 0)
	menu_root.add_child(root)
	_brand(menu_root)
	root.add_child(UI.label("OFFLINE / 1 PLAYER + 15 BOTS / 16/16 READY", 12, UI.ACCENT))
	root.add_child(UI.heading("BUILD. CAPTURE.\n", "BRING IT HOME.", 66))
	root.add_child(UI.label("Build on Earth. Capture twelve finite Science Flags on the Moon.\nOnly flags delivered home score. Ship destruction eliminates your crew.", 15, UI.MUTED))
	root.add_child(UI.spacer(8))
	root.add_child(UI.button("SINGLE PLAYER CAMPAIGN   ↗", show_campaign, true, 520, 54))
	root.add_child(UI.button("COMPETITIVE / OFFLINE PRACTICE   ↗", show_select, false, 520))
	root.add_child(UI.button("MISSION DESIGN & SCIENCE SIMULATOR   ↗", show_mission_control, false, 520))
	root.add_child(UI.button("FIELD MANUAL   ↗", show_help, false, 520))
	root.add_child(UI.button("SETTINGS", show_settings, false, 520))
	root.add_child(UI.button("QUIT", get_tree().quit, false, 520))
	root.add_child(UI.spacer(10))
	root.add_child(UI.label("●  1 HUMAN + 15 CLEARLY MARKED BOTS   ·   3 AI RIVAL TEAMS", 11, UI.MUTED))
	var s = Sim.SPECIALISTS[opts["selected"]]
	var feat := UI.vbox(2)
	feat.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	feat.position = Vector2(-520, -230)
	feat.custom_minimum_size = Vector2(480, 0)
	menu_root.add_child(feat)
	feat.add_child(UI.label("FEATURED SPECIALIST", 11, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	feat.add_child(UI.label(s["name"], 64, Color("#f2e6d8"), HORIZONTAL_ALIGNMENT_RIGHT))
	feat.add_child(UI.label(s["role"], 13, UI.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT))
	var d := UI.label(s["description"], 13, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feat.add_child(d)
	_footer()


func _brand(parent: Control) -> void:
	var b := UI.rich("[b]APOG[color=#eaa665]EX[/color][/b]", 30)
	b.position = Vector2(40, 26)
	b.size = Vector2(300, 44)
	parent.add_child(b)
	var sub := UI.label("T-MINUS · THE FIRST FRONTIER", 10, UI.MUTED)
	sub.position = Vector2(42, 66)
	parent.add_child(sub)


func _footer() -> void:
	var f := UI.label("T-MINUS / GODOT PORT OF BUILD 5.7.0", 10, UI.DIM)
	f.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	f.position = Vector2(40, -34)
	menu_root.add_child(f)
	var g := UI.label("ONLY DELIVERED FLAGS SCORE.", 10, UI.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	g.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	g.position = Vector2(-340, -34)
	g.size = Vector2(300, 20)
	menu_root.add_child(g)


var _lobby_countdown_tween: Tween
var _lobby_play_btn: Button
var _lobby_ready_labels: Array = []


func _cancel_lobby_countdown() -> void:
	if _lobby_countdown_tween != null and _lobby_countdown_tween.is_valid():
		_lobby_countdown_tween.kill()
	_lobby_countdown_tween = null
	if is_instance_valid(_lobby_play_btn):
		_lobby_play_btn.text = "PLAY  ·  %s" % Sim.SPECIALISTS[opts["selected"]]["name"]


func _toggle_lobby_countdown() -> void:
	if _lobby_countdown_tween != null and _lobby_countdown_tween.is_valid():
		_cancel_lobby_countdown()
		sfx("ui_click", -10.0)
		return
	if not is_instance_valid(_lobby_play_btn):
		show_loading_briefing()
		return
	sfx("ui_buy", -8.0)
	_lobby_countdown_tween = create_tween()
	for sec in [5, 4, 3, 2, 1, 0]:
		var s_val: int = sec
		_lobby_countdown_tween.tween_callback(func() -> void:
			if not is_instance_valid(_lobby_play_btn):
				return
			_lobby_play_btn.text = "STARTING IN %d  (CANCEL)" % s_val if s_val > 0 else "LAUNCHING  0..."
			sfx("ui_click", -8.0, 0.04)
			var ready_idx := 5 - s_val
			if ready_idx >= 0 and ready_idx < _lobby_ready_labels.size() and is_instance_valid(_lobby_ready_labels[ready_idx]):
				(_lobby_ready_labels[ready_idx] as Label).text = "✓ READY"
				(_lobby_ready_labels[ready_idx] as Label).add_theme_color_override("font_color", Color("#86efac"))
		)
		_lobby_countdown_tween.tween_interval(1.0 if s_val > 0 else 0.35)
	_lobby_countdown_tween.tween_callback(show_loading_briefing)


func show_select() -> void:
	_cancel_lobby_countdown()
	_lobby_ready_labels.clear()
	mode = "menu"
	_ensure_showcase()
	showcase.layout("select", opts["selected"])
	clear_menu()
	_brand(menu_root)
	var head := UI.vbox(2)
	head.position = Vector2(36, 74)
	menu_root.add_child(head)
	head.add_child(UI.label("SQUAD LOBBY · 16/16 PLAYERS · CLICK A BANNER TO SWITCH SPECIALIST", 11, Color("#ffe066")))

	# Fortnite-style 4 vertical colored squad banners across the lobby.
	var banners := UI.hbox(14)
	banners.position = Vector2(40, 114)
	menu_root.add_child(banners)
	var banner_colors := [Color("#ec4899"), Color("#84cc16"), Color("#0ea5e9"), Color("#475569")]
	for i in 4:
		var s = Sim.SPECIALISTS[i]
		var selected: bool = i == int(opts["selected"])
		var bc: Color = banner_colors[i]
		var p := UI.panel(Vector2(210, 112), Color(bc.r, bc.g, bc.b, 0.88 if selected else 0.62))
		p.add_theme_stylebox_override("panel", UI.style(
			Color(bc.r, bc.g, bc.b, 0.86 if selected else 0.56),
			Color("#ffe066") if selected else Color(1, 1, 1, 0.25), 6, 10, 3 if selected else 1
		))
		var v := UI.vbox(3)
		p.add_child(v)
		v.add_child(UI.label(("★ " if selected else "") + s["name"], 18, Color.WHITE))
		var rl := UI.label("✓ READY" if selected else "Standby · Bot", 11, Color("#fef08a") if selected else Color(1, 1, 1, 0.82))
		v.add_child(rl)
		_lobby_ready_labels.append(rl)
		v.add_child(UI.label(s["role"], 10, Color(1, 1, 1, 0.78)))
		var idx := i
		v.add_child(UI.button("SELECTED ✓" if selected else "SELECT", _set_opt.bind("selected", idx), false, 0, 26))
		banners.add_child(p)

	# Right column: Squads + Match Options + bright Fortnite PLAY button with 5->0 countdown.
	var right := UI.panel(Vector2(310, 0), Color(0.08, 0.14, 0.28, 0.82))
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-340, 74)
	menu_root.add_child(right)
	var rv := UI.vbox(7)
	right.add_child(rv)
	rv.add_child(UI.label("SQUADS · 4v4v4v4 SPACE RACE", 12, Color("#ffe066")))
	for t in range(1, 4):
		var row := UI.hbox(6)
		row.add_child(UI.label("● " + Sim.FACTIONS[t]["name"], 12, Sim.faction_color(t)))
		row.add_child(UI.spacer(0, 0, true))
		row.add_child(UI.label("READY", 10, Color("#86efac")))
		rv.add_child(row)
	rv.add_child(UI.label("DIFFICULTY", 10, UI.MUTED))
	var dh := UI.hbox(5)
	for k in ["cadet", "standard", "expert"]:
		var key: String = k
		dh.add_child(UI.toggle(Sim.DIFFICULTY[k]["label"], opts["difficulty"] == k, _set_opt.bind("difficulty", key), 86))
	rv.add_child(dh)
	rv.add_child(UI.label("MATCH LENGTH", 10, UI.MUTED))
	var lh := UI.hbox(5)
	for k in ["short", "standard", "long"]:
		var key: String = k
		lh.add_child(UI.toggle(Sim.LENGTHS[k]["label"].replace(" MIN", "M"), opts["length"] == k, _set_opt.bind("length", key), 86))
	rv.add_child(lh)
	rv.add_child(UI.button("QUICK DEPLOY (SKIP TO FLIGHT)", quick_deploy, false, 280, 32))
	rv.add_child(UI.button("ASSIGN BUILD PARTS", show_manifest, false, 280, 30))

	# Big Fortnite-style yellow PLAY button with 5->0 countdown.
	var bottom := UI.hbox(10)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom.position = Vector2(-470, -104)
	menu_root.add_child(bottom)
	bottom.add_child(UI.button("BACK", show_home, false, 110, 56))
	_lobby_play_btn = UI.button("PLAY  ·  %s" % Sim.SPECIALISTS[opts["selected"]]["name"], _toggle_lobby_countdown, true, 320, 56)
	var play_sb := StyleBoxFlat.new()
	play_sb.bg_color = Color("#facc15")
	play_sb.set_corner_radius_all(6)
	play_sb.content_margin_left = 14
	play_sb.content_margin_right = 14
	_lobby_play_btn.add_theme_stylebox_override("normal", play_sb)
	_lobby_play_btn.add_theme_color_override("font_color", Color("#111827"))
	_lobby_play_btn.add_theme_font_size_override("font_size", 20)
	bottom.add_child(_lobby_play_btn)
	_footer()


func show_loading_briefing() -> void:
	_cancel_lobby_countdown()
	mode = "menu"
	clear_menu()
	sfx("ui_click", -8.0)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.14, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	_brand(menu_root)

	var wrap := UI.vbox(14)
	wrap.set_anchors_preset(Control.PRESET_CENTER)
	wrap.position = Vector2(-540, -280)
	wrap.custom_minimum_size = Vector2(1080, 560)
	menu_root.add_child(wrap)
	wrap.add_child(UI.label("LOADING EXPEDITION · 4-PHASE MISSION GUIDE", 12, Color("#facc15"), HORIZONTAL_ALIGNMENT_CENTER))
	wrap.add_child(UI.heading("THE 4-PHASE ", "SPACE RACE", 36))

	# 4 visual phase cards with real in-game images + "Better Than..." strategy tips.
	var row := UI.hbox(14)
	wrap.add_child(row)
	var phases := [
		["1 · BUILD", "res://shots/sp04_workshop.png", Color("#f59e0b"),
			"Confirm all 12 rocket parts at the white Parts Shop (E), then start assembly at the Desk.",
			"PRO TIP: Using Quick Build is much faster than hand-picking 12 parts on your first match!"],
		["2 · LAUNCH", "res://shots/sp09_liftoff.png", Color("#38bdf8"),
			"Complete the 3 pad checks (E) and blast off into orbit toward the Moon.",
			"PRO TIP: Boosting early out of atmosphere beats slow cruising — watch rival launches!"],
		["3 · CAPTURE", "res://shots/sp11_orbit.png", Color("#34d399"),
			"Press B to draw your weapon, fight rival squads, and escort Fernando [4] to extract Science Flags.",
			"PRO TIP: Using Left Alt Dash to dodge Scattergun fire saves your shield better than backpedaling!"],
		["4 · DELIVER", "res://shots/sp07_stacked.png", Color("#a78bfa"),
			"Load flags up your ship ramp, fly back to Earth, and deliver them to win.",
			"PRO TIP: Delivering 2–3 flags early is safer than hoarding 6 and risking a rival ambush!"],
	]
	for ph in phases:
		var card := UI.panel(Vector2(256, 330), Color(0.09, 0.12, 0.20, 0.94))
		var cv := UI.vbox(8)
		card.add_child(cv)
		cv.add_child(UI.label(ph[0], 14, ph[2]))
		if ResourceLoader.exists(ph[1]):
			var tex := TextureRect.new()
			tex.texture = load(ph[1]) as Texture2D
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex.custom_minimum_size = Vector2(232, 128)
			cv.add_child(tex)
		var desc := UI.wrapped_label(ph[3], 11, UI.TEXT)
		desc.custom_minimum_size.x = 232
		cv.add_child(desc)
		var tip := UI.wrapped_label(ph[4], 11, Color("#fde68a"))
		tip.custom_minimum_size.x = 232
		cv.add_child(tip)
		row.add_child(card)

	var status := UI.label("Syncing launch complex, weather & 16 crew specialists...", 13, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(status)
	var bar := UI.bar(Color("#facc15"), 0.0, 10)
	bar.custom_minimum_size = Vector2(1080, 12)
	wrap.add_child(bar)
	var act := UI.hbox(12)
	act.add_child(UI.label("Controls: WASD Move · Shift Sprint · Alt Dash · Space Jump · E Interact · B Weapon · F9 Touch UI", 11, UI.MUTED))
	act.add_child(UI.spacer(0, 0, true))
	var drop_btn := UI.button("DROP IN NOW   ↗", start_match, true, 220, 38)
	act.add_child(drop_btn)
	wrap.add_child(act)

	var tw := create_tween()
	tw.tween_property(bar, "value", 45.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(status): status.text = "Cryo tanks pressurized · Launch pad clear!"
	)
	tw.tween_property(bar, "value", 100.0, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(status): status.text = "READY! Click DROP IN NOW or wait to deploy..."
	)


func show_manifest() -> void:
	mode = "menu"
	if sim == null:
		new_sim()
	sim.selected = opts["selected"]
	clear_menu()
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.11, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	_brand(menu_root)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 80
	scroll.offset_right = -80
	scroll.offset_top = 96
	scroll.offset_bottom = -20
	menu_root.add_child(scroll)
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UI.label("BUILD MANIFEST / 12 COMPONENTS / 36 FASTENERS", 12, UI.MUTED))
	v.add_child(UI.heading("EVERY MODULE ", "HAS A COST.", 50))
	var intro := UI.label("Assign each part to a specialist. In HANDS-ON mode you pick up, rotate, position and fasten your own modules; AI crew construct theirs. Switch specialists with 1–4. FAST ASSEMBLY builds all parts automatically.", 13, UI.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	v.add_child(UI.label("CREDITS %d / CORE PARTS RESERVED %d" % [sim.credits, sim.reserved_credits()], 14, UI.ACCENT))
	v.add_child(UI.label("More weapons, more cargo, or more reserve — you cannot maximize everything.", 12, UI.MUTED))
	var ups := UI.hbox(12)
	v.add_child(ups)
	for u in Sim.UPGRADES:
		var on: bool = sim.upgrades.has(u["id"])
		var p := UI.panel(Vector2(330, 0))
		var pv := UI.vbox(4)
		p.add_child(pv)
		pv.add_child(UI.label(u["name"], 16, UI.TEXT))
		pv.add_child(UI.label("%d CREDITS · +%d kg · +%.2f kW" % [u["cost"], u["mass"], u["power"]], 11, UI.ACCENT))
		var dsc := UI.label(u["description"], 12, UI.MUTED)
		dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pv.add_child(dsc)
		var id: String = u["id"]
		pv.add_child(UI.toggle("INSTALLED ✓" if on else "BUY OPTION", on, _toggle_upgrade.bind(id), 140))
		ups.add_child(p)
	var ds := sim.design_sheet()
	v.add_child(UI.label(UI.loadout_summary(sim), 13, UI.TEXT))
	v.add_child(UI.label("DRY %d kg + FUEL %d kg = WET %d kg · THRUST %.1f kN · GENERATION %.1f kW vs LOAD %.2f kW · CARGO %d FLAGS" % [ds["dry"], ds["propellant"], ds["wet"], ds["thrust"], ds["generation"], ds["load"], ds["cargo"]], 14, UI.TEXT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var metrics := [
		["Thrust-to-weight · Engine bay", "%.2f" % ds["twr"], ds["twr"] >= Sim.TWR_GO, "≥ 1.25"],
		["Delta-v · Engine bay", "%.1f m/s" % ds["dv"], ds["dv"] >= 215.0, "≥ 215"],
		["Power margin · Power room", "%.1f kW" % ds["power_margin"], ds["power_margin"] >= 1.0, "≥ 1.0"],
	]
	for m in metrics:
		var p := UI.panel(Vector2(330, 0))
		var h := UI.hbox(6)
		p.add_child(h)
		var mv := UI.vbox(2)
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mv.add_child(UI.label(m[0], 12, UI.MUTED))
		mv.add_child(UI.label(("GO · " if m[2] else "NO-GO · ") + m[3], 11, UI.GOOD if m[2] else UI.BAD))
		h.add_child(mv)
		h.add_child(UI.label(m[1], 20, UI.TEXT))
		grid.add_child(p)
	v.add_child(UI.label("PART ASSIGNMENTS", 12, UI.MUTED))
	for p in sim.parts:
		var row := UI.hbox(8)
		var nm := UI.label("%s · %d CREDITS" % [ShipCatalog.variant(p["id"], str(sim.loadout.get(p["id"], "kestrel")))["name"], p["price"]], 13, UI.TEXT)
		nm.custom_minimum_size = Vector2(360, 0)
		row.add_child(nm)
		var les := UI.label(p["lesson"], 11, UI.MUTED)
		les.custom_minimum_size = Vector2(420, 0)
		les.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(les)
		for r in 4:
			var pid: String = p["id"]
			var role := r
			row.add_child(UI.toggle(Sim.SPECIALISTS[r]["name"], p["owner"] == r, _assign.bind(pid, role), 86))
		v.add_child(row)
	var bh := UI.hbox(12)
	bh.add_child(UI.button("BACK TO CREW", show_select, false, 200))
	bh.add_child(UI.button("CONFIRM ASSIGNMENTS   ↗", start_match, true, 300))
	v.add_child(bh)
	v.add_child(UI.spacer(20))


func show_route() -> void:
	clear_menu()
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.11, 0.5)   # translucent: the pad stays visible and live behind the plan
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(bg)
	var v := UI.vbox(10)
	v.position = Vector2(80, 110)
	menu_root.add_child(v)
	v.add_child(UI.label("ROUTE / PROPELLANT", 12, UI.MUTED))
	v.add_child(UI.label(str(ShipCatalog.loadout_stats(sim.loadout)["design_name"]).to_upper() + " / " + str(ShipCatalog.loadout_stats(sim.loadout)["synergy"]), 13, UI.ACCENT))
	v.add_child(UI.heading("CHOOSE YOUR ", "WINDOW.", 50))
	v.add_child(UI.label("Every crew is choosing a route. Balance local maneuver cost, travel time and exposure. Keep enough fuel to get home.", 14, UI.MUTED))
	var row := UI.hbox(16)
	v.add_child(row)
	for r in Sim.ROUTES:
		var b := sim.route_budget(r)
		var p := UI.panel(Vector2(400, 0))
		if not b["valid"]:
			p.modulate = Color(1, 1, 1, 0.55)
		var pv := UI.vbox(6)
		p.add_child(pv)
		pv.add_child(UI.label({"sheltered": "◌", "balanced": "◎", "slingshot": "↗"}[r["id"]], 28, UI.ACCENT))
		pv.add_child(UI.label("%d M/S DEPARTURE Δv" % r["dv"], 11, UI.MUTED))
		pv.add_child(UI.label(r["name"], 24, UI.TEXT))
		var n := UI.label(r["note"], 12, UI.MUTED)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pv.add_child(n)
		for line in [["Transit time", "%d s" % r["duration"]], ["Debris exposure", "×%.2f" % r["hazard"]], ["Outbound burn", "%.1f kg" % b["outbound"]],
				["Return reserve", "%.1f kg" % b["return_reserve"]], ["Slow-climb loss", "%.1f kg" % b["slow_climb"]], ["Contingency", "5.0 kg"],
				["Required / loaded", "%.1f / %.1f kg" % [b["required"], sim.propellant]], ["Margin", "%+.1f kg" % b["margin"]]]:
			var lh := UI.hbox(4)
			var a := UI.label(line[0], 12, UI.MUTED)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lh.add_child(a)
			lh.add_child(UI.label(line[1], 12, UI.TEXT))
			pv.add_child(lh)
		var risk := sim.route_risk(b)
		pv.add_child(UI.label(risk, 13, UI.GOOD if risk == "NOMINAL" else (UI.BAD if risk == "NO-GO" else UI.WARN)))
		var id: String = r["id"]
		var btn := UI.button("SELECT ROUTE   ↗" if b["valid"] else "INSUFFICIENT PROPELLANT", _choose_route.bind(id), b["valid"], 0, 44)
		btn.disabled = not b["valid"]
		pv.add_child(btn)
		row.add_child(p)
	var clock := UI.label("MISSION CLOCK %s · rivals keep working while you decide" % UI.fmt_time(sim.limit - sim.time), 12, UI.MUTED)
	v.add_child(clock)
	v.add_child(UI.button("BACK TO PAD", _close_plan, false, 200))


func show_gonogo() -> void:
	var routes := Sim.ROUTES.filter(func(r): return r["id"] == chosen_route)
	if routes.is_empty():
		_back_routes()
		return
	var ds := sim.design_sheet()
	var b := sim.route_budget(routes[0])
	mode = "gonogo"
	clear_menu()
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(bg)
	var v := UI.vbox(12)
	v.position = Vector2(80, 110)
	menu_root.add_child(v)
	v.add_child(UI.label("GO / NO-GO POLL", 12, UI.MUTED))
	v.add_child(UI.heading("ALL STATIONS, ", "REPORT.", 50))
	var reports := [
		[["Thrust-to-weight", "%.2f" % ds["twr"]], ["Delta-v", "%.0f m/s" % ds["dv"]], ["Route margin", "%+.1f kg" % b["margin"]]],
		[["Power margin", "%.1f kW" % ds["power_margin"]], ["Battery", "%.1f kWh" % sim.power], ["Coolant", "%.0f °C" % sim.temperature]],
		[["Dorsal turret", "×%.2f" % ds["turret_mult"]], ["Comms array", "×%.2f scan" % ds["scan_mult"]], ["Route hazard", "×%.2f" % b["hazard"]]],
		[["Cargo racks", "%d flags" % sim.cargo_capacity], ["EVA plates", "%d spares" % sim.spares], ["Scanner", "CALIBRATED"]],
	]
	var row := UI.hbox(12)
	v.add_child(row)
	for i in 4:
		var p := UI.panel(Vector2(300, 0))
		var pv := UI.vbox(6)
		p.add_child(pv)
		pv.add_child(UI.label(Sim.SPECIALISTS[i]["name"], 20, Sim.role_color(i)))
		pv.add_child(UI.label(Sim.SPECIALISTS[i]["role"], 11, UI.MUTED))
		for line in reports[i]:
			var lh := UI.hbox(4)
			var a := UI.label(line[0], 13, UI.MUTED)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lh.add_child(a)
			lh.add_child(UI.label(line[1], 13, UI.TEXT))
			pv.add_child(lh)
		pv.add_child(UI.label("GO", 18, UI.GOOD))
		row.add_child(p)
	var bh := UI.hbox(12)
	bh.add_child(UI.button("BACK TO ROUTES", _back_routes, false, 200))
	bh.add_child(UI.button("LAUNCH EXPEDITION   ↗", launch, true, 300))
	v.add_child(bh)


func pause() -> void:
	if mode == "paused":
		return
	paused_from = mode
	mode = "paused"
	capture_mouse(false)
	clear_menu()
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.11, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	var v := UI.vbox(12)
	v.position = Vector2(80, 112)
	menu_root.add_child(v)
	v.add_child(UI.heading("EXPEDITION ", "PAUSED.", 50))
	v.add_child(UI.button("RESUME EXPEDITION   ↗", resume, true, 420))
	v.add_child(UI.button("CONTROLS", show_help, false, 420))
	_add_settings_buttons(v)
	v.add_child(UI.button("ABANDON TO MAIN MENU", show_home, false, 420))


func show_settings() -> void:
	clear_menu()
	var v := UI.vbox(12)
	v.position = Vector2(80, 112)
	menu_root.add_child(v)
	v.add_child(UI.heading("SETTINGS", "", 50))
	_add_settings_buttons(v)
	v.add_child(UI.button("BACK TO MAIN MENU", show_home, false, 420))


func _add_settings_buttons(v: VBoxContainer) -> void:
	v.add_child(UI.button("MOUSE SENSITIVITY: %.1f×" % sens, _cycle_sens, false, 420))
	var vol_pct := 0 if master_volume_db <= -60.0 else roundi(db_to_linear(master_volume_db) * 100.0)
	v.add_child(UI.button("AUDIO VOLUME: %d%%" % vol_pct, _cycle_volume, false, 420))
	v.add_child(UI.button("REDUCED MOTION: %s" % ("ON" if UI.reduced_motion else "OFF"), _toggle_reduced_motion, false, 420))
	v.add_child(UI.button("GRAPHICS", show_graphics, false, 420))


func show_graphics() -> void:
	clear_menu()
	graphics_open = true
	var bg := ColorRect.new()
	bg.color = Color("#14101e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	menu_root.add_child(margin)
	var panel := UI.vbox(12)
	margin.add_child(panel)
	panel.add_child(UI.heading("GRAPHICS", "", 50))
	var preset := UI.button("", _cycle_graphics_quality)
	panel.add_child(preset)
	graphics_buttons["quality"] = preset
	# Direct preset picks: going HIGH -> LOW through the cycle button forces a stop at
	# ULTRA (SSIL/SSR/volumetric fog/TAA/8K shadows), a multi-second shader stall on Metal.
	var presets := UI.hbox(8)
	panel.add_child(presets)
	for level in GraphicsSettings.CUSTOM:
		var pick := UI.button(GraphicsSettings.QUALITY_NAMES[level], _select_graphics_preset.bind(level), false, 120)
		pick.toggle_mode = true
		presets.add_child(pick)
		graphics_buttons["preset_%d" % level] = pick
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var options := GridContainer.new()
	options.columns = 2
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("h_separation", 12)
	options.add_theme_constant_override("v_separation", 8)
	scroll.add_child(options)
	for key in GraphicsSettings.OPTIONS:
		var option := UI.button("", _cycle_graphics_option.bind(key))
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.add_child(option)
		graphics_buttons[key] = option
	var actions := UI.hbox(12)
	panel.add_child(actions)
	actions.add_child(UI.button("BACK", _close_graphics, false, 140))
	actions.add_child(UI.button("RESET GRAPHICS TO DEFAULT", _reset_graphics, false, 330))
	_refresh_graphics_buttons()
	preset.grab_focus()


func _close_graphics() -> void:
	if mode == "paused":
		mode = paused_from
		pause()
	else:
		show_settings()


func _refresh_graphics_buttons() -> void:
	if not graphics_open:
		return
	var preset: Variant = graphics_buttons.get("quality")
	if is_instance_valid(preset):
		preset.text = "PRESET: %s" % GraphicsSettings.QUALITY_NAMES[graphics.quality]
	for level in GraphicsSettings.CUSTOM:
		var pick: Variant = graphics_buttons.get("preset_%d" % level)
		if is_instance_valid(pick):
			pick.set_pressed_no_signal(graphics.quality == level)
	for key in GraphicsSettings.OPTIONS:
		var button: Variant = graphics_buttons.get(key)
		if is_instance_valid(button):
			button.text = graphics.option_text(key, UI.reduced_motion)
			button.disabled = not graphics.can_cycle(key)


func _load_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	graphics.load_config(config)
	sens = clampf(float(config.get_value("accessibility", "mouse_sensitivity", 1.0)), 0.5, 2.0)
	UI.reduced_motion = bool(config.get_value("accessibility", "reduced_motion", false))
	master_volume_db = clampf(float(config.get_value("audio", "volume_db", 0.0)), -80.0, 0.0)
	_apply_graphics()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	graphics.save_config(config)
	config.set_value("accessibility", "mouse_sensitivity", sens)
	config.set_value("accessibility", "reduced_motion", UI.reduced_motion)
	config.set_value("audio", "volume_db", master_volume_db)
	var result := config.save(settings_path)
	if result != OK:
		push_warning("Could not save settings: %s" % error_string(result))


func _apply_graphics(update_display := true) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_graphics_pending = true
	_graphics_display_pending = _graphics_display_pending or update_display
	if not _graphics_applying:
		_graphics_applying = true
		_flush_graphics.call_deferred()


func _flush_graphics() -> void:
	# Input updates the requested settings immediately. At each frame boundary,
	# abandon superseded work and use the latest request.
	while _graphics_pending and is_inside_tree() and not is_queued_for_deletion():
		_graphics_pending = false
		if _graphics_display_pending:
			_graphics_display_pending = false
			await graphics.apply_display(get_window())
		for stage in [_apply_graphics_buffers, _apply_graphics_atlases, _apply_graphics_scene]:
			if not is_inside_tree() or is_queued_for_deletion():
				break
			await get_tree().process_frame
			if _graphics_pending or not is_inside_tree() or is_queued_for_deletion():
				break
			stage.call()
	_graphics_applying = false
	if _graphics_save_pending and is_inside_tree() and not is_queued_for_deletion():
		_graphics_save_pending = false
		_save_settings()


func _apply_graphics_buffers() -> void:
	var viewport := get_viewport()
	if is_instance_valid(viewport) and not viewport.is_queued_for_deletion():
		graphics.apply_viewport_buffers(viewport)
	if graphics.values["shadows"] == 0:
		graphics.apply_shadows(universe)
		graphics.apply_shadows(world)


func _apply_graphics_atlases() -> void:
	var viewport := get_viewport()
	if is_instance_valid(viewport) and not viewport.is_queued_for_deletion():
		graphics.apply_shadow_atlases(viewport)


func _apply_graphics_scene() -> void:
	Engine.max_fps = graphics.values["fps_limit"]
	if is_instance_valid(fps_counter):
		fps_counter.visible = graphics.values["fps_counter"]
	GraphicsSettings.motion_effects = graphics.values["motion_effects"]
	GraphicsSettings.particle_density = graphics.values["particles"] / 100.0
	if is_instance_valid(universe) and not universe.is_queued_for_deletion():
		graphics.apply_scene(universe)
		universe.apply_quality(graphics)
	if is_instance_valid(world) and (not is_instance_valid(universe) or world.get_parent() != universe):
		graphics.apply_scene(world)

func _cycle_graphics_quality() -> void:
	_select_graphics_preset((graphics.quality + 1) % GraphicsSettings.CUSTOM if graphics.quality != GraphicsSettings.CUSTOM else 0)


func _select_graphics_preset(preset: int) -> void:
	var display_before: Array = graphics.display_state()
	var previous_values: Dictionary = graphics.values.duplicate()
	var previous_quality := graphics.quality
	if not graphics.set_preset(preset):
		return
	if graphics.quality != previous_quality or graphics.values != previous_values:
		_graphics_changed(graphics.display_state() != display_before)


func _cycle_graphics_option(key: String) -> void:
	if graphics.can_cycle(key):
		graphics.cycle(key)
		_graphics_changed(key in GraphicsSettings.DISPLAY_KEYS)


func _reset_graphics() -> void:
	_select_graphics_preset(GraphicsSettings.HIGH)


func _graphics_changed(update_display := true) -> void:
	_graphics_save_pending = true
	_apply_graphics(update_display)
	_refresh_graphics_buttons()


func _settings_changed() -> void:
	_save_settings()
	if mode == "paused":
		mode = paused_from
		pause()
	else:
		show_settings()


func resume() -> void:
	clear_menu()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode = paused_from
	if mode == "cine" and cine["kind"] == "launch":
		launch_tick_usec = Time.get_ticks_usec()
	if mode == "play" or mode == "cine":
		capture_mouse(mode == "play")


func show_help() -> void:
	var was := mode
	if mode == "play":
		pause()
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.theme = UI.theme()
	menu_layer.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.08, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var p := UI.panel(Vector2(900, 0), UI.PANEL_SOLID)
	p.position = Vector2(350, 110)
	layer.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.heading("FIELD ", "MANUAL.", 40))
	v.add_child(UI.rich("""[b]01 / BUILD[/b]  Walk to your rack, [b]E[/b] buys and picks up your next module. [b]R[/b] rotates it until the slot ghost turns green. [b]E[/b] sets it in the slot, then [b]hold LMB[/b] on three bolts. Teammates build their own parts.
[b]02 / OUTFIT[/b]  Carry the four supply cases to the aft cargo hatch. Chip and Finn run pressure, power and engine checks — [b]mouse wheel[/b] sets the reading, [b]hold LMB[/b] inside the band.
[b]03 / ROUTE[/b]  Compare Δv, propellant, return reserve and debris. Keep enough fuel to get home.
[b]04 / FLIGHT[/b]  [b]1[/b] Finn pilots (WASD dodge, Q afterburner). [b]2[/b] Chip services systems (W/S choose, hold LMB, wheel = reactor). [b]3[/b] Barbara mans the dorsal turret (LMB). [b]4[/b] Fernando removes and replaces damaged hull plates (W/S, E, hold LMB).
[b]05 / MOON[/b]  Fernando holds [b]LMB[/b] at a flag: SCAN → STABILIZE → EXTRACT (5 s). [b]E[/b] loads it at the ship, [b]G[/b] drops it. Other roles fire blasters (LMB, R reload) to stun rival raiders. [b]T[/b] at the ship departs.
[b]TACTICS[/b]  [b]C[/b] cycles Escort / Recover / Regroup. [b]Z[/b] marks the flag nearest your crosshair for Fernando. [b]M[/b] opens the live tactical map. Use rocks as cover; suits recover after six seconds without damage. Chip improves recovery nearby.
[b]06 / DELIVER[/b]  Hold [b]E[/b] on the delivery pad. Only flags transferred to Earth score.

[color=#b4a8c6]WASD move · Shift sprint · Space jump · V camera · 1–4 roles · Q skill · F ultimate · H manual · Esc pause · F5 cycle fast-forward[/color]""", 15))
	v.add_child(UI.button("CLOSE", layer.queue_free, true, 200))


func show_debrief() -> void:
	mode = "debrief"
	capture_mouse(false)
	hud.visible = false
	if ff != Engine.time_scale:
		ff = 1.0
	clear_menu()
	var d := sim.debrief(0)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.12, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	_brand(menu_root)
	var p := UI.panel(Vector2(980, 0), UI.PANEL_SOLID)
	p.position = Vector2(310, 100)
	menu_root.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	v.add_child(UI.label(sim.reason.to_upper(), 12, UI.MUTED))
	if d["eliminated"]:
		v.add_child(UI.heading("CREW ", "LOST.", 54))
	elif d["victory"]:
		v.add_child(UI.heading("FRONTIER ", "SECURED.", 54))
	else:
		v.add_child(UI.heading("BRING IT ", "HOME.", 54))
	var stats := UI.hbox(40)
	v.add_child(stats)
	for s in [["%d/12" % d["delivered"], "FLAGS DELIVERED"], ["+%d XP" % d["xp"], "EXPERIENCE"], ["+%d" % d["credits"], "CREDITS"], ["#%d" % d["rank"], "RANK"]]:
		var sv := UI.vbox(0)
		sv.add_child(UI.label(s[0], 34, UI.ACCENT))
		sv.add_child(UI.label(s[1], 11, UI.MUTED))
		stats.add_child(sv)
	v.add_child(UI.label("MISSION PATCH · " + d["patch"].to_upper(), 13, UI.TEXT))
	v.add_child(UI.label("CREW IMPACT  /  %d extractions · %d recoveries · %d rival stuns · %d repairs · %d downs" % [sim.metrics["captures"], sim.metrics["recoveries"], sim.metrics["stuns"], sim.metrics["repairs"], sim.metrics["downs"]], 12, UI.ACCENT))
	v.add_child(UI.label("MATCH SEED %d · %s · %s" % [sim.match_seed, sim.difficulty.to_upper(), "QUICK DEPLOY" if sim.quick_deploy else "FULL EXPEDITION"], 11, UI.MUTED))
	var table := UI.vbox(4)
	v.add_child(table)
	var order := range(4)
	order.sort_custom(func(a, b): return sim.teams[a]["delivered"] > sim.teams[b]["delivered"])
	for i in order:
		var t = sim.teams[i]
		var h := UI.hbox(10)
		var n := UI.label(Sim.FACTIONS[i]["symbol"] + " " + t["name"] + ("  (YOU)" if i == 0 else ""), 15, Sim.faction_color(i))
		n.custom_minimum_size = Vector2(220, 0)
		h.add_child(n)
		var ph := UI.label(t["phase"].to_upper(), 12, UI.MUTED)
		ph.custom_minimum_size = Vector2(200, 0)
		h.add_child(ph)
		h.add_child(UI.label("%d delivered" % t["delivered"], 15, UI.TEXT))
		table.add_child(h)
	for l in d["log"]:
		var h := UI.hbox(12)
		var t := UI.label(l["title"], 12, UI.MUTED)
		t.custom_minimum_size = Vector2(160, 0)
		h.add_child(t)
		var val := UI.label(l["value"], 14, UI.TEXT)
		val.custom_minimum_size = Vector2(160, 0)
		h.add_child(val)
		var det := UI.label(l["detail"], 12, UI.MUTED)
		det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		det.custom_minimum_size = Vector2(600, 0)
		h.add_child(det)
		v.add_child(h)
	var bh := UI.hbox(12)
	bh.add_child(UI.button("REMATCH · SAME SEED", rematch, true, 240))
	bh.add_child(UI.button("NEW EXPEDITION   ↗", _start_new, false, 240))
	bh.add_child(UI.button("GAME MENU", show_home, false, 200))
	v.add_child(bh)


func _set_opt(key: String, value) -> void:
	opts[key] = value
	if key == "difficulty" or key == "length":
		sim = null
	show_select()


func _start_new() -> void:
	opts["seed"] = 0
	new_sim()
	start_match()


func _assign(pid: String, role: int) -> void:
	sim.assign_part(pid, role)
	show_manifest()


func _toggle_upgrade(id: String) -> void:
	if not sim.set_upgrade(id, not sim.upgrades.has(id)):
		sfx("reload_click")
	opts["upgrades"] = sim.upgrades.duplicate()
	show_manifest()


func _choose_route(id: String) -> void:
	chosen_route = id
	show_gonogo()


func _close_plan() -> void:
	clear_menu()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode = "play"
	capture_mouse(true)


func _back_routes() -> void:
	mode = "route"
	show_route()


func _cycle_sens() -> void:
	sens = 0.5 if sens >= 2.0 else sens + 0.5
	_settings_changed()


func _cycle_volume() -> void:
	if master_volume_db >= -1.0: master_volume_db = -6.0
	elif master_volume_db >= -7.0: master_volume_db = -12.0
	elif master_volume_db >= -15.0: master_volume_db = -80.0
	else: master_volume_db = 0.0
	sfx("ui_click", -8)
	_settings_changed()


func _toggle_reduced_motion() -> void:
	UI.reduced_motion = not UI.reduced_motion
	sfx("ui_click", -8)
	_settings_changed()


# ============================================================================
# Single-player campaign
# ============================================================================
func _sp_screen(eyebrow: String) -> VBoxContainer:
	mode = "menu"
	capture_mouse(false)
	hud.visible = false
	clear_menu()
	var bg := ColorRect.new()
	bg.color = Color("#0d141c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	var brand := UI.rich("[b]T[color=#eaa665]−[/color]MINUS[/b]", 28)
	brand.position = Vector2(48, 24)
	brand.size = Vector2(300, 40)
	menu_root.add_child(brand)
	var sub := UI.label("THE FIRST FRONTIER", 10, UI.ACCENT)
	sub.position = Vector2(50, 62)
	menu_root.add_child(sub)
	var top := UI.label(eyebrow, 12, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position = Vector2(-560, 34)
	top.size = Vector2(380, 20)
	menu_root.add_child(top)
	var mm := UI.button("MAIN MENU", show_home, false, 130, 40)
	mm.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mm.position = Vector2(-170, 24)
	menu_root.add_child(mm)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 60
	scroll.offset_right = -60
	scroll.offset_top = 100
	scroll.offset_bottom = -20
	menu_root.add_child(scroll)
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v


func _mint_heading(white: String, mint: String, size := 56) -> RichTextLabel:
	var r := UI.heading(white, mint, size)
	r.text = "[b]%s[color=#eaa665]%s[/color][/b]" % [white, mint]
	return r


func show_campaign() -> void:
	set_world(null)
	showcase = null
	var v := _sp_screen("SINGLE PLAYER / CAMPAIGN")
	var row := UI.hbox(40)
	v.add_child(row)
	var left := UI.vbox(14)
	left.custom_minimum_size = Vector2(520, 0)
	row.add_child(left)
	left.add_child(UI.label("CAMPAIGN / CHAPTER ONE", 12, UI.ACCENT))
	left.add_child(_mint_heading("THE FIRST\n", "FRONTIER.", 64))
	left.add_child(UI.label("Design the spacecraft. Build it in the workshop.\nWork as a crew. Bring the mission home.", 18, UI.MUTED))
	left.add_child(UI.label("A new space program starts with you.\nInes Valder / Mission Director", 14, UI.TEXT))
	var prog := Campaign.load_progress()
	left.add_child(UI.label("Two playable missions. Additional chapters are planned.\nProgress is saved on this computer. Completed: %d" % prog["completed"].size(), 12, UI.DIM))
	var list := UI.vbox(10)
	list.custom_minimum_size = Vector2(700, 0)
	row.add_child(list)
	for m in Campaign.MISSIONS:
		var open: bool = m["available"] and Campaign.unlocked(m["id"])
		var p := UI.panel(Vector2(700, 0), Color("#12202a") if open else Color("#0f1820"))
		var pv := UI.vbox(4)
		p.add_child(pv)
		var head := UI.hbox(14)
		head.add_child(UI.label(m["number"], 30, UI.ACCENT if open else UI.DIM))
		var hv := UI.vbox(2)
		if m["available"]:
			hv.add_child(UI.label(m["destination"] if open else "COMPLETE MISSION 01 TO UNLOCK", 11, UI.ACCENT if open else UI.DIM))
		else:
			hv.add_child(UI.label("FUTURE CHAPTER", 11, UI.DIM))
		hv.add_child(UI.label(m["name"], 22, UI.TEXT if open else UI.DIM))
		head.add_child(hv)
		pv.add_child(head)
		if m["available"]:
			var s := UI.label(m["summary"], 13, UI.MUTED)
			s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			pv.add_child(s)
			var best: int = int(prog["best"].get(m["id"], 0))
			pv.add_child(UI.label("%s · SOLO + CREW ASSISTANCE%s" % [m["duration"], (" · BEST %d" % best) if best > 0 else ""], 11, UI.ACCENT))
			if open:
				pv.add_child(UI.button("OPEN BRIEFING   ↗", show_briefing.bind(m["id"]), true, 0, 40))
		list.add_child(p)


func show_briefing(id: String) -> void:
	sp_mission = id
	var m := Campaign.mission(id)
	var v := _sp_screen("SINGLE PLAYER / CAMPAIGN")
	v.add_child(UI.label("MISSION %s / BRIEFING" % m["number"], 12, UI.ACCENT))
	v.add_child(_mint_heading(m["name"], "", 54))
	var s := UI.label(m["summary"], 16, UI.MUTED)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.custom_minimum_size = Vector2(900, 0)
	v.add_child(s)
	var p := UI.panel(Vector2(900, 0), Color("#12202a"))
	var pv := UI.vbox(6)
	p.add_child(pv)
	pv.add_child(UI.label("COMMANDER INES VALDER", 11, UI.ACCENT))
	pv.add_child(UI.label("“Every choice flies with you.”", 20, UI.TEXT))
	var q := UI.label("We have one spacecraft and one chance. Pick the hardware, buy every piece in the workshop and let the machines assemble it. Check your systems, collect the observations, and keep enough energy to bring everyone home.", 13, UI.MUTED)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(q)
	v.add_child(p)
	v.add_child(UI.label("SUCCESS CRITERIA", 12, UI.ACCENT))
	for c in m["criteria"]:
		v.add_child(UI.label("·  " + c, 14, UI.TEXT))
	v.add_child(UI.label("%s · Approximate playtime %s" % [m["destination"], m["duration"]], 12, UI.MUTED))
	var r := UI.label(m["reference"] + " Illustrative equipment values; guided flight and time compression are disclosed gameplay abstractions.", 11, UI.DIM)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(900, 0)
	v.add_child(r)
	var bh := UI.hbox(12)
	bh.add_child(UI.button("←  MISSION SELECT", show_campaign, false, 220))
	bh.add_child(UI.button("DESIGN SPACECRAFT   →", show_design, true, 280))
	v.add_child(bh)


func _set_part(key: String, id: String) -> void:
	sp_design[key] = id
	show_design()


func show_design() -> void:
	var m := Campaign.mission(sp_mission)
	var e := Campaign.evaluate_design(sp_design, sp_mission)
	var v := _sp_screen("SINGLE PLAYER / CAMPAIGN")
	v.add_child(UI.label("MISSION %s / ENGINEERING" % m["number"], 12, UI.ACCENT))
	v.add_child(_mint_heading("BUILD YOUR\n", "MISSION MARGIN.", 54))
	v.add_child(UI.label("The hardware you choose determines your spacecraft’s live capabilities. You will buy each piece in the workshop.", 14, UI.MUTED))
	var row := UI.hbox(30)
	v.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	row.add_child(grid)
	for key in Campaign.EQUIPMENT:
		var col := UI.vbox(6)
		col.add_child(UI.label(Campaign.EQUIPMENT_LABEL[key], 12, UI.ACCENT))
		for p in Campaign.EQUIPMENT[key]:
			var on: bool = sp_design[key] == p["id"]
			var stat := ""
			if p.has("wh"): stat = "%d Wh reserve" % p["wh"]
			elif key == "array": stat = "%d W generation" % p["watts"]
			elif key == "instrument": stat = "%d W draw" % p["watts"]
			else: stat = "%d MB/s downlink" % int(p["rate"])
			var b := UI.toggle("%s\n%d kg · %d credits · %s" % [p["name"], p["mass"], p["cost"], stat], on, _set_part.bind(key, p["id"]), 330)
			b.custom_minimum_size = Vector2(330, 58)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			col.add_child(b)
		grid.add_child(col)
	var ready := UI.panel(Vector2(420, 0), Color("#12202a"))
	row.add_child(ready)
	var rv := UI.vbox(6)
	ready.add_child(rv)
	rv.add_child(UI.label("LIVE READINESS / " + m["name"], 11, UI.ACCENT))
	rv.add_child(UI.label("GO FOR REVIEW" if e["valid"] else "NO-GO", 24, UI.GOOD if e["valid"] else UI.BAD))
	for line in [["Wet mass", "%d / 850 kg" % e["mass"]], ["Budget", "%d / %d credits" % [e["cost"], e["budget"]]], ["Science load", "%d W" % e["load"]],
			["Solar generation", "%d W" % e["parts"]["array"]["watts"]], ["Eclipse science endurance", "%d play seconds" % int(e["endurance"])]]:
		var h := UI.hbox(6)
		var a := UI.label(line[0], 13, UI.MUTED)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UI.label(line[1], 13, UI.TEXT))
		rv.add_child(h)
	for err in e["errors"]:
		var l := UI.label("✕ " + err, 12, UI.BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(l)
	for w in e["warnings"]:
		var l := UI.label("! " + w, 12, UI.WARN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(l)
	var note := UI.label("Fictional training hardware. Essential load 800 W (600 W in conservation). Resource simulation runs 8 s per play second. The training launcher (core stage, two side boosters, fairing) is program-supplied.", 11, UI.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(note)
	var bh := UI.hbox(12)
	bh.add_child(UI.button("←  BRIEFING", show_briefing.bind(sp_mission), false, 200))
	var go := UI.button("ACCEPT DESIGN & GO TO WORKSHOP   →", start_workshop, true, 380)
	go.disabled = not e["valid"]
	bh.add_child(go)
	v.add_child(bh)


func _sp_enter(w) -> void:
	clear_menu()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	showcase = null
	set_world(w)
	hud.visible = true
	hud.set_mode(true)
	mode = "play"
	capture_mouse(true)


func start_workshop() -> void:
	if not Campaign.evaluate_design(sp_design, sp_mission)["valid"]:
		return
	sim = null
	campaign = Campaign.new(sp_mission, sp_design)
	var w := Workshop.new()
	w.setup(self, sp_design, false)
	_sp_enter(w)
	hud.show_banner("WORKSHOP", "Buy each piece at the parts shop. The machines build it.", 3.5)


func board_ship() -> void:
	var o := OrbitShip.new()
	o.setup(self, campaign)
	_sp_enter(o)
	hud.show_banner("PREFLIGHT CHECKS", "Verify power, cabin and payload, then confirm launch on the flight deck", 3.5)


func start_campaign_launch() -> void:
	var w := Workshop.new()
	w.setup(self, sp_design, true)
	_sp_enter(w)


func launch_finished() -> void:
	if campaign.phase == "launch":
		campaign.set_phase("commission")
	var o := OrbitShip.new()
	o.setup(self, campaign)
	_sp_enter(o)
	hud.show_banner("ORBIT", "Deploy the solar wings and engage the autopilot", 3.5)


func campaign_finished() -> void:
	var rep := campaign.report()
	Campaign.save_result(campaign.mission_id, rep)
	var m := Campaign.mission(campaign.mission_id)
	var v := _sp_screen("SINGLE PLAYER / CAMPAIGN")
	set_world(null)
	v.add_child(UI.label("MISSION %s / %s" % [m["number"], Campaign.PHASE_NAMES[campaign.phase].to_upper()], 12, UI.ACCENT))
	v.add_child(_mint_heading("MISSION ", "COMPLETE." if rep["success"] else "REVIEW.", 54))
	var stats := UI.hbox(44)
	for s in [["%d" % rep["score"], "SCORE"], ["%d MB" % roundi(rep["science"]), "SCIENCE SENT"], ["%d%%" % roundi(rep["minimum_battery"]), "LOWEST BATTERY"], ["%.1f" % rep["minutes"], "MINUTES"]]:
		var sv := UI.vbox(0)
		sv.add_child(UI.label(s[0], 34, UI.ACCENT))
		sv.add_child(UI.label(s[1], 11, UI.MUTED))
		stats.add_child(sv)
	v.add_child(stats)
	for f in rep["feedback"]:
		var l := UI.label("·  " + f, 14, UI.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1000, 0)
		v.add_child(l)
	v.add_child(UI.label("MISSION LOG", 12, UI.ACCENT))
	for e in campaign.mission_log.slice(maxi(0, campaign.mission_log.size() - 14)):
		v.add_child(UI.label("T+%s  %s" % [UI.fmt_time(e["time"]), e["text"]], 12, UI.MUTED))
	var bh := UI.hbox(12)
	bh.add_child(UI.button("RETRY MISSION", show_design, true, 220))
	bh.add_child(UI.button("MISSION SELECT", show_campaign, false, 220))
	v.add_child(bh)


# ============================================================================
# Mission design & science simulator
# ============================================================================
func show_mission_control() -> void:
	MissionControlUI.show(self)


func _mc_set(key: String, value) -> void:
	MissionControlUI.set_param(self, key, value)


func _mc_add(key: String, delta: float, lo: float, hi: float) -> void:
	MissionControlUI.add_param(self, key, delta, lo, hi)


func _mc_policy(p: String) -> void:
	MissionControlUI.set_policy(self, p)


func _mc_run(days: int) -> void:
	MissionControlUI.run_sim(self, days)


func _mc_reset() -> void:
	MissionControlUI.reset_sim(self)


func _mc_render() -> void:
	MissionControlUI.render(self)


func open_ship_builder() -> void:
	if is_instance_valid(picker): return
	picker = preload("res://scripts/ship_builder.gd").new()
	menu_root.add_child(picker)
	picker.setup(self)
	capture_mouse(false)
	lmb = false
	rmb = false
	pressed_now.clear()


func open_picker(slot: String) -> void:
	if is_instance_valid(picker): return
	picker = preload("res://scripts/ship_picker.gd").new()
	menu_root.add_child(picker)
	picker.setup(self, slot)
	capture_mouse(false)
	lmb = false
	rmb = false
	pressed_now.clear()
