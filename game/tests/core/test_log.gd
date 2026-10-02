extends RefCounted
## Log: sink, ring and threshold behaviour (Log state is restored at the end of every test).

var _lines: Array[String] = []
var _saved_level: int = 0
var _saved_quiet: bool = false
var _saved_sink: Callable = Callable()
var _saved_ring: PackedStringArray = PackedStringArray()


func setup(_t: TestCtx) -> void:
	_saved_level = Log.level
	_saved_quiet = Log.quiet
	_saved_sink = Log.sink
	_saved_ring = Log.ring
	Log.ring = PackedStringArray()
	Log.sink = _capture


func teardown(_t: TestCtx) -> void:
	Log.level = _saved_level
	Log.quiet = _saved_quiet
	Log.sink = _saved_sink
	Log.ring = _saved_ring


func _capture(level: int, tag: String, msg: String) -> void:
	_lines.append("%d|%s|%s" % [level, tag, msg])


func test_sink_and_threshold(t: TestCtx) -> void:
	Log.level = Log.Level.WARN
	Log.debug("x", "d")
	Log.info("x", "i")
	Log.warn("x", "w")
	Log.error("y", "e")
	t.eq(_lines, ["2|x|w", "3|y|e"] as Array[String], "only WARN and above reach the sink")
	t.eq(Log.ring.size(), 4, "ring records every line, even below the threshold")


func test_quiet(t: TestCtx) -> void:
	Log.quiet = true
	Log.error("x", "boom")
	t.eq(_lines.size(), 0, "quiet suppresses the sink")
	t.eq(Log.ring.size(), 1, "ring still records")


func test_ring_keeps_last_256(t: TestCtx) -> void:
	Log.level = Log.Level.OFF
	for i: int in 300:
		Log.info("r", str(i))
	t.eq(Log.ring.size(), 256, "ring capped")
	t.eq(Log.ring[255], "INFO [r] 299", "newest last")
	t.eq(Log.ring[0], "INFO [r] 44", "oldest kept")


func test_default_callable_invalid(t: TestCtx) -> void:
	t.check_false(Callable().is_valid(), "default Callable() is not valid")
