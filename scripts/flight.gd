## Flight leg (outbound to Planet B or return to Planet A).
## Pilot dodges debris, Engineer services systems, Gunner works the dorsal turret, Raider replaces damaged plates.
## Roles not controlled by the human are flown by bots.
class_name Flight
extends Node3D

const SYSTEMS := ["reactor", "coolant", "scrubber", "stores"]
const SYSTEM_NAMES := {"reactor": "Reactor / power bus", "coolant": "Coolant loop", "scrubber": "CO₂ scrubber", "stores": "Food & water"}
const FAULT_SYSTEM := {"reactor": "reactor", "power": "reactor", "cooling": "coolant", "scrubber": "scrubber"}
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const ACCENT := Color("#f08a4b")
const LEG_DISTANCE_M := 1000.0
const ARRIVAL_RADIUS_M := 35.0
const EARTH_RETURN_RADIUS_M := 40.0
const ORIGIN_COLOR := Color("#6fe0e6")
const SHIP_OFFSET := Vector3(0, -3.0, 2.0)

var g
var rig: Node3D
var ship: Node3D
var flame: Node3D
var space_dust: CPUParticles3D
var turret_rig: Node3D
var turret_head: Node3D
var turret_aim_dir := Vector3.FORWARD
var plate_nodes: Array = []
var system_nodes := {}
var shield_dome: MeshInstance3D
var overlay_layer: CanvasLayer
var overlay: Control
var flight_speed := 0.0
var strafe_speed := 0.0
var world_units_per_meter := 1.0
var _synced_flight_time := 0.0
var _heading := Vector2.ZERO
var _start_heading := Vector2.ZERO
var destination_beacon: MeshInstance3D
var origin_beacon: MeshInstance3D
var beacon_basis := Basis.IDENTITY
var rocks: Array = []
var drones: Array = []
var tracers: Array = []
var sx := 0.0
var sy := 0.0
var spawn_clock := 1.5
var drone_clock := 9.0
var fire_cd := 0.0
var bot_fire := 0.55
var eng_sel := 0
var raid_sel := 0
var eng_delay := 0.0
var raid_delay := 0.0
var shake := 0.0
var _fov_kick := 0.0
var _applied_kick := 0.0
var _was_boosting := false
var _rumble_t := 0.0
var done := false
var warning_clock := 0.0
var bank_target := 0.0
const BANK_MAX := deg_to_rad(18.0)
var _prev_yaw := 0.0
var _yaw_rate_smooth := 0.0
var rng := RandomNumberGenerator.new()


func actor(_i: int) -> Variant:
	return null


## Pad touchdown points (planet-local) the legs fly to; B matches PlanetB.SHIP_POS.
const A_LAND := Vector3(0, 0, 64)
const B_LAND := Vector3(0, 0, 58)

var path_a := Vector3.ZERO      # universe-space origin of this node when the leg starts
var path_b := Vector3.ZERO      # approach point 900 m short of the destination pad
var land_pos := Vector3.ZERO    # node origin that puts the ship exactly on the destination pad
var yaw_end := 0.0              # PI when flying back toward Planet A (+Z)
var cine_from := Transform3D.IDENTITY
var cine_rig_from := Vector3.ZERO
var cine_started := false


## The leg is a real flight through the universe: `start` is where the ship is when the leg begins.
func setup(main, start: Transform3D) -> void:
	g = main
	g.sim.manual_flight = true
	g.sim.destination_reached = false
	name = "Flight"
	rng.seed = g.sim.match_seed + (7 if g.sim.flight_leg == "return" else 0)
	var going_home: bool = g.sim.flight_leg == "return"
	if going_home:
		land_pos = Universe.A_ORIGIN + A_LAND - SHIP_OFFSET
		path_b = land_pos + Vector3(0, 260, -900)
		yaw_end = PI
	else:
		land_pos = Universe.B_ORIGIN + B_LAND - SHIP_OFFSET
		path_b = land_pos + Vector3(0, 260, 900)
		yaw_end = 0.0
	path_a = start.origin
	world_units_per_meter = path_a.distance_to(path_b) / LEG_DISTANCE_M
	var direction := (path_b - path_a).normalized()
	_start_heading = Vector2(asin(direction.y), atan2(-direction.x, -direction.z))
	_heading = _start_heading
	transform = Transform3D(Basis.from_euler(Vector3(_heading.x, _heading.y, 0.0)), path_a)
	beacon_basis = transform.basis * Basis(Vector3.RIGHT, PI * 0.5)
	destination_beacon = _build_beacon(path_b, ACCENT)
	origin_beacon = _build_beacon(path_a, ORIGIN_COLOR)
	rig = Node3D.new()
	add_child(rig)
	ship = ShipModel.full(ACCENT, g.sim.loadout)
	ship.position = SHIP_OFFSET
	rig.add_child(ship)
	flame = ShipModel.flame(8.0, ship)
	ship.add_child(flame)
	space_dust = CPUParticles3D.new()
	space_dust.name = "SpaceDust"
	GraphicsSettings.set_particle_count(space_dust, 96)
	space_dust.position = Vector3(0, 0, -115)
	space_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	space_dust.emission_box_extents = Vector3(42, 27, 18)
	space_dust.local_coords = true
	space_dust.direction = Vector3.BACK
	space_dust.spread = 0.0
	space_dust.gravity = Vector3.ZERO
	space_dust.lifetime = 1.6
	space_dust.initial_velocity_min = 68.0
	space_dust.initial_velocity_max = 85.0
	space_dust.emitting = false
	var grain := BoxMesh.new()
	grain.size = Vector3(0.065, 0.065, 0.75)
	var dust_material := StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.albedo_color = Color("#8193aa")
	grain.material = dust_material
	space_dust.mesh = grain
	rig.add_child(space_dust)
	_build_stations()
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 4
	add_child(overlay_layer)
	overlay = FlightOverlay.new()
	overlay.flight = self
	overlay_layer.add_child(overlay)
	g.yaw = 0.0
	g.pitch = _start_heading.x
	g.cam.fov = 70.0
	_applied_kick = 0.0
	# Continue from the launch chase camera instead of cutting to the role camera.
	cam_from = Transform3D.IDENTITY.looking_at(Vector3(0, 2, -40) - Vector3(0, 10, 38), Vector3.UP)
	cam_from.origin = Vector3(0, 10, 38)
	if g.world is PlanetA and g.mode == "cine" and g.cine["kind"] == "launch":
		cam_from = transform.affine_inverse() * g.universe.transform.affine_inverse() * g.cam.global_transform
	cam_blend = 0.0


func _build_beacon(point: Vector3, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 3.5 * world_units_per_meter
	ring.outer_radius = 4.0 * world_units_per_meter
	marker.mesh = ring
	marker.material_override = Gfx.unshaded(color)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	marker.transform = transform.affine_inverse() * Transform3D(beacon_basis, point)
	return marker


func _distance_m(point: Vector3) -> float:
	return transform.origin.distance_to(point) / world_units_per_meter


func _can_return_to_earth() -> bool:
	return g.sim.phase == "flight" and g.sim.flight_leg == "outbound" \
		and is_instance_valid(g.world_a) and _distance_m(path_a) <= EARTH_RETURN_RADIUS_M


func _return_to_earth(s: Sim) -> void:
	done = true
	overlay_layer.hide()
	s.phase = "route"
	s.flight_time = 0.0
	s.boost = 0.0
	s.manual_flight = false
	s.destination_reached = false
	g.world_a.arrive_home()
	g.world_a.delivery = false
	g.world_a.pad_stage = "ready"
	g.enter_world(g.world_a, Transform3D.IDENTITY)


## Where the node is at progress p: climb out, cruise at altitude, then descend onto the approach.
func _pose(p: float) -> Transform3D:
	var climb := smoothstep(0.0, 0.14, p)
	var desc := smoothstep(0.82, 1.0, p)
	var y := lerpf(lerpf(path_a.y, Universe.CRUISE_ALT, climb), path_b.y, desc)
	var xz := Vector2(path_a.x, path_a.z).lerp(Vector2(path_b.x, path_b.z), p)
	var yaw := lerpf(0.0, yaw_end, smoothstep(0.0, 0.12, p))
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(xz.x, y, xz.y))


## The universe is moved under the ship so this node stays at the global origin (local == global).
func _sync_universe() -> void:
	var universe_frame := transform.affine_inverse()
	g.universe.transform = universe_frame
	destination_beacon.transform = universe_frame * Transform3D(beacon_basis, path_b)
	origin_beacon.transform = universe_frame * Transform3D(beacon_basis, path_a)


func _hazard() -> float:
	var s: Sim = g.sim
	if s.flight_leg == "return":
		return 1.0
	return s.route["hazard"] if s.route != null else 1.0


func _turret_pos() -> Vector3:
	var p = g.sim.part_by_id("engine")
	return rig.position + SHIP_OFFSET + p["slot"] + Vector3(0, 2.4, 0)


func _panel_pos(i: int) -> Vector3:
	var off: Vector3 = g.sim.panels[i]["offset"]
	return rig.position + SHIP_OFFSET + Vector3(off.x, Sim.SHIP_Y + off.y - 0.6 * Sim.SHIP_SCALE, off.z)


func tick(dt: float) -> void:
	var s: Sim = g.sim
	if done:
		return
	if s.phase == "spectator":
		_update_world(dt)
		_camera(dt)
		return
	if _can_return_to_earth() and g.pressed(KEY_E):
		_return_to_earth(s)
		return
	s.tick_systems(dt)
	var r := s.selected
	# Skills.
	if g.pressed(KEY_Q) and s.use_skill(r, "q"):
		g.sfx("shield_recharge", -6)
		g.sfx("ability_cast", -6)
		CombatFX.ring_pulse(rig, SHIP_OFFSET + Vector3(0, 2.0, 0), _turret_color() if r == 2 else Sim.role_color(r), 11.0, 0.45)
		g.hud.toast("%s · %s" % [Sim.SPECIALISTS[r]["name"], Sim.SPECIALISTS[r]["skill"]], 1.6)
	if g.pressed(KEY_F) and s.use_skill(r, "f"):
		g.sfx("shield_recharge", -3)
		g.sfx("ability_cast", -4)
		CombatFX.ring_pulse(rig, SHIP_OFFSET + Vector3(0, 2.0, 0), Color("#38bdf8"), 14.0, 0.55)
		g.hud.toast("ULTIMATE READY → USED", 1.6)
	_pilot(dt, r == 0)
	_gunner(dt, r == 2)
	_engineer(dt, r == 1)
	_raider(dt, r == 3)
	_spawn(dt)
	_threat_feedback(dt)
	_update_world(dt)
	_update_stations(dt)
	_camera(dt)
	if s.hull <= 0.0 and s.phase == "flight":
		s.eliminate_crew(0, rig.position, "space")
		_explode(rig.position, 8.0)
		ship.visible = false
		g.crew_eliminated()
		return
	var res := s.complete_flight()
	if res != "":
		done = true
		g.flight_finished(res)


# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------
func _pilot(dt: float, human: bool) -> void:
	var s: Sim = g.sim
	var tx := sx
	var ty := sy
	var strafe := 0.0
	var target_speed := 185.0 if s.boost > 0.0 else 0.0
	var sprinting: bool = human and g.held(KEY_SHIFT)
	if human:
		g.pitch = clampf(g.pitch, -1.15, 1.15)
		var turn_weight := 1.0 - exp(-dt * 5.0)
		_heading.x = lerpf(_heading.x, g.pitch, turn_weight)
		_heading.y = lerp_angle(_heading.y, g.yaw + _start_heading.y, turn_weight)
		strafe = float(g.held(KEY_D)) - float(g.held(KEY_A))
		if g.held(KEY_S):
			target_speed = -40.0
		elif s.boost <= 0.0 and g.held(KEY_W):
			target_speed = 150.0 if sprinting else 115.0
		tx = move_toward(sx, 0.0, dt * 14.0)
		ty = move_toward(sy, 0.0, dt * 10.0)
	else:
		var threat = null
		var best := -INF
		for k in rocks:
			if k["z"] > -170.0 and k["z"] < -6.0 and absf(k["x"] - sx) < k["r"] + 5.0 and absf(k["y"] - sy) < k["r"] + 4.0:
				if k["z"] > best:
					best = k["z"]
					threat = k
		if threat != null and threat["dodge"]:
			var side := signf(sx - threat["x"])
			if side == 0.0:
				side = 1.0 if threat["x"] < 0.0 else -1.0
			tx = threat["x"] + side * (threat["r"] + 7.0)
		else:
			tx = sx * 0.98
			ty = sy * 0.98
		tx = sx + clampf(tx - sx, -14.0 * dt * s.handling_mult, 14.0 * dt * s.handling_mult)
		ty = sy + clampf(ty - sy, -10.0 * dt * s.handling_mult, 10.0 * dt * s.handling_mult)
	if not human and s.phase == "flight":
		# Autopilot: with the player crewing another station, the AI pilot steers toward the
		# destination and cruises so the leg still progresses (it brakes inside the arrival zone).
		var to_dest := path_b - transform.origin
		if to_dest.length() > 0.001:
			var d := to_dest.normalized()
			var turn_weight := 1.0 - exp(-dt * 2.0)
			_heading.x = lerpf(_heading.x, asin(clampf(d.y, -1.0, 1.0)), turn_weight)
			_heading.y = lerp_angle(_heading.y, atan2(-d.x, -d.z), turn_weight)
		if _distance_m(path_b) > ARRIVAL_RADIUS_M:
			target_speed = maxf(target_speed, 115.0)
	var acceleration := 75.0
	if target_speed == 0.0:
		acceleration = 180.0
	elif target_speed < 0.0:
		acceleration = 95.0 if flight_speed > 0.0 else 40.0
	flight_speed = move_toward(flight_speed, target_speed, dt * acceleration)
	strafe_speed = move_toward(strafe_speed, strafe * (42.0 if sprinting else 30.0), dt * 100.0 * s.handling_mult)
	transform.basis = Basis.from_euler(Vector3(_heading.x, _heading.y, 0.0))
	# Visual-only roll: strafe/dodge bank plus a roll into yaw turns (max ±18°), levelling out when straight.
	var yaw_rate := wrapf(_heading.y - _prev_yaw, -PI, PI) / maxf(dt, 0.001)
	_prev_yaw = _heading.y
	_yaw_rate_smooth = lerpf(_yaw_rate_smooth, yaw_rate, 1.0 - exp(-dt * 8.0))
	var strafe_bank := clampf(strafe_speed * -0.009 - (tx - sx) / maxf(dt, 0.001) * 0.013, -0.28, 0.28)
	bank_target = clampf(strafe_bank + clampf(_yaw_rate_smooth * 0.5, -0.2, 0.2), -BANK_MAX, BANK_MAX)
	sx = clampf(tx, -16.0, 16.0)
	sy = clampf(ty, -9.0, 9.0)
	rig.position = Vector3(sx, sy, 0)
	rig.rotation.z = lerpf(rig.rotation.z, bank_target, 1.0 - exp(-dt * 6.0))
	for exhaust in flame.get_children():
		exhaust.intensity = 1.4 if s.boost > 0.0 else 0.85
		exhaust.scale = Vector3(1, 1, 1.45 if s.boost > 0.0 else 1.0)


func _fire(from: Vector3, dir: Vector3, dmg: float, color := Color("#ffd29a")) -> void:
	var hit_t := 260.0
	var target = null
	var kind := ""
	for d in drones:
		var t := _ray_sphere(from, dir, d["node"].position, 2.8)
		if t > 0.0 and t < hit_t:
			hit_t = t
			target = d
			kind = "drone"
	for k in rocks:
		var t := _ray_sphere(from, dir, Vector3(k["x"], k["y"], k["z"]), k["r"])
		if t > 0.0 and t < hit_t:
			hit_t = t
			target = k
			kind = "rock"
	_tracer(from, from + dir * hit_t, color)
	if target == null:
		return
	g.sfx("hitmarker", -10)
	g.hud.confirm_hit()
	if kind == "drone":
		target["hp"] -= dmg
		if target["hp"] <= 0.0:
			var pos: Vector3 = target["node"].position
			_explode(pos, 3.0)
			g.sfx_3d("explosion", to_global(pos), -4)
			target["node"].queue_free()
			drones.erase(target)
			g.sim.score += 50
	else:
		target["hp"] -= dmg
		if target["hp"] <= 0.0:
			var pos := Vector3(target["x"], target["y"], target["z"])
			_explode(pos, target["r"])
			g.sfx_3d("explosion", to_global(pos), -6)
			target["node"].queue_free()
			rocks.erase(target)


static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var h := b * b - cc
	if h < 0.0:
		return -1.0
	return -b - sqrt(h)


func _gunner(dt: float, human: bool) -> void:
	var s: Sim = g.sim
	fire_cd -= dt
	var dmg := s.turret_mult * (2.0 if s.upgrades.has("weapons") else 1.0) * (1.6 if s.overdrive > 0.0 else 1.0)
	var col := _turret_color()
	if human:
		turret_aim_dir = g.cam_forward()
		if g.lmb and fire_cd <= 0.0:
			fire_cd = 0.06 if s.overdrive > 0.0 else 0.11
			g.sfx("shot_carbine", -16)
			_fire(_turret_pos(), turret_aim_dir, dmg, col)
	else:
		bot_fire -= dt
		var target: Variant = null
		var best := INF
		for k in rocks:
			var rock_distance: float = -k["z"]
			if rock_distance > 10.0 and rock_distance < minf(best, 170.0) and absf(k["x"] - sx) < k["r"] + Sim.SHIP_SCALE and absf(k["y"] - sy) < k["r"] + 2.4 * Sim.SHIP_K:
				best = rock_distance
				target = Vector3(k["x"], k["y"], k["z"])
		var targeting_rock := target != null
		if not targeting_rock:
			for d in drones:
				var drone_distance: float = d["node"].position.length()
				if drone_distance < best:
					best = drone_distance
					target = d["node"].position
		turret_aim_dir = Vector3.FORWARD
		if target != null:
			var from := _turret_pos()
			turret_aim_dir = (target - from).normalized()
			if bot_fire <= 0.0:
				bot_fire = 0.38 if s.overdrive > 0.0 else 0.55
				if not targeting_rock and rng.randf() > 0.65:
					var shot_offset := Vector3(rng.randf_range(-6, 6), rng.randf_range(-4, 4), 0)
					turret_aim_dir = (target - from + shot_offset).normalized()
				g.sfx("shot_carbine", -20)
				_fire(from, turret_aim_dir, dmg, col)


func _engineer(dt: float, human: bool) -> void:
	var s: Sim = g.sim
	if human:
		if g.pressed(KEY_W): eng_sel = (eng_sel + 3) % 4
		if g.pressed(KEY_S): eng_sel = (eng_sel + 1) % 4
		if g.wheel != 0:
			s.reactor = clampf(s.reactor + g.wheel * 5.0, 30.0, 100.0)
		if g.lmb:
			s.maintain_system(1, dt, SYSTEMS[eng_sel])
		return
	var want := ""
	if s.fault != null:
		eng_delay += dt
		if eng_delay > 3.5:
			want = FAULT_SYSTEM[s.fault]
	else:
		eng_delay = 0.0
		if s.temperature > 62.0: want = "coolant"
		elif s.co2 > 1500.0: want = "scrubber"
		elif s.crew_nutrition < 45.0: want = "stores"
		elif s.power < 1.2: want = "reactor"
	s.reactor = 75.0 if s.power < 2.0 else 62.0
	if want != "":
		s.maintain_system(1, dt, want)


func _raider(dt: float, human: bool) -> void:
	var s: Sim = g.sim
	if human:
		if g.pressed(KEY_W): raid_sel = (raid_sel + 2) % 3
		if g.pressed(KEY_S): raid_sel = (raid_sel + 1) % 3
		if g.pressed(KEY_E) and s.remove_panel(raid_sel, 3):
			g.sfx("reload_click", -4)
		if g.lmb:
			var p = s.panels[raid_sel]
			var was: bool = p["removed"]
			if s.repair_panel(raid_sel, 3, dt) and was and not p["removed"]:
				g.sfx("capture_tick", -4)
		return
	var worst := -1
	for i in s.panels.size():
		if s.panels[i]["health"] < 60.0 and (worst < 0 or s.panels[i]["health"] < s.panels[worst]["health"]):
			worst = i
	if worst < 0:
		raid_delay = 0.0
		return
	raid_delay += dt
	if raid_delay > 4.0:
		s.remove_panel(worst, 3)
		s.repair_panel(worst, 3, dt)


# ---------------------------------------------------------------------------
# Hazards
# ---------------------------------------------------------------------------
func _spawn(dt: float) -> void:
	var s: Sim = g.sim
	var hz := _hazard()
	var remaining := s.flight_duration() - s.flight_time
	spawn_clock -= dt
	if spawn_clock <= 0.0 and remaining > 4.0 and absf(flight_speed) > 0.0:
		spawn_clock = rng.randf_range(0.9, 1.8) / hz
		var r := rng.randf_range(1.6, 4.6)
		var rock := Gfx.rock(r, Color("#8f8aa3"), rng)
		var k := {"node": rock, "x": sx + rng.randf_range(-22, 22), "y": sy + rng.randf_range(-10, 10), "z": -460.0, "r": r,
			"hp": r * 2.0, "dodge": rng.randf() < 0.8, "spin": Vector3(rng.randf(), rng.randf(), rng.randf()) * 1.5}
		var nose_spawn_chance := 0.10 if s.difficulty == "standard" else 0.35
		if rng.randf() < nose_spawn_chance:
			k["x"] = sx + rng.randf_range(-3, 3)
			k["y"] = sy + rng.randf_range(-2, 2)
		add_child(rock)
		rocks.append(k)
	drone_clock -= dt
	if drone_clock <= 0.0 and drones.size() < 3 and remaining > 8.0:
		drone_clock = rng.randf_range(12.0, 18.0) / hz
		var n := Node3D.new()
		var body := Gfx.sphere(1.6, Color("#3a3358"), Vector3.ZERO, 0.0, 12)
		n.add_child(body)
		for sxw in [-1, 1]:
			n.add_child(Gfx.box(Vector3(2.6, 0.2, 1.4), Color("#ed7d8d"), Vector3(sxw * 2.2, 0, 0)))
		n.add_child(Gfx.sphere(0.5, Color("#ff5d6c"), Vector3(0, 0, 1.4), 3.0, 8))
		n.position = Vector3(rng.randf_range(-40, 40), rng.randf_range(4, 20), -260)
		add_child(n)
		drones.append({"node": n, "hp": 4.0, "cd": 3.0, "home": Vector3(rng.randf_range(-20, 20), rng.randf_range(4, 14), rng.randf_range(-60, -40)), "t": rng.randf() * 10.0})
		g.hud.toast("RAIDER DRONE INBOUND — Barbara, man the turret (3)", 2.5)


func _update_world(dt: float) -> void:
	var s: Sim = g.sim
	var speed := absf(flight_speed)
	space_dust.visible = not UI.reduced_motion and GraphicsSettings.motion_effects
	space_dust.emitting = space_dust.visible and speed > 0.0
	space_dust.speed_scale = speed / 85.0
	if s.phase == "flight":
		var duration := s.flight_duration()
		if absf(s.flight_time - _synced_flight_time) > 0.05:
			transform.origin = _pose(clampf(s.flight_time / duration, 0.0, 1.0)).origin
		else:
			var velocity := transform.basis.x * strafe_speed - transform.basis.z * flight_speed
			transform.origin += velocity * world_units_per_meter * dt
		var distance := _distance_m(path_b)
		var reached := distance <= ARRIVAL_RADIUS_M
		s.destination_reached = reached
		s.flight_time = duration if reached else (1.0 - clampf(distance / LEG_DISTANCE_M, 0.0, 1.0)) * duration
		_synced_flight_time = s.flight_time
	_sync_universe()
	for k in rocks.duplicate():
		k["z"] += flight_speed * dt
		var node: Node3D = k["node"]
		node.position = Vector3(k["x"], k["y"], k["z"])
		node.rotation += k["spin"] * dt
		if k["z"] > -10.0 and k["z"] < 12.0 and s.phase == "flight":
			if absf(k["x"] - sx) < k["r"] + Sim.SHIP_SCALE and absf(k["y"] - sy) < k["r"] + 2.4 * Sim.SHIP_K:
				var dmg := 7.0 * maxf(1.0, k["r"] / 3.0)
				if s.shield > 0.0:
					g.sfx("shield_hit", -6)
				else:
					s.damage_ship(dmg)
					s.metrics["hazards"] += 1
					var p = s.panels[rng.randi() % s.panels.size()]
					p["health"] = maxf(10.0, p["health"] - 18.0)
					g.hud.hurt(0.4)
					g.sfx("explosion", -6)
					shake = 0.6
				_explode(node.position, k["r"])
				node.queue_free()
				rocks.erase(k)
				continue
		if k["z"] > 80.0 or k["z"] < -540.0:
			node.queue_free()
			rocks.erase(k)
	for d in drones:
		d["t"] += dt
		var n: Node3D = d["node"]
		var prev_pos := n.position
		var home: Vector3 = d["home"] + Vector3(sin(d["t"] * 0.9) * 10.0, sin(d["t"] * 1.3) * 3.0, 0)
		n.position = n.position.lerp(home + Vector3(sx, sy, 0), clampf(dt * 1.2, 0.0, 1.0))
		d["vel"] = (n.position - prev_pos) / maxf(dt, 0.001)
		n.look_at(rig.position, Vector3.UP)
		d["cd"] -= dt
		if d["cd"] <= 0.0 and s.phase == "flight":
			d["cd"] = 2.4
			var hit: bool = s.decoy <= 0.0 and rng.randf() < 0.7
			var to: Vector3 = rig.position + Vector3(0, 2, 0) + (Vector3.ZERO if hit else Vector3(rng.randf_range(-12, 12), 6, 0))
			_tracer(n.position, to, Color("#ff5d6c"))
			if hit:
				if s.shield > 0.0:
					g.sfx("shield_hit", -8)
				else:
					s.damage_ship(3.0)
					g.hud.hurt(0.25)
					g.sfx("hurt", -10)
	for t in tracers.duplicate():
		t["life"] -= dt
		if t["life"] <= 0.0:
			t["node"].queue_free()
			tracers.erase(t)
	if is_instance_valid(overlay):
		overlay.queue_redraw()


func _threat_feedback(dt: float) -> void:
	warning_clock = maxf(0.0, warning_clock - dt)
	if warning_clock > 0.0: return
	var scan_limit: float = -180.0 * float(g.sim.scan_mult)
	for rock in rocks:
		if rock["z"] < -70.0 and rock["z"] > scan_limit and absf(rock["x"] - sx) < rock["r"] + Sim.SHIP_SCALE and absf(rock["y"] - sy) < rock["r"] + 3.0:
			g.hud.toast("COLLISION COURSE · Pilot [1] evade %s or Gunner [3] destroy debris" % ("RIGHT" if rock["x"] <= sx else "LEFT"), 1.5)
			g.sfx("alarm_warn", -9)
			warning_clock = 4.0
			return


func _tracer(a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var c := Gfx.cyl(0.09, length, color, Vector3.ZERO, 6)
	c.material_override = Gfx.unshaded(color, 0.9)
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(c)
	c.position = (a + b) * 0.5
	var up := (b - a).normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	c.basis = Basis(x, up, x.cross(up))
	tracers.append({"node": c, "life": 0.07})


func _explode(p: Vector3, r: float) -> void:
	preload("res://scripts/combat_fx.gd").impact(self, p, Color("#ffb45e"), r, 32)


var cam_from := Transform3D.IDENTITY
var cam_blend := 1.0


func _camera(dt: float) -> void:
	var s: Sim = g.sim
	var cam: Camera3D = g.cam
	shake = maxf(0.0, shake - dt)
	var jitter := Vector3.ZERO
	if not UI.reduced_motion and GraphicsSettings.motion_effects:
		jitter = Vector3(randf() - 0.5, randf() - 0.5, 0) * shake * 1.5
		# Thrust rumble: subtle layered micro-shake scaled by forward speed, punchier on boost.
		var boosting := s.boost > 0.0 and s.phase == "flight"
		if boosting and not _was_boosting:
			_fov_kick = 5.0
		_was_boosting = boosting
		_fov_kick = move_toward(_fov_kick, 0.0, dt * 4.0)
		_rumble_t += dt
		var thrust := clampf(absf(flight_speed) / 185.0, 0.0, 1.0)
		var rumble := thrust * (0.07 + (0.09 if boosting else 0.0))
		if rumble > 0.001 and g.mode != "cine":
			jitter += Vector3(sin(_rumble_t * 47.0) + 0.5 * sin(_rumble_t * 83.0), cos(_rumble_t * 53.0) + 0.5 * sin(_rumble_t * 71.0), 0.0) * rumble
		var target_fov := 70.0
		if s.selected == 0 and s.phase == "flight" and g.mode != "cine":
			if s.boost > 0.0:
				target_fov = 84.0
			elif g.held(KEY_S):
				target_fov = 66.0
			elif g.held(KEY_W):
				target_fov = 78.0
		var base_fov := cam.fov - _applied_kick
		_applied_kick = _fov_kick * smoothstep(0.0, 5.0, _fov_kick)
		cam.fov = lerpf(base_fov, target_fov, 1.0 - exp(-dt * 5.0)) + _applied_kick
	else:
		_fov_kick = 0.0
		_applied_kick = 0.0
		_was_boosting = s.boost > 0.0
		cam.fov = 70.0
	match s.selected:
		2:
			cam.position = _turret_pos() + Vector3(0, 1.5, 0)
			cam.rotation = Vector3(g.pitch, g.yaw, 0)
		3:
			var p := _panel_pos(raid_sel)
			var out := Vector3(signf(p.x - rig.position.x) if absf(p.x - rig.position.x) > 1.0 else 0.0, 0.6, 1.0).normalized()
			cam.position = p + out * 11.0 + jitter
			cam.look_at(p, Vector3.UP)
		1:
			cam.position = rig.position + Vector3(16.0, 8.5, 11.0) + jitter
			cam.look_at(rig.position + Vector3(0, 2.0, 0), Vector3.UP)
		_:
			cam.position = rig.position + Vector3(0, 10, 38) + jitter
			cam.look_at(rig.position + Vector3(0, 2, -40), Vector3.UP)
	if cam_blend < 1.0:
		cam_blend = minf(1.0, cam_blend + dt / 2.2)
		var from_t := Transform3D(cam_from.basis, rig.position + cam_from.origin)
		cam.transform = from_t.interpolate_with(cam.transform, smoothstep(0.0, 1.0, cam_blend))


func on_role_changed() -> void:
	g.yaw = 0.0
	g.pitch = 0.05
	if g.sim.selected == 0:
		g.yaw = _heading.y - _start_heading.y
		g.pitch = _heading.x


## Final glide: the ship slows over the pad and settles on it, in the same universe.
func cine(_kind: String, k: float, dt: float) -> void:
	if is_instance_valid(overlay_layer):
		overlay_layer.visible = false
	space_dust.emitting = false
	space_dust.hide()
	destination_beacon.hide()
	origin_beacon.hide()
	for r in rocks:
		r["node"].visible = false
	for d in drones:
		d["node"].visible = false
	if not cine_started:
		cine_started = true
		cine_from = transform
		cine_rig_from = rig.position
	var e := 1.0 - pow(1.0 - k, 2.0)
	var o := cine_from.origin.lerp(land_pos, e)
	var attitude := cine_from.basis.slerp(Basis(Vector3.UP, yaw_end), e)
	transform = Transform3D(attitude, o)
	rig.position = cine_rig_from.lerp(Vector3.ZERO, e)
	rig.rotation.x = lerpf(rig.rotation.x, 0.0, 1.0 - exp(-dt * 3.0))
	rig.rotation.z = lerpf(rig.rotation.z, 0.0, 1.0 - exp(-dt * 3.0))
	flame.visible = k < 0.9
	_sync_universe()
	g.cam.fov = 70.0
	_applied_kick = 0.0
	_fov_kick = 0.0
	g.cam.position = rig.position + Vector3(26, 7 + 10.0 * (1.0 - k), 30)
	g.cam.look_at(rig.position + Vector3(0, -2, 0), Vector3.UP)


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func hud_update(hud: Hud) -> void:
	var s: Sim = g.sim
	var home: bool = s.flight_leg == "return"
	var left := _distance_m(path_b)
	hud.title.text = "RETURN TRANSFER" if home else "OUTBOUND TRANSFER"
	hud.subtitle.text = "%s · %d m TO %s" % [("RETURN LEG" if home else ("OUTBOUND LEG" if s.route == null else s.route["name"].to_upper())), int(left), "EARTH" if home else "MOON"]
	var r := s.selected
	var tips := ["MOUSE AIM · W THRUST · S BRAKE · A/D STRAFE", "W/S SELECT · LMB SERVICE", "LMB FIRE · Q OVERDRIVE", "W/S PLATE · E REMOVE · LMB REPAIR"]
	hud.objectives.text = "[color=#eaa665]%s[/color]\n%s" % [Sim.SPECIALISTS[r]["role"], tips[r]]
	var col := func(v: float, warn: float, bad: float, invert: bool) -> String:
		if invert:
			return "#ed7d8d" if v > bad else ("#f7ce59" if v > warn else "#f3eef8")
		return "#ed7d8d" if v < bad else ("#f7ce59" if v < warn else "#f3eef8")
	hud.vitals_panel.visible = true
	hud.vitals.text = "[color=#b4a8c6]VESSEL TELEMETRY · KESTREL[/color]\nHULL [color=%s]%d%%[/color]   SHIELD %s\nPOWER [color=%s]%.2f kWh[/color]   REACTOR %d%%\nTEMP [color=%s]%.0f °C[/color]   PRESSURE [color=%s]%.1f kPa[/color]\nCO₂ [color=%s]%d ppm[/color]   CREW FED %d%%\nPROPELLANT %.1f kg · SPARES %d\nFLAGS ON BOARD %d/%d" % [
		col.call(s.hull, 60.0, 30.0, false), int(s.hull), "ON" if s.shield > 0.0 else "—",
		col.call(s.power, 1.5, 0.5, false), s.power, int(s.reactor),
		col.call(s.temperature, 65.0, 85.0, true), s.temperature, col.call(s.pressure, 90.0, 70.0, false), s.pressure,
		col.call(s.co2, 1500.0, 3500.0, true), int(s.co2), int(s.crew_nutrition),
		s.propellant, s.spares, s.flag_counts(0)["onboard"], s.cargo_capacity]
	hud.station_panel.visible = r == 1 or r == 3
	if r == 1:
		var sl := PackedStringArray(["[color=#b4a8c6]ENGINEERING DECK · hold LMB[/color]"])
		for i in 4:
			var sys: String = SYSTEMS[i]
			var flag := ""
			if s.fault != null and FAULT_SYSTEM[s.fault] == sys:
				flag = " [color=#ed7d8d]FAULT[/color]"
			sl.append(("[color=#eaa665]▶ " if i == eng_sel else "   ") + SYSTEM_NAMES[sys] + ("[/color]" if i == eng_sel else "") + flag)
		hud.station.text = "\n".join(sl)
	elif r == 3:
		var pl := PackedStringArray(["[color=#b4a8c6]EVA · HULL PLATES · spares %d[/color]" % s.spares])
		for i in s.panels.size():
			var p = s.panels[i]
			var state := "removed · fit spare %d%%" % int(p["progress"] * 100) if p["removed"] else ("DAMAGED · E remove" if p["health"] < 60.0 else "OK")
			pl.append(("[color=#eaa665]▶ " if i == raid_sel else "   ") + "%s %d%% · %s" % [p["name"], int(p["health"]), state] + ("[/color]" if i == raid_sel else ""))
		hud.station.text = "\n".join(pl)
	hud.crosshair.visible = r == 2
	var prompt := ""
	match r:
		0: prompt = "PILOT · DODGE THE DEBRIS"
		1: prompt = "ENGINEER · " + ("SERVICE " + SYSTEM_NAMES[SYSTEMS[eng_sel]].to_upper())
		2: prompt = "GUNNER · %d DRONES" % drones.size()
		3: prompt = "RAIDER · " + s.panels[raid_sel]["name"].to_upper()
	if _can_return_to_earth():
		hud.set_prompt("E  RETURN TO EARTH PAD", "End this transfer and return to the launch pad.")
	else:
		hud.set_prompt(prompt, tips[r] if r == 0 else "", s.flight_time / s.flight_duration())
	hud.footer.text = "1–4 STATIONS    Q SKILL    F ULTIMATE    M MAP    H HELP"
	var st := ["EVADING", "FAULT!" if s.fault != null else "SYSTEMS OK", "%d DRONES" % drones.size(), "PLATES OK" if s.panels.all(func(p): return p["health"] >= 60.0) else "REPAIRING"]
	for i in 4:
		hud.set_crew_status(i, st[i] + (" · YOU" if i == r else " · BOT"), s.ultimate[i] / 100.0)
	hud.radar_title.text = "DEEP SPACE · %s" % ("RETURN" if home else "OUTBOUND")
	var pts: Array = []
	var ship_center := rig.transform * ship.position
	for k in rocks:
		if k["z"] < 0.0:
			var rel := (Vector3(k["x"], k["y"], k["z"]) - ship_center) / world_units_per_meter
			pts.append({"p": Vector2(rel.x, rel.z), "dist": rel.length(), "c": Color("#9f9cad"), "s": 2.5, "ring": false})
	for d in drones:
		var p: Vector3 = d["node"].position
		var rel := (p - ship_center) / world_units_per_meter
		pts.append({"p": Vector2(rel.x, rel.z), "dist": rel.length(), "c": Color("#ed7d8d"), "s": 4.0, "ring": false})
	for point: Vector3 in [path_a, path_b]:
		var destination := point == path_b
		var rel := transform.basis.inverse() * (point - transform.origin) / world_units_per_meter
		pts.append({"p": Vector2(rel.x, rel.z), "dist": _distance_m(point),
			"c": ACCENT if destination else ORIGIN_COLOR, "s": 5.0, "ring": true,
			"label": "EARTH" if destination == home else "MOON"})
	hud.radar.points = pts
	hud.radar.range_m = 200.0 * s.scan_mult
	hud.radar.request_redraw()
	hud.update_tactical(pts, "LIVE RADAR · " + ("RETURN" if home else "OUTBOUND"), hud.radar.range_m * 1.6)


func _turret_color() -> Color:
	var fam := str(g.sim.loadout.get("engine", "kestrel"))
	match fam:
		"lancer": return Color("#22d3ee")
		"halo": return Color("#a78bfa")
		"bulwark": return Color("#fbbf24")
		"hauler": return Color("#a3e635")
	return Color("#ffd29a")


func _build_stations() -> void:
	var s: Sim = g.sim
	var turret_col := _turret_color()
	turret_rig = Node3D.new()
	turret_rig.name = "TurretRig"
	turret_rig.position = SHIP_OFFSET + s.part_by_id("engine")["slot"] + Vector3(0, 2.0, 0)
	rig.add_child(turret_rig)
	var base := Gfx.cyl(0.95, 0.55, Color("#3b354b"), Vector3.ZERO, 12)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	turret_rig.add_child(base)
	turret_head = Node3D.new()
	turret_head.position = Vector3(0, 0.35, 0)
	turret_rig.add_child(turret_head)
	var cowl := Gfx.box(Vector3(1.1, 0.55, 1.3), turret_col.darkened(0.45), Vector3.ZERO)
	cowl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	turret_head.add_child(cowl)
	for side in [-0.32, 0.32]:
		var barrel := Gfx.cyl(0.11, 2.0, turret_col, Vector3(side, 0.05, -1.1), 8)
		barrel.rotation.x = PI * 0.5
		barrel.material_override = Gfx.mat(turret_col, 0.35, 1.2)
		barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		turret_head.add_child(barrel)

	plate_nodes.clear()
	for i in s.panels.size():
		var off: Vector3 = s.panels[i]["offset"]
		var plate := Gfx.box(Vector3(1.6, 1.0, 2.4), Color("#7f8b9c"), SHIP_OFFSET + Vector3(off.x, Sim.SHIP_Y + off.y - 0.6 * Sim.SHIP_SCALE, off.z))
		plate.name = "HullPlate_%d" % i
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(plate)
		plate_nodes.append(plate)

	system_nodes.clear()
	for sys in SYSTEMS:
		var part = s.part_by_id(sys)
		var pos: Vector3 = (part["slot"] if part != null else Vector3(0, Sim.SHIP_Y, 0)) + SHIP_OFFSET + Vector3(0, 1.1, 0)
		var beacon := Gfx.sphere(0.45, Color("#9cdeb1"), pos, 1.6, 10)
		beacon.name = "SysBeacon_%s" % sys
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(beacon)
		system_nodes[sys] = beacon

	shield_dome = Gfx.sphere(11.5, Color("#38bdf8"), SHIP_OFFSET + Vector3(0, Sim.SHIP_Y, 0), 0.4, 18)
	shield_dome.name = "ShieldDome"
	shield_dome.scale = Vector3(0.95, 0.55, 1.35)
	shield_dome.material_override = Gfx.unshaded(Color("#38bdf8"), 0.14)
	shield_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield_dome.visible = false
	rig.add_child(shield_dome)


func _update_stations(dt: float) -> void:
	var s: Sim = g.sim
	if is_instance_valid(turret_head):
		var local_dir := rig.basis.inverse() * turret_aim_dir
		if local_dir.length() > 0.01:
			var target_yaw := atan2(-local_dir.x, -local_dir.z)
			var flat_len := maxf(0.01, Vector2(local_dir.x, local_dir.z).length())
			var target_pitch := clampf(atan2(local_dir.y, flat_len), -0.5, 0.9)
			turret_head.rotation.y = lerp_angle(turret_head.rotation.y, target_yaw, clampf(dt * 14.0, 0.0, 1.0))
			turret_head.rotation.x = lerpf(turret_head.rotation.x, target_pitch, clampf(dt * 14.0, 0.0, 1.0))
	var pulse := 0.5
	if GraphicsSettings.motion_effects and not UI.reduced_motion:
		pulse += 0.5 * sin(s.flight_time * 7.0)
	for i in plate_nodes.size():
		var plate: MeshInstance3D = plate_nodes[i]
		var p: Dictionary = s.panels[i]
		var active := s.selected == 3 and i == raid_sel
		if p["removed"]:
			plate.material_override = Gfx.unshaded(Color("#38bdf8") if active else Color("#6fe0e6"), 0.25 + 0.2 * p["progress"])
		elif p["health"] < 60.0:
			var warn_col := Color("#ed7d8d").lerp(Color("#f7ce59"), pulse)
			plate.material_override = Gfx.mat(warn_col, 0.5, 1.4 if active else 0.8)
		else:
			plate.material_override = Gfx.mat(Color("#eaa665") if active else Color("#7f8b9c"), 0.6, 0.5 if active else 0.0)
	for i in SYSTEMS.size():
		var sys: String = SYSTEMS[i]
		var beacon: MeshInstance3D = system_nodes.get(sys)
		if beacon == null: continue
		var faulted: bool = s.fault != null and FAULT_SYSTEM[s.fault] == sys
		var active := s.selected == 1 and i == eng_sel
		var col := Color("#ed7d8d") if faulted else (Color("#eaa665") if active else Color("#9cdeb1"))
		beacon.material_override = Gfx.unshaded(col, 0.95 if (faulted or active) else 0.55)
		beacon.scale = Vector3.ONE * (1.35 + 0.25 * pulse if faulted else (1.2 if active else 0.85))
	if is_instance_valid(shield_dome):
		shield_dome.visible = s.shield > 0.0
		if shield_dome.visible:
			shield_dome.material_override = Gfx.unshaded(Color("#38bdf8"), 0.10 + 0.06 * pulse)


class FlightOverlay extends Control:
	var flight: Flight

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if flight == null or not is_instance_valid(flight) or flight.g == null or not flight.is_inside_tree():
			return
		var cam: Camera3D = flight.g.cam
		var s: Sim = flight.g.sim
		if cam == null or not cam.is_inside_tree() or s == null or s.phase != "flight":
			return
		var font := UI.font(true)
		var r := s.selected
		var scan_lim: float = -200.0 * float(s.scan_mult)
		if r == 0:
			var nose := size * 0.5
			var lead_world := flight.to_global(flight.rig.position + Vector3.FORWARD * 95.0)
			if not cam.is_position_behind(lead_world):
				var lead := cam.unproject_position(lead_world)
				draw_line(nose, lead, Color(UI.ACCENT, 0.6), 1.0, true)
				draw_arc(lead, 5.0, 0.0, TAU, 16, UI.ACCENT, 1.5, true)
			draw_line(nose + Vector2(-13, 0), nose + Vector2(-6, 0), UI.TEXT, 1.5, true)
			draw_line(nose + Vector2(6, 0), nose + Vector2(13, 0), UI.TEXT, 1.5, true)
			draw_line(nose + Vector2(0, 4), nose + Vector2(0, 9), UI.TEXT, 1.5, true)
			var speed_text := "%.0f m/s" % flight.flight_speed
			var speed_width := font.get_string_size(speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, nose + Vector2(-speed_width * 0.5, 26), speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TEXT)
			for rock in flight.rocks:
				if rock["z"] >= -12.0 or rock["z"] <= scan_lim: continue
				if absf(rock["x"] - flight.sx) >= rock["r"] + Sim.SHIP_SCALE * 1.15 or absf(rock["y"] - flight.sy) >= rock["r"] + 3.8: continue
				var wp := flight.to_global(Vector3(rock["x"], rock["y"], rock["z"]))
				if cam.is_position_behind(wp): continue
				var sp := cam.unproject_position(wp)
				var col := Color("#ed7d8d") if rock["z"] > -90.0 else Color("#f7ce59")
				draw_rect(Rect2(sp - Vector2(18, 18), Vector2(36, 36)), col, false, 2.0)
				var hint := ("◄ EVADE" if rock["x"] > flight.sx else "EVADE ►") + " %dm" % int(absf(rock["z"]))
				draw_string(font, sp + Vector2(-34, -24), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		elif r == 2:
			var tcol := flight._turret_color()
			for d in flight.drones:
				var n: Node3D = d["node"]
				var wp := flight.to_global(n.position)
				if cam.is_position_behind(wp): continue
				var sp := cam.unproject_position(wp)
				draw_rect(Rect2(sp - Vector2(16, 16), Vector2(32, 32)), Color("#ed7d8d"), false, 1.8)
				var hp_frac := clampf(float(d["hp"]) / 4.0, 0.0, 1.0)
				draw_rect(Rect2(sp + Vector2(-16, -22), Vector2(32.0 * hp_frac, 3)), Color("#ed7d8d"))
				var lead_wp := flight.to_global(n.position + d.get("vel", Vector3.ZERO) * 0.16)
				if not cam.is_position_behind(lead_wp):
					var lsp := cam.unproject_position(lead_wp)
					draw_line(sp, lsp, Color(tcol, 0.55), 1.0)
					draw_arc(lsp, 9.0, 0.0, TAU, 20, tcol, 1.5)
			for rock in flight.rocks:
				if rock["z"] >= -15.0 or rock["z"] <= scan_lim: continue
				if absf(rock["x"] - flight.sx) >= rock["r"] + Sim.SHIP_SCALE * 1.1 or absf(rock["y"] - flight.sy) >= rock["r"] + 3.5: continue
				var wp := flight.to_global(Vector3(rock["x"], rock["y"], rock["z"]))
				if cam.is_position_behind(wp): continue
				var sp := cam.unproject_position(wp)
				draw_rect(Rect2(sp - Vector2(12, 12), Vector2(24, 24)), Color("#f7ce59", 0.75), false, 1.2)
		elif r == 1:
			for i in Flight.SYSTEMS.size():
				var sys: String = Flight.SYSTEMS[i]
				var node: Node3D = flight.system_nodes.get(sys)
				if node == null or not node.is_inside_tree(): continue
				var wp := node.global_position
				if cam.is_position_behind(wp): continue
				var sp := cam.unproject_position(wp)
				var faulted: bool = s.fault != null and Flight.FAULT_SYSTEM[s.fault] == sys
				var active := i == flight.eng_sel
				var col := Color("#ed7d8d") if faulted else (Color("#eaa665") if active else Color("#9cdeb1"))
				draw_arc(sp, 10.0 if active else 7.0, 0.0, TAU, 16, col, 2.0 if active else 1.2)
				draw_string(font, sp + Vector2(14, 4), sys.to_upper() + (" [FAULT]" if faulted else (" ◀" if active else "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		elif r == 3:
			for i in flight.plate_nodes.size():
				var plate: Node3D = flight.plate_nodes[i]
				if not plate.is_inside_tree(): continue
				var wp := plate.global_position
				if cam.is_position_behind(wp): continue
				var sp := cam.unproject_position(wp)
				var p: Dictionary = s.panels[i]
				var active := i == flight.raid_sel
				var col := Color("#38bdf8") if p["removed"] else (Color("#ed7d8d") if p["health"] < 60.0 else (Color("#eaa665") if active else Color("#f3eef8")))
				draw_arc(sp, 11.0 if active else 7.0, 0.0, TAU, 16, col, 2.0 if active else 1.2)
				var tag := "%s %d%%" % [p["id"].to_upper(), int(p["health"])] if not p["removed"] else "%s %d%%" % [p["id"].to_upper(), int(p["progress"] * 100.0)]
				draw_string(font, sp + Vector2(14, 4), tag + (" ◀" if active else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

		var home := s.flight_leg == "return"
		_draw_waypoint(cam, font, flight.path_b, "DESTINATION: EARTH" if home else "DESTINATION: MOON", Flight.ACCENT)
		_draw_waypoint(cam, font, flight.path_a, "MOON PAD" if home else "EARTH PAD", Flight.ORIGIN_COLOR)

	func _draw_waypoint(cam: Camera3D, font: Font, point: Vector3, label: String, color: Color) -> void:
		var world: Vector3 = flight.g.universe.to_global(point)
		var center := size * 0.5
		var margin := Vector2(24, 34)
		var bounds := Rect2(margin, size - margin * 2.0)
		var behind := cam.is_position_behind(world)
		var screen := center
		if not behind:
			screen = cam.unproject_position(world)
		if behind or not bounds.has_point(screen):
			var view := cam.to_local(world)
			var direction := Vector2(view.x, -view.y)
			if direction.length_squared() < 0.0001:
				direction = Vector2.DOWN
			direction = direction.normalized()
			var extent := center - margin
			var edge := maxf(absf(direction.x) / maxf(extent.x, 1.0), absf(direction.y) / maxf(extent.y, 1.0))
			screen = center + direction / edge
			var side := direction.orthogonal() * 6.0
			draw_colored_polygon(PackedVector2Array([
				screen + direction * 8.0, screen - direction * 6.0 + side, screen - direction * 6.0 - side,
			]), color)
		else:
			draw_arc(screen, 8.0, 0.0, TAU, 24, color, 2.0, true)
		var caption := "%s · %d m" % [label, roundi(flight._distance_m(point))]
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var text_pos := Vector2(clampf(screen.x - width * 0.5, 4.0, maxf(4.0, size.x - width - 4.0)),
			screen.y + (24.0 if label.begins_with("DESTINATION") else -14.0))
		draw_string_outline(font, text_pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, UI.BG_DEEP)
		draw_string(font, text_pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
