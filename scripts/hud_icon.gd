class_name HudIcon
extends Control

var icon := "health"
var tint := UI.TEXT
var draw_count := 0

func _init(id := "health", color := UI.TEXT, px := 18.0) -> void:
	icon = id
	tint = color
	custom_minimum_size = Vector2.ONE * px
	mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_count += 1
	HudIcons.draw_icon(self, icon, minf(size.x, size.y), tint)
