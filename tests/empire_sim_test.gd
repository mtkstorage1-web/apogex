extends SceneTree

const Empire := preload("res://scripts/empire_sim.gd")

var _failures: int = 0


func _init() -> void:
	_test_roster_and_presets()
	_test_structure_upgrades()
	_test_shield_and_sabotage()
	_test_economy_and_acts()
	_test_radar_and_combat()
	_test_flags_and_ship_damage()
	_test_knockout()
	_test_timer()
	_test_full_match_and_snapshots()
	print("EmpireSim: PASS" if _failures == 0 else "EmpireSim: FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _new_match(preset: String = "standard", automate: bool = false) -> Empire:
	var sim := Empire.new()
	sim.setup(4209, preset)
	if not automate:
		for squad: Dictionary in sim.squads.values():
			squad["ai_enabled"] = false
	return sim


func _place(sim: Empire, squad_id: String, location: String, phase: String, progress: float = 0.0) -> void:
	var squad: Dictionary = sim.squads[squad_id]
	squad["location"] = location
	squad["phase"] = phase
	squad["progress"] = progress
	squad["phase_time"] = progress * squad["phase_duration"]
	for flag_id: String in squad["flags_carried"]:
		sim.flags[flag_id]["location"] = location


func _test_roster_and_presets() -> void:
	var sim := _new_match()
	_check(sim.seed_value == 4209 and sim.duration == 2400.0, "Default seed and 40-minute clock")
	_check(sim.squads.size() == 8, "Eight squads")
	var expected_roster := {
		"planet_a": ["orange", "cyan", "violet", "lime"],
		"planet_b": ["crimson", "amber", "obsidian", "cobalt"],
	}
	var expected_seats := [
		{"name": "Finn", "role": "PILOT"}, {"name": "Chip", "role": "ENGINEER"},
		{"name": "Barbara", "role": "GUNNER"}, {"name": "Fernando", "role": "RAIDER"},
	]
	var families := {}
	for alliance: String in expected_roster:
		var player_count := 0
		for index in range(4):
			var squad_id: String = expected_roster[alliance][index]
			var squad: Dictionary = sim.squads.get(squad_id, {})
			_check(squad.get("id") == squad_id and squad.get("alliance") == alliance, "%s identity" % squad_id)
			_check(squad.get("is_player_squad") == (squad_id == "orange"), "%s player squad marker" % squad_id)
			_check(squad["seats"] == expected_seats, "%s specialist seats" % squad_id)
			_check(squad["strategy"] == ["raider", "escort", "builder", "defender"][index], "%s strategy" % squad_id)
			_check(squad["location"] == alliance and squad["phase"] == "build", "%s starts building at home" % squad_id)
			_check(squad["progress"] == 0.0 and squad["ship_hp"] == 100.0, "%s starts idle and healthy" % squad_id)
			_check(squad["ship_hp"] == 100.0 and squad["max_ship_hp"] == 100.0, "%s full starting ship hull" % squad_id)
			_check(squad["flags_carried"].is_empty(), "%s starts without cargo" % squad_id)
			for counter in ["kills", "captures", "deliveries", "builds_contributed", "credits_contributed"]:
				_check(squad[counter] == 0, "%s starts with zero %s" % [squad_id, counter])
			player_count += squad["seats"].size()
			families[squad["ship_family"]] = true
		_check(player_count == 16, "%s has 16 seats" % alliance)
	_check(families.size() == 5 and families.has_all(["kestrel", "lancer", "hauler", "halo", "bulwark"]), "All default ship families")
	sim.setup(18, "short", "easy")
	_check(sim.duration == 900.0 and sim.match_preset == "short" and sim.difficulty == "easy", "15-minute short preset and easy difficulty")
	sim.setup(23, "classic", "hard")
	_check(sim.duration == 840.0 and sim.match_preset == "classic" and sim.difficulty == "hard", "14-minute classic preset and hard difficulty")
	sim.setup(1, "invalid", "invalid")
	_check(sim.duration == 2400.0 and sim.difficulty == "standard" and sim.elapsed == 0.0, "Setup resets state and normalizes unknown options")
	_check(sim.flags.size() == 32 and sim.event_log.is_empty(), "Setup resets flags and events")
	sim.tick(0.0)
	sim.tick(-1.0)
	sim.tick(NAN)
	sim.tick(INF)
	_check(sim.elapsed == 0.0, "Nonpositive and nonfinite time steps are ignored")


func _test_structure_upgrades() -> void:
	var sim := _new_match()
	var costs := {
		"defense_turrets": [150, 260, 420], "shield_gen": [200, 340, 520],
		"refinery": [140, 240, 380], "radar": [120, 220, 340],
		"hangar": [160, 280, 440], "vault": [0, 240, 420],
	}
	var hp := {
		"defense_turrets": [220, 360, 520], "shield_gen": [300, 480, 700],
		"refinery": [240, 380, 540], "radar": [180, 300, 440],
		"hangar": [260, 420, 600], "vault": [400, 650, 950],
	}
	_check(Empire.BUILDABLE_SLOT_IDS == costs.keys(), "Six canonical slot IDs")
	for alliance: String in sim.structures:
		var builder := "orange" if alliance == "planet_a" else "crimson"
		sim.treasury[alliance] = 0.0
		_check(sim.can_upgrade(alliance, "radar") == {"ok": false, "reason": "insufficient_credits", "cost": 120, "next_tier": 1}, "Upgrade quote on insufficient funds")
		_check(not sim.repair_structure(alliance, "radar", 50.0, builder)["ok"], "Unbuilt slot cannot be repaired")
		sim.treasury[alliance] = 10000.0
		_check(sim.get_defense_dps(alliance) == 0.0 and not sim.has_radar_intel(alliance) and not sim.is_shield_active(alliance), "Unbuilt facilities are offline")
		for slot_id: String in costs:
			var slot: Dictionary = sim.structures[alliance][slot_id]
			var start_tier := 1 if slot_id == "vault" else 0
			_check(slot["tier"] == start_tier and slot["hp"] == (400.0 if start_tier == 1 else 0.0), "%s %s starting tier and HP" % [alliance, slot_id])
			_check(FileAccess.file_exists("res://" + Empire.EMPIRE_SLOTS[slot_id]["glb"]), "%s asset exists" % slot_id)
			for tier in range(start_tier + 1, 4):
				var cost: int = costs[slot_id][tier - 1]
				var balance: float = sim.treasury[alliance]
				var quote := {"ok": true, "reason": "", "cost": cost, "next_tier": tier}
				_check(sim.can_upgrade(alliance, slot_id) == quote, "%s %s T%d quote" % [alliance, slot_id, tier])
				_check(sim.build_or_upgrade(alliance, slot_id, builder) == quote, "%s %s T%d builds" % [alliance, slot_id, tier])
				_check(slot["tier"] == tier and slot["hp"] == hp[slot_id][tier - 1] and slot["max_hp"] == slot["hp"], "%s %s T%d health" % [alliance, slot_id, tier])
				_check(sim.treasury[alliance] == balance - cost, "%s %s T%d treasury debit" % [alliance, slot_id, tier])
				if slot_id == "defense_turrets":
					_check(sim.get_defense_dps(alliance) == [12.0, 22.0, 36.0][tier - 1], "%s T%d defense DPS" % [alliance, tier])

			_check(sim.can_upgrade(alliance, slot_id)["reason"] == "max_tier", "%s %s caps at T3" % [alliance, slot_id])
		_check(sim.squads[builder]["builds_contributed"] == 17, "%s gets 17 construction contributions" % builder)
		_check(sim.get_hud_summary()["structure_tiers"][alliance]["vault"] == 3, "%s vault tier in HUD" % alliance)
		var south_asset: String = Empire.EMPIRE_SLOTS["defense_turrets"]["south_glb"][alliance]
		_check(FileAccess.file_exists("res://" + south_asset), "%s south battery asset exists" % alliance)
	_check(sim.can_upgrade("planet_a", "turret_north")["reason"] == "unknown_structure", "North and south batteries share one logical slot")
	sim.setup()
	_check(sim.build_or_upgrade("planet_b", "radar")["reason"] == "invalid_squad", "Cross-alliance construction rejected")
	_check(sim.repair_structure("planet_b", "vault", 10.0)["reason"] == "invalid_squad", "Cross-alliance repair rejected")
	_check(sim.damage_structure("planet_b", "vault", 10.0, "crimson")["reason"] == "invalid_squad", "Friendly structure attack rejected")


func _test_shield_and_sabotage() -> void:
	var sim := _new_match()
	sim.treasury["planet_a"] = 1000.0
	for slot in ["shield_gen", "hangar", "radar", "defense_turrets"]:
		_check(sim.build_or_upgrade("planet_a", slot)["ok"], "Build %s for sabotage test" % slot)
	_check(sim.is_shield_active("planet_a"), "Built shield is active")
	_check(sim.damage_structure("planet_a", "vault", 40.0, "crimson")["reason"] == "shielded", "Shield protects command vault")
	_check(sim.sabotage_structure("planet_a", "hangar", 100.0, "crimson")["reason"] == "shielded", "Shield protects launch pads and hangar")
	_place(sim, "crimson", "planet_a", "raid")
	_check(not sim.record_flag_captured("crimson", "planet_a_flag_13"), "Shield protects vault flags")
	_check(sim.sabotage_structure("planet_a", "shield_gen", 40.0, "crimson")["sabotage_timer"] == 0.0, "Partial sabotage leaves shield online")
	_check(sim.sabotage_structure("planet_a", "shield_gen", 60.0, "crimson")["sabotage_timer"] == 30.0, "Completed sabotage starts 30 seconds")
	_check(not sim.is_shield_active("planet_a"), "Shield at positive HP stays offline during sabotage")
	_check(sim.can_upgrade("planet_a", "shield_gen")["reason"] == "sabotaged", "Upgrade cannot bypass sabotage")
	_check(sim.record_flag_captured("crimson", "planet_a_flag_13"), "Vault flag can be taken while shield is offline")
	_check(sim.damage_structure("planet_a", "vault", 999.0, "crimson")["hp"] == 0.0, "Structure hull clamps to zero")
	_check(sim.repair_structure("planet_a", "vault", 999.0)["hp"] == 400.0, "Repair clamps to maximum hull")
	_check(not sim.damage_structure("planet_a", "vault", -10.0)["ok"], "Negative damage rejected")
	_check(not sim.repair_structure("planet_a", "vault", INF)["ok"], "Nonfinite repair rejected")
	sim.sabotage_structure("planet_a", "radar", 100.0, "crimson")
	sim.sabotage_structure("planet_a", "defense_turrets", 300.0, "crimson")
	var hangar_hit := sim.sabotage_structure("planet_a", "hangar", 99.0, "crimson")
	_check(hangar_hit["sabotage_timer"] == 0.0, "Incomplete sabotage has no cooldown")
	sim.sabotage_structure("planet_a", "hangar", 1.0, "crimson")
	_check(not sim.has_radar_intel("planet_a") and sim.get_defense_dps("planet_a") == 0.0, "Sabotage denies radar and turret effects")
	_check(sim.repair_structure("planet_a", "defense_turrets", 1000.0)["sabotage_timer"] == 30.0, "Repair restores hull without shortening disable")
	sim.tick(29.75)
	_check(not sim.is_shield_active("planet_a"), "Shield stays disabled until sabotage expires")
	sim.tick(0.25)
	_check(sim.is_shield_active("planet_a") and sim.has_radar_intel("planet_a") and sim.get_defense_dps("planet_a") == 12.0, "Repaired facilities come online at expiry")
	sim.tick(10.0)
	_check(sim.structures["planet_a"]["shield_gen"]["hp"] == 300.0, "Shield recharges to full")
	sim.damage_structure("planet_a", "shield_gen", 300.0, "crimson")
	_check(not sim.is_shield_active("planet_a"), "Destroyed shield has no protection")
	sim.tick(7.75)
	_check(not sim.is_shield_active("planet_a"), "Shield recharge respects damage delay")
	sim.tick(0.25)
	_check(sim.is_shield_active("planet_a") and sim.structures["planet_a"]["shield_gen"]["hp"] > 0.0, "Destroyed shield can recharge")


func _test_economy_and_acts() -> void:
	var sim := _new_match()
	_check(sim.treasury == {"planet_a": 300.0, "planet_b": 300.0}, "Equal starting treasuries")
	sim.tick(1.0)
	_check(sim.treasury["planet_a"] == 302.0 and sim.treasury["planet_b"] == 302.0, "Both alliances earn base income")
	for i in range(3):
		sim.treasury["planet_a"] += 1000.0
		sim.build_or_upgrade("planet_a", "refinery")
		var credits: float = sim.treasury["planet_a"]
		sim.tick(1.0)
		_check(sim.treasury["planet_a"] - credits == [8.0, 14.0, 22.0][i], "T%d refinery adds tier income" % (i + 1))
	sim.damage_structure("planet_a", "refinery", 540.0, "crimson")
	var balance: float = sim.treasury["planet_a"]
	sim.tick(1.0)
	_check(sim.treasury["planet_a"] - balance == 2.0, "Destroyed refinery pays no bonus")
	sim.repair_structure("planet_a", "refinery", 540.0)
	var thresholds := [480.0, 1080.0, 1920.0]
	var names := ["Foundation", "Corridor Skirmish", "Two-Way Invasion & Siege", "Overdrive Rush"]
	for i in thresholds.size():
		sim.tick(thresholds[i] - sim.elapsed - 0.25)
		var before := sim.get_hud_summary()
		_check(before["act_number"] == i + 1 and before["act_name"] == names[i], "Act %d before boundary" % (i + 1))
		_check(not before["overdrive"] and sim.flags.size() == 32, "No Golden Cores before Act IV")
		sim.tick(0.25)
		var after := sim.get_hud_summary()
		_check(after["act_number"] == i + 2 and after["act_name"] == names[i + 1], "Act %d starts at exact threshold" % (i + 2))
	_check(sim.overdrive and sim.flags.size() == 36, "Act IV spawns exactly four Golden Cores")
	for alliance: String in sim.structures:
		_check(sim.get_hud_summary()["flag_counts"][alliance]["golden"] == 2, "%s gets two Golden Cores" % alliance)
		for i in range(1, 3):
			var core: Dictionary = sim.flags["%s_gold_%02d" % [alliance, i]]
			_check(core["location"] == alliance and core["state"] == "available" and core["points"] == 2, "%s Golden Core value and spawn location" % alliance)
	var a_credits: float = sim.treasury["planet_a"]
	var b_credits: float = sim.treasury["planet_b"]
	sim.tick(2.0)
	_check(sim.treasury["planet_a"] - a_credits == 88.0 and sim.treasury["planet_b"] - b_credits == 8.0, "Overdrive doubles base and refinery income")
	_check(sim.flags.size() == 36, "Golden Cores spawn once")
	for preset: String in ["short", "classic"]:
		var shorter := _new_match(preset)
		shorter.tick(shorter.duration * 0.8)
		_check(shorter.act_number == 4 and shorter.overdrive and shorter.flags.size() == 36, "%s uses proportional acts" % preset)


func _test_radar_and_combat() -> void:
	var sim := _new_match()
	_place(sim, "crimson", "planet_a", "raid")
	_place(sim, "orange", "planet_b", "raid")
	_check(sim.get_active_invaders("planet_a")[0]["id"] == "crimson", "Planet A invader query")
	_check(sim.get_hud_summary()["active_allies_on_b"][0]["id"] == "orange", "Planet B invaders in HUD")
	sim.record_flag_captured("crimson", "planet_a_flag_01")
	_place(sim, "crimson", "space_to_b", "return", 0.25)
	_place(sim, "cyan", "space_to_b", "flight", 0.5)
	var traffic := sim.get_space_traffic()
	_check(traffic.size() == 2, "Both factions appear in space traffic")
	var crimson_traffic: Dictionary = traffic[1]
	_check(crimson_traffic["id"] == "crimson" and crimson_traffic["faction"] == "planet_b", "Traffic includes squad and faction")
	_check(crimson_traffic["progress"] == 0.25 and crimson_traffic["flags_carried"] == ["planet_a_flag_01"], "Traffic includes transit progress and cargo")
	var contact: Dictionary = sim.get_hud_summary()["radar_intel"]["planet_a"]
	_check(contact["enemy_space_traffic"].is_empty() and contact["enemy_flag_carriers"].is_empty(), "No radar contacts while offline")
	sim.build_or_upgrade("planet_a", "radar")
	contact = sim.get_hud_summary()["radar_intel"]["planet_a"]
	_check(contact["enemy_space_traffic"] == [crimson_traffic], "Online radar reveals enemy space traffic")
	_check(contact["enemy_flag_carriers"].size() == 1 and contact["enemy_flag_carriers"][0]["id"] == "crimson", "Online radar reveals enemy carriers")
	sim.build_or_upgrade("planet_a", "defense_turrets")
	_place(sim, "amber", "planet_a", "raid")
	sim.squads["amber"]["ship_hp"] = 0.5
	sim.tick(0.25)
	_check(sim.squads["cyan"]["ship_hp"] == 100.0, "Turrets spare own ships")
	_check(sim.squads["amber"]["ship_hp"] == 1.0 and sim.squads["amber"]["phase"] == "raid"
		and sim.squads["orange"]["kills"] == 0, "Orbital defense damages hull without destroying the ship or awarding a kill")
	sim.tick(480.0 - sim.elapsed)
	_place(sim, "orange", "space_to_b", "flight", 0.5)
	_place(sim, "crimson", "space_to_a", "flight", 0.5)
	sim.tick(0.25)
	_check(sim.squads["orange"]["ship_hp"] < 100.0 and sim.squads["crimson"]["ship_hp"] < 100.0, "Act II opposing traffic exchanges fire")


func _test_flags_and_ship_damage() -> void:
	var sim := _new_match()
	var first := "planet_b_flag_01"
	var second := "planet_b_flag_02"
	_check(not sim.record_flag_captured("orange", first), "Squads must reach the flag pool")
	_check(not sim.record_flag_captured("orange", "planet_a_flag_01"), "Squads cannot capture their own flag")
	_check(not sim.record_flag_captured("orange", "missing"), "Unknown flag rejected")
	_place(sim, "orange", "planet_b", "raid")
	_check(sim.record_flag_captured("orange", first), "Enemy Science Flag captured")
	_check(not sim.record_flag_captured("orange", first), "Duplicate capture rejected")
	_check(sim.record_flag_delivered("orange", first) == 0, "Cannot deliver at enemy vault")
	sim.damage_ship("orange", 1000.0)
	_check(sim.squads["orange"]["ship_hp"] == 1.0 and sim.squads["orange"]["location"] == "planet_b"
		and sim.squads["orange"]["phase"] == "raid" and sim.squads["orange"]["flags_carried"] == [first],
		"Critical damage keeps the ship and its cargo at the raid site")
	_check(sim.record_flag_dropped("orange", first), "Crew can drop the flag on the surface")
	_check(sim.flags[first]["state"] == "dropped" and sim.flags[first]["location"] == "planet_b", "Dropped surface flag stays on the current planet")
	_place(sim, "cyan", "planet_b", "raid")
	_check(sim.record_flag_captured("cyan", first) and sim.record_flag_captured("cyan", second), "Teammate can recover drop and take another objective")
	_place(sim, "cyan", "space_to_a", "return", 0.4)
	sim.damage_ship("cyan", 1000.0)
	_check(sim.squads["cyan"]["ship_hp"] == 1.0 and sim.squads["cyan"]["flags_carried"] == [first, second]
		and sim.squads["cyan"]["progress"] == 0.4, "Critical damage keeps cargo and progress during transit")
	_check(sim.record_flag_dropped("cyan", first) and sim.record_flag_dropped("cyan", second), "Crew can jettison cargo in transit")
	_check(sim.flags[first]["location"] == "space_to_a" and sim.flags[first]["progress"] == 0.4, "Space drop keeps its directional pool and transit progress")
	_place(sim, "violet", "space_to_a", "return", 0.4)
	_check(sim.record_flag_captured("violet", first), "Space pool drop can be recovered")
	_place(sim, "violet", "planet_a", "defend")
	_check(sim.record_flag_delivered("orange", first) == 0, "Noncarrier cannot deliver")
	var balance: float = sim.treasury["planet_a"]
	_check(sim.record_flag_delivered("violet", first) == 1, "Science Flag delivers for one point")
	_check(sim.record_flag_delivered("violet", first) == 0 and sim.scores["planet_a"] == 1, "Delivery is idempotent")
	_check(sim.treasury["planet_a"] - balance == 120.0 and sim.squads["violet"]["credits_contributed"] == 120, "Delivery adds 120 treasury credits and contribution")
	_check(sim.squads["violet"]["captures"] == 1 and sim.squads["violet"]["deliveries"] == 1, "Squad records personal objective contributions")
	_check(sim.get_hud_summary()["flag_counts"]["planet_b"]["delivered"] == 1, "HUD shows delivered flag by origin")
	var restored := Empire.new()
	_check(restored.from_snapshot(sim.to_snapshot()), "Snapshot retains directional drops and damaged hulls")
	sim.tick(20.0)
	restored.tick(20.0)
	_check(restored.to_snapshot() == sim.to_snapshot(), "Snapshot continues with the same hull and cargo state")


func _test_knockout() -> void:
	var sim := _new_match()
	sim.tick(1920.0)
	_place(sim, "crimson", "planet_a", "raid")
	for i in range(1, 17):
		_check(sim.record_flag_captured("crimson", "planet_a_flag_%02d" % i), "Knockout regular flag %d captured" % i)
	_check(sim.record_flag_captured("crimson", "planet_a_gold_01"), "First Golden Core captured")
	_check(sim.record_flag_captured("crimson", "planet_a_gold_02"), "Second Golden Core captured")
	_place(sim, "crimson", "planet_b", "defend")
	for i in range(1, 17):
		_check(sim.record_flag_delivered("crimson", "planet_a_flag_%02d" % i) == 1, "Knockout regular flag %d delivered" % i)
	var balance: float = sim.treasury["planet_b"]
	_check(sim.record_flag_delivered("crimson", "planet_a_gold_01") == 2, "Golden Core adds two points")
	_check(sim.treasury["planet_b"] - balance == 120.0 and sim.winner == "", "Golden Core awards 120 credits and 18 points does not win")
	_check(sim.record_flag_delivered("crimson", "planet_a_gold_02") == 2, "Second Golden Core delivers")
	_check(sim.scores["planet_b"] == 20 and sim.winner == "planet_b" and sim.win_reason == "knockout", "20 points wins before the clock expires")
	_check(sim.get_hud_summary()["clock_remaining"] == 480.0, "Early winner retains time remaining")
	var ended := sim.to_snapshot()
	sim.tick(1000.0)
	_check(sim.to_snapshot() == ended, "Knockout freezes subsequent time and income")


func _test_timer() -> void:
	var sim := _new_match()
	_place(sim, "orange", "planet_b", "raid")
	sim.record_flag_captured("orange", "planet_b_flag_01")
	_place(sim, "orange", "planet_a", "defend")
	sim.record_flag_delivered("orange", "planet_b_flag_01")
	sim.tick(2399.75)
	_check(sim.winner == "" and sim.get_hud_summary()["clock_remaining"] == 0.25, "Timer does not end early")
	sim.tick(90.0)
	_check(sim.elapsed == 2400.0 and sim.winner == "planet_a" and sim.win_reason == "timer", "Highest score wins exactly at 40:00")
	_check(sim.get_hud_summary()["clock_remaining"] == 0.0, "Clock clamps at zero")
	_check(sim.record_flag_captured("orange", "planet_b_gold_01") == false, "Finished match rejects captures")
	var tied := _new_match("classic")
	tied.tick(840.0)
	_check(tied.winner == "draw" and tied.win_reason == "timer", "Equal scores at the buzzer draw")


func _test_full_match_and_snapshots() -> void:
	var sim := _new_match("standard", true)
	var same := _new_match("standard", true)
	var different := Empire.new()
	different.setup(4210)
	_check(different.to_snapshot()["squads"] != sim.to_snapshot()["squads"], "Seed affects AI schedule")
	var seen_phases := {}
	for i in range(1080):
		sim.tick(1.0)
		for squad: Dictionary in sim.squads.values():
			seen_phases[squad["phase"]] = true
	sim.tick(0.125)
	same.tick(1080.125)
	_check(sim.to_snapshot() == same.to_snapshot(), "Same seed produces the same state across tick sizes")

	var snap := sim.to_snapshot()
	var restored := Empire.new()
	var wire_snap: Dictionary = bytes_to_var(var_to_bytes(snap))
	_check(restored.from_snapshot(wire_snap), "Versioned snapshot accepts Variant wire roundtrip")
	_check(restored.to_snapshot() == snap and restored.get_hud_summary() == sim.get_hud_summary(), "Snapshot restores complete match and HUD")
	var bad := snap.duplicate(true)
	bad["squads"]["orange"]["flags_carried"] = ["missing"]
	_check(not restored.from_snapshot(bad) and restored.to_snapshot() == snap, "Malformed cargo snapshot rejected atomically")
	bad = snap.duplicate(true)
	bad["version"] = -1
	_check(not restored.from_snapshot(bad), "Unsupported snapshot version rejected")
	snap["squads"]["orange"]["ship_hp"] = -1.0
	wire_snap["squads"]["orange"]["ship_hp"] = -1.0
	_check(restored.squads["orange"]["ship_hp"] >= 0.0 and sim.squads["orange"]["ship_hp"] >= 0.0, "Snapshots never alias live nested state")

	for i in range(1320):
		sim.tick(1.0)
		restored.tick(0.25)
		restored.tick(0.75)
		same.tick(1.0)
		for squad: Dictionary in sim.squads.values():
			seen_phases[squad["phase"]] = true
	_check(seen_phases.has_all(["build", "outfit", "defend", "flight", "raid", "return"]), "AI completes the strategic phase loop")
	_check(sim.elapsed == 2400.0 and sim.win_reason == "timer", "Autonomous 16v16 match runs the full 40 minutes")
	_check(sim.scores["planet_a"] > 0 and sim.scores["planet_b"] > 0, "Both AI alliances capture and deliver")
	_check(sim.to_snapshot() == restored.to_snapshot() and sim.to_snapshot() == same.to_snapshot(), "Same seed and restored RNG remain deterministic through the finish")
	_check(sim.flags.size() == 36 and sim.event_log.size() <= Empire.EVENT_LIMIT, "Full match has four Golden Cores and a bounded event log")
	_check(restored.from_snapshot(sim.to_snapshot()), "Completed match snapshot roundtrips")
