extends Node

const WorldAudio = preload("res://scripts/environment/WorldAudioController.gd")

var world: Node
var trauma := 0.0
var damage_pulse := 0.0
var damage_direction := Vector2.ZERO
var _camera: Camera3D
var _offset := Vector2.ZERO
var _time := 0.0
var _focus: Node
var _health := -1.0
var _shield := -1.0
var _shots := 0
var _missiles := 0
var _boosting := false
var _damage_flashes: Array[ColorRect] = []


func setup(context: Node) -> void:
	world = context
	world.vehicle_manager.active_vehicle_changed.connect(_focus_changed)
	for objective in world.capture_objectives:
		objective.captured.connect(_capture_feedback.bind(objective))


func _focus_changed(vehicle: Node) -> void:
	if is_instance_valid(_focus) and _focus.has_signal("damaged") and _focus.damaged.is_connected(_vehicle_impact):
		_focus.damaged.disconnect(_vehicle_impact)
	_focus = vehicle if vehicle != null else world.player_combat
	if vehicle != null:
		vehicle.damaged.connect(_vehicle_impact)
	_health = _focus.health
	_shield = _focus.shield
	_shots = vehicle.weapon_system.shots_fired if vehicle != null else _focus.shots_fired
	_missiles = vehicle.weapon_system.missiles if vehicle != null else 0
	_boosting = false


func setup_vignette(layer: Control) -> void:
	for index in 4:
		var edge := ColorRect.new()
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.set_anchors_and_offsets_preset([Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM][index])
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type canvas_item; uniform int edge; uniform float strength; void fragment(){ float d = edge == 0 ? UV.x : edge == 1 ? 1.0-UV.x : edge == 2 ? UV.y : 1.0-UV.y; COLOR = vec4(0.85,0.055,0.035,strength*pow(1.0-d,2.4)); }"
		material.shader = shader
		material.set_shader_parameter("edge", index)
		edge.material = material
		if index < 2:
			edge.anchor_top = 0.0
			edge.anchor_bottom = 1.0
			edge.offset_left = 0.0 if index == 0 else -130.0
			edge.offset_right = 130.0 if index == 0 else 0.0
		else:
			edge.anchor_left = 0.0
			edge.anchor_right = 1.0
			edge.offset_top = 0.0 if index == 2 else -112.0
			edge.offset_bottom = 112.0 if index == 2 else 0.0
		layer.add_child(edge)
		_damage_flashes.append(edge)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func damage_from(point: Vector3) -> void:
	var camera: Camera3D = world._get_view_camera()
	var direction := (point - camera.global_position).normalized()
	damage_direction = Vector2(direction.dot(camera.global_basis.x), -direction.dot(camera.global_basis.y))
	damage_pulse = 1.0


func _vehicle_impact(_amount: float, point: Vector3) -> void:
	damage_from(point)


func event(kind: StringName, point: Vector3, shake: float, reach: float = 85.0) -> void:
	var dist: float = world._get_focus_position().distance_to(point)
	if dist < reach:
		add_trauma(shake * (1.0 - dist / reach))
	world.world_audio.trigger_event(kind, point)


func _capture_feedback(_faction: String, _name: String, _present: bool, objective: Node3D) -> void:
	event(&"capture", objective.planet_position, 0.10, 110.0)


func _process(delta: float) -> void:
	if world == null or not world.ready_complete:
		return
	if not is_instance_valid(_focus):
		_focus_changed(world.get_active_vehicle())
	var craft: Node = world.get_active_vehicle()
	var shots: int = craft.weapon_system.shots_fired if craft != null else _focus.shots_fired
	if shots > _shots and (craft == null or world.can_mutate_world()):
		var missile: bool = craft != null and craft.weapon_system.missiles < _missiles
		event(&"missile" if missile else (&"cannon" if craft != null else &"rifle"), world._get_focus_position(), 0.42 if missile else 0.24)
	_shots = shots
	_missiles = craft.weapon_system.missiles if craft != null else 0
	var boosting: bool = craft != null and craft.get_boost_ratio() > 0.08
	if boosting and not _boosting:
		event(&"afterburner", world._get_focus_position(), 0.23)
	_boosting = boosting
	if _focus.health < _health or _focus.shield + 0.1 < _shield:
		damage_pulse = 1.0
		event(&"hit", world._get_focus_position(), 0.35)
	_health = _focus.health
	_shield = _focus.shield
	tick(delta, world._get_view_camera())


func tick(delta: float, camera: Camera3D) -> void:
	if is_instance_valid(_camera):
		_camera.h_offset -= _offset.x
		_camera.v_offset -= _offset.y
	_camera = camera
	_time += delta
	var strength := trauma * trauma
	_offset = Vector2(sin(_time * 74.0), sin(_time * 97.0 + 1.2)) * (0.072 * strength)
	if is_instance_valid(_camera):
		_camera.h_offset += _offset.x
		_camera.v_offset += _offset.y
	trauma = maxf(0.0, trauma - delta * 1.9)
	damage_pulse = move_toward(damage_pulse, 0.0, delta * 2.8)
	var directions := [-damage_direction.x, damage_direction.x, -damage_direction.y, damage_direction.y]
	for index in _damage_flashes.size():
		var material := _damage_flashes[index].material as ShaderMaterial
		material.set_shader_parameter("strength", damage_pulse * (0.22 + 0.62 * maxf(0.0, directions[index])))


class CombatAudio extends WorldAudio:
	const PROFILES := {
		&"rifle": Vector4(0.14, 185, 0.74, 22.0),
		&"cannon": Vector4(0.24, 105, 0.55, 13.0),
		&"missile": Vector4(0.54, 83, 0.38, 5.8),
		&"capture": Vector4(0.55, 488, 0.98, 5.0),
		&"orbital": Vector4(1.20, 51, 0.45, 3.4),
		&"afterburner": Vector4(0.48, 95, 0.25, 5.2),
		&"hit": Vector4(0.21, 120, 0.42, 16.0),
		&"impact": Vector4(0.34, 65, 0.50, 10.0),
	}
	var _combat_streams := {}


	func trigger_event(event: StringName, planet_pos: Vector3) -> void:
		if not PROFILES.has(event):
			for player in _one_shots:
				if not player.playing:
					player.stream = _stream_for({"kind": "thud", "freq": 60.0})
					player.unit_size = 10.0
					player.max_distance = 0.0
					player.volume_db = -14.0
					break
			super.trigger_event(event, planet_pos)
			return
		events_played += 1
		if not _combat_streams.has(event):
			_combat_streams[event] = _combat_wave(event, PROFILES[event])
		for player in _one_shots:
			if not player.playing:
				player.position = planet_pos - current_origin
				player.stream = _combat_streams[event]
				player.pitch_scale = 1.0
				player.unit_size = 90.0 if event == &"orbital" else 18.0
				player.max_distance = 650.0 if event == &"orbital" else 145.0
				player.volume_db = -5.0 if event == &"orbital" else -11.0
				player.play()
				return


	func _exit_tree() -> void:
		for player in _one_shots:
			if is_instance_valid(player):
				player.stop()
		for zone in _zones:
			var player: AudioStreamPlayer3D = zone.player
			if is_instance_valid(player):
				player.stop()


	func _combat_wave(event: StringName, profile: Vector4) -> AudioStreamWAV:
		const RATE := 16000
		var count := int(profile.x * RATE)
		var samples := PackedByteArray()
		samples.resize(count * 2)
		var noise := RandomNumberGenerator.new()
		noise.seed = 112904
		var rumble := 0.0
		var phase := 0.0
		for i in count:
			var t := float(i) / RATE
			var pitch := profile.y
			if event == &"capture":
				pitch *= 1.5 if t > 0.23 else 1.0
			else:
				pitch *= 0.48 + 0.52 * exp(-t * 8.0)
			phase += TAU * pitch / RATE
			rumble = lerpf(rumble, noise.randf_range(-1.0, 1.0), 0.19)
			var wave := (sin(phase) * profile.z + rumble * (1.0 - profile.z) * 2.5)
			var envelope := minf(t * 420.0, 1.0) * (1.0 - t / profile.x) * exp(-t * profile.w)
			samples.encode_s16(i * 2, int(clampf(wave * envelope, -1.0, 1.0) * 19000.0))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = RATE
		stream.data = samples
		return stream
