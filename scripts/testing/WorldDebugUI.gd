class_name WorldDebugUI
extends CanvasLayer
## Optional compact developer HUD + F1 diagnostics + M interactive map + P settings panel (mouse friendly).
## Talks to the WorldRoot through plain method calls (duck typed to avoid a script cycle).

const Transforms = preload("res://scripts/coordinates/CoordinateTransformUtils.gd")

signal panel_visibility_changed

const MAP_LON_RANGE := Vector2(-45.0, 45.0)
const MAP_LAT_RANGE := Vector2(-30.0, 30.0)
const BIOME_COLORS: Array[Color] = [
	Color(0.34, 0.31, 0.3),    # Ashen Wastes
	Color(0.7, 0.22, 0.12),    # Crimson Canyons
	Color(0.14, 0.1, 0.2),     # Obsidian Fields
	Color(0.74, 0.43, 0.18),   # Iron Desert
	Color(0.72, 0.7, 0.64),    # Fractured Highlands
	Color(0.52, 0.4, 0.36),    # Terminus Basin
]
const BIOME_NAMES: Array[String] = [
	"Ashen Wastes", "Crimson Canyons", "Obsidian Fields", "Iron Desert", "Fractured Highlands", "Terminus Basin",
]


## 2D world map: biome raster, landmark pins, live player dot, click-to-teleport.
class MapView:
	extends Control

	signal landmark_clicked(index: int)

	var map_texture: ImageTexture
	var pins: Array[Dictionary] = []     # {index, name, lat, lon}
	var player_lat: float = 0.0
	var player_lon: float = 0.0
	var player_heading: float = 0.0
	var _hover: int = -1

	func _init() -> void:
		custom_minimum_size = Vector2(720, 480)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func to_screen(lat: float, lon: float) -> Vector2:
		var u: float = inverse_lerp(WorldDebugUI.MAP_LON_RANGE.x, WorldDebugUI.MAP_LON_RANGE.y, lon)
		var v: float = inverse_lerp(WorldDebugUI.MAP_LAT_RANGE.y, WorldDebugUI.MAP_LAT_RANGE.x, lat)
		return Vector2(u * size.x, v * size.y)

	func _pin_at(p: Vector2) -> int:
		var best: int = -1
		var best_d: float = 16.0
		for i in pins.size():
			var d: float = to_screen(pins[i]["lat"], pins[i]["lon"]).distance_to(p)
			if d < best_d:
				best_d = d
				best = i
		return best

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var h: int = _pin_at((event as InputEventMouseMotion).position)
			if h != _hover:
				_hover = h
				queue_redraw()
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				var i: int = _pin_at(mb.position)
				if i >= 0:
					landmark_clicked.emit(int(pins[i]["index"]))
					accept_event()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.02, 0.02, 0.03))
		if map_texture != null:
			draw_texture_rect(map_texture, rect, false)
		# Graticule every 10 degrees.
		for lon in range(-40, 41, 10):
			var a: Vector2 = to_screen(WorldDebugUI.MAP_LAT_RANGE.y, float(lon))
			var b: Vector2 = to_screen(WorldDebugUI.MAP_LAT_RANGE.x, float(lon))
			draw_line(a, b, Color(1, 1, 1, 0.08), 1.0)
		for lat in range(-20, 21, 10):
			var a2: Vector2 = to_screen(float(lat), WorldDebugUI.MAP_LON_RANGE.x)
			var b2: Vector2 = to_screen(float(lat), WorldDebugUI.MAP_LON_RANGE.y)
			draw_line(a2, b2, Color(1, 1, 1, 0.08), 1.0)
		var font: Font = ThemeDB.fallback_font
		for i in pins.size():
			var p: Vector2 = to_screen(pins[i]["lat"], pins[i]["lon"])
			var hot: bool = i == _hover
			draw_circle(p, 8.0 if hot else 6.0, Color(0, 0, 0, 0.8))
			draw_circle(p, 5.5 if hot else 4.0, Color(1.0, 0.85, 0.3) if hot else Color(1.0, 0.6, 0.15))
			var label: String = str(pins[i]["name"])
			draw_string(font, p + Vector2(10, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95 if hot else 0.8))
		# Live player marker, clamped to the map edge when outside the shown region.
		var pp: Vector2 = to_screen(player_lat, player_lon)
		pp = pp.clamp(Vector2(4, 4), size - Vector2(4, 4))
		draw_circle(pp, 7.0, Color(0, 0, 0, 0.8))
		draw_circle(pp, 5.0, Color(0.2, 1.0, 0.55))
		draw_arc(pp, 10.0, 0, TAU, 20, Color(0.2, 1.0, 0.55, 0.6), 1.5)
		draw_rect(rect, Color(1, 1, 1, 0.35), false, 1.0)


var world: Node
var hud_bar: PanelContainer
var diag_panel: PanelContainer
var diag_label: Label
var storm_label: Label
var settings_panel: PanelContainer
var map_panel: PanelContainer
var map_view: MapView
var seed_edit: LineEdit
var quality_option: OptionButton
var camera_option: OptionButton
var toggle_buttons: Dictionary = {}
var status_label: Label
var _refresh_accum: float = 0.0
var _map_built_seed: int = -1
var network_button: Button


func _ready() -> void:
	layer = 50
	_build_hud_bar()
	_build_diag_panel()
	_build_settings_panel()
	_build_map_panel()


func setup(p_world: Node) -> void:
	world = p_world
	if seed_edit != null:
		seed_edit.text = str(world.get("world_config").world_seed)
	refresh_map_pins()


func _process(delta: float) -> void:
	if world == null:
		return
	_refresh_accum += delta
	if _refresh_accum < 0.2:
		return
	_refresh_accum = 0.0
	var d: Dictionary = world.get_diagnostics()
	if diag_panel.visible:
		diag_label.text = _format_diagnostics(d)
	if map_panel.visible:
		map_view.player_lat = d.get("lat_deg", 0.0)
		map_view.player_lon = d.get("lon_deg", 0.0)
		map_view.queue_redraw()
	if settings_panel.visible:
		_sync_settings(d)
		if storm_label != null:
			storm_label.text = "Storm: %.0f%%" % (float(d.get("weather", {}).get("storm_intensity", 0.0)) * 100.0)
	status_label.text = "%s | %s | %s | %.0f FPS" % [d.get("camera_mode", ""), d.get("move_mode", ""), d.get("biome", ""), d.get("fps", 0.0)]


func set_dev_bar_visible(enabled: bool) -> void:
	hud_bar.visible = enabled


func update_panel_layer() -> void:
	layer = 70 if map_panel.visible or settings_panel.visible or diag_panel.visible else 50


func get_tactical_terrain() -> Texture2D:
	_ensure_map_texture()
	return map_view.map_texture


func is_any_panel_open() -> bool:
	return settings_panel.visible or map_panel.visible or (
		world != null and world.combat_hud != null and world.combat_hud.has_open_panel()
	)


# --- toggles -----------------------------------------------------------------------------------

func toggle_diagnostics() -> void:
	diag_panel.visible = not diag_panel.visible
	update_panel_layer()


func toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		map_panel.visible = false
	panel_visibility_changed.emit()


func toggle_map() -> void:
	map_panel.visible = not map_panel.visible
	if map_panel.visible:
		settings_panel.visible = false
		_ensure_map_texture()
		refresh_map_pins()
	panel_visibility_changed.emit()


# --- construction ------------------------------------------------------------------------------

func _panel_style(alpha: float = 0.72) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, alpha)
	sb.border_color = Color(1.0, 0.5, 0.2, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _make_button(text: String, tooltip: String, callback: Callable, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	if toggle:
		b.toggled.connect(func(_on: bool) -> void: callback.call())
	else:
		b.pressed.connect(callback)
	return b


func _world_call(method: StringName, args: Array = []) -> void:
	if world != null and world.has_method(method):
		world.callv(method, args)


func _build_hud_bar() -> void:
	hud_bar = PanelContainer.new()
	hud_bar.name = "HudBar"
	hud_bar.add_theme_stylebox_override("panel", _panel_style(0.6))
	hud_bar.position = Vector2(8, 8)
	add_child(hud_bar)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	hud_bar.add_child(vb)
	var title := Label.new()
	title.text = "APOGEX  VESPER-9"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.62, 0.3))
	vb.add_child(title)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vb.add_child(status_label)
	var keys := Label.new()
	keys.text = "WASD move  Space/Ctrl up/down  Shift fast  Wheel speed  C camera\nF walk/fly  G gravity  M map  P settings  F1 diag  F2 wire  F3 coll  F4 LOD\nF5 regen  F6 next landmark  F7 orbit/surface  H hangar doors  K destruction  Esc pause"
	keys.add_theme_font_size_override("font_size", 10)
	keys.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(keys)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vb.add_child(row)
	row.add_child(_make_button("Settings", "P", func() -> void: _world_call(&"toggle_settings")))
	row.add_child(_make_button("Map", "M", func() -> void: _world_call(&"toggle_map")))
	row.add_child(_make_button("Diag", "F1", func() -> void: toggle_diagnostics()))
	row.add_child(_make_button("Next", "F6", func() -> void: _world_call(&"cycle_landmark")))
	row.add_child(_make_button("Orbit/Surface", "F7", func() -> void: _world_call(&"toggle_orbit_surface_view")))


func _build_diag_panel() -> void:
	diag_panel = PanelContainer.new()
	diag_panel.name = "DiagnosticsPanel"
	diag_panel.add_theme_stylebox_override("panel", _panel_style(0.78))
	diag_panel.visible = false
	diag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diag_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	diag_panel.position = Vector2(-410, 8)
	diag_panel.anchor_left = 1.0
	diag_panel.anchor_right = 1.0
	diag_panel.offset_left = -420.0
	diag_panel.offset_right = -8.0
	diag_panel.offset_top = 8.0
	add_child(diag_panel)
	diag_label = Label.new()
	diag_label.add_theme_font_size_override("font_size", 11)
	diag_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	diag_panel.add_child(diag_label)


func _build_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.add_theme_stylebox_override("panel", _panel_style(0.88))
	settings_panel.visible = false
	settings_panel.anchor_left = 1.0
	settings_panel.anchor_right = 1.0
	settings_panel.anchor_top = 0.0
	settings_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	settings_panel.offset_left = -420.0
	settings_panel.offset_right = -10.0
	settings_panel.offset_top = 60.0
	add_child(settings_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	settings_panel.add_child(vb)
	var title := Label.new()
	title.text = "WORLD SETTINGS"
	title.add_theme_color_override("font_color", Color(1.0, 0.62, 0.3))
	vb.add_child(title)

	var seed_row := HBoxContainer.new()
	vb.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "World Seed"
	seed_row.add_child(seed_label)
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(110, 0)
	seed_edit.text = "4209"
	seed_edit.text_submitted.connect(func(_t: String) -> void: _regenerate_from_field())
	seed_row.add_child(seed_edit)
	seed_row.add_child(_make_button("Regenerate", "F5 regenerates with the current seed", func() -> void: _regenerate_from_field()))

	var q_row := HBoxContainer.new()
	vb.add_child(q_row)
	var q_label := Label.new()
	q_label.text = "Quality"
	q_row.add_child(q_label)
	quality_option = OptionButton.new()
	for preset in ["LOW", "MEDIUM", "HIGH", "ULTRA"]:
		quality_option.add_item(preset)
	quality_option.item_selected.connect(func(i: int) -> void: _world_call(&"set_quality_preset", [quality_option.get_item_text(i)]))
	q_row.add_child(quality_option)

	var c_row := HBoxContainer.new()
	vb.add_child(c_row)
	var c_label := Label.new()
	c_label.text = "Camera"
	c_row.add_child(c_label)
	camera_option = OptionButton.new()
	for n in ExplorerController.CAMERA_MODE_NAMES:
		camera_option.add_item(n)
	camera_option.item_selected.connect(func(i: int) -> void: _world_call(&"set_camera_mode", [i]))
	c_row.add_child(camera_option)

	var grid := GridContainer.new()
	grid.columns = 2
	vb.add_child(grid)
	_add_toggle(grid, "walk_fly", "Walk / Fly (F)", &"toggle_walk_fly")
	_add_toggle(grid, "gravity", "Gravity Align (G)", &"toggle_gravity_alignment")
	_add_toggle(grid, "orbit", "Orbit / Surface (F7)", &"toggle_orbit_surface_view")
	_add_toggle(grid, "wireframe", "Wireframe (F2)", &"toggle_wireframe")
	_add_toggle(grid, "collision", "Collision (F3)", &"toggle_collision_debug")
	_add_toggle(grid, "lod", "LOD View (F4)", &"toggle_lod_heatmap")
	_add_toggle(grid, "map", "Map (M)", &"toggle_map")
	grid.add_child(_make_button("Next Landmark (F6)", "Teleport to the next landmark", func() -> void: _world_call(&"cycle_landmark")))
	grid.add_child(_make_button("Hangar Doors (H)", "Open / close the mothership hangar doors", func() -> void: _world_call(&"toggle_hangar_doors")))
	grid.add_child(_make_button("Cycle Destruction (K)", "Advance every destructible section one state", func() -> void: _world_call(&"cycle_destruction")))
	for ob in [["Debris Field", 20], ["Research Station", 21], ["Orbital Refinery", 22], ["Docking Hub", 23]]:
		var idx: int = ob[1]
		grid.add_child(_make_button(ob[0], "Teleport to " + ob[0], func() -> void: _world_call(&"teleport_to_landmark", [idx])))
	storm_label = Label.new()
	storm_label.name = "StormIndicator"
	storm_label.text = "Storm: 0%"
	storm_label.add_theme_font_size_override("font_size", 11)
	grid.add_child(storm_label)
	grid.add_child(_make_button("Cycle Camera (C)", "Next camera mode", func() -> void: _world_call(&"cycle_camera_mode")))

	grid.add_child(_make_button("Switch Faction", "Deploy to the other faction's hangar", func() -> void: _world_call(&"switch_to_other_faction")))
	grid.add_child(_make_button("Deploy (B)", "Choose a faction and spawn", func() -> void: _world_call(&"toggle_deploy")))
	grid.add_child(_make_button("Scoreboard (Tab)", "Show both 16-player rosters", func() -> void: _world_call(&"toggle_scoreboard")))
	network_button = _make_button("Host Multiplayer", "Host ENet on UDP port 24567 or disconnect", func() -> void: _world_call(&"toggle_network_host"))
	grid.add_child(network_button)
	grid.add_child(_make_button("Commander (O)", "Open the tactical console", func() -> void: _world_call(&"toggle_commander")))
	for entry in [["Turret (3) · 60", "turret"], ["Shield (4) · 50", "shield"], ["Supply (5) · 40", "supply"]]:
		var kind: String = entry[1]
		grid.add_child(_make_button(entry[0], "Deploy on the ground ahead", func() -> void: _world_call(&"request_buildable", [kind])))
	var join_row := HBoxContainer.new()
	vb.add_child(join_row)
	var address := LineEdit.new()
	address.placeholder_text = "Server address"
	address.text = "127.0.0.1"
	join_row.add_child(address)
	join_row.add_child(_make_button("Join ENet", "Connect on UDP port 24567", func() -> void:
		var result: Error = world.network_authority.join_server(address.text.strip_edges())
		if result != OK:
			status_label.text = "Join failed · " + error_string(result)))



	var quick_title := Label.new()
	quick_title.text = "Quick-Board Vehicles"
	vb.add_child(quick_title)
	var quick_grid := GridContainer.new()
	quick_grid.columns = 2
	vb.add_child(quick_grid)
	for entry in [
		["Helion Fighter [Hangar]", "helion_fighter_hangar"],
		["Cinder Fighter [Hangar]", "cinder_fighter_hangar"],
		["Helion Dropship", "helion_dropship_hangar"],
		["Cinder Dropship", "cinder_dropship_hangar"],
		["Helion Rover [Terminus]", "helion_rover_terminus"],
		["Cinder Rover [Refinery]", "cinder_rover_refinery"],
	]:
		var key: String = entry[1]
		quick_grid.add_child(_make_button(entry[0], "Board " + entry[0], func() -> void: _world_call(&"request_board_from_settings", [key])))
	var exit_button := _make_button("Exit Vehicle", "Return to the deck or ground", func() -> void:
		if world != null and not world.exit_vehicle() and world.get_active_vehicle() != null:
			toggle_settings())
	quick_grid.add_child(exit_button)


func _add_toggle(grid: GridContainer, key: String, label: String, method: StringName) -> void:
	var b: Button = _make_button(label, label, func() -> void: _world_call(method), true)
	b.custom_minimum_size = Vector2(150, 0)
	grid.add_child(b)
	toggle_buttons[key] = b


func _build_map_panel() -> void:
	map_panel = PanelContainer.new()
	map_panel.name = "MapPanel"
	map_panel.add_theme_stylebox_override("panel", _panel_style(0.92))
	map_panel.visible = false
	map_panel.set_anchors_preset(Control.PRESET_CENTER)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	map_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(map_panel)
	var vb := VBoxContainer.new()
	map_panel.add_child(vb)
	var title := Label.new()
	title.text = "VESPER-9 WORLD MAP   (click a pin to teleport)"
	title.add_theme_color_override("font_color", Color(1.0, 0.62, 0.3))
	vb.add_child(title)
	map_view = MapView.new()
	map_view.landmark_clicked.connect(func(i: int) -> void: _world_call(&"teleport_to_landmark", [i]))
	vb.add_child(map_view)
	var legend := HBoxContainer.new()
	vb.add_child(legend)
	for i in BIOME_NAMES.size():
		var sw := ColorRect.new()
		sw.color = BIOME_COLORS[i]
		sw.custom_minimum_size = Vector2(14, 14)
		legend.add_child(sw)
		var l := Label.new()
		l.text = BIOME_NAMES[i] + "  "
		l.add_theme_font_size_override("font_size", 11)
		legend.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_child(spacer)
	legend.add_child(_make_button("Orbit view", "Jump to the low orbit vantage", func() -> void: _world_call(&"teleport_to_landmark", [0])))
	legend.add_child(_make_button("Close", "M", func() -> void: toggle_map()))


# --- helpers -----------------------------------------------------------------------------------

func _regenerate_from_field() -> void:
	if world != null and not world.can_mutate_world():
		return
	var text: String = seed_edit.text.strip_edges()
	var new_seed: int = text.to_int() if text.is_valid_int() else hash(text)
	_world_call(&"regenerate_world", [new_seed])
	_map_built_seed = -1
	if map_panel.visible:
		_ensure_map_texture()


func _sync_settings(d: Dictionary) -> void:
	if network_button != null:
		network_button.text = "Host Multiplayer" if d.get("network", {}).get("mode", "OFFLINE") == "OFFLINE" else "Disconnect Multiplayer"
	var preset: String = d.get("quality", "HIGH")
	for i in quality_option.item_count:
		if quality_option.get_item_text(i) == preset:
			quality_option.select(i)
	camera_option.select(int(d.get("camera_mode_index", 0)))
	_set_toggle("walk_fly", d.get("move_mode", "") == "Walk")
	_set_toggle("gravity", d.get("gravity_alignment", true))
	_set_toggle("orbit", d.get("orbit_view", false))
	_set_toggle("wireframe", d.get("wireframe", false))
	_set_toggle("collision", d.get("collision_debug", false))
	_set_toggle("lod", d.get("lod_heatmap", false))
	_set_toggle("map", map_panel.visible)


func _set_toggle(key: String, value: bool) -> void:
	var b: Button = toggle_buttons.get(key)
	if b != null:
		b.set_pressed_no_signal(value)


func refresh_map_pins() -> void:
	if world == null or map_view == null:
		return
	var mgr: Object = world.get("landmark_manager")
	if mgr == null:
		return
	map_view.pins.clear()
	for lm in mgr.landmarks:
		if lm.get("is_orbit", false):
			continue
		var angles: Vector2 = Transforms.unit_dir_to_lat_lon(lm["unit_dir"])
		map_view.pins.append({"index": lm["index"], "name": lm["name"], "lat": rad_to_deg(angles.x), "lon": rad_to_deg(angles.y)})
	map_view.queue_redraw()


func _ensure_map_texture() -> void:
	if world == null:
		return
	var cfg: WorldConfig = world.get("world_config")
	var planet: PlanetGenerator = world.get("planet")
	if cfg == null or planet == null or (map_view.map_texture != null and _map_built_seed == cfg.world_seed):
		return
	_map_built_seed = cfg.world_seed
	var w := 180
	var h := 120
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var elevation := PackedFloat32Array()
	var biomes := PackedByteArray()
	elevation.resize(w * h)
	biomes.resize(w * h)
	for y in h:
		var lat := lerpf(MAP_LAT_RANGE.y, MAP_LAT_RANGE.x, (float(y) + 0.5) / float(h))
		for x in w:
			var lon := lerpf(MAP_LON_RANGE.x, MAP_LON_RANGE.y, (float(x) + 0.5) / float(w))
			var dir := Transforms.lat_lon_to_unit_dir(deg_to_rad(lat), deg_to_rad(lon))
			elevation[y * w + x] = planet.get_surface_radius(dir) - cfg.planet_radius
			biomes[y * w + x] = clampi(planet.get_biome_id_at(dir), 0, BIOME_COLORS.size() - 1)
	for y in h:
		for x in w:
			var index := y * w + x
			var east := elevation[y * w + mini(x + 1, w - 1)]
			var south := elevation[mini(y + 1, h - 1) * w + x]
			var height := elevation[index]
			var tint := BIOME_COLORS[biomes[index]].lerp(Color("#283f53"), 0.32)
			var relief := (height - east + height - south) / 195.0 + height / 2500.0
			tint = tint.lightened(clampf(relief, 0.0, 0.34)) if relief > 0.0 else tint.darkened(clampf(-relief, 0.0, 0.42))
			if floori(height / 95.0) != floori(east / 95.0) or floori(height / 95.0) != floori(south / 95.0):
				tint = tint.lerp(Color("#b5ccd6"), 0.15)
			img.set_pixel(x, y, tint)
	map_view.map_texture = ImageTexture.create_from_image(img)
	map_view.queue_redraw()


func _format_diagnostics(d: Dictionary) -> String:
	var lod_text: String = ""
	var lods: Dictionary = d.get("lod_counts", {})
	var keys: Array = lods.keys()
	keys.sort()
	for k in keys:
		lod_text += "L%s:%d " % [str(k), int(lods[k])]
	var pp: Vector3 = d.get("planet_pos", Vector3.ZERO)
	var rp: Vector3 = d.get("render_pos", Vector3.ZERO)
	var lines: PackedStringArray = [
		"FPS %.0f   frame %.2f ms   mem %.1f MB" % [d.get("fps", 0.0), d.get("frame_ms", 0.0), d.get("memory_mb", 0.0)],
		"Patches  total %d  visible %d  queued %d" % [d.get("total_patches", 0), d.get("visible_patches", 0), d.get("queued_builds", 0)],
		"LOD  %s" % lod_text,
		"Collision patches %d" % d.get("collision_patches", 0),
		"Planet pos  %.1f, %.1f, %.1f" % [pp.x, pp.y, pp.z],
		"Render pos  %.1f, %.1f, %.1f" % [rp.x, rp.y, rp.z],
		"Lat %.3f   Lon %.3f" % [d.get("lat_deg", 0.0), d.get("lon_deg", 0.0)],
		"Altitude %.1f m   AGL %.1f m" % [d.get("altitude", 0.0), d.get("height_above_ground", 0.0)],
		"Biome  %s" % d.get("biome", ""),
		"Origin shifts %d" % d.get("origin_shifts", 0),
		"Mode %s   Camera %s" % [d.get("move_mode", ""), d.get("camera_mode", "")],
		"Speed %.1f m/s   Gravity align %s" % [d.get("speed", 0.0), "ON" if d.get("gravity_alignment", true) else "OFF"],
		"Seed %d   Quality %s" % [d.get("seed", 0), d.get("quality", "")],
		"Landmark  %s" % d.get("landmark", ""),
	]
	var match_stats: Dictionary = d.get("match", {})
	if not match_stats.is_empty():
		lines.append("Match %s   Helion %.0f / Cinder %.0f   %.0fs" % [
			match_stats.match_state, match_stats.scores.helion, match_stats.scores.cinder, match_stats.match_time])
	var ai: Dictionary = d.get("ai", {})
	if not ai.is_empty():
		lines.append("AI %d infantry / %d fighters   Roster %dv%d" % [
			ai.troopers, ai.fighters, ai.roster_counts.helion, ai.roster_counts.cinder])
	var network: Dictionary = d.get("network", {})
	if not network.is_empty():
		lines.append("Network %s   Peers H:%d C:%d" % [
			network.mode, network.peer_counts.helion, network.peer_counts.cinder])
	var vehicle: Dictionary = d.get("vehicle", {})
	if not vehicle.is_empty():
		var guns: Dictionary = vehicle.weapons
		lines.append("%s  %s   Hull %.0f   Shield %.0f   Boost %.0f%%" % [
			vehicle.name, vehicle.regime, vehicle.health, vehicle.shield, vehicle.boost * 100.0])
		lines.append("Heat %.0f%%   Missiles %d/%d   Shots %d   Hits %d" % [
			guns.heat * 100.0, guns.missiles, guns.max_missiles, guns.shots_fired, guns.hits_registered])
	var st: Dictionary = d.get("streaming", {})
	if not st.is_empty():
		lines.append("Streaming  active %d  ready %d  loading %d  unloaded %d  retiring %d" % [st["active_regions"], st["ready_regions"], st["loading_regions"], st["unloaded_regions"], st["retiring_regions"]])
		lines.append("Residency %.0f / %.0f MB   transitions %d   LOD tier %d" % [st["residency_mb"], st["budget_mb"], st["transitions_count"], st["lod_tier"]])
	lines.append("Destruction  %s" % d.get("destruction", ""))
	var au: Dictionary = d.get("audio", {})
	if not au.is_empty():
		lines.append("Audio vacuum attenuation %.2f   zones playing %d" % [au["vacuum_attenuation"], au["playing"]])
	var orb: Dictionary = d.get("orbital", {})
	if not orb.is_empty():
		lines.append("Orbital structures %d (+debris field)" % orb["structures"])
	var wx: Dictionary = d.get("weather", {})
	if not wx.is_empty():
		lines.append("Storm intensity %.0f%%" % (float(wx["storm_intensity"]) * 100.0))
	return "\n".join(lines)
