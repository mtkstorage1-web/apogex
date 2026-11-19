extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1

# Pareto comparison includes purchase cost, mass, demand and every performance delta.
func dominates(a: Dictionary, b: Dictionary) -> bool:
	var better := false
	for key in ["price", "mass_kg", "load_kw", "armor", "thrust_kn", "exhaust_mult", "gen_kw", "battery_kwh", "radiator", "cargo_flags", "fuel_kg", "life", "turret_damage_mult", "scan_mult", "handling"]:
		var direction := -1.0 if key in ["price", "mass_kg", "load_kw", "armor"] else 1.0
		var diff := (float(a.get(key, 0)) - float(b.get(key, 0))) * direction
		if diff < -0.00001: return false
		if diff > 0.00001: better = true
	return better

func _initialize() -> void:
	var s := Sim.new(4242)
	var ds := s.design_sheet()
	check(ds["dry"] == 670.0 and ds["wet"] == 750.0 and ds["propellant"] == 80.0, "exact Kestrel masses")
	check(ds["thrust"] == 10.4 and ds["generation"] == 9.0 and ds["load"] == 5.4 and ds["cargo"] == 6, "exact Kestrel systems")
	check(ds["twr"] == 10400.0 / (750.0 * Sim.G0) and ds["dv"] == Sim.EXHAUST * log(750.0 / 670.0), "exact Kestrel TWR and delta-v")
	var cheapest := 0
	var premium := 0
	var names := {}
	for p in Sim.PARTS_DEF:
		var lo := 999999
		var hi := 0
		check(ShipCatalog.variant(p["id"], "kestrel")["price"] == p["price"], "Kestrel price " + p["id"])
		for family in ShipCatalog.FAMILIES:
			var v := ShipCatalog.variant(p["id"], family)
			check(not names.has(v["name"]), "unique " + v["name"])
			names[v["name"]] = true
			lo = mini(lo, v["price"])
			hi = maxi(hi, v["price"])
			for other in ShipCatalog.FAMILIES:
				if other != family:
					check(not dominates(v, ShipCatalog.variant(p["id"], other)), "no dominance %s %s / %s" % [p["id"], family, other])
		cheapest += lo
		premium += hi
	check(cheapest >= 1800 and cheapest <= 2200 and premium >= 5500, "price targets: %d / %d" % [cheapest, premium])
	var mixed := ShipCatalog.default_loadout()
	mixed["cargo"] = "hauler"
	mixed["port"] = "lancer"
	var stats := ShipCatalog.loadout_stats(mixed)
	check(stats["cost"] != ShipCatalog.loadout_cost({}) and stats["wet_mass"] > 750 and stats["twr"] > ds["twr"] and stats["cargo_capacity"] == 12, "mixed cost, mass, TWR and cargo")
	var balanced_budget := s.route_budget(Sim.ROUTES[1])
	var outbound := 750.0 * (1.0 - exp(-210.0 / Sim.EXHAUST))
	check(balanced_budget["outbound"] == outbound and balanced_budget["return_reserve"] == (750.0 - outbound) * (1.0 - exp(-95.0 / Sim.EXHAUST)), "exact Kestrel route budget")
	for family in ShipCatalog.FAMILIES:
		var family_loadout := ShipCatalog.default_loadout()
		for slot in family_loadout: family_loadout[slot] = family
		var summary := ShipCatalog.loadout_stats(family_loadout)
		print("FAMILY %s cost %d wet %.0f thrust %.1f TWR %.3f fuel %.0f dv %.1f cargo %d armor %.2f turret %.2f scan %.2f handling %.2f power %.2f" % [family, summary["cost"], summary["wet_mass"], summary["thrust_kn"], summary["twr"], summary["fuel"], summary["dv"], summary["cargo_capacity"], summary["armor"], summary["turret_damage_mult"], summary["scan_mult"], summary["handling"], summary["power_margin"]])
	var resilient := Sim.new(13)
	check(resilient.set_variant("keel", "bulwark"), "armored keel purchased")
	resilient.damage_ship(10.0)
	check(is_equal_approx(resilient.hull, 92.2), "armor scales incoming ship damage")
	var explorer := Sim.new(14)
	check(explorer.set_variant("port", "halo") and explorer.set_variant("battery", "halo"), "explorer systems purchased")
	check(explorer.exhaust_velocity > Sim.EXHAUST and explorer.power_capacity == 10.0, "engine efficiency and battery capacity applied")
	check(explorer.set_upgrade("reserve", true), "reserve upgrade stacks with variants")
	var mass_before := explorer.wet_mass
	var fuel_before := explorer.propellant
	explorer.refresh_loadout()
	check(explorer.wet_mass == mass_before and explorer.propellant == fuel_before, "refresh idempotent and preserves upgrades")
	explorer.propellant -= 10.0
	explorer.refresh_loadout()
	check(explorer.propellant == fuel_before - 10.0, "refresh preserves fuel consumed")
	var restored := Sim.new(15)
	restored.loadout = JSON.parse_string(JSON.stringify(explorer.loadout))
	restored.refresh_loadout()
	check(restored.exhaust_velocity == explorer.exhaust_velocity and restored.power_capacity == explorer.power_capacity, "loadout JSON round trip")
	var before := s.credits
	check(s.set_variant("cargo", "hauler") and s.credits == before - 360, "initial choice purchases full price")
	check(s.set_variant("cargo", "lancer") and s.credits == before - 130, "swap refunds difference")
	check(s.set_variant("cargo", "halo") and s.credits == before - 360, "swap charges difference")
	s.credits = 0
	var old := s.loadout.duplicate()
	check(not s.set_variant("reactor", "halo") and s.loadout == old and s.credits == 0, "insufficient funds atomic")
	check(not s.set_variant("invalid", "halo") and not s.set_variant("keel", "invalid"), "invalid ids rejected")
	s.credits = 4800
	s.auto_build["enabled"] = true
	check(not s.set_variant("keel", "lancer"), "choice locked when auto build begins")
	s.auto_build["enabled"] = false
	s.parts[0]["stage"] = "carried"
	check(not s.set_variant("keel", "lancer"), "choice locked after manual build begins")
	var automatic := Sim.new(9)
	automatic.loadout.clear()
	automatic.auto_build["enabled"] = true
	automatic.auto_assemble(Sim.AUTO_BUILD_SECONDS)
	check(automatic.all_parts_bought() and automatic.secured_count() == 12 and automatic.credits == 4800 - ShipCatalog.loadout_cost({}), "auto build defaults and charges Kestrel")
	var first := Sim.new(123)
	var second := Sim.new(123)
	var third := Sim.new(124)
	var different := false
	for i in range(1, 4):
		check(first.teams[i]["loadout"] == second.teams[i]["loadout"], "seeded rival %d" % i)
		different = different or first.teams[i]["loadout"] != third.teams[i]["loadout"]
	check(different and first.rng_state == first.match_seed, "rivals vary by seed without consuming gameplay RNG")
	print("RESULT ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(failures)
