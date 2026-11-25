class_name SceneChunkLoader
extends Node
## Threaded resource loading with a main-thread activation queue. ResourceLoader does the I/O off-thread;
## this class only ever hands finished resources back from poll()/take_ready(), which run on the main thread,
## so the SceneTree is never mutated from a worker thread.

signal chunk_loaded(path: String)
signal chunk_failed(path: String)

enum Status { IDLE, LOADING, READY, FAILED }

var _pending: Dictionary = {}        # path -> true (requested, not yet finished)
var _ready_queue: Array[String] = []  # finished, awaiting main-thread activation
var _resources: Dictionary = {}      # path -> Resource (loaded, unclaimed)
var _failed: Dictionary = {}
var requests_total: int = 0
var loaded_total: int = 0


## Starts a threaded load. Returns false when the path is invalid (never raises engine errors).
func request(path: String) -> bool:
	if _pending.has(path) or _resources.has(path):
		return true
	if not ResourceLoader.exists(path):
		_failed[path] = true
		chunk_failed.emit(path)
		return false
	if ResourceLoader.load_threaded_request(path) != OK:
		_failed[path] = true
		chunk_failed.emit(path)
		return false
	_failed.erase(path)
	_pending[path] = true
	requests_total += 1
	return true


func get_status(path: String) -> int:
	if _failed.has(path):
		return Status.FAILED
	if _resources.has(path) or _ready_queue.has(path):
		return Status.READY
	if _pending.has(path):
		return Status.LOADING
	return Status.IDLE


## Main-thread poll of every pending request. Finished loads move to the activation queue.
func poll() -> void:
	for path in _pending.keys():
		var st: int = ResourceLoader.load_threaded_get_status(path)
		match st:
			ResourceLoader.THREAD_LOAD_LOADED:
				_resources[path] = ResourceLoader.load_threaded_get(path)
				_pending.erase(path)
				_ready_queue.append(path)
				loaded_total += 1
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending.erase(path)
				_failed[path] = true
				chunk_failed.emit(path)


## Pops up to `max_count` finished paths for activation (call from the main thread only).
func take_ready(max_count: int = 1) -> Array[String]:
	var out: Array[String] = []
	while not _ready_queue.is_empty() and out.size() < max_count:
		var p: String = _ready_queue.pop_front()
		out.append(p)
		chunk_loaded.emit(p)
	return out


func get_resource(path: String) -> Resource:
	return _resources.get(path, null)


## Drops the cached resource reference (visual instances are retired by the residency manager).
func release(path: String) -> void:
	_resources.erase(path)
	_ready_queue.erase(path)
	_failed.erase(path)


func get_pending_count() -> int:
	return _pending.size()


func get_queue_depth() -> int:
	return _ready_queue.size()


func _process(_delta: float) -> void:
	if not _pending.is_empty():
		poll()
