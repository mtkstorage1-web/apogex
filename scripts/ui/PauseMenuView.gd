extends Control

const UI = preload("res://scripts/ui/UIThemeUtils.gd")

var _pause: VBoxContainer
var _settings: VBoxContainer
var _victory: VBoxContainer
var _debug_toggle: Button
var _winner: Label
var _final: Label
var _stats: Label
var _again: Button


func setup(frontend: CanvasLayer) -> void:
	UI.shade(self, [Color("#070d17aa"), Color("#08111bc9")], false)
	var center := CenterContainer.new()
	UI.full(self, center)
	var panel := UI.card(center, UI.STEEL.lightened(0.12), 25)
	panel.custom_minimum_size.x = 486
	var content := UI.column(panel, 12)
	UI.label(content, "APOGEX  /  VESPER-9", 14, UI.CYAN, 750)
	_pause = UI.column(content, 9)
	UI.label(_pause, "Match Paused", 43, UI.INK, 780)
	UI.line(_pause)
	UI.button(_pause, "RESUME", frontend.resume_gameplay, UI.CYAN, 54)
	UI.button(_pause, "CHANGE SPAWN / LOADOUT (B)", frontend.open_spawn_screen)
	UI.button(_pause, "SWITCH FACTION", frontend.switch_spawn_faction).name = "SwitchFaction"
	UI.button(_pause, "SETTINGS", frontend.toggle_settings)
	_debug_toggle = UI.button(_pause, "", frontend.toggle_dev_bar)
	UI.button(_pause, "RETURN TO MAIN MENU", frontend.open_main_menu)
	UI.button(_pause, "QUIT TO DESKTOP", get_tree().quit)

	_settings = UI.column(content)
	_victory = UI.column(content, 13)
	UI.label(_victory, "MATCH COMPLETE", 16, UI.MUTED, 750)
	_winner = UI.label(_victory, "", 43, UI.INK, 800)
	UI.line(_victory)
	_final = UI.label(_victory, "", 22, UI.INK, 700)
	_stats = UI.label(_victory, "", 17, UI.MUTED)
	_again = UI.button(_victory, "PLAY AGAIN", frontend.play_again, UI.CYAN, 53)
	UI.button(_victory, "RETURN TO LOBBY", frontend.open_lobby)


func refresh(frontend: CanvasLayer) -> void:
	var is_victory: bool = frontend.state == "VICTORY"
	var settings_open: bool = not is_victory and frontend.drawer == "settings"
	if settings_open and not _settings.visible:
		UI.label(_settings, "Settings", 38, UI.INK, 780)
		frontend.build_settings(_settings)
		UI.button(_settings, "← BACK", frontend.close_drawer)
	elif not settings_open and _settings.visible:
		for child in _settings.get_children():
			_settings.remove_child(child)
			child.queue_free()
	_settings.visible = settings_open
	_pause.visible = not is_victory and not settings_open
	_victory.visible = is_victory
	_debug_toggle.text = "DEV DEBUG BAR: " + ("ON" if frontend.dev_bar_enabled else "OFF")
	_pause.get_node("SwitchFaction").disabled = not frontend.world.can_mutate_world() and not frontend.client_ready()
	if is_victory:
		var match_summary: Dictionary = frontend.world.match_manager.get_match_summary()
		var winning_faction: String = match_summary.winner_faction
		var tint := UI.faction_color(winning_faction)
		_winner.text = winning_faction.to_upper() + " VICTORY"
		_winner.add_theme_color_override("font_color", tint)
		_final.text = "HELION  %d     /     %d  CINDER" % [match_summary.scores.helion, match_summary.scores.cinder]
		var stats: Dictionary = match_summary.player_stats
		_stats.text = "%d ELIMINATIONS   /   %d CAPTURES\n%.0f REPAIRED   /   %.0f EXTRACTED" % [stats.kills, stats.captures, stats.repairs, stats.extracted_resources]
		UI.emphasis(_again, tint)
