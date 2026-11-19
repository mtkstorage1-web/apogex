## Mission Design & Science Simulator, ported from engineering.js.
## Teaching model: daily energy/data budgets, not a flight-certified trajectory solver.
class_name MissionControl
extends RefCounted

const SCENARIOS := [
	{"id": "climate", "name": "A clearer picture", "subtitle": "Earth climate observatory", "body": "Earth", "description": "Map clouds and surface temperatures. Pair imaging with a radiometer, then choose an orbit that revisits the whole planet.", "budget": 125.0, "goal": 2200.0, "solar": 1.0, "weights": {"camera": 1.0, "spectrometer": 0.65, "radar": 0.8, "radiometer": 1.4, "magnetometer": 0.2}, "preferred": ["camera", "radiometer"], "orbit": "sso", "days": 60, "color": "#9cdeb1"},
	{"id": "lunar", "name": "Beneath the dust", "subtitle": "Lunar mineral survey", "body": "Moon", "description": "Find promising mineral deposits from lunar orbit. Spectroscopy reveals composition; radar can reveal structure beneath the surface.", "budget": 165.0, "goal": 2800.0, "solar": 1.0, "weights": {"camera": 0.7, "spectrometer": 1.5, "radar": 1.3, "radiometer": 0.4, "magnetometer": 0.6}, "preferred": ["spectrometer", "radar"], "orbit": "lunar-polar", "days": 60, "color": "#b7a0f3"},
	{"id": "mars", "name": "The next frontier", "subtitle": "Mars reconnaissance", "body": "Mars", "description": "Map landing sites and mineral signatures. Weak sunlight and a long radio link demand larger arrays and a capable antenna.", "budget": 225.0, "goal": 4800.0, "solar": 0.43, "weights": {"camera": 1.2, "spectrometer": 1.2, "radar": 1.0, "radiometer": 0.5, "magnetometer": 0.7}, "preferred": ["camera", "spectrometer"], "orbit": "mars-polar", "days": 90, "color": "#edbd81"},
]
const BUSES := [
	{"id": "light", "name": "Scout bus", "mass": 130.0, "power": 45.0, "cost": 10.0, "storage": 16.0, "hardening": 0.7, "note": "Low mass and cost; small data buffer and limited radiation shielding."},
	{"id": "standard", "name": "Explorer bus", "mass": 220.0, "power": 65.0, "cost": 17.0, "storage": 64.0, "hardening": 1.2, "note": "Balanced structure, onboard computer, thermal control and attitude control."},
	{"id": "hardened", "name": "Sentinel bus", "mass": 320.0, "power": 90.0, "cost": 25.0, "storage": 160.0, "hardening": 1.8, "note": "More shielding and storage improve resilience, but increase mass and idle power."},
]
const ARRAYS := [
	{"id": "compact", "name": "Compact wings", "mass": 60.0, "power": 350.0, "cost": 8.0, "note": "350 W at Earth before eclipse losses."},
	{"id": "standard", "name": "Deployable wings", "mass": 140.0, "power": 750.0, "cost": 16.0, "note": "750 W at Earth; added mass buys a larger power margin."},
	{"id": "large", "name": "Deep-space wings", "mass": 220.0, "power": 1200.0, "cost": 26.0, "note": "1,200 W at Earth; useful when sunlight is weaker at Mars."},
]
const BATTERIES := [
	{"id": "small", "name": "200 Wh pack", "mass": 15.0, "capacity": 200.0, "cost": 3.0, "note": "Lightweight reserve for short eclipses."},
	{"id": "standard", "name": "1,400 Wh pack", "mass": 40.0, "capacity": 1400.0, "cost": 7.0, "note": "A useful compromise between eclipse endurance and mass."},
	{"id": "large", "name": "3,200 Wh pack", "mass": 90.0, "capacity": 3200.0, "cost": 14.0, "note": "A larger buffer for long eclipses and disrupted sunlight."},
]
const RADIOS := [
	{"id": "basic", "name": "Compact X-band", "mass": 12.0, "rate": 2.0, "power": 25.0, "cost": 5.0, "note": "2 Mbps during contact."},
	{"id": "standard", "name": "High-gain X-band", "mass": 30.0, "rate": 8.0, "power": 55.0, "cost": 12.0, "note": "8 Mbps during contact."},
	{"id": "deep", "name": "Deep-space Ka-band", "mass": 75.0, "rate": 25.0, "power": 120.0, "cost": 22.0, "note": "25 Mbps before distance losses."},
]
const INSTRUMENTS := [
	{"id": "camera", "name": "Multispectral camera", "mass": 45.0, "power": 70.0, "cost": 12.0, "rate": 0.8, "science": 5.0, "note": "Maps terrain and clouds."},
	{"id": "spectrometer", "name": "Imaging spectrometer", "mass": 65.0, "power": 95.0, "cost": 18.0, "rate": 0.35, "science": 8.0, "note": "Identifies minerals and atmospheric chemistry."},
	{"id": "radar", "name": "Synthetic aperture radar", "mass": 110.0, "power": 180.0, "cost": 25.0, "rate": 1.5, "science": 7.0, "note": "Sees structure through darkness. Power hungry."},
	{"id": "radiometer", "name": "Thermal radiometer", "mass": 35.0, "power": 45.0, "cost": 9.0, "rate": 0.12, "science": 4.0, "note": "Tracks surface temperature and energy balance."},
	{"id": "magnetometer", "name": "Vector magnetometer", "mass": 15.0, "power": 15.0, "cost": 5.0, "rate": 0.02, "science": 2.0, "note": "Measures magnetic fields. Light and efficient."},
]
const ORBITS := [
	{"id": "leo", "name": "Low Earth orbit", "body": "Earth", "altitude": "500 km", "period": 96.0, "sun": 0.62, "contact": 0.19, "coverage": 0.72, "link": 1.0, "radiation": 0.7, "base_fuel": 20.0, "burn": 0.2, "lifetime": 180},
	{"id": "sso", "name": "Sun-synchronous orbit", "body": "Earth", "altitude": "700 km", "period": 99.0, "sun": 0.67, "contact": 0.25, "coverage": 0.95, "link": 1.0, "radiation": 1.0, "base_fuel": 25.0, "burn": 0.17, "lifetime": 365},
	{"id": "geo", "name": "Geostationary orbit", "body": "Earth", "altitude": "35,786 km", "period": 1440.0, "sun": 0.95, "contact": 0.9, "coverage": 0.58, "link": 0.7, "radiation": 1.4, "base_fuel": 55.0, "burn": 0.12, "lifetime": 720},
	{"id": "lunar-polar", "name": "Lunar polar orbit", "body": "Moon", "altitude": "100 km", "period": 118.0, "sun": 0.6, "contact": 0.48, "coverage": 0.9, "link": 0.72, "radiation": 1.3, "base_fuel": 45.0, "burn": 0.22, "lifetime": 180},
	{"id": "lunar-elliptic", "name": "Lunar elliptical orbit", "body": "Moon", "altitude": "100 × 800 km", "period": 210.0, "sun": 0.75, "contact": 0.64, "coverage": 0.68, "link": 0.72, "radiation": 1.15, "base_fuel": 35.0, "burn": 0.16, "lifetime": 180},
	{"id": "mars-polar", "name": "Mars polar orbit", "body": "Mars", "altitude": "300 km", "period": 113.0, "sun": 0.55, "contact": 0.21, "coverage": 0.94, "link": 0.12, "radiation": 1.5, "base_fuel": 75.0, "burn": 0.18, "lifetime": 365},
]
const LAUNCHERS := [
	{"id": "swift", "name": "Swift 1", "cost": 18.0, "capacity": {"leo": 900.0, "sso": 750.0}},
	{"id": "atlas", "name": "Atlas M", "cost": 32.0, "capacity": {"leo": 1800.0, "sso": 1400.0, "geo": 650.0, "lunar-polar": 720.0, "lunar-elliptic": 850.0}},
	{"id": "titan", "name": "Titan H", "cost": 55.0, "capacity": {"leo": 5000.0, "sso": 4000.0, "geo": 1500.0, "lunar-polar": 1800.0, "lunar-elliptic": 2100.0, "mars-polar": 1100.0}},
]
const DIFFICULTIES := {"cadet": {"name": "Cadet", "budget": 1.25, "goal": 0.8, "events": 0.6}, "standard": {"name": "Flight director", "budget": 1.0, "goal": 1.0, "events": 1.0}, "expert": {"name": "Expert", "budget": 0.85, "goal": 1.2, "events": 1.4}, "sandbox": {"name": "Sandbox", "budget": 1.0, "goal": 1.0, "events": 1.0}}
const POLICIES := {"balanced": "Balanced", "observe": "Observe more", "conserve": "Conserve", "downlink": "Downlink"}


static func find(list: Array, id: String) -> Dictionary:
	for x in list:
		if x["id"] == id:
			return x
	return list[0]


static func default_plan(id := "climate") -> Dictionary:
	var s := find(SCENARIOS, id)
	var sid: String = s["id"]
	return {"scenario": sid, "difficulty": "standard", "bus": "standard",
		"array": "large" if sid == "mars" else "standard", "battery": "large" if sid == "mars" else "standard",
		"radio": "deep" if sid == "mars" else "standard", "orbit": s["orbit"],
		"launcher": "titan" if sid == "mars" else ("atlas" if sid == "lunar" else "swift"),
		"payload": ["spectrometer", "radar"] if sid == "lunar" else s["preferred"].duplicate(),
		"fuel": 140.0 if sid == "mars" else (85.0 if sid == "lunar" else 60.0), "days": s["days"], "hours": 6.0, "seed": 2407}


static func evaluate(plan: Dictionary) -> Dictionary:
	var scenario := find(SCENARIOS, plan["scenario"])
	var diff: Dictionary = DIFFICULTIES[plan["difficulty"]]
	var bus := find(BUSES, plan["bus"])
	var array := find(ARRAYS, plan["array"])
	var battery := find(BATTERIES, plan["battery"])
	var radio := find(RADIOS, plan["radio"])
	var orbit := find(ORBITS, plan["orbit"])
	var launcher := find(LAUNCHERS, plan["launcher"])
	var payload := INSTRUMENTS.filter(func(i): return plan["payload"].has(i["id"]))
	var tot := func(k: String) -> float:
		var s := 0.0
		for i in payload:
			s += i[k]
		return s
	var fuel: float = plan["fuel"]
	var days: float = plan["days"]
	var hours: float = plan["hours"]
	var mass: float = bus["mass"] + array["mass"] + battery["mass"] + radio["mass"] + tot.call("mass") + fuel
	var cost: float = bus["cost"] + array["cost"] + battery["cost"] + radio["cost"] + tot.call("cost") + launcher["cost"] + fuel * 0.06
	var capacity: float = launcher["capacity"].get(orbit["id"], 0.0)
	var budget: float = scenario["budget"] * diff["budget"]
	var generated: float = array["power"] * scenario["solar"] * orbit["sun"]
	var load: float = bus["power"] + tot.call("power") * hours / 24.0 + radio["power"] * orbit["contact"]
	var power_margin := generated - load
	var eclipse_hours: float = orbit["period"] / 60.0 * (1.0 - orbit["sun"])
	var eclipse_required: float = (bus["power"] + tot.call("power") * hours / 24.0) * eclipse_hours
	var data_daily: float = tot.call("rate") / 8.0 * hours * 3600.0 / 1000.0
	var downlink_daily: float = radio["rate"] / 8.0 * 86400.0 * orbit["contact"] * orbit["link"] / 1000.0
	var fuel_required: float = orbit["base_fuel"] + days * orbit["burn"]
	var science_daily := 0.0
	for i in payload:
		science_daily += i["science"] * scenario["weights"].get(i["id"], 0.3)
	science_daily *= hours * orbit["coverage"]
	var target: float = scenario["goal"] * diff["goal"]
	var checks := []
	var check := func(level: String, title: String, why: String, fix: String):
		checks.append({"level": level, "title": title, "why": why, "fix": fix})
	if orbit["body"] != scenario["body"]:
		check.call("error", "Orbit reaches the wrong world", "%s is around %s; the objective is at %s." % [orbit["name"], orbit["body"], scenario["body"]], "Choose an orbit around the mission destination.")
	if capacity <= 0.0:
		check.call("error", "Launcher cannot reach this orbit", "%s has no supported %s injection in this model." % [launcher["name"], orbit["name"]], "Choose a launcher with a payload rating for this orbit.")
	elif mass > capacity:
		check.call("error", "Payload exceeds launch capacity", "%d kg exceeds the %d kg rating for this route." % [roundi(mass), roundi(capacity)], "Remove an instrument, choose lighter systems, or upgrade the launcher.")
	if cost > budget and plan["difficulty"] != "sandbox":
		check.call("error", "Mission exceeds the budget", "Development and launch cost %.1f M credits; the limit is %.1f M." % [cost, budget], "Reduce subsystem costs or use a cheaper compatible launcher.")
	if payload.is_empty():
		check.call("error", "No science instruments selected", "A spacecraft without a payload cannot collect science.", "Install at least one instrument relevant to the objective.")
	if fuel < fuel_required:
		check.call("error", "Propellant does not cover the mission", "Injection and station keeping require %.1f kg; only %.1f kg is loaded." % [fuel_required, fuel], "Add propellant or shorten the mission.")
	if days > orbit["lifetime"]:
		check.call("error", "Orbit lifetime is too short", "%s supports %d days." % [orbit["name"], orbit["lifetime"]], "Shorten the mission or select a longer-lived orbit.")
	if power_margin < 0.0:
		check.call("warn", "Average energy deficit", "Average generation is %d W versus %d W demand. The battery will drain." % [roundi(generated), roundi(load)], "Increase solar area, reduce observation hours, or use fewer instruments.")
	elif power_margin < load * 0.25:
		check.call("warn", "Small power safety margin", "Only %d W remains for unexpected losses in sunlight." % roundi(power_margin), "Leave extra generation margin for solar storms.")
	if battery["capacity"] < eclipse_required:
		check.call("warn", "Battery cannot span the eclipse", "The orbit needs about %d Wh during darkness, more than the %d Wh pack." % [roundi(eclipse_required), roundi(battery["capacity"])], "Install a larger battery or reduce the payload duty cycle.")
	if data_daily > downlink_daily:
		check.call("warn", "Data arrives faster than it can be sent", "%.2f GB/day is generated but %.2f GB/day can be downlinked." % [data_daily, downlink_daily], "Upgrade the antenna, reduce observation hours, or schedule downlink days.")
	if orbit["radiation"] > bus["hardening"]:
		check.call("warn", "Radiation protection is limited", "This orbit is harsher than the selected bus shielding.", "Use a hardened bus or leave extra lifetime and science margin.")
	if science_daily * days < target:
		check.call("warn", "Ideal science yield is below the objective", "Even without disruptions the payload yields %d points; the target is %d." % [roundi(science_daily * days), roundi(target)], "Choose instruments matched to the objective, observe longer, or extend the mission.")
	if plan["difficulty"] == "sandbox":
		check.call("info", "Budget constraint disabled", "Sandbox allows experiments above the budget.", "Compare with a budget-constrained mission when ready.")
	var errors := checks.filter(func(c): return c["level"] == "error")
	return {"plan": plan, "scenario": scenario, "difficulty": diff, "bus": bus, "array": array, "battery": battery, "radio": radio, "orbit": orbit,
		"launcher": launcher, "payload": payload, "mass": mass, "cost": cost, "budget": budget, "capacity": capacity, "generated": generated,
		"load": load, "power_margin": power_margin, "eclipse_hours": eclipse_hours, "eclipse_required": eclipse_required, "data_daily": data_daily,
		"downlink_daily": downlink_daily, "fuel_required": fuel_required, "science_daily": science_daily, "target": target, "checks": checks,
		"errors": errors, "valid": errors.is_empty()}


static func create_simulation(plan: Dictionary) -> Dictionary:
	var e := evaluate(plan)
	var seed_v: int = plan["seed"]
	seed_v = (seed_v * 1664525 + 1013904223) & 0xFFFFFFFF
	var offset := int(float(seed_v) / 4294967296.0 * 4.0)
	var events := [
		{"day": 8 + offset, "duration": 3, "type": "solar", "title": "Solar storm", "detail": "Reduced sunlight and radio interference for three days."},
		{"day": 22 + offset, "duration": 4, "type": "antenna", "title": "Antenna calibration drift", "detail": "Downlink capacity is halved for four days."},
		{"day": 38 + offset, "duration": 1, "type": "impact", "title": "Micrometeoroid strike", "detail": "Shielding limits the damage to spacecraft health."},
		{"day": 51 + offset, "duration": 1, "type": "leak", "title": "Thruster valve leak", "detail": "An unexpected maneuver consumes additional propellant."},
	]
	return {"e": e, "day": 0, "energy": e["battery"]["capacity"], "fuel": maxf(0.0, plan["fuel"] - e["orbit"]["base_fuel"]), "health": 100.0,
		"buffer": 0.0, "pending": 0.0, "science": 0.0, "generated_data": 0.0, "sent_data": 0.0, "lost_data": 0.0, "uptime": 0.0,
		"brownout_days": 0, "history": [], "events": events, "log": [], "done": not e["valid"], "aborted": not e["valid"], "decisions": []}


static func step(st: Dictionary, policy := "balanced") -> void:
	if st["done"]:
		return
	var e: Dictionary = st["e"]
	var plan: Dictionary = e["plan"]
	var orbit: Dictionary = e["orbit"]
	var bus: Dictionary = e["bus"]
	var battery: Dictionary = e["battery"]
	var radio: Dictionary = e["radio"]
	var evf: float = e["difficulty"]["events"]
	st["day"] += 1
	var day: int = st["day"]
	if st["decisions"].is_empty() or st["decisions"][-1]["policy"] != policy:
		st["decisions"].append({"day": day, "policy": policy})
	var solar := 1.0
	var link := 1.0
	var active := []
	for ev in st["events"]:
		if ev["day"] == day:
			st["log"].append(ev)
			if ev["type"] == "impact":
				st["health"] -= maxf(1.0, 12.0 - bus["hardening"] * 5.0) * evf
			if ev["type"] == "leak":
				st["fuel"] -= 6.0 * evf
		if day >= ev["day"] and day < ev["day"] + ev["duration"]:
			active.append(ev["title"])
			if ev["type"] == "solar":
				solar = 1.0 - 0.35 * evf
				link *= 1.0 - 0.45 * evf
			if ev["type"] == "antenna":
				link *= 0.5
	var duty: float = {"balanced": 1.0, "observe": 1.3, "conserve": 0.45, "downlink": 0.2}[policy]
	var hours: float = minf(20.0, plan["hours"] * duty)
	var payload_power := 0.0
	for i in e["payload"]:
		payload_power += i["power"]
	var load: float = bus["power"] + payload_power * hours / 24.0 + radio["power"] * orbit["contact"] * (1.4 if policy == "downlink" else 1.0)
	var gen: float = e["generated"] * solar
	var eclipse: float = (bus["power"] + payload_power * hours / 24.0) * e["eclipse_hours"]
	var energy_factor := clampf((gen * 24.0 + st["energy"]) / (load * 24.0), 0.0, 1.0)
	var eclipse_factor := clampf(battery["capacity"] / maxf(1.0, eclipse), 0.0, 1.0)
	var uptime := clampf(energy_factor * eclipse_factor * st["health"] / 100.0, 0.0, 1.0)
	st["energy"] = clampf(st["energy"] + (gen - load * energy_factor) * 24.0, 0.0, battery["capacity"])
	if uptime < 0.9:
		st["brownout_days"] += 1
	st["uptime"] += uptime
	var new_data: float = e["data_daily"] * (hours / plan["hours"]) * uptime
	var new_science: float = e["science_daily"] * (hours / plan["hours"]) * uptime
	st["generated_data"] += new_data
	st["buffer"] += new_data
	st["pending"] += new_science
	var dl: float = e["downlink_daily"] * link * (1.65 if policy == "downlink" else 1.0) * maxf(0.1, energy_factor)
	var sent := minf(st["buffer"], dl)
	var science_sent: float = st["pending"] * (sent / st["buffer"]) if st["buffer"] > 0.0 else 0.0
	st["buffer"] -= sent
	st["pending"] -= science_sent
	st["science"] += science_sent
	st["sent_data"] += sent
	if st["buffer"] > bus["storage"]:
		st["lost_data"] += st["buffer"] - bus["storage"]
		st["pending"] *= bus["storage"] / st["buffer"]
		st["buffer"] = bus["storage"]
	st["fuel"] -= orbit["burn"]
	st["health"] = clampf(st["health"] - maxf(0.0, orbit["radiation"] - bus["hardening"]) * 0.07 * evf, 0.0, 100.0)
	st["history"].append({"day": day, "energy": st["energy"] / battery["capacity"], "fuel": maxf(0.0, st["fuel"]), "health": st["health"],
		"buffer": st["buffer"] / bus["storage"], "science": st["science"], "power": uptime, "policy": policy, "events": active})
	if day >= plan["days"] or st["fuel"] <= 0.0 or st["health"] <= 0.0:
		st["done"] = true


static func report(st: Dictionary) -> Dictionary:
	var e: Dictionary = st["e"]
	var plan: Dictionary = e["plan"]
	var day: int = st["day"]
	var uptime: float = st["uptime"] / day if day > 0 else 0.0
	var goal_ratio: float = st["science"] / e["target"]
	var delivery: float = st["sent_data"] / st["generated_data"] if st["generated_data"] > 0.0 else 0.0
	var complete: bool = day >= plan["days"] and not st["aborted"] and st["health"] > 0.0 and st["fuel"] >= 0.0
	var success := complete and goal_ratio >= 1.0
	var cats := {"objectives": 300 if success else roundi(120.0 * minf(1.0, goal_ratio)), "science": roundi(250.0 * minf(1.0, goal_ratio)),
		"efficiency": roundi(200.0 * clampf((maxf(0.0, 1.0 - e["cost"] / e["budget"]) * 1.8 + delivery + maxf(0.0, st["fuel"] / plan["fuel"])) / 3.0, 0.0, 1.0)),
		"engineering": roundi(150.0 * uptime * st["health"] / 100.0), "collaboration": 100}
	var score := 0
	for v in cats.values():
		score += v
	var reasons := []
	for c in e["errors"]:
		reasons.append({"title": c["title"], "detail": c["why"], "tip": c["fix"]})
	if not st["aborted"]:
		reasons.append({"title": "Science objective achieved" if goal_ratio >= 1.0 else "Science objective missed",
			"detail": "%d / %d points delivered to the ground. Science counts only after transmission." % [roundi(st["science"]), roundi(e["target"])],
			"tip": "Try a lighter or lower-cost design while keeping this science margin." if goal_ratio >= 1.0 else "Increase useful observation time, choose matched instruments, or improve downlink."})
		if st["lost_data"] > 0.01:
			reasons.append({"title": "Storage overflow lost science", "detail": "%.1f GB was discarded when the %d GB buffer filled." % [st["lost_data"], roundi(e["bus"]["storage"])], "tip": "Install more storage, use a stronger antenna, or switch to downlink operations earlier."})
		if st["brownout_days"] > 0:
			reasons.append({"title": "Power or health reduced observation time", "detail": "%d days ran below 90%% effective uptime. Average uptime: %d%%." % [st["brownout_days"], roundi(uptime * 100.0)], "tip": "Check eclipse battery size and solar margin. Conserve during a solar storm."})
		if st["fuel"] < 0.0 or day < plan["days"]:
			reasons.append({"title": "Propellant ran out early", "detail": "Operations ended on day %d of %d." % [day, plan["days"]], "tip": "Carry a propellant reserve above the minimum."})
		if st["lost_data"] <= 0.0 and st["brownout_days"] == 0:
			reasons.append({"title": "Engineering margins protected the mission", "detail": "The buffer stayed within capacity and uptime stayed above 90%.", "tip": "Compare lower-mass alternatives to see where margins become too small."})
	return {"success": success, "aborted": st["aborted"], "score": score, "categories": cats, "science": st["science"], "target": e["target"],
		"uptime": uptime, "delivery": delivery, "days": day, "planned_days": plan["days"], "fuel_remaining": maxf(0.0, st["fuel"]),
		"health": st["health"], "lost_data": st["lost_data"], "reasons": reasons, "events": st["log"]}
