## T-MINUS — offline crew match (Godot port).
## Build a ship and fly between the three worlds.
## -> flight -> the Moon -> return flight -> dock -> deliver -> debrief.
extends Node3D

const WorldLabels := preload("res://scripts/ui/world_labels.gd")
const ArenaClashRules := preload("res://scripts/arena_clash_sim.gd")

const SETTINGS_PATH := "user://settings.cfg"
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const SettingsMenu = preload("res://scripts/settings_menu.gd")
const HudLayoutEditor = preload("res://scripts/hud_layout_editor.gd")
const ShipInteriorScript = preload("res://scripts/ship_interior.gd")
const FPV_NEAR := 0.025
const SPRINT_FOV := 7.0
const FOOTSTEP_INTERVAL := 0.36 # Actor.poll_step() cadence before speed scaling.

const SFX := ["shot_carbine", "shot_scatter", "shot_sidearm", "hitmarker", "capture_tick", "explosion", "hurt", "shield_recharge", "shield_hit", "shield_break", "reload_click", "reload_ratchet", "step_0", "step_1", "step_2", "step_3"]
const KEY_ACTIONS := {
	KEY_W: "move_forward", KEY_S: "move_back", KEY_A: "move_left", KEY_D: "move_right",
	KEY_SPACE: "jump", KEY_SHIFT: "sprint", KEY_E: "interact", KEY_R: "reload",
	KEY_B: "holster", KEY_Q: "skill", KEY_F: "ultimate", KEY_C: "orders",
	KEY_Z: "ping", KEY_M: "tactical_map", KEY_V: "camera_view", KEY_L: "land",
	KEY_CTRL: "flight_trim_down",
	KEY_G: "drop_flag", KEY_H: "help", KEY_1: "role_1", KEY_2: "role_2",
	KEY_3: "role_3", KEY_4: "role_4",
}
const GAMEPAD_BUTTONS := {
	"jump": JOY_BUTTON_A, "interact": JOY_BUTTON_X, "reload": JOY_BUTTON_B,
	"holster": JOY_BUTTON_Y, "skill": JOY_BUTTON_LEFT_SHOULDER, "ultimate": JOY_BUTTON_RIGHT_SHOULDER,
}
var _rebound_actions := {}

const EmpireRules = preload("res://scripts/empire_sim.gd")
const EmpireNet = preload("res://scripts/tminus_net.gd")
const RemoteSync = preload("res://scripts/tminus_remote_sync.gd")
const EmpireLayer = preload("res://scripts/empire_world_layer.gd")

var net: EmpireNet
var remote_sync: RemoteSync
var _net_status: Label
var _net_address := "127.0.0.1"
var _net_port := EmpireNet.DEFAULT_PORT
var _net_error := ""
var _empire_round := 0
var _empire_broadcast_time := 0.0
var _empire_action_result := {}
var _empire_sabotage := {}
var _empire_last_shot := {}
var _empire_sync_ready := false

var sim: Sim
var arena_clash: ArenaClashRules
var _arena_surface_hud: CombatHUD
var opts := {"difficulty": "standard", "length": "standard", "fast": false, "selected": 3, "upgrades": []}
var picker: Control
var mode := "menu"            # menu | play | paused | debrief
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
var sprint_step := false
var landing_impact := 0.0
var _follow_fov := 68.0
var _follow_near := 0.05
var _view_actor: Actor
var _view_in_first_person := false
var _foot_camera_actor: Actor
var _foot_camera_driven := false
var _stride_phase := 0.0
var _stride_blend := 0.0
var _sprint_fov := 0.0
var _step_kick := 0.0
var _landing_kick := 0.0
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
const TOUCH_ACTION_KEYS := {
	"land": KEY_L,
	"jump": KEY_SPACE, "interact": KEY_E, "reload": KEY_R, "ultimate": KEY_F,
	"weapon": KEY_B, "map": KEY_M, "order": KEY_C, "priority": KEY_Z, "dash": KEY_ALT,
	"camera_view": KEY_V,
}
var rmb := false
var wheel := 0
var event_index := 0
var ff := 1.0
var players: Array = []
var players_3d: Array = []
var ambient_player: AudioStreamPlayer
var _ambient_kind := ""
var master_volume_db := 0.0
var audio_muted := false
var invert_y := false
var touch_mode := "off"       # on = TOUCH, off = KBM (resolved from platform on first run)
var touch_opacity := 1.0
var haptics := true
var hud_layout := {}          # saved custom touch layout (empty = use preset)
var hud_preset := "2-FINGER"
var _hud_editor: Control
var advisor_hints := true
var hud_opacity := 0.85
var settings_tab := "graphics"
var settings_open := false
var _settings_menu: Control
var _save_queued := false
var streams := {}
var showcase = null
var universe: Universe          # one persistent scene: Earth, space, the Moon
var vessel: Flight
var piloting := false
var _travel_destination := ""
var _travel_time := 0.0
var _travel_swapped := false
var _travel_fade: ColorRect
const TRAVEL_FADE_SECONDS := 0.22
var world_a: PlanetA
var world_planet_b: PlanetA
# Walkable spacecraft interior for the flag modes.
var interior = null
var _interior_open := false
## Belly ramp on the parked spacecraft: crew physically walk up it into the airlock.
var boarding_ramp: BoardingRamp
var _boarding_auto := false        # E at the ramp foot: the player walks up on their own
var _boarding_block_cd := 0.0
var _interior_vessel: Node3D
var _input_masked := false     # true while the background world ticks under the interior
var _bg_yaw := 0.0
var _bg_pitch := -0.2
var _bg_fpv := false
var _bg_footer := ""
var _crane_camera_active := false
var _crane_camera_return := 0.0
var _crane_quit_key_down := false
var world_b: PlanetB  # Planet C (Moon arena)
var ad_runner
var runner: Autotest
var mc_plan := {}
var mc_state := {}
var mc_policy := "balanced"


func _ready() -> void:
	randomize()
	net = EmpireNet.new()
	net.name = "TMinusNet"
	add_child(net)
	net.session_changed.connect(_on_empire_session_changed)
	net.roster_updated.connect(_on_empire_roster)
	net.world_snapshot_received.connect(_on_empire_snapshot)
	net.action_requested.connect(_on_empire_action)
	net.action_resolved.connect(_on_empire_action_result)
	net.player_damaged.connect(_on_remote_player_damaged)
	remote_sync = RemoteSync.new()
	remote_sync.name = "TMinusRemoteSync"
	add_child(remote_sync)
	remote_sync.setup(net)
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
	LobbyPages.load_profile(settings_path)
	# Editor-visible camera. Its FOV and clipping range can now be adjusted visually.
	cam = get_node("GameCamera") as Camera3D
	_follow_fov = cam.fov
	_follow_near = cam.near
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
	hud.touch_ui_toggled.connect(func(on: bool) -> void: set_touch_mode("on" if on else "off"))
	_apply_controls()
	_apply_hud_layout()
	_apply_game()
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
	elif args.has("--autotest-mc"):
		autotest = true
		runner = Autotest.new()
		runner.run_mc(self)
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
		want = "ambient_flight" if piloting else ("ambient_moon" if sim.on_surface("planet_c") else "ambient_earth")
	if want == _ambient_kind:
		return
	_ambient_kind = want
	if want == "" or not streams.has(want):
		if ambient_player.playing:
			ambient_player.stop()
		return
	ambient_player.stream = streams[want]
	ambient_player.play()


func _set_audio_mode(audio_mode: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return
	if audio_mode != "flight" and am.has_method("set_engine_throttle"):
		am.set_engine_throttle(0.0)
	if am.has_method("set_mode"):
		am.set_mode(audio_mode)
	elif audio_mode == "menu" and am.has_method("play_menu_music"):
		am.play_menu_music()


func play_player_shot(legacy_clip: String, legacy_volume: float, legacy_pitch_var := 0.08) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx"):
		am.play_sfx("shoot", -5.0, 0.08)
	else:
		_play_local_sfx(legacy_clip, legacy_volume, legacy_pitch_var)


func sfx(name: String, vol := -8.0, pitch_var := 0.08) -> void:
	if name in ["shot_carbine", "shot_scatter", "shot_sidearm"]:
		_broadcast_local_shot()
	# Planet C sends player weapon fire here and bot weapon fire through sfx_3d.
	if world is PlanetB and name in ["shot_carbine", "shot_scatter", "shot_sidearm"]:
		play_player_shot(name, vol, pitch_var)
		return
	_play_local_sfx(name, vol, pitch_var)


func _play_local_sfx(name: String, vol: float, pitch_var: float) -> void:
	if not streams.has(name):
		return
	for p in players:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = vol
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
			p.volume_db = vol
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
	if _input_masked:
		return false
	if key == KEY_Q and _crane_quit_key_down:
		return false
	if touch_pressed.has(key):
		return true
	var action: String = KEY_ACTIONS.get(key, "")
	if pressed_now.has(key) and not _rebound_actions.has(action):
		return true
	if action != "" and InputMap.has_action(action):
		return Input.is_action_just_pressed(action)
	return pressed_now.has(key)


func flight_lift_tapped() -> bool:
	var key: int = _rebound_actions.get("jump", KEY_SPACE)
	return not _input_masked and (pressed_now.has(key) or touch_pressed.has(KEY_SPACE))


func held(key: int, include_touch := true) -> bool:
	if _input_masked:
		return false
	if key == KEY_Q and _crane_quit_key_down:
		return false
	var t: MobileControls = touch_ui() if include_touch else null
	if t != null:
		if key == KEY_E and t.is_interacting():
			return true
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
		if world.get_parent() != universe:
			world.queue_free()
	if not managed:
		drop_universe()
	if world != w:
		_free_interior()
		_release_follow_camera()
		_crane_camera_active = false
		_crane_camera_return = 0.0
		if hud:
			hud.set_crane_mode(false)
			hud.set_prompt("")
	world = w
	if w and w.get_parent() == null:
		add_child(w)
	if is_instance_valid(world):
		graphics.apply_scene(world)
	_bind_remote_sync()


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
	vessel = null
	piloting = false
	_travel_destination = ""
	if is_instance_valid(_travel_fade):
		_travel_fade.hide()
	world_a = null
	world_planet_b = null
	world_b = null


## Puts a world into the universe at `xf` and makes it the active one without any scene swap.
func enter_world(w: Node3D, xf: Transform3D) -> void:
	ensure_universe()
	if w.get_parent() == null:
		universe.add_child(w)
	w.transform = xf
	universe.focus_xf(xf)
	set_world(w)
	if not piloting and w is PlanetA:
		_set_audio_mode("earth")
	elif not piloting and w is PlanetB:
		_set_audio_mode("moon")


func clear_menu() -> void:
	_lobby_play_btn = null
	graphics_open = false
	settings_open = false
	_settings_menu = null
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
	if interior_active():
		return interior.actor(sim.selected)
	if piloting:
		return null
	if world and world.has_method("actor"):
		return world.actor(sim.selected)
	return null


# ============================================================================
# Input
# ============================================================================
func _input(e: InputEvent) -> void:
	if e is InputEventKey and (e.keycode == KEY_Q or e.physical_keycode == KEY_Q):
		if not e.pressed:
			_crane_quit_key_down = false
		elif _crane_quit_key_down:
			get_viewport().set_input_as_handled()
			return
		elif not e.echo and mode == "play" and _earth_crane_camera_active():
			_crane_quit_key_down = true
			pressed_now.erase(KEY_Q)
			if world.has_method("exit_crane_mode"):
				world.exit_crane_mode()
			get_viewport().set_input_as_handled()
			return
	if e is InputEventKey and e.keycode == KEY_F9 and e.pressed and not e.echo:
		toggle_touch_ui()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.keycode == KEY_F5 and e.pressed and not e.echo and not net.is_online():
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
			if settings_open or graphics_open:
				_close_settings()
			elif mode == "play":
				pause()
			elif mode == "paused":
				resume()
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if mode == "play" and piloting and not interior_active():
			vessel.steer(e.relative)
			return
		yaw -= e.relative.x * 0.0026 * sens
		pitch = clampf(pitch - e.relative.y * 0.0022 * sens * (-1.0 if invert_y else 1.0), -1.25, 0.95)
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
	var on := touch_mode != "on"
	set_touch_mode("on" if on else "off")
	hud.toast("TOUCH CONTROLS %s · F9" % ("ON" if on else "OFF"), 1.4)


func _tick_touch() -> void:
	hud.mobile_controls.set_flight_mode(piloting and not interior_active())
	hud.mobile_controls.set_active(mode == "play" and not settings_open and not is_instance_valid(picker))
	var t := touch_ui()
	if t == null:
		return
	var d := t.consume_look_delta()
	if piloting and not interior_active():
		vessel.steer(d * 2.0)
	elif d != Vector2.ZERO:
		yaw -= d.x * 0.0052 * sens
		pitch = clampf(pitch - d.y * 0.0044 * sens * (-1.0 if invert_y else 1.0), -1.25, 0.95)
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
	hud.tick(dt if mode == "play" and not _loading_active and not is_instance_valid(picker) else 0.0)
	_refresh_empire_network_status()
	_tick_remote_sync()
	if arena_clash != null and mode == "play" and not _loading_active:
		_tick_arena_clash(frame_dt)
	if net.is_online() and sim != null and sim.empire != null and (
			mode == "paused" or is_instance_valid(picker)):
		_tick_empire(dt)
	if is_instance_valid(picker):
		pressed_now.clear()
		touch_pressed.clear()
		return
	if universe != null and is_instance_valid(universe):
		universe.tick(dt)
	if showcase and is_instance_valid(showcase) and showcase.has_method("tick"):
		showcase.tick(dt)
	if mode == "play" and not _loading_active:
		_foot_camera_driven = false
		_play_common(dt)
		if arena_clash == null:
			_interior_hotkeys()
		if _travel_destination != "":
			_tick_travel(dt / maxf(1.0, Engine.time_scale))
		elif piloting:
			if interior_active():
				_input_masked = true
				vessel.tick(dt)
				_input_masked = false
				if interior_active():
					_tick_interior(dt)
			else:
				vessel.tick(dt)
			if arena_clash == null and sim.in_space():
				sim.tick_systems(dt)
		elif world and world.has_method("tick"):
			if is_instance_valid(vessel) and vessel.grounded:
				vessel.settle_parked(dt)
			var previous_camera := cam.global_transform
			world.tick(dt)
			if not piloting and not interior_active() and world is PlanetA:
				_update_earth_crane_camera(dt, previous_camera)
				world.update_station_labels(cam)
			elif world is PlanetB:
				world.update_station_labels(cam)
		if not piloting or interior_active():
			WorldLabels.declutter_nameplates(cam)
		_tick_boarding_ramp(dt)
		if sim != null:
			_tick_sim(dt)
		elif world and world.has_method("hud_update"):
			world.hud_update(hud)
	pressed_now.clear()
	touch_pressed.clear()
	wheel = 0


func _tick_sim(dt: float) -> void:
	if arena_clash != null:
		if mode == "play":
			_refresh_hud()
		return
	if sim == null:
		return
	# Manual fast-forward is already applied to dt by the engine.
	var steps := 1 if ff == Engine.time_scale or net.is_online() else int(ff)
	for i in maxi(1, steps):
		sim.tick_rivals(dt)
		_tick_empire(dt)
	if mode == "play":
		_refresh_hud()
	while event_index < sim.events.size():
		var ev = sim.events[event_index]
		event_index += 1
		hud.toast(ev["text"])
	if sim.over and mode != "debrief":
		show_debrief()


# ---- Spacecraft interior ----------------------------------------------------
func interior_active() -> bool:
	return _interior_open and interior != null and is_instance_valid(interior)


## [I] / Tab steps into the live interior during flight and back out again.
func _interior_hotkeys() -> void:
	if sim == null:
		return
	var toggle := pressed(KEY_I) or pressed(KEY_TAB)
	if not toggle:
		return
	if interior_active():
		exit_interior()
	elif piloting and sim.in_space() and _travel_destination == "":
		enter_interior()


func prepare_interior() -> Node3D:
	if interior == null or not is_instance_valid(interior):
		_free_interior()
		interior = ShipInteriorScript.new()
		add_child(interior)
		interior.setup(self)
	return interior


func enter_interior(via_airlock := false) -> void:
	if sim == null or interior_active():
		return
	var vessel := _live_interior_vessel()
	if not is_instance_valid(vessel):
		return
	var first_flight_entry := not is_instance_valid(interior)
	prepare_interior()
	_bg_yaw = yaw
	_bg_pitch = pitch
	_bg_fpv = first_person
	_bg_footer = hud.footer.text
	_release_follow_camera()
	_interior_open = true
	_bind_interior_vessel(vessel)
	interior.open(via_airlock)
	if interior.has_method("sync_to_ship"):
		interior.sync_to_ship(vessel)
	if via_airlock:
		yaw = -PI * 0.5   # facing into the ship from the side hatch
		pitch = -0.08
		hud.toast("ABOARD · walk to the COCKPIT and press E to take the pilot seat", 3.5)
		return
	if first_flight_entry:
		yaw = 0.0
		pitch = 0.0
	hud.toast("INSIDE THE SPACECRAFT · [I] / TAB back to pilot view", 3.5)


func exit_interior(free_it := false) -> void:
	if not interior_active():
		return
	_interior_open = false
	interior.close()
	_bind_interior_vessel(null)
	yaw = _bg_yaw
	pitch = _bg_pitch
	first_person = _bg_fpv
	_release_follow_camera()
	hud.footer.text = _bg_footer
	hud.crosshair.visible = true

	if free_it or not piloting:
		_free_interior()


func _free_interior() -> void:
	_interior_open = false
	_bind_interior_vessel(null)
	if interior != null and is_instance_valid(interior):
		interior.hide()
		interior.queue_free()
	interior = null


func _live_interior_vessel() -> Node3D:
	if piloting and is_instance_valid(vessel):
		return vessel.ship
	if world is PlanetA:
		return world.ship_root
	if world is Flight:
		return world.ship
	return null


func _bind_interior_vessel(vessel: Node3D) -> void:
	if _interior_vessel != vessel:
		if is_instance_valid(_interior_vessel):
			ShipModel.set_interior_cutaway(_interior_vessel, false)
		_interior_vessel = vessel
	if is_instance_valid(interior) and interior.has_method("set_cutaway_target"):
		interior.set_cutaway_target(vessel)


func _tick_interior(dt: float) -> void:
	var vessel := _live_interior_vessel()
	if not is_instance_valid(vessel):
		exit_interior(true)
		return
	_bind_interior_vessel(vessel)
	if interior.has_method("sync_to_ship"):
		interior.sync_to_ship(vessel)
	interior.tick(dt)


func _play_common(_dt: float) -> void:
	if pressed(KEY_H):
		hud.show_control_hints()
	if sim != null and arena_clash == null and pressed(KEY_M):
		hud.toggle_tactical()
	if piloting and not interior_active():
		return
	if arena_clash != null:
		if pressed(KEY_V):
			first_person = not first_person
		return
	if sim == null:
		if pressed(KEY_V):
			first_person = not first_person
		return
	for i in 4:
		if pressed(KEY_1 + i) and net.mode != "CLIENT":
			if sim.selected != i:
				sim.selected = i
				hud.toast("Now playing %s / %s" % [Sim.SPECIALISTS[i]["name"], Sim.SPECIALISTS[i]["role"]], 1.8)
				if world and world.has_method("on_role_changed"):
					world.on_role_changed()
	if pressed(KEY_V):
		first_person = not first_person


func _refresh_hud() -> void:
	var flying := piloting and not interior_active()
	hud.radar.heading = vessel.basis.get_euler().y if flying and is_instance_valid(vessel) else yaw
	hud.flight_panel.visible = flying
	hud.get_node("CrewAdvisor").visible = arena_clash == null and not flying and hud.advisor_hints
	hud.location_label.text = "SPACE" if sim.in_space() else Universe.PLANETS[sim.location]["label"]
	if arena_clash != null:
		hud.clock.text = arena_clock()
		if flying or not world is PlanetA:
			_arena_surface_hud.hide_vitals()
		else:
			var unit := arena_clash.combatant("%s:%d" % [arena_clash.player_squad, sim.selected])
			var bonus := arena_clash.get_bonuses(arena_clash.player_squad)
			_arena_surface_hud.primary_weapon_only = true
			_arena_surface_hud.vitals_limits = Vector2(ArenaClashRules.BASE_HEALTH + bonus["max_health"], ArenaClashRules.BASE_SHIELD + bonus["shield"])
			_arena_surface_hud.set_vitals(unit.get("health", ArenaClashRules.BASE_HEALTH), unit.get("shield", ArenaClashRules.BASE_SHIELD), 0, 24, false)
		var score := arena_clash.get_score()
		hud.set_match_score(score["planet_a"], score["planet_b"], arena_clash.kill_target)
		for i in 4:
			var unit := arena_clash.combatant("%s:%d" % [arena_clash.player_squad, i])
			var ratio: float = float(unit.get("health", 100.0)) / (ArenaClashRules.BASE_HEALTH + arena_clash.get_bonuses(arena_clash.player_squad)["max_health"])
			hud.set_crew_status(i, "YOU" if i == sim.selected else ("READY" if unit.get("alive", true) else "RESPAWNING"), ratio)
			if hud.style_selected != sim.selected:
				hud.crew_cards[i]["panel"].add_theme_stylebox_override("panel", UI.glass_style(UI.PANEL, 8, UI.ACCENT if i == sim.selected else UI.BG_DEEP))
		hud.style_selected = sim.selected
	elif sim != null:
		hud.update_common(sim, sim.selected)
		hud.update_empire(sim)
	hud.objectives.get_parent().get_parent().visible = sim.in_space() if flying else not (arena_clash != null and world is PlanetB)
	if piloting:
		if interior_active():
			interior.hud_update(hud)
		else:
			vessel.hud_update(hud)
	elif arena_clash != null and world is PlanetA:
		_update_arena_travel_hud()
	elif world and world.has_method("hud_update"):
		world.hud_update(hud)


func drive(a: Actor, dt: float, gravity := 22.0, speed_mul := 1.0) -> float:
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
	if _boarding_auto and a == player_actor():
		if dir.length() > 0.1:
			_boarding_auto = false   # the player took the controls back
		elif _ramp_live():
			dir = _boarding_walk_dir(a)
	var sprinting := held(KEY_SHIFT)
	var speed := (8.4 if sprinting else 5.4) * speed_mul
	a.tick_motion(dt)
	if pressed(KEY_ALT) and sim != null and sim.on_surface("planet_c"):
		if a.trigger_dash(dir):
			sfx("reload_click", -4.0, 0.15)
			hud.toast("DASH", 0.5)
	if a.dash_active():
		a.move_vel = a.dash_dir * Actor.DASH_SPEED
	else:
		var want := dir * speed
		var rate := Actor.ACCEL if want.length() > a.move_vel.length() * 0.98 or want.length() > 0.01 else Actor.DECEL
		a.move_vel = a.move_vel.move_toward(want, rate * dt)
	var previous := a.position
	a.position += a.move_vel * dt
	var floor_height := 0.0
	var on_ramp := false
	var on_surface: bool = not interior_active() and sim != null and (world is PlanetA or world is PlanetB) and a.get_parent() == world
	var ramp_origin: Vector3 = universe.to_local(world.global_position) if on_surface else Vector3.ZERO
	if on_surface:
		floor_height = universe.surface_height(sim.location, a.position)
		if _ramp_live():
			var deck: float = boarding_ramp.floor_at(a.position + ramp_origin)
			if deck > -INF and a.position.y >= deck - ramp_origin.y - BoardingRamp.STEP_UP:
				floor_height = maxf(floor_height, deck - ramp_origin.y)
				on_ramp = true
	var grounded := a.position.y <= floor_height + 0.001
	if grounded:
		a.coyote_t = Actor.COYOTE_TIME
	if pressed(KEY_SPACE):
		a.jump_buf_t = Actor.JUMP_BUFFER_TIME
	if a.jump_buf_t > 0.0 and (grounded or a.coyote_t > 0.0) and a.vy <= 0.001:
		a.vy = 8.0
		a.jump_buf_t = 0.0
		a.coyote_t = 0.0
	a.vy -= gravity * dt
	a.position.y = maxf(floor_height, a.position.y + a.vy * dt)
	landing_impact = maxf(0.0, -a.vy) if not grounded and a.position.y <= floor_height else 0.0
	if a.position.y <= floor_height:
		a.vy = 0.0
	if on_ramp or (on_surface and _ramp_live() and boarding_ramp.in_lane(a.position + ramp_origin)):
		pass   # the ramp lane has its own rails; hull blockers would push walkers off it
	elif world and world.has_method("collide"):
		a.position = world.collide(a.position)
		if on_surface and _ramp_live():
			# Only write back when pushed: the round trip through the far planet origin costs float precision.
			var probe := a.position + ramp_origin
			var pushed := boarding_ramp.block(probe)
			if pushed != probe:
				a.position = pushed - ramp_origin
	if first_person:
		a.heading = yaw
		a.rotation.y = yaw
	elif dir.length() > 0.0:
		a.face(dir, dt, 12.0)
	var move_speed := Vector2(a.move_vel.x, a.move_vel.z).length()
	var ground_travel := 0.0
	if move_speed > 0.0 and dt > 0.0:
		ground_travel = clampf((a.position - previous).dot(a.move_vel) / (move_speed * dt), 0.0, move_speed)
	var step_index := a.step_index
	a.player_step_pending = true
	var step := a.poll_step(dt, ground_travel)
	if step != "" and world is PlanetB:
		sfx_3d(step, a.global_position, -14)
	sprinting = sprinting and dir.length_squared() > 0.01 and ground_travel > 0.6 \
		and a.position.y <= floor_height + 0.001 and not a.dash_active()
	sprint_step = sprinting and a.step_index != step_index
	_update_foot_camera(a, dt, sprinting, ground_travel / maxf(speed, 0.01))
	if sprint_step and world is PlanetA and interior == null and not UI.reduced_motion:
		CombatFX.dust_puff(world, a.position, Color("#b5a797"), 0.55)
	return move_speed


func _update_foot_camera(a: Actor, dt: float, sprinting: bool, speed_fraction: float) -> void:
	var motion := not UI.reduced_motion and GraphicsSettings.motion_effects
	if a != _foot_camera_actor or not motion:
		_stride_blend = 0.0
		_sprint_fov = 0.0
		_step_kick = 0.0
		_landing_kick = 0.0
	_foot_camera_actor = a
	_foot_camera_driven = true
	if not motion:
		return
	if a.position.y <= 0.001 and speed_fraction > 0.0:
		_stride_phase = (float(a.step_index % 2) + a.step_clock / FOOTSTEP_INTERVAL) * PI
	var strength := smoothstep(0.15, 0.85, speed_fraction) if sprinting else 0.0
	_stride_blend = lerpf(_stride_blend, strength, 1.0 - exp(-12.0 * dt))
	_sprint_fov = lerpf(_sprint_fov, strength * SPRINT_FOV, 1.0 - exp(-8.0 * dt))
	_step_kick = 1.0 if sprint_step else move_toward(_step_kick, 0.0, dt / 0.11)
	_landing_kick = move_toward(_landing_kick, 0.0, dt / 0.23)
	if landing_impact > 0.0:
		_landing_kick = clampf(landing_impact / 8.0, 0.0, 1.0)


func _earth_crane_camera_active() -> bool:
	return world is PlanetA and world.is_crane_camera_active()


func _update_earth_crane_camera(dt: float, previous_camera: Transform3D) -> void:
	var active := _earth_crane_camera_active()
	var crane_label := ""
	var weight := 1.0 - exp(-10.0 * dt)
	if active:
		var pose: Dictionary = world.crane_camera_pose()
		crane_label = pose.get("label", "")
		var position: Vector3 = pose["pos"]
		var target: Vector3 = pose["target"]
		cam.global_transform = previous_camera
		cam.global_position = previous_camera.origin.lerp(position, weight)
		var direction := target - cam.global_position
		if not direction.is_zero_approx():
			var up := Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > 0.999 else Vector3.UP
			cam.look_at(target, up)
			cam.global_basis = previous_camera.basis.slerp(cam.global_basis, weight)
		_crane_camera_return = 0.6
	elif _crane_camera_return > 0.0:
		_crane_camera_return = maxf(0.0, _crane_camera_return - dt)
		if _crane_camera_return > 0.0:
			cam.global_transform = previous_camera.interpolate_with(cam.global_transform, weight)
	if active != _crane_camera_active:
		_crane_camera_active = active
		if active:
			_release_follow_camera()
		hud.set_crane_mode(active, crane_label)


func _release_follow_camera() -> void:
	if is_instance_valid(_view_actor):
		_set_actor_view(_view_actor, false)
		cam.fov = _follow_fov
		cam.near = _follow_near
	_view_actor = null
	_view_in_first_person = false
	_foot_camera_actor = null
	_foot_camera_driven = false


func _set_actor_view(a: Actor, fpv: bool) -> void:
	a.get_node("Holder").visible = not fpv
	a.ring.visible = not fpv
	if a.has_method("set_fpv_active"):
		a.call("set_fpv_active", fpv)


func follow_cam(a: Actor, dist := 6.8) -> void:
	if _crane_camera_active and world is PlanetA:
		first_person = false
	if not _foot_camera_driven:
		_foot_camera_actor = null
	if a != _view_actor:
		if is_instance_valid(_view_actor):
			_set_actor_view(_view_actor, false)
		_view_actor = a
		_set_actor_view(a, first_person)
	elif first_person != _view_in_first_person:
		_set_actor_view(a, first_person)
	_view_in_first_person = first_person
	var motion := _foot_camera_driven and _foot_camera_actor == a and mode == "play" \
		and not UI.reduced_motion and GraphicsSettings.motion_effects
	cam.fov = _follow_fov + (_sprint_fov if motion else 0.0)
	cam.near = FPV_NEAR if first_person else _follow_near
	cam.rotation = Vector3(pitch, yaw, 0)
	var fwd := -cam.transform.basis.z
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var offset := Vector3.ZERO
	if motion:
		var view_scale := 1.0 if first_person else 0.24
		var sway := sin(_stride_phase) * _stride_blend
		var bob := -cos(_stride_phase * 2.0) * _stride_blend
		var step_dip := _step_kick * _step_kick
		var land_dip := _landing_kick * _landing_kick
		var land_shake := sin(_landing_kick * TAU) * _landing_kick
		offset = (right * (0.035 * sway + 0.02 * land_shake) \
			+ Vector3.UP * (0.045 * bob - 0.018 * step_dip - 0.14 * land_dip)) * view_scale
		cam.rotation.x += (0.009 * bob - 0.009 * step_dip - 0.04 * land_dip) * view_scale
		cam.rotation.z += (0.018 * sway + 0.009 * land_shake) * view_scale
	if first_person:
		var eye := a.position + Vector3.UP * (a.visual_height * 0.9)
		cam.position = eye + Vector3(-sin(yaw), 0, -cos(yaw)) * 0.16 + offset
	else:
		var target := a.position + Vector3(0, a.visual_height * 0.9 + 0.15, 0) + right * 0.6
		var p := target - fwd * dist + offset
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
func new_sim(skip_empire := false) -> void:
	_clear_arena_clash()
	_free_interior()
	var preset: String = net.match_preset if net.is_online() else opts["length"]
	var seed_value: int = net.world_seed if net.is_online() else int(opts.get("seed", 0))
	sim = Sim.new(seed_value, _match_difficulty(), opts["length"] if opts["length"] == "long" else "standard")
	var assignment := _local_empire_assignment()
	if not skip_empire and preset in ["standard", "short"] and (net.is_online() or (LobbyPages.play_mode == "ranked" and not autotest)):
		if net.mode != "CLIENT" or not assignment.is_empty():
			sim.enable_empire(preset, assignment.get("squad_id", "orange"), request_empire_action)
	_empire_sync_ready = false
	_empire_broadcast_time = 0.0
	_empire_sabotage.clear()
	_empire_last_shot.clear()
	sim.selected = opts["selected"]
	for id in opts["upgrades"]:
		sim.set_upgrade(id, true)
	event_index = 0
	if ff != Engine.time_scale:
		ff = 1.0


var _loading_layer: CanvasLayer
var loading_screen: LoadingScreen
var _loading_active := false


func _show_loading_screen() -> LoadingScreen:
	_dismiss_loading_screen()
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 200
	add_child(_loading_layer)
	loading_screen = LoadingScreen.new()
	_loading_layer.add_child(loading_screen)
	loading_screen.set_progress(0.0, "Initializing launch complex...")
	return loading_screen


func _dismiss_loading_screen() -> void:
	if is_instance_valid(_loading_layer):
		_loading_layer.queue_free()
	_loading_layer = null
	loading_screen = null


func _load_step(ls: LoadingScreen, pct: float, text: String) -> void:
	if ls != null and is_instance_valid(ls):
		ls.set_progress(pct, text)


## Show the loading screen while the home surface and crew are created.
func start_match_with_loading() -> void:
	if _loading_active or net.mode == "CLIENT":
		return
	await _run_start_match(_show_loading_screen())


## Synchronous entry (tests, DROP IN, rematch): runs every step without yielding.
func start_match() -> void:
	if not _loading_active and net.mode != "CLIENT":
		_run_start_match(null)


func _run_start_match(ls: LoadingScreen) -> void:
	_loading_active = ls != null
	_apply_hud_layout()
	_load_step(ls, 5.0, "Clearing menus...")
	var arena_selected := _arena_selected()
	if arena_selected or sim == null or arena_clash != null or (LobbyPages.play_mode == "practice" and sim.difficulty != LobbyPages.PRACTICE_DIFFICULTY):
		new_sim(arena_selected)
	sim.selected = _local_empire_assignment().get("seat_index", opts["selected"]) if net.mode == "CLIENT" else opts["selected"]
	if arena_selected:
		_start_arena_clash()
	sim.auto_build["enabled"] = arena_clash == null and opts["fast"]
	sim.shop_open = arena_clash == null and not sim.all_parts_bought()   # modules are bought in the 3D parts shop
	clear_menu()
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	showcase = null
	if ls != null: await get_tree().process_frame
	_load_step(ls, 20.0, "Building universe & environment...")
	drop_universe()
	ensure_universe()
	if ls != null: await get_tree().process_frame
	_load_step(ls, 40.0, "Constructing launch complex, workshop & ships...")
	if ls != null: await get_tree().process_frame
	var a := _ensure_home_world()
	a.ship_root.show()
	sim.set_location(home_alliance())
	_load_step(ls, 75.0, "Spawning crews & audio...")
	if ls != null: await get_tree().process_frame
	enter_world(a, Transform3D(Basis.IDENTITY, home_origin()))
	_load_step(ls, 90.0, "Powering up HUD...")
	if ls != null: await get_tree().process_frame
	hud.visible = true
	hud.set_mode(arena_clash != null)
	hud.show_control_hints()
	hud.update_shop(sim)
	yaw = PI * 0.15
	pitch = -0.25
	mode = "play"
	first_person = false
	capture_mouse(true)
	_refresh_hud()
	_publish_empire_start()
	_load_step(ls, 100.0, "Ready to play")
	if ls != null: await get_tree().process_frame
	_loading_active = false
	_dismiss_loading_screen()


func quick_deploy() -> void:
	if _loading_active or net.mode == "CLIENT":
		return
	new_sim(_arena_selected())
	start_match()
	sim.quick_deploy = true
	if arena_clash != null:
		var squad := arena_clash.player_squad
		for slot: String in ArenaClashRules.FLIGHT_PARTS:
			sim.buy_part(slot)
		arena_clash.tick(ArenaClashRules.BUILD_SECONDS)
		home_world().sync_arena_build()
	else:
		for part: Dictionary in sim.parts:
			sim.buy_part(part["id"])
		sim.shop_open = false
		sim.auto_build["enabled"] = true
		sim.auto_assemble(Sim.AUTO_BUILD_SECONDS)
	board_ship()
	_refresh_hud()


func rematch() -> void:
	if net.mode == "CLIENT":
		return
	var seed_value: int = sim.match_seed
	var quick: bool = sim.quick_deploy
	opts["seed"] = seed_value
	if quick: quick_deploy()
	else: new_sim(); start_match()
	opts["seed"] = 0


func home_alliance() -> String:
	if arena_clash != null:
		return arena_clash.squads[arena_clash.player_squad]["alliance"]
	return sim.empire_home if sim != null else "planet_a"


func home_origin() -> Vector3:
	return Universe.B_ORIGIN if home_alliance() == "planet_b" else Universe.A_ORIGIN


func home_label() -> String:
	return Universe.B_LABEL if home_alliance() == "planet_b" else Universe.A_LABEL


func home_world() -> PlanetA:
	return world_planet_b if home_alliance() == "planet_b" else world_a


func _ensure_home_world() -> PlanetA:
	return _ensure_earth_world(home_alliance())


func _ensure_earth_world(planet: String) -> PlanetA:
	if planet == "planet_b":
		return _ensure_world_planet_b()
	if world_a == null:
		world_a = PlanetA.new()
		world_a.setup(self, false, "planet_a")
		universe.add_child(world_a)
	return world_a


func _ensure_world_planet_b() -> PlanetA:
	if world_planet_b == null:
		world_planet_b = PlanetA.new()
		world_planet_b.setup(self, false, "planet_b")
		world_planet_b.position = Universe.B_ORIGIN
		universe.add_child(world_planet_b)
		world_planet_b.ship_root.hide()
	return world_planet_b


func _ensure_world_b() -> void:
	if world_b == null:
		world_b = PlanetB.new()
		world_b.setup(self)
		world_b.position = Universe.C_ORIGIN
		universe.add_child(world_b)
		world_b.hide_ship()


func board_ship() -> bool:
	if piloting or sim.in_space() or not sim.flight_capable():
		return false
	if sim.flag_counts(0)["carried"] > 0:
		hud.toast("Load or drop carried flags before boarding.")
		return false
	exit_interior(true)
	_release_follow_camera()
	if not is_instance_valid(vessel):
		vessel = Flight.new()
		universe.add_child(vessel)
		vessel.setup(self, home_world().accent)
		vessel.position = Universe.PLANETS[sim.location]["origin"]
		vessel.position += world.ship_root.position
	vessel.sync_modules()
	if world is PlanetA:
		world.ship_root.hide()
	else:
		world.hide_ship()
	if world is PlanetB and world.combat_hud != null:
		world.combat_hud.hide()
	for seat in 4:
		var crew: Actor = world.actor(seat)
		if crew != null:
			crew.hide()
	if arena_clash != null and world is PlanetB:
		world.set_arena_aboard(true)
	piloting = true
	vessel.update_camera()
	_set_audio_mode("flight")
	capture_mouse(true)
	return true


func cockpit_position() -> Vector3:
	## Where the crew board: the foot of the belly ramp (falls back to the old nose spot without a parked ship).
	var cabin = _parked_cabin_frame()
	if cabin != null:
		var pose := BoardingRamp.compute_pose(cabin, _ground_global)
		var point: Vector3 = pose["foot"] - pose["axis"] * 1.1 - _surface_origin()
		point.y = universe.surface_height(sim.location, point)
		return point
	var fallback := Transform3D.IDENTITY
	if is_instance_valid(vessel):
		fallback = Transform3D(vessel.basis, vessel.position - _surface_origin())
	elif world is PlanetA:
		fallback.origin = world.ship_root.position
	return fallback * (Vector3(8.5, 0, -10.5) * ShipModel.VESSEL_SCALE)


func cockpit_prompt(at: Vector3) -> bool:
	if not sim.flight_capable():
		return false
	var on_deck := _ramp_live() and boarding_ramp.on_deck(at + _surface_origin())
	if not on_deck and not _boarding_auto and flat_dist(at, cockpit_position()) > 4.0:
		return false
	if not _ramp_live():
		hud.set_prompt("BOARDING RAMP", "Ramp lowering…")
		return true
	if _boarding_auto:
		hud.set_prompt("BOARDING", "Climbing the ramp into the airlock · move to cancel")
		return true
	hud.set_prompt("E  BOARD SHIP", "Walk up through the hatch, or press E to climb aboard" if on_deck
		else "Walk up the boarding ramp into the airlock")
	if pressed(KEY_E):
		_boarding_auto = true
	return true


## Cabin frame (ShipInterior's transform) of the spacecraft parked on this surface, or null.
func _parked_cabin_frame() -> Variant:
	if sim == null or sim.in_space() or not Universe.PLANETS.has(sim.location) or not (world is PlanetA or world is PlanetB):
		return null
	var ship: Node3D = null
	if is_instance_valid(vessel) and vessel.is_inside_tree() and is_instance_valid(vessel.ship):
		ship = vessel.ship
	elif world is PlanetA and is_instance_valid(world.ship_root) and world.ship_root.is_inside_tree():
		ship = world.ship_root
	if ship == null:
		return null
	# Universe-local frame: the universe node floats, the planet origins are authored in its space.
	var xf := universe.global_transform.affine_inverse() * ship.global_transform
	return Transform3D(xf.basis.orthonormalized(), xf.origin + xf.basis * ShipInteriorScript.CABIN_OFFSET)


func _surface_origin() -> Vector3:
	if sim != null and Universe.PLANETS.has(sim.location):
		return Universe.PLANETS[sim.location]["origin"]
	return Vector3.ZERO


func _ground_global(p: Vector3) -> float:
	var origin := _surface_origin()
	return universe.surface_height(sim.location, p - origin) + origin.y


func _ramp_live() -> bool:
	return boarding_ramp != null and is_instance_valid(boarding_ramp) and boarding_ramp.is_deployed()


## Auto-walk for E at the ramp: to the foot first, then straight up the deck through the hatch.
func _boarding_walk_dir(a: Actor) -> Vector3:
	var gp := universe.to_local(a.global_position)
	var target: Vector3 = boarding_ramp.top + boarding_ramp.axis * 0.6
	if not boarding_ramp.on_deck(gp):
		target = boarding_ramp.foot + boarding_ramp.axis * 0.4
	var d := target - gp
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else boarding_ramp.axis


func _tick_boarding_ramp(dt: float) -> void:
	var cabin = _parked_cabin_frame() if _travel_destination == "" else null
	if cabin == null:
		_boarding_auto = false
		if boarding_ramp != null and is_instance_valid(boarding_ramp):
			boarding_ramp.want = false
			boarding_ramp.visible = false
			boarding_ramp.deploy = 0.0
		return
	if boarding_ramp == null or not is_instance_valid(boarding_ramp):
		boarding_ramp = BoardingRamp.new()
		universe.add_child(boarding_ramp)
	var grounded := not is_instance_valid(vessel) or vessel.grounded
	boarding_ramp.want = sim.flight_capable() and grounded
	boarding_ramp.sync(cabin, _ground_global)
	var player := player_actor() if not piloting else null
	var walking := player != null and player.visible
	var gp := universe.to_local(player.global_position) if walking else Vector3.ZERO
	# Label reads from a distance; up close the ramp itself is the cue.
	var d_foot := boarding_ramp.foot.distance_to(gp) if walking else INF
	var near := walking and d_foot < 26.0 and d_foot > 7.0 and not boarding_ramp.on_deck(gp)
	boarding_ramp.tick(dt, near)
	_boarding_block_cd = maxf(0.0, _boarding_block_cd - dt)
	if not walking:
		_boarding_auto = false
		return
	if boarding_ramp.on_deck(gp) and boarding_ramp.progress(gp) >= BoardingRamp.ENTER_AT:
		_enter_ship_via_ramp(player)


## The player stepped through the hatch: the crew is aboard and the cabin opens at the airlock.
func _enter_ship_via_ramp(player: Actor) -> void:
	_boarding_auto = false
	if sim.flag_counts(0)["carried"] > 0:
		if _boarding_block_cd <= 0.0:
			hud.toast("Load or drop carried flags before boarding.")
			_boarding_block_cd = 2.0
		player.position -= boarding_ramp.axis * 0.8
		return
	if not board_ship():
		return
	sfx("reload_click", -6.0)
	enter_interior(true)


## Leave the parked ship from the airlock: out through the hatch onto the top of the ramp.
func exit_ship_on_foot() -> void:
	if not piloting or not is_instance_valid(vessel) or not vessel.grounded or sim.in_space():
		return
	exit_interior(true)
	disembark_ship()


func disembark_ship() -> void:
	if not piloting or not vessel.grounded or sim.in_space():
		return
	piloting = false
	_boarding_auto = false
	# Flight kept the universe centred on the ship; on foot the surface world must sit at the origin
	# again, because the follow camera works in world-local coordinates.
	if world is PlanetA or world is PlanetB:
		universe.focus_xf(world.transform)
	var exit := cockpit_position()
	var out := Vector3.ZERO
	var deck_y := 0.0
	var cabin = _parked_cabin_frame()
	if cabin != null:
		if boarding_ramp == null or not is_instance_valid(boarding_ramp):
			boarding_ramp = BoardingRamp.new()
			universe.add_child(boarding_ramp)
		boarding_ramp.sync(cabin, _ground_global)
		boarding_ramp.want = true
		boarding_ramp.deploy = 1.0
		boarding_ramp.tick(0.0, false)
		exit = boarding_ramp.exit_point() - _surface_origin()
		deck_y = boarding_ramp.floor_at(boarding_ramp.exit_point()) - _surface_origin().y
		out = -boarding_ramp.axis
	yaw = atan2(-out.x, -out.z) if out != Vector3.ZERO else vessel.basis.get_euler().y
	pitch = -0.2
	if world is PlanetB:
		world.combat_hud.show()
		if arena_clash != null:
			world.set_arena_aboard(false)
	var line := 0
	for seat in 4:
		var crew: Actor = world.actor(seat)
		if crew != null:
			if out != Vector3.ZERO and seat == sim.selected:
				# The player steps out of the hatch onto the top of the ramp and walks down.
				crew.position = exit
				crew.position.y = deck_y
			elif out != Vector3.ZERO:
				# The rest of the crew is already down at the foot, fanned out beside the ramp.
				line += 1
				var foot: Vector3 = boarding_ramp.foot - _surface_origin()
				crew.position = foot + out * (1.4 + 0.6 * line) + boarding_ramp.side * (line - 2) * 1.1
				crew.position.y = universe.surface_height(sim.location, crew.position)
			else:
				crew.position = exit + vessel.basis.x * (seat - 1.5) * 0.85
				crew.position.y = universe.surface_height(sim.location, crew.position)
			crew.move_vel = Vector3.ZERO
			crew.vy = 0.0
			if out != Vector3.ZERO:
				crew.heading = yaw
				crew.rotation.y = yaw
			if arena_clash == null or not (world is PlanetB) or arena_clash.combatant("%s:%d" % [arena_clash.player_squad, seat]).get("alive", false):
				crew.show()
	_set_audio_mode("moon" if world is PlanetB else "earth")
	var player := player_actor()
	if player != null:
		follow_cam(player)


func leave_surface() -> void:
	if _travel_destination == "" and not sim.in_space():
		_begin_travel("space")


func request_landing(planet: String) -> void:
	if _travel_destination == "" and sim.in_space() and vessel.arrival == planet:
		_begin_travel(planet)


func _begin_travel(destination: String) -> void:
	exit_interior(true)
	_travel_destination = destination
	_travel_time = 0.0
	_travel_swapped = false
	if not is_instance_valid(_travel_fade):
		var layer := CanvasLayer.new()
		layer.layer = 90
		add_child(layer)
		_travel_fade = ColorRect.new()
		_travel_fade.color = Color.TRANSPARENT
		_travel_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_travel_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_travel_fade)
	_travel_fade.show()


func _tick_travel(dt: float) -> void:
	_travel_time += dt
	var opacity := clampf(_travel_time / TRAVEL_FADE_SECONDS, 0.0, 1.0)
	if _travel_time >= TRAVEL_FADE_SECONDS:
		if not _travel_swapped:
			_travel_swapped = true
			_travel_fade.color = Color.BLACK
			_swap_flight_location(_travel_destination)
			return
		opacity = clampf(2.0 - _travel_time / TRAVEL_FADE_SECONDS, 0.0, 1.0)
	_travel_fade.color = Color(0, 0, 0, opacity)
	if _travel_time >= TRAVEL_FADE_SECONDS * 2.0:
		_travel_fade.hide()
		_travel_destination = ""


func _swap_flight_location(destination: String) -> void:
	var previous := sim.location
	sim.set_location(destination)
	if destination == "space":
		var origin: Vector3 = Universe.PLANETS[previous]["origin"]
		var radial := (Vector3.UP + vessel.forward() * 0.35).normalized()
		vessel.position = origin + radial * (universe.body_radius(previous) + 500.0)
		vessel.arrival = ""
		vessel.enter_space()
		set_world(vessel)
		_update_squad_location()
	elif destination == "planet_c":
		_ensure_world_b()
		enter_world(world_b, Transform3D(Basis.IDENTITY, Universe.C_ORIGIN))
		world_b.combat_hud.hide()
		if arena_clash != null:
			world_b.set_arena_aboard(true)
			world_b.start_arena()
		var bay := world_b.landing_zone()
		vessel.begin_approach(bay, Basis.IDENTITY)
	else:
		var earth := _ensure_earth_world(destination)
		var origin: Vector3 = Universe.PLANETS[destination]["origin"]
		enter_world(earth, Transform3D(Basis.IDENTITY, origin))
		earth.ship_root.hide()
		vessel.begin_approach(earth.ship_root.position, Basis.IDENTITY)
	vessel.update_camera()
	universe.tick(0.0)


func on_touchdown() -> void:
	_update_squad_location()
	if arena_clash != null and world is PlanetB:
		world.start_arena()
		world.set_arena_aboard(true)


func _update_squad_location() -> void:
	if arena_clash != null:
		arena_clash.set_squad_location(arena_clash.player_squad, sim.location)
	if sim.empire != null:
		request_empire_action("squad_stage", {"stage": sim.location})


# ============================================================================
# Menus
# ============================================================================
func _ensure_showcase() -> void:
	if showcase == null or not is_instance_valid(showcase):
		showcase = PlanetA.showcase(self)
		set_world(showcase)


func show_home() -> void:
	_clear_arena_clash()
	_free_interior()
	mode = "menu"
	_set_audio_mode("menu")
	hud.visible = false
	capture_mouse(false)
	sim = null
	_empire_sync_ready = false
	net.disconnect_match()
	_ensure_showcase()
	showcase.layout("home", opts["selected"])
	_lobby_shown_tab = ""
	clear_menu()
	var root := UI.vbox(14)
	root.position = Vector2(56, 120)
	root.custom_minimum_size = Vector2(620, 0)
	menu_root.add_child(root)
	_brand(menu_root)
	root.add_child(UI.label(LobbyPages.EMPIRE_HOME_LABEL, 12, UI.ACCENT))
	root.add_child(UI.heading("BUILD. CAPTURE.\n", "BRING IT HOME.", 66))
	root.add_child(UI.label("Build a ship, raid the opposing empire, and fly Science Flags home.\nOnly delivered flags score.", 15, UI.MUTED))
	root.add_child(UI.spacer(8))
	root.add_child(_input_mode_selector())
	root.add_child(UI.button("SQUAD LOBBY   ↗", show_select, true, 520, 54))
	root.add_child(UI.button("MISSION DESIGN & SCIENCE SIMULATOR   ↗", show_mission_control, false, 520))
	root.add_child(UI.button("FIELD MANUAL   ↗", show_help, false, 520))
	root.add_child(UI.button("SETTINGS", show_settings, false, 520))
	root.add_child(UI.button("QUIT", get_tree().quit, false, 520))
	root.add_child(UI.spacer(10))
	root.add_child(UI.label("●  1 HUMAN + 15 CLEARLY MARKED BOTS   ·   3 AI RIVAL TEAMS", 11, UI.MUTED))
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color("#060d18", 0.78), Color("#060d18", 0.62), Color("#060d18", 0.0)])
	var vignette_texture := GradientTexture2D.new()
	vignette_texture.gradient = gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(1.0, 0.86)
	vignette_texture.fill_to = Vector2(0.06, 0.86)
	var vignette := TextureRect.new()
	vignette.texture = vignette_texture
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	vignette.offset_left = -680.0
	vignette.offset_top = -340.0
	vignette.offset_right = 0.0
	vignette.offset_bottom = 0.0
	menu_root.add_child(vignette)
	menu_root.move_child(vignette, 0)
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


func _brand(parent: Control) -> void:
	var b := UI.heading("T", "-MINUS", 32)
	b.position = Vector2(40, 26)
	b.size = Vector2(300, 44)
	parent.add_child(b)
	var sub := UI.label("THE FIRST FRONTIER", 10, UI.MUTED)
	sub.position = Vector2(42, 66)
	parent.add_child(sub)


var _lobby_play_btn: Button
var _lobby_tab := "PLAY"


func _lobby_set_tab(tab: String) -> void:
	_lobby_tab = tab
	sfx("ui_click", -10.0)
	show_select()
	if showcase and is_instance_valid(showcase) and showcase.has_method("set_focus"):
		showcase.set_focus(_lobby_tab)


func _lobby_set_mode(m: String) -> void:
	if m == LobbyPages.play_mode or net.is_online():
		return
	LobbyPages.play_mode = m
	sim = null
	LobbyPages.save_profile(settings_path)
	show_select()


func _match_difficulty() -> String:
	return LobbyPages.PRACTICE_DIFFICULTY if LobbyPages.play_mode == "practice" else opts["difficulty"]


func _lobby_shop_action(op: String, id: String) -> void:
	if LobbyPages.apply_shop_action(op, id, settings_path):
		sfx("ui_buy", -8.0)
		show_select()


## Slow breathing scale + glow pulse on the lobby PLAY button (skipped with reduced motion).
func _start_play_pulse() -> void:
	var btn := _lobby_play_btn
	if not is_instance_valid(btn) or UI.reduced_motion:
		return
	btn.pivot_offset = Vector2(160, 28)
	var tw := btn.create_tween().set_loops()
	tw.set_parallel(true)
	tw.tween_property(btn, "scale", Vector2(1.03, 1.03), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(btn, "self_modulate", Color(1.18, 1.14, 0.9), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_property(btn, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(btn, "self_modulate", Color.WHITE, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


var _lobby_shown_tab := ""


## Slide + fade a lobby control in. Waits one frame so container layout settles first.
func _lobby_slide_in(c: Control, offset: Vector2, delay := 0.0) -> void:
	if c == null or UI.reduced_motion:
		return
	c.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	var end_pos := c.position
	c.position = end_pos + offset
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.38).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position", end_pos, 0.45).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func show_select() -> void:
	# Only play the entrance on a fresh page/tab; re-selecting a specialist just refreshes in place.
	var fresh := _lobby_shown_tab != _lobby_tab
	_lobby_shown_tab = _lobby_tab
	mode = "menu"
	_set_audio_mode("menu")
	UI.on_hover_sfx = sfx.bind("ui_click", -18.0)
	_ensure_showcase()
	showcase.layout("select", opts["selected"])
	if showcase.has_method("set_focus"):
		showcase.set_focus(_lobby_tab)
	clear_menu()
	_brand(menu_root)
	var tabs := LobbyPages.build_tab_bar(_lobby_tab, _lobby_set_tab)
	tabs.position = Vector2(36, 70)
	menu_root.add_child(tabs)
	if _lobby_tab != "PLAY":
		var page: Control
		match _lobby_tab:
			"SHOP": page = LobbyPages.build_shop(_lobby_shop_action)
			"LEADERBOARD": page = LobbyPages.build_leaderboard()
			"PROFILE": page = LobbyPages.build_profile()
			_: page = LobbyPages.build_guide()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.offset_left = 40
		page.offset_right = -40
		page.offset_top = 120
		page.offset_bottom = -110
		menu_root.add_child(page)
		if fresh:
			_lobby_slide_in(page, Vector2(0, 28))
		var back := UI.hbox(10)
		back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		back.position = Vector2(-160, -84)
		back.add_child(UI.button("BACK", show_home, false, 110, 48))
		menu_root.add_child(back)
		return
	var head := UI.vbox(2)
	head.position = Vector2(36, 112)
	menu_root.add_child(head)
	head.add_child(UI.label("SQUAD LOBBY · SELECT YOUR SPECIALIST", 11, Color("#ffe066")))

	# Fortnite-style 4 vertical colored squad banners across the lobby.
	var banners := UI.hbox(14)
	banners.position = Vector2(40, 150)
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
		var rl := UI.label("YOU" if selected else "BOT", 11, Color("#fef08a") if selected else Color(1, 1, 1, 0.82))
		v.add_child(rl)
		v.add_child(UI.label(s["role"], 10, Color(1, 1, 1, 0.78)))
		var idx := i
		v.add_child(UI.button("SELECTED ✓" if selected else "SELECT", _set_opt.bind("selected", idx), false, 0, 26))
		UI.add_juice(p)
		banners.add_child(p)
		if fresh:
			_lobby_slide_in(p, Vector2(-34, 0), 0.06 * i)

	# Right column: Squads + Match Options + bright Fortnite PLAY button with 5->0 countdown.
	var right := UI.panel(Vector2(310, 0), UI.PANEL)
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-340, 112)
	menu_root.add_child(right)
	if fresh:
		_lobby_slide_in(right, Vector2(46, 0), 0.12)
	var rv := UI.vbox(7)
	right.add_child(rv)
	rv.add_child(LobbyPages.build_mode_selector(_lobby_set_mode, net.is_online()))
	var local_squad: String = _local_empire_assignment().get("squad_id", "orange")
	if _arena_selected():
		local_squad = "crimson" if LobbyPages.arena_home == "planet_b" else "orange"
	rv.add_child(LobbyPages.build_alliance_roster(local_squad))
	if _arena_selected():
		rv.add_child(UI.label("ARENA PRESET", 10, UI.MUTED))
		var presets := UI.hbox(5)
		for preset: String in ArenaClashRules.PRESETS:
			presets.add_child(UI.toggle(preset.to_upper(), LobbyPages.arena_preset == preset, _set_arena_preset.bind(preset), 136))
		rv.add_child(presets)
		rv.add_child(UI.label("ARENA · " + Universe.C_LABEL, 11, UI.MUTED))
		var homes := UI.hbox(5)
		for alliance in ["planet_a", "planet_b"]:
			homes.add_child(UI.toggle(alliance.replace("_", " ").to_upper(), LobbyPages.arena_home == alliance, _set_arena_home.bind(alliance), 136))
		rv.add_child(homes)
	else:
		_build_expedition_options(rv)

	_build_lobby_play_button()


func _build_expedition_options(rv: VBoxContainer) -> void:
	rv.add_child(UI.label("DIFFICULTY", 10, UI.MUTED))
	if LobbyPages.play_mode == "practice":
		rv.add_child(UI.label("%s · LOCKED" % Sim.DIFFICULTY[LobbyPages.PRACTICE_DIFFICULTY]["label"], 12, UI.MUTED))
	else:
		var dh := UI.hbox(5)
		for k in ["cadet", "standard", "expert"]:
			var key: String = k
			dh.add_child(UI.toggle(Sim.DIFFICULTY[k]["label"], opts["difficulty"] == k, _set_opt.bind("difficulty", key), 86))
		rv.add_child(dh)
	rv.add_child(UI.label("MATCH LENGTH", 10, UI.MUTED))
	var lh := UI.hbox(5)
	for key: String in LobbyPages.EMPIRE_LENGTH_LABELS:
		var length_button := UI.toggle(LobbyPages.EMPIRE_LENGTH_LABELS[key], opts["length"] == key, _set_opt.bind("length", key), 86)
		length_button.disabled = net.is_online()
		lh.add_child(length_button)
	rv.add_child(lh)
	_add_empire_network_controls(rv)
	var deploy := UI.button("QUICK DEPLOY · SEATED ON PAD", quick_deploy, false, 280, 30)
	deploy.disabled = net.mode == "CLIENT"
	rv.add_child(deploy)
	var manifest := UI.button("ASSIGN BUILD PARTS", show_manifest, false, 280, 28)
	manifest.disabled = net.mode == "CLIENT"
	rv.add_child(manifest)

func _build_lobby_play_button() -> void:
	# Primary play button.
	var bottom := UI.hbox(10)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom.position = Vector2(-470, -104)
	menu_root.add_child(bottom)
	_lobby_play_btn = UI.button("▶  PLAY  ·  %s" % Sim.SPECIALISTS[opts["selected"]]["name"], start_match_with_loading, true, 320, 56)
	_lobby_play_btn.disabled = net.mode == "CLIENT"
	if net.mode == "CLIENT":
		_lobby_play_btn.text = "WAITING FOR HOST"
	var play_sb := StyleBoxFlat.new()
	play_sb.bg_color = Color("#facc15")
	play_sb.set_corner_radius_all(6)
	play_sb.content_margin_left = 14
	play_sb.content_margin_right = 14
	_lobby_play_btn.add_theme_stylebox_override("normal", play_sb)
	_lobby_play_btn.add_theme_color_override("font_color", Color("#111827"))
	_lobby_play_btn.add_theme_font_size_override("font_size", 25)
	_lobby_play_btn.add_theme_font_override("font", UI.font(true))
	UI.add_juice(_lobby_play_btn)
	bottom.add_child(_lobby_play_btn)
	_start_play_pulse()


## Legacy entry point: the old 4-phase briefing (with its DROP IN / DEPLOY button) is gone.
## Anything that used to open it now goes straight to the buttonless fullscreen LoadingScreen.
func show_loading_briefing() -> void:
	start_match_with_loading()


func show_manifest() -> void:
	mode = "menu"
	_set_audio_mode("earth")
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
		mv.add_child(UI.label("REFERENCE " + m[3], 11, UI.GOOD if m[2] else UI.BAD))
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


func pause() -> void:
	if mode == "paused":
		return
	paused_from = mode
	mode = "paused"
	capture_mouse(false)
	clear_menu()
	var bg := ColorRect.new()
	bg.color = Color(UI.BG_DEEP, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	var v := UI.vbox(12)
	v.position = Vector2(80, 112)
	menu_root.add_child(v)
	v.add_child(UI.heading("MATCH " if arena_clash != null else "EXPEDITION ", "PAUSED", 50))
	v.add_child(UI.button("RESUME MATCH" if arena_clash != null else "RESUME EXPEDITION", resume, true, 420))
	v.add_child(UI.button("CONTROLS", show_help, false, 420))
	_add_settings_buttons(v)
	v.add_child(UI.button("ABANDON TO MAIN MENU", show_home, false, 420))


func show_settings(tab := "") -> void:
	clear_menu()
	settings_open = true
	_settings_menu = SettingsMenu.new(self, tab if tab != "" else settings_tab)
	menu_root.add_child(_settings_menu)


func _add_settings_buttons(v: VBoxContainer) -> void:
	v.add_child(UI.button("MOUSE SENSITIVITY: %.1f×" % sens, _cycle_sens, false, 420))
	var vol_pct := 0 if master_volume_db <= -60.0 else roundi(db_to_linear(master_volume_db) * 100.0)
	v.add_child(UI.button("AUDIO VOLUME: %d%%" % vol_pct, _cycle_volume, false, 420))
	v.add_child(UI.button("REDUCED MOTION: %s" % ("ON" if UI.reduced_motion else "OFF"), _toggle_reduced_motion, false, 420))
	v.add_child(UI.button("GRAPHICS", show_graphics, false, 420))
	v.add_child(UI.button("ALL SETTINGS", show_settings, false, 420))


func show_graphics() -> void:
	show_settings("graphics")


func _close_settings() -> void:
	if mode == "paused":
		mode = paused_from
		pause()
	else:
		show_home()


func _close_graphics() -> void:
	_close_settings()


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
	sens = clampf(float(config.get_value("accessibility", "mouse_sensitivity", 1.0)), 0.4, 2.5)
	UI.reduced_motion = bool(config.get_value("accessibility", "reduced_motion", false))
	master_volume_db = clampf(float(config.get_value("audio", "volume_db", 0.0)), -80.0, 0.0)
	audio_muted = bool(config.get_value("audio", "muted", false))
	invert_y = bool(config.get_value("controls", "invert_y", false))
	var saved_mode := str(config.get_value("controls", "touch_mode", "auto"))
	touch_mode = saved_mode if saved_mode in ["on", "off"] else _default_touch_mode()
	touch_opacity = clampf(float(config.get_value("controls", "touch_opacity", 1.0)), 0.4, 1.0)
	haptics = bool(config.get_value("controls", "haptics", true))
	advisor_hints = bool(config.get_value("game", "advisor_hints", true))
	hud_opacity = clampf(float(config.get_value("game", "hud_opacity", 0.85)), 0.35, 1.0)
	var saved_layout: Variant = config.get_value("hud_layout", "controls", {})
	hud_layout = saved_layout if saved_layout is Dictionary else {}
	var saved_preset := str(config.get_value("hud_layout", "preset", "2-FINGER"))
	hud_preset = saved_preset if saved_preset in MobileControls.PRESET_NAMES or saved_preset == MobileControls.CUSTOM_PRESET else "2-FINGER"
	_apply_audio()
	_apply_controls()
	_apply_game()
	_apply_graphics()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	graphics.save_config(config)
	config.set_value("accessibility", "mouse_sensitivity", sens)
	config.set_value("accessibility", "reduced_motion", UI.reduced_motion)
	config.set_value("audio", "volume_db", master_volume_db)
	config.set_value("audio", "muted", audio_muted)
	config.set_value("controls", "invert_y", invert_y)
	config.set_value("controls", "touch_mode", touch_mode)
	config.set_value("controls", "touch_opacity", touch_opacity)
	config.set_value("controls", "haptics", haptics)
	config.set_value("game", "advisor_hints", advisor_hints)
	config.set_value("game", "hud_opacity", hud_opacity)
	config.set_value("hud_layout", "preset", hud_preset)
	config.set_value("hud_layout", "controls", hud_layout)
	var result := config.save(settings_path)
	if result != OK:
		push_warning("Could not save settings: %s" % error_string(result))


# ---- live-applied Control / Game / Audio settings (driven by SettingsMenu) ----
func _save_soon() -> void:
	if _save_queued:
		return
	_save_queued = true
	(func():
		_save_queued = false
		_save_settings()).call_deferred()


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, master_volume_db)
	AudioServer.set_bus_mute(0, audio_muted or master_volume_db <= -60.0)


func _apply_controls() -> void:
	if hud == null:
		return
	var mc: MobileControls = hud.mobile_controls
	mc.modulate.a = touch_opacity
	mc.haptics_enabled = haptics
	var want := touch_mode == "on"
	var changed := hud.touch_ui_visible() != want
	hud.set_touch_ui(want)
	if changed:
		lmb = false
		rmb = false
		capture_mouse(not want and mode == "play" and not settings_open and not is_instance_valid(picker))


## Push the saved layout / preset into the live touch controls.
func _apply_hud_layout() -> void:
	if hud == null:
		return
	var mc: MobileControls = hud.mobile_controls
	if hud_layout.is_empty() and hud_preset in MobileControls.PRESET_NAMES:
		mc.apply_preset(hud_preset)
	elif not hud_layout.is_empty():
		mc.set_layout(hud_layout, hud_preset)
	else:
		mc.reset_layout()


func open_hud_layout_editor() -> void:
	if is_instance_valid(_hud_editor):
		return
	var current := hud.mobile_controls
	var layout: Dictionary = current.get_layout()
	_hud_editor = HudLayoutEditor.new(layout, current.current_preset)
	_hud_editor.layout_saved.connect(_on_hud_layout_saved)
	_hud_editor.closed.connect(func():
		if is_instance_valid(_settings_menu):
			_settings_menu.refresh())
	menu_layer.add_child(_hud_editor)


func _on_hud_layout_saved(layout: Dictionary, preset: String) -> void:
	hud_layout = layout
	hud_preset = preset
	_apply_hud_layout()
	_save_settings()


func reset_hud_layout() -> void:
	hud_layout = {}
	hud_preset = "2-FINGER"
	_apply_hud_layout()
	_save_settings()


func _apply_game() -> void:
	if hud != null:
		hud.advisor_hints = advisor_hints
		hud.set_hud_opacity(hud_opacity)


func volume_percent() -> float:
	return 0.0 if master_volume_db <= -60.0 else roundf(db_to_linear(master_volume_db) * 100.0)


func set_volume_percent(pct: float) -> void:
	master_volume_db = -80.0 if pct <= 0.5 else linear_to_db(pct / 100.0)
	_apply_audio()
	_save_soon()


func set_audio_muted(on: bool) -> void:
	audio_muted = on
	_apply_audio()
	_save_soon()


func set_look_sensitivity(v: float) -> void:
	sens = clampf(snappedf(v, 0.1), 0.4, 2.5)
	_save_soon()


func set_invert_y(on: bool) -> void:
	invert_y = on
	_save_soon()


func _default_touch_mode() -> String:
	return "on" if UI.is_touch_platform() else "off"


func set_touch_mode(m: String) -> void:
	touch_mode = "on" if m == "on" else "off"
	_apply_controls()
	_save_soon()
	if mode == "menu" and is_instance_valid(_input_mode_buttons.get("on")):
		_refresh_input_mode_buttons()
	if is_instance_valid(_settings_menu):
		_settings_menu.refresh()


var _input_mode_buttons := {}


func _refresh_input_mode_buttons() -> void:
	for key in _input_mode_buttons:
		var b: Button = _input_mode_buttons[key]
		if is_instance_valid(b):
			b.button_pressed = (key == touch_mode)
			b.modulate = Color.WHITE if key == touch_mode else Color(1, 1, 1, 0.45)


func _input_mode_selector() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UI.label("INPUT MODE", 11, UI.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_input_mode_buttons.clear()
	for entry in [["off", "⌨  KEYBOARD & MOUSE"], ["on", "◎  TOUCH"]]:
		var b := UI.button(entry[1], set_touch_mode.bind(entry[0]), entry[0] == touch_mode, 255, 54)
		b.toggle_mode = true
		_input_mode_buttons[entry[0]] = b
		row.add_child(b)
	_refresh_input_mode_buttons()
	return box


func set_touch_opacity(v: float) -> void:
	touch_opacity = clampf(v, 0.4, 1.0)
	_apply_controls()
	_save_soon()


func set_haptics(on: bool) -> void:
	haptics = on
	_apply_controls()
	_save_soon()


func set_reduced_motion(on: bool) -> void:
	UI.reduced_motion = on
	_refresh_graphics_buttons()
	_save_soon()


func set_fps_counter(on: bool) -> void:
	if graphics.values["fps_counter"] != on:
		_cycle_graphics_option("fps_counter")


func set_hud_opacity(v: float) -> void:
	hud_opacity = clampf(v, 0.35, 1.0)
	_apply_game()
	_save_soon()


func set_advisor_hints(on: bool) -> void:
	advisor_hints = on
	_apply_game()
	_save_soon()


func reset_all_settings() -> void:
	sens = 1.0
	invert_y = false
	touch_mode = _default_touch_mode()
	touch_opacity = 1.0
	haptics = true
	advisor_hints = true
	hud_opacity = 0.85
	master_volume_db = 0.0
	audio_muted = false
	UI.reduced_motion = false
	_apply_audio()
	_apply_controls()
	_apply_game()
	_select_graphics_preset(GraphicsSettings.HIGH)
	_save_settings()
	if is_instance_valid(_settings_menu):
		_settings_menu.refresh()


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
	if is_instance_valid(_settings_menu):
		_settings_menu.refresh()


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
	if mode == "play":
		capture_mouse(true)


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
	v.add_child(UI.rich("""[b]ON FOOT[/b]  WASD move · Shift sprint · Space jump · E interact · V view. Build a reactor, engine and bridge, then press E beside the cockpit to board with your crew.
[b]PILOTING[/b]  Hold W for forward thrust or S to brake/reverse · mouse pitch/yaw · A/D yaw and bank · Shift boost · Space lift · Ctrl/C down. Release lift to hover on a surface. Climb into space and use the planet distances to navigate.
[b]LANDING[/b]  Press L in range to descend into a surface map. Fly down or use L again near the landing zone for auto-touchdown. E exits when stopped.
[b]PLANET C[/b]  Arena Clash counts eliminations. In flag modes, the Raider holds LMB to extract, E loads at the ship, and E delivers at the home pad.
[b]TOUCH[/b]  Stick forward for thrust, back to brake, sideways to yaw · drag to steer · hold LIFT, DOWN or BOOST · tap LAND when prompted.
[b]MENU[/b]  Esc pauses · H opens this manual.""", 15))
	v.add_child(UI.button("CLOSE", layer.queue_free, true, 200))


var _match_recorded_sim: Object = null


## Records the finished match into the lobby profile exactly once per sim.
func _record_profile_match(d: Dictionary) -> void:
	if sim == null or _match_recorded_sim == sim:
		return
	_match_recorded_sim = sim
	var m: Dictionary = d.get("metrics", {})
	var mode_id := "PRACTICE" if LobbyPages.play_mode == "practice" else "RANKED"
	var hull_pct := 0 if d.get("eliminated", false) else int(clampf(float(sim.get("hull")), 0.0, 100.0))
	var delivered := int(d.get("delivered", 0))
	var role_name := ""
	if opts.has("selected") and Sim.SPECIALISTS.size() > int(opts["selected"]):
		role_name = str(Sim.SPECIALISTS[opts["selected"]].get("name", ""))
	LobbyPages.record_match({
		"mode": mode_id, "result": "VICTORY" if d.get("victory", false) else "DEFEAT",
		"score": delivered * 100 + int(d.get("xp", 0)), "flags": delivered,
		"kos": int(m.get("stuns", 0)) + int(m.get("captures", 0)), "ship_hull": hull_pct,
		"duration_s": int(sim.get("time")), "role": role_name,
	}, settings_path)


func show_debrief() -> void:
	exit_interior(true)
	_set_audio_mode("debrief")
	mode = "debrief"
	capture_mouse(false)
	hud.visible = false
	if ff != Engine.time_scale:
		ff = 1.0
	clear_menu()
	var bg := ColorRect.new()
	bg.color = Color(UI.BG_DEEP, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	_brand(menu_root)
	var p := UI.panel(Vector2(980, 0), UI.PANEL_SOLID)
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.position = Vector2(-490, 100)
	menu_root.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	if arena_clash != null:
		_build_arena_debrief(v)
		return
	var d := sim.debrief(0)
	_record_profile_match(d)
	v.add_child(UI.label(sim.reason.to_upper(), 12, UI.MUTED))
	if d["eliminated"]:
		v.add_child(UI.heading("CREW ", "LOST.", 54))
	elif d["victory"]:
		v.add_child(UI.heading("FRONTIER ", "SECURED.", 54))
	else:
		v.add_child(UI.heading("BRING IT ", "HOME.", 54))
	var stats := UI.hbox(40)
	v.add_child(stats)
	for s in [["%d/%d" % [d["delivered"], d["total"]], "FLAGS DELIVERED"], ["+%d XP" % d["xp"], "EXPERIENCE"], ["+%d" % d["credits"], "CREDITS"], ["#%d" % d["rank"], "RANK"]]:
		var sv := UI.vbox(0)
		sv.add_child(UI.label(s[0], 34, UI.ACCENT))
		sv.add_child(UI.label(s[1], 11, UI.MUTED))
		stats.add_child(sv)
	v.add_child(UI.label("MISSION PATCH · " + d["patch"].to_upper(), 13, UI.TEXT))
	v.add_child(UI.label("CREW IMPACT  /  %d extractions · %d recoveries · %d rival stuns · %d repairs · %d downs" % [sim.metrics["captures"], sim.metrics["recoveries"], sim.metrics["stuns"], sim.metrics["repairs"], sim.metrics["downs"]], 12, UI.ACCENT))
	v.add_child(UI.label("MATCH SEED %d · %s · %s" % [sim.match_seed, sim.difficulty.to_upper(), "QUICK DEPLOY" if sim.quick_deploy else "FULL EXPEDITION"], 11, UI.MUTED))
	var table := UI.vbox(4)
	v.add_child(table)
	if sim.empire != null:
		for alliance: String in EmpireRules.ALLIANCE_SQUADS:
			var title := alliance.to_upper().replace("_", " ")
			var total: int = sim.empire.scores[alliance]
			table.add_child(UI.label("%s ALLIANCE · %d POINTS" % [title, total], 16, UI.TEXT))
	else:
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


func _arena_selected() -> bool:
	return LobbyPages.play_mode == "arena_clash" and not net.is_online()


func _set_arena_preset(preset: String) -> void:
	LobbyPages.arena_preset = preset
	LobbyPages.save_profile(settings_path)
	show_select()


func _set_arena_home(alliance: String) -> void:
	LobbyPages.arena_home = alliance
	LobbyPages.save_profile(settings_path)
	show_select()


func _start_arena_clash() -> void:
	arena_clash = ArenaClashRules.new()
	arena_clash.setup(sim.match_seed, LobbyPages.arena_preset, "crimson" if LobbyPages.arena_home == "planet_b" else "orange")
	arena_clash.live_combat = true
	sim.arena_clash = arena_clash
	sim.credits = arena_clash.squads[arena_clash.player_squad]["credits"]
	sim.flags.clear()
	_arena_surface_hud = CombatHUD.new()
	add_child(_arena_surface_hud)


func _clear_arena_clash() -> void:
	arena_clash = null
	if is_instance_valid(_arena_surface_hud):
		_arena_surface_hud.hide()
		_arena_surface_hud.queue_free()
	_arena_surface_hud = null


func arena_clock() -> String:
	return UI.fmt_time(ceilf(arena_clash.time_left))


func _tick_arena_clash(dt: float) -> void:
	arena_clash.live_combat = world is PlanetB and not piloting
	arena_clash.tick(dt)
	if world is PlanetA:
		world.sync_arena_build()
	if is_instance_valid(picker) and picker.has_method("update_arena_clock"):
		picker.update_arena_clock()
		_refresh_hud()
	if arena_clash.is_finished():
		_finish_arena_clash()


func _update_arena_travel_hud() -> void:
	hud.visual_status.hide()
	hud.vitals_panel.hide()
	hud.station_panel.hide()
	hud.crosshair.hide()
	hud.title.text = "ARENA CLASH"
	var squad: Dictionary = arena_clash.squads[arena_clash.player_squad]
	hud.subtitle.text = "%d CR · %d/%d BUILT" % [squad["credits"], squad["built"].size(), ArenaClashRules.BUILD_ORDER.size()]
	hud.objectives.text = "BOARDING RAMP · WALK ABOARD" if squad["flight_capable"] else "PARTS SHOP · REACTOR, ENGINE, BRIDGE"
	hud.footer.text = "WASD MOVE    E INTERACT    V VIEW    H HINTS"
	hud.radar_title.text = "BASE · " + sim.location.right(1).to_upper()
	hud.radar.range_m = 85.0
	var player_position := (world.actor(sim.selected) as Actor).position
	var squad_color := Color.html(Sim.EMPIRE_COLORS[arena_clash.player_squad])
	var contacts: Array = []
	for i in 4:
		if i != sim.selected:
			var offset := (world.actor(i) as Actor).position - player_position
			contacts.append({"p": Vector2(offset.x, offset.z).rotated(yaw), "c": squad_color, "s": 3.5})
	var objective := (cockpit_position() if squad["flight_capable"] else (world as PlanetA).shop_computer) - player_position
	contacts.append({"p": Vector2(objective.x, objective.z).rotated(yaw), "c": UI.GOLD, "s": 6.0, "ring": true})
	hud.radar.points = contacts
	hud.radar.request_redraw()


func _finish_arena_clash() -> void:
	if is_instance_valid(picker):
		picker.close()
	if world is PlanetB:
		world.combat_hud.hide()
	_arena_surface_hud.hide_vitals()
	_arena_surface_hud.hide()
	show_debrief()


func _arena_result() -> String:
	var winner := arena_clash.winner()
	if winner == "draw" or winner.is_empty():
		return "DRAW"
	return "VICTORY" if winner == home_alliance() else "DEFEAT"


func _build_arena_debrief(v: VBoxContainer) -> void:
	var score := arena_clash.get_score()
	var seat := arena_clash.combatant("%s:%d" % [arena_clash.player_squad, sim.selected])
	var winner := arena_clash.winner()
	v.add_child(UI.label("ARENA CLASH", 12, UI.MUTED))
	v.add_child(UI.heading("", _arena_result(), 54))
	var result_row := UI.hbox(16)
	for side: String in ["planet_a", "planet_b"]:
		var team_color := Color.html(Sim.EMPIRE_COLORS["orange" if side == "planet_a" else "crimson"])
		result_row.add_child(UI.mono_label("%s  %d" % [side.replace("_", " ").to_upper(), score[side]], 28, team_color))
	v.add_child(result_row)
	if winner != "draw":
		v.add_child(UI.label(winner.to_upper().replace("_", " ") + " WINS", 16, UI.TEXT))
	v.add_child(UI.label("%d KILLS  ·  %d DEATHS" % [seat.get("kills", 0), seat.get("deaths", 0)], 16, UI.MUTED))
	v.add_child(UI.button("RETURN TO LOBBY", _return_to_arena_lobby, true, 240))


func _return_to_arena_lobby() -> void:
	_clear_arena_clash()
	sim = null
	show_select()


func _set_opt(key: String, value) -> void:
	if key == "difficulty" and LobbyPages.play_mode == "practice":
		return
	if key == "length" and net.is_online():
		return
	opts[key] = value
	if key == "difficulty" or key == "length":
		sim = null
	show_select()


func _start_new() -> void:
	if net.mode == "CLIENT":
		return
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
# Shared menu screen helpers (Mission Control)
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


# ============================================================================
# Live peer replication (no-op while offline)
# ============================================================================
func _remote_zone(w: Node) -> String:
	if w == null or not is_instance_valid(w) or w == showcase:
		return "menu"
	if w is Flight:
		return "flight"
	if w is PlanetB:
		return "planet_c"
	if w is PlanetA:
		return w.home_alliance
	return "menu"


func _bind_remote_sync() -> void:
	if remote_sync == null:
		return
	var zone := _remote_zone(world)
	if net.is_online() and zone != "menu":
		remote_sync.set_active_world(world, zone)
	else:
		remote_sync.set_active_world(null, zone)


func _sample_local_state() -> Dictionary:
	var state := {"zone": remote_sync.zone, "anim": "idle", "hp": EmpireNet.MAX_HP}
	if sim == null or world == null or not is_instance_valid(world) or mode != "play":
		state["zone"] = "menu"
		return state
	var squad: Dictionary = {}
	if sim.empire != null and sim.empire.squads.has(sim.empire_squad):
		squad = sim.empire.squads[sim.empire_squad]
	var carried: Array = squad.get("flags_carried", [])
	state["carrying_flag"] = str(carried[0]) if not carried.is_empty() else ""
	if sim.in_space() and is_instance_valid(vessel):
		var ship_node: Node3D = world.ship if world.ship != null else world
		var gp := ship_node.global_position
		state["ship_pos"] = universe.to_local(gp) if universe != null and is_instance_valid(universe) else gp
		state["ship_rot"] = (vessel.basis * vessel.ship.basis).orthonormalized().get_euler()
		state["role"] = clampi(sim.selected, 0, 3)
	elif (world is PlanetA or world is PlanetB) and sim.selected >= 0 and sim.selected < world.actors.size():
		var a: Actor = world.actors[sim.selected]
		state["pos"] = a.position
		state["heading"] = a.rotation.y
		state["speed"] = Vector2(a.move_vel.x, a.move_vel.z).length()
		state["anim"] = a.current if a.current != "" else "idle"
		state["role"] = a.role
		state["weapon_drawn"] = a.weapon_drawn
	return state


func _tick_remote_sync() -> void:
	if remote_sync == null or not net.is_online():
		return
	remote_sync.submit_local_state(_sample_local_state())


func _broadcast_local_shot() -> void:
	if remote_sync == null or not net.is_online() or cam == null or mode != "play":
		return
	if remote_sync.zone == "menu":
		return
	var origin: Vector3 = world.to_local(cam.global_position)
	var hit: Vector3 = world.to_local(cam.global_position - cam.global_basis.z * 60.0)
	net.broadcast_shot_fx(net.get_local_peer_id(), remote_sync.zone, origin, hit, Color("#7ff3ff"))


func _on_remote_player_damaged(target: int, _attacker: int, damage: float, hp: float, _zone: String) -> void:
	if target == net.get_local_peer_id() and hud != null:
		hud.show_banner("HIT -%d" % int(damage), "HP %d" % int(hp), 1.0)


func _local_empire_assignment() -> Dictionary:
	if not net.is_online():
		return {}
	return net.get_peer_assignment(net.multiplayer.get_unique_id())


func _publish_empire_start() -> void:
	if sim.empire == null or net.mode == "CLIENT":
		return
	_empire_sync_ready = true
	_empire_round += 1
	_on_empire_roster(net.roster)
	_broadcast_empire()


func _broadcast_empire() -> void:
	if net.is_host() and _empire_sync_ready:
		net.broadcast_world_snapshot({"round": _empire_round, "empire": sim.empire.to_snapshot()})


func _on_empire_snapshot(packet: Dictionary) -> void:
	var state: Variant = packet.get("empire")
	var round_id: Variant = packet.get("round")
	if not state is Dictionary or not round_id is int or _local_empire_assignment().is_empty():
		return
	if not _empire_sync_ready or _empire_round != round_id:
		new_sim()
		if sim.empire == null or not sim.empire.from_snapshot(state):
			return
		_empire_round = round_id
		_empire_sync_ready = true
		_run_start_match(null)
	elif not sim.empire.from_snapshot(state):
		return
	sim.sync_empire_flags()
	sim.finish_empire_if_needed()


func _on_empire_roster(roster: Dictionary) -> void:
	if not net.is_host() or sim == null or sim.empire == null:
		return
	for id: String in roster:
		var squad: Dictionary = sim.empire.squads[id]
		var occupied := false
		for seat: Dictionary in roster[id]:
			occupied = occupied or seat["peer_id"] > 0
		if occupied and squad["ai_enabled"]:
			sim.empire._set_phase(squad, "build", squad["alliance"], 40.0)
		squad["ai_enabled"] = not occupied


func _tick_empire(dt: float) -> void:
	if sim.empire == null or not _empire_sync_ready:
		return
	var empire := sim.empire
	if net.mode != "CLIENT":
		empire.tick(dt)
		_empire_broadcast_time += dt
		if _empire_broadcast_time >= 0.5:
			_empire_broadcast_time = fmod(_empire_broadcast_time, 0.5)
			_broadcast_empire()
	sim.sync_empire_flags()
	sim.finish_empire_if_needed()


func request_empire_action(action_type: String, payload: Dictionary) -> Dictionary:
	if sim == null or sim.empire == null:
		return {"ok": false, "reason": "unavailable"}
	if not net.is_online():
		return _apply_empire_action(sim.empire_squad, sim.selected, action_type, payload, 1)
	_empire_action_result = {}
	if not net.request_empire_action(action_type, payload):
		return {"ok": false, "reason": "connection_unavailable"}
	if net.mode == "CLIENT":
		return {"ok": true, "pending": true}
	return _empire_action_result


func _on_empire_action(peer_id: int, action_type: String, payload: Dictionary) -> void:
	if sim == null or sim.empire == null or not net.is_host():
		return
	var seat := net.get_peer_assignment(peer_id)
	if seat.is_empty():
		return
	var role: int = sim.selected if peer_id == 1 else seat["seat_index"]
	var result := _apply_empire_action(seat["squad_id"], role, action_type, payload, peer_id)
	if peer_id == 1:
		_empire_action_result = result
	if result.get("ok", false) and action_type not in ["squad_stage", "sabotage_start", "sabotage_cancel"]:
		_broadcast_empire()
	net.send_action_result(peer_id, action_type, payload, result)


func _on_empire_action_result(action_type: String, payload: Dictionary, result: Dictionary) -> void:
	if sim == null or sim.empire == null:
		return
	if payload.has("flag_id") and sim.empire_pending_flags.get(payload["flag_id"]) == action_type:
		sim.empire_pending_flags.erase(payload["flag_id"])
		sim.sync_empire_flags()
	if not result.get("ok", false) and action_type != "squad_stage":
		hud.toast(str(result.get("reason", "Unavailable")).replace("_", " ").capitalize())


func _apply_empire_action(squad_id: String, role: int, action_type: String, payload: Dictionary, peer_id: int) -> Dictionary:
	var empire := sim.empire
	if empire.winner != "":
		return {"ok": false, "reason": "match_over"}
	var squad: Dictionary = empire.squads[squad_id]
	var home: String = squad["alliance"]
	var enemy := "planet_b" if home == "planet_a" else "planet_a"
	var location: String = squad["location"]
	var id: String = payload.get("slot_id", "")
	var flag_id: String = payload.get("flag_id", "")
	var ok := false
	match action_type:
		"build_or_upgrade", "repair":
			if location != home or payload.get("alliance", home) != home:
				return {"ok": false, "reason": "return_to_home_planet"}
			if action_type == "repair":
				return EmpireLayer.repair_slot(empire, home, id, squad_id)
			return empire.build_or_upgrade(home, id, squad_id)
		"sabotage_start", "sabotage_cancel", "sabotage", "damage_structure":
			if location != enemy or payload.get("alliance", enemy) != enemy or not EmpireRules.EMPIRE_SLOTS.has(id):
				return {"ok": false, "reason": "enemy_structure_unavailable"}
			if action_type == "sabotage_cancel":
				_empire_sabotage.erase(peer_id)
				return {"ok": true}
			if action_type == "sabotage_start":
				var duration: float = EmpireLayer.SABOTAGE_TIME * (0.5 if role == 1 else 1.0)
				_empire_sabotage[peer_id] = {"slot_id": id, "ready": empire.elapsed + duration - EmpireRules.STEP}
				return {"ok": true, "duration": duration}
			if action_type == "sabotage":
				var task: Dictionary = _empire_sabotage.get(peer_id, {})
				if task.get("slot_id") != id or empire.elapsed < task["ready"]:
					return {"ok": false, "reason": "sabotage_interrupted"}
				_empire_sabotage.erase(peer_id)
				return empire.sabotage_structure(enemy, id, EmpireRules.SABOTAGE_THRESHOLD, squad_id)
			if role == 3 or empire.elapsed < _empire_last_shot.get(peer_id, 0.0):
				return {"ok": false, "reason": "weapon_cycling"}
			_empire_last_shot[peer_id] = empire.elapsed + maxf(0.0, Sim.FIELD_WEAPONS[role]["interval"] - EmpireRules.STEP)
			return empire.damage_structure(enemy, id, Sim.field_damage(role, 12.0), squad_id)
		"capture_flag":
			ok = empire.record_flag_captured(squad_id, flag_id)
		"deliver_flag":
			ok = empire.record_flag_delivered(squad_id, flag_id) > 0
		"drop_flag":
			ok = location == enemy and sim.drop_empire_flag(squad_id, flag_id)
		"squad_stage":
			var stage: Variant = payload.get("stage", "")
			if stage is String:
				ok = sim.move_empire_squad(squad_id, stage)
			if ok:
				_empire_sabotage.erase(peer_id)
	return {"ok": ok, "reason": "" if ok else "action_unavailable"}


func _add_empire_network_controls(parent: VBoxContainer) -> void:
	var row := UI.hbox(5)
	var address := LineEdit.new()
	address.placeholder_text = "Host IP"
	address.text = _net_address
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.text_changed.connect(func(value: String) -> void: _net_address = value)
	row.add_child(address)
	var port := SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = _net_port
	port.value_changed.connect(func(value: float) -> void: _net_port = int(value))
	row.add_child(port)
	parent.add_child(row)
	var buttons := UI.hbox(4)
	buttons.add_child(UI.button("OFFLINE (1+31 BOTS)", _change_empire_session.bind("OFFLINE"), false, 0, 26))
	var host := UI.button("HOST 32P", _change_empire_session.bind("HOST"), false, 0, 26)
	host.disabled = opts["length"] == "classic" or LobbyPages.play_mode == "practice"
	buttons.add_child(host)
	buttons.add_child(UI.button("JOIN ENET", _change_empire_session.bind("CLIENT"), false, 0, 26))
	parent.add_child(buttons)
	_net_status = UI.label("", 10, UI.MUTED)
	parent.add_child(_net_status)
	_refresh_empire_network_status()


func _change_empire_session(next: String) -> void:
	_net_error = ""
	net.disconnect_match()
	sim = null
	_empire_sync_ready = false
	var result := {"ok": true}
	if next != "OFFLINE":
		ff = 1.0
		Engine.time_scale = 1.0
	if next == "HOST":
		var seed_value := int(opts.get("seed", 0))
		result = net.host_match(_net_port, seed_value if seed_value > 0 else randi_range(1, 999999), opts["length"])
	elif next == "CLIENT":
		result = net.join_match(_net_address, _net_port)
	if not result["ok"]:
		_net_error = error_string(result["error"])
	show_select()


func _refresh_empire_network_status() -> void:
	if not is_instance_valid(_net_status):
		return
	var status := "%s · %d/32 HUMAN" % [net.get_status_text(), net.get_total_human_count()]
	if not net.is_online():
		status = "OFFLINE · 1 HUMAN + 31 BOTS"
	if not _net_error.is_empty():
		status += " · " + _net_error
	if _net_status.text != status:
		_net_status.text = status


func _on_empire_session_changed(next: String) -> void:
	if next == "OFFLINE" and _empire_sync_ready and sim != null and sim.empire != null:
		_empire_sync_ready = false
		show_home.call_deferred()
	elif next == "OFFLINE" and mode == "menu" and is_instance_valid(_net_status):
		show_select.call_deferred()
