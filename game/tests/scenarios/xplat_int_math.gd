extends SceneTree
## Cross-platform determinism scenario: pure integer math, no engine randomness, no floats.
## Run through tools/py/xplat_determinism.py (macOS native vs linux/amd64 vs linux/arm64 container):
##   tools/gd run res://tests/scenarios/xplat_int_math.gd [-- --ticks=N] [--diverge=os|arch]
## Prints `HASH tick=<n> <8 hex digits>` every 20 ticks; identical chains on every platform are required.
## It exercises exactly what the real sim relies on (docs/ARCHITECTURE.md section 4): 32-bit masked xorshift128,
## exact integer sqrt, C-semantics `/` and `%` on negatives, floor division, arithmetic shifts and
## products kept below 2^62.
##   --diverge=os|arch  deliberately mixes the OS / CPU architecture name into the state at tick 60, so a
##                      mismatch must be reported at exactly that tick (proves the comparator works).

const MASK32: int = 0xFFFFFFFF
const FNV_PRIME: int = 16777619
const FNV_OFFSET: int = 2166136261
const REPORT_EVERY: int = 20

var _x: int = 123456789
var _y: int = 362436069
var _z: int = 521288629
var _w: int = 88675123
var _hash: int = FNV_OFFSET


func _initialize() -> void:
	var ticks: int = 200
	var diverge: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			ticks = arg.substr("--ticks=".length()).to_int()
		elif arg.begins_with("--diverge="):
			diverge = arg.substr("--diverge=".length())
	var first: PackedStringArray = _run(ticks, diverge)
	_reset()
	var second: PackedStringArray = _run(ticks, diverge, false)
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE ticks=%d lines=%d" % [ticks, first.size()])
	quit(0)


func _reset() -> void:
	_x = 123456789
	_y = 362436069
	_z = 521288629
	_w = 88675123
	_hash = FNV_OFFSET


func _run(ticks: int, diverge: String, _unused: bool = true) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for tick: int in range(1, ticks + 1):
		_step(tick)
		if tick == 60 and diverge != "":
			_mix(_string_sum(OS.get_name() if diverge == "os" else Engine.get_architecture_name()))
		if tick % REPORT_EVERY == 0:
			out.append("HASH tick=%d %08x" % [tick, _hash])
	return out


func _step(tick: int) -> void:
	var r: int = _next()
	var a: int = (r << 20) ^ _next()              # < 2^52
	var sqrt_a: int = _isqrt(a)
	var divisor: int = (r % 977) + 1
	var fdiv: int = _floor_div(a - (1 << 50), divisor)
	var fl_mod: int = _floor_mod(a - (1 << 50), divisor)
	var cdiv: int = (-a) / 1009                    # truncates toward zero
	var cmod: int = (-a) % 1009                    # keeps the dividend's sign
	var prod: int = (a * (_next() & 0x3FF)) >> 7   # < 2^62 before the shift
	var neg_shift: int = (-a) >> 5                 # arithmetic shift
	_mix(sqrt_a)
	_mix(fdiv)
	_mix(fl_mod)
	_mix(cdiv)
	_mix(cmod)
	_mix(prod)
	_mix(neg_shift)
	_mix(tick)


func _next() -> int:
	var t: int = _x ^ ((_x << 11) & MASK32)
	_x = _y
	_y = _z
	_z = _w
	_w = (_w ^ (_w >> 19)) ^ (t ^ (t >> 8))
	_w &= MASK32
	return _w


## Folds a (possibly negative, up to 62 bit) integer into the FNV-1a 32 bit hash, byte by byte.
func _mix(v: int) -> void:
	var u: int = v
	for _i: int in 8:
		_hash = ((_hash ^ (u & 0xFF)) * FNV_PRIME) & MASK32
		u = u >> 8


func _string_sum(s: String) -> int:
	var total: int = 0
	for i: int in s.length():
		total = total * 31 + s.unicode_at(i)
	return total


func _bit_length(n: int) -> int:
	var bits: int = 0
	var v: int = n
	while v > 0:
		bits += 1
		v = v >> 1
	return bits


func _isqrt(n: int) -> int:
	if n < 2:
		return n
	var x: int = 1 << ((_bit_length(n) + 1) >> 1)
	while true:
		var y: int = (x + n / x) >> 1
		if y >= x:
			return x
		x = y
	return x


func _floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


func _floor_mod(a: int, b: int) -> int:
	var m: int = a % b
	if m != 0 and ((m < 0) != (b < 0)):
		m += b
	return m
