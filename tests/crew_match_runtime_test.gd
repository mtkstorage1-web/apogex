extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.autotest = true
	g.set_process(false)
	g.opts["seed"] = 4545
	g.quick_deploy()
	check(g.world is Flight and g.mode == "play", "quick deploy enters real flight")
	check(g.sim.all_parts_bought() and g.sim.secured_count() == 12 and g.sim.all_cargo_stowed(), "quick deploy completes paid build and checks")
	check(g.sim.teams[1]["phase"] == "outbound" and g.sim.teams[1]["planet"] == "space", "rival launch synchronized")
	for i in 100: g._process(0.05)
	check(g.sim.flight_time > 4.0 and g.sim.hull > 0.0, "flight sim and HUD run")
	g.sim.phase = "landing"
	g._end_cine("landing")
	var b: PlanetB = g.world
	g.sim.selected = 1
	var chip: Actor = b.actors[1]
	var starting_ammo: int = b.ammo
	g.lmb = true
	g._process(0.05)
	check(b.ammo == starting_ammo and not chip.weapon_drawn, "holstered weapon cannot fire")
	g.lmb = false
	g.pressed_now[KEY_B] = true
	g._process(0.05)
	for i in 30:
		g._process(0.02)
		await process_frame
	check(chip.weapon_ready(), "B completes the draw animation")
	check(chip.weapon_grip.get_parent() is BoneAttachment3D, "weapon attached to the real hand bone")
	check(chip.held_weapon.rotation.y == 0.0 and chip.weapon_muzzle.position.z < -0.5, "barrel and muzzle point forward away from the character")
	var minimum_foot := INF
	for foot in chip.ground_feet: minimum_foot = minf(minimum_foot, (chip._transform_from_actor(chip.skeleton) * chip.skeleton.get_bone_global_pose(foot).origin).y)
	check(absf(minimum_foot - 0.06) < 0.04, "Chip animated feet stay grounded")
	g.lmb = true
	g._process(0.05)
	g.lmb = false
	check(b.ammo < starting_ammo and g.sim.metrics["shots"] > 0, "drawn gun consumes ammo when fired")
	g.pressed_now[KEY_R] = true
	g._process(0.05)
	for i in 30: g._process(0.05)
	check(b.ammo == 24, "reload completes and restores magazine")
	g.pressed_now[KEY_B] = true
	g._process(0.05)
	for i in 12: g._process(0.05)
	check(not chip.weapon_drawn and chip.weapon_blend <= 0.0, "B returns to empty hands")
	b._damage_rival(1, 48.0)
	check(is_equal_approx(b.rivals[1]["hp"], 52.0), "shots reduce rival health")
	b._damage_rival(1, 60.0)
	check(g.sim.teams[1]["stun"] > 0.0 and g.sim.metrics["stuns"] > 0, "lethal damage knocks the rival out")
	b._downed()
	g._process(0.05)
	check(chip.is_downed and b.down_t > 0.0, "player knockout starts a grounded collapse")
	for i in 65: g._process(0.05)
	check(b.down_t <= 0.0 and not chip.is_downed, "player recovers at the ramp after the knockout")
	g.sim.selected = 0
	g.pressed_now[KEY_C] = true
	g._process(0.05)
	check(g.sim.crew_order == "recover", "C orders real teammates")
	g.pressed_now[KEY_Z] = true
	g._process(0.05)
	check(g.sim.priority_flag >= 0, "Z assigns a priority sample")
	g.pressed_now[KEY_M] = true
	g._process(0.05)
	check(g.hud.tactical_panel.visible, "M opens tactical overlay")
	check(b.get_node("FrontierArena").get_child_count() > 100, "tactical arena instantiated with real cover")
	check(not b._line_clear(Vector3(-5, 1.25, 0), Vector3(5, 1.25, 0)) if _cover_fixture(b) else false, "rock cover blocks fire")
	b.blockers.pop_back()
	b.suit_hp[0] = 40.0
	b.last_hit[0] = 0.0
	b._tactics(1.0)
	check(b.suit_hp[0] > 40.0, "suit recovers out of combat")
	g.sim.selected = 1
	b.field_hp = 55.0
	g.sim.selected = 0
	check(b.field_hp != 55.0, "role switching preserves independent suit health")
	g.sim.selected = 0
	g.sim.priority_flag = 10
	for i in 900: g._process(0.05)
	check(g.sim.metrics["loads"] > 0, "AI raider navigates out, extracts, and returns a sample to the ship")
	check(g.sim.metrics["captures"] > 0, "AI raider extracts a sample during the live simulation")
	for i in 6500: g._process(0.05)
	check(g.sim.teams[1]["delivered"] + g.sim.teams[2]["delivered"] + g.sim.teams[3]["delivered"] > 0, "rivals navigate the arena, load samples, return, and score")
	g.pause()
	check(not g.hud.tactical_panel.visible and g.mode == "paused", "pause closes tactical overlay")
	g.resume()
	check(g.mode == "play", "resume restores gameplay")
	g.sim.finish_match("Runtime test complete")
	g.show_debrief()
	check(g.mode == "debrief", "debrief renders crew telemetry")
	var previous_seed: int = g.sim.match_seed
	g.rematch()
	check(g.sim.match_seed == previous_seed and g.world is Flight, "same-seed rematch restarts quick deployment")
	for player in g.players:
		player.stop()
		player.stream = null
	g.streams.clear()
	await create_timer(0.1).timeout
	g.queue_free()
	chip = null
	b = null
	g = null
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("Crew match runtime: %d failures" % failures)
	quit(failures)

func _cover_fixture(b: PlanetB) -> bool:
	b.blockers.append({"c": Vector2.ZERO, "r": 2.0, "cover": true})
	return true
