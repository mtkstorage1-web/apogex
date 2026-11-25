extends SceneTree
## Wave 5 (Milestone 9): automated end-to-end validation of the 25 final acceptance criteria.
## Run: Godot --headless --path . -s res://tests/world_validation/test_acceptance_25.gd

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")
const WORLD_SCENE := "res://scenes/world/WorldRoot.tscn"

var _failures: int = 0
var _n: int = 0
var _world: WorldRoot


func _initialize() -> void:
	_run()


func _crit(cond: bool, msg: String) -> void:
	_n += 1
	if cond:
		print("  ok   [%02d] %s" % [_n, msg])
	else:
		_failures += 1
		print("  FAIL [%02d] %s" % [_n, msg])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldRoot
	root.add_child(_world)
	await _frames(4)
	_world_core()
	_orbital()
	await _streaming_and_landmarks()
	_weather_destruction_audio()
	await _quality_and_regen()
	_ui_and_docs()
	_crit(_n == 25, "exactly 25 acceptance criteria evaluated (%d)" % _n)
	_world.queue_free()
	await _frames(2)
	print("Acceptance25 %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _world_core() -> void:
	print("[core world]")
	var cfg: WorldConfig = _world.world_config
	_crit(cfg.planet_radius == 12000.0 and cfg.planet_name == "VESPER-9", "1 planet Vesper-9 configured at 12 km radius")
	var u: Vector3 = Transforms.lat_lon_to_unit_dir(deg_to_rad(12.0), deg_to_rad(-33.0))
	var geo: Dictionary = Transforms.cartesian_to_geographic_deg(u * cfg.planet_radius, cfg.planet_radius)
	_crit(absf(float(geo["latitude"]) - 12.0) < 0.01 and absf(float(geo["longitude"]) + 33.0) < 0.01, "2 coordinate round trip lat/lon")
	var st: Dictionary = _world.planet.get_stats()
	_crit(int(st.get("total_patches", 0)) > 0, "3 cube-sphere terrain patches generated")
	var names: Dictionary = {}
	for lat in [0, 18, -18]:
		for lon in [0, -20, 20, -13, 13]:
			names[_world.planet.get_biome_name_at(Transforms.lat_lon_to_unit_dir(deg_to_rad(float(lat)), deg_to_rad(float(lon))))] = true
	_crit(names.size() >= 4, "4 multiple distinct biomes (%d)" % names.size())
	_crit(_world.atmosphere != null and _world.world_lighting != null and _world.star != null, "5 atmosphere, lighting and star present")
	_crit(_world.surface_facilities != null and _world.surface_facilities.facilities.size() >= 5, "6 five surface facilities")
	_crit(_world.mothership_manager != null and _world.mothership_manager.ships.size() == 2, "7 two motherships (Helion + Cinder)")
	var before: bool = _world.mothership_manager.is_hangar_doors_open()
	_world.toggle_hangar_doors()
	_crit(_world.mothership_manager.is_hangar_doors_open() != before, "8 hangar doors toggle")
	var shifts: int = _world.floating_origin.shift_count
	var far: Vector3 = _world.explorer.get_planet_position() + Vector3(5000, 0, 0)
	_world.floating_origin.check_and_shift(far)
	_crit(_world.floating_origin.shift_count > shifts, "9 floating origin shifts at distance")


func _orbital() -> void:
	print("[orbital]")
	var o: OrbitalEnvironmentManager = _world.orbital_environment
	var f: Dictionary = _world.atmosphere.get_cloud_formations()
	_crit(f["high_wisps"] > 0.0 and f["volcanic_plumes"] > 0.0 and f["storm_bands"] > 0.0, "10 three cloud formations active at HIGH")
	_crit(_world.space_environment.galactic_haze != null and _world.space_environment.exoplanet != null and _world.space_environment.starfield != null, "11 starfield + exoplanet + galactic haze")
	var alt_ok: bool = true
	for key in o.structures:
		var alt: float = (o.structures[key]["base_pos"] as Vector3).length() - _world.world_config.planet_radius
		alt_ok = alt_ok and alt >= 1799.0 and alt <= 3201.0
	_crit(o.structures.size() >= 4 + OrbitalEnvironmentManager.SATELLITE_COUNT and alt_ok, "12 all orbital structures within 1,800-3,200 m")
	var names_ok: bool = o.structures.has("station") and o.structures.has("refinery") and o.structures.has("beacon") and o.structures.has("hub") and o.structures.has("satellite_0")
	_crit(names_ok, "13 station, refinery, satellites, beacon array, docking hub")
	var dc: Dictionary = o.debris_field.call("get_tier_collision_counts")
	var tiers: Dictionary = o.debris_field.call("get_tier_counts")
	_crit(dc["large"] > 0 and dc["medium"] > 0 and dc["small"] == 0 and dc["dust"] == 0 and tiers["small"] > 0 and tiers["dust"] > 0, "14 four-tier debris (collision only on tiers 1-2)")
	var sig: int = o.debris_field.call("get_signature")
	o.rebuild()
	_crit(int(o.debris_field.call("get_signature")) == sig, "15 debris deterministic from world_seed")


func _streaming_and_landmarks() -> void:
	print("[streaming + landmarks]")
	var lm: LandmarkManager = _world.landmark_manager
	var names: Array[String] = []
	for i in lm.get_count():
		names.append(String(lm.get_landmark(i)["name"]))
	_crit(names.has("Orbital Debris Field") and names.has("Abandoned Research Station") and names.has("Broken Orbital Refinery") and names.has("Orbital Docking Hub"), "16 orbital landmarks registered")
	var close: bool = true
	for idx in [20, 21, 22, 23]:
		_world.teleport_to_landmark(idx)
		await _frames(1)
		var key: String = String(lm.get_landmark(idx)["orbital"])
		var target: Vector3 = _world.orbital_environment.get_planet_position(key)
		var pl: Dictionary = OrbitalEnvironmentManager.placement(key, _world.world_config.planet_radius)
		close = close and _world.explorer.get_planet_position().distance_to(target) < float(pl["standoff"]) * 1.2
	_crit(close, "17 orbital teleports land beside each structure")
	for i in 8:
		await _frames(1)
	var s: Dictionary = _world.streaming.get_streaming_stats()
	_crit(int(s["active_regions"]) + int(s["ready_regions"]) + int(s["loading_regions"]) >= 1, "18 streaming activates regions near the camera")
	var o: OrbitalEnvironmentManager = _world.orbital_environment
	var key0: String = "station"
	var rp: Vector3 = o.get_structure(key0).position
	var shift: Vector3 = Vector3(777, -333, 1200)
	var prior: Vector3 = o.current_origin
	o.apply_origin(prior + shift)
	var moved: Vector3 = o.get_structure(key0).position
	var ok_shift: bool = moved.distance_to(rp - shift) < 0.01
	o.apply_origin(prior)
	_crit(ok_shift, "19 orbital structures re-base on origin shift")


func _weather_destruction_audio() -> void:
	print("[weather / destruction / audio]")
	var w: WeatherEffectsController = _world.weather
	w.storm_base = 0.0
	for i in 200:
		w.follow(Vector3.ZERO, Vector3.UP, "Ashen Wastes", 20.0, 0.05)
	var iron_ok: bool = w.storm_base > 0.9
	for i in 200:
		w.follow(Vector3.ZERO, Vector3.UP, "Terminus Basin", 20.0, 0.05)
	_crit(iron_ok and w.storm_base < 0.01 and w.ash_plume != null and w.arc_zones.size() >= 3, "20 dust storms (biome gated) + volcanic plumes + arc zones")
	var d: DestructionStateController = _world.destruction
	var ids: Array[StringName] = d.get_section_ids()
	d.cycle_all_states()
	var cycled: bool = true
	for id in ids:
		cycled = cycled and d.get_state(id) == DestructionStateController.DestructionState.DAMAGED
	d.set_section_state(&"mining_derrick_rig", DestructionStateController.DestructionState.DESTROYED)
	var kept: bool = d.has_rubble_collision(&"mining_derrick_rig")
	d.unload_section_visual(&"mining_derrick_rig")
	d.load_section_visual(&"mining_derrick_rig")
	_crit(ids.size() == 5 and cycled and kept and d.get_state(&"mining_derrick_rig") == DestructionStateController.DestructionState.DESTROYED and d.has_rubble_collision(&"mining_derrick_rig"), "21 destruction states cycle + survive unload/reload")
	for id in ids:
		d.set_section_state(id, DestructionStateController.DestructionState.INTACT)
	var a: WorldAudioController = _world.world_audio
	var buses_ok: bool = true
	for b in WorldAudioController.BUS_NAMES:
		buses_ok = buses_ok and AudioServer.get_bus_index(b) != -1
	_crit(buses_ok and a.get_zone_count() >= 9, "22 four audio buses + 9 audio zones")
	a.update_audio(Vector3.ZERO, 3000.0, false, 0.0, 1.0, true)
	var vac_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Environment"))
	a.update_audio(Vector3.ZERO, 5.0, false, 0.0, 1.0, true)
	var air_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Environment"))
	a.update_audio(Vector3.ZERO, 3000.0, true, 0.0, 1.0, true)
	var int_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Environment"))
	a.update_audio(Vector3.ZERO, 5.0, false, 0.0, 1.0, true)
	_crit(vac_db <= -50.0 and air_db > -1.0 and int_db > vac_db + 20.0 and a.get_playing_count() <= WorldAudioController.BUDGET["HIGH"], "23 vacuum acoustics (vacuum %.0f dB, air %.0f dB, interior %.0f dB)" % [vac_db, air_db, int_db])


func _quality_and_regen() -> void:
	print("[quality + regeneration]")
	var counts: Array[float] = []
	var ok: bool = true
	for p in ["LOW", "MEDIUM", "HIGH", "ULTRA"]:
		_world.set_quality_preset(p)
		await _frames(1)
		var f: Dictionary = _world.atmosphere.get_cloud_formations()
		counts.append(float(f["high_wisps"]) + float(f["storm_bands"]) + float(f["volcanic_plumes"]))
		ok = ok and _world.orbital_environment.debris_field.call("get_tier_counts")["small"] > 0
	_crit(ok and counts[0] < counts[1] and counts[1] < counts[2] and counts[2] < counts[3], "24 all four quality presets scale clouds + debris (%s)" % str(counts))
	_world.set_quality_preset("HIGH")
	var sig: int = _world.orbital_environment.debris_field.call("get_signature")
	_world.regenerate_world(_world.world_config.world_seed)
	await _frames(2)
	_crit(_world.orbital_environment.debris_field != null and int(_world.orbital_environment.debris_field.call("get_signature")) == sig and _world.destruction.get_section_ids().size() == 5, "25 regeneration rebuilds all Wave 5 systems deterministically")


func _ui_and_docs() -> void:
	print("[ui + docs]")
	# Extra (non-counted) sanity: K hotkey action + debug button wiring + architecture doc present.
	var got: Array[StringName] = []
	_world.explorer.action_requested.connect(func(a: StringName) -> void: got.append(a))
	_world.explorer.call("_on_key", KEY_K)
	print("  info K hotkey emits: %s" % str(got))
	if not got.has(&"cycle_destruction"):
		_failures += 1
		print("  FAIL K hotkey does not emit cycle_destruction")
	var found: bool = _find_button(_world.debug_ui, "Cycle Destruction")
	if not found:
		_failures += 1
		print("  FAIL Cycle Destruction button missing")
	if not FileAccess.file_exists("res://docs/APOGEX_WORLD_ARCHITECTURE.md"):
		_failures += 1
		print("  FAIL architecture doc missing")
	var diag: Dictionary = _world.get_diagnostics()
	for k in ["streaming", "destruction", "audio", "orbital"]:
		if not diag.has(k):
			_failures += 1
			print("  FAIL diagnostics missing %s" % k)


func _find_button(n: Node, text: String) -> bool:
	if n is Button and (n as Button).text.begins_with(text):
		return true
	for c in n.get_children():
		if _find_button(c, text):
			return true
	return false
