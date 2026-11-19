## Exercises the real assembly, hoisting, ignition and separation code without input.
extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.start_match()
	var world = main.world
	world._fx_init()
	assert(world.fx_boosters.size() == 2)
	for step in 121:
		main.sim.auto_build["t"] = float(step)/120.0*Sim.AUTO_BUILD_SECONDS
		world._build_fx(float(step)/120.0,1.0/60.0)
		world._erect_fx(float(step)/120.0,1.0/60.0)
		world._booster_fx(float(step)/120.0,1.0/60.0)
	for arm in world.fx_arms:
		assert((arm["tip"] as Node3D).position.is_finite())
	# Rigid attachment must survive the gravity turn, including the separation frame.
	world._launch_ascent(0.0, .1)
	for k in [.53, .60, .69, .70]:
		world._launch_ascent(k, .1)
		for bd in world.fx_boosters:
			var bn: Node3D = bd["node"]
			var attached: Transform3D = world.ship_root.transform * (bd["launch_local"] as Transform3D)
			assert(bn.transform.is_equal_approx(attached))
			assert(bn.basis.y.dot(-world.ship_root.basis.z) > .999)
			assert(bn.get_node("BoosterExhaust").visible == (k < .70))
	for step in range(85, 121):
		world._launch_ascent(float(step)/120.0, .1)
	for bi in world.fx_boosters.size():
		var bd: Dictionary = world.fx_boosters[bi]
		var from: Transform3D = bd["shed_from"]
		var bn: Node3D = bd["node"]
		assert(bn.position.y < from.origin.y)
		assert(absf(bn.position.x) > absf(from.origin.x))
	world.arrive_home()
	for bd in world.fx_boosters:
		assert(not (bd["node"] as Node3D).visible)
	var workshop := Workshop.new()
	root.add_child(workshop)
	workshop.setup(main,main.sp_design,true)
	for step in 190:
		workshop._pose_robot(Vector3(-16,3,sin(step*.1)*2.0),.1)
		workshop._launch(.1)
	assert(workshop.booster.position.is_finite())
	print("HARDWARE_RUNTIME_PASS: assembly, IK, hoists, both launchers, ignition, separation")
	quit()
