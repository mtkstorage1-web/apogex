## One crew member (or rival raider): animated model, name tag, carried item socket and simple kinematics.
class_name Actor
extends Node3D

const HEIGHT := 2.5
const TK_HAND_CLEARANCE := 0.2
const RIFLE_PATH := "res://assets/weapons/fpv_rifle/blaster-e.glb"
const RIFLE_GRIP := Vector3(-0.045, -0.02, 1.0)   # grip pivot in model space (model runs z 0..1.39, muzzle at z=0)
const RIFLE_MUZZLE := Vector3(-0.045, 0.03, 0.0)
const RIFLE_LEN := 1.39
const FPV_SCALE := 0.5
const FPV_REST := Vector3(0.20, -0.27, -0.45)
const FPV_FORE := Vector3(0.0, -0.062, -0.30)     # left-hand foregrip spot in rifle space
const FPV_MAG := Vector3(-0.045, -0.14, 0.745)    # magazine centre in model space
const FPV_FLASH_TIME := 0.075
const RIFLE_FINISH := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform bool scope = false;
uniform bool magazine = false;
varying vec3 part_position;
varying vec3 part_normal;

void vertex() {
	part_position = VERTEX;
	part_normal = NORMAL;
}

float band(float value, float start, float end, float pixel) {
	return smoothstep(start - pixel, start + pixel, value) * (1.0 - smoothstep(end - pixel, end + pixel, value));
}

void fragment() {
	vec3 point = part_position;
	vec3 axis = abs(normalize(part_normal));
	float polymer_swatch = 1.0 - step(0.28, UV.x);
	float steel_swatch = step(0.53, UV.x);
	float fore = (1.0 - smoothstep(0.16, 0.44, point.z)) * float(!scope && !magazine);
	float furniture = max(polymer_swatch * (1.0 - fore), float(magazine) * 0.82);
	float steel = max(steel_swatch * (1.0 - furniture), fore * 0.78);
	float brush_coord = (point.y + point.x * 0.52) * 630.0;
	float brush = (sin(brush_coord) * 0.65 + sin(brush_coord * 2.73 + point.z * 11.0) * 0.35)
		* (1.0 - smoothstep(0.4, 2.9, fwidth(brush_coord)));
	vec2 weave_uv = vec2(point.z + point.x * 0.63, point.y + point.x * 0.8) * 510.0;
	float weave = sin(weave_uv.x + weave_uv.y) * sin(weave_uv.x - weave_uv.y);
	weave *= 1.0 - smoothstep(0.45, 3.0, length(fwidth(weave_uv)));
	vec3 titanium = vec3(0.107, 0.133, 0.157) * (1.0 + brush * 0.19);
	vec3 polished = vec3(0.24, 0.28, 0.32) * (1.0 + brush * 0.10);
	vec3 carbon = vec3(0.029, 0.034, 0.041) * (1.0 + weave * 0.30);
	vec3 finish_color = mix(mix(titanium, polished, steel), carbon, furniture);
	float alloy = mix(mix(0.82, 0.94, steel), 0.06, furniture);
	float rough = mix(mix(0.28 + brush * 0.055, 0.21, steel), 0.77 + weave * 0.09, furniture);
	float side = smoothstep(0.55, 0.88, axis.x);
	float pixel_y = clamp(fwidth(point.y) * 0.55, 0.0004, 0.006);
	float pixel_z = max(fwidth(point.z) * 0.55, 0.0005);
	float rail = band(point.y, 0.029, 0.045, pixel_y) * side * float(!scope && !magazine);
	float cyan = rail * band(point.z, 0.18, 0.64, pixel_z);
	float amber = rail * band(point.z, 0.89, 1.06, pixel_z);
	float radius = length(point.xy - vec2(0.0, 0.07));
	float lens = (1.0 - smoothstep(0.022, 0.025, radius)) * smoothstep(0.22, 0.241, abs(point.z)) * axis.z * float(scope);
	float optic = lens * (0.16 + 0.84 * band(radius, 0.017, 0.022, max(fwidth(radius) * 0.5, 0.0003)));
	finish_color = mix(finish_color, vec3(0.012, 0.087, 0.116), lens);
	ALBEDO = OUTPUT_IS_SRGB ? pow(finish_color, vec3(1.0 / 2.2)) : finish_color;
	METALLIC = mix(alloy, 0.48, lens);
	ROUGHNESS = mix(rough, 0.10, lens);
	EMISSION = vec3(0.04, 0.86, 1.0) * (cyan * 2.4 + optic * 2.2) + vec3(1.0, 0.37, 0.038) * amber * 2.2;
}
"""

static var _rifle_materials: Array[ShaderMaterial] = []

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
	"work": ["Interact", "EVA_Repair_Panel", "Crane_Console_Operate", "Robot_Punch"],
	"scan": ["Interact", "Idle_Neutral", "Inspect", "EVA_Spacewalk_Reach", "Robot_Standing"],
	"celebrate": ["Wave", "Celebrate", "Robot_Dance"],
	"hit": ["HitRecieve", "HitRecieve_2", "HitReact", "Robot_No"],
	"jump": ["Jump", "Jump_Airborne", "Jump_Idle", "Robot_Jump"],
	"wave": ["Wave", "Robot_Wave"],
	"death": ["Death"],
}

static var _cache := {}


## Skeleton modifier: applies the telekinesis pose after animation each frame.
class TKModifier extends SkeletonModifier3D:
	var actor: Actor

	func _process_modification() -> void:
		if actor != null:
			actor._apply_tk_bones()
			actor._apply_weapon_pose()
			actor._update_team_gear()

var visual_height := HEIGHT
var role := 0
var color := Color.WHITE
var model: Node3D
var anim: AnimationPlayer
var animation_detail := true
var _pose_modifier: TKModifier
var anim_names := {}
var current := ""
var carry_socket: Node3D
const WorldLabels := preload("res://scripts/ui/world_labels.gd")
var name_tag: Label3D
var _nameplate_ink := Color.WHITE
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
var bone_head := -1
var weapon_pitch := 0.0
var grounding_offset := 0.0
var health_bar: Sprite3D
var displayed_hp := -1
var down_blend := 0.0
var stand_y := 0.0
var is_downed := false
var ground_feet: Array = []
var _fix_root_offset := false  # legacy .fbx robot only; the CC0 crew GLBs already stand at y=0
var step_clock := 0.0
var step_index := 0
var player_step_pending := false

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
		_fix_root_offset = true
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
			if bone_head < 0 and b_name.contains("head") and not b_name.contains("end") and not b_name.contains("top"):
				bone_head = b
			if b_name.contains("rightarm") or b_name.contains("upperarm_r") or b_name.contains("upperarm.r"):
				bone_right_arm = b
			elif b_name.contains("leftarm") or b_name.contains("upperarm_l") or b_name.contains("upperarm.l"):
				bone_left_arm = b
			elif b_name.contains("spine") or b_name == "torso":
				bone_spine = b
		_pose_modifier = TKModifier.new()
		_pose_modifier.name = "TKModifier"
		_pose_modifier.actor = self
		skeleton.add_child(_pose_modifier)

	carry_socket = Node3D.new()
	carry_socket.position = Vector3(0, HEIGHT + 0.7, 0)
	add_child(carry_socket)
	ring = Gfx.ring(0.95, 0.12, p_color, 0.7)
	ring.position.y = 0.04
	add_child(ring)
	if tag != "":
		_nameplate_ink = tag_color
		name_tag = Gfx.label(tag.to_upper(), tag_color, 20, 4)
		name_tag.font = UI.font()
		name_tag.add_to_group("crew_nameplates")
		name_tag.outline_modulate = UI.BG_DEEP
		name_tag.position.y = visual_height + 0.42
		name_tag.visibility_range_end = WorldLabels.NAME_RANGE
		name_tag.visibility_range_end_margin = 6.0
		name_tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(name_tag)
	stand_y = holder.position.y
	_holder_base_scale = holder.scale
	play("idle")
	return self


func _process(_dt: float) -> void:
	if not is_visible_in_tree() or name_tag == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := camera.global_position.distance_to(name_tag.global_position)
	var alpha := 1.0 - smoothstep(28.0, WorldLabels.NAME_RANGE, distance)
	if name_tag.visible and alpha > 0.0:
		WorldLabels.clamp_billboard(name_tag, camera, WorldLabels.NAME_MAX_PIXELS, 0.010)
	var ink_alpha := 0.0 if name_tag.get_meta("overlaps_label", false) else alpha
	name_tag.modulate = Color(_nameplate_ink, ink_alpha)
	name_tag.outline_modulate = Color(UI.BG_DEEP, ink_alpha)
	if health_bar != null:
		var pixels := WorldLabels.pixels_per_meter(camera, health_bar.global_position)
		var viewport_scale := maxf(1.0, get_viewport().get_stretch_transform().get_scale().y)
		var world_scale := absf(health_bar.global_basis.get_scale().x)
		health_bar.pixel_size = minf(0.010, 70.0 / maxf(1.0, pixels * 84.0 * viewport_scale * world_scale))
		health_bar.modulate.a = alpha


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


## Keep distant combatants moving without evaluating their skeletal poses every frame.
func set_animation_detail(enabled: bool) -> void:
	if animation_detail == enabled:
		return
	animation_detail = enabled
	if anim != null:
		anim.active = enabled
	if _pose_modifier != null:
		_pose_modifier.active = enabled


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
	if held_weapon: held_weapon.visible = weapon_blend > 0.02 and not _fpv_active
	if holstered_weapon: holstered_weapon.visible = weapon_blend < 0.02 and not _fpv_active
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
## `_path` is kept for call-site compatibility; every crew member now carries the CC0 Blaster-E rifle.
func install_weapon(_path := RIFLE_PATH) -> void:
	if skeleton == null: return
	var hand := skeleton.find_bone("Hand.R")
	if hand < 0:
		hand = skeleton.find_bone("Middle1.R")
	if hand < 0: return
	hand_attachment = BoneAttachment3D.new()
	hand_attachment.name = "RightHandWeaponAttachment"
	hand_attachment.bone_idx = hand
	skeleton.add_child(hand_attachment)
	weapon_grip = Node3D.new()
	weapon_grip.name = "WeaponGrip"
	hand_attachment.add_child(weapon_grip)
	var unit := visual_height * 0.55 / RIFLE_LEN
	held_weapon = make_rifle(unit)
	held_weapon.position = Vector3(0, 0.03, 0)
	_weapon_rest_pos = held_weapon.position
	weapon_grip.add_child(held_weapon)
	weapon_muzzle = held_weapon.get_node("Muzzle")
	holstered_weapon = make_rifle(unit)
	holstered_weapon.name = "HolsteredWeapon"
	holstered_weapon.position = Vector3(0.32, visual_height * 0.58, 0.4)
	holstered_weapon.rotation_degrees = Vector3(80, 0, -15)
	add_child(holstered_weapon)
	held_weapon.visible = false


## Blaster-E wrapped so the origin is the pistol grip and the barrel points down -Z; "Muzzle" marks the tip.
static func make_rifle(unit_scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Rifle"
	var scene := load(RIFLE_PATH) as PackedScene
	if scene != null:
		var mdl: Node3D = scene.instantiate()
		mdl.name = "Model"
		mdl.position = -RIFLE_GRIP
		_finish_rifle(mdl)
		root.add_child(mdl)
	root.scale = Vector3.ONE * unit_scale
	var muz := Node3D.new()
	muz.name = "Muzzle"
	muz.position = RIFLE_MUZZLE - RIFLE_GRIP
	root.add_child(muz)
	return root


static func _finish_rifle(model_root: Node3D) -> void:
	if _rifle_materials.is_empty():
		var shader := Shader.new()
		shader.code = RIFLE_FINISH
		for part in ["receiver", "scope", "magazine"]:
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("scope", part == "scope")
			material.set_shader_parameter("magazine", part == "magazine")
			_rifle_materials.append(material)
	if model_root is MeshInstance3D:
		(model_root as MeshInstance3D).material_override = _rifle_materials[0]
	for part in model_root.find_children("*", "MeshInstance3D", true, false):
		(part as MeshInstance3D).material_override = _rifle_materials[1 if part.name == &"scope" else (2 if part.name == &"magazine" else 0)]


func set_weapon_drawn(value: bool) -> void:
	if held_weapon == null: return
	weapon_drawn = value

func weapon_ready() -> bool:
	return weapon_drawn and weapon_blend >= 0.98 and weapon_reload <= 0.0

func recoil_weapon() -> void:
	weapon_recoil = 0.11
	_fpv_shot_pending = true

func _apply_weapon_pose() -> void:
	if skeleton == null: return
	# Imported robot animations have a vertical root offset. Keep the lowest foot at the floor.
	if _fix_root_offset and down_blend <= 0.0 and not ground_feet.is_empty():
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


# ───────────────────────── FPV rifle + gloved hands ─────────────────────────
# Caller (planet_b) adds `build_fpv_rig()` under its camera-locked node, then calls `tick_fpv(dt, speed)` each
# frame and `set_fpv_active(on)` when the camera enters/leaves first person. The rig is in camera space (-Z forward).
var fpv_rig: Node3D
var _fpv_active := false
var _fpv_sway: Node3D
var _fpv_rifle: Node3D
var _fpv_left: Node3D
var _fpv_flash: Node3D
var _fpv_flash_light: OmniLight3D
var _fpv_mag_real: Node3D
var _fpv_mag_fresh: Node3D
var _fpv_mag_rest := Vector3.ZERO
var _fpv_sleeve_mats: Array = []
var _fpv_shot_pending := false
var _fpv_flash_t := 0.0
var _fpv_kick_z := 0.0
var _fpv_kick_v := 0.0
var _fpv_pitch := 0.0
var _fpv_pitch_v := 0.0
var _fpv_sprint := 0.0
var _fpv_phase := 0.0
var _fpv_time := 0.0
var _fpv_lock_done := false
var _team_color := Color.WHITE
var _team_mats: Dictionary = {}
var _team_gear: Node3D
var _gear_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D


static func _prim(mesh: Mesh, col: Color, pos: Vector3, rough := 0.7, metal := 0.1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _capsule(r: float, h: float, col: Color, pos: Vector3, axis: Vector3) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	var mi := _prim(cm, col, pos, 0.75, 0.05)
	mi.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	return mi


## Tactical EVA glove. `left` hand cups the foregrip from below; right hand wraps the pistol grip.
func _make_glove_hand(left: bool) -> Node3D:
	var hand := Node3D.new()
	hand.name = "LeftHand" if left else "RightHand"
	var glove := Color("#1b2227")
	var plate := Color("#2c3a42")
	if left:
		hand.add_child(_prim(_box(Vector3(0.07, 0.03, 0.085)), glove, Vector3.ZERO, 0.8, 0.05))
		for i in 4:
			hand.add_child(_capsule(0.0105, 0.05, glove, Vector3(0.042, 0.03, -0.03 + i * 0.02), Vector3.UP))
		hand.add_child(_capsule(0.012, 0.05, glove, Vector3(-0.043, 0.026, -0.03), Vector3(-0.3, 1.0, 0.2)))
		hand.add_child(_prim(_box(Vector3(0.05, 0.01, 0.06)), plate, Vector3(0.0, -0.019, 0.0), 0.5, 0.4))
	else:
		hand.add_child(_prim(_box(Vector3(0.03, 0.095, 0.07)), glove, Vector3.ZERO, 0.8, 0.05))
		for i in 3:
			hand.add_child(_capsule(0.0105, 0.05, glove, Vector3(-0.022, -0.004 - i * 0.022, -0.045), Vector3.RIGHT))
		hand.add_child(_capsule(0.0095, 0.05, glove, Vector3(-0.03, 0.044, -0.062), Vector3(0.0, 0.0, -1.0)))   # trigger finger
		hand.add_child(_capsule(0.012, 0.05, glove, Vector3(-0.058, 0.02, 0.012), Vector3(0.0, 0.0, 1.0)))     # thumb
		hand.add_child(_prim(_box(Vector3(0.012, 0.07, 0.03)), plate, Vector3(0.02, 0.0, -0.028), 0.5, 0.4))
	# Spacesuit forearm + dark cuff; runs back toward the camera and off the screen edge.
	var dir := Vector3(-0.35, -0.3, 0.85) if left else Vector3(0.5, -0.25, 0.8)
	dir = dir.normalized()
	var wrist := Vector3(0.0, -0.005, 0.055) if left else Vector3(0.03, -0.02, 0.05)
	var cuff_cyl := CylinderMesh.new()
	cuff_cyl.top_radius = 0.05
	cuff_cyl.bottom_radius = 0.05
	cuff_cyl.height = 0.045
	var cuff := _prim(cuff_cyl, Color("#38454d"), wrist + dir * 0.02, 0.45, 0.5)
	cuff.basis = Basis(Quaternion(Vector3.UP, dir))
	hand.add_child(cuff)
	var sleeve_cyl := CylinderMesh.new()
	sleeve_cyl.top_radius = 0.058
	sleeve_cyl.bottom_radius = 0.047
	sleeve_cyl.height = 0.6
	var sleeve := _prim(sleeve_cyl, Color("#dfe6e5"), wrist + dir * 0.34, 0.65, 0.05)
	sleeve.basis = Basis(Quaternion(Vector3.UP, dir))
	hand.add_child(sleeve)
	_fpv_sleeve_mats.append(sleeve.material_override)
	return hand


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func build_fpv_rig() -> Node3D:
	if is_instance_valid(fpv_rig):
		return fpv_rig
	fpv_rig = Node3D.new()
	fpv_rig.name = "FPVRig"
	_fpv_sleeve_mats.clear()
	_fpv_sway = Node3D.new()
	_fpv_sway.name = "Sway"
	_fpv_sway.position = FPV_REST
	fpv_rig.add_child(_fpv_sway)
	_fpv_rifle = make_rifle(FPV_SCALE)
	_fpv_sway.add_child(_fpv_rifle)
	var model := _fpv_rifle.get_node_or_null("Model")
	if model != null:
		_fpv_mag_real = model.find_child("magazine", true, false)
		if _fpv_mag_real != null:
			_fpv_mag_rest = _fpv_mag_real.position
			_fpv_mag_fresh = _fpv_mag_real.duplicate()
			_fpv_mag_fresh.name = "FreshMagazine"
			_fpv_mag_real.get_parent().add_child(_fpv_mag_fresh)
			_fpv_mag_fresh.visible = false
	var right := _make_glove_hand(false)
	right.position = Vector3(0.034, -0.047, 0.02)
	_fpv_sway.add_child(right)
	_fpv_left = _make_glove_hand(true)
	_fpv_left.position = FPV_FORE
	_fpv_sway.add_child(_fpv_left)
	# Muzzle flash: hot core + star burst + short light, parked at the barrel tip.
	_fpv_flash = Node3D.new()
	_fpv_flash.name = "MuzzleFlash"
	_fpv_flash.position = (RIFLE_MUZZLE - RIFLE_GRIP) * FPV_SCALE + Vector3(0, 0, -0.02)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.82, 0.4, 0.95)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.7, 0.25)
	fm.emission_energy_multiplier = 3.0
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var core := SphereMesh.new()
	core.radius = 0.035
	core.height = 0.07
	var core_mi := MeshInstance3D.new()
	core_mi.mesh = core
	core_mi.material_override = fm
	core_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fpv_flash.add_child(core_mi)
	for k in 3:
		var spike := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.2, 0.035)
		spike.mesh = q
		spike.material_override = fm
		spike.rotation.z = k * PI / 3.0
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fpv_flash.add_child(spike)
	_fpv_flash_light = OmniLight3D.new()
	_fpv_flash_light.name = "MuzzleLight"
	_fpv_flash_light.light_color = Color(1.0, 0.72, 0.35)
	_fpv_flash_light.omni_range = 7.5
	_fpv_flash_light.omni_attenuation = 1.45
	_fpv_flash_light.position = _fpv_flash.position
	_fpv_flash_light.hide()
	_fpv_sway.add_child(_fpv_flash_light)
	_fpv_flash.visible = false
	_fpv_sway.add_child(_fpv_flash)
	_tint_fpv_sleeves()
	return fpv_rig


func set_fpv_flash_color(color: Color) -> void:
	if is_instance_valid(_fpv_flash_light):
		_fpv_flash_light.light_color = color


## First-person mode: the 3rd-person body, stump arms, rifle and holster stop drawing (they still cast shadows).
func set_fpv_active(on: bool) -> void:
	_fpv_active = on
	if model != null:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if is_instance_valid(_team_gear):
		for mi in _team_gear.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if held_weapon: held_weapon.visible = not on and weapon_blend > 0.02
	if holstered_weapon: holstered_weapon.visible = not on and weapon_blend < 0.02
	if is_instance_valid(fpv_rig): fpv_rig.visible = on


func _m2g(p: Vector3) -> Vector3:
	return (p - RIFLE_GRIP) * FPV_SCALE


## Drives rifle + gloved hands: spring recoil, muzzle flash, sprint carry, and the staged reload.
func tick_fpv(dt: float, speed := 0.0) -> void:
	if not is_instance_valid(fpv_rig) or _fpv_sway == null:
		return
	dt = clampf(dt, 0.0, 0.05)
	_fpv_time += dt
	var reloading := weapon_reload > 0.0
	var p := clampf(1.0 - weapon_reload / 1.3, 0.0, 1.0) if reloading else 0.0
	var grounded := position.y <= 0.05
	var sprint_goal := 1.0 if (speed > 4.0 and grounded and not is_downed) else 0.0
	_fpv_sprint = move_toward(_fpv_sprint, sprint_goal * (0.0 if reloading else 1.0), dt * 5.0)
	var walk_amt := clampf(speed / 6.0, 0.0, 1.0) if grounded else 0.0
	_fpv_phase += dt * (3.0 + speed * 0.9) * walk_amt
	# Shot: backward kick + muzzle climb, then critically-damped spring recovery.
	if _fpv_shot_pending:
		_fpv_shot_pending = false
		_fpv_kick_v = minf(_fpv_kick_v + 1.7, 2.4)
		_fpv_pitch_v = minf(_fpv_pitch_v + 3.3, 4.6)
		_fpv_flash_t = FPV_FLASH_TIME
		_fpv_flash.rotation.z = randf() * TAU
		_fpv_flash.scale = Vector3.ONE * randf_range(0.8, 1.35)
	else:
		_fpv_flash_t = maxf(0.0, _fpv_flash_t - dt)
	_fpv_kick_v += (-170.0 * _fpv_kick_z - 19.0 * _fpv_kick_v) * dt
	_fpv_kick_z += _fpv_kick_v * dt
	_fpv_pitch_v += (-170.0 * _fpv_pitch - 19.0 * _fpv_pitch_v) * dt
	_fpv_pitch += _fpv_pitch_v * dt
	_fpv_flash.visible = _fpv_flash_t > 0.0
	_fpv_flash_light.visible = _fpv_flash.visible
	_fpv_flash_light.light_energy = 3.9 * pow(_fpv_flash_t / FPV_FLASH_TIME, 2.0)
	# Pose composition.
	var pos := FPV_REST
	var rot := Vector3.ZERO   # x pitch (+ muzzle up), y yaw (+ muzzle left), z roll (+ top left)
	var draw := 1.0 - smoothstep(0.0, 1.0, weapon_blend)
	pos += Vector3(0.12, -0.75, 0.0) * draw
	pos.y += sin(_fpv_time * 1.7) * 0.0025
	var bob := walk_amt * (1.0 - _fpv_sprint)
	pos += Vector3(sin(_fpv_phase) * 0.006, -absf(sin(_fpv_phase)) * 0.009, 0.0) * bob
	var s := _fpv_sprint
	pos += Vector3(-0.19, -0.13, 0.07) * s
	rot += Vector3(-0.22, 0.6, 0.5) * s
	pos += Vector3(sin(_fpv_phase) * 0.03, sin(_fpv_phase * 2.0) * 0.022, 0.0) * s
	rot += Vector3(sin(_fpv_phase * 2.0) * 0.03, sin(_fpv_phase) * 0.05, sin(_fpv_phase) * 0.06) * s
	pos.z += _fpv_kick_z
	rot.x += _fpv_pitch
	var left_pos := FPV_FORE
	var left_rot := Vector3.ZERO
	var real_vis := true
	var fresh_vis := false
	var real_off := Vector3.ZERO
	var real_rot := Vector3.ZERO
	var fresh_off := Vector3.ZERO
	if reloading:
		# Tilt the rifle so the magwell is exposed, then return to ready for the rack.
		var tilt := smoothstep(0.0, 0.12, p) * (1.0 - smoothstep(0.84, 1.0, p))
		rot += Vector3(0.2, 0.0, -0.55) * tilt
		pos += Vector3(-0.04, 0.05, 0.05) * tilt
		var well := FPV_MAG
		var below := Vector3(0, -0.075, 0)
		var mag_bottom := _m2g(well) + below
		var pouch_off := Vector3(-0.25, -1.1, 0.15)
		var pouch := _m2g(well + pouch_off) + below
		var rack := _m2g(Vector3(-0.045, 0.1, 1.12))
		if p < 0.12:
			left_pos = FPV_FORE.lerp(mag_bottom, smoothstep(0.0, 1.0, p / 0.12))
		elif p < 0.30:
			var u := smoothstep(0.0, 1.0, (p - 0.12) / 0.18)
			real_off = Vector3(0, -0.28 * u, 0)
			left_pos = mag_bottom + Vector3(0, -0.28 * u * FPV_SCALE, 0)
		elif p < 0.48:
			var tau := (p - 0.30) / 0.18
			real_off = Vector3(0, -0.28 - 3.0 * tau * tau, 0)
			real_rot = Vector3(tau * 1.4, 0.0, tau * 0.8)
			left_pos = (mag_bottom + Vector3(0, -0.28 * FPV_SCALE, 0)).lerp(pouch, smoothstep(0.0, 1.0, tau))
		elif p < 0.62:
			left_pos = pouch
		if p >= 0.48:
			real_vis = false
		if p >= 0.45 and p < 0.62:
			var rise := smoothstep(0.0, 1.0, (p - 0.45) / 0.17)
			fresh_vis = true
			fresh_off = pouch_off.lerp(Vector3(0, -0.45, 0), rise)
			left_pos = _m2g(well + fresh_off) + below
		elif p >= 0.62 and p < 0.84:
			fresh_vis = true
			var seat := smoothstep(0.0, 1.0, clampf((p - 0.62) / 0.14, 0.0, 1.0))
			seat *= seat
			fresh_off = Vector3(0, -0.45 * (1.0 - seat), 0)
			if p < 0.76:
				left_pos = _m2g(well + fresh_off) + below
			else:
				left_pos = _m2g(well) + below
		if p >= 0.76 and not _fpv_lock_done:
			_fpv_lock_done = true
			_fpv_pitch_v += 2.2
			_fpv_kick_v += 0.8
		if p >= 0.76 and p < 0.84:
			var r := smoothstep(0.0, 1.0, (p - 0.76) / 0.08)
			left_pos = _m2g(well) + below
			left_pos = left_pos.lerp(rack, r)
		elif p >= 0.84 and p < 0.90:
			var pull := smoothstep(0.0, 1.0, (p - 0.84) / 0.06)
			left_pos = rack + Vector3(0, 0, 0.07 * pull)
			pos.z += 0.012 * pull
		elif p >= 0.90:
			var back := smoothstep(0.0, 1.0, (p - 0.90) / 0.10)
			left_pos = (rack + Vector3(0, 0, 0.07)).lerp(FPV_FORE, back)
		left_rot.z = -0.3 * tilt
	else:
		_fpv_lock_done = false
	_fpv_sway.position = pos
	_fpv_sway.basis = Basis.from_euler(Vector3(rot.x, rot.y, rot.z))
	_fpv_left.position = left_pos
	_fpv_left.rotation = left_rot
	if _fpv_mag_real != null:
		_fpv_mag_real.visible = real_vis
		_fpv_mag_real.position = _fpv_mag_rest + real_off
		_fpv_mag_real.rotation = real_rot
		_fpv_mag_fresh.visible = fresh_vis
		_fpv_mag_fresh.position = _fpv_mag_rest + fresh_off


func _tint_fpv_sleeves() -> void:
	for m in _fpv_sleeve_mats:
		(m as StandardMaterial3D).albedo_color = Color("#e3e9e8").lerp(_team_color, 0.35 if _team_color != Color.WHITE else 0.0)


# ───────────────────────── Team suit tinting ─────────────────────────
## Boldly tint the suit (body armor, backpack, helmet trim, visor glow) to a team colour. Textures/lighting are
## kept (albedo is multiplied, emission is only a low base) so shading stays readable instead of going flat.
func apply_team_suit_color(col: Color, is_enemy: bool = false) -> void:
	_team_color = col
	# Bare-skin / face / hair materials are never tinted; only the outfit is.
	var keep := ["skin", "eye", "hair", "moustache", "earring", "gunner_brown"]
	if model != null:
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var mat := _team_material(mi, i)
				if mat == null:
					continue
				var base: Color = mat.get_meta("tk_base", Color.WHITE)
				var n := String(mat.resource_name).to_lower()
				var skip := false
				for kw in keep:
					if n.contains(kw):
						skip = true
				if skip:
					continue
				if n.contains("black") or n.contains("grey") or n.contains("gray") or n.contains("edges") or n.contains("webbing"):
					# Boots / trim: dark base with a crisp glowing team accent.
					mat.albedo_color = base.lerp(col.darkened(0.55), 0.6 if is_enemy else 0.35)
					mat.emission_enabled = true
					mat.emission = col
					mat.emission_energy_multiplier = 1.6 if is_enemy else 0.9
				else:
					# Outfit (jacket, vest, trousers, armour, shirt): bold team colour; keeps any albedo texture shading.
					mat.albedo_color = Color.WHITE.lerp(col, 0.9 if is_enemy else 0.7)
					mat.emission_enabled = true
					mat.emission = col.darkened(0.55)
					mat.emission_energy_multiplier = 0.7 if is_enemy else 0.35
	_ensure_team_gear()
	_gear_mat.albedo_color = col
	_gear_mat.emission = col
	_gear_mat.emission_energy_multiplier = 3.0 if is_enemy else 2.0
	_visor_mat.albedo_color = col
	_visor_mat.emission = col
	_visor_mat.emission_energy_multiplier = 3.2 if is_enemy else 2.4
	_tint_fpv_sleeves()
	set_ring_color(col)


func _team_material(mi: MeshInstance3D, surf: int) -> BaseMaterial3D:
	var cur := mi.get_surface_override_material(surf)
	if cur is BaseMaterial3D and cur.has_meta("tk_team"):
		return cur
	var src := mi.get_active_material(surf)
	if not (src is BaseMaterial3D):
		return null
	var mat: BaseMaterial3D = src.duplicate()
	mat.set_meta("tk_team", true)
	mat.set_meta("tk_base", (src as BaseMaterial3D).albedo_color)
	mi.set_surface_override_material(surf, mat)
	return mat


## Slim glowing team trim for rigged crew with no spacesuit: a chest band plus a thin halo over the head.
## No backpack / helmet / visor blocks, so the sleek character models stay visible.
func _ensure_team_gear() -> void:
	if is_instance_valid(_team_gear):
		return
	_team_gear = Node3D.new()
	_team_gear.name = "TeamGear"
	add_child(_team_gear)
	var k := visual_height / HEIGHT
	_gear_mat = StandardMaterial3D.new()
	_gear_mat.roughness = 0.35
	_gear_mat.emission_enabled = true
	_visor_mat = _gear_mat
	var band := MeshInstance3D.new()
	band.name = "ChestBand"
	var bm := TorusMesh.new()
	bm.inner_radius = 0.30 * k
	bm.outer_radius = 0.33 * k
	band.mesh = bm
	band.material_override = _gear_mat
	_team_gear.add_child(band)
	var halo := MeshInstance3D.new()
	halo.name = "HeadHalo"
	var hm := TorusMesh.new()
	hm.inner_radius = 0.20 * k
	hm.outer_radius = 0.23 * k
	halo.mesh = hm
	halo.material_override = _gear_mat
	_team_gear.add_child(halo)
	if _fpv_active:
		set_fpv_active(true)


func _update_team_gear() -> void:
	if not is_instance_valid(_team_gear) or skeleton == null or not is_inside_tree():
		return
	var k := visual_height / HEIGHT
	var xf := skeleton.global_transform
	var spine_w := xf * skeleton.get_bone_global_pose(bone_spine).origin if bone_spine >= 0 else global_position + Vector3.UP * visual_height * 0.5
	var head_w := xf * skeleton.get_bone_global_pose(bone_head).origin if bone_head >= 0 else spine_w + Vector3.UP * visual_height * 0.3
	var b := global_basis
	var chest := spine_w.lerp(head_w, 0.35)
	var band: Node3D = _team_gear.get_node("ChestBand")
	band.global_transform = Transform3D(b, chest)
	var halo: Node3D = _team_gear.get_node("HeadHalo")
	halo.global_transform = Transform3D(b, head_w + Vector3(0, 0.38 * k, 0))


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
	image.fill_rect(Rect2i(2, 2, maxi(0, roundi(float(hp) * 0.8)), 6), UI.ramp_color(float(hp) / 100.0))
	health_bar.texture = ImageTexture.create_from_image(image)


func poll_step(dt: float, speed: float) -> String:
	var player_step := player_step_pending
	player_step_pending = false
	if is_downed or position.y > 0.05 or speed <= 0.6:
		step_clock = 0.0
		return ""
	step_clock += dt * clampf(speed / 5.4, 0.75, 1.6)
	if step_clock >= 0.36:
		step_clock -= 0.36
		var clip := "step_%d" % (step_index % 4)
		step_index += 1
		if player_step:
			# The local player's footstep is played exactly once, here, and "" is returned so callers
			# (planet_b plays returned clips via sfx_3d) never double-fire it.
			_play_player_step(speed > 6.0)
			return ""
		return clip
	return ""


var _step_fallback: AudioStreamPlayer3D

## Player footsteps go through the AudioManager autoload; if it is missing (e.g. a scene run in isolation)
## a local AudioStreamPlayer3D plays the same synthesized walk/run clip instead.
func _play_player_step(running: bool) -> void:
	var id := "run" if running else "walk"
	var db := -7.0 if running else -10.0
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx"):
		am.play_sfx(id, db, 0.10)
		return
	var stream: AudioStream = SfxGen.build_all().get("sfx_" + id)
	if stream == null or not is_inside_tree():
		return
	if not is_instance_valid(_step_fallback):
		_step_fallback = AudioStreamPlayer3D.new()
		_step_fallback.name = "StepFallback"
		add_child(_step_fallback)
	_step_fallback.stream = stream
	_step_fallback.volume_db = db
	_step_fallback.pitch_scale = randf_range(0.9, 1.1)
	_step_fallback.play()


func set_ring_color(col: Color, alpha := 0.7) -> void:
	if is_instance_valid(ring):
		ring.material_override = Gfx.unshaded(col, alpha)
