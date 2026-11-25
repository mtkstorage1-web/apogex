extends SceneTree

const Builder := preload("res://scripts/ship_builder.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1


func run() -> void:
	var old_mode := LobbyPages.play_mode
	var old_preset := LobbyPages.arena_preset
	var old_home := LobbyPages.arena_home
	var game = load("res://main.tscn").instantiate()
	var settings_file := "user://arena_clash_runtime_%d.cfg" % Time.get_ticks_usec()
	game.settings_path = settings_file
	root.add_child(game)
	game.autotest = true
	game.set_process(false)
	game.opts["seed"] = 4545
	game.opts["selected"] = 0
	game._lobby_set_mode("arena_clash")
	game._set_arena_preset("short")
	game._set_arena_home("planet_a")
	var saved := ConfigFile.new()
	check(saved.load(settings_file) == OK
		and saved.get_value("profile", "play_mode") == "arena_clash"
		and saved.get_value("profile", "arena_preset") == "short", "Lobby persists Arena Clash and the Short preset")
	game.start_match()
	check(game.world is PlanetA and game.arena_clash != null and game.mode == "play", "Arena Clash opens in Planet A")
	if game.arena_clash != null and game.world is PlanetA:
		await _play_match(game)
	_test_crimson_home(game)
	for player in game.players:
		player.stop()
		player.stream = null
	game.streams.clear()
	game.queue_free()
	await process_frame
	await process_frame
	LobbyPages.play_mode = old_mode
	LobbyPages.arena_preset = old_preset
	LobbyPages.arena_home = old_home
	DirAccess.remove_absolute(settings_file)
	print("Arena Clash runtime: %d/%d checks passed" % [checks - failures, checks])
	quit(failures)


## Real boarding path: E at the ramp foot walks up through the hatch, then E at the cockpit seat.
func _board_via_ramp(game, crew: Actor) -> bool:
	for i in 30:
		if game._ramp_live():
			break
		game._process(0.05)
	crew.position = game.cockpit_position()
	game.pressed_now[KEY_E] = true
	game._process(0.05)
	for i in 200:
		if game.interior_active():
			break
		game._process(0.05)
	if not game.interior_active():
		return false
	game.interior.actor(game.sim.selected).position = preload("res://scripts/ship_interior.gd").STATION_POS["cockpit"]
	game.pressed_now[KEY_E] = true
	game._process(0.05)
	return game.piloting and not game.interior_active()


func _play_match(game) -> void:
	var clash = game.arena_clash
	var earth: PlanetA = game.world
	check(game.sim.empire == null and clash.to_snapshot()["seed"] == 4545,
		"Main starts seeded scene-driven combat without Empire")
	check(game.hud.clock.text == "04:00" and game.hud.subtitle.text.contains("4000 CR"),
		"HUD shows the running match clock and credits")
	earth.actor(0).position = earth.shop_computer
	game.pressed_now[KEY_E] = true
	game._process(0.05)
	var builder := game.picker as Builder
	check(is_instance_valid(builder), "Planet A shop interaction opens the real Ship Builder")
	if not is_instance_valid(builder):
		return
	for slot in ["reactor", "engine", "bridge"]:
		builder._select_variant(slot, "kestrel")
	builder._purchase_button.pressed.emit()
	check(clash.squads["orange"]["credits"] == 3500 and game.sim.credits == 3500, "Partial loadout debits the authoritative construction credits")
	check(clash.squads["orange"]["building"].size() == 3, "Purchasing starts installation on all three slots")
	game._process(4.0)
	check(game.sim.secured_count() == 3 and clash.squads["orange"]["flight_capable"]
		and game.hud.subtitle.text.contains("3/12 BUILT"), "Completed installations update the pad ship and home HUD")
	check(_board_via_ramp(game, earth.actor(0)) and game.vessel.grounded, "Walking up the ramp boards on the home pad")
	game.disembark_ship()
	earth.actor(0).position = earth.shop_computer
	game.pressed_now[KEY_E] = true
	game._process(0.05)
	var reopened := game.picker as Builder
	check(is_instance_valid(reopened), "A parked squad can order optional parts after boarding")
	if is_instance_valid(reopened):
		reopened._go_to_step(Builder.BUILD_ORDER.find("port"))
		reopened._select_variant("port", "lancer")
		reopened._purchase_button.pressed.emit()
		game._process(ArenaClashSim.BUILD_SECONDS)
		var port: Node3D = game.vessel.ship.get_node("port")
		check(port.visible and port.get_meta("ship_family") == "lancer" and not earth.ship_root.visible,
			"An optional module updates the parked ship and preserves the active exterior")
	_board_via_ramp(game, earth.actor(0))
	game._process(85.0)
	check(clash.combatants.size() == 28 and game.world == earth, "AI arrives without waiting for the player")
	_land_on_moon(game)
	check(game.world is PlanetB and not game.piloting, "Player enters the live arena on touchdown and exit")
	var moon: PlanetB = game.world
	var count := {"planet_a": 0, "planet_b": 0}
	for entry in moon.arena_actors.values():
		if entry["actor"] is Actor:
			count[entry["state"]["alliance"]] += 1
	check(count == {"planet_a": 16, "planet_b": 16}, "Frontier Arena has 32 Actor combatants split 16 per alliance")
	check(moon.flag_nodes.is_empty() and moon.rivals.is_empty() and moon.empire_layer == null
		and moon.priority_beacon == null and game.sim.flags.is_empty(), "Flags, expedition rivals and Empire are inactive")
	if moon.arena_actors.size() != 32:
		return

	var player: Actor = game.player_actor()
	var enemy: Actor = moon.arena_actors["crimson:1"]["actor"]
	var target: Dictionary = clash.combatant("crimson:1")
	check(player == moon.arena_actors["orange:0"]["actor"] and clash.combatant("orange:0")["health"] == 120.0,
		"Player controls their selected Orange seat and receives their built-module bonuses")
	check(moon.combat_hud._hp == 120.0 and moon.combat_hud._shield == 95.0
		and moon.combat_hud.vitals_limits == Vector2(120.0, 95.0), "HUD displays the actual bonus health and shield counts")
	# Use an open patch inside the actual arena and aim through the game's camera.
	var firing_position := Vector3.ZERO
	for x in range(-30, 31, 2):
		var from := Vector3(x, 0, 35)
		var to := from + Vector3.FORWARD * 4.0
		if moon.collide(from) == from and moon.collide(to) == to and moon._line_clear(from + Vector3.UP, to + Vector3.UP):
			firing_position = from
			break
	check(firing_position != Vector3.ZERO, "Found a clear firing lane in the authored arena")
	player.position = firing_position
	enemy.position = firing_position + Vector3.FORWARD * 4.0
	game.yaw = 0.0
	game.pitch = -0.1
	game.first_person = true
	for i in 12:
		game._process(0.04)
		await process_frame
	# Return the test target to the sightline after the AI warm-up.
	enemy.position = firing_position + Vector3.FORWARD * 4.0
	var previous_vitals: float = target["health"] + target["shield"]
	var shots: int = game.sim.metrics["shots"]
	game.lmb = true
	game._process(0.05)
	game.lmb = false
	check(game.sim.metrics["shots"] > shots and target["health"] + target["shield"] < previous_vitals,
		"Player fire ray damages the authoritative enemy state")
	var allied: Dictionary = clash.combatant("orange:1")
	var allied_shield: float = allied["shield"]
	moon._arena_hit("orange:0", "orange:1", 999.0)
	check(allied["shield"] == allied_shield, "Scene-driven hits cannot damage an ally")
	var score: int = clash.get_score()["planet_a"]
	moon._arena_hit("orange:0", "crimson:1", 999.0)
	game._process(0.05)
	check(clash.get_score()["planet_a"] == score + 1 and not enemy.visible
		and moon.combat_hud._feed[0]["text"] == "orange-Finn eliminated crimson-Chip"
		and moon.combat_hud._team_scores[0]["target"] == 30, "A lethal hit updates the score, feed and actor visibility")
	moon._arena_hit("crimson:0", "orange:0", 999.0)
	game._process(0.05)
	check(not player.visible and game.hud._prompt_text == "RESPAWNING", "Player knockout shows the squad-wave countdown")
	game._process(8.0)
	check(player.visible and player.position.is_equal_approx(moon.arena_actors["orange:0"]["spawn"]) and enemy.visible,
		"Respawn waves return both combatants to their spawn points")

	var samples := 120
	var started := Time.get_ticks_usec()
	var tick_usec := 0
	for i in samples:
		var tick_started := Time.get_ticks_usec()
		game._process(1.0 / 60.0)
		tick_usec += Time.get_ticks_usec() - tick_started
		await process_frame
	print("Arena Clash headless (32 actors, %d frames): %.2f ms/frame, %.2f ms gameplay tick" % [
		samples, float(Time.get_ticks_usec() - started) / (1000.0 * samples), float(tick_usec) / (1000.0 * samples)])
	var score_before: Dictionary = clash.get_score()
	for i in 360:
		game._process(0.05)
	check(clash.get_score() != score_before, "Live AI navigates cover and scores without simulated auto-attacks")

	game._process(clash.time_left + 0.25)
	var lobby_button: Button
	for button in game.menu_root.find_children("*", "Button", true, false):
		if button.text == "RETURN TO LOBBY":
			lobby_button = button
	check(clash.is_finished() and game.mode == "debrief" and is_instance_valid(lobby_button),
		"Finishing the arena opens the debrief with a return button")
	var captions: Array[String] = []
	for label in game.menu_root.find_children("*", "Label", true, false):
		captions.append(label.text)
	var final_score: Dictionary = clash.get_score()
	var record: Dictionary = clash.combatant("orange:0")
	check("PLANET A  %d" % final_score["planet_a"] in captions
		and "PLANET B  %d" % final_score["planet_b"] in captions
		and "%d KILLS  ·  %d DEATHS" % [record["kills"], record["deaths"]] in captions,
		"Debrief displays the final scores and player kills and deaths")
	if not is_instance_valid(lobby_button):
		return
	lobby_button.pressed.emit()
	check(game.mode == "menu" and game.arena_clash == null, "Debrief returns to the lobby and clears the active match")
	await process_frame

	game.start_match()
	clash = game.arena_clash
	game._process(90.0)
	check(game.world is PlanetA and clash.combatant("orange:0").is_empty()
		and clash.combatants.size() == 28, "An unfinished squad stays home while AI squads join")


func _land_on_moon(game) -> void:
	game._swap_flight_location("space")
	game._swap_flight_location("planet_c")
	game.vessel.touch_down(game.vessel.landing_zone)
	game.disembark_ship()
	game._process(0.05)


func _test_crimson_home(game) -> void:
	game._set_arena_home("planet_b")
	game.start_match()
	var twin: PlanetA = game.world_planet_b
	check(game.world == twin and game.arena_clash.player_squad == "crimson"
		and twin.ship_root.visible and twin.position == Universe.B_ORIGIN, "Crimson starts with its ship on the Planet B pad")
	var earth: PlanetA = game.world_a
	if earth == null:
		earth = PlanetA.new()
		earth.setup(game, false)
		game.universe.add_child(earth)
	var equivalent := true
	for path in ["LaunchPad", "Buildings/PartsShop", "PartRacks", "SystemCheckConsoles"]:
		equivalent = equivalent and twin.editable_root.has_node(path) and earth.editable_root.has_node(path)
	check(equivalent and twin.editable_root != earth.editable_root
		and twin.slot_nodes.keys() == earth.slot_nodes.keys() and twin.launch_desk == earth.launch_desk,
		"Both home worlds bind independent copies of the same pad, shop and build layout")
	var banner := twin.get_node("HomeBanner") as Label3D
	check(banner.text == Universe.B_LABEL and banner.modulate == Color.html(Sim.EMPIRE_COLORS["crimson"])
		and earth.accent != twin.accent, "Planet B uses its crimson coalition accent and name banner")
	for i in range(1, 4):
		var squad: Dictionary = twin._pad_squad(i)
		var expected_id: String = EmpireSim.ALLIANCE_SQUADS["planet_b"][i]
		check(squad["id"] == expected_id and squad["color"] == Color.html(Sim.EMPIRE_COLORS[expected_id]),
			"Planet B pad %d uses the %s squad color" % [i, expected_id])
	var universe: Universe = game.universe
	check(universe.planet_a.position == Universe.A_ORIGIN and universe.planet_b.position == Universe.B_ORIGIN
		and universe.planet_c.position == Universe.C_ORIGIN and Universe.A_ORIGIN != Universe.B_ORIGIN
		and Universe.B_ORIGIN != Universe.C_ORIGIN and Universe.C_ORIGIN != Universe.A_ORIGIN,
		"Three distinct authored planet positions match the flight origins")
	check(universe.body_a.get_parent() == universe.planet_a and universe.body_b.get_parent() == universe.planet_b
		and universe.body_c.get_parent() == universe.planet_c and universe.body_b.has_node("Clouds")
		and not universe.body_c.has_node("Clouds"), "Earth, its twin and the Moon each have the correct orbital body")
	for slot: String in ArenaClashSim.FLIGHT_PARTS:
		game.sim.buy_part(slot)
	game._process(89.0)
	check(_board_via_ramp(game, twin.actor(0)) and game.sim.on_surface("planet_b"), "Crimson boards on the Earth twin")
	_land_on_moon(game)
	check(game.player_actor() == game.world_b.arena_actors["crimson:0"]["actor"]
		and game.vessel.position.is_equal_approx(Universe.C_ORIGIN + Vector3(0, 0, -62)),
		"Crimson lands at its own coalition bay and controls its seat")
	var foes: Array = game.world_b._foes()
	check(foes.size() == 16 and foes.all(func(entry: Dictionary) -> bool:
		return entry["state"]["alliance"] == "planet_a"), "Crimson weapon targeting selects Planet A combatants")
