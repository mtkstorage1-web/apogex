class_name VehicleManager
extends Node3D

const Vehicle = preload("res://scripts/vehicles/VehicleBase.gd")
const Shot = preload("res://scripts/vehicles/Projectile.gd")
const BOARD_RANGE := 16.0
const PARKED_CLEARANCE := 0.035

const SCENES := {
	"helion_fighter": preload("res://scenes/vehicles/HelionFighter.tscn"),
	"cinder_fighter": preload("res://scenes/vehicles/CinderFighter.tscn"),
	"helion_dropship": preload("res://scenes/vehicles/HelionDropship.tscn"),
	"cinder_dropship": preload("res://scenes/vehicles/CinderDropship.tscn"),
	"helion_rover": preload("res://scenes/vehicles/HelionRover.tscn"),
	"cinder_rover": preload("res://scenes/vehicles/CinderRover.tscn"),
}
# Positions use the decks' and pads' local frames. Hangar bow is ship-local +Z.
const HANGAR_SLOTS := {
	"fighter": Vector3(-16, 0, 387),
	"dropship": Vector3(16, 0, 387),
}
const SURFACE_SLOTS := [
	["helion_fighter_terminus", "helion_fighter", "extraction", Vector3(31, 0, 20), 0.0],
	["helion_rover_terminus", "helion_rover", "extraction", Vector3(-29, 0, 32), 0.0],
	["cinder_rover_terminus", "cinder_rover", "extraction", Vector3(27, 0, -25), 0.0],
	["cinder_fighter_launch", "cinder_fighter", "launch", Vector3(-38, 0.30, -20), PI * 0.5],
	["helion_dropship_launch", "helion_dropship", "launch", Vector3(-38, 0.30, 3), PI * 0.5],
	["cinder_rover_refinery", "cinder_rover", "refinery", Vector3(-4, 0.07, 40), 0.0],
]

signal active_vehicle_changed(vehicle: Vehicle)

var vehicles: Dictionary[String, Vehicle] = {}
var active_vehicle: Vehicle
var projectile_root: Node3D
var _world: Node
var _origin := Vector3.ZERO
var _surface_anchors: Dictionary[String, Vector3] = {}


func setup(world: Node) -> void:
	_world = world
	_origin = _world.floating_origin.current_origin
	projectile_root = Node3D.new()
	projectile_root.name = "Projectiles"
	add_child(projectile_root)
	rebuild()


func rebuild() -> void:
	release_for_world_travel()
	for vehicle in vehicles.values():
		remove_child(vehicle)
		vehicle.queue_free()
	vehicles.clear()
	_surface_anchors.clear()
	for effect in projectile_root.get_children():
		projectile_root.remove_child(effect)
		effect.queue_free()
	for faction in ["helion", "cinder"]:
		var ship: Node3D = _world.mothership_manager.get_ship(faction)
		var frame: Basis = ship.planet_basis
		for kind in HANGAR_SLOTS:
			var model := "%s_%s" % [faction, kind]
			var slot: Vector3 = HANGAR_SLOTS[kind] + Vector3.UP * PARKED_CLEARANCE
			_spawn(model + "_hangar", model, ship.local_to_planet(slot), frame * Basis(Vector3.UP, PI))
	for slot in SURFACE_SLOTS:
		var facility: Dictionary = _world.surface_facilities.get_facility_info(slot[2])
		var frame: Basis = facility.basis
		var anchor: Vector3 = facility.origin + frame * slot[3]
		_surface_anchors[slot[0]] = anchor
		_spawn(slot[0], slot[1], anchor + frame.y * PARKED_CLEARANCE, frame * Basis(Vector3.UP, slot[4]))


func _physics_process(_delta: float) -> void:
	# Coarse terrain collision can sit proud of a pad until its finer patch streams in.
	for key in _surface_anchors:
		var vehicle := vehicles[key]
		if vehicle.origin_is_resyncing():
			continue
		var anchor := _surface_anchors[key]
		if anchor.distance_squared_to(vehicle.get_planet_position()) > 1.0:
			continue
		var up := vehicle.global_basis.y
		var center := anchor - _origin
		var support := vehicle.raycast(center + up * 0.95, center - up * 0.45)
		if support.is_empty() or up.dot(support.normal) < 0.9:
			continue
		var parked: Vector3 = support.position + up * PARKED_CLEARANCE + _origin
		if parked.distance_squared_to(vehicle.get_planet_position()) > 0.000025:
			vehicle.set_planet_position(parked)


func _spawn(key: String, model: String, at: Vector3, frame: Basis) -> void:
	var vehicle := (SCENES[model] as PackedScene).instantiate() as Vehicle
	vehicle.vehicle_id = key
	vehicle.planet = _world.planet
	vehicle.coord = _world.coord_system
	vehicle.origin_mgr = _world.floating_origin
	vehicle.mothership_manager = _world.mothership_manager
	vehicle.destruction_controller = _world.destruction
	vehicle.projectile_root = projectile_root
	add_child(vehicle)
	vehicle.global_basis = frame
	vehicle.set_planet_position(at)
	vehicles[key] = vehicle


func apply_origin(new_origin: Vector3) -> void:
	for vehicle in vehicles.values():
		vehicle.apply_origin(new_origin)
	var delta := new_origin - _origin
	for effect in projectile_root.get_children():
		if effect is Shot:
			effect.apply_origin_delta(delta)
		else:
			effect.global_position -= delta
			effect.reset_physics_interpolation()
	_origin = new_origin


func find_nearest_parked(planet_pos: Vector3, radius: float = BOARD_RANGE) -> Vehicle:
	var nearest: Vehicle
	var best := radius * radius
	for vehicle in vehicles.values():
		if vehicle.is_piloted or vehicle.health <= 0.0 or vehicle.get_speed() > 1.0:
			continue
		var distance: float = vehicle.get_planet_position().distance_squared_to(planet_pos)
		if distance <= best:
			best = distance
			nearest = vehicle
	return nearest


func interact() -> bool:
	if active_vehicle != null:
		return exit_active_vehicle()
	return _board(find_nearest_parked(_world.explorer.get_planet_position()))


func quick_board_vehicle(vehicle_key: String) -> bool:
	var vehicle := vehicles.get(vehicle_key) as Vehicle
	if vehicle == null and SCENES.has(vehicle_key):
		for candidate in vehicles.values():
			if candidate.vehicle_id.begins_with(vehicle_key + "_"):
				vehicle = candidate
				break
	return _board(vehicle)


func _board(vehicle: Vehicle) -> bool:
	if vehicle == null or vehicle.health <= 0.0:
		return false
	if vehicle == active_vehicle:
		return true
	if active_vehicle != null and not exit_active_vehicle():
		return false
	var position := vehicle.get_planet_position()
	_world.floating_origin.check_and_shift(position)
	if vehicle.get_ship() == null and vehicle.get_height_above_ground() < 150.0:
		_world.planet.ensure_area_ready(position)
	_surface_anchors.erase(vehicle.vehicle_id)
	active_vehicle = vehicle
	vehicle.controls_enabled = _world.explorer.mouse_captured or DisplayServer.get_name() == "headless"
	vehicle.board(_world.explorer)
	active_vehicle_changed.emit(vehicle)
	return true


func exit_active_vehicle() -> bool:
	if active_vehicle == null:
		return false
	active_vehicle.exit_vehicle()
	if active_vehicle.is_piloted:
		return false
	active_vehicle = null
	active_vehicle_changed.emit(null)
	return true


func release_for_world_travel() -> void:
	if active_vehicle == null:
		return
	active_vehicle.release_pilot()
	_world.explorer.set_piloting_state(false)
	active_vehicle = null
	active_vehicle_changed.emit(null)
