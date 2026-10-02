class_name MapGenJob
extends RefCounted
## Time-sliceable map generation for the loading screen (net.md NetWorldJob adapter, terrain_movement 5.12.7).
## Threaded mode: one worker Thread runs the generator; `step` only polls it (never blocks, < 50 us). Unthreaded mode:
## `step(budget_us)` runs whole stages until the budget is spent (a stage is at most about 0.5 s at 256^2, so it may
## overshoot by one stage). The clock only decides WHEN to yield: slicing never changes the result, and both modes
## produce byte-identical maps (tested).

## Jobs with a running worker thread (instance id -> WeakRef): `cancel_all()` joins them at quit even when their owner leaked or was never told to
## stop (a worker still running GDScript while the engine tears the script language down crashes the process).
static var _live: Dictionary = {}

var _runner: MapGenerator.Runner = null
var _id: int = 0  # instance id (a method call on self is not possible inside the PREDELETE notification)
var _thread: Thread = null
var _mutex: Mutex = Mutex.new()
var _pct: int = 0
var _cancel: bool = false
var _finished: bool = false


## Starts a job for a lobby `config.map` dictionary. Tables and the terrain table are resolved on the calling thread.
static func begin(map_cfg: Dictionary, tables: MapGenTables = null, use_thread: bool = true) -> MapGenJob:
	var j: MapGenJob = MapGenJob.new()
	j._id = j.get_instance_id()
	j._runner = MapGenerator.make_runner(map_cfg, tables, Callable(j, "_on_progress"))
	if j._runner == null:
		j._finished = true
		return j
	if use_thread:
		j._thread = Thread.new()
		if j._thread.start(j._work) != OK:
			j._thread = null
		else:
			_live[j.get_instance_id()] = weakref(j)
	return j


## Cancels and joins every job that still has a worker thread (quit). Main thread only.
static func cancel_all() -> int:
	var n: int = 0
	for id: Variant in _live.keys():
		var j: MapGenJob = (_live[id] as WeakRef).get_ref() as MapGenJob
		if j != null and j._thread != null:
			j.cancel()
			n += 1
	_live.clear()
	return n


func _on_progress(_stage: int, p: int) -> void:
	_mutex.lock()
	_pct = maxi(_pct, p)
	_mutex.unlock()


func _work() -> void:
	while true:
		_mutex.lock()
		var c: bool = _cancel
		_mutex.unlock()
		if c or _runner.step():
			return


## True when finished (or cancelled). Threaded: polls the worker. Unthreaded: runs stages while the budget lasts.
func step(budget_us: int) -> bool:
	if _finished:
		return true
	if _thread != null:
		if _thread.is_started() and not _thread.is_alive():
			_thread.wait_to_finish()
			_thread = null
			_live.erase(_id)
			_finished = true
		return _finished
	var t0: int = Time.get_ticks_usec()  # lint-allow: L003 job yield decision only, never enters the result
	while true:
		if _cancel:
			_finished = true
			return true
		if _runner.step():
			_finished = true
			return true
		if Time.get_ticks_usec() - t0 >= budget_us:  # lint-allow: L003 job yield decision only, never enters the result
			return false
	return false


## 0..100, monotonic.
func progress_pct() -> int:
	_mutex.lock()
	var p: int = _pct
	_mutex.unlock()
	return 100 if _finished and result() != null else p


## The finalized map (nav prepared); valid after step() returned true; null on cancel.
func result() -> MapData:
	if not _finished or _cancel or _runner == null or not _runner.done:
		return null
	return _runner.map


func cancel() -> void:
	_mutex.lock()
	_cancel = true
	_mutex.unlock()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_live.erase(_id)
	_finished = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _thread != null:
		_live.erase(_id)
		_mutex.lock()
		_cancel = true
		_mutex.unlock()
		# the worker itself can drop the last reference (a Callable it is running holds the job for a moment while the owner let go): it
		# must not join itself ("Threads can't wait to finish on themselves"); the cancel flag ends its loop, the Thread object is released
		if _thread.is_started() and _thread.get_id() != str(OS.get_thread_caller_id()):
			_thread.wait_to_finish()
