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
	LobbyPages.play_mode = "practice"
	g.start_match()
	check(not g.sim.all_parts_bought(), "slots start unbought")
	check(is_instance_valid(g.hud.shop_summary) and g.hud.shop_summary.text == UI.loadout_summary(g.sim),
		"HUD shows the shared summary before the first play frame")
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
	var pivot := g.world.ship_root.get_node("port/EnginePivot") as Node3D
	var nozzle := pivot.get_node("NozzleGlow") as Node3D
	var exit: Vector3 = pivot.get_meta("nozzle_exit")
	check(is_equal_approx(pivot.rotation.x, PI * 0.5) and exit.is_equal_approx(nozzle.position + Vector3.BACK * 0.12),
		"Parked drive and its nozzle exit follow the selected variant")
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
		if not g.sim.construction_supplied():
			actor.position = pad._lift_seat(g.sim.selected)
			g.pressed_now[KEY_E] = true
			pad._shop_interact(actor)
			g.pressed_now.clear()
			check(g.sim.shop_open and pad.lift_state == PlanetA.LiftState.GROUND,
				"elevator waits for reactor, engine and bridge")
		i += 1
	check(g.sim.confirmed_count() == 12 and g.sim.all_parts_bought(), "all twelve slots confirmed")
	check(UI.loadout_summary(g.sim).ends_with("Unbought: none — ready to build"), "no unbought slots remain")
	check(g.sim.set_variant("bridge", "lancer"), "external variant swap succeeds")
	check(g.hud.shop_summary.text == UI.loadout_summary(g.sim), "external purchase notification refreshes HUD immediately")
	# Exercise external set_variant calls, not only picker-driven rebuilding.
	g._process(.05)
	check(pad.ship_root.scale.is_equal_approx(Vector3.ONE * 1.45), "Earth ship retains uniform scale after a loadout refresh")
	for p in g.sim.parts:
		check(pad.slot_nodes[p["id"]]["node"].get_meta("ship_family") == g.sim.loadout[p["id"]], "external variant refreshes pad")
	for rival in pad.rival_ships:
		check(rival["node"].scale.is_equal_approx(Vector3.ONE * 1.45), "Earth rival uses the same uniform vessel scale")
		for slot in ShipCatalog.VARIANTS:
			check(rival["node"].get_node(NodePath(slot)).get_meta("ship_family") == g.sim.teams[rival["team"]]["loadout"][slot], "pad rival uses deterministic loadout")
	actor.position = pad.SHOP_DESK
	g.pressed_now[KEY_E] = true
	pad._shop_interact(actor)
	g.pressed_now.clear()
	check(pad.pad_stage == "shop" and pad.lift_state == PlanetA.LiftState.GROUND
		and pad.beacon_target.is_equal_approx(pad._lift_node(g.sim.selected).position),
		"completed shop desk directs the crew to the elevator")
	actor.position = pad._lift_seat(g.sim.selected)
	g.pressed_now[KEY_E] = true
	pad._shop_interact(actor)
	g.pressed_now.clear()
	check(g.mode == "play" and pad.pad_stage == "build" and not g.sim.shop_open
		and pad.lift_state == PlanetA.LiftState.BOARDING, "mixed build retains controls while boarding")
	var return_requested := false
	for frame in 470:
		if not return_requested and pad.lift_state == PlanetA.LiftState.DECK:
			# Complete the manual crane work via the sim's bulk assembly path.
			g.sim.auto_build["enabled"] = true
			check(g.sim.auto_assemble(Sim.AUTO_BUILD_SECONDS), "assembly fixture secures the mixed loadout")
			actor.position = pad._lift_seat(g.sim.selected)
			g.pressed_now[KEY_E] = true
			return_requested = true
		g._process(.05)
	check(pad.lift_state == PlanetA.LiftState.PARKED and g.sim.secured_count() == 12
		and pad.pad_stage == "ready" and g.mode == "play",
		"mixed ship finishes assembly within 470 frames")
	for p in g.sim.parts:
		check(pad.slot_nodes[p["id"]]["node"].get_meta("ship_family") == g.sim.loadout[p["id"]], "build FX preserve selected geometry")
	g.board_ship()
	g._swap_flight_location("space")
	g._ensure_world_b()
	check(g.world.ship.scale.is_equal_approx(Vector3.ONE * 1.45), "flight ship uses the same uniform vessel scale")
	for team in 4:
		check(g.world_b.rival_ships[team]["node"].scale.is_equal_approx(Vector3.ONE * 1.45),
			"Moon bay %d ship uses the same uniform vessel scale" % team)
	for slot in ShipCatalog.VARIANTS:
		check(g.world.ship.get_node(NodePath(slot)).get_meta("ship_family") == g.sim.loadout[slot], "flight uses loadout")
		for team in 4:
			var expected: Dictionary = g.sim.loadout if team == 0 else g.sim.teams[team]["loadout"]
			check(g.world_b.rival_ships[team]["node"].get_node(NodePath(slot)).get_meta("ship_family") == expected[slot], "Planet C · Moon uses team loadouts")
	g.free()
	await process_frame
	print("SHOP_PICKER_RESULT: %d failures" % failures)
	quit(1 if failures else 0)
