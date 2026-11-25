extends SceneTree

const WorldScene := preload("res://scenes/world/WorldRoot.tscn")
const PORT_WAIT := 300
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := _make_world("FrontendHost")
	var front := world.frontend_ui
	_check(world.get_frontend_state() == "GAMEPLAY" and world.combat_hud.visible and not world.explorer.modal_open, "Headless WorldRoot starts directly in gameplay")
	_check(not world.debug_ui.hud_bar.visible, "Developer bar starts hidden")
	world.open_main_menu()
	_check(world.get_frontend_state() == "MAIN_MENU" and front.menu_camera.current and not world.combat_hud.visible and not world.vehicle_hud.visible and not world.explorer.mouse_captured, "Main menu selects live orbital camera, frees cursor and hides both HUDs")
	var eye: Vector3 = front.menu_camera.global_position
	await _frames(4)
	_check(eye.distance_to(front.menu_camera.global_position) > 0.01, "Orbital menu camera moves")
	_press(world, "SETTINGS")
	_check(front.drawer == "settings", "Main menu opens Settings")
	var quality := _find_option(world, "ULTRA")
	if quality != null:
		quality.select(0)
		quality.item_selected.emit(0)
	_check(quality != null and world.world_config.quality_preset == "LOW", "Settings quality is applied to the live world")
	var seed := front._main._drawer.find_child("WorldSeed", true, false) as LineEdit
	var expected_seed := world.world_config.world_seed + 1
	if seed != null:
		seed.text = str(expected_seed)
	_press(world, "Regenerate")
	_check(seed != null and world.world_config.world_seed == expected_seed, "Settings regenerates Vesper-9 with the entered seed (expected %d, got %d, found field %s)" % [expected_seed, world.world_config.world_seed, seed != null])
	_key(world, KEY_ESCAPE)
	_press(world, "CONTROLS & FIELD GUIDE")
	_check(front.drawer == "guide", "Main menu opens the field guide")
	_key(world, KEY_ESCAPE)
	_press(world, "PLAY — QUICK DEPLOY")
	_check(world.get_frontend_state() == "SPAWN", "Quick Deploy opens tactical deployment directly")
	_key(world, KEY_ESCAPE)
	_check(world.get_frontend_state() == "MAIN_MENU", "Escape returns a Quick Deploy visitor to the menu")
	_press(world, "MATCH LOBBY (16V16 / MULTIPLAYER)")
	_check(world.get_frontend_state() == "LOBBY" and front.menu_camera.current, "Main Menu opens the lobby")
	_check(front.select_faction("cinder") and front._lobby._roster.cinder[0].text.contains("[YOU]") and front._lobby._roster.cinder.size() == 16 and front._lobby._roster.helion.size() == 16, "Cinder selection moves [YOU] into the correct 16-player roster")
	for entry in [["assault", "hangar"], ["engineer", "hangar"], ["pilot", "fighter"], ["commander", "bridge"]]:
		var choice: Button = front._lobby._roles[entry[0]]
		choice.pressed.emit()
		_check(front.role == entry[0] and front.spawn_id == entry[1], "%s selects %s" % entry)
	_check(front.start_host(0) == OK and world.network_authority.get_network_mode() == "HOST", "Lobby starts an ENet listen server")
	var port: int = world.multiplayer.multiplayer_peer.host.get_local_port()
	var client := _make_world("FrontendClient")
	client.open_lobby()
	var remote := client.frontend_ui
	_check(remote.join_session("127.0.0.1", port) == OK, "A second lobby starts an ENet join")
	for index in PORT_WAIT:
		if remote.client_ready():
			break
		await physics_frame
	_check(remote.client_ready() and world.network_authority.peer_factions.size() == 2, "ENet joins and publishes team assignments")
	_check(remote.select_faction("cinder"), "Joined player can request a different faction")
	_check(remote.launch_lobby() and remote.select_role("commander") and remote.deploy_from_frontend("bridge", remote.faction, "commander"), "Client requests an authoritative command bridge deploy")
	for index in PORT_WAIT:
		if client.get_frontend_state() == "GAMEPLAY":
			break
		await physics_frame
	_check(client.get_frontend_state() == "GAMEPLAY" and client.match_manager.player_faction == "cinder" and client.explorer.get_planet_position().distance_to(client.infantry_spawn("bridge", "cinder").position) < 2.0, "ENet confirms the client’s bridge spawn")
	await create_timer(0.8).timeout
	client.open_spawn_screen()
	_check(remote.deploy_from_frontend("fighter", remote.faction, "pilot"), "Client requests a faction cockpit")
	for index in PORT_WAIT:
		if client.get_frontend_state() == "GAMEPLAY" or not remote.deploy_pending:
			break
		await physics_frame
	_check(client.get_frontend_state() == "GAMEPLAY" and client.explorer.is_piloting and client.get_active_vehicle().vehicle_id == "cinder_fighter_hangar", "ENet confirms cockpit boarding (%s)" % remote.notice)
	front.stop_session()
	for index in PORT_WAIT:
		if client.network_authority.get_network_mode() == "OFFLINE":
			break
		await physics_frame
	_check(world.network_authority.get_network_mode() == "OFFLINE" and client.network_authority.get_network_mode() == "OFFLINE", "Lobby host can disconnect the ENet session")
	client.queue_free()
	await process_frame
	set_multiplayer(null, NodePath("/root/FrontendClient"))

	front._lobby._select_mode(0)
	front.target_score = 500
	_press(world, "LAUNCH & DEPLOY →")
	_check(world.get_frontend_state() == "SPAWN" and world.match_manager.target_score == 500.0, "Lobby launches Tactical Deployment with the configured score target")
	_press(world, "◇ ALPHA")
	_check(front.spawn_id == "alpha" and front._spawn._location.text == "Terminus Extraction Spire", "Tactical pin click selects a surface location and updates the details")
	_check(world.deploy_from_frontend("hangar", "cinder", "assault"), "Assault deploys to the Cinder hangar")
	await _frames(3)
	_check(world.get_frontend_state() == "GAMEPLAY" and world.explorer.move_mode == ExplorerController.MoveMode.WALK and world.explorer.get_planet_position().distance_to(world.infantry_spawn("hangar", "cinder").position) < 2.0 and world.player_combat.selected_tool == 0 and world.player_combat.shield == 100.0, "Hangar places a walking Assault with the rifle and 100 shield")
	_check(world.combat_hud.visible and not world.debug_ui.hud_bar.visible and world.explorer.mouse_captured, "Deployment captures input and presents the clean HUD")
	_key(world, KEY_B)
	_check(world.get_frontend_state() == "SPAWN" and not world.combat_hud.deploy_panel.visible, "B opens the new tactical screen")
	_check(world.deploy_from_frontend("fighter", "cinder", "pilot") and world.explorer.is_piloting and world.get_active_vehicle().vehicle_id == "cinder_fighter_hangar", "Pilot deploys directly into the Cinder fighter")
	world.open_spawn_screen()
	_check(world.deploy_from_frontend("bridge", "helion", "commander"), "Commander deploys to the Helion command bridge")
	await _frames(4)
	_check(not world.explorer.is_piloting and world.commander_system.near_holotable(), "Command bridge places infantry within holotable range")
	var resources: float = world.match_manager.team_resources.helion
	for id in ["alpha", "bravo", "charlie"]:
		world.open_spawn_screen()
		_check(world.deploy_from_frontend(id, "helion", "engineer"), "Engineer deploys to " + id)
		await _frames(4)
		var placement := world.infantry_spawn(id, "helion")
		_check(world.explorer.get_planet_position().distance_to(placement.position) < 1.5 and world.player_combat.selected_tool == 1 and world.player_combat.max_shield == 75.0, "%s uses the surface spawn and engineering loadout" % id)
	_check(is_equal_approx(world.match_manager.team_resources.helion, resources + 100.0), "Engineer grants 100 faction resources once per match")

	_key(world, KEY_M)
	_check(world.debug_ui.map_panel.visible, "M still opens the developer map")
	_key(world, KEY_ESCAPE)
	_check(world.get_frontend_state() == "GAMEPLAY" and not world.debug_ui.map_panel.visible, "Escape closes a gameplay modal before opening Pause")
	_key(world, KEY_TAB)
	_check(world.combat_hud.scoreboard_panel.visible, "Tab still opens the gameplay scoreboard")
	_key(world, KEY_ESCAPE)
	_key(world, KEY_ESCAPE)
	_check(world.get_frontend_state() == "PAUSED" and not world.explorer.mouse_captured and not world.combat_hud.visible, "Escape opens Pause and frees the pointer")
	_press(world, "DEV DEBUG BAR: OFF")
	_check(world.debug_ui.hud_bar.visible, "Pause can show the developer bar")
	_press(world, "DEV DEBUG BAR: ON")
	_check(not world.debug_ui.hud_bar.visible, "Pause can hide the developer bar")
	_key(world, KEY_ESCAPE)
	_check(world.get_frontend_state() == "GAMEPLAY" and world.explorer.mouse_captured, "Escape resumes and captures the mouse")
	_check(world.player_combat.take_damage(999.0, "cinder"), "Local elimination is accepted")
	await _frames(2)
	_check(world.get_frontend_state() == "SPAWN" and front.respawn_remaining > 0.0 and not world.deploy_from_frontend("hangar", "helion", "assault"), "Elimination opens the spawn screen and gates deployment")
	_key(world, KEY_ESCAPE)
	_check(world.get_frontend_state() == "SPAWN", "Escape cannot dismiss a required respawn")
	await create_timer(2.1).timeout
	_check(world.deploy_from_frontend("hangar", "helion", "assault") and world.player_combat.health == 100.0, "Respawn timer unlocks deployment and restores health")

	world.match_manager.record_extraction(world.match_manager.target_score)
	_check(world.get_frontend_state() == "VICTORY" and front._pause._winner.text == "HELION VICTORY" and not world.combat_hud.visible, "Victory displays the winning faction and hides the gameplay HUD")
	_press(world, "PLAY AGAIN")
	_check(world.get_frontend_state() == "SPAWN" and world.match_manager.match_state == "ACTIVE" and world.match_manager.scores.helion == 0.0, "Play Again clears the result and returns to deployment")
	world.deploy_from_frontend("hangar", "helion", "assault")
	world.match_manager.record_extraction(world.match_manager.target_score)
	_press(world, "RETURN TO LOBBY")
	_check(world.get_frontend_state() == "LOBBY", "Victory can return to the lobby")
	_press(world, "← MAIN MENU")
	_check(world.get_frontend_state() == "MAIN_MENU" and front.menu_camera.current, "Lobby returns to the live main menu")
	_press(world, "EXPLORER SANDBOX")
	_check(world.get_frontend_state() == "GAMEPLAY" and front.sandbox and world.debug_ui.hud_bar.visible and world.explorer.camera_mode == ExplorerController.CameraMode.FREE_FLIGHT, "Explorer Sandbox enters free flight with the developer bar")
	_key(world, KEY_ESCAPE)
	_press(world, "RETURN TO MAIN MENU")
	_check(world.get_frontend_state() == "MAIN_MENU" and not world.debug_ui.hud_bar.visible, "Pause returns to the main menu and clears the developer bar")
	world.queue_free()
	await _frames(2)
	print("Frontend flow PASS" if _failures == 0 else "Frontend flow FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _make_world(node_name: String) -> WorldRoot:
	var world := WorldScene.instantiate() as WorldRoot
	world.name = node_name
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/" + node_name))
	root.add_child(world)
	return world


func _key(world: WorldRoot, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	world.explorer._input(event)


func _press(world: WorldRoot, title: String) -> void:
	for node in world.frontend_ui.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == title and button.is_visible_in_tree() and not button.disabled:
			button.pressed.emit()
			return
	_check(false, "Visible button exists for " + title)


func _find_option(world: WorldRoot, item: String) -> OptionButton:
	for node in world.frontend_ui.find_children("*", "OptionButton", true, false):
		var option := node as OptionButton
		if option.is_visible_in_tree():
			for index in option.item_count:
				if option.get_item_text(index) == item:
					return option
	return null


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", description])
