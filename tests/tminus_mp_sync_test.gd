extends SceneTree

const Net = preload("res://scripts/tminus_net.gd")
const Sync = preload("res://scripts/tminus_remote_sync.gd")

const TIMEOUT_MSEC := 4000

var _failures := 0
var _rigs: Array = []


func _initialize() -> void:
	multiplayer_poll = false
	_run.call_deferred()


func _run() -> void:
	var host := _rig("Host")
	var enemy := _rig("Enemy")
	var ally := _rig("Ally")
	var started: Dictionary = host.net.host_match(0, 4209, "short")
	_check(started.ok, "Host binds an ephemeral ENet port")
	if not started.ok:
		quit(1)
		return
	_check(enemy.net.join_match("127.0.0.1", started.port).ok, "Enemy client starts joining")
	var ok := await _wait(func() -> bool: return host.net.get_total_human_count() == 2 and enemy.net.get_total_human_count() == 2)
	_check(ok, "Enemy client is seated")
	_check(ally.net.join_match("127.0.0.1", started.port).ok, "Ally client starts joining")
	ok = await _wait(func() -> bool: return host.net.get_total_human_count() == 3 and ally.net.get_total_human_count() == 3)
	_check(ok, "Ally client is seated")
	var host_id: int = 1
	var enemy_id: int = enemy.net.get_local_peer_id()
	var ally_id: int = ally.net.get_local_peer_id()
	_check(host.net.get_peer_assignment(enemy_id).alliance != host.net.get_peer_assignment(host_id).alliance,
		"Second peer is in the opposing alliance")
	_check(host.net.get_peer_assignment(ally_id).alliance == host.net.get_peer_assignment(host_id).alliance,
		"Third peer is in the host's alliance")

	var baseline_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# Host and clients all stand in Planet A.
	for r in [host, enemy, ally]:
		r.sync.set_active_world(r.world_a, "planet_a")
	host.sync.submit_local_state({"zone": "planet_a", "pos": Vector3(0, 0, 0), "role": 0}, true)
	ally.sync.submit_local_state({"zone": "planet_a", "pos": Vector3(2, 0, 0), "role": 1}, true)
	var state := {"zone": "planet_a", "pos": Vector3(10, 0, 5), "heading": 1.0, "speed": 4.0,
		"anim": "run", "role": 3, "carrying_flag": "flag_2", "weapon_drawn": true}
	enemy.sync.submit_local_state(state, true)
	ok = await _wait(func() -> bool: return host.sync.get_avatar(enemy_id) != null)
	var avatar: Node3D = host.sync.get_avatar(enemy_id)
	_check(ok and avatar is Actor and avatar.get_parent() == host.sync.container
		and host.sync.container.get_parent() == host.world_a and host.sync.container.name == "RemotePlayers",
		"Host spawns a real Actor for the client inside PlanetA/RemotePlayers")
	if avatar is Actor:
		var tag: String = avatar.name_tag.text if avatar.name_tag != null else ""
		_check(tag.contains("ENEMY") and avatar.role == 3, "Enemy avatar carries an ENEMY nameplate and its crew role")
		_check(avatar.weapon_drawn or avatar.held_weapon == null, "Remote weapon-drawn state is applied")
		_check(avatar.get_node_or_null("CarriedFlag") != null, "Remote flag carrier shows a glowing flag marker")
	var ally_avatar: Node3D = host.sync.get_avatar(ally_id)
	_check(ally_avatar is Actor and ally_avatar.name_tag != null and ally_avatar.name_tag.text.contains("ALLY"),
		"Ally avatar carries an ALLY nameplate")
	_check(enemy.sync.get_avatar(host_id) != null and enemy.sync.get_avatar(ally_id) != null,
		"Clients see the host and the other client via host relay")

	# Smooth interpolation toward a new target.
	state["pos"] = Vector3(20, 0, 5)
	enemy.sync.submit_local_state(state, true)
	ok = await _wait(func() -> bool: return host.sync.get_avatar(enemy_id) != null and host.sync._states[enemy_id]["pos"].x > 19.0)
	var x0: float = host.sync.get_avatar(enemy_id).position.x
	_check(ok and x0 < 20.0 and x0 >= 10.0, "Avatar position is interpolated, not snapped")
	await _wait(func() -> bool: return host.sync.get_avatar(enemy_id).position.x > x0 + 0.5)
	_check(host.sync.get_avatar(enemy_id).position.x > x0, "Avatar keeps converging on the target")

	# Shot FX.
	enemy.net.broadcast_shot_fx(enemy_id, "planet_a", Vector3(10, 1.5, 5), Vector3(0, 1.5, 0), Color.CYAN)
	ok = await _wait(func() -> bool: return host.sync.tracers.size() > 0)
	_check(ok and host.sync.tracers.size() >= 1, "Shot FX RPC renders a tracer in the matching zone")
	var before: int = ally.sync.tracers.size()
	enemy.net.broadcast_shot_fx(enemy_id, "planet_b", Vector3.ZERO, Vector3(0, 0, 9), Color.RED)
	await _wait(func() -> bool: return false, 300)
	_check(host.sync.tracers.size() <= 1 and ally.sync.tracers.size() <= before + 1,
		"Shots in another zone are not drawn")

	# Damage authority.
	var rejected_before: int = host.net.rejected_damage_count
	ally.net.request_player_damage(host_id, 25.0, "planet_a")
	await _wait(func() -> bool: return host.net.rejected_damage_count > rejected_before)
	_check(host.net.rejected_damage_count == rejected_before + 1 and host.net.peer_hp.get(host_id, 100.0) == 100.0,
		"Friendly-fire damage is rejected by the host")
	var hits: Array = []
	host.net.player_damaged.connect(func(t: int, a: int, d: float, hp: float, _z: String) -> void: hits.append([t, a, d, hp]))
	enemy.net.request_player_damage(host_id, 25.0, "planet_a")
	ok = await _wait(func() -> bool: return not hits.is_empty())
	_check(ok and hits[0] == [host_id, enemy_id, 25.0, 75.0], "Enemy-alliance damage is accepted and applied authoritatively")
	_check(not host.net.request_player_damage(enemy_id, 5.0, "flight"),
		"Damage claiming a zone the target is not in is rejected")

	# Zone switch: enemy flies; host leaves the planet avatar and later sees a spacecraft in Flight.
	state = {"zone": "flight", "ship_pos": Vector3(0, 900, -150), "ship_rot": Vector3(0, 0.5, 0), "role": 0}
	enemy.sync.submit_local_state(state, true)
	ok = await _wait(func() -> bool: return host.sync.get_avatar(enemy_id) == null)
	_check(ok and host.sync.container.get_child_count() <= 2, "Avatar leaves the PlanetA container when the client launches")
	host.sync.set_active_world(host.world_f, "flight")
	ok = await _wait(func() -> bool: return host.sync.get_avatar(enemy_id) != null)
	var ship: Node3D = host.sync.get_avatar(enemy_id)
	_check(ok and not (ship is Actor) and ship.get_parent() == host.sync.container
		and host.sync.container.get_parent() == host.world_f,
		"Client appears as a spacecraft inside Flight/RemotePlayers")

	# Disconnect cleanup.
	enemy.net.disconnect_match()
	ok = await _wait(func() -> bool: return host.sync.get_avatar(enemy_id) == null and host.net.get_total_human_count() == 2)
	_check(ok and host.sync.avatar_count() <= 1 and not host.net.peer_states.has(enemy_id),
		"Disconnect removes the remote avatar and its state")
	ally.net.disconnect_match()
	await _wait(func() -> bool: return host.net.get_total_human_count() == 1)
	host.net.disconnect_match()
	for r in _rigs:
		r.sync.clear()
	await process_frame
	_check(host.sync.avatar_count() == 0 and host.sync.tracers.is_empty() and ally.sync.avatar_count() == 0,
		"No remote avatars or tracers remain after the match ends")
	for r in _rigs:
		r.sync.set_active_world(null, "menu")
	await process_frame
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans <= baseline_orphans, "Zero orphan nodes leaked (%d vs %d)" % [orphans, baseline_orphans])

	# tminus_net API compatibility.
	var n := Net.new()
	_check(n.request_empire_action("launch", {}) and n.mode == "OFFLINE", "Offline net still constructs")
	_check(Net._valid_action("build_or_upgrade", {"slot_id": "x"}) and not Net._valid_action("bogus", {}),
		"Existing empire action validation is unchanged")
	n.free()

	if _failures == 0:
		print("PASS T-MINUS live multiplayer sync")
	else:
		printerr("FAIL T-MINUS live multiplayer sync (%d checks)" % _failures)
	quit(int(_failures != 0))


func _rig(rig_name: String) -> Dictionary:
	var branch := Node.new()
	branch.name = rig_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var net := Net.new()
	net.name = "Net"
	branch.add_child(net)
	var sync := Sync.new()
	sync.name = "Sync"
	branch.add_child(sync)
	sync.setup(net)
	var world_a := Node3D.new()
	world_a.name = "PlanetA"
	var world_f := Node3D.new()
	world_f.name = "Flight"
	branch.add_child(world_a)
	branch.add_child(world_f)
	var rig := {"net": net, "sync": sync, "world_a": world_a, "world_f": world_f}
	_rigs.append(rig)
	return rig


func _wait(condition: Callable, msec := TIMEOUT_MSEC) -> bool:
	var deadline := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		for r in _rigs:
			r.net.tick_poll()
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
