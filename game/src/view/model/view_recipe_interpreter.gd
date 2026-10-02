class_name ViewRecipeInterpreter
extends RefCounted
## Executes a recipe's op list on a ViewMeshBuilder (render spec 5.8.3). Two phases per run(): COMPILE (every expression string
## becomes a ViewExpr bound to frame slots, every op an _Op record; ALL errors are found here, before any geometry exists) and
## EXECUTE. Errors carry the op path (`unit.napc.guardian_tank/ops[14]/for[3]/box`) and abort the build: `error` is non-empty
## afterwards and the builder substitutes a placeholder. A run is a pure function of (recipe, style, seed_base); an instance is
## single-use state, so every build (thread) creates its own interpreter. No engine singletons are touched.
##
## Path scheme: op number i of list L is `<parent>/<L>[i]`; a block op's children live in list `<block name>` (for, then, else,
## mirror_x, push, part, case.<key>, slot.<name>); an op error appends the op name: `id/ops[3]/for[1]/box`.
## Scope: seed (slot 0), extra_vars, params (recipe.params > style.kit > archetype.defaults), derive lets, `let`s, loop
## variables, PI, TAU, true, false. Colour slots accept palette keys, "#rrggbb", "key*1.2", "mix(a,b,t)" or an expression whose
## string result is one of those. Macros come from ViewRecipeMacros (typed argument signatures).

const MAX_FOR: int = 64
const MAX_FOR_NEST: int = 3
const MAX_PRIMS: int = 4000
const MAX_DEPTH: int = 8

enum K {
	BRUSH, AO, BEVEL, JITTER, SEED, BOX, TBOX, EXTRUDE, PRISM, POCKET, LATHE, CYL, FRUSTUM, DOME, WHEEL, TRACK, GREEBLE, SOCKET,
	MEMBER, SCALE, TIER, META, LET, FOR, IF, SWITCH, MIRROR, PUSH, PART, CALL, SEQ,
}

## Argument type letters: n number (or expression), v vec3, w vec2, c colour, s string / expression, M material name,
## K part name, N literal name, P vec2 list, Q vec3 list, R vec4 list (rects), G prism loop, A number list.
## name -> [op kind, type letters, number of required arguments]
const PRIMS: Dictionary = {
	"brush": [K.BRUSH, "cMn", 1], "ao": [K.AO, "n", 1], "bevel": [K.BEVEL, "n", 1], "jitter": [K.JITTER, "n", 1], "seed": [K.SEED, "n", 1],
	"box": [K.BOX, "vvn", 2], "tbox": [K.TBOX, "vwwnwn", 4], "extrude": [K.EXTRUDE, "Pnnn", 3], "prism": [K.PRISM, "GGn", 2],
	"pocket": [K.POCKET, "vvRn", 4], "lathe": [K.LATHE, "vvQnn", 3], "cyl": [K.CYL, "vvnnnn", 3], "frustum": [K.FRUSTUM, "vvnnnn", 4],
	"dome": [K.DOME, "vvnnnn", 4], "wheel": [K.WHEEL, "vnnccnnn", 5], "track": [K.TRACK, "nnQnn", 3],
	"greeble": [K.GREEBLE, "vvvvnnnnnn", 9], "socket": [K.SOCKET, "NvvKv", 3], "member": [K.MEMBER, "nn", 2], "scale": [K.SCALE, "n", 1],
	"tier": [K.TIER, "n", 1], "meta": [K.META, "N?", 2],
}
const BLOCK_KEYS: Array[String] = ["let", "for", "if", "switch", "mirror_x", "push", "part", "call", "slot"]
const BLOCK_ALLOWED: Dictionary = {
	"let": ["let"], "for": ["for", "n", "do"], "if": ["if", "then", "else"], "switch": ["switch", "cases", "default"], "mirror_x": ["mirror_x"],
	"push": ["push", "do"], "part": ["part", "do"], "call": ["call", "args"], "slot": ["slot"],
}
const MATS: Dictionary = {"paint": 0, "metal": 1, "glass": 2, "rubber": 3, "emissive": 4}
const PARTS: Dictionary = {
	"static": 0, "turret": 1, "barrel": 2, "wheel": 3, "track": 4, "rotor": 5, "tail_rotor": 6, "radar": 7, "leg_a": 8, "leg_b": 9,
	"arm_a": 10, "arm_b": 11, "body_bob": 12, "door": 13, "blink": 14, "deploy": 15, "deploy_z": 16, "slide_y": 17, "slide_z": 18,
	"turret1": 19, "barrel1": 20, "turret2": 21, "barrel2": 22, "turret3": 23, "barrel3": 24,
}
const DEFAULT_PALETTE: Dictionary = {
	"base": "#6b7280", "dark": "#33363b", "sec": "#d9d4c5", "acc": "#e07b1a", "metal": "#525450", "rubber": "#121210",
	"glass": "#173340", "light": "#ffd98c", "plate": "#1a1a18", "concrete": "#807d75",
}

# ---------------------------------------------------------------------------------------------- public state
## Non-empty after run() when the recipe failed (first error only): "<op path>: <what>".
var error: String = ""
## Variables injected into the scope before the params (structures: fw, fh, door_cx, ...). name -> float.
var extra_vars: Dictionary = {}
## Value of the reserved `seed` variable (drives rnd(n)); the builder sets it to the recipe seed.
var seed_base: int = 0
var livery_tris: Vector3i = Vector3i.ZERO  ## triangles added by the subfaction livery of the last run()
var style_id: StringName = &""  ## id of the style being built (ViewLivery applies to subfaction ids, which carry a dot)
## Executed primitive ops (macro calls count once), for tests and budgets.
var prims: int = 0
## Meta values written by `meta` ops and recipe / archetype meta: key -> value (also applied to ViewModelInfo where it has a field).
var meta: Dictionary = {}

var _b: ViewMeshBuilder = null
var _r: ViewRecipe = null
var _style: Dictionary = {}
var _pal: Dictionary = {}
var _scope: ViewExpr.Scope = null
var _frame: Array = []
var _what: String = ""


# ---------------------------------------------------------------------------------------------- compiled records
class _Num extends RefCounted:
	var k: float = 0.0
	var e: ViewExpr = null

	func f(fr: Array) -> float:
		if e == null:
			return k
		return e.eval_float(fr)


class _Vec extends RefCounted:
	var n: Array[_Num] = []

	func v3(fr: Array) -> Vector3:
		return Vector3(n[0].f(fr), n[1].f(fr), n[2].f(fr))

	func v2(fr: Array) -> Vector2:
		return Vector2(n[0].f(fr), n[1].f(fr))

	func r4(fr: Array) -> Rect2:
		return Rect2(n[0].f(fr), n[1].f(fr), n[2].f(fr), n[3].f(fr))


class _Col extends RefCounted:
	var k: Color = Color.WHITE
	var e: ViewExpr = null


class _Gen extends RefCounted:
	var lit: Variant = null
	var e: ViewExpr = null
	var items: Array = []  # array-valued meta: _Gen entries
	var is_array: bool = false

	func get_value(fr: Array) -> Variant:
		if is_array:
			var out: Array = []
			for it: Variant in items:
				out.append((it as _Gen).get_value(fr))
			return out
		if e == null:
			return lit
		return e.eval(fr)


class _Loop extends RefCounted:
	var ngon: bool = false
	var c: _Vec = null
	var nums: Array[_Num] = []  # ngon: rx, rz, n, rot
	var pts: Array[_Vec] = []


class _Op extends RefCounted:
	var k: int = 0
	var path: String = ""
	var name: String = ""
	var a: Array = []
	var body: Array = []
	var body2: Array = []
	var slot: int = -1
	var cases: Dictionary = {}
	var extra: Variant = null


# ---------------------------------------------------------------------------------------------- run
func run(r: ViewRecipe, style: Dictionary, b: ViewMeshBuilder) -> void:
	error = ""
	prims = 0
	livery_tris = Vector3i.ZERO
	meta = {}
	ViewExpr.quiet = true  # errors are reported through `error` (with the op path) and logged by the builder on the main thread
	_b = b
	_r = r
	_style = style
	_what = ""
	var arch: ViewRecipe.Archetype = r.arch
	if arch == null:
		_fail("%s" % r.id, "unknown archetype '%s'" % r.archetype)
		return
	_pal = _make_palette(style)
	if error != "":
		return
	_scope = ViewExpr.Scope.new()
	for k: Variant in extra_vars:
		_scope.slot(StringName(str(k)))
	# parameters: recipe.params > style.kit > archetype.defaults
	for k: Variant in r.params:
		if not arch.defaults.has(k):
			_fail("%s/params/%s" % [r.id, k], "unknown parameter (archetype '%s' declares: %s)" % [arch.id, ", ".join(PackedStringArray(arch.defaults.keys()))])
			return
	var kit: Dictionary = style.get("kit", {}) as Dictionary
	var literals: Array = []  # [slot, value]
	var exprs: Array = []  # [slot, ViewExpr]
	for k: Variant in arch.defaults:
		_scope.slot(StringName(str(k)))
	for k: Variant in arch.defaults:
		var def: Variant = arch.defaults[k]
		var val: Variant = def
		if kit.has(k) and _param_fits(def, kit[k], false):
			val = kit[k]
		if r.params.has(k):
			if not _param_fits(def, r.params[k], true):
				_fail("%s/params/%s" % [r.id, k], "expected %s, got %s" % [_type_word(def), str(r.params[k])])
				return
			val = r.params[k]
		var slot: int = _scope.slot(StringName(str(k)))
		if (def is float or def is int) and val is String:
			var e: ViewExpr = _compile(val as String, "%s/params/%s" % [r.id, k])
			if e == null:
				return
			exprs.append([slot, e])
		elif val is float or val is int:
			literals.append([slot, float(val)])
		else:
			literals.append([slot, val])
	# derived lets
	var derive: Array = []  # [slot, _Gen]
	for k: Variant in arch.derive:
		var g: _Gen = _gen(arch.derive[k], "%s/derive/%s" % [r.id, k], true)
		if g == null:
			return
		derive.append([_scope.slot(StringName(str(k))), g])
	# ops
	var ops: Array = _compile_list(arch.ops, "%s/ops" % r.id, 1, 0)
	if error != "":
		return
	var after: Array = _compile_list(r.ops_after, "%s/ops_after" % r.id, 1, 0)
	if error != "":
		return
	var extra_ops: Array = []
	for k: Variant in r.sockets:
		var sd: Variant = r.sockets[k]
		if not (sd is Dictionary):
			_fail("%s/sockets/%s" % [r.id, k], "expected an object {pos, dir, part?}")
			return
		var sk: Array = ["socket", str(k), (sd as Dictionary).get("pos", [0, 0, 0]), (sd as Dictionary).get("dir", [0, 1, 0])]
		if (sd as Dictionary).has("part"):
			sk.append((sd as Dictionary)["part"])
		var so: _Op = _compile_op(sk, "%s/sockets[%s]" % [r.id, k], 1, 0)
		if error != "":
			return
		extra_ops.append(so)
	# frame
	_frame = _scope.make_frame()
	_frame[ViewExpr.SEED_SLOT] = float(seed_base)
	for k: Variant in extra_vars:
		_frame[_scope.slot(StringName(str(k)))] = float(extra_vars[k])
	for lit: Variant in literals:
		_frame[(lit as Array)[0] as int] = (lit as Array)[1]
	for ex: Variant in exprs:
		_frame[(ex as Array)[0] as int] = ((ex as Array)[1] as ViewExpr).eval(_frame)
	for dv: Variant in derive:
		_frame[(dv as Array)[0] as int] = ((dv as Array)[1] as _Gen).get_value(_frame)
	# meta: archetype, then recipe
	for mk: Variant in arch.meta:
		_put_meta(str(mk), arch.meta[mk])
	for mk: Variant in r.meta:
		_put_meta(str(mk), r.meta[mk])
	if error != "":
		return
	_exec(ops)
	_exec(after)
	_exec(extra_ops)
	if error == "":
		livery_tris = ViewLivery.apply(_b, _style, String(style_id), String(arch.id), _pal)  # VQ2A: subfaction flank / wing-tip livery


func ok() -> bool:
	return error == ""


# ---------------------------------------------------------------------------------------------- errors / helpers
func _fail(path: String, msg: String) -> void:
	if error == "":
		error = "%s: %s" % [path, (_what + ": " + msg) if _what != "" else msg]


func _compile(src: String, path: String) -> ViewExpr:
	var e: ViewExpr = ViewExpr.compile(src, _scope, "")
	if e == null:
		_fail(path, ViewExpr.last_error)
	return e


static func _type_word(def: Variant) -> String:
	if def is bool:
		return "a boolean"
	if def is String:
		return "a string"
	return "a number or expression"


static func _param_fits(def: Variant, v: Variant, allow_expr: bool) -> bool:
	if def is bool:
		return v is bool
	if def is String:
		return v is String
	return v is float or v is int or (allow_expr and v is String)


func _make_palette(style: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in DEFAULT_PALETTE:
		out[str(k)] = Color(str(DEFAULT_PALETTE[k]))
	var p: Dictionary = style.get("palette", {}) as Dictionary
	for k: Variant in p:
		var hex: String = str(p[k])
		if not Color.html_is_valid(hex):
			_fail("style.palette.%s" % k, "invalid colour '%s'" % hex)
			continue
		out[str(k)] = Color.html(hex)
	return out


## Palette key, "#rrggbb", "key*f" or "mix(a,b,t)" -> Color; null when the string is none of these.
func _try_color(s: String) -> Variant:
	s = s.strip_edges()
	if _pal.has(s):
		return _pal[s]
	if s.begins_with("#"):
		if Color.html_is_valid(s):
			return Color.html(s)
		return null
	if s.begins_with("mix(") and s.ends_with(")"):
		var parts: PackedStringArray = s.substr(4, s.length() - 5).split(",")
		if parts.size() != 3 or not parts[2].strip_edges().is_valid_float():
			return null
		var ca: Variant = _try_color(parts[0])
		var cb: Variant = _try_color(parts[1])
		if ca == null or cb == null:
			return null
		return (ca as Color).lerp(cb as Color, parts[2].strip_edges().to_float())
	var star: int = s.rfind("*")
	if star > 0 and s.substr(star + 1).strip_edges().is_valid_float():
		var cc: Variant = _try_color(s.substr(0, star))
		if cc == null:
			return null
		var f: float = s.substr(star + 1).strip_edges().to_float()
		var c0: Color = cc as Color
		return Color(clampf(c0.r * f, 0.0, 1.0), clampf(c0.g * f, 0.0, 1.0), clampf(c0.b * f, 0.0, 1.0), 1.0)
	return null


static func _is_word(s: String) -> bool:
	if s.is_empty() or not (s[0] == "_" or (s[0] >= "A" and s[0] <= "Z") or (s[0] >= "a" and s[0] <= "z")):
		return false
	for i in s.length():
		var ch: String = s[i]
		if not (ch == "_" or ch == "." or (ch >= "0" and ch <= "9") or (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z")):
			return false
	return true


# ---------------------------------------------------------------------------------------------- compile: values
func _num(v: Variant, path: String) -> _Num:
	var n: _Num = _Num.new()
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			n.k = float(v)
		TYPE_BOOL:
			n.k = 1.0 if v else 0.0
		TYPE_STRING:
			var e: ViewExpr = _compile(v as String, path)
			if e == null:
				return null
			if e.is_const():
				n.k = e.eval_float([])
			else:
				n.e = e
		_:
			_fail(path, "expected a number or an expression, got %s" % type_string(typeof(v)))
			return null
	return n


func _vec(v: Variant, n: int, path: String) -> _Vec:
	if not (v is Array) or (v as Array).size() != n:
		_fail(path, "expected a vector of %d numbers" % n)
		return null
	var out: _Vec = _Vec.new()
	for x: Variant in v as Array:
		var c: _Num = _num(x, path)
		if c == null:
			return null
		out.n.append(c)
	return out


func _veclist(v: Variant, n: int, path: String) -> Array[_Vec]:
	var out: Array[_Vec] = []
	if not (v is Array):
		_fail(path, "expected a list of %d-vectors" % n)
		return out
	for x: Variant in v as Array:
		var c: _Vec = _vec(x, n, path)
		if c == null:
			return out
		out.append(c)
	return out


func _col(v: Variant, path: String) -> _Col:
	var c: _Col = _Col.new()
	if v is Array and (v as Array).size() == 3:
		var rgb: Array[float] = []
		for x: Variant in v as Array:
			if not (x is float or x is int):
				_fail(path, "colour components must be numbers")
				return null
			rgb.append(float(x))
		c.k = Color(rgb[0], rgb[1], rgb[2])
		return c
	if not (v is String):
		_fail(path, "expected a colour (palette key, #rrggbb, key*f, mix(a,b,t), [r,g,b] or an expression)")
		return null
	var lit: Variant = _try_color(v as String)
	if lit != null:
		c.k = lit as Color
		return c
	c.e = _compile(v as String, path)
	return null if c.e == null else c


## Generic value. `force_expr`: strings are always expressions (derive, if / switch subjects). Otherwise a plain word that is not
## a scope name is a literal string ("brake", "tracked").
func _gen(v: Variant, path: String, force_expr: bool = false) -> _Gen:
	var g: _Gen = _Gen.new()
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			g.lit = float(v)
		TYPE_BOOL:
			g.lit = v
		TYPE_STRING:
			var s: String = v as String
			var lit_word: bool = s.is_empty() or (not force_expr and _is_word(s) and not _scope.has_name(StringName(s)) \
				and s != "true" and s != "false" and s != "PI" and s != "TAU")
			if lit_word:
				g.lit = s
			else:
				g.e = _compile(s, path)
				if g.e == null:
					return null
				if g.e.is_const():
					g.lit = g.e.eval([])
					g.e = null
		TYPE_ARRAY:
			g.is_array = true
			for x: Variant in v as Array:
				var it: _Gen = _gen(x, path, force_expr)
				if it == null:
					return null
				g.items.append(it)
		TYPE_DICTIONARY:
			g.lit = (v as Dictionary).duplicate(true)
		_:
			_fail(path, "unsupported value type %s" % type_string(typeof(v)))
			return null
	return g


func _loop(v: Variant, path: String) -> _Loop:
	var l: _Loop = _Loop.new()
	if v is Array and (v as Array).size() >= 5 and (v as Array)[0] is String and (v as Array)[0] == "ngon":
		var a: Array = v as Array
		l.ngon = true
		l.c = _vec(a[1], 3, path)
		if l.c == null:
			return null
		for i in range(2, a.size()):
			var nn: _Num = _num(a[i], path)
			if nn == null:
				return null
			l.nums.append(nn)
		return l
	l.pts = _veclist(v, 3, path)
	return null if error != "" else l


func _carg(t: String, v: Variant, path: String) -> Variant:
	match t:
		"n":
			return _num(v, path)
		"v":
			return _vec(v, 3, path)
		"w":
			return _vec(v, 2, path)
		"c":
			return _col(v, path)
		"s", "M", "K":
			return _gen(v, path)
		"N":
			if v is String:
				return v
			_fail(path, "expected a name")
			return null
		"P":
			return _veclist(v, 2, path)
		"Q":
			return _veclist(v, 3, path)
		"R":
			return _veclist(v, 4, path)
		"G":
			return _loop(v, path)
		"A":
			var out: Array[_Num] = []
			if not (v is Array):
				_fail(path, "expected a list of numbers")
				return null
			for x: Variant in v as Array:
				var c: _Num = _num(x, path)
				if c == null:
					return null
				out.append(c)
			return out
		"?":
			return _gen(v, path)
	_fail(path, "internal: unknown argument type '%s'" % t)
	return null


# ---------------------------------------------------------------------------------------------- compile: ops
func _compile_list(list: Variant, prefix: String, depth: int, nest: int) -> Array:
	var out: Array = []
	if not (list is Array):
		_fail(prefix, "expected an op array")
		return out
	if depth > MAX_DEPTH:
		_fail(prefix, "op-list depth exceeds %d" % MAX_DEPTH)
		return out
	var arr: Array = list as Array
	for i in arr.size():
		var op: _Op = _compile_op(arr[i], "%s[%d]" % [prefix, i], depth, nest)
		if error != "":
			return out
		if op != null:
			out.append(op)
	return out


func _compile_op(v: Variant, seg: String, depth: int, nest: int) -> _Op:
	_what = ""
	if v is Array:
		return _compile_prim(v as Array, seg)
	if v is Dictionary:
		return _compile_block(v as Dictionary, seg, depth, nest)
	_fail(seg, "an op is an array [name, args...] or an object")
	return null


func _compile_prim(a: Array, seg: String) -> _Op:
	if a.is_empty() or not (a[0] is String):
		_fail(seg, "an op array starts with its name")
		return null
	var name: String = a[0] as String
	var path: String = "%s/%s" % [seg, name]
	if not PRIMS.has(name):
		_fail(path, "unknown op '%s'" % name)
		return null
	var sig: Array = PRIMS[name] as Array
	var types: String = sig[1] as String
	var nreq: int = sig[2] as int
	var nargs: int = a.size() - 1
	if nargs < nreq or (nargs > types.length() and name != "meta"):
		_fail(path, "takes %d..%d arguments, got %d" % [nreq, types.length(), nargs])
		return null
	var op: _Op = _Op.new()
	op.k = sig[0] as int
	op.path = path
	op.name = name
	for i in nargs:
		_what = "argument %d" % (i + 1)
		var c: Variant = _carg(types[mini(i, types.length() - 1)], a[i + 1], path)
		if error != "":
			return null
		op.a.append(c)
	_what = ""
	if op.k == K.SOCKET and op.a.size() > 3:
		var pn: String = ""
		var pg: _Gen = op.a[3] as _Gen
		if pg.e == null:
			pn = str(pg.lit)
		if pn != "" and not PARTS.has(pn):
			_fail(path, "argument 4: unknown part '%s'" % pn)
			return null
	return op


func _compile_block(d: Dictionary, seg: String, depth: int, nest: int) -> _Op:
	var kind: String = ""
	for k: String in BLOCK_KEYS:
		if d.has(k):
			kind = k
			break
	if kind == "":
		_fail(seg, "unknown block (keys: %s)" % ", ".join(PackedStringArray(d.keys())))
		return null
	var path: String = "%s/%s" % [seg, kind]
	var allowed: Array = BLOCK_ALLOWED[kind] as Array
	for k: Variant in d:
		if not allowed.has(k):
			_fail(path, "unexpected key '%s' (a %s block takes: %s)" % [k, kind, ", ".join(PackedStringArray(allowed))])
			return null
	var op: _Op = _Op.new()
	op.path = path
	op.name = kind
	match kind:
		"let":
			op.k = K.LET
			if not (d["let"] is Dictionary):
				_fail(path, "let takes an object {name: expression}")
				return null
			for name: Variant in d["let"] as Dictionary:
				var g: _Gen = _gen((d["let"] as Dictionary)[name], path)
				if g == null:
					return null
				op.a.append([_scope.slot(StringName(str(name))), g])
		"for":
			op.k = K.FOR
			if not (d["for"] is String) or not _is_word(d["for"] as String) or not d.has("n") or not d.has("do"):
				_fail(path, "for needs a variable name, 'n' and 'do'")
				return null
			if nest + 1 > MAX_FOR_NEST:
				_fail(path, "for nesting exceeds %d" % MAX_FOR_NEST)
				return null
			_what = "n"
			var n: _Num = _num(d["n"], path)
			if n == null:
				return null
			if n.e == null and (n.k > MAX_FOR or n.k < 0.0):
				_fail(path, "n = %d is outside 0..%d" % [int(n.k), MAX_FOR])
				return null
			_what = ""
			op.a = [n]
			op.slot = _scope.slot(StringName(d["for"] as String))
			op.body = _compile_list(d["do"], "%s/for" % seg, depth + 1, nest + 1)
		"if":
			op.k = K.IF
			var c: _Gen = _gen(d["if"], path, true)
			if c == null:
				return null
			op.a = [c]
			op.body = _compile_list(d.get("then", []), "%s/then" % seg, depth + 1, nest)
			if d.has("else"):
				op.body2 = _compile_list(d["else"], "%s/else" % seg, depth + 1, nest)
		"switch":
			op.k = K.SWITCH
			var sg: _Gen = _gen(d["switch"], path, true)
			if sg == null:
				return null
			op.a = [sg]
			if not (d.get("cases", {}) is Dictionary):
				_fail(path, "cases must be an object {value: [ops]}")
				return null
			for key: Variant in d.get("cases", {}) as Dictionary:
				op.cases[str(key)] = _compile_list((d["cases"] as Dictionary)[key], "%s/case.%s" % [seg, key], depth + 1, nest)
			if d.has("default"):
				op.body2 = _compile_list(d["default"], "%s/default" % seg, depth + 1, nest)
		"mirror_x":
			op.k = K.MIRROR
			op.body = _compile_list(d["mirror_x"], "%s/mirror_x" % seg, depth + 1, nest)
		"push":
			op.k = K.PUSH
			if not (d["push"] is Dictionary):
				_fail(path, "push takes an object {pos, euler}")
				return null
			var pd: Dictionary = d["push"] as Dictionary
			var pos: _Vec = _vec(pd.get("pos", [0, 0, 0]), 3, path)
			var eul: _Vec = _vec(pd.get("euler", [0, 0, 0]), 3, path)
			if pos == null or eul == null:
				return null
			op.a = [pos, eul]
			op.body = _compile_list(d.get("do", []), "%s/push" % seg, depth + 1, nest)
		"part":
			op.k = K.PART
			if not (d["part"] is Dictionary):
				_fail(path, "part takes an object {kind, pivot, param, extra, trunnion}")
				return null
			var qd: Dictionary = d["part"] as Dictionary
			var kname: String = str(qd.get("kind", ""))
			if not PARTS.has(kname):
				_fail(path, "unknown part kind '%s'" % kname)
				return null
			var pv: _Vec = _vec(qd.get("pivot", [0, 0, 0]), 3, path)
			var pp: _Num = _num(qd.get("param", 0.0), path)
			var px: _Num = _num(qd.get("extra", 0.0), path)
			var pt: _Vec = _vec(qd.get("trunnion", [0, 0]), 2, path)
			if pv == null or pp == null or px == null or pt == null:
				return null
			op.a = [PARTS[kname], pv, pp, px, pt]
			op.body = _compile_list(d.get("do", []), "%s/part" % seg, depth + 1, nest)
		"call":
			op.k = K.CALL
			var mname: String = str(d["call"])
			var msig: Dictionary = ViewRecipeMacros.signature(mname)
			if msig.is_empty():
				_fail(path, "unknown macro '%s'" % mname)
				return null
			var args: Variant = d.get("args", {})
			if not (args is Dictionary):
				_fail(path, "args must be an object")
				return null
			for an: Variant in args as Dictionary:
				if not msig.has(str(an)):
					_fail(path, "macro '%s' has no argument '%s' (takes: %s)" % [mname, an, ", ".join(PackedStringArray(msig.keys()))])
					return null
			op.name = mname
			var compiled: Dictionary = {}
			for an: Variant in msig:
				var spec: Array = msig[an] as Array
				var src: Variant = (args as Dictionary).get(an, spec[1])
				_what = "argument '%s'" % an
				var cv: Variant = _carg(spec[0] as String, src, path)
				if error != "":
					return null
				compiled[str(an)] = [spec[0], cv]
			_what = ""
			op.extra = compiled
		"slot":
			op.k = K.SEQ
			var sname: String = str(d["slot"])
			var list: Variant = _slot_list(sname)
			if list != null:
				op.body = _compile_list(list, "%s/slot.%s" % [seg, sname], depth + 1, nest)
	return op


## recipe.slots[name] > style.slots[name] > arch.slots[name] > nothing.
func _slot_list(name: String) -> Variant:
	if _r.slots.has(name):
		return _r.slots[name]
	var ss: Variant = _style.get("slots", {})
	if ss is Dictionary and (ss as Dictionary).has(name):
		return (ss as Dictionary)[name]
	if _r.arch.slots.has(name):
		return _r.arch.slots[name]
	return null


# ---------------------------------------------------------------------------------------------- execute
func _rt(op: _Op, msg: String) -> void:
	if error == "":
		error = "%s: %s" % [op.path, msg]


func _color_of(c: _Col, op: _Op) -> Color:
	if c.e == null:
		return c.k
	var s: String = str(c.e.eval(_frame))
	var lit: Variant = _try_color(s)
	if lit == null:
		_rt(op, "expression result '%s' is not a colour" % s)
		return Color.MAGENTA
	return lit as Color


func _exec(ops: Array) -> void:
	for o: Variant in ops:
		if error != "":
			return
		_exec_op(o as _Op)


func _f(x: Variant, dflt: float) -> float:
	if x == null:
		return dflt
	return (x as _Num).f(_frame)


func _v3(x: Variant) -> Vector3:
	return (x as _Vec).v3(_frame)


func _exec_op(op: _Op) -> void:
	var a: Array = op.a
	var na: int = a.size()
	match op.k:
		K.BRUSH:
			var team: float = _f(a[2], 0.0) if na > 2 else 0.0
			var mname: String = "paint"
			if na > 1:
				mname = str((a[1] as _Gen).get_value(_frame))
			if not MATS.has(mname):
				_rt(op, "unknown material '%s'" % mname)
				return
			_b.brush(_color_of(a[0] as _Col, op), MATS[mname] as int, team)
		K.AO:
			_b.ao = _f(a[0], 1.0)
		K.BEVEL:
			_b.default_bevel = _f(a[0], 0.0)
		K.JITTER:
			_b.jitter = _f(a[0], 0.0)
		K.SEED:
			var sv: float = _f(a[0], 0.0)
			_b.seed_rng(int(sv))
			_frame[ViewExpr.SEED_SLOT] = sv
		K.BOX:
			_count(op)
			_b.box(_v3(a[0]), _v3(a[1]), _f(a[2] if na > 2 else null, -1.0))
		K.TBOX:
			_count(op)
			var sh: Vector2 = (a[4] as _Vec).v2(_frame) if na > 4 else Vector2.ZERO
			_b.tapered_box(_v3(a[0]), (a[1] as _Vec).v2(_frame), (a[2] as _Vec).v2(_frame), _f(a[3], 0.0), sh, _f(a[5] if na > 5 else null, -1.0))
		K.EXTRUDE:
			_count(op)
			var prof: PackedVector2Array = PackedVector2Array()
			for pv: Variant in a[0] as Array:
				prof.append((pv as _Vec).v2(_frame))
			_b.extrude(prof, _f(a[1], 0.0), _f(a[2], 0.0), _f(a[3] if na > 3 else null, -1.0))
		K.PRISM:
			_count(op)
			var la: PackedVector3Array = _loop_pts(a[0] as _Loop)
			var lb: PackedVector3Array = _loop_pts(a[1] as _Loop)
			if la.size() != lb.size() or la.size() < 3:
				_rt(op, "the two loops need the same number (>= 3) of points, got %d and %d" % [la.size(), lb.size()])
				return
			_b.prism(la, lb, _f(a[2] if na > 2 else null, -1.0))
		K.POCKET:
			_count(op)
			var rects: Array[Rect2] = []
			for rv: Variant in a[2] as Array:
				rects.append((rv as _Vec).r4(_frame))
			_b.pocket_box(_v3(a[0]), _v3(a[1]), rects, _f(a[3], 0.0))
		K.LATHE:
			_count(op)
			var lp: PackedVector3Array = PackedVector3Array()
			for lv: Variant in a[2] as Array:
				lp.append((lv as _Vec).v3(_frame))
			_b.lathe(_v3(a[0]), _v3(a[1]), lp, int(_f(a[3] if na > 3 else null, 12.0)), _f(a[4] if na > 4 else null, 38.0))
		K.CYL:
			_count(op)
			_b.cylinder(_v3(a[0]), _v3(a[1]), _f(a[2], 0.1), int(_f(a[3] if na > 3 else null, 12.0)), _f(a[4] if na > 4 else null, 0.0),
				_f(a[5] if na > 5 else null, 1.0) != 0.0)
		K.FRUSTUM:
			_count(op)
			_b.frustum(_v3(a[0]), _v3(a[1]), _f(a[2], 0.1), _f(a[3], 0.1), int(_f(a[4] if na > 4 else null, 12.0)), _f(a[5] if na > 5 else null, 1.0) != 0.0)
		K.DOME:
			_count(op)
			_b.dome(_v3(a[0]), _v3(a[1]), _f(a[2], 0.1), _f(a[3], 0.1), int(_f(a[4] if na > 4 else null, 12.0)), int(_f(a[5] if na > 5 else null, 4.0)))
		K.WHEEL:
			_count(op)
			_b.wheel(_v3(a[0]), _f(a[1], 0.3), _f(a[2], 0.3), _color_of(a[3] as _Col, op), _color_of(a[4] as _Col, op),
				int(_f(a[5] if na > 5 else null, 2.0)), int(_f(a[6] if na > 6 else null, 14.0)), _f(a[7] if na > 7 else null, 1.0) != 0.0)
		K.TRACK:
			_count(op)
			var circles: Array[Vector3] = []
			for cv: Variant in a[2] as Array:
				circles.append((cv as _Vec).v3(_frame))
			var saved: Array = _save_part()
			_b.set_part(ViewMeshBuilder.Part.TRACK)
			_b.track_belt(_f(a[0], 0.0), _f(a[1], 0.4), circles, _f(a[3] if na > 3 else null, 0.06), int(_f(a[4] if na > 4 else null, 12.0)))
			_restore_part(saved)
		K.GREEBLE:
			_count(op)
			var t0: int = _b.tier
			_b.tier = maxi(t0, 1)
			_b.greebles(_v3(a[0]), _v3(a[1]), _v3(a[2]), _v3(a[3]), int(_f(a[4], 0.0)), _f(a[5], 0.1), _f(a[6], 0.2), _f(a[7], 0.02), _f(a[8], 0.05),
				_f(a[9] if na > 9 else null, 0.25))
			_b.tier = t0
		K.SOCKET:
			var pn: String = ""
			if na > 3:
				pn = str((a[3] as _Gen).get_value(_frame))
				if not PARTS.has(pn):
					_rt(op, "unknown part '%s'" % pn)
					return
			var pivot: Vector3 = _v3(a[4]) if na > 4 else Vector3.ZERO
			_b.socket(StringName(a[0] as String), _v3(a[1]), _v3(a[2]), (PARTS[pn] as int) if pn != "" else 0, pivot)
		K.MEMBER:
			_b.member(int(_f(a[0], 0.0)), int(_f(a[1], 0.0)))
		K.SCALE:
			_b.model_scale *= _f(a[0], 1.0)
		K.TIER:
			_b.tier = clampi(int(_f(a[0], 0.0)), 0, 2)
		K.META:
			_put_meta(a[0] as String, (a[1] as _Gen).get_value(_frame))
		K.LET:
			for pair: Variant in a:
				_frame[(pair as Array)[0] as int] = ((pair as Array)[1] as _Gen).get_value(_frame)
		K.FOR:
			var n: int = int(_f(a[0], 0.0))
			if n < 0 or n > MAX_FOR:
				_rt(op, "n = %d is outside 0..%d" % [n, MAX_FOR])
				return
			for i in n:
				_frame[op.slot] = float(i)
				_exec(op.body)
				if error != "":
					return
		K.IF:
			if _truthy((a[0] as _Gen).get_value(_frame)):
				_exec(op.body)
			else:
				_exec(op.body2)
		K.SWITCH:
			var key: String = _key_of((a[0] as _Gen).get_value(_frame))
			if op.cases.has(key):
				_exec(op.cases[key] as Array)
			else:
				_exec(op.body2)
		K.MIRROR:
			var m: PackedInt32Array = _b.mark()
			_exec(op.body)
			_b.mirror_x(m)
		K.PUSH:
			_b.push(ViewMeshBuilder.xf(_v3(a[0]), _v3(a[1])))
			_exec(op.body)
			_b.pop()
		K.PART:
			var st: Array = _save_part()
			_b.set_part(a[0] as int, _v3(a[1]), _f(a[2], 0.0), _f(a[3], 0.0), (a[4] as _Vec).v2(_frame))
			_exec(op.body)
			_restore_part(st)
		K.CALL:
			_call(op)
		K.SEQ:
			_exec(op.body)


func _count(op: _Op) -> void:
	prims += 1
	if prims > MAX_PRIMS:
		_rt(op, "executed-primitive cap %d exceeded" % MAX_PRIMS)


func _loop_pts(l: _Loop) -> PackedVector3Array:
	if l.ngon:
		var rot: float = l.nums[3].f(_frame) if l.nums.size() > 3 else 0.0
		return ViewMeshBuilder.ngon(l.c.v3(_frame), l.nums[0].f(_frame), l.nums[1].f(_frame), maxi(int(l.nums[2].f(_frame)), 3), rot)
	var out: PackedVector3Array = PackedVector3Array()
	for p: _Vec in l.pts:
		out.append(p.v3(_frame))
	return out


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is String:
		return not (v as String).is_empty()
	return float(v) != 0.0


static func _key_of(v: Variant) -> String:
	if v is float and is_equal_approx(v as float, roundf(v as float)):
		return str(int(v as float))
	return str(v)


func _save_part() -> Array:
	return [_b.part, _b.pivot, _b.part_param, _b.part_extra, _b.trunnion]


func _restore_part(st: Array) -> void:
	_b.part = st[0] as int
	_b.pivot = st[1] as Vector3
	_b.part_param = st[2] as float
	_b.part_extra = st[3] as float
	_b.trunnion = st[4] as Vector2


func _call(op: _Op) -> void:
	_count(op)
	var args: Dictionary = {}
	var spec: Dictionary = op.extra as Dictionary
	for an: Variant in spec:
		var t: String = (spec[an] as Array)[0] as String
		var cv: Variant = (spec[an] as Array)[1]
		match t:
			"n":
				args[an] = (cv as _Num).f(_frame)
			"v":
				args[an] = (cv as _Vec).v3(_frame)
			"w":
				args[an] = (cv as _Vec).v2(_frame)
			"c":
				args[an] = _color_of(cv as _Col, op)
			"s":
				args[an] = str((cv as _Gen).get_value(_frame))
			"A":
				var arr: Array[float] = []
				for x: _Num in cv as Array:
					arr.append(x.f(_frame))
				args[an] = arr
	if error != "":
		return
	# macros must keep brush / part state balanced; the interpreter guarantees it
	var sv: Array = [_b.paint, _b.mat, _b.team_mask, _b.ao, _b.tier, _b.default_bevel]
	var sp: Array = _save_part()
	var err: String = ViewRecipeMacros.run(op.name, _b, args, _pal)
	_b.paint = sv[0] as Color
	_b.mat = sv[1] as int
	_b.team_mask = sv[2] as float
	_b.ao = sv[3] as float
	_b.tier = sv[4] as int
	_b.default_bevel = sv[5] as float
	_restore_part(sp)
	if err != "":
		_rt(op, err)


# ---------------------------------------------------------------------------------------------- meta
func _put_meta(key: String, value: Variant) -> void:
	meta[key] = value
	apply_meta(_b.info(), key, value)


## Writes the recipe meta keys that have a ViewModelInfo field (hover, members, footprint, death, buildup_ticks, spawn_fx).
static func apply_meta(info: ViewModelInfo, key: String, value: Variant) -> void:
	match key:
		"hover":
			info.hover = float(value)
		"members":
			info.members = maxi(int(value), 1)
		"footprint":
			if value is Array and (value as Array).size() >= 2:
				info.footprint = Vector2i(int((value as Array)[0]), int((value as Array)[1]))
		"death":
			if value is Dictionary:
				info.death_kind = StringName(str((value as Dictionary).get("kind", "")))
				info.death_ticks = int((value as Dictionary).get("ticks", 0))
		"buildup_ticks":
			info.buildup_ticks = int(value)
		"spawn_fx":
			info.spawn_fx = StringName(str(value))
