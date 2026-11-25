class_name NetworkAuthorityManager
extends Node

signal session_changed(mode: String)

const Replication = preload("res://scripts/multiplayer/NetworkPlayerReplication.gd")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Turret = preload("res://scripts/gameplay/DefenseTurret.gd")
const Shot = preload("res://scripts/vehicles/Projectile.gd")
const Fleet = preload("res://scripts/vehicles/VehicleManager.gd")
const MAX_PLAYERS := 32
const TEAM_SIZE := 16
const DEFAULT_PORT := 24567
const SNAPSHOT_INTERVAL := 0.5

var world_seed := 0
var peer_factions: Dictionary = {}
var _mode := "OFFLINE"
var _world: Node
var _snapshot_wait := 0.0
var replication: Replication
var _fire_times := {}
var _engineering_times := {}
var _vehicle_owners := {}
var _client_fire_wait := 0.0
var _respawns := {}
var _manual_spawn_times := {}



func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connection_failed.connect(disconnect_session)
	multiplayer.server_disconnected.connect(disconnect_session)


func setup(world: Node) -> void:
	_world = world
	world_seed = world.world_config.world_seed
	replication = Replication.new()
	replication.name = "NetworkPlayerReplication"
	add_child(replication)
	replication.setup(world)


func host_server(port: int = DEFAULT_PORT, seed: int = 0) -> Error:
	if not is_inside_tree() or _mode != "OFFLINE":
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	# The listen server takes one of the 32 roster slots.
	var result := peer.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		return result
	multiplayer.multiplayer_peer = peer
	_mode = "HOST"
	world_seed = seed
	peer_factions.clear()
	assign_peer_faction(1, _world.match_manager.player_faction if _world != null else "helion")
	if _world != null and _world.world_config.world_seed != seed:
		_world.regenerate_world(seed)
	session_changed.emit(_mode)
	return OK


func join_server(address: String, port: int = DEFAULT_PORT) -> Error:
	if not is_inside_tree() or _mode != "OFFLINE":
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address, port)
	if result != OK:
		return result
	peer_factions.clear()
	multiplayer.multiplayer_peer = peer
	_mode = "CLIENT"
	session_changed.emit(_mode)
	return OK


func disconnect_session() -> void:
	if _mode == "OFFLINE":
		return
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_mode = "OFFLINE"
	peer_factions.clear()
	reset_live_state()
	_snapshot_wait = 0.0
	session_changed.emit(_mode)


func is_server_authority() -> bool:
	return _mode != "CLIENT"


func get_network_mode() -> String:
	return _mode


func assign_peer_faction(peer_id: int, preferred: String = "") -> String:
	if not is_server_authority() or peer_id <= 0:
		return ""
	if peer_factions.has(peer_id):
		return peer_factions[peer_id]
	var counts := get_peer_counts()
	if counts.helion >= TEAM_SIZE and counts.cinder >= TEAM_SIZE:
		return ""
	var team := "helion" if counts.helion <= counts.cinder else "cinder"
	if counts.has(preferred) and counts[preferred] < TEAM_SIZE and counts[preferred] == counts[team]:
		team = preferred
	peer_factions[peer_id] = team
	return team


func set_host_faction(faction: String) -> bool:
	if _mode != "HOST":
		return _mode == "OFFLINE"
	if faction not in ["helion", "cinder"]:
		return false
	if peer_factions.get(1) == faction:
		return true
	if get_peer_counts()[faction] >= TEAM_SIZE:
		return false
	peer_factions[1] = faction
	return true


func get_peer_counts() -> Dictionary:
	var counts := {"helion": 0, "cinder": 0}
	for team in peer_factions.values():
		counts[team] += 1
	return counts


func _peer_connected(id: int) -> void:
	if _mode != "HOST":
		return
	if assign_peer_faction(id).is_empty():
		multiplayer.multiplayer_peer.disconnect_peer(id)
	elif _world != null:
		_receive_snapshot.rpc_id(id, build_world_sync_snapshot(_world))
		_initialize_remote_player(id)


func _peer_disconnected(id: int) -> void:
	if _mode == "HOST":
		peer_factions.erase(id)
		_release_remote_vehicle(id)
		replication.remove_peer(id)
		_fire_times.erase(id)
		_engineering_times.erase(id)
		_respawns.erase(id)
		_manual_spawn_times.erase(id)


func tick(delta: float) -> void:
	replication.network_tick(delta)
	if _mode == "CLIENT":
		_client_fire_wait = maxf(0.0, _client_fire_wait - delta)
	if _mode == "HOST":
		for id in _respawns.keys():
			_respawns[id] -= delta
			if _respawns[id] <= 0.0:
				_respawns.erase(id)
				_spawn_remote_player(id, "hangar")
		for id in _vehicle_owners.keys():
			var craft: Node3D = _world.vehicle_manager.vehicles.get(_vehicle_owners[id])
			if craft == null or craft.health <= 0.0:
				_release_remote_vehicle(id)
				_vehicle_status.rpc_id(id, "")
				_spawn_remote_player(id, "hangar")
	if _mode != "HOST" or _world == null or multiplayer.get_peers().is_empty():
		return
	_snapshot_wait -= delta
	if _snapshot_wait <= 0.0:
		_snapshot_wait = SNAPSHOT_INTERVAL
		_receive_snapshot.rpc(build_world_sync_snapshot(_world))


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	if _mode == "CLIENT" and _world != null:
		apply_world_sync_snapshot(_world, snapshot)


func build_world_sync_snapshot(world_root: Node) -> Dictionary:
	var summary: Dictionary = world_root.match_manager.get_match_summary()
	var vehicles := {}
	for id in world_root.vehicle_manager.vehicles:
		var vehicle: CharacterBody3D = world_root.vehicle_manager.vehicles[id]
		var state := _unit_state(vehicle, vehicle.get_planet_position())
		var weapons: Node = vehicle.weapon_system
		state.weapons = {"heat": weapons.heat, "overheated": weapons.overheated, "missiles": weapons.missiles, "reload_left": weapons._reload_left}
		vehicles[id] = state
	var units := {}
	for unit in world_root.ai_manager.troopers + world_root.ai_manager.fighters:
		units[unit.callsign] = _unit_state(unit, unit.global_position + world_root.floating_origin.current_origin)
	return {
		"world_seed": world_root.world_config.world_seed, "match_state": summary.match_state,
		"winner_faction": summary.winner_faction, "match_time": summary.match_time,
		"target_score": summary.target_score, "scores": summary.scores, "killfeed": summary.killfeed,
		"team_resources": summary.team_resources,
		"engineering": world_root.engineering_build_manager.snapshot(),
		"rally_orders": world_root.ai_manager.rally_orders.duplicate(),
		"commander_cooldowns": world_root.commander_system.cooldowns.duplicate(true),
		"orbital_warnings": world_root.commander_system.warnings_snapshot(),
		"objectives": summary.objectives, "destruction_states": world_root.destruction.get_states(),
		"vehicle_transforms": vehicles, "ai_units": units, "roster_counts": world_root.ai_manager.get_roster_counts(),
		"peer_factions": peer_factions.duplicate(), "ai_roster": world_root.ai_manager.roster.duplicate(true),
	}


func _unit_state(unit: CharacterBody3D, planet_position: Vector3) -> Dictionary:
	return {
		"transform": Transform3D(unit.global_basis, planet_position),
		"velocity": unit.velocity, "health": unit.health, "shield": unit.shield,
	}


func apply_world_sync_snapshot(world_root: Node, snapshot: Dictionary) -> bool:
	if not _valid_snapshot(world_root, snapshot):
		return false
	var seed: int = snapshot.world_seed
	if world_root.world_config.world_seed != seed:
		world_root.regenerate_world(seed)
	world_seed = seed
	var match_manager: Node = world_root.match_manager
	match_manager.match_state = snapshot.match_state
	match_manager.winner_faction = snapshot.winner_faction
	match_manager.match_time = snapshot.match_time
	match_manager.target_score = snapshot.target_score
	match_manager.scores = snapshot.scores.duplicate()
	match_manager.team_resources = snapshot.team_resources.duplicate()
	world_root.engineering_build_manager.apply_snapshot(snapshot.engineering)
	world_root.ai_manager.apply_rally_orders(snapshot.rally_orders)
	world_root.commander_system.cooldowns = snapshot.commander_cooldowns.duplicate(true)
	if _mode == "CLIENT":
		world_root.commander_system.apply_warnings(snapshot.orbital_warnings)
	match_manager.killfeed.assign(snapshot.killfeed)
	for objective in match_manager.objectives:
		for data in snapshot.objectives:
			if data.id == objective.objective_id:
				objective.apply_capture_status(data)
	for id in snapshot.destruction_states:
		if world_root.destruction.get_state(id) != snapshot.destruction_states[id]:
			world_root.destruction.set_section_state(id, snapshot.destruction_states[id])
	for id in world_root.vehicle_manager.vehicles:
		var vehicle: CharacterBody3D = world_root.vehicle_manager.vehicles[id]
		var state: Dictionary = snapshot.vehicle_transforms[id]
		if _mode != "CLIENT" or vehicle != world_root.get_active_vehicle():
			vehicle.global_basis = state.transform.basis
			vehicle.set_planet_position(state.transform.origin)
			vehicle.velocity = state.velocity
		vehicle.health = state.health
		vehicle.shield = state.shield
		var weapons: Node = vehicle.weapon_system
		var inventory: Dictionary = state.weapons
		weapons.heat = inventory.heat
		weapons.overheated = inventory.overheated
		weapons.missiles = inventory.missiles
		weapons._reload_left = inventory.reload_left
	for unit in world_root.ai_manager.troopers + world_root.ai_manager.fighters:
		var state: Dictionary = snapshot.ai_units[unit.callsign]
		var posed: Transform3D = state.transform
		posed.origin -= world_root.floating_origin.current_origin
		unit.global_transform = posed
		unit.velocity = state.velocity
		unit.health = state.health
		unit.shield = state.shield
		unit.visible = state.health > 0.0
		unit.collision_layer = 0 if not unit.visible else (8 if unit in world_root.ai_manager.troopers else 8 | 4)
		unit.reset_physics_interpolation()
	for faction in ["helion", "cinder"]:
		for index in TEAM_SIZE:
			var entry: Dictionary = world_root.ai_manager.roster[faction][index]
			entry.kills = snapshot.ai_roster[faction][index].kills
			entry.deaths = snapshot.ai_roster[faction][index].deaths
	if _mode != "HOST":
		peer_factions = snapshot.peer_factions.duplicate()
	if _mode == "CLIENT":
		var local_team: String = peer_factions.get(multiplayer.get_unique_id(), "")
		if not local_team.is_empty():
			match_manager.switch_faction(local_team)
	return true


func _valid_snapshot(world_root: Node, data: Dictionary) -> bool:
	if not data.get("world_seed") is int or data.get("match_state") not in ["ACTIVE", "VICTORY"]:
		return false
	if data.get("winner_faction") not in ["", "helion", "cinder"] or not _valid_number(data.get("match_time")):
		return false
	if not _valid_number(data.get("target_score")) or data.target_score <= 0.0:
		return false
	if not data.get("scores") is Dictionary or data.scores.size() != 2:
		return false
	if not data.get("killfeed") is Array or data.killfeed.size() > 6:
		return false
	for event in data.killfeed:
		if not event is String:
			return false
	if not data.get("objectives") is Array or data.objectives.size() != world_root.match_manager.objectives.size():
		return false
	var ids := {}
	for state in data.objectives:
		if not state is Dictionary or not state.get("id") is String or ids.has(state.id):
			return false
		if state.get("owner_faction") not in ["neutral", "helion", "cinder"] or not state.get("contested") is bool:
			return false
		var progress: Variant = state.get("capture_progress")
		if not (progress is float or progress is int) or not is_finite(progress) or absf(progress) > 1.0:
			return false
		ids[state.id] = true
	for objective in world_root.match_manager.objectives:
		if not ids.has(objective.objective_id):
			return false
	if not data.get("destruction_states") is Dictionary or data.destruction_states.size() != world_root.destruction.get_section_ids().size():
		return false
	for id in world_root.destruction.get_section_ids():
		var state: Variant = data.destruction_states.get(id)
		if not state is int or state < 0 or state > 3:
			return false
	if not data.get("vehicle_transforms") is Dictionary or not data.get("ai_units") is Dictionary:
		return false
	for id in world_root.vehicle_manager.vehicles:
		var vehicle_state: Variant = data.vehicle_transforms.get(id)
		if not _valid_unit(vehicle_state) or not vehicle_state.get("weapons") is Dictionary:
			return false
		var weapons: Dictionary = vehicle_state.weapons
		if not _valid_number(weapons.get("heat")) or not _valid_number(weapons.get("reload_left")) or not weapons.get("missiles") is int or not weapons.get("overheated") is bool:
			return false
	for unit in world_root.ai_manager.troopers + world_root.ai_manager.fighters:
		if not _valid_unit(data.ai_units.get(unit.callsign)):
			return false
	if not data.get("roster_counts") is Dictionary or not data.get("ai_roster") is Dictionary or not data.get("peer_factions") is Dictionary:
		return false
	var peers := {"helion": 0, "cinder": 0}
	for id in data.peer_factions:
		var faction: Variant = data.peer_factions[id]
		if not id is int or id <= 0 or faction not in ["helion", "cinder"]:
			return false
		peers[faction] += 1
	if not _valid_phase4(world_root, data):
		return false
	for faction in peers:
		var entries: Variant = data.ai_roster.get(faction)
		if peers[faction] > TEAM_SIZE or data.roster_counts.get(faction) != TEAM_SIZE or not _valid_number(data.scores.get(faction)):
			return false
		if not entries is Array or entries.size() != TEAM_SIZE:
			return false
		for entry in entries:
			if not entry is Dictionary or not entry.get("kills") is int or not entry.get("deaths") is int:
				return false
	return true


func _valid_unit(state: Variant) -> bool:
	if not state is Dictionary or not state.get("transform") is Transform3D or not state.get("velocity") is Vector3:
		return false
	return state.transform.is_finite() and state.velocity.is_finite() and _valid_number(state.get("health")) and _valid_number(state.get("shield"))


func _valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value) and value >= 0.0


func _valid_phase4(context: Node, data: Dictionary) -> bool:
	for key in ["team_resources", "engineering", "rally_orders", "commander_cooldowns"]:
		if not data.get(key) is Dictionary:
			return false
	if not data.get("orbital_warnings") is Array or data.engineering.size() > 96:
		return false
	for team in ["helion", "cinder"]:
		if not _valid_number(data.team_resources.get(team)) or not data.commander_cooldowns.get(team) is Dictionary:
			return false
		for ability in data.commander_cooldowns[team]:
			if ability not in ["strike", "supply", "rally"] or not _valid_number(data.commander_cooldowns[team][ability]):
				return false
	for team in data.rally_orders:
		if team not in ["helion", "cinder"] or not data.rally_orders[team] is String or context.ai_manager.objective_by_id(data.rally_orders[team]) == null:
			return false
	for id in data.engineering:
		var state: Variant = data.engineering[id]
		if not id is String or id.validate_node_name() != id or not state is Dictionary:
			return false
		if state.get("kind") not in ["turret", "shield", "supply"] or state.get("faction") not in ["helion", "cinder"]:
			return false
		if not state.get("position") is Vector3 or not state.position.is_finite() or not state.get("basis") is Basis or not state.basis.is_finite():
			return false
		if state.kind == "supply":
			if not state.get("launch") is Vector3 or not state.launch.is_finite() or not _valid_number(state.get("drop")):
				return false
		elif not _valid_number(state.get("health")):
			return false
		if state.kind == "turret":
			for angle in ["yaw", "pitch"]:
				if not (state.get(angle) is float or state.get(angle) is int) or not is_finite(state[angle]):
					return false
	for warning in data.orbital_warnings:
		if not warning is Dictionary or warning.get("faction") not in ["helion", "cinder"] or not _valid_number(warning.get("remaining")):
			return false
		if not warning.get("point") is Vector3 or not warning.point.is_finite() or not warning.get("frame") is Basis or not warning.frame.is_finite():
			return false
	return true


func reset_live_state() -> void:
	for id in _vehicle_owners.keys():
		_release_remote_vehicle(id)
	_fire_times.clear()
	_engineering_times.clear()
	_respawns.clear()
	_manual_spawn_times.clear()
	if replication != null:
		replication.clear()


func _connected_client() -> bool:
	return _mode == "CLIENT" and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _avatar_of_sender() -> Node3D:
	var id := multiplayer.get_remote_sender_id()
	if _mode != "HOST" or not peer_factions.has(id) or not _world.can_simulate_combat():
		return null
	var avatar: Node3D = replication.avatars.get(id)
	return avatar if avatar != null and avatar.health > 0.0 else null


func request_deploy_buildable(kind: String, planet_pos: Vector3) -> bool:
	if not _connected_client():
		return false
	_deploy_buildable.rpc_id(1, kind, planet_pos)
	return true


func request_commander_ability(ability: String, target_obj_id: String) -> bool:
	if not _connected_client():
		return false
	_commander_ability.rpc_id(1, ability, target_obj_id)
	return true


func request_infantry_fire(origin: Vector3, dir: Vector3) -> bool:
	if not _connected_client() or _client_fire_wait > 0.0:
		return false
	submit_player_pose.rpc_id(1, replication.local_sample())
	_client_fire_wait = Combat.FIRE_INTERVAL
	_infantry_fire.rpc_id(1, origin, dir)
	return true


func request_vehicle_board(vehicle_id: String) -> bool:
	if not _connected_client():
		return false
	submit_player_pose.rpc_id(1, replication.local_sample())
	_vehicle_board.rpc_id(1, vehicle_id)
	return true


func request_reload() -> void:
	if _connected_client():
		_reload.rpc_id(1)


func request_player_deploy(choice: String) -> bool:
	if not _connected_client():
		return false
	_player_deploy.rpc_id(1, choice)
	return true


func poll_local_actions(delta: float) -> void:
	if not _connected_client():
		return
	var player: Node3D = _world.explorer
	var combat: Node = _world.player_combat
	var craft: Node3D = _world.get_active_vehicle()
	if craft != null:
		craft._update_cameras(delta)
		if craft.controls_enabled and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
			_vehicle_fire.rpc_id(1, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		return
	if player.combat_input_allowed() and combat.health > 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var camera: Camera3D = player.get_camera()
		var point: Vector3 = _world.floating_origin.render_to_planet(camera.global_position)
		if combat.selected_tool == 0 and combat.ammo > 0:
			request_infantry_fire(point, -camera.global_basis.z)
		elif combat.selected_tool == 1 and _client_fire_wait <= 0.0:
			_client_fire_wait = 0.12
			_engineering_beam.rpc_id(1, point, -camera.global_basis.z)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_player_pose(sample: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _mode != "HOST" or not peer_factions.has(id):
		return
	var vehicle_id: String = _vehicle_owners.get(id, "")
	if sample.get("vehicle") != vehicle_id or not replication.accept_pose(id, peer_factions[id], sample, vehicle_id):
		return
	if not vehicle_id.is_empty():
		var vehicle: Node3D = _world.vehicle_manager.vehicles.get(vehicle_id)
		if vehicle != null and vehicle.health > 0.0:
			var state: Dictionary = replication.player_states[id]
			vehicle.global_basis = state.pose.basis
			vehicle.set_planet_position(state.pose.origin)
			vehicle.velocity = state.velocity


func publish_player_states() -> void:
	if _mode == "HOST" and not multiplayer.get_peers().is_empty():
		_receive_players.rpc(peer_factions, replication.states_for_network())


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_players(teams: Dictionary, states: Dictionary) -> void:
	if _mode == "CLIENT" and not peer_factions.is_empty():
		replication.apply_players(teams, states)


@rpc("any_peer", "call_remote", "reliable")
func _deploy_buildable(kind: String, planet_pos: Vector3) -> void:
	var avatar := _avatar_of_sender()
	if avatar == null or not avatar.vehicle_id.is_empty() or not planet_pos.is_finite():
		return
	var position: Vector3 = avatar.server_pose.origin
	if position.distance_to(planet_pos) > 8.0 or _world.engineering_build_manager.ground_at(position, 4.5).is_empty():
		return
	if _world.engineering_build_manager.deploy(kind, avatar.faction, planet_pos) != null:
		_snapshot_wait = 0.0


@rpc("any_peer", "call_remote", "reliable")
func _commander_ability(ability: String, target_obj_id: String) -> void:
	var avatar := _avatar_of_sender()
	if avatar != null and _world.commander_system.execute(avatar.faction, ability, target_obj_id, avatar.server_pose.origin):
		_snapshot_wait = 0.0


@rpc("any_peer", "call_remote", "reliable")
func _infantry_fire(origin: Vector3, dir: Vector3) -> void:
	var avatar := _avatar_of_sender()
	if avatar == null or avatar.ammo <= 0 or not _valid_aim(avatar, origin, dir, 0):
		return
	var id: int = avatar.peer_id
	var now := Time.get_ticks_msec()
	if now - int(_fire_times.get(id, -1000)) < int(Combat.FIRE_INTERVAL * 1000) - 8:
		return
	_fire_times[id] = now
	avatar.ammo -= 1
	var start: Vector3 = _world.floating_origin.planet_to_render(origin)
	var end := start + dir.normalized() * Combat.RIFLE_RANGE
	var hit := Combat.cast_ray(avatar, start, end)
	var point: Vector3 = hit.get("position", end)
	var blocked: Dictionary = _world.engineering_build_manager.intercept_shot(start, point, avatar.faction, 24.0)
	if blocked.is_empty():
		var target: Node3D = hit.get("collider")
		if target != null and (target == _world.explorer or target.has_method("take_faction_damage") or target is Turret.Vehicle):
			if target.has_method("set_shield_hp"):
				target.take_faction_damage(24.0, avatar.faction)
			else:
				Turret.damage_target(_world, target, 24.0, avatar.faction, start if target == _world.explorer else point, true)
	else:
		point = blocked.position
	publish_tracer(start + dir * 0.5, point, Combat.faction_color(avatar.faction), 0.045)
	_infantry_feedback.rpc_id(id)


func _valid_aim(avatar: Node3D, origin: Vector3, dir: Vector3, tool: int) -> bool:
	var state: Dictionary = replication.player_states[avatar.peer_id]
	return avatar.vehicle_id.is_empty() and state.tool == tool and origin.is_finite() and dir.is_finite() and origin.distance_to(state.pose.origin + state.pose.basis.y * 0.7) <= 3.0 and absf(dir.length_squared() - 1.0) < 0.04 and dir.dot(state.aim) > 0.8


@rpc("authority", "call_remote", "unreliable")
func _infantry_feedback() -> void:
	if _mode == "CLIENT":
		_world.player_combat.shots_fired += 1
		_world.player_combat.viewmodel.position.z += 0.052


@rpc("any_peer", "call_remote", "reliable")
func _engineering_beam(origin: Vector3, dir: Vector3) -> void:
	var avatar := _avatar_of_sender()
	if avatar == null or not _valid_aim(avatar, origin, dir, 1):
		return
	var id: int = avatar.peer_id
	var now := Time.get_ticks_msec()
	if now - int(_engineering_times.get(id, -1000)) < 105:
		return
	_engineering_times[id] = now
	var start: Vector3 = _world.floating_origin.planet_to_render(origin)
	var end := start + dir.normalized() * Combat.BEAM_RANGE
	var hit := Combat.cast_ray(avatar, start, end)
	var target: Object = hit.get("collider")
	var repaired := 0.0
	if target is Turret.Vehicle and target.faction == avatar.faction and target.health > 0.0:
		var before: float = target.health + target.shield
		target.health = minf(target.max_health, target.health + 3.6)
		target.shield = minf(target.max_shield, target.shield + 2.88)
		repaired = target.health + target.shield - before
	elif target != null and target.has_method("repair") and target.get("faction") == avatar.faction:
		repaired = target.repair(4.32)
	elif target != null and target.has_method("support_capture"):
		target.support_capture(avatar.faction, 0.132)
		_world.match_manager.credit_engineering(avatar.faction, "extraction", 0.48, 1.0, 25.0)
	if repaired > 0.0:
		_world.match_manager.credit_engineering(avatar.faction, "repair", repaired, 10.0, 10.0)
	publish_tracer(start + dir * 0.5, hit.get("position", end), Color("#74ffbc"), 0.045)


@rpc("any_peer", "call_remote", "reliable")
func _reload() -> void:
	var avatar := _avatar_of_sender()
	if avatar != null and avatar.vehicle_id.is_empty():
		avatar.ammo = Combat.MAGAZINE_SIZE


func replenish_peer(id: int) -> void:
	if _mode == "HOST":
		_replenish.rpc_id(id)


@rpc("authority", "call_remote", "reliable")
func _replenish() -> void:
	if _mode == "CLIENT":
		_world.player_combat.jetpack_fuel = _world.player_combat.max_jetpack


@rpc("any_peer", "call_remote", "reliable")
func _vehicle_board(vehicle_id: String) -> void:
	var avatar := _avatar_of_sender()
	if avatar == null:
		return
	var id: int = avatar.peer_id
	if vehicle_id.is_empty():
		var owned: Node3D = _world.vehicle_manager.vehicles.get(_vehicle_owners.get(id, ""))
		if owned != null and owned.velocity.length() <= 4.0:
			_release_remote_vehicle(id)
			_vehicle_status.rpc_id(id, "")
		return
	var vehicle: Node3D = _world.vehicle_manager.vehicles.get(vehicle_id)
	if vehicle == null or not avatar.vehicle_id.is_empty() or vehicle.is_piloted or vehicle.health <= 0.0 or vehicle.faction != avatar.faction:
		return
	if vehicle.get_planet_position().distance_to(avatar.server_pose.origin) > Fleet.BOARD_RANGE or vehicle.get_speed() > 1.0:
		return
	_vehicle_owners[id] = vehicle_id
	avatar.vehicle_id = vehicle_id
	avatar.update_visibility()
	var state: Dictionary = replication.player_states[id]
	state.vehicle = vehicle_id
	state.pose = Transform3D(vehicle.global_basis, vehicle.get_planet_position())
	state.received = Time.get_ticks_msec()
	_world.vehicle_manager._surface_anchors.erase(vehicle_id)
	vehicle.is_piloted = true
	vehicle.controls_enabled = false
	vehicle.set_physics_process(false)
	_vehicle_status.rpc_id(id, vehicle_id)


func _release_remote_vehicle(id: int) -> void:
	var vehicle: Node3D = _world.vehicle_manager.vehicles.get(_vehicle_owners.get(id, ""))
	_vehicle_owners.erase(id)
	if vehicle == null:
		return
	vehicle.release_pilot()
	vehicle.set_physics_process(true)
	var avatar: Node3D = replication.avatars.get(id)
	if avatar != null:
		avatar.vehicle_id = ""
		avatar.update_visibility()
		replication.player_states[id].vehicle = ""


@rpc("authority", "call_remote", "reliable")
func _vehicle_status(vehicle_id: String) -> void:
	if _mode != "CLIENT":
		return
	if vehicle_id.is_empty():
		var vehicle: Node3D = _world.get_active_vehicle()
		if vehicle != null and not _world.vehicle_manager.exit_active_vehicle():
			_world.vehicle_manager.release_for_world_travel()
		if vehicle != null:
			vehicle.set_physics_process(false)
	else:
		var vehicle: Node3D = _world.vehicle_manager.vehicles.get(vehicle_id)
		if vehicle != null:
			vehicle.weapon_system.set_physics_process(false)
			_world.vehicle_manager.quick_board_vehicle(vehicle_id)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _vehicle_fire(primary: bool, secondary: bool) -> void:
	var avatar := _avatar_of_sender()
	if avatar == null:
		return
	var vehicle: Node3D = _world.vehicle_manager.vehicles.get(_vehicle_owners.get(avatar.peer_id, ""))
	if vehicle != null:
		if primary:
			vehicle.weapon_system.fire_primary()
		if secondary:
			vehicle.weapon_system.fire_secondary()


func schedule_peer_respawn(id: int) -> void:
	if _mode == "HOST":
		_respawns[id] = 2.0


@rpc("any_peer", "call_remote", "reliable")
func _player_deploy(choice: String) -> void:
	var avatar := _avatar_of_sender()
	if avatar == null or not avatar.vehicle_id.is_empty() or choice not in ["hangar", "alpha", "bravo", "charlie"]:
		return
	var now := Time.get_ticks_msec()
	if now - int(_manual_spawn_times.get(avatar.peer_id, -5000)) < 3000:
		return
	_manual_spawn_times[avatar.peer_id] = now
	_spawn_remote_player(avatar.peer_id, choice)


func reset_remote_spawns() -> void:
	if _mode != "HOST" or multiplayer.get_peers().is_empty():
		return
	_receive_snapshot.rpc(build_world_sync_snapshot(_world))
	for id in multiplayer.get_peers():
		if peer_factions.has(id):
			_initialize_remote_player(id)


func _initialize_remote_player(id: int) -> void:
	var faction: String = peer_factions[id]
	var placement: Dictionary = _world.infantry_spawn("hangar", faction)
	var pose := Transform3D(Basis.looking_at(placement.facing, placement.up), placement.position)
	replication.accept_pose(id, faction, {"pose": pose, "aim": placement.facing, "tool": 0, "velocity": Vector3.ZERO}, "")
	_spawn_remote_player(id, "hangar")


func _spawn_remote_player(id: int, choice: String) -> void:
	var avatar: Node3D = replication.avatars.get(id)
	if avatar == null or choice not in ["hangar", "alpha", "bravo", "charlie"]:
		return
	var placement: Dictionary = _world.infantry_spawn(choice, avatar.faction)
	var point: Vector3 = placement.position
	var facing: Vector3 = placement.facing
	var up: Vector3 = placement.up
	var pose := Transform3D(Basis.looking_at(facing, up), point)
	var state: Dictionary = replication.player_states[id]
	state.pose = pose
	state.aim = facing
	state.received = Time.get_ticks_msec()
	avatar.server_pose = pose
	avatar.target_pose = pose
	avatar.health = 100.0
	avatar.shield = 75.0
	avatar.ammo = Combat.MAGAZINE_SIZE
	avatar.update_visibility()
	_player_spawned.rpc_id(id, choice, point, facing)


@rpc("authority", "call_remote", "reliable")
func _player_spawned(choice: String, point: Vector3, facing: Vector3) -> void:
	if _mode == "CLIENT":
		_world.place_infantry(choice, point, facing)
		_world.player_combat.reset_for_spawn()
		_world.combat_hud.close_panels()


func publish_tracer(start: Vector3, end: Vector3, color: Color, width: float) -> void:
	Combat.spawn_tracer(_world.combat_effects, start, end, color, width, 0.13)
	relay_tracer(start, end, color, width)


func relay_tracer(start: Vector3, end: Vector3, color: Color, width: float) -> void:
	if _mode == "HOST" and not multiplayer.get_peers().is_empty():
		var origin: Vector3 = _world.floating_origin.current_origin
		_receive_tracer.rpc(start + origin, end + origin, color, width)


@rpc("authority", "call_remote", "unreliable")
func _receive_tracer(start: Vector3, end: Vector3, color: Color, width: float) -> void:
	if _mode == "CLIENT":
		var origin: Vector3 = _world.floating_origin.current_origin
		Combat.spawn_tracer(_world.combat_effects, start - origin, end - origin, color, width, 0.13)


func relay_orbital(stage: String, faction: String, point: Vector3, frame: Basis) -> void:
	if _mode == "HOST" and not multiplayer.get_peers().is_empty():
		_receive_orbital.rpc(stage, faction, point, frame)


@rpc("authority", "call_remote", "reliable")
func _receive_orbital(stage: String, faction: String, point: Vector3, frame: Basis) -> void:
	if _mode == "CLIENT":
		if stage == "warning":
			_world.commander_system.show_warning(faction, point, frame)
		else:
			_world.commander_system.show_impact(faction, point, frame)


func get_remote_vehicle_ids() -> Array:
	return _vehicle_owners.values()


func relay_vehicle_projectile(shot: Node3D) -> void:
	if _mode == "HOST" and not multiplayer.get_peers().is_empty():
		var planet_point: Vector3 = _world.floating_origin.render_to_planet(shot.global_position)
		_receive_vehicle_projectile.rpc(shot.shooter.vehicle_id, planet_point, shot.direction * shot.speed, shot.splash_radius > 0.0, shot.energy_color)


@rpc("authority", "call_remote", "unreliable")
func _receive_vehicle_projectile(vehicle_id: String, point: Vector3, velocity: Vector3, missile: bool, color: Color) -> void:
	if _mode != "CLIENT":
		return
	var craft: Node3D = _world.vehicle_manager.vehicles.get(vehicle_id)
	if craft == null:
		return
	replication.show_projectile(craft, point, velocity, missile, color)
	if craft == _world.get_active_vehicle():
		var weapons: Node = craft.weapon_system
		weapons.shots_fired += 1
		_world.game_feel.event(&"missile" if missile else &"cannon", point, 0.42 if missile else 0.24)
