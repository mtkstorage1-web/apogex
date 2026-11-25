extends SceneTree
## Wave 4 (Milestone 5) validation: Helion + Cinder motherships, modular kit, 7-room interiors, hangar doors,
## artificial ship gravity.
## Run: Godot --headless --path . -s res://tests/world_validation/test_motherships.gd

const K = preload("res://scripts/environment/ModularKitBuilder.gd")
const InteriorScript = preload("res://scripts/environment/MothershipInterior.gd")
const WORLD_SCENE := "res://scenes/world/WorldRoot.tscn"
const FACTIONS: Array[String] = ["helion", "cinder"]

var _failures: int = 0
var _world: WorldRoot
var _mgr: Node3D


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_failures += 1
		print("  FAIL ", msg)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return _world.get_world_3d().direct_space_state.intersect_ray(q)


func _run() -> void:
	var packed: PackedScene = load(WORLD_SCENE) as PackedScene
	_check(packed != null, "WorldRoot.tscn loads")
	if packed == null:
		quit(1)
		return
	_world = packed.instantiate() as WorldRoot
	root.add_child(_world)
	await _frames(4)
	_mgr = _world.mothership_manager
	_check(_mgr != null, "MothershipManager wired into WorldRoot")
	if _mgr == null:
		quit(1)
		return

	_test_catalog()
	_test_ships_exist()
	await _test_rooms_have_floors()
	await _test_path_clearance()
	await _test_hangar_doors()
	await _test_artificial_gravity()
	_test_landmarks_and_lights()
	_test_actions()

	print("Mothership models: glb=%s procedural=%s" % [str(K.glb_loaded), str(K.procedural_used)])
	_world.queue_free()
	await _frames(2)
	print("Motherships %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _has_solid_collision(n: Node) -> bool:
	if n is StaticBody3D and (n as StaticBody3D).collision_layer == 1:
		for c in n.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				return true
	for ch in n.get_children():
		if _has_solid_collision(ch):
			return true
	return false


func _test_catalog() -> void:
	print("[catalog]")
	_check(K.CATALOG.size() == 23, "catalog lists 23 modules (%d)" % K.CATALOG.size())
	var ok: int = 0
	for faction in FACTIONS:
		for m in K.CATALOG:
			var node: Node3D = K.build_module(m, faction)
			var good: bool = node != null and node.get_meta("module", "") == m and _has_solid_collision(node)
			if good:
				ok += 1
			else:
				print("    module failed: ", m, " / ", faction)
			if node != null:
				node.free()
	_check(ok == 46, "all 23 modules build with solid layer-1 collision for both factions (%d/46)" % ok)


func _test_ships_exist() -> void:
	print("[ships]")
	var hull_colors: Array[Color] = []
	for f in FACTIONS:
		var ship: Node3D = _mgr.get_ship(f)
		_check(ship != null, "%s mothership exists" % f)
		if ship == null:
			continue
		var dims: Vector3 = ship.get_exterior_dimensions()
		_check(dims.is_equal_approx(Vector3(320, 190, 850)), "%s exterior dimensions 320x190x850 (%s)" % [f, str(dims)])
		var aabb: AABB = ship.get_hull_visual_aabb()
		_check(absf(aabb.size.z - 850.0) < 12.0 and absf(aabb.size.x - 320.0) < 12.0 and absf(aabb.size.y - 190.0) < 12.0,
			"%s hull visual bounds ~850x320x190 (%s)" % [f, str(aabb.size)])
		_check(ship.interior != null and ship.interior.get("built"), "%s interior built" % f)
		_check(ship.faction == f, "%s faction identity" % f)
		hull_colors.append(K.palette(f)["hull"])
	_check(hull_colors.size() == 2 and not hull_colors[0].is_equal_approx(hull_colors[1]), "factions have distinct palettes")
	_check(K.palette("helion")["accent"].is_equal_approx(Color("22E5FF")) and K.palette("cinder")["accent"].is_equal_approx(Color("FF6A1A")), "faction emissive accents (cyan / amber)")
	var h: Node3D = _mgr.get_ship("helion")
	var c: Node3D = _mgr.get_ship("cinder")
	_check(h.get_local_up_direction().is_normalized() and c.get_local_up_direction().is_normalized(), "ship up vectors normalised")
	var hp: Vector3 = h.planet_origin
	var cp: Vector3 = c.planet_origin
	_check(absf(hp.length() - cp.length()) < 1.0 and hp.distance_to(cp) > 1500.0, "ships in opposing low orbits at equal altitude (alt %.0f m)" % (hp.length() - _world.world_config.planet_radius))
	_check((h.planet_basis.z).dot(-hp.normalized()) > 0.999, "Helion bow (hangar + bridge) faces Vesper-9")
	_check((c.planet_basis.z).dot(-cp.normalized()) > 0.999, "Cinder bow (hangar + bridge) faces Vesper-9")


func _test_rooms_have_floors() -> void:
	print("[rooms]")
	await _frames(2)
	var verified: int = 0
	for f in FACTIONS:
		var ship: Node3D = _mgr.get_ship(f)
		var interior: Node3D = ship.interior
		var spawns: Dictionary = interior.get_room_spawn_points()
		_check(spawns.size() == 7, "%s has 7 rooms (%d)" % [f, spawns.size()])
		for room in InteriorScript.ROOM_NAMES:
			_check(spawns.has(room), "%s room present: %s" % [f, room])
			if not spawns.has(room):
				continue
			var local: Vector3 = spawns[room]
			var from: Vector3 = ship.to_global(local)
			var down: Vector3 = -ship.global_basis.y
			var hit: Dictionary = _ray(from, from + down * 4.0)
			var ok: bool = false
			if not hit.is_empty():
				var hl: Vector3 = ship.to_local(hit["position"])
				ok = absf(hl.y - interior.get_room_floor_y(room)) < 0.2
			_check(ok, "%s / %s: downward ray hits solid floor" % [f, room])
			if ok:
				verified += 1
	_check(verified == 14, "14/14 rooms verified (%d)" % verified)


func _test_path_clearance() -> void:
	print("[circulation]")
	for f in FACTIONS:
		var ship: Node3D = _mgr.get_ship(f)
		var segs: Array = ship.interior.get_walkable_path_segments()
		_check(segs.size() >= 6, "%s exposes walkable path segments (%d)" % [f, segs.size()])
		var routes: Dictionary = {}
		for s in segs:
			var a: Vector3 = ship.to_global(s["from"])
			var b: Vector3 = ship.to_global(s["to"])
			var hit: Dictionary = _ray(a, b)
			_check(hit.is_empty(), "%s clear: %s (%s)" % [f, s["name"], s["route"]])
			routes[s["route"]] = true
		_check(routes.has("bridge") and routes.has("reactor"), "%s covers Hangar->Bridge and Hangar->Reactor" % f)


func _test_hangar_doors() -> void:
	print("[hangar doors]")
	for f in FACTIONS:
		var ship: Node3D = _mgr.get_ship(f)
		_mgr.set_hangar_doors_open(false)
		_mgr.tick(10.0)
		await _frames(2)
		_check(not ship.interior.is_hangar_doors_open(), "%s doors report CLOSED" % f)
		var a: Vector3 = ship.to_global(Vector3(-10, 10, 380))
		var b: Vector3 = ship.to_global(Vector3(-10, 10, 460))
		var closed_hit: Dictionary = _ray(a, b)
		_check(not closed_hit.is_empty(), "%s: door collision blocks the mouth when CLOSED" % f)
		_mgr.toggle_hangar_doors()
		_mgr.tick(10.0)
		await _frames(2)
		_check(ship.interior.is_hangar_doors_open() and is_equal_approx(ship.interior.get_door_progress(), 1.0), "%s doors OPEN + fully slid" % f)
		_check(_ray(a, b).is_empty(), "%s: collision cleared when OPEN (ray through mouth)" % f)
		# Fly-in path from deep space straight onto the hangar deck.
		var outside: Vector3 = ship.to_global(Vector3(0, 10, 560))
		var inside: Vector3 = ship.to_global(Vector3(0, 10, 300))
		_check(_ray(outside, inside).is_empty(), "%s: unobstructed fly-in from space into the hangar" % f)
		var leaves: Array = ship.interior.get_hangar_door_leaves()
		_check(leaves.size() == 2 and absf((leaves[0] as Node3D).position.x) > 60.0, "%s: leaves slid into the wall pockets" % f)
	_mgr.set_hangar_doors_open(true)
	await _frames(2)


func _test_artificial_gravity() -> void:
	print("[ship gravity]")
	var cases: Array = [["Helion Mothership - Main Hangar", "helion"], ["Cinder Mothership - Reactor Chamber", "cinder"]]
	for cs in cases:
		var idx: int = _find_landmark(cs[0])
		_check(idx >= 0, "landmark exists: %s" % cs[0])
		if idx < 0:
			continue
		_world.teleport_to_landmark(idx)
		await _frames(3)
		var ship: Node3D = _mgr.get_ship(cs[1])
		var ex: ExplorerController = _world.explorer
		_check(ex.move_mode == ExplorerController.MoveMode.WALK, "%s: explorer in walk mode" % cs[0])
		var start_y: float = ship.to_local(ex.global_position).y
		await _frames(90)
		var ly: Vector3 = ship.to_local(ex.global_position)
		_check(ex.in_ship_interior, "%s: ship interior detected" % cs[0])
		_check(ex.grounded, "%s: explorer grounded" % cs[0])
		_check(ly.y > 0.5 and ly.y < 1.5, "%s: stands on the deck (local y %.2f, start %.2f)" % [cs[0], ly.y, start_y])
		_check(ex.gravity_dir.dot(-ship.get_local_up_direction()) > 0.999, "%s: gravity = ship floor-down" % cs[0])
		_check(absf(ex.gravity_dir.dot(-ex.get_planet_position().normalized())) < 0.9, "%s: not radial planet gravity" % cs[0])
		_check(ship.contains_planet_point_in_interior(ex.get_planet_position()), "%s: contains_planet_point_in_interior" % cs[0])


func _find_landmark(lm_name: String) -> int:
	for lm in _world.landmark_manager.landmarks:
		if lm["name"] == lm_name:
			return int(lm["index"])
	return -1


func _test_landmarks_and_lights() -> void:
	print("[landmarks / lights]")
	var names: Array[String] = [
		"Helion Mothership - Exterior Approach", "Helion Mothership - Main Hangar", "Helion Mothership - Command Bridge",
		"Cinder Mothership - Exterior Approach", "Cinder Mothership - Main Hangar", "Cinder Mothership - Reactor Chamber",
	]
	for n in names:
		_check(_find_landmark(n) >= 0, "landmark: %s" % n)
	for f in FACTIONS:
		var ship: Node3D = _mgr.get_ship(f)
		var omni: int = 0
		var shadowed: int = 0
		var stack: Array = [ship]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			if nd is OmniLight3D:
				omni += 1
				if (nd as OmniLight3D).shadow_enabled:
					shadowed += 1
			stack.append_array(nd.get_children())
		_check(shadowed == 0, "%s: no shadow-casting omni lights (%d omni)" % [f, omni])
		_check(omni <= 40, "%s: omni light budget (%d <= 40)" % [f, omni])
		var diag: Dictionary = ship.get_diagnostics()
		_check(diag.get("rooms", 0) == 7, "%s diagnostics report 7 rooms" % f)


func _test_actions() -> void:
	print("[actions]")
	var before: bool = _mgr.is_hangar_doors_open()
	_world.handle_action(&"toggle_hangar_doors")
	_check(_mgr.is_hangar_doors_open() != before, "toggle_hangar_doors action flips door state")
	_world.handle_action(&"toggle_hangar_doors")
	_check(_mgr.is_hangar_doors_open() == before, "toggle_hangar_doors action flips back")
	var d: Dictionary = _world.get_diagnostics()
	_check(d.has("motherships") and d.has("hangar_doors_open"), "diagnostics include motherships")
	var shifts: int = _world.floating_origin.shift_count
	_world.regenerate_world(_world.world_config.world_seed)
	_check(_mgr.get_ship("helion") != null and _mgr.get_ship("cinder") != null, "ships survive regenerate_world")
	_check(_world.floating_origin.shift_count >= shifts, "floating origin intact after regenerate")
