class_name ArenaClashSim
extends RefCounted
## Authoritative Arena Clash rules. Time advances in quarter-second steps.

const Empire := preload("res://scripts/empire_sim.gd")
const Catalog := preload("res://scripts/ship_catalog.gd")
const BUILD_ORDER := Catalog.BUILD_ORDER
const AI_TRANSIT_SECONDS := 55.0
const PRESETS := {
	"standard": {"duration": 480.0, "kill_target": 60},
	"short": {"duration": 240.0, "kill_target": 30},
}
# The default catalog's flight minimum costs 1060 credits.
const PART_PRICES := {
	"reactor": 180, "engine": 170, "bridge": 150, "keel": 150,
	"port": 120, "thruster": 120, "battery": 140, "coolant": 120,
	"scrubber": 120, "stores": 90, "cargo": 100, "antenna": 90,
}
const STARTING_CREDITS := 1000
# The human squad starts richer so the cheapest full ship (~1500 CR) is affordable.
const PLAYER_STARTING_CREDITS := 4000
const BUILD_SECONDS := 4.0
const FLIGHT_PARTS := ["reactor", "engine", "bridge"]
const BASE_HEALTH := 100.0
const BASE_SHIELD := 75.0 # PlayerCombatComponent.BASE_SHIELD
const BASE_RESPAWN := 8.0
const STEP := 0.25
const AI_ATTACK_INTERVAL := 0.5
const EVENT_LIMIT := Empire.EVENT_LIMIT
const SNAPSHOT_VERSION := 2

var live_combat := false
var time_left: float = 0.0
var kill_target: int = 0
var squads: Dictionary = {}
var combatants: Dictionary = {}
var event_log: Array = []

var _preset: String = "standard"
var player_squad: String = "orange"
var _scores: Dictionary = {}
var _winner: String = ""
var _accumulator: float = 0.0
var _ai_attack_left: float = AI_ATTACK_INTERVAL
var _rng := RandomNumberGenerator.new()


## Pass an empty player squad to simulate construction, travel and combat for both sides.
func setup(seed_value: int = 4209, preset: String = "standard", player_squad: String = "orange") -> void:
	_preset = preset if PRESETS.has(preset) else "standard"
	time_left = PRESETS[_preset]["duration"]
	kill_target = PRESETS[_preset]["kill_target"]
	_winner = ""
	_accumulator = 0.0
	_ai_attack_left = AI_ATTACK_INTERVAL
	_rng.seed = seed_value
	squads.clear()
	combatants.clear()
	event_log.clear()
	_scores.clear()
	for alliance: String in Empire.ALLIANCE_SQUADS:
		_scores[alliance] = 0
		var roster: Array = Empire.ALLIANCE_SQUADS[alliance]
		for index in roster.size():
			var squad_id: String = roster[index]
			squads[squad_id] = {
				"id": squad_id, "alliance": alliance, "ship_family": Empire.SHIP_FAMILIES[alliance][index],
				"seats": Empire.SPECIALISTS.duplicate(true), "credits": STARTING_CREDITS,
				"owned": [], "building": {}, "built": [], "location": alliance,
				"flight_capable": false, "transit_left": 0.0,
			}
	self.player_squad = player_squad if player_squad.is_empty() or squads.has(player_squad) else "orange"
	if squads.has(self.player_squad):
		squads[self.player_squad]["credits"] = PLAYER_STARTING_CREDITS


func tick(dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0 or is_finished() or squads.is_empty():
		return
	_accumulator += minf(dt, time_left)
	while _accumulator + 0.000000001 >= STEP and not is_finished():
		_accumulator = maxf(0.0, _accumulator - STEP)
		_step()
	if is_finished():
		_accumulator = 0.0


func buy_part(squad_id: String, slot: String) -> Dictionary:
	var error := _shop_error(squad_id, slot)
	if not error.is_empty():
		return {"ok": false, "error": error}
	var squad: Dictionary = squads[squad_id]
	if slot in squad["owned"]:
		return {"ok": false, "error": "already_owned"}
	var price: int = PART_PRICES[slot]
	if squad["credits"] < price:
		return {"ok": false, "error": "insufficient_credits"}
	squad["credits"] -= price
	squad["owned"].append(slot)
	return {"ok": true, "error": ""}


func build_part(squad_id: String, slot: String) -> Dictionary:
	var error := _shop_error(squad_id, slot)
	if not error.is_empty():
		return {"ok": false, "error": error}
	var squad: Dictionary = squads[squad_id]
	if slot not in squad["owned"]:
		return {"ok": false, "error": "not_owned"}
	if slot in squad["built"]:
		return {"ok": false, "error": "already_built"}
	if squad["building"].has(slot):
		return {"ok": false, "error": "already_building"}
	squad["building"][slot] = BUILD_SECONDS
	return {"ok": true, "error": ""}


func is_finished() -> bool:
	return _winner != ""


func set_squad_location(squad_id: String, location: String) -> bool:
	if is_finished() or not squads.has(squad_id) or (location != "space" and not Universe.PLANETS.has(location)):
		return false
	var squad: Dictionary = squads[squad_id]
	if not squad["flight_capable"]:
		return false
	if squad["location"] == location:
		return true
	squad["location"] = location
	if location != "planet_c":
		return true
	for seat in Empire.SPECIALISTS.size():
		var id := "%s:%d" % [squad_id, seat]
		if combatants.has(id):
			continue
		var state := {
			"id": id, "squad_id": squad_id, "alliance": squad["alliance"], "seat_index": seat,
			"alive": false, "health": 0.0, "shield": 0.0, "respawn_left": 0.0,
			"kills": 0, "deaths": 0,
		}
		combatants[id] = state
		_spawn(state)
	_log_event("%s landed on %s" % [squad_id, Universe.C_LABEL])
	return true


func is_in_arena(state: Dictionary) -> bool:
	return not state.is_empty() and squads[state["squad_id"]]["location"] == "planet_c"


func ai_prep_step(squad_id: String) -> void:
	if is_finished() or not squads.has(squad_id):
		return
	var squad: Dictionary = squads[squad_id]
	if squad["location"] != squad["alliance"] or not squad["building"].is_empty():
		return
	for slot: String in BUILD_ORDER:
		if slot in squad["built"]:
			continue
		if slot in squad["owned"] or buy_part(squad_id, slot)["ok"]:
			build_part(squad_id, slot)
			return
	if set_squad_location(squad_id, "space"):
		squad["transit_left"] = AI_TRANSIT_SECONDS


## Health and shield values are additive bonuses. Respawn time is in seconds.
func get_bonuses(squad_id: String) -> Dictionary:
	var squad: Dictionary = squads.get(squad_id, {})
	var built: Array = squad.get("built", [])
	return {
		"max_health": minf(50.0, 20.0 * _count_parts(built, ["keel", "bridge", "stores"])),
		"shield": minf(50.0, 20.0 * _count_parts(built, ["battery", "reactor", "coolant"])),
		"damage_multiplier": minf(1.25, 1.0 + 0.1 * _count_parts(built, ["port", "thruster", "antenna"])),
		"respawn_time": maxf(4.0, BASE_RESPAWN - 1.5 * _count_parts(built, ["scrubber", "cargo", "engine"])),
	}


func apply_damage(attacker_id: String, victim_id: String, amount: float) -> Dictionary:
	if is_finished() or not is_finite(amount) or amount <= 0.0:
		return {"killed": false}
	var attacker: Dictionary = combatants.get(attacker_id, {})
	var victim: Dictionary = combatants.get(victim_id, {})
	if not attacker.get("alive", false) or not victim.get("alive", false) or not is_in_arena(attacker) or not is_in_arena(victim):
		return {"killed": false}
	var alliance: String = attacker["alliance"]
	if alliance == victim["alliance"]:
		return {"killed": false}

	var damage: float = amount * get_bonuses(attacker["squad_id"])["damage_multiplier"]
	var absorbed := minf(victim["shield"], damage)
	victim["shield"] -= absorbed
	victim["health"] = maxf(0.0, victim["health"] - (damage - absorbed))
	if victim["health"] > 0.0:
		return {"killed": false}

	victim["respawn_left"] = _next_respawn(victim["squad_id"])
	victim["alive"] = false
	victim["deaths"] += 1
	attacker["kills"] += 1
	_scores[alliance] += 1
	_log_event("%s killed %s" % [attacker["squad_id"], victim_id])
	if _scores[alliance] >= kill_target:
		_finish(alliance)
	return {"killed": true}


## Read-only view of the authoritative live state, or an empty dictionary before arena entry.
func combatant(id: String) -> Dictionary:
	return combatants.get(id, {})


func get_score() -> Dictionary:
	return _scores.duplicate()


func winner() -> String:
	return _winner


func get_hud_summary() -> Dictionary:
	var squad_summary := {}
	for squad_id: String in squads:
		var squad: Dictionary = squads[squad_id]
		squad_summary[squad_id] = {
			"credits": squad["credits"], "built": squad["built"].size(), "location": squad["location"],
		}
	return {
		"time_left": time_left, "scores": get_score(),
		"kill_target": kill_target, "squads": squad_summary,
	}


func to_snapshot() -> Dictionary:
	return {
		"version": SNAPSHOT_VERSION, "seed": _rng.seed, "rng_state": _rng.state,
		"preset": _preset, "player_squad": player_squad, "time_left": time_left,
		"kill_target": kill_target, "winner": _winner, "accumulator": _accumulator,
		"ai_attack_left": _ai_attack_left, "live_combat": live_combat, "scores": get_score(), "squads": squads.duplicate(true),
		"combatants": combatants.duplicate(true), "event_log": event_log.duplicate(),
	}


## Restore a snapshot produced by to_snapshot() from the same snapshot version.
func from_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.get("version") != SNAPSHOT_VERSION:
		return false
	# Match the Variant wire types before assigning any state.
	var expected := to_snapshot()
	for key: String in expected:
		if typeof(snapshot.get(key)) != typeof(expected[key]):
			return false
	if not PRESETS.has(snapshot["preset"]):
		return false
	var state := snapshot.duplicate(true)
	_rng.seed = state["seed"]
	_rng.state = state["rng_state"]
	_preset = state["preset"]
	player_squad = state["player_squad"]
	time_left = state["time_left"]
	kill_target = state["kill_target"]
	_winner = state["winner"]
	_accumulator = state["accumulator"]
	_ai_attack_left = state["ai_attack_left"]
	live_combat = state.get("live_combat", false)
	_scores = state["scores"]
	squads = state["squads"]
	combatants = state["combatants"]
	event_log = state["event_log"]
	return true


func _shop_error(squad_id: String, slot: String) -> String:
	if is_finished():
		return "match_finished"
	if not squads.has(squad_id):
		return "unknown_squad"
	if squads[squad_id]["location"] != squads[squad_id]["alliance"]:
		return "away_from_home"
	if not PART_PRICES.has(slot):
		return "unknown_slot"
	return ""


func _count_parts(built: Array, slots: Array) -> int:
	var count := 0
	for slot: String in slots:
		count += int(slot in built)
	return count


func _step() -> void:
	time_left = maxf(0.0, time_left - STEP)
	if time_left <= 0.0:
		var leader := "draw"
		if _scores["planet_a"] != _scores["planet_b"]:
			leader = "planet_a" if _scores["planet_a"] > _scores["planet_b"] else "planet_b"
		_finish(leader)
		return
	_advance_builds()
	_advance_spawns()
	for id: String in squads:
		if id == player_squad:
			continue
		var squad: Dictionary = squads[id]
		if squad["location"] == "space":
			squad["transit_left"] = maxf(0.0, squad["transit_left"] - STEP)
			if squad["transit_left"] == 0.0:
				set_squad_location(id, "planet_c")
		else:
			ai_prep_step(id)
	if not live_combat:
		_ai_attack_left -= STEP
		if _ai_attack_left <= 0.0:
			_ai_attack_left = AI_ATTACK_INTERVAL
			_ai_attack()


func _advance_builds() -> void:
	for squad: Dictionary in squads.values():
		if squad["location"] != squad["alliance"]:
			continue
		var building: Dictionary = squad["building"]
		if building.is_empty():
			continue
		var built: Array = squad["built"]
		for slot: String in building.keys():
			building[slot] -= STEP
			if building[slot] <= 0.0:
				building.erase(slot)
				built.append(slot)
		squad["flight_capable"] = FLIGHT_PARTS.all(func(slot: String) -> bool: return slot in built)


func _spawn(combatant: Dictionary) -> void:
	var bonuses := get_bonuses(combatant["squad_id"])
	combatant["health"] = BASE_HEALTH + bonuses["max_health"]
	combatant["shield"] = BASE_SHIELD + bonuses["shield"]
	combatant["respawn_left"] = 0.0
	combatant["alive"] = true


## A squad's first casualty starts its wave. Later casualties join that countdown.
func _next_respawn(squad_id: String) -> float:
	for teammate: Dictionary in combatants.values():
		if teammate["squad_id"] == squad_id and not teammate["alive"] and teammate["deaths"] > 0:
			return teammate["respawn_left"]
	return get_bonuses(squad_id)["respawn_time"]


func _advance_spawns() -> void:
	for combatant: Dictionary in combatants.values():
		if not combatant["alive"]:
			combatant["respawn_left"] -= STEP
			if combatant["respawn_left"] <= 0.0:
				_spawn(combatant)


func _ai_attack() -> void:
	if live_combat:
		return
	var teams := {"planet_a": [], "planet_b": []}
	for combatant: Dictionary in combatants.values():
		if combatant["alive"] and combatant["squad_id"] != player_squad and is_in_arena(combatant):
			teams[combatant["alliance"]].append(combatant["id"])
	var attackers: Array = teams["planet_a"]
	var defenders: Array = teams["planet_b"]
	if attackers.is_empty() or defenders.is_empty():
		return
	if _rng.randi_range(0, 1) == 1:
		attackers = teams["planet_b"]
		defenders = teams["planet_a"]
	apply_damage(
		attackers[_rng.randi_range(0, attackers.size() - 1)],
		defenders[_rng.randi_range(0, defenders.size() - 1)],
		_rng.randf_range(55.0, 95.0)
	)


func _finish(result: String) -> void:
	_winner = result
	_accumulator = 0.0
	_log_event("match finished: %s" % result)


func _log_event(message: String) -> void:
	event_log.append(message)
	if event_log.size() > EVENT_LIMIT:
		event_log.pop_front()
