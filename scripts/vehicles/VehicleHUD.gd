class_name VehicleHUD
extends Control

const Fleet = preload("res://scripts/vehicles/VehicleManager.gd")
const Vehicle = preload("res://scripts/vehicles/VehicleBase.gd")
const INK := Color(0.91, 0.97, 1.0)
const MUTED := Color(0.63, 0.75, 0.82)
const PANEL := Color(0.025, 0.052, 0.072, 0.91)
const HOT := Color(1.0, 0.42, 0.23)
const FLIGHT_GUIDE := "[LMB] Guns   [RMB] Missiles   [Shift] Boost   [Q / Hold E] Roll   [X] Hover   [Z] Assist   [V] Cam   [Tap E] Exit"
const DRIVE_GUIDE := "[LMB] Guns   [RMB] Missiles   [Shift] Turbo   [Space] Brake   [V] Cam   [Tap E] Exit"

var _fleet: Fleet
var _explorer: Node3D
var _debug_ui: CanvasLayer
var _observed: Vehicle
var _nearby: Vehicle
var _hit_flash := 0.0
var _exit_notice := 0.0
var _accent := Color.CYAN
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func setup(fleet: Fleet, explorer: Node3D, debug_ui: CanvasLayer) -> void:
	_fleet = fleet
	_explorer = explorer
	_debug_ui = debug_ui
	_fleet.active_vehicle_changed.connect(_on_vehicle_changed)


func _on_vehicle_changed(vehicle: Vehicle) -> void:
	if is_instance_valid(_observed):
		_observed.hit_confirmed.disconnect(_on_hit)
		_observed.exit_refused.disconnect(_on_exit_refused)
	_observed = vehicle
	_hit_flash = 0.0
	_exit_notice = 0.0
	if vehicle != null:
		vehicle.hit_confirmed.connect(_on_hit)
		vehicle.exit_refused.connect(_on_exit_refused)
		_accent = vehicle.get_energy_color().lerp(Color.WHITE, 0.24)


func _on_hit() -> void:
	_hit_flash = 0.24


func _on_exit_refused() -> void:
	_exit_notice = 2.25


func _process(delta: float) -> void:
	if _fleet == null:
		return
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_exit_notice = maxf(0.0, _exit_notice - delta)
	_nearby = _fleet.find_nearest_parked(_explorer.get_planet_position()) if _observed == null else null
	queue_redraw()


func _draw() -> void:
	if _debug_ui == null or _debug_ui.is_any_panel_open():
		return
	if _observed == null:
		if is_instance_valid(_nearby):
			_message("[E] BOARD %s (%s)" % [_nearby.display_name.to_upper(), _nearby.faction.to_upper()],
				size.y * 0.70, _nearby.get_energy_color(), 19)
		return

	var vehicle := _observed
	var guns := vehicle.weapon_system.get_weapon_status()
	var reference := Vector2(960, 540)
	var scale_factor := minf(size.x / reference.x, size.y / reference.y)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	var viewport_size := size / scale_factor

	var left := Vector2(24, viewport_size.y - 144)
	var right := Vector2(viewport_size.x - 278, viewport_size.y - 144)
	_panel(Rect2(left, Vector2(254, 93)), _accent)
	_panel(Rect2(right, Vector2(254, 93)), _accent)
	_meter(left + Vector2(13, 19), "HULL", vehicle.health / vehicle.max_health, _accent)
	_meter(left + Vector2(13, 44), "SHIELD", vehicle.shield / maxf(vehicle.max_shield, 1.0), Color("74aefa"))
	_meter(left + Vector2(13, 69), "BOOST", vehicle.get_boost_ratio(), Color("ecce74"))
	_meter(right + Vector2(13, 19), "HEAT", guns.heat, HOT if guns.overheated else _accent)
	_text(right + Vector2(13, 50), "MISSILES", MUTED, 13)
	_text(right + Vector2(132, 50), "%d / %d" % [guns.missiles, guns.max_missiles], INK, 18)
	if guns.missiles == 0:
		_meter(right + Vector2(13, 69), "RELOAD", guns.reload_ratio, _accent)
	elif guns.overheated:
		_text(right + Vector2(13, 77), "GUNS COOLING", HOT, 13)

	var top := Vector2(viewport_size.x * 0.5 - 178.0, 56)
	_panel(Rect2(top, Vector2(356, 77)), _accent)
	_text(top + Vector2(14, 21), vehicle.display_name.to_upper(), MUTED, 13)
	_text(top + Vector2(14, 54), "%03.0f" % vehicle.get_speed(), INK, 29)
	_text(top + Vector2(70, 55), "m/s", MUTED, 13)
	_text(top + Vector2(120, 54), "%04.0f" % vehicle.get_altitude(), INK, 27)
	_text(top + Vector2(190, 55), "m ALT", MUTED, 13)
	var badge := Rect2(top + Vector2(236, 32), Vector2(108, 29))
	draw_rect(badge, Color(_accent, 0.13))
	draw_rect(badge, Color(_accent, 0.6), false)
	var regime := vehicle.get_flight_regime()
	_text(badge.position + Vector2((badge.size.x - _measure(regime, 12)) * 0.5, 19), regime, _accent, 12)

	var center := viewport_size * 0.5
	var aim_frame := vehicle.get_weapon_transform()
	var aim_at := aim_frame.origin - aim_frame.basis.z * 300.0
	var camera := vehicle.get_active_camera()
	var cross := center
	if not camera.is_position_behind(aim_at):
		var projected := camera.unproject_position(aim_at) / scale_factor
		cross = projected.clamp(viewport_size * Vector2(0.2, 0.3), viewport_size * Vector2(0.8, 0.7))
	_reticle(cross, vehicle.get_boost_ratio(), guns.overheated)
	draw_set_transform(Vector2.ZERO)
	var guide := DRIVE_GUIDE if vehicle.vehicle_type == "rover" else FLIGHT_GUIDE
	_message(guide, size.y - 24.0 * scale_factor, _accent, maxi(10, roundi(13.0 * scale_factor)))
	if _exit_notice > 0.0:
		_message("LAND AND SLOW DOWN TO EXIT", size.y * 0.70, HOT, 16)


func _reticle(center: Vector2, boost: float, overheated: bool) -> void:
	var gap := 6.0 + boost * 7.0
	var color := HOT if overheated else _accent
	draw_arc(center, 24.0 + boost * 8.0, -0.53, 0.53, 16, Color(color, 0.57), 1.2, true)
	draw_arc(center, 24.0 + boost * 8.0, PI - 0.53, PI + 0.53, 16, Color(color, 0.57), 1.2, true)
	draw_circle(center, 1.7, INK)
	for axis in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * gap, center + axis * (gap + 8.0), color, 1.7, true)
	if _hit_flash > 0.0:
		for diagonal in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(center + diagonal * 7.0, center + diagonal * 16.0,
				Color(INK, minf(_hit_flash * 7.0, 1.0)), 2.6, true)


func _meter(at: Vector2, label: String, value: float, color: Color) -> void:
	_text(at + Vector2(0, 4), label, MUTED, 12)
	var track := Rect2(at + Vector2(59, -5), Vector2(168, 9))
	draw_rect(track, Color("233643"))
	track.size.x *= clampf(value, 0.0, 1.0)
	draw_rect(track, color)


func _panel(rect: Rect2, color: Color) -> void:
	draw_rect(rect, PANEL)
	draw_rect(rect, Color(color, 0.38), false)
	draw_line(rect.position, rect.position + Vector2(26, 0), color, 2.2)


func _message(message: String, y: float, color: Color, font_size: int) -> void:
	var width := _measure(message, font_size)
	var at := Vector2((size.x - width) * 0.5, y - font_size)
	_panel(Rect2(at - Vector2(13, 7), Vector2(width + 26, font_size + 13)), color)
	_text(at + Vector2(0, font_size - 2), message, INK, font_size)


func _measure(value: String, font_size: int) -> float:
	return _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _text(value_at: Vector2, value: String, color: Color, font_size: int) -> void:
	draw_string(_font, value_at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
