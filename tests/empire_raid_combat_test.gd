extends SceneTree

const Layer = preload("res://scripts/empire_world_layer.gd")
const Rules = preload("res://scripts/empire_sim.gd")
const DT := 0.05
const SETTINGS_PATH := "user://empire-raid-test-%d.cfg"
const REGRESSION_SUITES := ["hud_style", "pad_sequence_runtime"]

# Run the original suites in this tree and capture their normal exit codes.
const SUITE_ADAPTER := """
var tree: SceneTree
var result := -1
var root: Window:
	get: return tree.root
var process_frame: Signal:
	get: return tree.process_frame

func quit(code := 0) -> void:
	result = code
"""

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var play_mode := LobbyPages.play_mode
	LobbyPages.play_mode = "ranked"
	var settings := SETTINGS_PATH % OS.get_process_id()
	var game: Node = load("res://main.tscn").instantiate()
	game.settings_path = settings
	root.add_child(game)
	game.set_process(false)
	LobbyPages.play_mode = "ranked"
	game.opts["length"] = "standard"
	game.opts["seed"] = 6184
	game.new_sim()
	game.start_match()
	var home: PlanetA = game.world_a
	var sim: Sim = game.sim
	_check(home != null and home.empire_layer != null and sim.empire != null, "Ranked match enters Planet A with Empire rules")
	if home != null and home.empire_layer != null and sim.empire != null:
		await _test_home(game, home, sim.empire)
		_test_frontier_and_flight(game, sim)
	while game._graphics_applying:
		await process_frame
	game.queue_free()
	DirAccess.remove_absolute(settings)
	await process_frame

	LobbyPages.play_mode = play_mode
	for suite: String in REGRESSION_SUITES:
		await _run_regression(suite)
	print("%s EMPIRE_RAID_COMBAT (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(int(failures != 0))


func _test_home(game: Node, home: PlanetA, empire: Rules) -> void:
	var layer: Layer = home.empire_layer
	var pilot: Actor = home.actor(game.sim.selected)
	var build_pill: MeshInstance3D = layer.slots["refinery"]["build_beacon"]
	game.pressed_now[KEY_B] = true
	home.tick(DT)
	game.pressed_now.clear()
	_check(empire.act_number == 1 and empire.get_active_invaders("planet_a").is_empty()
		and layer.raid_groups.is_empty() and layer.find_children("Raid_*", "Node3D", false, false).is_empty()
		and pilot.held_weapon == null and build_pill.is_visible_in_tree(), "Act I keeps Planet A peaceful and shows the build pad beacon")

	for squad: Dictionary in empire.squads.values():
		squad["ai_enabled"] = false
	empire.elapsed = empire.duration * 0.2 - Rules.STEP
	empire.tick(Rules.STEP)
	var refinery: Node3D = layer.slots["refinery"]["terminal"]
	_check(layer.interact(refinery.global_position, false).get("ok", false) and not build_pill.visible,
		"Building at the normal refinery terminal clears its blueprint beacon")
	var refinery_state: Dictionary = empire.structures["planet_a"]["refinery"]
	var starting_hp: float = refinery_state["hp"]

	empire._set_phase(empire.squads["crimson"], "raid", "planet_a", 75.0)
	home.tick(DT)
	_check(layer.raid_groups.has("crimson"), "Act II Empire raid spawns a physical group on Planet A")
	if not layer.raid_groups.has("crimson"):
		return
	var raid: Dictionary = layer.raid_groups["crimson"]
	var units: Dictionary = raid["units"]
	var dropship: Node3D = raid["dropship"]
	var outside := false
	if is_instance_valid(dropship):
		# The normalized GLB is 16 m across. Test the full footprint, not just the origin.
		var footprint := Rect2(Vector2(dropship.position.x, dropship.position.z) - Vector2(8, 8), Vector2(16, 16))
		outside = not footprint.intersects(PlanetA.CRANE_CLAMP) and not footprint.intersects(home.shop_footprint)
		for route: Curve3D in home.gse_routes:
			for point: Vector3 in route.get_baked_points():
				outside = outside and not footprint.has_point(Vector2(point.x, point.z))
	_check(outside and is_instance_valid(dropship)
		and not dropship.find_children("*", "MeshInstance3D", true, false).is_empty()
		and dropship.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"Cinder Blender dropship lands outside the crane, shop, and conveyors without collision")
	_check(units.size() == 4, "Crimson deploys four remodeled crew Actors")
	if units.is_empty():
		return
	var lead: Actor = units.keys().front()
	var spawn := lead.position
	var refinery_pad: Node3D = layer.slots["refinery"]["anchor"]
	for step in 160:
		layer.tick_raid(DT, true)
		if refinery_state["hp"] < starting_hp:
			break
	var defend: Label3D = layer.slots["refinery"]["defend_label"]
	_check(lead.position.distance_to(refinery_pad.position) < spawn.distance_to(refinery_pad.position)
		and refinery_state["hp"] < starting_hp and defend.is_visible_in_tree()
		and defend.text.begins_with("DEFEND: ") and not layer.find_children("RaidBolt*", "MeshInstance3D", false, false).is_empty(),
		"Raiders march toward the refinery, fire physical bolts, damage HP, and expose the defend marker")

	var battery: Node3D = layer.slots["defense_turrets"]["terminal"]
	var built := bool(layer.interact(battery.global_position, false).get("ok", false))
	var health_before := _squad_health(units)
	layer.tick_raid(DT, true)
	var battery_anchor: Node3D = layer.slots["defense_turrets"]["anchor"]
	var turret := battery_anchor.get_node("DefenseTurretAim") as Node3D
	var tracked := layer.nearest_raider(turret.global_position, 165.0)
	var aligned := tracked != null and (-turret.global_basis.z).dot(
		turret.global_position.direction_to(Layer.raider_center(tracked))) > 0.99
	_check(built and turret.visible and aligned and _squad_health(units) < health_before,
		"Built Planet A battery tracks live raiders and damages them automatically")

	# Stop the battery after verifying its hit, so allied and player shots can be measured independently.
	empire.damage_structure("planet_a", "defense_turrets", 999.0, "crimson")
	var ally := home.actor(1)
	ally.position = lead.position + Vector3(0, 0, 12)
	health_before = _squad_health(units)
	for step in 15:
		home._bot(1, DT)
	_check(ally.weapon_drawn and _squad_health(units) < health_before,
		"An on-foot allied pad bot draws a weapon and damages a nearby raider")

	game.sim.selected = 1
	var player := home.actor(1)
	game.first_person = true
	var funds: float = empire.treasury["planet_a"]
	var hits: int = game.sim.metrics["hits"]
	var raid_node: Node3D = raid["root"]
	player.position = lead.position + Vector3(0, 0, 9)
	_aim_at(game, player, lead)
	game.pressed_now[KEY_B] = true
	home.tick(DT)
	game.pressed_now.clear()
	game._refresh_hud()
	_check(player.weapon_drawn and game.hud.crosshair.visible, "B draws the on-foot blaster and enables the Planet A crosshair")
	var reload_checked := false
	for step in 230:
		if units.is_empty():
			break
		var target: Actor = units.keys().front()
		player.position = target.position + Vector3(0, 0, 9)
		_aim_at(game, player, target)
		game.lmb = true
		home.tick(DT)
		if not reload_checked and home._defense_ammo[1] < PlanetA.DEFENSE_MAGAZINE:
			game.lmb = false
			game.pressed_now[KEY_R] = true
			home.tick(DT)
			game.pressed_now.clear()
			reload_checked = player.weapon_reload > 0.0 and home._defense_ammo[1] == PlanetA.DEFENSE_MAGAZINE
	game.lmb = false
	_check(reload_checked and game.sim.metrics["hits"] > hits, "R reloads and LMB resolves Planet A blaster ray hits")
	_check(units.is_empty() and empire.treasury["planet_a"] == funds + 4 * Layer.RAID_BOUNTY,
		"The player eliminates four raiders for 40 alliance credits each")
	_check(layer.raid_groups.is_empty() and empire.get_active_invaders("planet_a").is_empty()
		and empire.squads["crimson"]["phase"] == "return" and empire.squads["crimson"]["ship_hp"] > 0.0 and not defend.visible,
		"Wiping the squad clears the raid and sends the intact ship home")
	await process_frame
	_check(not is_instance_valid(raid_node) and not is_instance_valid(dropship), "The defeated squad and dropship are freed")

	empire._set_phase(empire.squads["amber"], "raid", "planet_a", 75.0)
	layer.tick_raid(DT, true)
	var retreat_node: Node3D = layer.raid_groups.get("amber", {}).get("root")
	var spawned := is_instance_valid(retreat_node)
	empire._set_phase(empire.squads["amber"], "return", "space_to_b", 75.0)
	layer.tick_raid(DT, true)
	await process_frame
	_check(spawned and not is_instance_valid(retreat_node) and layer.raid_groups.is_empty()
		and empire.squads["amber"]["phase"] == "return",
		"An EmpireSim retreat despawns the second ground squad and keeps its return phase")


func _aim_at(game: Node, player: Actor, target: Actor) -> void:
	for iteration in 2:
		game.follow_cam(player)
		var aim: Vector3 = game.cam.global_position.direction_to(Layer.raider_center(target))
		game.yaw = atan2(-aim.x, -aim.z)
		game.pitch = asin(aim.y)


func _squad_health(units: Dictionary) -> float:
	var total := 0.0
	for unit: Dictionary in units.values():
		total += float(unit["hp"])
	return total


func _test_frontier_and_flight(game: Node, sim: Sim) -> void:
	var empire := sim.empire
	for part: Dictionary in sim.parts:
		sim.buy_part(part["id"])
	sim.shop_open = false
	sim.auto_build["enabled"] = true
	sim.auto_assemble(Sim.AUTO_BUILD_SECONDS)
	_check(game.board_ship(), "Completed build boards on the home pad")
	game._swap_flight_location("space")
	_check(game.world is Flight and game.world_b == null, "Free space flight keeps unvisited surface unloaded")
	var shield := empire.build_or_upgrade("planet_b", "shield_gen", "crimson")
	game._swap_flight_location("planet_c")
	game.vessel.touch_down(game.vessel.landing_zone)
	game.disembark_ship()
	sim.selected = 1
	var frontier: PlanetB = game.world_b
	var layer: Layer = frontier.empire_layer
	layer.sync_visuals()
	var sabotage: Node3D = layer.sabotage_beacon
	var sabotage_text := sabotage.get_node("Label") as Label3D
	_check(shield.get("ok", false) and sabotage_text.is_visible_in_tree()
		and sabotage_text.text == "SABOTAGE SHIELD TO OPEN VAULT" and sabotage_text.visibility_range_end >= 180.0,
		"Planet C · Moon shows the long-range sabotage waypoint while the vault shield is active")
	var terminal: Node3D = layer.slots["shield_gen"]["terminal"]
	var started := layer.interact(terminal.global_position, true)
	empire.tick(1.5)
	layer.tick_terminal(1.5, terminal.global_position, true)
	_check(started.get("ok", false) and not sabotage.visible and sim.empire_flag_available(sim.flags[12]),
		"Engineer sabotage removes the waypoint and opens the protected vault flags")

	frontier._visuals(0.0)
	var gold_ids := [Rules.STANDARD_FLAGS_PER_PLANET, Rules.STANDARD_FLAGS_PER_PLANET + 1]
	var before_unlock := true
	for id: int in gold_ids:
		var beacon: Node3D = frontier.flag_nodes[id]["gold_beacon"]
		before_unlock = before_unlock and not beacon.visible
	empire.elapsed = empire.duration * 0.8 - Rules.STEP
	empire.tick(Rules.STEP)
	sim.sync_empire_flags()
	frontier._visuals(DT)
	var after_unlock := true
	for id: int in gold_ids:
		var beacon: Node3D = frontier.flag_nodes[id]["gold_beacon"]
		var label := beacon.get_node("Label") as Label3D
		var beam := beacon.get_node("Beam") as MeshInstance3D
		after_unlock = after_unlock and label.is_visible_in_tree() and beam.is_visible_in_tree() \
			and label.text == "2x GOLDEN CORE" and empire.flags[sim.flags[id]["empire_id"]]["points"] == 2
	_check(before_unlock and empire.act_number == 4 and after_unlock, "Act IV reveals glowing 2x Golden Core beams and labels")


func _run_regression(name: String) -> void:
	var existing := root.get_children()
	var original_size := root.size
	var original_content_scale := root.content_scale_size
	var code := GDScript.new()
	var path := "res://tests/%s_test.gd" % name
	code.resource_path = path + ".batched"
	code.source_code = FileAccess.get_file_as_string(path).replace("extends SceneTree", "extends RefCounted").replace(
		"func _initialize() -> void:", "func start() -> void:") + SUITE_ADAPTER
	var result := -1
	if code.reload() == OK:
		var suite: RefCounted = code.new()
		suite.tree = self
		suite.start.call_deferred()
		var deadline := Time.get_ticks_msec() + 90_000
		while suite.result == -1 and Time.get_ticks_msec() < deadline:
			await process_frame
		result = suite.result
	for child in root.get_children():
		if child not in existing:
			child.free()
	await process_frame
	root.size = original_size
	root.content_scale_size = original_content_scale
	Engine.time_scale = 1.0
	_check(result == 0, "%s_test.gd completed with exit 0 (got %d)" % [name, result])


func _check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	failures += int(not ok)
