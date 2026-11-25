extends Control

const UI = preload("res://scripts/ui/UIThemeUtils.gd")

var _drawer: PanelContainer
var _ship_tags := {}


func setup(frontend: CanvasLayer) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	UI.shade(self, [Color("#070e18"), Color("#070e1800")])
	for faction in UI.FACTIONS:
		var tint := UI.faction_color(faction)
		var tag := UI.card(self, Color(tint, 0.47), 7)
		tag.mouse_filter = MOUSE_FILTER_IGNORE
		UI.label(tag, "◈ " + faction.to_upper() + " MOTHERSHIP", 13, tint.lightened(0.28), 700)
		_ship_tags[faction] = tag
	var rail := MarginContainer.new()
	add_child(rail)
	rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_left = 43
	rail.anchor_right = 0.3
	rail.offset_right = 18
	rail.offset_top = 42
	rail.offset_bottom = -38
	rail.mouse_filter = MOUSE_FILTER_IGNORE
	var menu := UI.column(rail, 10)
	menu.mouse_filter = MOUSE_FILTER_IGNORE
	var imprint := UI.row(menu, 9)
	var mark := UI.label(imprint, "◆", 16, UI.CYAN)
	mark.custom_minimum_size.x = 19
	UI.label(imprint, "VESPER-9 OPERATIONS", 14, UI.CYAN, 700)
	UI.space(menu)
	UI.label(menu, "APOGEX", 74, UI.INK, 850)
	var subtitle := UI.label(menu, "VESPER-9 · 16V16 PLANETARY & ORBITAL WARFARE", 15, UI.MUTED, 650)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size.x = 335
	UI.line(menu, UI.CYAN.darkened(0.47))
	var quick := UI.button(menu, "PLAY — QUICK DEPLOY", frontend.quick_deploy, UI.CYAN, 56)
	quick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for entry in [
		["MATCH LOBBY (16V16 / MULTIPLAYER)", frontend.open_lobby],
		["EXPLORER SANDBOX", frontend.world.enter_sandbox_mode],
		["SETTINGS", frontend.toggle_settings],
		["CONTROLS & FIELD GUIDE", frontend.toggle_field_guide],
		["QUIT", get_tree().quit],
	]:
		var item := UI.button(menu, entry[0], entry[1])
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UI.space(menu)
	_drawer = UI.card(self, UI.STEEL.lightened(0.14), 23)
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_drawer.offset_left = 435
	_drawer.offset_right = 838
	_drawer.offset_top = -228
	_drawer.hide()


func project_ships(camera: Camera3D, world: Node) -> void:
	for faction in _ship_tags:
		var tag: PanelContainer = _ship_tags[faction]
		var origin: Vector3 = world.mothership_manager.ship_origin(faction)
		var point: Vector3 = world.floating_origin.planet_to_render(origin)
		var projected := camera.unproject_position(point)
		tag.visible = Rect2(Vector2(0.34 * size.x, 34), Vector2(0.66 * size.x, size.y - 34)).has_point(projected)
		tag.position = Vector2(clampf(projected.x - tag.size.x * 0.5, size.x * 0.34, maxf(size.x * 0.34, size.x - tag.size.x - 20)), projected.y - 53.0)


func show_drawer(frontend: CanvasLayer, kind: String) -> void:
	for child in _drawer.get_children():
		_drawer.remove_child(child)
		child.queue_free()
	_drawer.visible = not kind.is_empty()
	if kind.is_empty():
		return
	var column := UI.column(_drawer, 12)
	var title := UI.row(column)
	UI.label(title, "SETTINGS" if kind == "settings" else "CONTROLS & FIELD GUIDE", 23, UI.INK, 750)
	UI.space(title)
	UI.button(title, "×", frontend.close_drawer, Color.TRANSPARENT, 35)
	UI.line(column)
	if kind == "settings":
		frontend.build_settings(column)
	else:
		for group in [
			["INFANTRY", "WASD move · Shift sprint · Space jump / EVA\nLMB use tool · 1 rifle · 2 engineering · R reload\n3 / 4 / 5 deploy turret / shield / supplies"],
			["VEHICLES", "E board / tap to exit · V camera · Shift boost\nLMB guns · RMB missiles · Q / hold E roll\nX hover · Z flight assist"],
			["TACTICAL", "B redeploy · Tab scoreboard · O commander\nM map · P world tools · Esc pause / close"],
			["EXPLORER", "F walk / fly · C camera · G gravity alignment\nF1 diagnostics · F2 wireframe · F3 collision\nF4 LOD · F5 regenerate · F6 landmark · F7 orbit"],
		]:
			UI.label(column, group[0], 14, UI.CYAN, 750)
			UI.label(column, group[1], 15, UI.INK)
