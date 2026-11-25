class_name EmpireWorldLayer
extends Node3D

const Rules = preload("res://scripts/empire_sim.gd")
const SLOT_LABELS := {
	"defense_turrets": "Defense Batteries", "shield_gen": "Shield Generator",
	"refinery": "Refinery", "radar": "Radar Relay", "hangar": "Refit Hangar",
	"vault": "Command Flag Vault",
}
# Master-planned home districts. West industrial avenue (x=-110, 28 m centre spacing) and east command/fleet
# avenue (x=+110). Every slot owns a paved slab; all coordinates are audited against ponds, pads and rocks by
# tests/planet_a_layout_and_interior_test.gd.
const HOME_SITES := [
	Vector3(-110, 0, 14), Vector3(-110, 0, 42), Vector3(-110, 0, 70),
	Vector3(110, 0, -8), Vector3(110, 0, 20), Vector3(110, 0, 48),
]
const SLAB_TOP := 0.30
const HOME_SLAB_HALF := 7.0      # 14 m x 14 m foundations
const VAULT_SLAB_HALF := 9.0     # 18 m x 18 m Command Flag Vault foundation
const CONCRETE := Color("#8a9097")
const CONCRETE_DARK := Color("#656b72")
const HAZARD_YELLOW := Color("#f2c230")
const HAZARD_BLACK := Color("#14161a")
const FRONTIER_SITES := [
	Vector3(-72, 0, 8), Vector3(-73, 0, 38), Vector3(-65, 0, 58),
	Vector3(72, 0, 8), Vector3(80, 0, 44), Vector3(65, 0, 58),
]
const INTERACT_DISTANCE := 6.5
const SABOTAGE_TIME := 3.0
const REPAIR_HP := 90.0
const REPAIR_COST := 45
const RAID_LANDING_SITES := [
	Vector3(-74, 0, 99), Vector3(74, 0, 99),
	Vector3(-50, 0, 119), Vector3(50, 0, 119),
]
const RAID_TARGETS := ["shield_gen", "refinery", "defense_turrets", "vault"]
const RAID_HP := 70.0
const RAID_BOUNTY := 40
const RAID_COLOR := Color("#ff3f63")
const DEFENSE_COLOR := Color("#58e7ff")
const SABOTAGE_COLOR := Color("#ffac58")
const GOLD_COLOR := Color("#ffd66b")

var empire: Rules
var alliance := "planet_a"
var friendly := true
var squad_id := "orange"
var action: Callable
var slots := {}
var _raid_sites: Array[Vector3] = []
var shield_dome: MeshInstance3D
var sabotage_beacon: Node3D
var raid_groups := {}
var _turret_head: Node3D
var _turret_cooldown := 0.0
var _raid_siren := 0.0
var _shield_sound_delay := 0.0
var _visual_time := 0.0
var _accent: Color
var _burst_time := 0.0
var _sabotage_slot := ""
var _sabotage_left := 0.0
var _sabotage_duration := SABOTAGE_TIME



## Beveled concrete foundation slab with a yellow-black hazard border and corner light bollards. The slab bottom
## sits at y=0 and its top at SLAB_TOP; props must be placed at SLAB_TOP. Returns the slab root (centred at `center`).
static func paved_slab(parent: Node3D, center: Vector3, half: Vector2, accent: Color, slab_name := "Foundation") -> Node3D:
	var root := Node3D.new()
	root.name = slab_name
	root.position = Vector3(center.x, 0.0, center.z)
	root.set_meta("footprint_half", half)
	root.set_meta("slab_top", SLAB_TOP)
	parent.add_child(root)
	var base := Gfx.box(Vector3(half.x * 2.0, 0.22, half.y * 2.0), CONCRETE_DARK, Vector3(0, 0.11, 0))
	base.name = "SlabBase"
	root.add_child(base)
	var plate := Gfx.box(Vector3(half.x * 2.0 - 0.5, 0.08, half.y * 2.0 - 0.5), CONCRETE, Vector3(0, 0.26, 0))
	plate.name = "SlabTop"
	root.add_child(plate)
	var inner := Vector2(half.x - 0.45, half.y - 0.45)
	var strip := 0.34
	for edge in [Vector3(0, 0, -inner.y), Vector3(0, 0, inner.y)]:
		root.add_child(Gfx.box(Vector3(inner.x * 2.0, 0.012, strip), HAZARD_YELLOW, Vector3(edge.x, SLAB_TOP + 0.006, edge.z)))
	for edge in [Vector3(-inner.x, 0, 0), Vector3(inner.x, 0, 0)]:
		root.add_child(Gfx.box(Vector3(strip, 0.012, inner.y * 2.0 - strip * 2.0), HAZARD_YELLOW, Vector3(edge.x, SLAB_TOP + 0.006, edge.z)))
	# Black dashes turn the yellow strip into hazard striping (one MultiMesh per edge orientation).
	var dash_x := BoxMesh.new()
	dash_x.size = Vector3(0.7, 0.014, strip + 0.002)
	var dash_z := BoxMesh.new()
	dash_z.size = Vector3(strip + 0.002, 0.014, 0.7)
	var xs: Array[Transform3D] = []
	var zs: Array[Transform3D] = []
	var nx := int(floor(inner.x * 2.0 / 1.4))
	for i in nx:
		var px := -inner.x + 0.7 + i * 1.4
		xs.append(Transform3D(Basis.IDENTITY, Vector3(px, SLAB_TOP + 0.007, -inner.y)))
		xs.append(Transform3D(Basis.IDENTITY, Vector3(px, SLAB_TOP + 0.007, inner.y)))
	var nz := int(floor((inner.y * 2.0 - strip * 2.0) / 1.4))
	for i in nz:
		var pz := -inner.y + strip + 0.7 + i * 1.4
		zs.append(Transform3D(Basis.IDENTITY, Vector3(-inner.x, SLAB_TOP + 0.007, pz)))
		zs.append(Transform3D(Basis.IDENTITY, Vector3(inner.x, SLAB_TOP + 0.007, pz)))
	for pair in [[dash_x, xs], [dash_z, zs]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = pair[1].size()
		for i in pair[1].size():
			mm.set_instance_transform(i, pair[1][i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "HazardDashes"
		inst.multimesh = mm
		inst.material_override = Gfx.mat(HAZARD_BLACK, 0.8)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(inst)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := Gfx.cyl(0.17, 0.9, Color("#2a2e34"), Vector3(sx * (half.x - 0.9), SLAB_TOP + 0.45, sz * (half.y - 0.9)), 8)
			post.name = "Bollard"
			root.add_child(post)
			var cap := Gfx.cyl(0.2, 0.1, accent, Vector3(sx * (half.x - 0.9), SLAB_TOP + 0.95, sz * (half.y - 0.9)), 8)
			cap.material_override = Gfx.unshaded(accent, 0.95)
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(cap)
	return root


## Paved road strip from `from` to `to` (xz plane). Top surface at y=0.18 (a kerb step below slab tops), with white edge
## lines and a dashed centre line.
static func paved_road(parent: Node3D, from: Vector2, to: Vector2, width: float, road_name := "Road") -> Node3D:
	var root := Node3D.new()
	root.name = road_name
	var mid := (from + to) * 0.5
	var length := from.distance_to(to)
	root.position = Vector3(mid.x, 0.0, mid.y)
	root.rotation.y = atan2(-(to.y - from.y), to.x - from.x)
	root.set_meta("road_half", Vector2(length * 0.5, width * 0.5))
	root.set_meta("center", mid)
	root.set_meta("yaw", root.rotation.y)
	parent.add_child(root)
	root.add_child(Gfx.box(Vector3(length, 0.18, width), Color("#5b6067"), Vector3(0, 0.09, 0)))
	for side in [-1.0, 1.0]:
		root.add_child(Gfx.box(Vector3(length, 0.012, 0.16), Color("#d9dde2"), Vector3(0, 0.186, side * (width * 0.5 - 0.35))))
	var count := int(floor(length / 4.0))
	if count > 0:
		var dash := BoxMesh.new()
		dash.size = Vector3(1.8, 0.012, 0.18)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = dash
		mm.instance_count = count
		for i in count:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(-length * 0.5 + 2.0 + i * 4.0, 0.188, 0)))
		var inst := MultiMeshInstance3D.new()
		inst.name = "CentreDashes"
		inst.multimesh = mm
		inst.material_override = Gfx.mat(HAZARD_YELLOW, 0.8)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(inst)
	return root


## Builds the draggable `EmpireDistricts` group under `root` (Planet A home slots + raid landing markers) so every pad,
## terminal and raid zone is visible and movable in the Godot editor. setup() binds to these nodes at runtime.
static func bake_home_districts(root: Node3D) -> Node3D:
	var districts := Node3D.new()
	districts.name = "EmpireDistricts"
	root.add_child(districts)
	var accent := Color("#58e7ff")
	for index in Rules.BUILDABLE_SLOT_IDS.size():
		var id: String = Rules.BUILDABLE_SLOT_IDS[index]
		var site: Vector3 = HOME_SITES[index]
		var slot := Node3D.new()
		slot.name = id
		slot.position = Vector3(site.x, SLAB_TOP, site.z)
		districts.add_child(slot)
		var side := VAULT_SLAB_HALF if id == "vault" else HOME_SLAB_HALF
		var pad := paved_slab(slot, Vector3.ZERO, Vector2(side, side), accent, "FoundationPad")
		pad.position.y = -SLAB_TOP
		var terminal := Node3D.new()
		terminal.name = "Terminal"
		terminal.position = Vector3(-signf(site.x) * 5.5, 0, 6.0 if id == "vault" else 0.0)
		slot.add_child(terminal)
		var kiosk := Gfx.box(Vector3(0.78, 1.2, 0.68), Color("#253548"), Vector3(0, 0.6, 0))
		kiosk.name = "Kiosk"
		terminal.add_child(kiosk)
		var screen := Gfx.box(Vector3(0.63, 0.10, 0.49), accent, Vector3(0, 1.22, 0), 0.9)
		screen.name = "KioskScreen"
		terminal.add_child(screen)
		var core := Gfx.cyl(0.58, 0.5, accent, Vector3(0, 1.56, 0), 6)
		core.name = "StructureCore"
		core.material_override = Gfx.unshaded(accent, 0.9)
		terminal.add_child(core)
		var guide := Gfx.label(str(SLOT_LABELS[id]).to_upper() + " (" + id + ")", accent, 38, 7)
		guide.name = "EditorGuide"
		guide.position = Vector3(0, 3.2, 0)
		guide.pixel_size = 0.012
		slot.add_child(guide)
	var zones := Node3D.new()
	zones.name = "RaidLandingZones"
	districts.add_child(zones)
	for i in RAID_LANDING_SITES.size():
		var zone := Node3D.new()
		zone.name = "RaidZone%d" % i
		zone.position = RAID_LANDING_SITES[i]
		zones.add_child(zone)
		var ring := Gfx.ring(5.0, 0.15, RAID_COLOR)
		ring.name = "ZoneRing"
		ring.position.y = 0.06
		ring.material_override = Gfx.unshaded(RAID_COLOR, 0.6)
		zone.add_child(ring)
	return districts


func setup(rules: Rules, target: String, is_friendly: bool, squad: String, dispatch: Callable, editable_scene: Node3D = null) -> void:
	name = "EmpireWorldLayer"
	var districts: Node3D = null
	if is_friendly and editable_scene != null and editable_scene.has_node("EmpireDistricts"):
		districts = editable_scene.get_node("EmpireDistricts") as Node3D
	if districts != null:
		var zones := districts.get_node_or_null("RaidLandingZones")
		if zones != null:
			var found: Array[Vector3] = []
			for i in RAID_LANDING_SITES.size():
				var zone := zones.get_node_or_null("RaidZone%d" % i) as Node3D
				found.append(districts.position + zone.position if zone != null else RAID_LANDING_SITES[i])
			_raid_sites = found
	empire = rules
	alliance = target
	friendly = is_friendly
	squad_id = squad
	action = dispatch
	_accent = Color("#58e7ff") if alliance == "planet_a" else Color("#ff684d")
	var sites := HOME_SITES if friendly else FRONTIER_SITES
	for index in Rules.BUILDABLE_SLOT_IDS.size():
		var id: String = Rules.BUILDABLE_SLOT_IDS[index]
		var bound := districts.get_node_or_null(id) as Node3D if districts != null else null
		var anchor: Node3D = bound
		var terminal: Node3D
		if bound != null:
			# Scene-first: the editable slot node IS the anchor; its pad and Terminal already exist in the scene.
			terminal = bound.get_node_or_null("Terminal") as Node3D
			if terminal == null:
				terminal = Node3D.new()
				terminal.name = "Terminal"
				bound.add_child(terminal)
			anchor = bound
		else:
			anchor = Node3D.new()
			anchor.name = id
			anchor.position = sites[index]
			add_child(anchor)
			terminal = Node3D.new()
			terminal.name = "Terminal"
		if bound != null:
			pass
		elif friendly:
			# Paved foundation: the anchor sits ON the slab top so every structure is grounded, never floating.
			var side := VAULT_SLAB_HALF if id == "vault" else HOME_SLAB_HALF
			paved_slab(self, sites[index], Vector2(side, side), _accent, id + "_foundation")
			anchor.position.y = SLAB_TOP
			terminal.position = Vector3(-signf(anchor.position.x) * 5.5, 0, 6.0 if id == "vault" else 0.0)
		else:
			var pad := Gfx.cyl(3.25, 0.08, _accent, Vector3(0, 0.04, 0), 6)
			pad.material_override = Gfx.unshaded(_accent, 0.22)
			anchor.add_child(pad)
			terminal.position = Vector3(-signf(anchor.position.x) * 5.0, 0, 11.0 if id == "vault" else 0.0)
		if bound == null:
			anchor.add_child(terminal)
			terminal.add_child(Gfx.box(Vector3(0.78, 1.2, 0.68), Color("#253548"), Vector3(0, 0.6, 0)))
			terminal.add_child(Gfx.box(Vector3(0.63, 0.10, 0.49), _accent, Vector3(0, 1.22, 0), 0.9))
		var label := Gfx.label("", _accent, 38, 7)
		label.position.y = 2.45
		label.pixel_size = 0.007
		label.visibility_range_end = 58.0
		terminal.add_child(label)
		var core := terminal.get_node_or_null("StructureCore") as MeshInstance3D if bound != null else null
		if core == null:
			core = Gfx.cyl(0.58, 0.5, _accent, terminal.position + Vector3(0, 1.56, 0), 6)
			core.name = "StructureCore"
			core.material_override = Gfx.unshaded(_accent, 0.9)
			anchor.add_child(core)
		var rings: Array[MeshInstance3D] = []
		for tier in 3:
			var ring := Gfx.ring(3.6 + tier * 0.36, 0.12, _accent)
			ring.position.y = 0.12 + tier * 0.045
			ring.material_override = Gfx.unshaded(_accent, 0.85)
			anchor.add_child(ring)
			rings.append(ring)
		var build_beacon: MeshInstance3D
		var defend_label: Label3D
		if friendly:
			var pill := CapsuleMesh.new()
			pill.radius = 0.24
			pill.height = 4.8
			pill.radial_segments = 10
			pill.rings = 4
			build_beacon = MeshInstance3D.new()
			build_beacon.name = "BuildBeacon"
			build_beacon.mesh = pill
			build_beacon.position.y = 8.4
			build_beacon.material_override = Gfx.unshaded(_accent, 1.3)
			build_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			anchor.add_child(build_beacon)
			defend_label = objective_label("DEFEND: " + str(SLOT_LABELS[id]).to_upper(), RAID_COLOR, 11.5)
			defend_label.name = "DefendBeacon"
			defend_label.hide()
			anchor.add_child(defend_label)
		slots[id] = {"anchor": anchor, "terminal": terminal, "label": label, "core": core,
			"rings": rings, "model": null, "tier": -1, "build_beacon": build_beacon,
			"defend_label": defend_label}
	if friendly and alliance == "planet_a":
		_setup_turret()
	elif not friendly:
		var shield_site: Node3D = slots["shield_gen"]["anchor"]
		sabotage_beacon = make_beacon(shield_site, "SabotageShieldBeacon",
			"SABOTAGE SHIELD TO OPEN VAULT", SABOTAGE_COLOR, 13.0)
	var mesh := SphereMesh.new()
	mesh.radius = 12.0
	mesh.height = 12.0
	mesh.is_hemisphere = true
	shield_dome = MeshInstance3D.new()
	shield_dome.name = "VaultShield"
	shield_dome.mesh = mesh
	shield_dome.material_override = BlenderVisualUpgrades.shield(_accent, 0.34, 24.0)
	shield_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if districts != null:
		shield_dome.position = districts.position + (slots["vault"]["anchor"] as Node3D).position
	else:
		shield_dome.position = sites.back() + Vector3(0, SLAB_TOP if friendly else 0.0, 0)
	add_child(shield_dome)
	sync_visuals(false)


func sync_visuals(animate := true) -> void:
	shield_dome.visible = empire.is_shield_active(alliance)
	if sabotage_beacon != null:
		sabotage_beacon.visible = shield_dome.visible
	if _turret_head != null:
		_turret_head.visible = empire.get_defense_dps(alliance) > 0.0
	for id: String in slots:
		var state: Dictionary = empire.structures[alliance][id]
		var slot: Dictionary = slots[id]
		var tier: int = state["tier"]
		var online: bool = state["hp"] > 0.0 and state["sabotage_timer"] <= 0.0
		if animate and slot.has("hp"):
			if friendly and tier > slot["tier"]:
				play_feedback(self, "ui_buy", -12.0)
			if not friendly and state["sabotage_timer"] > 0.0 and slot["sabotage_timer"] <= 0.0:
				play_feedback(self, "ko_chime", -12.0)
			elif id == "shield_gen" and state["hp"] < slot["hp"] and _shield_sound_delay <= 0.0:
				play_feedback(self, "scan_hum", -16.0)
				_shield_sound_delay = 0.22
		slot["hp"] = state["hp"]
		slot["sabotage_timer"] = state["sabotage_timer"]
		if slot["tier"] != tier:
			_set_model(id, tier, animate)
		if friendly:
			slot["build_beacon"].visible = tier == 0 and state["sabotage_timer"] <= 0.0
		slot["core"].visible = tier > 0
		for index in 3:
			slot["rings"][index].visible = index < maxi(1, tier)
			slot["rings"][index].transparency = 0.0 if online else 0.65
		var health := roundi(100.0 * float(state["hp"]) / maxf(1.0, state["max_hp"]))
		var caption := "%s · T%d · %d%% HP\n%s" % [SLOT_LABELS[id], tier, health, _prompt(id)]
		if slot["label"].text != caption:
			slot["label"].text = caption


func _set_model(id: String, tier: int, animate: bool) -> void:
	var slot: Dictionary = slots[id]
	if is_instance_valid(slot["model"]):
		slot["model"].queue_free()
	slot["model"] = null
	slot["tier"] = tier
	if tier == 0:
		return
	var definition: Dictionary = Rules.EMPIRE_SLOTS[id]
	var asset: String = definition.get("south_glb", {}).get(alliance, definition["glb"])
	var model := BlenderVisualUpgrades.place(slot["anchor"], asset.trim_prefix(BlenderVisualUpgrades.MODEL_ROOT.trim_prefix("res://")),
		Vector3.ZERO, 4.8 + tier * 1.35, -signf(slot["anchor"].position.x) * PI * 0.5 if friendly else 0.0)
	slot["model"] = model
	if model != null and animate and is_inside_tree() and not UI.reduced_motion:
		model.position.y = -2.5
		create_tween().tween_property(model, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _prompt(id: String) -> String:
	var state: Dictionary = empire.structures[alliance][id]
	if state["sabotage_timer"] > 0.0:
		return "DISABLED · %ds" % ceili(state["sabotage_timer"])
	if friendly:
		if state["hp"] < state["max_hp"]:
			return "[E] REPAIR · %d CR" % _repair_cost(state)
		var upgrade := empire.can_upgrade(alliance, id)
		if state["tier"] == 0:
			return "[E] BUILD %s T1 · %d CR" % [SLOT_LABELS[id].to_upper(), upgrade["cost"]]
		return "[E] UPGRADE T%d · %d CR" % [upgrade["next_tier"], upgrade["cost"]] if state["tier"] < 3 else "MAX TIER"
	if state["tier"] == 0:
		return "UNBUILT"
	if state["hp"] <= 0.0:
		return "DISABLED"
	if id == _sabotage_slot:
		return "SABOTAGING · %.1fs" % _sabotage_left
	return "[E] SABOTAGE ENEMY %s (3s)" % SLOT_LABELS[id].to_upper()


func nearest_interactable(world_pos: Vector3, max_dist := INTERACT_DISTANCE) -> Dictionary:
	var nearest := {}
	var best := max_dist
	for id: String in slots:
		var terminal: Node3D = slots[id]["terminal"]
		var distance := world_pos.distance_to(terminal.global_position)
		if distance <= best:
			best = distance
			nearest = {"slot_id": id, "position": terminal.global_position, "prompt": _prompt(id)}
	return nearest


func interact(actor_pos: Vector3, is_engineer: bool) -> Dictionary:
	var target := nearest_interactable(actor_pos)
	if target.is_empty():
		return {"ok": false, "reason": "out_of_range"}
	var id: String = target["slot_id"]
	var state: Dictionary = empire.structures[alliance][id]
	if state["sabotage_timer"] > 0.0:
		return {"ok": false, "reason": "disabled"}
	if friendly:
		var type := "repair" if state["hp"] < state["max_hp"] else "build_or_upgrade"
		return _dispatch(type, {"slot_id": id, "alliance": alliance})
	if state["tier"] == 0 or state["hp"] <= 0.0 or _sabotage_slot != "":
		return {"ok": false, "reason": "unavailable"}
	if id in ["vault", "hangar"] and empire.is_shield_active(alliance):
		return {"ok": false, "reason": "shielded"}
	var result := _dispatch("sabotage_start", {"slot_id": id, "alliance": alliance, "engineer": is_engineer})
	if result["ok"]:
		_sabotage_slot = id
		_sabotage_duration = SABOTAGE_TIME * (0.5 if is_engineer else 1.0)
		_sabotage_left = _sabotage_duration
	return result


func tick_terminal(dt: float, actor_pos: Vector3, input_enabled: bool) -> void:
	if _sabotage_slot.is_empty():
		return
	var terminal: Node3D = slots[_sabotage_slot]["terminal"]
	if not input_enabled or terminal.global_position.distance_to(actor_pos) > INTERACT_DISTANCE:
		_dispatch("sabotage_cancel", {"slot_id": _sabotage_slot, "alliance": alliance})
		_sabotage_slot = ""
		return
	_sabotage_left = maxf(0.0, _sabotage_left - dt)
	if _sabotage_left == 0.0:
		var id := _sabotage_slot
		_sabotage_slot = ""
		_dispatch("sabotage", {"slot_id": id, "alliance": alliance})


func sabotage_fraction() -> float:
	return -1.0 if _sabotage_slot.is_empty() else 1.0 - _sabotage_left / _sabotage_duration


func tick_visuals(dt: float, player_local: Vector3) -> void:
	_visual_time += dt
	_shield_sound_delay = maxf(0.0, _shield_sound_delay - dt)
	sync_visuals()
	if friendly:
		return
	_burst_time -= dt
	if _burst_time > 0.0 or empire.get_defense_dps(alliance) <= 0.0:
		return
	var invaders := empire.get_active_invaders(alliance)
	if invaders.is_empty():
		return
	_burst_time = 1.5
	var battery: Node3D = slots["defense_turrets"]["anchor"]
	var destination := player_local + Vector3(0, 4, 0)
	for index in 3:
		var offset := Vector3(index - 1, 0, 0)
		CombatFX.tracer(self, battery.position + Vector3.UP * 4.0 + offset,
			destination + offset * 2.2, _accent, 0.07, 0.18)


func tick_raid(dt: float, authoritative: bool) -> void:
	if _turret_head == null:
		return
	var active := {}
	if empire.act_number >= 2 and empire.winner.is_empty():
		for squad in empire.get_active_invaders(alliance):
			var id: String = squad["id"]
			active[id] = true
			if not raid_groups.has(id):
				_spawn_raid(id)
	for id: String in raid_groups.keys():
		if not active.has(id):
			_remove_raid(id)
	if raid_groups.is_empty():
		_raid_siren = 0.0
		_turret_cooldown = 0.0
		return
	_raid_siren -= dt
	if _raid_siren <= 0.0:
		play_feedback(self, "alarm_warn", -14.0)
		_raid_siren = 8.0
	for id: String in raid_groups:
		_advance_raiders(id, dt, authoritative)
	_tick_raid_turret(dt, authoritative)
	_update_defend_beacons()


func _spawn_raid(id: String) -> void:
	var group := Node3D.new()
	group.name = "Raid_" + id.capitalize()
	add_child(group)
	var index: int = Rules.ALLIANCE_SQUADS["planet_b"].find(id)
	var landing: Vector3 = _raid_sites[index] if index < _raid_sites.size() else RAID_LANDING_SITES[index]
	var dropship := BlenderVisualUpgrades.place(group, "vehicles/cinder_dropship.glb", landing, 16.0, PI)
	var color := RAID_COLOR if index % 2 == 0 else Color("#ff9857")
	var units := {}
	for role in 4:
		var raider := Actor.new()
		var specialist: Dictionary = Sim.SPECIALISTS[role]
		raider.name = "Raider%d" % role
		raider.setup(specialist["model"], role, color, "%s · %s" % [id, specialist["name"]], color)
		for mesh: MeshInstance3D in raider.model.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				if material != null:
					var tinted := material.duplicate() as BaseMaterial3D
					tinted.albedo_color = material.albedo_color.lerp(color, 0.47)
					mesh.set_surface_override_material(surface, tinted)
		group.add_child(raider)
		raider.position = landing + Vector3((role - 1.5) * 2.8, 0, -10.0 - (role % 2) * 2.0)
		raider.install_weapon()
		raider.set_weapon_drawn(true)
		units[raider] = {"hp": RAID_HP, "cooldown": role * 0.24, "lane": (role - 1.5) * 2.9}
	raid_groups[id] = {"root": group, "dropship": dropship, "units": units, "target": ""}


func _remove_raid(id: String) -> void:
	var group: Node3D = raid_groups[id]["root"]
	raid_groups.erase(id)
	group.hide()
	group.queue_free()
	_update_defend_beacons()


func _raid_target(from: Vector3) -> String:
	var nearest := ""
	var best := INF
	for id: String in RAID_TARGETS:
		var state: Dictionary = empire.structures[alliance][id]
		if state["hp"] <= 0.0 or (id == "vault" and empire.is_shield_active(alliance)):
			continue
		var anchor: Node3D = slots[id]["anchor"]
		var distance := from.distance_squared_to(anchor.position)
		if distance < best:
			nearest = id
			best = distance
	return nearest


func _advance_raiders(id: String, dt: float, authoritative: bool) -> void:
	var raid: Dictionary = raid_groups[id]
	var units: Dictionary = raid["units"]
	var lead: Actor = units.keys().front()
	var target := _raid_target(lead.position)
	raid["target"] = target
	for raider: Actor in units:
		var unit: Dictionary = units[raider]
		if target.is_empty():
			raider.animate(dt, 0.0)
			continue
		var anchor: Node3D = slots[target]["anchor"]
		var core: Node3D = slots[target]["core"]
		var destination := anchor.position + Vector3(unit["lane"], 0, 0)
		# Cross behind the complex when the remaining targets are on the other flank.
		var crossing := absf(raider.position.x - destination.x) > 11.0 and signf(raider.position.x) != signf(destination.x)
		if crossing:
			destination.z = 87.0
			if raider.position.z < 85.0 and absf(raider.position.x) > 45.0:
				destination.x = raider.position.x
		var distance := raider.walk_to(destination, dt, 5.5, 1.0 if crossing else 11.0)
		unit["cooldown"] = maxf(0.0, unit["cooldown"] - dt)
		if not crossing and distance <= 11.0:
			raider.face(anchor.position - raider.position, dt)
			if unit["cooldown"] <= 0.0:
				unit["cooldown"] = 1.2
				raider.trigger_weapon_kick()
				fire_raid_bolt(actor_muzzle(raider), core.global_position, RAID_COLOR)
				if authoritative:
					empire.damage_structure(alliance, target, 5.0, id)
		raider.animate(dt, raider.vel.length())


func _setup_turret() -> void:
	_turret_head = Node3D.new()
	_turret_head.name = "DefenseTurretAim"
	_turret_head.position.y = 4.2
	slots["defense_turrets"]["anchor"].add_child(_turret_head)
	_turret_head.add_child(Gfx.box(Vector3(1.65, 0.45, 0.8), Color("#30495b"), Vector3.ZERO))
	for side in [-1.0, 1.0]:
		_turret_head.add_child(Gfx.box(Vector3(0.25, 0.23, 1.8), DEFENSE_COLOR,
			Vector3(side * 0.65, 0.0, -0.8), 0.65))


func _tick_raid_turret(dt: float, authoritative: bool) -> void:
	var dps := empire.get_defense_dps(alliance)
	if dps <= 0.0:
		return
	var target := nearest_raider(_turret_head.global_position, 165.0)
	if target == null:
		return
	var aim := raider_center(target)
	_turret_head.look_at(aim)
	_turret_cooldown = maxf(0.0, _turret_cooldown - dt)
	if _turret_cooldown > 0.0:
		return
	_turret_cooldown = 0.55
	for side in [-1.0, 1.0]:
		fire_raid_bolt(_turret_head.to_global(Vector3(side * 0.65, 0.0, -1.7)), aim, DEFENSE_COLOR)
	if authoritative:
		damage_raider(target, dps * _turret_cooldown)


func _update_defend_beacons() -> void:
	var threatened := {}
	for raid: Dictionary in raid_groups.values():
		threatened[raid["target"]] = true
	for id: String in slots:
		var marker: Label3D = slots[id]["defend_label"]
		marker.visible = threatened.has(id)
		marker.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_visual_time * 5.0)) if not UI.reduced_motion else 1.0


func nearest_raider(from: Vector3, distance: float) -> Actor:
	var nearest: Actor
	var limit := distance * distance
	for raid: Dictionary in raid_groups.values():
		for raider: Actor in raid["units"]:
			var separation := from.distance_squared_to(raider_center(raider))
			if separation < limit:
				nearest = raider
				limit = separation
	return nearest


# Returns the bounty paid for this hit. Only the world authority calls this.
func damage_raider(raider: Actor, damage: float, player_shot := false) -> int:
	for id: String in raid_groups.keys():
		var units: Dictionary = raid_groups[id]["units"]
		if not units.has(raider):
			continue
		var unit: Dictionary = units[raider]
		unit["hp"] = maxf(0.0, unit["hp"] - damage)
		raider.set_health(unit["hp"] / RAID_HP * 100.0)
		if unit["hp"] > 0.0:
			return 0
		units.erase(raider)
		raider.hide()
		raider.queue_free()
		if player_shot:
			empire.treasury[alliance] += RAID_BOUNTY
			empire.squads[squad_id]["credits_contributed"] += RAID_BOUNTY
		if units.is_empty():
			_remove_raid(id)
			empire.repel_raid(id)
		return RAID_BOUNTY if player_shot else 0
	return 0


func fire_raid_bolt(from: Vector3, to: Vector3, color: Color) -> void:
	var delta := to - from
	var distance := delta.length()
	if distance < 0.1:
		return
	var bolt := Gfx.box(Vector3(0.07, 0.07, 2.25), color, Vector3.ZERO)
	bolt.name = "RaidBolt"
	bolt.material_override = Gfx.unshaded(color, 1.5)
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bolt)
	bolt.global_position = from
	bolt.look_at(to, Vector3.FORWARD if absf(delta.y) / distance > 0.99 else Vector3.UP)
	var travel := clampf(distance / 135.0, 0.07, 0.45)
	var tween := bolt.create_tween()
	tween.tween_property(bolt, "global_position", to, travel)
	tween.tween_callback(bolt.queue_free)


static func raider_center(raider: Actor) -> Vector3:
	return raider.global_position + Vector3.UP * raider.visual_height * 0.55


static func actor_muzzle(actor: Actor) -> Vector3:
	return actor.weapon_muzzle.global_position if actor.weapon_muzzle else raider_center(actor)


static func objective_label(caption: String, color: Color, height: float) -> Label3D:
	var label := Gfx.label(caption, color, 48, 10)
	label.position.y = height
	label.fixed_size = true
	label.pixel_size = 0.00065
	label.visibility_range_end = 300.0
	return label


static func make_beacon(parent: Node3D, beacon_name: String, caption: String, color: Color, height: float) -> Node3D:
	var beacon := Node3D.new()
	beacon.name = beacon_name
	parent.add_child(beacon)
	var beam := Gfx.cyl(0.15, height - 3.0, color, Vector3(0, (height + 1.0) * 0.5, 0), 10)
	beam.name = "Beam"
	beam.material_override = Gfx.unshaded(color, 1.2)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(beam)
	var label := objective_label(caption, color, height)
	label.name = "Label"
	beacon.add_child(label)
	return beacon


static func play_feedback(world: Node, cue: String, volume: float) -> void:
	if not world.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var audio := world.get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", cue, volume, 0.0)


func ray_core(origin: Vector3, direction: Vector3, limit: float) -> Dictionary:
	var closest := {}
	for id: String in slots:
		var core: MeshInstance3D = slots[id]["core"]
		if not core.visible:
			continue
		var anchor: Node3D = slots[id]["anchor"]
		var core_pos := to_local(core.global_position) if core.is_inside_tree() and is_inside_tree() else anchor.position + core.position
		var offset := core_pos - origin
		var projection := offset.dot(direction)
		var radial := 0.92 * 0.92 - (offset.length_squared() - projection * projection)
		if radial < 0.0:
			continue
		var distance := projection - sqrt(radial)
		if distance > 0.0 and distance < limit:
			limit = distance
			closest = {"slot_id": id, "distance": distance}
	return closest


func hit_core(id: String, role: int) -> Dictionary:
	var result := _dispatch("damage_structure", {"slot_id": id, "alliance": alliance, "role": role})
	if result.get("reason") == "shielded" and _shield_sound_delay <= 0.0:
		play_feedback(self, "scan_hum", -16.0)
		_shield_sound_delay = 0.22
	return result


func _dispatch(type: String, payload: Dictionary) -> Dictionary:
	var result: Dictionary
	if action.is_valid():
		result = action.call(type, payload)
	else:
		var id: String = payload["slot_id"]
		match type:
			"repair":
				result = repair_slot(empire, alliance, id, squad_id)
			"build_or_upgrade":
				result = empire.build_or_upgrade(alliance, id, squad_id)
			"sabotage":
				result = empire.sabotage_structure(alliance, id, Rules.SABOTAGE_THRESHOLD, squad_id)
			"damage_structure":
				result = empire.damage_structure(alliance, id, 22.0, squad_id)
			_:
				result = {"ok": true}
	if result.get("ok", false):
		sync_visuals()
	return result



static func _repair_cost(state: Dictionary) -> int:
	var missing := minf(REPAIR_HP, float(state["max_hp"]) - float(state["hp"]))
	return ceili(REPAIR_COST * missing / REPAIR_HP)


static func repair_slot(rules: Rules, target: String, id: String, squad: String) -> Dictionary:
	if not Rules.EMPIRE_SLOTS.has(id):
		return {"ok": false, "reason": "unknown_structure"}
	var state: Dictionary = rules.structures[target][id]
	var cost := _repair_cost(state)
	if state["sabotage_timer"] > 0.0 or cost <= 0:
		return {"ok": false, "reason": "repair_unavailable"}
	if rules.treasury[target] < cost:
		return {"ok": false, "reason": "insufficient_credits"}
	var result := rules.repair_structure(target, id, REPAIR_HP, squad)
	if result["ok"]:
		rules.treasury[target] -= cost
		result["cost"] = cost
	return result
