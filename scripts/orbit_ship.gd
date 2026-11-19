## Single-player mission inside the spacecraft (ship_interior.glb: six rooms along +Z plus a side airlock).
## Walk to the lit station in the indicated room and press E. Timed tasks keep running while you move on.
class_name OrbitShip
extends Node3D

const ROOM_Z := {"engine_bay": 3.0, "power_room": 8.8, "life_support": 14.1, "workshop": 19.4, "lab": 24.7, "cockpit": 30.0}
const STATIONS := {
	"power_room": [Vector3(1.6, 0, 8.8), "prop_fuse_box"],
	"life_support": [Vector3(1.6, 0, 14.1), "prop_co2_filter_slot"],
	"workshop": [Vector3(1.6, 0, 19.4), "prop_toggle_panel"],
	"lab": [Vector3(1.6, 0, 24.7), "prop_scan_screen"],
	"cockpit": [Vector3(0, 0, 31.4), "prop_button_console"],
	"airlock": [Vector3(-4.6, 0, 18.6), "prop_keypad"],
}
const AIRLOCK_OUTSIDE := Vector3(-7.5, 1.2, 19.4)
const TELESCOPE_BAY := Vector3(-20, 1.5, 27)

var g
var c: Campaign
var player: Actor
var station_nodes := {}
var beacon: MeshInstance3D
var env: WorldEnvironment
var exterior: Node3D
var eva := false
var vel := Vector3.ZERO
var ctx := {"alignment": 20.0, "closure": 62.0, "calibration": 22.0, "at_telescope": false, "at_airlock": false}
var action_idx := 0
var speed_mul := 1.0
var launched := false
var finished := false
var accum := 0.0


func actor(_i: int) -> Variant:
	return player


func setup(main, campaign: Campaign) -> void:
	g = main
	c = campaign
	name = "OrbitShip"
	var on_pad := c.phase == "checkout"
	if on_pad:
		env = Gfx.environment(Color("#7fb2e2"), Color("#cfe2f2"), Color("#556b47"), 0.9)
	else:
		env = Gfx.environment(Color("#03060d"), Color("#0a1426"), Color("#03060d"), 0.7)
	add_child(env)
	add_child(Gfx.sun(Vector3(-35, -40, 0), Color("#fff1d6"), 1.3))
	# Interior mesh, room lights, and each interactive console are editable in Godot.
	var editable: Node3D = preload("res://scenes/levels/OrbitShipInterior.tscn").instantiate() as Node3D
	add_child(editable)
	var stations: Node = editable.get_node("Stations")
	for room in STATIONS:
		var n: Node3D = stations.get_node(room) as Node3D
		station_nodes[room] = {"node": n, "ring": n.get_node("ObjectiveRing"), "label": n.get_node("StationLabel")}
	beacon = Gfx.sphere(0.18, Color("#eaa665"), Vector3.ZERO, 3.0, 10)
	add_child(beacon)
	_exterior(on_pad)
	var s = Sim.SPECIALISTS[g.opts["selected"]]
	player = Actor.new()
	player.setup(s["model"], g.opts["selected"], Sim.role_color(g.opts["selected"]))
	player.position = Vector3(0, 0, 19.4) if on_pad else Vector3(0, 0, 28.5)
	add_child(player)
	g.first_person = true
	g.yaw = PI
	g.pitch = -0.1
	if c.phase == "eva":
		_enter_eva()


func _exterior(on_pad: bool) -> void:
	exterior = Node3D.new()
	add_child(exterior)
	if on_pad:
		return
	var earth := Gfx.sphere(900, Color("#2f6fb0"), Vector3(0, -980, 10), 0.05, 48)
	exterior.add_child(earth)
	var clouds := Gfx.sphere(906, Color("#ffffff"), Vector3(0, -980, 10), 0.0, 48)
	clouds.material_override = Gfx.mat(Color("#ffffff"), 0.9, 0.2, 0.25)
	exterior.add_child(clouds)
	if c.mission_id == "telescope":
		var scope := Node3D.new()
		scope.position = Vector3(-20, 1.5, 34)
		var tube := Gfx.cyl(2.2, 13.0, Color("#d9dee6"), Vector3.ZERO, 24)
		tube.rotation.x = PI / 2
		scope.add_child(tube)
		scope.add_child(Gfx.cyl(2.25, 0.5, Color("#c9a24a"), Vector3(0, 0, -3), 24))
		scope.get_child(1).rotation.x = PI / 2
		for side in [-1, 1]:
			scope.add_child(Gfx.box(Vector3(6, 0.1, 2.4), Color("#2c5581"), Vector3(side * 5.4, 0, 0), 0.15))
		exterior.add_child(scope)
		var bay := Gfx.ring(1.4, 0.15, Color("#9cdeb1"), 0.9)
		bay.position = TELESCOPE_BAY
		bay.rotation.x = PI / 2
		exterior.add_child(bay)
		var bl := Gfx.label("INSTRUMENT BAY", Color("#9cdeb1"), 40)
		bl.position = TELESCOPE_BAY + Vector3(0, 2.2, 0)
		exterior.add_child(bl)
	var ab := Gfx.ring(1.2, 0.12, Color("#eaa665"), 0.9)
	ab.position = AIRLOCK_OUTSIDE
	ab.rotation.z = PI / 2
	exterior.add_child(ab)


func _enter_eva() -> void:
	eva = true
	player.position = AIRLOCK_OUTSIDE + Vector3(-1.5, 0, 0)
	g.yaw = PI * 0.75
	g.first_person = false
	g.hud.show_banner("EXTRAVEHICULAR ACTIVITY", "WASD float · Space up · Ctrl down · tethered to the airlock", 3.0)


func _exit_eva() -> void:
	eva = false
	player.position = Vector3(-4.2, 0, 19.4)
	vel = Vector3.ZERO
	g.first_person = true


# ---------------------------------------------------------------------------
# Gameplay
# ---------------------------------------------------------------------------
func collide(p: Vector3) -> Vector3:
	if eva:
		return p
	if p.x < -2.0 and p.z > 18.3 and p.z < 20.5:
		p.x = maxf(p.x, -5.6)
	else:
		p.x = clampf(p.x, -2.0, 2.0)
	p.z = clampf(p.z, 0.5, 32.0)
	return p


func room_at(p: Vector3) -> String:
	if eva:
		if p.distance_to(TELESCOPE_BAY) < 3.5:
			return "exterior"
		if p.distance_to(AIRLOCK_OUTSIDE) < 3.5:
			return "airlock"
		return ""
	if p.x < -2.4:
		return "airlock"
	var best := ""
	var bd := INF
	for room in ROOM_Z:
		var d: float = absf(p.z - ROOM_Z[room])
		if d < bd:
			bd = d
			best = room
	return best


func tick(dt: float) -> void:
	if g.sim == null and g.pressed(KEY_M):
		g.hud.toggle_tactical()
	if finished:
		return
	if g.pressed(KEY_F5):
		speed_mul = 1.0 if speed_mul > 1.0 else 4.0
		g.hud.toast("Time ×%d" % int(speed_mul), 1.2)
	if g.pressed(KEY_C):
		var cmds := ["monitor", "orientation", "prepare"]
		c.crew_command = cmds[(cmds.find(c.crew_command) + 1) % 3]
		g.hud.toast("Crew command: " + c.crew_command.to_upper(), 1.5)
	if g.pressed(KEY_X):
		c.conserve = not c.conserve
		g.hud.toast("Conservation mode " + ("ON (600 W essential load)" if c.conserve else "OFF"), 1.5)
	if g.pressed(KEY_TAB):
		action_idx += 1
	accum += dt * speed_mul
	while accum >= 0.05:
		c.tick(0.05)
		accum -= 0.05
	if eva:
		_float(dt)
	else:
		var sp: float = g.drive(player, dt, 22.0, 0.75)
		player.animate(dt, sp)
	g.follow_cam(player, 4.5 if eva else 2.6)
	ctx["at_telescope"] = eva and player.position.distance_to(TELESCOPE_BAY) < 3.5
	ctx["at_airlock"] = eva and player.position.distance_to(AIRLOCK_OUTSIDE) < 3.5
	if c.phase == "eva" and not eva:
		_enter_eva()
	elif c.phase != "eva" and eva:
		_exit_eva()
	if c.phase == "launch" and not launched:
		launched = true
		g.start_campaign_launch()
		return
	_interact(dt)
	_station_visuals(dt)
	if c.terminal():
		finished = true
		g.campaign_finished()


func _float(dt: float) -> void:
	var cam: Camera3D = g.cam
	var f := -cam.global_transform.basis.z
	var r := cam.global_transform.basis.x
	var acc := Vector3.ZERO
	if g.held(KEY_W): acc += f
	if g.held(KEY_S): acc -= f
	if g.held(KEY_D): acc += r
	if g.held(KEY_A): acc -= r
	if g.held(KEY_SPACE): acc += Vector3.UP
	if g.held(KEY_CTRL): acc -= Vector3.UP
	vel += acc.normalized() * 6.0 * dt if acc.length() > 0.0 else Vector3.ZERO
	vel *= 1.0 - minf(1.0, dt * 0.8)
	vel = vel.limit_length(5.0)
	player.position += vel * dt
	# Tether: stay within reach of the airlock.
	var off := player.position - AIRLOCK_OUTSIDE
	if off.length() > 26.0:
		player.position = AIRLOCK_OUTSIDE + off.normalized() * 26.0
		vel *= -0.3
	player.rotation.y = g.yaw
	player.heading = g.yaw
	player.animate(dt, 0.0, "jump")


func _room_actions(room: String) -> Array:
	return c.objectives().filter(func(a): return a["room"] == room and a["id"] != "wait")


func _station_position(room: String) -> Vector3:
	return station_nodes[room]["node"].position


func _interact(dt: float) -> void:
	var room := room_at(player.position)
	var near := ""
	if eva:
		near = room
	else:
		for r in STATIONS:
			if g.flat_dist(player.position, _station_position(r)) < 2.4:
				near = r
	if c.activity != null:
		var a = c.activity
		var label := ""
		for o in c.objectives():
			if o["id"] == a["id"]:
				label = o["label"]
		g.hud.set_prompt(label.to_upper(), "In progress · %d s" % ceili(a["remaining"]), 1.0 - a["remaining"] / a["total"])
		return
	var objs := c.objectives()
	if objs.is_empty():
		g.hud.set_prompt("")
		return
	if objs[0]["id"] == "wait":
		g.hud.set_prompt(objs[0]["label"].to_upper(), objs[0]["note"] + " · F5 time ×4", c.phase_time / 45.0)
		return
	if near == "":
		var target: String = objs[0]["room"]
		g.hud.set_prompt(objs[0]["label"].to_upper(), "Go to the %s" % Campaign.ROOMS[target].to_lower())
		return
	var here := _room_actions(near)
	if here.is_empty():
		g.hud.set_prompt(Campaign.ROOMS[near].to_upper(), "No task here · next: %s (%s)" % [objs[0]["label"], Campaign.ROOMS[objs[0]["room"]]])
		return
	var a: Dictionary = here[action_idx % here.size()]
	var detail := ""
	if a["id"] == "rendezvous":
		ctx["alignment"] = clampf(ctx["alignment"] + g.wheel * 2.0, 0.0, 100.0)
		if g.held(KEY_Q): ctx["closure"] = maxf(0.0, ctx["closure"] - dt * 15.0)
		if g.held(KEY_F): ctx["closure"] = minf(100.0, ctx["closure"] + dt * 15.0)
		detail = "Alignment %d (50 ±7, wheel) · Closure %d (30 ±7, Q/F) · " % [int(ctx["alignment"]), int(ctx["closure"])]
	elif a["id"] == "calibrate":
		ctx["calibration"] = clampf(ctx["calibration"] + g.wheel * 2.0, 0.0, 100.0)
		detail = "Calibration %d — band 50 ±6 (mouse wheel) · " % int(ctx["calibration"])
	var why := c.can_action(a["id"], a["room"], ctx)
	detail += why if why != "" else ("%d s task" % int(a["seconds"]) if a["seconds"] > 0.0 else "Instant")
	if here.size() > 1:
		detail += " · TAB next task (%d/%d)" % [action_idx % here.size() + 1, here.size()]
	g.hud.set_prompt("E · " + a["label"].to_upper(), detail)
	if g.pressed(KEY_E):
		var res := c.start_action(a["id"], a["room"], ctx)
		if res["ok"]:
			g.sfx("capture_tick", -6)
			action_idx = 0
		else:
			g.hud.toast(res["reason"], 2.5)


func _station_visuals(dt: float) -> void:
	var objs := c.objectives()
	var active := ""
	if not objs.is_empty() and objs[0]["id"] != "wait":
		active = objs[0]["room"]
	for room in station_nodes:
		var sn: Dictionary = station_nodes[room]
		var lit := false
		for o in objs:
			if o["room"] == room and o["id"] != "wait":
				lit = true
		sn["ring"].visible = lit
		sn["ring"].scale = Vector3.ONE * (1.0 + 0.1 * sin(c.elapsed * 4.0)) * Vector3(1, 0.05, 1)
	if active != "" and STATIONS.has(active) and not eva:
		beacon.visible = true
		beacon.position = _station_position(active) + Vector3(0, 2.8 + sin(c.elapsed * 3.0) * 0.1, 0)
	elif eva:
		beacon.visible = true
		beacon.position = (TELESCOPE_BAY if not c.installed else AIRLOCK_OUTSIDE) + Vector3(0, 2.0, 0)
	else:
		beacon.visible = false


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func hud_update(hud: Hud) -> void:
	var idx: int = {"checkout": 0, "launch": 1, "commission": 1, "rendezvous": 1, "prepare": 1, "eva": 1, "science": 2, "eclipse": 3, "downlink": 4, "return": 5, "reentry": 5}.get(c.phase, 5)
	hud.set_sp_steps(["CHECKOUT", "ORBIT", "SCIENCE", "ECLIPSE", "DOWNLINK", "RETURN"], idx)
	hud.clock.text = "T+" + UI.fmt_time(c.elapsed)
	var m := Campaign.mission(c.mission_id)
	hud.title.text = Campaign.PHASE_NAMES[c.phase].to_upper() + "."
	hud.subtitle.text = "MISSION %s · %s · %s" % [m["number"], m["name"].to_upper(), "EVA" if eva else Campaign.ROOMS.get(room_at(player.position), "").to_upper()]
	var lines := PackedStringArray()
	lines.append("[color=#eaa665][b]OBJECTIVES[/b][/color]")
	for o in c.objectives():
		lines.append("○ %s [color=#7d7191]%s[/color]" % [o["label"], Campaign.ROOMS.get(o["room"], "").to_upper()])
	lines.append("")
	lines.append("[color=#b4a8c6]SUCCESS CRITERIA[/color]")
	for k in m["criteria"]:
		lines.append("[color=#b4a8c6]· %s[/color]" % k)
	if c.mission_log.size() > 0:
		lines.append("")
		for e in c.mission_log.slice(maxi(0, c.mission_log.size() - 3)):
			lines.append("[color=#7d7191]T+%s %s[/color]" % [UI.fmt_time(e["time"]), e["text"]])
	hud.objectives.text = "\n".join(lines)
	var p := c.power_status()
	hud.vitals_panel.visible = true
	var pct: float = c.energy / p["capacity"] * 100.0
	var contact := "OPEN" if c.contact_open() else ("in %d s" % ceili(30.0 - fmod(c.phase_time, 90.0)) if c.phase == "downlink" else "—")
	hud.vitals.text = "[color=#b4a8c6]SPACECRAFT[/color]\nENERGY [color=%s]%d Wh · %d%%[/color]\nGEN %d W · LOAD %d W · NET [color=%s]%+d W[/color]\nSTORED %d / 240 MB · SENT %d / 90 MB\nOBSERVING %s · CONSERVE %s\nCREW %s · CONTACT %s\nFAULT %s" % [
		"#ed7d8d" if pct < 25.0 else "#f3eef8", int(c.energy), int(pct), int(p["generation"]), int(p["load"]),
		"#9cdeb1" if p["net"] >= 0.0 else "#ed7d8d", int(p["net"]), int(c.stored), int(c.transmitted),
		"ON" if c.observing else "OFF", "ON" if c.conserve else "OFF", c.crew_command.to_upper(), contact,
		"[color=#ed7d8d]LAB CIRCUIT[/color]" if c.fault else "none"]
	hud.station_panel.visible = false
	hud.crosshair.visible = not eva
	hud.footer.text = "WASD MOVE · E OPERATE · TAB NEXT TASK · C CREW COMMAND · X CONSERVE · F5 TIME ×4 · V VIEW · M MAP · ESC MENU"
	hud.radar_title.text = "SPACECRAFT · ROOMS"
	var pts := []
	var objs := c.objectives()
	var add := func(pos: Vector3, room: String, hot: bool):
		var offset := pos - player.position
		pts.append({"p": Vector2(offset.x, offset.z).rotated(g.yaw), "c": Color("#eaa665") if hot else Color("#7d7191"),
			"s": 5.0 if hot else 3.0, "ring": not hot, "label": Campaign.ROOMS[room], "dist": offset.length()})
	for room in STATIONS:
		var pos := AIRLOCK_OUTSIDE if eva and room == "airlock" else _station_position(room)
		add.call(pos, room, objs.any(func(o): return o["room"] == room))
	if eva:
		add.call(TELESCOPE_BAY, "exterior", not c.installed)
	hud.radar.points = pts
	hud.radar.range_m = 22.0
	hud.radar.request_redraw()
	hud.tactical_radar.cover_shapes.clear()
	hud.update_tactical(pts, "SPACECRAFT · LIVE TACTICAL MAP", 35.0)
