## Exercises the real assembly, horizontal launch and landing code without input.
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
	for step in 121:
		var progress := float(step) / 120.0
		main.sim.auto_build["t"] = progress * Sim.AUTO_BUILD_SECONDS
		world._build_fx(progress, 1.0 / 60.0)
		world._outfit_fx(progress, 1.0 / 60.0)
	for arm in world.fx_arms:
		assert((arm["tip"] as Node3D).position.is_finite())
	world._fx_finish()
	for k in [0.0, 0.5, 1.0]:
		world._launch_ascent(k)
		assert(world.flame.visible)
		assert(is_zero_approx(world.ship_root.rotation.x))
	world.arrive_home()
	assert(world.ship_root.visible and not world.flame.visible)
	print("HARDWARE_RUNTIME_PASS: assembly, IK, horizontal launch and landing")
	main.free()
	quit()
