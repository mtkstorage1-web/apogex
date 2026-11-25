class_name TMinusNet
extends Node

signal session_changed(new_mode: String)
signal roster_updated(roster_snap: Dictionary)
signal world_snapshot_received(empire_snap: Dictionary)
signal action_resolved(action_type: String, payload: Dictionary, result: Dictionary)
signal action_requested(peer_id: int, action_type: String, payload: Dictionary)
signal peer_state_received(peer_id: int, state: Dictionary)
signal peer_state_removed(peer_id: int)
signal shot_fx_received(peer_id: int, zone: String, origin: Vector3, hit_pos: Vector3, color: Color)
signal player_damaged(target_peer_id: int, attacker_peer_id: int, damage: float, hp: float, zone: String)

const MAX_PLAYERS := 32
const ALLIANCE_SQUADS := {
	"planet_a": ["orange", "cyan", "violet", "lime"],
	"planet_b": ["crimson", "amber", "obsidian", "cobalt"],
}
const ROLES := ["PILOT", "ENGINEER", "GUNNER", "RAIDER"]
const DEFAULT_PORT := 24567

const SPECIALISTS := ["Finn", "Chip", "Barbara", "Fernando"]
const SERVER_ID := 1
const ZONES := ["planet_a", "flight", "planet_b", "planet_c", "menu"]
const STATE_INTERVAL_MSEC := 50   # 20 Hz
const MAX_HP := 100.0
const MAX_DAMAGE := 60.0
const MAX_COORD := 1.0e7
const DEFAULT_SEED := 4209
const DEFAULT_PRESET := "standard"

var mode: String = "OFFLINE"
var world_seed: int = DEFAULT_SEED
var match_preset: String = DEFAULT_PRESET
var roster: Dictionary = _make_bot_roster()

var _session_api: MultiplayerAPI
var _previous_peer: MultiplayerPeer
var _enet_peer: ENetMultiplayerPeer
var peer_states: Dictionary = {}   # peer_id -> last validated state (host: all peers, client: relayed)
var peer_hp: Dictionary = {}       # host-authoritative hit points per peer
var rejected_damage_count := 0
var _last_state_send_msec := -STATE_INTERVAL_MSEC


func _exit_tree() -> void:
	_end_session()


func host_match(port: int = DEFAULT_PORT, seed_val: int = DEFAULT_SEED,
		preset: String = DEFAULT_PRESET) -> Dictionary:
	var error := _session_start_error()
	if error == OK and (port < 0 or port > 65535):
		error = ERR_INVALID_PARAMETER
	if error != OK:
		return {"ok": false, "error": error, "port": port}

	var peer := ENetMultiplayerPeer.new()
	error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return {"ok": false, "error": error, "port": port}

	var bound_port := peer.get_host().get_local_port()
	_start_session(peer, "HOST")
	world_seed = seed_val
	match_preset = preset
	assign_peer(SERVER_ID, "", -1, "Host")
	if is_host():
		session_changed.emit(mode)
	return {"ok": true, "error": OK, "port": bound_port}


func join_match(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Dictionary:
	var error := _session_start_error()
	if error == OK and (address.strip_edges().is_empty() or port < 1 or port > 65535):
		error = ERR_INVALID_PARAMETER
	if error != OK:
		return {"ok": false, "error": error}

	var peer := ENetMultiplayerPeer.new()
	error = peer.create_client(address.strip_edges(), port)
	if error != OK:
		return {"ok": false, "error": error}

	_start_session(peer, "CLIENT")
	_publish_roster()
	if mode == "CLIENT":
		session_changed.emit(mode)
	return {"ok": true, "error": OK}


func disconnect_match() -> void:
	if not is_online():
		return
	_end_session()
	_publish_roster()
	if mode == "OFFLINE":
		session_changed.emit(mode)


func is_host() -> bool:
	return mode == "HOST"


func is_online() -> bool:
	return mode != "OFFLINE"


func get_status_text() -> String:
	if mode == "CLIENT" and not _transport_connected():
		return "CLIENT (connecting)"
	return mode


func assign_peer(peer_id: int, preferred_alliance: String = "", preferred_role: int = -1,
		display_name: String = "") -> Dictionary:
	if mode == "CLIENT":
		return {"ok": false, "error": ERR_UNAUTHORIZED}
	if peer_id <= 0:
		return {"ok": false, "error": ERR_INVALID_PARAMETER}
	var existing := get_peer_assignment(peer_id)
	if not existing.is_empty():
		existing.merge({"ok": true, "error": OK})
		return existing

	var planet_a_count := get_alliance_human_count("planet_a")
	var planet_b_count := get_alliance_human_count("planet_b")
	if planet_a_count + planet_b_count >= MAX_PLAYERS:
		return {"ok": false, "error": ERR_UNAVAILABLE}
	var alliance := "planet_a" if planet_a_count <= planet_b_count else "planet_b"
	if planet_a_count == planet_b_count and ALLIANCE_SQUADS.has(preferred_alliance):
		alliance = preferred_alliance

	var choice := _find_open_seat(alliance, preferred_role)
	var seat: Dictionary = roster[choice.squad_id][choice.seat_index]
	seat.peer_id = peer_id
	var player_name := display_name.strip_edges()
	seat.display_name = player_name if not player_name.is_empty() else "Player %d" % peer_id
	var assignment := get_peer_assignment(peer_id)
	assignment.merge({"ok": true, "error": OK})
	_publish_roster()
	return assignment


func unassign_peer(peer_id: int) -> void:
	if mode == "CLIENT":
		return
	var assignment := get_peer_assignment(peer_id)
	if assignment.is_empty():
		return
	roster[assignment.squad_id][assignment.seat_index] = _make_bot_seat(
		assignment.alliance, assignment.seat_index
	)
	_publish_roster()


func get_peer_assignment(peer_id: int) -> Dictionary:
	if peer_id <= 0:
		return {}
	for squad_id in roster:
		for seat: Dictionary in roster[squad_id]:
			if seat.peer_id == peer_id:
				var assignment := seat.duplicate()
				assignment.squad_id = squad_id
				return assignment
	return {}


func get_alliance_human_count(alliance: String) -> int:
	var count := 0
	for squad_id in ALLIANCE_SQUADS.get(alliance, []):
		for seat: Dictionary in roster[squad_id]:
			count += int(seat.peer_id > 0)
	return count


func get_total_human_count() -> int:
	return get_alliance_human_count("planet_a") + get_alliance_human_count("planet_b")


func get_roster_snapshot() -> Dictionary:
	return roster.duplicate(true)


func apply_roster_snapshot(snap: Dictionary) -> void:
	var next_roster := _make_bot_roster()
	if snap.size() != next_roster.size():
		return
	var occupied_peers := {}
	for squad_id in next_roster:
		var seats: Variant = snap.get(squad_id)
		if not (seats is Array) or seats.size() != ROLES.size():
			return
		for index in ROLES.size():
			var seat: Variant = seats[index]
			var canonical: Dictionary = next_roster[squad_id][index]
			if not (seat is Dictionary) or not seat.has_all(canonical.keys()):
				return
			if (seat.seat_index != index or seat.role != canonical.role
					or seat.specialist != canonical.specialist or seat.alliance != canonical.alliance):
				return
			if not (seat.peer_id is int and seat.display_name is String and seat.ready is bool):
				return
			if seat.peer_id != -1:
				if seat.peer_id <= 0 or occupied_peers.has(seat.peer_id):
					return
				occupied_peers[seat.peer_id] = true
			canonical.peer_id = seat.peer_id
			canonical.display_name = seat.display_name
			canonical.ready = seat.ready
	roster = next_roster
	_publish_roster()


func broadcast_world_snapshot(empire_snap: Dictionary) -> void:
	if is_host() and not _session_api.get_peers().is_empty():
		_receive_world_snapshot.rpc(empire_snap)


func send_action_result(peer_id: int, action_type: String, payload: Dictionary, result: Dictionary) -> void:
	if is_host() and peer_id != SERVER_ID:
		_receive_action_result.rpc_id(peer_id, action_type, payload, result)


@rpc("authority", "call_remote", "reliable")
func _receive_action_result(action_type: String, payload: Dictionary, result: Dictionary) -> void:
	if mode == "CLIENT":
		action_resolved.emit(action_type, payload, result)


func request_empire_action(action_type: String, payload: Dictionary) -> bool:
	if not _valid_action(action_type, payload):
		return false
	if mode == "CLIENT":
		return _transport_connected() and rpc_id(
			SERVER_ID, &"_receive_empire_action", action_type, payload
		) == OK
	action_requested.emit(SERVER_ID, action_type, payload.duplicate(true))
	return true


func tick_poll() -> void:
	# The scene API polls ENet and dispatches high-level RPCs.
	if _session_api != null:
		_session_api.poll()


func _session_start_error() -> Error:
	if not is_inside_tree():
		return ERR_UNCONFIGURED
	var peer := multiplayer.multiplayer_peer
	if is_online() or (peer != null and not (peer is OfflineMultiplayerPeer)):
		return ERR_ALREADY_IN_USE
	return OK


func _start_session(peer: ENetMultiplayerPeer, new_mode: String) -> void:
	_session_api = multiplayer
	_previous_peer = _session_api.multiplayer_peer
	_enet_peer = peer
	mode = new_mode
	roster = _make_bot_roster()
	_session_api.peer_connected.connect(_on_peer_connected)
	_session_api.peer_disconnected.connect(_on_peer_disconnected)
	_session_api.connection_failed.connect(_on_connection_lost)
	_session_api.server_disconnected.connect(_on_connection_lost)
	_session_api.multiplayer_peer = peer


func _end_session() -> void:
	if _session_api == null:
		return
	_session_api.peer_connected.disconnect(_on_peer_connected)
	_session_api.peer_disconnected.disconnect(_on_peer_disconnected)
	_session_api.connection_failed.disconnect(_on_connection_lost)
	_session_api.server_disconnected.disconnect(_on_connection_lost)
	if _session_api.multiplayer_peer == _enet_peer:
		_session_api.multiplayer_peer = _previous_peer
	_enet_peer.close()
	_enet_peer = null
	_previous_peer = null
	_session_api = null
	mode = "OFFLINE"
	world_seed = DEFAULT_SEED
	match_preset = DEFAULT_PRESET
	roster = _make_bot_roster()
	for pid in peer_states.keys():
		peer_state_removed.emit(pid)
	peer_states.clear()
	peer_hp.clear()


func _transport_connected() -> bool:
	return _enet_peer != null and (
		_enet_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)


func _on_peer_connected(peer_id: int) -> void:
	if not is_host():
		return
	if not get_peer_assignment(peer_id).is_empty():
		_receive_roster.rpc_id(peer_id, get_roster_snapshot(), world_seed, match_preset)
		return
	if not assign_peer(peer_id).ok:
		_enet_peer.disconnect_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if is_host():
		unassign_peer(peer_id)
		_drop_peer_state(peer_id)
		if not _session_api.get_peers().is_empty():
			_receive_peer_left.rpc(peer_id)


func _on_connection_lost() -> void:
	# Let SceneMultiplayer finish its poll before replacing its peer.
	_finish_connection_loss.call_deferred(_enet_peer)


func _finish_connection_loss(lost_peer: ENetMultiplayerPeer) -> void:
	if _enet_peer == lost_peer:
		disconnect_match()


func _publish_roster() -> void:
	var snapshot := get_roster_snapshot()
	if is_host() and not _session_api.get_peers().is_empty():
		_receive_roster.rpc(snapshot, world_seed, match_preset)
	roster_updated.emit(snapshot)


func _find_open_seat(alliance: String, preferred_role: int) -> Dictionary:
	var role_counts := [0, 0, 0, 0]
	for squad_id in ALLIANCE_SQUADS[alliance]:
		for seat: Dictionary in roster[squad_id]:
			role_counts[seat.seat_index] += int(seat.peer_id > 0)

	var best_score := MAX_PLAYERS
	var choice := {}
	for squad_id in ALLIANCE_SQUADS[alliance]:
		var seats: Array = roster[squad_id]
		var squad_count := 0
		for seat: Dictionary in seats:
			squad_count += int(seat.peer_id > 0)
		for seat: Dictionary in seats:
			if seat.peer_id != -1:
				continue
			var score: int = squad_count * ROLES.size() + role_counts[seat.seat_index]
			# A vacant preferred role wins, then spread people among squads and roles.
			if seat.seat_index == preferred_role:
				score -= MAX_PLAYERS
			if score < best_score:
				best_score = score
				choice = {"squad_id": squad_id, "seat_index": seat.seat_index}
	return choice


static func _make_bot_roster() -> Dictionary:
	var result := {}
	for alliance in ALLIANCE_SQUADS:
		for squad_id in ALLIANCE_SQUADS[alliance]:
			var seats: Array = []
			for index in ROLES.size():
				seats.append(_make_bot_seat(alliance, index))
			result[squad_id] = seats
	return result


static func _make_bot_seat(alliance: String, index: int) -> Dictionary:
	return {
		"seat_index": index,
		"role": ROLES[index],
		"specialist": SPECIALISTS[index],
		"peer_id": -1,
		"display_name": SPECIALISTS[index],
		"alliance": alliance,
		"ready": false,
	}


static func _valid_action(action_type: String, payload: Dictionary) -> bool:
	# The simulation owns gameplay rules. The bridge checks the request shape and sender.
	match action_type:
		"build_or_upgrade", "repair", "sabotage_start", "sabotage_cancel", "sabotage", "sabotage_structure", "damage_structure":
			return _has_action_id(payload, "slot_id")
		"capture", "capture_flag", "record_flag_captured", "deliver", "deliver_flag", "record_flag_delivered", "drop_flag":
			return _has_action_id(payload, "flag_id")
		"launch", "squad_stage":
			return true
		_:
			return false


static func _has_action_id(payload: Dictionary, key: String) -> bool:
	var value: Variant = payload.get(key)
	return value is String and not value.strip_edges().is_empty()


@rpc("authority", "call_remote", "reliable")
func _receive_roster(snap: Dictionary, seed_val: int, preset: String) -> void:
	if mode == "CLIENT":
		world_seed = seed_val
		match_preset = preset
		apply_roster_snapshot(snap)


@rpc("authority", "call_remote", "reliable")
func _receive_world_snapshot(empire_snap: Dictionary) -> void:
	if mode == "CLIENT":
		world_snapshot_received.emit(empire_snap)


@rpc("any_peer", "call_remote", "reliable")
func _receive_empire_action(action_type: String, payload: Dictionary) -> void:
	if not is_host() or not _valid_action(action_type, payload):
		return
	var peer_id := _session_api.get_remote_sender_id()
	if peer_id <= SERVER_ID:
		return
	var assignment := get_peer_assignment(peer_id)
	if assignment.is_empty() or payload.get("peer_id", peer_id) != peer_id:
		return
	for key in ["squad_id", "by_squad", "attacker_squad"]:
		if payload.get(key, assignment.squad_id) != assignment.squad_id:
			return
	if action_type == "build_or_upgrade" and payload.get("alliance", assignment.alliance) != assignment.alliance:
		return
	action_requested.emit(peer_id, action_type, payload)


# ============================================================================
# Live avatar / ship / combat replication
# ============================================================================
## Sends the local peer's state at 20 Hz. Clients go to the host, which validates and relays.
func send_local_state(state: Dictionary, force := false) -> bool:
	if not is_online() or _session_api == null:
		return false
	var now := Time.get_ticks_msec()
	if not force and now - _last_state_send_msec < STATE_INTERVAL_MSEC:
		return false
	_last_state_send_msec = now
	if mode == "CLIENT":
		return _transport_connected() and rpc_id(SERVER_ID, &"_receive_peer_state", state) == OK
	_ingest_peer_state(SERVER_ID, state)
	return true


func get_local_peer_id() -> int:
	return _session_api.get_unique_id() if _session_api != null else SERVER_ID


## Replicates a visible blaster / turret tracer to every other peer.
func broadcast_shot_fx(_peer_id: int, zone: String, origin: Vector3, hit_pos: Vector3,
		color: Color = Color.WHITE) -> bool:
	if not is_online() or not ZONES.has(zone) or not _finite_vec(origin) or not _finite_vec(hit_pos):
		return false
	if mode == "CLIENT":
		return _transport_connected() and rpc_id(
			SERVER_ID, &"_receive_shot_fx", zone, origin, hit_pos, color) == OK
	_relay_shot_fx(SERVER_ID, zone, origin, hit_pos, color)
	return true


## Asks the host to damage another peer. The host rejects friendly fire and bad data.
func request_player_damage(target_peer_id: int, damage: float, zone: String) -> bool:
	if not is_online():
		return false
	if mode == "CLIENT":
		return _transport_connected() and rpc_id(
			SERVER_ID, &"_receive_damage_request", target_peer_id, damage, zone) == OK
	return _apply_damage(SERVER_ID, target_peer_id, damage, zone)


static func _finite_vec(v: Vector3) -> bool:
	return v.is_finite() and maxf(maxf(absf(v.x), absf(v.y)), absf(v.z)) < MAX_COORD


static func sanitize_state(peer_id: int, raw: Dictionary) -> Dictionary:
	var zone := String(raw.get("zone", "menu"))
	if not ZONES.has(zone):
		zone = "menu"
	var out := {
		"peer_id": peer_id,
		"zone": zone,
		"pos": Vector3.ZERO,
		"heading": 0.0,
		"speed": 0.0,
		"anim": String(raw.get("anim", "idle")).left(24),
		"role": clampi(int(raw.get("role", 0)), 0, ROLES.size() - 1),
		"carrying_flag": String(raw.get("carrying_flag", "")).left(32),
		"weapon_drawn": bool(raw.get("weapon_drawn", false)),
		"ship_pos": Vector3.ZERO,
		"ship_rot": Vector3.ZERO,
		"hp": clampf(float(raw.get("hp", MAX_HP)), 0.0, MAX_HP) if is_finite(float(raw.get("hp", MAX_HP))) else MAX_HP,
	}
	for key in ["pos", "ship_pos", "ship_rot"]:
		var v: Variant = raw.get(key, Vector3.ZERO)
		if v is Vector3 and _finite_vec(v):
			out[key] = v
	for key in ["heading", "speed"]:
		var f := float(raw.get(key, 0.0))
		out[key] = f if is_finite(f) and absf(f) < MAX_COORD else 0.0
	return out


func _ingest_peer_state(peer_id: int, raw: Dictionary) -> void:
	var state := sanitize_state(peer_id, raw)
	if peer_id == SERVER_ID or not peer_hp.has(peer_id):
		peer_hp[peer_id] = peer_hp.get(peer_id, MAX_HP)
	peer_states[peer_id] = state
	peer_state_received.emit(peer_id, state)
	if _session_api == null:
		return
	for other in _session_api.get_peers():
		if other != peer_id:
			_relay_peer_state.rpc_id(other, state)


func _drop_peer_state(peer_id: int) -> void:
	peer_hp.erase(peer_id)
	if peer_states.erase(peer_id):
		peer_state_removed.emit(peer_id)


func _relay_shot_fx(peer_id: int, zone: String, origin: Vector3, hit_pos: Vector3, color: Color) -> void:
	shot_fx_received.emit(peer_id, zone, origin, hit_pos, color)
	for other in _session_api.get_peers():
		if other != peer_id:
			_receive_shot_fx_relay.rpc_id(other, peer_id, zone, origin, hit_pos, color)


func _apply_damage(attacker: int, target: int, damage: float, zone: String) -> bool:
	var a := get_peer_assignment(attacker)
	var t := get_peer_assignment(target)
	var ok: bool = not a.is_empty() and not t.is_empty() and attacker != target \
		and is_finite(damage) and damage > 0.0 and ZONES.has(zone) \
		and a.alliance != t.alliance
	if ok:
		for pid in [attacker, target]:
			var known: Dictionary = peer_states.get(pid, {})
			if not known.is_empty() and known.zone != zone:
				ok = false
	if not ok:
		rejected_damage_count += 1
		return false
	var hp := maxf(0.0, float(peer_hp.get(target, MAX_HP)) - minf(damage, MAX_DAMAGE))
	peer_hp[target] = hp
	player_damaged.emit(target, attacker, minf(damage, MAX_DAMAGE), hp, zone)
	for other in _session_api.get_peers():
		_receive_player_hp.rpc_id(other, target, attacker, minf(damage, MAX_DAMAGE), hp, zone)
	if hp <= 0.0:
		peer_hp[target] = MAX_HP   # respawn pool refills once the knockout was broadcast
	return true


@rpc("any_peer", "call_remote", "unreliable")
func _receive_peer_state(state: Dictionary) -> void:
	if not is_host():
		return
	var sender := _session_api.get_remote_sender_id()
	if sender <= SERVER_ID or get_peer_assignment(sender).is_empty():
		return
	_ingest_peer_state(sender, state)


@rpc("authority", "call_remote", "unreliable")
func _relay_peer_state(state: Dictionary) -> void:
	if mode != "CLIENT":
		return
	var pid := int(state.get("peer_id", 0))
	if pid <= 0 or pid == get_local_peer_id():
		return
	var clean := sanitize_state(pid, state)
	peer_states[pid] = clean
	peer_state_received.emit(pid, clean)


@rpc("authority", "call_remote", "reliable")
func _receive_peer_left(peer_id: int) -> void:
	if mode == "CLIENT":
		_drop_peer_state(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _receive_shot_fx(zone: String, origin: Vector3, hit_pos: Vector3, color: Color) -> void:
	if not is_host() or not ZONES.has(zone) or not _finite_vec(origin) or not _finite_vec(hit_pos):
		return
	var sender := _session_api.get_remote_sender_id()
	if sender <= SERVER_ID or get_peer_assignment(sender).is_empty():
		return
	_relay_shot_fx(sender, zone, origin, hit_pos, color)


@rpc("authority", "call_remote", "reliable")
func _receive_shot_fx_relay(peer_id: int, zone: String, origin: Vector3, hit_pos: Vector3, color: Color) -> void:
	if mode == "CLIENT" and ZONES.has(zone) and _finite_vec(origin) and _finite_vec(hit_pos):
		shot_fx_received.emit(peer_id, zone, origin, hit_pos, color)


@rpc("any_peer", "call_remote", "reliable")
func _receive_damage_request(target_peer_id: int, damage: float, zone: String) -> void:
	if not is_host():
		return
	var sender := _session_api.get_remote_sender_id()
	if sender <= SERVER_ID:
		return
	_apply_damage(sender, target_peer_id, damage, zone)


@rpc("authority", "call_remote", "reliable")
func _receive_player_hp(target: int, attacker: int, damage: float, hp: float, zone: String) -> void:
	if mode == "CLIENT":
		peer_hp[target] = hp
		player_damaged.emit(target, attacker, damage, hp, zone)
