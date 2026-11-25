class_name CubeSphereBuilder
extends RefCounted

## Spherified-cube mesh builder. Face basis (n, a, b) satisfies a x b = n so
## triangles (00, 01, 10) / (10, 01, 11) are clockwise (Godot front face) from outside.

const FACE_N: PackedVector3Array = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
	Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
]
const FACE_A: PackedVector3Array = [
	Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0, 0, 1),
	Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
]
const FACE_B: PackedVector3Array = [
	Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0),
	Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0),
]


static func cube_point_to_sphere(p: Vector3) -> Vector3:
	var x2: float = p.x * p.x
	var y2: float = p.y * p.y
	var z2: float = p.z * p.z
	return Vector3(
		p.x * sqrt(1.0 - y2 * 0.5 - z2 * 0.5 + y2 * z2 / 3.0),
		p.y * sqrt(1.0 - z2 * 0.5 - x2 * 0.5 + z2 * x2 / 3.0),
		p.z * sqrt(1.0 - x2 * 0.5 - y2 * 0.5 + x2 * y2 / 3.0))


static func face_uv_to_direction(face_index: int, uv: Vector2) -> Vector3:
	var f: int = clampi(face_index, 0, 5)
	var cube: Vector3 = FACE_N[f] + FACE_A[f] * uv.x + FACE_B[f] * uv.y
	return cube_point_to_sphere(cube).normalized()


static func patch_center_direction(face_index: int, uv_min: Vector2, uv_max: Vector2) -> Vector3:
	return face_uv_to_direction(face_index, (uv_min + uv_max) * 0.5)


static func face_from_direction(dir: Vector3) -> int:
	var ax: float = absf(dir.x)
	var ay: float = absf(dir.y)
	var az: float = absf(dir.z)
	if ax >= ay and ax >= az:
		return 0 if dir.x >= 0.0 else 1
	if ay >= az:
		return 2 if dir.y >= 0.0 else 3
	return 4 if dir.z >= 0.0 else 5


static func build_patch_mesh(face_index: int, uv_min: Vector2, uv_max: Vector2, resolution: int, noise_stack: TerrainNoiseStack, skirt_depth: float, patch_origin: Vector3) -> Dictionary:
	var res: int = maxi(resolution, 2)
	var count: int = res * res
	var total: int = count + res * 4

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uvs2 := PackedVector2Array()
	var dirs := PackedVector3Array()
	verts.resize(total)
	normals.resize(total)
	colors.resize(total)
	uvs.resize(total)
	uvs2.resize(total)
	dirs.resize(count)

	var biome_counts := PackedInt32Array()
	biome_counts.resize(6)
	biome_counts.fill(0)

	for j in res:
		var v: float = lerpf(uv_min.y, uv_max.y, float(j) / float(res - 1))
		for i in res:
			var u: float = lerpf(uv_min.x, uv_max.x, float(i) / float(res - 1))
			var idx: int = j * res + i
			var dir: Vector3 = face_uv_to_direction(face_index, Vector2(u, v))
			var vdata: Dictionary = noise_stack.sample_vertex_data(dir)
			var pos: Vector3 = vdata["position"]
			var cw: Color = vdata["color_weights"]
			var ew: Color = vdata["extra_weights"]
			var bid: int = vdata["biome_id"]
			dirs[idx] = dir
			verts[idx] = pos - patch_origin
			normals[idx] = noise_stack.sample_surface_normal(dir)
			colors[idx] = cw
			uvs[idx] = Vector2(ew.b, ew.a)  # industrial, moisture_erosion
			uvs2[idx] = Vector2(ew.r, ew.g)  # biome_id / 5, canyon_strata
			biome_counts[clampi(bid, 0, 5)] += 1

	var indices := PackedInt32Array()
	var collision_faces := PackedVector3Array()
	for j in res - 1:
		for i in res - 1:
			var a: int = j * res + i
			var b: int = (j + 1) * res + i
			var c: int = j * res + i + 1
			var d: int = (j + 1) * res + i + 1
			indices.append_array(PackedInt32Array([a, b, c, c, b, d]))
			collision_faces.append(verts[a])
			collision_faces.append(verts[b])
			collision_faces.append(verts[c])
			collision_faces.append(verts[c])
			collision_faces.append(verts[b])
			collision_faces.append(verts[d])

	# Skirts: ordered so that outward x traversal = surface normal for CW winding.
	var edges: Array[PackedInt32Array] = []
	var e0 := PackedInt32Array()
	var e1 := PackedInt32Array()
	var e2 := PackedInt32Array()
	var e3 := PackedInt32Array()
	for i in res:
		e0.append(i)
		e1.append((res - 1) + i * res)
		e2.append((res - 1) * res + (res - 1 - i))
		e3.append((res - 1 - i) * res)
	edges.append(e0)
	edges.append(e1)
	edges.append(e2)
	edges.append(e3)

	for k in 4:
		var edge: PackedInt32Array = edges[k]
		var base: int = count + k * res
		for m in res:
			var g: int = edge[m]
			verts[base + m] = verts[g] - dirs[g] * skirt_depth
			normals[base + m] = normals[g]
			colors[base + m] = colors[g]
			uvs[base + m] = uvs[g]
			uvs2[base + m] = uvs2[g]
		for m in res - 1:
			var t0: int = edge[m]
			var t1: int = edge[m + 1]
			var b0: int = base + m
			var b1: int = base + m + 1
			indices.append_array(PackedInt32Array([t0, t1, b0, t1, b1, b0]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var aabb: AABB = mesh.get_aabb()
	var best_biome: int = 0
	for bi in 6:
		if biome_counts[bi] > biome_counts[best_biome]:
			best_biome = bi

	return {
		"mesh": mesh,
		"collision_faces": collision_faces,
		"aabb_center": patch_origin + aabb.get_center(),
		"patch_radius": aabb.size.length() * 0.5,
		"avg_biome": best_biome,
	}
