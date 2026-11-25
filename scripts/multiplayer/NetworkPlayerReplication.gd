extends Node3D

const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Shot = preload("res://scripts/vehicles/Projectile.gd")
const Turret = preload("res://scripts/gameplay/DefenseTurret.gd")
const UPDATE_INTERVAL := 0.05

var world: Node
var avatars := {}
var player_states := {}
var _origin := Vector3.ZERO
var _sample_wait := 0.0
var _projectiles: Array[Dictionary] = []


func setup(context: Node) -> void:
	world = context
	_origin = world.floating_origin.current_origin


func clear() -> void:
	for id in avatars.keys():
		remove_peer(id)
	player_states.clear()
	for entry in _projectiles:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	_projectiles.clear()
	_sample_wait = 0.0


func remove_peer(id: int) -> void:
	if avatars.has(id):
		remove_child(avatars[id])
		avatars[id].queue_free()
		avatars.erase(id)
	player_states.erase(id)


func local_sample() -> Dictionary:
	var player: Node3D = world.explorer
	var vehicle: Node3D = world.get_active_vehicle()
	var model: Node3D = vehicle if vehicle != null else player
	var point: Vector3 = vehicle.get_planet_position() if vehicle != null else player.get_planet_position()
	return {
		"pose": Transform3D(model.global_basis, point),
		"aim": -world._get_view_camera().global_basis.z,
		"tool": world.player_combat.selected_tool,
		"vehicle": vehicle.vehicle_id if vehicle != null else "",
		"velocity": model.velocity,
		"received": Time.get_ticks_msec(),
	}


func network_tick(delta: float) -> void:
	var authority: Node = world.network_authority
	if authority.get_network_mode() == "OFFLINE" or authority.peer_factions.is_empty():
		return
	_sample_wait -= delta
	if _sample_wait > 0.0:
		return
	_sample_wait = UPDATE_INTERVAL
	if authority.get_network_mode() == "CLIENT":
		authority.submit_player_pose.rpc_id(1, local_sample())
	else:
		var state := local_sample()
		state.merge({"health": world.player_combat.health, "shield": world.player_combat.shield, "ammo": world.player_combat.ammo})
		player_states[1] = state
		authority.publish_player_states()


func accept_pose(id: int, faction: String, sample: Dictionary, vehicle_id: String) -> bool:
	if not sample.get("pose") is Transform3D or not sample.get("aim") is Vector3 or not sample.get("velocity") is Vector3 or sample.get("tool") not in [0, 1]:
		return false
	var pose: Transform3D = sample.pose
	var aim: Vector3 = sample.aim
	var velocity: Vector3 = sample.velocity
	if not pose.is_finite() or not aim.is_finite() or not velocity.is_finite() or absf(aim.length_squared() - 1.0) > 0.04:
		return false
	var frame := pose.basis
	if absf(frame.determinant() - 1.0) > 0.08 or not frame.is_equal_approx(frame.orthonormalized()):
		return false
	var radius: float = world.world_config.planet_radius
	if pose.origin.length() < radius * 0.78 or pose.origin.length() > radius * 10.0:
		return false
	var previous: Dictionary = player_states.get(id, {})
	var now := Time.get_ticks_msec()
	var speed_limit := 48.0 if vehicle_id.is_empty() else 700.0
	if not previous.is_empty() and previous.vehicle == vehicle_id:
		var elapsed := clampf((now - previous.received) * 0.001, 0.02, 0.5)
		if pose.origin.distance_to(previous.pose.origin) > 1.5 + speed_limit * elapsed:
			return false
	var state := {
		"pose": Transform3D(frame.orthonormalized(), pose.origin), "aim": aim.normalized(),
		"tool": int(sample.tool), "vehicle": vehicle_id, "velocity": velocity.limit_length(speed_limit), "received": now,
		"health": previous.get("health", 100.0), "shield": previous.get("shield", 75.0),
		"ammo": previous.get("ammo", Combat.MAGAZINE_SIZE),
	}
	player_states[id] = state
	_update_avatar(id, faction, state, true)
	return true


func states_for_network() -> Dictionary:
	var states := player_states.duplicate(true)
	for id in avatars:
		states[id].health = avatars[id].health
		states[id].shield = avatars[id].shield
		states[id].ammo = avatars[id].ammo
	return states


func apply_players(teams: Dictionary, states: Dictionary) -> void:
	var local := multiplayer.get_unique_id()
	for id in avatars.keys():
		if not teams.has(id):
			remove_peer(id)
	for id in states:
		if id != local and teams.has(id):
			_update_avatar(id, teams[id], states[id], false)
		elif id == local:
			var combat: Node = world.player_combat
			var state: Dictionary = states[id]
			if state.health < combat.health or state.shield < combat.shield:
				world.game_feel.damage_pulse = 1.0
			combat.health = state.health
			combat.shield = state.shield
			combat.ammo = state.ammo
		var vehicle: Node3D = world.vehicle_manager.vehicles.get(states[id].vehicle)
		if vehicle != null and vehicle != world.get_active_vehicle():
			vehicle.global_basis = states[id].pose.basis
			vehicle.set_planet_position(states[id].pose.origin)
			vehicle.velocity = states[id].velocity


func _update_avatar(id: int, faction: String, state: Dictionary, authority: bool) -> void:
	var avatar: StaticBody3D = avatars.get(id)
	var first := avatar == null
	if first:
		avatar = RemotePlayerAvatar.new()
		avatar.name = "RemotePlayerAvatar_%d" % id
		avatar.peer_id = id
		avatar.replication = self
		avatar.faction = faction
		add_child(avatar)
		avatars[id] = avatar
	elif avatar.faction != faction:
		avatar.faction = faction
		avatar.rebuild_model()
	avatar.target_pose = state.pose
	avatar.active_tool = state.tool
	avatar.vehicle_id = state.vehicle
	avatar.velocity = state.velocity
	if not authority:
		avatar.health = state.health
		avatar.shield = state.shield
		avatar.ammo = state.ammo
	avatar.update_visibility()
	if first:
		avatar.snap(_origin)
	if authority:
		avatar.server_pose = state.pose


func apply_origin(origin: Vector3) -> void:
	var shift := origin - _origin
	_origin = origin
	for avatar in avatars.values():
		avatar.global_position -= shift
		avatar.visual.global_position -= shift
		avatar.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if world == null:
		return
	for avatar in avatars.values():
		var authoritative: bool = world.can_mutate_world()
		var pose: Transform3D = avatar.server_pose if authoritative else avatar.target_pose
		avatar.global_transform = Transform3D(pose.basis, pose.origin - _origin)
		if authoritative:
			avatar.shield_wait = maxf(0.0, avatar.shield_wait - delta)
			if avatar.health > 0.0 and avatar.shield_wait == 0.0:
				avatar.shield = minf(75.0, avatar.shield + 20.0 * delta)


func _process(delta: float) -> void:
	if world == null:
		return
	_update_projectiles(delta)
	for avatar in avatars.values():
		var target: Transform3D = avatar.target_pose
		target.origin -= _origin
		avatar.visual.global_transform = avatar.visual.global_transform.interpolate_with(target, 1.0 - exp(-15.0 * delta))


func show_projectile(craft: Node3D, point: Vector3, velocity: Vector3, missile: bool, color: Color) -> void:
	var shot := Shot.new()
	shot.splash_radius = 10.0 if missile else 0.0
	shot.energy_color = color
	world.combat_effects.add_child(shot)
	shot.set_physics_process(false)
	var direction := velocity.normalized()
	var up := Vector3.RIGHT if absf(direction.y) > 0.98 else Vector3.UP
	shot.global_transform = Transform3D(Basis.looking_at(direction, up), point - _origin)
	Shot.spawn_flash(world.combat_effects, shot.global_position, color, 0.68 if missile else 0.37, 0.085)
	_projectiles.append({"node": shot, "shooter": craft, "velocity": velocity, "time": 2.2})


func _update_projectiles(delta: float) -> void:
	for index in range(_projectiles.size() - 1, -1, -1):
		var entry := _projectiles[index]
		var shot: Node3D = entry.node
		if not is_instance_valid(shot):
			_projectiles.remove_at(index)
			continue
		var from := shot.global_position
		var to: Vector3 = from + entry.velocity * delta
		var hit := Combat.cast_ray(entry.shooter, from, to) if is_instance_valid(entry.shooter) else {}
		entry.time -= delta
		if hit.is_empty() and entry.time > 0.0:
			shot.global_position = to
		else:
			if not hit.is_empty():
				Shot.spawn_flash(world.combat_effects, hit.position, shot.energy_color, 1.8 if shot.splash_radius > 0.0 else 0.52, 0.2)
			shot.queue_free()
			_projectiles.remove_at(index)


class RemotePlayerAvatar extends StaticBody3D:
	var peer_id := 0
	var replication: Node
	var faction := "helion"
	var health := 100.0
	var shield := 75.0
	var shield_wait := 0.0
	var ammo := Combat.MAGAZINE_SIZE
	var active_tool := 0
	var vehicle_id := ""
	var velocity := Vector3.ZERO
	var target_pose := Transform3D.IDENTITY
	var server_pose := Transform3D.IDENTITY
	var visual: Node3D
	var _rifle: Node3D
	var _engineer: Node3D

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 0
		Turret.add_hit_box(self, Vector3(0.72, 1.8, 0.65))
		# The replicated explorer position is the center of its capsule.
		get_child(0).position.y = 0.0
		rebuild_model()

	func rebuild_model() -> void:
		if visual != null:
			remove_child(visual)
			visual.queue_free()
		visual = Node3D.new()
		visual.top_level = true
		add_child(visual)
		visual.global_transform = global_transform
		var model := Combat.instantiate_model(Combat.COMBAT_MODELS + faction + "_trooper.glb")
		if model == null:
			model = Node3D.new()
			var armor := Combat.hull_material()
			var accent := Combat.glow_material(Combat.faction_color(faction), 1.7)
			Turret.box(model, Vector3(0.64, 0.69, 0.34), Vector3.UP * 1.05, armor)
			Turret.box(model, Vector3(0.36, 0.38, 0.36), Vector3.UP * 1.59, armor)
			Turret.box(model, Vector3(0.28, 0.11, 0.38), Vector3.UP * 1.64, accent)
			for side in [-0.18, 0.18]:
				Turret.box(model, Vector3(0.24, 0.74, 0.26), Vector3(side, 0.36, 0), armor)
		visual.add_child(model)
		model.position.y = -0.9
		_rifle = _tool_model(Combat.RIFLES[faction], Combat.faction_color(faction))
		_engineer = _tool_model("engineering_tool", Color("#74ffbc"))

	func _tool_model(filename: String, color: Color) -> Node3D:
		var model := Combat.instantiate_model(Combat.COMBAT_MODELS + filename + ".glb")
		if model == null:
			model = Node3D.new()
			Turret.box(model, Vector3(0.14, 0.14, 0.52), Vector3.ZERO, Combat.hull_material())
			Turret.box(model, Vector3(0.09, 0.09, 0.12), Vector3.FORWARD * 0.28, Combat.glow_material(color, 1.6))
		visual.add_child(model)
		model.position = Vector3(0.34, 0.26, -0.25)
		return model

	func snap(origin: Vector3) -> void:
		global_transform = Transform3D(target_pose.basis, target_pose.origin - origin)
		visual.global_transform = global_transform
		reset_physics_interpolation()

	func update_visibility() -> void:
		var boarded := not vehicle_id.is_empty()
		set_meta("boarded", boarded)
		visible = health > 0.0 and not boarded
		set_deferred("collision_layer", 8 if visible else 0)
		_rifle.visible = active_tool == 0
		_engineer.visible = active_tool == 1

	func take_damage(amount: float, source: Variant = "") -> bool:
		return take_faction_damage(amount, source if source is String else "")

	func take_faction_damage(amount: float, source: String, player_kill: bool = false) -> bool:
		if not replication.world.can_simulate_combat() or amount <= 0.0 or health <= 0.0 or source == faction or not vehicle_id.is_empty():
			return false
		var absorbed := minf(shield, amount)
		shield -= absorbed
		health = maxf(0.0, health - (amount - absorbed))
		shield_wait = 4.0
		update_visibility()
		if health <= 0.0:
			replication.world.match_manager.record_elimination(source, "Peer %d" % peer_id, player_kill)
			replication.world.network_authority.schedule_peer_respawn(peer_id)
		return true
