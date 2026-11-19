## Sequential parts shop. Main pauses play while this picker is open.
extends Control

const BUILD_ORDER := ["reactor", "engine", "bridge", "keel", "port", "thruster", "battery", "coolant", "scrubber", "stores", "cargo", "antenna"]
const FAMILIES := ["kestrel", "lancer", "hauler", "halo", "bulwark"]
const CYAN := Color("#00a8b5")
const BLUE := Color("#0284c7")
const ORANGE := Color("#ff8c00")
const COST_INK := Color("#914600")
const INK := Color("#0f172a")
const MUTED := Color("#334155")
const SURFACE := Color("#f8fafc")
const INSET := Color("#e2e8f0")
const EDGE := Color("#cbd5e1")
const ShopPreview := preload("res://scripts/shop_preview.gd")


class ComparisonGraph extends Control:
	const METRICS := {
		"mass_kg": ["Dry mass", "%+.0f kg", 1.0],
		"fuel_kg": ["Propellant capacity", "%+.0f kg", 1.0],
		"thrust_kn": ["Thrust", "%+.1f kN", 1.0],
		"gen_kw": ["Power generation", "%+.1f kW", 1.0],
		"load_kw": ["Power draw", "%+.2f kW", 1.0],
		"battery_kwh": ["Battery capacity", "%+.1f kWh", 1.0],
		"exhaust_mult": ["Exhaust velocity", "%+.1f m/s", 0.0],
		"cargo_flags": ["Cargo capacity", "%+.0f flags", 1.0],
		"armor": ["Damage taken (armor)", "%+.0f%%", 100.0],
		"handling": ["Handling", "%+.0f%%", 100.0],
		"scan_mult": ["Scan speed", "%+.0f%%", 100.0],
		"radiator": ["Cooling", "%+.0f%%", 100.0],
		"life": ["Life support resilience", "%+.0f%%", 100.0],
		"turret_damage_mult": ["Turret output", "%+.0f%%", 100.0],
	}
	const GROUP_HEIGHT := 119
	const ROW_HEIGHT := 18
	const GAP := 18.0

	var _groups: Array[Dictionary] = []
	var _highlighted := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(_fit_groups)

	func set_slot(slot: String) -> void:
		var variants: Array[Dictionary] = []
		for family in FAMILIES:
			variants.append(ShipCatalog.variant(slot, family))
		_groups.clear()
		var baseline := ShipCatalog.loadout_stats({})
		for key in METRICS:
			var values: Array[float] = []
			var present := false
			var metric: Array = METRICS[key]
			var scale: float = baseline["exhaust"] if key == "exhaust_mult" else metric[2]
			for variant in variants:
				present = present or variant.has(key)
				values.append(float(variant.get(key, 0.0)) * scale)
			if present:
				_groups.append({"title": "Δ " + metric[0], "format": metric[1], "values": values})
		if variants.any(func(v): return v.has("fuel_kg") or v.has("exhaust_mult")):
			var values: Array[float] = []
			for family in FAMILIES:
				var candidate := {}
				candidate[slot] = family
				var stats := ShipCatalog.loadout_stats(candidate)
				values.append(float(stats["dv"]) - float(baseline["dv"]))
			_groups.append({"title": "Δ Delta-V (Kestrel baseline)", "format": "%+.1f m/s", "values": values})
		_fit_groups()

	func highlight(family: String) -> void:
		_highlighted = family
		queue_redraw()

	func _columns() -> int:
		return 2 if size.x >= 620.0 else 1

	func _fit_groups() -> void:
		custom_minimum_size.y = ceili(float(_groups.size()) / _columns()) * GROUP_HEIGHT
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var columns := _columns()
		var width := (size.x - GAP * (columns - 1)) / columns
		for index in _groups.size():
			var origin := Vector2((index % columns) * (width + GAP), floorf(float(index) / columns) * GROUP_HEIGHT)
			_draw_group(_groups[index], origin, width, font)

	func _draw_group(group: Dictionary, origin: Vector2, width: float, font: Font) -> void:
		var values: Array[float] = group["values"]
		var low := minf(0.0, values.min())
		var high := maxf(0.0, values.max())
		var span := maxf(high - low, 0.001)
		var label_width := 0.0
		for value in values:
			var caption: String = group["format"] % value
			label_width = maxf(label_width, font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
		var left := origin.x + 59.0 + (label_width + 6.0 if low < 0.0 else 0.0)
		var right := origin.x + width - label_width - 6.0
		var track := maxf(1.0, right - left)
		var zero := left + track * (-low / span)
		draw_string(font, origin + Vector2(0, 13), group["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)
		draw_line(Vector2(zero, origin.y + 20), Vector2(zero, origin.y + 109), EDGE)
		for index in FAMILIES.size():
			var family: String = FAMILIES[index]
			var color := INK if family == _highlighted else MUTED
			var bar_color := BLUE if family == _highlighted else Color("#64748b")
			var value := values[index]
			var end := zero + track * (value / span)
			var y := origin.y + 29 + index * ROW_HEIGHT
			draw_string(font, Vector2(origin.x, y + 4), ShipCatalog.FAMILIES[family]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
			draw_rect(Rect2(left, y - 3, track, 6), INSET)
			draw_rect(Rect2(minf(zero, end), y - 3, maxf(1.0, absf(end - zero)), 6), bar_color)
			var caption: String = group["format"] % value
			var caption_x := end + 6.0
			if value < 0.0:
				caption_x = end - 6.0 - font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2(caption_x, y + 4), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


var g
var draft: Dictionary = {}
var selected_slots: Dictionary = {}
var _modules: Dictionary = {}
var current_step_index := 0
var ship_container: Node3D
var preview_view: SubViewportContainer
var preview_camera: Camera3D
var _ghost: Node3D
var _hidden_module: Node3D
var _active_card: PanelContainer
var _step_host: Control
var _step_content: HBoxContainer
var _stage_caption: Label
var _progress_caption: Label
var _credits: Label
var _purchase_status: Label
var _purchase_button: Button
var _quick_build_button: Button
var _graph: ComparisonGraph
var _telemetry: Label
var _progress: ProgressBar
var _camera_home: Vector3
var _hull_size: Vector3
var _camera_tween: Tween
var _card_normal: StyleBoxFlat
var _card_hover: StyleBoxFlat
var _closing := false
var _can_render := false


func setup(main) -> void:
	g = main
	for slot in BUILD_ORDER:
		if g.sim.slot_confirmed(slot):
			draft[slot] = str(g.sim.loadout[slot])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_can_render = DisplayServer.get_name() != "headless"
	_setup_theme()
	_build_backdrop()

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	var outer := UI.vbox(12)
	margin.add_child(outer)
	var body := UI.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_stretch_ratio = 2.5
	outer.add_child(body)
	_build_stage(body)
	_build_right_column(body)

	_step_host = MarginContainer.new()
	_step_host.custom_minimum_size.y = 232
	for edge in ["left", "right", "top", "bottom"]:
		_step_host.add_theme_constant_override("margin_" + edge, 8)
	outer.add_child(_step_host)
	_show_step()
	_update_progress()


func _setup_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Inter", "SF Pro Display", "Segoe UI"])
	font.fallbacks = [UI.font()]
	theme = Theme.new()
	theme.default_font = font
	_card_normal = _box(SURFACE, EDGE, 10, 8)
	_card_hover = _box(SURFACE, CYAN, 10, 8)
	_card_hover.set_border_width_all(2)
	_card_hover.shadow_color = Color(CYAN, 0.42)
	_card_hover.shadow_size = 8


func _build_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color.WHITE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _panel(parent: Container) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(SURFACE, EDGE, 12, 12))
	parent.add_child(panel)
	var content := UI.vbox(5)
	panel.add_child(content)
	return content


func _build_right_column(parent: HBoxContainer) -> void:
	var column := UI.vbox(10)
	column.custom_minimum_size.x = 290
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var comparison := _panel(column)
	comparison.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	comparison.add_child(_label("ITEMS STATS", 15))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comparison.add_child(scroll)
	_graph = ComparisonGraph.new()
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_graph)

	var status := _panel(column)
	status.add_child(_label("CURRENT CRAFT STATUS", 15))
	_telemetry = _label("", 13, MUTED)
	status.add_child(_telemetry)
	_progress_caption = _label("", 13, MUTED)
	status.add_child(_progress_caption)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = BUILD_ORDER.size()
	_progress.custom_minimum_size.y = 7
	_progress.add_theme_stylebox_override("background", _box(INSET, EDGE, 4, 0))
	_progress.add_theme_stylebox_override("fill", _box(CYAN, CYAN, 4, 0))
	status.add_child(_progress)
	_credits = _label("", 14, COST_INK, true)
	status.add_child(_credits)
	_purchase_status = _label("", 12, MUTED, true)
	status.add_child(_purchase_status)
	_quick_build_button = _button("CONFIRM ALL 12 SLOTS (QUICK BUILD)", true, _quick_build)
	_quick_build_button.name = "QuickBuildButton"
	_quick_build_button.tooltip_text = "Fill every empty slot with the Kestrel blueprint and purchase in one click."
	_quick_build_button.custom_minimum_size.y = 42
	_quick_build_button.add_theme_font_size_override("font_size", 14)
	status.add_child(_quick_build_button)
	var actions := UI.hbox(8)
	status.add_child(actions)
	_purchase_button = _button("PURCHASE ALL", true, _purchase_all)
	_purchase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_purchase_button)
	actions.add_child(_button("CLOSE", false, close))


func _build_stage(parent: HBoxContainer) -> void:
	var stage_frame := PanelContainer.new()
	stage_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_frame.size_flags_stretch_ratio = 2.35
	stage_frame.add_theme_stylebox_override("panel", _box(SURFACE, EDGE, 12, 6))
	parent.add_child(stage_frame)
	var stage := UI.vbox(0)
	stage_frame.add_child(stage)
	var render := ShopPreview.create(stage, true)
	var root: Node3D = render["root"]
	preview_view = render["view"]
	preview_view.custom_minimum_size = Vector2(260, 220)
	var preview_frame := preview_view.get_parent() as PanelContainer
	preview_frame.add_theme_stylebox_override("panel", _box(SURFACE, EDGE, 8, 1))
	preview_camera = render["camera"]
	var viewport := preview_camera.get_viewport() as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if _can_render else SubViewport.UPDATE_DISABLED
	_camera_home = preview_camera.position
	ship_container = Node3D.new()
	ship_container.name = "ShipContainer"
	root.add_child(ship_container)

	# Measure a full baseline hull once. Module transforms remain in prefab space.
	var reference := ShipModel.full(UI.ACCENT)
	var bounds := _bounds(reference)
	reference.free()
	var factor := 4.0 / maxf(0.01, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	_hull_size = bounds.size * factor
	ship_container.scale = Vector3.ONE * factor
	ship_container.position = -bounds.get_center() * factor
	var grid := viewport.get_node_or_null("StageGrid") as Node3D
	if grid:
		grid.position.y = -bounds.size.y * factor * 0.5 - 0.18

	if not viewport.has_node("StageSpotlight"):
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, 5, 1)
		spot.rotation_degrees.x = -80.0
		spot.light_color = CYAN
		spot.light_energy = 2.0
		spot.spot_range = 12.0
		spot.spot_angle = 46.0
		viewport.add_child(spot)
	preview_view.resized.connect(_fit_camera)
	_fit_camera()
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_frame.add_child(overlay)
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = Vector2(10, 10)
	pill.add_theme_stylebox_override("panel", _box(SURFACE, EDGE, 12, 7))
	overlay.add_child(pill)
	_stage_caption = _label("", 13, MUTED)
	pill.add_child(_stage_caption)


func _fit_camera() -> void:
	var aspect := preview_view.size.x / maxf(1.0, preview_view.size.y)
	preview_camera.size = maxf(5.6, 5.0 / maxf(aspect, 0.1))


func _show_step() -> void:
	_step_content = UI.hbox(14)
	_step_host.add_child(_step_content)
	var slot: String = BUILD_ORDER[current_step_index]
	var previous := _button("◀", false, _step_by.bind(-1))
	previous.tooltip_text = "Previous slot"
	previous.disabled = current_step_index == 0
	previous.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_step_content.add_child(previous)
	var cards := UI.hbox(12)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_content.add_child(cards)
	for family in FAMILIES:
		_add_card(cards, slot, family)
	var next := _button("▶", false, _step_by.bind(1))
	next.tooltip_text = "Next slot"
	next.disabled = current_step_index == BUILD_ORDER.size() - 1
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_step_content.add_child(next)
	_graph.set_slot(slot)
	_graph.highlight(str(draft.get(slot, "")))
	_stage_caption.text = _stage_status()


func _add_card(parent: HBoxContainer, slot: String, family: String) -> void:
	var variant := ShipCatalog.variant(slot, family)
	# The HBox sizes the holder. The card can scale independently.
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_theme_stylebox_override("panel", _card_normal)
	card.set_meta("selected", selected_slots.get(slot) == family)
	holder.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.resized.connect(func() -> void: card.pivot_offset = card.size * 0.5)

	var details := UI.vbox(4)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(details)
	_add_thumbnail(details, slot, family)
	var heading := UI.hbox(4)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(heading)
	var title := _label(ShipCatalog.FAMILIES[family]["name"], 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var cost := PanelContainer.new()
	cost.add_theme_stylebox_override("panel", _box(Color("#fff0dc"), Color(ORANGE, 0.55), 6, 3))
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(cost)
	cost.add_child(_label("%d CR" % g.sim.variant_charge(slot, family), 12, COST_INK))
	details.add_child(_label(str(variant["advantage"]), 12, MUTED, true))
	details.add_child(_label("Δ MASS %+.0f kg" % float(variant.get("mass_kg", 0)), 11, MUTED))
	var select := _button("SELECT", true, _select_variant.bind(slot, family))
	details.add_child(select)
	card.tooltip_text = "%s\n%s" % [variant["name"], variant["drawback"]]
	if draft.get(slot) == family and not selected_slots.has(slot):
		card.tooltip_text += "\nOwned"
	select.tooltip_text = card.tooltip_text
	select.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_entered.connect(_set_candidate.bind(card, slot, family, true))
	card.mouse_exited.connect(_candidate_exit.bind(card, slot, family))
	select.mouse_entered.connect(_set_candidate.bind(card, slot, family, true))
	select.mouse_exited.connect(_candidate_exit.bind(card, slot, family))
	_style_card(card, false)
	holder.custom_minimum_size = card.get_combined_minimum_size()
	card.minimum_size_changed.connect(func() -> void: holder.custom_minimum_size = card.get_combined_minimum_size())


func _add_thumbnail(parent: VBoxContainer, slot: String, family: String) -> void:
	var frame := PanelContainer.new()
	frame.custom_minimum_size.y = 70
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _box(INSET, EDGE, 7, 2))
	parent.add_child(frame)
	if not _can_render:
		return
	var view := SubViewportContainer.new()
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(view)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	view.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = INSET
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#eef4fc")
	environment.environment.ambient_light_energy = 0.8
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 3.7
	camera.position = Vector3(0, 1.7, 5)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -32, 0)
	light.light_energy = 1.5
	viewport.add_child(light)
	var pivot := Node3D.new()
	pivot.rotation.y = 0.85
	viewport.add_child(pivot)
	var part := ShipModel.module(slot, family, UI.ACCENT)
	var bounds := _bounds(part)
	var factor := 3.1 / maxf(bounds.size.length(), 0.01)
	pivot.scale = Vector3.ONE * factor
	pivot.position = -(pivot.basis * bounds.get_center())
	pivot.add_child(part)


func _candidate_exit(card: PanelContainer, slot: String, family: String) -> void:
	# Moving onto the embedded button is still a hover within this card.
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == card or (hovered != null and card.is_ancestor_of(hovered)):
		return
	_set_candidate(card, slot, family, false)


func _set_candidate(card: PanelContainer, slot: String, family: String, active: bool) -> void:
	if _closing or not card.is_inside_tree() or slot != BUILD_ORDER[current_step_index]:
		return
	if active:
		if _active_card == card:
			return
		if is_instance_valid(_active_card):
			_style_card(_active_card, false)
		_active_card = card
		_style_card(card, true)
		_graph.highlight(family)
		_remove_ghost()
		if selected_slots.get(slot) == family:
			return
		if _modules.has(slot):
			_hidden_module = _modules[slot]
			_hidden_module.hide()
		_ghost = ShipModel.module(slot, family, UI.ACCENT)
		var hologram := StandardMaterial3D.new()
		hologram.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hologram.albedo_color = Color(CYAN, 0.38)
		hologram.emission_enabled = true
		hologram.emission = CYAN
		hologram.emission_energy_multiplier = 0.25
		_apply_hologram(_ghost, hologram)
		ship_container.add_child(_ghost)
	elif _active_card == card:
		_style_card(card, false)
		_active_card = null
		_remove_ghost()
		_graph.highlight(str(draft.get(slot, "")))


func _style_card(card: PanelContainer, active: bool) -> void:
	card.add_theme_stylebox_override("panel", _card_hover if active or card.get_meta("selected", false) else _card_normal)
	card.z_index = 1 if active else 0
	var previous: Tween = card.get_meta("hover_tween", null) if card.has_meta("hover_tween") else null
	if previous:
		previous.kill()
	if UI.reduced_motion:
		return
	card.pivot_offset = card.size * 0.5
	var tween := card.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	card.set_meta("hover_tween", tween)
	tween.tween_property(card, "scale", Vector2.ONE * (1.05 if active else 1.0), 0.13)


func _apply_hologram(node: Node, hologram: Material) -> void:
	if node is GeometryInstance3D:
		node.material_override = hologram
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_hologram(child, hologram)


func _remove_ghost() -> void:
	if is_instance_valid(_hidden_module):
		_hidden_module.show()
		_hidden_module = null
	if is_instance_valid(_ghost):
		ship_container.remove_child(_ghost)
		_ghost.queue_free()
		_ghost = null


func _select_variant(slot: String, family: String) -> void:
	if _closing or slot != BUILD_ORDER[current_step_index]:
		return
	_remove_ghost()
	draft[slot] = family
	selected_slots[slot] = family
	if _modules.has(slot):
		var previous: Node3D = _modules[slot]
		ship_container.remove_child(previous)
		previous.queue_free()
	var part := ShipModel.module(slot, family, UI.ACCENT)
	_modules[slot] = part
	ship_container.add_child(part)
	_install_effects(_bounds(part).get_center())

	var next_step := current_step_index
	for offset in range(1, BUILD_ORDER.size()):
		var index := (current_step_index + offset) % BUILD_ORDER.size()
		if not selected_slots.has(BUILD_ORDER[index]):
			next_step = index
			break
	_go_to_step(next_step)
	_update_progress()


func _step_by(delta: int) -> void:
	_go_to_step(clampi(current_step_index + delta, 0, BUILD_ORDER.size() - 1))


func _go_to_step(index: int) -> void:
	if _closing or index < 0 or index >= BUILD_ORDER.size():
		return
	_remove_ghost()
	_active_card = null
	current_step_index = index
	_step_host.remove_child(_step_content)
	_step_content.queue_free()
	_show_step()


func _draft_charge() -> int:
	var total := 0
	for slot in draft:
		total += int(g.sim.variant_charge(slot, draft[slot]))
	return total


func _purchase_all() -> void:
	if _closing:
		return
	_update_progress()
	if _purchase_button.disabled:
		return
	if not g.sim.purchase_loadout(draft):
		var message: String = g.sim.loadout_purchase_error(draft)
		if message.is_empty():
			message = "The draft could not be purchased."
		_show_purchase_status(message, true)
		g.sfx("ui_error", -6)
		g.hud.toast(message)
		return
	g.sfx("ui_buy", -6)
	g.world.refresh_ship_loadout()
	g._refresh_hud()
	g.hud.toast("Assembly complete")
	close()


## Fills every unselected slot (keeping existing picks / owned parts, else Kestrel) and
## purchases through the same path as PURCHASE ALL.
func _quick_build() -> void:
	if _closing:
		return
	for slot in BUILD_ORDER:
		if not selected_slots.has(slot):
			var family := str(draft.get(slot, "kestrel"))
			draft[slot] = family
			selected_slots[slot] = family
	_rebuild_modules()
	_update_progress()
	if _purchase_button.disabled:
		var shortfall: int = _draft_charge() - g.sim.credits
		var message := "Not enough credits for the full blueprint (short %d CR)." % shortfall
		_show_purchase_status(message, true)
		g.sfx("ui_error", -6)
		g.hud.toast(message)
		return
	_purchase_all()


func _rebuild_modules() -> void:
	_remove_ghost()
	for slot in BUILD_ORDER:
		if not draft.has(slot):
			continue
		var existing: Node3D = _modules.get(slot)
		if is_instance_valid(existing):
			if str(existing.get_meta("ship_family", "")) == str(draft[slot]):
				continue
			ship_container.remove_child(existing)
			existing.queue_free()
		var part := ShipModel.module(slot, draft[slot], UI.ACCENT)
		_modules[slot] = part
		ship_container.add_child(part)


func _install_effects(part_center: Vector3) -> void:
	if not _can_render or UI.reduced_motion:
		return
	# Sparkle uses ship-container coordinates; focus uses preview-root coordinates.
	var helpers: Object = ShopPreview
	if _accepts_call(helpers, &"spawn_install_sparkle", 2):
		helpers.call("spawn_install_sparkle", ship_container, part_center)
	else:
		_install_flash(part_center)
	if _accepts_call(helpers, &"focus_camera", 4):
		var root := ship_container.get_parent() as Node3D
		# The helper measures the visible subtree. Supply the full envelope for stable framing.
		var envelope := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = _hull_size
		envelope.mesh = box
		envelope.hide()
		root.add_child(envelope)
		helpers.call("focus_camera", preview_camera, root, preview_view, ship_container.transform * part_center)
		envelope.free()
	else:
		if _camera_tween:
			_camera_tween.kill()
		var offset := ship_container.to_global(part_center)
		var drift := Vector3(offset.x, offset.y, 0) * 0.20
		_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_camera_tween.tween_property(preview_camera, "position", _camera_home + drift, 0.22)
		_camera_tween.tween_property(preview_camera, "position", _camera_home, 0.55)


func _accepts_call(helpers: Object, method: StringName, count: int) -> bool:
	if not helpers.has_method(method):
		return false
	for info in (helpers as Script).get_script_method_list():
		if info["name"] == method:
			var total: int = info["args"].size()
			return count <= total and count >= total - info["default_args"].size()
	return false


func _install_flash(center: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 24
	sparks.lifetime = 0.46
	sparks.explosiveness = 1.0
	sparks.spread = 180.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 6.0
	sparks.scale_amount_min = 0.30
	sparks.scale_amount_max = 0.75
	sparks.local_coords = true
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CYAN
	mesh.material = material
	sparks.mesh = mesh
	sparks.position = center
	ship_container.add_child(sparks)
	sparks.finished.connect(sparks.queue_free)
	sparks.emitting = true


func _update_progress() -> void:
	var count := selected_slots.size()
	var total := _draft_charge()
	var shortfall: int = total - g.sim.credits
	_progress.value = count
	_progress_caption.text = "%d / %d selected" % [count, BUILD_ORDER.size()]
	_credits.text = "Draft %d CR / %d CR" % [total, g.sim.credits]
	_stage_caption.text = _stage_status()
	_purchase_button.disabled = count < BUILD_ORDER.size() or shortfall > 0
	var remaining := BUILD_ORDER.size() - count
	_quick_build_button.visible = remaining > 0
	_quick_build_button.text = (
		"CONFIRM ALL 12 SLOTS (QUICK BUILD)" if remaining == BUILD_ORDER.size()
		else "CONFIRM REMAINING %d SLOTS (QUICK BUILD)" % remaining
	)
	var status := ""
	if shortfall > 0:
		status = "Over budget by %d CR — adjust earlier picks" % shortfall
	_show_purchase_status(status, shortfall > 0)
	var stats := ShipCatalog.loadout_stats(draft)
	_telemetry.text = (
		"Wet Mass  %.1f kg\nThrust  %.1f kN\nDelta-V  %.1f m/s\n"
		+ "TWR  %.2f\nExhaust Vel  %.1f m/s\nPower Margin  %+.2f kW"
	) % [stats["wet_mass"], stats["thrust_kn"], stats["dv"], stats["twr"], stats["exhaust"], stats["power_margin"]]
	if draft.size() < BUILD_ORDER.size():
		_telemetry.text += "\nEmpty slots use Kestrel baseline stats."


func _show_purchase_status(message: String, warning: bool) -> void:
	_purchase_status.text = message
	_purchase_status.add_theme_color_override("font_color", COST_INK if warning else MUTED)
	_purchase_status.visible = not message.is_empty()


func _bay_status() -> String:
	return "%d / %d MODULES SELECTED" % [selected_slots.size(), BUILD_ORDER.size()]


func _stage_status() -> String:
	return "STEP %d / %d · %s · %s" % [
		current_step_index + 1, BUILD_ORDER.size(),
		BUILD_ORDER[current_step_index].to_upper(), _bay_status(),
	]


func _bounds(node: Node3D) -> AABB:
	var result := [null]
	Actor._aabb(node, Transform3D.IDENTITY, result)
	return result[0] if result[0] != null else AABB()


func _box(background: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style


func _label(caption: String, font_size: int, color := INK, wrapped := false) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrapped:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(caption: String, primary: bool, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 34
	button.add_theme_font_size_override("font_size", 13)
	var normal := ORANGE if primary else INSET
	var border := ORANGE.darkened(0.15) if primary else EDGE
	button.add_theme_stylebox_override("normal", _box(normal, border, 6, 7))
	button.add_theme_stylebox_override("hover", _box(normal.lightened(0.18), CYAN, 6, 7))
	button.add_theme_stylebox_override("pressed", _box(normal.darkened(0.15), CYAN, 6, 7))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, BLUE, 6, 7))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_stylebox_override("disabled", _box(INSET, EDGE, 6, 7))
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.pressed.connect(action)
	return button


func close() -> void:
	if _closing:
		return
	_closing = true
	g.picker = null
	g.pressed_now.clear()
	g.capture_mouse(true)
	hide()
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_Q]:
		get_viewport().set_input_as_handled()
		close()
