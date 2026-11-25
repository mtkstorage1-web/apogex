extends SceneTree
## Physical boarding: the crew walk up the belly ramp, step through the hatch into the cabin
## airlock, walk to the cockpit to take the pilot seat, and leave again down the ramp.

const Interior := preload("res://scripts/ship_interior.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1


func step(game, seconds: float) -> void:
	for i in int(ceil(seconds / 0.05)):
		game._process(0.05)


func run() -> void:
	var old_mode := LobbyPages.play_mode
	var old_preset := LobbyPages.arena_preset
	var old_home := LobbyPages.arena_home
	var game = load("res://main.tscn").instantiate()
	var settings_file := "user://boarding_ramp_%d.cfg" % Time.get_ticks_usec()
	game.settings_path = settings_file
	root.add_child(game)
	game.autotest = true
	game.set_process(false)
	game.opts["seed"] = 4545
	game.opts["selected"] = 0
	game._lobby_set_mode("arena_clash")
	game._set_arena_preset("short")
	game._set_arena_home("planet_a")
	game.start_match()
	var earth: PlanetA = game.world
	var me: Actor = earth.actor(0)
	step(game, 0.2)
	check(game.boarding_ramp == null or not game.boarding_ramp.visible, "No ramp while the ship cannot fly")
	for slot in ArenaClashSim.FLIGHT_PARTS:
		game.sim.buy_part(slot)
	game.arena_clash.tick(ArenaClashSim.BUILD_SECONDS)
	step(game, 1.4)
	var ramp: BoardingRamp = game.boarding_ramp
	check(ramp != null and ramp.is_deployed(), "Ramp swings down once the ship is flight capable")
	if ramp == null:
		_finish(game, settings_file, old_mode, old_preset, old_home)
		return
	check(ramp.top.y - ramp.foot.y > 1.2 and ramp.run >= BoardingRamp.MIN_RUN, "Ramp climbs from the ground to the raised hatch")

	# Walk up by hand: the deck lifts the walker, the hull blockers do not push them off.
	me.position = game.cockpit_position()
	var out: Vector3 = -ramp.axis
	game.yaw = atan2(out.x, out.z)   # facing up the ramp (toward the hatch)
	var peak := 0.0
	var was_on_deck := false
	for i in 120:
		_hold(game, KEY_W, true)
		game._process(0.05)
		if game.interior_active():
			break
		peak = maxf(peak, me.position.y)
		was_on_deck = was_on_deck or ramp.on_deck(game.universe.to_local(me.global_position))
	_hold(game, KEY_W, false)
	check(was_on_deck and peak > 0.8, "Walking forward climbs the deck (peak %.2f m)" % peak)
	check(game.piloting and game.interior_active() and game.vessel.grounded, "Stepping through the hatch boards the ship and opens the cabin")
	if not game.interior_active():
		_finish(game, settings_file, old_mode, old_preset, old_home)
		return
	var inside: Actor = game.interior.actor(0)
	check(inside.position.distance_to(Interior.AIRLOCK_POS) < 0.8, "The player arrives in the airlock, not the pilot seat")
	check(not earth.actors.any(func(c: Actor) -> bool: return c.visible), "Crew are no longer standing outside")
	step(game, 0.2)
	var hidden_bots := 0
	for i in 4:
		if i != 0 and not game.interior.crew[i].visible:
			hidden_bots += 1
	check(hidden_bots >= 2, "Crew follow through the hatch one after another")
	step(game, 3.5)
	check(game.interior.crew.all(func(c: Actor) -> bool: return c.visible), "Whole crew is aboard after the walk-in")

	# Take the pilot seat at the cockpit.
	inside.position = Interior.STATION_POS["cockpit"]
	game.pressed_now[KEY_E] = true
	game._process(0.05)
	check(game.piloting and not game.interior_active(), "E at the cockpit takes the pilot seat")

	# E from the pilot seat on the ground steps out onto the top of the ramp.
	game.disembark_ship()
	step(game, 0.05)
	check(not game.piloting and ramp.on_deck(game.universe.to_local(me.global_position)) and me.visible, "Disembarking puts the player on the ramp")
	var y0 := me.position.y
	game.yaw = atan2(-out.x, -out.z)   # facing down the ramp
	for i in 30:
		_hold(game, KEY_W, true)
		game._process(0.05)
	_hold(game, KEY_W, false)
	check(me.position.y < y0 - 0.5 and not game.piloting, "Walking down the ramp lowers the player to the ground")

	# E at the ramp foot walks the player up on their own (mobile-friendly).
	me.position = game.cockpit_position()
	game.pressed_now[KEY_E] = true
	game._process(0.05)
	check(game._boarding_auto, "E at the ramp foot starts the walk up")
	for i in 120:
		game._process(0.05)
		if game.interior_active():
			break
	check(game.interior_active() and game.piloting, "Auto-walk carries the player through the hatch")
	if game.interior_active():
		game.interior.actor(0).position = Interior.AIRLOCK_POS
		game.pressed_now[KEY_E] = true
		game._process(0.05)
		check(not game.piloting and not game.interior_active() and ramp.on_deck(game.universe.to_local(me.global_position)),
			"E in the airlock leaves the ship onto the ramp")
		# Take off: the ramp folds away.
		game.board_ship()
		game.vessel.grounded = false
		step(game, 1.3)
		check(not ramp.visible, "Ramp stows once the ship lifts off")
	_finish(game, settings_file, old_mode, old_preset, old_home)


func _hold(game, key: int, down: bool) -> void:
	var action: String = game.KEY_ACTIONS[key]
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _finish(game, settings_file: String, old_mode: String, old_preset: String, old_home: String) -> void:
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
	print("Boarding ramp runtime: %d/%d checks passed" % [checks - failures, checks])
	quit(failures)
