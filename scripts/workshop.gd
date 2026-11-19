## Single-player workshop and launch pad.
## Walk to the PARTS SHOP kiosk and buy each piece. Machines do the assembly: the robot arm frames the hull and
## bolts every spacecraft module on the jig; the pad crane stacks the core stage, both side boosters, the
## spacecraft and the fairing. Board at the gantry elevator. In launch mode the same pad plays the staged ascent.
class_name Workshop
extends Node3D

const Hardware = preload("res://scripts/industrial_hardware.gd")
const LIVERY := Color("#f6a052")
const WHITE := Color("#eef1f4")
const DARK := Color("#2b3245")
const JIG := Vector3(-16, 0, 0)
const KIOSK := Vector3(-5, 0, 7)
const PAD := Vector3(18, 0, 0)
const YARD := Vector3(18, 0, 16)
const ELEVATOR := Vector3(22.5, 0, 3.5)
const CORE_H := 15.0
const BEATS := [
	[0.0, "COUNTDOWN", "T−5", "Umbilicals retracting · propellant topped off"],
	[5.0, "LIFTOFF", "LIFTOFF", "Core stage and both side boosters at full thrust"],
	[10.5, "STAGING", "BOOSTER SEPARATION", "Side boosters spent · core stage continues"],
	[13.5, "STAGING", "CORE STAGE SEPARATION", "Spacecraft flying free on its own engine"],
	[16.0, "ORBIT", "ORBIT INSERTION", "Solar wings deploying"],
]
const LAUNCH_DURATION := 20.0

var _texture_sky_k := -1.0

var g
var blockers: Array = []
var launch_mode := false
var competitive := false  ## launch sequence reused by the offline competitive mode
var evaluation := {}
var items: Array = []
var budget_left := 0
var stage := "framing"
var stage_t := 0.0
var player: Actor
var craft: Node3D
var craft_holder: Node3D
var craft_parts := {}
var frame_parts: Array = []
var booster: Node3D
var booster_parts := {}
var arm_pivot: Node3D
var arm_rig := {}
var arm_goal := Vector3(-16,4,0)
var arm_tip: Node3D
var hook: Node3D
var cable: MeshInstance3D
var jib_y := 26.0
var sparks: Array = []
var _spark_pool: Array[MeshInstance3D] = []
var _hud_elapsed := 0.1
var env: WorldEnvironment
var pad_steam: CPUParticles3D
var launch_t := 0.0
var side_drop := [Vector3.ZERO, Vector3.ZERO]
var core_drop := Vector3.ZERO
var flames: Array = []
var beat_index := -1
var rng := RandomNumberGenerator.new()


func actor(_i: int) -> Variant:
	return player


func setup(main, design: Dictionary, p_launch := false, p_competitive := false) -> void:
	g = main
	launch_mode = p_launch
	competitive = p_competitive
	name = "Workshop"
	rng.seed = 5
	evaluation = Campaign.evaluate_design(design, g.sp_mission)
	budget_left = evaluation["budget"]
	# The workshop, robotic arm, gantry, terrain, lighting and props are editable.
	var editable: Node3D = preload("res://scenes/levels/WorkshopEnvironment.tscn").instantiate() as Node3D
	add_child(editable)
	env = editable.get_node("WorldEnvironment") as WorldEnvironment
	arm_pivot = editable.get_node("WorkshopBuilding/RobotArmPivot") as Node3D
	arm_tip = editable.get_node("WorkshopBuilding/RobotArmPivot/RobotArmTip") as Node3D
	hook = editable.get_node("LaunchPad/CraneHook") as Node3D
	cable = editable.get_node("LaunchPad/CraneCable") as MeshInstance3D
	arm_pivot.visible = false
	# Replace the legacy three-box kiosk with the premium one (same position and footprint).
	editable.get_node("WorkshopBuilding/PartsShopKiosk").visible = false
	var shop_kiosk: Node3D = preload("res://scripts/shop_kiosk.gd").build()
	shop_kiosk.position = KIOSK
	add_child(shop_kiosk)
	arm_rig = {"base": Vector3(-16,2,-5.5), "upper": Hardware.link(Color("#bb793e"),.45,7.0), "lower": Hardware.link(Color("#bbc1bd"),.35,7.0), "elbow": Hardware.joint(.6), "tip": Hardware.tool()}
	for key in ["upper","lower","elbow","tip"]:
		add_child(arm_rig[key])
	_detail_crane(editable)
	preload("res://scripts/model_detail.gd").surroundings(self, KIOSK)
	preload("res://scripts/model_detail.gd").surroundings(self, PAD)
	preload("res://scripts/model_detail.gd").batch(editable.get_node("LaunchPad/CraneTower"), [], 160.0)
	blockers.clear()
	for marker in editable.get_node("CollisionFootprints").get_children():
		var footprint: Vector2 = marker.get_meta("footprint", Vector2.ZERO)
		var pt: Vector3 = (marker as Node3D).position
		blockers.append(Rect2(pt.x - footprint.x * 0.5, pt.z - footprint.y * 0.5, footprint.x, footprint.y))
	_build_booster()
	_build_craft()
	_items()
	if launch_mode:
		_assembled()
		stage = "launch"
	else:
		var s = Sim.SPECIALISTS[g.opts["selected"]]
		player = Actor.new()
		player.setup(s["model"], g.opts["selected"], Sim.role_color(g.opts["selected"]))
		player.position = Vector3(-4, 0, 16)
		add_child(player)
		g.yaw = 0.3
		g.pitch = -0.2
		g.first_person = false


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------
func _ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	add_child(Gfx.mesh(plane, Gfx.terrain_mat(Color("#6f8a5c"))))
	var ocean := PlaneMesh.new()
	ocean.size = Vector2(1400, 500)
	var o := Gfx.mesh(ocean, Gfx.mat(Color("#3f78b5"), 0.3))
	o.position = Vector3(0, 0.02, -480)
	add_child(o)
	for i in 40:
		var ang := rng.randf() * TAU
		var d := rng.randf_range(90, 300)
		var r := rng.randf_range(4, 14)
		var hill := Gfx.rock(r, Color("#5e7a4c"), rng, 0.45)
		hill.position = Vector3(cos(ang) * d, 0, absf(sin(ang)) * d + 40)
		add_child(hill)
	var road := Gfx.box(Vector3(40, 0.04, 5), Color("#55596a"), Vector3(2, 0.02, 9))
	add_child(road)


func _workshop_building() -> void:
	var floor_box := Gfx.box(Vector3(30, 0.3, 22), Color("#8b8f9c"), Vector3(-16, 0.15, 0))
	add_child(floor_box)
	for x in [-30.5, -1.5]:
		for z in [-10.5, 10.5]:
			add_child(Gfx.box(Vector3(0.8, 12, 0.8), DARK, Vector3(x, 6, z)))
	var roof := Gfx.box(Vector3(31, 0.6, 23), Color("#3a4057"), Vector3(-16, 12.3, 0))
	add_child(roof)
	add_child(Gfx.box(Vector3(30, 11.5, 0.4), Color("#4a5070"), Vector3(-16, 6, -11)))
	var sign := Gfx.label("WORKSHOP", Color("#ffd27a"), 140)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.position = Vector3(-16, 13.6, 11.6)
	add_child(sign)
	# Jig cradle.
	add_child(Gfx.box(Vector3(9, 0.8, 3.2), Color("#565c7a"), JIG + Vector3(0, 0.7, 0)))
	for x in [-3.0, 3.0]:
		add_child(Gfx.box(Vector3(0.9, 1.6, 2.4), Color("#f6d04d"), JIG + Vector3(x, 1.5, 0)))
	var jl := Gfx.label("ASSEMBLY JIG", Color("#e9e4f2"), 40)
	jl.position = JIG + Vector3(0, 7.2, 0)
	add_child(jl)
	# Robot arm.
	var base := Gfx.cyl(0.9, 1.2, Color("#f6a052"), JIG + Vector3(0, 0.6, -5.5), 16)
	add_child(base)
	arm_pivot = Node3D.new()
	arm_pivot.position = JIG + Vector3(0, 1.4, -5.5)
	add_child(arm_pivot)
	var upper := Gfx.box(Vector3(0.5, 0.5, 5.0), Color("#f6a052"), Vector3(0, 0, -2.5))
	arm_pivot.add_child(upper)
	arm_tip = Node3D.new()
	arm_tip.position = Vector3(0, 0, -5.0)
	arm_pivot.add_child(arm_tip)
	arm_tip.add_child(Gfx.sphere(0.45, DARK, Vector3.ZERO, 0.0, 12))
	arm_tip.add_child(Gfx.box(Vector3(0.9, 0.3, 0.3), DARK, Vector3(0, -0.35, 0)))
	# Parts shop kiosk (same layout as the web build).
	var k := preload("res://scripts/shop_kiosk.gd").build()
	k.position = KIOSK
	add_child(k)


func _pad() -> void:
	var pad := Gfx.disc(11.0, Color("#55596a"), 0.4)
	pad.position = PAD
	add_child(pad)
	add_child(Gfx.box(Vector3(6, 1.2, 6), Color("#3d4152"), PAD + Vector3(0, 0.9, 0)))
	# Red service tower with crane jib.
	var red := Color("#d2513d")
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			add_child(Gfx.box(Vector3(0.35, 30, 0.35), red, PAD + Vector3(5.5 + dx, 15, 3.5 + dz)))
	for y in range(2, 30, 3):
		add_child(Gfx.box(Vector3(2.4, 0.2, 2.4), red, PAD + Vector3(5.5, y, 3.5)))
	var jib := Gfx.box(Vector3(10, 0.6, 0.6), Color("#f6d04d"), PAD + Vector3(1.5, jib_y + 1.0, 3.5))
	add_child(jib)
	hook = Node3D.new()
	hook.position = PAD + Vector3(0, jib_y - 4.0, 3.5)
	hook.add_child(Gfx.box(Vector3(0.8, 0.5, 0.8), Color("#f6d04d")))
	add_child(hook)
	cable = Gfx.cyl(0.05, 1.0, DARK, Vector3.ZERO, 6)
	add_child(cable)
	var el := Gfx.box(Vector3(2, 0.2, 2), Color("#9cdeb1"), ELEVATOR + Vector3(0, 0.15, 0))
	add_child(el)
	var ell := Gfx.label("GANTRY ELEVATOR · BOARD", Color("#9cdeb1"), 36)
	ell.position = ELEVATOR + Vector3(0, 3.2, 0)
	add_child(ell)
	var yard := Gfx.box(Vector3(14, 0.2, 6), Color("#55596a"), YARD + Vector3(0, 0.1, 0))
	add_child(yard)
	var yl := Gfx.label("STAGE DELIVERY YARD", Color("#e9e4f2"), 36)
	yl.position = YARD + Vector3(0, 3.0, 0)
	add_child(yl)


func _build_booster() -> void:
	booster = Node3D.new()
	booster.position = PAD + Vector3(0, 1.5, 0)
	add_child(booster)
	var core := Hardware.booster(1.55, CORE_H, "CORE")
	# Core carries the payload adapter instead of an ogive.
	core.get_child(1).queue_free()
	booster.add_child(core)
	booster_parts["core"] = core
	for side in [-1,1]:
		var sb := Hardware.booster(.8, 10.0, "L" if side < 0 else "R")
		sb.position = Vector3(side*2.45,0,0)
		booster.add_child(sb)
		booster_parts["side_l" if side < 0 else "side_r"] = sb
	var fairing := Node3D.new()
	for side in [-1, 1]:
		var half := CSGCombiner3D.new()
		var c := CSGCylinder3D.new()
		c.radius = 1.7
		c.height = 6.5
		c.sides = 64
		c.position.y = 3.25
		c.material = Gfx.mat(WHITE, 0.6)
		half.add_child(c)
		var cone := CSGCylinder3D.new()
		cone.radius = 1.7
		cone.height = 2.6
		cone.cone = true
		cone.sides = 64
		cone.position.y = 7.8
		cone.material = Gfx.mat(WHITE, 0.6)
		half.add_child(cone)
		var cut := CSGBox3D.new()
		cut.size = Vector3(3.6, 12, 3.6)
		cut.position = Vector3(-side * 1.8, 5, 0)
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		half.add_child(cut)
		var band := CSGCylinder3D.new()
		band.radius = 1.72
		band.height = 0.4
		band.position.y = 1.0
		band.material = Gfx.mat(LIVERY, 0.6)
		half.add_child(band)
		half.name = "half_%d" % side
		fairing.add_child(half)
	fairing.position = Vector3(0, CORE_H, 0)
	booster.add_child(fairing)
	booster_parts["fairing"] = fairing


## The spacecraft is built along +Y; on the jig it lies on its side.
func _build_craft() -> void:
	craft_holder = Node3D.new()
	add_child(craft_holder)
	craft = Node3D.new()
	craft_holder.add_child(craft)
	var parts: Dictionary = evaluation["parts"]
	# Structure framed by the robots.
	var engine := Node3D.new()
	engine.add_child(Gfx.cyl(0.55, 0.9, DARK, Vector3(0, 0.45, 0), 16, 0.35))
	engine.add_child(Gfx.cyl(0.9, 0.7, Color("#c9ced8"), Vector3(0, 1.2, 0), 16))
	var tank := Gfx.cyl(1.0, 1.4, WHITE, Vector3(0, 2.25, 0), 20)
	var hull := Node3D.new()
	hull.add_child(Gfx.cyl(1.05, 2.4, WHITE, Vector3(0, 4.15, 0), 20))
	hull.add_child(Gfx.cyl(1.07, 0.35, LIVERY, Vector3(0, 3.2, 0), 20))
	hull.add_child(Gfx.cyl(1.07, 0.35, LIVERY, Vector3(0, 5.0, 0), 20))
	var nose := Node3D.new()
	nose.add_child(Gfx.cyl(0.25, 1.4, WHITE, Vector3(0, 6.05, 0), 20, 1.05))
	nose.get_child(0).rotation.x = PI
	nose.add_child(Gfx.box(Vector3(0.9, 0.35, 0.2), Color("#7fd8e6"), Vector3(0, 5.95, 0.82), 0.5))
	for n in [engine, tank, hull, nose]:
		craft.add_child(n)
		frame_parts.append(n)
	# Equipment chosen on the design screen.
	var bat := Node3D.new()
	var big: bool = parts["battery"]["id"] == "reserve"
	bat.add_child(Gfx.box(Vector3(0.9, 1.2 if big else 0.8, 0.7), Color("#3b4058"), Vector3(0, 0, 0)))
	bat.add_child(Gfx.box(Vector3(0.92, 0.1, 0.5), Color("#7dffb5"), Vector3(0, 0.35, 0), 1.0))
	bat.position = Vector3(1.25, 2.3, 0)
	craft.add_child(bat)
	craft_parts["battery"] = bat
	var arr := Node3D.new()
	var span: float = 4.2 if parts["array"]["id"] == "expanded" else 3.0
	for side in [-1, 1]:
		var hinge := Node3D.new()
		hinge.name = "hinge_%d" % side
		hinge.position = Vector3(side * 1.05, 4.0, 0)
		var panel := Gfx.box(Vector3(span, 1.4, 0.08), Color("#2c5581"), Vector3(side * span * 0.5, 0, 0), 0.15)
		hinge.add_child(panel)
		for k in 3:
			hinge.add_child(Gfx.box(Vector3(0.05, 1.42, 0.1), Color("#c9ced8"), Vector3(side * (k + 1) * span / 4.0, 0, 0)))
		arr.add_child(hinge)
	craft.add_child(arr)
	craft_parts["array"] = arr
	var inst := Node3D.new()
	var spec: bool = parts["instrument"]["id"] == "spectrometer"
	inst.add_child(Gfx.cyl(0.35 if not spec else 0.45, 0.9 if not spec else 1.2, Color("#d5dbe4"), Vector3.ZERO, 16, 0.45 if not spec else 0.55))
	inst.add_child(Gfx.cyl(0.25, 0.1, Color("#8ff0d0"), Vector3(0, -0.5, 0), 16))
	inst.get_child(1).material_override = Gfx.mat(Color("#8ff0d0"), 0.2, 1.5)
	inst.rotation.x = PI / 2
	inst.position = Vector3(0, 4.3, 1.4)
	craft.add_child(inst)
	craft_parts["instrument"] = inst
	var radio := Node3D.new()
	var hg: bool = parts["radio"]["id"] == "highgain"
	radio.add_child(Gfx.cyl(0.06, 1.0, Color("#d9dee6"), Vector3(0, 0.5, 0), 8))
	var dish := Gfx.cyl(0.75 if hg else 0.5, 0.12, Color("#d9dee6"), Vector3(0, 1.05, 0), 20, 0.15)
	radio.add_child(dish)
	radio.position = Vector3(-0.9, 5.0, -0.4)
	radio.rotation.z = 0.4
	craft.add_child(radio)
	craft_parts["radio"] = radio
	for n in craft_parts.values():
		n.visible = false
	for n in frame_parts:
		n.visible = false
	_fold_wings(1.0)
	_place_on_jig()


func _fold_wings(k: float) -> void:
	# k = 1 folded against the hull, 0 fully deployed.
	var arr: Node3D = craft_parts["array"]
	for h in arr.get_children():
		var side := -1.0 if String(h.name).ends_with("-1") else 1.0
		h.rotation.y = side * k * PI * 0.5 * -1.0


func _place_on_jig() -> void:
	craft_holder.position = JIG + Vector3(-3.4, 2.5, 0)
	craft_holder.rotation = Vector3(0, 0, -PI / 2)


func _items() -> void:
	var parts: Dictionary = evaluation["parts"]
	for key in ["battery", "array", "instrument", "radio"]:
		items.append({"key": key, "kind": "craft", "name": parts[key]["name"], "cost": parts[key]["cost"], "part": parts[key], "state": "shop", "t": 0.0})
	for l in Campaign.LAUNCHER:
		items.append({"key": l["id"], "kind": "booster", "name": l["name"], "cost": 0, "part": l, "state": "shop", "t": 0.0})
	for it in items:
		var crate := Node3D.new()
		crate.add_child(Gfx.box(Vector3(1.0, 0.8, 0.8), Color("#e9e4f2")))
		crate.add_child(Gfx.box(Vector3(1.02, 0.15, 0.82), LIVERY if it["kind"] == "craft" else Color("#9cdeb1"), Vector3(0, 0.2, 0)))
		add_child(crate)
		it["crate"] = crate
		crate.visible = false
	for key in booster_parts:
		booster_parts[key].visible = false


func _assembled() -> void:
	for n in frame_parts:
		n.visible = true
	for n in craft_parts.values():
		n.visible = true
	for n in booster_parts.values():
		n.visible = true
	for it in items:
		it["state"] = "done"
	_stack_craft(1.0)


func _stack_craft(k: float) -> void:
	var top := booster.position + Vector3(0, CORE_H + 0.3, 0)
	var from := JIG + Vector3(0, 2.5, 0)
	var e := smoothstep(0.0, 1.0, k)
	craft_holder.rotation = Vector3(0, 0, -PI / 2 * (1.0 - smoothstep(0.0, 0.4, k)))
	var mid := from + Vector3(0, 20, 0)
	if k < 0.4:
		craft_holder.position = from.lerp(mid, k / 0.4)
	else:
		var q := (k - 0.4) / 0.6
		var above := top + Vector3(0, 8, 0)
		craft_holder.position = mid.lerp(above, smoothstep(0.0, 1.0, minf(1.0, q * 1.4))).lerp(top, maxf(0.0, (q - 0.6) / 0.4))
	if e >= 1.0:
		craft_holder.position = top


# ---------------------------------------------------------------------------
# Gameplay
# ---------------------------------------------------------------------------
func collide(p: Vector3) -> Vector3:
	# Read collision rectangles from the editor-visible footprints.
	var rects := blockers
	for r in rects:
		var e: Rect2 = (r as Rect2).grow(0.6)
		if e.has_point(Vector2(p.x, p.z)):
			var d := [p.x - e.position.x, e.end.x - p.x, p.z - e.position.y, e.end.y - p.z]
			var m: float = d.min()
			if m == d[0]: p.x = e.position.x
			elif m == d[1]: p.x = e.end.x
			elif m == d[2]: p.z = e.position.y
			else: p.z = e.end.y
	return p


func _next_shop_item() -> Variant:
	for it in items:
		if it["state"] == "shop":
			if it["key"] == "fairing" and not (stage == "fairing"):
				return null
			return it
	return null


func tick(dt: float) -> void:
	if g.sim == null and g.pressed(KEY_M):
		g.hud.toggle_tactical()
	_hud_elapsed += dt
	if launch_mode:
		_launch(dt)
		return
	var speed: float = g.drive(player, dt)
	g.follow_cam(player)
	player.animate(dt, speed)
	stage_t += dt
	_machines(dt)
	_interact()
	for i in range(sparks.size() - 1, -1, -1):
		var s: Dictionary = sparks[i]
		s["life"] -= dt
		s["node"].position += s["v"] * dt
		s["v"].y -= 9.0 * dt
		if s["life"] <= 0.0:
			s["node"].visible = false
			_spark_pool.append(s["node"])
			sparks.remove_at(i)


func _interact() -> void:
	var p := player.position
	var it = _next_shop_item()
	if g.flat_dist(p, KIOSK) < 4.5 and it != null:
		var part: Dictionary = it["part"]
		var detail := ""
		if it["kind"] == "craft":
			detail = "%d credits · %d kg%s%s · budget left %d" % [it["cost"], part["mass"], (" · %d W" % part["watts"]) if part.has("watts") else "", (" · %d Wh" % part["wh"]) if part.has("wh") else "", budget_left]
		else:
			detail = "Program-supplied launcher stage · " + part["note"]
		g.hud.set_prompt("E · BUY %s" % it["name"].to_upper(), detail)
		if g.pressed(KEY_E):
			if budget_left < it["cost"]:
				g.hud.toast("Not enough mission credits.")
			else:
				budget_left -= it["cost"]
				it["state"] = "queued"
				g.sfx("reload_click", -4)
				g.hud.toast("Ordered %s — the machines take it from here." % it["name"], 2.5)
		return
	if stage == "ready" and g.flat_dist(p, ELEVATOR) < 3.0:
		g.hud.set_prompt("E · BOARD THE SPACECRAFT", "Ride the gantry elevator to the crew hatch")
		if g.pressed(KEY_E):
			g.board_ship()
		return
	if stage == "ready":
		g.hud.set_prompt("VEHICLE STACKED", "Walk to the green gantry elevator beside the pad")
	elif it != null:
		g.hud.set_prompt("GO TO THE PARTS SHOP", "Next order: %s · %d m" % [it["name"], int(g.flat_dist(p, KIOSK))])
	else:
		g.hud.set_prompt("MACHINES AT WORK", _stage_text())


func _stage_text() -> String:
	match stage:
		"framing": return "Robots are framing the hull and propulsion modules"
		"stacking": return "Crane raising the spacecraft onto the core stage"
		"fairing": return "Order the payload fairing at the parts shop"
		"closing": return "Fairing halves closing around the spacecraft"
	for it in items:
		if it["state"] in ["deliver", "bolt"]:
			return ("Robot arm" if it["kind"] == "craft" else "Pad crane") + " · " + it["name"]
	return "Waiting for the next order"


func _spark(at: Vector3, col := Color("#ffd27a")) -> void:
	var s: MeshInstance3D
	if _spark_pool.is_empty():
		s = Gfx.sphere(0.08, col, at, 3.0, 4)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
	else:
		s = _spark_pool.pop_back()
	s.position = at
	s.visible = true
	s.material_override = Gfx.unshaded(col)
	sparks.append({"node": s, "life": 0.5, "v": Vector3(rng.randf_range(-3, 3), rng.randf_range(1, 4), rng.randf_range(-3, 3))})


func _mount_world(it: Dictionary) -> Vector3:
	if it["kind"] == "craft":
		return craft_parts[it["key"]].global_position
	var bp: Node3D = booster_parts[it["key"]]
	return booster.global_position + bp.position + Vector3(0, 6 if it["key"] != "fairing" else 4, 0)


func _machines(dt: float) -> void:
	match stage:
		"framing":
			var per := 0.75
			for i in frame_parts.size():
				var k := (stage_t - i * per) / per
				var n: Node3D = frame_parts[i]
				n.visible = k > 0.0
				if k > 0.0 and k < 1.0 and rng.randf() < dt * 25.0:
					_spark(n.global_position)
			_pose_robot(craft_holder.position + Vector3(sin(stage_t*2.0)*2.0,1.5,0), dt)
			if stage_t >= per * frame_parts.size():
				stage = "shopping"
				stage_t = 0.0
				g.hud.toast("Hull framed. Buy the modules at the parts shop.", 3.0)
			return
		"stacking":
			_stack_craft(clampf(stage_t / 6.0, 0.0, 1.0))
			_hook_to(craft_holder.position + Vector3(0, 7, 0))
			if stage_t >= 6.0:
				stage = "fairing"
				stage_t = 0.0
				g.hud.toast("Spacecraft stacked. Order the payload fairing.", 3.0)
			return
		"closing":
			var fair: Node3D = booster_parts["fairing"]
			fair.visible = true
			var k := clampf(stage_t / 2.5, 0.0, 1.0)
			for h in fair.get_children():
				var side := -1.0 if String(h.name).ends_with("-1") else 1.0
				h.position.x = side * (1.0 - smoothstep(0.0, 1.0, k)) * 3.0
			if k >= 1.0:
				stage = "ready"
				stage_t = 0.0
				g.hud.show_banner("VEHICLE READY", "Board at the gantry elevator", 3.0)
			return
	# Process the oldest order.
	for it in items:
		if it["state"] == "queued":
			it["state"] = "deliver"
			it["t"] = 0.0
			var crate: Node3D = it["crate"]
			crate.visible = true
			crate.global_position = KIOSK + Vector3(0, 1.3, 0) if it["kind"] == "craft" else YARD + Vector3(0, 0.6, 0)
			it["from"] = crate.global_position
			if it["kind"] == "booster":
				var bp: Node3D = booster_parts[it["key"]]
				bp.visible = true
				it["home"] = bp.position
				if it["key"] == "fairing":
					for h in bp.get_children():
						h.position.x = (-1.0 if String(h.name).ends_with("-1") else 1.0) * 3.0
			break
		if it["state"] in ["deliver", "bolt"]:
			_work(it, dt)
			break
	if stage == "shopping" and items.all(func(x): return x["state"] == "done" or x["key"] == "fairing"):
		stage = "stacking"
		stage_t = 0.0
	if stage == "fairing":
		var f = items.filter(func(x): return x["key"] == "fairing")[0]
		if f["state"] == "done":
			stage = "closing"
			stage_t = 0.0


func _hook_to(target: Vector3) -> void:
	hook.position = target
	var top := Vector3(hook.position.x, jib_y + 0.7, hook.position.z)
	var clen := top.distance_to(hook.position)
	cable.position = (top + hook.position) * 0.5
	cable.scale = Vector3(1, maxf(0.01, clen), 1)


func _work(it: Dictionary, dt: float) -> void:
	it["t"] += dt
	var crate: Node3D = it["crate"]
	if it["kind"] == "craft":
		var target := _mount_world(it)
		if it["state"] == "deliver":
			var k := smoothstep(0.0,1.0,minf(1.0, it["t"] / 1.6))
			crate.global_position = (it["from"] as Vector3).lerp(target, k) + Vector3(0, sin(k * PI) * 4.0, 0)
			_pose_robot(crate.global_position, dt)
			if k >= 1.0:
				it["state"] = "bolt"
				it["t"] = 0.0
		else:
			_pose_robot(target, dt)
			if rng.randf() < dt * 30.0:
				_spark(target)
			if it["t"] >= 1.3:
				it["state"] = "done"
				crate.visible = false
				craft_parts[it["key"]].visible = true
				g.sfx("capture_tick", -6)
	else:
		var bp: Node3D = booster_parts[it["key"]]
		var home: Vector3 = it["home"]
		var yard_local: Vector3 = YARD - booster.position + Vector3(0, 0.3, 0)
		crate.visible = false
		if it["state"] == "deliver":
			var k := minf(1.0, it["t"] / 3.0)
			var start := Vector3(home.x, yard_local.y, yard_local.z)
			bp.position = start.lerp(home, smoothstep(0.0, 1.0, k)) + Vector3(0, sin(k * PI) * 7.0, 0)
			_hook_to(booster.position + bp.position + Vector3(0, 15.5 if it["key"] == "core" else (12.7 if it["key"] != "fairing" else 9.5), 0))
			if k >= 1.0:
				it["state"] = "bolt"
				it["t"] = 0.0
		else:
			bp.position = home
			if rng.randf() < dt * 20.0:
				_spark(booster.position + home + Vector3(0, 0.6, 0), Color("#9cdeb1"))
			if it["t"] >= 1.0:
				it["state"] = "done"
				g.sfx("capture_tick", -6)
				_hook_to(PAD + Vector3(0, jib_y - 4.0, 3.5))


# ---------------------------------------------------------------------------
# Launch cinematic
# ---------------------------------------------------------------------------
func _flame(r: float, length: float) -> Node3D:
	var fx := preload("res://scripts/exhaust_fx.gd").create(r, length, true)
	fx.rotation.x = PI / 2.0
	return fx


func _launch(dt: float) -> void:
	launch_t += dt
	var t := launch_t
	var cam: Camera3D = g.cam
	if flames.is_empty():
		pad_steam = ExhaustFX.pad_cloud()
		pad_steam.position = PAD + Vector3(0,.8,0)
		add_child(pad_steam)
		var cf := _flame(1.05, 12.0)
		cf.position.y = -1.65
		booster_parts["core"].add_child(cf)
		flames.append(cf)
		for key in ["side_l", "side_r"]:
			var f := _flame(0.58, 9.0)
			f.position.y = -1.65
			booster_parts[key].add_child(f)
			flames.append(f)
		var ef := _flame(0.5, 3.0)
		craft.add_child(ef)
		flames.append(ef)
	for i in BEATS.size():
		if t >= BEATS[i][0] and beat_index < i:
			beat_index = i
			var title: String = BEATS[i][2]
			if i == 0:
				title = "T−5"
			g.hud.show_banner(title, BEATS[i][3], 3.0)
	pad_steam.emitting = t >= 4.6 and t < 7.5
	var lit := t >= 5.0
	for i in 3:
		flames[i].visible = t >= 4.65 and (i == 0 or t < 10.5) and t < 13.5
	flames[3].visible = t >= 13.5 and t < 16.0
	for f in flames:
		f.intensity = smoothstep(4.65,5.1,t) * (0.95 + sin(launch_t * 29.0) * 0.04)
	if t < 5.0:
		g.hud.show_banner("T−%d" % maxi(1, 5 - int(t)), "Umbilicals retracting · propellant topped off", 0.6)
	var alt := 0.0
	if lit:
		var x := t - 5.0
		alt = 2.0 * x * x + 3.0 * x
	booster.position.y = 1.5 + alt
	craft_holder.position.y = booster.position.y + CORE_H + 0.3 - 1.5 + 1.5
	if t >= 10.5:
		for i in 2:
			var key := "side_l" if i == 0 else "side_r"
			var sb: Node3D = booster_parts[key]
			if sb.get_parent() == booster:
				var gp := sb.global_position
				booster.remove_child(sb)
				add_child(sb)
				sb.global_position = gp
				side_drop[i] = Vector3((-1 if i == 0 else 1) * 6.0, 6.0, 0)
			side_drop[i].y -= 14.0 * dt
			sb.position += side_drop[i] * dt
			sb.rotation.z += (1 if i == 0 else -1) * 1.2 * dt
	if t >= 13.5:
		# Core stage falls away; the spacecraft continues on its own engine.
		var fair: Node3D = booster_parts["fairing"]
		for h in fair.get_children():
			var side := -1.0 if String(h.name).ends_with("-1") else 1.0
			h.position.x += side * dt * 6.0
			h.rotation.z += side * dt * 0.8
		core_drop.y -= 10.0 * dt
		booster.position.y = 1.5 + 2.0 * 8.5 * 8.5 + 3.0 * 8.5 + core_drop.y * (t - 13.5)
		craft_holder.position.y = 1.5 + 2.0 * 8.5 * 8.5 + 3.0 * 8.5 + CORE_H + 0.3 + (t - 13.5) * 40.0
	if t >= 16.0:
		_fold_wings(1.0 - clampf((t - 16.0) / 2.5, 0.0, 1.0))
	var sky_k := clampf((craft_holder.position.y - 60.0) / 300.0, 0.0, 1.0)
	if absf(sky_k - _texture_sky_k) > 0.01 or sky_k != _texture_sky_k and sky_k in [0.0, 1.0]:
		_texture_sky_k = sky_k
		var sm := env.environment.sky.sky_material as ShaderMaterial
		sm.set_shader_parameter("atmosphere", 1.0 - sky_k)
		sm.set_shader_parameter("sky_top_color", Color("#7fb2e2").lerp(Color("#050914"), sky_k))
		sm.set_shader_parameter("sky_horizon_color", Color("#cfe2f2").lerp(Color("#101a30"), sky_k))
	env.environment.fog_enabled = sky_k < 0.5
	var focus := craft_holder.global_position
	if t < 5.0:
		cam.position = PAD + Vector3(-30, 8, 38)
		cam.look_at(PAD + Vector3(0, 11, 0), Vector3.UP)
	elif t < 13.5:
		cam.position = PAD + Vector3(-30, 8 + alt * 0.6, 38)
		cam.look_at(booster.global_position + Vector3(0, 9, 0), Vector3.UP)
	else:
		cam.position = focus + Vector3(-12, 4, 16)
		cam.look_at(focus + Vector3(0, 3, 0), Vector3.UP)
	if t >= LAUNCH_DURATION:
		launch_mode = false
		if competitive:
			g.competitive_launch_finished()
		else:
			g.launch_finished()


func hud_update(hud: Hud) -> void:
	if competitive:
		hud.clock.text = "T%s%02d" % ["−" if launch_t < 5.0 else "+", absi(int(launch_t - 5.0))]
		hud.set_prompt("")
		hud.crosshair.visible = false
		return
	if _hud_elapsed >= 0.1:
		_hud_elapsed = fmod(_hud_elapsed, 0.1)
		hud.set_sp_steps(["WORKSHOP", "STACK", "BOARD", "LAUNCH", "ORBIT", "RETURN"], 3 if launch_mode else (2 if stage == "ready" else (1 if stage in ["stacking", "fairing", "closing"] else 0)))
		hud.clock.text = ("T%s%02d" % ["−" if launch_t < 5.0 else "+", absi(int(launch_t - 5.0))]) if launch_mode else "BUDGET %d" % budget_left
		if launch_mode:
			hud.set_prompt("")
		var m := Campaign.mission(g.sp_mission)
		hud.title.text = "LAUNCH." if launch_mode else "BUILD YOUR SPACECRAFT."
		hud.subtitle.text = "MISSION %s · %s" % [m["number"], m["name"].to_upper()]
		var lines := PackedStringArray()
		lines.append("[color=#eaa665][b]BUILD BAY · MACHINE ASSEMBLY[/b][/color]")
		lines.append("[color=#b4a8c6]Buy each piece at the parts shop. The robot arm and pad crane assemble it.[/color]")
		lines.append("%s Hull frame & propulsion [color=#7d7191]ROBOTS[/color]" % ("[color=#9cdeb1]✓[/color]" if stage != "framing" else "◐"))
		for it in items:
			var mark: String = {"shop": "○", "queued": "[color=#eaa665]…[/color]", "deliver": "[color=#f7ce59]◐[/color]", "bolt": "[color=#f7ce59]◐[/color]", "done": "[color=#9cdeb1]✓[/color]"}[it["state"]]
			lines.append("%s %s [color=#7d7191]%s[/color]" % [mark, it["name"], ("%d CR" % it["cost"]) if it["kind"] == "craft" else "LAUNCHER"])
		lines.append("%s Stack spacecraft on core [color=#7d7191]CRANE[/color]" % ("[color=#9cdeb1]✓[/color]" if stage in ["fairing", "closing", "ready"] else "○"))
		hud.objectives.text = "\n".join(lines)
		hud.vitals_panel.visible = true
		hud.vitals.text = "[color=#b4a8c6]LIVE READINESS[/color]\nWet mass %d / 850 kg\nBudget %d / %d credits\nScience load %d W\nSolar generation %d W\nEclipse endurance %d s" % [
			evaluation["mass"], evaluation["cost"], evaluation["budget"], evaluation["load"], evaluation["parts"]["array"]["watts"], int(evaluation["endurance"])]
		hud.station_panel.visible = false
		hud.crosshair.visible = false
		hud.footer.text = "WASD MOVE · SHIFT SPRINT · V VIEW · E BUY / BOARD · M MAP · ESC MENU"
	hud.radar_title.text = "LAUNCH COMPLEX"
	if player:
		var pts := []
		for marker in [[KIOSK, Color("#ffd27a"), "SHOP"], [JIG, Color("#f6a052"), "BUILD BAY"],
				[PAD, Color("#ece7f4"), "PAD"], [ELEVATOR, Color("#9cdeb1"), "ELEVATOR"],
				[YARD, Color("#b4a8c6"), "YARD"]]:
			var offset: Vector3 = marker[0] - player.position
			pts.append({"p": Vector2(offset.x, offset.z).rotated(g.yaw), "c": marker[1], "s": 5.0,
				"ring": true, "label": marker[2], "dist": offset.length()})
		hud.radar.points = pts
		hud.radar.range_m = 45.0
		hud.radar.request_redraw()
		hud.tactical_radar.cover_shapes.clear()
		hud.update_tactical(pts, "LAUNCH COMPLEX · LIVE TACTICAL MAP", 45.0)


func _pose_robot(target: Vector3, dt: float) -> void:
	arm_goal = arm_goal.lerp(target, 1.0-exp(-dt*5.0))
	var base: Vector3 = arm_rig["base"]
	var direction := (arm_goal-base).normalized()
	var distance := clampf(base.distance_to(arm_goal),.2,13.8)
	var pole := Vector3.UP - direction * direction.dot(Vector3.UP)
	if pole.length_squared() < .001:
		pole = Vector3.RIGHT
	var elbow := base + direction*distance*.5 + pole.normalized()*sqrt(49.0-distance*distance*.25)
	var tip := base+direction*distance
	for pair in [["upper",base,elbow],["lower",elbow,tip]]:
		var link: Node3D = arm_rig[pair[0]]
		var start: Vector3 = pair[1]
		var end: Vector3 = pair[2]
		link.look_at_from_position(start,end,Vector3.RIGHT if absf((end-start).normalized().y)>.99 else Vector3.UP)
		link.scale.z = start.distance_to(end)/7.0
	(arm_rig["elbow"] as Node3D).position = elbow
	(arm_rig["tip"] as Node3D).position = tip


func _detail_crane(editable: Node3D) -> void:
	var tower := editable.get_node("LaunchPad/CraneTower")
	for y in range(2,29,3):
		for z in [2.5,4.5]:
			_brace(tower,Vector3(22.5,y,z),Vector3(24.5,y+3,z),.07)
			_brace(tower,Vector3(24.5,y,z),Vector3(22.5,y+3,z),.07)
		for x in [22.5,24.5]:
			_brace(tower,Vector3(x,y,2.5),Vector3(x,y+3,4.5),.07)
	# A bridge spans the actual delivery route; the hoist travels along it.
	for x in [16.5,19.5]:
		_brace(tower,Vector3(x,27,-2),Vector3(x,27,19),.18)
	for z in range(-2,20,2):
		_brace(tower,Vector3(16.5,27,z),Vector3(19.5,27,z),.12)
	for child in hook.get_children():
		child.queue_free()
	for x in [-.28,.28]:
		var wheel := Hardware.cylinder(hook,.32,.16,Vector3(x,.25,0),Color("#59656d"))
		wheel.rotation.z = PI/2
	hook.add_child(Gfx.box(Vector3(.9,.55,.65),Color("#be8c36")))
	var sling := TorusMesh.new()
	sling.inner_radius = .17
	sling.outer_radius = .25
	var ring := Hardware.part(hook,sling,Vector3(0,-.5,0),Color("#5e6870"))
	ring.rotation.x = PI/2


func _brace(parent: Node, a: Vector3, b: Vector3, radius: float) -> void:
	var rod := Gfx.cyl(radius,a.distance_to(b),Color("#656e73"),(a+b)*.5,8)
	parent.add_child(rod)
	rod.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
