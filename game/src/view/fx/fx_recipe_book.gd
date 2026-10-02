class_name FxRecipeBook
extends RefCounted
## Loads, compiles and interprets `fx.json` (render spec 7.5, 3.6): data-driven composite effects made of layers.
##
## COMPILE (load_file / load_dict): every expression string becomes a ViewExpr bound to frame slots, every layer a Layer record
## with constants pre-filled, every reference (`fx`, `loop`, `native`, batch names) is checked, `extends` is resolved and
## cycles are rejected. ALL errors are collected with the layer path (`expl_small/layers[3]/size: ...`) and the offending
## effect is not registered. RUN (run): the layer list is interpreted against an FxManager; a composite costs a few tens of
## microseconds (measured by tests/view/test_fx_recipes.gd, limit 100 us).
##
## Effect: {class, kind, radius, scale, min_dist, vars, layers, extends, template, meta}. Layer keys (all accept `when`
## (expression, skip if false), `delay` (seconds; > 0 defers the layer via FxManager.schedule), and the position keys `at`
## ("a" | "b"), `along` (metres from the anchor along dir(a->b)), `off` ([x, y, z] added last)):
##   sprites {batch,size,life,param=1,pal=0}   puff {batch,size,life,alpha=1}   ring {batch,radius,life,pal=0}
##   wake {length,width,life=4}   dome {radius,life,mode=0}   column {batch,radius,height,life}
##   ribbon {batch,to,to_off,life,width,tail=0,flight,linger=0,arc_h=0,pal=0}   tracer {to,to_off,speed,tail,width,pal=0,arc_h=0}
##   trail {batch=trail,to,to_off,flight,linger,width,arc_h=0}   cone {length,width,life,dir="fwd"|"back"}
##   beam|rail|shimmer {to,to_off,life,width}   bolt {to,to_off,life,width,arc_h}   light {color:[r,g,b],energy,range,life}
##   scorch {radius,life,hot=0}   shake {amount}   fx {id,scale=1,b_at="b",b_off,inline=false}   loop {id,interval,duration,scale=1,b_at,b_off}
##   for {var,n,do}   if {if,then,else}   let {name,value}   native {name,args}
## Expression scope: seed, s, dist, ax..az, bx..bz (anchors), dx..dz (unit a->b), flight (= dist / speed when the effect has a
## `speed` var), then the effect's vars in order, loop variables and lets; functions of ViewExpr plus rand(), randr(lo, hi),
## rsq() (fresh on every evaluation, presentation-only RNG).

const SCHEMA: String = "meridian.fx/1"
const MAX_FOR: int = 64
const MAX_RUN_DEPTH: int = 8

enum Op {
	SPRITES, PUFF, RING, WAKE, DOME, COLUMN, RIBBON, TRACER, TRAIL, CONE, BEAM, RAIL, SHIMMER, BOLT, LIGHT, SCORCH, SHAKE, FX,
	LOOP, FOR, IF, LET, NATIVE,
}

# value slots of every layer (Layer.v / Layer.ex): common first, op arguments from K_ARG
const K_WHEN: int = 0
const K_DELAY: int = 1
const K_ALONG: int = 2
const K_OFF: int = 3  # 3, 4, 5
const K_BOFF: int = 6  # 6, 7, 8: end / child-b offset
const K_ARG: int = 9

# fixed frame slots (declared in this order in every effect scope; slot 0 is ViewExpr's `seed`)
const F_S: int = 1
const F_DIST: int = 2
const F_AX: int = 3
const F_BX: int = 6
const F_DX: int = 9
const F_FLIGHT: int = 12

const COMMON_KEYS: Array[String] = ["op", "when", "delay", "at", "along", "off"]

## op name -> [Op, batch kind ("" none), numeric args [[key, default (null = required)], ...], extra keys]
const SCHEMAS: Dictionary = {
	"sprites": [Op.SPRITES, "sprite", [["size", null], ["life", null], ["param", 1.0], ["pal", 0.0]], ["batch"]],
	"puff": [Op.PUFF, "sprite", [["size", null], ["life", null], ["alpha", 1.0]], ["batch"]],
	"ring": [Op.RING, "ring", [["radius", null], ["life", null], ["pal", 0.0]], ["batch"]],
	"wake": [Op.WAKE, "", [["length", null], ["width", null], ["life", 4.0]], []],
	"dome": [Op.DOME, "", [["radius", null], ["life", null], ["mode", 0.0]], []],
	"column": [Op.COLUMN, "column", [["radius", null], ["height", null], ["life", null]], ["batch"]],
	"ribbon": [Op.RIBBON, "ribbon", [["life", null], ["width", null], ["tail", 0.0], ["flight", null], ["linger", 0.0], ["arc_h", 0.0], ["pal", 0.0]], ["batch", "to", "to_off"]],
	"tracer": [Op.TRACER, "", [["speed", null], ["tail", null], ["width", null], ["pal", 0.0], ["arc_h", 0.0]], ["to", "to_off"]],
	"trail": [Op.TRAIL, "ribbon", [["flight", null], ["linger", null], ["width", null], ["arc_h", 0.0]], ["batch", "to", "to_off"]],
	"cone": [Op.CONE, "", [["length", null], ["width", null], ["life", null]], ["dir"]],
	"beam": [Op.BEAM, "", [["life", null], ["width", null]], ["to", "to_off"]],
	"rail": [Op.RAIL, "", [["life", null], ["width", null]], ["to", "to_off"]],
	"shimmer": [Op.SHIMMER, "", [["life", null], ["width", null]], ["to", "to_off"]],
	"bolt": [Op.BOLT, "", [["life", null], ["width", null], ["arc_h", 0.0]], ["to", "to_off"]],
	"light": [Op.LIGHT, "", [["energy", null], ["range", null], ["life", null]], ["color"]],
	"scorch": [Op.SCORCH, "", [["radius", null], ["life", null], ["hot", 0.0]], []],
	"shake": [Op.SHAKE, "", [["amount", null]], []],
	"fx": [Op.FX, "", [["scale", 1.0]], ["id", "b_at", "b_off", "inline"]],
	"loop": [Op.LOOP, "", [["interval", null], ["duration", null], ["scale", 1.0]], ["id", "b_at", "b_off"]],
	"for": [Op.FOR, "", [["n", null]], ["var", "do"]],
	"if": [Op.IF, "", [["if", null]], ["then", "else"]],
	"let": [Op.LET, "", [["value", null]], ["name"]],
	"native": [Op.NATIVE, "", [], ["name", "args"]],
}
## Batch kinds a layer op may target.
const BATCH_KINDS: Dictionary = {"sprite": "sprite", "ring": "ring", "column": "column", "ribbon": "ribbon"}


## One compiled effect. Public fields are the spec's FxDef (id, cls, kind, radius, nominal_scale, layers).
class FxDef extends RefCounted:
	var id: StringName = &""
	var cls: int = FxManager.Cls.MEDIUM
	var kind: int = FxManager.Kind.POINT
	var radius: float = 1.0
	var nominal_scale: float = 1.0
	var min_dist: float = 0.0  ## LINE effects shorter than this are skipped
	var template: bool = false
	var extends_id: StringName = &""
	var meta: Dictionary = {}
	var layers: Array[Layer] = []
	var refs: Array[StringName] = []  ## effect ids spawned by fx / loop layers (cycle check)
	var inline_refs: Array[StringName] = []  ## `fx` layers with inline=true (may target templates; no admission)
	var scope: ViewExpr.Scope = null
	var frame: Array = []
	var busy: bool = false
	var var_slots: PackedInt32Array = PackedInt32Array()
	var var_ex: Array = []  # ViewExpr or null
	var var_k: PackedFloat64Array = PackedFloat64Array()
	var var_rs: Array[PackedInt32Array] = []
	var has_speed: bool = false
	var speed_slot: int = -1


## One compiled layer (op).
class Layer extends RefCounted:
	var kind: int = 0
	var path: String = ""
	var v: PackedFloat64Array = PackedFloat64Array()  # constants pre-filled, dynamic entries rewritten on every evaluation
	var ex: Array = []  # ViewExpr per index or null
	var dyn: PackedInt32Array = PackedInt32Array()
	var rs: PackedInt32Array = PackedInt32Array()  # frame slots of rand() occurrences, refreshed before each evaluation
	var at_b: bool = false
	var to_b: bool = true
	var b_at_b: bool = true
	var inline: bool = false
	var back: bool = false
	var sa: StringName = &""
	var slot: int = -1
	var color: Color = Color.WHITE
	var body: Array[Layer] = []
	var els: Array[Layer] = []
	var native: Callable = Callable()


## name -> Callable(m: FxManager, a: Vector3, b: Vector3, s: float, args: Array). Register before load_file().
var natives: Dictionary = {}
## fx.json `classes` and `mappings` sections as parsed (FxManager reads the first, FxCatalog the second).
var class_table: Dictionary = {}
var mappings: Dictionary = {}
var source_path: String = ""

var _defs: Dictionary = {}  # StringName -> FxDef
var _ids: PackedStringArray = PackedStringArray()
var _errors: PackedStringArray = PackedStringArray()
var _raw: Dictionary = {}
var _resolving: Array[String] = []
var _rand_n: int = 0
# run state (saved / restored around nested runs)
var _m: FxManager = null
var _a: Vector3 = Vector3.ZERO
var _b: Vector3 = Vector3.ZERO
var _s: float = 1.0
var _dir: Vector3 = Vector3.FORWARD
var _fr: Array = []
var _depth: int = 0
var _warned_depth: bool = false


# ---------------------------------------------------------------------------------------------- public API
func load_file(path: String = "res://data/recipes/fx.json") -> bool:
	source_path = path
	if not FileAccess.file_exists(path):
		_reset()
		_errors.append("%s: file not found" % path)
		return false
	var txt: String = FileAccess.get_file_as_string(path)
	var js: JSON = JSON.new()
	if js.parse(txt) != OK:
		_reset()
		_errors.append("%s: JSON error at line %d: %s" % [path, js.get_error_line(), js.get_error_message()])
		return false
	if not (js.data is Dictionary):
		_reset()
		_errors.append("%s: root must be an object" % path)
		return false
	return load_dict(js.data as Dictionary)


## Compiles an already parsed document (tests). Returns true when no error was found.
func load_dict(doc: Dictionary) -> bool:
	_reset()
	if String(doc.get("schema", SCHEMA)) != SCHEMA:
		_errors.append("fx.json: unknown schema '%s' (expected %s)" % [doc.get("schema"), SCHEMA])
	class_table = doc.get("classes", {}) as Dictionary
	mappings = doc.get("mappings", {}) as Dictionary
	_raw = doc.get("effects", {}) as Dictionary
	var quiet_was: bool = ViewExpr.quiet
	ViewExpr.quiet = true
	var names: Array = _raw.keys()
	names.sort()
	for id_v: Variant in names:
		var id: String = id_v as String
		if not _defs.has(StringName(id)):
			_compile_effect(id)
	ViewExpr.quiet = quiet_was
	_check_refs()
	_ids = PackedStringArray()
	for id_v: Variant in _defs.keys():
		var d: FxDef = _defs[id_v] as FxDef
		if not d.template:
			_ids.append(String(d.id))
	_ids.sort()
	return _errors.is_empty()


func has(id: StringName) -> bool:
	var d: FxDef = _defs.get(id) as FxDef
	return d != null and not d.template


## The compiled effect, or null for an unknown id and for templates.
func def(id: StringName) -> FxDef:
	var d: FxDef = _defs.get(id) as FxDef
	if d == null or d.template:
		return null
	return d


## Every spawnable (non-template) effect id, sorted.
func ids() -> PackedStringArray:
	return _ids


func errors() -> PackedStringArray:
	return _errors


## Interprets the layer list of `d` against `m`. Anchors: `a` origin, `b` destination (LINE) or b.x = duration (AREA), `s` scale.
func run(d: FxDef, m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var seg: Vector3 = b - a
	var dist: float = seg.length()
	if d.min_dist > 0.0 and dist < d.min_dist:
		return
	if _depth >= MAX_RUN_DEPTH:
		if not _warned_depth:
			_warned_depth = true
			Log.warn("view", "FxRecipeBook: nested effect depth exceeded at '%s'" % d.id)
		return
	var p_m: FxManager = _m
	var p_a: Vector3 = _a
	var p_b: Vector3 = _b
	var p_s: float = _s
	var p_dir: Vector3 = _dir
	var p_fr: Array = _fr
	var was_busy: bool = d.busy
	var fr: Array = d.scope.make_frame() if was_busy else d.frame
	d.busy = true
	_depth += 1
	_m = m
	_a = a
	_b = b
	_s = s
	_dir = seg / dist if dist > 0.001 else Vector3.FORWARD
	_fr = fr
	fr[F_S] = s
	fr[F_DIST] = dist
	fr[F_AX] = a.x
	fr[F_AX + 1] = a.y
	fr[F_AX + 2] = a.z
	fr[F_BX] = b.x
	fr[F_BX + 1] = b.y
	fr[F_BX + 2] = b.z
	fr[F_DX] = _dir.x
	fr[F_DX + 1] = _dir.y
	fr[F_DX + 2] = _dir.z
	fr[F_FLIGHT] = 0.0
	for i: int in d.var_slots.size():
		var rs: PackedInt32Array = d.var_rs[i]
		for r: int in rs:
			fr[r] = randf()
		var e: ViewExpr = d.var_ex[i] as ViewExpr
		fr[d.var_slots[i]] = d.var_k[i] if e == null else e.eval_float(fr)
	if d.has_speed:
		fr[F_FLIGHT] = dist / maxf(float(fr[d.speed_slot]), 0.001)
	_exec(d.layers, true)
	_depth -= 1
	if not was_busy:
		d.busy = false
	_m = p_m
	_a = p_a
	_b = p_b
	_s = p_s
	_dir = p_dir
	_fr = p_fr


# ---------------------------------------------------------------------------------------------- interpreter
func _exec(list: Array[Layer], allow_delay: bool) -> void:
	for l: Layer in list:
		_exec_one(l, allow_delay)


func _exec_one(l: Layer, allow_delay: bool) -> void:
	var fr: Array = _fr
	var v: PackedFloat64Array = l.v
	for r: int in l.rs:
		fr[r] = randf()
	for i: int in l.dyn:
		v[i] = (l.ex[i] as ViewExpr).eval_float(fr)
	if v[K_WHEN] == 0.0:
		return
	var delay: float = v[K_DELAY]
	var kind: int = l.kind
	if delay > 0.0 and allow_delay and kind != Op.FX and kind != Op.LOOP:
		_m.schedule_call(delay, _run_delayed.bind(l, fr.duplicate(), _m, _a, _b, _s))
		return
	# position = anchor + along * dir + off
	var p: Vector3 = _b if l.at_b else _a
	if v[K_ALONG] != 0.0:
		p += _dir * v[K_ALONG]
	p += Vector3(v[K_OFF], v[K_OFF + 1], v[K_OFF + 2])
	const A: int = K_ARG
	if kind == Op.SPRITES:
		_m.sprites(l.sa, p, v[A], v[A + 1], v[A + 2], int(v[A + 3]))
	elif kind == Op.PUFF:
		_m.puff(l.sa, p, v[A], v[A + 1], v[A + 2])
	elif kind == Op.RING:
		_m.ring(l.sa, p, v[A], v[A + 1], int(v[A + 2]))
	elif kind == Op.FX:
		var scale: float = v[A]
		var cb: Vector3 = (_b if l.b_at_b else _a) + Vector3(v[K_BOFF], v[K_BOFF + 1], v[K_BOFF + 2])
		if l.inline:
			if delay > 0.0:
				_m.schedule_call(delay, _run_inline.bind(l.sa, _m, p, cb, scale))
			else:
				_run_inline(l.sa, _m, p, cb, scale)
		elif delay > 0.0:
			_m.schedule(delay, l.sa, p, cb, scale)
		else:
			_m.spawn(l.sa, p, cb, scale)
	elif kind == Op.LIGHT:
		var col: Color = l.color
		_m.light_flash(p, col, v[A], v[A + 1], v[A + 2])
	elif kind == Op.SCORCH:
		_m.scorch(p, v[A], v[A + 1], v[A + 2])
	elif kind == Op.SHAKE:
		_m.shake(v[A], p)
	elif kind == Op.FOR:
		var n: int = mini(int(v[A]), MAX_FOR)
		for i: int in n:
			fr[l.slot] = float(i)
			_exec(l.body, true)
	elif kind == Op.IF:
		if v[A] != 0.0:
			_exec(l.body, true)
		else:
			_exec(l.els, true)
	elif kind == Op.LET:
		fr[l.slot] = v[A]
	elif kind == Op.LOOP:
		var lb: Vector3 = (_b if l.b_at_b else _a) + Vector3(v[K_BOFF], v[K_BOFF + 1], v[K_BOFF + 2])
		_m.start_loop(l.sa, p, lb, v[A + 2], v[A], v[A + 1], maxf(delay, 0.0))
	elif kind == Op.NATIVE:
		var args: Array = []
		for i: int in v.size() - A:
			args.append(v[A + i])
		l.native.call(_m, _a, _b, _s, args)
	else:
		_exec_geometry(l, v, p)


## Ribbon-like ops (their end point is the `to` anchor + to_off).
func _exec_geometry(l: Layer, v: PackedFloat64Array, p: Vector3) -> void:
	const A: int = K_ARG
	var kind: int = l.kind
	if kind == Op.WAKE:
		_m.wake(p, _dir, v[A], v[A + 1], v[A + 2])
		return
	if kind == Op.DOME:
		_m.dome(p, v[A], v[A + 1], int(v[A + 2]))
		return
	if kind == Op.COLUMN:
		_m.column(l.sa, p, v[A], v[A + 1], v[A + 2])
		return
	if kind == Op.CONE:
		_m.cone(p, -_dir if l.back else _dir, v[A], v[A + 1], v[A + 2])
		return
	var q: Vector3 = (_b if l.to_b else _a) + Vector3(v[K_BOFF], v[K_BOFF + 1], v[K_BOFF + 2])
	if kind == Op.TRACER:
		_m.tracer(p, q, v[A], v[A + 1], v[A + 2], int(v[A + 3]), Vector3(0.0, v[A + 4], 0.0))
	elif kind == Op.RIBBON:
		_m.ribbon(l.sa, p, q, v[A], v[A + 1], v[A + 2], v[A + 3], v[A + 4], Vector3(0.0, v[A + 5], 0.0), int(v[A + 6]))
	elif kind == Op.TRAIL:
		_m.trail(p, q, v[A], v[A + 1], v[A + 2], Vector3(0.0, v[A + 3], 0.0), l.sa)
	elif kind == Op.BEAM:
		_m.beam(p, q, v[A], v[A + 1])
	elif kind == Op.RAIL:
		_m.rail(p, q, v[A], v[A + 1])
	elif kind == Op.SHIMMER:
		_m.shimmer(p, q, v[A], v[A + 1])
	elif kind == Op.BOLT:
		_m.bolt(p, q, v[A], v[A + 1], v[A + 2])


## `fx` layer with inline=true: the child's layers run as part of the composite (no admission, no token, templates allowed).
func _run_inline(id: StringName, m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var d: FxDef = _defs.get(id) as FxDef
	if d != null:
		run(d, m, a, b, s)


## Deferred layer (delay > 0): restores the run state of its composite and executes the layer without deferring again.
func _run_delayed(l: Layer, frame: Array, m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var p_m: FxManager = _m
	var p_a: Vector3 = _a
	var p_b: Vector3 = _b
	var p_s: float = _s
	var p_dir: Vector3 = _dir
	var p_fr: Array = _fr
	_m = m
	_a = a
	_b = b
	_s = s
	var seg: Vector3 = b - a
	_dir = seg.normalized() if seg.length() > 0.001 else Vector3.FORWARD
	_fr = frame
	_exec_one(l, false)
	_m = p_m
	_a = p_a
	_b = p_b
	_s = p_s
	_dir = p_dir
	_fr = p_fr


# ---------------------------------------------------------------------------------------------- compile
func _reset() -> void:
	_defs.clear()
	_ids = PackedStringArray()
	_errors = PackedStringArray()
	_raw = {}
	class_table = {}
	mappings = {}
	_resolving.clear()


func _err(path: String, msg: String) -> void:
	_errors.append("%s: %s" % [path, msg])


## Effect record with `extends` resolved: {class, kind, radius, scale, min_dist, template, meta, vars, layers}.
func _resolve(id: String) -> Dictionary:
	var src: Variant = _raw.get(id)
	if not (src is Dictionary):
		_err(id, "effect must be an object")
		return {}
	var e: Dictionary = src as Dictionary
	var out: Dictionary = {}
	if e.has("extends"):
		var pid: String = str(e["extends"])
		if _resolving.has(id):
			_err(id, "extends cycle: %s -> %s" % [" -> ".join(_resolving), id])
			return {}
		if not _raw.has(pid):
			_err(id, "extends unknown effect '%s'" % pid)
			return {}
		_resolving.append(id)
		out = _resolve(pid)
		_resolving.pop_back()
		out = out.duplicate(true)
		out.erase("template")  # templates are not inherited
	var vars: Dictionary = (out.get("vars", {}) as Dictionary).duplicate()
	for k: Variant in e.keys():
		if k == "vars":
			var cv: Dictionary = e["vars"] as Dictionary if e["vars"] is Dictionary else {}
			for vk: Variant in cv.keys():
				vars[vk] = cv[vk]
		else:
			out[k] = e[k]
	out["vars"] = vars
	return out


func _compile_effect(id: String) -> void:
	_resolving.clear()
	var e: Dictionary = _resolve(id)
	if e.is_empty():
		return
	var d: FxDef = FxDef.new()
	d.id = StringName(id)
	var errs_before: int = _errors.size()
	for k: Variant in e.keys():
		if not ["class", "kind", "radius", "scale", "min_dist", "template", "vars", "layers", "extends", "meta", "desc"].has(k):
			_err(id, "unknown key '%s'" % k)
	var cname: String = str(e.get("class", "medium"))
	d.cls = FxManager.CLASS_NAMES.find(cname)
	if d.cls < 0:
		_err(id, "unknown class '%s'" % cname)
		d.cls = FxManager.Cls.MEDIUM
	var kname: String = str(e.get("kind", "point"))
	d.kind = FxManager.KIND_NAMES.find(kname)
	if d.kind < 0:
		_err(id, "unknown kind '%s'" % kname)
		d.kind = FxManager.Kind.POINT
	d.radius = float(e.get("radius", 1.0))
	d.nominal_scale = float(e.get("scale", 1.0))
	d.min_dist = float(e.get("min_dist", 0.0))
	d.template = bool(e.get("template", false))
	d.extends_id = StringName(str(e.get("extends", "")))
	d.meta = e.get("meta", {}) as Dictionary if e.get("meta", {}) is Dictionary else {}
	var scope: ViewExpr.Scope = ViewExpr.Scope.new()
	for nm: String in ["s", "dist", "ax", "ay", "az", "bx", "by", "bz", "dx", "dy", "dz", "flight"]:
		scope.slot(StringName(nm))
	d.scope = scope
	_rand_n = 0
	_compile_vars(d, e.get("vars", {}) as Dictionary, id)
	var layers_v: Variant = e.get("layers", [])
	if not (layers_v is Array):
		_err(id + "/layers", "must be an array")
	else:
		d.layers = _compile_layers(layers_v as Array, id + "/layers", scope, d, 0)
	d.frame = scope.make_frame()
	if _errors.size() == errs_before:
		_defs[d.id] = d
	else:
		_defs.erase(d.id)


func _compile_vars(d: FxDef, vars: Dictionary, id: String) -> void:
	for k: Variant in vars.keys():
		var name: String = str(k)
		var path: String = "%s/vars/%s" % [id, name]
		var val: Variant = vars[k]
		var rs: PackedInt32Array = PackedInt32Array()
		var ex: ViewExpr = null
		var kv: float = 0.0
		if val is String:
			ex = _cx(val as String, d.scope, path, rs)
			if ex != null and ex.is_const():
				kv = ex.eval_float(d.scope.make_frame())
				ex = null
		elif val is float or val is int or val is bool:
			kv = float(val)
		else:
			_err(path, "must be a number or an expression string")
		var slot: int = d.scope.slot(StringName(name))  # declared AFTER its own expression compiled (no self reference)
		d.var_slots.append(slot)
		d.var_ex.append(ex)
		d.var_k.append(kv)
		d.var_rs.append(rs)
		if name == "speed":
			d.has_speed = true
			d.speed_slot = slot


func _compile_layers(arr: Array, path: String, scope: ViewExpr.Scope, d: FxDef, depth: int) -> Array[Layer]:
	var out: Array[Layer] = []
	if depth > 4:
		_err(path, "nested deeper than 4 levels")
		return out
	for i: int in arr.size():
		var lp: String = "%s[%d]" % [path, i]
		if not (arr[i] is Dictionary):
			_err(lp, "layer must be an object")
			continue
		var l: Layer = _compile_layer(arr[i] as Dictionary, lp, scope, d, depth)
		if l != null:
			out.append(l)
	return out


func _compile_layer(src: Dictionary, path: String, scope: ViewExpr.Scope, d: FxDef, depth: int) -> Layer:
	var opname: String = str(src.get("op", ""))
	if not SCHEMAS.has(opname):
		_err(path, "unknown op '%s'" % opname)
		return null
	path = "%s/%s" % [path, opname]
	var sch: Array = SCHEMAS[opname] as Array
	var l: Layer = Layer.new()
	l.kind = sch[0] as int
	l.path = path
	var nargs: int = (sch[2] as Array).size()
	if l.kind == Op.NATIVE:
		nargs = (src.get("args", []) as Array).size() if src.get("args", []) is Array else 0
	var total: int = K_ARG + nargs
	l.v.resize(total)
	l.v.fill(0.0)
	l.ex.resize(total)
	l.ex.fill(null)
	l.v[K_WHEN] = 1.0
	var ok_keys: Array = COMMON_KEYS.duplicate()
	ok_keys.append_array(sch[3] as Array)
	for na: Array in sch[2] as Array:
		ok_keys.append(na[0])
	for k: Variant in src.keys():
		if not ok_keys.has(k):
			_err(path, "unknown key '%s'" % k)
	# common keys
	_put(l, K_WHEN, src.get("when", 1.0), scope, path + "/when")
	_put(l, K_DELAY, src.get("delay", 0.0), scope, path + "/delay")
	_put(l, K_ALONG, src.get("along", 0.0), scope, path + "/along")
	_put_vec(l, K_OFF, src.get("off", null), scope, path + "/off")
	l.at_b = _anchor(src, "at", "a", path) == "b"
	# numeric args
	var idx: int = K_ARG
	for na: Array in sch[2] as Array:
		var key: String = na[0] as String
		if src.has(key):
			_put(l, idx, src[key], scope, "%s/%s" % [path, key])
		elif na[1] == null:
			_err(path, "missing required key '%s'" % key)
		else:
			l.v[idx] = float(na[1])
		idx += 1
	_compile_op_extras(l, opname, sch, src, scope, d, depth, path)
	return l


func _compile_op_extras(l: Layer, opname: String, sch: Array, src: Dictionary, scope: ViewExpr.Scope, d: FxDef, depth: int, path: String) -> void:
	var extra: Array = sch[3] as Array
	var bkind: String = sch[1] as String
	if extra.has("batch"):
		var bname: StringName = StringName(str(src.get("batch", "trail" if l.kind == Op.TRAIL else "")))
		l.sa = bname
		if not FxManager.BATCHES.has(bname):
			_err(path + "/batch", "unknown batch '%s'" % bname)
		elif bkind != "" and str((FxManager.BATCHES[bname] as Array)[0]) != bkind:
			_err(path + "/batch", "batch '%s' cannot be used by '%s' (needs a %s batch)" % [bname, opname, bkind])
	if extra.has("to"):
		l.to_b = _anchor(src, "to", "b", path) == "b"
		_put_vec(l, K_BOFF, src.get("to_off", null), scope, path + "/to_off")
	match l.kind:
		Op.CONE:
			var dv: String = str(src.get("dir", "fwd"))
			if dv != "fwd" and dv != "back":
				_err(path + "/dir", "must be \"fwd\" or \"back\"")
			l.back = dv == "back"
		Op.LIGHT:
			var cv: Variant = src.get("color", null)
			if cv is Array and (cv as Array).size() == 3:
				var c: Array = cv as Array
				l.color = Color(float(c[0]), float(c[1]), float(c[2]))
			else:
				_err(path + "/color", "must be [r, g, b]")
		Op.FX, Op.LOOP:
			l.sa = StringName(str(src.get("id", "")))
			l.inline = l.kind == Op.FX and bool(src.get("inline", false))
			if str(src.get("id", "")) == "":
				_err(path, "missing required key 'id'")
			elif l.inline:
				d.inline_refs.append(l.sa)
			else:
				d.refs.append(l.sa)
			l.b_at_b = _anchor(src, "b_at", "b", path) == "b"
			_put_vec(l, K_BOFF, src.get("b_off", null), scope, path + "/b_off")
		Op.FOR:
			var vname: String = str(src.get("var", ""))
			if vname == "":
				_err(path, "missing required key 'var'")
				vname = "_i"
			l.slot = scope.slot(StringName(vname))
			l.body = _compile_layers(src.get("do", []) as Array if src.get("do", []) is Array else [], path + "/do", scope, d, depth + 1)
		Op.IF:
			l.body = _compile_layers(src.get("then", []) as Array if src.get("then", []) is Array else [], path + "/then", scope, d, depth + 1)
			l.els = _compile_layers(src.get("else", []) as Array if src.get("else", []) is Array else [], path + "/else", scope, d, depth + 1)
		Op.LET:
			var lname: String = str(src.get("name", ""))
			if lname == "":
				_err(path, "missing required key 'name'")
				lname = "_let"
			# re-set the value expression first (compiled above with the previous scope), then declare the name
			l.slot = scope.slot(StringName(lname))
		Op.NATIVE:
			var nname: String = str(src.get("name", ""))
			if not natives.has(nname):
				_err(path + "/name", "unknown native '%s'" % nname)
			else:
				l.native = natives[nname] as Callable
			var av: Variant = src.get("args", [])
			if av is Array:
				for i: int in (av as Array).size():
					_put(l, K_ARG + i, (av as Array)[i], scope, "%s/args[%d]" % [path, i])
			else:
				_err(path + "/args", "must be an array")


func _anchor(src: Dictionary, key: String, dflt: String, path: String) -> String:
	var v: String = str(src.get(key, dflt))
	if v != "a" and v != "b":
		_err("%s/%s" % [path, key], "must be \"a\" or \"b\"")
		return dflt
	return v


func _put_vec(l: Layer, base: int, val: Variant, scope: ViewExpr.Scope, path: String) -> void:
	if val == null:
		return
	if not (val is Array) or (val as Array).size() != 3:
		_err(path, "must be an array of 3 numbers / expressions")
		return
	for i: int in 3:
		_put(l, base + i, (val as Array)[i], scope, "%s[%d]" % [path, i])


## Stores one numeric field: a constant goes straight into `v`, an expression is compiled (constants folded) and evaluated per run.
func _put(l: Layer, idx: int, val: Variant, scope: ViewExpr.Scope, path: String) -> void:
	if val is float or val is int:
		l.v[idx] = float(val)
	elif val is bool:
		l.v[idx] = 1.0 if val else 0.0
	elif val is String:
		var rs: PackedInt32Array = PackedInt32Array()
		var e: ViewExpr = _cx(val as String, scope, path, rs)
		if e == null:
			return
		if e.is_const() and rs.is_empty():
			l.v[idx] = e.eval_float(scope.make_frame())
		else:
			l.ex[idx] = e
			l.dyn.append(idx)
			for r: int in rs:
				l.rs.append(r)
	else:
		_err(path, "must be a number or an expression string")


## Compiles an expression; rand() / randr(lo, hi) / rsq() become hidden frame variables refreshed before each evaluation.
func _cx(src: String, scope: ViewExpr.Scope, path: String, rs: PackedInt32Array) -> ViewExpr:
	var text: String = _rewrite_rand(src, scope, rs)
	var e: ViewExpr = ViewExpr.compile(text, scope, "")
	if e == null:
		_err(path, ViewExpr.last_error.trim_prefix("ViewExpr: "))
	return e


func _rewrite_rand(src: String, scope: ViewExpr.Scope, rs: PackedInt32Array) -> String:
	if not src.contains("rand") and not src.contains("rsq"):
		return src
	var out: String = ""
	var i: int = 0
	var n: int = src.length()
	while i < n:
		var prev_ok: bool = i == 0 or not (src[i - 1] == "_" or (src[i - 1] >= "a" and src[i - 1] <= "z") or (src[i - 1] >= "A" and src[i - 1] <= "Z") or (src[i - 1] >= "0" and src[i - 1] <= "9"))
		if prev_ok and src.substr(i, 6) == "randr(":
			var close: int = _match_paren(src, i + 5)
			if close > 0:
				var inner: String = src.substr(i + 6, close - i - 6)
				var comma: int = _top_comma(inner)
				if comma > 0:
					var lo: String = _rewrite_rand(inner.substr(0, comma), scope, rs)
					var hi: String = _rewrite_rand(inner.substr(comma + 1), scope, rs)
					var nm: String = _new_rand(scope, rs)
					out += "((%s)+((%s)-(%s))*%s)" % [lo, hi, lo, nm]
					i = close + 1
					continue
		if prev_ok and src.substr(i, 6) == "rand()":
			out += _new_rand(scope, rs)
			i += 6
			continue
		if prev_ok and src.substr(i, 5) == "rsq()":
			out += "(%s*2-1)" % _new_rand(scope, rs)
			i += 5
			continue
		out += src[i]
		i += 1
	return out


func _new_rand(scope: ViewExpr.Scope, rs: PackedInt32Array) -> String:
	var nm: String = "__r%d" % _rand_n
	_rand_n += 1
	rs.append(scope.slot(StringName(nm)))
	return nm


static func _match_paren(s: String, open_at: int) -> int:
	var depth: int = 0
	for i: int in range(open_at, s.length()):
		if s[i] == "(":
			depth += 1
		elif s[i] == ")":
			depth -= 1
			if depth == 0:
				return i
	return -1


static func _top_comma(s: String) -> int:
	var depth: int = 0
	for i: int in s.length():
		if s[i] == "(":
			depth += 1
		elif s[i] == ")":
			depth -= 1
		elif s[i] == "," and depth == 0:
			return i
	return -1


## Every `fx` / `loop` reference resolves to a spawnable effect and the reference graph has no cycle.
func _check_refs() -> void:
	for id_v: Variant in _defs.keys():
		var d: FxDef = _defs[id_v] as FxDef
		for r: StringName in d.inline_refs:
			if not _defs.has(r) and not _raw.has(String(r)):
				_err(String(d.id), "inline fx references unknown effect '%s'" % r)
		for r: StringName in d.refs:
			var t: FxDef = _defs.get(r) as FxDef
			if t == null:
				if _raw.has(String(r)):
					continue  # the target failed to compile: its own error is already listed
				_err(String(d.id), "fx/loop references unknown effect '%s'" % r)
			elif t.template:
				_err(String(d.id), "fx/loop references template '%s'" % r)
	var color: Dictionary = {}
	var ids_sorted: Array = _defs.keys()
	ids_sorted.sort()
	for id_v: Variant in ids_sorted:
		_dfs(id_v as StringName, color, [])


func _dfs(id: StringName, color: Dictionary, stack: Array) -> void:
	var st: int = color.get(id, 0) as int
	if st == 2:
		return
	if st == 1:
		var cyc: Array = stack.slice(stack.find(id))
		cyc.append(id)
		_err(String(id), "fx cycle: %s" % " -> ".join(PackedStringArray(cyc.map(func(x: Variant) -> String: return String(x as StringName)))))
		return
	color[id] = 1
	stack.append(id)
	var d: FxDef = _defs.get(id) as FxDef
	if d != null:
		for r: StringName in d.refs + d.inline_refs:
			if _defs.has(r):
				_dfs(r, color, stack)
	stack.pop_back()
	color[id] = 2
