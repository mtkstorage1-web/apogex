class_name TMinusRemoteSync
extends Node
## Renders remote ENet peers (crew avatars, spacecraft, tracers) inside whichever 3D world Main is showing.
## It owns a "RemotePlayers" child of the active world, so planets and flight need no edits.

const NetScript = preload("res://scripts/tminus_net.gd")
const ALLY_COLOR := Color("#35e6ff")
const ENEMY_COLOR := Color("#ff3355")
const LERP_RATE := 14.0
const TRACER_LIFE := 0.18
const STALE_SECONDS := 6.0

var net: NetScript
var zone := "menu"
var container: Node3D
var local_state: Dictionary = {}
var avatars: Dictionary = {}   # peer_id -> {"node": Node3D, "kind": "actor"|"ship", "target": Vector3, ...}
var tracers: Array = []        # [{"node": Node3D, "life": float}]
var spawned_total := 0
var _states: Dictionary = {}
var _seen: Dictionary = {}     # peer_id -> seconds since the last state


func setup(p_net: NetScript) -> Node:
	net = p_net
	net.peer_state_received.connect(_on_state)
	net.peer_state_removed.connect(_on_removed)
	net.shot_fx_received.connect(_on_shot)
	return self


func set_active_world(world_node: Node3D, zone_name: String) -> void:
	_clear_avatars()
	_clear_tracers()
	if is_instance_valid(container):
		if container.get_parent() != null:
			container.get_parent().remove_child(container)
		container.free()
	container = null
	zone = zone_name
	if world_node == null or not is_instance_valid(world_node):
		return
	container = Node3D.new()
	container.name = "RemotePlayers"
	world_node.add_child(container)
	for pid in _states:
		_sync_avatar(pid, 0.0, true)


## Main hands over the local sample each frame; this sends it at the net's 20 Hz throttle.
func submit_local_state(state: Dictionary, force := false) -> void:
	if net == null or not net.is_online():
		return
	local_state = state
	state["zone"] = zone if not state.has("zone") else state["zone"]
	net.send_local_state(state, force)


func avatar_count() -> int:
	return avatars.size()


func get_avatar(peer_id: int) -> Node3D:
	var entry: Dictionary = avatars.get(peer_id, {})
	return entry.get("node") if not entry.is_empty() else null


func clear() -> void:
	_clear_avatars()
	_clear_tracers()
	_states.clear()
	_seen.clear()


func _exit_tree() -> void:
	if is_instance_valid(container) and container.get_parent() != null:
		container.get_parent().remove_child(container)
		container.free()


func _process(dt: float) -> void:
	if net == null or not net.is_online():
		if not avatars.is_empty() or not tracers.is_empty() or not _states.is_empty():
			clear()
		return
	for pid in _seen.keys():
		_seen[pid] += dt
		if _seen[pid] > STALE_SECONDS:
			_on_removed(pid)
	for pid in avatars.keys():
		_sync_avatar(pid, dt, false)
	for i in range(tracers.size() - 1, -1, -1):
		var t: Dictionary = tracers[i]
		t["life"] -= dt
		if t["life"] <= 0.0 or not is_instance_valid(t["node"]):
			if is_instance_valid(t["node"]):
				t["node"].free()
			tracers.remove_at(i)
		else:
			var mi: MeshInstance3D = t["node"]
			var mat := mi.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color.a = clampf(t["life"] / TRACER_LIFE, 0.0, 1.0)


func _on_state(peer_id: int, state: Dictionary) -> void:
	if net == null or peer_id == net.get_local_peer_id():
		return
	_states[peer_id] = state
	_seen[peer_id] = 0.0
	_sync_avatar(peer_id, 0.0, false)


func _on_removed(peer_id: int) -> void:
	_states.erase(peer_id)
	_seen.erase(peer_id)
	_free_avatar(peer_id)


func _wanted_kind(state: Dictionary) -> String:
	if container == null or not is_instance_valid(container):
		return ""
	var z: String = state.get("zone", "menu")
	if z != zone:
		return ""
	return "ship" if z == "flight" else ("actor" if z in ["planet_a", "planet_b", "planet_c"] else "")


func _sync_avatar(peer_id: int, dt: float, snap: bool) -> void:
	var state: Dictionary = _states.get(peer_id, {})
	var kind := _wanted_kind(state) if not state.is_empty() else ""
	var entry: Dictionary = avatars.get(peer_id, {})
	if kind == "" or (not entry.is_empty() and entry["kind"] != kind):
		_free_avatar(peer_id)
		entry = {}
	if kind == "":
		return
	if entry.is_empty():
		entry = _spawn(peer_id, kind, state)
		if entry.is_empty():
			return
		avatars[peer_id] = entry
		snap = true
	var node: Node3D = entry["node"]
	var weight := 1.0 if snap else clampf(dt * LERP_RATE, 0.0, 1.0)
	if kind == "actor":
		var actor: Actor = node as Actor
		var target: Vector3 = state["pos"]
		node.position = target if snap else node.position.lerp(target, weight)
		actor.heading = lerp_angle(actor.heading, float(state["heading"]), weight)
		node.rotation.y = actor.heading
		var carrying: bool = String(state["carrying_flag"]) != ""
		actor.set_weapon_drawn(bool(state["weapon_drawn"]))
		actor.animate(dt, float(state["speed"]), String(state["anim"]), carrying)
		_update_flag_marker(entry, carrying)
	else:
		var sp: Vector3 = state["ship_pos"]
		var rot: Vector3 = state["ship_rot"]
		var space := container.get_parent().get_parent() if container.get_parent() != null else null
		if space is Node3D:   # flight worlds move inside the universe, so place ships in universe space
			sp = (space as Node3D).to_global(sp)
			node.global_position = sp if snap else node.global_position.lerp(sp, weight)
		else:
			node.position = sp if snap else node.position.lerp(sp, weight)
		var q := Basis.from_euler(rot).get_rotation_quaternion()
		node.quaternion = q if snap else node.quaternion.slerp(q, weight)
	entry["target"] = state["pos"] if kind == "actor" else state["ship_pos"]


func _faction(peer_id: int) -> Dictionary:
	var mine := net.get_peer_assignment(net.get_local_peer_id())
	var theirs := net.get_peer_assignment(peer_id)
	var ally: bool = not mine.is_empty() and not theirs.is_empty() and mine.alliance == theirs.alliance
	var nick := String(theirs.get("display_name", "Player %d" % peer_id))
	return {"ally": ally, "color": ALLY_COLOR if ally else ENEMY_COLOR,
		"tag": "[%s · %s]" % ["ALLY" if ally else "ENEMY", nick.to_upper()]}


func _spawn(peer_id: int, kind: String, state: Dictionary) -> Dictionary:
	var f := _faction(peer_id)
	var col: Color = f["color"]
	var role := clampi(int(state["role"]), 0, Sim.SPECIALISTS.size() - 1)
	var node: Node3D
	var entry := {"kind": kind, "flag": null}
	if kind == "actor":
		var actor := Actor.new()
		actor.name = "Remote_%d" % peer_id
		container.add_child(actor)
		actor.setup(Sim.SPECIALISTS[role]["model"], role, col, f["tag"], col)
		actor.install_weapon()
		node = actor
	else:
		node = Node3D.new()
		node.name = "RemoteShip_%d" % peer_id
		container.add_child(node)
		var asset := "vehicles/helion_fighter.glb" if f["ally"] else "vehicles/cinder_fighter.glb"
		var hull := BlenderVisualUpgrades.model(asset, 6.0, false)
		if hull == null:
			hull = Node3D.new()
			hull.add_child(Gfx.sphere(1.4, col, Vector3.ZERO, 0.6, 12))
			hull.add_child(Gfx.box(Vector3(5.0, 0.2, 1.6), col.darkened(0.3), Vector3.ZERO, 0.4))
		node.add_child(hull)
		var ring := Gfx.ring(4.2, 0.18, col, 0.8)
		ring.rotation.x = PI * 0.5
		node.add_child(ring)
		var label := Gfx.label(f["tag"], col.lightened(0.28), 32, 8)
		label.fixed_size = true
		label.pixel_size = 0.0012
		label.position.y = 4.0
		node.add_child(label)
	entry["node"] = node
	spawned_total += 1
	return entry


func _update_flag_marker(entry: Dictionary, carrying: bool) -> void:
	var marker: Node3D = entry["flag"]
	if carrying and marker == null:
		marker = Node3D.new()
		marker.name = "CarriedFlag"
		marker.add_child(Gfx.sphere(0.3, Color("#ffd23a"), Vector3.ZERO, 3.0, 10))
		marker.add_child(Gfx.box(Vector3(0.7, 0.45, 0.05), Color("#ffe27a"), Vector3(0.38, 0.1, 0), 2.0))
		marker.position = Vector3(0, Actor.HEIGHT + 1.35, 0)
		entry["node"].add_child(marker)
		entry["flag"] = marker
	elif not carrying and marker != null:
		marker.free()
		entry["flag"] = null


func _on_shot(peer_id: int, shot_zone: String, origin: Vector3, hit_pos: Vector3, color: Color) -> void:
	if shot_zone != zone or container == null or not is_instance_valid(container):
		return
	if peer_id == net.get_local_peer_id():
		return
	var length := origin.distance_to(hit_pos)
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Tracer_%d" % peer_id
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = length
	cyl.radial_segments = 6
	mi.mesh = cyl
	mi.material_override = Gfx.unshaded(color, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	container.add_child(mi)
	var mid := (origin + hit_pos) * 0.5
	var dir := (hit_pos - origin) / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	# CylinderMesh runs along local Y, so rotate the look basis from -Z onto Y.
	mi.transform = Transform3D(basis * Basis(Vector3.RIGHT, -PI * 0.5), mid)
	tracers.append({"node": mi, "life": TRACER_LIFE})


func _free_avatar(peer_id: int) -> void:
	var entry: Dictionary = avatars.get(peer_id, {})
	if entry.is_empty():
		return
	avatars.erase(peer_id)
	var node: Node3D = entry["node"]
	if is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


func _clear_avatars() -> void:
	for pid in avatars.keys():
		_free_avatar(pid)


func _clear_tracers() -> void:
	for t in tracers:
		if is_instance_valid(t["node"]):
			t["node"].free()
	tracers.clear()
