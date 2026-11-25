extends Control

const UI = preload("res://scripts/ui/UIThemeUtils.gd")
const LOCATIONS := {
	"hangar": ["Main Hangar", "ORBITAL · INFANTRY", "Deploy on foot beside the faction fighters and dropships."],
	"fighter": ["Launch Fighter", "ORBITAL · COCKPIT", "Board the faction’s flight-ready hangar fighter."],
	"bridge": ["Command Bridge", "ORBITAL · COMMAND", "Deploy beside the Tactical Holotable. Press O to open commander orders."],
	"alpha": ["Terminus Extraction Spire", "ALPHA · CENTRAL BASIN", "Southern apron of Terminus Extraction Spire. Rovers available."],
	"bravo": ["Northern Mining Excavation", "BRAVO · FRACTURED HIGHLANDS", "Excavation pad overlooking the northern mining works."],
	"charlie": ["Eastern Iron Refinery", "CHARLIE · IRON DESERT", "Refinery staging grounds. A rover is parked nearby."],
}
const PIN_POINTS := {"alpha": Vector2(0.5, 0.51), "bravo": Vector2(0.5, 0.255), "charlie": Vector2(0.7222, 0.51)}


class TacticalMap extends Control:
	const UI = preload("res://scripts/ui/UIThemeUtils.gd")
	var terrain: Texture2D

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0a1623"))
		var map_rect := Rect2(0, size.y * 0.085, size.x, size.y * 0.85)
		if terrain != null:
			draw_texture_rect(terrain, map_rect, false, Color("#c1d7e8"))
		draw_rect(map_rect, Color("#06172525"))
		for step in range(1, 12):
			var x := size.x * step / 12.0
			draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), Color("#bdddf22e"))
		for step in range(1, 8):
			var y := map_rect.position.y + map_rect.size.y * step / 8.0
			draw_line(Vector2(0, y), Vector2(size.x, y), Color("#bdddf22e"))
		draw_rect(map_rect, UI.STEEL.lightened(0.25), false, 1.0)
		var center := size * Vector2(0.5, 0.51)
		draw_arc(center, minf(size.x, size.y) * 0.25, 0.0, TAU, 72, Color("#c3d9e25f"), 1.0, true)
		draw_arc(center, minf(size.x, size.y) * 0.38, 0.0, TAU, 72, Color("#c3d9e244"), 1.0, true)


var _frontend: CanvasLayer
var _map: TacticalMap
var _pins := {}
var _orbit_ships := {}
var _orbit_actions := {}
var _location: Label
var _layer: Label
var _owner: Label
var _description: Label
var _faction: OptionButton
var _role: OptionButton
var _role_detail: Label
var _deploy: Button
var _back: Button
var _notice: Label


func setup(frontend: CanvasLayer) -> void:
	_frontend = frontend
	UI.shade(self, [Color("#070d17f5"), Color("#101d2cf2")], false)
	var margin := MarginContainer.new()
	UI.full(self, margin, 30)
	var layout := UI.column(margin, 13)
	var header := UI.row(layout)
	var title := UI.column(header, 2)
	UI.label(title, "APOGEX  /  VESPER-9", 14, UI.CYAN, 750)
	UI.label(title, "Tactical Deployment", 44, UI.INK, 780)
	UI.space(header)
	_back = UI.button(header, "← BACK  [ESC]", frontend.back_from_spawn)
	_back.size_flags_vertical = SIZE_SHRINK_CENTER

	var body := UI.row(layout, 15)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	var frame := UI.card(body, UI.STEEL.lightened(0.13), 12)
	frame.size_flags_horizontal = SIZE_EXPAND_FILL
	var column := UI.column(frame, 10)
	var orbit := UI.row(column, 12)
	UI.label(orbit, "ORBIT", 14, UI.MUTED, 750)
	for faction in UI.FACTIONS:
		var ship := UI.button(orbit, "◈  %s MOTHERSHIP" % faction.to_upper(), func() -> void:
			if frontend.select_faction(faction):
				frontend.select_spawn("hangar")
		, UI.faction_color(faction), 38)
		ship.size_flags_horizontal = SIZE_EXPAND_FILL
		_orbit_ships[faction] = ship
	var ship_actions := UI.row(column, 8)
	for id in ["hangar", "fighter", "bridge"]:
		var action := UI.button(ship_actions, LOCATIONS[id][0], frontend.select_spawn.bind(id), UI.CYAN, 38)
		action.size_flags_horizontal = SIZE_EXPAND_FILL
		_orbit_actions[id] = action

	_map = TacticalMap.new()
	_map.size_flags_vertical = SIZE_EXPAND_FILL
	_map.custom_minimum_size.y = 270
	_map.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(_map)
	_map.resized.connect(_layout_pins)
	var subtitle := UI.label(_map, "SURFACE GRID  /  ±30° LAT  ·  ±45° LON", 13, UI.MUTED, 750)
	subtitle.position = Vector2(8, 2)
	for region in [
		["FRACTURED HIGHLANDS", Vector2(0.44, 0.133)], ["TERMINUS BASIN", Vector2(0.449, 0.605)],
		["IRON DESERT", Vector2(0.684, 0.606)], ["OBSIDIAN FIELDS", Vector2(0.21, 0.555)],
	]:
		var name_label := UI.label(_map, region[0], 13, Color("#eef6fa"), 750)
		name_label.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
		name_label.anchor_left = region[1].x
		name_label.anchor_right = region[1].x
		name_label.anchor_top = region[1].y
		name_label.anchor_bottom = region[1].y
	for id in PIN_POINTS:
		var pin := UI.button(_map, "◆ " + id.to_upper(), frontend.select_spawn.bind(id), UI.MUTED, 38)
		_pins[id] = pin
	_layout_pins()
	var legend := UI.row(column, 16)
	UI.label(legend, "CONTROL", 13, UI.MUTED, 750)
	for id in ["neutral", "helion", "cinder"]:
		UI.label(legend, "◆ " + id.to_upper(), 13, UI.faction_color(id), 700)

	var details := UI.card(body, UI.STEEL, 19)
	details.custom_minimum_size.x = 345
	var aside := UI.column(details, 11)
	_layer = UI.label(aside, "", 13, UI.CYAN, 750)
	_location = UI.label(aside, "", 29, UI.INK, 780)
	_location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_owner = UI.label(aside, "", 14, UI.MUTED, 750)
	_description = UI.label(aside, "", 17, UI.MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.line(aside)
	UI.label(aside, "DEPLOYMENT LOADOUT", 14, UI.MUTED, 750)
	_faction = UI.option(aside, ["Helion", "Cinder"], func(index: int) -> void: frontend.select_faction(UI.FACTIONS[index]))
	_role = UI.select_role(aside, frontend.select_role)
	_role_detail = UI.label(aside, "", 15, UI.MUTED)
	_role_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.space(aside)
	_notice = UI.label(aside, "", 15, UI.ORANGE)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deploy = UI.button(aside, "DEPLOY NOW", frontend.deploy_selected, UI.CYAN, 62)


func _layout_pins() -> void:
	for id in _pins:
		var pin: Button = _pins[id]
		var center: Vector2 = PIN_POINTS[id] * _map.size
		pin.size = Vector2(115, 38)
		pin.position = center - pin.size * 0.5
	_map.queue_redraw()


func prepare_map() -> void:
	_map.terrain = _frontend.world.debug_ui.get_tactical_terrain()
	_map.queue_redraw()


func refresh() -> void:
	var front := _frontend
	var world: Node = front.world
	var point: Array = LOCATIONS[front.spawn_id]
	var tint := UI.faction_color(front.faction)
	var owners := {}
	for objective in world.capture_objectives:
		owners[objective.objective_id] = objective.owner_faction
	var owner: String = owners.get(front.spawn_id, front.faction)
	_location.text = point[0]
	_layer.text = point[1]
	_layer.add_theme_color_override("font_color", tint)
	_owner.text = "◆ " + ("NEUTRAL" if owner == "neutral" else owner.to_upper() + " CONTROL")
	_owner.add_theme_color_override("font_color", UI.faction_color(owner))
	_description.text = point[2]
	_faction.select(UI.FACTIONS.find(front.faction))
	_faction.disabled = (not world.can_mutate_world() and not front.client_ready()) or front.deploy_pending
	_role.select(UI.ROLES.keys().find(front.role))
	_role_detail.text = UI.ROLES[front.role][1]
	_back.disabled = front.respawn_required or front.deploy_pending
	_deploy.disabled = front.respawn_remaining > 0.0 or front.deploy_pending
	_deploy.text = "RESPAWN IN %.1f S" % front.respawn_remaining if front.respawn_remaining > 0.0 else ("DEPLOYING…" if front.deploy_pending else "DEPLOY NOW")
	_notice.text = front.notice
	for id in _pins:
		var pin: Button = _pins[id]
		pin.text = ("◆ " if id == front.spawn_id else "◇ ") + id.to_upper()
		UI.emphasis(pin, UI.faction_color(owners.get(id, "neutral")), id == front.spawn_id)
	for faction in _orbit_ships:
		_orbit_ships[faction].disabled = (not world.can_mutate_world() and not front.client_ready()) or front.deploy_pending
	for id in _orbit_actions:
		var action: Button = _orbit_actions[id]
		action.text = ("◆ " if id == front.spawn_id else "◇ ") + LOCATIONS[id][0]
		UI.emphasis(action, tint)
	UI.emphasis(_deploy, tint)
