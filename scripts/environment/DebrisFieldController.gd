class_name DebrisFieldController
extends Node3D
## Part 10.3 four-tier orbital debris field, fully deterministic from world_seed:
##   1 Large traversable wreckage (hull slabs, rocket stage hulks)  - StaticBody3D collision
##   2 Medium physical obstacles (broken satellites)                - StaticBody3D collision
##   3 Small decorative fragments (solar array bits + metal shards) - MultiMeshInstance3D, NO collision
##   4 Distant orbital dust / debris ring                           - MultiMeshInstance3D, NO collision

const LARGE_COUNT := 6
const MEDIUM_COUNT := 8
const SMALL := {"LOW": 120, "MEDIUM": 240, "HIGH": 400, "ULTRA": 600}
const DUST := {"LOW": 300, "MEDIUM": 600, "HIGH": 1000, "ULTRA": 1600}
const MAX_SMALL := 600
const MAX_DUST := 1600
const MAX_SHARDS := 600

var world_seed: int = 0
var center_planet: Vector3 = Vector3.ZERO
var field_radius: float = 420.0
var quality_preset: String = "HIGH"
var detail_active: bool = true
var current_origin: Vector3 = Vector3.ZERO
var large_pivot: Node3D
var medium_pivot: Node3D
var small_pivot: Node3D
var dust_pivot: Node3D
var solar_fragments: MultiMeshInstance3D
var metal_shards: MultiMeshInstance3D
var dust_ring: MultiMeshInstance3D
var _time: float = 0.0
var _large_bodies: Array[StaticBody3D] = []
var _signature: int = 0


func setup(p_seed: int, p_quality: String, p_center: Vector3, unit_dir: Vector3, p_radius: float) -> void:
	world_seed = p_seed
	center_planet = p_center
	field_radius = p_radius
	quality_preset = p_quality.to_upper()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_large_bodies.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "debris_field"]) & 0x7fffffff
	large_pivot = _pivot("LargeWreckage")
	medium_pivot = _pivot("MediumObstacles")
	small_pivot = _pivot("SmallFragments")
	dust_pivot = _pivot("DustRing")
	var sig: Array = []
	for i in LARGE_COUNT:
		var model: String = "hull_wreckage_slab" if i % 3 != 2 else "rocket_stage_hulk"
		var v: Node3D = OrbitalEnvironmentManager.build_visual(model, true)
		v.name = "Large%d_%s" % [i, model]
		v.position = _rand_in_sphere(rng, field_radius * 0.6)
		v.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		large_pivot.add_child(v)
		sig.append(v.position)
		var body: StaticBody3D = v.get_node_or_null("Collision") as StaticBody3D
		if body != null:
			_large_bodies.append(body)
	for i in MEDIUM_COUNT:
		var v2: Node3D = OrbitalEnvironmentManager.build_visual("broken_satellite", true)
		v2.name = "Medium%d_satellite" % i
		v2.position = _rand_in_sphere(rng, field_radius * 0.85)
		v2.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		medium_pivot.add_child(v2)
		sig.append(v2.position)
	_build_small(rng)
	_build_dust(rng)
	_signature = hash(sig)
	set_quality(quality_preset)


func _pivot(n: String) -> Node3D:
	var p := Node3D.new()
	p.name = n
	add_child(p)
	return p


func _rand_in_sphere(rng: RandomNumberGenerator, r: float) -> Vector3:
	var z: float = rng.randf_range(-1.0, 1.0)
	var a: float = rng.randf() * TAU
	var s: float = sqrt(1.0 - z * z)
	return Vector3(s * cos(a), z * 0.6, s * sin(a)) * r * pow(rng.randf(), 0.45)


func _mm_instance(name_: String, mesh: Mesh, count: int, color: Color, emissive: float = 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mat.metallic = 0.5
	if emissive > 0.0:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = mat
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = field_radius * 4.0
	return mmi


func _build_small(rng: RandomNumberGenerator) -> void:
	var panel := BoxMesh.new()
	panel.size = Vector3(12, 0.12, 5)
	solar_fragments = _mm_instance("SolarFragments", panel, MAX_SMALL, Color(0.08, 0.12, 0.24))
	var shard := BoxMesh.new()
	shard.size = Vector3(0.8, 0.12, 1.8)
	metal_shards = _mm_instance("MetalShards", shard, MAX_SHARDS, Color(0.45, 0.46, 0.5))
	for mmi in [solar_fragments, metal_shards]:
		var is_panel: bool = mmi == solar_fragments
		for i in MAX_SMALL:
			var s: float = rng.randf_range(0.08, 0.3) if is_panel else rng.randf_range(0.6, 2.2)
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3(s, s, s))
			(mmi as MultiMeshInstance3D).multimesh.set_instance_transform(i, Transform3D(b, _rand_in_sphere(rng, field_radius * 1.1)))
		small_pivot.add_child(mmi)


func _build_dust(rng: RandomNumberGenerator) -> void:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 4
	m.rings = 2
	dust_ring = _mm_instance("DustRingMesh", m, MAX_DUST, Color(0.55, 0.5, 0.45), 1.0)
	for i in MAX_DUST:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(field_radius * 2.2, field_radius * 3.6)
		var s: float = rng.randf_range(1.0, 4.0)
		var p := Vector3(cos(a) * r, rng.randfn(0.0, field_radius * 0.06), sin(a) * r)
		dust_ring.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), p))
	dust_pivot.add_child(dust_ring)


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()
	if solar_fragments == null:
		return
	var n: int = SMALL.get(quality_preset, 400)
	solar_fragments.multimesh.visible_instance_count = n / 2
	metal_shards.multimesh.visible_instance_count = n / 2
	dust_ring.multimesh.visible_instance_count = DUST.get(quality_preset, 1000)


## Streaming hook: retire/restore the detailed tiers. Authoritative layout is deterministic, so nothing is lost.
func set_detail_active(active: bool) -> void:
	detail_active = active
	medium_pivot.visible = active
	small_pivot.visible = active
	for body in _large_bodies:
		if is_instance_valid(body):
			body.collision_layer = 1 if active else 0
	for c in medium_pivot.get_children():
		var b: StaticBody3D = c.get_node_or_null("Collision") as StaticBody3D
		if b != null:
			b.collision_layer = 1 if active else 0


func apply_origin(new_origin: Vector3) -> void:
	current_origin = new_origin
	position = center_planet - new_origin


func tick(delta: float) -> void:
	_time += delta
	large_pivot.rotation.y = _time * 0.004
	medium_pivot.rotation.y = _time * 0.006
	small_pivot.rotation.y = _time * 0.012
	dust_pivot.rotation.y = _time * 0.002


func get_tier_counts() -> Dictionary:
	return {"large": large_pivot.get_child_count() if large_pivot else 0,
		"medium": medium_pivot.get_child_count() if medium_pivot else 0,
		"small": (solar_fragments.multimesh.visible_instance_count + metal_shards.multimesh.visible_instance_count) if solar_fragments else 0,
		"dust": dust_ring.multimesh.visible_instance_count if dust_ring else 0}


## Number of CollisionShape3D nodes under each tier pivot (tiers 3 and 4 must stay at zero).
func count_collision_shapes(pivot: Node) -> int:
	var n: int = 0
	if pivot is CollisionShape3D:
		n += 1
	for c in pivot.get_children():
		n += count_collision_shapes(c)
	return n


func get_tier_collision_counts() -> Dictionary:
	return {"large": count_collision_shapes(large_pivot), "medium": count_collision_shapes(medium_pivot),
		"small": count_collision_shapes(small_pivot), "dust": count_collision_shapes(dust_pivot)}


func get_signature() -> int:
	return _signature
