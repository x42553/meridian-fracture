class_name TestCtx
extends RefCounted
## Assertion context passed to every `func test_*(t: TestCtx)` method (see tests/harness/test_suite.gd).
##
## Every assertion returns `true` when it passed, so tests can bail out early:
##   if not t.not_null(world, "world built"): return
## Failures never throw and never abort the run; they are recorded with the caller's file:line.
## Engine errors raised while a test runs (script runtime errors, push_error) fail the test as well,
## unless the test declared them with expect_errors(n).

## Number of assertions evaluated (passed + failed).
var assertions: int = 0
## One entry per failed assertion: {msg: String, file: String, line: int}.
var failures: Array[Dictionary] = []
## Informational lines printed under the test result (see note()).
var notes: Array[String] = []
## Set by skip(); the runner reports the test as SKIP.
var skipped: bool = false
var skip_reason: String = ""
## Exact number of engine errors this test is allowed (and required) to raise. Default 0.
var expected_errors: int = 0
## Per-test limit for tests that await (seconds); <= 0 means the suite default (30 s). See set_timeout().
var timeout_s: float = -1.0


## Slowness of this process relative to the reference machine (1.0 = as fast or faster): a fixed integer loop is timed once (best of 5) and compared with
## 4.5 ms (Apple M-series, native). Wall-clock budgets in tests multiply by it so an emulated (linux/amd64 on Apple silicon: ~2.6x) or heavily loaded
## machine does not fail a performance assertion that is about the code, not the box. Capped at 6.
static var _perf_factor: float = 0.0


static func perf_factor() -> float:
	if _perf_factor > 0.0:
		return _perf_factor
	var best: float = 1.0e9
	for rep: int in 5:
		var t0: int = Time.get_ticks_usec()
		var acc: int = 1
		var arr: PackedInt32Array = PackedInt32Array()
		arr.resize(256)
		for i: int in 150000:
			acc = (acc * 31 + i) & 0xFFFFFF
			arr[i & 255] = acc
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0 + float(acc & 0) + float(arr[3] & 0))
	_perf_factor = clampf(best / 4.5, 1.0, 6.0)
	return _perf_factor


## Passes when `condition` is true.
func check(condition: bool, msg: String = "") -> bool:
	assertions += 1
	if condition:
		return true
	_record("check failed" if msg.is_empty() else "check failed: " + msg)
	return false


## Passes when `condition` is false.
func check_false(condition: bool, msg: String = "") -> bool:
	assertions += 1
	if not condition:
		return true
	_record("check_false failed" if msg.is_empty() else "check_false failed: " + msg)
	return false


## Passes when `actual == expected` AND both have the same Variant type (int 1 != float 1.0, which
## catches accidental float math in integer code). String and StringName count as the same type.
func eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	assertions += 1
	if _same_type(actual, expected) and actual == expected:
		return true
	var detail: String = "eq failed: got %s, expected %s" % [_show(actual), _show(expected)]
	if not _same_type(actual, expected):
		detail += " (type %s vs %s)" % [type_string(typeof(actual)), type_string(typeof(expected))]
	_record(detail if msg.is_empty() else detail + " - " + msg)
	return false


## Passes when `actual != unexpected` (types are not compared: differing types count as not equal).
func ne(actual: Variant, unexpected: Variant, msg: String = "") -> bool:
	assertions += 1
	if not (_same_type(actual, unexpected) and actual == unexpected):
		return true
	var detail: String = "ne failed: both are %s" % _show(actual)
	_record(detail if msg.is_empty() else detail + " - " + msg)
	return false


## Passes when |actual - expected| <= eps. Test code may use floats freely (only src/ is float-banned).
func near(actual: float, expected: float, eps: float = 0.0001, msg: String = "") -> bool:
	assertions += 1
	if absf(actual - expected) <= eps:
		return true
	var detail: String = "near failed: got %s, expected %s +/- %s" % [actual, expected, eps]
	_record(detail if msg.is_empty() else detail + " - " + msg)
	return false


## Passes when `value == null`.
func is_null(value: Variant, msg: String = "") -> bool:
	assertions += 1
	if value == null:
		return true
	_record("is_null failed: got %s" % _show(value) + ("" if msg.is_empty() else " - " + msg))
	return false


## Passes when `value != null`.
func not_null(value: Variant, msg: String = "") -> bool:
	assertions += 1
	if value != null:
		return true
	_record("not_null failed: got null" + ("" if msg.is_empty() else " - " + msg))
	return false


## Passes when a < b (numbers or anything with a defined `<`).
func lt(a: Variant, b: Variant, msg: String = "") -> bool:
	return _cmp(a < b, "lt", a, b, msg)


## Passes when a <= b.
func le(a: Variant, b: Variant, msg: String = "") -> bool:
	return _cmp(a <= b, "le", a, b, msg)


## Passes when a > b.
func gt(a: Variant, b: Variant, msg: String = "") -> bool:
	return _cmp(a > b, "gt", a, b, msg)


## Passes when a >= b.
func ge(a: Variant, b: Variant, msg: String = "") -> bool:
	return _cmp(a >= b, "ge", a, b, msg)


## Unconditional failure (use for code paths that must not be reached).
func fail(msg: String) -> void:
	assertions += 1
	_record(msg)


## Adds an informational line to the test's report (printed under the result line).
func note(msg: String) -> void:
	notes.append(msg)


## Marks the test as skipped (call it first, then `return`). Skips do not fail the run.
func skip(reason: String) -> void:
	skipped = true
	skip_reason = reason


## Declares that this test deliberately provokes exactly `count` engine errors (push_error, script
## runtime errors). Without this call any engine error fails the test.
func expect_errors(count: int) -> void:
	expected_errors = count


## Raises (or lowers) the wall-clock limit of an async test; call it first thing in the test.
func set_timeout(seconds: float) -> void:
	timeout_s = seconds


## True while no assertion has failed.
func passed() -> bool:
	return failures.is_empty()


func _cmp(ok: bool, op: String, a: Variant, b: Variant, msg: String) -> bool:
	assertions += 1
	if ok:
		return true
	var detail: String = "%s failed: %s vs %s" % [op, _show(a), _show(b)]
	_record(detail if msg.is_empty() else detail + " - " + msg)
	return false


func _same_type(a: Variant, b: Variant) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if ta == tb:
		return true
	return (ta == TYPE_STRING or ta == TYPE_STRING_NAME) and (tb == TYPE_STRING or tb == TYPE_STRING_NAME)


## Failure text of a value. NEVER `var_to_str` an Object: it serialises every property (a RefCounted cycle such as brain <-> context
## overflows the native stack and kills the runner with SIGBUS/SIGABRT), so Objects print as class name + instance id, also inside
## containers (bounded depth / width).
func _show(v: Variant, depth: int = 0) -> String:
	if typeof(v) == TYPE_OBJECT:
		return _show_object(v as Object)
	if v is Array:
		if depth >= 3:
			return "[...]"
		var parts: PackedStringArray = PackedStringArray()
		for item: Variant in v as Array:
			if parts.size() >= 12:
				parts.append("...")
				break
			parts.append(_show(item, depth + 1))
		return "[" + ", ".join(parts) + "]"
	if v is Dictionary:
		if depth >= 3:
			return "{...}"
		var dparts: PackedStringArray = PackedStringArray()
		for k: Variant in (v as Dictionary).keys():
			if dparts.size() >= 12:
				dparts.append("...")
				break
			dparts.append("%s: %s" % [_show(k, depth + 1), _show((v as Dictionary)[k], depth + 1)])
		return "{" + ", ".join(dparts) + "}"
	return var_to_str(v)


static func _show_object(o: Object) -> String:
	if o == null:
		return "null"
	if not is_instance_valid(o):
		return "<freed Object>"
	var cls: String = o.get_class()
	var scr: Variant = o.get_script()
	if scr is Script and not (scr as Script).get_global_name().is_empty():
		cls = String((scr as Script).get_global_name())
	return "<%s#%d>" % [cls, o.get_instance_id()]


## Records a failure with the file:line of the first stack frame outside this file.
func _record(msg: String) -> void:
	var here: String = get_script().resource_path
	var file: String = ""
	var line: int = 0
	for frame: Dictionary in get_stack():
		var source: String = frame.get("source", "")
		if source != here:
			file = source
			line = frame.get("line", 0)
			break
	failures.append({"msg": msg, "file": file, "line": line})
