## Walkable spacecraft interior: a real, fully enclosed multi-crew bridge & operations deck built in ShipInterior's local
## frame INSIDE the spacecraft model (no separate room, no sky offset). Forward is -Z toward the nose.
##   Cabin envelope: 9.2 m wide (x -4.6..4.6), 4.6 m tall (y 0..4.6), 24 m long (z -18.0 nose glass .. +6.0 aft bulkhead).
##   The node stays 1:1 (scale ONE) even though the vessel root is VESSEL_SCALE larger.
##   Facilities (all real furniture + glowing computers): pilot flight bridge (seats, yoke, HOTAS, 5-screen avionics),
##   gunnery fire-control deck, reactor + engineer diagnostics, life support bay, hull workshop, science lab with
##   holo-table and flag rack, aft engine bay with twin plasma manifolds and propulsion console.
##   Windows: panoramic forward canopy (3 angled panes) + side viewports (outside is the live world).
## [I] or [Tab] opens the cabin in the legacy flag modes. Crew can service the ship while it flies.
## Actors are children of this node (interior-local). sync_to_ship() locks this node to the live vessel and tick()
## places the camera through global_transform.
extends Node3D

const Hardware = preload("res://scripts/industrial_hardware.gd")
const CABIN_W := 9.2
const CABIN_H := 4.6
const Z_NOSE := -18.0
const Z_AFT := 6.0
const CABIN_LENGTH := 24.0
const HALF_W := 4.6
const WALK_X := 3.0
const ALCOVE_X := 4.4
const CAM_X := 4.35
const CAM_Y_MIN := 0.35
const CAM_Y_MAX := 4.25
const CAM_Z_MIN := -17.4
const CAM_Z_MAX := 5.6
const WIN_BOTTOM := 1.0
const WIN_TOP := 3.3
const ROOM_Z := {"engine_bay": 3.4, "power_room": -0.6, "life_support": -0.6, "workshop": -5.8, "lab": -10.6,
	"gunnery": -10.6, "cockpit": -14.4}
const ROOM_NAMES := {"engine_bay": "ENGINE BAY", "power_room": "POWER ROOM", "life_support": "LIFE SUPPORT",
	"workshop": "WORKSHOP", "lab": "LAB", "cockpit": "COCKPIT", "gunnery": "GUNNERY", "airlock": "AIRLOCK"}
const STATION_POS := {
	"cockpit": Vector3(0, 0, -14.4), "lab": Vector3(-2.7, 0, -10.6), "gunnery": Vector3(2.7, 0, -10.6),
	"workshop": Vector3(2.7, 0, -5.8), "power_room": Vector3(-2.7, 0, -0.6), "life_support": Vector3(2.7, 0, -0.6),
	"engine_bay": Vector3(0, 0, 3.4),
}
const AIRLOCK_POS := Vector3(-4.2, 0, -5.8)
const DOOR_POS := Vector3(-2.8, 0, -5.8)
const COCKPIT_SPAWN := Vector3(0, 0, -12.4)
const BOT_HOME := ["cockpit", "power_room", "gunnery", "workshop"]   # favourite station per crew index
const INTERACT_RANGE := 2.3
const CABIN_OFFSET := Vector3(0, 1.2, 0)   # cabin floor offset inside the vessel's local frame
# Room tasks (flight only). seconds = time at the station; cooldown = before the station can be used again.
const TASKS := {
	"engine_bay": {"label": "TUNE THRUSTERS", "detail": "Temporary cruise speed boost", "seconds": 3.0, "cooldown": 35.0},
	"power_room": {"label": "BOOST REACTOR", "detail": "Restore power margin", "seconds": 2.5, "cooldown": 25.0},
	"life_support": {"label": "SCRUB CO2 · COOL CABIN", "detail": "Clear CO2 and drop cabin temperature", "seconds": 2.5, "cooldown": 25.0},
	"workshop": {"label": "PATCH HULL", "detail": "Repair damaged plates, +hull +shield", "seconds": 3.5, "cooldown": 30.0},
	"lab": {"label": "DEEP-SPACE SENSOR SWEEP", "detail": "Overcharge shields", "seconds": 3.0, "cooldown": 40.0},

}
const READY := Color("#9cdeb1")
const BUSY := Color("#eaa665")
const IDLE := Color("#6c7a86")
const GUN := Color("#262b32")
const GUN_LIGHT := Color("#3b434d")
const CYAN := Color("#59d8e8")
const WARM := Color("#ffb768")

var g
var is_open := false
var player_idx := -1
var crew: Array = []              # one Actor per crew index; the selected one is the player
var spawned := [false, false, false, false]
var bots: Array = [{}, {}, {}, {}]
var stations := {}                # room -> {"node","ring","label","cd"}
var task := {}
var entry_yaw := 0.0
var entry_pitch := -0.1
var _t := 0.0
var _saved_footer := ""
var _vessel: Node3D
var _cutaway_vessel: Node3D
## Boarded on foot through the belly ramp: crew appear in the airlock and walk in one after another.
var _airlock_entry := false
var _entry_delay := [0.0, 0.0, 0.0, 0.0]
var _entry_order := 0


func setup(main) -> void:
	g = main
	name = "ShipInterior"
	_build_cabin()
	_build_stations()
	for i in 4:
		var sp = Sim.SPECIALISTS[i]
		var a := Actor.new()
		a.setup(sp["model"], i, Sim.role_color(i), sp["name"], Sim.role_color(i))
		a.visible = false
		add_child(a)
		crew.append(a)
	visible = false


func _exit_tree() -> void:
	_restore_cutaway()


# ---------------------------------------------------------------------------
# Spacecraft binding
# ---------------------------------------------------------------------------
func set_cutaway_target(vessel: Node3D) -> void:
	if _cutaway_vessel != null and _cutaway_vessel != vessel:
		_restore_cutaway()
	_vessel = vessel
	if vessel != null and is_instance_valid(vessel):
		_cutaway_vessel = vessel
		ShipModel.set_interior_cutaway(vessel, true)


func _restore_cutaway() -> void:
	if _cutaway_vessel != null and is_instance_valid(_cutaway_vessel):
		ShipModel.set_interior_cutaway(_cutaway_vessel, false)
	_cutaway_vessel = null


## Locks the cabin to the spacecraft, including steep flight attitudes.
func sync_to_ship(vessel: Node3D) -> void:
	if vessel != null and is_instance_valid(vessel):
		_vessel = vessel
	vessel = _vessel
	if vessel == null or not is_instance_valid(vessel) or not vessel.is_inside_tree():
		return
	var xf := vessel.global_transform
	if absf((-xf.basis.z).normalized().y) > 0.7:
		# At steep attitudes, keep the deck level and centred inside the hull.
		var yaw := Basis(Vector3.UP, xf.basis.get_euler().y)
		var box := _world_bounds(vessel)
		var centre := box.get_center() if box.size.length() > 0.1 else xf.origin
		global_transform = Transform3D(yaw.orthonormalized(), centre - Vector3(0, CABIN_H * 0.5, 0))
	else:
		# Orthonormalized basis: interior stays true 1:1 human scale inside a VESSEL_SCALE-larger hull; the floor
		# offset still follows the hull scale so the deck sits at the right height.
		global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin + xf.basis * CABIN_OFFSET)
	scale = Vector3.ONE


func _world_bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).visible:
			var mi := n as MeshInstance3D
			var b := mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		stack.append_array(n.get_children())
	return box


## Player's actor (Main.player_actor() uses this while the interior is open).
func actor(_i: int) -> Variant:
	return crew[g.sim.selected] if crew.size() == 4 else null


func open(via_airlock := false) -> void:
	_airlock_entry = via_airlock
	is_open = true
	visible = true
	_saved_footer = g.hud.footer.text
	_sync_origin()
	g.first_person = true
	var p: int = g.sim.selected
	if not spawned[p]:
		_spawn(p, true)
	entry_yaw = g.yaw
	if crew[p].position.distance_to(COCKPIT_SPAWN) < 0.5:
		g.yaw = PI          # leaving the pilot seat: face aft through the ship
	g.pitch = -0.08
	player_idx = p
	_apply_player_view()


func close() -> void:
	is_open = false
	visible = false
	task = {}
	_restore_cutaway()
	g.hud.footer.text = _saved_footer
	g.hud.set_prompt("")


func _spawn(i: int, as_player: bool) -> void:
	var a: Actor = crew[i]
	spawned[i] = true
	a.visible = true
	a.heading = 0.0
	if _airlock_entry:
		# Stepping in through the side hatch: face into the ship from the airlock alcove.
		a.heading = -PI * 0.5
		if as_player:
			a.position = AIRLOCK_POS + Vector3(0.3, 0, 0)
		else:
			_entry_order += 1
			a.position = AIRLOCK_POS + Vector3(-0.1, 0, (i % 2 - 0.5) * 0.5)
			bots[i] = {"room": BOT_HOME[i], "arrived": false, "t": 0.0}
			_entry_delay[i] = 0.6 + _entry_order * 0.85
	elif as_player:
		a.position = COCKPIT_SPAWN
	else:
		var st: String = BOT_HOME[i]
		a.position = _stand_point(st, i)
		bots[i] = {"room": st, "arrived": true, "t": randf_range(3.0, 9.0)}
	a.rotation.y = a.heading


func _sync_origin() -> void:
	if _vessel == null or not is_instance_valid(_vessel):
		return
	sync_to_ship(_vessel)
	if _cutaway_vessel != _vessel:
		set_cutaway_target(_vessel)


func _apply_player_view() -> void:
	# Name tags only for the bots; the player's own tag is hidden.
	for i in 4:
		var tag = crew[i].name_tag
		if tag:
			tag.visible = i != g.sim.selected


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
func collide(p: Vector3) -> Vector3:
	if absf(p.z - AIRLOCK_POS.z) < 0.9 and p.x < -WALK_X:
		p.x = maxf(p.x, -ALCOVE_X)      # side hatch alcove
	else:
		p.x = clampf(p.x, -WALK_X, WALK_X)
	p.z = clampf(p.z, Z_NOSE + 2.4, Z_AFT - 2.0)
	return p


func room_at(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for room in STATION_POS:
		var d: float = Vector2(p.x - STATION_POS[room].x, p.z - STATION_POS[room].z).length()
		if d < bd:
			bd = d
			best = room
	if Vector2(p.x - AIRLOCK_POS.x, p.z - AIRLOCK_POS.z).length() < bd:
		best = "airlock"
	return best


func _stand_point(room: String, i: int) -> Vector3:
	var p: Vector3 = STATION_POS[room]
	var side := -1.0 if p.x > 0.5 else 1.0
	if absf(p.x) < 0.5:
		return p + Vector3((i - 1.5) * 0.6, 0, 0.9)
	return p + Vector3(side * 0.8, 0, (i - 1.5) * 0.45)


func tick(dt: float) -> void:
	if not is_open or crew.size() != 4:
		return
	_t += dt
	_sync_origin()
	var s: Sim = g.sim
	if s.selected != player_idx:
		# 1-4 switched role while aboard: the previous player becomes a bot at their spot.
		if player_idx >= 0:
			bots[player_idx] = {"room": room_at(crew[player_idx].position), "arrived": true, "t": 4.0}
		player_idx = s.selected
		if not spawned[player_idx]:
			_spawn(player_idx, true)
		bots[player_idx] = {}
		task = {}
		_apply_player_view()
	for i in 4:
		var a: Actor = crew[i]
		if i == player_idx:
			continue
		if not spawned[i]:
			_spawn(i, false)
		if _entry_delay[i] > 0.0:
			# Still climbing the ramp behind the player.
			_entry_delay[i] -= dt
			a.visible = false
			continue
		a.visible = true
		_bot(i, a, dt)
	var player: Actor = crew[player_idx]
	player.visible = true
	for room in stations:
		stations[room]["cd"] = maxf(0.0, stations[room]["cd"] - dt)
	var sp: float = g.drive(player, dt, 22.0, 0.8)
	player.position = collide(player.position)
	player.animate(dt, sp)
	g.follow_cam(player, 3.4)
	var shake := Vector3.ZERO
	if not UI.reduced_motion:
		# Quiet engine rumble: a hair of high-frequency shudder plus a slow sway.
		shake = Vector3(sin(_t * 41.0) * 0.0035 + sin(_t * 1.3) * 0.004, sin(_t * 33.0 + 1.0) * 0.003, 0)
	var local_cam: Vector3 = g.cam.position + shake
	# Keep the camera strictly inside the enclosed cabin: it can never poke through roof, floor or walls.
	local_cam = Vector3(clampf(local_cam.x, -CAM_X, CAM_X), clampf(local_cam.y, CAM_Y_MIN, CAM_Y_MAX),
		clampf(local_cam.z, CAM_Z_MIN, CAM_Z_MAX))
	g.cam.global_transform = global_transform * Transform3D(Basis.from_euler(g.cam.rotation), local_cam)
	_interact(dt, player)
	_station_visuals()


func _bot(i: int, a: Actor, dt: float) -> void:
	var b: Dictionary = bots[i]
	if b.is_empty():
		var h: String = BOT_HOME[i]
		b = {"room": h, "arrived": false, "t": 0.0}
		bots[i] = b
	var target := _stand_point(b["room"], i)
	if a.position.x < -WALK_X - 0.05 and target.x > -WALK_X:
		target = DOOR_POS   # leave the airlock through the door before heading down the corridor
	var d := a.walk_to(target, dt, 3.4, 0.3)
	if d > 0.5:
		a.animate(dt, 3.4, "", false)
		return
	if not b["arrived"]:
		b["arrived"] = true
		b["t"] = randf_range(7.0, 14.0)
	a.face(STATION_POS[b["room"]] - a.position, dt)
	a.animate(dt, 0.0, "work", false)
	b["t"] -= dt
	if b["t"] <= 0.0 and a.position.x > -WALK_X - 0.05:
		var rooms: Array = STATION_POS.keys()
		var pick: String = rooms[randi() % rooms.size()]
		if pick == b["room"]:
			pick = BOT_HOME[i]
		b["room"] = pick
		b["arrived"] = false


# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------
func _near_station(p: Vector3) -> String:
	var best := ""
	var bd := INTERACT_RANGE
	for room in STATION_POS:
		var d: float = g.flat_dist(p, STATION_POS[room])
		if d < bd:
			bd = d
			best = room
	return best


func _interact(dt: float, player: Actor) -> void:
	var s: Sim = g.sim
	if g.mode != "play":
		return
	var room := room_at(player.position)
	var near := _near_station(player.position)
	if not task.is_empty():
		if near != task["room"]:
			g.hud.toast("%s interrupted: stay at the station until it finishes." % TASKS[task["room"]]["label"].capitalize(), 2.2)
			task = {}
		else:
			task["t"] += dt
			var def: Dictionary = TASKS[task["room"]]
			g.hud.set_prompt(def["label"], "In progress · %d s" % ceili(def["seconds"] - task["t"]), task["t"] / def["seconds"])
			if task["t"] >= def["seconds"]:
				_complete(task["room"])
				task = {}
			return
	if not g.piloting:
		g.hud.set_prompt("SYSTEMS OFFLINE", "The flight is over")
		return
	var parked := parked_on_surface()
	if parked and near == "" and room == "airlock":
		g.hud.set_prompt("E · EXIT SHIP", "Step out of the airlock and down the boarding ramp")
		if g.pressed(KEY_E):
			g.exit_ship_on_foot()
		return
	if parked and near == "cockpit":
		g.hud.set_prompt("E · TAKE PILOT SEAT", "Strap in and take the controls")
		if g.pressed(KEY_E):
			g.exit_interior()
		return
	if parked and near == "":
		g.hud.set_prompt(ROOM_NAMES.get(room, ""), "Walk forward to the cockpit to take the pilot seat")
		return
	if near == "":
		g.hud.set_prompt(ROOM_NAMES.get(room, ""), "Walk to a glowing station ring · [I] / TAB exterior flight view")
		return
	if near == "cockpit":
		g.hud.set_prompt("E · RETURN TO PILOT VIEW", "Back to the exterior flight view · or press [I]")
		if g.pressed(KEY_E):
			g.exit_interior()
		return
	if not TASKS.has(near):
		g.hud.set_prompt(ROOM_NAMES[near])
		return
	var d: Dictionary = TASKS[near]
	var cd: float = stations[near]["cd"]
	if cd > 0.0:
		g.hud.set_prompt(d["label"], "Recharging · %d s" % ceili(cd))
		return
	g.hud.set_prompt("E · " + d["label"], d["detail"])
	if g.pressed(KEY_E):
		task = {"room": near, "t": 0.0}
		g.sfx("capture_tick", -6)


func _complete(room: String) -> void:
	var s: Sim = g.sim
	var cd: float = TASKS[room]["cooldown"]
	stations[room]["cd"] = cd
	var msg := ""
	match room:
		"engine_bay":
			s.boost = maxf(s.boost, 8.0)
			msg = "Thrusters tuned: cruise speed boosted for 8 s."
		"power_room":
			s.reactor = minf(100.0, s.reactor + 12.0)
			s.power = minf(s.power_capacity, s.power + s.power_capacity * 0.4)
			if s.fault == "reactor" or s.fault == "power":
				s.fault = null
			msg = "Reactor boosted: power margin restored."
		"life_support":
			s.co2 = maxf(300.0, s.co2 - 900.0)
			s.temperature = maxf(15.0, s.temperature - 18.0)
			if s.fault == "scrubber" or s.fault == "cooling":
				s.fault = null
			msg = "CO2 scrubbed and cabin cooled."
		"workshop":
			s.hull = minf(100.0, s.hull + 20.0)
			for p in s.panels:
				p["health"] = minf(100.0, p["health"] + 35.0)
			Flight.ship_shield = minf(Flight.SHIELD_MAX, Flight.ship_shield + 20.0)
			msg = "Hull plates patched: +20 hull, +20 shield."
		"lab":
			Flight.ship_shield = Flight.SHIELD_MAX
			s.shield = maxf(s.shield, 6.0)
			s.scan_boost = maxf(s.scan_boost, 7.0)
			msg = "Sensor sweep complete: shields overcharged."
	g.sfx("reload_click", -4)
	g.hud.toast(msg, 3.0)


func _station_visuals() -> void:
	for room in stations:
		var st: Dictionary = stations[room]
		var ring: MeshInstance3D = st["ring"]
		var label: Label3D = st["label"]
		var col := IDLE
		var text: String = ROOM_NAMES[room]
		var lit := false
		if room == "cockpit":
			lit = true
			col = READY
			text = "COCKPIT\n[E] PILOT SEAT" if parked_on_surface() else "COCKPIT\n[E] PILOT VIEW"
		elif TASKS.has(room):
			var cd: float = st["cd"]
			lit = true
			if not task.is_empty() and task["room"] == room:
				col = BUSY
				text += "\nWORKING…"
			elif cd > 0.0:
				col = IDLE
				text += "\nRECHARGING %d s" % ceili(cd)
			else:
				col = READY
				text += "\n[E] " + String(TASKS[room]["label"])
		ring.visible = lit
		label.text = text
		label.modulate = col
		ring.scale = Vector3.ONE * (1.0 + 0.1 * sin(_t * 4.0)) * Vector3(1, 0.05, 1)
		if ring.material_override is BaseMaterial3D:
			(ring.material_override as BaseMaterial3D).albedo_color = col


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func hud_update(hud: Hud) -> void:
	hud.crosshair.visible = false
	var player: Actor = crew[player_idx] if player_idx >= 0 else null
	var where: String = ROOM_NAMES.get(room_at(player.position), "") if player != null else ""
	hud.subtitle.text = "SPACECRAFT INTERIOR · %s" % where
	if parked_on_surface():
		hud.footer.text = "WASD MOVE · COCKPIT: E PILOT SEAT · AIRLOCK: E EXIT SHIP · ESC MENU"
	else:
		hud.footer.text = "WASD MOVE · E OPERATE · [I] / TAB PILOT VIEW · ESC MENU"


## True while the ship sits on a planet surface (boarded on foot, before takeoff).
func parked_on_surface() -> bool:
	return g.piloting and is_instance_valid(g.vessel) and g.vessel.grounded and not g.sim.in_space()


# ---------------------------------------------------------------------------
# Cabin construction (all local to this node; floor y = 0, forward = -Z)
# ---------------------------------------------------------------------------
func _hull_mat(color: Color, metal := 0.7, rough := 0.4) -> Material:
	return Hardware.material(color, metal, rough)


func _slab(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := Gfx.mesh(bm, mat, pos)
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, top := -1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top < 0.0 else top
	cm.height = height
	cm.radial_segments = 20
	cm.rings = 1
	var mi := Gfx.mesh(cm, mat, pos)
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 28
	tm.ring_segments = 8
	var mi := Gfx.mesh(tm, mat, pos)
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	var mi := Gfx.mesh(sm, mat, pos)
	parent.add_child(mi)
	return mi


func _group(parent: Node3D, group_name: String, pos := Vector3.ZERO, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	return n


func _glow(color: Color, energy := 2.2) -> Material:
	return Gfx.mat(color, 0.4, energy)


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.85, 0.95, 0.10)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic = 0.1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m


## Wall along one side with viewport / hatch openings. side = -1 port / +1 starboard; openings are [z0, z1, "window"|"hatch"].
func _side_wall(root: Node3D, side: float, openings: Array) -> void:
	var wall := _hull_mat(GUN_LIGHT, 0.75, 0.38)
	var frame := _hull_mat(GUN, 0.8, 0.3)
	var x := side * (HALF_W + 0.06)
	var glass := _glass()
	var prev := Z_NOSE + 1.6
	var ops := openings.duplicate()
	ops.sort_custom(func(a, b): return a[0] < b[0])
	for w in ops:
		if w[0] - prev > 0.05:
			_slab(root, Vector3(0.12, CABIN_H, w[0] - prev), Vector3(x, CABIN_H * 0.5, (prev + w[0]) * 0.5), wall)
		prev = w[1]
		var mid: float = (w[0] + w[1]) * 0.5
		var len: float = w[1] - w[0]
		if w[2] == "hatch":
			_slab(root, Vector3(0.12, CABIN_H - 3.1, len), Vector3(x, (3.1 + CABIN_H) * 0.5, mid), wall)
			continue
		_slab(root, Vector3(0.12, WIN_BOTTOM, len), Vector3(x, WIN_BOTTOM * 0.5, mid), wall)
		_slab(root, Vector3(0.12, CABIN_H - WIN_TOP, len), Vector3(x, (WIN_TOP + CABIN_H) * 0.5, mid), wall)
		_slab(root, Vector3(0.05, WIN_TOP - WIN_BOTTOM, len), Vector3(x, (WIN_BOTTOM + WIN_TOP) * 0.5, mid), glass)
		_slab(root, Vector3(0.16, 0.07, len + 0.12), Vector3(x, WIN_BOTTOM + 0.03, mid), frame)
		_slab(root, Vector3(0.16, 0.07, len + 0.12), Vector3(x, WIN_TOP - 0.03, mid), frame)
		for zz in [w[0] - 0.03, w[1] + 0.03]:
			_slab(root, Vector3(0.16, WIN_TOP - WIN_BOTTOM, 0.07), Vector3(x, (WIN_BOTTOM + WIN_TOP) * 0.5, zz), frame)
		_slab(root, Vector3(0.03, 0.03, len), Vector3(x - side * 0.08, WIN_BOTTOM - 0.05, mid), _glow(CYAN, 1.8))
	if Z_AFT - prev > 0.05:
		_slab(root, Vector3(0.12, CABIN_H, Z_AFT - prev), Vector3(x, CABIN_H * 0.5, (prev + Z_AFT) * 0.5), wall)


func _build_cabin() -> void:
	var root := Node3D.new()
	root.name = "Cabin"
	add_child(root)
	var len := Z_AFT - Z_NOSE
	var cz := (Z_NOSE + Z_AFT) * 0.5
	var deck := _hull_mat(GUN, 0.8, 0.45)
	var hull := _hull_mat(GUN_LIGHT, 0.75, 0.38)
	# Floor deck + grating bars, glowing guide strips and a painted walkway centre line.
	_slab(root, Vector3(CABIN_W + 0.3, 0.2, len + 0.4), Vector3(0, -0.1, cz), deck)
	var grate := _hull_mat(Color("#161a1f"), 0.9, 0.5)
	var zz := Z_NOSE + 0.8
	while zz < Z_AFT:
		_slab(root, Vector3(CABIN_W - 0.3, 0.025, 0.07), Vector3(0, 0.012, zz), grate)
		zz += 0.45
	for sx in [-1.15, 1.15]:
		_slab(root, Vector3(0.07, 0.02, len - 3.4), Vector3(sx, 0.022, cz + 0.4), _glow(CYAN, 1.6))
	var stripe := _glow(Color("#f2c230"), 0.9)
	zz = Z_NOSE + 3.0
	while zz < Z_AFT - 2.4:
		_slab(root, Vector3(0.12, 0.02, 0.9), Vector3(0, 0.024, zz), stripe)
		zz += 1.8
	# Ceiling with structural beams, lighting channels and warm / cyan strip lighting.
	_slab(root, Vector3(CABIN_W + 0.3, 0.2, len + 0.4), Vector3(0, CABIN_H + 0.1, cz), deck)
	var rib := Z_NOSE + 1.6
	while rib < Z_AFT:
		_slab(root, Vector3(CABIN_W, 0.2, 0.16), Vector3(0, CABIN_H - 0.1, rib), hull)
		for sx in [-1.0, 1.0]:
			_slab(root, Vector3(0.18, 0.8, 0.16), Vector3(sx * (HALF_W - 0.09), CABIN_H - 0.5, rib), hull)
		rib += 2.4
	for sx in [-2.3, 2.3]:
		_slab(root, Vector3(0.26, 0.28, len - 2.8), Vector3(sx, CABIN_H - 0.14, cz + 0.4), hull)
	for sx in [-1.5, 1.5]:
		_slab(root, Vector3(0.14, 0.04, len - 3.2), Vector3(sx, CABIN_H - 0.30, cz + 0.4), _glow(WARM, 2.4))
	_slab(root, Vector3(0.08, 0.03, len - 3.2), Vector3(0, CABIN_H - 0.30, cz + 0.4), _glow(CYAN, 2.0))
	for lz in [-14.6, -10.6, -5.8, -0.6, 3.4]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, CABIN_H - 0.6, lz)
		lamp.light_color = Color("#d9ecff") if lz < -4.0 else Color("#ffd9a8")
		lamp.light_energy = 1.2
		lamp.omni_range = 9.5
		lamp.shadow_enabled = false
		root.add_child(lamp)
	# Side walls: port (lab, hatch, power) / starboard (gunnery, workshop, life support) viewports.
	_side_wall(root, -1.0, [[-14.6, -12.4, "window"], [-9.2, -7.8, "window"], [-6.8, -4.8, "hatch"], [2.2, 4.4, "window"]])
	_side_wall(root, 1.0, [[-14.6, -12.4, "window"], [-8.6, -7.2, "window"], [-3.4, -2.4, "window"], [2.2, 4.4, "window"]])
	# Side hatch (airlock doorway) on the port wall, flush with the boarding gantry.
	var door := _hull_mat(GUN, 0.85, 0.35)
	_slab(root, Vector3(0.2, 3.1, 0.14), Vector3(-HALF_W - 0.02, 1.55, -6.88), door)
	_slab(root, Vector3(0.2, 3.1, 0.14), Vector3(-HALF_W - 0.02, 1.55, -4.72), door)
	_slab(root, Vector3(0.2, 0.14, 2.3), Vector3(-HALF_W - 0.02, 3.1, -5.8), door)
	_slab(root, Vector3(0.05, 0.05, 2.0), Vector3(-HALF_W + 0.04, 3.02, -5.8), _glow(BUSY, 2.5))
	_slab(root, Vector3(1.2, 0.03, 2.0), Vector3(-HALF_W + 0.6, 0.02, -5.8), _glow(BUSY, 0.9))
	var air := Gfx.label("AIRLOCK", BUSY, 26, 4)
	air.pixel_size = 0.007
	air.position = Vector3(-HALF_W + 0.35, 3.55, -5.8)
	air.rotation.y = PI * 0.5
	root.add_child(air)
	# Aft bulkhead with status lights.
	_slab(root, Vector3(CABIN_W + 0.3, CABIN_H, 0.2), Vector3(0, CABIN_H * 0.5, Z_AFT + 0.1), hull)
	for lx in [-3.6, -1.2, 1.2, 3.6]:
		_slab(root, Vector3(1.6, 0.07, 0.04), Vector3(lx, 3.6, Z_AFT - 0.02), _glow(CYAN if lx < 0.0 else WARM, 1.8))
	# Nose: angled armoured chamfers + the panoramic canopy (centre pane + two raked side panes).
	var frame := _hull_mat(GUN, 0.85, 0.3)
	var dx := 1.5
	var dz := 2.2
	var ang := atan2(dz, dx)
	var plen := sqrt(dx * dx + dz * dz)
	for side in [-1.0, 1.0]:
		var cx: float = side * (HALF_W - dx * 0.5)
		var cz2: float = Z_NOSE + dz * 0.5
		_slab(root, Vector3(plen, 1.0, 0.12), Vector3(cx, 0.5, cz2), hull, Vector3(0, -side * ang, 0))
		_slab(root, Vector3(plen, 2.3, 0.04), Vector3(cx, 2.15, cz2), _glass(), Vector3(0, -side * ang, 0))
		_slab(root, Vector3(plen, 0.14, 0.16), Vector3(cx, 3.35, cz2), frame, Vector3(0, -side * ang, 0))
		_slab(root, Vector3(plen, 0.14, 0.16), Vector3(cx, 1.0, cz2), frame, Vector3(0, -side * ang, 0))
		_slab(root, Vector3(plen, CABIN_H - 3.4, 0.14), Vector3(cx, (3.4 + CABIN_H) * 0.5, cz2), hull, Vector3(0, -side * ang, 0))
	var cx0 := Z_NOSE
	var cw := CABIN_W - dx * 2.0
	_slab(root, Vector3(cw, 2.3, 0.04), Vector3(0, 2.15, cx0 + 0.02), _glass(), Vector3(0.18, 0, 0))
	_slab(root, Vector3(cw + 0.1, 1.0, 0.14), Vector3(0, 0.5, cx0 - 0.02), hull)
	_slab(root, Vector3(cw + 0.1, CABIN_H - 3.4, 0.7), Vector3(0, (3.4 + CABIN_H) * 0.5, cx0 + 0.3), frame)
	for fx in [-cw * 0.5, -cw * 0.25, 0.0, cw * 0.25, cw * 0.5]:
		_slab(root, Vector3(0.09, 2.3, 0.11), Vector3(fx, 2.15, cx0 + 0.02), frame, Vector3(0.18, 0, 0))
	_slab(root, Vector3(cw, 0.07, 0.12), Vector3(0, 1.0, cx0 + 0.04), frame)
	_slab(root, Vector3(cw, 0.07, 0.12), Vector3(0, 3.35, cx0 + 0.04), frame)
	_build_facilities(root)


# ---------------------------------------------------------------------------
# Crew facilities: every role gets recognisable furniture and glowing computer screens.
# ---------------------------------------------------------------------------
func _build_facilities(root: Node3D) -> void:
	var f := Node3D.new()
	f.name = "Facilities"
	root.add_child(f)
	_build_pilot_bridge(f)
	_build_gunnery(f)
	_build_reactor_bay(f)
	_build_life_support(f)
	_build_workshop(f)
	_build_lab(f)
	_build_engine_bay(f)


## Seat group facing -Z. kind: "captain" | "copilot" | "gunner" (armoured, red trim).
func _build_seat(parent: Node3D, seat_name: String, pos: Vector3, kind: String, yaw := 0.0) -> Node3D:
	var g_ := _group(parent, seat_name, pos, yaw)
	var leather := _hull_mat(Color("#1a1d22") if kind != "gunner" else Color("#23201f"), 0.3, 0.62)
	var metal := _hull_mat(GUN_LIGHT, 0.85, 0.3)
	var trim := _glow(Color("#ffb768") if kind == "captain" else (Color("#ff5a4a") if kind == "gunner" else CYAN), 1.4)
	_cyl(g_, 0.34, 0.06, Vector3(0, 0.03, 0), metal)                       # floor plate
	_cyl(g_, 0.07, 0.34, Vector3(0, 0.23, 0), metal)                       # swivel column
	for k in 5:                                                            # star base
		var a := TAU * k / 5.0
		_slab(g_, Vector3(0.36, 0.05, 0.06), Vector3(cos(a) * 0.18, 0.1, sin(a) * 0.18), metal, Vector3(0, -a, 0))
	_slab(g_, Vector3(0.64, 0.12, 0.64), Vector3(0, 0.46, 0), metal)       # seat pan
	_slab(g_, Vector3(0.58, 0.12, 0.58), Vector3(0, 0.57, 0), leather)     # cushion
	var back_h := 1.15 if kind == "captain" else 0.95
	_slab(g_, Vector3(0.6, back_h, 0.14), Vector3(0, 0.62 + back_h * 0.5, 0.31), leather, Vector3(0.12, 0, 0))
	for sx in [-1.0, 1.0]:                                                  # side bolsters + armrests
		_slab(g_, Vector3(0.1, back_h * 0.7, 0.24), Vector3(sx * 0.33, 0.9, 0.24), leather, Vector3(0.12, 0, sx * 0.1))
		_slab(g_, Vector3(0.09, 0.06, 0.52), Vector3(sx * 0.42, 0.86, -0.04), leather)
		_slab(g_, Vector3(0.05, 0.28, 0.05), Vector3(sx * 0.42, 0.7, 0.1), metal)
		_slab(g_, Vector3(0.025, 0.02, 0.3), Vector3(sx * 0.42, 0.9, -0.04), trim)
	_slab(g_, Vector3(0.36, 0.26, 0.12), Vector3(0, 0.62 + back_h + 0.1, 0.36), leather, Vector3(0.12, 0, 0))   # headrest
	_slab(g_, Vector3(0.5, 0.04, 0.02), Vector3(0, 0.62 + back_h * 0.55, 0.235), trim, Vector3(0.12, 0, 0))     # backlight stripe
	return g_


## Glowing display: bezel + emissive face (+ simple procedural content). Face looks along local +Z.
func _screen(parent: Node3D, screen_name: String, size: Vector2, pos: Vector3, rot: Vector3, color: Color, kind := "") -> Node3D:
	var h := _group(parent, screen_name, pos)
	h.rotation = rot
	_slab(h, Vector3(size.x + 0.1, size.y + 0.1, 0.06), Vector3.ZERO, _hull_mat(GUN, 0.85, 0.3))
	_slab(h, Vector3(size.x, size.y, 0.02), Vector3(0, 0, 0.032), _glow(color.darkened(0.55), 0.8))
	var z := 0.05
	var c := _glow(color, 2.0)
	var warm := _glow(WARM, 2.0)
	match kind:
		"horizon":
			_slab(h, Vector3(size.x * 0.9, size.y * 0.42, 0.01), Vector3(0, size.y * 0.23, z), _glow(Color("#3d86c9"), 1.1))
			_slab(h, Vector3(size.x * 0.9, size.y * 0.42, 0.01), Vector3(0, -size.y * 0.23, z), _glow(Color("#7a5230"), 1.1))
			_slab(h, Vector3(size.x * 0.9, 0.02, 0.012), Vector3(0, 0, z + 0.004), _glow(Color.WHITE, 2.0))
			_slab(h, Vector3(size.x * 0.4, 0.025, 0.012), Vector3(0, 0, z + 0.008), warm)
			_slab(h, Vector3(0.025, size.y * 0.25, 0.012), Vector3(0, 0, z + 0.008), warm)
		"starmap":
			for k in 18:
				var px := fmod(k * 0.37, 1.0) - 0.5
				var py := fmod(k * 0.61, 1.0) - 0.5
				_slab(h, Vector3(0.035, 0.035, 0.012), Vector3(px * size.x * 0.85, py * size.y * 0.8, z), _glow(Color.WHITE if k % 3 else WARM, 2.2))
			for k in 4:
				_slab(h, Vector3(size.x * 0.4, 0.012, 0.01), Vector3(fmod(k * 0.23, 0.4) * size.x - 0.2 * size.x, (k - 1.5) * size.y * 0.2, z),
					c, Vector3(0, 0, 0.5 + k * 0.4))
		"bars":
			for k in 5:
				var hh := size.y * (0.25 + 0.14 * ((k * 3) % 5))
				_slab(h, Vector3(size.x * 0.12, hh, 0.012), Vector3((k - 2) * size.x * 0.18, -size.y * 0.4 + hh * 0.5, z),
					_glow(READY if k < 3 else BUSY, 2.0))
		"hull":
			for k in 3:
				_slab(h, Vector3(size.x * 0.8, 0.012, 0.01), Vector3(0, (k - 1) * size.y * 0.3, z), c)
			_slab(h, Vector3(size.x * 0.22, size.y * 0.7, 0.012), Vector3(0, 0, z + 0.004), _glow(READY, 1.6))
			_slab(h, Vector3(size.x * 0.7, size.y * 0.16, 0.012), Vector3(0, -size.y * 0.1, z + 0.004), _glow(READY, 1.6))
		"reticle":
			_torus(h, size.y * 0.26, size.y * 0.3, Vector3(0, 0, z), _glow(Color("#ff4a3a"), 2.4), Vector3(PI * 0.5, 0, 0))
			_slab(h, Vector3(size.x * 0.8, 0.02, 0.012), Vector3(0, 0, z), _glow(Color("#ff4a3a"), 2.0))
			_slab(h, Vector3(0.02, size.y * 0.8, 0.012), Vector3(0, 0, z), _glow(Color("#ff4a3a"), 2.0))
			_slab(h, Vector3(0.08, 0.08, 0.012), Vector3(size.x * 0.15, size.y * 0.1, z + 0.004), c)
		"radar":
			_torus(h, size.y * 0.33, size.y * 0.37, Vector3(0, 0, z), c, Vector3(PI * 0.5, 0, 0))
			_torus(h, size.y * 0.16, size.y * 0.19, Vector3(0, 0, z), c, Vector3(PI * 0.5, 0, 0))
			_slab(h, Vector3(size.y * 0.34, 0.015, 0.012), Vector3(size.y * 0.17, size.y * 0.1, z + 0.004), _glow(READY, 2.4), Vector3(0, 0, 0.5))
			_ball(h, 0.03, Vector3(-0.1, -0.08, z + 0.01), warm)
		"heat":
			for k in 4:
				_slab(h, Vector3(size.x * 0.8, size.y * 0.1, 0.012), Vector3(0, (1.5 - k) * size.y * 0.22, z), _glow(Color("#2a2f36"), 0.4))
				_slab(h, Vector3(size.x * 0.8 * (0.35 + 0.15 * ((k * 2) % 4)), size.y * 0.1, 0.012),
					Vector3(-size.x * 0.4 * (1.0 - (0.35 + 0.15 * ((k * 2) % 4))), (1.5 - k) * size.y * 0.22, z + 0.004),
					_glow(Color("#ff7a3c") if k % 2 == 0 else CYAN, 2.2))
		"graph":
			for k in 8:
				var gh := size.y * (0.2 + 0.5 * absf(sin(k * 0.9)))
				_slab(h, Vector3(size.x * 0.07, gh, 0.012), Vector3((k - 3.5) * size.x * 0.11, -size.y * 0.4 + gh * 0.5, z), c)
		"buttons":
			for gx in 4:
				for gy in 3:
					_slab(h, Vector3(size.x * 0.16, size.y * 0.2, 0.014), Vector3((gx - 1.5) * size.x * 0.22, (gy - 1.0) * size.y * 0.3, z),
						_glow([READY, BUSY, CYAN, Color("#ff5a4a")][(gx + gy) % 4], 1.8))
		_:
			for k in 4:
				_slab(h, Vector3(size.x * (0.4 + 0.1 * (k % 3)), 0.02, 0.01), Vector3(-size.x * 0.1, (1.5 - k) * size.y * 0.2, z), c)
	return h


func _button_deck(parent: Node3D, pos: Vector3, cols: int, rows: int, rot := Vector3.ZERO) -> Node3D:
	var h := _group(parent, "ButtonDeck", pos)
	h.rotation = rot
	_slab(h, Vector3(cols * 0.17 + 0.1, 0.04, rows * 0.17 + 0.1), Vector3.ZERO, _hull_mat(GUN, 0.8, 0.35))
	var cols_m: Array = [_glow(READY, 1.6), _glow(BUSY, 1.6), _glow(CYAN, 1.6), _glow(Color("#ff5a4a"), 1.6)]
	for cx in cols:
		for cy in rows:
			_slab(h, Vector3(0.1, 0.04, 0.1), Vector3((cx - (cols - 1) * 0.5) * 0.17, 0.035, (cy - (rows - 1) * 0.5) * 0.17), cols_m[(cx + cy * 3) % 4])
	return h


func _build_pilot_bridge(f: Node3D) -> void:
	var metal := _hull_mat(GUN, 0.7, 0.35)
	var steel := _hull_mat(GUN_LIGHT, 0.85, 0.3)
	_build_seat(f, "PilotSeat", Vector3(-1.7, 0, -14.0), "captain")
	_build_seat(f, "CoPilotSeat", Vector3(1.7, 0, -14.0), "copilot")
	# Flight yoke + dual HOTAS directly in front of the pilot seat.
	var yoke := _group(f, "FlightYoke", Vector3(-1.7, 0, -15.45))
	_cyl(yoke, 0.05, 0.8, Vector3(0, 1.0, -0.38), steel, Vector3(PI * 0.5, 0, 0))
	_torus(yoke, 0.15, 0.2, Vector3(0, 1.12, 0.0), _hull_mat(Color("#15181c"), 0.3, 0.6), Vector3(PI * 0.5, 0, 0))
	_slab(yoke, Vector3(0.5, 0.06, 0.06), Vector3(0, 1.12, 0.0), steel)
	for sx in [-1.0, 1.0]:
		_slab(yoke, Vector3(0.1, 0.16, 0.1), Vector3(sx * 0.25, 1.12, 0.0), _hull_mat(Color("#15181c"), 0.3, 0.6))
		_ball(yoke, 0.025, Vector3(sx * 0.25, 1.22, 0.0), _glow(Color("#ff5a4a") if sx < 0.0 else READY, 2.2))
	_slab(yoke, Vector3(0.26, 0.1, 0.5), Vector3(-0.62, 0.95, -0.4), metal)                      # throttle quadrant
	_slab(yoke, Vector3(0.05, 0.3, 0.07), Vector3(-0.62, 1.1, -0.36), steel, Vector3(-0.35, 0, 0))
	_slab(yoke, Vector3(0.2, 0.02, 0.36), Vector3(-0.62, 1.01, -0.4), _glow(BUSY, 1.4))
	_slab(yoke, Vector3(0.2, 0.1, 0.2), Vector3(0.62, 0.95, -0.4), metal)                        # joystick base
	_cyl(yoke, 0.03, 0.3, Vector3(0.62, 1.15, -0.4), steel)
	_slab(yoke, Vector3(0.08, 0.14, 0.08), Vector3(0.62, 1.34, -0.4), _hull_mat(Color("#15181c"), 0.3, 0.6))
	_ball(yoke, 0.022, Vector3(0.62, 1.4, -0.4), _glow(Color("#ff5a4a"), 2.4))
	# Wraparound illuminated avionics console under the canopy.
	var dash := _group(f, "PilotDashboard", Vector3(0, 0, Z_NOSE + 1.2))
	var main := _slab(dash, Vector3(6.2, 0.9, 1.3), Vector3(0, 0.45, 0), metal)
	main.name = "CockpitDash"
	_slab(dash, Vector3(6.0, 0.04, 1.0), Vector3(0, 0.92, 0.05), _glow(CYAN, 1.0), Vector3(-0.25, 0, 0))
	for sx in [-1.0, 1.0]:
		_slab(dash, Vector3(1.1, 0.9, 1.3), Vector3(sx * 3.55, 0.45, 0.25), metal)
		_slab(dash, Vector3(1.0, 0.04, 1.1), Vector3(sx * 3.55, 0.92, 0.3), _glow(CYAN, 0.9), Vector3(-0.25, 0, 0))
	# Five angled screens: star-map nav, artificial horizon, fuel / delta-v bars, hull status, tactile button deck.
	_screen(dash, "NavStarMapScreen", Vector2(1.1, 0.7), Vector3(-2.7, 1.55, 0.2), Vector3(-0.3, 0.5, 0), CYAN, "starmap")
	_screen(dash, "HorizonScreen", Vector2(1.1, 0.7), Vector3(-1.4, 1.55, 0.2), Vector3(-0.3, 0.2, 0), READY, "horizon")
	_screen(dash, "FuelDeltaVScreen", Vector2(1.0, 0.7), Vector3(0.0, 1.55, 0.2), Vector3(-0.3, 0.0, 0), BUSY, "bars")
	_screen(dash, "HullStatusScreen", Vector2(1.1, 0.7), Vector3(1.4, 1.55, 0.2), Vector3(-0.3, -0.2, 0), READY, "hull")
	_screen(dash, "ButtonDeckScreen", Vector2(1.1, 0.7), Vector3(2.7, 1.55, 0.2), Vector3(-0.3, -0.5, 0), CYAN, "buttons")
	_slab(dash, Vector3(5.9, 0.3, 0.15), Vector3(0, 1.08, 0.0), metal)           # screen mounting rail
	_button_deck(dash, Vector3(-1.7, 0.99, 0.55), 5, 2, Vector3(-0.25, 0, 0))
	_button_deck(dash, Vector3(1.7, 0.99, 0.55), 5, 2, Vector3(-0.25, 0, 0))
	var sign_node := Gfx.label("FLIGHT BRIDGE", READY, 30, 4)
	sign_node.pixel_size = 0.01
	sign_node.position = Vector3(0, 3.95, Z_NOSE + 0.75)
	f.add_child(sign_node)


func _build_gunnery(f: Node3D) -> void:
	var metal := _hull_mat(GUN, 0.7, 0.35)
	var steel := _hull_mat(GUN_LIGHT, 0.85, 0.3)
	var red := _glow(Color("#ff4a3a"), 2.0)
	var zc := -10.6
	# Raised tactical ring deck + armoured swivel gunner chair (faces the starboard fire-control wall).
	_cyl(f, 1.1, 0.16, Vector3(3.3, 0.08, zc), metal)
	_torus(f, 1.04, 1.12, Vector3(3.3, 0.17, zc), red)
	_build_seat(f, "GunnerSeat", Vector3(3.2, 0.16, zc), "gunner", -PI * 0.5)
	# Dual-joystick turret fire-control console against the wall.
	var con := _group(f, "ShootingConsole", Vector3(4.12, 0, zc))
	_slab(con, Vector3(0.75, 0.95, 2.6), Vector3(0, 0.475, 0), metal)
	_slab(con, Vector3(0.7, 0.05, 2.4), Vector3(-0.02, 1.0, 0), steel, Vector3(0, 0, 0.3))
	_slab(con, Vector3(0.04, 0.02, 2.0), Vector3(-0.2, 1.04, 0), _glow(Color("#ff4a3a"), 1.2), Vector3(0, 0, 0.3))
	for sz in [-0.55, 0.55]:
		_slab(con, Vector3(0.2, 0.1, 0.2), Vector3(-0.2, 1.08, sz), steel)
		_cyl(con, 0.03, 0.34, Vector3(-0.2, 1.3, sz), steel)
		_slab(con, Vector3(0.09, 0.16, 0.09), Vector3(-0.2, 1.52, sz), _hull_mat(Color("#15181c"), 0.3, 0.6))
		_ball(con, 0.025, Vector3(-0.2, 1.62, sz), _glow(Color("#ff4a3a"), 2.4))
	for k in 6:
		_slab(con, Vector3(0.08, 0.05, 0.08), Vector3(-0.3, 1.06, -0.95 + k * 0.38), _glow([READY, BUSY, Color("#ff4a3a")][k % 3], 1.8), Vector3(0, 0, 0.3))
	_slab(con, Vector3(0.22, 0.12, 0.22), Vector3(-0.28, 1.1, 0.0), steel)                                # guarded fire switch
	_ball(con, 0.07, Vector3(-0.28, 1.2, 0.0), _glow(Color("#ff2a1a"), 2.8))
	# Targeting computers: reticle display, radar scope, weapon heat / ammo bars.
	var comps := _group(f, "GunnerComputers", Vector3(4.28, 0, zc))
	_screen(comps, "TargetReticleScreen", Vector2(0.85, 0.62), Vector3(0, 1.85, -0.95), Vector3(0, -PI * 0.5 - 0.35, 0), Color("#ff6a5c"), "reticle")
	_screen(comps, "RadarScopeScreen", Vector2(0.85, 0.62), Vector3(0, 1.85, 0.0), Vector3(0, -PI * 0.5, 0), CYAN, "radar")
	_screen(comps, "WeaponHeatScreen", Vector2(0.85, 0.62), Vector3(0, 1.85, 0.95), Vector3(0, -PI * 0.5 + 0.35, 0), BUSY, "heat")
	var sign_node := Gfx.label("WEAPONS CONTROL", Color("#ff8a3a"), 30, 4)
	sign_node.pixel_size = 0.009
	sign_node.position = Vector3(4.4, 3.55, zc)
	sign_node.rotation.y = -PI * 0.5
	f.add_child(sign_node)
	_slab(f, Vector3(0.1, 0.5, 2.5), Vector3(4.5, 3.55, zc), _glow(Color("#7a1c12"), 1.2))


func _build_reactor_bay(f: Node3D) -> void:
	var metal := _hull_mat(GUN, 0.7, 0.35)
	var steel := _hull_mat(GUN_LIGHT, 0.85, 0.3)
	var rc := _group(f, "ReactorConsole")
	# Glowing vertical fusion reactor core with containment rings.
	var core_p := Vector3(-3.85, 0, -1.7)
	_cyl(rc, 0.7, 0.3, core_p + Vector3(0, 0.15, 0), metal)
	var core := _cyl(rc, 0.36, 2.5, core_p + Vector3(0, 1.55, 0), _glow(Color("#ffd35a"), 3.0))
	core.name = "FusionCore"
	for ry in [0.7, 1.3, 1.9, 2.5]:
		_torus(rc, 0.44, 0.56, core_p + Vector3(0, ry, 0), steel)
	_cyl(rc, 0.6, 0.2, core_p + Vector3(0, 2.9, 0), metal)
	_cyl(rc, 0.16, 1.4, core_p + Vector3(0, 3.7, 0), steel)
	var omni := OmniLight3D.new()
	omni.position = core_p + Vector3(0.6, 1.6, 0)
	omni.light_color = Color("#ffd35a")
	omni.light_energy = 0.7
	omni.omni_range = 4.5
	omni.shadow_enabled = false
	rc.add_child(omni)
	# Breaker panel on the hull wall.
	_slab(rc, Vector3(0.1, 1.2, 1.2), Vector3(-4.5, 1.55, -0.2), metal)
	for k in 12:
		_slab(rc, Vector3(0.05, 0.08, 0.06), Vector3(-4.44, 1.15 + (k / 4) * 0.3, -0.65 + (k % 4) * 0.3),
			_glow(READY if k % 3 else BUSY, 1.8))
	# Engineer diagnostic computer bank: desk, keyboard tray, three telemetry monitors, technician stool.
	_slab(rc, Vector3(1.0, 0.95, 2.4), Vector3(-4.0, 0.475, 0.5), metal)
	_slab(rc, Vector3(1.05, 0.06, 2.45), Vector3(-4.0, 0.98, 0.5), steel)
	_slab(rc, Vector3(0.4, 0.04, 0.9), Vector3(-3.55, 1.03, 0.5), _hull_mat(Color("#15181c"), 0.3, 0.6), Vector3(0, 0, 0.1))
	_slab(rc, Vector3(0.34, 0.02, 0.8), Vector3(-3.55, 1.06, 0.5), _glow(CYAN, 0.7), Vector3(0, 0, 0.1))
	var kinds := ["graph", "bars", "graph"]
	for k in 3:
		_screen(rc, "TelemetryScreen%d" % k, Vector2(0.8, 0.55), Vector3(-4.3, 1.55, 0.5 + (k - 1) * 0.85),
			Vector3(0, PI * 0.5 - (k - 1) * 0.3, 0), Color("#ffd35a") if k != 1 else CYAN, kinds[k])
	_cyl(rc, 0.28, 0.08, Vector3(-2.85, 0.62, 0.5), _hull_mat(Color("#1a1d22"), 0.3, 0.6))
	_cyl(rc, 0.05, 0.6, Vector3(-2.85, 0.3, 0.5), steel)
	_cyl(rc, 0.26, 0.05, Vector3(-2.85, 0.03, 0.5), steel)


func _build_life_support(f: Node3D) -> void:
	var metal := _hull_mat(GUN, 0.7, 0.35)
	var steel := _hull_mat(GUN_LIGHT, 0.85, 0.3)
	var lb := _group(f, "LifeSupportBay")
	for tz in [-1.95, -0.95]:
		_cyl(lb, 0.42, 2.7, Vector3(3.95, 1.5, tz), _hull_mat(Color("#3b5d57"), 0.7, 0.35))
		_ball(lb, 0.42, Vector3(3.95, 2.85, tz), _hull_mat(Color("#3b5d57"), 0.7, 0.35))
		_torus(lb, 0.42, 0.48, Vector3(3.95, 0.5, tz), steel)
		_torus(lb, 0.42, 0.48, Vector3(3.95, 2.4, tz), steel)
		_torus(lb, 0.1, 0.16, Vector3(3.51, 1.3, tz), _glow(Color("#8fe0a8"), 1.3), Vector3(0, 0, PI * 0.5))   # valve wheel
		_slab(lb, Vector3(0.04, 0.02, 0.28), Vector3(3.5, 1.3, tz), _glow(Color("#8fe0a8"), 1.3))
	_cyl(lb, 0.07, 1.4, Vector3(3.95, 0.7, -1.45), steel, Vector3(PI * 0.5, 0, 0))
	_cyl(lb, 0.07, 1.4, Vector3(3.95, 2.6, -1.45), steel, Vector3(PI * 0.5, 0, 0))
	_cyl(lb, 0.06, 1.6, Vector3(4.4, 1.9, -1.45), steel)
	_slab(lb, Vector3(1.0, 0.95, 2.0), Vector3(4.0, 0.475, 1.0), metal)
	_slab(lb, Vector3(1.05, 0.06, 2.05), Vector3(4.0, 0.98, 1.0), steel)
	_screen(lb, "AtmosphereScreen", Vector2(0.85, 0.6), Vector3(4.3, 1.55, 0.55), Vector3(0, -PI * 0.5 + 0.3, 0), Color("#8fe0a8"), "graph")
	_screen(lb, "CabinTempScreen", Vector2(0.85, 0.6), Vector3(4.3, 1.55, 1.45), Vector3(0, -PI * 0.5 - 0.3, 0), CYAN, "bars")
	_slab(lb, Vector3(0.4, 0.04, 0.8), Vector3(3.65, 1.03, 1.0), _hull_mat(Color("#15181c"), 0.3, 0.6), Vector3(0, 0, -0.1))


func _build_workshop(f: Node3D) -> void:
	var metal := _hull_mat(GUN, 0.7, 0.35)
	var steel := _hull_mat(GUN_LIGHT, 0.85, 0.3)
	var wb := _group(f, "WorkshopBench")
	_slab(wb, Vector3(1.0, 0.9, 2.8), Vector3(4.0, 0.45, -5.8), metal)
	_slab(wb, Vector3(1.1, 0.1, 2.9), Vector3(4.0, 0.95, -5.8), steel)
	for k in 3:
		_slab(wb, Vector3(0.86, 0.04, 0.8), Vector3(4.0, 0.62, -6.8 + k * 1.0), _hull_mat(Color("#15181c"), 0.4, 0.5))   # drawer fronts
	_slab(wb, Vector3(0.22, 0.2, 0.3), Vector3(3.7, 1.1, -6.8), steel)                  # vise
	_slab(wb, Vector3(0.06, 0.12, 0.24), Vector3(3.58, 1.18, -6.8), steel)
	_screen(wb, "PartsDiagnosticScreen", Vector2(0.9, 0.62), Vector3(4.3, 1.62, -5.5), Vector3(0, -PI * 0.5 + 0.2, 0), BUSY, "hull")
	_slab(wb, Vector3(0.1, 0.5, 0.1), Vector3(4.35, 1.28, -5.5), steel)
	_slab(wb, Vector3(0.5, 0.05, 0.3), Vector3(3.85, 1.03, -5.0), _hull_mat(Color("#15181c"), 0.4, 0.5))   # parts tray
	for k in 3:
		_slab(wb, Vector3(0.1, 0.08, 0.12), Vector3(3.85, 1.09, -5.12 + k * 0.12), _glow(BUSY, 1.4))
	# Tool locker.
	_slab(wb, Vector3(0.6, 2.3, 1.0), Vector3(4.2, 1.15, -8.0), metal)
	_slab(wb, Vector3(0.02, 2.2, 0.03), Vector3(3.88, 1.15, -8.0), steel)
	for sz in [-0.25, 0.25]:
		_slab(wb, Vector3(0.04, 0.3, 0.04), Vector3(3.87, 1.2, -8.0 + sz), _glow(BUSY, 1.0))
	# Spare hull armour plates on a rack.
	for sz in [-4.3, -3.3]:
		_slab(wb, Vector3(0.08, 1.7, 0.08), Vector3(4.4, 0.85, sz), steel)
	_slab(wb, Vector3(0.7, 0.07, 1.3), Vector3(4.1, 0.1, -3.8), steel)
	for k in 3:
		_slab(wb, Vector3(0.07, 1.6, 0.95), Vector3(4.05 - k * 0.14, 0.95, -3.8), _hull_mat(Color("#4a525c"), 0.85, 0.4), Vector3(0, 0, -0.12))
	# Articulated overhead repair arm.
	_slab(wb, Vector3(0.5, 0.12, 0.5), Vector3(3.7, CABIN_H - 0.08, -5.8), steel)
	_ball(wb, 0.14, Vector3(3.7, CABIN_H - 0.25, -5.8), steel)
	_cyl(wb, 0.07, 1.3, Vector3(3.45, 3.75, -5.8), steel, Vector3(0, 0, 0.55))
	_ball(wb, 0.12, Vector3(3.15, 3.2, -5.8), steel)
	_cyl(wb, 0.06, 1.2, Vector3(3.55, 2.85, -5.8), steel, Vector3(0, 0, -0.65))
	_ball(wb, 0.1, Vector3(3.95, 2.35, -5.8), steel)
	_cyl(wb, 0.035, 0.5, Vector3(3.95, 2.05, -5.8), _glow(BUSY, 2.2))


func _build_lab(f: Node3D) -> void:
	var metal := _hull_mat(GUN, 0.7, 0.35)
	var steel := _hull_mat(GUN_LIGHT, 0.85, 0.3)
	var zc := -10.6
	var tb := _group(f, "ScienceHolotable", Vector3(-2.9, 0, zc))
	_cyl(tb, 0.95, 0.95, Vector3(0, 0.475, 0), metal)
	_torus(tb, 0.9, 1.04, Vector3(0, 0.97, 0), _glow(CYAN, 1.8))
	_cyl(tb, 1.05, 0.08, Vector3(0, 0.99, 0), steel)
	var holo := ShaderMaterial.new()
	holo.shader = preload("res://shaders/hologram.gdshader")
	holo.set_shader_parameter("cyan_color", Color("#59d8e8"))
	var globe := _ball(tb, 0.5, Vector3(0, 1.65, 0), holo)
	globe.name = "HologramGlobe"
	_torus(tb, 0.6, 0.64, Vector3(0, 1.65, 0), holo, Vector3(0.4, 0, 0.2))
	_cyl(tb, 0.7, 0.02, Vector3(0, 1.06, 0), holo)
	var omni := OmniLight3D.new()
	omni.position = Vector3(0, 1.7, 0)
	omni.light_color = CYAN
	omni.light_energy = 0.8
	omni.omni_range = 4.0
	omni.shadow_enabled = false
	tb.add_child(omni)
	# Science flag containment rack with illuminated slots.
	var rack := _group(f, "FlagContainmentRack", Vector3(-4.25, 0, -12.6))
	_slab(rack, Vector3(0.5, 2.3, 1.6), Vector3(0, 1.15, 0), metal)
	for gy in 3:
		for gz in 3:
			var py := 0.6 + gy * 0.6
			var pz := (gz - 1) * 0.5
			_slab(rack, Vector3(0.04, 0.4, 0.4), Vector3(0.26, py, pz), _glow(CYAN.darkened(0.3), 0.9))
			if (gy + gz) % 2 == 0:
				_slab(rack, Vector3(0.1, 0.22, 0.22), Vector3(0.3, py, pz), _glow([BUSY, READY, Color("#ff5a4a")][(gy + gz) % 3], 1.8))
	_slab(rack, Vector3(0.52, 0.06, 1.62), Vector3(0, 2.31, 0), steel)
	# Dual spectrometer analysis computers.
	var sp := _group(f, "SpectrometerBank")
	_slab(sp, Vector3(0.75, 0.9, 1.9), Vector3(-4.12, 0.45, -8.6), metal)
	_slab(sp, Vector3(0.8, 0.06, 1.95), Vector3(-4.12, 0.93, -8.6), steel)
	_screen(sp, "SpectrometerScreenA", Vector2(0.75, 0.55), Vector3(-4.35, 1.5, -9.05), Vector3(0, PI * 0.5 + 0.25, 0), CYAN, "graph")
	_screen(sp, "SpectrometerScreenB", Vector2(0.75, 0.55), Vector3(-4.35, 1.5, -8.15), Vector3(0, PI * 0.5 - 0.25, 0), Color("#b48cff"), "starmap")
	_slab(sp, Vector3(0.3, 0.18, 0.4), Vector3(-3.95, 1.05, -8.6), steel)
	_cyl(sp, 0.07, 0.3, Vector3(-3.78, 1.07, -8.6), _glow(CYAN, 1.6), Vector3(0, 0, PI * 0.5))


func _build_engine_bay(f: Node3D) -> void:
	var metal := _hull_mat(GUN, 0.7, 0.35)
	var steel := _hull_mat(GUN_LIGHT, 0.85, 0.3)
	var ec := _group(f, "EngineConsole")
	var plasma := _glow(CYAN, 3.0)
	for sx in [-1.0, 1.0]:
		var mx: float = sx * 2.9
		_cyl(ec, 0.62, 0.2, Vector3(mx, 0.1, 4.8), metal)
		_cyl(ec, 0.4, 3.4, Vector3(mx, 1.8, 4.8), plasma)
		for ry in [0.6, 1.2, 1.8, 2.4, 3.0]:
			_torus(ec, 0.46, 0.58, Vector3(mx, ry, 4.8), steel)
		_cyl(ec, 0.5, 0.25, Vector3(mx, 3.6, 4.8), metal)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(mx - sx * 0.9, 1.8, 4.8)
		lamp.light_color = CYAN
		lamp.light_energy = 0.8
		lamp.omni_range = 4.5
		lamp.shadow_enabled = false
		ec.add_child(lamp)
		# Braided conduit ribs from the manifold to the bulkhead.
		for k in 3:
			_cyl(ec, 0.05, 1.1, Vector3(mx - sx * (0.52 + 0.05 * k), 0.9 + k * 0.8, 5.45), steel, Vector3(PI * 0.5, 0, 0))
	_slab(ec, Vector3(3.0, 1.0, 0.9), Vector3(0, 0.5, 4.95), metal)
	_slab(ec, Vector3(2.9, 0.05, 0.8), Vector3(0, 1.03, 4.9), _glow(CYAN, 0.9), Vector3(-0.25, 0, 0))
	for k in 6:
		_slab(ec, Vector3(0.08, 0.05, 0.3), Vector3(-1.1 + k * 0.44, 1.06, 4.72), _glow([READY, BUSY, CYAN][k % 3], 1.8), Vector3(-0.25, 0, 0))
	_screen(ec, "PropulsionScreenA", Vector2(0.95, 0.65), Vector3(-1.05, 1.6, 5.3), Vector3(-0.25, PI - 0.25, 0), Color("#ff7a5c"), "bars")
	_screen(ec, "PropulsionScreenB", Vector2(0.95, 0.65), Vector3(0.0, 1.6, 5.3), Vector3(-0.25, PI, 0), CYAN, "graph")
	_screen(ec, "PropulsionScreenC", Vector2(0.95, 0.65), Vector3(1.05, 1.6, 5.3), Vector3(-0.25, PI + 0.25, 0), BUSY, "heat")


func _build_stations() -> void:
	var root := Node3D.new()
	root.name = "Stations"
	add_child(root)
	var colors := {"cockpit": READY, "lab": CYAN, "workshop": BUSY, "power_room": Color("#ffd35a"),
		"life_support": Color("#8fe0a8"), "engine_bay": Color("#ff7a5c"), "gunnery": Color("#ff6a5c")}
	for room in STATION_POS:
		var pos: Vector3 = STATION_POS[room]
		var node := Node3D.new()
		node.name = room
		node.position = pos
		root.add_child(node)
		var col: Color = colors[room]
		var ring := Gfx.ring(1.0, 0.14, col, 0.85)
		ring.name = "ObjectiveRing"
		ring.material_override = Gfx.unshaded(col, 0.85).duplicate()
		ring.position = Vector3(0, 0.03, 0)
		node.add_child(ring)
		var label := Gfx.label(String(ROOM_NAMES[room]), col, 24, 4)
		label.name = "StationLabel"
		label.pixel_size = 0.0055
		label.position = Vector3(0, 2.6, 0)
		node.add_child(label)
		stations[room] = {"node": node, "ring": ring, "label": label, "cd": 0.0}
