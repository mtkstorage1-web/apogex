extends SceneTree

const Net := preload("res://scripts/tminus_net.gd")
const TIMEOUT_MSEC := 3000

var _failures := 0


func _initialize() -> void:
	multiplayer_poll = false
	_run.call_deferred()


func _run() -> void:
	_test_roster()
	var host := _add_endpoint("HostBranch")
	var client := _add_endpoint("ClientBranch")
	await _test_loopback(host, client)
	client.disconnect_match()
	host.disconnect_match()
	if _failures == 0:
		print("PASS T-MINUS ENet session and roster authority")
	else:
		printerr("FAIL T-MINUS ENet session and roster authority (%d checks)" % _failures)
	quit(int(_failures != 0))


func _test_roster() -> void:
	var net := Net.new()
	var initial := net.get_roster_snapshot()
	var alliances := {
		"planet_a": ["orange", "cyan", "violet", "lime"],
		"planet_b": ["crimson", "amber", "obsidian", "cobalt"],
	}
	var roles := ["PILOT", "ENGINEER", "GUNNER", "RAIDER"]
	var specialists := ["Finn", "Chip", "Barbara", "Fernando"]
	var valid_topology := initial.size() == 8 and net.get_total_human_count() == 0
	for alliance in alliances:
		for squad_id in alliances[alliance]:
			var seats: Array = initial.get(squad_id, [])
			valid_topology = valid_topology and seats.size() == 4
			for index in seats.size():
				var seat: Dictionary = seats[index]
				valid_topology = valid_topology and (
					seat.seat_index == index and seat.role == roles[index]
					and seat.specialist == specialists[index] and seat.peer_id == -1
					and seat.alliance == alliance and not seat.ready
				)
	_check(valid_topology, "Eight four-specialist squads start with 32 AI seats")

	var preferred := net.assign_peer(1, "planet_b", 3, "Test Raider")
	_check(preferred.get("ok", false) and preferred.get("alliance") == "planet_b"
		and preferred.get("role") == "RAIDER" and preferred.get("display_name") == "Test Raider",
		"Assignment honors a role and an alliance preference when balanced")
	_check(net.assign_peer(1) == preferred and net.get_total_human_count() == 1,
		"Assigning an existing peer keeps their original seat")
	var balanced := true
	for peer_id in range(2, 33):
		var assignment := net.assign_peer(peer_id, "planet_b")
		balanced = balanced and assignment.get("ok", false) and abs(
			net.get_alliance_human_count("planet_a") - net.get_alliance_human_count("planet_b")
		) <= 1
	var full := net.get_roster_snapshot()
	var occupied := {}
	for squad_id in full:
		for seat: Dictionary in full[squad_id]:
			var peer_id: int = seat.peer_id
			balanced = balanced and peer_id > 0 and not occupied.has(peer_id)
			occupied[peer_id] = true
	_check(balanced and occupied.size() == 32 and net.get_alliance_human_count("planet_a") == 16
		and net.get_alliance_human_count("planet_b") == 16,
		"All 32 peers occupy unique seats with a 16 vs 16 split")
	_check(not net.assign_peer(33).ok and net.get_roster_snapshot() == full,
		"The 33rd peer is rejected without changing the roster")

	if preferred.get("ok", false):
		net.unassign_peer(1)
		var restored: Dictionary = net.roster[preferred.squad_id][preferred.seat_index]
		_check(restored == initial[preferred.squad_id][preferred.seat_index]
			and net.get_total_human_count() == 31 and net.get_peer_assignment(1).is_empty(),
			"Unassigning a peer restores the original AI seat")
	net.apply_roster_snapshot(full)
	var copy := net.get_roster_snapshot()
	copy["orange"][0]["display_name"] = "Changed copy"
	_check(net.get_roster_snapshot() == full and copy != full,
		"Roster snapshots round-trip and remain detached from live state")

	var local_actions: Array = []
	net.action_requested.connect(func(peer_id: int, action_type: String, payload: Dictionary) -> void:
		local_actions.append([peer_id, action_type, payload])
	)
	var build := {"slot_id": "refinery"}
	_check(net.request_empire_action("build_or_upgrade", build)
		and local_actions == [[1, "build_or_upgrade", build]] and not net.is_online(),
		"Offline actions emit immediately without a multiplayer peer")
	net.free()


func _add_endpoint(branch_name: String) -> Net:
	# Distinct multiplayer APIs with the same relative RPC node path on both endpoints.
	var branch := Node.new()
	branch.name = branch_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var endpoint := Net.new()
	endpoint.name = "Net"
	branch.add_child(endpoint)
	return endpoint


func _test_loopback(host: Net, client: Net) -> void:
	var client_rosters: Array[Dictionary] = []
	var client_worlds: Array[Dictionary] = []
	var host_actions: Array = []
	var host_modes: Array[String] = []
	var client_modes: Array[String] = []
	client.roster_updated.connect(func(snapshot: Dictionary) -> void: client_rosters.append(snapshot))
	client.world_snapshot_received.connect(func(snapshot: Dictionary) -> void: client_worlds.append(snapshot))
	host.action_requested.connect(func(peer_id: int, action_type: String, payload: Dictionary) -> void:
		host_actions.append([peer_id, action_type, payload])
	)
	host.session_changed.connect(func(new_mode: String) -> void: host_modes.append(new_mode))
	client.session_changed.connect(func(new_mode: String) -> void: client_modes.append(new_mode))

	var started := host.host_match(0, 8675309, "short")
	_check(started.ok and started.port > 0 and host.is_host() and host.get_total_human_count() == 1,
		"ENet binds an ephemeral port and assigns the host a seat")
	if not started.ok or started.port <= 0:
		return
	_check(host.request_empire_action("launch", {}) and host_actions == [[1, "launch", {}]],
		"Listen-host actions emit immediately")
	host_actions.clear()

	var connected := await _connect_client(host, client, started.port)
	_check(connected, "Live ENet loopback synchronizes both human assignments")
	if not connected:
		return
	var client_id := client.multiplayer.get_unique_id()
	var assignment := client.get_peer_assignment(client_id)
	_check(assignment == host.get_peer_assignment(client_id) and assignment.alliance == "planet_b"
		and client_rosters.back() == host.get_roster_snapshot()
		and client.world_seed == host.world_seed and client.match_preset == host.match_preset,
		"Client receives the host's roster, world seed and match preset")
	_check(not client.assign_peer(33).ok and client.get_total_human_count() == 2,
		"Only the host can assign seats in a network session")

	var empire := {
		"clock_remaining": 839.5,
		"scores": {"planet_a": 3, "planet_b": 2},
		"structures": [{"slot_id": "refinery", "tier": 1, "online": true}],
	}
	host.broadcast_world_snapshot(empire)
	var received := await _wait_for(host, client, func() -> bool: return not client_worlds.is_empty())
	_check(received and client_worlds == [empire],
		"The client receives the complete authoritative empire snapshot")

	var build := {
		"alliance": assignment.alliance,
		"slot_id": "refinery",
		"by_squad": assignment.squad_id,
	}
	var spoofed := build.duplicate()
	spoofed.by_squad = "orange"
	var wrong_alliance := build.duplicate()
	wrong_alliance.alliance = "planet_a"
	# Send malformed data directly to exercise the host-side checks independently.
	var malformed_sent := client.rpc_id(1, &"_receive_empire_action", "build_or_upgrade", {}) == OK
	var spoofed_sent := client.request_empire_action("build_or_upgrade", spoofed)
	var wrong_alliance_sent := client.request_empire_action("build_or_upgrade", wrong_alliance)
	var build_sent := client.request_empire_action("build_or_upgrade", build)
	var accepted := await _wait_for(host, client, func() -> bool:
		return [client_id, "build_or_upgrade", build] in host_actions
	)
	_check(malformed_sent and spoofed_sent and wrong_alliance_sent and build_sent
		and accepted and host_actions == [[client_id, "build_or_upgrade", build]],
		"Host validates build requests and attributes the valid RPC to its ENet sender")

	client.disconnect_match()
	var released := await _wait_for(host, client, func() -> bool:
		return host.get_total_human_count() == 1
	)
	_check(released and host.is_host() and host.get_peer_assignment(client_id).is_empty()
		and client.mode == "OFFLINE" and client.get_total_human_count() == 0,
		"A departing client returns its seat to AI and goes offline")

	var reconnected := await _connect_client(host, client, started.port)
	_check(reconnected, "A client can rejoin the same live host")
	host.disconnect_match()
	var closed := await _wait_for(host, client, func() -> bool: return client.mode == "OFFLINE")
	_check(closed and host.mode == "OFFLINE" and not host.is_online() and not client.is_online()
		and host.get_total_human_count() == 0 and client.get_total_human_count() == 0
		and host_modes == ["HOST", "OFFLINE"] and client_modes == ["CLIENT", "OFFLINE", "CLIENT", "OFFLINE"],
		"Host shutdown returns both peers to offline play and clears the assigned seats")


func _connect_client(host: Net, client: Net, port: int) -> bool:
	if not client.join_match("127.0.0.1", port).ok:
		return false
	return await _wait_for(host, client, func() -> bool:
		return host.get_total_human_count() == 2 and client.get_total_human_count() == 2
	)


func _wait_for(host: Net, client: Net, condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		host.tick_poll()
		client.tick_poll()
		if condition.call():
			return true
		await process_frame
	return false


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS " + description)
	else:
		printerr("FAIL " + description)
		_failures += 1
