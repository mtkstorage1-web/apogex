## Physical boarding: a hinged belly ramp on the parked spacecraft.
##
## The ramp swings down from under the hull at the cabin airlock line. Crew walk up its deck
## with real floor physics (Main.drive() samples floor_at()), and reaching the hatch at the top
## carries them into the cabin airlock. All positions are in the parent (Universe) local frame.
class_name BoardingRamp
extends Node3D

const Interior = preload("res://scripts/ship_interior.gd")
## Hatch sill in the cabin frame (floor y = 0, port side = -X), under the hull belly on the airlock line.
const TOP_LOCAL := Vector3(-3.6, 0.0, -5.8)
const WIDTH := 1.9
const SLOPE := 0.37            # ~21 degrees: comfortable walking ramp
const MIN_RUN := 2.4
const MAX_RUN := 9.0
const STEP_UP := 0.55          # how far below the deck a walker can still step onto it
const LANDING := 0.9           # flat hatch landing beyond the hinge, under the belly
const APRON := 2.2             # clear approach in front of the foot
const DEPLOY_TIME := 1.1
const STOWED_ANGLE := 1.45     # folded up into the belly
const ENTER_AT := 0.93         # deck progress that counts as stepping through the hatch
const GLOW := Color("#59d8e8")
const DECK := Color("#3b434d")
const TREAD := Color("#6c7a86")
const WARN := Color("#f7ce59")

var deploy := 0.0              # 0 stowed, 1 fully deployed
var want := false
var top := Vector3.ZERO        # hinge point at the hatch sill
var foot := Vector3.ZERO       # point where the deck meets the ground
var axis := Vector3.RIGHT      # horizontal unit vector from the foot toward the hatch
var side := Vector3.FORWARD
var run := 4.5                 # horizontal length of the sloped deck
var _slope_len := 0.0
var _hinge: Node3D
var _deck_root: Node3D
var _deck: MeshInstance3D
var _rails: Array = []
var _treads: Array = []
var _light: OmniLight3D
var _label: Label3D
var _hatch: MeshInstance3D
var _t := 0.0


func _init() -> void:
	name = "BoardingRamp"
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	add_child(_hinge)
	_deck_root = Node3D.new()
	_deck_root.name = "DeckRoot"
	_hinge.add_child(_deck_root)
	_deck = Gfx.box(Vector3(1, 0.12, WIDTH), DECK)
	_deck.name = "Deck"
	_deck_root.add_child(_deck)
	for s in [-1.0, 1.0]:
		var rail := Gfx.box(Vector3(1, 0.06, 0.06), GLOW, Vector3.ZERO, 1.6)
		rail.name = "Rail%d" % int(s)
		rail.set_meta("side", s)
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_deck_root.add_child(rail)
		_rails.append(rail)
	for i in 7:
		var tread := Gfx.box(Vector3(0.08, 0.03, WIDTH * 0.86), TREAD if i % 2 == 0 else WARN)
		tread.name = "Tread%d" % i
		_deck_root.add_child(tread)
		_treads.append(tread)
	# Dark hatch opening in the belly with a glowing frame, plus a warm work light over the sill.
	_hatch = Gfx.box(Vector3(LANDING + 0.4, 0.04, WIDTH + 0.3), Color("#0d1116"))
	_hatch.name = "HatchOpening"
	_hatch.material_override = Gfx.unshaded(Color("#0d1116"))
	add_child(_hatch)
	_light = OmniLight3D.new()
	_light.name = "HatchLight"
	_light.light_color = Color("#ffd9a0")
	_light.light_energy = 1.6
	_light.omni_range = 6.5
	_light.shadow_enabled = false
	add_child(_light)
	_label = Gfx.label("BOARDING RAMP", GLOW, 40, 8)
	_label.name = "Label"
	add_child(_label)
	visible = false


## Pose of the ramp for a cabin frame (Interior's transform) and a ground sampler (xz -> y).
static func compute_pose(cabin: Transform3D, ground: Callable) -> Dictionary:
	var hinge := cabin * TOP_LOCAL
	var out := -cabin.basis.x
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.LEFT
	var r := MIN_RUN
	var g: float = ground.call(hinge + out * 4.0)
	for i in 3:
		r = clampf((hinge.y - g) / tan(SLOPE), MIN_RUN, MAX_RUN)
		g = ground.call(hinge + out * r)
	var f := hinge + out * r
	f.y = minf(g, hinge.y - 0.05)
	return {"top": hinge, "foot": f, "axis": -out, "run": r}


func sync(cabin: Transform3D, ground: Callable) -> void:
	var pose := compute_pose(cabin, ground)
	top = pose["top"]
	foot = pose["foot"]
	axis = pose["axis"]
	run = pose["run"]
	side = axis.cross(Vector3.UP).normalized()
	# Hinge frame: local +X points down the ramp (outward), +Y up, rotation about local Z swings it.
	var out := -axis
	var basis_out := Basis(out, Vector3.UP, out.cross(Vector3.UP))
	transform = Transform3D(basis_out, top)
	var slope_len := Vector2(run, top.y - foot.y).length()
	if absf(slope_len - _slope_len) > 0.03:
		_slope_len = slope_len
		_layout_deck()
	_hatch.position = Vector3(-LANDING * 0.5 + 0.1, 0.02, 0)
	_light.position = Vector3(-0.3, 1.6, 0)
	_label.position = Vector3(run + 0.4, 2.6 + (top.y - foot.y) * 0.2, 0)


func _layout_deck() -> void:
	(_deck.mesh as BoxMesh).size = Vector3(_slope_len + LANDING, 0.12, WIDTH)
	_deck.position = Vector3((_slope_len - LANDING) * 0.5, -0.06, 0)
	for rail: MeshInstance3D in _rails:
		(rail.mesh as BoxMesh).size = Vector3(_slope_len + LANDING, 0.06, 0.06)
		rail.position = Vector3((_slope_len - LANDING) * 0.5, 0.02, float(rail.get_meta("side")) * (WIDTH * 0.5 - 0.03))
	for i in _treads.size():
		_treads[i].position = Vector3(_slope_len * (i + 0.6) / (_treads.size() + 0.4), 0.02, 0)


func tick(dt: float, show_label: bool) -> void:
	_t += dt
	deploy = move_toward(deploy, 1.0 if want else 0.0, dt / DEPLOY_TIME)
	visible = want or deploy > 0.001
	var eased := deploy * deploy * (3.0 - 2.0 * deploy)
	var down := atan2(top.y - foot.y, run)
	# Rotation about local Z: positive lifts the outer end. Deployed = pointing down the slope.
	_hinge.rotation = Vector3(0, 0, lerpf(STOWED_ANGLE, -down, eased))
	_light.light_energy = 1.6 * eased
	_label.visible = show_label and is_deployed()
	_label.modulate.a = 0.75 + 0.25 * sin(_t * 3.0)


func is_deployed() -> bool:
	return visible and deploy >= 0.98


## Deck height under a point, or -INF when the point is off the ramp.
func floor_at(p: Vector3) -> float:
	if not is_deployed():
		return -INF
	var u := progress(p)
	if absf((p - foot).dot(side)) > WIDTH * 0.5 + 0.05 or u < 0.0 or u > 1.0 + LANDING / run:
		return -INF
	return lerpf(foot.y, top.y, clampf(u, 0.0, 1.0))


## 0 at the foot, 1 at the hatch sill (beyond 1 is the landing under the belly).
func progress(p: Vector3) -> float:
	return (p - foot).dot(axis) / maxf(run, 0.01)


## Walk-in lane: the deck plus a short apron in front of the foot, kept clear of hull blockers so
## crew can always reach the ramp even where the hull or wings overhang it.
func in_lane(p: Vector3) -> bool:
	if not is_deployed():
		return false
	var u := progress(p)
	return absf((p - foot).dot(side)) <= WIDTH * 0.5 + 0.2 and u >= -APRON / run and u <= 1.0 + LANDING / run


func on_deck(p: Vector3) -> bool:
	var f := floor_at(p)
	return f > -INF and p.y >= f - STEP_UP


## Keeps walkers below the deck (e.g. under the raised end) from passing through it sideways-in.
func block(p: Vector3) -> Vector3:
	if not is_deployed():
		return p
	var d := p - foot
	var lat := d.dot(side)
	var u := d.dot(axis) / maxf(run, 0.01)
	var half := WIDTH * 0.5 + 0.35
	if absf(lat) >= half or u < 0.0 or u > 1.0 + LANDING / run:
		return p
	if p.y >= lerpf(foot.y, top.y, clampf(u, 0.0, 1.0)) - STEP_UP:
		return p
	return p + side * ((half if lat >= 0.0 else -half) - lat)


## Where to stand to start boarding (just off the foot of the ramp).
func approach_point() -> Vector3:
	return foot - axis * 1.1


## Where crew step out of the hatch when leaving the ship.
func exit_point() -> Vector3:
	return top - axis * 1.0   # well below ENTER_AT so stepping out never re-boards
