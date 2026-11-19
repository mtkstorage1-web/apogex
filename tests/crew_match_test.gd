extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

func _initialize() -> void:
	check(is_equal_approx(Sim.field_damage(0, 10.0), 34.0), "carbine close damage")
	check(Sim.field_damage(1, 10.0) > Sim.field_damage(2, 10.0), "weapons have distinct damage profiles")
	check(Sim.field_damage(0, 80.0) < Sim.field_damage(0, 10.0), "ranged damage falls off")
	check(Sim.field_damage(0, 10.0, true) > Sim.field_damage(0, 10.0), "headshots reward precision")
	check(Sim.field_damage(3, 10.0) == 0.0, "scanner is not a firearm")
	var s := Sim.new(1717)
	check(s.cycle_order() == "recover" and s.cycle_order() == "regroup" and s.cycle_order() == "escort", "crew orders cycle")
	check(not s.set_priority(-1) and not s.set_priority(99), "priority rejects invalid flags")
	check(s.set_priority(8) and s.frontier_target(Vector3.ZERO)["id"] == 8, "priority changes the crew target")
	s.phase = "surface"
	s.teams[0]["planet"] = "B"
	s.teams[0]["phase"] = "surface"
	for i in 60: s.scan_flag(8, 0, 3, 0.1, 1.0)
	check(s.metrics["captures"] == 1, "extraction counted once")
	check(s.drop_flag(0, 3, Vector3.ZERO), "raider drops sample")
	check(s.recover_flag(8, 0, 0, 1.0), "pilot can recover a loose sample")
	# A second carrier must not erase the first carrier from the departure guard.
	s.flags[1]["state"] = "ground"
	check(s.recover_flag(1, 0, 2, 1.0), "multiple specialists can carry different samples")
	check(s.load_flag(0, 2, 1.0), "second carrier loads")
	check(not s.depart_frontier(0), "departure blocked while any crew member carries a sample")
	check(s.load_flag(0, 0, 1.0) and s.depart_frontier(0), "departure succeeds after all samples loaded")
	check(s.metrics["loads"] == 2 and s.metrics["recoveries"] == 2, "load and recovery telemetry")
	check(s.flag_counts(0)["delivered"] == 0, "loading still awards no victory score")
	s.arrive_home(0)
	check(s.deliver_flag(0, 1.0) and s.flag_counts(0)["delivered"] == 1, "home delivery scores")
	var warning := Sim.new(42)
	warning.time = warning.limit - 90.05
	warning.tick_match(0.1)
	var count := warning.events.size()
	warning.tick_match(0.1)
	check(warning.events.size() == count, "time warnings fire only once")
	var first := Sim.new(7373)
	var second := Sim.new(7373)
	for i in 2200:
		first.tick_match(0.25)
		second.tick_match(0.25)
	check(first.flags == second.flags and first.teams == second.teams, "same seed replays the same rival decisions")
	print("Crew match rules: %d failures" % failures)
	quit(failures)
