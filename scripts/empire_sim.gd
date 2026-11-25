class_name EmpireSim
extends RefCounted
## Authoritative match rules. All mutable state is included in the snapshot.


const ALLIANCE_SQUADS := {
	"planet_a": ["orange", "cyan", "violet", "lime"],
	"planet_b": ["crimson", "amber", "obsidian", "cobalt"],
}
const SPECIALISTS := [
	{"name": "Finn", "role": "PILOT"},
	{"name": "Chip", "role": "ENGINEER"},
	{"name": "Barbara", "role": "GUNNER"},
	{"name": "Fernando", "role": "RAIDER"},
]
const MATCH_PRESETS := {"standard": 2400.0, "short": 900.0, "classic": 840.0}
const ACT_NAMES := [
	"Foundation", "Corridor Skirmish", "Two-Way Invasion & Siege", "Overdrive Rush",
]
const BUILDABLE_SLOT_IDS := ["defense_turrets", "shield_gen", "refinery", "radar", "hangar", "vault"]
const EMPIRE_SLOTS := {
	"defense_turrets": {
		"name": "Orbital Defense Batteries", "costs": [150, 260, 420],
		"hp": [220, 360, 520], "dps": [12, 22, 36],
		"glb": "assets/models/apogex/deployables/mothership_turret_battery.glb",
		"south_glb": {
			"planet_a": "assets/models/apogex/deployables/helion_defense_turret.glb",
			"planet_b": "assets/models/apogex/deployables/cinder_defense_turret.glb",
		},
	},
	"shield_gen": {
		"name": "Planetary Shield Generator", "costs": [200, 340, 520],
		"hp": [300, 480, 700], "glb": "assets/models/apogex/deployables/deployable_shield_gen.glb",
	},
	"refinery": {
		"name": "Resource Extractor & Refinery", "costs": [140, 240, 380],
		"hp": [240, 380, 540], "income": [6, 12, 20],
		"glb": "assets/models/apogex/surface/refinery_tower_cluster.glb",
	},
	"radar": {
		"name": "Deep-Space Radar Relay", "costs": [120, 220, 340],
		"hp": [180, 300, 440], "glb": "assets/models/apogex/landmarks/relay_tower.glb",
	},
	"hangar": {
		"name": "Rapid Refit & Repair Hangar", "costs": [160, 280, 440],
		"hp": [260, 420, 600],
		"glb": "assets/models/apogex/surface/launch_service_tower.glb",
	},
	"vault": {
		"name": "Command Flag Vault", "costs": [0, 240, 420],
		"hp": [400, 650, 950], "glb": "assets/models/apogex/surface/extraction_spire_core.glb",
	},
}

const WIN_SCORE := 20
const DELIVERY_CREDITS := 120
const STARTING_TREASURY := 300.0
const BASE_INCOME := 2.0
const STANDARD_FLAGS_PER_PLANET := 16
const SABOTAGE_SECONDS := 30.0
const SABOTAGE_THRESHOLD := 100.0
const SHIELD_RECHARGE_DELAY := 8.0
const SHIELD_RECHARGE_RATE := 10.0
const STEP := 0.25
const SNAPSHOT_VERSION := 1
const EVENT_LIMIT := 80

const STRATEGIES := ["raider", "escort", "builder", "defender"]
const SHIP_FAMILIES := {
	"planet_a": ["kestrel", "lancer", "hauler", "halo"],
	"planet_b": ["kestrel", "lancer", "hauler", "bulwark"],
}
const SPACE_LOCATIONS := ["space_to_a", "space_to_b"]
const PHASES := ["build", "outfit", "flight", "raid", "defend", "return"]
const BUILD_PRIORITIES := {
	"raider": ["radar", "hangar", "refinery", "defense_turrets", "shield_gen", "vault"],
	"escort": ["hangar", "radar", "defense_turrets", "refinery", "shield_gen", "vault"],
	"builder": ["refinery", "hangar", "shield_gen", "radar", "defense_turrets", "vault"],
	"defender": ["defense_turrets", "shield_gen", "vault", "radar", "refinery", "hangar"],
}

var seed_value: int = 4209
var match_preset: String = "standard"
var difficulty: String = "standard"
var elapsed: float = 0.0
var duration: float = MATCH_PRESETS["standard"]
var act_number: int = 1
var overdrive: bool = false
var winner: String = ""
var win_reason: String = ""
var squads: Dictionary = {}
var structures: Dictionary = {}
var treasury: Dictionary = {}
var scores: Dictionary = {}
var flags: Dictionary = {}
var event_log: Array = []

var _accumulator: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(seed_val: int = 4209, match_preset: String = "standard", difficulty: String = "standard") -> void:
	seed_value = seed_val
	self.match_preset = match_preset if MATCH_PRESETS.has(match_preset) else "standard"
	self.difficulty = difficulty if difficulty in ["easy", "standard", "hard"] else "standard"
	duration = MATCH_PRESETS[self.match_preset]
	elapsed = 0.0
	act_number = 1
	overdrive = false
	winner = ""
	win_reason = ""
	_accumulator = 0.0
	_rng.seed = seed_val
	squads.clear()
	structures.clear()
	treasury.clear()
	scores.clear()
	flags.clear()
	event_log.clear()

	for alliance in ALLIANCE_SQUADS:
		treasury[alliance] = STARTING_TREASURY
		scores[alliance] = 0
		structures[alliance] = {}
		for slot_id in BUILDABLE_SLOT_IDS:
			var tier: int = 1 if slot_id == "vault" else 0
			var hp: float = float(EMPIRE_SLOTS[slot_id]["hp"][0]) if tier == 1 else 0.0
			structures[alliance][slot_id] = {
				"tier": tier, "hp": hp, "max_hp": hp, "sabotage_timer": 0.0,
				"sabotage_progress": 0.0, "recharge_delay": 0.0, "built_by": "",
			}
		for index in ALLIANCE_SQUADS[alliance].size():
			var squad_id: String = ALLIANCE_SQUADS[alliance][index]
			var squad := {
				"id": squad_id, "alliance": alliance, "is_player_squad": squad_id == "orange",
				"strategy": STRATEGIES[index], "ship_family": SHIP_FAMILIES[alliance][index],
				"seats": SPECIALISTS.duplicate(true), "ai_enabled": true,
				"ship_hp": 100.0, "max_ship_hp": 100.0, "flags_carried": [],
				"kills": 0, "captures": 0, "deliveries": 0, "builds_contributed": 0,
				"credits_contributed": 0,
			}
			_set_phase(squad, "build", alliance, _rng.randf_range(30.0, 45.0))
			squads[squad_id] = squad
		for index in range(1, STANDARD_FLAGS_PER_PLANET + 1):
			_add_flag(alliance, index, false)


func tick(dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0 or winner != "" or squads.is_empty():
		return
	_accumulator += minf(dt, duration - elapsed)
	while _accumulator + 0.000000001 >= STEP and winner == "":
		_accumulator = maxf(0.0, _accumulator - STEP)
		_step()
	if winner != "":
		_accumulator = 0.0


func can_upgrade(alliance: String, slot_id: String) -> Dictionary:
	var result := {"ok": false, "reason": "", "cost": 0, "next_tier": 0}
	if not _has_structure(alliance, slot_id):
		result["reason"] = "unknown_structure"
		return result
	var structure: Dictionary = structures[alliance][slot_id]
	var tier: int = structure["tier"]
	if tier >= 3:
		result["reason"] = "max_tier"
		return result
	result["next_tier"] = tier + 1
	result["cost"] = EMPIRE_SLOTS[slot_id]["costs"][tier]
	if winner != "":
		result["reason"] = "match_over"
	elif structure["sabotage_timer"] > 0.0:
		result["reason"] = "sabotaged"
	elif treasury[alliance] < result["cost"]:
		result["reason"] = "insufficient_credits"
	else:
		result["ok"] = true
	return result


func build_or_upgrade(alliance: String, slot_id: String, by_squad: String = "orange") -> Dictionary:
	var result := can_upgrade(alliance, slot_id)
	if not result["ok"]:
		return result
	if not _is_allied_squad(alliance, by_squad):
		result["ok"] = false
		result["reason"] = "invalid_squad"
		return result
	var structure: Dictionary = structures[alliance][slot_id]
	structure["tier"] = result["next_tier"]
	structure["max_hp"] = float(EMPIRE_SLOTS[slot_id]["hp"][structure["tier"] - 1])
	structure["hp"] = structure["max_hp"]
	structure["recharge_delay"] = 0.0
	structure["sabotage_progress"] = 0.0
	structure["built_by"] = by_squad
	treasury[alliance] -= result["cost"]
	squads[by_squad]["builds_contributed"] += 1
	_log_event("structure_upgraded", alliance, by_squad, slot_id)
	return result


func damage_structure(alliance: String, slot_id: String, amount: float, attacker_squad: String = "") -> Dictionary:
	return _attack_structure(alliance, slot_id, amount, attacker_squad, false)


func sabotage_structure(alliance: String, slot_id: String, amount: float, attacker_squad: String = "") -> Dictionary:
	return _attack_structure(alliance, slot_id, amount, attacker_squad, true)


func repair_structure(alliance: String, slot_id: String, amount: float, by_squad: String = "orange") -> Dictionary:
	if not _has_structure(alliance, slot_id):
		return {"ok": false, "reason": "unknown_structure"}
	if not _is_allied_squad(alliance, by_squad):
		return {"ok": false, "reason": "invalid_squad"}
	var structure: Dictionary = structures[alliance][slot_id]
	if winner != "" or structure["tier"] == 0 or not is_finite(amount) or amount <= 0.0:
		return {"ok": false, "reason": "unavailable"}
	var old_hp: float = structure["hp"]
	structure["hp"] = minf(structure["max_hp"], old_hp + amount)
	return {
		"ok": true, "reason": "", "hp": structure["hp"], "repaired": structure["hp"] - old_hp,
		"sabotage_timer": structure["sabotage_timer"],
	}


func is_shield_active(alliance: String) -> bool:
	return _online_tier(alliance, "shield_gen") > 0


func has_radar_intel(alliance: String) -> bool:
	return _online_tier(alliance, "radar") > 0


func get_defense_dps(alliance: String) -> float:
	var tier := _online_tier(alliance, "defense_turrets")
	return EMPIRE_SLOTS["defense_turrets"]["dps"][tier - 1] if tier > 0 else 0.0


func record_flag_captured(squad_id: String, flag_id: String) -> bool:
	if winner != "" or not squads.has(squad_id) or not flags.has(flag_id):
		return false
	var squad: Dictionary = squads[squad_id]
	var flag: Dictionary = flags[flag_id]
	if not _can_capture(squad, flag):
		return false
	flag["state"] = "carried"
	flag["carrier"] = squad_id
	flag["location"] = squad["location"]
	squad["flags_carried"].append(flag_id)
	squad["captures"] += 1
	_log_event("flag_captured", squad["alliance"], squad_id, flag_id)
	return true


func record_flag_dropped(squad_id: String, flag_id: String) -> bool:
	if winner != "" or not squads.has(squad_id):
		return false
	var squad: Dictionary = squads[squad_id]
	var location: String = squad["location"]
	if flag_id not in squad["flags_carried"] or location == squad["alliance"]:
		return false
	squad["flags_carried"].erase(flag_id)
	var flag: Dictionary = flags[flag_id]
	flag["carrier"] = ""
	flag["state"] = "dropped"
	flag["location"] = location
	flag["progress"] = squad["progress"] if location in SPACE_LOCATIONS else 0.0
	return true


func record_flag_delivered(squad_id: String, flag_id: String) -> int:
	if winner != "" or not squads.has(squad_id) or not flags.has(flag_id):
		return 0
	var squad: Dictionary = squads[squad_id]
	var flag: Dictionary = flags[flag_id]
	var alliance: String = squad["alliance"]
	if squad["location"] != alliance or flag["carrier"] != squad_id or flag["state"] != "carried":
		return 0
	squad["flags_carried"].erase(flag_id)
	squad["deliveries"] += 1
	squad["credits_contributed"] += DELIVERY_CREDITS
	flag["carrier"] = ""
	flag["state"] = "delivered"
	flag["location"] = alliance
	var points: int = flag["points"]
	scores[alliance] += points
	treasury[alliance] += DELIVERY_CREDITS
	_log_event("flag_delivered", alliance, squad_id, flag_id)
	if scores[alliance] >= WIN_SCORE:
		_finish(alliance, "knockout")
	return points


func get_active_invaders(target_planet: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for squad: Dictionary in squads.values():
		if squad["location"] == target_planet and squad["alliance"] != target_planet and squad["phase"] == "raid":
			result.append(squad.duplicate(true))
	return result


func get_space_traffic() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for squad: Dictionary in squads.values():
		if squad["location"] in SPACE_LOCATIONS:
			result.append({
				"id": squad["id"], "alliance": squad["alliance"], "faction": squad["alliance"],
				"location": squad["location"], "phase": squad["phase"], "progress": squad["progress"],
				"flags_carried": squad["flags_carried"].duplicate(),
			})
	return result


func get_hud_summary() -> Dictionary:
	var structure_tiers := {}
	var radar_intel := {}
	var flag_counts := {}
	var space_traffic := get_space_traffic()
	for alliance in structures:
		structure_tiers[alliance] = {}
		for slot_id in BUILDABLE_SLOT_IDS:
			structure_tiers[alliance][slot_id] = structures[alliance][slot_id]["tier"]
		radar_intel[alliance] = _get_radar_contacts(alliance, space_traffic)
		flag_counts[alliance] = {"available": 0, "dropped": 0, "carried": 0, "delivered": 0, "golden": 0}
	for flag: Dictionary in flags.values():
		var counts: Dictionary = flag_counts[flag["origin"]]
		counts[flag["state"]] += 1
		if flag["points"] == 2:
			counts["golden"] += 1
	return {
		"clock_remaining": duration - elapsed, "act_number": act_number, "act_name": ACT_NAMES[act_number - 1],
		"overdrive": overdrive, "scores": scores.duplicate(), "treasury": treasury.duplicate(),
		"structure_tiers": structure_tiers, "flag_counts": flag_counts, "radar_intel": radar_intel,
		"active_invaders_on_a": get_active_invaders("planet_a"), "active_allies_on_b": get_active_invaders("planet_b"),
		"winner": winner, "win_reason": win_reason, "event_log": event_log.duplicate(true),
	}


func to_snapshot() -> Dictionary:
	return {
		"version": SNAPSHOT_VERSION, "seed": seed_value, "match_preset": match_preset, "difficulty": difficulty,
		"elapsed": elapsed, "duration": duration, "act_number": act_number, "overdrive": overdrive,
		"winner": winner, "win_reason": win_reason, "accumulator": _accumulator, "rng_state": _rng.state,
		"squads": squads.duplicate(true), "structures": structures.duplicate(true),
		"treasury": treasury.duplicate(), "scores": scores.duplicate(), "flags": flags.duplicate(true),
		"event_log": event_log.duplicate(true),
	}


func from_snapshot(snap: Dictionary) -> bool:
	if not _valid_snapshot(snap):
		return false
	var state := snap.duplicate(true)
	seed_value = state["seed"]
	match_preset = state["match_preset"]
	difficulty = state["difficulty"]
	elapsed = state["elapsed"]
	duration = state["duration"]
	act_number = state["act_number"]
	overdrive = state["overdrive"]
	winner = state["winner"]
	win_reason = state["win_reason"]
	_accumulator = state["accumulator"]
	_rng.seed = seed_value
	_rng.state = state["rng_state"]
	squads = state["squads"]
	structures = state["structures"]
	treasury = state["treasury"]
	scores = state["scores"]
	flags = state["flags"]
	event_log = state["event_log"]
	return true


func _step() -> void:
	elapsed += STEP
	for alliance in ALLIANCE_SQUADS:
		var tier := _online_tier(alliance, "refinery")
		var refinery_income: float = float(EMPIRE_SLOTS["refinery"]["income"][tier - 1]) if tier > 0 else 0.0
		treasury[alliance] += (BASE_INCOME + refinery_income) * STEP * (2.0 if overdrive else 1.0)
		_update_structures(alliance)
	var next_act := _act_at(elapsed, duration)
	if act_number != next_act:
		act_number = next_act
		_log_event("act_started", "", "", ACT_NAMES[act_number - 1])
		if act_number == 4:
			overdrive = true
			for alliance in ALLIANCE_SQUADS:
				for index in range(1, 3):
					_add_flag(alliance, index, true)
	if elapsed >= duration:
		var timer_winner := "draw"
		if scores["planet_a"] != scores["planet_b"]:
			timer_winner = "planet_a" if scores["planet_a"] > scores["planet_b"] else "planet_b"
		_finish(timer_winner, "timer")
		return
	for squad: Dictionary in squads.values():
		_advance_squad(squad)
		if winner != "":
			return
	_apply_combat()


func _act_at(time: float, match_duration: float) -> int:
	if time >= match_duration * 0.8:
		return 4
	if time >= match_duration * 0.45:
		return 3
	if time >= match_duration * 0.2:
		return 2
	return 1


func _update_structures(alliance: String) -> void:
	for slot_id in BUILDABLE_SLOT_IDS:
		var structure: Dictionary = structures[alliance][slot_id]
		var previous_timer: float = structure["sabotage_timer"]
		structure["sabotage_timer"] = maxf(0.0, previous_timer - STEP)
		structure["recharge_delay"] = maxf(0.0, structure["recharge_delay"] - STEP)
		if previous_timer > 0.0 and structure["sabotage_timer"] == 0.0:
			_log_event("sabotage_expired", alliance, "", slot_id)
		if slot_id == "shield_gen" and previous_timer == 0.0 and structure["recharge_delay"] == 0.0:
			structure["hp"] = minf(structure["max_hp"], structure["hp"] + SHIELD_RECHARGE_RATE * STEP)


func _has_structure(alliance: String, slot_id: String) -> bool:
	return structures.has(alliance) and EMPIRE_SLOTS.has(slot_id)


func _is_allied_squad(alliance: String, squad_id: String) -> bool:
	return squads.has(squad_id) and squads[squad_id]["alliance"] == alliance


func _online_tier(alliance: String, slot_id: String) -> int:
	if not _has_structure(alliance, slot_id):
		return 0
	var structure: Dictionary = structures[alliance][slot_id]
	if structure["hp"] <= 0.0 or structure["sabotage_timer"] > 0.0:
		return 0
	return structure["tier"]


func _attack_structure(alliance: String, slot_id: String, amount: float, attacker_squad: String, sabotage: bool) -> Dictionary:
	if not _has_structure(alliance, slot_id):
		return {"ok": false, "reason": "unknown_structure"}
	if attacker_squad != "" and not _is_allied_squad(_opponent(alliance), attacker_squad):
		return {"ok": false, "reason": "invalid_squad"}
	var structure: Dictionary = structures[alliance][slot_id]
	if winner != "" or structure["tier"] == 0 or not is_finite(amount) or amount <= 0.0:
		return {"ok": false, "reason": "unavailable"}
	if slot_id in ["vault", "hangar"] and is_shield_active(alliance):
		return {"ok": false, "reason": "shielded", "hp": structure["hp"]}
	if structure["hp"] == 0.0 and not sabotage:
		return {"ok": false, "reason": "already_destroyed"}
	var old_hp: float = structure["hp"]
	structure["hp"] = maxf(0.0, old_hp - amount)
	structure["recharge_delay"] = SHIELD_RECHARGE_DELAY
	if old_hp > 0.0 and structure["hp"] == 0.0:
		_log_event("structure_destroyed", alliance, attacker_squad, slot_id)
	if sabotage:
		structure["sabotage_progress"] += amount
		if structure["hp"] == 0.0 or structure["sabotage_progress"] >= SABOTAGE_THRESHOLD:
			structure["sabotage_timer"] = SABOTAGE_SECONDS
			structure["sabotage_progress"] = 0.0
			_log_event("structure_sabotaged", alliance, attacker_squad, slot_id)
	return {"ok": true, "reason": "", "hp": structure["hp"], "sabotage_timer": structure["sabotage_timer"]}


func _opponent(alliance: String) -> String:
	return "planet_b" if alliance == "planet_a" else "planet_a"


func _add_flag(alliance: String, index: int, golden: bool) -> void:
	var kind := "gold" if golden else "flag"
	var flag_id := "%s_%s_%02d" % [alliance, kind, index]
	flags[flag_id] = {
		"id": flag_id, "origin": alliance, "location": alliance, "points": 2 if golden else 1,
		"state": "available", "carrier": "", "progress": 0.0,
		"vault_protected": not golden and index > 12,
	}


func _can_capture(squad: Dictionary, flag: Dictionary) -> bool:
	if squad["ship_hp"] <= 0.0 or squad["alliance"] == flag["origin"] or squad["location"] != flag["location"]:
		return false
	if flag["state"] == "dropped":
		return true
	return flag["state"] == "available" and (
		not flag["vault_protected"] or not is_shield_active(flag["origin"])
	)


func _set_phase(squad: Dictionary, phase: String, location: String, phase_duration: float) -> void:
	squad["phase"] = phase
	squad["location"] = location
	squad["progress"] = 0.0
	squad["phase_time"] = 0.0
	squad["phase_duration"] = phase_duration
	for flag_id: String in squad["flags_carried"]:
		flags[flag_id]["location"] = location


func _advance_squad(squad: Dictionary) -> void:
	var alliance: String = squad["alliance"]
	var target := _opponent(alliance)
	var phase: String = squad["phase"]
	if not squad["ai_enabled"]:
		return

	squad["phase_time"] += STEP
	squad["progress"] = clampf(squad["phase_time"] / squad["phase_duration"], 0.0, 1.0)
	if phase in ["flight", "return"] and squad["flags_carried"].is_empty():
		_try_capture(squad, true)
	if squad["progress"] < 1.0:
		return

	match phase:
		"build":
			_build_or_service(squad)
			_set_phase(squad, "outfit", alliance, _rng.randf_range(20.0, 30.0))
		"outfit":
			if _should_launch(squad):
				_set_phase(squad, "flight", "space_to_" + target.right(1), _travel_time(squad))
				_log_event("squad_launched", alliance, squad["id"], target)
			else:
				_set_phase(squad, "defend", alliance, _rng.randf_range(40.0, 65.0))
		"flight":
			_set_phase(squad, "raid", target, _raid_time(squad))
			_log_event("raid_started", alliance, squad["id"], target)
		"raid":
			if act_number >= 3 and squad["strategy"] == "builder":
				var objective := "shield_gen" if is_shield_active(target) else "defense_turrets"
				sabotage_structure(target, objective, 100.0, squad["id"])
			if squad["flags_carried"].is_empty():
				_try_capture(squad, false)
			_set_phase(squad, "return", "space_to_" + alliance.right(1), _travel_time(squad))
			_log_event("squad_returning", alliance, squad["id"], alliance)
		"return":
			_set_phase(squad, "defend", alliance, _rng.randf_range(35.0, 55.0))
			for flag_id: String in squad["flags_carried"].duplicate():
				record_flag_delivered(squad["id"], flag_id)
		"defend":
			squad["ship_hp"] = squad["max_ship_hp"]
			_set_phase(squad, "build", alliance, _rng.randf_range(25.0, 35.0))


func _should_launch(squad: Dictionary) -> bool:
	match squad["strategy"]:
		"raider", "escort":
			return act_number >= 2
		"builder":
			return act_number >= 3
		_:
			return act_number == 4


func _travel_time(squad: Dictionary) -> float:
	var travel := _rng.randf_range(95.0, 115.0)
	if squad["alliance"] == "planet_b":
		if difficulty == "hard":
			return travel * 0.85
		if difficulty == "easy":
			return travel * 1.15
	return travel


func _raid_time(squad: Dictionary) -> float:
	# Batteries threaten slower raiders without making a built defense impassable.
	return _rng.randf_range(65.0, 85.0) + (10.0 if squad["strategy"] == "builder" else 0.0)


func _build_or_service(squad: Dictionary) -> void:
	var alliance: String = squad["alliance"]
	var priorities: Array = BUILD_PRIORITIES[squad["strategy"]]
	for slot_id: String in priorities:
		var structure: Dictionary = structures[alliance][slot_id]
		if structure["hp"] < structure["max_hp"] * 0.6:
			repair_structure(alliance, slot_id, 90.0, squad["id"])
			return
		if can_upgrade(alliance, slot_id)["ok"]:
			build_or_upgrade(alliance, slot_id, squad["id"])
			return


func _try_capture(squad: Dictionary, in_space: bool) -> void:
	var candidate: Dictionary = {}
	for flag: Dictionary in flags.values():
		if not _can_capture(squad, flag):
			continue
		if in_space and absf(flag["progress"] - squad["progress"]) > 0.08:
			continue
		if candidate.is_empty() or flag["points"] > candidate["points"]:
			candidate = flag
	if not candidate.is_empty():
		record_flag_captured(squad["id"], candidate["id"])
	elif not in_space:
		var target := _opponent(squad["alliance"])
		var slot_id := "shield_gen" if is_shield_active(target) else "vault"
		sabotage_structure(target, slot_id, 100.0, squad["id"])
		for flag: Dictionary in flags.values():
			if _can_capture(squad, flag):
				record_flag_captured(squad["id"], flag["id"])
				return


func _apply_combat() -> void:
	for alliance: String in ALLIANCE_SQUADS:
		var dps := get_defense_dps(alliance)
		if dps <= 0.0:
			continue

		for invader_id: String in ALLIANCE_SQUADS[_opponent(alliance)]:
			var invader: Dictionary = squads[invader_id]
			if invader["location"] == alliance and invader["phase"] == "raid":
				# Raiders are exposed to the orbital battery during arrival and departure approaches.
				if invader["phase_time"] < 1.0 or invader["phase_time"] >= invader["phase_duration"] - 1.0:
					damage_ship(invader["id"], dps * STEP)

	if act_number < 2:
		return
	for a_id: String in ALLIANCE_SQUADS["planet_a"]:
		var a: Dictionary = squads[a_id]
		if a["location"] not in SPACE_LOCATIONS:
			continue
		for b_id: String in ALLIANCE_SQUADS["planet_b"]:
			if a["location"] not in SPACE_LOCATIONS:
				break
			var b: Dictionary = squads[b_id]
			if b["location"] not in SPACE_LOCATIONS or a["location"] == b["location"]:
				continue
			if absf(a["progress"] + b["progress"] - 1.0) <= 0.045:
				var interception_dps := 1.5 * STEP
				damage_ship(a["id"], interception_dps)
				damage_ship(b["id"], interception_dps)


func repel_raid(squad_id: String) -> void:
	var squad: Dictionary = squads[squad_id]
	var alliance: String = squad["alliance"]
	_set_phase(squad, "return", "space_to_" + alliance.right(1), _travel_time(squad))


func damage_ship(squad_id: String, amount: float) -> void:
	if winner == "" and squads.has(squad_id):
		var squad: Dictionary = squads[squad_id]
		squad["ship_hp"] = maxf(1.0, squad["ship_hp"] - maxf(0.0, amount))


func _get_radar_contacts(alliance: String, space_traffic: Array[Dictionary]) -> Dictionary:
	var contacts := {"enemy_space_traffic": [], "enemy_flag_carriers": []}
	if has_radar_intel(alliance):
		for entry in space_traffic:
			if entry["alliance"] != alliance:
				contacts["enemy_space_traffic"].append(entry.duplicate(true))
		for squad_id: String in ALLIANCE_SQUADS[_opponent(alliance)]:
			var squad: Dictionary = squads[squad_id]
			if not squad["flags_carried"].is_empty():
				contacts["enemy_flag_carriers"].append({
					"id": squad_id, "alliance": squad["alliance"], "location": squad["location"],
					"progress": squad["progress"], "flags_carried": squad["flags_carried"].duplicate(),
				})
	return contacts


func _log_event(type: String, alliance: String, squad_id: String, subject: String, dropped: Array = []) -> void:
	event_log.append({
		"type": type, "time": elapsed, "alliance": alliance, "squad_id": squad_id,
		"subject": subject, "dropped_flags": dropped.duplicate(),
	})
	if event_log.size() > EVENT_LIMIT:
		event_log.pop_front()


func _finish(result: String, reason: String) -> void:
	winner = result
	win_reason = reason
	_accumulator = 0.0
	_log_event("match_finished", result, "", reason)


func _valid_snapshot(snap: Dictionary) -> bool:
	if snap.get("version") != SNAPSHOT_VERSION or typeof(snap.get("seed")) != TYPE_INT:
		return false
	if typeof(snap.get("rng_state")) != TYPE_INT or not MATCH_PRESETS.has(snap.get("match_preset")):
		return false
	if snap.get("difficulty") not in ["easy", "standard", "hard"]:
		return false
	var preset_duration: float = MATCH_PRESETS[snap["match_preset"]]
	if snap.get("duration") != preset_duration or not _valid_number(snap.get("elapsed"), preset_duration):
		return false
	if not _valid_number(snap.get("accumulator"), STEP) or snap["accumulator"] == STEP:
		return false
	var expected_act := _act_at(snap["elapsed"], preset_duration)
	if snap.get("act_number") != expected_act or snap.get("overdrive") != (expected_act == 4):
		return false
	if snap.get("winner") not in ["", "planet_a", "planet_b", "draw"]:
		return false
	if snap.get("win_reason") not in ["", "knockout", "timer"]:
		return false
	if (snap["winner"] == "") != (snap["win_reason"] == ""):
		return false
	for key in ["squads", "structures", "treasury", "scores", "flags"]:
		if typeof(snap.get(key)) != TYPE_DICTIONARY:
			return false
	if snap["squads"].size() != 8 or snap["structures"].size() != ALLIANCE_SQUADS.size():
		return false
	var flag_count := STANDARD_FLAGS_PER_PLANET + (2 if expected_act == 4 else 0)
	if snap["flags"].size() != flag_count * ALLIANCE_SQUADS.size():
		return false
	for alliance in ALLIANCE_SQUADS:
		if not _valid_alliance_snapshot(snap, alliance, flag_count):
			return false
	var events = snap.get("event_log")
	if typeof(events) != TYPE_ARRAY or events.size() > EVENT_LIMIT:
		return false
	for event in events:
		if typeof(event) != TYPE_DICTIONARY or not _valid_number(event.get("time"), snap["elapsed"]):
			return false
		for key in ["type", "alliance", "squad_id", "subject"]:
			if typeof(event.get(key)) != TYPE_STRING:
				return false
		if typeof(event.get("dropped_flags")) != TYPE_ARRAY:
			return false
	return true


func _valid_alliance_snapshot(snap: Dictionary, alliance: String, flag_count: int) -> bool:
	var slots = snap["structures"].get(alliance)
	if typeof(slots) != TYPE_DICTIONARY or slots.size() != BUILDABLE_SLOT_IDS.size():
		return false
	if not _valid_number(snap["treasury"].get(alliance)) or not _valid_counter(snap["scores"].get(alliance)):
		return false
	for slot_id in BUILDABLE_SLOT_IDS:
		if not _valid_structure_snapshot(slots.get(slot_id), alliance, slot_id):
			return false
	for squad_id in ALLIANCE_SQUADS[alliance]:
		if not _valid_squad_snapshot(snap, squad_id, alliance):
			return false
	for index in range(1, flag_count + 1):
		var golden := index > STANDARD_FLAGS_PER_PLANET
		var flag_index := index - STANDARD_FLAGS_PER_PLANET if golden else index
		var flag_id := "%s_%s_%02d" % [alliance, "gold" if golden else "flag", flag_index]
		var flag = snap["flags"].get(flag_id)
		if typeof(flag) != TYPE_DICTIONARY or flag.get("id") != flag_id or flag.get("origin") != alliance:
			return false
		if flag.get("points") != (2 if golden else 1) or typeof(flag.get("vault_protected")) != TYPE_BOOL:
			return false
		if flag.get("state") not in ["available", "carried", "dropped", "delivered"]:
			return false
		if flag.get("location") not in ["planet_a", "planet_b", "space_to_a", "space_to_b"]:
			return false
		if not _valid_number(flag.get("progress"), 1.0):
			return false
		if flag["state"] == "carried":
			var carrier = snap["squads"].get(flag.get("carrier"))
			if typeof(carrier) != TYPE_DICTIONARY or typeof(carrier.get("flags_carried")) != TYPE_ARRAY:
				return false
			if flag_id not in carrier["flags_carried"]:
				return false
		elif flag.get("carrier") != "":
			return false
	return true


func _valid_structure_snapshot(structure: Variant, alliance: String, slot_id: String) -> bool:
	if typeof(structure) != TYPE_DICTIONARY:
		return false
	var tier = structure.get("tier")
	if not _valid_counter(tier) or tier > 3 or (slot_id == "vault" and tier < 1):
		return false
	var max_hp: float = float(EMPIRE_SLOTS[slot_id]["hp"][tier - 1]) if tier > 0 else 0.0
	if structure.get("max_hp") != max_hp or not _valid_number(structure.get("hp"), max_hp):
		return false
	if not _valid_number(structure.get("sabotage_timer"), SABOTAGE_SECONDS):
		return false
	if not _valid_number(structure.get("sabotage_progress"), SABOTAGE_THRESHOLD):
		return false
	if not _valid_number(structure.get("recharge_delay"), SHIELD_RECHARGE_DELAY):
		return false
	return structure.get("built_by") == "" or structure.get("built_by") in ALLIANCE_SQUADS[alliance]


func _valid_squad_snapshot(snap: Dictionary, squad_id: String, alliance: String) -> bool:
	var squad = snap["squads"].get(squad_id)
	if typeof(squad) != TYPE_DICTIONARY or squad.get("id") != squad_id or squad.get("alliance") != alliance:
		return false
	if squad.get("is_player_squad") != (squad_id == "orange") or squad.get("seats") != SPECIALISTS:
		return false
	if typeof(squad.get("ai_enabled")) != TYPE_BOOL or squad.get("strategy") not in STRATEGIES:
		return false
	if squad.get("ship_family") not in ["kestrel", "lancer", "hauler", "halo", "bulwark"]:
		return false
	if squad.get("phase") not in PHASES or squad.get("location") not in [
		"planet_a", "space_to_b", "planet_b", "space_to_a",
	]:
		return false
	if not _valid_number(squad.get("phase_duration")) or squad["phase_duration"] == 0.0:
		return false
	if not _valid_number(squad.get("phase_time")) or not _valid_number(squad.get("progress"), 1.0):
		return false
	if not _valid_number(squad.get("max_ship_hp"), 100.0) or squad["max_ship_hp"] == 0.0:
		return false
	if not _valid_number(squad.get("ship_hp"), squad["max_ship_hp"]) or squad["ship_hp"] < 1.0:
		return false
	for key in ["kills", "captures", "deliveries", "builds_contributed", "credits_contributed"]:
		if not _valid_counter(squad.get(key)):
			return false
	var cargo = squad.get("flags_carried")
	if typeof(cargo) != TYPE_ARRAY:
		return false
	var seen := {}
	for flag_id in cargo:
		if typeof(flag_id) != TYPE_STRING or seen.has(flag_id):
			return false
		var flag = snap["flags"].get(flag_id)
		if typeof(flag) != TYPE_DICTIONARY:
			return false
		if flag.get("state") != "carried" or flag.get("carrier") != squad_id:
			return false
		seen[flag_id] = true
	return true


func _valid_number(value: Variant, maximum: float = INF) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(value) and value >= 0.0 and value <= maximum


func _valid_counter(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0
