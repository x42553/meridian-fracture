class_name ViewMacrosStructures
extends RefCounted
## Native macros for structures, ships and (through ViewMacrosLandmarks) superweapon / advanced-defence silhouettes
## (render spec 5.8.5, VIEW-M4). Called from recipes as `{"call": name, "args": {...}}`; ViewRecipeMacros.signature() / run()
## fall through to this class for every name they do not know, so the interpreter needs no second dispatch.
##
## Conventions (art_direction 5.9): structures are built around the footprint CENTRE, +Z is the front (south, the approach
## side), +Y up, origin on the ground, metres; a structure never leaves its (fw*3-0.5) x (fh*3-0.5) m plinth. Ships face -Z
## like every unit, origin on the water plane (the hull continues `draft` below it). Argument types: n number, v vec3, w vec2,
## c colour, s string, A number list (same SIGS syntax as ViewRecipeMacros). Every macro is a pure function of (args, palette),
## keeps tier / brush / part state balanced (the interpreter restores brush, tier and part anyway) and never leaves a part open.
## Palette keys used: base dark sec acc metal rubber glass light plate concrete.

const Mat := ViewMeshBuilder.Mat
const Pt := ViewMeshBuilder.Part
const WARN_RED: Color = Color(1.0, 0.1, 0.05)

const SIGS: Dictionary = {
	# structures
	"foundation": "fw:n=3 fh:n=3 depth:n=1.2 col:c=concrete edge:c=dark chevron:n=1 acc:c=acc",
	"wall_block": "center:v size:v=4,3,4 col:c=base sec:c=sec dado:n=0.9 ribs:n=1 coping:n=1 rib:c=sec cap:c=mix(sec,dark,0.4)",
	"roller_door": "center:v w:n=3.76 h:n=3 slats:n=10 wall_l:n=3.8 wall_r:n=3.8 wall_h:n=3.6 thick:n=0.5 col:c=base frame:c=sec lintel:c=acc glow:n=1",
	"window_strip": "center:v n:n=4 size:v=0.8,0.5,0.05 dir:n=0 col:c=light frame:c=dark",
	"stack": "center:v r:n=0.4 h:n=3 col:c=metal band:c=acc bands:n=2 cap:n=1",
	"silo": "center:v r:n=0.8 h:n=5 col:c=sec band:c=acc",
	"silo_cluster": "center:v n:n=4 r:n=0.8 h:n=5 col:c=sec band:c=acc",
	"crane": "center:v reach:n=5 h:n=5 kind:s=jib yaw:n=0 col:c=acc mast:c=sec",
	"pad": "center:v size:v=2.4,0.04,2.4 mark:s=ring col:c=sec base:c=dark",
	"dome_shell": "center:v r:n=2 h:n=0 col:c=sec band:c=acc lens:n=0",
	"pylon_ring": "center:v r:n=3 n:n=6 h:n=2.5 col:c=sec cap:c=acc",
	"launch_rail": "center:v len:n=4 elev:n=25 width:n=0.5 mount:n=0 col:c=metal glow:c=acc",
	"turret_base": "center:v r:n=1 h:n=0.9 col:c=base ring:c=acc",
	"pennant": "pos:v h:n=2 w:n=0.56 l:n=0.36",
	"beacon": "pos:v r:n=0.09 col:c=#ff1a0d phase:n=0",
	"roof_plate": "center:v size:v=1.6,0.04,1.4",
	"conveyor": "from:v to:v=0,0,3 w:n=0.6 col:c=dark belt:c=metal",
	"funnel": "center:v r:n=0.9 h:n=0.9 col:c=sec",
	"lattice": "center:v h:n=8 w0:n=1.6 w1:n=0.7 bays:n=5 col:c=sec brace:c=metal",
	# ships
	"hull_ship": "len:n=5 beam:n=2 draft:n=0.4 bow:s=sharp freeboard:n=0.8 col:c=base low:c=dark stripe:c=acc deck:c=dark",
	"superstructure": "center:v len:n=2 wid:n=1.4 tiers:n=2 tier_h:n=0.55 col:c=base radar:n=1 mast:n=1",
	"vls": "center:v rows:n=4 cols:n=2 pitch:n=0.34",
	"ship_turret": "pos:v barrels:n=1 mount:n=0 r:n=0.42 len:n=1.4 br:n=0.045 col:c=base",
	"flight_deck": "center:v len:n=8 wid:n=3 thick:n=0.18 lifts:n=2 col:c=dark mark:c=sec",
	"deck_drones": "center:v n:n=6 cols:n=3 pitch:n=0.55",
	"sail": "pos:v h:n=1.2 len:n=1.8 w:n=0.6 col:c=base",
}

static var _sig_cache: Dictionary = {}
static var _sig_lock: Mutex = Mutex.new()


## Parsed signature (arg name -> [type letter, default]) of a structure / ship / landmark macro; empty when unknown.
static func signature(macro: String) -> Dictionary:
	var src: String = ""
	if SIGS.has(macro):
		src = SIGS[macro] as String
	elif ViewMacrosLandmarks.SIGS.has(macro):
		src = ViewMacrosLandmarks.SIGS[macro] as String
	else:
		return {}
	_sig_lock.lock()
	var got: Variant = _sig_cache.get(macro)
	if got == null:
		got = ViewRecipeMacros.parse_sig(src)
		_sig_cache[macro] = got
	_sig_lock.unlock()
	return got as Dictionary


## Sorted names of the macros this class (and ViewMacrosLandmarks) implements.
static func macro_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(SIGS.keys())
	out.append_array(PackedStringArray(ViewMacrosLandmarks.SIGS.keys()))
	out.sort()
	return out


## Runs macro `macro` with evaluated arguments; returns "" or an error message.
static func run(macro: String, b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> String:
	if ViewMacrosLandmarks.SIGS.has(macro):
		return ViewMacrosLandmarks.run(macro, b, a, pal)
	match macro:
		"foundation": _foundation(b, a)
		"wall_block": _wall_block(b, a)
		"roller_door": _roller_door(b, a, pal)
		"window_strip": _window_strip(b, a)
		"stack": _stack(b, a)
		"silo": _silo(b, a, pal)
		"silo_cluster": _silo_cluster(b, a, pal)
		"crane": _crane(b, a, pal)
		"pad": _pad(b, a)
		"dome_shell": _dome_shell(b, a, pal)
		"pylon_ring": _pylon_ring(b, a, pal)
		"launch_rail": _launch_rail(b, a, pal)
		"turret_base": _turret_base(b, a, pal)
		"pennant": _pennant(b, a, pal)
		"beacon": _beacon(b, a)
		"roof_plate": _roof_plate(b, a, pal)
		"conveyor": _conveyor(b, a)
		"funnel": _funnel(b, a, pal)
		"lattice": _lattice(b, a)
		"hull_ship": return _hull_ship(b, a)
		"superstructure": _superstructure(b, a, pal)
		"vls": _vls(b, a, pal)
		"ship_turret": _ship_turret(b, a, pal)
		"flight_deck": _flight_deck(b, a, pal)
		"deck_drones": _deck_drones(b, a, pal)
		"sail": _sail(b, a, pal)
		_:
			return "unknown macro '%s'" % macro
	b.clear_part()
	return ""


# ---------------------------------------------------------------------------------------------- argument access
static func _f(a: Dictionary, k: String) -> float:
	return a[k] as float


static func _i(a: Dictionary, k: String) -> int:
	return roundi(a[k] as float)


static func _v(a: Dictionary, k: String) -> Vector3:
	return a[k] as Vector3


static func _c(a: Dictionary, k: String) -> Color:
	return a[k] as Color


static func _s(a: Dictionary, k: String) -> String:
	return a[k] as String


static func _p(pal: Dictionary, k: String) -> Color:
	return pal.get(k, Color(0.5, 0.5, 0.5)) as Color


static func _turret_kind(mount: int) -> int:
	return [Pt.TURRET, Pt.TURRET1, Pt.TURRET2, Pt.TURRET3][clampi(mount, 0, 3)] as int


static func _barrel_kind(mount: int) -> int:
	return [Pt.BARREL, Pt.BARREL1, Pt.BARREL2, Pt.BARREL3][clampi(mount, 0, 3)] as int


## Box aligned with the segment p0 -> p1 (w x d cross-section). Struts, braces, tilted rails.
static func _beam(b: ViewMeshBuilder, p0: Vector3, p1: Vector3, w: float, d: float = -1.0, bevel: float = 0.0) -> void:
	var dv: Vector3 = p1 - p0
	var l: float = dv.length()
	if l < 0.001:
		return
	var y: Vector3 = dv / l
	var ref: Vector3 = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var z: Vector3 = ref.cross(y).normalized()
	var x: Vector3 = y.cross(z).normalized()
	b.push(Transform3D(Basis(x, y, z), p0))
	b.box(Vector3(0.0, l * 0.5, 0.0), Vector3(w, l, w if d < 0.0 else d), bevel)
	b.pop()


static func _yaw(b: ViewMeshBuilder, center: Vector3, deg: float) -> void:
	b.push(ViewMeshBuilder.xf(center, Vector3(0.0, deg, 0.0)))


# ---------------------------------------------------------------------------------------------- structures
## Universal plinth (art_direction 5.9.1): concrete slab (fw*3-0.5) x (fh*3-0.5) m, a skirt below the ground so a rising
## build-up never shows a gap, four corner bollards and the 0.9 m hazard-chevron approach strip on the south edge.
static func _foundation(b: ViewMeshBuilder, a: Dictionary) -> void:
	var w: float = _f(a, "fw") * 3.0 - 0.5
	var h: float = _f(a, "fh") * 3.0 - 0.5
	var depth: float = maxf(_f(a, "depth"), 0.1)
	b.brush(_c(a, "col"))
	b.box(Vector3(0.0, 0.08, 0.0), Vector3(w, 0.16, h), 0.02)
	b.ao = 0.6
	b.brush(_c(a, "edge"))
	b.box(Vector3(0.0, -depth * 0.5, 0.0), Vector3(w - 0.3, depth, h - 0.3), 0.0)
	b.ao = 1.0
	b.brush(_c(a, "edge"), Mat.METAL)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p: Vector3 = Vector3(sx * (w * 0.5 - 0.2), 0.16, sz * (h * 0.5 - 0.2))
			b.cylinder(p, p + Vector3(0.0, 0.36, 0.0), 0.09, 8, 0.0)
	if _f(a, "chevron") > 0.0:
		var n: int = clampi(floori((w - 1.0) / 0.5), 1, 40)
		b.tier = 1
		for i in n:
			b.brush(_c(a, "acc") if i % 2 == 0 else Color(0.11, 0.11, 0.10))
			b.box(Vector3((float(i) - float(n - 1) * 0.5) * 0.5, 0.166, h * 0.5 - 0.5), Vector3(0.38, 0.012, 0.8), 0.0)
		b.tier = 0


## Wall volume with a coloured base course (`dado`), an upper body, pilasters and a coping slab.
static func _wall_block(b: ViewMeshBuilder, a: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var sz: Vector3 = _v(a, "size")
	var dado: float = clampf(_f(a, "dado"), 0.0, sz.y * 0.5)
	var y0: float = c.y - sz.y * 0.5
	var col: Color = _c(a, "col")
	if dado > 0.02:
		b.brush(col)
		b.box(Vector3(c.x, y0 + dado * 0.5, c.z), Vector3(sz.x + 0.08, dado, sz.z + 0.08), -1.0)
	b.brush(_c(a, "sec"))
	b.box(Vector3(c.x, y0 + dado + (sz.y - dado) * 0.5, c.z), Vector3(sz.x, sz.y - dado, sz.z), -1.0)
	var up: float = sz.y - dado
	if _f(a, "ribs") > 0.0 and up > 0.6:
		b.tier = 1
		b.brush(_c(a, "rib"))
		var nx: int = clampi(floori(sz.x / 2.0) + 1, 2, 9)
		for i in nx:
			var x: float = c.x + (float(i) / float(nx - 1) - 0.5) * (sz.x - 0.3)
			for sz_sign: float in [-1.0, 1.0]:
				b.box(Vector3(x, y0 + dado + up * 0.5, c.z + sz_sign * (sz.z * 0.5 + 0.04)), Vector3(0.22, up - 0.1, 0.1), 0.0)
		b.tier = 0
	if _f(a, "coping") > 0.0:
		b.brush(_c(a, "cap"))
		b.box(Vector3(c.x, c.y + sz.y * 0.5 + 0.05, c.z), Vector3(sz.x + 0.16, 0.1, sz.z + 0.16), 0.02)


## Facade with a roll-up door (spike factory): two piers and a header around the opening, dark interior with lit strips,
## frame posts, an accent lintel housing and `slats` DOOR slats that stack inside the header when `u_aux.y` = 1. `center` =
## (door centre x, 0, z of the outer facade face); `wall_l` / `wall_r` = extent of the facade to the left / right of the door
## centre (so a door that is off-centre in its wall works), `wall_h` = facade height (>= h + 0.6 hides the open stack). The
## wall body must start behind `thick`.
static func _roller_door(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var w: float = _f(a, "w")
	var h: float = _f(a, "h")
	var wl: float = maxf(_f(a, "wall_l"), w * 0.5 + 0.1)
	var wr: float = maxf(_f(a, "wall_r"), w * 0.5 + 0.1)
	var wh: float = maxf(_f(a, "wall_h"), h + 0.5)
	var th: float = _f(a, "thick")
	var n: int = clampi(_i(a, "slats"), 2, 24)
	var col: Color = _c(a, "col")
	var frame: Color = _c(a, "frame")
	var zc: float = c.z - th * 0.5
	b.brush(col)
	var pl: float = wl - w * 0.5
	var pr: float = wr - w * 0.5
	b.box(Vector3(c.x - w * 0.5 - pl * 0.5, wh * 0.5, zc), Vector3(pl, wh, th), 0.04)
	b.box(Vector3(c.x + w * 0.5 + pr * 0.5, wh * 0.5, zc), Vector3(pr, wh, th), 0.04)
	b.box(Vector3(c.x, h + (wh - h) * 0.5, zc), Vector3(w + 0.02, wh - h, th), 0.04)
	# interior backdrop, lit strips and floor mat
	b.brush(Color(0.05, 0.05, 0.05), Mat.METAL)
	b.box(Vector3(c.x, h * 0.5 + 0.1, c.z - th + 0.06), Vector3(w - 0.06, h - 0.1, 0.05), 0.0)
	if _f(a, "glow") > 0.0:
		b.brush(_p(pal, "light"), Mat.EMISSIVE)
		b.box(Vector3(c.x, h * 0.9, c.z - th + 0.1), Vector3(w * 0.8, 0.08, 0.04), 0.0)
		b.box(Vector3(c.x, h * 0.47, c.z - th + 0.1), Vector3(w * 0.8, 0.05, 0.04), 0.0)
	b.brush(Color(0.20, 0.19, 0.17), Mat.METAL)
	b.box(Vector3(c.x, 0.17, c.z - th * 0.5), Vector3(w - 0.06, 0.06, th - 0.1), 0.0)
	# frame posts, lintel housing and accent bar
	b.brush(frame)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(c.x + sx * (w * 0.5 + 0.02), h * 0.5 + 0.02, c.z + 0.05), Vector3(0.24, h + 0.04, 0.2), 0.03)
	b.box(Vector3(c.x, h + 0.16, c.z + 0.1), Vector3(w + 0.5, 0.34, 0.3), 0.04)
	b.brush(_c(a, "lintel"))
	b.box(Vector3(c.x, h + 0.36, c.z + 0.1), Vector3(w + 0.5, 0.07, 0.32), 0.0)
	# slats: slat i travels to a stacked slot inside the header
	var sl: float = h / float(n)
	for i in n:
		var y: float = sl * (float(i) + 0.5)
		var yf: float = h + sl * 0.5 + 0.04 + 0.03 * float(i)
		b.set_part(Pt.DOOR, Vector3.ZERO, 0.0, yf - y)
		b.brush(frame if i % 3 != 0 else frame.darkened(0.18))
		b.box(Vector3(c.x, y, c.z - 0.04), Vector3(w - 0.04, sl - 0.02, 0.07), 0.01)
	b.clear_part()


## Row of `n` lit panes (emissive) in a dark frame, facing +Z rotated by `dir` degrees about Y; `center` = strip centre.
static func _window_strip(b: ViewMeshBuilder, a: Dictionary) -> void:
	var n: int = clampi(_i(a, "n"), 1, 24)
	var sz: Vector3 = _v(a, "size")
	var gap: float = 0.12
	var total: float = float(n) * (sz.x + gap) + gap
	_yaw(b, _v(a, "center"), _f(a, "dir"))
	b.tier = 1
	b.brush(_c(a, "frame"))
	b.box(Vector3(0.0, 0.0, -sz.z * 0.3), Vector3(total, sz.y + 0.14, sz.z * 0.8), 0.0)
	b.brush(_c(a, "col"), Mat.EMISSIVE)
	for i in n:
		b.box(Vector3((float(i) - float(n - 1) * 0.5) * (sz.x + gap), 0.0, sz.z * 0.15), sz, 0.0)
	b.tier = 0
	b.pop()


## Chimney: tapered shaft on a base ring with `bands` accent rings and a capped rim.
static func _stack(b: ViewMeshBuilder, a: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	var h: float = _f(a, "h")
	var r1: float = r * 0.82
	b.brush(_c(a, "col"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, 0.25, 0.0), r * 1.25, 10, 0.02)
	b.frustum(c + Vector3(0.0, 0.2, 0.0), c + Vector3(0.0, h, 0.0), r, r1, 10, true)
	var nb: int = clampi(_i(a, "bands"), 0, 6)
	b.brush(_c(a, "band"))
	for i in nb:
		var t: float = 0.35 + 0.5 * float(i) / float(maxi(nb, 1))
		var yy: float = lerpf(0.2, h, t)
		var rr: float = lerpf(r, r1, (yy - 0.2) / (h - 0.2)) * 1.03
		b.cylinder(c + Vector3(0.0, yy, 0.0), c + Vector3(0.0, yy + h * 0.06, 0.0), rr, 10, 0.0)
	if _f(a, "cap") > 0.0:
		b.brush(_c(a, "col"), Mat.METAL)
		b.cylinder(c + Vector3(0.0, h - 0.06, 0.0), c + Vector3(0.0, h + 0.1, 0.0), r1 * 1.18, 10, 0.015)
		b.brush(Color(0.04, 0.04, 0.04))
		b.cylinder(c + Vector3(0.0, h + 0.09, 0.0), c + Vector3(0.0, h + 0.11, 0.0), r1 * 0.8, 8, 0.0)


## Storage silo: banded cylinder, domed roof, ladder and base ring.
static func _silo(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	var h: float = _f(a, "h")
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, 0.3, 0.0), r * 1.1, 16, 0.02)
	b.brush(_c(a, "col"))
	b.cylinder(c + Vector3(0.0, 0.3, 0.0), c + Vector3(0.0, h, 0.0), r, 16, 0.02)
	b.dome(c + Vector3(0.0, h, 0.0), Vector3.UP, r, r * 0.42, 16, 3)
	b.brush(_c(a, "band"))
	for k in 2:
		var y: float = h * (0.42 + 0.3 * float(k))
		b.cylinder(c + Vector3(0.0, y, 0.0), c + Vector3(0.0, y + 0.14, 0.0), r * 1.03, 16, 0.0)
	b.tier = 1
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.box(c + Vector3(0.0, h * 0.5 + 0.1, r + 0.05), Vector3(0.12, h - 0.2, 0.05), 0.0)
	b.cylinder(c + Vector3(0.0, h + r * 0.42, 0.0), c + Vector3(0.0, h + r * 0.42 + 0.35, 0.0), 0.06, 6, 0.0)
	b.tier = 0


static func _silo_cluster(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var n: int = clampi(_i(a, "n"), 1, 7)
	var r: float = _f(a, "r")
	var sa: Dictionary = {"r": r, "h": _f(a, "h"), "col": _c(a, "col"), "band": _c(a, "band")}
	for i in n:
		var off: Vector3 = Vector3.ZERO
		if n > 1:
			if i == 0 and n >= 7:
				off = Vector3.ZERO
			else:
				var k: int = i - (1 if n >= 7 else 0)
				var m: int = n - (1 if n >= 7 else 0)
				var ang: float = TAU * float(k) / float(m) + 0.5
				off = Vector3(cos(ang), 0.0, sin(ang)) * r * (2.15 if m > 2 else 1.1)
		sa["center"] = c + off
		sa["h"] = _f(a, "h") * (1.0 - 0.08 * float(i % 3))
		_silo(b, sa, pal)


## Jib crane (`kind` jib: mast + boom + counterweight + cab + hook on SLIDE_Y) or gantry (`kind` gantry: two legs and a
## bridge beam of length `reach`, hook trolley). `yaw` turns the boom about Y; `center` = mast base.
static func _crane(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var reach: float = _f(a, "reach")
	var h: float = _f(a, "h")
	var col: Color = _c(a, "col")
	var mast: Color = _c(a, "mast")
	_yaw(b, c, _f(a, "yaw"))
	if _s(a, "kind") == "gantry":
		b.brush(mast)
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * reach * 0.5, h * 0.5, 0.0), Vector3(0.4, h, 0.4), 0.03)
		b.brush(col)
		b.box(Vector3(0.0, h + 0.17, 0.0), Vector3(reach + 0.8, 0.34, 0.42), 0.03)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.box(Vector3(reach * 0.15, h - 0.1, 0.0), Vector3(0.6, 0.5, 0.5), 0.03)
		b.set_part(Pt.SLIDE_Y, Vector3.ZERO, 0.0, -h * 0.3)
		b.cylinder(Vector3(reach * 0.15, h - 0.35, 0.0), Vector3(reach * 0.15, h - 1.4, 0.0), 0.02, 5, 0.0, false)
		b.brush(_c(a, "col"))
		b.box(Vector3(reach * 0.15, h - 1.5, 0.0), Vector3(0.3, 0.22, 0.3), 0.02)
		b.clear_part()
	else:
		b.brush(_p(pal, "dark"))
		b.box(Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.4, 1.0), 0.03)
		b.brush(mast)
		b.box(Vector3(0.0, h * 0.5, 0.0), Vector3(0.5, h, 0.5), 0.03)
		b.brush(col)
		b.box(Vector3(reach * 0.5 - 0.7, h + 0.25, 0.0), Vector3(reach + 1.4, 0.34, 0.42), 0.03)
		b.box(Vector3(-1.05, h + 0.25, 0.0), Vector3(0.9, 0.7, 0.7), 0.04)
		b.brush(_p(pal, "glass"), Mat.GLASS)
		b.box(Vector3(0.0, h - 0.4, -0.32), Vector3(0.5, 0.5, 0.2), 0.02)
		b.tier = 1
		b.brush(_p(pal, "metal"), Mat.METAL)
		_beam(b, Vector3(0.0, h + 0.4, 0.0), Vector3(reach * 0.5, h + 0.42, 0.0), 0.05)
		b.tier = 0
		b.set_part(Pt.SLIDE_Y, Vector3.ZERO, 0.0, -h * 0.25)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.cylinder(Vector3(reach - 0.6, h + 0.1, 0.0), Vector3(reach - 0.6, h * 0.35, 0.0), 0.02, 5, 0.0, false)
		b.brush(col)
		b.box(Vector3(reach - 0.6, h * 0.35 - 0.1, 0.0), Vector3(0.3, 0.22, 0.3), 0.02)
		b.clear_part()
	b.pop()


## Flat marking pad: slab plus a painted `mark` (ring, h, x, runway, none) in `col`.
static func _pad(b: ViewMeshBuilder, a: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var sz: Vector3 = _v(a, "size")
	var th: float = maxf(sz.y, 0.02)
	b.brush(_c(a, "base"))
	b.box(c + Vector3(0.0, th * 0.5, 0.0), Vector3(sz.x, th, sz.z), 0.0)
	b.brush(_c(a, "col"))
	var y: float = c.y + th + 0.004
	var r: float = minf(sz.x, sz.z) * 0.5
	match _s(a, "mark"):
		"ring":
			b.cylinder(Vector3(c.x, c.y + th, c.z), Vector3(c.x, y, c.z), r * 0.86, 20, 0.0)
			b.brush(_c(a, "base"))
			b.cylinder(Vector3(c.x, y, c.z), Vector3(c.x, y + 0.004, c.z), r * 0.68, 20, 0.0)
			b.brush(_c(a, "col"))
			b.box(Vector3(c.x, y + 0.004, c.z), Vector3(r * 0.9, 0.006, r * 0.14), 0.0)
			b.box(Vector3(c.x, y + 0.004, c.z), Vector3(r * 0.14, 0.006, r * 0.9), 0.0)
		"h":
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(c.x + sx * r * 0.32, y, c.z), Vector3(r * 0.16, 0.008, r * 1.0), 0.0)
			b.box(Vector3(c.x, y, c.z), Vector3(r * 0.64, 0.008, r * 0.16), 0.0)
		"x":
			for ang: float in [45.0, -45.0]:
				b.push(ViewMeshBuilder.xf(Vector3(c.x, y, c.z), Vector3(0.0, ang, 0.0)))
				b.box(Vector3.ZERO, Vector3(r * 1.5, 0.008, r * 0.14), 0.0)
				b.pop()
		"runway":
			var n: int = clampi(floori(sz.z / 1.4), 1, 12)
			for i in n:
				b.box(Vector3(c.x, y, c.z + (float(i) - float(n - 1) * 0.5) * 1.4), Vector3(0.16, 0.008, 0.7), 0.0)
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(c.x + sx * (sz.x * 0.5 - 0.15), y, c.z), Vector3(0.12, 0.008, sz.z - 0.2), 0.0)


## Observatory / reactor dome on a base ring; `lens` = 1 adds a lit lens on top; `h` 0 = 0.85 r.
static func _dome_shell(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	var h: float = _f(a, "h") if _f(a, "h") > 0.05 else r * 0.85
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, 0.3, 0.0), r * 1.05, 20, 0.02)
	b.brush(_c(a, "col"))
	b.dome(c + Vector3(0.0, 0.3, 0.0), Vector3.UP, r, h, 20, 5)
	b.brush(_c(a, "band"))
	b.cylinder(c + Vector3(0.0, 0.3, 0.0), c + Vector3(0.0, 0.42, 0.0), r * 1.02, 20, 0.0)
	if _f(a, "lens") > 0.0:
		b.brush(_p(pal, "light"), Mat.EMISSIVE)
		b.set_part(Pt.BLINK, Vector3.ZERO, 0.5, 0.0)
		b.dome(c + Vector3(0.0, 0.3 + h * 0.86, 0.0), Vector3.UP, r * 0.28, r * 0.16, 12, 2)
		b.clear_part()


static func _pylon_ring(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	var n: int = clampi(_i(a, "n"), 3, 16)
	var h: float = _f(a, "h")
	for i in n:
		var ang: float = TAU * float(i) / float(n)
		var p: Vector3 = c + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		b.brush(_c(a, "col"))
		b.push(ViewMeshBuilder.xf(p, Vector3(0.0, -rad_to_deg(ang), 0.0)))
		b.tapered_box(Vector3(0.0, h * 0.5, 0.0), Vector2(0.36, 0.36), Vector2(0.22, 0.22), h, Vector2.ZERO, 0.02)
		b.brush(_c(a, "cap"))
		b.box(Vector3(0.0, h + 0.06, 0.0), Vector3(0.3, 0.12, 0.3), 0.01)
		b.pop()
		b.tier = 1
		b.brush(_p(pal, "metal"), Mat.METAL)
		var q: Vector3 = c + Vector3(cos(ang + TAU / float(n)) * r, 0.0, sin(ang + TAU / float(n)) * r)
		_beam(b, p + Vector3(0.0, h * 0.8, 0.0), q + Vector3(0.0, h * 0.8, 0.0), 0.05)
		b.tier = 0


## Elevated launch rail / mass-driver barrel: a yoke on a drum (TURRET of `mount`) and two rails with cross-ties (BARREL of
## `mount`, elevation `elev` degrees baked into the geometry, recoil 0.5 m). Socket muzzle{mount}_0 at the tip.
static func _launch_rail(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var len_m: float = _f(a, "len")
	var w: float = _f(a, "width")
	var mount: int = _i(a, "mount")
	var elev: float = deg_to_rad(_f(a, "elev"))
	var col: Color = _c(a, "col")
	b.set_part(_turret_kind(mount), c)
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(c + Vector3(0.0, -0.4, 0.0), c + Vector3(0.0, 0.1, 0.0), w * 1.5, 16, 0.02)
	b.brush(_p(pal, "base"))
	for sx: float in [-1.0, 1.0]:
		b.box(c + Vector3(sx * (w * 0.85), 0.4, 0.15), Vector3(0.16, 0.9, 0.7), 0.03)
	b.set_part(_barrel_kind(mount), c, 0.0, 0.5, Vector2(c.y + 0.4, c.z))
	b.push(Transform3D(Basis(Vector3.RIGHT, elev), c + Vector3(0.0, 0.4, 0.0)))
	b.brush(col, Mat.METAL)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * w * 0.4, 0.0, -len_m * 0.5 + 0.6), Vector3(0.14, 0.2, len_m), 0.02)
	b.brush(_p(pal, "dark"))
	for i in clampi(floori(len_m / 0.8), 2, 12):
		b.box(Vector3(0.0, -0.05, 0.4 - 0.8 * float(i)), Vector3(w, 0.12, 0.22), 0.01)
	b.brush(_c(a, "glow"), Mat.EMISSIVE)
	b.box(Vector3(0.0, 0.11, -len_m + 0.5), Vector3(w * 0.7, 0.05, 0.18), 0.0)
	b.socket(StringName("muzzle%d_0" % mount), Vector3(0.0, 0.1, -len_m + 0.5), Vector3(0.0, 0.0, -1.0), _barrel_kind(mount))
	b.pop()
	b.clear_part()


## Armoured drum (casemate) for a defence gun: chamfered cylinder, accent lift ring and a dark turret-ring seat on top. The
## turret / gun of the recipe sits at (center.x, center.y + h, center.z).
static func _turret_base(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	var h: float = _f(a, "h")
	b.brush(_c(a, "col"))
	b.cylinder(c, c + Vector3(0.0, h, 0.0), r, 16, 0.06)
	b.brush(_c(a, "ring"))
	b.cylinder(c + Vector3(0.0, h * 0.45, 0.0), c + Vector3(0.0, h * 0.45 + 0.1, 0.0), r * 1.03, 16, 0.0)
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(c + Vector3(0.0, h - 0.02, 0.0), c + Vector3(0.0, h + 0.08, 0.0), r * 0.72, 16, 0.01)
	b.tier = 1
	b.brush(_c(a, "ring"))
	for i in 4:
		var ang: float = PI * 0.5 * float(i) + 0.4
		b.box(c + Vector3(cos(ang) * r * 0.98, h * 0.7, sin(ang) * r * 0.98), Vector3(0.14, 0.14, 0.14), 0.0)
	b.tier = 0


## Team pennant (0.56 x 0.36 m flag, team colour over a dark plate border) on a metal pole; `pos` = pole base.
static func _pennant(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var p: Vector3 = _v(a, "pos")
	var h: float = _f(a, "h")
	var fw: float = _f(a, "w")
	var fl: float = _f(a, "l")
	b.tier = 1
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(p, p + Vector3(0.0, h, 0.0), 0.025, 6, 0.0)
	b.brush(_p(pal, "plate"))
	b.box(p + Vector3(fw * 0.5 + 0.03, h - fl * 0.5 - 0.06, 0.0), Vector3(fw + 0.04, fl + 0.04, 0.03), 0.0)
	b.brush(_p(pal, "base"), Mat.PAINT, 1.0)
	b.box(p + Vector3(fw * 0.5 + 0.03, h - fl * 0.5 - 0.06, 0.0), Vector3(fw, fl, 0.05), 0.0)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(p + Vector3(0.0, h, 0.0), p + Vector3(0.0, h + 0.07, 0.0), 0.045, 6, 0.0)
	b.tier = 0


## Aircraft-warning beacon: a small emissive cube that pulses (BLINK part, `phase` 0..1).
static func _beacon(b: ViewMeshBuilder, a: Dictionary) -> void:
	var p: Vector3 = _v(a, "pos")
	var r: float = _f(a, "r")
	b.set_part(Pt.BLINK, Vector3.ZERO, clampf(_f(a, "phase"), 0.0, 1.0), 0.0)
	b.brush(_c(a, "col"), Mat.EMISSIVE)
	b.box(p + Vector3(0.0, r, 0.0), Vector3(r * 1.6, r * 1.6, r * 1.6), 0.0)
	b.clear_part()


## Roof team plate: dark gasket, pale quiet ring, dark inner gasket, then the team surface (art_direction 5.4.3).
static func _roof_plate(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var sz: Vector3 = _v(a, "size")
	b.brush(_p(pal, "plate"))
	b.box(c + Vector3(0.0, 0.0, 0.0), Vector3(sz.x + 0.24, sz.y, sz.z + 0.24), 0.0)
	b.brush(_p(pal, "sec"))
	b.box(c + Vector3(0.0, 0.004, 0.0), Vector3(sz.x + 0.12, sz.y, sz.z + 0.12), 0.0)
	b.brush(_p(pal, "plate"))
	b.box(c + Vector3(0.0, 0.008, 0.0), Vector3(sz.x + 0.04, sz.y, sz.z + 0.04), 0.0)
	b.brush(_p(pal, "base"), Mat.PAINT, 1.0)
	b.box(c + Vector3(0.0, 0.012, 0.0), sz, 0.0)


static func _conveyor(b: ViewMeshBuilder, a: Dictionary) -> void:
	var p0: Vector3 = _v(a, "from")
	var p1: Vector3 = _v(a, "to")
	var w: float = _f(a, "w")
	b.brush(_c(a, "col"))
	_beam(b, p0, p1, w, 0.2, 0.01)
	b.brush(_c(a, "belt"), Mat.RUBBER)
	_beam(b, p0 + Vector3(0.0, 0.1, 0.0), p1 + Vector3(0.0, 0.1, 0.0), w * 0.8, 0.03)
	b.tier = 1
	b.brush(_c(a, "col"))
	for sx: float in [-1.0, 1.0]:
		var off: Vector3 = (p1 - p0).cross(Vector3.UP).normalized() * sx * w * 0.5
		_beam(b, p0 + off + Vector3(0.0, 0.1, 0.0), p1 + off + Vector3(0.0, 0.1, 0.0), 0.04, 0.16)
	b.tier = 0


## Intake funnel (inverted frustum on a short throat).
static func _funnel(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	var h: float = _f(a, "h")
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, h * 0.35, 0.0), r * 0.4, 10, 0.0)
	b.brush(_c(a, "col"))
	b.frustum(c + Vector3(0.0, h * 0.3, 0.0), c + Vector3(0.0, h, 0.0), r * 0.42, r, 14, false)
	b.brush(Color(0.05, 0.05, 0.05))
	b.cylinder(c + Vector3(0.0, h - 0.06, 0.0), c + Vector3(0.0, h - 0.04, 0.0), r * 0.9, 14, 0.0)


## Lattice tower: four tilted legs, horizontal rings per bay, diagonal braces; base square `w0`, top square `w1`.
static func _lattice(b: ViewMeshBuilder, a: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var h: float = _f(a, "h")
	var w0: float = _f(a, "w0") * 0.5
	var w1: float = _f(a, "w1") * 0.5
	var bays: int = clampi(_i(a, "bays"), 1, 10)
	b.brush(_c(a, "col"))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_beam(b, c + Vector3(sx * w0, 0.0, sz * w0), c + Vector3(sx * w1, h, sz * w1), 0.1)
	b.brush(_c(a, "brace"), Mat.METAL)
	for k in bays + 1:
		var t: float = float(k) / float(bays)
		var ww: float = lerpf(w0, w1, t)
		var y: float = h * t
		b.tier = 0 if k % 2 == 0 else 1
		for s in 4:
			var ang: float = PI * 0.5 * float(s)
			var mid: Vector3 = c + Vector3(cos(ang), 0.0, sin(ang)) * ww + Vector3(0.0, y, 0.0)
			_beam(b, mid + Vector3(-sin(ang), 0.0, cos(ang)) * ww, mid - Vector3(-sin(ang), 0.0, cos(ang)) * ww, 0.05)
	b.tier = 1
	for k in bays:
		var t0: float = float(k) / float(bays)
		var t1: float = float(k + 1) / float(bays)
		var wa: float = lerpf(w0, w1, t0)
		var wb: float = lerpf(w0, w1, t1)
		var sgn: float = 1.0 if k % 2 == 0 else -1.0
		for s in 4:
			var ang: float = PI * 0.5 * float(s)
			var ux: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
			var uz: Vector3 = Vector3(-sin(ang), 0.0, cos(ang))
			_beam(b, c + ux * wa + uz * wa * sgn + Vector3(0.0, h * t0, 0.0), c + ux * wb - uz * wb * sgn + Vector3(0.0, h * t1, 0.0), 0.04)
	b.tier = 0


# ---------------------------------------------------------------------------------------------- ships
const _BOW_POINTS: Dictionary = {
	"sharp": [[-0.86, 0.5], [0.86, 0.5], [1.0, 0.3], [1.0, -0.10], [0.55, -0.36], [0.0, -0.5], [-0.55, -0.36], [-1.0, -0.10], [-1.0, 0.3]],
	"blunt": [[-0.9, 0.5], [0.9, 0.5], [1.0, 0.35], [1.0, -0.30], [0.92, -0.5], [-0.92, -0.5], [-1.0, -0.30], [-1.0, 0.35]],
	"round": [[-0.8, 0.5], [0.8, 0.5], [1.0, 0.3], [1.0, -0.15], [0.8, -0.38], [0.42, -0.5], [-0.42, -0.5], [-0.8, -0.38], [-1.0, -0.15], [-1.0, 0.3]],
}


static func _hull_loop(pts: Array, bw: float, len_m: float, sx: float, sz: float, y: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for pv: Variant in pts:
		var p: Array = pv as Array
		out.append(Vector3((p[0] as float) * bw * sx, y, (p[1] as float) * len_m * sz))
	return out


## Convex ship hull: keel -> waterline (`low` antifouling) -> deck (`col`), accent waterline stripe, dark deck plate. `bow` sharp |
## blunt | round. The deck is at y = freeboard, the keel at y = -draft. Ships face -Z.
static func _hull_ship(b: ViewMeshBuilder, a: Dictionary) -> String:
	var bow: String = _s(a, "bow")
	if not _BOW_POINTS.has(bow):
		return "hull_ship: unknown bow '%s' (sharp, blunt, round)" % bow
	var pts: Array = _BOW_POINTS[bow] as Array
	var l: float = _f(a, "len")
	var bw: float = _f(a, "beam") * 0.5
	var dr: float = maxf(_f(a, "draft"), 0.1)
	var fb: float = maxf(_f(a, "freeboard"), 0.2)
	var keel: PackedVector3Array = _hull_loop(pts, bw, l, 0.5, 0.94, -dr)
	var wl: PackedVector3Array = _hull_loop(pts, bw, l, 0.95, 0.985, 0.0)
	var deck: PackedVector3Array = _hull_loop(pts, bw, l, 1.0, 1.0, fb)
	b.ao = 0.6
	b.brush(_c(a, "low"))
	b.prism(keel, wl, 0.03)
	b.ao = 1.0
	b.brush(_c(a, "col"))
	b.prism(wl, deck, 0.03)
	b.brush(_c(a, "stripe"))
	b.tier = 1
	b.prism(_hull_loop(pts, bw, l, 0.955, 0.988, -0.02), _hull_loop(pts, bw, l, 0.962, 0.99, 0.14), 0.0)
	b.tier = 0
	b.brush(_c(a, "deck"))
	b.prism(_hull_loop(pts, bw, l, 0.88, 0.94, fb - 0.01), _hull_loop(pts, bw, l, 0.88, 0.94, fb + 0.045), 0.0)
	return ""


## Stepped deckhouse (`tiers` boxes narrowing upward) with glazed bridge strips, a mast and an optional rotating radar bar.
static func _superstructure(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var l: float = _f(a, "len")
	var w: float = _f(a, "wid")
	var nt: int = clampi(_i(a, "tiers"), 1, 5)
	var th: float = _f(a, "tier_h")
	var col: Color = _c(a, "col")
	var top_y: float = c.y
	var top_z: float = c.z
	var top_l: float = l
	for k in nt:
		var tl: float = l * (1.0 - 0.2 * float(k))
		var tw: float = w * (1.0 - 0.16 * float(k))
		var y: float = c.y + th * (float(k) + 0.5)
		var zc: float = c.z + 0.1 * float(k) * l * 0.5
		b.brush(col if k % 2 == 0 else col.lightened(0.08))
		b.box(Vector3(c.x, y, zc), Vector3(tw, th, tl), 0.03)
		b.tier = 1
		b.brush(_p(pal, "glass"), Mat.GLASS)
		b.box(Vector3(c.x, y + th * 0.08, zc - tl * 0.5 - 0.005), Vector3(tw * 0.82, th * 0.34, 0.03), 0.0)
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(c.x + sx * (tw * 0.5 + 0.005), y + th * 0.08, zc - tl * 0.1), Vector3(0.03, th * 0.3, tl * 0.5), 0.0)
		b.tier = 0
		top_y = y + th * 0.5
		top_z = zc
		top_l = tl
	b.brush(_p(pal, "dark"))
	b.box(Vector3(c.x, top_y + 0.03, top_z), Vector3(w * 0.5, 0.06, top_l * 0.7), 0.0)
	if _f(a, "mast") > 0.0:
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.cylinder(Vector3(c.x, top_y, top_z + top_l * 0.1), Vector3(c.x, top_y + th * 1.3, top_z + top_l * 0.1), 0.035, 6, 0.0)
		if _f(a, "radar") > 0.0:
			var pv: Vector3 = Vector3(c.x, top_y + th * 1.35, top_z + top_l * 0.1)
			b.set_part(Pt.RADAR, pv)
			b.brush(_p(pal, "sec"))
			b.box(pv, Vector3(w * 0.8, 0.05, 0.11), 0.01)
			b.brush(_p(pal, "acc"))
			b.box(pv + Vector3(w * 0.32, 0.04, 0.0), Vector3(0.16, 0.04, 0.09), 0.0)
			b.clear_part()
		else:
			b.brush(_p(pal, "light"), Mat.EMISSIVE)
			b.box(Vector3(c.x, top_y + th * 1.32, top_z + top_l * 0.1), Vector3(0.07, 0.07, 0.07), 0.0)


## Vertical launch cells: dark bed and a grid of lidded cells (`rows` along Z, `cols` along X), centred at `center`.
static func _vls(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var rows: int = clampi(_i(a, "rows"), 1, 10)
	var cols: int = clampi(_i(a, "cols"), 1, 8)
	var p: float = _f(a, "pitch")
	b.brush(_p(pal, "dark"))
	b.box(c + Vector3(0.0, 0.02, 0.0), Vector3(float(cols) * p + 0.08, 0.04, float(rows) * p + 0.08), 0.0)
	b.tier = 1
	for r in rows:
		for k in cols:
			var pos: Vector3 = c + Vector3((float(k) - float(cols - 1) * 0.5) * p, 0.06, (float(r) - float(rows - 1) * 0.5) * p)
			b.brush(_p(pal, "metal"), Mat.METAL)
			b.box(pos, Vector3(p * 0.82, 0.05, p * 0.82), 0.0)
			b.brush(_p(pal, "acc"))
			b.box(pos + Vector3(0.0, 0.03, 0.0), Vector3(p * 0.3, 0.012, p * 0.3), 0.0)
	b.tier = 0


## Deck gun: drum + housing (TURRET of `mount`) and `barrels` barrels along X (BARREL of `mount`, elevation-capable, recoil
## 0.25 m); sockets muzzle{mount}_{i} at every muzzle. `pos` = drum base on the deck.
static func _ship_turret(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var p: Vector3 = _v(a, "pos")
	var r: float = _f(a, "r")
	var mount: int = _i(a, "mount")
	var nb: int = clampi(_i(a, "barrels"), 1, 3)
	var len_m: float = _f(a, "len")
	var br: float = _f(a, "br")
	var s: float = r / 0.42
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(p, p + Vector3(0.0, 0.14 * s, 0.0), r * 0.82, 14, 0.01)
	b.set_part(_turret_kind(mount), p + Vector3(0.0, 0.14 * s, 0.0))
	b.brush(_c(a, "col"))
	b.tapered_box(p + Vector3(0.0, 0.32 * s, 0.0), Vector2(r * 1.2, r * 1.65), Vector2(r * 0.9, r * 1.3), 0.36 * s, Vector2(0.0, r * 0.12), 0.03)
	b.brush(_p(pal, "dark"))
	b.box(p + Vector3(0.0, 0.5 * s, r * 0.08), Vector3(r * 0.5, 0.02, r * 0.7), 0.0)
	var ty: float = p.y + 0.36 * s
	var pv: Vector3 = p + Vector3(0.0, 0.14 * s, 0.0)
	b.set_part(_barrel_kind(mount), pv, 1.0, 0.25, Vector2(ty, p.z))
	b.brush(_p(pal, "metal"), Mat.METAL)
	for k in nb:
		var ox: float = (float(k) - float(nb - 1) * 0.5) * br * 2.9
		b.cylinder(Vector3(ox, ty, p.z - r * 0.6), Vector3(ox, ty, p.z - r * 0.6 - len_m), br, 8, 0.0)
		b.cylinder(Vector3(ox, ty, p.z - r * 0.6 - len_m + 0.04), Vector3(ox, ty, p.z - r * 0.6 - len_m - 0.05), br * 1.4, 8, 0.0)
		b.socket(StringName("muzzle%d_%d" % [mount, k]), Vector3(ox, ty, p.z - r * 0.6 - len_m - 0.05), Vector3(0.0, 0.0, -1.0), _barrel_kind(mount))
	b.clear_part()


## Carrier flight deck slab with centre / edge lines, landing box and `lifts` elevator platforms (SLIDE_Y, rise 0.5 m).
static func _flight_deck(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var l: float = _f(a, "len")
	var w: float = _f(a, "wid")
	var th: float = _f(a, "thick")
	var mark: Color = _c(a, "mark")
	b.brush(_c(a, "col"))
	b.box(c + Vector3(0.0, th * 0.5, 0.0), Vector3(w, th, l), 0.03)
	var y: float = c.y + th + 0.004
	b.tier = 1
	b.brush(mark)
	var n: int = clampi(floori(l / 1.0), 2, 14)
	for i in n:
		b.box(Vector3(c.x, y, c.z + (float(i) - float(n - 1) * 0.5) * (l / float(n))), Vector3(0.12, 0.008, l / float(n) * 0.5), 0.0)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(c.x + sx * (w * 0.5 - 0.14), y, c.z), Vector3(0.08, 0.008, l - 0.4), 0.0)
	b.brush(_p(pal, "acc"))
	b.box(Vector3(c.x, y, c.z - l * 0.32), Vector3(w * 0.5, 0.008, 0.1), 0.0)
	b.box(Vector3(c.x, y, c.z - l * 0.32 - 0.7), Vector3(w * 0.5, 0.008, 0.1), 0.0)
	b.tier = 0
	var nl: int = clampi(_i(a, "lifts"), 0, 3)
	for i in nl:
		var lz: float = c.z + l * (0.25 - 0.3 * float(i))
		b.set_part(Pt.SLIDE_Y, Vector3.ZERO, 0.0, 0.5)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.box(Vector3(c.x + (w * 0.18 if i % 2 == 0 else -w * 0.18), c.y + th + 0.01, lz), Vector3(w * 0.32, 0.03, l * 0.14), 0.0)
		b.clear_part()


static func _deck_drones(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var n: int = clampi(_i(a, "n"), 1, 16)
	var cols: int = clampi(_i(a, "cols"), 1, 6)
	var p: float = _f(a, "pitch")
	var rows: int = ceili(float(n) / float(cols))
	for i in n:
		var pos: Vector3 = c + Vector3((float(i % cols) - float(cols - 1) * 0.5) * p, 0.0, (float(i / cols) - float(rows - 1) * 0.5) * p)
		b.brush(_p(pal, "sec"))
		b.box(pos + Vector3(0.0, 0.07, 0.0), Vector3(0.16, 0.1, 0.34), 0.015)
		b.brush(_p(pal, "base"), Mat.PAINT, 1.0)
		b.box(pos + Vector3(0.0, 0.125, 0.0), Vector3(0.1, 0.02, 0.16), 0.0)
		b.tier = 1
		b.brush(_p(pal, "metal"), Mat.METAL)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.cylinder(pos + Vector3(sx * 0.15, 0.1, sz * 0.13), pos + Vector3(sx * 0.15, 0.115, sz * 0.13), 0.09, 8, 0.0)
		b.tier = 0


## Submarine sail (conning tower) with dive planes and a raised periscope / radar mast (RADAR part).
static func _sail(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var p: Vector3 = _v(a, "pos")
	var h: float = _f(a, "h")
	var l: float = _f(a, "len")
	var w: float = _f(a, "w")
	b.brush(_c(a, "col"))
	b.tapered_box(p + Vector3(0.0, h * 0.5, 0.0), Vector2(w, l), Vector2(w * 0.72, l * 0.62), h, Vector2(0.0, -l * 0.08), 0.05)
	b.brush(_p(pal, "dark"))
	for sx: float in [-1.0, 1.0]:
		b.box(p + Vector3(sx * (w * 0.5 + 0.28), h * 0.62, -l * 0.1), Vector3(0.55, 0.05, 0.4), 0.01)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(p + Vector3(0.0, h, l * 0.05), p + Vector3(0.0, h + 0.55, l * 0.05), 0.03, 6, 0.0)
	var pv: Vector3 = p + Vector3(0.0, h + 0.58, l * 0.05)
	b.set_part(Pt.RADAR, pv)
	b.brush(_p(pal, "sec"))
	b.box(pv, Vector3(0.36, 0.03, 0.07), 0.0)
	b.clear_part()
