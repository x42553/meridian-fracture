class_name NetClock
extends RefCounted
## Monotonic microsecond time source for the network layer: real (Time.get_ticks_usec) or manual
## (tests / virtual time). Net code never reads wall time any other way.

var _manual: bool = false
var _us: int = 0


## Wall-clock (monotonic) time source.
static func real() -> NetClock:
	return NetClock.new()


## Manual time source starting at `start_us`; advance with advance_us().
static func manual(start_us: int = 0) -> NetClock:
	var c: NetClock = NetClock.new()
	c._manual = true
	c._us = start_us
	return c


func is_manual() -> bool:
	return _manual


func now_us() -> int:
	return _us if _manual else Time.get_ticks_usec()


func now_ms() -> int:
	return now_us() / 1000


## Manual clocks only (asserts otherwise; a real clock ignores the call).
func advance_us(us: int) -> void:
	assert(_manual, "NetClock.advance_us on a real clock")
	if _manual:
		_us += maxi(us, 0)


func set_us(us: int) -> void:
	assert(_manual, "NetClock.set_us on a real clock")
	if _manual:
		_us = us
