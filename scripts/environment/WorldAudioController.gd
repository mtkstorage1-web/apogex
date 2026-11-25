class_name WorldAudioController
extends Node3D
## Environmental audio: 4 buses (Environment, Machinery, Weather, Ambience), a budgeted set of spatial
## AudioStreamPlayer3D hooks over procedurally generated looping AudioStreamWAV buffers (no files, so no
## missing-asset errors) and vacuum acoustics that fade the air-borne buses above the atmosphere.

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const FacilityMgr = preload("res://scripts/environment/SurfaceFacilityManager.gd")
const ShipMgr = preload("res://scripts/environment/MothershipManager.gd")

const BUS_NAMES: Array[StringName] = [&"Environment", &"Machinery", &"Weather", &"Ambience"]
const AIR_BUSES: Array[StringName] = [&"Environment", &"Weather", &"Ambience"]
const MIX_RATE := 8000
const ATMOSPHERE_FULL_ALT := 600.0
const VACUUM_ALT := 1100.0      # fully vacuum at/above this altitude
const VACUUM_FLOOR_DB := -60.0
const INTERIOR_FLOOR_DB := -12.0   # ship / suit coupled feedback inside mothership interiors
const MACHINERY_VACUUM_DB := -30.0 # structure-borne vibration only
const BUDGET := {"LOW": 4, "MEDIUM": 6, "HIGH": 8, "ULTRA": 9}

## kind: hum (low machinery), noise (wind/dust), crackle (lava), tone, thud (impact)
const ZONES: Array = [
	{"id": &"hangar_machinery", "bus": &"Machinery", "kind": "hum", "freq": 55.0, "ship": "helion", "local": Vector3(0, 1, 300), "range": 160.0},
	{"id": &"reactor_room", "bus": &"Machinery", "kind": "hum", "freq": 38.0, "ship": "cinder", "local": Vector3(-70, 1, -100), "range": 120.0},
	{"id": &"mining_refinery", "bus": &"Machinery", "kind": "hum", "freq": 72.0, "lat": 0.0, "lon": 20.0, "local": Vector3(0, 4, 0), "range": 140.0},
	{"id": &"surface_wind", "bus": &"Environment", "kind": "noise", "follow": true, "range": 60.0},
	{"id": &"dust_storm", "bus": &"Weather", "kind": "noise", "follow": true, "range": 60.0},
	{"id": &"lava_fissure", "bus": &"Environment", "kind": "crackle", "lat": 2.0, "lon": -22.0, "local": Vector3.ZERO, "range": 120.0},
	{"id": &"underground_tunnel", "bus": &"Ambience", "kind": "hum", "freq": 28.0, "lat": 0.0, "lon": 20.0, "local": Vector3(18, 1, -6), "range": 80.0},
	{"id": &"launch_facility", "bus": &"Machinery", "kind": "hum", "freq": 90.0, "lat": -18.0, "lon": 0.0, "local": Vector3(0, 3, 0), "range": 160.0},
	{"id": &"orbital_debris_impact", "bus": &"Ambience", "kind": "thud", "orbital": "debris", "range": 400.0},
]

var noise: TerrainNoiseStack
var world_cfg: WorldConfig
var quality_preset: String = "HIGH"
var current_origin: Vector3 = Vector3.ZERO
var atmosphere_factor: float = 1.0       # 1 = full air, 0 = vacuum
var vacuum_attenuation: float = 0.0      # 1 - atmosphere_factor
var in_interior: bool = false
var storm_level: float = 0.0
var _zones: Array[Dictionary] = []
var _one_shots: Array[AudioStreamPlayer3D] = []
var events_played: int = 0
var _streams: Dictionary = {}


func setup(p_noise: TerrainNoiseStack, p_world_cfg: WorldConfig) -> void:
	noise = p_noise
	world_cfg = p_world_cfg
	quality_preset = world_cfg.quality_preset.to_upper()
	ensure_buses()
	rebuild()


## Creates any missing bus (routed to Master). Idempotent.
static func ensure_buses() -> void:
	for n in BUS_NAMES:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, n)
			AudioServer.set_bus_send(idx, &"Master")


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_zones.clear()
	_one_shots.clear()
	if noise == null:
		return
	for z in ZONES:
		var p := AudioStreamPlayer3D.new()
		p.name = "Zone_%s" % String(z["id"])
		p.bus = z["bus"]
		p.stream = _stream_for(z)
		p.volume_db = -24.0
		p.max_distance = float(z["range"]) * 2.0
		p.unit_size = float(z["range"]) * 0.25
		p.autoplay = false
		add_child(p)
		_zones.append({"def": z, "player": p, "planet_pos": _zone_pos(z), "active": false})
	for i in 3:
		var o := AudioStreamPlayer3D.new()
		o.name = "OneShot%d" % i
		o.bus = &"Ambience"
		o.stream = _make_wave("thud", 60.0, 0.5)
		o.volume_db = -14.0
		add_child(o)
		_one_shots.append(o)
	apply_origin(current_origin)


func _zone_pos(z: Dictionary) -> Vector3:
	if z.has("follow"):
		return Vector3.ZERO
	if z.has("ship"):
		var pl: Dictionary = ShipMgr.ship_placement(z["ship"], world_cfg.planet_radius)
		return (pl["origin"] as Vector3) + (pl["basis"] as Basis) * (z["local"] as Vector3)
	if z.has("orbital"):
		return OrbitalEnvironmentManager.placement(z["orbital"], world_cfg.planet_radius)["origin"]
	var pt: Dictionary = FacilityMgr.pad_transform(noise, z["lat"], z["lon"])
	return (pt["origin"] as Vector3) + (pt["basis"] as Basis) * (z["local"] as Vector3)


func _stream_for(z: Dictionary) -> AudioStreamWAV:
	var key: String = "%s_%s" % [z["kind"], str(z.get("freq", 0))]
	if not _streams.has(key):
		_streams[key] = _make_wave(z["kind"], float(z.get("freq", 60.0)), 0.5)
	return _streams[key]


## Tiny deterministic 16-bit mono loop (0.5 s @ 8 kHz).
static func _make_wave(kind: String, freq: float, seconds: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var seed_v: int = 12345
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / MIX_RATE
		var s: float = 0.0
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var r: float = float(seed_v) / 2147483647.0 * 2.0 - 1.0
		match kind:
			"hum":
				# Integer cycles over the loop so it tiles without a click.
				var f: float = roundf(freq * seconds) / seconds
				s = 0.6 * sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t) + 0.05 * r
			"noise":
				lp += (r - lp) * 0.12
				s = lp * 1.6
			"crackle":
				s = r * (1.0 if fposmod(t * 9.0, 1.0) < 0.06 else 0.05)
			"thud":
				s = sin(TAU * freq * t) * exp(-t * 9.0)
			_:
				s = 0.0
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 12000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	if kind != "thud":
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	for z in _zones:
		if not z["def"].has("follow"):
			(z["player"] as AudioStreamPlayer3D).position = (z["planet_pos"] as Vector3) - current_origin


## Smooth fade factor for air-borne sound: 1 below 600 m, 0 at/above the 1,100 m vacuum threshold.
static func atmosphere_factor_for(altitude: float) -> float:
	return 1.0 - smoothstep(ATMOSPHERE_FULL_ALT, VACUUM_ALT, altitude)


## Bus volumes (dB) for an atmosphere factor. Interiors keep ship / suit coupled feedback.
static func air_bus_db(atmo: float, interior: bool) -> float:
	if interior:
		return 0.0   # pressurised ship interior: hull air carries sound
	return lerpf(VACUUM_FLOOR_DB, 0.0, atmo)


static func machinery_bus_db(atmo: float, interior: bool) -> float:
	if interior:
		return 0.0
	return lerpf(MACHINERY_VACUUM_DB, 0.0, atmo)


## Per-frame: updates attenuation (smoothed), budget, storm level, and follow zones.
func update_audio(cam_render_pos: Vector3, altitude: float, interior: bool, storm: float, delta: float, snap: bool = false) -> void:
	in_interior = interior
	storm_level = storm
	atmosphere_factor = atmosphere_factor_for(altitude)
	vacuum_attenuation = 1.0 - atmosphere_factor
	var k: float = 1.0 if snap else 1.0 - exp(-6.0 * delta)
	for b in AIR_BUSES:
		var idx: int = AudioServer.get_bus_index(b)
		if idx == -1:
			continue
		var target: float = air_bus_db(atmosphere_factor, interior)
		if interior and b != &"Ambience":
			target = INTERIOR_FLOOR_DB   # hull-muted but present: suit / ship coupled feedback
		AudioServer.set_bus_volume_db(idx, lerpf(AudioServer.get_bus_volume_db(idx), target, k))
	var mi: int = AudioServer.get_bus_index(&"Machinery")
	if mi != -1:
		AudioServer.set_bus_volume_db(mi, lerpf(AudioServer.get_bus_volume_db(mi), machinery_bus_db(atmosphere_factor, interior), k))
	# Budget: nearest N zones play; the rest are stopped.
	var budget: int = BUDGET.get(quality_preset, 8)
	var ranked: Array = []
	for z in _zones:
		var def: Dictionary = z["def"]
		var p: AudioStreamPlayer3D = z["player"]
		if def.has("follow"):
			p.global_position = cam_render_pos
			var want: float = 1.0 if (def["id"] == &"surface_wind" and altitude < ATMOSPHERE_FULL_ALT) else 0.0
			if def["id"] == &"dust_storm":
				want = storm
			p.volume_db = linear_to_db(maxf(want, 0.0001)) - 18.0
			z["dist"] = 0.0 if want > 0.01 else INF
		else:
			z["dist"] = cam_render_pos.distance_to((z["planet_pos"] as Vector3) - current_origin)
		ranked.append(z)
	ranked.sort_custom(func(a, b) -> bool: return a["dist"] < b["dist"])
	var playing: int = 0
	for z in ranked:
		var def2: Dictionary = z["def"]
		var in_range: bool = z["dist"] < float(def2["range"]) * 2.0
		var on: bool = in_range and playing < budget
		if on:
			playing += 1
		var pl: AudioStreamPlayer3D = z["player"]
		if on and not pl.playing:
			pl.play()
		elif not on and pl.playing:
			pl.stop()
		z["active"] = on


func get_playing_count() -> int:
	var n: int = 0
	for z in _zones:
		if (z["player"] as AudioStreamPlayer3D).playing:
			n += 1
	return n


func get_zone_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for z in _zones:
		out.append(z["def"]["id"])
	return out


func get_zone_count() -> int:
	return _zones.size()


## One-shot audio event at a planet-space point (destruction, debris impact).
func trigger_event(event: StringName, planet_pos: Vector3) -> void:
	events_played += 1
	for o in _one_shots:
		if not o.playing:
			o.position = planet_pos - current_origin
			o.pitch_scale = {&"collapse": 0.6, &"alarm": 1.4, &"crackle": 1.1}.get(event, 1.0)
			o.play()
			return


func on_destruction_audio(_section_id: StringName, event: StringName, planet_pos: Vector3) -> void:
	trigger_event(event, planet_pos)


func get_diagnostics() -> Dictionary:
	return {"atmosphere_factor": atmosphere_factor, "vacuum_attenuation": vacuum_attenuation,
		"playing": get_playing_count(), "zones": _zones.size(), "events": events_played,
		"env_db": AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Environment")) if AudioServer.get_bus_index(&"Environment") != -1 else 0.0}
