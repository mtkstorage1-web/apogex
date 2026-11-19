## Single-player campaign rules, ported from campaign-core.js.
## Equipment values are fictional gameplay tuning. Simulation seconds = play seconds x 8.
## Godot addition: the training launcher (core stage, two side boosters, fairing) is ordered at the
## workshop kiosk too; it is program-supplied, so it costs no mission credits.
class_name Campaign
extends RefCounted

const SAVE_PATH := "user://campaign_progress.json"

const EQUIPMENT := {
	"battery": [{"id": "compact", "name": "Compact battery", "mass": 24, "cost": 8, "wh": 800}, {"id": "reserve", "name": "Reserve battery", "mass": 65, "cost": 18, "wh": 1800}],
	"array": [{"id": "standard", "name": "Standard solar wings", "mass": 60, "cost": 12, "watts": 1800}, {"id": "expanded", "name": "Expanded solar wings", "mass": 110, "cost": 22, "watts": 2600}],
	"instrument": [{"id": "camera", "name": "Survey camera", "mass": 35, "cost": 12, "watts": 350, "rate": 1.0}, {"id": "spectrometer", "name": "Imaging spectrometer", "mass": 70, "cost": 22, "watts": 750, "rate": 1.5}],
	"radio": [{"id": "standard", "name": "Standard antenna", "mass": 20, "cost": 8, "rate": 2.0}, {"id": "highgain", "name": "High-gain antenna", "mass": 40, "cost": 16, "rate": 4.0}],
}
const EQUIPMENT_LABEL := {"battery": "BATTERY", "array": "ARRAY", "instrument": "INSTRUMENT", "radio": "RADIO"}

const LAUNCHER := [
	{"id": "core", "name": "Core stage", "note": "Liquid-fuel core · 15 m"},
	{"id": "side_l", "name": "Port side booster", "note": "Solid booster · burns 5.5 s"},
	{"id": "side_r", "name": "Starboard side booster", "note": "Solid booster · burns 5.5 s"},
	{"id": "fairing", "name": "Payload fairing", "note": "Protects the spacecraft through the atmosphere"},
]

const MISSIONS := [
	{"id": "orbital", "number": "01", "name": "First Orbital Flight", "destination": "EARTH / LOW ORBIT", "duration": "15–20 MIN",
	 "summary": "Your program’s first crewed flight. Bring the ship online, observe Earth, recover from an electrical fault, and bring the science home.",
	 "goal": 90, "budget": 70, "available": true,
	 "criteria": ["Complete spacecraft checkout and orbital insertion.", "Collect and transmit at least 90 MB of observations.", "Recover the laboratory electrical circuit.", "Complete the guided return safely."],
	 "reference": "Inspired by the milestone of Vostok 1 (1961). This multi-crew spacecraft, science activity and circuit fault are fictional; this is not a reconstruction."},
	{"id": "telescope", "number": "02", "name": "Restore the Observatory", "destination": "EARTH / SERVICING ORBIT", "duration": "15–20 MIN",
	 "summary": "Rendezvous with an orbital observatory. Prepare the airlock, carry a replacement instrument outside, and restore its scientific capability.",
	 "goal": 90, "budget": 78, "available": true,
	 "criteria": ["Rendezvous with the observatory.", "Prepare the airlock and complete the spacewalk.", "Install the replacement instrument.", "Transmit 90 MB and return safely."],
	 "reference": "Inspired by Hubble Servicing Mission 1 (1993). This telescope, rendezvous and EVA procedure are simplified fictional gameplay."},
	{"id": "spacewalk", "number": "03", "name": "Beyond the Airlock", "available": false},
	{"id": "docking", "number": "04", "name": "Two Ships, One Orbit", "available": false},
	{"id": "deployment", "number": "05", "name": "Eyes on Earth", "available": false},
	{"id": "station", "number": "06", "name": "A Home in Orbit", "available": false},
	{"id": "lunar-orbit", "number": "07", "name": "Around the Moon", "available": false},
	{"id": "lunar-landing", "number": "08", "name": "First Footprints", "available": false},
	{"id": "samples", "number": "09", "name": "Bring the Moon Home", "available": false},
]

const DEFAULT_DESIGN := {"battery": "reserve", "array": "standard", "instrument": "camera", "radio": "standard"}

const PHASE_NAMES := {"checkout": "Preflight checks", "launch": "Launch & insertion", "commission": "Orbital checkout", "rendezvous": "Rendezvous",
	"prepare": "EVA preparation", "eva": "External servicing", "science": "Earth observation", "eclipse": "Eclipse operations",
	"downlink": "Ground contact", "return": "Return preparation", "reentry": "Guided return", "complete": "Mission complete",
	"aborted": "Mission aborted", "failed": "Mission ended"}

const ROOMS := {"cockpit": "Flight deck", "lab": "Science laboratory", "power_room": "Power room", "life_support": "Life support",
	"workshop": "Workshop", "engine_bay": "Engine bay", "airlock": "Airlock", "exterior": "Observatory bay"}

# ---- state -------------------------------------------------------------------
var mission_id := "orbital"
var design := {}
var phase := "checkout"
var elapsed := 0.0
var phase_time := 0.0
var energy := 0.0
var min_energy := 0.0
var stored := 0.0
var transmitted := 0.0
var data_lost := 0.0
var observing := false
var arrays := false
var calibrated := false
var autopilot := false
var fault := false
var isolated := false
var fuse := false
var spare := false
var tool := false
var tether := false
var suit := false
var depressurized := false
var installed := false
var verified := false
var returned := false
var optional := false
var conserve := false
var downlink := false
var crew_command := "monitor"
var crew_timer := 0.0
var done: Array = []
var mission_log: Array = []
var activity: Variant = null
var failed_reason := ""
var simulation_rate := 8.0


static func mission(id: String) -> Dictionary:
	for m in MISSIONS:
		if m["id"] == id:
			return m
	return MISSIONS[0]


static func part(key: String, id: String) -> Dictionary:
	for p in EQUIPMENT[key]:
		if p["id"] == id:
			return p
	return EQUIPMENT[key][0]


static func sanitize_design(input: Dictionary) -> Dictionary:
	var r := {}
	for key in EQUIPMENT:
		var ok := false
		for p in EQUIPMENT[key]:
			if p["id"] == input.get(key, ""):
				ok = true
		r[key] = input[key] if ok else DEFAULT_DESIGN[key]
	return r


static func evaluate_design(input: Dictionary, target_mission := "orbital") -> Dictionary:
	var d := sanitize_design(input)
	var m := mission(target_mission)
	var parts := {}
	var mass := 520.0
	var cost := 0
	for key in EQUIPMENT:
		parts[key] = part(key, d[key])
		mass += parts[key]["mass"]
		cost += parts[key]["cost"]
	var demand: float = 800.0 + parts["instrument"]["watts"]
	var errors := []
	var warnings := []
	if cost > m["budget"]:
		errors.append("Equipment exceeds the mission budget.")
	if mass > 850.0:
		errors.append("Spacecraft exceeds the training launcher’s 850 kg capacity.")
	if parts["array"]["watts"] < demand + 300.0:
		errors.append("Generation must cover the instrument and a 300 W recharge margin.")
	if parts["battery"]["wh"] < demand * 300.0 * 8.0 / 3600.0 * 1.25:
		warnings.append("Limited eclipse reserve: suspend observations while repairing the circuit.")
	# Play seconds of observing in eclipse before the battery is empty.
	var endurance: float = parts["battery"]["wh"] / demand * 3600.0 / 8.0
	return {"design": d, "parts": parts, "mass": mass, "cost": cost, "load": demand, "errors": errors, "warnings": warnings,
		"valid": errors.is_empty(), "budget": m["budget"], "endurance": endurance}


func _init(p_mission := "orbital", p_design := DEFAULT_DESIGN) -> void:
	mission_id = p_mission
	var e := evaluate_design(p_design, p_mission)
	design = e["design"]
	energy = e["parts"]["battery"]["wh"]
	min_energy = energy


func terminal() -> bool:
	return phase in ["complete", "aborted", "failed"]


func set_phase(next: String) -> void:
	phase = next
	phase_time = 0.0
	activity = null
	mission_log.append({"time": elapsed, "text": PHASE_NAMES[next]})


static func _a(id: String, label: String, room: String, seconds := 0.0, note := "") -> Dictionary:
	return {"id": id, "label": label, "room": room, "seconds": seconds, "note": note}


func objectives() -> Array:
	if terminal():
		return []
	var r := []
	match phase:
		"checkout":
			r = [_a("check-power", "Verify electrical supply", "power_room", 8), _a("check-cabin", "Verify cabin systems", "life_support", 8),
				_a("check-payload", "Secure the science payload", "lab", 8), _a("launch", "Confirm guidance & launch", "cockpit", 5)]
			r = r.filter(func(a): return not done.has(a["id"]))
		"launch":
			r = [_a("wait", "Monitor ascent and insertion", "cockpit", 0, "Guided, time-compressed ascent. Essential systems remain under automatic control.")]
		"commission":
			if not arrays: r.append(_a("deploy", "Deploy solar wings", "power_room", 12))
			if not autopilot: r.append(_a("autopilot", "Engage orbital autopilot", "cockpit", 5))
			r.append(_a("commission", "Accept orbital checkout", "cockpit", 5))
		"rendezvous":
			r = [_a("rendezvous", "Match the approach indicators", "cockpit", 15, "Match both indicators to their marked safe bands.")]
		"prepare":
			if not tool: r.append(_a("tool", "Collect replacement instrument", "workshop", 8))
			if not suit: r.append(_a("suit", "Check suit oxygen and pressure", "airlock", 12))
			if not tether: r.append(_a("tether", "Attach safety tether", "airlock", 5))
			r.append(_a("depressurize", "Depressurize airlock", "airlock", 12))
		"eva":
			r = [_a("install", "Replace observatory instrument", "exterior", 45) if not installed else _a("ingress", "Return to airlock & repressurize", "airlock", 15)]
		"science":
			r = [_a("calibrate", "Calibrate the science instrument", "lab", 20) if not calibrated else _a("observe", "Suspend observation" if observing else "Start Earth observation", "lab", 5),
				_a("advance", "Review observations", "lab", 5)]
		"eclipse":
			if fault and not isolated: r.append(_a("isolate", "Isolate laboratory circuit", "power_room", 8))
			if fault and isolated and not spare: r.append(_a("spare", "Retrieve spare fuse", "workshop", 8))
			if fault and isolated and spare and not fuse: r.append(_a("fuse", "Fit the correctly rated fuse", "power_room"))
			if fault and fuse: r.append(_a("restore", "Restore laboratory circuit", "power_room", 8))
			if not fault: r.append(_a("optional", "Suspend optional observation" if observing else "Collect optional observation", "lab", 5))
			if not fault: r.append(_a("eclipse-end", "Finish eclipse operations", "cockpit", 5))
		"downlink":
			r = [_a("transmit", "Transmit stored observations", "lab", 5), _a("return", "Confirm science receipt & prepare return", "cockpit", 5)]
		"return":
			if not done.has("secure"): r.append(_a("secure", "Secure instruments for return", "lab", 8))
			r.append(_a("deorbit", "Confirm return guidance", "cockpit", 8))
		"reentry":
			r = [_a("wait", "Monitor guided return", "cockpit", 0, "Time-compressed return. Your crew monitors cabin and guidance automatically.")]
	return r


func _objective(id: String) -> Variant:
	for a in objectives():
		if a["id"] == id:
			return a
	return null


func contact_open() -> bool:
	return phase == "downlink" and fmod(phase_time, 90.0) >= 30.0


func can_action(id: String, room: String, ctx := {}) -> String:
	var a = _objective(id)
	if a == null or id == "wait":
		return "This action is not available now."
	if a["room"] != room:
		return "Go to the " + ROOMS.get(a["room"], a["room"]).to_lower() + "."
	if activity != null:
		return "Finish or cancel the current task first."
	if id == "launch" and not ["check-power", "check-cabin", "check-payload"].all(func(k): return done.has(k)):
		return "Complete all three preflight checks."
	if id == "commission" and (not arrays or not autopilot):
		return "Deploy solar wings and engage autopilot."
	if id == "rendezvous" and not (absf(ctx.get("alignment", 0.0) - 50.0) <= 7.0 and absf(ctx.get("closure", 0.0) - 30.0) <= 7.0):
		return "Match alignment to 50 and closure to 30 (±7)."
	if id == "depressurize" and (not tool or not suit or not tether):
		return "Collect the instrument, check the suit and attach the tether."
	if id == "install" and not ctx.get("at_telescope", false):
		return "Float to the highlighted telescope instrument bay."
	if id == "ingress" and not ctx.get("at_airlock", false):
		return "Return to the ship’s airlock beacon."
	if id in ["calibrate", "observe", "optional"] and (fault or energy < 5.0):
		return "Restore electrical supply first."
	if id == "calibrate" and absf(ctx.get("calibration", 0.0) - 50.0) > 6.0:
		return "Set calibration inside the marked band (50 ±6)."
	if id == "advance" and stored < mission(mission_id)["goal"]:
		return "Collect at least 90 MB before reviewing observations."
	if id == "eclipse-end" and phase_time < 180.0:
		return "Eclipse ends in %d seconds. Conserve energy or collect optional data." % ceili(180.0 - phase_time)
	if id == "transmit" and (not contact_open() or stored <= 0.0):
		return "No data remains in storage." if stored <= 0.0 else "Ground contact opens in %d seconds." % ceili(30.0 - fmod(phase_time, 90.0))
	if id == "return" and transmitted < 90.0:
		return "Transmit at least 90 MB to the ground."
	if id == "deorbit" and not done.has("secure"):
		return "Secure the laboratory equipment first."
	return ""


func start_action(id: String, room: String, ctx := {}) -> Dictionary:
	var reason := can_action(id, room, ctx)
	if reason != "":
		return {"ok": false, "reason": reason}
	var a = _objective(id)
	if a["seconds"] > 0.0:
		activity = {"id": id, "room": room, "remaining": a["seconds"], "total": a["seconds"]}
		return {"ok": true}
	return complete_action(id)


func complete_action(id: String) -> Dictionary:
	var a = _objective(id)
	if a == null:
		return {"ok": false, "reason": "This action is not available now."}
	if id == "fuse" and not (phase == "eclipse" and isolated and spare):
		return {"ok": false, "reason": "Isolate the circuit and retrieve a spare first."}
	mission_log.append({"time": elapsed, "text": a["label"]})
	if not done.has(id):
		done.append(id)
	match id:
		"launch": set_phase("launch")
		"deploy": arrays = true
		"autopilot": autopilot = true
		"commission": set_phase("rendezvous" if mission_id == "telescope" else "science")
		"rendezvous": set_phase("prepare")
		"tool": tool = true
		"suit": suit = true
		"tether": tether = true
		"depressurize":
			depressurized = true
			set_phase("eva")
		"install": installed = true
		"ingress":
			depressurized = false
			verified = true
			set_phase("science")
		"calibrate": calibrated = true
		"observe", "optional": observing = not observing
		"advance":
			observing = false
			fault = true
			isolated = false
			fuse = false
			set_phase("eclipse")
		"isolate": isolated = true
		"spare": spare = true
		"fuse": fuse = true
		"restore":
			fault = false
			isolated = false
			spare = false
		"eclipse-end":
			observing = false
			set_phase("downlink")
		"transmit": downlink = true
		"return":
			downlink = false
			set_phase("return")
		"deorbit": set_phase("reentry")
	return {"ok": true}


func power_status() -> Dictionary:
	var e := evaluate_design(design, mission_id)
	var generation: float = e["parts"]["array"]["watts"] if arrays and phase != "eclipse" else 0.0
	var demand: float = (600.0 if conserve else 800.0) + (e["parts"]["instrument"]["watts"] if observing and not fault else 0.0) + (250.0 if downlink and contact_open() else 0.0)
	return {"generation": generation, "load": demand, "net": generation - demand, "capacity": float(e["parts"]["battery"]["wh"])}


func tick(dt: float) -> void:
	if terminal() or dt <= 0.0:
		return
	var t := minf(dt, 0.25)
	elapsed += t
	phase_time += t
	crew_timer += t
	var power := power_status()
	if crew_command == "monitor" and energy / power["capacity"] < 0.25:
		conserve = true
	if crew_command == "prepare" and crew_timer >= 20.0:
		if phase == "prepare" and not tool:
			tool = true
			done.append("tool")
			mission_log.append({"time": elapsed, "text": "Fernando prepared the replacement instrument."})
		if phase == "return" and not done.has("secure"):
			done.append("secure")
			mission_log.append({"time": elapsed, "text": "Fernando secured the laboratory for return."})
		crew_timer = 0.0
	power = power_status()
	energy = clampf(energy + power["net"] * t * simulation_rate / 3600.0, 0.0, power["capacity"])
	min_energy = minf(min_energy, energy)
	var e := evaluate_design(design, mission_id)
	if observing and not fault and energy > 0.0:
		var rate: float = e["parts"]["instrument"]["rate"] * (1.1 if crew_command == "orientation" else 1.0)
		var produced := rate * t
		var accepted := minf(produced, 240.0 - stored)
		stored += accepted
		data_lost += produced - accepted
		if phase == "eclipse" and stored >= 120.0:
			optional = true
	if downlink and contact_open() and energy > 0.0:
		var sent := minf(stored, e["parts"]["radio"]["rate"] * t)
		stored -= sent
		transmitted += sent
	if activity != null:
		activity["remaining"] -= t
		if activity["remaining"] <= 0.0:
			var id: String = activity["id"]
			activity = null
			complete_action(id)
	if phase == "launch" and phase_time >= 45.0:
		set_phase("commission")
	if phase == "reentry" and phase_time >= 45.0:
		returned = true
		set_phase("complete")
	if energy <= 0.0:
		observing = false
		downlink = false
		failed_reason = "Electrical reserves were exhausted. Reconfigure the battery or suspend nonessential loads earlier."
		set_phase("failed")


func abort() -> void:
	if not terminal():
		observing = false
		downlink = false
		set_phase("aborted")


func report() -> Dictionary:
	var e := evaluate_design(design, mission_id)
	var cap: float = e["parts"]["battery"]["wh"]
	var science := minf(1.0, transmitted / 90.0)
	var safe := 1.0 if returned else 0.0
	var score := roundi(science * 500.0 + safe * 300.0 + (100.0 if done.has("restore") else 0.0) + (50.0 if optional else 0.0) + (50.0 * min_energy / cap if safe > 0.0 else 0.0))
	return {"success": phase == "complete" and transmitted >= 90.0, "score": score, "science": transmitted, "minimum_battery": min_energy / cap * 100.0,
		"minutes": elapsed / 60.0, "feedback": [
			failed_reason if failed_reason != "" else "The spacecraft configuration and your operating decisions jointly determined the energy margin.",
			"Battery reserve fell below 20%. A larger battery or earlier load shedding would improve the margin." if min_energy / cap < 0.2 else "Battery reserves remained above the critical margin.",
			"Storage filled: %d MB was lost. Suspend collection or downlink earlier." % roundi(data_lost) if data_lost > 0.0 else "All collected data stayed within storage capacity.",
			"You isolated, repaired and restored the laboratory circuit." if done.has("restore") else "The laboratory recovery procedure was not completed."]}


# ---- progress ------------------------------------------------------------------
static func load_progress() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"completed": [], "best": {}}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {"completed": [], "best": {}}
	return data


static func save_result(id: String, rep: Dictionary) -> void:
	var p := load_progress()
	if rep["success"] and not p["completed"].has(id):
		p["completed"].append(id)
	p["best"][id] = maxi(int(p["best"].get(id, 0)), int(rep["score"]))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(p))


static func unlocked(id: String) -> bool:
	if id == "orbital":
		return true
	if id == "telescope":
		return load_progress()["completed"].has("orbital") or OS.get_cmdline_user_args().has("--autotest")
	return false
