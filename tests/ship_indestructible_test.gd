extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# --- Sim ---
	var sim := Sim.new()
	sim.damage_hull(5.0)
	check(sim.hull < 100.0 and sim.hull > 1.0, "Ordinary hits still damage the hull")
	sim.damage_ship(500.0)
	check(sim.hull == 1.0 and not sim.teams[0]["eliminated"], "Extreme damage stops at 1 HP")
	sim.set_location("space")
	sim.hull = 3.0
	sim.pressure = 0.0
	for i in 600:
		sim.tick_systems(0.1)
	check(sim.hull == 1.0 and sim.in_space(), "Prolonged systems damage leaves the ship in flight")

	var game: Node = load("res://main.tscn").instantiate()
	game.settings_path = "user://ship_indestructible_%d.cfg" % Time.get_ticks_usec()
	root.add_child(game)
	game.set_process(false)
	game.opts["seed"] = 6184
	var old_mode := LobbyPages.play_mode
	LobbyPages.play_mode = "ranked"
	game.quick_deploy()
	var hud_sim: Sim = game.sim
	var flight: Flight = game.vessel
	game._swap_flight_location("space")
	hud_sim.damage_ship(900.0)
	flight.tick(0.01)
	check(hud_sim.hull == 1.0 and hud_sim.in_space() and game.world == flight
		and flight.ship.visible and not hud_sim.teams[0]["eliminated"], "Critical damage keeps the ship in service")
	game._swap_flight_location("planet_c")
	flight.touch_down(flight.landing_zone)
	game.disembark_ship()
	var moon: PlanetB = game.world_b
	moon._damage_ship(900.0, Vector3.ZERO)
	check(hud_sim.hull == 1.0 and hud_sim.on_surface("planet_c") and game.world == moon
		and moon._ship_targetable() and not hud_sim.teams[0]["eliminated"], "Moon fire leaves the ship on its pad")
	hud_sim.propellant = 0.0
	check(game.board_ship(), "Critical hull and an empty legacy fuel reserve still allow boarding")
	game._swap_flight_location("space")
	Input.action_press("move_forward")
	for frame in 25:
		flight.tick(0.05)
	Input.action_release("move_forward")
	check(flight.flight_speed > 0 and hud_sim.hull == 1.0
		and not hud_sim.teams[0]["eliminated"], "Free flight remains controllable with an empty legacy fuel reserve")

	# --- HUD overlap ---
	for dims in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.content_scale_size = dims
		root.size = dims
		var hud := Hud.new(false)
		root.add_child(hud)
		hud.update_empire(hud_sim)
		await process_frame
		await process_frame
		var bar := hud.alliance_bar.get_global_rect()
		var location_panel := hud.clock.get_parent().get_parent() as Control
		var others: Array = [location_panel.get_global_rect(), hud.radar.get_parent().get_parent().get_global_rect(), hud.board.get_parent().get_global_rect()]
		for c in hud.crew_cards:
			others.append(c["panel"].get_global_rect())
		for r in others:
			check(not bar.intersects(r), "alliance bar overlaps %s at %s (bar %s)" % [r, dims, bar])
		for c in hud.crew_cards:
			check(bar.position.y >= c["panel"].get_global_rect().end.y + 6.0, "alliance bar >= 6px below crew cards at %s" % dims)
		hud.free()

	for player in game.players + game.players_3d:
		player.stop()
		player.stream = null
	game.streams.clear()
	await process_frame
	game.queue_free()
	await process_frame
	await process_frame
	LobbyPages.play_mode = old_mode
	print("Ship indestructible: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
