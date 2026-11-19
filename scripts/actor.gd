## One crew member (or rival raider): animated model, name tag, carried item socket and simple kinematics.
class_name Actor
extends Node3D

const HEIGHT := 2.5
const TK_HAND_CLEARANCE := 0.2

enum CarryStyle { NONE, ONE_HAND, TWO_HAND, DRAG, TELEKINESIS }

const CARRY_THRESHOLDS := {
	"one_hand_max": 0.9,    
	"two_hand_max": 1.8,    
	"telekin_max": 3.5,     
}

# These names MUST match the animations inside your .glb / .fbx files.
const ANIMS := {
	"idle": ["Idle", "Robot_Idle"],
	"walk": ["Walk", "Robot_Walking"],
	"run": ["Run", "UAL_Jog_Fwd_Loop", "Robot_Running"],
	"work": ["EVA_Repair_Panel", "Crane_Console_Operate", "Robot_Punch"],
	"scan": ["Inspect", "EVA_Spacewalk_Reach", "Robot_Standing"],
	"celebrate": ["Celebrate", "Robot_Dance"],
	"hit": ["HitReact", "Robot_No"],
	"jump": ["Jump_Idle", "Jump", "Robot_Jump"],
	"wave": ["Wave", "Robot_Wave"],
}

static var _cache := {}


## Skeleton modifier: applies the telekinesis pose after animation each frame.
class TKModifier extends SkeletonModifier3D:
	var actor: Actor

	func _process_modification() -> void:
		if actor != null:
			actor._apply_tk_bones()
			actor._apply_weapon_pose()

var visual_height := HEIGHT
var role := 0
var color := Color.WHITE
var model: Node3D
var anim: AnimationPlayer
var anim_names := {}
var current := ""
var carry_socket: Node3D
var name_tag: Label3D
var ring: MeshInstance3D
var vel := Vector3.ZERO
var vy := 0.0
var heading := 0.0
var override_anim := ""
var override_time := 0.0
var bot_state := {}

var carry_style := CarryStyle.NONE
var telekinesis_enabled := true

# Bone tracking for procedural posing
var skeleton: Skeleton3D
var bone_right_arm := -1
var bone_left_arm := -1
var bone_spine := -1
var weapon_drawn := false
var weapon_blend := 0.0
var weapon_recoil := 0.0
var weapon_reload := 0.0
var weapon_grip: Node3D
var hand_attachment: BoneAttachment3D
var held_weapon: Node3D
var holstered_weapon: Node3D
var weapon_muzzle: Node3D
var weapon_pitch := 0.0
var grounding_offset := 0.0
var health_bar: Sprite3D
var displayed_hp := -1
var down_blend := 0.0
var stand_y := 0.0
var is_downed := false
var ground_feet: Array = []
var step_clock := 0.0
var step_index := 0

# Tactile movement feel
const SPRINT_LEAN_MAX := deg_to_rad(6.0)
const LAND_SETTLE_TIME := 0.14
const WEAPON_KICK_TIME := 0.10
var _lean := 0.0
var _land_t := 0.0
var _was_airborne := false
var _holder_base_scale := Vector3.ONE
var _weapon_rest_pos := Vector3.ZERO
var _kick_t := 0.0
var _kick_strength := 1.0

# Used for floating idle animations
var _tk_time := 0.0

# Cycle 8A: responsive movement + tactical dash
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.12
const DASH_TIME := 0.26
const DASH_COOLDOWN := 2.4
const DASH_SPEED := 17.0
const ACCEL := 46.0
const DECEL := 38.0
const BANK_MAX := deg_to_rad(5.0)
const DASH_LEAN := deg_to_rad(16.0)
var move_vel := Vector3.ZERO  # horizontal momentum owned by Main.drive()
var coyote_t := 0.0
var jump_buf_t := 0.0
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector3.ZERO
var _bank := 0.0
var _dash_lean := 0.0
var _breath := 0.0
var _prev_heading := 0.0
var _tk_hand := Vector3.ZERO  # palm position in actor space, updated by the pose modifier
var _tk_hand_valid := false
var _tk_radius := 0.0  # horizontal radius of the carried piece


func setup(model_path: String, p_role: int, p_color: Color, tag := "", tag_color := Color.WHITE) -> Actor:
	role = p_role
	color = p_color
	if not _cache.has(model_path):
		_cache[model_path] = load(model_path)
	var scene: PackedScene = _cache[model_path]
	model = scene.instantiate()
	var holder := Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	holder.add_child(model)
	
	# Normalise to crew height
	var acc := [null]
	_aabb(model, Transform3D.IDENTITY, acc)
	var box: AABB = acc[0] if acc[0] != null else AABB(Vector3.ZERO, Vector3.ONE * HEIGHT)
	var k := HEIGHT / maxf(0.1, box.size.y)
	if model_path.ends_with(".fbx"):
		k *= 0.5
		visual_height = HEIGHT * 0.5
	holder.scale = Vector3.ONE * k
	holder.position.y = -box.position.y * k
	holder.rotation.y = PI
	
	# Setup Animations
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		anim = aps[0]
		for n in anim.get_animation_list():
			var a := anim.get_animation(n)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
			anim_names[String(n).get_slice("|", String(n).get_slice_count("|") - 1)] = n
			
	# Find Skeleton for procedural posing
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		skeleton = sks[0]
		for b in skeleton.get_bone_count():
			var b_name = skeleton.get_bone_name(b).to_lower()
			if "foot" in b_name and not "toe" in b_name: ground_feet.append(b)
			if b_name.contains("rightarm") or b_name.contains("upperarm_r") or b_name.contains("upperarm.r"):
				bone_right_arm = b
			elif b_name.contains("leftarm") or b_name.contains("upperarm_l") or b_name.contains("upperarm.l"):
				bone_left_arm = b
			elif b_name.contains("spine") or b_name == "torso":
				bone_spine = b
		var tk_mod := TKModifier.new()
		tk_mod.name = "TKModifier"
		tk_mod.actor = self
		skeleton.add_child(tk_mod)

	carry_socket = Node3D.new()
	carry_socket.position = Vector3(0, HEIGHT + 0.7, 0)
	add_child(carry_socket)
	ring = Gfx.ring(0.95, 0.12, p_color, 0.7)
	ring.position.y = 0.04
	add_child(ring)
	if tag != "":
		name_tag = Gfx.label(tag, tag_color, 30)
		# Constant on-screen size: crisp and compact whether the teammate is near or far.
		name_tag.fixed_size = true
		name_tag.pixel_size = 0.0006
		name_tag.font_size = 28
		name_tag.outline_size = 6
		name_tag.position.y = visual_height + 0.55
		add_child(name_tag)
	stand_y = holder.position.y
	_holder_base_scale = holder.scale
	play("idle")
	return self


static func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_aabb(c, t, acc)


func play(state: String, speed := 1.0) -> void:
	if anim == null:
		return
	var key := state
	if key == current:
		anim.speed_scale = speed
		return
	for cand in ANIMS.get(state, [state]):
		if anim_names.has(cand):
			anim.play(anim_names[cand], 0.18)
			anim.speed_scale = speed
			current = key
			return


func flash(state: String, seconds := 0.8) -> void:
	override_anim = state
	override_time = seconds


func animate(dt: float, speed: float, working := "", _carrying := false) -> void:
	is_downed = working == "down"
	down_blend = move_toward(down_blend, 1.0 if is_downed else 0.0, dt * 3.2)
	var body_holder: Node3D = get_node("Holder")
	body_holder.rotation.z = smoothstep(0.0, 1.0, down_blend) * 1.45
	if down_blend > 0.0:
		body_holder.position.y = lerpf(stand_y, 0.7, down_blend)
	elif role != 1:
		body_holder.position.y = stand_y
	_update_tactile_feel(dt, speed, body_holder)
	_update_expressive(dt, speed, body_holder)
	if is_downed:
		set_weapon_drawn(false)
		working = "hit"
	if override_time > 0.0:
		override_time -= dt
		play(override_anim)
	else:
		if working != "":
			play(working)
		elif speed > 6.0:
			play("run", 1.1)
		elif speed > 0.4:
			play("walk", clampf(speed / 3.0, 0.7, 1.6))
		else:
			play("idle")
	
	weapon_blend = move_toward(weapon_blend, 1.0 if weapon_drawn else 0.0, dt * 2.8)
	weapon_recoil = move_toward(weapon_recoil, 0.0, dt * 5.0)
	weapon_reload = maxf(0.0, weapon_reload - dt)
	if held_weapon: held_weapon.visible = weapon_blend > 0.02
	if holstered_weapon: holstered_weapon.visible = weapon_blend < 0.02
	# Force the arm position procedurally if using Telekinesis
	if carry_style == CarryStyle.TELEKINESIS:
		_apply_procedural_tk_pose(dt)


## Sprint forward-lean, jump-land squash and weapon kickback. Pivots sit at the feet, so feet stay grounded.
func _update_tactile_feel(dt: float, speed: float, body_holder: Node3D) -> void:
	var airborne := position.y > 0.05
	if _was_airborne and not airborne and not is_downed:
		_land_t = LAND_SETTLE_TIME
		var world := get_parent()
		if world is Node3D and is_inside_tree():
			CombatFX.dust_puff(world as Node3D, global_position)
	_was_airborne = airborne
	var sprinting := speed > 4.0 and not airborne and not is_downed and down_blend <= 0.0
	var lean_target := SPRINT_LEAN_MAX * clampf((speed - 4.0) / 3.0, 0.0, 1.0) if sprinting else 0.0
	_lean = lerpf(_lean, lean_target, clampf(dt * 8.0, 0.0, 1.0))
	# The holder is yawed by PI, so a positive local X rotation pitches the body forward.
	body_holder.rotation.x = _lean + _dash_lean
	_land_t = maxf(0.0, _land_t - dt)
	var f := 0.0 if is_downed else smoothstep(0.0, 1.0, _land_t / LAND_SETTLE_TIME)
	body_holder.scale = _holder_base_scale * Vector3(1.0 + 0.04 * f, 1.0 - 0.08 * f, 1.0 + 0.04 * f)
	_kick_t = maxf(0.0, _kick_t - dt)
	if held_weapon:
		var k := smoothstep(0.0, 1.0, _kick_t / WEAPON_KICK_TIME) * _kick_strength
		held_weapon.position = _weapon_rest_pos + Vector3(0.0, 0.02, 0.14) * k


func dash_ready() -> bool:
	return dash_cd <= 0.0 and dash_t <= 0.0 and not is_downed


func dash_active() -> bool:
	return dash_t > 0.0


## Tactical boost-dash: 0.26s burst along world_dir (facing forward if zero), 2.4s cooldown.
## Main.drive() integrates the motion through the world's collide(), so blockers and bounds hold.
func trigger_dash(world_dir: Vector3) -> bool:
	if not dash_ready():
		return false
	var d := Vector3(world_dir.x, 0.0, world_dir.z)
	if d.length() < 0.01:
		d = Vector3(-sin(heading), 0.0, -cos(heading))
	dash_dir = d.normalized()
	dash_t = DASH_TIME
	dash_cd = DASH_COOLDOWN
	move_vel = dash_dir * DASH_SPEED
	heading = atan2(-dash_dir.x, -dash_dir.z)
	rotation.y = heading
	var world := get_parent()
	if world is Node3D and is_inside_tree():
		CombatFX.dust_puff(world as Node3D, global_position)
	return true


## Advances dash timers; call once per frame from the driver.
func tick_motion(dt: float) -> void:
	dash_t = maxf(0.0, dash_t - dt)
	dash_cd = maxf(0.0, dash_cd - dt)
	coyote_t = maxf(0.0, coyote_t - dt)
	jump_buf_t = maxf(0.0, jump_buf_t - dt)


## Idle breathing sway, turn banking roll and dash pose. All pivots sit at the feet (holder origin), so feet never lift.
func _update_expressive(dt: float, speed: float, body_holder: Node3D) -> void:
	var k := clampf(dt * 9.0, 0.0, 1.0)
	var live := not is_downed and down_blend <= 0.0
	var airborne := position.y > 0.05
	var dash_target := DASH_LEAN * smoothstep(0.0, 1.0, dash_t / DASH_TIME) if live else 0.0
	_dash_lean = lerpf(_dash_lean, dash_target, k)
	body_holder.rotation.x = _lean + _dash_lean
	# Banking: yaw rate scaled by speed, clamped to +-5 deg.
	var yaw_rate := angle_difference(_prev_heading, heading) / maxf(dt, 0.0001)
	_prev_heading = heading
	var bank_target := 0.0
	if live and speed > 1.5:
		bank_target = clampf(yaw_rate * 0.05, -1.0, 1.0) * BANK_MAX * clampf(speed / 6.0, 0.0, 1.0)
	_bank = lerpf(_bank, bank_target, k)
	# Breathing: tiny chest sway only when standing still; scale/roll about the feet pivot.
	var still := live and speed < 0.4 and not airborne
	_breath = lerpf(_breath, 1.0 if still else 0.0, clampf(dt * 4.0, 0.0, 1.0))
	if _breath > 0.001:
		_tk_time_breath(dt)
	var sway := sin(_breath_clock) * _breath
	body_holder.rotation.z = body_holder.rotation.z + _bank + sway * deg_to_rad(0.6)
	body_holder.rotation.x += sway * deg_to_rad(0.5)
	var s := body_holder.scale
	body_holder.scale = Vector3(s.x, s.y * (1.0 + 0.006 * sway), s.z)


var _breath_clock := 0.0
func _tk_time_breath(dt: float) -> void:
	_breath_clock = fmod(_breath_clock + dt * 2.1, TAU)


## Snappy 3D kickback of the held weapon visual; recovers over 0.10s. Rotation and bone attachment are untouched.
func trigger_weapon_kick(strength := 1.0) -> void:
	_kick_strength = clampf(strength, 0.0, 3.0)
	_kick_t = WEAPON_KICK_TIME


func face(dir: Vector3, dt: float, rate := 10.0) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	var target := atan2(-dir.x, -dir.z)
	heading = lerp_angle(heading, target, clampf(rate * dt, 0.0, 1.0))
	rotation.y = heading


func walk_to(target: Vector3, dt: float, speed := 4.5, stop := 0.3) -> float:
	var d := Vector3(target.x - position.x, 0, target.z - position.z)
	var dist := d.length()
	if dist > stop:
		var step := minf(dist - stop * 0.5, speed * dt)
		position += d.normalized() * step
		face(d, dt)
		vel = d.normalized() * speed
	else:
		vel = Vector3.ZERO
	return dist


func set_carry(node: Node3D) -> void:
	for c in carry_socket.get_children():
		c.queue_free()
	if node == null or !is_instance_valid(node) or node.is_queued_for_deletion():
		carry_style = CarryStyle.NONE
		_reset_carry_socket()
		return

	# Measure the object's local bounds safely
	var acc := [null]
	_aabb(node, Transform3D.IDENTITY, acc)
	var box: AABB = acc[0] if acc[0] != null else AABB(Vector3.ZERO, Vector3.ZERO)
	
	# Use 'scale' instead of 'global_transform.basis.get_scale()' to prevent tree errors.
	var node_scale: Vector3 = node.scale
	var safe_scale := Vector3(
		maxf(0.001, absf(node_scale.x)),
		maxf(0.001, absf(node_scale.y)),
		maxf(0.001, absf(node_scale.z))
	)
	var world_size := Vector3(
		box.size.x * safe_scale.x,
		box.size.y * safe_scale.y,
		box.size.z * safe_scale.z
	)
	var longest := maxf(world_size.x, maxf(world_size.y, world_size.z))

	carry_socket.add_child(node)
	_tk_radius = 0.5 * sqrt(box.size.x * box.size.x + box.size.z * box.size.z)

	if telekinesis_enabled and longest <= CARRY_THRESHOLDS.telekin_max:
		carry_style = CarryStyle.TELEKINESIS
		carry_socket.position = Vector3(0.55, HEIGHT * 0.75, -1.1)
	elif longest <= CARRY_THRESHOLDS.one_hand_max:
		carry_style = CarryStyle.ONE_HAND
		carry_socket.position = Vector3(0.35, HEIGHT * 0.55, -0.25)
	elif longest <= CARRY_THRESHOLDS.two_hand_max:
		carry_style = CarryStyle.TWO_HAND
		carry_socket.position = Vector3(0, HEIGHT * 0.6, -0.35)
	else:
		carry_style = CarryStyle.DRAG
		carry_socket.position = Vector3(0, 0, 0.6)
		carry_socket.rotation = Vector3(PI * 0.15, 0, 0)


func _reset_carry_socket() -> void:
	carry_socket.position = Vector3(0, HEIGHT + 0.7, 0)
	carry_socket.rotation = Vector3.ZERO


## Replaces the need for a custom animation by physically rotating the skeleton
## bones every frame to create the "Superhero Mind Control" pose.
func _apply_procedural_tk_pose(dt: float) -> void:
	if skeleton == null or bone_right_arm == -1:
		return
	
	_tk_time += dt

	# Float the object gently
	if carry_style == CarryStyle.TELEKINESIS:
		var base := Vector3(0.55, HEIGHT * 0.75, -1.1)
		if _tk_hand_valid:
			# Keep the piece's near face clear of the palm so hand and piece never overlap.
			base.x = _tk_hand.x
			base.z = minf(base.z, _tk_hand.z - TK_HAND_CLEARANCE - _tk_radius)
		carry_socket.position = base + Vector3(0, sin(_tk_time * 2.0) * 0.06, 0)
		carry_socket.rotation.y += dt * 0.6


## Runs after the AnimationPlayer (via TKModifier), so the animation cannot overwrite the pose.
func _apply_tk_bones() -> void:
	if skeleton == null or bone_right_arm == -1 or carry_style != CarryStyle.TELEKINESIS:
		return

	# 2. Right arm reaches forward, hand raised palm-out with fingers spread
	_aim_bone("UpperArm.R", "LowerArm.R", _tk_dir(Vector3(0.45, 0.1, -0.9)))
	_aim_bone("LowerArm.R", "", _tk_dir(Vector3(0.1, 0.3, -1.0)))
	# Fingers point up, spread sideways: thumb inward (-X), pinky outward (+X).
	var spread := {"Thumb": Vector3(-0.8, 0.6, -0.2), "Index": Vector3(-0.2, 1.0, -0.15),
		"Middle": Vector3(0.0, 1.0, -0.15), "Pinky": Vector3(0.3, 1.0, -0.15)}
	for f: String in spread:
		var d := _tk_dir(spread[f])
		for n in [1, 2, 3]:
			var bone_name := "%s%d.R" % [f, n]
			if skeleton.find_bone(bone_name) != -1:
				_aim_bone(bone_name, "%s%d.R" % [f, n + 1], d)
	var palm := skeleton.find_bone("Middle1.R")
	if palm != -1:
		_tk_hand = (global_transform.affine_inverse() * skeleton.global_transform) * skeleton.get_bone_global_pose(palm).origin
		_tk_hand_valid = true
	
	# 3. Add a slight lean back to the spine
	if bone_spine != -1:
		var s_rot := skeleton.get_bone_pose_rotation(bone_spine)
		var s_target := Quaternion.from_euler(Vector3(deg_to_rad(10), 0, 0))
		skeleton.set_bone_pose_rotation(bone_spine, s_rot.slerp(s_target, 0.3))


## Actor-local direction -> skeleton-local direction.
func _tk_dir(d: Vector3) -> Vector3:
	return (skeleton.global_transform.basis.inverse() * (global_transform.basis * d)).normalized()


## Rotate `bone` so its rest axis (toward `child`, or away from its parent if child is
## missing) points along `dir` (skeleton space).
func _aim_bone(bone_name: String, child_name: String, dir: Vector3, weight := 1.0) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone == -1:
		return
	var child := skeleton.find_bone(child_name) if child_name != "" else -1
	var rest_g := skeleton.get_bone_global_rest(bone)
	var rest_dir: Vector3
	if child != -1:
		rest_dir = (skeleton.get_bone_global_rest(child).origin - rest_g.origin).normalized()
	else:
		var par := skeleton.get_bone_parent(bone)
		if par == -1:
			return
		rest_dir = (rest_g.origin - skeleton.get_bone_global_rest(par).origin).normalized()
	if rest_dir.length() < 0.001:
		return
	var new_basis := Basis(Quaternion(rest_dir, dir)) * rest_g.basis
	var par_idx := skeleton.get_bone_parent(bone)
	var par_basis := skeleton.get_bone_global_pose(par_idx).basis.orthonormalized() if par_idx != -1 else Basis.IDENTITY
	var local := (par_basis.inverse() * new_basis).orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(local, weight))


## The firearm is a child of an actual hand bone, with a separate hip holster.
func install_weapon(path: String) -> void:
	if skeleton == null: return
	var hand := skeleton.find_bone("Middle1.R")
	if hand < 0: return
	hand_attachment = BoneAttachment3D.new()
	hand_attachment.name = "RightHandWeaponAttachment"
	hand_attachment.bone_idx = hand
	skeleton.add_child(hand_attachment)
	weapon_grip = Node3D.new()
	weapon_grip.name = "WeaponGrip"
	hand_attachment.add_child(weapon_grip)
	held_weapon = load(path).instantiate()
	var bounds := [null]
	_aabb(held_weapon, Transform3D.IDENTITY, bounds)
	var box: AABB = bounds[0]
	var scale_factor := maxf(1.2, visual_height * 0.8) / maxf(0.05, box.size.z)
	held_weapon.scale = Vector3.ONE * scale_factor
	held_weapon.rotation.y = 0.0
	held_weapon.position = Vector3(0, 0.06, -0.18)
	_weapon_rest_pos = held_weapon.position
	weapon_grip.add_child(held_weapon)
	weapon_muzzle = Node3D.new()
	weapon_muzzle.name = "Muzzle"
	weapon_muzzle.position = held_weapon.position + Vector3(0, box.get_center().y * scale_factor, box.position.z * scale_factor - 0.03)
	weapon_grip.add_child(weapon_muzzle)
	holstered_weapon = load(path).instantiate()
	holstered_weapon.name = "HolsteredWeapon"
	holstered_weapon.scale = Vector3.ONE * scale_factor
	holstered_weapon.position = Vector3(0.32, visual_height * 0.58, 0.4)
	holstered_weapon.rotation_degrees = Vector3(80, 0, -15)
	add_child(holstered_weapon)
	held_weapon.visible = false

func set_weapon_drawn(value: bool) -> void:
	if held_weapon == null: return
	weapon_drawn = value

func weapon_ready() -> bool:
	return weapon_drawn and weapon_blend >= 0.98 and weapon_reload <= 0.0

func recoil_weapon() -> void:
	weapon_recoil = 0.11

func _apply_weapon_pose() -> void:
	if skeleton == null: return
	# Imported robot animations have a vertical root offset. Keep the lowest foot at the floor.
	if role == 1 and down_blend <= 0.0 and not ground_feet.is_empty():
		var local_skeleton := _transform_from_actor(skeleton)
		var foot_y := INF
		for foot in ground_feet:
			foot_y = minf(foot_y, (local_skeleton * skeleton.get_bone_global_pose(foot).origin).y)
		if is_finite(foot_y):
			var holder: Node3D = get_node("Holder")
			var correction := clampf(0.06 - foot_y, -0.15, 0.15)
			holder.position.y += correction
			stand_y = holder.position.y
	if weapon_grip == null or not is_inside_tree(): return
	var blend := smoothstep(0.0, 1.0, weapon_blend)
	if blend > 0.0:
		_aim_bone("UpperArm.R", "LowerArm.R", _tk_dir(Vector3(0.15, -0.45, -0.65)), blend)
		_aim_bone("LowerArm.R", "Middle1.R", _tk_dir(Vector3(-0.08, 0.1 + weapon_pitch * 0.3, -1.0)), blend)
		_aim_bone("UpperArm.L", "LowerArm.L", _tk_dir(Vector3(-0.08, -0.4, -0.75)), blend)
		_aim_bone("LowerArm.L", "Middle1.L", _tk_dir(Vector3(0.4, 0.12, -0.9)), blend)
	var hand := hand_attachment.bone_idx
	var hand_pose := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	var aim := global_basis * Basis.from_euler(Vector3(weapon_pitch, 0, 0))
	var reload_tilt := sin(clampf(weapon_reload / 1.3, 0.0, 1.0) * PI) * 0.65
	weapon_grip.global_transform = Transform3D(aim * Basis.from_euler(Vector3(-reload_tilt - (1.0 - blend) * 0.8, 0, -reload_tilt * 0.5)), hand_pose.origin + aim * Vector3(0, -0.035, weapon_recoil))

func _transform_from_actor(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != self and parent is Node3D:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


func set_health(value: float, knocked := false) -> void:
	var hp := clampi(roundi(value), 0, 100)
	if health_bar == null:
		health_bar = Sprite3D.new()
		health_bar.name = "HealthBar"
		health_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		health_bar.pixel_size = 0.018
		health_bar.position.y = visual_height + 0.28
		health_bar.shaded = false
		add_child(health_bar)
	health_bar.position.y = 0.8 if knocked else visual_height + 0.28
	if displayed_hp == hp: return
	displayed_hp = hp
	var image := Image.create(84, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.02, 0.03, 0.04, 0.92))
	image.fill_rect(Rect2i(2, 2, maxi(0, roundi(float(hp) * 0.8)), 6), Color("#f26b62") if hp < 35 else Color("#8cdfba"))
	health_bar.texture = ImageTexture.create_from_image(image)


func poll_step(dt: float, speed: float) -> String:
	if is_downed or position.y > 0.05 or speed <= 0.6:
		step_clock = 0.0
		return ""
	step_clock += dt * clampf(speed / 5.4, 0.75, 1.6)
	if step_clock >= 0.36:
		step_clock -= 0.36
		var clip := "step_%d" % (step_index % 4)
		step_index += 1
		return clip
	return ""


func set_ring_color(col: Color, alpha := 0.7) -> void:
	if is_instance_valid(ring):
		ring.material_override = Gfx.unshaded(col, alpha)
