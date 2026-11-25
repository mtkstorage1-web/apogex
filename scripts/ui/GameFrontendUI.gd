extends CanvasLayer

const UI = preload("res://scripts/ui/UIThemeUtils.gd")
const MainMenu = preload("res://scripts/ui/MainMenuView.gd")
const Lobby = preload("res://scripts/ui/LobbyView.gd")
const Spawn = preload("res://scripts/ui/SpawnScreenView.gd")
const Pause = preload("res://scripts/ui/PauseMenuView.gd")
const RESPAWN_DELAY := 2.0

var world: Node
var state := "GAMEPLAY"
var managed := false
var active_match := true
var sandbox := false
var dev_bar_enabled := false
var drawer := ""
var faction := "helion"
var role := "assault"
var spawn_id := "hangar"
var seed_text := ""
var target_score := 1000
var session_message := ""
var notice := ""
var respawn_required := false
var respawn_remaining := 0.0
var deploy_pending := false
var menu_camera: Camera3D

var _main: Control
var _lobby: Control
var _spawn: Control
var _pause: Control
var _spawn_origin := "GAMEPLAY"
var _menu_time := 0.0
var _refresh_wait := 0.0
var _deploy_timeout := 0.0
var _remote_assault := {}
var _remote_deploy_times := {}
var _last_session_mode := "OFFLINE"
var _host_port := 0
var _match_prepared := false
var _client_faction_selected := false


func setup(context: Node) -> void:
	world = context
	faction = world.match_manager.player_faction
	seed_text = str(world.world_config.world_seed)
	var screen := Control.new()
	screen.name = "Screen"
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = UI.create_theme()
	UI.full(self, screen)
	_main = MainMenu.new()
	_lobby = Lobby.new()
	_spawn = Spawn.new()
	_pause = Pause.new()
	for view in [_main, _lobby, _spawn, _pause]:
		UI.full(screen, view)
		view.setup(self)
	menu_camera = Camera3D.new()
	menu_camera.name = "FrontendOrbitCamera"
	menu_camera.fov = 49.0
	menu_camera.near = 2.0
	menu_camera.far = 240000.0
	add_child(menu_camera)
	process_physics_priority = -1
	world.multiplayer.peer_disconnected.connect(_forget_peer)
	world.network_authority.session_changed.connect(_session_changed)
	world.match_manager.victory_declared.connect(_on_victory)
	_setup_audio_buses()
	if DisplayServer.get_name() == "headless" or "--skip-menu" in OS.get_cmdline_args() or "--skip-menu" in OS.get_cmdline_user_args():
		managed = DisplayServer.get_name() != "headless"
		_show_state("GAMEPLAY")
	else:
		open_main_menu()


func _show_state(next: String) -> void:
	state = next
	drawer = ""
	_main.show_drawer(self, "")
	_main.visible = next == "MAIN_MENU"
	_lobby.visible = next == "LOBBY"
	_spawn.visible = next == "SPAWN"
	_pause.visible = next in ["PAUSED", "VICTORY"]
	if uses_menu_camera():
		update_menu_camera(0.0)
		menu_camera.make_current()
	else:
		var vehicle: Node3D = world.get_active_vehicle()
		if vehicle == null:
			world.explorer.get_camera().make_current()
		else:
			vehicle.get_active_camera().make_current()
	world.apply_frontend_presentation()
	if _lobby.visible:
		_lobby.refresh()
	if _spawn.visible:
		_spawn.prepare_map()
		_spawn.refresh()
	if _pause.visible:
		_pause.refresh(self)


func uses_menu_camera() -> bool:
	return state in ["MAIN_MENU", "LOBBY"] or (state == "SPAWN" and _spawn_origin in ["MAIN_MENU", "LOBBY"])


func update_menu_camera(delta: float) -> void:
	if not uses_menu_camera():
		return
	_menu_time += delta
	var angle := 0.19 * sin(_menu_time * 0.12)
	var pivot := Vector3(0, 0, 13900)
	var eye := pivot + Vector3(-5300, 850, 4900).rotated(Vector3.UP, angle)
	var center := pivot + Vector3(-2000, 250, -2700)
	menu_camera.position = world.floating_origin.planet_to_render(eye)
	menu_camera.look_at(world.floating_origin.planet_to_render(center), Vector3.UP)
	if _main.visible:
		_main.project_ships(menu_camera, world)


func open_main_menu() -> void:
	managed = true
	active_match = false
	_match_prepared = false
	sandbox = false
	dev_bar_enabled = false
	_clear_deployment()
	stop_session()
	world.vehicle_manager.release_for_world_travel()
	seed_text = str(world.world_config.world_seed)
	_show_state("MAIN_MENU")
	_play_menu_audio()


func open_lobby() -> void:
	managed = true
	active_match = false
	_match_prepared = false
	sandbox = false
	dev_bar_enabled = false
	_clear_deployment()
	world.vehicle_manager.release_for_world_travel()
	_show_state("LOBBY")
	_play_menu_audio()


func quick_deploy() -> void:
	_clear_deployment()
	active_match = false
	_match_prepared = false
	open_spawn_screen()


func launch_lobby() -> bool:
	if state != "LOBBY":
		return false
	if world.can_mutate_world():
		if not seed_text.is_valid_int() or target_score not in [500, 1000, 1500]:
			notice = "Enter a valid world seed and target score."
			_lobby.refresh()
			return false
		world.match_manager.target_score = float(target_score)
		if int(seed_text) != world.world_config.world_seed:
			world.regenerate_world(int(seed_text))
	elif not client_ready():
		return false
	notice = ""
	open_spawn_screen()
	return true


func open_spawn_screen() -> void:
	if state == "SPAWN":
		return
	managed = true
	_spawn_origin = state
	notice = ""
	_show_state("SPAWN")


func back_from_spawn() -> void:
	if state != "SPAWN" or respawn_required or deploy_pending:
		return
	if _spawn_origin == "GAMEPLAY":
		resume_gameplay()
	else:
		_show_state(_spawn_origin)


func open_pause_menu() -> void:
	if state != "GAMEPLAY":
		return
	managed = true
	_show_state("PAUSED")


func resume_gameplay() -> void:
	if state == "PAUSED" or (state == "SPAWN" and not respawn_required and _spawn_origin == "GAMEPLAY"):
		_show_state("GAMEPLAY")


func enter_sandbox_mode() -> void:
	managed = true
	active_match = false
	_match_prepared = false
	sandbox = true
	dev_bar_enabled = true
	_clear_deployment()
	stop_session()
	world.teleport_to_landmark(0)
	world.explorer.set_camera_mode(world.explorer.CameraMode.FREE_FLIGHT)
	_show_state("GAMEPLAY")
	_play_game_audio()


func select_faction(value: String) -> bool:
	if value not in UI.FACTIONS or deploy_pending:
		return false
	var network: Node = world.network_authority
	var mode: String = network.get_network_mode()
	if mode == "CLIENT" and not client_ready():
		return false
	if mode != "OFFLINE":
		var team: String = network.peer_factions.get(world.multiplayer.get_unique_id(), "")
		if value != team and network.get_peer_counts()[value] >= 16:
			notice = "That faction is full."
			_refresh()
			return false
	if mode == "CLIENT":
		_client_faction_selected = true
	elif mode == "HOST" and state == "LOBBY":
		network.set_host_faction(value)
		world.match_manager.switch_faction(value)
	faction = value
	notice = ""
	_refresh()
	return true

func switch_spawn_faction() -> void:
	open_spawn_screen()
	select_faction("cinder" if faction == "helion" else "helion")


func select_role(value: String) -> bool:
	if not UI.ROLES.has(value) or deploy_pending:
		return false
	role = value
	spawn_id = UI.ROLES[role][2]
	notice = ""
	_refresh()
	return true


func select_spawn(value: String) -> bool:
	if not Spawn.LOCATIONS.has(value) or deploy_pending:
		return false
	spawn_id = value
	notice = ""
	_refresh()
	return true


func deploy_selected() -> void:
	deploy_from_frontend(spawn_id, faction, role)


func deploy_from_frontend(id: String, team: String, loadout: String) -> bool:
	if not Spawn.LOCATIONS.has(id) or not UI.ROLES.has(loadout) or team not in UI.FACTIONS:
		return false
	if respawn_remaining > 0.0 or deploy_pending:
		return false
	if not world.can_mutate_world():
		if not client_ready():
			return false
		deploy_pending = true
		_deploy_timeout = 5.0
		_request_deploy.rpc_id(1, id, team, loadout)
		_refresh()
		return true
	if id == "fighter" and not world.frontend_fighter_available(team):
		return _deploy_failure("The hangar fighter is unavailable. Select another spawn.")
	if not world.network_authority.set_host_faction(team):
		return _deploy_failure("That faction is full.")
	_prepare_match()
	world.match_manager.switch_faction(team)
	if id == "fighter" and world.get_active_vehicle() != world.vehicle_manager.vehicles[team + "_fighter_hangar"]:
		world.vehicle_manager.release_for_world_travel()
	world.explorer.gravity_alignment = true
	if not world.deploy_player(id):
		return _deploy_failure("Deployment failed. Select a spawn and try again.")
	_finish_deployment(id, team, loadout)
	world.match_manager.apply_starting_role(team, loadout, 1)
	return true


func _prepare_match() -> void:
	if not active_match and not _match_prepared:
		world.reset_combat_match(false)
		_match_prepared = true


func _deploy_failure(message: String) -> bool:
	notice = message
	deploy_pending = false
	_refresh()
	return false


func _finish_deployment(id: String, team: String, loadout: String) -> void:
	spawn_id = id
	faction = team
	role = loadout
	world.player_combat.apply_starting_role(loadout)
	world.player_combat.spawn_choice = "hangar" if id == "fighter" else id
	_clear_deployment()
	managed = true
	active_match = true
	sandbox = false
	_show_state("GAMEPLAY")
	_play_game_audio()


func _clear_deployment() -> void:
	respawn_required = false
	respawn_remaining = 0.0
	deploy_pending = false
	notice = ""


func on_player_eliminated() -> void:
	if not managed or not active_match or respawn_required or state == "VICTORY":
		return
	respawn_required = true
	respawn_remaining = RESPAWN_DELAY
	open_spawn_screen()
	_refresh()


func _on_victory(_winner: String) -> void:
	if managed and active_match and state != "VICTORY":
		_clear_deployment()
		_show_state("VICTORY")


func play_again() -> void:
	if not world.can_mutate_world():
		open_lobby()
		return
	world.reset_combat_match(false)
	active_match = false
	_match_prepared = false
	_match_prepared = true
	_spawn_origin = "LOBBY"
	_show_state("SPAWN")


func handle_key(key: Key) -> bool:
	if key in [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_M, KEY_P] and (managed or world.explorer.modal_open):
		world.explorer._on_key(key)
		return true
	if not managed:
		return false
	if key == KEY_ESCAPE:
		if world.debug_ui.is_any_panel_open():
			world.close_frontend_modals()
		elif not drawer.is_empty():
			close_drawer()
		else:
			match state:
				"GAMEPLAY": open_pause_menu()
				"PAUSED": resume_gameplay()
				"SPAWN": back_from_spawn()
				"LOBBY": open_main_menu()
		return true
	if key == KEY_B and state in ["GAMEPLAY", "PAUSED", "SPAWN"]:
		if state == "SPAWN":
			back_from_spawn()
		else:
			open_spawn_screen()
		return true
	return false


func toggle_dev_bar() -> void:
	dev_bar_enabled = not dev_bar_enabled
	world.apply_frontend_presentation(false)
	_refresh()


func toggle_settings() -> void:
	_set_drawer("" if drawer == "settings" else "settings")


func toggle_field_guide() -> void:
	_set_drawer("" if drawer == "guide" else "guide")


func close_drawer() -> void:
	_set_drawer("")


func _set_drawer(kind: String) -> void:
	drawer = kind
	if state == "MAIN_MENU":
		_main.show_drawer(self, kind)
	elif state == "PAUSED":
		_pause.refresh(self)


func build_settings(parent: VBoxContainer) -> void:
	var presets := ["LOW", "MEDIUM", "HIGH", "ULTRA"]
	UI.label(parent, "Quality preset", 15, UI.MUTED)
	var quality := UI.option(parent, presets, func(index: int) -> void: world.set_quality_preset(presets[index]))
	quality.select(presets.find(world.world_config.quality_preset))
	UI.label(parent, "World seed", 15, UI.MUTED)
	var seed_row := UI.row(parent, 6)
	var input := UI.field(seed_row, str(world.world_config.world_seed), "Integer seed", 20)
	input.name = "WorldSeed"
	var status := UI.label(parent, "", 14, UI.ORANGE)
	status.hide()
	var regenerate := UI.button(seed_row, "Regenerate", func() -> void:
		if not input.text.is_valid_int():
			status.text = "Enter a valid integer seed."
			status.show()
			return
		status.hide()
		world.regenerate_world(int(input.text))
		seed_text = str(world.world_config.world_seed)
		if state == "PAUSED":
			world.deploy_player("hangar")
			world.apply_frontend_presentation(false)
	)
	input.editable = world.can_mutate_world()
	regenerate.disabled = not input.editable
	UI.line(parent)
	for bus in [&"Master", &"Music", &"Effects"]:
		var index := AudioServer.get_bus_index(bus)
		var volume := 0.0 if AudioServer.is_bus_mute(index) else AudioServer.get_bus_volume_linear(index)
		_slider(parent, String(bus) + " volume", 0.0, 1.0, volume, func(value: float) -> void:
			AudioServer.set_bus_mute(index, value <= 0.0)
			AudioServer.set_bus_volume_linear(index, maxf(0.0001, value)))
	_slider(parent, "Mouse sensitivity", 0.25, 2.5, world.explorer.mouse_sensitivity, func(value: float) -> void:
		world.explorer.mouse_sensitivity = value)


func _slider(parent: VBoxContainer, title: String, minimum: float, maximum: float, value: float, change: Callable) -> void:
	var column := UI.column(parent, 1)
	var header := UI.row(column, 2)
	UI.label(header, title, 15, UI.MUTED)
	UI.space(header)
	var number := UI.label(header, "%d%%" % roundi(value * 100.0), 15)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = value
	column.add_child(slider)
	slider.value_changed.connect(func(amount: float) -> void:
		number.text = "%d%%" % roundi(amount * 100.0)
		change.call(amount))


func _setup_audio_buses() -> void:
	for bus in [&"Music", &"Effects"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	var effects := AudioServer.get_bus_index(&"Effects")
	if effects > 1:
		AudioServer.move_bus(effects, 1)
	for bus in [&"Environment", &"Machinery", &"Weather", &"Ambience"]:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_send(index, &"Effects")
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		for player in audio.get("_music_players"):
			player.bus = &"Music"
		for player in audio.get("_sfx_players"):
			player.bus = &"Effects"
		for property in ["_bed_player", "_wind_player", "_bird_player", "_engine_player"]:
			var player: AudioStreamPlayer = audio.get(property)
			if player != null:
				player.bus = &"Effects"


func _play_menu_audio() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_menu_music()


func _play_game_audio() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.set_mode("flight", 0.8)


func start_host(port: int) -> Error:
	if not seed_text.is_valid_int() or port < 0 or port > 65535:
		session_message = "Enter a valid world seed and port."
		_refresh()
		return ERR_INVALID_PARAMETER
	var result: Error = world.network_authority.host_server(port, int(seed_text))
	if result == OK:
		world.match_manager.target_score = float(target_score)
		world.network_authority.set_host_faction(faction)
		world.match_manager.switch_faction(faction)
		_host_port = world.multiplayer.multiplayer_peer.host.get_local_port()
		session_message = ""
	else:
		session_message = "Host failed · " + error_string(result)
	_refresh()
	return result


func join_session(address: String, port: int) -> Error:
	if address.is_empty() or port < 1 or port > 65535:
		session_message = "Enter a host address and valid port."
		_refresh()
		return ERR_INVALID_PARAMETER
	var result: Error = world.network_authority.join_server(address, port)
	session_message = "" if result == OK else "Connection failed · " + error_string(result)
	_refresh()
	return result


func stop_session() -> void:
	world.network_authority.disconnect_session()
	session_message = ""
	_refresh()


func _session_changed(mode: String) -> void:
	if mode == "OFFLINE":
		_client_faction_selected = false
		_remote_assault.clear()
		_remote_deploy_times.clear()
		if _last_session_mode == "CLIENT":
			deploy_pending = false
			if state in ["SPAWN", "GAMEPLAY", "PAUSED", "VICTORY"] and managed:
				open_lobby()
			session_message = "Disconnected from server."
	_last_session_mode = mode
	_refresh()


func client_ready() -> bool:
	return world.network_authority.get_network_mode() == "CLIENT" and world.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and world.network_authority.peer_factions.has(world.multiplayer.get_unique_id())


func session_status() -> String:
	if not session_message.is_empty():
		return session_message
	match world.network_authority.get_network_mode():
		"HOST": return "Hosting on UDP %d · %d / 32 players" % [_host_port, world.network_authority.peer_factions.size()]
		"CLIENT": return "Connected · " + faction.capitalize() if client_ready() else "Connecting to server…"
		_: return "Offline · bots fill open slots"


func _process(delta: float) -> void:
	if world == null:
		return
	if managed and active_match:
		if world.match_manager.match_state == "VICTORY":
			_on_victory(world.match_manager.winner_faction)
		elif not world.can_mutate_world() and world.player_combat.health <= 0.0:
			on_player_eliminated()
	respawn_remaining = maxf(0.0, respawn_remaining - delta)
	if deploy_pending:
		_deploy_timeout -= delta
		if _deploy_timeout <= 0.0:
			_deploy_failure("The server did not confirm deployment. Try again.")
	_refresh_wait -= delta
	if _refresh_wait <= 0.0:
		_refresh_wait = 0.15
		if client_ready() and not _client_faction_selected:
			faction = world.network_authority.peer_factions[world.multiplayer.get_unique_id()]
		_refresh()


func _refresh() -> void:
	if state == "LOBBY":
		_lobby.refresh()
	elif state == "SPAWN":
		_spawn.refresh()
	elif state in ["PAUSED", "VICTORY"]:
		_pause.refresh(self)


func _forget_peer(id: int) -> void:
	_remote_assault.erase(id)
	_remote_deploy_times.erase(id)


func _physics_process(delta: float) -> void:
	if world == null or not world.can_simulate_combat():
		return
	# The replication system handles shields through 75. Preserve its damage delay
	# while regenerating the additional Assault shield points on the server.
	for id in _remote_assault:
		var avatar: Node = world.network_authority.replication.avatars.get(id)
		if avatar != null and avatar.health > 0.0 and avatar.shield_wait <= delta:
			avatar.shield = minf(100.0, avatar.shield + 20.0 * delta)
			avatar.shield_wait = delta + 0.000001


@rpc("any_peer", "call_remote", "reliable")
func _request_deploy(id: String, team: String, loadout: String) -> void:
	var network: Node = world.network_authority
	var peer := multiplayer.get_remote_sender_id()
	if network.get_network_mode() != "HOST" or not network.peer_factions.has(peer):
		return
	if not Spawn.LOCATIONS.has(id) or not UI.ROLES.has(loadout) or team not in UI.FACTIONS:
		_deploy_rejected.rpc_id(peer, "Invalid spawn, faction or role.")
		return
	var avatar: Node = network.replication.avatars.get(peer)
	if network.peer_factions[peer] != team and network.get_peer_counts()[team] >= 16:
		_deploy_rejected.rpc_id(peer, "That faction is full.")
		return
	var now := Time.get_ticks_msec()
	if avatar == null or avatar.health <= 0.0 or now - int(_remote_deploy_times.get(peer, -5000)) < 750:
		_deploy_rejected.rpc_id(peer, "Spawn is still on cooldown.")
		return
	if id == "fighter" and not world.frontend_fighter_available(team):
		_deploy_rejected.rpc_id(peer, "The faction’s hangar fighter is unavailable.")
		return
	if active_match and world.match_manager.match_state != "ACTIVE":
		_deploy_rejected.rpc_id(peer, "The match is complete. Return to the lobby.")
		return
	_prepare_match()
	active_match = true
	_remote_deploy_times[peer] = now
	var previous_vehicle: String = avatar.vehicle_id
	network._release_remote_vehicle(peer)
	if not previous_vehicle.is_empty() and id == "fighter":
		network._vehicle_status.rpc_id(peer, "")
	if avatar.faction != team:
		network.peer_factions[peer] = team
		avatar.faction = team
		avatar.rebuild_model()
	var placement: Dictionary = world.infantry_spawn("hangar" if id == "fighter" else id, team)
	var point: Vector3 = placement.position
	var facing: Vector3 = placement.facing
	var vehicle_id := ""
	if id == "fighter":
		vehicle_id = team + "_fighter_hangar"
		var fighter: Node3D = world.vehicle_manager.vehicles[vehicle_id]
		point = fighter.get_planet_position()
	var pose := Transform3D(Basis.looking_at(facing, placement.up), point)
	var sample: Dictionary = network.replication.player_states[peer]
	sample.pose = pose
	sample.aim = facing
	sample.tool = 1 if loadout == "engineer" else 0
	sample.velocity = Vector3.ZERO
	sample.received = now
	avatar.server_pose = pose
	avatar.target_pose = pose
	avatar.health = 100.0
	avatar.shield = 100.0 if loadout == "assault" else 75.0
	avatar.shield_wait = 0.0
	avatar.ammo = world.player_combat.MAGAZINE_SIZE
	avatar.update_visibility()
	if loadout == "assault":
		_remote_assault[peer] = true
	else:
		_remote_assault.erase(peer)
	world.match_manager.apply_starting_role(team, loadout, peer)
	if not vehicle_id.is_empty():
		network._vehicle_board(vehicle_id)
		if avatar.vehicle_id != vehicle_id:
			_deploy_rejected.rpc_id(peer, "The fighter cannot be boarded. Select another spawn.")
			return
	_deploy_confirmed.rpc_id(peer, id, team, loadout, point, facing)


@rpc("authority", "call_remote", "reliable")
func _deploy_rejected(message: String) -> void:
	if deploy_pending:
		_deploy_failure(message)


@rpc("authority", "call_remote", "reliable")
func _deploy_confirmed(id: String, team: String, loadout: String, point: Vector3, facing: Vector3) -> void:
	if not deploy_pending:
		return
	if id == "fighter":
		if world.get_active_vehicle() == null or world.get_active_vehicle().vehicle_id != team + "_fighter_hangar":
			_deploy_failure("Cockpit boarding failed. Select another spawn.")
			return
	else:
		world.explorer.gravity_alignment = true
		world.place_infantry(id, point, facing)
	world.network_authority.peer_factions[world.multiplayer.get_unique_id()] = team
	world.match_manager.switch_faction(team)
	_client_faction_selected = false
	_finish_deployment(id, team, loadout)
