extends SceneTree

const Showcase = preload("res://tools/capture_apogex_showcase.gd")
const WorldScene = preload("res://scenes/world/WorldRoot.tscn")
const Engineering = preload("res://scripts/gameplay/EngineeringBuildManager.gd")
const Commander = preload("res://scripts/gameplay/CommanderSystem.gd")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const ProjectileScript = preload("res://scripts/vehicles/Projectile.gd")
const PERIMETER := &"terminus_outer_perimeter"

var _raw_models: Array[PackedScene] = []
var world: WorldRoot
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if OS.has_environment("APOGEX_TEST_RAW_DEPLOYABLE_GLB"):
		_raw_models = Showcase.cache_unimported_deployables()
		for filename in Showcase.DEPLOYABLES:
			_check(ResourceLoader.exists(Engineering.Turret.MODELS + filename + ".glb"), "resolves Blender model " + filename)
	world = WorldScene.instantiate() as WorldRoot
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/WorldRoot"))
	root.add_child(world)
	await _frames(3)
	await _engineering()
	await _commander()
	await _batteries()
	_game_feel()
	await _network()
	world.queue_free()
	await process_frame
	print("Phase 4 systems PASS" if failures == 0 else "Phase 4 systems FAIL (%d)" % failures)
	quit(int(failures != 0))


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", description])


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame


func _until(condition: Callable, maximum_frames: int = 180) -> bool:
	for frame in maximum_frames:
		if condition.call():
			return true
		await physics_frame
	return condition.call()


func _quiet_bots() -> void:
	for bot in world.ai_manager.troopers + world.ai_manager.fighters:
		bot.set_physics_process(false)
		bot.global_position += Vector3.UP * 10000.0


func _engineering() -> void:
	world.deploy_player("alpha")
	world.explorer.set_physics_process(false)
	_quiet_bots()
	await _frames(5)
	var manager := world.engineering_build_manager
	var alpha := world.capture_objectives[0]
	var frame := alpha.global_basis
	var point: Vector3 = alpha.planet_position
	var team := world.match_manager
	team.reset_match()
	var turret := manager.deploy("turret", "helion", point + frame * Vector3(-14, 1, 8))
	var shield := manager.deploy("shield", "helion", point + frame * Vector3(9, 1, 7))
	var pod := manager.deploy("supply", "helion", point + frame * Vector3(0, 1, 14))
	_check(turret is Engineering.Turret and shield is Engineering.Shield and pod is Engineering.Pod, "deploys all three structures")
	if turret == null or shield == null or pod == null:
		return
	if OS.has_environment("APOGEX_TEST_RAW_DEPLOYABLE_GLB"):
		_check(turret.model_source == "glb", "deployed turret uses the Blender yaw and pitch pivots")
	_check(is_equal_approx(team.team_resources.helion, 100.0), "three builds spend 150 team resources")
	for structure in [turret, shield, pod]:
		var up: Vector3 = structure.global_basis.y
		var hit := Combat.cast_ray(structure, structure.global_position + up * 0.25, structure.global_position - up * 0.25, 1)
		_check(not hit.is_empty() and structure.global_position.distance_to(hit.position) < 0.015 and up.dot(structure.planet_position.normalized()) > 0.999, "%s mounts flush with spherical up" % structure.name)
	team.team_resources.helion = 39.0
	_check(manager.deploy("supply", "helion", point + frame * Vector3(13, 1, -18)) == null and team.team_resources.helion == 39.0, "insufficient resources reject deployment without spending")
	var origin := world.floating_origin.current_origin
	var moved: Vector3 = turret.planet_position + frame.x * 100.0
	manager.apply_origin(moved)
	_check(turret.global_position.distance_to(turret.planet_position - moved) < 0.002, "buildables preserve planet position across origin changes")
	manager.apply_origin(origin)
	var rival := world.ai_manager.troopers[6]
	rival.global_transform = Transform3D(frame, turret.global_position + frame * Vector3(9, 0, 0))
	var original: float = rival.shield
	await _frames(24)
	_check(turret.target == rival and turret.shots_fired > 0 and rival.shield < original, "turret tracks and damages an enemy BotTrooper")

	var start: Vector3 = shield.global_position + frame * Vector3(0, 1.4, 9)
	var end: Vector3 = shield.global_position + frame * Vector3(0, 1.4, 3)
	_check(manager.intercept_shot(start, end, "helion", 80.0).is_empty() and shield.shield_hp == 350.0, "shield lets friendly fire through")
	var shooter := world.vehicle_manager.vehicles["cinder_fighter_hangar"]
	var bolt := ProjectileScript.new()
	bolt.shooter = shooter
	bolt.damage = 80.0
	bolt.direction = (end - start).normalized()
	bolt.speed = 420.0
	world.vehicle_manager.projectile_root.add_child(bolt)
	bolt.global_position = start
	await _frames(3)
	_check(shield.shield_hp == 270.0 and not is_instance_valid(bolt), "shield absorbs a live swept enemy projectile")
	var player := world.explorer
	player.teleport_to(shield.planet_position + frame * Vector3(0, 0.9, 8), -frame.z)
	player.get_camera().look_at(shield.global_position + frame.y * 1.3, frame.y)
	world.player_combat.select_tool(1)
	await _frames(2)
	_check(world.player_combat.use_engineering_beam(0.5) and shield.shield_hp > 270.0, "Engineering Tool restores shield charge")
	var combat := world.player_combat
	player.teleport_to(pod.planet_position + frame * Vector3(0, 1, -4), frame.z)
	combat.health = 48.0
	combat.ammo = 1
	combat.jetpack_fuel = 4.0
	pod._pulse_wait = 0.0
	pod.tick(0.02, true)
	_check(combat.health > 48.0 and combat.ammo == Combat.MAGAZINE_SIZE and combat.jetpack_fuel == combat.max_jetpack, "supply pod heals infantry and replenishes ammo and jetpack")
	manager.rebuild()
	_check(manager.structures.is_empty() and manager.get_child_count() == 0, "buildable rebuild clears nodes and registered IDs")
	combat.reset_for_spawn()


func _commander() -> void:
	var command := world.commander_system
	var ai := world.ai_manager
	var team := world.match_manager
	team.reset_match()
	world.deploy_player("alpha")
	await _frames(4)
	_check(command.execute("helion", "rally", "bravo") and ai.rally_orders.get("helion") == "bravo", "Commander issues an authoritative rally order")
	var bravo := ai.objective_by_id("bravo")
	_check(ai.troopers.slice(0, 6).all(func(bot: Node) -> bool: return bot.objective == bravo) and ai.fighters[0]._route[0].distance_to(bravo.planet_position) < 500.0, "rally reroutes troopers and fighter patrols")
	_check(not command.execute("helion", "rally", "charlie") and command.ready_in("helion", "rally") > 11.0, "rally enforces its faction cooldown")
	_check(command.execute("helion", "supply", "alpha"), "Commander launches an orbital supply drop")
	var supply: Node3D = world.engineering_build_manager.structures.get("supply-0001")
	if supply != null:
		_check(supply is Engineering.Pod and supply.drop_remaining > 0.0 and supply.global_position.distance_to(world.capture_objectives[0].global_position) > 800.0, "orbital pod starts above the objective at the mothership")
		supply.tick(Engineering.Pod.DROP_TIME, true)
		_check(supply.drop_remaining == 0.0 and supply.collision_layer == 8 and world.floating_origin.render_to_planet(supply.global_position).distance_to(supply.planet_position) < 0.005, "orbital pod lands at its ground anchor")
	else:
		_check(false, "orbital pod has a deterministic ID")

	team.team_resources.helion = 180.0
	var alpha := world.capture_objectives[0]
	var enemy := ai.troopers[6]
	enemy.global_position = alpha.global_position + alpha.global_basis.x * 11.0
	enemy.health = 100.0
	enemy.shield = 40.0
	world.destruction.set_section_state(PERIMETER, 0)
	var audio := world.world_audio.events_played
	command.set_physics_process(false)
	_check(command.execute("helion", "strike", "alpha") and team.team_resources.helion == 0.0, "Commander spends 180 resources to arm the strike")
	_check(command.pending_strikes.size() == 1 and world.combat_effects.has_node("OrbitalStrikeBeacon") and world.combat_effects.has_node("OrbitalUplink"), "strike spawns warning beacon and uplink beam")
	command._physics_process(Commander.WARNING_TIME - 0.01)
	_check(enemy.health == 100.0 and world.destruction.get_state(PERIMETER) == 0, "no strike damage before the warning finishes")
	command._physics_process(0.02)
	_check(enemy.health == 0.0 and world.combat_effects.has_node("OrbitalStrikeBeam"), "strike beam applies heavy enemy area damage")
	_check(world.destruction.get_state(PERIMETER) == 1 and world.world_audio.events_played > audio and world.game_feel.trauma > 0.0, "strike advances destruction and triggers audio and camera shake")
	command.set_physics_process(true)


func _batteries() -> void:
	var ai := world.ai_manager
	_quiet_bots()
	for faction in ["helion", "cinder"]:
		var ship: Node3D = world.mothership_manager.get_ship(faction)
		var batteries: Array = ship.defense_batteries
		if OS.has_environment("APOGEX_TEST_RAW_DEPLOYABLE_GLB"):
			_check(batteries.all(func(node: Node) -> bool: return node.model_source == "glb"), "%s batteries use Blender pivots" % faction)
		_check(batteries.size() == 2 and batteries.all(func(node: Node) -> bool: return node.get_parent() == ship.hull_visual), "%s mounts two exterior defense batteries" % faction)
		ship.set_hull_visible(false)
		_check(not batteries[0].is_visible_in_tree() and not batteries[1].is_visible_in_tree(), "%s batteries hide with the exterior hull" % faction)
		ship.set_hull_visible(true)
		var rival := ai.fighters[2 if faction == "helion" else 0]
		rival.health = 180.0
		rival.shield = 100.0
		rival.global_basis = ship.global_basis
		rival.global_position = ship.to_global(Vector3(0, 145, -350))
		await _frames(36)
		_check(batteries.all(func(node: Node) -> bool: return node.shots_fired > 0) and rival.shield < 100.0, "%s batteries track and fire at the rival fighter" % faction)
		rival.global_position += Vector3.UP * 5000.0


func _game_feel() -> void:
	var feel := world.game_feel
	var camera := world.explorer.get_camera()
	feel.add_trauma(1.0)
	feel.tick(0.016, camera)
	_check(absf(camera.h_offset) + absf(camera.v_offset) > 0.01, "trauma displaces the active camera")
	for tick in 80:
		feel.tick(0.016, camera)
	_check(feel.trauma == 0.0 and absf(camera.h_offset) + absf(camera.v_offset) < 0.0001, "camera shake decays back to its resting offset")


func _network() -> void:
	world.reset_combat_match()
	world.deploy_player("alpha")
	_quiet_bots()
	await _frames(4)
	var server := world.network_authority
	_check(server.host_server(0, world.world_config.world_seed) == OK, "Phase 4 ENet server listens")
	if server.get_network_mode() != "HOST":
		return
	var port: int = world.multiplayer.multiplayer_peer.host.get_local_port()
	var client_view := SubViewport.new()
	client_view.name = "Phase4ClientView"
	client_view.own_world_3d = true
	root.add_child(client_view)
	var path := NodePath("/root/Phase4ClientView/ClientWorld")
	set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	var client := WorldScene.instantiate() as WorldRoot
	client.name = "ClientWorld"
	client_view.add_child(client)
	var receiver := client.network_authority
	_check(receiver.join_server("127.0.0.1", port) == OK, "separate world connects over local ENet")
	var connected := await _until(func() -> bool: return server.replication.avatars.size() == 1 and receiver.replication.avatars.has(1))
	_check(connected, "host and client spawn each other's remote avatars")
	if connected:
		var id := client.multiplayer.get_unique_id()
		var avatar: Node3D = server.replication.avatars[id]
		_check(client.deploy_player("alpha"), "client requests a server-authorized infantry spawn")
		var alpha := world.capture_objectives[0]
		var reached := await _until(func() -> bool: return client.explorer.get_planet_position().distance_to(alpha.planet_position) < 12.0 and avatar.server_pose.origin.distance_to(alpha.planet_position) < 12.0)
		_check(reached, "server and client agree on the client spawn's planet position")
		if reached:
			client.explorer.set_physics_process(false)
			var position: Vector3 = client.explorer.get_planet_position()
			client.explorer.teleport_to(position + alpha.global_basis.x * 2.0, alpha.global_basis.z)
			client.player_combat.select_tool(1)
			var replicated := await _until(func() -> bool: return avatar.target_pose.origin.distance_to(position + alpha.global_basis.x * 2.0) < 0.2 and avatar.active_tool == 1)
			var mid_distance: float = avatar.visual.global_position.distance_to(avatar.target_pose.origin - world.floating_origin.current_origin)
			var settled := await _until(func() -> bool: return avatar.visual.global_position.distance_to(avatar.target_pose.origin - world.floating_origin.current_origin) < 0.15)
			_check(replicated and mid_distance > 0.04 and settled, "remote position interpolates and active tool replicates")
			var before: float = world.match_manager.team_resources.cinder
			receiver.request_deploy_buildable("turret", avatar.server_pose.origin + Vector3.UP * 100.0)
			await _frames(8)
			_check(world.engineering_build_manager.structures.is_empty() and world.match_manager.team_resources.cinder == before, "server rejects spoofed out-of-reach deployment")
			var build_at: Vector3 = avatar.server_pose.origin + alpha.global_basis * Vector3(4, 0, -3)
			_check(receiver.request_deploy_buildable("turret", build_at) and receiver.request_commander_ability("rally", "charlie"), "client submits build and rally RPCs")
			var synced := await _until(func() -> bool: return client.engineering_build_manager.structures.has("turret-0001") and client.ai_manager.rally_orders.get("cinder") == "charlie")
			_check(synced and world.engineering_build_manager.structures.has("turret-0001") and world.ai_manager.rally_orders.get("cinder") == "charlie" and is_equal_approx(world.match_manager.team_resources.cinder, before - 60.0), "host spends the assigned faction's resources and replicates build and rally")
			await _network_combat(client, avatar, alpha)
	receiver.disconnect_session()
	_check(await _until(func() -> bool: return server.replication.avatars.is_empty()), "disconnect removes the remote avatar")
	server.disconnect_session()
	client_view.queue_free()
	await process_frame
	set_multiplayer(null, path)


func _network_combat(client: WorldRoot, avatar: Node3D, alpha: Node3D) -> void:
	var receiver := client.network_authority
	var rival := world.ai_manager.troopers[0]
	var frame := alpha.global_basis
	var camera := client.explorer.get_camera()
	client.player_combat.select_tool(0)
	var from: Vector3 = client.floating_origin.render_to_planet(camera.global_position)
	rival.global_basis = frame
	rival.global_position = world.floating_origin.planet_to_render(from - camera.global_basis.z * 12.0) - frame.y * 1.12
	rival.health = 100.0
	rival.shield = 40.0
	await _until(func() -> bool: return avatar.active_tool == 0)
	await _frames(2)
	var shots := client.player_combat.shots_fired
	_check(receiver.request_infantry_fire(from, -camera.global_basis.z), "client submits an infantry fire RPC")
	_check(await _until(func() -> bool: return avatar.ammo == Combat.MAGAZINE_SIZE - 1 and rival.shield < 40.0 and client.player_combat.shots_fired > shots), "server sweeps infantry fire and replicates ammo, damage and tracer feedback")
	rival.global_position += frame.y * 200.0

	var rover := world.vehicle_manager.vehicles["cinder_rover_refinery"]
	world.vehicle_manager._surface_anchors.erase(rover.vehicle_id)
	rover.global_basis = frame
	rover.set_planet_position(avatar.server_pose.origin + frame.x * 6.0)
	rover.velocity = Vector3.ZERO
	rover.set_physics_process(false)
	var arrived := await _until(func() -> bool: return client.vehicle_manager.vehicles[rover.vehicle_id].get_planet_position().distance_to(rover.get_planet_position()) < 1.0)
	_check(arrived and receiver.request_vehicle_board(rover.vehicle_id), "client requests boarding for a nearby friendly vehicle")
	_check(await _until(func() -> bool: return rover.is_piloted and avatar.vehicle_id == rover.vehicle_id and not avatar.visible and client.get_active_vehicle() != null), "server grants vehicle ownership and hides the remote infantry avatar")
