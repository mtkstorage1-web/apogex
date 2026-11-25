class_name AIManager
extends Node3D

const TrooperScene = preload("res://scenes/combat/BotTrooper.tscn")
const Trooper = preload("res://scripts/ai/BotTrooper.gd")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Turret = preload("res://scripts/gameplay/DefenseTurret.gd")
const Fighter = preload("res://scripts/ai/BotFighterAI.gd")
const Match = preload("res://scripts/gameplay/MatchManager.gd")

var world: Node
var current_origin := Vector3.ZERO
var troopers: Array[CharacterBody3D] = []
var fighters: Array[CharacterBody3D] = []
var roster: Dictionary = {}
var _player_kills: Dictionary = {}
var _entries_by_callsign: Dictionary = {}
var rally_orders := {}
var _fighter_patrols := {}
var _origin_shift_frame := -2


func setup(p_world: Node) -> void:
	world = p_world
	current_origin = world.floating_origin.current_origin
	for faction in Match.FACTIONS:
		var entries: Array[Dictionary] = []
		for slot in 16:
			var entry := {
				"callsign": "%s-%02d" % [faction.to_upper(), slot + 1],
				"role": "Infantry" if slot < 6 else ("Fighter" if slot < 8 else "Reserve"),
				"kills": 0, "deaths": 0,
			}
			entries.append(entry)
			_entries_by_callsign[entry.callsign] = entry
		roster[faction] = entries
		for index in 6:
			var bot := TrooperScene.instantiate() as CharacterBody3D
			bot.set_script(FieldTrooper)
			bot.faction = faction
			bot.callsign = entries[index].callsign
			bot.objective = world.match_manager.objectives[index / 2]
			bot.squad_slot = index % 2
			bot.manager = self
			bot.name = bot.callsign
			add_child(bot)
			bot.eliminated.connect(_record_elimination)
			troopers.append(bot)
		for index in 2:
			var fighter := FieldFighter.new()
			fighter.faction = faction
			fighter.callsign = entries[6 + index].callsign
			fighter.wing_slot = index
			fighter.manager = self
			fighter.name = fighter.callsign
			add_child(fighter)
			fighter.eliminated.connect(_record_elimination)
			fighters.append(fighter)
	reset_pool()


func reset_pool() -> void:
	clear_rally_orders()
	_player_kills.clear()
	for entry in _entries_by_callsign.values():
		entry.kills = 0
		entry.deaths = 0
	for bot in troopers:
		bot.respawn()
	for fighter in fighters:
		fighter.respawn(false)
		_fighter_patrols[fighter] = fighter._route.duplicate()


func apply_origin(new_origin: Vector3) -> void:
	var shift := new_origin - current_origin
	for bot in get_children():
		bot.global_position -= shift
		bot.reset_physics_interpolation()
	current_origin = new_origin
	_origin_shift_frame = Engine.get_physics_frames()


func origin_is_resyncing() -> bool:
	return Engine.get_physics_frames() <= _origin_shift_frame + 1


func update_objectives(delta: float) -> void:
	for faction in rally_orders:
		_apply_fighter_rally(faction, objective_by_id(rally_orders[faction]))
	var player: CharacterBody3D = world.explorer
	var combat: Node = world.player_combat
	for objective in world.match_manager.objectives:
		var helion := 0
		var cinder := 0
		for bot in troopers:
			if bot.health > 0.0 and objective.is_in_capture_radius(bot.global_position):
				if bot.faction == "helion":
					helion += 1
				else:
					cinder += 1
		var present := ""
		if not player.is_piloting and combat.health > 0.0 and player.move_mode == 0 and objective.is_in_capture_radius(player.global_position):
			var height: float = (player.global_position - objective.global_position).dot(objective.global_basis.y)
			if absf(height) <= 6.0:
				present = combat.faction
				if present == "helion":
					helion += 1
				else:
					cinder += 1
		for avatar in world.network_authority.replication.avatars.values():
			if avatar.health > 0.0 and avatar.visible and objective.is_in_capture_radius(avatar.global_position):
				if avatar.faction == "helion":
					helion += 1
				else:
					cinder += 1
		objective.update_capture(delta, helion, cinder, present)


func get_roster_counts() -> Dictionary:
	return {"helion": roster.get("helion", []).size(), "cinder": roster.get("cinder", []).size()}


func get_scoreboard() -> Dictionary:
	var board := roster.duplicate(true)
	var peer_teams: Dictionary = world.network_authority.peer_factions
	if world.network_authority.get_network_mode() == "OFFLINE":
		peer_teams = {1: world.match_manager.player_faction}
	var slots := {"helion": 15, "cinder": 15}
	var ids := peer_teams.keys()
	ids.sort()
	for id in ids:
		var faction: String = peer_teams[id]
		var is_local: bool = id == world.multiplayer.get_unique_id()
		var kills: int = world.match_manager.player_stats.kills if is_local else 0
		var label := "You" if is_local else "Peer %d" % id
		board[faction][slots[faction]] = {"callsign": label, "role": "Player", "kills": kills, "deaths": 0}
		slots[faction] -= 1
	return board


func find_trooper_target(bot: CharacterBody3D, reach: float) -> Node3D:
	var closest: Node3D
	var best := reach * reach
	for other in troopers + world.network_authority.replication.avatars.values():
		if other.faction == bot.faction or other.health <= 0.0 or other.get_meta("boarded", false):
			continue
		var distance := bot.global_position.distance_squared_to(other.global_position)
		if distance < best:
			best = distance
			closest = other
	var player: CharacterBody3D = world.explorer
	if not player.is_piloting and world.player_combat.health > 0.0 and world.player_combat.faction != bot.faction:
		if bot.global_position.distance_squared_to(player.global_position) < best:
			closest = player
	return closest


func find_fighter_target(bot: CharacterBody3D, reach: float) -> Node3D:
	var closest: Node3D
	var best := reach * reach
	for other in fighters:
		if other.faction == bot.faction or other.health <= 0.0 or other.state == "LAUNCH":
			continue
		var distance := bot.global_position.distance_squared_to(other.global_position)
		if distance < best:
			best = distance
			closest = other
	var player: CharacterBody3D = world.get_active_vehicle()
	if player != null and player.faction != bot.faction and player.vehicle_type == "fighter" and player.health > 0.0:
		if bot.global_position.distance_squared_to(player.global_position) < best:
			best = bot.global_position.distance_squared_to(player.global_position)
			closest = player
	for id in world.network_authority.get_remote_vehicle_ids():
		var vehicle: Node3D = world.vehicle_manager.vehicles.get(id)
		if vehicle == null or vehicle.faction == bot.faction or vehicle.vehicle_type != "fighter" or vehicle.health <= 0.0:
			continue
		var distance: float = bot.global_position.distance_squared_to(vehicle.global_position)
		if distance < best:
			best = distance
			closest = vehicle
	return closest


func note_player_kill(bot: Node) -> void:
	_player_kills[bot] = true


func note_bot_kill(attacker: Node, victim: Node) -> void:
	if _entries_by_callsign.has(attacker.callsign) and victim.health <= 0.0:
		_entries_by_callsign[attacker.callsign].kills += 1


func _record_elimination(bot: Node, killer_faction: String) -> void:
	_entries_by_callsign[bot.callsign].deaths += 1
	var player_kill := _player_kills.erase(bot)
	world.match_manager.record_elimination(killer_faction, bot.callsign, player_kill)


func objective_by_id(id: String) -> Node3D:
	for objective in world.match_manager.objectives:
		if objective.objective_id == id:
			return objective
	return null


func set_rally_order(faction: String, id: String) -> bool:
	var objective := objective_by_id(id)
	if faction not in Match.FACTIONS or objective == null:
		return false
	rally_orders[faction] = id
	for bot in troopers:
		if bot.faction == faction:
			bot.objective = objective
	_apply_fighter_rally(faction, objective)
	return true


func _apply_fighter_rally(faction: String, objective: Node3D) -> void:
	for fighter in fighters:
		if fighter.faction != faction:
			continue
		var center: Vector3 = objective.planet_position + objective.global_basis.y * (260.0 + fighter.wing_slot * 90.0)
		var route: Array[Vector3] = []
		for offset in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
			route.append(center + objective.global_basis * offset * 310.0)
		if fighter._route != route:
			fighter._route = route
			fighter._waypoint = 0


func clear_rally_orders() -> void:
	rally_orders.clear()
	for index in troopers.size():
		troopers[index].objective = world.match_manager.objectives[(index % 6) / 2]
	for fighter in fighters:
		if _fighter_patrols.has(fighter):
			fighter._route = _fighter_patrols[fighter].duplicate()
			fighter._waypoint = 0


func apply_rally_orders(orders: Dictionary) -> void:
	if rally_orders == orders:
		return
	clear_rally_orders()
	for faction in orders:
		set_rally_order(faction, orders[faction])


func fire_bot_weapon(bot: CharacterBody3D, target: Node3D, start: Vector3, end: Vector3, damage: float, width: float) -> void:
	var hit := Combat.cast_ray(bot, start, end, Combat.HIT_MASK | 2)
	var point: Vector3 = hit.get("position", end)
	var screened: Dictionary = world.engineering_build_manager.intercept_shot(start, point, bot.faction, damage)
	world.network_authority.publish_tracer(start, screened.get("position", point), Combat.faction_color(bot.faction), width)
	if not screened.is_empty() or hit.get("collider") != target:
		return
	if Turret.damage_target(world, target, damage, bot.faction, start if target == world.explorer else point) and target != world.explorer:
		note_bot_kill(bot, target)


class FieldTrooper extends Trooper:
	func _fire(up: Vector3) -> void:
		_cooldown = 0.48 + squad_slot * 0.12
		var center: Vector3 = Turret.aim_point(manager.world, _target)
		manager.fire_bot_weapon(self, _target, global_position + up * 1.37, center, 9.0 if _target == manager.world.explorer or _target.get("peer_id") != null else 16.0, 0.028)


class FieldFighter extends Fighter:
	func _fire_at(enemy: Node3D) -> void:
		_cooldown = 0.24 + wing_slot * 0.08
		var start := global_position + global_basis * Vector3(0, 1.5, -6)
		manager.fire_bot_weapon(self, enemy, start, enemy.global_position + enemy.global_basis.y * 1.5, 18.0 if enemy is Vehicle else 22.0, 0.24)
