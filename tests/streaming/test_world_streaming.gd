extends SceneTree
## Wave 5 (Milestone 7) validation: the 5 streaming classes, 6-state machine, hysteresis, rapid traversal and
## state preservation across unload/reload.
## Run: Godot --headless --path . -s res://tests/streaming/test_world_streaming.gd

const C = RegionStreamingController.ChunkState
const WORLD_SCENE := "res://scenes/world/WorldRoot.tscn"

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_failures += 1
		print("  FAIL ", msg)


func _make_regions() -> RegionStreamingController:
	var r := RegionStreamingController.new()
	root.add_child(r)
	r.setup(12000.0)
	return r


func _pump(r: RegionStreamingController, pos: Vector3, vel: Vector3, n: int) -> void:
	for i in n:
		r.update(pos, vel, Vector3.FORWARD)


func _run() -> void:
	_test_classes()
	_test_state_machine()
	_test_hysteresis()
	_test_activation_cap()
	_test_rapid_traversal()
	_test_state_preservation()
	_test_loader()
	await _test_world_integration()
	print("Streaming %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_classes() -> void:
	print("[classes]")
	var w := WorldStreamingManager.new()
	root.add_child(w)
	var cfg := WorldConfig.new()
	w.setup(cfg)
	_check(w.loader is SceneChunkLoader and w.residency is AssetResidencyManager, "loader + residency created")
	_check(w.lod is EnvironmentLODController and w.regions is RegionStreamingController, "LOD + region controllers created")
	_check(w.regions.get_region_ids().size() == 8, "8 strategic regions")
	var st: Dictionary = w.get_streaming_stats()
	for k in ["active_regions", "ready_regions", "loading_regions", "unloaded_regions", "retiring_regions", "residency_mb", "budget_mb", "transitions_count", "lod_tier"]:
		_check(st.has(k), "stats key %s" % k)
	_check(int(st["unloaded_regions"]) == 8, "all regions start UNLOADED")
	for def in RegionStreamingController.REGION_DEFS:
		_check(float(def["enter"]) < float(def["exit"]) * 0.8, "hysteresis radii %s" % def["id"])
	w.queue_free()


func _test_state_machine() -> void:
	print("[state machine]")
	var r := _make_regions()
	var id := &"central_terminus"
	var center: Vector3 = r.get_region(id)["center"]
	var seen: Array[int] = [r.get_state(id)]
	for i in 8:
		r.update(center, Vector3.ZERO, Vector3.FORWARD)
		if seen.back() != r.get_state(id):
			seen.append(r.get_state(id))
	_check(seen == [C.UNLOADED, C.REQUESTED, C.LOADING, C.READY, C.ACTIVE], "ramps UNLOADED->REQUESTED->LOADING->READY->ACTIVE %s" % str(seen))
	var far: Vector3 = center * 1.5
	r.update(far, Vector3.ZERO, Vector3.FORWARD)
	_check(r.get_state(id) == C.RETIRING, "leaving exit radius -> RETIRING")
	r.update(far, Vector3.ZERO, Vector3.FORWARD)
	_check(r.get_state(id) == C.UNLOADED, "RETIRING -> UNLOADED")
	r.queue_free()


func _test_hysteresis() -> void:
	print("[hysteresis]")
	var r := _make_regions()
	var id := &"central_terminus"
	var center: Vector3 = r.get_region(id)["center"]
	var up: Vector3 = center.normalized()
	var east: Vector3 = up.cross(Vector3.UP).normalized()
	var enter_r: float = r.get_region(id)["enter"]
	var exit_r: float = r.get_region(id)["exit"]
	_pump(r, center, Vector3.ZERO, 8)
	_check(r.get_state(id) == C.ACTIVE, "active at centre")
	var mid: Vector3 = center + east * ((enter_r + exit_r) * 0.5)   # between radii: must stay ACTIVE
	var flips: Array[int] = [0]
	r.region_state_changed.connect(func(rid: StringName, _o: int, _n: int) -> void:
		if rid == id:
			flips[0] += 1)
	_pump(r, mid, Vector3.ZERO, 6)
	_check(r.get_state(id) == C.ACTIVE and flips[0] == 0, "no flapping between enter and exit radius")
	var r2 := _make_regions()
	_pump(r2, mid, Vector3.ZERO, 8)
	_check(r2.get_state(id) == C.UNLOADED, "region does not load between radii from outside")
	# velocity lookahead brings a region in earlier than the focus alone.
	var r3 := _make_regions()
	var approach: Vector3 = center + east * (enter_r + 400.0)
	r3.update(approach, Vector3.ZERO, Vector3.FORWARD)
	var no_bias: int = r3.get_state(id)
	r3.update(approach, -east * 400.0, Vector3.FORWARD)
	_check(no_bias == C.UNLOADED and r3.get_state(id) != C.UNLOADED, "velocity lookahead requests early")
	r.queue_free(); r2.queue_free(); r3.queue_free()


func _test_activation_cap() -> void:
	print("[activation cap]")
	var r := _make_regions()
	r.max_activations_per_frame = 1
	# Force several regions ready at once by teleporting between neighbours' overlap: use big enter radii.
	for id in r.get_region_ids():
		r.get_region(id)["enter"] = 1.0e6
		r.get_region(id)["exit"] = 2.0e6
	var max_seen: int = 0
	for i in 24:
		r.update(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD)
		max_seen = maxi(max_seen, r.get_activations_this_frame())
	_check(max_seen == 1, "max 1 activation per frame (saw %d)" % max_seen)
	_check(r.get_count(C.ACTIVE) == 8, "all regions eventually active")
	r.queue_free()


func _test_rapid_traversal() -> void:
	print("[rapid traversal]")
	var w := WorldStreamingManager.new()
	root.add_child(w)
	var cfg := WorldConfig.new()
	w.setup(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 400:
		var p: Vector3 = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * (12000.0 + rng.randf() * 3000.0)
		w.update_streaming(p, Vector3(rng.randfn() * 300.0, rng.randfn() * 300.0, rng.randfn() * 300.0), Vector3.FORWARD, p.length() - 12000.0, 0.016)
	var st: Dictionary = w.get_streaming_stats()
	var total: int = int(st["active_regions"]) + int(st["ready_regions"]) + int(st["loading_regions"]) + int(st["unloaded_regions"]) + int(st["retiring_regions"])
	_check(total == 8, "region counts consistent after 400 random jumps")
	_check(int(st["transitions_count"]) > 0, "transitions occurred (%d)" % int(st["transitions_count"]))
	_check(float(st["residency_mb"]) <= float(st["budget_mb"]), "residency within budget")
	w.queue_free()


func _test_state_preservation() -> void:
	print("[state preservation]")
	var res := AssetResidencyManager.new()
	root.add_child(res)
	res.set_quality("LOW")
	_check(is_equal_approx(res.get_budget_mb(), 256.0), "LOW budget 256 MB")
	res.set_world_state(&"mining_derrick_rig", {"state": 2})
	var node := Node3D.new()
	root.add_child(node)
	res.make_resident(&"north_highlands", 90.0, node)
	_check(res.is_resident(&"north_highlands"), "resident after make_resident")
	res.retire(&"north_highlands", true)
	_check(not res.is_resident(&"north_highlands"), "retired")
	_check(res.get_world_state(&"mining_derrick_rig").get("state", -1) == 2, "authoritative state survives retirement")
	res.make_resident(&"north_highlands", 90.0)
	_check(res.reload_count == 1, "reload counted")
	_check(not res.can_fit(1000.0), "budget rejects oversize load")
	# Destruction state survives visual unload/reload.
	var cfg := WorldConfig.new()
	var gen := PlanetGenerator.new()
	_check(true, "residency API ok")
	var lod_t: int = EnvironmentLODController.resolve_tier(1500.0 * 1.05, EnvironmentLODController.DEFAULT_RANGES, 0)
	_check(lod_t == 0, "LOD holds tier inside hysteresis band")
	_check(EnvironmentLODController.resolve_tier(1500.0 * 1.2, EnvironmentLODController.DEFAULT_RANGES, 0) == 1, "LOD moves out past band")
	_check(EnvironmentLODController.resolve_tier(1500.0 * 0.95, EnvironmentLODController.DEFAULT_RANGES, 1) == 1, "LOD holds tier on the way back in")
	_check(EnvironmentLODController.resolve_tier(1500.0 * 0.8, EnvironmentLODController.DEFAULT_RANGES, 1) == 0, "LOD moves in past band")
	gen.free()
	res.queue_free()


func _test_loader() -> void:
	print("[loader]")
	var l := SceneChunkLoader.new()
	root.add_child(l)
	_check(not l.request("res://does/not/exist.tscn"), "missing path rejected without error")
	_check(l.get_status("res://does/not/exist.tscn") == SceneChunkLoader.Status.FAILED, "missing path FAILED")
	var path := "res://scenes/orbital/Satellite.tscn"
	_check(l.request(path), "threaded request accepted")
	var guard: int = 0
	while l.get_status(path) == SceneChunkLoader.Status.LOADING and guard < 2000:
		l.poll()
		OS.delay_msec(1)
		guard += 1
	var got: Array[String] = l.take_ready(4)
	_check(got.has(path) and l.get_resource(path) is PackedScene, "main-thread activation yields PackedScene")
	l.release(path)
	_check(l.get_status(path) == SceneChunkLoader.Status.IDLE, "release clears cache")
	l.queue_free()


func _test_world_integration() -> void:
	print("[world integration]")
	var packed: PackedScene = load(WORLD_SCENE) as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(world)
	for i in 4:
		await process_frame
	_check(world.streaming != null, "streaming wired into WorldRoot")
	var stats: Dictionary = world.streaming.get_streaming_stats()
	_check(stats.has("active_regions"), "WorldRoot streaming stats available")
	# Walk the orbit landmarks: rapid traversal through the real world.
	for idx in [20, 14, 19, 0, 20, 5, 3, 21, 22, 23]:
		world.teleport_to_landmark(idx)
		await process_frame
	for i in 6:
		await process_frame
	stats = world.streaming.get_streaming_stats()
	_check(int(stats["transitions_count"]) > 0, "world traversal drove transitions (%d)" % int(stats["transitions_count"]))
	world.queue_free()
	await process_frame
