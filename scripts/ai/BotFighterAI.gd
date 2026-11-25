class_name BotFighterAI
extends CharacterBody3D

signal eliminated(bot: Node, killer_faction: String)

const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Vehicle = preload("res://scripts/vehicles/VehicleBase.gd")
const VEHICLE_MODELS := "res://assets/models/apogex/vehicles/"
const MAX_HEALTH := 180.0
const MAX_SHIELD := 100.0

var faction := "helion"
var callsign := "HELION-07"
var health := MAX_HEALTH
var shield := MAX_SHIELD
var dimensions := Vector3(14.0, 4.2, 16.0)
var wing_slot := 0
var state := "PATROL"
var model_source := "procedural"
var manager: Node3D
var respawn_remaining := 0.0
var _waypoint := 0
var _launching := false
var _launch_point := Vector3.ZERO
var _route: Array[Vector3] = []
var _cooldown := 0.0


func _ready() -> void:
	add_to_group("bot_fighters")
	# Layer 4 connects to the existing spacecraft projectile mask.
	collision_layer = 8 | 4
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := BoxShape3D.new()
	shape.size = Vector3(10.5, 3.0, 13.0)
	var body := CollisionShape3D.new()
	body.shape = shape
	body.position.y = 1.5
	add_child(body)
	var model := Combat.instantiate_model(VEHICLE_MODELS + faction + "_fighter.glb")
	if model == null:
		model = Combat.instantiate_model(Combat.COMBAT_MODELS + faction + "_fighter.glb")
	if model != null:
		add_child(model)
		model_source = "glb"
	else:
		_build_fallback()


func _build_fallback() -> void:
	var hull := BoxMesh.new()
	hull.size = Vector3(3.0, 2.0, 11.0)
	Combat.add_mesh(self, hull, Vector3.UP * 1.4, Combat.hull_material())
	var wings := PrismMesh.new()
	wings.size = Vector3(13.0, 7.0, 0.6)
	var wing_mesh := Combat.add_mesh(self, wings, Vector3(0, 1.3, 1.5), Combat.hull_material())
	wing_mesh.rotation.x = -PI * 0.5
	var thruster := BoxMesh.new()
	thruster.size = Vector3(2.2, 0.55, 0.25)
	Combat.add_mesh(self, thruster, Vector3(0, 1.3, 5.6), Combat.glow_material(Combat.faction_color(faction), 3.2))


func respawn(in_hangar: bool = true) -> void:
	health = MAX_HEALTH
	shield = MAX_SHIELD
	respawn_remaining = 0.0
	collision_layer = 8 | 4
	velocity = Vector3.ZERO
	var ships: Node3D = manager.world.mothership_manager
	var ship: Node3D = ships.get_ship(faction)
	var other: String = "cinder" if faction == "helion" else "helion"
	var origin: Vector3 = manager.current_origin
	var midpoint: Vector3 = (ships.ship_origin(faction) + ships.ship_origin(other)) * 0.5
	var alpha: Node3D = manager.world.match_manager.objectives[0]
	var side := -1.0 if faction == "helion" else 1.0
	var patrol_up := alpha.global_basis.y
	var patrol_right := alpha.global_basis.x
	var patrol_forward := alpha.global_basis.z
	_route = [
		alpha.planet_position + patrol_up * (380.0 + wing_slot * 100.0) + patrol_right * (420.0 * side),
		midpoint + patrol_forward * (460.0 * side) + patrol_up * (120.0 + wing_slot * 170.0),
		ships.ship_origin(other).lerp(midpoint, 0.32) + patrol_forward * (600.0 * side),
		ships.ship_origin(faction).lerp(midpoint, 0.40) - patrol_forward * (520.0 * side),
	]
	_waypoint = 0 if in_hangar else 1
	_launching = in_hangar
	var lane := -6.0 + wing_slot * 12.0
	_launch_point = ship.local_to_planet(Vector3(lane, 5.0, 520.0))
	if in_hangar:
		global_position = ship.local_to_planet(Vector3(lane, 5.0, 415.0)) - origin
		global_basis = ships.ship_basis(faction) * Basis(Vector3.UP, PI)
	else:
		global_position = _route[0] - origin
		_turn_toward((_route[1] - _route[0]).normalized(), 1.0)
	_cooldown = 0.5 + wing_slot * 0.18
	state = "LAUNCH" if in_hangar else "PATROL"
	reset_physics_interpolation()
	show()


func _physics_process(delta: float) -> void:
	if manager == null or manager.origin_is_resyncing() or not manager.world.can_simulate_combat():
		return
	if health <= 0.0:
		respawn_remaining -= delta
		if respawn_remaining <= 0.0:
			respawn()
		return
	_cooldown -= delta
	var planet_position: Vector3 = global_position + manager.current_origin
	var target := _launch_point if _launching else _route[_waypoint]
	if _launching and planet_position.distance_to(target) < 25.0:
		_launching = false
		target = _route[_waypoint]
	elif not _launching and planet_position.distance_to(target) < 105.0:
		_waypoint = (_waypoint + 1) % _route.size()
		target = _route[_waypoint]
	state = "LAUNCH" if _launching else "PATROL"
	var enemy: Node3D = manager.find_fighter_target(self, 820.0) if not _launching else null
	if enemy != null:
		state = "DOGFIGHT"
		var intercept: Vector3 = enemy.global_position + enemy.velocity * 0.52 + manager.current_origin
		if planet_position.distance_to(intercept) > 95.0:
			target = intercept
		if _cooldown <= 0.0 and global_position.distance_squared_to(enemy.global_position) < 650.0 * 650.0:
			var line := (enemy.global_position - global_position).normalized()
			if line.dot(-global_basis.z) > 0.60:
				_fire_at(enemy)
	var up := planet_position.normalized()
	var floor_radius: float = manager.world.planet.get_surface_radius(up) + 100.0
	if not _launching and target.length() < floor_radius:
		target = target.normalized() * floor_radius
	var heading := (target - planet_position).normalized()
	if not heading.is_zero_approx():
		_turn_toward(heading, 1.0 - exp(-2.4 * delta))
	var airspeed := 52.0 if _launching else (165.0 if enemy != null else 138.0)
	velocity = velocity.lerp(-global_basis.z * airspeed, 1.0 - exp(-1.8 * delta))
	move_and_slide()


func _turn_toward(heading: Vector3, weight: float) -> void:
	if heading.is_zero_approx():
		return
	var up := (global_position + Vector3(manager.current_origin)).normalized()
	if absf(up.dot(heading)) > 0.97:
		up = global_basis.x.cross(heading).normalized()
		if up.is_zero_approx():
			up = Vector3.UP if absf(heading.y) < 0.97 else Vector3.RIGHT
	global_basis = global_basis.slerp(Basis.looking_at(heading, up), weight).orthonormalized()


func _fire_at(enemy: Node3D) -> void:
	_cooldown = 0.24 + wing_slot * 0.08
	var start := global_position + global_basis * Vector3(0, 1.5, -6)
	var end := enemy.global_position + enemy.global_basis.y * 1.5
	var hit := Combat.cast_ray(self, start, end)
	Combat.spawn_tracer(manager.world.combat_effects, start, hit.get("position", end), Combat.faction_color(faction), 0.24, 0.12)
	if hit.get("collider") == enemy:
		if enemy is Vehicle:
			enemy.take_damage(18.0, hit.position)
		else:
			if enemy.take_faction_damage(22.0, faction):
				manager.note_bot_kill(self, enemy)


## The spacecraft projectile sends the render-space hit position as its second argument.
func take_damage(amount: float, source: Variant = "") -> bool:
	if source is Vector3:
		# The legacy projectile exposes its shooter through the calling shot only.
		# Incoming player spacecraft hits use the active craft's faction.
		var piloted: Vehicle = manager.world.get_active_vehicle()
		return take_faction_damage(amount, piloted.faction if piloted != null else "", piloted != null)
	return take_faction_damage(amount, str(source))


func take_faction_damage(amount: float, source_faction: String, player_kill: bool = false) -> bool:
	if health <= 0.0 or amount <= 0.0 or source_faction == faction or not manager.world.can_simulate_combat():
		return false
	var absorbed := minf(shield, amount)
	shield -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	if health == 0.0:
		state = "RESPAWNING"
		respawn_remaining = 10.0 + wing_slot * 2.0
		collision_layer = 0
		hide()
		if player_kill:
			manager.note_player_kill(self)
		eliminated.emit(self, source_faction)
	return true
