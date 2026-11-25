class_name AssetResidencyManager
extends Node
## Memory-budgeted residency records. Authoritative world state (destruction states, door states, ...) lives in a
## dictionary that is NEVER freed with the visual instance, so retiring an asset and reloading it later restores
## exactly the same simulation state.

const BUDGET_MB := {"LOW": 256.0, "MEDIUM": 512.0, "HIGH": 1024.0, "ULTRA": 2048.0}

var quality_preset: String = "HIGH"
var _records: Dictionary = {}     # id -> {mb, resident, touched, node}
var _world_state: Dictionary = {} # id -> Dictionary (authoritative, survives retirement)
var _pool: Dictionary = {}        # kind -> Array[Node]
var _clock: int = 0
var retire_count: int = 0
var reload_count: int = 0


func set_quality(preset: String) -> void:
	quality_preset = preset.to_upper()


func get_budget_mb() -> float:
	return BUDGET_MB.get(quality_preset, 1024.0)


func get_residency_mb() -> float:
	var total: float = 0.0
	for id in _records:
		if _records[id]["resident"]:
			total += _records[id]["mb"]
	return total


func is_over_budget() -> bool:
	return get_residency_mb() > get_budget_mb()


func can_fit(mb: float) -> bool:
	return get_residency_mb() + mb <= get_budget_mb()


func is_resident(id: StringName) -> bool:
	return _records.has(id) and _records[id]["resident"]


## Marks `id` resident with an estimated footprint. A previously retired id counts as a reload.
func make_resident(id: StringName, mb: float, node: Node = null) -> void:
	if _records.has(id) and not _records[id]["resident"]:
		reload_count += 1
	_clock += 1
	_records[id] = {"mb": mb, "resident": true, "touched": _clock, "node": node}


func touch(id: StringName) -> void:
	if _records.has(id):
		_clock += 1
		_records[id]["touched"] = _clock


## Retires the visual instance only. The authoritative state dictionary is kept.
func retire(id: StringName, free_node: bool = false) -> void:
	if not _records.has(id) or not _records[id]["resident"]:
		return
	var n: Node = _records[id]["node"]
	_records[id]["resident"] = false
	_records[id]["node"] = null
	retire_count += 1
	if free_node and n != null and is_instance_valid(n):
		n.queue_free()


## Least-recently-touched resident ids first (eviction order when over budget).
func get_eviction_candidates() -> Array[StringName]:
	var ids: Array = []
	for id in _records:
		if _records[id]["resident"]:
			ids.append(id)
	ids.sort_custom(func(a, b) -> bool: return _records[a]["touched"] < _records[b]["touched"])
	var out: Array[StringName] = []
	for id in ids:
		out.append(id)
	return out


func set_world_state(id: StringName, state: Dictionary) -> void:
	_world_state[id] = state.duplicate(true)


func get_world_state(id: StringName) -> Dictionary:
	return (_world_state.get(id, {}) as Dictionary).duplicate(true)


func has_world_state(id: StringName) -> bool:
	return _world_state.has(id)


## Simple node pool: retired visuals can be recycled instead of rebuilt.
func pool_put(kind: StringName, node: Node) -> void:
	if not _pool.has(kind):
		_pool[kind] = []
	(_pool[kind] as Array).append(node)


func pool_get(kind: StringName) -> Node:
	var arr: Array = _pool.get(kind, [])
	while not arr.is_empty():
		var n: Node = arr.pop_back()
		if is_instance_valid(n):
			return n
	return null


func get_pool_size() -> int:
	var n: int = 0
	for k in _pool:
		n += (_pool[k] as Array).size()
	return n


func get_record_count() -> int:
	return _records.size()
