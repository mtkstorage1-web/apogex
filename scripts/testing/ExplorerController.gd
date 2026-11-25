class_name ExplorerController
extends CharacterBody3D
## Spherical-world explorer: ground walking (capsule 1.8 x 0.4, gravity aligned to the planet) and
## free flight, with five camera modes and altitude-scaled near/far planes.

enum MoveMode { WALK, FLY }
enum CameraMode { FIRST_PERSON, FREE_FLIGHT, PLANET_ORBIT, CINEMATIC, DEBUG_OVERVIEW }
const CAMERA_MODE_NAMES: PackedStringArray = [
	"First-Person Walking", "Free-Flight", "Planet Orbit Inspection", "Cinematic Spectator", "Debug Overview",
]
const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")

## Emitted for keys the world root / debug UI owns (map, settings, F-keys, ...).
signal action_requested(action: StringName)
signal mode_changed

const WALK_SPEED := 6.0
const RUN_MULT := 2.4
const JUMP_SPEED := 5.5
const FLY_BASE_SPEED := 22.0
const EYE_HEIGHT := 0.7         # camera above capsule centre (capsule centre is 0.9 above feet)
const MOUSE_SENS := 0.0023
const SHIP_GRAVITY := 9.81      # artificial gravity inside a mothership interior (m/s^2)
const MIN_CLEARANCE := 1.4      # fly mode never goes closer than this to the terrain (centre height)

var planet: PlanetGenerator
var coord: WorldCoordinateSystem
var origin_mgr: FloatingOriginManager
## MothershipManager (duck-typed): find_ship_containing(planet_pos) -> ship controller or null.
var mothership_manager: Node
var in_ship_interior: bool = false
var current_ship: Node3D

var move_mode: int = MoveMode.FLY
var camera_mode: int = CameraMode.FREE_FLIGHT
var gravity_alignment: bool = true
var speed_multiplier: float = 1.0
var mouse_sensitivity := 1.0
var mouse_captured: bool = false
var input_enabled: bool = true
var modal_open := false
var combat: Node
var is_piloting := false
var _exit_key_pressed_at := -1

# Telemetry
var planet_pos: Vector3 = Vector3.ZERO
var altitude: float = 0.0               # above reference radius
var height_above_ground: float = 0.0    # above sampled terrain
var gravity_dir: Vector3 = Vector3.DOWN
var ground_normal: Vector3 = Vector3.UP
var grounded: bool = false
var current_speed: float = 0.0

var _head: Node3D
var _camera: Camera3D
var _ray: RayCast3D
var _pitch: float = 0.0
var _vertical_speed: float = 0.0
var _fly_velocity: Vector3 = Vector3.ZERO
var _look_delta: Vector2 = Vector2.ZERO
var _orbit_lat: float = 0.0
var _orbit_lon: float = 0.0
var _orbit_dist: float = 30000.0
var _cin_dir: Vector3 = Vector3.BACK
var _cin_angle: float = 0.0
var _cin_time: float = 0.0
var _surface_radius: float = 12000.0


func _ready() -> void:
	_head = get_node("Head") as Node3D
	_camera = get_node("Head/Camera3D") as Camera3D
	_ray = get_node("GroundRay") as RayCast3D
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(58.0)
	floor_snap_length = 0.7
	floor_stop_on_slope = true
	floor_constant_speed = true
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_head.position = Vector3(0, EYE_HEIGHT, 0)
	_ray.target_position = Vector3(0, -3.0, 0)
	_ray.collision_mask = 1
	_ray.enabled = true
	_camera.current = true


func setup(p_planet: PlanetGenerator, p_coord: WorldCoordinateSystem, p_origin: FloatingOriginManager) -> void:
	planet = p_planet
	coord = p_coord
	origin_mgr = p_origin


func set_piloting_state(active: bool) -> void:
	is_piloting = active
	_exit_key_pressed_at = -1
	visible = not active
	if combat != null:
		combat.on_pilot_changed(active)
	set_physics_process(not active)
	collision_layer = 0 if active else 2
	collision_mask = 0 if active else 1
	velocity = Vector3.ZERO
	_fly_velocity = Vector3.ZERO
	_vertical_speed = 0.0
	_look_delta = Vector2.ZERO
	if not active:
		_camera.make_current()


func get_camera() -> Camera3D:
	return _camera


func get_camera_mode_name() -> String:
	return CAMERA_MODE_NAMES[camera_mode]


func get_planet_position() -> Vector3:
	return origin_mgr.render_to_planet(global_position) if origin_mgr != null else global_position


func get_camera_planet_position() -> Vector3:
	return origin_mgr.render_to_planet(_camera.global_position) if origin_mgr != null else _camera.global_position


func get_look_direction() -> Vector3:
	return -_camera.global_basis.z


# ---------------------------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------------------------

func set_move_mode(mode: int) -> void:
	move_mode = mode
	_vertical_speed = 0.0
	_fly_velocity = Vector3.ZERO
	if mode == MoveMode.WALK and camera_mode != CameraMode.FIRST_PERSON:
		camera_mode = CameraMode.FIRST_PERSON
	mode_changed.emit()


func toggle_move_mode() -> void:
	set_move_mode(MoveMode.FLY if move_mode == MoveMode.WALK else MoveMode.WALK)


func toggle_gravity_alignment() -> void:
	gravity_alignment = not gravity_alignment
	mode_changed.emit()


func cycle_camera_mode() -> void:
	set_camera_mode((camera_mode + 1) % CameraMode.size())


func set_camera_mode(mode: int) -> void:
	mode = clampi(mode, 0, CameraMode.size() - 1)
	var previous: int = camera_mode
	camera_mode = mode
	_vertical_speed = 0.0
	_fly_velocity = Vector3.ZERO
	var pos: Vector3 = get_planet_position()
	match mode:
		CameraMode.FIRST_PERSON:
			pass
		CameraMode.FREE_FLIGHT:
			move_mode = MoveMode.FLY
		CameraMode.PLANET_ORBIT:
			var angles: Vector2 = Transforms.unit_dir_to_lat_lon(pos)
			_orbit_lat = angles.x
			_orbit_lon = angles.y
			_orbit_dist = maxf(pos.length(), planet_radius() * 2.6)
		CameraMode.CINEMATIC:
			_cin_dir = pos.normalized()
			_cin_angle = 0.0
			_cin_time = 0.0
		CameraMode.DEBUG_OVERVIEW:
			move_mode = MoveMode.FLY
			var dir: Vector3 = pos.normalized()
			var overview: Vector3 = dir * (planet_radius() + 9000.0)
			_place(overview, _face_toward(overview, -dir, Vector3.UP))
	if previous != mode:
		_pitch = 0.0
		_head.rotation = Vector3.ZERO
	mode_changed.emit()


func _find_ship(planet_position: Vector3) -> Node3D:
	if mothership_manager == null or not mothership_manager.has_method("find_ship_containing"):
		return null
	return mothership_manager.call("find_ship_containing", planet_position) as Node3D


func planet_radius() -> float:
	return coord.planet_radius if coord != null else 12000.0


func set_mouse_captured(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------------------------------------
# Teleport / placement
# ---------------------------------------------------------------------------------------------

## Teleports to planet-space position facing look_dir. WorldRoot is responsible for the origin shift.
func teleport_to(target_planet_pos: Vector3, look_dir: Vector3) -> void:
	var up: Vector3 = (target_planet_pos - _planet_center()).normalized()
	var ship: Node3D = _find_ship(target_planet_pos)
	if ship != null and gravity_alignment:
		up = ship.call("get_local_up_direction")
	var look: Vector3 = look_dir.normalized()
	var tangent_look: Vector3 = look - up * look.dot(up)
	_vertical_speed = 0.0
	_fly_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_pitch = 0.0
	_head.rotation = Vector3.ZERO
	if tangent_look.length_squared() < 1.0e-6:
		tangent_look = Vector3.UP.cross(up) if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# Walking-height teleports keep a level head; orbital ones aim exactly along look_dir.
	var altitude_here: float = target_planet_pos.length() - planet_radius()
	var facing: Vector3 = look if (altitude_here > 400.0 and ship == null) else tangent_look.normalized()
	_place(target_planet_pos, _face_toward(target_planet_pos, facing, up))
	_update_telemetry()


func _place(target_planet_pos: Vector3, basis_in: Basis) -> void:
	global_position = origin_mgr.planet_to_render(target_planet_pos) if origin_mgr != null else target_planet_pos
	global_basis = basis_in
	planet_pos = target_planet_pos


func _face_toward(_pos: Vector3, forward: Vector3, up: Vector3) -> Basis:
	var f: Vector3 = forward.normalized()
	var u: Vector3 = up.normalized()
	if absf(f.dot(u)) > 0.999:
		u = Vector3.RIGHT if absf(f.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	return Basis.looking_at(f, u)


func _planet_center() -> Vector3:
	return coord.planet_center if coord != null else Vector3.ZERO


## Raises the explorer above ground if the terrain was regenerated underneath it.
func snap_above_ground(clearance: float = 1.2) -> void:
	if planet == null:
		return
	var pos: Vector3 = get_planet_position()
	var dir: Vector3 = (pos - _planet_center()).normalized()
	var surf: float = planet.get_surface_radius(dir)
	if pos.length() < surf + clearance:
		pos = dir * (surf + clearance)
		_place(pos, global_basis)
		_vertical_speed = 0.0


# ---------------------------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not input_enabled or not event is InputEventKey or not event.pressed or event.echo or combat == null:
		return
	var key: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	var focus := get_viewport().gui_get_focus_owner()
	if (focus is LineEdit or focus is TextEdit) and key != KEY_ESCAPE:
		return
	if combat.world.frontend_ui != null and combat.world.frontend_ui.handle_key(key):
		get_viewport().set_input_as_handled()
		return
	if combat.world.get_frontend_state() != "GAMEPLAY":
		return
	match key:
		KEY_B:
			action_requested.emit(&"toggle_deploy")
		KEY_TAB:
			action_requested.emit(&"toggle_scoreboard")
		KEY_O:
			action_requested.emit(&"toggle_commander")
		KEY_ESCAPE:
			if not modal_open or not combat.world.combat_hud.has_open_panel():
				return
			action_requested.emit(&"close_combat_panel")
		_:
			return
	get_viewport().set_input_as_handled()


func combat_input_allowed() -> bool:
	return mouse_captured and not is_piloting and not _movement_blocked() and camera_mode <= CameraMode.FREE_FLIGHT


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or (combat != null and combat.world.get_frontend_state() != "GAMEPLAY"):
		return
	if modal_open:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_M, KEY_P]:
			_on_key(event.keycode)
		return
	if event is InputEventMouseMotion and mouse_captured and not is_piloting:
		_look_delta += (event as InputEventMouseMotion).relative
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and not is_piloting:
			_wheel(1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and not is_piloting:
			_wheel(-1.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mouse_captured:
			set_mouse_captured(true)
			action_requested.emit(&"mouse_capture_changed")
	elif event is InputEventKey and not event.echo:
		var key: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		if key == KEY_E and is_piloting:
			# A tap exits, while holding E is available for right roll.
			if event.pressed:
				_exit_key_pressed_at = Time.get_ticks_msec()
			else:
				var tapped := _exit_key_pressed_at >= 0 and Time.get_ticks_msec() - _exit_key_pressed_at < 180
				_exit_key_pressed_at = -1
				if tapped:
					action_requested.emit(&"interact_vehicle")
		elif event.pressed:
			_on_key(key)


func _wheel(direction: float) -> void:
	if camera_mode == CameraMode.PLANET_ORBIT:
		_orbit_dist = clampf(_orbit_dist * pow(0.9, direction), planet_radius() * 1.15, 120000.0)
	else:
		speed_multiplier = clampf(speed_multiplier * pow(1.18, direction), 0.05, 60.0)


func _on_key(keycode: int) -> void:
	if is_piloting and keycode in [KEY_F, KEY_G, KEY_C]:
		return
	match keycode:
		KEY_1, KEY_2:
			if combat != null and combat_input_allowed():
				combat.select_tool(0 if keycode == KEY_1 else 1)
		KEY_3, KEY_4, KEY_5:
			if not is_piloting:
				action_requested.emit([&"build_turret", &"build_shield", &"build_supply"][keycode - KEY_3])
		KEY_R:
			if combat != null and combat_input_allowed():
				combat.reload()
		KEY_E:
			action_requested.emit(&"interact_vehicle")
		KEY_F:
			toggle_move_mode()
		KEY_G:
			toggle_gravity_alignment()
		KEY_C:
			cycle_camera_mode()
		KEY_M:
			action_requested.emit(&"toggle_map")
		KEY_P:
			action_requested.emit(&"toggle_settings")
		KEY_F1:
			action_requested.emit(&"toggle_diagnostics")
		KEY_F2:
			action_requested.emit(&"toggle_wireframe")
		KEY_F3:
			action_requested.emit(&"toggle_collision_debug")
		KEY_F4:
			action_requested.emit(&"toggle_lod_heatmap")
		KEY_F5:
			action_requested.emit(&"regenerate")
		KEY_F6:
			action_requested.emit(&"next_landmark")
		KEY_F7:
			action_requested.emit(&"toggle_orbit_surface")
		KEY_H:
			action_requested.emit(&"toggle_hangar_doors")
		KEY_K:
			action_requested.emit(&"cycle_destruction")
		KEY_ESCAPE:
			set_mouse_captured(not mouse_captured)
			action_requested.emit(&"mouse_capture_changed")


func _movement_blocked() -> bool:
	if not input_enabled or modal_open:
		return true
	var vp: Viewport = get_viewport()
	if vp == null:
		return true
	var focus: Control = vp.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _read_move_input() -> Vector3:
	if _movement_blocked():
		return Vector3.ZERO
	var x: float = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var z: float = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var y: float = float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_CTRL))
	return Vector3(x, y, z)


# ---------------------------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if planet == null or coord == null or (combat != null and combat.world.get_frontend_state() != "GAMEPLAY"):
		return
	planet_pos = get_planet_position()
	var center: Vector3 = _planet_center()
	var rel: Vector3 = planet_pos - center
	var up: Vector3 = rel.normalized()
	# Artificial ship gravity: inside a mothership interior "down" is the ship's deck floor, not the planet.
	current_ship = _find_ship(planet_pos) if gravity_alignment else null
	in_ship_interior = current_ship != null
	if in_ship_interior:
		up = current_ship.call("get_local_up_direction")
	gravity_dir = -up
	_apply_mouse_look()

	match camera_mode:
		CameraMode.PLANET_ORBIT:
			_update_orbit(delta)
		CameraMode.CINEMATIC:
			_update_cinematic(delta)
		_:
			if move_mode == MoveMode.WALK:
				_update_walk(delta, up)
			else:
				_update_fly(delta, up)
	_update_telemetry()
	_update_camera_planes()


func _apply_mouse_look() -> void:
	if _look_delta == Vector2.ZERO:
		return
	if camera_mode == CameraMode.PLANET_ORBIT:
		_orbit_lon -= _look_delta.x * 0.002 * mouse_sensitivity
		_orbit_lat = clampf(_orbit_lat + _look_delta.y * 0.002 * mouse_sensitivity, -1.45, 1.45)
	elif camera_mode != CameraMode.CINEMATIC:
		rotate_object_local(Vector3.UP, -_look_delta.x * MOUSE_SENS * mouse_sensitivity)
		_pitch = clampf(_pitch - _look_delta.y * MOUSE_SENS * mouse_sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))
		_head.rotation.x = _pitch
	_look_delta = Vector2.ZERO


func _align_to_up(up: Vector3, delta: float) -> void:
	if not gravity_alignment:
		return
	var current_up: Vector3 = global_basis.y
	if current_up.dot(up) > 0.99999:
		return
	var q := Quaternion(current_up.normalized(), up)
	var step: float = 1.0 - exp(-10.0 * delta)
	var smooth_q: Quaternion = Quaternion.IDENTITY.slerp(q, step)
	global_basis = (Basis(smooth_q) * global_basis).orthonormalized()


func _update_walk(delta: float, up: Vector3) -> void:
	_align_to_up(up, delta)
	up_direction = up
	var input: Vector3 = _read_move_input()
	var run: bool = Input.is_physical_key_pressed(KEY_SHIFT) and not _movement_blocked()
	var speed: float = WALK_SPEED * speed_multiplier * (RUN_MULT if run else 1.0)
	var fwd: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	fwd = (fwd - up * fwd.dot(up)).normalized()
	right = (right - up * right.dot(up)).normalized()
	var wish: Vector3 = (right * input.x - fwd * input.z)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	grounded = is_on_floor()
	var eva := is_in_eva()
	var g: float = 0.0 if eva else (SHIP_GRAVITY if in_ship_interior else coord.get_gravity_magnitude(planet_pos))
	if grounded:
		if _vertical_speed < 0.0:
			_vertical_speed = 0.0
		if input.y > 0.5 and not _movement_blocked():
			_vertical_speed = JUMP_SPEED
	else:
		_vertical_speed -= g * delta
	if eva:
		velocity += (global_basis.x * input.x - global_basis.z * input.z) * (4.0 * delta)
		velocity = velocity.limit_length(65.0)
	else:
		velocity = wish * speed + up * _vertical_speed
	if combat != null:
		combat.apply_jetpack(delta, input.y > 0.5 and combat_input_allowed())
	move_and_slide()
	_vertical_speed = velocity.dot(up)
	if is_on_floor() and _vertical_speed < 0.0:
		_vertical_speed = 0.0
	_update_ground_ray(up)
	# Safety net: never sink through the world (collision not streamed yet, or terrain regenerated).
	var dir: Vector3 = (get_planet_position() - _planet_center()).normalized()
	var surf: float = planet.get_surface_radius(dir)
	var r: float = (get_planet_position() - _planet_center()).length()
	if r < surf - 1.0 and not in_ship_interior:
		_place(dir * (surf + 1.1), global_basis)
		_vertical_speed = 0.0
		velocity = Vector3.ZERO
	current_speed = Vector3(velocity - up * velocity.dot(up)).length()


func is_in_eva() -> bool:
	return not in_ship_interior and height_above_ground > 1650.0


func _update_fly(delta: float, up: Vector3) -> void:
	_align_to_up(up, delta)
	up_direction = up
	var input: Vector3 = _read_move_input()
	var fast: bool = Input.is_physical_key_pressed(KEY_SHIFT) and not _movement_blocked()
	var scale_by_alt: float = clampf(height_above_ground / 120.0, 1.0, 70.0)
	var speed: float = FLY_BASE_SPEED * scale_by_alt * speed_multiplier
	if camera_mode == CameraMode.DEBUG_OVERVIEW:
		speed *= 4.0
	if fast:
		speed *= 4.0
	var cam_basis: Basis = _camera.global_basis
	var wish: Vector3 = cam_basis.x * input.x - cam_basis.z * input.z + up * input.y
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var target: Vector3 = wish * speed
	_fly_velocity = _fly_velocity.lerp(target, 1.0 - exp(-7.0 * delta))
	var new_pos: Vector3 = get_planet_position() + _fly_velocity * delta
	var rel: Vector3 = new_pos - _planet_center()
	var dir: Vector3 = rel.normalized()
	var surf: float = planet.get_surface_radius(dir)
	if rel.length() < surf + MIN_CLEARANCE:
		new_pos = _planet_center() + dir * (surf + MIN_CLEARANCE)
		_fly_velocity = _fly_velocity - dir * minf(_fly_velocity.dot(dir), 0.0)
	global_position = origin_mgr.planet_to_render(new_pos)
	velocity = _fly_velocity
	current_speed = _fly_velocity.length()
	grounded = false
	_update_ground_ray(up)


func _update_orbit(delta: float) -> void:
	var input: Vector3 = _read_move_input()
	_orbit_lon += input.x * delta * 0.6
	_orbit_lat = clampf(_orbit_lat - input.z * delta * 0.6, -1.45, 1.45)
	var dir: Vector3 = Transforms.lat_lon_to_unit_dir(_orbit_lat, _orbit_lon)
	var pos: Vector3 = _planet_center() + dir * _orbit_dist
	global_position = origin_mgr.planet_to_render(pos)
	global_basis = _face_toward(pos, -dir, Vector3.UP)
	_head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	current_speed = 0.0
	grounded = false


func _update_cinematic(delta: float) -> void:
	_cin_time += delta
	_cin_angle += delta * 0.07
	var tb: Basis = Transforms.surface_tangent_basis(_cin_dir)
	var pivot_surface: Vector3 = planet.noise_stack.sample_surface_position(_cin_dir)
	var radius_m: float = 650.0
	var offset: Vector3 = (tb.x * cos(_cin_angle) + tb.z * sin(_cin_angle)) * radius_m
	var dir: Vector3 = (pivot_surface + offset).normalized()
	var surf: float = planet.get_surface_radius(dir)
	var alt: float = 240.0 + 55.0 * sin(_cin_time * 0.21)
	var pos: Vector3 = _planet_center() + dir * (surf + alt)
	var look_at_pt: Vector3 = pivot_surface + _cin_dir * 40.0
	global_position = origin_mgr.planet_to_render(pos)
	global_basis = _face_toward(pos, look_at_pt - pos, dir)
	_head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	current_speed = radius_m * 0.07
	grounded = false


func _update_ground_ray(up: Vector3) -> void:
	_ray.force_raycast_update()
	if _ray.is_colliding():
		ground_normal = _ray.get_collision_normal()
	else:
		ground_normal = up


func _update_telemetry() -> void:
	planet_pos = get_planet_position()
	var rel: Vector3 = planet_pos - _planet_center()
	altitude = rel.length() - planet_radius()
	var dir: Vector3 = rel.normalized()
	_surface_radius = planet.get_surface_radius(dir) if planet != null else planet_radius()
	height_above_ground = rel.length() - _surface_radius


## Dynamic near/far: tight planes on the ground, wide ones in orbit; no z-fighting at either extreme.
func _update_camera_planes() -> void:
	if in_ship_interior:
		_camera.near = 0.12
		_camera.far = 150000.0
		return
	var t: float = smoothstep(300.0, 5000.0, height_above_ground)
	if camera_mode == CameraMode.PLANET_ORBIT:
		t = 1.0
	_camera.near = lerpf(0.25, 2.0, t)
	if camera_mode == CameraMode.FIRST_PERSON and move_mode == MoveMode.WALK:
		_camera.near = 0.12
	elif camera_mode == CameraMode.FREE_FLIGHT and combat != null:
		_camera.near = 0.25
	_camera.far = lerpf(60000.0, 180000.0, t)
