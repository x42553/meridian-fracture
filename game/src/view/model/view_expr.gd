class_name ViewExpr
extends RefCounted
## Expression compiler + evaluator shared by model and fx recipes (render spec 3.5, 5.8.3).
##
## Compiled once per string to RPN with variables bound to frame slots at compile time (no dictionary lookups at run
## time). Grammar: numbers, identifiers (recipe params, lets, loop variables, PI, TAU, true, false), + - * / %, unary -,
## comparisons, `and or not`, ternary `c ? a : b`, string literals in single quotes with == / !=, parentheses.
## Functions: min max abs sqrt sin cos tan atan2 floor ceil round sign fract clamp lerp pow deg rad rnd(n).
## Division (or modulo) by zero yields 0 and sets `warned`. rnd(n) is a deterministic hash of (frame[SEED_SLOT], n) in [0,1).
##
## Programs without string values run on a float stack (fast path); programs with string literals, == / != or a bare
## variable run on a tree-walking Variant evaluator (slower, still allocation-light). An instance keeps a scratch stack:
## it is NOT re-entrant, compile one ViewExpr per thread (a recipe interpreter run owns its expressions).

const SEED_SLOT: int = 0
const MAX_DEPTH: int = 8

# opcodes of the register machine (fast path): regs[d] = regs[a] op regs[b] (c is the third operand of SEL / CLAMP / LERP)
const OP_MUL: int = 0
const OP_ADD: int = 1
const OP_SUB: int = 2
const OP_DIV: int = 3
const OP_MIN: int = 4
const OP_MAX: int = 5
const OP_SQRT: int = 6
const OP_LERP: int = 7
const OP_SIN: int = 8
const OP_COS: int = 9
const OP_ABS: int = 10
const OP_CLAMP: int = 11
const OP_SEL: int = 12
const OP_NEG: int = 13
const OP_MOD: int = 14
const OP_LT: int = 15
const OP_LE: int = 16
const OP_GT: int = 17
const OP_GE: int = 18
const OP_EQ: int = 19
const OP_NE: int = 20
const OP_AND: int = 21
const OP_OR: int = 22
const OP_NOT: int = 23
const OP_FN: int = 24  # rare functions: function id in c

const FN_MIN: int = 0
const FN_MAX: int = 1
const FN_ABS: int = 2
const FN_SQRT: int = 3
const FN_SIN: int = 4
const FN_COS: int = 5
const FN_TAN: int = 6
const FN_ATAN2: int = 7
const FN_FLOOR: int = 8
const FN_CEIL: int = 9
const FN_ROUND: int = 10
const FN_SIGN: int = 11
const FN_FRACT: int = 12
const FN_CLAMP: int = 13
const FN_LERP: int = 14
const FN_POW: int = 15
const FN_DEG: int = 16
const FN_RAD: int = 17
const FN_RND: int = 18

## name -> [function id, arity]
const FUNCS: Dictionary = {
	"min": [FN_MIN, 2], "max": [FN_MAX, 2], "abs": [FN_ABS, 1], "sqrt": [FN_SQRT, 1], "sin": [FN_SIN, 1], "cos": [FN_COS, 1],
	"tan": [FN_TAN, 1], "atan2": [FN_ATAN2, 2], "floor": [FN_FLOOR, 1], "ceil": [FN_CEIL, 1], "round": [FN_ROUND, 1],
	"sign": [FN_SIGN, 1], "fract": [FN_FRACT, 1], "clamp": [FN_CLAMP, 3], "lerp": [FN_LERP, 3], "pow": [FN_POW, 2],
	"deg": [FN_DEG, 1], "rad": [FN_RAD, 1], "rnd": [FN_RND, 1],
}

## Set true to keep compile errors out of the engine log (tests); `last_error` is always filled.
static var quiet: bool = false
static var last_error: String = ""  ## written from model-build worker threads: always under `_err_lock`
static var _err_lock: Mutex = Mutex.new()

## Set by eval / eval_float when a division or modulo by zero produced 0.
var warned: bool = false

var _code: PackedInt32Array = PackedInt32Array()
var _rd: PackedInt32Array = PackedInt32Array()
var _ra: PackedInt32Array = PackedInt32Array()
var _rb: PackedInt32Array = PackedInt32Array()
var _rc: PackedInt32Array = PackedInt32Array()
var _regs: PackedFloat64Array = PackedFloat64Array()  # [used variables | constants | temporaries]
var _used: PackedInt32Array = PackedInt32Array()  # frame slot of each variable register
var _kreg: Dictionary = {}  # constant value -> register (compile time only)
var _kbase: int = 0
var _tbase: int = 0
var _tcur: int = 0
var _tmax: int = 0
var _ops: int = 0
var _result: int = 0
var _generic: bool = false
var _ast: Array = []
var _const: bool = false
var _const_val: Variant = 0.0
var _bool_result: bool = false
var _src: String = ""


## Variable slots of one expression frame. Slot 0 is the reserved `seed` (rnd() input).
class Scope extends RefCounted:
	var _slots: Dictionary = {&"seed": 0}
	var _names: Array[StringName] = [&"seed"]

	func slot(name: StringName) -> int:
		if _slots.has(name):
			return _slots[name] as int
		var i: int = _names.size()
		_slots[name] = i
		_names.append(name)
		return i

	func has_name(name: StringName) -> bool:
		return _slots.has(name)

	func size() -> int:
		return _names.size()

	## A frame with every slot 0.0; the caller fills the slots it declared.
	func make_frame() -> Array:
		var f: Array = []
		f.resize(_names.size())
		f.fill(0.0)
		return f


# ---------------------------------------------------------------------------------------------- compile
static func compile(src: String, scope: Scope, ctx: String = "") -> ViewExpr:
	var p: _Parser = _Parser.new()
	p.src = src
	p.scope = scope
	if not p.tokenize():
		return _fail(ctx, src, p.error)
	var ast: Variant = p.parse_all()
	if p.error != "":
		return _fail(ctx, src, p.error)
	var e: ViewExpr = ViewExpr.new()
	e._src = src
	var folded: Array = _fold(ast as Array)
	e._ast = folded
	e._bool_result = _is_bool(folded)
	if folded[0] == "k":
		e._const = true
		e._const_val = folded[1]
	e._generic = _needs_generic(folded)
	e._ops = _count_ops(folded)
	if not e._generic:
		e._emit_program(folded)
	return e


static func _fail(ctx: String, src: String, msg: String) -> ViewExpr:
	var text: String = "ViewExpr%s: %s in \"%s\"" % [("[" + ctx + "]") if ctx != "" else "", msg, src]
	_err_lock.lock()
	last_error = text
	_err_lock.unlock()
	if not quiet:
		Log.error("view", text)
	return null


static func _is_bool(n: Array) -> bool:
	match n[0]:
		"k":
			return n[1] is bool
		"bin":
			return ["<", "<=", ">", ">=", "==", "!=", "and", "or"].has(n[1])
		"un":
			return n[1] == "not"
		"tern":
			return _is_bool(n[2] as Array) and _is_bool(n[3] as Array)
	return false


static func _needs_generic(n: Array) -> bool:
	match n[0]:
		"k":
			return n[1] is String
		"var":
			return true  # a bare variable may hold a String or Vector3: return the frame value untouched
		_:
			return _tree_generic(n)


static func _tree_generic(n: Array) -> bool:
	match n[0]:
		"k":
			return n[1] is String
		"var":
			return false
		"bin":
			if n[1] == "==" or n[1] == "!=":
				return true
			return _tree_generic(n[2] as Array) or _tree_generic(n[3] as Array)
		"un":
			return _tree_generic(n[2] as Array)
		"call":
			for a: Variant in n[2] as Array:
				if _tree_generic(a as Array):
					return true
			return false
		"tern":
			return _tree_generic(n[1] as Array) or _tree_generic(n[2] as Array) or _tree_generic(n[3] as Array)
	return false


static func _num(v: Variant) -> float:
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)


# constant folding: returns a (possibly new) node
static func _fold(n: Array) -> Array:
	match n[0]:
		"bin":
			var a: Array = _fold(n[2] as Array)
			var b: Array = _fold(n[3] as Array)
			if a[0] == "k" and b[0] == "k":
				var tmp: ViewExpr = ViewExpr.new()
				return ["k", tmp._binary(n[1] as String, a[1], b[1])]
			return ["bin", n[1], a, b]
		"un":
			var a: Array = _fold(n[2] as Array)
			if a[0] == "k":
				var tmp: ViewExpr = ViewExpr.new()
				return ["k", tmp._unary(n[1] as String, a[1])]
			return ["un", n[1], a]
		"call":
			var args: Array = []
			var all_k: bool = true
			for x: Variant in n[2] as Array:
				var f: Array = _fold(x as Array)
				args.append(f)
				if f[0] != "k":
					all_k = false
			if all_k and n[1] != FN_RND:
				var vals: Array = []
				for f: Variant in args:
					vals.append((f as Array)[1])
				var tmp: ViewExpr = ViewExpr.new()
				return ["k", tmp._call_fn(n[1] as int, vals, null)]
			return ["call", n[1], args]
		"tern":
			var c: Array = _fold(n[1] as Array)
			var a: Array = _fold(n[2] as Array)
			var b: Array = _fold(n[3] as Array)
			if c[0] == "k":
				return a if _truthy(c[1]) else b
			return ["tern", c, a, b]
	return n


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is String:
		return not (v as String).is_empty()
	return float(v) != 0.0


static func _count_ops(n: Array) -> int:
	match n[0]:
		"k":
			return 0
		"var":
			return 1
		"bin":
			return 1 + _count_ops(n[2] as Array) + _count_ops(n[3] as Array)
		"un":
			return 1 + _count_ops(n[2] as Array)
		"call":
			var c: int = 1
			for a: Variant in n[2] as Array:
				c += _count_ops(a as Array)
			return c
		"tern":
			return 1 + _count_ops(n[1] as Array) + _count_ops(n[2] as Array) + _count_ops(n[3] as Array)
	return 0


# ---------------------------------------------------------------------------------------------- register program
func _collect(n: Array, vars: Dictionary, consts: Dictionary) -> void:
	match n[0]:
		"k":
			consts[_num(n[1])] = true
		"var":
			vars[n[1] as int] = true
		"bin":
			_collect(n[2] as Array, vars, consts)
			_collect(n[3] as Array, vars, consts)
		"un":
			_collect(n[2] as Array, vars, consts)
		"call":
			for a: Variant in n[2] as Array:
				_collect(a as Array, vars, consts)
		"tern":
			_collect(n[1] as Array, vars, consts)
			_collect(n[2] as Array, vars, consts)
			_collect(n[3] as Array, vars, consts)


func _emit_program(n: Array) -> void:
	var vars: Dictionary = {}
	var consts: Dictionary = {}
	_collect(n, vars, consts)
	var slots: Array = vars.keys()
	slots.sort()
	_used = PackedInt32Array(slots)
	var kvals: Array = consts.keys()
	kvals.sort()
	_kbase = _used.size()
	_tbase = _kbase + kvals.size()
	_regs.resize(_tbase + 1)
	for i in kvals.size():
		_kreg[kvals[i]] = _kbase + i
		_regs[_kbase + i] = kvals[i] as float
	_result = _gen(n)
	_regs.resize(_tbase + _tmax + 1)
	_kreg.clear()


func _alloc() -> int:
	var r: int = _tbase + _tcur
	_tcur += 1
	_tmax = maxi(_tmax, _tcur)
	return r


func _release(r: int) -> void:
	if r >= _tbase:
		_tcur -= 1


func _emit(op: int, d: int, a: int, b: int = 0, c: int = 0) -> void:
	_code.append(op)
	_rd.append(d)
	_ra.append(a)
	_rb.append(b)
	_rc.append(c)


## Generates code for a node and returns the register holding its value (a variable / constant register for leaves).
func _gen(n: Array) -> int:
	match n[0]:
		"k":
			return _kreg[_num(n[1])] as int
		"var":
			return _used.find(n[1] as int)
		"un":
			var a: int = _gen(n[2] as Array)
			_release(a)
			var d: int = _alloc()
			_emit(OP_NEG if n[1] == "-" else OP_NOT, d, a)
			return d
		"tern":
			var c0: int = _gen(n[1] as Array)
			var a1: int = _gen(n[2] as Array)
			var b1: int = _gen(n[3] as Array)
			_release(b1)
			_release(a1)
			_release(c0)
			var d1: int = _alloc()
			_emit(OP_SEL, d1, c0, a1, b1)
			return d1
		"call":
			var regs: Array = []
			for x: Variant in n[2] as Array:
				regs.append(_gen(x as Array))
			for i in range(regs.size() - 1, -1, -1):
				_release(regs[i] as int)
			var d2: int = _alloc()
			var ra: int = regs[0] as int
			var rb: int = regs[1] as int if regs.size() > 1 else 0
			var rc: int = regs[2] as int if regs.size() > 2 else 0
			match n[1]:
				FN_MIN:
					_emit(OP_MIN, d2, ra, rb)
				FN_MAX:
					_emit(OP_MAX, d2, ra, rb)
				FN_SQRT:
					_emit(OP_SQRT, d2, ra)
				FN_SIN:
					_emit(OP_SIN, d2, ra)
				FN_COS:
					_emit(OP_COS, d2, ra)
				FN_ABS:
					_emit(OP_ABS, d2, ra)
				FN_CLAMP:
					_emit(OP_CLAMP, d2, ra, rb, rc)
				FN_LERP:
					_emit(OP_LERP, d2, ra, rb, rc)
				_:
					_emit(OP_FN, d2, ra, rb, n[1] as int)
			return d2
		"bin":
			var l: int = _gen(n[2] as Array)
			var r: int = _gen(n[3] as Array)
			_release(r)
			_release(l)
			var d3: int = _alloc()
			_emit({"+": OP_ADD, "-": OP_SUB, "*": OP_MUL, "/": OP_DIV, "%": OP_MOD, "<": OP_LT, "<=": OP_LE, ">": OP_GT,
				">=": OP_GE, "==": OP_EQ, "!=": OP_NE, "and": OP_AND, "or": OP_OR}[n[1]] as int, d3, l, r)
			return d3
	return 0


## Number of operations: variable loads plus operators / functions / selects (constants are free after folding).
func op_count() -> int:
	return _ops


func is_const() -> bool:
	return _const


func is_bool() -> bool:
	return _bool_result


# ---------------------------------------------------------------------------------------------- evaluation
func eval(frame: Array) -> Variant:
	if _const:
		return _const_val
	if _generic:
		return _ev(_ast, frame)
	var r: float = _run(frame)
	if _bool_result:
		return r != 0.0
	return r


func eval_float(frame: Array) -> float:
	if _const:
		return _num(_const_val)
	if _generic:
		return _num(_ev(_ast, frame))
	return _run(frame)


func eval_bool(frame: Array) -> bool:
	return _truthy(eval(frame))


func _run(frame: Array) -> float:
	var r: PackedFloat64Array = _regs
	var used: PackedInt32Array = _used
	for i in used.size():
		var v: Variant = frame[used[i]]
		r[i] = v if v is float else _num(v)
	var code: PackedInt32Array = _code
	var rd: PackedInt32Array = _rd
	var ra: PackedInt32Array = _ra
	var rb: PackedInt32Array = _rb
	var n: int = code.size()
	var pc: int = 0
	while pc < n:
		var op: int = code[pc]
		if op == OP_MUL:
			r[rd[pc]] = r[ra[pc]] * r[rb[pc]]
		elif op == OP_ADD:
			r[rd[pc]] = r[ra[pc]] + r[rb[pc]]
		elif op == OP_SUB:
			r[rd[pc]] = r[ra[pc]] - r[rb[pc]]
		elif op == OP_MIN:
			r[rd[pc]] = minf(r[ra[pc]], r[rb[pc]])
		elif op == OP_MAX:
			r[rd[pc]] = maxf(r[ra[pc]], r[rb[pc]])
		elif op == OP_SQRT:
			r[rd[pc]] = sqrt(maxf(r[ra[pc]], 0.0))
		elif op == OP_LERP:
			var x: float = r[ra[pc]]
			r[rd[pc]] = x + (r[rb[pc]] - x) * r[_rc[pc]]
		elif op == OP_DIV:
			var den: float = r[rb[pc]]
			if den == 0.0:
				warned = true
				r[rd[pc]] = 0.0
			else:
				r[rd[pc]] = r[ra[pc]] / den
		elif op == OP_SIN:
			r[rd[pc]] = sin(r[ra[pc]])
		elif op == OP_COS:
			r[rd[pc]] = cos(r[ra[pc]])
		elif op == OP_ABS:
			r[rd[pc]] = absf(r[ra[pc]])
		elif op == OP_CLAMP:
			r[rd[pc]] = clampf(r[ra[pc]], r[rb[pc]], r[_rc[pc]])
		elif op == OP_SEL:
			r[rd[pc]] = r[rb[pc]] if r[ra[pc]] != 0.0 else r[_rc[pc]]
		elif op == OP_NEG:
			r[rd[pc]] = -r[ra[pc]]
		elif op == OP_MOD:
			var m: float = r[rb[pc]]
			if m == 0.0:
				warned = true
				r[rd[pc]] = 0.0
			else:
				r[rd[pc]] = fmod(r[ra[pc]], m)
		elif op == OP_LT:
			r[rd[pc]] = 1.0 if r[ra[pc]] < r[rb[pc]] else 0.0
		elif op == OP_LE:
			r[rd[pc]] = 1.0 if r[ra[pc]] <= r[rb[pc]] else 0.0
		elif op == OP_GT:
			r[rd[pc]] = 1.0 if r[ra[pc]] > r[rb[pc]] else 0.0
		elif op == OP_GE:
			r[rd[pc]] = 1.0 if r[ra[pc]] >= r[rb[pc]] else 0.0
		elif op == OP_EQ:
			r[rd[pc]] = 1.0 if r[ra[pc]] == r[rb[pc]] else 0.0
		elif op == OP_NE:
			r[rd[pc]] = 1.0 if r[ra[pc]] != r[rb[pc]] else 0.0
		elif op == OP_AND:
			r[rd[pc]] = 1.0 if (r[ra[pc]] != 0.0 and r[rb[pc]] != 0.0) else 0.0
		elif op == OP_OR:
			r[rd[pc]] = 1.0 if (r[ra[pc]] != 0.0 or r[rb[pc]] != 0.0) else 0.0
		elif op == OP_NOT:
			r[rd[pc]] = 1.0 if r[ra[pc]] == 0.0 else 0.0
		else:
			r[rd[pc]] = _rare(_rc[pc], r[ra[pc]], r[rb[pc]], int(frame[SEED_SLOT]))
		pc += 1
	return r[_result]


func _rare(fn: int, a: float, b: float, seed_v: int) -> float:
	match fn:
		FN_TAN:
			return tan(a)
		FN_ATAN2:
			return atan2(a, b)
		FN_FLOOR:
			return floor(a)
		FN_CEIL:
			return ceil(a)
		FN_ROUND:
			return round(a)
		FN_SIGN:
			return signf(a)
		FN_FRACT:
			return a - floor(a)
		FN_POW:
			return pow(a, b)
		FN_DEG:
			return rad_to_deg(a)
		FN_RAD:
			return deg_to_rad(a)
		FN_RND:
			return _rnd(seed_v, int(floor(a)))
	return 0.0


## Deterministic hash of (seed, n) in [0, 1): two rounds of a 32-bit integer mix, no engine RNG.
static func _rnd(seed_v: int, n: int) -> float:
	var h: int = (seed_v * 0x9E3779B1 + n * 0x85EBCA6B + 0x165667B1) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	h = ((h ^ (h >> 12)) * 0x297A2D39) & 0xFFFFFFFF
	h = h ^ (h >> 15)
	return float(h & 0xFFFFFF) / 16777216.0


# generic (Variant) tree-walking path
func _ev(n: Array, frame: Array) -> Variant:
	match n[0]:
		"k":
			return n[1]
		"var":
			return frame[n[1] as int]
		"un":
			return _unary(n[1] as String, _ev(n[2] as Array, frame))
		"bin":
			var op: String = n[1]
			if op == "and":
				return _truthy(_ev(n[2] as Array, frame)) and _truthy(_ev(n[3] as Array, frame))
			if op == "or":
				return _truthy(_ev(n[2] as Array, frame)) or _truthy(_ev(n[3] as Array, frame))
			return _binary(op, _ev(n[2] as Array, frame), _ev(n[3] as Array, frame))
		"tern":
			return _ev(n[2] as Array, frame) if _truthy(_ev(n[1] as Array, frame)) else _ev(n[3] as Array, frame)
		"call":
			var vals: Array = []
			for a: Variant in n[2] as Array:
				vals.append(_ev(a as Array, frame))
			return _call_fn(n[1] as int, vals, frame)
	return 0.0


func _unary(op: String, v: Variant) -> Variant:
	if op == "not":
		return not _truthy(v)
	return -_num(v)


func _binary(op: String, a: Variant, b: Variant) -> Variant:
	if op == "==" or op == "!=":
		var eq: bool
		if (a is String) or (b is String):
			eq = str(a) == str(b) if ((a is String) and (b is String)) else false
		else:
			eq = _num(a) == _num(b)
		return eq if op == "==" else not eq
	if op == "and":
		return _truthy(a) and _truthy(b)
	if op == "or":
		return _truthy(a) or _truthy(b)
	var x: float = _num(a)
	var y: float = _num(b)
	match op:
		"+":
			return x + y
		"-":
			return x - y
		"*":
			return x * y
		"/":
			if y == 0.0:
				warned = true
				return 0.0
			return x / y
		"%":
			if y == 0.0:
				warned = true
				return 0.0
			return fmod(x, y)
		"<":
			return x < y
		"<=":
			return x <= y
		">":
			return x > y
		">=":
			return x >= y
	return 0.0


func _call_fn(fn: int, v: Array, frame: Variant) -> Variant:
	var a: float = _num(v[0])
	var b: float = _num(v[1]) if v.size() > 1 else 0.0
	var c: float = _num(v[2]) if v.size() > 2 else 0.0
	match fn:
		FN_MIN:
			return minf(a, b)
		FN_MAX:
			return maxf(a, b)
		FN_ABS:
			return absf(a)
		FN_SQRT:
			return sqrt(maxf(a, 0.0))
		FN_SIN:
			return sin(a)
		FN_COS:
			return cos(a)
		FN_TAN:
			return tan(a)
		FN_ATAN2:
			return atan2(a, b)
		FN_FLOOR:
			return floor(a)
		FN_CEIL:
			return ceil(a)
		FN_ROUND:
			return round(a)
		FN_SIGN:
			return signf(a)
		FN_FRACT:
			return a - floor(a)
		FN_CLAMP:
			return clampf(a, b, c)
		FN_LERP:
			return a + (b - a) * c
		FN_POW:
			return pow(a, b)
		FN_DEG:
			return rad_to_deg(a)
		FN_RAD:
			return deg_to_rad(a)
		FN_RND:
			var sv: int = int((frame as Array)[SEED_SLOT]) if frame != null else 0
			return _rnd(sv, int(floor(a)))
	return 0.0


# ---------------------------------------------------------------------------------------------- parser
class _Parser extends RefCounted:
	var src: String = ""
	var scope: Scope = null
	var error: String = ""
	var toks: Array = []  # [kind, value, column]; kinds: n num, i ident, s string, o operator, e end
	var pos: int = 0
	var depth: int = 0

	func tokenize() -> bool:
		var i: int = 0
		var n: int = src.length()
		while i < n:
			var ch: String = src[i]
			if ch == " " or ch == "\t":
				i += 1
				continue
			var col: int = i + 1
			if _is_digit(ch) or (ch == "." and i + 1 < n and _is_digit(src[i + 1])):
				var j: int = i
				while j < n and (_is_digit(src[j]) or src[j] == "."):
					j += 1
				if j < n and (src[j] == "e" or src[j] == "E"):
					var k: int = j + 1
					if k < n and (src[k] == "+" or src[k] == "-"):
						k += 1
					if k < n and _is_digit(src[k]):
						while k < n and _is_digit(src[k]):
							k += 1
						j = k
				toks.append(["n", src.substr(i, j - i).to_float(), col])
				i = j
			elif _is_alpha(ch):
				var j2: int = i
				while j2 < n and (_is_alpha(src[j2]) or _is_digit(src[j2])):
					j2 += 1
				toks.append(["i", src.substr(i, j2 - i), col])
				i = j2
			elif ch == "'":
				var j3: int = src.find("'", i + 1)
				if j3 < 0:
					error = "unterminated string at column %d" % col
					return false
				toks.append(["s", src.substr(i + 1, j3 - i - 1), col])
				i = j3 + 1
			else:
				var two: String = src.substr(i, 2)
				if two == "==" or two == "!=" or two == "<=" or two == ">=":
					toks.append(["o", two, col])
					i += 2
				elif "+-*/%()<>?:,".contains(ch):
					toks.append(["o", ch, col])
					i += 1
				else:
					error = "unexpected character '%s' at column %d" % [ch, col]
					return false
		toks.append(["e", "", n + 1])
		return true

	static func _is_digit(ch: String) -> bool:
		return ch >= "0" and ch <= "9"

	static func _is_alpha(ch: String) -> bool:
		return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"

	func parse_all() -> Variant:
		if toks.size() == 1:
			error = "empty expression"
			return null
		var n: Variant = _ternary()
		if error != "":
			return null
		if (toks[pos] as Array)[0] != "e":
			error = "unexpected '%s' at column %d" % [str((toks[pos] as Array)[1]), (toks[pos] as Array)[2] as int]
			return null
		return n

	func _peek_is(v: String) -> bool:
		var t: Array = toks[pos] as Array
		return (t[0] == "o" or t[0] == "i") and t[1] == v

	func _eat(v: String) -> bool:
		if _peek_is(v):
			pos += 1
			return true
		return false

	func _enter() -> bool:
		depth += 1
		if depth > ViewExpr.MAX_DEPTH:
			error = "nesting depth %d exceeds %d at column %d" % [depth, ViewExpr.MAX_DEPTH, (toks[pos] as Array)[2] as int]
			return false
		return true

	func _ternary() -> Variant:
		var c: Variant = _or()
		if error != "":
			return null
		if _eat("?"):
			if not _enter():
				return null
			var a: Variant = _ternary()
			if error != "":
				return null
			if not _eat(":"):
				error = "expected ':' at column %d" % ((toks[pos] as Array)[2] as int)
				return null
			var b: Variant = _ternary()
			depth -= 1
			if error != "":
				return null
			return ["tern", c, a, b]
		return c

	func _or() -> Variant:
		var l: Variant = _and()
		while error == "" and _peek_is("or"):
			pos += 1
			var r: Variant = _and()
			if error != "":
				return null
			l = ["bin", "or", l, r]
		return l

	func _and() -> Variant:
		var l: Variant = _not()
		while error == "" and _peek_is("and"):
			pos += 1
			var r: Variant = _not()
			if error != "":
				return null
			l = ["bin", "and", l, r]
		return l

	func _not() -> Variant:
		if _peek_is("not"):
			pos += 1
			if not _enter():
				return null
			var v: Variant = _not()
			depth -= 1
			if error != "":
				return null
			return ["un", "not", v]
		return _cmp()

	func _cmp() -> Variant:
		var l: Variant = _add()
		while error == "":
			var t: Array = toks[pos] as Array
			if t[0] == "o" and ["==", "!=", "<", "<=", ">", ">="].has(t[1]):
				pos += 1
				var r: Variant = _add()
				if error != "":
					return null
				l = ["bin", t[1], l, r]
			else:
				break
		return l

	func _add() -> Variant:
		var l: Variant = _mul()
		while error == "":
			var t: Array = toks[pos] as Array
			if t[0] == "o" and (t[1] == "+" or t[1] == "-"):
				pos += 1
				var r: Variant = _mul()
				if error != "":
					return null
				l = ["bin", t[1], l, r]
			else:
				break
		return l

	func _mul() -> Variant:
		var l: Variant = _unary()
		while error == "":
			var t: Array = toks[pos] as Array
			if t[0] == "o" and (t[1] == "*" or t[1] == "/" or t[1] == "%"):
				pos += 1
				var r: Variant = _unary()
				if error != "":
					return null
				l = ["bin", t[1], l, r]
			else:
				break
		return l

	func _unary() -> Variant:
		if _peek_is("-"):
			pos += 1
			var v: Variant = _unary()
			if error != "":
				return null
			return ["un", "-", v]
		if _peek_is("+"):
			pos += 1
			return _unary()
		return _primary()

	func _primary() -> Variant:
		var t: Array = toks[pos] as Array
		var col: int = t[2] as int
		match t[0]:
			"n":
				pos += 1
				return ["k", t[1]]
			"s":
				pos += 1
				return ["k", t[1]]
			"o":
				if t[1] == "(":
					pos += 1
					if not _enter():
						return null
					var v: Variant = _ternary()
					depth -= 1
					if error != "":
						return null
					if not _eat(")"):
						error = "expected ')' at column %d" % ((toks[pos] as Array)[2] as int)
						return null
					return v
				error = "unexpected '%s' at column %d" % [t[1], col]
				return null
			"i":
				pos += 1
				var name: String = t[1]
				if _peek_is("("):
					return _call(name, col)
				match name:
					"PI":
						return ["k", PI]
					"TAU":
						return ["k", TAU]
					"true":
						return ["k", true]
					"false":
						return ["k", false]
				if scope != null and scope.has_name(StringName(name)):
					return ["var", scope.slot(StringName(name))]
				error = "unknown identifier '%s' at column %d" % [name, col]
				return null
		error = "unexpected end of expression at column %d" % col
		return null

	func _call(name: String, col: int) -> Variant:
		if not ViewExpr.FUNCS.has(name):
			error = "unknown function '%s' at column %d" % [name, col]
			return null
		var spec: Array = ViewExpr.FUNCS[name] as Array
		pos += 1  # (
		if not _enter():
			return null
		var args: Array = []
		if not _peek_is(")"):
			while true:
				var a: Variant = _ternary()
				if error != "":
					return null
				args.append(a)
				if not _eat(","):
					break
		depth -= 1
		if not _eat(")"):
			error = "expected ')' at column %d" % ((toks[pos] as Array)[2] as int)
			return null
		if args.size() != (spec[1] as int):
			error = "function '%s' takes %d argument(s), got %d at column %d" % [name, spec[1] as int, args.size(), col]
			return null
		return ["call", spec[0], args]
