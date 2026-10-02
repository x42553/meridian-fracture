class_name Log
extends RefCounted
## Logging facade (sim_core 3.2.6). The only code allowed to print / push_warning (lint L006); it never
## influences the simulation. `sink` is the injectable output (tests capture with it).

enum Level { DEBUG, INFO, WARN, ERROR, OFF }

const RING_SIZE: int = 256

## Lines below this level are not emitted (they are still recorded in `ring`).
static var level: int = Level.INFO
## true suppresses the sink and console output (the ring still records).
static var quiet: bool = false
## Optional `func(level: int, tag: String, msg: String)`; when valid it replaces the console output.
static var sink: Callable = Callable()
## The last RING_SIZE lines, "LEVEL [tag] msg".
static var ring: PackedStringArray = PackedStringArray()

const _NAMES: PackedStringArray = ["DEBUG", "INFO", "WARN", "ERROR"]

## Guards `ring`: `_emit` is called from worker threads too (map generation thread, WorkerThreadPool model builds, the engine Logger hook) while the
## main thread logs and reads the ring. A PackedStringArray appended and re-sliced from two threads at once is heap corruption.
static var _ring_lock: Mutex = Mutex.new()


static func debug(tag: String, msg: String) -> void:
	_emit(Level.DEBUG, tag, msg)


static func info(tag: String, msg: String) -> void:
	_emit(Level.INFO, tag, msg)


static func warn(tag: String, msg: String) -> void:
	_emit(Level.WARN, tag, msg)


static func error(tag: String, msg: String) -> void:
	_emit(Level.ERROR, tag, msg)


static func _emit(lv: int, tag: String, msg: String) -> void:
	var line: String = "%s [%s] %s" % [_NAMES[lv], tag, msg]
	ring_push(line)
	if quiet or lv < level:
		return
	if sink.is_valid():
		sink.call(lv, tag, msg)
	elif lv == Level.ERROR:
		push_error(line)
	elif lv == Level.WARN:
		push_warning(line)
	else:
		print(line)


## Appends one line to `ring` (bounded to RING_SIZE). Thread-safe; `AppLogger` records engine errors through it as well.
static func ring_push(line: String) -> void:
	_ring_lock.lock()
	ring.append(line)
	if ring.size() > RING_SIZE:
		ring = ring.slice(ring.size() - RING_SIZE)
	_ring_lock.unlock()


## The newest `n` lines of `ring` (a copy, thread-safe).
static func ring_tail(n: int = RING_SIZE) -> PackedStringArray:
	_ring_lock.lock()
	var out: PackedStringArray = ring.slice(maxi(0, ring.size() - n))
	_ring_lock.unlock()
	return out
