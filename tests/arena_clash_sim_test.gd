extends SceneTree

const Arena := preload("res://scripts/arena_clash_sim.gd")
const Empire := preload("res://scripts/empire_sim.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	_test_roster_and_presets()
	_test_shop_and_build()
	_test_independent_arrivals()
	_test_ship_bonuses()
	_test_combat_and_respawn()
	_test_match_results()
	_test_snapshot()
	_test_live_combat()
	_test_full_ai_match()
	print("ArenaClashSim: %s (%d/%d checks)" % ["PASS" if _failures == 0 else "FAIL", _checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _new_match(player_squad: String = "orange") -> Arena:
	var sim := Arena.new()
	sim.setup(4209, "short", player_squad)
	return sim


func _queue_parts(sim: Arena, squad_id: String, parts: Array) -> void:
	for slot: String in parts:
		_check(sim.buy_part(squad_id, slot)["ok"], "%s can buy %s" % [squad_id, slot])
		_check(sim.build_part(squad_id, slot)["ok"], "%s can start building %s" % [squad_id, slot])


func _start_combat(sim: Arena) -> void:
	for id: String in sim.squads:
		for part: String in Arena.FLIGHT_PARTS:
			sim.buy_part(id, part)
			sim.build_part(id, part)
	sim.tick(Arena.BUILD_SECONDS)
	for id: String in sim.squads:
		sim.set_squad_location(id, "planet_c")
	sim.live_combat = true


func _test_roster_and_presets() -> void:
	var sim := Arena.new()
	sim.setup()
	_check(sim.time_left == 480.0 and sim.kill_target == 60, "Standard preset")
	sim.setup(1, "short", "cyan")
	_check(sim.time_left == 240.0 and sim.kill_target == 30, "Short preset")
	_check(sim.squads.size() == 8 and sim.combatants.is_empty(), "Eight squads and no pre-arena combatants")
	for alliance: String in Empire.ALLIANCE_SQUADS:
		var roster: Array = Empire.ALLIANCE_SQUADS[alliance]
		for index in roster.size():
			var squad: Dictionary = sim.squads[roster[index]]
			_check(squad["alliance"] == alliance and squad["ship_family"] == Empire.SHIP_FAMILIES[alliance][index], "%s alliance and ship family" % squad["id"])
			_check(squad["seats"] == Empire.SPECIALISTS and squad["credits"] == (Arena.PLAYER_STARTING_CREDITS if squad["id"] == sim.player_squad else Arena.STARTING_CREDITS), "%s specialist seats and credits" % squad["id"])
	sim.tick(Arena.STEP)
	_check(sim.squads["cyan"]["owned"].is_empty() and sim.squads["orange"]["owned"] == ["reactor"], "AI construction skips the selected player squad")
	_start_combat(sim)
	_check(sim.time_left == 235.75, "The clock keeps its original time through squad arrivals")
	_check(sim.combatants.size() == 32, "Arena has 32 combatant records")
	var counts := {"planet_a": 0, "planet_b": 0}
	for combatant: Dictionary in sim.combatants.values():
		counts[combatant["alliance"]] += 1
	_check(counts == {"planet_a": 16, "planet_b": 16}, "Arena has 16 combatants per alliance")
	_check(sim.combatants["cyan:3"]["seat_index"] == 3 and sim.combatants["cyan:3"]["squad_id"] == "cyan", "Stable IDs identify squad and specialist seat")


func _test_shop_and_build() -> void:
	var sim := _new_match()
	var orange: Dictionary = sim.squads["orange"]
	# Exercise the base economy; the player bonus is covered in the setup test.
	orange["credits"] = Arena.STARTING_CREDITS
	_check(sim.buy_part("missing", "reactor")["error"] == "unknown_squad", "Unknown squad rejected")
	_check(sim.buy_part("orange", "missing")["error"] == "unknown_slot", "Unknown slot rejected")
	_check(sim.build_part("orange", "reactor")["error"] == "not_owned", "Part must be bought before building")
	_queue_parts(sim, "orange", Arena.FLIGHT_PARTS)
	_check(sim.buy_part("orange", "reactor")["error"] == "already_owned", "Duplicate purchase rejected")
	_check(sim.build_part("orange", "reactor")["error"] == "already_building", "Duplicate construction rejected")
	_check(orange["credits"] == 500 and orange["built"].is_empty(), "Purchase charges once and does not finish construction")
	sim.tick(Arena.BUILD_SECONDS - Arena.STEP)
	_check(orange["built"].is_empty() and not orange["flight_capable"], "Building takes the full build time")
	sim.tick(Arena.STEP)
	_check(orange["built"] == Arena.FLIGHT_PARTS and orange["flight_capable"], "Construction completes on schedule and enables flight")
	var hud := sim.get_hud_summary()
	_check(hud["time_left"] == 236.0 and hud["kill_target"] == 30 and hud["scores"] == {"planet_a": 0, "planet_b": 0}, "HUD reports clock and scoring")
	_check(hud["squads"]["orange"] == {"credits": 500, "built": 3, "location": "planet_a"}, "HUD reports squad credits, built count and location")
	_check(sim.build_part("orange", "reactor")["error"] == "already_built", "Built part cannot be rebuilt")
	for slot in ["keel", "port", "thruster", "stores"]:
		_check(sim.buy_part("orange", slot)["ok"], "Can spend remaining credits on %s" % slot)
	_check(sim.buy_part("orange", "battery")["error"] == "insufficient_credits" and orange["credits"] == 20, "Unaffordable purchase preserves credits")
	sim.set_squad_location("orange", "space")
	_check(sim.buy_part("orange", "cargo")["error"] == "away_from_home", "Purchases require the home shop")
	_check(sim.build_part("orange", "keel")["error"] == "away_from_home", "Construction starts at home")


func _test_independent_arrivals() -> void:
	var sim := _new_match()
	_queue_parts(sim, "orange", ["reactor"])
	sim.tick(Arena.BUILD_SECONDS)
	_check(not sim.set_squad_location("orange", "planet_c"), "Incomplete ship cannot enter the arena")
	sim.tick(25.0)
	_check(sim.squads["cyan"]["location"] == "space" and sim.combatants.is_empty(), "AI finishes construction, then travels before joining")
	_check(sim.squads["cyan"]["built"] == ["reactor", "engine", "bridge", "keel", "port", "thruster", "stores"], "AI builds in order and skips unaffordable parts")
	sim.tick(Arena.AI_TRANSIT_SECONDS)
	_check(sim.combatants.size() == 28 and sim.squads["orange"]["location"] == "planet_a"
		and sim.combatant("orange:0").is_empty(), "AI fights while unfinished player remains at home")
	_queue_parts(sim, "orange", ["engine", "bridge"])
	sim.tick(Arena.BUILD_SECONDS)
	_check(sim.set_squad_location("orange", "planet_c") and sim.combatant("orange:0")["alive"], "Player squad joins on landing")
	sim.set_squad_location("orange", "space")
	_check(not sim.apply_damage("crimson:0", "orange:0", 999.0)["killed"], "A departing squad is out of combat")
	sim.set_squad_location("orange", "planet_c")
	_check(sim.combatants.size() == 32 and sim.combatant("orange:0")["deaths"] == 0, "Returning preserves combatant identity")


func _test_ship_bonuses() -> void:
	var sim := _new_match()
	var starting := sim.get_bonuses("orange")
	_queue_parts(sim, "orange", Arena.FLIGHT_PARTS)
	sim.tick(Arena.BUILD_SECONDS)
	var partial := sim.get_bonuses("orange")
	_check(partial["max_health"] > starting["max_health"] and partial["shield"] > starting["shield"], "Built bridge and reactor improve health and shield")
	_check(partial["respawn_time"] < starting["respawn_time"], "Built engine speeds up respawn")
	_queue_parts(sim, "orange", ["keel", "stores"])
	sim.tick(Arena.BUILD_SECONDS)
	_check(sim.get_bonuses("orange")["max_health"] == 50.0, "Health bonus caps at +50")

	var upgrades := {
		"shield": ["battery", "coolant"],
		"damage_multiplier": ["port", "thruster", "antenna"],
		"respawn_time": ["scrubber", "cargo"],
	}
	var caps := {"shield": 50.0, "damage_multiplier": 1.25, "respawn_time": 4.0}
	for bonus: String in upgrades:
		sim = _new_match()
		_queue_parts(sim, "orange", Arena.FLIGHT_PARTS + upgrades[bonus])
		sim.tick(Arena.BUILD_SECONDS)
		_check(sim.get_bonuses("orange")[bonus] == caps[bonus], "%s reaches its cap" % bonus)
		sim.set_squad_location("orange", "planet_c")
		_check(sim.get_bonuses("orange")[bonus] == caps[bonus], "%s carries into the arena" % bonus)


func _test_combat_and_respawn() -> void:
	var sim := _new_match()
	_queue_parts(sim, "orange", Arena.FLIGHT_PARTS + ["port"])
	sim.tick(Arena.BUILD_SECONDS)
	_start_combat(sim)
	var attacker: Dictionary = sim.combatants["orange:0"]
	var victim: Dictionary = sim.combatants["crimson:0"]
	_check(attacker["health"] == 120.0 and attacker["shield"] == 95.0, "Crew spawns with its ship stat bonuses")
	_check(not sim.apply_damage("crimson:1", "crimson:0", 1000.0)["killed"] and victim["shield"] == 95.0, "Friendly fire is ignored")
	sim.apply_damage("orange:0", "crimson:0", 50.0)
	_check(is_equal_approx(victim["shield"], 40.0) and victim["health"] == 120.0, "Shield takes multiplied damage first")
	sim.apply_damage("orange:0", "crimson:0", 50.0)
	_check(victim["shield"] == 0.0 and is_equal_approx(victim["health"], 105.0), "Damage left after shield goes to health")
	_check(sim.apply_damage("orange:0", "crimson:0", 120.0)["killed"], "Lethal damage reports a kill")
	_check(sim.get_score() == {"planet_a": 1, "planet_b": 0} and attacker["kills"] == 1 and victim["deaths"] == 1, "Kill updates score and combatant records")
	_check("orange killed crimson:0" in sim.event_log, "Kill is logged")
	_check(not sim.apply_damage("orange:0", "crimson:0", 500.0)["killed"] and not sim.apply_damage("crimson:0", "orange:0", 500.0)["killed"], "Dead attackers and victims are ignored")
	sim.tick(2.0)
	sim.apply_damage("orange:0", "crimson:1", 500.0)
	_check(sim.combatants["crimson:1"]["respawn_left"] == 4.5, "Later casualties join the squad's next wave")
	sim.tick(4.25)
	_check(not victim["alive"], "Victim stays dead until its wave")
	sim.tick(0.25)
	_check(victim["alive"] and sim.combatants["crimson:1"]["alive"] and victim["health"] == 120.0 and victim["shield"] == 95.0, "Wave respawns teammates together with full stats")
	sim.apply_damage("crimson:0", "orange:0", 500.0)
	_check(attacker["respawn_left"] == 6.5, "Engine bonus shortens the crew's respawn wave")
	sim.tick(6.5)
	_check(attacker["alive"] and attacker["health"] == 120.0 and attacker["shield"] == 95.0, "Boosted crew respawns on its shorter timer")


func _test_match_results() -> void:
	var sim := _new_match()
	_start_combat(sim)
	var victims: Array[String] = []
	for combatant: Dictionary in sim.combatants.values():
		if combatant["alliance"] == "planet_b":
			victims.append(combatant["id"])
	for index in sim.kill_target:
		sim.apply_damage("orange:0", victims[index % victims.size()], 500.0)
		if index == victims.size() - 1:
			sim.tick(8.0)
	_check(sim.is_finished() and sim.winner() == "planet_a" and sim.time_left > 0.0, "Kill target wins immediately with time remaining")
	_check(sim.get_score()["planet_a"] == 30 and not sim.apply_damage("orange:0", "cobalt:3", 500.0)["killed"], "Finished match no longer accepts damage")

	sim = _new_match()
	_start_combat(sim)
	sim.apply_damage("crimson:0", "orange:0", 500.0)
	_check(sim.winner() == "", "Below target the match keeps running")
	sim.tick(sim.time_left)
	_check(sim.is_finished() and sim.winner() == "planet_b", "Arena timeout awards the higher score")
	sim = _new_match()
	_start_combat(sim)
	sim.apply_damage("crimson:0", "orange:0", 500.0)
	sim.apply_damage("orange:1", "crimson:0", 500.0)
	sim.tick(sim.time_left)
	_check(sim.is_finished() and sim.winner() == "draw", "Equal scores at arena timeout are a draw")


func _test_snapshot() -> void:
	var sim := _new_match("")
	sim.tick(1.125)
	var snapshot := sim.to_snapshot()
	var wire: Dictionary = bytes_to_var(var_to_bytes(snapshot))
	var restored := Arena.new()
	_check(restored.from_snapshot(wire) and restored.to_snapshot() == snapshot, "Snapshot preserves build timers and fractional time")
	_check(restored.get_hud_summary() == sim.get_hud_summary(), "HUD summary roundtrips")
	wire["squads"]["orange"]["credits"] = -1
	_check(restored.squads["orange"]["credits"] >= 0 and sim.squads["orange"]["credits"] >= 0, "Snapshot dictionaries do not alias the live state")
	wire["version"] = -1
	_check(not restored.from_snapshot(wire) and restored.to_snapshot() == snapshot, "Unknown snapshot version is rejected before changing any state")
	sim.tick(105.0)
	restored.tick(105.0)
	_check(sim.combatants.size() == 32 and sim.to_snapshot() == restored.to_snapshot(), "Restored construction continues through travel into seeded combat")
	snapshot = sim.to_snapshot()
	_check(restored.from_snapshot(snapshot) and restored.to_snapshot() == snapshot, "Active arena snapshot restores combatants and scores")
	sim.tick(300.0)
	restored.tick(300.0)
	_check(sim.is_finished() and sim.to_snapshot() == restored.to_snapshot(), "Restored arena finishes identically with RNG state intact")


func _test_full_ai_match() -> void:
	var first := Arena.new()
	var second := Arena.new()
	first.setup(4209, "standard", "")
	second.setup(4209, "standard", "")
	for index in 700:
		first.tick(1.0)
		second.tick(0.375)
		second.tick(0.625)
	_check(first.is_finished() and first.winner() in ["planet_a", "planet_b", "draw"], "AI-only match reaches a result")
	_check(first.get_score()["planet_a"] > 0 and first.get_score()["planet_b"] > 0, "Both AI alliances earn kills")
	_check(first.to_snapshot() == second.to_snapshot(), "Same seed produces identical results across tick sizes")
	_check(first.event_log.size() == Arena.EVENT_LIMIT and ("orange landed on " + Universe.C_LABEL) not in first.event_log, "Event log drops its oldest entries at the cap")
	print("ArenaClashSim AI seed 4209: %s, %s" % [first.winner(), first.get_score()])


func _test_live_combat() -> void:
	var sim := _new_match("")
	sim.live_combat = true
	sim.tick(105.0)
	_check(sim.combatants.size() == 32, "Live combat still advances construction and AI transit")
	var before := sim.to_snapshot()
	sim._ai_attack()
	_check(sim.to_snapshot() == before, "Live combat skips simulated attacks")
	sim.tick(50.0)
	_check(sim.combatants == before["combatants"] and sim.get_score() == before["scores"],
		"Scene-free live combat never deals passive damage")
	_check(sim.combatant("missing").is_empty(), "Combatant lookup tolerates an unknown ID")
	_check(sim.apply_damage("orange:0", "crimson:0", 999.0)["killed"]
		and not sim.combatant("crimson:0")["alive"], "Live damage updates the combatant state")
	sim.tick(Arena.BASE_RESPAWN)
	_check(sim.combatant("crimson:0")["alive"], "Live combat keeps squad respawns running")
	var restored := Arena.new()
	var snapshot := sim.to_snapshot()
	_check(restored.from_snapshot(snapshot) and restored.live_combat, "Snapshot preserves live combat")
	snapshot.erase("live_combat")
	_check(not restored.from_snapshot(snapshot) and restored.live_combat, "Missing required snapshot fields are rejected")
