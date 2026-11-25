class_name TacticalCombatHUD
extends CanvasLayer

signal panel_visibility_changed

const Commander = preload("res://scripts/gameplay/CommanderSystem.gd")
const Engineering = preload("res://scripts/gameplay/EngineeringBuildManager.gd")
const Combat = preload("res://scripts/combat/PlayerCombatComponent.gd")
const INK := Color("#e5eef5")
const MUTED := Color("#9aafbe")
const BACKGROUND := Color("#08101ae6")
const FrontendTheme = preload("res://scripts/ui/UIThemeUtils.gd")

var world: Node
var deploy_panel: PanelContainer
var scoreboard_panel: PanelContainer
var _root: Control
var _soldier_panel: PanelContainer
var _match_bar: PanelContainer
var _event_panel: PanelContainer
var _feed: Label
var _clock: Label
var _reticle: Control
var _hitmarker: Label
var _tool: Label
var _deploy_faction: Label
var _deploy_message: Label
var _deploy_actions: Array[Button] = []
var _restart: Button
var _scores: Dictionary = {}
var _score_bars: Dictionary = {}
var _pills: Array[Label] = []
var _vitals: Dictionary = {}
var _team_headers: Dictionary = {}
var _rows: Dictionary = {}
var _refresh_wait := 0.0
var commander_panel: PanelContainer
var _resources: Label
var _bridge_prompt: PanelContainer
var _tactical_status: Label
var _build_status: Label
var _target: OptionButton
var _ability_controls := {}
var _build_controls := {}
var _build_panel: PanelContainer


func setup(p_world: Node) -> void:
	world = p_world
	_root = Control.new()
	_root.name = "CombatDisplay"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.game_feel.setup_vignette(_root)
	_build_match_bar()
	_build_soldier_panel()
	_build_feed()
	_build_deploy()
	_build_scoreboard()
	_build_field_controls()
	_refresh()


func has_open_panel() -> bool:
	return deploy_panel.visible or scoreboard_panel.visible or commander_panel.visible


func close_panels() -> void:
	_set_panel(false, false)


func toggle_deploy() -> void:
	_set_panel(not deploy_panel.visible, false)


func toggle_scoreboard() -> void:
	_set_panel(false, not scoreboard_panel.visible)


func toggle_commander() -> void:
	_set_panel(false, false, not commander_panel.visible)


func _set_panel(deploy: bool, scoreboard: bool, tactical: bool = false) -> void:
	if deploy_panel.visible == deploy and scoreboard_panel.visible == scoreboard and commander_panel.visible == tactical:
		return
	deploy_panel.visible = deploy
	scoreboard_panel.visible = scoreboard
	commander_panel.visible = tactical
	_deploy_message.text = ""
	_tactical_status.text = ""
	_refresh()
	panel_visibility_changed.emit()


func _process(delta: float) -> void:
	if world == null:
		return
	if not visible:
		return
	var on_foot: bool = not world.explorer.is_piloting
	_soldier_panel.visible = on_foot
	_match_bar.visible = on_foot
	_bridge_prompt.visible = not has_open_panel() and world.commander_system.near_holotable()
	_reticle.visible = on_foot and world.explorer.mouse_captured and not world.explorer.modal_open and world.explorer.camera_mode <= 1
	_hitmarker.visible = world.player_combat.hitmarker_time > 0.0
	_refresh_wait -= delta
	if _refresh_wait <= 0.0:
		_refresh_wait = 0.10
		_refresh()


func _build_match_bar() -> void:
	_match_bar = _panel("MatchBar", Vector2(0.5, 0), Vector2(-205, 17))
	var rows := _column(_match_bar, 5)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 12)
	rows.add_child(top)
	_build_team_gauge(top, "helion")
	_clock = _label("00:00", 16)
	_clock.custom_minimum_size.x = 104
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_clock)
	_build_team_gauge(top, "cinder")
	var objectives := HBoxContainer.new()
	objectives.alignment = BoxContainer.ALIGNMENT_CENTER
	objectives.add_theme_constant_override("separation", 8)
	rows.add_child(objectives)
	for tag in ["A", "B", "C"]:
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_theme_stylebox_override("panel", _style(Color("#142334"), 6, 6, 2))
		objectives.add_child(pill)
		var label := _label(tag, 12, Combat.faction_color("neutral"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = 81
		pill.add_child(label)
		_pills.append(label)


func _build_team_gauge(parent: HBoxContainer, faction: String) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	var color := Combat.faction_color(faction)
	var score := _label(faction.to_upper(), 14, color)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(score)
	_scores[faction] = score
	_score_bars[faction] = _bar(column, color, 126, 5)


func _build_soldier_panel() -> void:
	_soldier_panel = _panel("SoldierPanel", Vector2(0, 1), Vector2(20, -149))
	var rows := _column(_soldier_panel, 4)
	_tool = _label("", 13)
	_tool.custom_minimum_size.x = 237
	rows.add_child(_tool)
	for entry in [["Health", "health", Color("#f78884")], ["Shield", "shield", Color("#81cbfa")], ["Jetpack", "jetpack_fuel", Color("#f2c94c")]]:
		var line := HBoxContainer.new()
		rows.add_child(line)
		var label := _label(entry[0], 12, MUTED)
		label.custom_minimum_size.x = 70
		line.add_child(label)
		var meter := _bar(line, entry[2], 115, 6)
		var value := _label("", 12)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size.x = 44
		line.add_child(value)
		_vitals[entry[1]] = {"meter": meter, "label": value}
	rows.add_child(_label("B  Deploy     Tab  Scoreboard", 11, MUTED))
	_reticle = Control.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_reticle)
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	for rect in [Rect2(-9, -1, 6, 2), Rect2(3, -1, 6, 2), Rect2(-1, -9, 2, 6), Rect2(-1, 3, 2, 6)]:
		var mark := ColorRect.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.color = Color("#e5eef5d9")
		mark.position = rect.position
		mark.size = rect.size
		_reticle.add_child(mark)
	_hitmarker = _label("×", 28, Color("#fff1ab"))
	_hitmarker.position = Vector2(-9, -21)
	_reticle.add_child(_hitmarker)


func _build_feed() -> void:
	_event_panel = _panel("EventFeed", Vector2(1, 0), Vector2(-248, 17))
	_feed = _label("", 12)
	_feed.custom_minimum_size.x = 195
	_event_panel.add_child(_feed)


func _build_deploy() -> void:
	deploy_panel = _panel("DeployPanel", Vector2(0.5, 0.5), Vector2.ZERO, true)
	deploy_panel.hide()
	var rows := _column(deploy_panel, 8)
	rows.custom_minimum_size.x = 350
	rows.add_child(_label("Deploy", 23))
	_deploy_faction = _label("", 14, MUTED)
	rows.add_child(_deploy_faction)
	var factions := HBoxContainer.new()
	rows.add_child(factions)
	for faction in ["helion", "cinder"]:
		var button := _button(faction.capitalize(), func() -> void:
			if not world.switch_faction(faction):
				_deploy_message.text = "Faction is unavailable.")
		button.modulate = Combat.faction_color(faction).lerp(Color.WHITE, 0.42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		factions.add_child(button)
		_deploy_actions.append(button)
	for spawn in [["Mothership Hangar", "hangar"], ["Alpha  /  Extraction Spire", "alpha"],
		["Bravo  /  Mining Excavation", "bravo"], ["Charlie  /  Iron Refinery", "charlie"], ["Quick-Launch Fighter", "fighter"]]:
		var choice: String = spawn[1]
		var button := _button(spawn[0], func() -> void:
			if not world.deploy_player(choice):
				_deploy_message.text = "Spawn is unavailable.")
		rows.add_child(button)
		button.set_meta("host_only", choice == "fighter")
		_deploy_actions.append(button)
	_deploy_message = _label("", 12, MUTED)
	rows.add_child(_deploy_message)
	_restart = _button("Start next match", world.reset_combat_match)
	rows.add_child(_restart)
	rows.add_child(_button("Close  [B / Esc]", close_panels))


func _build_scoreboard() -> void:
	scoreboard_panel = _panel("ScoreboardPanel", Vector2(0.5, 0.5), Vector2.ZERO, true)
	scoreboard_panel.hide()
	var content := _column(scoreboard_panel, 7)
	content.add_child(_label("Scoreboard", 22))
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 15)
	content.add_child(teams)
	for faction in ["helion", "cinder"]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		column.custom_minimum_size.x = 258
		teams.add_child(column)
		var title := _label(faction.capitalize(), 17, Combat.faction_color(faction))
		column.add_child(title)
		_team_headers[faction] = title
		var headers := _scoreboard_row(column)
		headers[0].text = "Callsign"
		headers[1].text = "Role"
		headers[2].text = "K"
		headers[3].text = "D"
		var rows: Array = []
		for slot in 16:
			rows.append(_scoreboard_row(column))
		_rows[faction] = rows
	content.add_child(_button("Close  [Tab / Esc]", close_panels))


func _scoreboard_row(column: VBoxContainer) -> Array[Label]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	column.add_child(row)
	var cells: Array[Label] = []
	for width in [112, 69, 24, 24]:
		var label := _label("", 12, MUTED)
		label.custom_minimum_size.x = width
		row.add_child(label)
		cells.append(label)
	return cells


func _refresh() -> void:
	var summary: Dictionary = world.match_manager.get_match_summary()
	for faction in _scores:
		_scores[faction].text = "%s  %d" % [faction.to_upper(), int(summary.scores[faction])]
		_score_bars[faction].max_value = summary.target_score
		_score_bars[faction].value = summary.scores[faction]
	var seconds := int(summary.match_time)
	_clock.text = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
	if summary.match_state == "VICTORY":
		_clock.text = "%s WINS" % summary.winner_faction.to_upper()
	for i in mini(_pills.size(), summary.objectives.size()):
		var objective: Dictionary = summary.objectives[i]
		_pills[i].text = "%s  %s" % [objective.id.left(1).to_upper(), "CONTEST" if objective.contested else objective.owner_faction.to_upper()]
		_pills[i].add_theme_color_override("font_color", Combat.faction_color(objective.owner_faction))
	_feed.text = "\n".join(summary.killfeed)
	_event_panel.visible = not world.explorer.is_piloting and not summary.killfeed.is_empty()
	var combat: Dictionary = world.player_combat.get_combat_status()
	var available: float = summary.team_resources[combat.faction]
	_resources.text = "TEAM RESOURCES  %d" % int(available)
	var active: bool = summary.match_state == "ACTIVE" and combat.health > 0.0
	for kind in _build_controls:
		_build_controls[kind].disabled = not active or world.explorer.is_piloting or world.explorer.in_ship_interior or available < Engineering.COSTS[kind]
	_build_panel.visible = not has_open_panel() and not world.explorer.is_piloting and not world.explorer.in_ship_interior
	if commander_panel.visible:
		for ability in _ability_controls:
			var details: Dictionary = Commander.ABILITIES[ability]
			var wait: float = world.commander_system.ready_in(combat.faction, ability)
			_ability_controls[ability].disabled = not active or wait > 0.0 or available < details.cost or (_target.selected == 3 and ability != "supply")
			_ability_controls[ability].text = "%s   ·   %s" % [details.title, ("%ds" % ceili(wait)) if wait > 0.0 else ("%d resources" % int(details.cost) if details.cost > 0.0 else "12s cooldown")]

	_update_meter("health", combat.health, combat.max_health)
	_update_meter("shield", combat.shield, combat.max_shield)
	_update_meter("jetpack_fuel", combat.jetpack_fuel, combat.max_jetpack)
	_tool.text = "› [1] Rifle %02d/%02d   [2] Eng Tool" % [combat.ammo, combat.max_ammo] if combat.tool == 0 else "[1] Rifle   › [2] Engineering Tool"
	if deploy_panel.visible:
		var authority: bool = world.can_mutate_world()
		_deploy_faction.text = "Faction  /  " + summary.player_faction.capitalize()
		for button in _deploy_actions:
			button.disabled = not authority and button.get_meta("host_only", true)
		_restart.visible = authority and summary.match_state == "VICTORY"
	if scoreboard_panel.visible:
		var board: Dictionary = world.ai_manager.get_scoreboard()
		for faction in _rows:
			_team_headers[faction].text = "%s  ·  %d/16" % [faction.capitalize(), board[faction].size()]
			for i in _rows[faction].size():
				var entry: Dictionary = board[faction][i]
				var row: Array = _rows[faction][i]
				row[0].text = entry.callsign
				row[1].text = entry.role
				row[2].text = str(entry.kills)
				row[3].text = str(entry.deaths)


func _update_meter(key: String, current: float, maximum: float) -> void:
	_vitals[key].meter.max_value = maximum
	_vitals[key].meter.value = current
	_vitals[key].label.text = "%d" % ceili(current)


func _panel(label: String, anchor: Vector2, offset: Vector2, interactive: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = label
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	var frame := FrontendTheme.style(BACKGROUND, Color("#345263a0"), 9, 5)
	frame.content_margin_left = 13
	frame.content_margin_right = 13
	panel.add_theme_stylebox_override("panel", frame)
	_root.add_child(panel)
	panel.anchor_left = anchor.x
	panel.anchor_right = anchor.x
	panel.anchor_top = anchor.y
	panel.anchor_bottom = anchor.y
	panel.offset_left = offset.x
	panel.offset_right = offset.x
	panel.offset_top = offset.y
	panel.offset_bottom = offset.y
	if interactive:
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	return panel


func _column(panel: Container, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", separation)
	panel.add_child(column)
	return column


func _style(color: Color, radius: int, horizontal: int = 0, vertical: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style


func _label(value: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _bar(parent: Container, color: Color, width: int, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, height)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", _style(Color("#314456"), 3))
	bar.add_theme_stylebox_override("fill", _style(color, 3))
	parent.add_child(bar)
	return bar


func _button(title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 30
	button.add_theme_stylebox_override("normal", _style(Color("#1d3144"), 5, 9, 4))
	button.add_theme_stylebox_override("hover", _style(Color("#304d64"), 5, 9, 4))
	button.add_theme_stylebox_override("pressed", _style(Color("#41627b"), 5, 9, 4))
	button.add_theme_stylebox_override("disabled", _style(Color("#16212e"), 5, 9, 4))
	button.pressed.connect(action)
	return button


func _build_field_controls() -> void:
	_build_panel = _panel("FieldEngineering", Vector2(0.5, 1.0), Vector2(0, -105), true)
	var rows := _column(_build_panel, 4)
	_resources = _label("", 13, MUTED)
	_resources.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_resources)
	var hotbar := HBoxContainer.new()
	rows.add_child(hotbar)
	for entry in [["[3] Turret 60", "turret"], ["[4] Shield 50", "shield"], ["[5] Supply 40", "supply"]]:
		var kind: String = entry[1]
		var button := _button(entry[0], func() -> void:
			if not world.request_buildable(kind):
				_build_status.text = "Find clear ground within reach."
			else:
				_build_status.text = "")
		_build_controls[kind] = button
		hotbar.add_child(button)
	hotbar.add_child(_button("[O] Commander", world.toggle_commander))
	_build_status = _label("", 12, MUTED)
	_build_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_build_status)

	_bridge_prompt = _panel("BridgePrompt", Vector2(0.5, 0.65), Vector2(-132, 0))
	_bridge_prompt.add_child(_label("[O] Open Commander Tactical Console", 14))
	_bridge_prompt.hide()

	commander_panel = _panel("CommanderConsole", Vector2(0.5, 0.5), Vector2.ZERO, true)
	commander_panel.custom_minimum_size.x = 395.0
	var console := _column(commander_panel, 8)
	console.add_child(_label("Commander Tactical Console", 23))
	console.add_child(_label("Target", 13, MUTED))
	_target = OptionButton.new()
	for label in ["Alpha · Terminus Extraction Spire", "Bravo · Northern Mining Excavation", "Charlie · Eastern Iron Refinery", "Player beacon · current position"]:
		_target.add_item(label)
	_target.item_selected.connect(func(_index: int) -> void: _refresh())
	console.add_child(_target)
	for ability in Commander.ABILITIES:
		var id: String = ability
		var button := _button("", func() -> void:
			var target_id: String = ["alpha", "bravo", "charlie", "beacon"][_target.selected]
			_tactical_status.text = "Order submitted." if world.commander_system.request_local(id, target_id) else "Order unavailable at this target."
			_refresh())
		console.add_child(button)
		_ability_controls[id] = button
	_tactical_status = _label("", 13, MUTED)
	console.add_child(_tactical_status)
	console.add_child(_button("Close · Esc", close_panels))
	commander_panel.hide()
