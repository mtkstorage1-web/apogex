## T-MINUS / APOGEX offline crew match rules.
## Ported from the web build: expedition-core.js (build, outfit, route, flight systems)
## and science-match.js (finite pool of twelve Science Flags, rival crews, scoring).
class_name Sim
extends RefCounted

signal shop_changed

## Ship is built at K x the original size so 1.75 m crew (2.5 units) fit inside the hull.
const SHIP_K := 1.5
const SHIP_SCALE := 3.6 * SHIP_K
const SHIP_Y := (0.22 + 0.41 * 3.6) * SHIP_K
const TWR_GO := 1.25
const G0 := 9.80665
const EXHAUST := 360.0 * 9.80665
const BASE_DRY := 670.0
const BASE_PROPELLANT := 80.0
const BASE_THRUST_KN := 10.4
const BASE_LOAD_KW := 5.4
const GENERATION_KW := 9.0
const AUTO_BUILD_SECONDS := 15.0
const SCAN_DURATIONS := [1.7, 1.6, 1.7]
const SCAN_TOTAL := 5.0
const FIELD_WEAPONS := [
	{"damage": 34.0, "interval": 0.18, "model": "res://assets/weapons/blaster-d.glb"},
	{"damage": 48.0, "interval": 0.30, "model": "res://assets/weapons/blaster-b.glb"},
	{"damage": 22.0, "interval": 0.10, "model": "res://assets/weapons/blaster-f.glb"},
]

static func field_damage(role: int, distance: float, headshot := false) -> float:
	if role < 0 or role >= FIELD_WEAPONS.size(): return 0.0
	var falloff := lerpf(1.0, 0.65, clampf((distance - 18.0) / 60.0, 0.0, 1.0))
	return FIELD_WEAPONS[role]["damage"] * falloff * (1.5 if headshot else 1.0)


const SPECIALISTS := [
	{"name": "FINN", "role": "PILOT", "species": "Frog", "color": "#f6a052", "tag": "Find the way home.",
	 "job": "Pilot, evade, navigate and protect the return reserve.",
	 "description": "Finn the Frog flies with twin maneuver-thrusters and a steady hand.",
	 "weapon": "Pulse carbine", "skill": "Afterburner", "model": "res://assets/characters/frog.glb"},
	{"name": "CHIP", "role": "ENGINEER", "species": "Maintenance robot", "color": "#f5be76", "tag": "Every system matters.",
	 "job": "Repair propulsion, power, cooling and life support.",
	 "description": "Chip carries a rectangular service pack and a modular repair tool.",
	 "weapon": "Arc projector", "skill": "Power reroute", "model": "res://assets/characters/Robot.fbx"},
	{"name": "BARBARA", "role": "GUNNER", "species": "Bee", "color": "#f7ce59", "tag": "Keep the corridor clear.",
	 "job": "Operate the dorsal turret, communications and defensive cover.",
	 "description": "Barbara the Bee brings an antenna harness, wings and disciplined covering fire.",
	 "weapon": "Vulcan repeater", "skill": "Turret overdrive", "model": "res://assets/characters/bee.glb"},
	{"name": "FERNANDO", "role": "RAIDER", "species": "Flamingo", "color": "#f7a28f", "tag": "Discovery is only the beginning.",
	 "job": "Scan, stabilize and extract Science Flags; carry them to the ship.",
	 "description": "Fernando the Flamingo carries a scanner arm and a protective sample case.",
	 "weapon": "Scientific scanner", "skill": "Scanner boost", "model": "res://assets/characters/flamingo.glb"},
]

const PARTS_DEF := [
	{"id": "keel", "name": "Keel & pressure hull", "owner": 0, "angle": 0, "position": [0, 1.2, -0.7], "size": [2, 0.9, 5.8], "type": "hull", "price": 220, "lesson": "A continuous structure carries launch loads and holds cabin pressure."},
	{"id": "port", "name": "Port maneuver engine", "owner": 0, "angle": 1, "position": [-1.8, 1.2, 1.2], "size": [0.95, 0.95, 2.4], "type": "engine", "price": 180, "lesson": "Symmetric mounting helps the attitude-control system avoid unwanted torque."},
	{"id": "bridge", "name": "Bridge & navigation module", "owner": 0, "angle": 2, "position": [0, 1.8, -2], "size": [1.4, 0.65, 1.6], "type": "bridge", "price": 300, "lesson": "Navigation and attitude sensing keep the vehicle pointed along its intended trajectory."},
	{"id": "reactor", "name": "Power distribution core", "owner": 1, "angle": 0, "position": [0, 1.8, 0.3], "size": [1.1, 0.65, 1.2], "type": "power", "price": 400, "lesson": "Electrical buses distribute generation to critical and optional loads."},
	{"id": "battery", "name": "Battery enclosure", "owner": 1, "angle": 1, "position": [0.85, 0.95, 1.8], "size": [0.8, 0.65, 1], "type": "battery", "price": 280, "lesson": "Stored energy bridges eclipses and temporary generation faults."},
	{"id": "coolant", "name": "Coolant radiator", "owner": 1, "angle": 3, "position": [2.5, 1.15, 0.8], "size": [3.5, 0.18, 2.5], "type": "radiator", "price": 240, "lesson": "In space, radiators reject heat by radiation; airflow outside cannot cool the ship."},
	{"id": "cargo", "name": "Cargo restraint rack", "owner": 3, "angle": 0, "position": [-0.75, 0.85, -0.2], "size": [0.7, 0.65, 1.3], "type": "cargo", "price": 200, "lesson": "Secured cargo prevents dangerous shifts during acceleration."},
	{"id": "scrubber", "name": "Atmosphere scrubber", "owner": 3, "angle": 2, "position": [0.8, 0.9, -0.2], "size": [0.7, 0.8, 1.1], "type": "life", "price": 260, "lesson": "Oxygen supply and carbon-dioxide removal are separate life-support requirements."},
	{"id": "stores", "name": "Food & water stores", "owner": 3, "angle": 1, "position": [-0.75, 0.95, 1.7], "size": [0.7, 0.6, 1.1], "type": "stores", "price": 120, "lesson": "Consumable reserves must cover mission duration and a contingency margin."},
	{"id": "engine", "name": "Dorsal turret assembly", "owner": 2, "angle": 3, "position": [0, 2.5, 0.3], "size": [1.2, 0.6, 1.5], "type": "turret", "price": 360, "lesson": "Thrust and propellant consumption depend on engine performance and vehicle mass."},
	{"id": "thruster", "name": "Starboard maneuver engine", "owner": 2, "angle": 1, "position": [1.65, 1.2, 2.5], "size": [0.95, 0.95, 2], "type": "engine", "price": 300, "lesson": "Paired engines must be mounted and tested before committing to flight."},
	{"id": "antenna", "name": "High-gain communications array", "owner": 2, "angle": 2, "position": [0, 2.45, 1.6], "size": [1, 0.5, 1], "type": "antenna", "price": 200, "lesson": "Antenna alignment and contact time determine how much science reaches home."},
]

const CARGO_DEF := [
	{"id": "propellant", "name": "Propellant service kit", "owner": 0, "lesson": "Fuel mass is already included in the configured wet mass. Stowing this kit completes fueling."},
	{"id": "coolant", "name": "Coolant & battery tools", "owner": 1, "lesson": "Maintenance equipment and spare coolant provide resilience against thermal faults."},
	{"id": "rations", "name": "Rations & drinking water", "owner": 2, "lesson": "Each crew member needs food and water even when the ship is operating normally."},
	{"id": "spares", "name": "EVA replacement plates", "owner": 3, "lesson": "Replacement plates restore structural protection after damaged material is removed."},
]

const ROUTES := [
	{"id": "sheltered", "name": "Shielded passage", "dv": 120.0, "duration": 100.0, "hazard": 0.65, "note": "A longer, lower-energy rendezvous corridor. Less debris, more time for other teams to catch up."},
	{"id": "balanced", "name": "Transfer corridor", "dv": 210.0, "duration": 82.0, "hazard": 1.0, "note": "A moderate maneuver with a balanced travel time and obstacle exposure."},
	{"id": "slingshot", "name": "Debris slingshot", "dv": 320.0, "duration": 65.0, "hazard": 1.5, "note": "A faster local departure with higher propellant use and more debris."},
]

const UPGRADES := [
	{"id": "weapons", "name": "Heavy dorsal turret", "cost": 1100, "mass": 75.0, "power": 1.8, "cargo": 0, "fuel": 0.0, "description": "Higher damage, but more mass and electrical demand."},
	{"id": "cargo", "name": "Expanded sample racks", "cost": 950, "mass": 80.0, "power": 0.15, "cargo": 2, "fuel": 0.0, "description": "Carry eight flags instead of six. More cargo capacity adds dry mass."},
	{"id": "reserve", "name": "Reserve propellant tank", "cost": 450, "mass": 20.0, "power": 0.0, "cargo": 0, "fuel": 20.0, "description": "Adds 20 kg of propellant and 20 kg to wet mass."},
]

const FACTIONS := [
	{"name": "ORANGE", "color": "#f79442", "symbol": "▲"},
	{"name": "CYAN", "color": "#53d3db", "symbol": "●"},
	{"name": "VIOLET", "color": "#a486d4", "symbol": "◆"},
	{"name": "LIME", "color": "#b9d75b", "symbol": "■"},
]

const FLAG_SITES := [[-28, -22], [-19, -26], [-28, -4], [-20, 8], [-6, -10], [6, -10], [-6, 10], [6, 10], [22, -24], [30, -14], [24, 6], [31, 19]]
const LANDING_BAYS := [[0, 58], [-58, -30], [58, -30], [0, -62]]
const RACKS := [[-30, -20], [30, -20], [-30, 22], [30, 22]]
const CARGO_SPOTS := [[-26, 34], [26, 34], [-26, -32], [26, -32]]
const CARGO_HATCH := Vector3(0, 0, 17)
const DELIVERY_PAD := Vector3(0, 0, 39)
const CHECK_RANGES := {"pressure": [95.0, 105.0], "power": [45.0, 65.0], "engine": [68.0, 78.0]}
const CHECK_ROLE := {"pressure": 1, "power": 1, "engine": 0}

const DIFFICULTY := {
	"cadet": {"label": "CADET", "damage": 0.75, "fault_every": 26.0, "rival_pace": 1.25},
	"standard": {"label": "STANDARD", "damage": 1.0, "fault_every": 20.0, "rival_pace": 1.0},
	"expert": {"label": "EXPERT", "damage": 1.3, "fault_every": 15.0, "rival_pace": 0.82},
}
const LENGTHS := {
	"short": {"label": "SHORT 10 MIN", "limit": 600.0},
	"standard": {"label": "STANDARD 14 MIN", "limit": 840.0},
	"long": {"label": "LONG 20 MIN", "limit": 1200.0},
}

# ---- expedition state -------------------------------------------------------
var match_seed: int = 1
var rng_state: int = 1
var difficulty := "standard"
var length := "standard"
var credits := 4800
var upgrades: Array = []
var loadout: Dictionary = ShipCatalog.default_loadout()
var armor_mult := 1.0
var turret_mult := 1.0
var scan_mult := 1.0
var handling_mult := 1.0
var thrust_kn := BASE_THRUST_KN
var generation_kw := GENERATION_KW
var load_kw := BASE_LOAD_KW
var exhaust_velocity := EXHAUST
var radiator_mult := 1.0
var life_mult := 1.0
var _catalog_stats: Dictionary = ShipCatalog.loadout_stats({})
var cargo_capacity := 6
var extra_load := 0.0
var scan_boost := 0.0
var overdrive := 0.0
var flight_leg := "outbound"
var phase := "assembly"
var selected := 3
var parts: Array = []
var auto_build := {"enabled": false, "t": 0.0}
var shop_open := false   ## true while the crew is buying modules at the 3D parts shop (assembly waits)
var ai_assist := true
var carry: Array = [null, null, null, null]
var rotation: Array = [0, 0, 0, 0]
var cargo: Array = []
var checks := {"pressure": 0.0, "power": 0.0, "engine": 0.0}
var check_readings := {"pressure": 80.0, "power": 45.0, "engine": 50.0}
var flight_time := 0.0
var manual_flight := false
var destination_reached := false
var route: Variant = null
var hull := 100.0
var power := 3.6
var power_capacity := 6.0
var reactor := 62.0
var temperature := 41.0
var pressure := 101.3
var co2 := 480.0
var food := 8.0
var water := 16.0
var crew_nutrition := 100.0
var spares := 6
var propellant := BASE_PROPELLANT
var wet_mass := BASE_DRY + BASE_PROPELLANT
var panels: Array = []
var fault: Variant = null
var fault_clock := 17.0
var ability_cd := [0.0, 0.0, 0.0, 0.0]
var ultimate := [45.0, 45.0, 45.0, 45.0]
var shield := 0.0
var boost := 0.0
var decoy := 0.0
var score := 0
var bot_watch: Array = [null, null, null, null]
var human_modules := 0
var fault_log: Array = []

# ---- science match ----------------------------------------------------------
var time := 0.0
var limit := 840.0
var over := false
var reason := ""
var winner: Variant = null
var flags: Array = []
var teams: Array = []
var wrecks: Array = []
var events: Array = []

# Offline crew tactics and match telemetry. Scoring still requires delivery.
var navigation: RefCounted
var crew_order := "escort"
var priority_flag := -1
var quick_deploy := false
var metrics := {"captures": 0, "recoveries": 0, "loads": 0, "stuns": 0, "downs": 0, "repairs": 0, "hazards": 0, "shots": 0, "hits": 0}
var announced := {}

func cycle_order() -> String:
	var orders := ["escort", "recover", "regroup"]
	crew_order = orders[(orders.find(crew_order) + 1) % orders.size()]
	return crew_order

func set_priority(id: int) -> bool:
	if id < 0 or id >= flags.size() or flags[id]["planet"] != "B" or not flags[id]["state"] in ["site", "ground"]:
		return false
	priority_flag = id
	crew_order = "recover"
	return true

func frontier_target(position: Vector3, team := 0) -> Variant:
	var best = null
	var cost := INF
	for f in flags:
		if f["planet"] != "B" or not f["state"] in ["site", "ground"]:
			continue
		var value: float = position.distance_to(f["position"])
		# Distinct rival strategies: Cyan races, Violet avoids contests, Lime salvages.
		if f["scanner"] != null and f["scanner"] != team:
			value += 24.0 if team == 2 else 8.0
		if f["state"] == "ground":
			value -= 22.0 if team == 3 else 8.0
		if team == 0 and f["id"] == priority_flag:
			value -= 1000.0
		if value < cost:
			cost = value
			best = f
	return best

func objective_advice() -> String:
	match phase:
		"assembly": return "Buy modules at the shop, then build your assigned parts. 1–4 changes specialist."
		"outfit": return "Finish cargo and systems checks. Watch the crew cards for unfinished work."
		"route": return "Choose a route with positive fuel margin. Save enough for the return leg."
		"flight":
			if fault != null: return "SYSTEM FAULT: switch to Chip [2] and service the affected system."
			if panels.any(func(p): return p["health"] < 60.0): return "HULL BREACH: Fernando [4] can remove and replace damaged plates."
			return "Pilot [1] avoids debris · Gunner [3] clears drones · Q skill · F ultimate."
		"surface":
			var c := flag_counts(0)
			if c["carried"] > 0: return "Samples in the field: escort carriers back to the ramp. E loads your sample."
			if c["onboard"] >= cargo_capacity: return "CARGO FULL. Regroup at the ramp and press T to bring your science home."
			if limit - time < 95.0: return "RETURN WINDOW CLOSING. Reach the ramp and depart; undelivered samples do not score."
			return "Z marks a flag · C changes crew orders · M tactical map · Raider [4] extracts samples."
		"delivery", "docking": return "Hold E at the delivery pad. Only science delivered home counts toward victory."
		"delivered", "spectator": return "F5 accelerates the remaining race. Review the final standings at debrief."
	return "Bring your crew and science home."



static func ship_point(p: Array) -> Vector3:
	return Vector3(p[0] * SHIP_SCALE, SHIP_Y + (p[1] - 0.6) * SHIP_SCALE, p[2] * SHIP_SCALE)


static func ship_size(p: Array) -> Vector3:
	return Vector3(p[0] * SHIP_SCALE, p[1] * SHIP_SCALE, p[2] * SHIP_SCALE)


func _init(p_seed: int = 0, p_difficulty := "standard", p_length := "standard") -> void:
	match_seed = p_seed if p_seed > 0 else int(Time.get_unix_time_from_system()) % 999999 + 1
	rng_state = match_seed
	difficulty = p_difficulty
	length = p_length
	limit = LENGTHS[length]["limit"]
	fault_clock = 17.0
	for d in PARTS_DEF:
		var p: Dictionary = d.duplicate(true)
		p["slot"] = ship_point(d["position"])
		p["dims"] = ship_size(d["size"])
		p["stage"] = "shelf"
		p["purchased"] = false
		p["bolts"] = [0.0, 0.0, 0.0]
		parts.append(p)
	for i in CARGO_DEF.size():
		var c: Dictionary = CARGO_DEF[i].duplicate(true)
		c["position"] = Vector3(CARGO_SPOTS[i][0], 0, CARGO_SPOTS[i][1])
		c["stowed"] = false
		cargo.append(c)
	panels = [
		{"id": "port", "name": "Port coolant plate", "offset": Vector3(-3.5, 1.37, 0.8) * SHIP_SCALE, "health": 100.0, "removed": false, "progress": 0.0},
		{"id": "aft", "name": "Aft shield plate", "offset": Vector3(1.05, 0.87, 1.7) * SHIP_SCALE, "health": 100.0, "removed": false, "progress": 0.0},
		{"id": "starboard", "name": "Starboard power cover", "offset": Vector3(3.5, 1.37, 0.8) * SHIP_SCALE, "health": 100.0, "removed": false, "progress": 0.0},
	]
	_create_match()
	refresh_loadout()


## Reapply after restoring a serialized loadout. Preserve spent fuel and upgrade mass.
func refresh_loadout() -> void:
	var stats := ShipCatalog.loadout_stats(loadout)
	wet_mass += float(stats["wet_mass"]) - float(_catalog_stats["wet_mass"])
	propellant += float(stats["fuel"]) - float(_catalog_stats["fuel"])
	cargo_capacity += int(stats["cargo_capacity"]) - int(_catalog_stats["cargo_capacity"])
	power_capacity = stats["battery_kwh"]
	power = minf(power, power_capacity)
	armor_mult = stats["armor"]
	turret_mult = stats["turret_damage_mult"]
	scan_mult = stats["scan_mult"]
	handling_mult = stats["handling"]
	thrust_kn = stats["thrust_kn"]
	generation_kw = stats["gen_kw"]
	load_kw = stats["load_kw"]
	exhaust_velocity = stats["exhaust"]
	radiator_mult = stats["radiator"]
	life_mult = stats["life"]
	_catalog_stats = stats
	for p in parts:
		p["price"] = part_price(p["id"])
	if not teams.is_empty():
		teams[0]["capacity"] = cargo_capacity
		teams[0]["loadout"] = loadout.duplicate(true)
		teams[0]["stats"] = stats.duplicate(true)


func part_price(slot_id: String) -> int:
	var family = loadout.get(slot_id, "kestrel")
	if family == null or not ShipCatalog.FAMILIES.has(family): family = "kestrel"
	return int(ShipCatalog.variant(slot_id, str(family)).get("price", 0))


## Selecting a variant also purchases it. Swaps pay only the difference.
func set_variant(slot_id: String, family_id: String) -> bool:
	var p = part_by_id(slot_id)
	var v := ShipCatalog.variant(slot_id, family_id)
	if p == null or v.is_empty() or phase != "assembly" or auto_build["enabled"] or parts.any(func(q): return q["stage"] != "shelf"):
		return false
	var charge: int = variant_charge(slot_id, family_id)
	if credits < charge: return false
	credits -= charge
	loadout[slot_id] = family_id
	p["purchased"] = true
	refresh_loadout()
	shop_changed.emit()
	return true


## The same quote is used by individual purchases and the whole-ship draft.
func variant_charge(slot_id: String, family_id: String) -> int:
	return int(ShipCatalog.variant(slot_id, family_id).get("price", 0)) - (part_price(slot_id) if slot_confirmed(slot_id) else 0)


func loadout_purchase_error(draft: Dictionary) -> String:
	if phase != "assembly" or auto_build["enabled"] or parts.any(func(p): return p["stage"] != "shelf"):
		return "Assembly has started; the loadout is locked."
	var total := 0
	for slot in ShipCatalog.VARIANTS:
		if part_by_id(slot) == null or ShipCatalog.variant(slot, str(draft.get(slot, ""))).is_empty():
			return "Choose a valid variant for every slot."
		total += variant_charge(slot, str(draft[slot]))
	if total > credits: return "Not enough credits: need %d CR more." % (total - credits)
	return ""


## Validate everything before mutation; refunds fund subsequent purchases.
func purchase_loadout(draft: Dictionary) -> bool:
	if not loadout_purchase_error(draft).is_empty(): return false
	var slots := ShipCatalog.VARIANTS.keys()
	slots.sort_custom(func(a, b): return variant_charge(a, str(draft[a])) < variant_charge(b, str(draft[b])))
	for slot in slots:
		if slot_confirmed(slot) and loadout.get(slot) == draft[slot]: continue
		if not set_variant(slot, str(draft[slot])): return false
	return true


func _confirm_default(slot_id: String) -> void:
	if not ShipCatalog.VARIANTS.has(slot_id): return
	if loadout.get(slot_id) == null:
		loadout[slot_id] = "kestrel"
	var p = part_by_id(slot_id)
	if p != null: p["price"] = part_price(slot_id)


func rand() -> float:
	rng_state = (rng_state * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(rng_state) / 4294967296.0


static func faction_color(i: int) -> Color:
	return Color.html(FACTIONS[i]["color"])


static func role_color(i: int) -> Color:
	return Color.html(SPECIALISTS[i]["color"])


# ============================================================================
# Science match (science-match.js)
# ============================================================================
func _create_match() -> void:
	time = 0.0
	over = false
	reason = ""
	winner = null
	flags.clear()
	teams.clear()
	wrecks.clear()
	events.clear()
	for i in FLAG_SITES.size():
		var s = FLAG_SITES[i]
		flags.append({"id": i, "site": i, "state": "site", "planet": "B", "position": Vector3(s[0], 0, s[1]),
			"owner": null, "carrier": null, "stage": 0, "progress": 0.0, "scanner": null})
	var pace: float = DIFFICULTY[difficulty]["rival_pace"]
	for i in FACTIONS.size():
		var bay = LANDING_BAYS[i]
		var rival_loadout := ShipCatalog.default_loadout()
		if i != 0:
			var rival_rng := RandomNumberGenerator.new()
			rival_rng.seed = match_seed + i * 7919
			for slot in rival_loadout:
				rival_loadout[slot] = ShipCatalog.FAMILIES.keys()[rival_rng.randi_range(0, 4)]
		var stats := ShipCatalog.loadout_stats(rival_loadout)
		teams.append({"id": i, "name": FACTIONS[i]["name"], "color": FACTIONS[i]["color"], "ai": i != 0,
			"progress": 0.0, "elapsed": 0.0, "finished": false, "phase": "building", "phase_time": 0.0,
			"planet": "A", "delivered": 0, "onboard": 0, "hull": 2000.0, "capacity": stats["cargo_capacity"], "loadout": rival_loadout, "stats": stats, "eliminated": false,
			"position": Vector3(bay[0], 0, bay[1]), "bot_position": Vector3(bay[0], 0, bay[1]), "target": null,
			"carrying": null, "stun": 0.0, "salvage_cd": 0.0,
			"build_duration": (155.0 + float((match_seed + i * 37) % 40)) * pace, "travel_duration": (85.0 + i * 7) * clampf(1.414 / float(stats["twr"]), 0.85, 1.2), "cycles": 0})


func flags_at_sites() -> int:
	var n := 0
	for f in flags:
		if f["state"] == "site":
			n += 1
	return n


func flag_counts(team: int) -> Dictionary:
	var c := {"sites": 0, "onboard": 0, "carried": 0, "delivered": 0, "loose": 0}
	for f in flags:
		var st: String = f["state"]
		if st == "site":
			c["sites"] += 1
		elif st == "ground" or st == "wreck":
			c["loose"] += 1
		elif f["owner"] == team and c.has(st):
			c[st] += 1
	return c


func _alive(team: int) -> bool:
	return team >= 0 and team < teams.size() and not teams[team]["eliminated"] and not over


func carried_flag(team: int, role: int) -> Variant:
	for f in flags:
		if f["state"] == "carried" and f["owner"] == team and f["carrier"] == role:
			return f
	return null


func scan_fraction(f) -> float:
	if f == null or f["state"] != "site":
		return 0.0
	var done := 0.0
	for i in mini(3, f["stage"]):
		done += SCAN_DURATIONS[i]
	return minf(1.0, (done + f["progress"] * SCAN_DURATIONS[mini(2, f["stage"])]) / SCAN_TOTAL)


func scan_flag(id: int, team: int, role: int, dt: float, distance: float, aligned := true, powered := false) -> bool:
	var f = flags[id]
	if not _alive(team) or role != 3 or f["state"] != "site" or distance > 3.8 or not aligned or teams[team]["planet"] != "B":
		return false
	if carried_flag(team, role) != null:
		return false
	if f["scanner"] != null and f["scanner"] != team:
		f["progress"] = maxf(0.0, f["progress"] - dt * 0.5)
		if f["progress"] > 0.0:
			return false
		f["stage"] = 0
	f["scanner"] = team
	f["progress"] = clampf(f["progress"] + maxf(0.0, dt) * (scan_mult if team == 0 else float(teams[team]["stats"]["scan_mult"])) * (1.3 if powered else 1.0) / SCAN_DURATIONS[f["stage"]], 0.0, 1.0)
	if f["progress"] >= 1.0:
		f["progress"] = 0.0
		f["stage"] += 1
		if f["stage"] >= 3:
			f["state"] = "carried"
			f["owner"] = team
			f["carrier"] = role
			f["scanner"] = null
			teams[team]["carrying"] = id
			if team == 0: metrics["captures"] += 1
			events.append({"time": time, "text": "%s extracted Science Flag %d" % [FACTIONS[team]["name"], id + 1]})
	return true


func drop_flag(team: int, role: int, position: Vector3, planet := "B") -> bool:
	var f = carried_flag(team, role)
	if f == null:
		return false
	f["state"] = "ground"
	f["planet"] = planet
	f["position"] = Vector3(position.x, 0, position.z)
	f["owner"] = null
	f["carrier"] = null
	teams[team]["carrying"] = null
	return true


func recover_flag(id: int, team: int, role: int, distance: float, planet := "B") -> bool:
	var f = flags[id]
	if not _alive(team) or not (f["state"] in ["ground", "wreck"]) or f["planet"] != planet or distance > 3.8:
		return false
	if carried_flag(team, role) != null:
		return false
	if team == 0: metrics["recoveries"] += 1
	f["state"] = "carried"
	f["owner"] = team
	f["carrier"] = role
	teams[team]["carrying"] = id
	return true


func load_flag(team: int, role: int, distance: float) -> bool:
	var t = teams[team]
	var f = carried_flag(team, role)
	if not _alive(team) or f == null or distance > 4.5 or t["planet"] != "B" or flag_counts(team)["onboard"] >= t["capacity"]:
		return false
	f["state"] = "onboard"
	f["carrier"] = null
	f["planet"] = "ship"
	t["carrying"] = null
	t["onboard"] = flag_counts(team)["onboard"]
	if team == 0: metrics["loads"] += 1
	return true


func deliver_flag(team: int, distance: float) -> bool:
	var t = teams[team]
	if not _alive(team) or t["planet"] != "A" or not (t["phase"] in ["docked", "delivering"]) or distance > 5.0:
		return false
	for f in flags:
		if f["state"] == "onboard" and f["owner"] == team:
			f["state"] = "delivered"
			f["planet"] = "A"
			f["carrier"] = null
			var c := flag_counts(team)
			t["delivered"] = c["delivered"]
			t["onboard"] = c["onboard"]
			events.append({"time": time, "text": "%s delivered Science Flag %d" % [t["name"], f["id"] + 1]})
			return true
	return false


func recover_wreck_flag(id: int, team: int) -> bool:
	var f = flags[id]
	var t = teams[team]
	if not _alive(team) or f["state"] != "wreck" or f["planet"] != "space" or t["planet"] != "space" or flag_counts(team)["onboard"] >= t["capacity"]:
		return false
	f["state"] = "onboard"
	f["planet"] = "ship"
	f["owner"] = team
	f["carrier"] = null
	t["onboard"] = flag_counts(team)["onboard"]
	return true


func eliminate_crew(team: int, position: Vector3, planet := "space") -> bool:
	var t = teams[team]
	if t["eliminated"]:
		return false
	t["eliminated"] = true
	t["hull"] = 0.0
	t["phase"] = "eliminated"
	t["finished"] = true
	var ids := []
	for f in flags:
		if f["owner"] == team and (f["state"] == "onboard" or f["state"] == "carried"):
			var was_carried: bool = f["state"] == "carried"
			f["state"] = "ground" if planet == "B" else "wreck"
			f["planet"] = planet
			f["position"] = t["bot_position"] if was_carried else position
			f["owner"] = null
			f["carrier"] = null
			ids.append(f["id"])
	t["carrying"] = null
	t["onboard"] = 0
	if ids.size() > 0:
		wrecks.append({"team": team, "position": position, "planet": planet, "flags": ids})
	events.append({"time": time, "text": "%s crew eliminated; %d flags exposed for recovery." % [t["name"], ids.size()]})
	return true


func depart_frontier(team: int) -> bool:
	var t = teams[team]
	if not _alive(team) or t["planet"] != "B" or t["phase"] != "surface" or flags.any(func(f): return f["state"] == "carried" and f["owner"] == team):
		return false
	t["phase"] = "return"
	t["phase_time"] = 0.0
	t["planet"] = "space"
	# Rival departures share this method, while the flight controls belong to the player.
	if team == 0:
		manual_flight = false
		destination_reached = false
	return true


func arrive_home(team: int) -> bool:
	var t = teams[team]
	if not _alive(team):
		return false
	t["phase"] = "docked"
	t["phase_time"] = 0.0
	t["planet"] = "A"
	return true


func finish_match(why := "Match complete") -> void:
	if over:
		return
	over = true
	reason = why
	var best := 0
	for t in teams:
		best = maxi(best, t["delivered"])
	var leaders := teams.filter(func(t): return t["delivered"] == best)
	winner = leaders[0]["id"] if best > 0 and leaders.size() == 1 else null


func _move_bot(t: Dictionary, target: Vector3, dt: float, speed := 3.5) -> float:
	var p: Vector3 = t["bot_position"]
	var d := Vector2(p.x - target.x, p.z - target.z).length()
	if d > 0.1:
		var waypoint: Vector3 = navigation.next_point(t["id"] + 10, p, target) if navigation else target
		var direction := Vector2(waypoint.x - p.x, waypoint.z - p.z)
		var movement := direction.limit_length(speed * dt)
		p.x += movement.x
		p.z += movement.y
		t["bot_position"] = p
	return d


func tick_match(dt: float) -> void:
	if over:
		return
	var step := clampf(dt, 0.0, 0.25)
	time += step
	for threshold in [180, 90, 30]:
		if limit - time <= threshold and not announced.has(threshold):
			announced[threshold] = true
			events.append({"time": time, "text": "%d seconds left — %s" % [threshold, "depart now to protect your return" if threshold == 90 else "only delivered science scores"]})
	for t in teams:
		if t["id"] == 0 or t["eliminated"]:
			continue
		t["elapsed"] += step
		t["phase_time"] += step
		if t["stun"] > 0.0:
			t["stun"] = maxf(0.0, t["stun"] - step)
			continue
		match t["phase"]:
			"building":
				t["progress"] = minf(0.3, t["phase_time"] / t["build_duration"] * 0.3)
				if t["phase_time"] >= t["build_duration"]:
					t["phase"] = "systems test"
					t["phase_time"] = 0.0
			"systems test":
				t["progress"] = 0.3 + t["phase_time"] / 18.0 * 0.1
				if t["phase_time"] >= 18.0:
					t["phase"] = "launching"
					t["phase_time"] = 0.0
			"launching":
				if t["phase_time"] >= 6.0:
					t["phase"] = "outbound"
					t["phase_time"] = 0.0
					t["planet"] = "space"
			"outbound":
				t["progress"] = 0.4 + minf(1.0, t["phase_time"] / t["travel_duration"]) * 0.15
				if t["phase_time"] >= t["travel_duration"]:
					t["phase"] = "surface"
					t["phase_time"] = 0.0
					t["planet"] = "B"
					var bay = LANDING_BAYS[t["id"]]
					var landing := Vector3(bay[0], 0, bay[1])
					t["position"] = landing + (-landing).normalized() * 18.0 if navigation else landing
					t["bot_position"] = t["position"]
			"surface":
				t["progress"] = 0.55
				var c := flag_counts(t["id"])
				if t["carrying"] != null:
					if _move_bot(t, t["position"], step) < 3.5:
						load_flag(t["id"], 3, 2.0)
				elif c["onboard"] >= (4 if t["id"] == 3 else 3) or (limit - time < 90.0 and c["onboard"] > 0) or (flags_at_sites() == 0 and c["onboard"] > 0) or (t["phase_time"] > 145.0 and c["onboard"] > 0):
					depart_frontier(t["id"])
				else:
					var f = null
					if t["target"] != null:
						var cand = flags[t["target"]]
						if cand["state"] in ["site", "ground"] and cand["planet"] == "B":
							f = cand
					if f == null:
						f = frontier_target(t["bot_position"], t["id"])
					t["target"] = f["id"] if f != null else null
					if f != null:
						if _move_bot(t, f["position"], step, 3.1) <= 3.8:
							if f["state"] == "ground":
								recover_flag(f["id"], t["id"], 3, 2.0)
							else:
								scan_flag(f["id"], t["id"], 3, step * 0.65, 2.0, true, true)
					elif c["onboard"] == 0 and flags_at_sites() == 0:
						t["phase"] = "return"
						t["phase_time"] = 0.0
						t["planet"] = "space"
			"return":
				t["salvage_cd"] = maxf(0.0, t["salvage_cd"] - step)
				if t["phase_time"] > 20.0 and t["salvage_cd"] <= 0.0 and flag_counts(t["id"])["onboard"] < t["capacity"]:
					for f in flags:
						if f["state"] == "wreck" and f["planet"] == "space":
							if recover_wreck_flag(f["id"], t["id"]):
								t["salvage_cd"] = 3.0
							break
				t["progress"] = 0.75 + minf(1.0, t["phase_time"] / 60.0) * 0.15
				if t["phase_time"] >= 60.0:
					arrive_home(t["id"])
					t["cycles"] += 1
			"docked":
				t["phase"] = "delivering"
				t["phase_time"] = 0.0
			"delivering":
				if t["phase_time"] >= 1.5:
					t["phase_time"] = 0.0
					deliver_flag(t["id"], 1.0)
					if flag_counts(t["id"])["onboard"] == 0:
						t["phase"] = "delivered"
						t["progress"] = 1.0
						t["finished"] = true
	var delivered := 0
	var outstanding := false
	for f in flags:
		if f["state"] == "delivered":
			delivered += 1
		elif f["state"] == "onboard" or f["state"] == "carried":
			outstanding = true
	var active := teams.filter(func(t): return not t["eliminated"])
	if delivered == 12:
		finish_match("All twelve Science Flags delivered.")
	elif active.is_empty():
		finish_match("All crews eliminated.")
	elif time >= limit:
		finish_match("Mission window closed. Delivered flags determine the result.")
	elif active.all(func(t): return t["phase"] in ["delivered", "docked", "delivering"]) and not outstanding:
		finish_match("All surviving crews have returned. Undelivered flags do not score.")


func debrief(team := 0) -> Dictionary:
	var c := flag_counts(team)
	var t = teams[team]
	var rank := 1
	for o in teams:
		if o["delivered"] > c["delivered"]:
			rank += 1
	var d: int = c["delivered"]
	return {"delivered": d, "total": 12, "rank": rank, "victory": winner == team, "eliminated": t["eliminated"],
		"metrics": metrics.duplicate(), "seed": match_seed,
		"xp": d * 25 + (0 if t["eliminated"] else 25), "credits": d * 20 + (0 if t["eliminated"] else 10),
		"patch": "Frontier Vanguard" if d >= 7 else ("Orbital Pathfinder" if d >= 3 else "Flight Cadet"),
		"log": [
			{"title": "FUEL RESERVE", "value": "%.1f kg" % propellant, "detail": "Departure mass and Δv determined the propellant cost. Return reserve had to remain available."},
			{"title": "POWER RECOVERED", "value": "%.1f kWh" % power, "detail": "A maintained power bus kept propulsion, scanning and life support available."},
			{"title": "SAFE RETURN", "value": "Crew eliminated" if t["eliminated"] else "%d flags delivered" % d, "detail": "Loading cargo did not score. Only flags transferred to Earth earned points."},
		]}


# ============================================================================
# Expedition (expedition-core.js)
# ============================================================================
func part_by_id(id: String) -> Variant:
	for p in parts:
		if p["id"] == id:
			return p
	return null


func reserved_credits() -> int:
	var r := 0
	for p in parts:
		if not slot_confirmed(p["id"]):
			r += part_price(p["id"])
	return r


## Parts shop (offline competitive): the crew buys each module before assembly starts.
func buy_part(id: String) -> bool:
	_confirm_default(id)
	var p = part_by_id(id)
	if p == null or p["purchased"] or p["stage"] != "shelf" or credits < p["price"]:
		return false
	credits -= p["price"]
	p["purchased"] = true
	shop_changed.emit()
	return true


## Purchased is the sole confirmation flag; a catalog selection must also be valid.
func slot_confirmed(id: String) -> bool:
	var p = part_by_id(id)
	return p != null and bool(p["purchased"]) and ShipCatalog.FAMILIES.has(loadout.get(id))


func confirmed_count() -> int:
	return parts.filter(func(p): return slot_confirmed(p["id"])).size()


func unconfirmed_slots() -> Array[String]:
	var missing: Array[String] = []
	for id in ShipCatalog.VARIANTS:
		if not slot_confirmed(id): missing.append(id)
	return missing


func all_parts_bought() -> bool:
	return unconfirmed_slots().is_empty()


func assign_part(id: String, owner: int) -> bool:
	var p = part_by_id(id)
	if p == null or owner < 0 or owner > 3:
		return false
	p["owner"] = owner
	return true


func pick_part(id: String, role: int) -> bool:
	_confirm_default(id)
	if auto_build["enabled"] or shop_open:
		return false
	var p = part_by_id(id)
	if phase != "assembly" or p == null or p["owner"] != role or p["stage"] != "shelf" or carry[role] != null:
		return false
	if not slot_confirmed(p["id"]):
		if credits < p["price"]:
			return false
		credits -= p["price"]
		p["purchased"] = true
	p["stage"] = "carried"
	carry[role] = id
	rotation[role] = 0
	return true


func rotate_carried(role: int) -> bool:
	if carry[role] == null:
		return false
	rotation[role] = (rotation[role] + 1) % 4
	return true


func place_part(role: int, distance: float) -> bool:
	if auto_build["enabled"] or carry[role] == null:
		return false
	var p = part_by_id(carry[role])
	if p == null or p["stage"] != "carried" or distance > 3.0 or rotation[role] != p["angle"]:
		return false
	p["stage"] = "positioned"
	carry[role] = null
	return true


func fasten_bolt(id: String, bolt: int, role: int, dt: float, distance: float, aligned := true, human := true) -> bool:
	if auto_build["enabled"]:
		return false
	var p = part_by_id(id)
	if p == null or p["owner"] != role or p["stage"] != "positioned" or distance > 3.5 or not aligned or bolt < 0 or bolt > 2:
		return false
	p["bolts"][bolt] = clampf(p["bolts"][bolt] + maxf(0.0, dt) / 0.7, 0.0, 1.0)
	if p["bolts"].all(func(b): return b >= 1.0):
		p["stage"] = "secured"
		score += 75
		if human and role == selected:
			human_modules += 1
		if parts.all(func(q): return q["stage"] == "secured"):
			phase = "outfit"
	return true


func secured_count() -> int:
	return parts.filter(func(p): return p["stage"] == "secured").size()


func pick_cargo(id: String, role: int) -> bool:
	var c = null
	for x in cargo:
		if x["id"] == id:
			c = x
	if phase != "outfit" or c == null or c["stowed"] or carry[role] != null or carry.has("cargo:" + id):
		return false
	carry[role] = "cargo:" + id
	return true


func stow_cargo(role: int, distance: float) -> bool:
	var id = carry[role]
	if id == null or not String(id).begins_with("cargo:") or distance > 3.0:
		return false
	for c in cargo:
		if c["id"] == String(id).substr(6) and not c["stowed"]:
			c["stowed"] = true
			carry[role] = null
			score += 60
			return true
	return false


func all_cargo_stowed() -> bool:
	return cargo.all(func(c): return c["stowed"])


func run_check(type: String, role: int, dt: float, reading: float) -> bool:
	if phase != "outfit" or not checks.has(type) or not all_cargo_stowed():
		return false
	if role != CHECK_ROLE[type]:
		return false
	var r = CHECK_RANGES[type]
	check_readings[type] = reading
	if reading < r[0] or reading > r[1]:
		return false
	checks[type] = clampf(checks[type] + dt / 2.2, 0.0, 1.0)
	if checks.values().all(func(v): return v >= 1.0):
		phase = "route"
		score += 150
	return true


## Machines stow the cargo and run every systems check (no manual outfit work).
func auto_outfit() -> void:
	if phase != "outfit":
		return
	for c in cargo:
		if not c["stowed"]:
			c["stowed"] = true
			score += 60
	for k in checks.keys():
		checks[k] = 1.0
		var r = CHECK_RANGES[k]
		check_readings[k] = (r[0] + r[1]) * 0.5
	for r2 in 4:
		if carry[r2] != null and String(carry[r2]).begins_with("cargo:"):
			carry[r2] = null
	phase = "route"
	score += 150


func design_sheet() -> Dictionary:
	var opt_load := 0.0
	for id in upgrades:
		for u in UPGRADES:
			if u["id"] == id:
				opt_load += u["power"]
	var wet := wet_mass
	var twr := thrust_kn * 1000.0 / (wet * G0)
	var dv := exhaust_velocity * log(wet / maxf(1.0, wet - propellant))
	return {"dry": wet - propellant, "wet": wet, "propellant": propellant, "thrust": thrust_kn, "twr": twr, "dv": dv,
		"generation": generation_kw, "load": load_kw + opt_load, "power_margin": generation_kw - load_kw - opt_load,
		"cargo": cargo_capacity, "design_name": _catalog_stats["design_name"], "dominant_family": _catalog_stats["dominant_family"],
		"synergy": _catalog_stats["synergy"], "cost": _catalog_stats["cost"], "armor": armor_mult, "turret_mult": turret_mult,
		"scan_mult": scan_mult, "handling": handling_mult, "exhaust": exhaust_velocity}


static func slow_climb_kg(twr: float) -> float:
	return 0.0 if twr >= TWR_GO else (1.0 - twr / TWR_GO) * 120.0


func route_budget(r: Dictionary) -> Dictionary:
	var outbound := wet_mass * (1.0 - exp(-r["dv"] / exhaust_velocity))
	var return_reserve := (wet_mass - outbound) * (1.0 - exp(-95.0 / exhaust_velocity))
	var contingency := 5.0
	var slow_climb := slow_climb_kg(design_sheet()["twr"])
	var required := outbound + return_reserve + contingency + slow_climb
	var b := r.duplicate()
	b.merge({"outbound": outbound, "return_reserve": return_reserve, "contingency": contingency, "slow_climb": slow_climb,
		"required": required, "margin": propellant - required, "valid": propellant >= required})
	return b


func route_risk(b: Dictionary) -> String:
	if not b["valid"]:
		return "NO-GO"
	if b["hazard"] >= 1.4:
		return "HIGH DEBRIS"
	if b["margin"] < 8.0:
		return "THIN MARGIN"
	return "NOMINAL"


func launch_flight(id: String) -> bool:
	var r = null
	for x in ROUTES:
		if x["id"] == id:
			r = route_budget(x)
	if phase != "route" or r == null or not r["valid"]:
		return false
	route = r
	propellant -= r["outbound"] + r["slow_climb"]
	phase = "flight"
	flight_leg = "outbound"
	flight_time = 0.0
	manual_flight = false
	destination_reached = false
	return true


func tick_systems(dt: float) -> void:
	if phase != "flight" or over:
		return
	var t := clampf(dt, 0.0, 0.1)
	var demand := load_kw + extra_load + (2.0 if boost > 0.0 else 0.0) + (1.8 if fault == "power" else 0.0)
	var generation := reactor / 100.0 * generation_kw * (0.45 if fault == "reactor" else 1.0)
	power = clampf(power + (generation - demand) * t * 30.0 / 3600.0, 0.0, power_capacity)
	temperature = clampf(temperature + (reactor / 100.0 * 0.25 - 0.08 * radiator_mult + (0.45 if fault == "cooling" else 0.0)) * t, 15.0, 110.0)
	var leaking := panels.any(func(p): return p["health"] < 60.0)
	pressure = clampf(pressure - (0.42 if leaking else 0.0) * t, 0.0, 105.0)
	co2 = clampf(co2 + (22.0 if fault == "scrubber" else 1.5) * t / life_mult, 300.0, 8000.0)
	crew_nutrition = clampf(crew_nutrition - t * 0.16 / life_mult, 0.0, 100.0)
	if power <= 0.02 or temperature > 90.0 or pressure < 55.0 or co2 > 5000.0:
		hull = maxf(0.0, hull - t * 1.3 * armor_mult)
	for i in 4:
		ability_cd[i] = maxf(0.0, ability_cd[i] - t)
		ultimate[i] = minf(100.0, ultimate[i] + t * 0.8)
	shield = maxf(0.0, shield - t)
	boost = maxf(0.0, boost - t)
	decoy = maxf(0.0, decoy - t)
	scan_boost = maxf(0.0, scan_boost - t)
	overdrive = maxf(0.0, overdrive - t)
	if not manual_flight:
		flight_time += t * (1.6 if boost > 0.0 else 1.0)
	fault_clock -= t
	if fault_clock <= 0.0:
		fault = ["reactor", "power", "cooling", "scrubber"][int(rand() * 4.0) % 4]
		var p = panels[int(rand() * panels.size()) % panels.size()]
		p["health"] = maxf(10.0, p["health"] - 45.0)
		p["removed"] = false
		p["progress"] = 0.0
		fault_clock = DIFFICULTY[difficulty]["fault_every"]
		fault_log.append({"time": flight_time, "event": fault})


func damage_ship(amount: float) -> void:
	if shield > 0.0:
		return
	hull = maxf(0.0, hull - amount * armor_mult * DIFFICULTY[difficulty]["damage"])


func maintain_system(role: int, dt: float, system: String) -> bool:
	if phase != "flight" or role != 1:
		return false
	match system:
		"reactor":
			if fault == "reactor" or fault == "power":
				fault = null
			power = minf(power_capacity, power + dt * 0.16 / life_mult)
		"coolant":
			temperature = maxf(35.0, temperature - dt * 4.0)
			if fault == "cooling":
				fault = null
		"scrubber":
			co2 = maxf(400.0, co2 - dt * 220.0)
			pressure = minf(101.3, pressure + dt * 1.8)
			if fault == "scrubber":
				fault = null
		"stores":
			if food <= 0.0 or water < 0.5:
				return false
			food = maxf(0.0, food - 0.2 * dt)
			water = maxf(0.0, water - 0.1 * dt)
			crew_nutrition = minf(100.0, crew_nutrition + dt * 9.0)
		_:
			return false
	return true


func remove_panel(idx: int, role: int) -> bool:
	var p = panels[idx]
	if role != 3 or p["health"] >= 60.0 or p["removed"]:
		return false
	p["removed"] = true
	p["progress"] = 0.0
	return true


func repair_panel(idx: int, role: int, dt: float) -> bool:
	var p = panels[idx]
	if role != 3 or not p["removed"] or spares <= 0:
		return false
	p["progress"] = clampf(p["progress"] + dt / 2.5, 0.0, 1.0)
	if p["progress"] >= 1.0:
		p["health"] = 100.0
		p["removed"] = false
		spares -= 1
		metrics["repairs"] += 1
		hull = minf(100.0, hull + 14.0)
		score += 100
	return true


func use_skill(role: int, slot: String) -> bool:
	if teams[0]["eliminated"] or over:
		return false
	if slot == "f":
		if ultimate[role] < 100.0:
			return false
		ultimate[role] = 0.0
	else:
		if ability_cd[role] > 0.0:
			return false
		ability_cd[role] = 12.0
	match role:
		0:
			if slot == "q": boost = 3.0
			else: shield = 8.0
		1:
			if slot == "q": power = minf(power_capacity, power + 0.7)
			else:
				temperature = 36.0
				fault = null
				power = minf(power_capacity, power + 1.5)
		2:
			if slot == "q": overdrive = 7.0
			else: shield = 5.0
		3:
			if slot == "q": scan_boost = 7.0
			else: hull = minf(100.0, hull + 12.0)
	return true


func build_order() -> Array:
	return parts.duplicate()


func auto_assemble(dt: float) -> bool:
	if not auto_build["enabled"] or phase != "assembly" or shop_open:
		return false
	auto_build["t"] = minf(AUTO_BUILD_SECONDS, auto_build["t"] + maxf(0.0, dt))
	var n := parts.size()
	var w := 2.5
	var gap := (AUTO_BUILD_SECONDS - w) / float(n - 1)
	for i in n:
		var p = parts[i]
		_confirm_default(p["id"])
		if p["stage"] == "secured":
			continue
		var k: float = (auto_build["t"] - i * gap) / w
		if k <= 0.0:
			continue
		if not slot_confirmed(p["id"]):
			if credits < p["price"]:
				continue
			credits -= p["price"]
			p["purchased"] = true
		if k < 0.3:
			p["stage"] = "carried"
			continue
		p["stage"] = "positioned"
		var f := minf(1.0, (k - 0.3) / 0.7)
		p["bolts"] = [f, f, f]
		if k >= 1.0 or auto_build["t"] >= AUTO_BUILD_SECONDS:
			p["bolts"] = [1.0, 1.0, 1.0]
			p["stage"] = "secured"
			score += 75
	for r in 4:
		if carry[r] != null and not String(carry[r]).begins_with("cargo:"):
			carry[r] = null
	if parts.all(func(q): return q["stage"] == "secured"):
		phase = "outfit"
		auto_build["enabled"] = false
	return true


## After a bot teammate stalls for 10 s, a remote service arm walks it through the same paid transitions.
func rescue_stalled_crew(role: int, dt: float) -> bool:
	if phase != "assembly" or auto_build["enabled"] or shop_open or not ai_assist or role == selected:
		return false
	var p = null
	for q in parts:
		if q["owner"] == role and q["stage"] != "secured":
			p = q
			break
	if p == null:
		return false
	var sig := "%s:%d,%d,%d" % [p["stage"], int(p["bolts"][0] * 100), int(p["bolts"][1] * 100), int(p["bolts"][2] * 100)]
	var w = bot_watch[role]
	if w == null or w["id"] != p["id"]:
		w = {"id": p["id"], "sig": sig, "age": 0.0, "rescue": false}
		bot_watch[role] = w
	if not w["rescue"]:
		if sig != w["sig"]:
			w["sig"] = sig
			w["age"] = 0.0
		else:
			w["age"] += clampf(dt, 0.0, 0.1)
	if not w["rescue"] and w["age"] < 10.0:
		return false
	w["rescue"] = true
	match p["stage"]:
		"shelf":
			return pick_part(p["id"], role)
		"carried":
			rotation[role] = p["angle"]
			return place_part(role, 2.0)
		"positioned":
			var nb: int = p["bolts"].find_custom(func(b): return b < 1.0)
			return nb >= 0 and fasten_bolt(p["id"], nb, role, clampf(dt, 0.0, 0.1) * 1.5, 2.0, true, false)
	return false


func tick_rivals(dt: float) -> void:
	auto_assemble(dt)
	var t = teams[0]
	if not t["eliminated"]:
		match phase:
			"assembly":
				t["phase"] = "building"
				t["planet"] = "A"
				t["progress"] = secured_count() / 12.0 * 0.25
			"outfit":
				t["phase"] = "systems test"
				var stowed := cargo.filter(func(c): return c["stowed"]).size()
				var ck := 0.0
				for v in checks.values():
					ck += v
				t["progress"] = 0.25 + stowed / 4.0 * 0.1 + ck / 3.0 * 0.05
			"route":
				t["phase"] = "ready"
				t["progress"] = 0.4
			"flight":
				t["phase"] = "return" if flight_leg == "return" else "outbound"
				t["planet"] = "space"
				var dur: float = 60.0 if flight_leg == "return" else (route["duration"] if route != null else 90.0)
				t["progress"] = (0.75 if flight_leg == "return" else 0.4) + minf(1.0, flight_time / dur) * 0.15
			"surface":
				t["phase"] = "surface"
				t["planet"] = "B"
				t["progress"] = 0.6
	tick_match(dt)


func flight_duration() -> float:
	if flight_leg == "return":
		return 60.0
	return route["duration"] if route != null else 90.0


## Returns "landing", "docking", "lost" or "" while the leg is still under way.
func complete_flight() -> String:
	if phase != "flight" or over:
		return ""
	if flight_time < flight_duration() and not (manual_flight and destination_reached):
		return ""
	if flight_leg == "outbound":
		phase = "landing"
		teams[0]["phase"] = "surface"
		teams[0]["planet"] = "B"
		return "landing"
	if propellant < route["return_reserve"]:
		hull = 0.0
		eliminate_crew(0, Vector3.ZERO, "space")
		phase = "spectator"
		return "lost"
	propellant -= route["return_reserve"]
	arrive_home(0)
	phase = "docking"
	return "docking"


func set_upgrade(id: String, enabled: bool) -> bool:
	var u = null
	for x in UPGRADES:
		if x["id"] == id:
			u = x
	if u == null:
		return false
	var current := upgrades.has(id)
	if current == enabled:
		return true
	if enabled and credits - reserved_credits() < u["cost"]:
		return false
	if enabled:
		upgrades.append(id)
		credits -= u["cost"]
	else:
		upgrades.erase(id)
		credits += u["cost"]
	var direction := 1.0 if enabled else -1.0
	wet_mass += u["mass"] * direction
	propellant += u["fuel"] * direction
	extra_load += u["power"] * direction
	cargo_capacity += int(u["cargo"] * direction)
	teams[0]["capacity"] = cargo_capacity
	return true


## Step ordering used by the HUD phase strip.
func strip_index() -> int:
	match phase:
		"assembly": return 0
		"outfit": return 1
		"route": return 2
		"flight", "landing": return 3 if flight_leg == "outbound" else 5
		"surface": return 4
		"docking", "delivery", "delivered": return 5
	return 5
