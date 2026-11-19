extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	g.start_match()
	g._end_cine("intro")
	check(not g.sim.all_parts_bought(), "slots start unbought")
	g.open_picker("port")
	check(g.mode == "play" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "picker releases mouse in play mode")
	var actor: Actor = g.world.actors[g.sim.selected]
	var before := actor.position
	var time: float = g.sim.time
	g._process(.05)
	check(actor.position == before and g.sim.time == time, "modal freezes movement and simulation")
	g.picker.highlight(1)
	var credits: int = g.sim.credits
	g.picker.buy()
	check(g.sim.loadout["port"] == "lancer" and g.sim.credits == credits - 117, "buy charges chosen variant")
	check(g.sim.slot_confirmed("port"), "picker confirms live part")
	check(not UI.loadout_summary(g.sim).get_slice("Unbought: ", 1).contains("port"), "summary excludes confirmed port")
	check(g.hud.shop_summary.text == UI.loadout_summary(g.sim), "visible HUD refreshes immediately")
	check(g.world.slot_nodes["port"]["node"].get_meta("ship_family") == "lancer", "pad updates chosen geometry")
	check(g.world.ship_root.get_node("EngineExhaust").get_child(0).position.is_equal_approx(g.world.ship_root.get_node("port").transform * g.world.ship_root.get_node("port/NozzleGlow").position + Vector3(0, 0, .12)), "pad exhaust follows variant")
	g.picker.highlight(0)
	g.picker.buy()
	check(g.sim.credits == credits - 180, "swap charges difference")
	g.picker.highlight(1)
	g.picker.buy()
	check(g.sim.credits == credits - 117 and g.sim.slot_confirmed("port"), "cheaper swap refunds difference and stays confirmed")
	g.picker.highlight(0)
	g.picker.buy()
	g.sim.credits = 0
	g.picker.highlight(3)
	check(g.picker.confirm.disabled, "unaffordable confirm disabled")
	g.picker.buy()
	check(g.sim.loadout["port"] == "kestrel", "failed purchase preserves selection")
	g.picker.close()
	check(g.picker == null and g.mode == "play", "close returns to play")
	var pad = g.world
	actor.position = pad.SHOP_DESK
	g.pressed_now[KEY_E] = true
	pad._shop_interact(actor)
	g.pressed_now.clear()
	check(g.sim.shop_open and not g.sim.auto_build["enabled"], "desk rejects incomplete confirmations")
	g.sim.credits = 10000
	var families := ["bulwark", "halo", "lancer", "hauler", "kestrel"]
	var i := 0
	for p in g.sim.parts:
		g.open_picker(p["id"])
		g.picker.highlight(g.picker.families.find(families[i % 5]))
		g.picker.buy()
		check(g.sim.slot_confirmed(p["id"]), "mixed picker selection confirms slot")
		check(g.picker.summary.text == UI.loadout_summary(g.sim), "modal summary refreshes immediately")
		g.picker.close()
		if i < 11:
			actor.position = pad.SHOP_DESK
			g.pressed_now[KEY_E] = true
			pad._shop_interact(actor)
			g.pressed_now.clear()
			check(not g.sim.auto_build["enabled"], "desk requires every one of twelve slots")
		i += 1
	check(g.sim.confirmed_count() == 12 and g.sim.all_parts_bought(), "all twelve slots confirmed")
	check(UI.loadout_summary(g.sim).ends_with("Unbought: none — ready to build"), "no unbought slots remain")
	check(g.sim.set_variant("bridge", "lancer"), "external variant swap succeeds")
	check(g.hud.shop_summary.text == UI.loadout_summary(g.sim), "external purchase notification refreshes HUD immediately")
	# Exercise external set_variant calls, not only picker-driven rebuilding.
	g._process(.05)
	for p in g.sim.parts:
		check(pad.slot_nodes[p["id"]]["node"].get_meta("ship_family") == g.sim.loadout[p["id"]], "external variant refreshes pad")
	for rival in pad.rival_ships:
		for slot in ShipCatalog.VARIANTS:
			check(rival["node"].get_node(NodePath(slot)).get_meta("ship_family") == g.sim.teams[rival["team"]]["loadout"][slot], "pad rival uses deterministic loadout")
	actor.position = pad.SHOP_DESK
	g.pressed_now[KEY_E] = true
	pad._shop_interact(actor)
	g.pressed_now.clear()
	check(g.mode == "play" and pad.pad_stage == "build", "mixed build retains controls")
	for frame in 470: g._process(.05)
	check(g.sim.secured_count() == 12 and pad.pad_stage == "erect_wait", "mixed ship finishes assembly and outfitting")
	for p in g.sim.parts:
		check(pad.slot_nodes[p["id"]]["node"].get_meta("ship_family") == g.sim.loadout[p["id"]], "build FX preserve selected geometry")
	g._begin_flight(Transform3D(Basis.IDENTITY, Vector3(0, 900, -150)))
	for slot in ShipCatalog.VARIANTS:
		check(g.world.ship.get_node(NodePath(slot)).get_meta("ship_family") == g.sim.loadout[slot], "flight uses loadout")
		for team in 4:
			var expected: Dictionary = g.sim.loadout if team == 0 else g.sim.teams[team]["loadout"]
			check(g.world_b.rival_ships[team]["node"].get_node(NodePath(slot)).get_meta("ship_family") == expected[slot], "Planet B uses team loadouts")
	g.free()
	await process_frame
	print("SHOP_PICKER_RESULT: %d failures" % failures)
	quit(1 if failures else 0)
