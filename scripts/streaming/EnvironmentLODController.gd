class_name EnvironmentLODController
extends Node
## Distance / altitude driven visibility + LOD tiers with hysteresis for facilities, prop scatterers,
## motherships and orbital structures. A tier only changes once the camera is `hysteresis` beyond the boundary.

const HYSTERESIS := 0.12
## Default tier boundaries (m): tier 0 near, 1 mid, 2 far, 3 culled.
const DEFAULT_RANGES: Array = [1500.0, 5000.0, 14000.0]

var _entries: Dictionary = {}   # id -> {node, ranges, tier}
var tier_changes: int = 0
var global_tier: int = 0


func register(id: StringName, node: Node3D, ranges: Array = DEFAULT_RANGES) -> void:
	_entries[id] = {"node": node, "ranges": ranges, "tier": 0}


func unregister(id: StringName) -> void:
	_entries.erase(id)


func get_tier(id: StringName) -> int:
	return _entries.get(id, {}).get("tier", 0)


## Pure hysteresis tier function (testable): distance + currently held tier -> new tier.
static func resolve_tier(dist: float, ranges: Array, current: int) -> int:
	var t: int = current
	# Move outward only once past boundary * (1 + h); inward once inside boundary * (1 - h).
	while t < ranges.size() and dist > float(ranges[t]) * (1.0 + HYSTERESIS):
		t += 1
	while t > 0 and dist < float(ranges[t - 1]) * (1.0 - HYSTERESIS):
		t -= 1
	return t


func update(camera_render_pos: Vector3, altitude: float) -> void:
	for id in _entries:
		var e: Dictionary = _entries[id]
		var n: Node3D = e["node"]
		if not is_instance_valid(n):
			continue
		var dist: float = n.global_position.distance_to(camera_render_pos)
		var nt: int = resolve_tier(dist, e["ranges"], e["tier"])
		if nt != e["tier"]:
			e["tier"] = nt
			tier_changes += 1
			n.visible = nt < (e["ranges"] as Array).size()
			n.set_meta("lod_tier", nt)
	# Global tier from altitude: surface / low flight / orbital / deep space.
	global_tier = resolve_tier(altitude, [800.0, 1800.0, 4000.0], global_tier)


func get_entry_count() -> int:
	return _entries.size()
