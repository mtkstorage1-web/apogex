extends SceneTree

const Net = preload("res://scripts/tminus_net.gd")
const Layer = preload("res://scripts/empire_world_layer.gd")
const Rules = preload("res://scripts/empire_sim.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_mode := LobbyPages.play_mode
	LobbyPages.play_mode = "ranked"
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	LobbyPages.play_mode = "ranked"
	game.set_process(false)
	game.opts["seed"] = 6184
	game.start_match()
	var sim: Sim = game.sim
	_check(sim.empire != null and game.net is Net and game.world is PlanetA and sim.limit == 2400.0,
		"Main starts the default 40-minute Empire match with Planet A and a network bridge")
	if sim.empire != null:
		_test_worlds(game, sim)
	game.free()
	await process_frame
	await _test_enet()
	LobbyPages.play_mode = previous_mode
	quit(int(failures > 0))


func _test_worlds(game, sim: Sim) -> void:
	var empire := sim.empire
	var home: PlanetA = game.world_a
	var layer: Layer = home.empire_layer
	_check(layer.slots.size() == 6 and layer.slots["refinery"]["model"] == null,
		"Planet A starts with six terminals and refinery blueprint")
	empire.treasury["planet_a"] = 4000.0
	var funds: float = empire.treasury["planet_a"]
	_check(_use_terminal(layer, "refinery") and _use_terminal(layer, "refinery"),
		"Planet A refinery can be built and upgraded from the same terminal")
	_check(empire.treasury["planet_a"] == funds - 140.0 - 240.0
		and empire.structures["planet_a"]["refinery"]["tier"] == 2 and _has_mesh(layer, "refinery"),
		"Refinery upgrade spends the correct treasury credits and instantiates a Blender mesh")
	empire.damage_structure("planet_a", "refinery", 60.0, "crimson")
	funds = empire.treasury["planet_a"]
	_check(_use_terminal(layer, "refinery") and empire.structures["planet_a"]["refinery"]["hp"] == 380.0
		and empire.treasury["planet_a"] == funds - 30.0, "Repair restores damaged structure HP using the shared treasury")
	var shield_ok := _use_terminal(layer, "shield_gen")
	_check(shield_ok and layer.shield_dome.visible and _has_mesh(layer, "shield_gen"),
		"An online Shield Generator lights the Planet A vault dome")
	_check(_use_terminal(layer, "radar"), "Radar Relay online")
	for squad: Dictionary in empire.squads.values():
		squad["ai_enabled"] = false
	for part: Dictionary in sim.parts:
		sim.buy_part(part["id"])
	sim.shop_open = false
	sim.auto_build["enabled"] = true
	sim.auto_assemble(Sim.AUTO_BUILD_SECONDS)
	_check(game.board_ship() and game.piloting and sim.on_surface("planet_a"),
		"Empire ship can be boarded after construction")
	game._swap_flight_location("space")
	_check(game.world is Flight and game.world_b == null and empire.squads["orange"]["location"] == "space_to_b",
		"Departure marks Orange in space and leaves the Moon unloaded")
	empire.build_or_upgrade("planet_b", "shield_gen", "crimson")
	game.hud.toggle_tactical()
	game.hud.update_empire(sim)
	_check(game.hud.strategic_overview.is_visible_in_tree()
		and game.hud.strategic_contacts[0].text.split("  ").size() == 6,
		"Tactical map displays the three-zone overview with six structure dots")
	_land(game, "planet_c")
	var frontier: PlanetB = game.world_b
	var enemy: Layer = frontier.empire_layer
	enemy.sync_visuals()
	_check(enemy.slots.size() == 6 and enemy.shield_dome.visible and _has_mesh(enemy, "shield_gen")
		and not sim.empire_flag_available(sim.flags[12]), "Planet B shield protects the four vault flags")
	sim.selected = 1
	var terminal: Node3D = enemy.slots["shield_gen"]["terminal"]
	var center: Vector3 = enemy.slots["shield_gen"]["core"].position + enemy.slots["shield_gen"]["anchor"].position
	var hit := enemy.ray_core(center + Vector3.RIGHT * 3.0, Vector3.LEFT, 6.0)
	_check(hit.get("slot_id") == "shield_gen" and enemy.hit_core("shield_gen", 1).get("ok", false)
		and empire.structures["planet_b"]["shield_gen"]["hp"] < 300.0,
		"Surface weapon hit detection can damage the enemy shield core")
	var sabotage := enemy.interact(terminal.global_position, true)
	empire.tick(1.25)
	enemy.tick_terminal(1.25, terminal.global_position, true)
	_check(sabotage.get("ok", false) and enemy.shield_dome.visible, "Chip's sabotage takes time")
	empire.tick(0.25)
	enemy.tick_terminal(0.25, terminal.global_position, true)
	_check(not enemy.shield_dome.visible and sim.empire_flag_available(sim.flags[12]),
		"Chip disables the Planet B shield in 1.5 seconds and opens the vault")
	for stage in 3:
		sim.scan_flag(12, 0, 3, 10.0, 1.0)
	_check(sim.load_flag(0, 3, 1.0) and empire.squads["orange"]["flags_carried"] == ["planet_b_flag_13"],
		"Normal scan and ship loading transfer the vault flag to Orange")
	_check(game.board_ship(), "Loaded squad boards to return home")
	game._swap_flight_location("space")
	_land(game, "planet_a")
	funds = empire.treasury["planet_a"]
	home._deliver_step(0.8, 1.0)
	_check(empire.scores["planet_a"] == 1 and empire.treasury["planet_a"] == funds + 120.0,
		"Delivery pad scores for Planet A and credits 120 CR once")
	for tier in 3:
		_check(_use_terminal(layer, "hangar"), "Hangar tier %d built at its terminal" % (tier + 1))
	_check(_has_mesh(layer, "hangar"), "Hangar installs a real Blender mesh")
	game.board_ship()
	game._swap_flight_location("space")
	var transfer: Flight = game.vessel
	sim.damage_ship(1000.0)
	transfer.tick(0.01)
	_check(game.world == transfer and sim.in_space() and sim.hull == 1.0
		and transfer.ship.visible and not sim.teams[0]["eliminated"], "Critical damage leaves the Empire flight playable")
	_land(game, "planet_c")
	for stage in 3:
		sim.scan_flag(1, 0, 3, 10.0, 1.0)
	sim.load_flag(0, 3, 1.0)
	frontier._damage_ship(1000.0, Vector3.ZERO)
	_check(game.world == frontier and sim.on_surface("planet_c") and sim.hull == 1.0
		and empire.flags["planet_b_flag_02"]["state"] == "carried"
		and game.vessel.ship.visible, "Critical surface damage leaves the ship and its cargo on the Moon")
	empire.tick(1920.0 - empire.elapsed)
	sim.sync_empire_flags()
	_check(empire.overdrive and sim.flags[16]["state"] == "site"
		and sim.flags[17]["state"] == "site" and empire.flags["planet_b_gold_01"]["points"] == 2,
		"Act IV reveals two golden cores worth two points each")


func _land(game, planet: String) -> void:
	game._swap_flight_location(planet)
	game.vessel.touch_down(game.vessel.landing_zone)
	game.disembark_ship()


func _use_terminal(layer: Layer, id: String) -> bool:
	var terminal: Node3D = layer.slots[id]["terminal"]
	return layer.interact(terminal.global_position, false).get("ok", false)


func _has_mesh(layer: Layer, id: String) -> bool:
	var model: Node3D = layer.slots[id]["model"]
	return is_instance_valid(model) and not model.find_children("*", "MeshInstance3D", true, false).is_empty()


func _test_enet() -> void:
	var host_branch := Node.new()
	host_branch.name = "EmpireHost"
	root.add_child(host_branch)
	set_multiplayer(SceneMultiplayer.new(), host_branch.get_path())
	var client_branch := Node.new()
	client_branch.name = "EmpireClient"
	root.add_child(client_branch)
	set_multiplayer(SceneMultiplayer.new(), client_branch.get_path())
	var host: Node = load("res://main.tscn").instantiate()
	var client: Node = load("res://main.tscn").instantiate()
	host_branch.add_child(host)
	client_branch.add_child(client)
	host.set_process(false)
	client.set_process(false)
	LobbyPages.play_mode = "ranked"
	var result: Dictionary = host.net.host_match(0, 6184)
	var joined := false
	if result.get("ok", false):
		joined = client.net.join_match("127.0.0.1", result["port"]).get("ok", false)
	var connected := joined and await _wait_for(func() -> bool: return client.net.get_total_human_count() == 2)
	_check(connected, "Main host and client connect over ENet and receive alliance assignments")
	if connected:
		host.start_match()
		var started := await _wait_for(func() -> bool: return client.sim != null and client.world is PlanetA)
		_check(started and client.sim.empire_home == "planet_b" and client.sim.match_seed == 6184,
			"Host starts the same seeded Empire round on the assigned opposing alliance")
		if started:
			var layer: Layer = client.world_planet_b.empire_layer
			var sent := _use_terminal(layer, "refinery")
			var synced := await _wait_for(func() -> bool:
				return client.sim.empire.structures["planet_b"]["refinery"]["tier"] == 1)
			_check(sent and synced and host.sim.empire.structures["planet_b"]["refinery"]["tier"] == 1
				and host.sim.empire.treasury["planet_b"] == 160.0
				and client.sim.empire.treasury["planet_b"] == 160.0,
				"Client terminal RPC builds on the authoritative host and replicates the snapshot")
	var client_path := client_branch.get_path()
	var host_path := host_branch.get_path()
	client_branch.free()
	host_branch.free()
	set_multiplayer(null, client_path)
	set_multiplayer(null, host_path)
	await process_frame


func _wait_for(condition: Callable) -> bool:
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await process_frame
	return false


func _check(pass_check: bool, message: String) -> void:
	print(("PASS " if pass_check else "FAIL ") + message)
	failures += int(not pass_check)
