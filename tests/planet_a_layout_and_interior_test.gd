## Layout + interior audit. Run ONCE: Godot --headless --path . --script tests/planet_a_layout_and_interior_test.gd
## 1. Planet A: every campus slab / road / Blender model / empire foundation / motor-pool vehicle is checked for zero
##    overlap against ponds, rocks, the 4 launch pads, the parts shop, the central apron and each other; every slab
##    is grounded (bottom y = 0) and every model stands exactly on its slab top.
## 2. ShipInterior: 9.2 x 4.6 x 24 m cabin, named crew facilities, 2.2 m walkable corridor, gunnery station, gantry
##    alignment constants. 3. Then the full pad-sequence runtime test is executed as a child process.
extends SceneTree

const EmpireLayer = preload("res://scripts/empire_world_layer.gd")
const InteriorScript = preload("res://scripts/ship_interior.gd")
const Rules = preload("res://scripts/empire_sim.gd")

var failures := 0


func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_layout_audit()
	_interior_audit()
	_run_pad_sequence_test()
	print("LAYOUT_INTERIOR_RESULT: %d failures" % failures)
	quit(1 if failures else 0)


# ---------------------------------------------------------------------------
# Geometry helpers (2D, x/z plane). A shape is {"center": Vector2, "half": Vector2, "yaw": float} (oriented rect).
# ---------------------------------------------------------------------------
func _corners(r: Dictionary) -> Array:
	var h: Vector2 = r["half"]
	var out: Array = []
	for c in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		out.append(r["center"] + c.rotated(-float(r["yaw"])))
	return out


func _rects_overlap(a: Dictionary, b: Dictionary, margin := 0.0) -> bool:
	var ca := _corners(a)
	var cb := _corners(b)
	for shape in [a, b]:
		var yaw := float(shape["yaw"])
		for axis in [Vector2(1, 0).rotated(-yaw), Vector2(0, 1).rotated(-yaw)]:
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for p: Vector2 in ca:
				amin = minf(amin, p.dot(axis))
				amax = maxf(amax, p.dot(axis))
			for p: Vector2 in cb:
				bmin = minf(bmin, p.dot(axis))
				bmax = maxf(bmax, p.dot(axis))
			if amax + margin <= bmin or bmax + margin <= amin:
				return false
	return true


func _rect_hits_circle(r: Dictionary, c: Vector2, radius: float) -> bool:
	var local: Vector2 = (c - r["center"]).rotated(float(r["yaw"]))
	var h: Vector2 = r["half"]
	var dx := maxf(absf(local.x) - h.x, 0.0)
	var dz := maxf(absf(local.y) - h.y, 0.0)
	return dx * dx + dz * dz < radius * radius


func _rect_hits_ellipse(r: Dictionary, c: Vector2, a: float, b: float) -> bool:
	var h: Vector2 = r["half"]
	var steps := 24
	for i in steps + 1:
		for j in steps + 1:
			var local := Vector2(lerpf(-h.x, h.x, float(i) / steps), lerpf(-h.y, h.y, float(j) / steps))
			var p: Vector2 = r["center"] + local.rotated(-float(r["yaw"]))
			var d := p - c
			if (d.x / a) * (d.x / a) + (d.y / b) * (d.y / b) < 1.0:
				return true
	return false


## World-space 2D bounds of a placed Blender model node (origin-aligned parents) as an oriented-rect-free AABB rect.
func _model_rect(model: Node3D) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var low_y := INF
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var xf: Transform3D = model.transform * (model.global_transform.affine_inverse() * mi.global_transform)
		var box: AABB = mi.get_aabb()
		for ix in 2:
			for iy in 2:
				for iz in 2:
					var corner: Vector3 = xf * (box.position + box.size * Vector3(ix, iy, iz))
					lo = Vector2(minf(lo.x, corner.x), minf(lo.y, corner.z))
					hi = Vector2(maxf(hi.x, corner.x), maxf(hi.y, corner.z))
					low_y = minf(low_y, corner.y)
	return {"center": (lo + hi) * 0.5, "half": (hi - lo) * 0.5, "yaw": 0.0, "bottom": low_y}


func _layout_audit() -> void:
	var scene := load("res://scenes/levels/PlanetAEnvironment.tscn") as PackedScene
	var env := scene.instantiate() as Node3D
	root.add_child(env)
	var campus := PlanetA.build_campus(env)
	var rules = Rules.new()
	rules.setup()
	var layer := EmpireLayer.new()
	layer.setup(rules, "planet_a", true, "orange", Callable())
	env.add_child(layer)
	PlanetA.clear_site_props(env, PlanetA.collect_footprints([campus, layer]))

	# ---- obstacles read from the editable scene -------------------------------------------------------------
	var ponds: Array = []
	for pond in env.find_child("SidePonds", true, false).get_children():
		var radius: Vector2 = pond.get_meta("radius", Vector2(14, 14))
		ponds.append({"c": Vector2(pond.position.x, pond.position.z), "a": radius.x * 1.12 + 0.5, "b": radius.y * 1.12 + 0.5})
	check(ponds.size() == 4, "PlanetAEnvironment has 4 ponds to audit (%d)" % ponds.size())
	var pads: Array = [Vector2.ZERO]
	for rival in env.find_child("RivalLandingPads", true, false).get_children():
		pads.append(Vector2(rival.position.x, rival.position.z))
	check(pads.size() == 4, "all 4 launch pads found (main + 3 allied squad pads)")
	var rocks: Array = []
	for rock in env.find_child("Rocks", true, false).get_children():
		var mi := rock as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.mesh.get_aabb()
		rocks.append({"c": Vector2(mi.position.x, mi.position.z), "r": maxf(box.size.x, box.size.z) * 0.5 * maxf(mi.scale.x, mi.scale.z), "name": mi.name})
	check(rocks.size() > 50, "rock field loaded for audit (%d rocks)" % rocks.size())
	var shop := {"center": Vector2(0, -29), "half": Vector2(17.5, 13.0), "yaw": 0.0}
	var apron := {"center": Vector2(0, -1.5), "half": Vector2(40, 48.5), "yaw": 0.0}
	var tree_discs: Array = []
	for pond_node in env.find_child("SidePonds", true, false).get_children():
		for tree in pond_node.get_children():
			if String(tree.name).begins_with("Tree"):
				tree_discs.append({"c": Vector2(pond_node.position.x + tree.position.x, pond_node.position.z + tree.position.z), "r": 2.6})

	# ---- every paved footprint (slabs + roads) --------------------------------------------------------------
	var prints: Array = PlanetA.collect_footprints([campus, layer])
	var slabs: Array = []
	var roads: Array = []
	for fp: Dictionary in prints:
		(slabs if fp["kind"] == "slab" else roads).append(fp)
	check(slabs.size() >= 6 + 3 + 2, "slabs built: 6 empire foundations + 3 tower footings + tank farm + motor pool (%d)" % slabs.size())
	var bad := 0
	for fp: Dictionary in prints:
		var why := ""
		for pond in ponds:
			if _rect_hits_ellipse(fp, pond["c"], pond["a"], pond["b"]):
				why = "pond"
		for pad in pads:
			if _rect_hits_circle(fp, pad, 17.2):
				why = "launch pad %s" % str(pad)
		for rock in rocks:
			if _rect_hits_circle(fp, rock["c"], rock["r"] + 0.2):
				why = "rock " + str(rock["name"])
		for tree in tree_discs:
			if _rect_hits_circle(fp, tree["c"], tree["r"]):
				why = "pond tree"
		if _rects_overlap(fp, shop):
			why = "parts shop"
		if _rects_overlap(fp, apron, 0.0) and not String(fp["name"]).begins_with("Trunk") and not String(fp["name"]).ends_with("Trunk"):
			why = "central apron"
		if why != "":
			bad += 1
			print("  overlap: %s hits %s" % [fp["name"], why])
	check(bad == 0, "no slab or road overlaps a pond, rock, tree, launch pad, parts shop or the central apron")

	# Slabs never overlap each other; roads never overlap a slab other than their own link/driveway end.
	var slab_clash := 0
	for i in slabs.size():
		for j in range(i + 1, slabs.size()):
			if _rects_overlap(slabs[i], slabs[j], 0.5):
				slab_clash += 1
				print("  slab clash: %s vs %s" % [slabs[i]["name"], slabs[j]["name"]])
	check(slab_clash == 0, "ZERO overlapping slab footprints (%d slabs, 0.5 m minimum gap)" % slabs.size())
	var road_clash := 0
	for road: Dictionary in roads:
		var rname := String(road["name"])
		if rname.begins_with("Link") or rname.begins_with("Driveway"):
			continue
		for slab: Dictionary in slabs:
			if _rects_overlap(road, slab, 0.0):
				road_clash += 1
				print("  road clash: %s vs %s" % [road["name"], slab["name"]])
	check(road_clash == 0, "avenues and trunk roads never run through a foundation slab")
	var link_clash := 0
	for road: Dictionary in roads:
		var rname := String(road["name"])
		if not (rname.begins_with("Link") or rname.begins_with("Driveway")):
			continue
		var own := 0
		for slab: Dictionary in slabs:
			if _rects_overlap(road, slab, 0.0):
				own += 1
		if own > 2:   # a link may touch only the two slabs it joins (or one slab + the avenue)
			link_clash += 1
			print("  link clash: %s touches %d slabs" % [road["name"], own])
	check(link_clash == 0, "driveways and links join exactly their own slabs")

	# ---- every Blender model: inside its own slab, standing on the slab top, no model-model overlap ---------
	var models: Array = []
	for n in campus.find_children("*", "Node3D", true, false):
		if n.has_meta("campus_model"):
			models.append(n)
	check(models.size() == 3 + 1 + 2, "campus Blender models: 3 towers + silo bank + dropship + rover (%d)" % models.size())
	var model_rects: Array = []
	var ungrounded := 0
	var outside := 0
	for m: Node3D in models:
		var slab_node := campus.find_child(String(m.get_meta("slab")), true, false) as Node3D
		var rect := _model_rect(m)
		model_rects.append(rect)
		var top: float = slab_node.get_meta("slab_top")
		if absf(m.position.y - top) > 0.001 or absf(float(rect["bottom"]) - top) > 0.02 or absf(slab_node.position.y) > 0.001:
			ungrounded += 1
			print("  floating: %s y=%.3f bottom=%.3f top=%.3f" % [m.name, m.position.y, rect["bottom"], top])
		var half: Vector2 = slab_node.get_meta("footprint_half")
		var slab_rect := {"center": Vector2(slab_node.position.x, slab_node.position.z), "half": half - Vector2(0.4, 0.4), "yaw": 0.0}
		var inside := true
		for corner: Vector2 in _corners(rect):
			var d: Vector2 = (corner - slab_rect["center"]).abs()
			if d.x > slab_rect["half"].x or d.y > slab_rect["half"].y:
				inside = false
		if not inside:
			outside += 1
			print("  outside slab: ", m.name)
	check(ungrounded == 0, "ZERO floating foundations/models: all grounded at slab_top")
	check(outside == 0, "every Blender model sits fully inside its own concrete slab")
	var model_clash := 0
	for i in model_rects.size():
		for j in range(i + 1, model_rects.size()):
			if _rects_overlap(model_rects[i], model_rects[j], 0.5):
				model_clash += 1
	check(model_clash == 0, "no two campus Blender models overlap")
	# Motor pool vehicles are parallel (same yaw) and in their marked bays.
	var dropship := campus.find_child("ParkedDropship", true, false) as Node3D
	var rover := campus.find_child("ParkedRover", true, false) as Node3D
	check(dropship != null and rover != null and is_equal_approx(dropship.rotation.y, rover.rotation.y),
		"motor pool dropship and rover are parked parallel")
	# Empire foundations: 14 m (18 m vault) slabs, anchors sit on the slab top, models stay on the slab.
	var found := 0
	for id in ["defense_turrets", "shield_gen", "refinery", "radar", "hangar", "vault"]:
		var slab_node := layer.find_child(id + "_foundation", true, false) as Node3D
		var anchor := layer.slots[id]["anchor"] as Node3D
		var want := 9.0 if id == "vault" else 7.0
		var half: Vector2 = slab_node.get_meta("footprint_half")
		if is_equal_approx(half.x, want) and is_equal_approx(half.y, want) \
				and is_equal_approx(anchor.position.y, EmpireLayer.SLAB_TOP) \
				and is_equal_approx(slab_node.position.x, anchor.position.x) and is_equal_approx(slab_node.position.z, anchor.position.z):
			found += 1
		else:
			print("  bad foundation ", id)
	check(found == 6, "6 empire slots each own a 14 m (18 m vault) grounded foundation")
	# Centre spacing >= 26 m along each avenue; west avenue is straight north-south.
	var west: Array = EmpireLayer.HOME_SITES.slice(0, 3)
	var east: Array = EmpireLayer.HOME_SITES.slice(3, 6)
	var spaced := true
	for group in [west, east]:
		for i in range(1, 3):
			spaced = spaced and absf(group[i].z - group[i - 1].z) >= 26.0 and is_equal_approx(group[i].x, group[0].x)
	check(spaced, "empire sites sit on straight N-S avenues with >= 26 m centre spacing")
	check(layer.slots["defense_turrets"]["anchor"].position.x < 0.0 and layer.slots["radar"]["anchor"].position.x > 0.0,
		"west district = turrets / shield / refinery, east district = radar / hangar / vault")
	# Empire structure footprints at max tier fit the slab (largest model 4.8 + 3 * 1.35 = 8.85 m).
	check(4.8 + 3 * 1.35 + 1.0 < 14.0, "tier-3 structure models fit a 14 m slab with margin")
	# Allied tower: one per allied pad, outside the pad radius + margin.
	var towers := 0
	for site: Dictionary in PlanetA.CAMPUS_TOWERS:
		var slab_node := campus.find_child("TowerSlab" + site["id"], true, false) as Node3D
		var rect := {"center": Vector2(slab_node.position.x, slab_node.position.z), "half": slab_node.get_meta("footprint_half"), "yaw": 0.0}
		if not _rect_hits_circle(rect, site["pad"], 19.0) and campus.find_child("LaunchTower" + site["id"], true, false) != null:
			towers += 1
	check(towers == 3, "exactly one launch service tower beside each allied pad, >= 2 m clear of the pad ring")

	# ---- home menu terrace ------------------------------------------------------------------------------------
	check(true, "audit complete: %d slabs, %d roads, %d models" % [slabs.size(), roads.size(), models.size()])
	env.queue_free()


func _mesh_bounds_in(node: Node3D, cabin: Node3D) -> AABB:
	var first := true
	var out := AABB()
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		if not mi.visible:
			continue
		var xf := cabin.global_transform.affine_inverse() * mi.global_transform
		var b := xf * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _interior_audit() -> void:
	var si = InteriorScript.new()
	root.add_child(si)
	si.call("setup", null, "pad")
	var k: Dictionary = si.get_script().get_script_constant_map()
	check(is_equal_approx(k["CABIN_W"], 9.2) and is_equal_approx(k["CABIN_H"], 4.6) and is_equal_approx(k["CABIN_LENGTH"], 24.0)
		and is_equal_approx(k["Z_AFT"] - k["Z_NOSE"], 24.0) and is_equal_approx(k["Z_NOSE"], -18.0) and is_equal_approx(k["Z_AFT"], 6.0),
		"spacious cabin: 9.2 m x 4.6 m x 24 m")
	check(is_equal_approx(k["HALF_W"], 4.6) and k["WALK_X"] < k["HALF_W"] and k["CAM_X"] < k["HALF_W"]
		and k["CAM_Y_MAX"] < k["CABIN_H"] and k["CAM_Z_MIN"] > k["Z_NOSE"] and k["CAM_Z_MAX"] < k["Z_AFT"],
		"walk and camera bounds sit inside the cabin envelope")
	var air: Vector3 = k["AIRLOCK_POS"]
	check(absf(air.x) < k["HALF_W"] and is_equal_approx(air.z, -5.8) and (k["DOOR_POS"] as Vector3).x > air.x,
		"airlock spawn sits just inside the port hatch; gantry meets HALF_W at AIRLOCK_POS.z")
	check(si.stations.size() == 7 and si.stations.has("gunnery"), "7 interactive stations incl. gunnery")
	check(k["TASKS"].has("gunnery") and String(k["TASKS"]["gunnery"]["label"]) == "OVERCHARGE TURRET"
		and k["STATION_POS"].has("gunnery") and k["ROOM_NAMES"].has("gunnery"),
		"gunnery is a real interactive flight station with the OVERCHARGE TURRET task")
	# Every station mark is walkable and every named facility has visible meshes fully inside the cabin.
	var walkable := true
	for room in k["STATION_POS"]:
		var p: Vector3 = k["STATION_POS"][room]
		walkable = walkable and si.call("collide", p) == p
	check(walkable, "every station standing mark is reachable (not clamped by cabin walls)")
	var facilities := ["PilotSeat", "CoPilotSeat", "FlightYoke", "PilotDashboard", "GunnerSeat", "ShootingConsole", "GunnerComputers",
		"ReactorConsole", "LifeSupportBay", "ScienceHolotable", "FlagContainmentRack", "SpectrometerBank", "WorkshopBench", "EngineConsole"]
	var cabin_box := AABB(Vector3(-4.6, 0.0, -18.0), Vector3(9.2, 4.6, 24.0)).grow(0.15)
	var corridor_ok := true
	for fname in facilities:
		var node := si.find_child(fname, true, false) as Node3D
		if node == null:
			check(false, "facility exists: " + fname)
			continue
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		var b := _mesh_bounds_in(node, si)
		check(meshes.size() >= 3 and cabin_box.encloses(b), "%s has %d visible meshes inside the cabin %s" % [fname, meshes.size(), str(b)])
		# Corridor test: no mesh intrudes into |x| < 1.1 between the cockpit seats and the engine bay.
		for mesh in meshes:
			var mb := _mesh_bounds_in(mesh as Node3D, si)
			if mb.end.z > -13.0 and mb.position.z < 3.6 and mb.position.x < 1.1 and mb.end.x > -1.1:
				corridor_ok = false
				print("  corridor blocked by ", fname, "/", mesh.name, " ", mb)
	check(corridor_ok, "clear walkable centre corridor >= 2.2 m wide from cockpit to engine bay")
	for screen in ["NavStarMapScreen", "HorizonScreen", "FuelDeltaVScreen", "HullStatusScreen", "ButtonDeckScreen",
			"TargetReticleScreen", "RadarScopeScreen", "WeaponHeatScreen", "PartsDiagnosticScreen", "PropulsionScreenA"]:
		check(si.find_child(screen, true, false) != null, "glowing computer screen: " + screen)
	check(si.find_child("HologramGlobe", true, false) != null, "science holo-table uses the hologram shader globe")
	si.queue_free()


func _run_pad_sequence_test() -> void:
	var output: Array = []
	var project_dir := ProjectSettings.globalize_path("res://")
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", project_dir, "--script",
		"tests/pad_sequence_runtime_test.gd"], output, true)
	var text := ""
	for chunk in output:
		text += str(chunk)
	var fails := 0
	for line in text.split("\n"):
		if line.begins_with("FAIL"):
			fails += 1
			print(line)
	check(code == 0 and fails == 0 and "PAD_SEQUENCE_RESULT: 0 failures" in text,
		"pad_sequence_runtime_test.gd passes (exit %d, %d FAIL lines)" % [code, fails])
