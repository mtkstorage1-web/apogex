## One manually piloted vessel, shared by surface and space travel.
class_name Flight
extends Node3D

const GraphicsSettings = preload("res://scripts/graphics_settings.gd")

const SURFACE_CEILING := 650.0
const TILT_RATE := 1.5
const LIFT_STEP_TIME := 0.24
const CLIMB_SPEED := 380.0
const DESCENT_SPEED := 180.0
const SURFACE_FALL_LIMIT := 260.0
const MAX_THRUST := 920.0
const SURFACE_SPEED := 1400.0
const SURFACE_BOOST_SPEED := 1848.0
const CRUISE_SPEED := 4800.0
const BOOST_SPEED := 6200.0
const SURFACE_ACCEL := 520.0
const SURFACE_BOOST_ACCEL := 800.0
const SURFACE_BRAKE := 480.0
const SURFACE_COAST_DECEL := 40.0
const SPACE_ACCEL := 820.0
const SPACE_BRAKE := 820.0
const SPACE_COAST_DECEL := 220.0
const SPACE_TRIM_SPEED := 650.0
const SPACE_TRIM_ACCEL := 780.0
const REVERSE_FRACTION := 0.15
const STOP_EPSILON := 0.5
const ROLL_RATE := PI / 2.0
const SURFACE_BANK_LIMIT := PI / 3.0
const SURFACE_APPROACH_SPEED := 140.0
const SURFACE_APPROACH_CEILING := 600.0
const SPACE_APPROACH_SPEED := 480.0
const BODY_CLEARANCE := 135.0
const ARRIVAL_GRACE := 0.75
const TERRAIN_SWEEP_STEP := 1.0
const ARRIVAL_ALTITUDE := 1600.0
const APPROACH_HEIGHT := 68.0
const TOUCHDOWN_HEIGHT := 42.0
const TOUCHDOWN_RANGE := 60.0
const CHASE_OFFSET := Vector3(0, 12, 46)
const CHASE_LOOK := Vector3(0, 3, -40)
const SHIELD_MAX := 100.0

static var ship_shield := SHIELD_MAX
static var under_fire := 0.0

var g
var ship: Node3D
var engine_pivots: Array[Node3D] = []
var _plumes: Array[ExhaustFX] = []
var _gear: Array[Node3D] = []
var _gear_retraction := 0.0
var _loadout := {}
var _accent: Color
var engine_tilt := ShipModel.PARKED_TILT
var engine_power := 0.0
var vertical_thrust := 0.0
var altitude := 0.0
var _surface_velocity := Vector3.ZERO
var _surface_reversing := false
var _space_trim_velocity := Vector3.ZERO
var _arrival_grace := 0.0
var roll := 0.0
var _body_pitch := 0.0
var _hover_height := 0.0
var _hovering := false
var _bob_phase := 0.0
var _lift_held := false
var _lift_step := 0.0
var flight_speed := 0.0
var vertical_speed := 0.0
var grounded := true
var landing_zone := Vector3.ZERO
var arrival := ""
var _look_delta := Vector2.ZERO
var _space_dust: CPUParticles3D


func setup(main, accent: Color) -> void:
	g = main
	name = "Flight"
	_accent = accent
	_setup_space_dust()
	sync_modules()


func _build_ship() -> void:
	if is_instance_valid(ship):
		remove_child(ship)
		ship.queue_free()
	_loadout = g.sim.loadout.duplicate()
	ship = ShipModel.full(_accent, _loadout, true)
	ship.scale = Vector3.ONE * ShipModel.VESSEL_SCALE
	add_child(ship)
	engine_pivots.clear()
	_plumes.clear()
	for slot: String in ShipModel.DRIVE_SLOTS:
		var pivot := ship.get_node("%s/EnginePivot" % slot) as Node3D
		pivot.rotation.x = engine_tilt
		engine_pivots.append(pivot)
		_plumes.append(ShipModel.attach_drive_exhaust(pivot, slot == "engine"))
	_gear.clear()
	for node in ship.find_children("Landing*", "MeshInstance3D", true, false):
		var gear := node as Node3D
		gear.set_meta("deployed_position", gear.position)
		_gear.append(gear)
	_pose_body()
	_pose_gear()


func sync_modules() -> void:
	if not is_instance_valid(ship) or _loadout != g.sim.loadout:
		_build_ship()
	for part: Dictionary in g.sim.parts:
		var module := ship.get_node(part["id"]) as Node3D
		module.visible = part["stage"] == "secured"


func steer(delta: Vector2) -> void:
	_look_delta += delta


func forward() -> Vector3:
	return -basis.z


func body_basis() -> Basis:
	return basis * Basis(Vector3.FORWARD, roll)


func _pose_body() -> void:
	ship.basis = (Basis(Vector3.RIGHT, _body_pitch) * Basis(Vector3.FORWARD, roll)).scaled(
		Vector3.ONE * ShipModel.VESSEL_SCALE)


func tick(dt: float) -> void:
	var touch: MobileControls = null if g.interior_active() else g.touch_ui()
	var stick := touch.move_vector() if touch != null else Vector2.ZERO
	var drive := maxf(-stick.y, float(g.held(KEY_W, false)))
	var brake := maxf(stick.y, float(g.held(KEY_S, false)))
	var roll_input := clampf(stick.x + float(g.held(KEY_D, false)) - float(g.held(KEY_A, false)), -1.0, 1.0)
	var in_space: bool = g.sim.in_space()
	var bay_boost: bool = in_space and g.arena_clash == null and g.sim.boost > 0.0
	var boosting: bool = g.held(KEY_SHIFT, false) or (touch != null and touch.is_firing()) or bay_boost
	var lift: bool = g.held(KEY_SPACE) or (touch != null and touch.flight_held("jump"))
	var down: bool = g.held(KEY_CTRL) or g.held(KEY_C) or (touch != null and touch.flight_held("crouch"))
	if (lift and not _lift_held) or g.flight_lift_tapped():
		_lift_step = LIFT_STEP_TIME
	_lift_held = lift
	var trim := float(lift or _lift_step > 0.0) - float(down)
	_lift_step = maxf(0.0, _lift_step - dt)
	var yaw_input := 0.0
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		yaw_input = float(g.held(KEY_RIGHT)) - float(g.held(KEY_LEFT))
	_apply_steering(yaw_input, dt, in_space)
	_apply_roll(roll_input, dt, in_space)
	drive *= 1.0 - brake
	_tilt_engines(atan2(absf(trim), drive) if drive > 0.0 and not grounded else ShipModel.PARKED_TILT, dt)
	var accelerating := drive * (1.0 - smoothstep(SURFACE_SPEED * 0.72, SURFACE_SPEED, absf(flight_speed)))
	var lean := (accelerating * cos(engine_tilt) - brake) * deg_to_rad(6.0) if not grounded and not in_space else 0.0
	_body_pitch = lerpf(_body_pitch, lean, 1.0 - exp(-dt * 5.0))
	_pose_body()
	if in_space:
		_tick_space(dt, drive, brake, boosting, trim)
	else:
		_tick_surface(dt, drive, brake, boosting, trim)
	var gear_down := not in_space and (grounded or altitude < 15.0)
	_gear_retraction = move_toward(_gear_retraction, 0.0 if gear_down else 1.0, dt * 2.0)
	_pose_gear()
	_update_power_fx()
	update_camera()


func _tilt_engines(target: float, dt: float) -> void:
	var step := (target - engine_tilt) * (1.0 - exp(-dt * 5.0))
	var limit := TILT_RATE * minf(dt, 0.1)
	engine_tilt += clampf(step, -limit, limit)
	for pivot in engine_pivots:
		pivot.rotation.x = engine_tilt


func _pose_gear() -> void:
	var travel := smoothstep(0.0, 1.0, _gear_retraction)
	for gear in _gear:
		var deployed: Vector3 = gear.get_meta("deployed_position")
		gear.position = deployed + Vector3.UP * (2.65 * travel)
		gear.visible = _gear_retraction < 1.0


func _setup_space_dust() -> void:
	_space_dust = CPUParticles3D.new()
	_space_dust.name = "SpaceDust"
	_space_dust.emitting = false
	_space_dust.local_coords = true
	_space_dust.lifetime = 1.15
	GraphicsSettings.set_particle_count(_space_dust, 48)
	_space_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_space_dust.emission_box_extents = Vector3(56.0, 34.0, 22.0)
	_space_dust.direction = Vector3.BACK
	_space_dust.spread = 0.0
	_space_dust.gravity = Vector3.ZERO
	_space_dust.initial_velocity_min = 11.0
	_space_dust.initial_velocity_max = 19.0
	_space_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streak := BoxMesh.new()
	streak.size = Vector3(0.06, 0.06, 2.2)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.50, 0.68, 0.85, 1.0)
	streak.material = material
	_space_dust.mesh = streak
	add_child(_space_dust)


func _speed_effect() -> float:
	if g.sim.in_space():
		return smoothstep(SPACE_APPROACH_SPEED, BOOST_SPEED, absf(flight_speed))
	return smoothstep(SURFACE_APPROACH_SPEED, SURFACE_BOOST_SPEED, absf(flight_speed))


func _update_power_fx() -> void:
	var speed := _speed_effect()
	for plume in _plumes:
		plume.intensity = engine_power
		plume.length_scale = lerpf(1.0, 2.2, speed)
	var audio: Node = g.get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.set_engine_throttle(clampf(engine_power * 0.75 + speed * 0.35, 0.0, 1.0))


func settle_parked(dt: float) -> void:
	_tilt_engines(ShipModel.PARKED_TILT, dt)
	_body_pitch = move_toward(_body_pitch, 0.0, dt)
	_pose_body()
	_gear_retraction = move_toward(_gear_retraction, 0.0, dt * 2.0)
	_pose_gear()


func _apply_steering(yaw_input: float, dt: float, in_space: bool) -> void:
	var look := _look_delta
	_look_delta = Vector2.ZERO
	var yaw_delta := -look.x * 0.0026 * float(g.sens) - yaw_input * dt * 1.05
	var pitch_delta := -look.y * 0.0022 * float(g.sens) * (-1.0 if g.invert_y else 1.0)
	if is_zero_approx(yaw_delta) and is_zero_approx(pitch_delta):
		return
	if in_space:
		basis = (basis * Basis(Vector3.UP, yaw_delta) * Basis(Vector3.RIGHT, pitch_delta)).orthonormalized()
		return
	var angles := basis.get_euler()
	angles.y += yaw_delta
	angles.x = clampf(angles.x + pitch_delta, -PI / 6.0, PI / 6.0) if not grounded else 0.0
	basis = Basis.from_euler(angles)


func _apply_roll(input: float, dt: float, in_space: bool) -> void:
	if in_space:
		roll = wrapf(roll + input * ROLL_RATE * dt, -PI, PI) if input != 0.0 else roll
	elif grounded or input == 0.0:
		roll = move_toward(roll, 0.0, ROLL_RATE * dt)
	else:
		roll = clampf(roll + input * ROLL_RATE * dt, -SURFACE_BANK_LIMIT, SURFACE_BANK_LIMIT)


func _tick_surface(dt: float, drive: float, brake: float, boosting: bool, trim: float) -> void:
	var planet: String = g.sim.location
	var origin: Vector3 = Universe.PLANETS[planet]["origin"]
	var local := position - origin
	var ground: float = g.universe.surface_height(planet, local)
	var gravity := 8.0 if planet == "planet_c" else 20.0
	engine_power = 0.0
	vertical_thrust = 0.0
	if grounded:
		if g.pressed(KEY_E):
			g.disembark_ship()
			return
		if trim <= 0.0:
			return
	elif g.pressed(KEY_L) and _can_touchdown():
		touch_down(landing_zone)
		return

	var holding_height := trim == 0.0 and drive == 0.0
	if holding_height and not _hovering:
		_hover_height = local.y
		vertical_speed = 0.0
		_bob_phase = 0.0
	_hovering = holding_height
	_bob_phase += dt
	var hover_bob := 0.18 * sin(_bob_phase * 1.8) if not UI.reduced_motion else 0.0
	var desired_climb := trim * (CLIMB_SPEED if trim >= 0.0 else DESCENT_SPEED)
	var vertical_accel := (desired_climb - vertical_speed) * 2.6
	if holding_height:
		var target_height := maxf(ground + 0.12, _hover_height + hover_bob)
		var correction_speed := (target_height - local.y) * 2.25
		vertical_accel = (correction_speed - vertical_speed) * (1.0 - exp(-12.0 * dt)) / maxf(dt, 0.0001)

	var cruise_support := gravity * (1.0 - sin(engine_tilt))
	vertical_accel = clampf(vertical_accel, -MAX_THRUST, MAX_THRUST + cruise_support - gravity)
	var lift_thrust := maxf(0.0, vertical_accel + gravity - cruise_support)
	var forward_thrust := drive * cos(engine_tilt) * (SURFACE_BOOST_ACCEL if boosting else SURFACE_ACCEL)
	var forward_accel := forward() * forward_thrust
	vertical_thrust = maxf(0.0, lift_thrust + forward_accel.y)
	engine_power = minf(1.0, Vector2(forward_thrust, lift_thrust).length() / MAX_THRUST)
	grounded = false
	vertical_speed = clampf(vertical_speed + (vertical_accel + forward_accel.y) * dt,
		-SURFACE_FALL_LIMIT, CLIMB_SPEED)

	var heading := Vector3(forward().x, 0.0, forward().z).normalized()
	if brake > 0.0:
		if _surface_velocity.length() < STOP_EPSILON:
			_surface_reversing = true
		var target := -heading * (SURFACE_SPEED * REVERSE_FRACTION * brake) if _surface_reversing else Vector3.ZERO
		_surface_velocity = _surface_velocity.move_toward(target, SURFACE_BRAKE * brake * dt)
	elif drive > 0.0:
		_surface_reversing = false
		_surface_velocity += Vector3(forward_accel.x, 0.0, forward_accel.z) * dt
	else:
		_surface_velocity = _surface_velocity.move_toward(Vector3.ZERO,
			maxf(SURFACE_COAST_DECEL, _surface_velocity.length() * 0.65) * dt)

	var full_speed := SURFACE_BOOST_SPEED if boosting else SURFACE_SPEED
	var ahead := local + (_surface_velocity + Vector3.UP * vertical_speed) * dt
	var clearance := minf(local.y - ground, ahead.y - g.universe.surface_height(planet, ahead))
	var max_speed := lerpf(SURFACE_APPROACH_SPEED, full_speed,
		clampf(clearance / SURFACE_APPROACH_CEILING, 0.0, 1.0))
	var velocity := (_surface_velocity + Vector3.UP * vertical_speed).limit_length(max_speed)
	_surface_velocity = Vector3(velocity.x, 0.0, velocity.z)
	vertical_speed = velocity.y
	flight_speed = _surface_velocity.length() * (-1.0 if _surface_velocity.dot(heading) < 0.0 else 1.0)
	var next := local + velocity * dt
	var departing := next.y >= SURFACE_CEILING and next.y > local.y
	if departing and local.y < SURFACE_CEILING:
		next = local.lerp(next, inverse_lerp(local.y, next.y, SURFACE_CEILING))
		next.y = SURFACE_CEILING
	next = _sweep_surface(planet, local, next)
	altitude = maxf(0.0, next.y - g.universe.surface_height(planet, next))
	if altitude == 0.0:
		touch_down(next)
	else:
		position = origin + next
		if departing and next.y >= SURFACE_CEILING:
			g.leave_surface()


func _sweep_surface(planet: String, start: Vector3, end: Vector3) -> Vector3:
	# Terrain and pads share the same height field. Sample the path in horizontal world units.
	var steps := maxi(1, ceili(Vector2(end.x - start.x, end.z - start.z).length() / TERRAIN_SWEEP_STEP))
	var above := 0.0
	for step in range(1, steps + 1):
		var below := float(step) / steps
		var point := start.lerp(end, below)
		var height: float = g.universe.surface_height(planet, point)
		if point.y <= height:
			for refine in 8:
				var middle := (above + below) * 0.5
				point = start.lerp(end, middle)
				if point.y > g.universe.surface_height(planet, point):
					above = middle
				else:
					below = middle
			point = start.lerp(end, below)
			point.y = g.universe.surface_height(planet, point)
			return point
		above = below
	return end


func _tick_space(dt: float, drive: float, brake: float, boosting: bool, trim: float) -> void:
	var thrust := drive * cos(engine_tilt) * (MAX_THRUST if boosting else SPACE_ACCEL)
	vertical_thrust = trim * SPACE_TRIM_ACCEL
	engine_power = maxf(thrust, absf(vertical_thrust)) / MAX_THRUST
	var full_speed := BOOST_SPEED if boosting else CRUISE_SPEED
	if brake > 0.0:
		var target := 0.0 if flight_speed >= STOP_EPSILON else -CRUISE_SPEED * REVERSE_FRACTION * brake
		flight_speed = move_toward(flight_speed, target, SPACE_BRAKE * brake * dt)
	else:
		var speed_limit := maxf(full_speed, flight_speed - SPACE_COAST_DECEL * dt)
		flight_speed = minf(flight_speed + thrust * dt, speed_limit)

	if trim != 0.0:
		var up := body_basis().y
		var along_up := _space_trim_velocity.dot(up)
		var across_up := _space_trim_velocity - up * along_up
		var target_speed := move_toward(along_up, trim * SPACE_TRIM_SPEED, SPACE_TRIM_ACCEL * dt)
		_space_trim_velocity = (up * target_speed + across_up * exp(-dt * 3.0)).limit_length(SPACE_TRIM_SPEED)
	else:
		_space_trim_velocity *= exp(-dt * 3.0)
	var velocity := forward() * flight_speed + _space_trim_velocity
	var next := position + velocity * dt
	var approach_limit := INF
	for planet: String in Universe.PLANETS:
		var center: Vector3 = Universe.PLANETS[planet]["origin"]
		var closest := Geometry3D.get_closest_point_to_segment(center, position, next)
		var height: float = closest.distance_to(center) - g.universe.body_radius(planet)
		if height <= ARRIVAL_ALTITUDE * 2.0:
			var blend := inverse_lerp(ARRIVAL_ALTITUDE, ARRIVAL_ALTITUDE * 2.0, height)
			approach_limit = minf(approach_limit, lerpf(SPACE_APPROACH_SPEED, full_speed, clampf(blend, 0.0, 1.0)))
	if velocity.length() > approach_limit:
		var factor := approach_limit / velocity.length()
		flight_speed *= factor
		_space_trim_velocity *= factor
		velocity *= factor
		next = position + velocity * dt
	vertical_speed = _space_trim_velocity.dot(basis.y)

	next = _sweep_space(position, next, dt)
	position = next
	if arrival != "" and g.pressed(KEY_L):
		_level_body()
		g.request_landing(arrival)


func _sweep_space(start: Vector3, end: Vector3, dt: float) -> Vector3:
	var next := end
	var contact: String = ""
	var nearest := INF
	var first_hit := INF
	var direction := start.direction_to(end)
	var distance := start.distance_to(end)
	for planet: String in Universe.PLANETS:
		var center: Vector3 = Universe.PLANETS[planet]["origin"]
		var radius: float = g.universe.body_radius(planet)
		var hard_radius := radius + BODY_CLEARANCE
		var from_center := start - center
		var hit := _ray_sphere(start, direction, center, hard_radius) if distance > 0.0 else -1.0
		if from_center.length() < hard_radius or (hit >= 0.0 and hit <= distance and hit < first_hit):
			first_hit = maxf(0.0, hit)
			var normal := (start + direction * first_hit - center).normalized()
			next = center + (normal if normal != Vector3.ZERO else Vector3.UP) * (hard_radius + 0.02)
	if first_hit < INF:
		flight_speed = 0.0
		vertical_speed = 0.0
		_space_trim_velocity = Vector3.ZERO
	for planet: String in Universe.PLANETS:
		var center: Vector3 = Universe.PLANETS[planet]["origin"]
		var closest := Geometry3D.get_closest_point_to_segment(center, start, next)
		var height: float = closest.distance_to(center) - g.universe.body_radius(planet)
		if height <= ARRIVAL_ALTITUDE and height < nearest:
			contact = planet
			nearest = height
	if contact != "":
		arrival = contact
		_arrival_grace = ARRIVAL_GRACE
	else:
		_arrival_grace = maxf(0.0, _arrival_grace - dt)
		if _arrival_grace == 0.0:
			arrival = ""
	return next


func enter_space() -> void:
	grounded = false
	vertical_speed = 0.0
	_space_trim_velocity = Vector3.ZERO
	_arrival_grace = 0.0
	_hovering = false
	_lift_step = 0.0


func _level_body() -> void:
	roll = 0.0
	_body_pitch = 0.0
	_pose_body()


func begin_approach(zone: Vector3, heading: Basis) -> void:
	landing_zone = zone
	var origin: Vector3 = Universe.PLANETS[g.sim.location]["origin"]
	transform = Transform3D(heading, origin + zone + Vector3.UP * APPROACH_HEIGHT)
	altitude = APPROACH_HEIGHT
	_surface_velocity = Vector3.ZERO
	_surface_reversing = false
	_level_body()
	flight_speed = 0.0
	vertical_speed = 0.0
	_hovering = false
	_lift_step = 0.0
	grounded = false
	arrival = ""
	engine_power = 0.0
	vertical_thrust = 0.0
	_update_power_fx()


func touch_down(point: Vector3) -> void:
	var origin: Vector3 = Universe.PLANETS[g.sim.location]["origin"]
	position = origin + point
	basis = Basis(Vector3.UP, basis.get_euler().y)
	_level_body()
	grounded = true
	altitude = 0.0
	_surface_velocity = Vector3.ZERO
	_surface_reversing = false
	flight_speed = 0.0
	vertical_speed = 0.0
	_hovering = false
	_lift_step = 0.0
	engine_power = 0.0
	vertical_thrust = 0.0
	_update_power_fx()
	g.on_touchdown()


func update_camera() -> void:
	if not g.piloting:
		return
	g.universe.focus(position)
	if g.interior_active():
		_space_dust.emitting = false
		_space_dust.hide()
		return
	var in_space: bool = g.sim.in_space()
	var camera_bank := roll if in_space else roll * 0.2
	var view := Transform3D(basis * Basis(Vector3.FORWARD, camera_bank), global_position)
	var camera_pose := view * Transform3D(Basis.IDENTITY, CHASE_OFFSET).looking_at(CHASE_LOOK)
	if not in_space:
		var origin: Vector3 = Universe.PLANETS[g.sim.location]["origin"]
		var local_camera: Vector3 = position + (camera_pose.origin - view.origin) - origin
		var ground: float = g.universe.surface_height(g.sim.location, local_camera)
		if local_camera.y < ground + 2.0:
			camera_pose.origin.y += ground + 2.0 - local_camera.y
			camera_pose = camera_pose.looking_at(to_global(CHASE_LOOK), view.basis.y)
	g.cam.global_transform = camera_pose
	var motion := GraphicsSettings.motion_effects and not UI.reduced_motion
	var speed := _speed_effect()
	g.cam.fov = 70.0 + (speed * 12.0 if motion else 0.0)
	_space_dust.emitting = in_space and motion and flight_speed > SPACE_APPROACH_SPEED * 2.0
	_space_dust.visible = _space_dust.emitting
	if _space_dust.emitting:
		_space_dust.global_transform = camera_pose.translated_local(Vector3(0, 0, -55.0))
		_space_dust.speed_scale = lerpf(0.85, 2.8, speed)


func _can_touchdown() -> bool:
	var origin: Vector3 = Universe.PLANETS[g.sim.location]["origin"]
	var approach := position - origin - landing_zone
	return approach.y <= TOUCHDOWN_HEIGHT and Vector2(approach.x, approach.z).length() <= TOUCHDOWN_RANGE


func hud_update(hud: Hud) -> void:
	hud.set_flight_footer()
	if g.arena_clash == null and g.sim.in_space() and not hud.touch_ui_visible():
		hud.footer.text += "   I CABIN"
	hud.visual_status.hide()
	hud.vitals_panel.hide()
	hud.station_panel.hide()
	hud.crosshair.hide()
	hud.title.text = "FLIGHT"
	var tilt := rad_to_deg(engine_tilt)
	hud.set_flight_instruments(flight_speed, altitude, vertical_speed, tilt, engine_power, g.sim.in_space())
	hud.subtitle.text = "HULL %d%%" % roundi(g.sim.hull)
	hud.objectives.get_parent().get_parent().visible = g.sim.in_space()

	hud.radar_title.text = "PLANET CONTACTS" if g.sim.in_space() else "LANDING PAD"
	hud.radar.points = []
	hud.radar.range_m = 30000.0 if g.sim.in_space() else 160.0
	if g.sim.in_space():
		var contacts := PackedStringArray()
		for planet: String in Universe.PLANETS:
			var origin: Vector3 = Universe.PLANETS[planet]["origin"]
			var distance := maxf(0.0, position.distance_to(origin) - g.universe.body_radius(planet))
			var contact := basis.inverse() * (origin - position)
			var direction := contact.normalized()
			var color := UI.CYAN
			if planet != "planet_c":
				color = Color.html(Sim.EMPIRE_COLORS["orange" if planet == "planet_a" else "crimson"])
			hud.radar.points.append({"p": Vector2(contact.x, contact.z), "c": color, "s": 5.0, "ring": true, "label": planet.right(1).to_upper(), "priority": true})
			contacts.append("%s %s · %.1f km" % [
				"▲" if direction.z < -0.65 else ("→" if direction.x > 0.0 else "←"),
				Universe.PLANETS[planet]["label"], distance / 1000.0])
		hud.objectives.text = "\n".join(contacts)
		hud.set_prompt("PRESS L TO LAND · " + Universe.PLANETS[arrival]["label"] if arrival != "" else "")
	else:
		var origin: Vector3 = Universe.PLANETS[g.sim.location]["origin"]
		var zone_offset := position - origin - landing_zone
		var offset := basis.inverse() * -zone_offset
		var distance := Vector2(zone_offset.x, zone_offset.z).length()
		hud.radar.points.append({"p": Vector2(offset.x, offset.z), "c": UI.CYAN, "s": 5.0, "ring": true})
		hud.objectives.text = "ALTITUDE %d m · V/S %+.1f m/s\nSPACE ABOVE %d m · PAD %d m" % [
			roundi(altitude), vertical_speed, roundi(SURFACE_CEILING), roundi(distance)]
		if grounded and flight_speed < 1.0:
			hud.set_prompt("E  EXIT SHIP", "Hold Space to lift" if not hud.touch_ui_visible() else "Hold LIFT to take off")
		elif not grounded and _can_touchdown():
			hud.set_prompt("PRESS L FOR AUTO-TOUCHDOWN")
		else:
			hud.set_prompt("")
	hud.radar.request_redraw()
	if g.arena_clash == null and hud.tactical_panel.visible:
		hud.tactical_radar.cover_shapes.clear()
		hud.update_tactical(hud.radar.points, hud.radar_title.text, hud.radar.range_m)


static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var h := b * b - (oc.dot(oc) - r * r)
	return -1.0 if h < 0.0 else -b - sqrt(h)
