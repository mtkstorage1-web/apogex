class_name CaptureObjective
extends StaticBody3D

signal captured(faction: String, objective_name: String, player_present: bool)

const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const MODEL := "res://assets/models/apogex/combat/capture_beacon_node.glb"
const BEAM_HEIGHT := 1900.0
const CAPTURE_RATE := 0.125

@export var objective_id := "alpha"
@export var display_name := "Terminus Extraction Spire"
@export var latitude := 0.0
@export var longitude := 0.0
@export var capture_radius := 28.0
var capture_progress := 0.0
var owner_faction := "neutral"
var contested := false
var planet_position := Vector3.ZERO
var model_source := "procedural"
var _engineer_faction := ""
var _engineering_time := 0.0
var _glow: StandardMaterial3D
var _haze: StandardMaterial3D


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	add_to_group("capture_objectives")
	_glow = Combat.glow_material(Combat.faction_color("neutral"), 2.6)
	var imported := Combat.instantiate_model(MODEL)
	if imported != null:
		add_child(imported)
		model_source = "glb"
	else:
		var base := CylinderMesh.new()
		base.top_radius = 1.7
		base.bottom_radius = 2.25
		base.height = 0.65
		base.radial_segments = 8
		Combat.add_mesh(self, base, Vector3(0, -0.025, 0), Combat.hull_material())
		var mast := BoxMesh.new()
		mast.size = Vector3(1.05, 4.9, 1.05)
		Combat.add_mesh(self, mast, Vector3(0, 2.75, 0), Combat.hull_material())
	var emitter := CylinderMesh.new()
	emitter.top_radius = 0.84
	emitter.bottom_radius = 0.84
	emitter.height = 0.28
	Combat.add_mesh(self, emitter, Vector3(0, 4.9, 0), _glow)
	var column := CylinderMesh.new()
	column.top_radius = 1.4
	column.bottom_radius = 0.48
	column.height = BEAM_HEIGHT
	column.radial_segments = 8
	var beam := Combat.add_mesh(self, column, Vector3.UP * (5.1 + BEAM_HEIGHT * 0.5), _glow)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := column.duplicate() as CylinderMesh
	halo.top_radius = 7.0
	halo.bottom_radius = 1.4
	_haze = Combat.glow_material(Combat.faction_color("neutral"), 0.0)
	_haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_haze.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var outer := Combat.add_mesh(self, halo, beam.position, _haze)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tint()


func place_on_pad(pad: Dictionary, offset: Vector3, origin: Vector3) -> void:
	global_basis = pad.basis
	planet_position = pad.origin + global_basis * offset
	apply_origin(origin)


func apply_origin(new_origin: Vector3) -> void:
	global_position = planet_position - new_origin
	reset_physics_interpolation()


func is_in_capture_radius(point: Vector3) -> bool:
	return global_position.distance_squared_to(point) <= capture_radius * capture_radius


func support_capture(faction: String, delta: float) -> void:
	_engineer_faction = faction
	_engineering_time = maxf(_engineering_time, delta)


func update_capture(delta: float, helion: int, cinder: int, player_faction: String = "") -> void:
	contested = helion > 0 and cinder > 0
	var engineering := _engineering_time > 0.0
	_engineering_time = maxf(0.0, _engineering_time - delta)
	if contested or helion == cinder:
		return
	var faction := "helion" if helion > cinder else "cinder"
	var direction := 1.0 if faction == "helion" else -1.0
	var rate := CAPTURE_RATE * (1.5 if engineering and _engineer_faction == faction else 1.0)
	capture_progress = move_toward(capture_progress, direction, delta * rate)
	if (owner_faction == "helion" and capture_progress <= 0.0) or (owner_faction == "cinder" and capture_progress >= 0.0):
		owner_faction = "neutral"
		_tint()
	if capture_progress == direction and owner_faction != faction:
		owner_faction = faction
		_tint()
		captured.emit(faction, objective_id.to_upper(), player_faction == faction)


func reset_capture() -> void:
	_engineering_time = 0.0
	apply_capture_status({"capture_progress": 0.0, "owner_faction": "neutral", "contested": false})


func get_capture_status() -> Dictionary:
	return {
		"id": objective_id, "name": display_name, "capture_progress": capture_progress,
		"owner_faction": owner_faction, "contested": contested,
	}


func apply_capture_status(state: Dictionary) -> void:
	capture_progress = state.capture_progress
	owner_faction = state.owner_faction
	contested = state.contested
	_tint()


func _tint() -> void:
	if _glow != null:
		var color := Combat.faction_color(owner_faction)
		_glow.albedo_color = color
		_glow.emission = color
		_haze.albedo_color = Color(color, 0.18)
