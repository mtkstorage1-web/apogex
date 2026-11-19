class_name HudIcons
extends RefCounted

const NAMES := [
	"health", "ammo", "fuel", "power", "heat", "pressure", "co2", "radar",
	"objective", "flag", "crew", "credits", "warning", "ship", "cargo", "wrench",
	"hit_marker", "clock", "lock", "check", "ping", "comms", "planet", "evac",
	"fire", "battery", "delta", "mass", "armor", "turret", "handling",
]

static func line(c: CanvasItem, pts: Array, tint: Color, closed := false) -> void:
	var p := PackedVector2Array()
	for v in pts: p.append(Vector2(v[0], v[1]))
	if closed: p.append(p[0])
	c.draw_polyline(p, tint, 1.75, true)

static func polygon(c: CanvasItem, pts: Array, tint: Color) -> void:
	var p := PackedVector2Array()
	for v in pts: p.append(Vector2(v[0], v[1]))
	c.draw_colored_polygon(p, tint)

static func draw_icon(c: CanvasItem, id: String, px: float, tint: Color) -> void:
	c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * px / 24.0)
	match id:
		"health":
			c.draw_rect(Rect2(10,4,4,16), tint); c.draw_rect(Rect2(4,10,16,4), tint)
		"ammo":
			for x in [7,14]:
				c.draw_rect(Rect2(x,9,4,11), tint); polygon(c, [[x,9],[x+2,4],[x+4,9]], tint)
		"fuel": polygon(c, [[12,3],[18,13],[16,19],[8,19],[6,13]], tint); line(c, [[10,12],[9,16]], UI.TEXT)
		"power": polygon(c, [[14,2],[6,13],[12,13],[10,22],[18,11],[12,11]], tint)
		"heat":
			line(c, [[12,4],[12,15]], tint); c.draw_circle(Vector2(12,17.5),3.5,tint)
			for y in [5,9,13]: line(c, [[16,y],[19,y]], tint)
		"pressure": c.draw_arc(Vector2(12,13),8,PI*0.8,PI*2.2,24,tint,1.75,true); line(c, [[12,13],[17,8]], tint)
		"co2":
			line(c, [[8,14],[12,8],[16,14],[8,14]], tint)
			for p in [Vector2(8,14),Vector2(16,14),Vector2(12,8)]: c.draw_arc(p,3,0,TAU,20,tint,1.75,true)
		"radar", "ping":
			for r in [5,9]: c.draw_arc(Vector2(12,12),r,0,TAU,32,tint,1.75,true)
			c.draw_circle(Vector2(12,12),1.5,tint)
			if id == "radar": line(c, [[12,12],[19,6]], tint)
		"objective": line(c, [[12,3],[21,12],[12,21],[3,12]],tint,true); polygon(c, [[12,9],[15,12],[12,15],[9,12]],tint)
		"flag": line(c, [[6,3],[6,21]],tint); polygon(c, [[6,4],[19,7.5],[6,12]],tint)
		"crew": c.draw_arc(Vector2(12,8),4,0,TAU,24,tint,1.75,true); line(c, [[5,20],[7,14],[17,14],[19,20]],tint)
		"credits", "cargo":
			line(c, [[12,3],[20,7.5],[20,16.5],[12,21],[4,16.5],[4,7.5]],tint,true)
			if id == "credits": line(c, [[12,7],[12,17]],tint)
			else: line(c, [[4,7.5],[12,12],[20,7.5]],tint); line(c, [[12,12],[12,21]],tint)
		"warning": line(c, [[12,3],[22,20],[2,20]],tint,true); line(c, [[12,9],[12,14]],tint); c.draw_circle(Vector2(12,17.5),1,tint)
		"ship": line(c, [[12,3],[19,18],[12,15],[5,18]],tint,true); line(c, [[12,3],[12,15]],tint)
		"wrench": line(c, [[6,18],[15,9]],tint); c.draw_arc(Vector2(17,7),3.5,0.1,PI*1.5,20,tint,1.75,true)
		"hit_marker":
			for p in [[[5,5],[9,9]],[[19,5],[15,9]],[[5,19],[9,15]],[[19,19],[15,15]]]: line(c,p,tint)
		"clock": c.draw_arc(Vector2(12,12),9,0,TAU,32,tint,1.75,true); line(c, [[12,7],[12,12],[16,12]],tint)
		"lock": c.draw_arc(Vector2(12,9),4,PI,TAU,20,tint,1.75,true); c.draw_rect(Rect2(6,10,12,10),tint,false,1.75)
		"check": line(c, [[4,12.5],[9.5,18],[20,6.5]],tint)
		"comms":
			c.draw_circle(Vector2(6,18),2,tint)
			for r in [6,11]: c.draw_arc(Vector2(6,18),r,-PI/2,0,24,tint,1.75,true)
		"planet":
			c.draw_arc(Vector2(12,12),6,0,TAU,32,tint,1.75,true)
			line(c, [[2,15],[5,11],[19,7],[22,9],[19,13],[5,17],[2,15]],tint)
		"evac": line(c, [[6,6],[12,12],[6,18]],tint); line(c, [[13,6],[19,12],[13,18]],tint)
		"fire":
			line(c, [[12, 3], [16, 7], [16, 11], [19, 9], [20, 15],
				[18, 19], [14, 21], [10, 21], [6, 19], [4, 15], [6, 10],
				[9, 12], [11, 8]], tint, true)
			line(c, [[10, 20], [9, 17], [12, 13], [15, 17], [14, 20]], tint)
		"battery":
			line(c, [[3, 6], [18, 6], [18, 18], [3, 18]], tint, true)
			c.draw_rect(Rect2(19, 9, 3, 6), tint)
			for x in [6, 10, 14]:
				c.draw_rect(Rect2(x, 9, 2, 6), tint)
		"delta":
			line(c, [[12, 3], [21, 19], [12, 15], [3, 19]], tint, true)
			line(c, [[12, 15], [12, 20]], tint)
		"mass":
			c.draw_arc(Vector2(12, 7), 3, PI, TAU, 16, tint, 1.75, true)
			line(c, [[8, 7], [16, 7], [20, 17], [17, 20], [7, 20], [4, 17]], tint, true)
			line(c, [[9, 14], [15, 14]], tint)
		"armor":
			line(c, [[12, 3], [20, 6], [19, 14], [16, 18], [12, 21],
				[8, 18], [5, 14], [4, 6]], tint, true)
		"turret":
			c.draw_arc(Vector2(12, 12), 7, 0, TAU, 32, tint, 1.75, true)
			line(c, [[12, 2], [12, 8]], tint)
			line(c, [[12, 16], [12, 22]], tint)
			line(c, [[2, 12], [8, 12]], tint)
			line(c, [[16, 12], [22, 12]], tint)
			c.draw_circle(Vector2(12, 12), 1.25, tint, true, -1.0, true)
		"handling":
			c.draw_arc(Vector2(12, 12), 8.5, 0, TAU, 32, tint, 1.75, true)
			line(c, [[4, 10], [9, 10], [12, 13], [15, 10], [20, 10]], tint)
			line(c, [[12, 13], [12, 20]], tint)
			c.draw_circle(Vector2(12, 13), 1.65, tint, true, -1.0, true)
	c.draw_set_transform(Vector2.ZERO)
