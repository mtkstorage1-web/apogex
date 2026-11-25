extends StaticBody3D

const Turret = preload("res://scripts/gameplay/DefenseTurret.gd")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const Shot = preload("res://scripts/vehicles/Projectile.gd")
const RANGE := 12.0
const DROP_TIME := 4.0

var world: Node
var faction := "helion"
var planet_position := Vector3.ZERO
var launch_position := Vector3.ZERO
var drop_remaining := 0.0
var _pulse_wait := 0.0
var _trail: MeshInstance3D
var _trail_wait := 0.0


func _ready() -> void:
	collision_mask = 0
	Turret.add_hit_box(self, Vector3(2.2, 2.6, 2.2))
	var model := Combat.instantiate_model(Turret.MODELS + "supply_ammo_pod.glb")
	if model != null:
		add_child(model)
	else:
		Turret.box(self, Vector3(2.15, 2.85, 2.15), Vector3.UP * 1.175, Combat.hull_material())
		var glow := Combat.glow_material(Combat.faction_color(faction), 2.1)
		Turret.box(self, Vector3(2.22, 0.2, 2.22), Vector3.UP * 2.24, glow)
		Turret.box(self, Vector3(0.3, 0.78, 2.23), Vector3.UP * 1.1, glow)
	_trail = Combat.add_mesh(self, BoxMesh.new(), Vector3.ZERO, Combat.glow_material(Color("#ff7a2e"), 4.0))
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pose(Vector3.ZERO)


func pose(origin: Vector3) -> void:
	var fraction := clampf(drop_remaining / DROP_TIME, 0.0, 1.0)
	var point := planet_position.lerp(launch_position, pow(fraction, 2.8))
	global_position = point - origin
	_trail.visible = drop_remaining > 0.0
	collision_layer = 0 if _trail.visible else 8
	if _trail.visible:
		var tail := (launch_position - planet_position).normalized()
		Combat.set_segment(_trail, global_position + global_basis.y, global_position + tail * (8.0 + 18.0 * fraction), 0.38)


func tick(delta: float, authority: bool) -> void:
	if drop_remaining > 0.0:
		drop_remaining = maxf(0.0, drop_remaining - delta)
		pose(world.floating_origin.current_origin)
		_trail_wait -= delta
		if drop_remaining == 0.0 or _trail_wait <= 0.0:
			_trail_wait = 0.065
			Shot.spawn_flash(world.combat_effects, global_position + global_basis.y, Color("#ff7225"), 1.8, 0.25)
		if drop_remaining == 0.0:
			world.game_feel.event(&"impact", planet_position, 0.2)
		return
	if not authority:
		return
	_pulse_wait -= delta
	if _pulse_wait > 0.0:
		return
	_pulse_wait = 1.2
	var combat: Node = world.player_combat
	if combat.faction == faction and not world.explorer.is_piloting and world.explorer.get_planet_position().distance_to(planet_position) <= RANGE:
		combat.heal(24.0)
		combat.ammo = Combat.MAGAZINE_SIZE
		combat.jetpack_fuel = combat.max_jetpack
	for avatar in world.network_authority.replication.avatars.values():
		if avatar.faction == faction and not avatar.get_meta("boarded", false) and avatar.health > 0.0 and avatar.global_position.distance_to(global_position) <= RANGE:
			avatar.health = minf(100.0, avatar.health + 24.0)
			avatar.ammo = Combat.MAGAZINE_SIZE
			world.network_authority.replenish_peer(avatar.peer_id)
	for vehicle in world.vehicle_manager.vehicles.values():
		if vehicle.faction == faction and vehicle.health > 0.0 and vehicle.get_planet_position().distance_to(planet_position) <= RANGE:
			vehicle.health = minf(vehicle.max_health, vehicle.health + 24.0)
			vehicle.shield = minf(vehicle.max_shield, vehicle.shield + 18.0)
