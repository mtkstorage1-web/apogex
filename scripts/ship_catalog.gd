## Variant values are deltas against the original 1x Kestrel simulation.
## Multiplier deltas are additive, then applied once; armor is damage taken (lower is better).
class_name ShipCatalog
extends RefCounted

const BUILD_ORDER := ["reactor", "engine", "bridge", "keel", "port", "thruster", "battery", "coolant", "scrubber", "stores", "cargo", "antenna"]

const FAMILIES := {
  "kestrel": {
    "id": "kestrel",
    "name": "Kestrel",
    "display_name": "Kestrel",
    "tagline": "Balanced and dependable",
    "color": "#f79442",
    "colour": "#f79442",
    "prefab_path": "res://scenes/prefabs/Kestrel.tscn"
  },
  "lancer": {
    "id": "lancer",
    "name": "Lancer",
    "display_name": "Lancer",
    "tagline": "Speed before steel",
    "color": "#6edfee",
    "colour": "#6edfee",
    "prefab_path": "res://scenes/prefabs/ships/lancer.tscn"
  },
  "hauler": {
    "id": "hauler",
    "name": "Hauler",
    "display_name": "Hauler",
    "tagline": "Room for the frontier",
    "color": "#d6b46b",
    "colour": "#d6b46b",
    "prefab_path": "res://scenes/prefabs/ships/hauler.tscn"
  },
  "halo": {
    "id": "halo",
    "name": "Halo",
    "display_name": "Halo",
    "tagline": "Reach beyond the horizon",
    "color": "#b9a5ef",
    "colour": "#b9a5ef",
    "prefab_path": "res://scenes/prefabs/ships/halo.tscn"
  },
  "bulwark": {
    "id": "bulwark",
    "name": "Bulwark",
    "display_name": "Bulwark",
    "tagline": "Hold the line",
    "color": "#d77981",
    "colour": "#d77981",
    "prefab_path": "res://scenes/prefabs/ships/bulwark.tscn"
  }
}
const VARIANTS := {
  "keel": {
    "kestrel": {
      "name": "Kestrel Standard Pressure Keel",
      "price": 220,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Pressure Keel",
      "price": 143,
      "mass_kg": -8,
      "armor": 0.15,
      "fuel_kg": -8,
      "advantage": "-8 kg dry mass; Lower purchase cost.",
      "drawback": "-8 kg fuel; +15% damage taken."
    },
    "hauler": {
      "name": "Hauler Atlas Pressure Keel",
      "price": 132,
      "mass_kg": 12,
      "fuel_kg": 35,
      "armor": 0.05,
      "advantage": "+35 kg fuel; Lower purchase cost.",
      "drawback": "+12 kg dry mass; +5% damage taken."
    },
    "halo": {
      "name": "Halo Farstar Pressure Keel",
      "price": 396,
      "mass_kg": 4,
      "fuel_kg": 15,
      "armor": 0.08,
      "advantage": "+15 kg fuel.",
      "drawback": "+4 kg dry mass; +8% damage taken; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Pressure Keel",
      "price": 385,
      "mass_kg": 18,
      "armor": -0.22,
      "fuel_kg": -4,
      "advantage": "-22% damage taken.",
      "drawback": "+18 kg dry mass; -4 kg fuel; Higher purchase cost."
    }
  },
  "port": {
    "kestrel": {
      "name": "Kestrel Standard Vector Drive",
      "price": 180,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Vector Drive",
      "price": 117,
      "mass_kg": -8,
      "thrust_kn": 1.6,
      "load_kw": 0.25,
      "advantage": "-8 kg dry mass; +1.6 kN thrust; Lower purchase cost.",
      "drawback": "+0.25 kW draw."
    },
    "hauler": {
      "name": "Hauler Atlas Vector Drive",
      "price": 140,
      "mass_kg": 12,
      "thrust_kn": -0.6,
      "load_kw": -0.15,
      "advantage": "-0.15 kW draw; Lower purchase cost.",
      "drawback": "+12 kg dry mass; -0.6 kN thrust."
    },
    "halo": {
      "name": "Halo Farstar Vector Drive",
      "price": 324,
      "mass_kg": 4,
      "thrust_kn": -0.4,
      "exhaust_mult": 0.16,
      "load_kw": -0.1,
      "advantage": "-0.1 kW draw; +16% exhaust velocity.",
      "drawback": "+4 kg dry mass; -0.4 kN thrust; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Vector Drive",
      "price": 315,
      "mass_kg": 18,
      "thrust_kn": 0.5,
      "load_kw": 0.4,
      "armor": -0.03,
      "advantage": "+0.5 kN thrust; -3% damage taken.",
      "drawback": "+18 kg dry mass; +0.4 kW draw; Higher purchase cost."
    }
  },
  "bridge": {
    "kestrel": {
      "name": "Kestrel Standard Navigator",
      "price": 300,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Navigator",
      "price": 195,
      "mass_kg": -8,
      "handling": 0.28,
      "load_kw": 0.15,
      "advantage": "-8 kg dry mass; +28% handling; Lower purchase cost.",
      "drawback": "+0.15 kW draw."
    },
    "hauler": {
      "name": "Hauler Atlas Navigator",
      "price": 234,
      "mass_kg": 12,
      "handling": -0.12,
      "load_kw": -0.15,
      "advantage": "-0.15 kW draw; Lower purchase cost.",
      "drawback": "+12 kg dry mass; -12% handling."
    },
    "halo": {
      "name": "Halo Farstar Navigator",
      "price": 540,
      "mass_kg": 4,
      "handling": 0.08,
      "scan_mult": 0.08,
      "advantage": "+8% scan speed; +8% handling.",
      "drawback": "+4 kg dry mass; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Navigator",
      "price": 525,
      "mass_kg": 18,
      "handling": -0.06,
      "armor": -0.06,
      "advantage": "-6% damage taken.",
      "drawback": "+18 kg dry mass; -6% handling; Higher purchase cost."
    }
  },
  "reactor": {
    "kestrel": {
      "name": "Kestrel Standard Bus Core",
      "price": 400,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Bus Core",
      "price": 260,
      "mass_kg": -8,
      "gen_kw": -0.8,
      "load_kw": -0.1,
      "advantage": "-8 kg dry mass; -0.1 kW draw; Lower purchase cost.",
      "drawback": "-0.8 kW generation."
    },
    "hauler": {
      "name": "Hauler Atlas Bus Core",
      "price": 312,
      "mass_kg": 12,
      "gen_kw": 1,
      "load_kw": 0.3,
      "advantage": "+1 kW generation; Lower purchase cost.",
      "drawback": "+12 kg dry mass; +0.3 kW draw."
    },
    "halo": {
      "name": "Halo Farstar Bus Core",
      "price": 720,
      "mass_kg": 4,
      "gen_kw": 4,
      "load_kw": 0.15,
      "advantage": "+4 kW generation.",
      "drawback": "+4 kg dry mass; +0.15 kW draw; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Bus Core",
      "price": 700,
      "mass_kg": 18,
      "gen_kw": 2,
      "load_kw": 0.6,
      "advantage": "+2 kW generation.",
      "drawback": "+18 kg dry mass; +0.6 kW draw; Higher purchase cost."
    }
  },
  "battery": {
    "kestrel": {
      "name": "Kestrel Standard Cell Bank",
      "price": 280,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Cell Bank",
      "price": 182,
      "mass_kg": -8,
      "battery_kwh": -1.2,
      "load_kw": -0.1,
      "advantage": "-8 kg dry mass; -0.1 kW draw; Lower purchase cost.",
      "drawback": "-1.2 kWh battery."
    },
    "hauler": {
      "name": "Hauler Atlas Cell Bank",
      "price": 218,
      "mass_kg": 12,
      "battery_kwh": 1,
      "load_kw": 0.1,
      "advantage": "+1 kWh battery; Lower purchase cost.",
      "drawback": "+12 kg dry mass; +0.1 kW draw."
    },
    "halo": {
      "name": "Halo Farstar Cell Bank",
      "price": 504,
      "mass_kg": 4,
      "battery_kwh": 4,
      "load_kw": -0.15,
      "advantage": "-0.15 kW draw; +4 kWh battery.",
      "drawback": "+4 kg dry mass; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Cell Bank",
      "price": 490,
      "mass_kg": 18,
      "battery_kwh": 2,
      "load_kw": 0.2,
      "advantage": "+2 kWh battery.",
      "drawback": "+18 kg dry mass; +0.2 kW draw; Higher purchase cost."
    }
  },
  "coolant": {
    "kestrel": {
      "name": "Kestrel Standard Heat Wing",
      "price": 240,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Heat Wing",
      "price": 156,
      "mass_kg": -8,
      "radiator": -0.15,
      "load_kw": -0.1,
      "advantage": "-8 kg dry mass; -0.1 kW draw; Lower purchase cost.",
      "drawback": "-15% cooling."
    },
    "hauler": {
      "name": "Hauler Atlas Heat Wing",
      "price": 187,
      "mass_kg": 12,
      "radiator": 0.1,
      "load_kw": 0.1,
      "advantage": "+10% cooling; Lower purchase cost.",
      "drawback": "+12 kg dry mass; +0.1 kW draw."
    },
    "halo": {
      "name": "Halo Farstar Heat Wing",
      "price": 432,
      "mass_kg": 4,
      "radiator": 0.4,
      "load_kw": 0.1,
      "advantage": "+40% cooling.",
      "drawback": "+4 kg dry mass; +0.1 kW draw; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Heat Wing",
      "price": 420,
      "mass_kg": 18,
      "radiator": 0.25,
      "load_kw": 0.2,
      "advantage": "+25% cooling.",
      "drawback": "+18 kg dry mass; +0.2 kW draw; Higher purchase cost."
    }
  },
  "cargo": {
    "kestrel": {
      "name": "Kestrel Standard Sample Rack",
      "price": 200,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Sample Rack",
      "price": 130,
      "mass_kg": -8,
      "cargo_flags": -2,
      "load_kw": -0.1,
      "advantage": "-8 kg dry mass; -0.1 kW draw; Lower purchase cost.",
      "drawback": "-2  flag capacity."
    },
    "hauler": {
      "name": "Hauler Atlas Sample Rack",
      "price": 360,
      "mass_kg": 12,
      "cargo_flags": 6,
      "load_kw": 0.3,
      "advantage": "+6  flag capacity.",
      "drawback": "+12 kg dry mass; +0.3 kW draw; Higher purchase cost."
    },
    "halo": {
      "name": "Halo Farstar Sample Rack",
      "price": 360,
      "mass_kg": 4,
      "cargo_flags": 1,
      "load_kw": -0.05,
      "advantage": "-0.05 kW draw; +1  flag capacity.",
      "drawback": "+4 kg dry mass; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Sample Rack",
      "price": 350,
      "mass_kg": 18,
      "cargo_flags": -1,
      "armor": -0.08,
      "advantage": "-8% damage taken.",
      "drawback": "+18 kg dry mass; -1  flag capacity; Higher purchase cost."
    }
  },
  "scrubber": {
    "kestrel": {
      "name": "Kestrel Standard Breather",
      "price": 260,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Breather",
      "price": 169,
      "mass_kg": -8,
      "life": -0.15,
      "load_kw": -0.15,
      "advantage": "-8 kg dry mass; -0.15 kW draw; Lower purchase cost.",
      "drawback": "-15% life resilience."
    },
    "hauler": {
      "name": "Hauler Atlas Breather",
      "price": 203,
      "mass_kg": 12,
      "life": 0.1,
      "load_kw": 0.1,
      "advantage": "+10% life resilience; Lower purchase cost.",
      "drawback": "+12 kg dry mass; +0.1 kW draw."
    },
    "halo": {
      "name": "Halo Farstar Breather",
      "price": 468,
      "mass_kg": 4,
      "life": 0.4,
      "load_kw": -0.1,
      "advantage": "-0.1 kW draw; +40% life resilience.",
      "drawback": "+4 kg dry mass; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Breather",
      "price": 455,
      "mass_kg": 18,
      "life": 0.2,
      "load_kw": 0.2,
      "advantage": "+20% life resilience.",
      "drawback": "+18 kg dry mass; +0.2 kW draw; Higher purchase cost."
    }
  },
  "stores": {
    "kestrel": {
      "name": "Kestrel Standard Trail Stores",
      "price": 120,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Trail Stores",
      "price": 78,
      "mass_kg": -8,
      "fuel_kg": -5,
      "life": -0.1,
      "advantage": "-8 kg dry mass; Lower purchase cost.",
      "drawback": "-5 kg fuel; -10% life resilience."
    },
    "hauler": {
      "name": "Hauler Atlas Trail Stores",
      "price": 94,
      "mass_kg": 12,
      "fuel_kg": 25,
      "life": 0.1,
      "advantage": "+25 kg fuel; +10% life resilience; Lower purchase cost.",
      "drawback": "+12 kg dry mass."
    },
    "halo": {
      "name": "Halo Farstar Trail Stores",
      "price": 216,
      "mass_kg": 4,
      "fuel_kg": 12,
      "life": 0.3,
      "advantage": "+12 kg fuel; +30% life resilience.",
      "drawback": "+4 kg dry mass; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Trail Stores",
      "price": 210,
      "mass_kg": 18,
      "life": 0.2,
      "armor": -0.04,
      "advantage": "+20% life resilience; -4% damage taken.",
      "drawback": "+18 kg dry mass; Higher purchase cost."
    }
  },
  "engine": {
    "kestrel": {
      "name": "Kestrel Standard Dorsal Cannon",
      "price": 360,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Dorsal Cannon",
      "price": 234,
      "mass_kg": -8,
      "turret_damage_mult": -0.1,
      "load_kw": -0.2,
      "advantage": "-8 kg dry mass; -0.2 kW draw; Lower purchase cost.",
      "drawback": "-10% turret output."
    },
    "hauler": {
      "name": "Hauler Atlas Dorsal Cannon",
      "price": 281,
      "mass_kg": 12,
      "turret_damage_mult": -0.2,
      "load_kw": -0.3,
      "advantage": "-0.3 kW draw; Lower purchase cost.",
      "drawback": "+12 kg dry mass; -20% turret output."
    },
    "halo": {
      "name": "Halo Farstar Dorsal Cannon",
      "price": 648,
      "mass_kg": 4,
      "turret_damage_mult": 0.1,
      "load_kw": -0.1,
      "advantage": "-0.1 kW draw; +10% turret output.",
      "drawback": "+4 kg dry mass; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Dorsal Cannon",
      "price": 630,
      "mass_kg": 18,
      "turret_damage_mult": 0.65,
      "load_kw": 0.8,
      "advantage": "+65% turret output.",
      "drawback": "+18 kg dry mass; +0.8 kW draw; Higher purchase cost."
    }
  },
  "thruster": {
    "kestrel": {
      "name": "Kestrel Standard Impulse Drive",
      "price": 300,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Impulse Drive",
      "price": 195,
      "mass_kg": -8,
      "thrust_kn": 1.6,
      "load_kw": 0.25,
      "advantage": "-8 kg dry mass; +1.6 kN thrust; Lower purchase cost.",
      "drawback": "+0.25 kW draw."
    },
    "hauler": {
      "name": "Hauler Atlas Impulse Drive",
      "price": 234,
      "mass_kg": 12,
      "thrust_kn": -0.6,
      "load_kw": -0.15,
      "advantage": "-0.15 kW draw; Lower purchase cost.",
      "drawback": "+12 kg dry mass; -0.6 kN thrust."
    },
    "halo": {
      "name": "Halo Farstar Impulse Drive",
      "price": 540,
      "mass_kg": 4,
      "thrust_kn": -0.4,
      "exhaust_mult": 0.16,
      "load_kw": -0.1,
      "advantage": "-0.1 kW draw; +16% exhaust velocity.",
      "drawback": "+4 kg dry mass; -0.4 kN thrust; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Impulse Drive",
      "price": 525,
      "mass_kg": 18,
      "thrust_kn": 0.5,
      "load_kw": 0.4,
      "armor": -0.03,
      "advantage": "+0.5 kN thrust; -3% damage taken.",
      "drawback": "+18 kg dry mass; +0.4 kW draw; Higher purchase cost."
    }
  },
  "antenna": {
    "kestrel": {
      "name": "Kestrel Standard Signal Crown",
      "price": 200,
      "mass_kg": 0,
      "advantage": "Balanced, proven equipment.",
      "drawback": "No specialist performance bonus."
    },
    "lancer": {
      "name": "Lancer Needle Signal Crown",
      "price": 130,
      "mass_kg": -8,
      "scan_mult": 0.15,
      "load_kw": 0.1,
      "advantage": "-8 kg dry mass; +15% scan speed; Lower purchase cost.",
      "drawback": "+0.1 kW draw."
    },
    "hauler": {
      "name": "Hauler Atlas Signal Crown",
      "price": 156,
      "mass_kg": 12,
      "scan_mult": -0.12,
      "load_kw": -0.15,
      "advantage": "-0.15 kW draw; Lower purchase cost.",
      "drawback": "+12 kg dry mass; -12% scan speed."
    },
    "halo": {
      "name": "Halo Farstar Signal Crown",
      "price": 360,
      "mass_kg": 4,
      "scan_mult": 0.45,
      "load_kw": 0.15,
      "advantage": "+45% scan speed.",
      "drawback": "+4 kg dry mass; +0.15 kW draw; Higher purchase cost."
    },
    "bulwark": {
      "name": "Bulwark Bastion Signal Crown",
      "price": 350,
      "mass_kg": 18,
      "scan_mult": 0.1,
      "armor": -0.03,
      "advantage": "-3% damage taken; +10% scan speed.",
      "drawback": "+18 kg dry mass; Higher purchase cost."
    }
  }
}

static func variant(slot: String, family: String) -> Dictionary:
	return VARIANTS.get(slot, {}).get(family, {}).duplicate(true)

static func default_loadout() -> Dictionary:
	var result := {}
	for slot in VARIANTS: result[slot] = "kestrel"
	return result

static func loadout_cost(loadout: Dictionary) -> int:
	return int(loadout_stats(loadout)["cost"])

static func loadout_stats(loadout: Dictionary) -> Dictionary:
	var s := {"mass_kg": 670.0, "thrust_kn": 10.4, "gen_kw": 9.0, "load_kw": 5.4,
		"cargo_capacity": 6, "fuel": 80.0, "exhaust_mult": 1.0, "armor": 1.0,
		"turret_damage_mult": 1.0, "scan_mult": 1.0, "handling": 1.0,
		"battery_kwh": 6.0, "radiator": 1.0, "life": 1.0, "cost": 0}
	var counts := {}
	for slot in VARIANTS:
		var family: String = str(loadout.get(slot, "kestrel"))
		if not FAMILIES.has(family): family = "kestrel"
		counts[family] = int(counts.get(family, 0)) + 1
		var v: Dictionary = VARIANTS[slot][family]
		s["cost"] += v["price"]
		for key in v:
			var target: String = {"fuel_kg": "fuel", "cargo_flags": "cargo_capacity"}.get(key, key)
			if s.has(target) and key != "price": s[target] += v[key]
	var dominant := "kestrel"
	var most := 0
	var bonuses: Array[String] = []
	for family in FAMILIES:
		var n: int = counts.get(family, 0)
		if n > most:
			most = n
			dominant = family
		if n >= 3:
			match family:
				"lancer":
					s["handling"] += 0.05
					bonuses.append("Lancer: +5% handling")
				"hauler":
					s["cargo_capacity"] += 1
					bonuses.append("Hauler: +1 flag capacity")
				"halo":
					s["exhaust_mult"] += 0.03
					bonuses.append("Halo: +3% exhaust velocity")
				"bulwark":
					s["armor"] -= 0.03
					bonuses.append("Bulwark: -3% damage taken")
	s["dominant_family"] = dominant
	s["design_name"] = FAMILIES[dominant]["name"] + (" Hybrid" if most < 12 else "")
	s["synergy"] = "; ".join(bonuses) if not bonuses.is_empty() else "No set bonus"
	s["exhaust"] = 360.0 * 9.80665 * s["exhaust_mult"]
	s["wet_mass"] = s["mass_kg"] + s["fuel"]
	s["total_mass"] = s["wet_mass"]
	s["twr"] = s["thrust_kn"] * 1000.0 / (s["wet_mass"] * 9.80665)
	s["dv"] = s["exhaust"] * log(s["wet_mass"] / s["mass_kg"])
	s["power_margin"] = s["gen_kw"] - s["load_kw"]
	return s
