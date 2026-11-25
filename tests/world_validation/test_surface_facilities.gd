extends SceneTree
## Surface facility + infrastructure validation.
## Run: Godot --headless --path . -s res://tests/world_validation/test_surface_facilities.gd

const FBU = preload("res://scripts/environment/FacilityBuilderUtils.gd")
const WORLD_SCENE := "res://scenes/world/WorldRoot.tscn"
const KEYS: Array[String] = ["extraction", "mining", "refinery", "launch", "settlement"]
## Landmark index of each facility entrance.
const LANDMARK_INDEX: Dictionary = {"extraction": 1, "settlement": 3, "refinery": 4, "mining": 5, "launch": 6}

var _failures: int = 0
var _world: WorldRoot
var _sfm: Node3D
var _infra: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load(WORLD_SCENE) as PackedScene
	_check(packed != null, "WorldRoot.tscn loads")
	if packed == null:
		quit(1)
		return
	_world = packed.instantiate() as WorldRoot
	root.add_child(_world)
	await _frames(4)
	_sfm = _world.surface_facilities
	_check(_sfm != null, "SurfaceFacilityManager wired into WorldRoot")
	if _sfm == null:
		quit(1)
		return
	_infra = _sfm.infrastructure

	_test_facilities_exist()
	_test_spire_height()
	_test_landmarks()
	await _test_interior_floors()
	await _test_bridges()
	await _test_roads()
	_test_foundations()
	_test_animation()
	_test_infrastructure_counts()

	print("Surface facility models: glb=%s procedural=%s" % [str(FBU.glb_loaded), str(FBU.procedural_used)])
	_world.queue_free()
	await _frames(2)
	print("Surface facilities %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


func _count(node: Node, kind: String) -> int:
	var c: int = 0
	if kind == "mesh" and node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		c += 1
	elif kind == "multimesh" and node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		c += 1
	elif kind == "body" and node is StaticBody3D and (node as StaticBody3D).collision_layer == 1:
		for ch in node.get_children():
			if ch is CollisionShape3D and (ch as CollisionShape3D).shape != null:
				c += 1
				break
	for ch in node.get_children():
		c += _count(ch, kind)
	return c


func _test_facilities_exist() -> void:
	for k in KEYS:
		var n: Node3D = _sfm.get_facility(k)
		_check(n != null, "facility '%s' exists" % k)
		if n == null:
			continue
		var meshes: int = _count(n, "mesh")
		var bodies: int = _count(n, "body")
		_check(meshes > 20, "%s has valid meshes (%d)" % [k, meshes])
		_check(bodies > 10, "%s has StaticBody3D collision (%d)" % [k, bodies])
		_check(n.has_method("get_interior_floor_points") and (n.call("get_interior_floor_points") as Array).size() >= 3, "%s exposes interior floor points" % k)
	_check(_infra != null, "InfrastructureNetwork exists")


func _test_spire_height() -> void:
	var ex: Node3D = _sfm.get_facility("extraction")
	var h: float = float(ex.call("get_spire_height"))
	_check(h >= 180.0 and h <= 250.0, "Extraction Spire height %.1f m within 180-250" % h)


func _test_landmarks() -> void:
	var lm: LandmarkManager = _world.landmark_manager
	_check(lm.get_count() >= 12, "landmarks registered incl. interiors + bridge (%d)" % lm.get_count())
	for k in KEYS:
		var d: Dictionary = lm.get_landmark(int(LANDMARK_INDEX[k]))
		_check(str(d.get("facility", "")) == k, "landmark %d targets facility '%s'" % [int(LANDMARK_INDEX[k]), k])
	_check("Bridge" in str(lm.get_landmark(13).get("name", "")), "Crimson Canyon Bridge landmark registered")


func _ray_down(p_render: Vector3, up: Vector3, above: float, below: float) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p_render + up * above, p_render - up * below, 1)
	return space.intersect_ray(q)


func _test_interior_floors() -> void:
	for k in KEYS:
		_world.teleport_to_landmark(int(LANDMARK_INDEX[k]))
		await _frames(4)
		var n: Node3D = _sfm.get_facility(k)
		var pts: Array = n.call("get_interior_floor_points")
		var ok: int = 0
		for lp in pts:
			var local: Vector3 = lp
			var p: Vector3 = n.to_global(local)
			var up: Vector3 = n.global_basis.y.normalized()
			var hit: Dictionary = _ray_down(p, up, 1.8, 1.5)
			var good: bool = false
			if not hit.is_empty():
				good = absf(((hit["position"] as Vector3) - p).dot(up)) < 0.35
			if good:
				ok += 1
			else:
				print("  floor miss %s at local %s dist_up=%s collider=%s" % [k, str(local), str(((hit["position"] as Vector3) - p).dot(up)) if not hit.is_empty() else "none", str((hit.get("collider") as Node).get_path()) if not hit.is_empty() else ""])
		_check(ok == pts.size(), "%s interior floors solid (%d/%d)" % [k, ok, pts.size()])


func _test_bridges() -> void:
	var pts: Array[Vector3] = _infra.call("get_bridge_test_points")
	var per: int = pts.size() / 2
	_check(pts.size() > 60, "bridge test points exported (%d)" % pts.size())
	for b in 2:
		var total: int = 0
		var ok: int = 0
		var group: Array = pts.slice(b * per, (b + 1) * per)
		_world.floating_origin.check_and_shift(group[group.size() / 2])
		await _frames(3)
		var step: int = 2
		for i in range(0, group.size(), step):
			var pr: Vector3 = _world.floating_origin.planet_to_render(group[i])
			var up: Vector3 = (group[i] as Vector3).normalized()
			total += 1
			var hit: Dictionary = _ray_down(pr, up, 6.0, 10.0)
			if not hit.is_empty() and absf(((hit["position"] as Vector3) - pr).dot(up)) < 0.35:
				ok += 1
		_check(ok == total and total > 10, "bridge %d deck solid (%d/%d)" % [b, ok, total])
	var recs: Array = _infra.pier_records
	_check(recs.size() >= 8, "bridge piers built (%d)" % recs.size())
	var piers_ok: bool = true
	for r in recs:
		var rd: Dictionary = r
		var bottom: Vector3 = rd["bottom"]
		var ground: Vector3 = rd["ground"]
		if bottom.length() > ground.length() - 1.0:
			piers_ok = false
	_check(piers_ok, "all bridge piers descend below terrain (no floating piers)")


func _test_roads() -> void:
	var pts: Array[Vector3] = _infra.call("get_road_sample_points")
	_check(pts.size() > 500, "road sample points exported (%d)" % pts.size())
	var worst: float = 0.0
	var bad: int = 0
	for i in range(0, pts.size(), 3):
		var p: Vector3 = pts[i]
		var surf_r: float = _world.planet.get_surface_radius(p.normalized())
		var dr: float = absf(p.length() - surf_r)
		worst = maxf(worst, dr)
		if dr > 1.2:
			bad += 1
	_check(bad == 0, "roads hug terrain (worst %.3f m, %d over 1.2 m)" % [worst, bad])
	_check((_infra.roads as Array).size() >= 6, "road network has highways + canyon branch (%d)" % (_infra.roads as Array).size())
	# Road collision exists under sampled points.
	var tested: int = 0
	var hits: int = 0
	for idx in [5, 200, 600, 900]:
		if idx >= pts.size():
			continue
		var p: Vector3 = pts[idx]
		_world.floating_origin.check_and_shift(p)
		await _frames(3)
		var pr: Vector3 = _world.floating_origin.planet_to_render(p)
		var hit: Dictionary = _ray_down(pr, p.normalized(), 4.0, 6.0)
		tested += 1
		if not hit.is_empty() and absf(((hit["position"] as Vector3) - pr).dot(p.normalized())) < 0.6:
			hits += 1
	_check(tested > 0 and hits == tested, "road collision solid (%d/%d)" % [hits, tested])


func _find_foundation(n: Node) -> Node:
	for c in n.get_children():
		if c.has_meta("depth"):
			return c
	return null


func _test_foundations() -> void:
	for k in KEYS:
		var info: Dictionary = _sfm.get_facility_info(k)
		var n: Node3D = info["node"]
		var u: Vector3 = info["unit_dir"]
		var terrain_r: float = _world.planet.get_surface_radius(u)
		var delta: float = terrain_r - (info["base"] as Vector3).length()
		_check(delta > 0.2 and delta < 0.8, "%s pad base embedded in terrain (%.2f m below)" % [k, delta])
		var slab_delta: float = terrain_r - (info["origin"] as Vector3).length()
		_check(slab_delta > -0.6 and slab_delta < 0.0, "%s slab top within 0.6 m of terrain, never floating (%.2f)" % [k, slab_delta])
		var f: Node = _find_foundation(n)
		_check(f != null, "%s has deep foundation skirt" % k)
		if f == null:
			continue
		var depth: float = float(f.get_meta("depth"))
		_check(depth >= 8.0 or k == "settlement", "%s skirt depth %.1f m" % [k, depth])
		var g: Callable = n.get("ground_h")
		var bottom: float = float(f.get_meta("top_y")) - depth
		var low: float = 0.0
		for i in 12:
			var a: float = TAU * float(i) / 12.0
			var pr: float = 45.0
			low = minf(low, float(g.call(Vector3(cos(a) * pr, 0, sin(a) * pr))))
		_check(bottom < low or depth >= 59.0, "%s skirt (%.1f) reaches below lowest terrain (%.1f)" % [k, bottom, low])


func _spin_of(n: Node3D) -> Basis:
	return n.transform.basis


func _test_animation() -> void:
	var targets: Dictionary = {
		"extraction": "TacticalHologram", "mining": "DrillHead1", "refinery": "VentFan0",
		"launch": "CraneTrolley", "settlement": "SparkEmitter",
	}
	var before: Dictionary = {}
	for k in targets:
		var n: Node3D = _sfm.get_facility(k).find_child(targets[k], true, false) as Node3D
		_check(n != null, "%s animated node '%s' exists" % [k, targets[k]])
		before[k] = n.transform if n != null else Transform3D.IDENTITY
	var t0: int = _sfm.tick_count
	for i in 12:
		_sfm.tick(0.1)
	_check(_sfm.tick_count == t0 + 12, "facility manager ticks")
	for k in targets:
		var n: Node3D = _sfm.get_facility(k).find_child(targets[k], true, false) as Node3D
		if n == null:
			continue
		var moved: bool = not (n.transform as Transform3D).is_equal_approx(before[k]) or (k == "settlement")
		_check(moved, "%s machinery animates (%s)" % [k, targets[k]])
	var belt: Node = _sfm.get_facility("mining").find_child("Belt", true, false)
	_check(belt is MeshInstance3D and (belt as MeshInstance3D).material_override is ShaderMaterial, "mining conveyor uses scrolling shader")
	# Origin shift keeps facilities registered on planet space.
	var info: Dictionary = _sfm.get_facility_info("refinery")
	var expect: Vector3 = _world.floating_origin.planet_to_render(info["origin"])
	_check((info["node"] as Node3D).global_position.distance_to(expect) < 0.05, "refinery tracks floating origin")


func _test_infrastructure_counts() -> void:
	var s: Dictionary = _infra.call("get_summary")
	_check(int(s["bridges"]) == 2, "two Crimson Canyon bridges")
	_check(int(s["pipelines"]) == 2, "two pipelines")
	_check(int(s["power_lines"]) == 2 and int(s["pylons"]) > 10, "power lines with pylons (%d)" % int(s["pylons"]))
	_check(int(s["pillars"]) > 20, "pipeline pillars anchored (%d)" % int(s["pillars"]))


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s" % label)
