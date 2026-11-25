class_name MatchManager
extends Node

signal faction_changed(faction: String)
signal victory_declared(faction: String)

const FACTIONS := ["helion", "cinder"]
const CAPTURE_POINTS := 40.0
const ELIMINATION_POINTS := 15.0
const EXTRACTION_PER_SECOND := 2.0

var target_score := 1000.0
var scores := {"helion": 0.0, "cinder": 0.0}
var team_resources := {"helion": 250.0, "cinder": 250.0}
var _engineering_income := {}
var _starting_resource_grants := {}
var player_faction := "helion"
var match_state := "ACTIVE"
var winner_faction := ""
var match_time := 0.0
var objectives: Array = []
var killfeed: Array[String] = []
var player_stats := {"kills": 0, "captures": 0, "repairs": 0.0, "extracted_resources": 0.0}


func tick(delta: float) -> void:
	if match_state != "ACTIVE":
		return
	match_time += delta
	for objective in objectives:
		var faction: String = objective.owner_faction
		if scores.has(faction):
			scores[faction] += EXTRACTION_PER_SECOND * delta
			team_resources[faction] += 8.0 * delta
	_check_victory()


func switch_faction(faction: String) -> bool:
	if not scores.has(faction):
		return false
	if player_faction != faction:
		player_faction = faction
		faction_changed.emit(faction)
	return true


func reset_match() -> void:
	for faction in FACTIONS:
		scores[faction] = 0.0
		team_resources[faction] = 250.0
	_engineering_income.clear()
	_starting_resource_grants.clear()
	match_state = "ACTIVE"
	winner_faction = ""
	match_time = 0.0
	killfeed.clear()
	player_stats = {"kills": 0, "captures": 0, "repairs": 0.0, "extracted_resources": 0.0}
	for objective in objectives:
		objective.reset_capture()


func record_capture(faction: String, objective_name: String, player_present: bool) -> void:
	if match_state != "ACTIVE" or not scores.has(faction):
		return
	if player_present and faction == player_faction:
		player_stats.captures += 1
	_add_event("%s captured %s" % [faction.to_upper(), objective_name])
	_award(faction, CAPTURE_POINTS)


func record_elimination(killer_faction: String, victim_name: String, player_kill: bool = true) -> void:
	if match_state != "ACTIVE" or not scores.has(killer_faction):
		return
	if player_kill and killer_faction == player_faction:
		player_stats.kills += 1
	_add_event("%s eliminated %s" % [killer_faction.to_upper(), victim_name])
	team_resources[killer_faction] += 20.0
	_award(killer_faction, ELIMINATION_POINTS)


func record_repair(amount: float) -> void:
	if match_state == "ACTIVE" and amount > 0.0:
		player_stats.repairs += amount
		credit_engineering(player_faction, "repair", amount, 10.0, 10.0)
		_award(player_faction, amount * 0.1)


func record_extraction(amount: float) -> void:
	if match_state == "ACTIVE" and amount > 0.0:
		player_stats.extracted_resources += amount
		credit_engineering(player_faction, "extraction", amount, 1.0, 25.0)
		_award(player_faction, amount)


func get_match_summary() -> Dictionary:
	var control: Array[Dictionary] = []
	for objective in objectives:
		control.append(objective.get_capture_status())
	return {
		"match_state": match_state, "winner_faction": winner_faction, "match_time": match_time,
		"target_score": target_score, "scores": scores.duplicate(), "player_faction": player_faction,
		"team_resources": team_resources.duplicate(), "objectives": control, "killfeed": killfeed.duplicate(), "player_stats": player_stats.duplicate(),
	}


func _award(faction: String, amount: float) -> void:
	scores[faction] += amount
	_check_victory()


func _check_victory() -> void:
	if match_state == "ACTIVE" and maxf(scores.helion, scores.cinder) >= target_score:
		match_state = "VICTORY"
		winner_faction = "helion" if scores.helion >= scores.cinder else "cinder"
		_add_event("%s victory" % winner_faction.to_upper())
		victory_declared.emit(winner_faction)


func _add_event(event: String) -> void:
	killfeed.push_front(event)
	if killfeed.size() > 6:
		killfeed.pop_back()


func apply_starting_role(faction: String, role: String, player_id: int) -> void:
	if role != "engineer" or match_state != "ACTIVE" or not team_resources.has(faction):
		return
	var key := Vector2i(player_id, FACTIONS.find(faction))
	if not _starting_resource_grants.has(key):
		_starting_resource_grants[key] = true
		team_resources[faction] += 100.0


func spend_resources(faction: String, cost: float) -> bool:
	if match_state != "ACTIVE" or not team_resources.has(faction) or not is_finite(cost) or cost < 0.0 or team_resources[faction] < cost:
		return false
	team_resources[faction] -= cost
	return true


func credit_engineering(faction: String, job: String, amount: float, work_per_award: float, award: float) -> void:
	var key := faction + ":" + job
	var accumulated: float = _engineering_income.get(key, 0.0) + amount
	var completed := floorf((accumulated + 0.00001) / work_per_award)
	_engineering_income[key] = maxf(0.0, accumulated - completed * work_per_award)
	team_resources[faction] += completed * award
