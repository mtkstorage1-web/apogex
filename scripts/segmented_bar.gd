class_name SegmentedBar
extends Control
var value := 1.0:
	set(v):
		if value != v: value = v; queue_redraw()
var nominal := UI.GOOD
var segments := 12
func _draw() -> void:
	var width := (size.x - (segments - 1) * 2) / segments
	for i in segments:
		draw_style_box(UI.style(UI.ramp_color(value, nominal) if float(i) / segments < value else Color(1,1,1,0.10), Color.TRANSPARENT, 1, 0, 0), Rect2(i * (width + 2), 0, width, size.y))
