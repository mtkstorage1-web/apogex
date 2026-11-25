extends SceneTree

const WorldScene = preload("res://scenes/world/WorldRoot.tscn")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Network = preload("res://scripts/multiplayer/NetworkAuthorityManager.gd")
const Rig := &"mining_derrick_rig"

var _world: WorldRoot
var _failures := 0
var _raw_models: Array[PackedScene] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.has_environment("APOGEX_TEST_RAW_COMBAT_GLB"):
		_cache_combat_models()
	_world = WorldScene.instantiate() as WorldRoot
	_world.name = "HostWorld"
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/HostWorld"))
	root.add_child(_world)
	await _steps(7)
	if _world.player_combat == null or _world.ai_manager == null or _world.combat_hud == null:
		_check(false, "WorldRoot initialized its gameplay systems")
		quit(1)
		return
	await _check_objectives()
	await _check_ai()
	await _check_infantry()
	await _check_engineering()
	await _check_match_and_hud()
	await _check_network()
	_world.queue_free()
	await process_frame
	await process_frame
	print("Gameplay loop PASS" if _failures == 0 else "Gameplay loop FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _steps(count: int) -> void:
	for step in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", message])


func _check_objectives() -> void:
	var objectives := _world.capture_objectives
	_check(objectives.size() == 3, "all three capture objectives exist")
	var names := ["alpha", "bravo", "charlie"]
	var pad_names := ["FoundationRing", "ExcavationPad", "RefineryPad"]
	for i in objectives.size():
		var objective := objectives[i]
		_world.deploy_player(names[i])
		await _steps(4)
		var up := objective.global_basis.y
		var floor_hit := Combat.cast_ray(objective, objective.global_position + up * 0.3, objective.global_position - up * 0.4, 1)
		var floor: Vector3 = floor_hit.get("position", Vector3.INF)
		var depth := (objective.global_position - floor).dot(up)
		var footing: Node = floor_hit.get("collider")
		_check(objective.objective_id == names[i] and footing != null and footing.name == pad_names[i]
			and depth >= -0.015 and depth <= 0.08, "%s sits flush on its facility slab (%.3f m)" % [names[i], depth])
		_check(_world.floating_origin.render_to_planet(objective.global_position).distance_to(objective.planet_position) < 0.005,
			"%s retains its planet-space position through rebasing" % names[i])
		if OS.has_environment("APOGEX_TEST_RAW_COMBAT_GLB"):
			_check(objective.model_source == "glb", "%s loads the Blender capture beacon" % names[i])
	_world.set_physics_process(false)
	var objective := objectives[0]
	_world.match_manager.reset_match()
	objective.update_capture(2.0, 1, 0, "helion")
	_check(is_equal_approx(objective.capture_progress, 0.25) and objective.owner_faction == "neutral", "neutral capture progresses smoothly")
	objective.update_capture(1.0, 2, 1)
	_check(objective.contested and is_equal_approx(objective.capture_progress, 0.25), "opposing presence stalls capture")
	objective.support_capture("helion", 5.0)
	objective.update_capture(2.0, 1, 0, "helion")
	_check(is_equal_approx(objective.capture_progress, 0.625), "engineering increases capture rate by 50 percent")
	objective.update_capture(4.0, 1, 0, "helion")
	var score := float(_world.match_manager.scores.helion)
	_world.match_manager.tick(3.0)
	_check(objective.owner_faction == "helion" and score >= 40.0 and _world.match_manager.scores.helion > score
		and _world.match_manager.player_stats.captures == 1, "Helion capture awards capture and ongoing extraction points")
	objective.update_capture(8.0, 0, 1)
	_check(objective.owner_faction == "neutral", "Cinder advance neutralizes Helion at the midpoint")
	objective.update_capture(8.0, 0, 1)
	_check(objective.owner_faction == "cinder" and _world.match_manager.scores.cinder >= 40.0, "Cinder takes control and scores")
	_world.match_manager.reset_match()
	_world.set_physics_process(true)
	await _steps(2)


func _check_ai() -> void:
	var ai := _world.ai_manager
	ai.reset_pool()
	await _steps(2)
	_check(ai.get_roster_counts() == {"helion": 16, "cinder": 16} and ai.get_scoreboard().helion.size() == 16,
		"scoreboard holds 16 Helion and 16 Cinder entries")
	_check(ai.troopers.size() == 12 and ai.fighters.size() == 4, "active pool holds 12 troopers and four fighters")
	for objective in _world.capture_objectives:
		var slots := {"helion": 0, "cinder": 0}
		for bot in ai.troopers:
			if bot.objective != objective:
				continue
			slots[bot.faction] += 1
			var up := objective.global_basis.y
			var floor := Combat.cast_ray(bot, bot.global_position + up * 0.3, bot.global_position - up * 0.8, 1)
			var ground: Vector3 = floor.get("position", Vector3.INF)
			_check(not floor.is_empty() and absf((bot.global_position - ground).dot(up)) < 0.13 and bot.global_basis.y.dot(up) > 0.99,
				"%s has grounded boots on %s" % [bot.callsign, objective.objective_id])
			if OS.has_environment("APOGEX_TEST_RAW_COMBAT_GLB"):
				_check(bot.model_source == "glb", "%s loads the Blender trooper" % bot.callsign)
		_check(slots == {"helion": 2, "cinder": 2}, "%s has a two-trooper squad from each faction" % objective.objective_id)
	var fighter := ai.fighters[0]
	var start := fighter.global_position
	var rival := ai.fighters[2]
	var up := (start + ai.current_origin).normalized()
	var forward := -fighter.global_basis.z.slide(up).normalized()
	fighter.global_basis = Basis.looking_at(forward, up)
	rival.global_position = start + forward * 250.0
	rival.global_basis = Basis.looking_at(-forward, up)
	await _steps(77)
	_check(ai.troopers.any(func(bot: Node) -> bool: return bot.shield < 40.0), "troopers detect enemies and exchange damage")
	_check(fighter.global_position.distance_to(start) > 15.0 and (fighter.shield < 100.0 or rival.shield < 100.0),
		"fighters fly and exchange dogfight damage")
	var victim := ai.troopers[6]
	var killer_faction: String = "helion"
	_check(victim.take_damage(500.0, killer_faction) and victim.health == 0.0 and not victim.visible
		and victim.state == "RESPAWNING" and victim.collision_layer == 0, "trooper elimination updates state and collision")
	victim.respawn_remaining = 0.02
	fighter.take_damage(600.0, "cinder")
	fighter.respawn_remaining = 0.02
	await _steps(5)
	_check(victim.visible and victim.health == 100.0 and victim.collision_layer == 8, "trooper respawns from its timer")
	var ship: Node3D = _world.mothership_manager.get_ship(fighter.faction)
	var launch_position: Vector3 = ship.planet_to_local(fighter.global_position + ai.current_origin)
	_check(fighter.visible and fighter.health == 180.0 and fighter.state == "LAUNCH"
		and launch_position.distance_to(Vector3(-6, 5, 415)) < 5.0, "fighter respawns inside its faction hangar")


func _check_infantry() -> void:
	var combat := _world.player_combat
	var player := _world.explorer
	var ai := _world.ai_manager
	var enemy := ai.troopers[6]
	var position := Vector3(0, 19500, 0)
	_world.floating_origin.check_and_shift(position)
	player.set_move_mode(ExplorerController.MoveMode.FLY)
	player.teleport_to(position, Vector3.FORWARD)
	player.set_physics_process(false)
	enemy.respawn()
	enemy.set_physics_process(false)
	enemy.global_basis = Basis.IDENTITY
	enemy.global_position = player.global_position + Vector3(0, -0.2, -12)
	combat.reset_for_spawn()
	combat.select_tool(0)
	await _steps(3)
	var shield: float = enemy.shield
	_check(combat.fire_weapon() and not combat.fire_weapon() and combat.ammo == 29 and enemy.shield < shield,
		"rifle sweeps into an enemy trooper, consumes ammo and respects cadence")
	_check(combat.hitmarker_time > 0.0 and _world.combat_effects.get_child_count() >= 2, "rifle records a hit and spawns tracer and flash")
	combat.reload()
	_check(combat.ammo == 30, "reload refills the magazine")
	if OS.has_environment("APOGEX_TEST_RAW_COMBAT_GLB"):
		_check(combat.model_source == "glb", "Helion rifle loads the Blender model")

	var enemy_vehicle := _world.vehicle_manager.vehicles["cinder_fighter_hangar"]
	enemy_vehicle.set_planet_position(position + Vector3(0, 0, -30))
	enemy_vehicle.global_basis = Basis.IDENTITY
	enemy.respawn()
	enemy.set_physics_process(true)
	await _steps(9)
	var vehicle_shield := enemy_vehicle.shield
	_check(combat.fire_weapon() and enemy_vehicle.shield < vehicle_shield, "infantry rifle damages an enemy VehicleBase")

	var enemy_fighter := ai.fighters[2]
	enemy_fighter.respawn(false)
	enemy_fighter.set_physics_process(false)
	enemy_fighter.global_position = Vector3(0, 0, -70)
	enemy_fighter.global_basis = Basis.IDENTITY
	await _steps(8)
	var fighter_shield: float = enemy_fighter.shield
	enemy_vehicle.set_planet_position(position + Vector3(40, 0, -30))
	await _steps(2)
	_check(combat.fire_weapon() and enemy_fighter.shield < fighter_shield, "infantry rifle damages an AI fighter")
	var craft := _world.vehicle_manager.vehicles["helion_fighter_hangar"]
	craft.set_planet_position(position)
	craft.global_basis = Basis.IDENTITY
	fighter_shield = enemy_fighter.shield
	_check(craft.weapon_system.fire_primary(), "existing spacecraft cannon fires at an AI fighter")
	await _steps(15)
	_check(enemy_fighter.shield < fighter_shield, "existing swept spacecraft projectile damages an AI fighter")
	enemy_fighter.set_physics_process(true)
	enemy_fighter.respawn(false)

	player.set_move_mode(ExplorerController.MoveMode.WALK)
	player.grounded = false
	player.velocity = Vector3.ZERO
	var fuel := combat.jetpack_fuel
	var impulse := combat.apply_jetpack(0.2)
	_check(player.is_in_eva() and impulse > 0.0 and player.velocity.dot(player.global_basis.y) > 0.0 and combat.jetpack_fuel < fuel,
		"airborne EVA thrust uses local up and burns fuel")
	var after_burn := combat.jetpack_fuel
	combat.apply_jetpack(0.2, false)
	_check(combat.jetpack_fuel > after_burn, "jetpack regenerates on release")
	combat.apply_jetpack(0.2)
	player.grounded = true
	after_burn = combat.jetpack_fuel
	_check(combat.apply_jetpack(0.2) == 0.0 and combat.jetpack_fuel > after_burn, "grounded jetpack regenerates with no thrust")
	player.set_physics_process(true)
	_world.deploy_player("alpha")
	await _steps(5)
	_check(_world.explorer.get_planet_position().distance_to(_world.capture_objectives[0].planet_position) < 10.0,
		"Alpha deploy places infantry beside the beacon")
	Input.parse_input_event(_key(KEY_SPACE))
	player.set_mouse_captured(true)
	await _steps(18)
	var rising := player.height_above_ground > 2.0 and combat.jetpack_fuel < combat.max_jetpack
	Input.parse_input_event(_key(KEY_SPACE, false))
	player.set_mouse_captured(false)
	_check(rising, "holding Space jumps and boosts in surface Walk mode")

	combat.reset_for_spawn()
	_check(combat.take_damage(90.0, "cinder") and combat.health == 85.0 and combat.shield == 0.0, "shield absorbs damage before health")
	combat.heal(4.0)
	_check(combat.health == 89.0 and not combat.take_damage(50.0, "helion"), "healing restores health and friendly damage is ignored")
	combat.spawn_choice = "hangar"
	_check(combat.take_damage(500.0, "cinder") and combat.health == 0.0, "lethal damage schedules respawn")
	await process_frame
	await _steps(2)
	var hangar: Vector3 = _world.mothership_manager.get_room_planet_point("helion", "Main Hangar")
	_check(combat.health == 100.0 and combat.shield == 75.0 and player.get_planet_position().distance_to(hangar) < 1.0,
		"respawn restores vitals in the Helion main hangar")
	_world.vehicle_manager.rebuild()
	ai.reset_pool()


func _check_engineering() -> void:
	var combat := _world.player_combat
	var player := _world.explorer
	var position := Vector3(0, 19200, 0)
	_world.floating_origin.check_and_shift(position)
	player.set_move_mode(ExplorerController.MoveMode.FLY)
	player.teleport_to(position, Vector3.FORWARD)
	player.set_physics_process(false)
	var craft := _world.vehicle_manager.vehicles["helion_fighter_hangar"]
	craft.set_planet_position(position + Vector3(0, 0, -15))
	craft.global_basis = Basis.IDENTITY
	craft.set_process(false)
	craft.shield = 0.0
	craft.health = 100.0
	player.set_mouse_captured(true)
	player._unhandled_input(_key(KEY_2))
	await _steps(3)
	var repaired_before: float = _world.match_manager.player_stats.repairs
	_check(combat.selected_tool == 1 and combat.use_engineering_beam(0.25) and craft.health > 100.0 and craft.shield > 0.0
		and _world.match_manager.player_stats.repairs > repaired_before, "engineering key equips a working beam that repairs friendly hull and shield")
	if OS.has_environment("APOGEX_TEST_RAW_COMBAT_GLB"):
		_check(combat.model_source == "glb", "engineering tool loads the Blender model")
	player.set_mouse_captured(false)
	craft.set_process(true)

	var section := _world.destruction.get_section_position(Rig)
	var up := section.normalized()
	var camera := player.get_camera()
	var above := section + up * 12.0
	_world.floating_origin.check_and_shift(above)
	player.teleport_to(above, Vector3.FORWARD)
	var target := _world.floating_origin.planet_to_render(section + up * 3.5)
	camera.look_at(target, player.global_basis.x)
	await _steps(3)
	_world.destruction.set_section_state(Rig, 2)
	_check(combat.use_engineering_beam(1.5) and _world.destruction.get_state(Rig) == 0, "engineering beam brings a critical destruction section back to INTACT")
	combat.select_tool(0)
	_check(combat.fire_weapon() and _world.destruction.get_state(Rig) == 1, "rifle advances damage on the same destruction section")

	var objective := _world.capture_objectives[1]
	var beacon: Vector3 = objective.planet_position
	player.teleport_to(beacon + objective.global_basis * Vector3(0, 2, -10), objective.global_basis.z)
	camera.look_at(objective.global_position + objective.global_basis.y * 2.0, objective.global_basis.y)
	combat.select_tool(1)
	await _steps(3)
	var prior: float = _world.match_manager.player_stats.extracted_resources
	_check(combat.use_engineering_beam(0.4) and _world.match_manager.player_stats.extracted_resources > prior,
		"engineering the beacon extracts resources and scores")
	camera.basis = Basis.IDENTITY
	player.set_physics_process(true)
	_world.vehicle_manager.rebuild()


func _check_match_and_hud() -> void:
	_world.explorer._input(_key(KEY_B))
	_check(_world.combat_hud.deploy_panel.visible and _world.explorer.modal_open, "B opens the modal deploy overlay")
	_world.explorer._input(_key(KEY_TAB))
	_check(_world.combat_hud.scoreboard_panel.visible and not _world.combat_hud.deploy_panel.visible, "Tab switches from deploy to scoreboard")
	_world.explorer._input(_key(KEY_ESCAPE))
	_check(not _world.combat_hud.has_open_panel() and not _world.explorer.modal_open, "Escape closes the gameplay modal")
	_check(_world.switch_faction("cinder") and _world.player_combat.faction == "cinder", "faction switch deploys as Cinder and changes the infantry loadout")
	_world.player_combat.select_tool(0)
	if OS.has_environment("APOGEX_TEST_RAW_COMBAT_GLB"):
		_check(_world.player_combat.model_source == "glb", "Cinder carbine loads the Blender model")
	_check(_world.deploy_player("fighter"), "quick-launch deploy boards the Cinder hangar fighter")
	await process_frame
	await process_frame
	_check(_world.explorer.is_piloting and not _world.player_combat.viewmodel.visible and not _world.combat_hud.get_node("CombatDisplay/SoldierPanel").visible,
		"pilot view hides the infantry model and soldier panel")
	_world.match_manager.record_extraction(_world.match_manager.target_score)
	_check(_world.match_manager.match_state == "VICTORY" and _world.match_manager.winner_faction == "cinder", "target score declares the winner")
	var frozen := _world.match_manager.match_time
	_world.match_manager.tick(2.0)
	_check(_world.match_manager.match_time == frozen, "match time freezes after victory")
	_world.reset_combat_match()
	_check(_world.match_manager.match_state == "ACTIVE" and _world.match_manager.scores.cinder == 0.0 and _world.match_manager.killfeed.is_empty()
		and _world.capture_objectives.all(func(objective: Node3D) -> bool: return objective.owner_faction == "neutral"),
		"match reset clears victory, scores, events and ownership")


func _check_network() -> void:
	var network := _world.network_authority
	var stable := true
	for id in range(1, 33):
		var team := network.assign_peer_faction(id)
		stable = stable and not team.is_empty() and network.assign_peer_faction(id) == team
	_check(stable, "all 32 peers get stable team assignments")
	_check(network.get_peer_counts() == {"helion": 16, "cinder": 16} and network.assign_peer_faction(33).is_empty(),
		"team assigner balances 16v16 and rejects the 33rd peer")

	_world.set_physics_process(false)
	_world.set_process(false)
	_world.capture_objectives[1].update_capture(8.0, 1, 0)
	_world.destruction.set_section_state(Rig, 2)
	var original := network.build_world_sync_snapshot(_world)
	_check(network.build_world_sync_snapshot(_world) == original, "world snapshot is deterministic at a fixed simulation state")
	_world.match_manager.reset_match()
	_world.destruction.set_section_state(Rig, 0)
	network.peer_factions.clear()
	var malformed := original.duplicate(true)
	malformed.objectives[0].capture_progress = 2.0
	_check(not network.apply_world_sync_snapshot(_world, malformed) and _world.destruction.get_state(Rig) == 0,
		"invalid snapshot is rejected before world mutation")
	_check(network.apply_world_sync_snapshot(_world, original)
		and network.build_world_sync_snapshot(_world) == original, "world snapshot roundtrip restores match, objectives, destruction, fleet and roster")
	_world.set_process(true)
	_world.set_physics_process(true)

	var hosted_seed: int = _world.world_config.world_seed + 73
	_check(network.host_server(0, hosted_seed) == OK and network.get_network_mode() == "HOST"
		and network.is_server_authority(), "local ENet listen server starts on an available port")
	if network.get_network_mode() != "HOST":
		return
	var server: ENetMultiplayerPeer = _world.multiplayer.multiplayer_peer
	var port := server.host.get_local_port()
	_world.capture_objectives[1].update_capture(8.0, 1, 0)
	_world.destruction.set_section_state(Rig, 3)
	var api := MultiplayerAPI.create_default_interface()
	set_multiplayer(api, NodePath("/root/ClientWorld"))
	var client_world := WorldScene.instantiate() as WorldRoot
	client_world.name = "ClientWorld"
	root.add_child(client_world)
	var client := client_world.network_authority
	_check(client.join_server("127.0.0.1", port) == OK and client.get_network_mode() == "CLIENT"
		and not client.is_server_authority(), "second world connects to local ENet as a client")
	for frame in 210:
		if client_world.world_config.world_seed == hosted_seed and client_world.destruction.get_state(Rig) == 3:
			break
		await _steps(1)
	_check(client_world.world_config.world_seed == hosted_seed and client_world.capture_objectives[1].owner_faction == "helion"
		and client_world.destruction.get_state(Rig) == 3 and client.peer_factions.size() == 2,
		"host delivers authoritative seed, objective, destruction and team assignment over ENet")
	_check(is_equal_approx(_world.planet.get_surface_radius(Vector3.BACK), client_world.planet.get_surface_radius(Vector3.BACK)),
		"host and client rebuild matching terrain locally from the transmitted seed")
	_check(not client_world.player_combat.fire_weapon() and not client_world.quick_board_vehicle("helion_fighter_hangar"),
		"client world rejects local combat and boarding mutations")
	network.disconnect_session()
	for frame in 120:
		if client.get_network_mode() == "OFFLINE":
			break
		await _steps(1)
	_check(network.get_network_mode() == "OFFLINE" and client.get_network_mode() == "OFFLINE"
		and network.is_server_authority() and network.peer_factions.is_empty(), "ENet disconnect restores offline mode on both worlds")
	client.disconnect_session()
	client_world.queue_free()
	await process_frame
	set_multiplayer(null, NodePath("/root/ClientWorld"))


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _cache_combat_models() -> void:
	for model in ["helion_trooper", "cinder_trooper", "helion_pulse_rifle", "cinder_carbine", "engineering_tool", "capture_beacon_node"]:
		var path: String = Combat.COMBAT_MODELS + model + ".glb"
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) != OK:
			_check(false, "can read %s" % model)
			continue
		var node := document.generate_scene(state)
		var packed := PackedScene.new()
		if node != null and packed.pack(node) == OK:
			packed.take_over_path(path)
			_raw_models.append(packed)
		else:
			_check(false, "can generate Blender scene %s" % model)
		if node != null:
			node.free()
