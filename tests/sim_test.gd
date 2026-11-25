extends SceneTree
## Headless rules test: rivals run a whole match; our crew builds, flies, scans, returns, delivers.
func _init() -> void:
	var fails := 0
	var s := Sim.new(4242)
	# Upgrades and credits.
	assert(s.set_upgrade("cargo", true))
	if s.cargo_capacity != 8: fails += 1; print("FAIL cargo cap")
	var ds := s.design_sheet()
	print("TWR %.2f dv %.1f" % [ds["twr"], ds["dv"]])
	# Pick wrong rotation -> place fails; correct -> works.
	var p = s.part_by_id("cargo")
	if not s.pick_part("cargo", 3): fails += 1; print("FAIL pick")
	if s.part_by_id("cargo")["angle"] != 0: pass
	s.rotation[3] = 1
	if s.place_part(3, 1.0): fails += 1; print("FAIL wrong rotation placed")
	s.rotation[3] = 0
	if not s.place_part(3, 1.0): fails += 1; print("FAIL place")
	for b in 3:
		s.fasten_bolt("cargo", b, 3, 0.7, 1.0)
	if p["stage"] != "secured": fails += 1; print("FAIL secure")
	# Auto-build the rest (timed incremental flow; the game defaults to manual crane assembly).
	s.manual_crane_build = false
	s.auto_build["enabled"] = true
	for i in 200: s.tick_rivals(0.1)
	if not s.flight_capable(): fails += 1; print("FAIL build")
	for r in 4:
		s.pick_cargo(s.cargo[r]["id"], r)
		s.stow_cargo(r, 1.0)
	for i in 30:
		s.run_check("pressure", 1, 0.1, 100)
		s.run_check("power", 1, 0.1, 50)
		s.run_check("engine", 0, 0.1, 70)
	if not s.checks.values().all(func(value): return value >= 1.0):
		fails += 1
		print("FAIL checks ", s.checks)
	s.set_location("space")
	for i in 240:
		s.tick_systems(0.1)
		s.tick_rivals(0.1)
		if s.fault != null:
			s.maintain_system(1, 0.1, "reactor")
			s.maintain_system(1, 0.1, "coolant")
			s.maintain_system(1, 0.1, "scrubber")
	s.set_location("planet_c")
	# Scan one flag.
	var steps := 0
	while s.carried_flag(0, 3) == null and steps < 100:
		s.scan_flag(6, 0, 3, 0.1, 1.0); steps += 1
	print("scan steps ", steps)
	if not s.load_flag(0, 3, 1.0): fails += 1; print("FAIL load")
	s.set_location("space")
	if s.deliver_flag(0, 1.0): fails += 1; print("FAIL delivery in space")
	s.set_location("planet_b")
	if s.deliver_flag(0, 1.0): fails += 1; print("FAIL delivery away from home")
	s.set_location("planet_a")
	if not s.deliver_flag(0, 1.0): fails += 1; print("FAIL deliver")
	var guard := 0
	while not s.over and guard < 20000:
		s.tick_match(0.25); guard += 1
	print("over: ", s.reason, " time %.0f" % s.time)
	for t in s.teams: print("  ", t["name"], " delivered ", t["delivered"], " phase ", t["phase"])
	var d := s.debrief()
	print("debrief rank ", d["rank"], " xp ", d["xp"], " patch ", d["patch"])
	var states := {}
	for f in s.flags: states[f["state"]] = states.get(f["state"], 0) + 1
	print("flag states ", states)
	print("RESULT ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(fails)
