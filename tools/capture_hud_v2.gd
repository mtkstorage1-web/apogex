extends "res://tools/capture_tminus_upgraded.gd"
## Run with a graphical display. Reuses the original live-window capture harness.

func _capture() -> void:
	if not _require(DisplayServer.get_name() != "headless", "A graphical Godot window is required"):
		return
	directory = ProjectSettings.globalize_path("res://artifacts/hud_v2")
	if not _require(DirAccess.make_dir_recursive_absolute(directory) == OK, "Could not create capture directory"):
		return

	root.size = SIZE
	var config := ConfigFile.new()
	config.set_value("audio", "muted", true)
	config.set_value("controls", "touch_mode", "off")
	config.set_value("graphics", "resolution", SIZE)
	settings_path = "user://tminus-hud-v2-capture-%d.cfg" % OS.get_process_id()
	if not _require(config.save(settings_path) == OK, "Could not save capture settings"):
		return
	game = preload("res://main.tscn").instantiate()
	game.settings_path = settings_path
	root.add_child(game)
	current_scene = game
	game.autotest = true
	game.set_process(false)
	game.opts["seed"] = 4545
	game.opts["selected"] = 0
	LobbyPages.play_mode = "arena_clash"
	LobbyPages.arena_home = "planet_a"
	LobbyPages.arena_preset = "short"

	game.show_select()
	_step_for(0.5)
	game.cam.attributes = null
	await create_timer(0.55).timeout
	if not await _save("01-lobby.png"):
		return
	game.start_match()
	var earth := game.world as PlanetA
	var crew := earth.actor(game.sim.selected)
	crew.position = earth.actors[1].position + Vector3(-2, 0, 3)
	_step_for(0.5)
	if not await _save("02-planet-a-on-foot.png"):
		return

	game.open_ship_builder()
	var builder: Control = game.picker
	for slot in ["reactor", "engine", "bridge"]:
		builder._select_variant(slot, "kestrel")
	builder._go_to_step(builder.BUILD_ORDER.find("engine"))
	if not await _save("03-ship-builder.png"):
		return
	builder._purchase_button.pressed.emit()
	_step_for(4.1)
	crew.position = game.cockpit_position()
	_tap(KEY_E)
	if not _require(game.piloting, "Could not board on Planet A"):
		return
	Input.action_press("jump")
	_step_for(1.1)
	Input.action_release("jump")
	Input.action_press("jump")
	Input.action_press("move_forward")
	_step_for(0.35)
	Input.action_release("move_forward")
	Input.action_release("jump")
	if not await _save("04-surface-vtol.png"):
		return
	if not _require(_fly_to_space(), "Could not fly into space"):
		return

	var flight: Flight = game.vessel
	# Move into the normal Moon approach volume so the landing prompt is visible.
	var origin := Universe.C_ORIGIN
	var from_moon := (Universe.A_ORIGIN - origin).normalized()
	flight.position = origin + from_moon * (game.universe.body_radius("planet_c") + 1600.0)
	flight.basis = Basis.looking_at((-from_moon + Vector3.UP * 0.72).normalized(), Vector3.UP)
	_step_for(0.4)
	if not await _save("05-space-flight.png"):
		return

	game.arena_clash.tick(85.0)
	game._swap_flight_location("planet_c")
	flight.touch_down(flight.landing_zone)
	game.disembark_ship()
	var moon := game.world as PlanetB
	var player: Actor = game.player_actor()
	if not _require(moon.arena_actors.has("crimson:1"), "The Crimson squad did not enter the arena"):
		return
	var enemy: Actor = moon.arena_actors["crimson:1"]["actor"]
	var lane := Vector3(0, 0, 35)
	for x in range(-30, 31, 2):
		var spot := Vector3(x, 0, 35)
		if moon.collide(spot) == spot and moon._line_clear(spot + Vector3.UP, spot + Vector3.UP + Vector3.FORWARD * 8):
			lane = spot
			break
	player.position = lane
	enemy.position = lane + Vector3.FORWARD * 8.0
	game.yaw = 0.0
	game.pitch = -0.10
	game.first_person = true
	_step_for(0.5)
	moon._arena_hit("orange:0", "crimson:2", 999.0)
	moon.combat_hud.trigger_damage(true)
	_step_for(0.3)
	if not await _save("06-planet-c-arena.png"):
		return

	game.arena_clash.tick(game.arena_clash.time_left + 1.0)
	game._finish_arena_clash()
	if not await _save("07-debrief.png"):
		return
	print("T-MINUS HUD v2 real-window capture complete")
	await _finish(0)
