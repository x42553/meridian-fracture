extends RefCounted
## VIEW-M1 acceptance: ViewExpr grammar, functions, errors, folding, performance.


func _scope(names: Array[StringName]) -> ViewExpr.Scope:
	var sc: ViewExpr.Scope = ViewExpr.Scope.new()
	for n: StringName in names:
		sc.slot(n)
	return sc


func _f(src: String, names: Array[StringName] = [], vals: Array = []) -> Variant:
	var sc: ViewExpr.Scope = _scope(names)
	var e: ViewExpr = ViewExpr.compile(src, sc, "test")
	if e == null:
		return null
	var frame: Array = sc.make_frame()
	for i in names.size():
		frame[sc.slot(names[i])] = vals[i]
	return e.eval(frame)


func test_arithmetic_and_functions(t: TestCtx) -> void:
	t.eq(_f("1+2*3"), 7.0, "precedence")
	t.eq(_f("min(3,4)"), 3.0, "min")
	t.near(_f("lerp(0,10,0.25)") as float, 2.5, 1.0e-9, "lerp")
	t.eq(_f("a>2 ? 5 : 6", [&"a"], [3.0]), 5.0, "ternary true")
	t.eq(_f("a>2 ? 5 : 6", [&"a"], [1.0]), 6.0, "ternary false")
	t.near(_f("len*0.5", [&"len"], [3.5]) as float, 1.75, 1.0e-9, "variable")
	t.eq(_f("-(2+3)*2"), -10.0, "unary minus")
	t.eq(_f("7 % 4"), 3.0, "modulo")
	t.eq(_f("clamp(9, 0, 5)"), 5.0, "clamp")
	t.near(_f("atan2(1, 1)") as float, PI / 4.0, 1.0e-9, "atan2")
	t.near(_f("deg(PI)") as float, 180.0, 1.0e-9, "deg + PI")
	t.near(_f("rad(180)") as float, PI, 1.0e-9, "rad")
	t.eq(_f("floor(2.7) + ceil(2.2) + round(2.5) + sign(-4)"), 2.0 + 3.0 + 3.0 - 1.0, "rounding functions")
	t.near(_f("fract(2.75)") as float, 0.75, 1.0e-9, "fract")
	t.eq(_f("pow(2, 10)"), 1024.0, "pow")
	t.eq(_f("a and not b", [&"a", &"b"], [true, false]), true, "logic with bools")
	t.eq(_f("a < 2 or b >= 4", [&"a", &"b"], [3.0, 4.0]), true, "comparison + or")
	t.eq(_f("1e2 + .5"), 100.5, "number forms")


func test_string_comparison(t: TestCtx) -> void:
	t.eq(_f("skirt=='modules'", [&"skirt"], ["modules"]), true, "string equal")
	t.eq(_f("skirt!='modules'", [&"skirt"], ["modules"]), false, "string not-equal")
	t.eq(_f("i % 2 == 0 ? 'base' : 'sec'", [&"i"], [3.0]), "sec", "string ternary (colour slot form)")
	t.eq(_f("i % 2 == 0 ? 'base' : 'sec'", [&"i"], [4.0]), "base", "string ternary even")
	t.eq(_f("skirt", [&"skirt"], ["slab"]), "slab", "bare string variable")
	t.eq(_f("p", [&"p"], [Vector3(1, 2, 3)]), Vector3(1, 2, 3), "bare Vector3 variable")


func test_division_by_zero(t: TestCtx) -> void:
	var sc: ViewExpr.Scope = _scope([])
	var e: ViewExpr = ViewExpr.compile("a/b", _scope([&"a", &"b"]), "dz")
	var fr: Array = [0.0, 5.0, 0.0]
	t.eq(e.eval(fr), 0.0, "x/0 = 0")
	t.check(e.warned, "warning flag set")
	var e2: ViewExpr = ViewExpr.compile("5/0", sc, "dz")
	t.eq(e2.eval([0.0]), 0.0, "constant 5/0 = 0")


func test_errors(t: TestCtx) -> void:
	ViewExpr.quiet = true
	var sc: ViewExpr.Scope = _scope([&"a"])
	t.is_null(ViewExpr.compile("a + foo * 2", sc, "unit.x/ops[3]"), "unknown identifier is null")
	t.check(ViewExpr.last_error.contains("foo") and ViewExpr.last_error.contains("column 5"), "error names identifier and column: " + ViewExpr.last_error)
	t.check(ViewExpr.last_error.contains("unit.x/ops[3]"), "error carries ctx")
	t.is_null(ViewExpr.compile("((((((((( 1 )))))))))", sc), "nesting depth 9 rejected")
	t.check(ViewExpr.last_error.contains("nesting"), "depth error text: " + ViewExpr.last_error)
	t.not_null(ViewExpr.compile("(((((((( 1 ))))))))", sc), "nesting depth 8 accepted")
	t.is_null(ViewExpr.compile("min(1)", sc), "arity checked")
	t.is_null(ViewExpr.compile("1 +", sc), "dangling operator")
	t.is_null(ViewExpr.compile("bogus(1)", sc), "unknown function")
	t.is_null(ViewExpr.compile("'abc", sc), "unterminated string")
	ViewExpr.quiet = false


func test_constant_folding(t: TestCtx) -> void:
	var sc: ViewExpr.Scope = _scope([&"x"])
	var e: ViewExpr = ViewExpr.compile("2*3+x", sc)
	t.eq(e.op_count(), 2, "2*3+x compiles to 2 ops")
	t.eq(e.eval([0.0, 4.0]), 10.0, "folded value")
	var c: ViewExpr = ViewExpr.compile("2*3 + sin(0)", sc)
	t.check(c.is_const(), "pure constants fold")
	t.eq(c.eval([0.0, 0.0]), 6.0, "constant value")
	var tern: ViewExpr = ViewExpr.compile("1 > 0 ? x : 9", sc)
	t.eq(tern.op_count(), 1, "constant condition selects the branch at compile time")


func test_rnd_is_deterministic(t: TestCtx) -> void:
	var sc: ViewExpr.Scope = _scope([&"i"])
	var e: ViewExpr = ViewExpr.compile("rnd(i)", sc)
	var a: float = e.eval_float([42.0, 3.0])
	var b: float = e.eval_float([42.0, 3.0])
	var c: float = e.eval_float([43.0, 3.0])
	var d: float = e.eval_float([42.0, 4.0])
	t.eq(a, b, "same (seed, n) -> same value")
	t.ne(a, c, "seed changes the value")
	t.ne(a, d, "n changes the value")
	var lo: float = 1.0
	var hi: float = 0.0
	for i in 500:
		var v: float = e.eval_float([7.0, float(i)])
		lo = minf(lo, v)
		hi = maxf(hi, v)
	t.ge(lo, 0.0, "rnd >= 0")
	t.lt(hi, 1.0, "rnd < 1")
	t.gt(hi - lo, 0.9, "rnd covers the range")


func test_performance(t: TestCtx) -> void:
	var sc: ViewExpr.Scope = _scope([&"a", &"b", &"c"])
	# 20 tokens: (a*2+b)*0.5 - min(c,3)*sqrt(a+1) + lerp(0,10,b)
	var e: ViewExpr = ViewExpr.compile("(a*2+b)*0.5 - min(c,3)*sqrt(a+1) + lerp(0,10,b)", sc, "perf")
	var frame: Array = [0.0, 3.0, 0.25, 4.0]
	var t0: int = Time.get_ticks_usec()
	var acc: float = 0.0
	for i in 10000:
		frame[1] = float(i & 15)
		acc += e.eval_float(frame)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	t.note("10k evals: %.1f ms (acc %.1f)" % [ms, acc])
	t.le(ms, 30.0 * TestCtx.perf_factor(), "10 000 evaluations of a 20-token program in <= 30 ms (x perf_factor)")
