extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	CombatFX.impact(world, Vector3(1, 2, 3), Color.RED)
	CombatFX.impact(world, Vector3.ZERO, Color.BLUE)
	var pool := world.get_node("ImpactPool")
	check(pool.get_child_count() == 2, "Concurrent impacts need independent emitters")
	var first := pool.get_child(0)
	var light := first.get_child(0)
	await create_timer(0.8).timeout
	check(not first.visible and not first.emitting, "Expired impact must stop and hide")
	CombatFX.impact(world, Vector3(4, 5, 6), Color.GREEN, 2.0, 8)
	check(pool.get_child_count() == 2, "Next impact must reuse idle emitter")
	check(first.visible and first.position == Vector3(4, 5, 6), "Reuse resets visibility and position")
	check(first.get_child(0) == light and light.light_color == Color.GREEN, "Reuse resets retained flash light")
	check(first.amount == 8, "Reuse updates burst size")
	var fx := ExhaustFX.create(0.5, 3.0)
	world.add_child(fx)
	var emitter: CPUParticles3D = fx.emitters[0]
	var exhaust_light: OmniLight3D = fx.lights[0]
	fx.hide()
	fx._process(0.016)
	check(not emitter.emitting and exhaust_light.light_energy == 0.0, "Hidden exhaust must stop emitting and lighting")
	fx.show()
	fx._process(0.016)
	check(fx.emitters[0] == emitter and emitter.emitting and fx.lights[0] == exhaust_light, "Exhaust activation must reuse particles and light")
	check(Gfx.unshaded(Color.RED) == Gfx.unshaded(Color.RED), "Unshaded materials must be shared")
	check(Gfx.unshaded(Color.RED, 0.2) != Gfx.unshaded(Color.RED, 0.8), "Alpha must distinguish cached materials")
	world.free()
	print("PERFORMANCE_RESULT: %d failures" % failures)
	quit(1 if failures else 0)
