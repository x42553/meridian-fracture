class_name ViewRecipeMacros
extends RefCounted
## Native composite builders callable from recipes as `{"call": name, "args": {...}}` (render spec 5.8.5): common, running gear,
## hull and armour, weapons, sensors, infantry, air. Structure / ship macros live in ViewMacrosStructures (VIEW-M4).
##
## Every macro takes ARGUMENTS BY NAME with a typed signature (SIGS): n number, v vec3, w vec2, c colour (palette key, hex or
## expression), s string, A number list. All arguments have a default, so recipes only state what differs. The interpreter
## evaluates the arguments, calls run() and restores brush / tier / part state afterwards; macros still finish with
## clear_part() and never leave a part open. Pure functions of (args, palette): thread-safe, no engine singletons.
## Coordinates: +X right, +Y up, -Z forward, metres, origin on the ground. Palette keys used: base dark sec acc metal rubber
## glass light plate.

const Mat := ViewMeshBuilder.Mat
const Pt := ViewMeshBuilder.Part
const SKIN: Color = Color(0.72, 0.52, 0.38)

## name -> "arg:type[=default] ..."; vec defaults are comma separated. Missing default: n 0, v 0,0,0, w 0,0, c base, s "", A [].
const SIGS: Dictionary = {
	# common
	"hatch": "c:v r:n=0.15 body:c=sec ring:c=acc",
	"whip": "base:v tip:v=0,1,0 r:n=0.012 col:c=metal",
	"team_panel": "center:v size:v col:c=base",
	"light_pair": "center:v spacing:n=1 size:v=0.2,0.09,0.05 col:c=light",
	"vent": "center:v size:v=0.6,0.05,0.4 slats:n=4",
	"pipe": "from:v to:v=0,1,0 r:n=0.03 col:c=metal",
	"greeble_patch": "center:v hu:n=0.4 hv:n=0.4 count:n=4",
	"hazard_stripes": "center:v size:v=1,0.03,0.3 n:n=6",
	# running gear
	"track_run": "x:n=0.88 width:n=0.46 z_front:n=1.33 z_rear:n=-1.31 sprocket_r:n=0.34 road_n:n=5 road_r:n=0.3 tk:n=0.07",
	"wheel_row": "x:n=0.88 z0:n=-1 z1:n=1 n:n=3 r:n=0.35 width:n=0.3 detail:n=1",
	"axles": "x:n=0.88 zs:A r:n=0.4 width:n=0.32 arch:n=1",
	"swing_wheels": "x:n=0.9 zs:A r:n=0.36",
	"crawler_pods": "x:n=1 zs:A w:n=0.5 h:n=0.7",
	"hover_skirt": "len:n=3.5 wid:n=2.2 h:n=0.5",
	# hull and armour
	"hull": "profile:s=wedge half_w:n=0.9 bevel:n=0.05 len:n=3.5 top:n=1.1 col:c=base",
	"skirt": "kind:s=modules x:n=1.17 y:n=0.7 len:n=3.5 h:n=0.4",
	"plates": "kind:s=bolted center:v size:v=1,0.05,1 n:n=4",
	"container": "center:v size:v=1.4,0.55,1 col:c=sec",
	"mount_plate": "center:v size:v=0.5,0.05,0.5",
	# weapons
	"turret_ngon": "pivot:v n:n=8 rot:n=22.5 hw:n=0.74 hl:n=0.96 h:n=0.42 top:n=0.72 shift:n=0.06 y0:n=1.23 mount:n=0",
	"gun": "mount:n=0 pivot:v y:n=1.4 z:n=0 len:n=2 r:n=0.075 muzzle:s=brake elev:n=0 recoil:n=0.32",
	"rws": "center:v mount:n=0",
	"missile_rack": "center:v cols:n=2 rows:n=2 elev:n=35 mount:n=0",
	"rocket_pods": "center:v cols:n=3 rows:n=2",
	"launcher_tube": "center:v len:n=1.2",
	"flak_twin": "center:v",
	"dome_emitter": "center:v r:n=0.4",
	"spade_pair": "z:n=2 x:n=0.62",
	"outriggers": "z:n=0 span:n=2.6",
	# sensors
	"sensor_mast": "base:v h:n=1 folded:n=0.4",
	"sensor_crown": "center:v n:n=6 r:n=0.16",
	"radar_dish": "center:v r:n=0.4 spin:n=1",
	"ball_sensor": "center:v r:n=0.25",
	# infantry
	"soldier": "x:n=0 z:n=0 phase:n=0 member:n=0 count:n=1 kit:s=rifle helmet:s=round pack:s=small",
	"squad": "n:n=4 layout:s=circle spread:n=0.55 kit:s=rifle helmet:s=round",
	# air
	"fuselage": "profile:s=heli len:n=3.6 half_w:n=0.56 h:n=1",
	"wing": "span:n=4 chord:n=1.2 sweep:n=0.5 thick:n=0.1 fold:n=0 y:n=1 z:n=0",
	"rotor_main": "hub:v blades:n=4 radius:n=2.5 chord:n=0.24",
	"rotor_tail": "pos:v",
	"tilt_nacelle": "pos:v r:n=0.3",
	"nozzle": "pos:v r:n=0.2",
	"gear": "pos:v",
	"drone_body": "center:v r:n=0.35 arms:n=4",
}

static var _sig_cache: Dictionary = {}
static var _sig_lock: Mutex = Mutex.new()


## Parsed signature of a macro: arg name -> [type letter, default (float | Array | String)]; empty when unknown.
static func signature(macro: String) -> Dictionary:
	if not SIGS.has(macro):
		return ViewMacrosStructures.signature(macro)  # structure / ship / landmark macros (VIEW-M4)
	_sig_lock.lock()
	var got: Variant = _sig_cache.get(macro)
	if got == null:
		got = _parse_sig(SIGS[macro] as String)
		_sig_cache[macro] = got
	_sig_lock.unlock()
	return got as Dictionary


static func macro_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(SIGS.keys())
	out.sort()
	return out


## Parses a SIGS entry ("arg:type[=default] ...") into arg name -> [type letter, default]. Shared with ViewMacrosStructures.
static func parse_sig(src: String) -> Dictionary:
	return _parse_sig(src)


static func _parse_sig(src: String) -> Dictionary:
	var out: Dictionary = {}
	for tok: String in src.split(" ", false):
		var eq: int = tok.find("=")
		var head: String = tok if eq < 0 else tok.substr(0, eq)
		var dflt: String = "" if eq < 0 else tok.substr(eq + 1)
		var colon: int = head.find(":")
		var name: String = head.substr(0, colon)
		var t: String = head.substr(colon + 1)
		var val: Variant
		match t:
			"n":
				val = dflt.to_float() if eq >= 0 else 0.0
			"v":
				val = _floats(dflt if eq >= 0 else "0,0,0")
			"w":
				val = _floats(dflt if eq >= 0 else "0,0")
			"c":
				val = dflt if eq >= 0 else "base"
			"s":
				val = dflt
			_:
				val = _floats(dflt)
		out[name] = [t, val]
	return out


static func _floats(s: String) -> Array:
	var out: Array = []
	for p: String in s.split(",", false):
		out.append(p.to_float())
	return out


## Runs macro `macro` with evaluated arguments; returns "" or an error message.
static func run(macro: String, b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> String:
	match macro:
		"hatch": _hatch(b, a)
		"whip": _whip(b, a)
		"team_panel": _team_panel(b, pal, _v(a, "center"), _v(a, "size"), _c(a, "col"))
		"light_pair": _light_pair(b, a)
		"vent": _vent(b, a, pal)
		"pipe": _pipe(b, a)
		"greeble_patch": _greeble_patch(b, a, pal)
		"hazard_stripes": _hazard(b, a, pal)
		"track_run": _track_run(b, a, pal)
		"wheel_row": _wheel_row(b, a, pal)
		"axles": _axles(b, a, pal)
		"swing_wheels": _swing_wheels(b, a, pal)
		"crawler_pods": _crawler_pods(b, a, pal)
		"hover_skirt": _hover_skirt(b, a, pal)
		"hull": _hull(b, a)
		"skirt": _skirt(b, a, pal)
		"plates": _plates(b, a, pal)
		"container": _container(b, a, pal)
		"mount_plate": _mount_plate(b, a, pal)
		"turret_ngon": _turret_ngon(b, a, pal)
		"gun": _gun(b, a, pal)
		"rws": _rws(b, a, pal)
		"missile_rack": _missile_rack(b, a, pal)
		"rocket_pods": _rocket_pods(b, a, pal)
		"launcher_tube": _launcher_tube(b, a, pal)
		"flak_twin": _flak_twin(b, a, pal)
		"dome_emitter": _dome_emitter(b, a, pal)
		"spade_pair": _spade_pair(b, a, pal)
		"outriggers": _outriggers(b, a, pal)
		"sensor_mast": _sensor_mast(b, a, pal)
		"sensor_crown": _sensor_crown(b, a, pal)
		"radar_dish": _radar_dish(b, a, pal)
		"ball_sensor": _ball_sensor(b, a, pal)
		"soldier": _soldier(b, a, pal)
		"squad": return _squad(b, a, pal)
		"fuselage": return _fuselage(b, a, pal)
		"wing": _wing(b, a, pal)
		"rotor_main": _rotor_main(b, a, pal)
		"rotor_tail": _rotor_tail(b, a, pal)
		"tilt_nacelle": _tilt_nacelle(b, a, pal)
		"nozzle": _nozzle(b, a, pal)
		"gear": _gear(b, a, pal)
		"drone_body": _drone_body(b, a, pal)
		_:
			return ViewMacrosStructures.run(macro, b, a, pal)  # structure / ship / landmark macros (VIEW-M4)
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


static func _hash01(i: int) -> float:
	var h: int = (i * 2654435761 + 40503) & 0xFFFFFFFF
	h = ((h >> 15) ^ h) * 2246822519 & 0xFFFFFFFF
	h = ((h >> 13) ^ h) * 3266489917 & 0xFFFFFFFF
	return float((h >> 8) & 0xFFFF) / 65536.0


# ---------------------------------------------------------------------------------------------- common
static func _hatch(b: ViewMeshBuilder, a: Dictionary) -> void:
	var c: Vector3 = _v(a, "c")
	var r: float = _f(a, "r")
	b.brush(_c(a, "ring"))
	b.cylinder(c, c + Vector3(0.0, 0.05, 0.0), r * 1.12, 14, 0.01)
	b.brush(_c(a, "body"))
	b.cylinder(c + Vector3(0.0, 0.05, 0.0), c + Vector3(0.0, 0.085, 0.0), r * 0.92, 14, 0.012)


static func _whip(b: ViewMeshBuilder, a: Dictionary) -> void:
	b.tier = 1
	b.brush(_c(a, "col"), Mat.METAL)
	b.cylinder(_v(a, "base"), _v(a, "tip"), _f(a, "r"), 5, 0.0, false)


## Team surface over a dark `plate` border 2 cm wider than the surface, so any player colour separates from any hull paint.
static func _team_panel(b: ViewMeshBuilder, pal: Dictionary, center: Vector3, size: Vector3, col: Color) -> void:
	b.brush(_p(pal, "plate"))
	b.box(center + Vector3(0.0, -0.004, 0.0), Vector3(size.x + 0.04, size.y, size.z + 0.04), 0.0)
	b.brush(col, Mat.PAINT, 1.0)
	b.box(center + Vector3(0.0, 0.002, 0.0), size, 0.0)


static func _light_pair(b: ViewMeshBuilder, a: Dictionary) -> void:
	b.brush(_c(a, "col"), Mat.EMISSIVE)
	var c: Vector3 = _v(a, "center")
	for sx: float in [-1.0, 1.0]:
		b.box(c + Vector3(sx * _f(a, "spacing") * 0.5, 0.0, 0.0), _v(a, "size"), 0.0)


static func _vent(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var n: int = maxi(_i(a, "slats"), 1)
	var pk: Array[Rect2] = []
	for i in n:
		pk.append(Rect2(0.08, 0.08 + 0.84 * float(i) / float(n), 0.84, 0.84 / float(n) * 0.55))
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.pocket_box(_v(a, "center"), _v(a, "size"), pk, 0.03)


static func _pipe(b: ViewMeshBuilder, a: Dictionary) -> void:
	b.brush(_c(a, "col"), Mat.METAL)
	b.cylinder(_v(a, "from"), _v(a, "to"), _f(a, "r"), 8, 0.0, true)


static func _greeble_patch(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.greebles(_v(a, "center"), Vector3.UP, Vector3(_f(a, "hu"), 0.0, 0.0), Vector3(0.0, 0.0, _f(a, "hv")), _i(a, "count"), 0.1, 0.2, 0.03, 0.08)


static func _hazard(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var sz: Vector3 = _v(a, "size")
	var n: int = maxi(_i(a, "n"), 1)
	var c: Vector3 = _v(a, "center")
	var w: float = sz.x / float(n)
	for i in n:
		b.brush(_p(pal, "acc") if i % 2 == 0 else _p(pal, "dark"))
		b.box(c + Vector3(-sz.x * 0.5 + w * (float(i) + 0.5), 0.0, 0.0), Vector3(w, sz.y, sz.z), 0.0)


# ---------------------------------------------------------------------------------------------- running gear
static func _track_run(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var x: float = _f(a, "x")
	var w: float = _f(a, "width")
	var zf: float = maxf(_f(a, "z_front"), _f(a, "z_rear"))
	var zr: float = minf(_f(a, "z_front"), _f(a, "z_rear"))
	var sr: float = _f(a, "sprocket_r")
	var rr: float = _f(a, "road_r")
	var tk: float = _f(a, "tk")
	var n: int = maxi(_i(a, "road_n"), 1)
	var rubber: Color = _p(pal, "rubber")
	var metal: Color = _p(pal, "metal")
	var br: float = sr + 0.06
	var yc: float = br + tk
	b.brush(rubber, Mat.RUBBER)
	b.set_part(Pt.TRACK)
	var circles: Array[Vector3] = [Vector3(zf, yc, br), Vector3(zr, yc, br)]
	b.track_belt(x, w, circles, tk)
	b.clear_part()
	b.ao = 0.75
	b.wheel(Vector3(x, yc, zf), sr, w * 0.78, rubber, metal, 1, 12)
	b.wheel(Vector3(x, yc, zr), sr, w * 0.78, rubber, metal, 1, 12)
	for i in n:
		var z: float = lerpf(zr + sr + 0.22, zf - sr - 0.24, float(i) / float(maxi(n - 1, 1)))
		b.wheel(Vector3(x, rr + tk, z), rr, w * 0.8, rubber, metal, 0, 10)
	b.ao = 1.0
	b.brush(_p(pal, "dark"))
	b.box(Vector3(x, 2.0 * sr + 0.205 + tk, (zf + zr) * 0.5), Vector3(w + 0.16, 0.045, zf - zr + 0.56), 0.015)


static func _wheel_row(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var n: int = maxi(_i(a, "n"), 1)
	var r: float = _f(a, "r")
	b.ao = 0.7
	for i in n:
		var z: float = lerpf(_f(a, "z0"), _f(a, "z1"), float(i) / float(maxi(n - 1, 1)))
		b.wheel(Vector3(_f(a, "x"), r, z), r, _f(a, "width"), _p(pal, "rubber"), _p(pal, "metal"), _i(a, "detail"), 14)
	b.ao = 1.0


static func _axles(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var zs: Array = a["zs"] as Array
	var x: float = _f(a, "x")
	var r: float = _f(a, "r")
	for zv: Variant in zs:
		var z: float = zv as float
		b.ao = 0.7
		b.wheel(Vector3(x, r, z), r, _f(a, "width"), _p(pal, "rubber"), _p(pal, "metal"), 2, 14)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.box(Vector3(x - signf(x) * 0.26, r + 0.02, z), Vector3(0.36, 0.06, 0.10), 0.0)
		b.ao = 1.0
		if _f(a, "arch") != 0.0:
			b.brush(_p(pal, "dark"))
			b.box(Vector3(x - signf(x) * 0.02, 2.0 * r + 0.06, z), Vector3(0.34, 0.06, r * 2.4), 0.02)


static func _swing_wheels(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var x: float = _f(a, "x")
	var r: float = _f(a, "r")
	for zv: Variant in a["zs"] as Array:
		var z: float = zv as float
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.push(ViewMeshBuilder.xf(Vector3(x * 0.62, r + 0.12, z), Vector3(0.0, 0.0, -18.0 * signf(x))))
		b.box(Vector3.ZERO, Vector3(x * 0.8, 0.09, 0.14), 0.01)
		b.pop()
		b.ao = 0.7
		b.wheel(Vector3(x, r, z), r, 0.30, _p(pal, "rubber"), _p(pal, "metal"), 2, 14)
		b.ao = 1.0


static func _crawler_pods(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var w: float = _f(a, "w")
	var h: float = _f(a, "h")
	for zv: Variant in a["zs"] as Array:
		b.brush(_p(pal, "dark"))
		b.ao = 0.75
		b.box(Vector3(_f(a, "x"), h * 0.5, zv as float), Vector3(w, h, w * 1.5), 0.05)
		b.brush(_p(pal, "rubber"), Mat.RUBBER)
		b.box(Vector3(_f(a, "x"), h * 0.16, zv as float), Vector3(w * 1.08, h * 0.32, w * 1.6), 0.04)
		b.ao = 1.0


static func _hover_skirt(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var h: float = _f(a, "h")
	b.brush(_p(pal, "rubber"), Mat.RUBBER)
	b.tapered_box(Vector3(0.0, h * 0.5, 0.0), Vector2(_f(a, "wid"), _f(a, "len") + 0.3), Vector2(_f(a, "wid") - 0.15, _f(a, "len") + 0.15), h, Vector2.ZERO, 0.06)


# ---------------------------------------------------------------------------------------------- hull and armour
static func _hull(b: ViewMeshBuilder, a: Dictionary) -> void:
	var hl: float = _f(a, "len") * 0.5
	var hw: float = _f(a, "half_w")
	var top: float = _f(a, "top")
	var prof: PackedVector2Array
	match _s(a, "profile"):
		"slab":
			prof = PackedVector2Array([Vector2(-hl, 0.55), Vector2(-hl, top), Vector2(hl - 0.15, top), Vector2(hl, top - 0.2), Vector2(hl, 0.55)])
		"boxy":
			prof = PackedVector2Array([Vector2(-hl, 0.55), Vector2(-hl, top), Vector2(hl, top), Vector2(hl, 0.55)])
		"walker":
			prof = PackedVector2Array([Vector2(-hl * 0.8, 0.9), Vector2(-hl, top * 0.7), Vector2(-hl * 0.6, top), Vector2(hl * 0.6, top), Vector2(hl, top * 0.75), Vector2(hl * 0.8, 0.9)])
		"boat":
			prof = PackedVector2Array([Vector2(-hl, 0.3), Vector2(-hl, top), Vector2(hl * 0.4, top), Vector2(hl, top * 0.6), Vector2(hl * 0.8, 0.3)])
		_:
			prof = PackedVector2Array([Vector2(-hl, 0.86), Vector2(-hl, top - 0.10), Vector2(-hl + 0.5, top), Vector2(hl - 0.75, top), Vector2(hl, 0.92), Vector2(hl - 0.05, 0.86)])
	b.brush(_c(a, "col"))
	b.extrude(prof, -hw, hw, _f(a, "bevel"))


static func _skirt(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var x: float = _f(a, "x")
	var y: float = _f(a, "y")
	var h: float = _f(a, "h")
	var length: float = _f(a, "len")
	var hl: float = length * 0.5
	var base: Color = _p(pal, "base")
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	match _s(a, "kind"):
		"modules":
			var n: int = 6 if length > 3.2 else 5
			var seg: float = (length - 0.5) / float(n)
			for i in n:
				var z: float = -hl + 0.25 + seg * (float(i) + 0.5)
				b.brush(base if i % 2 == 0 else sec, Mat.PAINT, 1.0 if i == 0 else 0.0)
				b.box(Vector3(x, y, z), Vector3(0.09, h, seg - 0.07), 0.02)
				b.brush(acc)
				b.box(Vector3(x, y + h * 0.5 + 0.015, z), Vector3(0.10, 0.04, seg - 0.07), 0.0)
		"slab":
			b.brush(base)
			b.box(Vector3(x - 0.01, y + 0.02, hl * 0.09), Vector3(0.06, h * 0.9, length * 0.72), 0.02)
			b.brush(acc)
			b.box(Vector3(x - 0.005, y + h * 0.45 + 0.02, hl * 0.09), Vector3(0.07, 0.03, length * 0.72), 0.0)
		"layered":
			for i in 3:
				b.brush(base if i != 1 else sec)
				b.box(Vector3(x + 0.03 * float(i), y + 0.02 - 0.11 * float(i - 1), 0.1), Vector3(0.05, h * 0.42, length * (0.78 - 0.08 * float(i))), 0.015)
		"cage":
			b.brush(_p(pal, "metal"), Mat.METAL)
			b.tier = 1
			for i in 6:
				b.box(Vector3(x, y, -hl + 0.4 + (length - 0.8) * float(i) / 5.0), Vector3(0.04, h, 0.04), 0.0)
			b.box(Vector3(x, y + h * 0.5, 0.0), Vector3(0.04, 0.04, length - 0.6), 0.0)
			b.box(Vector3(x, y - h * 0.5, 0.0), Vector3(0.04, 0.04, length - 0.6), 0.0)
			b.tier = 0
		"fabric":
			b.brush(sec)
			b.tapered_box(Vector3(x, y, 0.1), Vector2(0.08, length * 0.7), Vector2(0.03, length * 0.66), h, Vector2(-0.05, 0.0), 0.01)


static func _plates(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var sz: Vector3 = _v(a, "size")
	var n: int = maxi(_i(a, "n"), 1)
	var w: float = sz.x / float(n)
	for i in n:
		b.brush(_p(pal, "base") if i % 2 == 0 else _p(pal, "acc"))
		b.box(c + Vector3(-sz.x * 0.5 + w * (float(i) + 0.5), 0.0, 0.0), Vector3(w - 0.03, sz.y, sz.z), 0.012)
		b.tier = 1
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.cylinder(c + Vector3(-sz.x * 0.5 + w * (float(i) + 0.5), sz.y * 0.5, 0.0), c + Vector3(-sz.x * 0.5 + w * (float(i) + 0.5), sz.y * 0.5 + 0.02, 0.0), 0.025, 6, 0.0)
		b.tier = 0


static func _container(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var sz: Vector3 = _v(a, "size")
	b.brush(_c(a, "col"))
	b.box(c, sz, 0.02)
	b.tier = 2
	b.brush(_p(pal, "dark"))
	for i in 6:
		b.box(c + Vector3(-sz.x * 0.5 + sz.x * (float(i) + 0.5) / 6.0, 0.0, 0.0), Vector3(0.05, sz.y * 0.96, sz.z * 1.02), 0.0)
	b.tier = 0
	b.brush(_p(pal, "acc"))
	b.box(c + Vector3(0.0, sz.y * 0.5 + 0.005, 0.0), Vector3(sz.x, 0.03, 0.16), 0.0)


static func _mount_plate(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var sz: Vector3 = _v(a, "size")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.box(c, sz, 0.01)
	b.tier = 1
	b.brush(_p(pal, "dark"), Mat.METAL)
	for sx: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			b.cylinder(c + Vector3(sx * sz.x * 0.4, sz.y * 0.5, sz2 * sz.z * 0.4), c + Vector3(sx * sz.x * 0.4, sz.y * 0.5 + 0.025, sz2 * sz.z * 0.4), 0.02, 6, 0.0)


# ---------------------------------------------------------------------------------------------- weapons
static func _turret_ngon(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var pv: Vector3 = _v(a, "pivot")
	var tz: float = pv.z
	var tn: int = maxi(_i(a, "n"), 3)
	var hw: float = _f(a, "hw")
	var hl: float = _f(a, "hl")
	var th: float = _f(a, "h")
	var top: float = _f(a, "top")
	var shift: float = _f(a, "shift")
	var y0: float = _f(a, "y0")
	var base: Color = _p(pal, "base")
	var cn: float = cos(PI / float(tn))
	var top_y: float = y0 + th
	var gy: float = y0 + th * 0.5
	var fz: float = tz - hl * (1.0 + top) * 0.5 + shift * 0.5
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(Vector3(0.0, pv.y - 0.02, tz), Vector3(0.0, y0, tz), clampf(hw * 0.85, 0.5, 0.72), 18, 0.01)
	b.brush(base)
	b.prism(ViewMeshBuilder.ngon(Vector3(0.0, y0, tz), hw / cn, hl / cn, tn, _f(a, "rot")),
		ViewMeshBuilder.ngon(Vector3(0.0, top_y, tz + shift), hw / cn * top, hl / cn * top, tn, _f(a, "rot")), 0.04)
	_team_panel(b, pal, Vector3(0.0, top_y + 0.012, tz + shift - 0.02), Vector3(hw * top * 0.75, 0.03, hl * top * 1.2), base)
	b.brush(base)
	b.box(Vector3(0.0, y0 + th * 0.42, tz + hl * 0.98), Vector3(hw * 1.45, th * 0.80, 0.40), 0.03)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, y0 + th * 0.42, tz + hl * 0.98 + 0.205), Vector3(hw * 1.05, th * 0.36, 0.02), 0.0)
	b.brush(_p(pal, "dark"))
	b.box(Vector3(0.0, gy, fz - 0.02), Vector3(0.58, th * 0.66, 0.30), 0.03)


static func _barrel_kind(mount: int) -> int:
	return [Pt.BARREL, Pt.BARREL1, Pt.BARREL2, Pt.BARREL3][clampi(mount, 0, 3)] as int


static func _turret_kind(mount: int) -> int:
	return [Pt.TURRET, Pt.TURRET1, Pt.TURRET2, Pt.TURRET3][clampi(mount, 0, 3)] as int


static func _gun(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var y: float = _f(a, "y")
	var z0: float = _f(a, "z")
	var bl: float = _f(a, "len")
	var br: float = _f(a, "r")
	var metal: Color = _p(pal, "metal")
	var acc: Color = _p(pal, "acc")
	b.set_part(_barrel_kind(_i(a, "mount")), _v(a, "pivot"), _f(a, "elev"), _f(a, "recoil"), Vector2(y, z0 + 0.14))
	b.brush(metal, Mat.METAL)
	b.cylinder(Vector3(0.0, y, z0 + 0.32), Vector3(0.0, y, z0 - 0.15), br * 1.55, 12, 0.01)
	var kind: String = _s(a, "muzzle")
	var offs: Array[float] = [0.0]
	if kind == "twin":
		offs = [-br * 2.6, br * 2.6]
	for ox: float in offs:
		b.cylinder(Vector3(ox, y, z0), Vector3(ox, y, z0 - bl), br if kind != "bore" else br * 1.25, 10, 0.0, true)
	match kind:
		"brake":
			b.cylinder(Vector3(0.0, y, z0 - bl * 0.55 + 0.13), Vector3(0.0, y, z0 - bl * 0.55 - 0.13), br * 1.75, 10, 0.012)
			b.cylinder(Vector3(0.0, y, z0 - bl + 0.02), Vector3(0.0, y, z0 - bl - 0.26), br * 1.7, 10, 0.014)
			b.brush(acc)
			b.cylinder(Vector3(0.0, y, z0 - bl + 0.34), Vector3(0.0, y, z0 - bl + 0.28), br * 1.18, 10, 0.0)
		"sleeve":
			b.brush(_p(pal, "sec"))
			b.cylinder(Vector3(0.0, y, z0 - 0.10), Vector3(0.0, y, z0 - bl * 0.66), br * 1.5, 10, 0.01)
			b.brush(acc)
			b.cylinder(Vector3(0.0, y, z0 - bl * 0.66), Vector3(0.0, y, z0 - bl * 0.66 - 0.05), br * 1.55, 10, 0.0)
			b.brush(metal, Mat.METAL)
			b.cylinder(Vector3(0.0, y, z0 - bl + 0.02), Vector3(0.0, y, z0 - bl - 0.10), br * 1.3, 8, 0.008)
		"coil":
			b.brush(_p(pal, "light"), Mat.EMISSIVE)
			for i in 4:
				var zz: float = z0 - bl * (0.3 + 0.17 * float(i))
				b.cylinder(Vector3(0.0, y, zz + 0.03), Vector3(0.0, y, zz - 0.03), br * 1.9, 10, 0.0)
		"prism":
			b.brush(_p(pal, "light"), Mat.EMISSIVE)
			b.frustum(Vector3(0.0, y, z0 - bl), Vector3(0.0, y, z0 - bl - 0.3), br * 1.4, br * 0.5, 8)
		"bore":
			b.brush(_p(pal, "dark"), Mat.METAL)
			b.cylinder(Vector3(0.0, y, z0 - bl + 0.05), Vector3(0.0, y, z0 - bl - 0.25), br * 1.7, 10, 0.012)
		"gatling":
			b.brush(_p(pal, "dark"), Mat.METAL)
			for i in 6:
				var ang: float = TAU * float(i) / 6.0
				b.cylinder(Vector3(cos(ang) * br * 1.6, y + sin(ang) * br * 1.6, z0 - 0.1), Vector3(cos(ang) * br * 1.6, y + sin(ang) * br * 1.6, z0 - bl), br * 0.55, 6, 0.0)
		_:
			b.cylinder(Vector3(0.0, y, z0 - bl + 0.02), Vector3(0.0, y, z0 - bl - 0.14), br * 1.35, 8, 0.008)
			b.brush(acc)
			b.cylinder(Vector3(0.0, y, z0 - bl * 0.5 + 0.03), Vector3(0.0, y, z0 - bl * 0.5 - 0.03), br * 1.12, 8, 0.0)
	b.clear_part()


static func _rws(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var rp: Vector3 = _v(a, "center")
	var m: int = _i(a, "mount")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(rp, rp + Vector3(0.0, 0.10, 0.0), 0.20, 12, 0.01)
	b.set_part(_turret_kind(m), rp)
	b.brush(_p(pal, "dark"))
	b.box(rp + Vector3(0.0, 0.22, 0.0), Vector3(0.30, 0.20, 0.42), 0.03)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.set_part(_barrel_kind(m), rp, 0.0, 0.10, Vector2(rp.y + 0.24, rp.z))
	b.cylinder(rp + Vector3(0.0, 0.24, -0.15), rp + Vector3(0.0, 0.24, -0.85), 0.035, 8, 0.0)


static func _missile_rack(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var cols: int = maxi(_i(a, "cols"), 1)
	var rows: int = maxi(_i(a, "rows"), 1)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, 0.12, 0.0), 0.3, 12, 0.01)
	b.set_part(_turret_kind(_i(a, "mount")), c)
	b.push(ViewMeshBuilder.xf(c + Vector3(0.0, 0.32, 0.0), Vector3(-_f(a, "elev"), 0.0, 0.0)))
	b.brush(_p(pal, "dark"))
	b.box(Vector3.ZERO, Vector3(float(cols) * 0.24 + 0.1, float(rows) * 0.24 + 0.1, 1.0), 0.03)
	for i in cols:
		for j in rows:
			var p: Vector3 = Vector3((float(i) - float(cols - 1) * 0.5) * 0.24, (float(j) - float(rows - 1) * 0.5) * 0.24, -0.5)
			b.brush(_p(pal, "sec"))
			b.cylinder(p, p + Vector3(0.0, 0.0, -0.16), 0.09, 8, 0.01)
			b.tier = 1
			b.brush(_p(pal, "acc"))
			b.cylinder(p + Vector3(0.0, 0.0, -0.15), p + Vector3(0.0, 0.0, -0.19), 0.06, 8, 0.0)
			b.tier = 0
	b.pop()


static func _rocket_pods(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var cols: int = maxi(_i(a, "cols"), 1)
	var rows: int = maxi(_i(a, "rows"), 1)
	b.brush(_p(pal, "dark"))
	b.box(c, Vector3(float(cols) * 0.2 + 0.08, float(rows) * 0.2 + 0.08, 0.7), 0.03)
	b.tier = 1
	b.brush(_p(pal, "metal"), Mat.METAL)
	for i in cols:
		for j in rows:
			var p: Vector3 = c + Vector3((float(i) - float(cols - 1) * 0.5) * 0.2, (float(j) - float(rows - 1) * 0.5) * 0.2, -0.35)
			b.cylinder(p, p + Vector3(0.0, 0.0, -0.05), 0.075, 8, 0.0)
	b.tier = 0


static func _launcher_tube(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var l: float = _f(a, "len")
	b.brush(_p(pal, "dark"))
	b.box(c + Vector3(0.0, 0.12, 0.0), Vector3(0.36, 0.24, 0.5), 0.03)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.push(ViewMeshBuilder.xf(c + Vector3(0.0, 0.32, 0.0), Vector3(-25.0, 0.0, 0.0)))
	b.cylinder(Vector3(0.0, 0.0, 0.3), Vector3(0.0, 0.0, 0.3 - l), 0.12, 10, 0.01)
	b.brush(_p(pal, "acc"))
	b.cylinder(Vector3(0.0, 0.0, 0.3 - l), Vector3(0.0, 0.0, 0.3 - l - 0.05), 0.13, 10, 0.0)
	b.pop()


static func _flak_twin(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, 0.1, 0.0), 0.32, 12, 0.01)
	b.set_part(Pt.TURRET, c)
	b.brush(_p(pal, "base"))
	b.box(c + Vector3(0.0, 0.28, 0.0), Vector3(0.7, 0.34, 0.6), 0.04)
	b.brush(_p(pal, "base"), Mat.PAINT, 1.0)
	b.box(c + Vector3(0.0, 0.46, 0.05), Vector3(0.3, 0.03, 0.3), 0.0)
	b.set_part(Pt.BARREL, c, 0.0, 0.2, Vector2(c.y + 0.3, c.z - 0.3))
	b.brush(_p(pal, "metal"), Mat.METAL)
	for sx: float in [-1.0, 1.0]:
		b.cylinder(c + Vector3(sx * 0.2, 0.3, -0.25), c + Vector3(sx * 0.2, 0.3, -1.3), 0.045, 8, 0.0)
		b.cylinder(c + Vector3(sx * 0.2, 0.3, -1.1), c + Vector3(sx * 0.2, 0.3, -1.3), 0.07, 8, 0.01)


static func _dome_emitter(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, 0.1, 0.0), r * 1.1, 14, 0.015)
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	b.dome(c + Vector3(0.0, 0.1, 0.0), Vector3.UP, r * 0.85, r * 0.7, 12, 4)
	b.brush(_p(pal, "acc"))
	b.cylinder(c + Vector3(0.0, 0.1, 0.0), c + Vector3(0.0, 0.13, 0.0), r * 1.0, 14, 0.0, false)


static func _spade_pair(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var z: float = _f(a, "z")
	for sx: float in [-_f(a, "x"), _f(a, "x")]:
		b.set_part(Pt.DEPLOY, Vector3(sx, 0.55, z + 0.06), 1.0, 0.0)
		b.brush(_p(pal, "dark"), Mat.METAL)
		b.box(Vector3(sx, 0.97, z + 0.10), Vector3(0.70, 0.84, 0.07), 0.02)
		b.brush(_p(pal, "acc"))
		b.box(Vector3(sx, 1.35, z + 0.10), Vector3(0.72, 0.08, 0.09), 0.0)
	b.clear_part()


static func _outriggers(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var z: float = _f(a, "z")
	var half: float = _f(a, "span") * 0.5
	for sx: float in [-1.0, 1.0]:
		b.set_part(Pt.DEPLOY_Z, Vector3(sx * half * 0.55, 0.7, z), 1.0, 0.0)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.box(Vector3(sx * half * 0.8, 0.7, z), Vector3(half * 0.5, 0.12, 0.16), 0.02)
		b.brush(_p(pal, "acc"))
		b.box(Vector3(sx * half, 0.55, z), Vector3(0.36, 0.06, 0.36), 0.02)
	b.clear_part()


# ---------------------------------------------------------------------------------------------- sensors
static func _sensor_mast(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var base: Vector3 = _v(a, "base")
	var h: float = _f(a, "h")
	var folded: float = clampf(_f(a, "folded"), 0.05, h)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(base, base + Vector3(0.0, folded, 0.0), 0.035, 8, 0.0)
	b.set_part(Pt.SLIDE_Y, base, 0.0, h - folded)
	b.cylinder(base + Vector3(0.0, folded * 0.5, 0.0), base + Vector3(0.0, folded + 0.05, 0.0), 0.024, 6, 0.0)
	b.brush(_p(pal, "sec"))
	b.box(base + Vector3(0.0, folded + 0.08, 0.0), Vector3(0.62, 0.06, 0.10), 0.01)
	b.brush(_p(pal, "acc"))
	b.box(base + Vector3(0.0, folded + 0.115, 0.0), Vector3(0.62, 0.02, 0.05), 0.0)


static func _sensor_crown(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var n: int = maxi(_i(a, "n"), 3)
	var r: float = _f(a, "r")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, 0.18, 0.0), 0.08, 8, 0.0)
	b.brush(_p(pal, "acc"))
	for i in n:
		var ang: float = TAU * float(i) / float(n)
		b.box(c + Vector3(cos(ang) * r, 0.24, sin(ang) * r), Vector3(0.05, 0.16, 0.05), 0.0)
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	b.box(c + Vector3(0.0, 0.31, 0.0), Vector3(0.10, 0.03, 0.10), 0.0)


static func _radar_dish(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, 0.16, 0.0), 0.05, 8, 0.0)
	if _f(a, "spin") != 0.0:
		b.set_part(Pt.RADAR, c + Vector3(0.0, 0.2, 0.0))
	b.brush(_p(pal, "sec"))
	b.push(ViewMeshBuilder.xf(c + Vector3(0.0, 0.2, 0.0), Vector3(-35.0, 0.0, 0.0)))
	b.dome(Vector3.ZERO, Vector3.UP, r, r * 0.35, 14, 3)
	b.pop()
	b.brush(_p(pal, "acc"))
	b.cylinder(c + Vector3(0.0, 0.22, 0.0), c + Vector3(0.0, 0.22 + r * 0.6, -r * 0.45), 0.015, 5, 0.0, false)


static func _ball_sensor(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(c, c + Vector3(0.0, r * 0.6, 0.0), r * 0.4, 8, 0.01)
	b.brush(_p(pal, "sec"))
	b.dome(c + Vector3(0.0, r * 0.6, 0.0), Vector3.UP, r, r, 14, 5)
	b.dome(c + Vector3(0.0, r * 0.6, 0.0), Vector3.DOWN, r, r * 0.9, 14, 4)
	b.brush(_p(pal, "glass"), Mat.GLASS)
	b.box(c + Vector3(0.0, r * 1.6, -r * 0.85), Vector3(r * 0.7, r * 0.3, 0.03), 0.0)


# ---------------------------------------------------------------------------------------------- infantry
static func _soldier(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var x0: float = _f(a, "x")
	var z0: float = _f(a, "z")
	var ph: float = _f(a, "phase")
	var base: Color = _p(pal, "base")
	var dark: Color = _p(pal, "dark")
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	var metal: Color = _p(pal, "metal")
	b.member(_i(a, "member"), _i(a, "count"))
	b.push(ViewMeshBuilder.xf(Vector3(x0, 0.0, z0)))
	for sx: float in [-1.0, 1.0]:
		b.set_part(Pt.LEG_A if sx < 0.0 else Pt.LEG_B, Vector3(x0 + sx * 0.075, 0.45, z0), ph, 0.0)
		b.brush(dark)
		b.box(Vector3(sx * 0.075, 0.225, 0.0), Vector3(0.12, 0.45, 0.15), 0.0)
		b.brush(_p(pal, "rubber"), Mat.RUBBER)
		b.box(Vector3(sx * 0.075, 0.04, -0.03), Vector3(0.13, 0.08, 0.22), 0.0)
	b.set_part(Pt.BODY_BOB, Vector3.ZERO, ph, 0.0)
	b.brush(base)
	b.box(Vector3(0.0, 0.62, 0.0), Vector3(0.36, 0.36, 0.21), 0.012)
	b.brush(dark)
	b.box(Vector3(0.0, 0.50, -0.01), Vector3(0.38, 0.10, 0.23), 0.0)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 0.66, 0.175), Vector3(0.26, 0.32, 0.14), 0.015)
	b.brush(SKIN)
	b.box(Vector3(0.0, 0.88, 0.0), Vector3(0.14, 0.13, 0.15), 0.0)
	# helmet
	b.brush(sec)
	match _s(a, "helmet"):
		"angular":
			b.tapered_box(Vector3(0.0, 0.955, 0.0), Vector2(0.27, 0.27), Vector2(0.19, 0.22), 0.11, Vector2(0.0, 0.01), 0.01)
		"cap":
			b.box(Vector3(0.0, 0.95, 0.0), Vector3(0.24, 0.07, 0.24), 0.01)
			b.box(Vector3(0.0, 0.925, -0.16), Vector3(0.2, 0.02, 0.1), 0.0)
		"wrap":
			b.box(Vector3(0.0, 0.94, 0.0), Vector3(0.22, 0.12, 0.23), 0.02)
			b.tier = 2
			b.brush(acc)
			b.box(Vector3(0.0, 0.89, 0.0), Vector3(0.235, 0.03, 0.245), 0.0)
		_:
			b.dome(Vector3(0.0, 0.92, 0.0), Vector3.UP, 0.125, 0.11, 10, 3)
			b.tier = 2
			b.brush(acc)
			b.box(Vector3(0.0, 0.955, 0.0), Vector3(0.05, 0.03, 0.26), 0.0)
	b.tier = 2
	b.brush(_p(pal, "glass"), Mat.GLASS)
	b.box(Vector3(0.0, 0.89, -0.078), Vector3(0.13, 0.045, 0.02), 0.0)
	# pack
	match _s(a, "pack"):
		"small":
			b.brush(dark)
			b.box(Vector3(0.0, 0.62, 0.20), Vector3(0.24, 0.26, 0.10), 0.02)
		"large":
			b.brush(dark)
			b.box(Vector3(0.0, 0.66, 0.22), Vector3(0.30, 0.38, 0.16), 0.02)
			b.brush(acc)
			b.box(Vector3(0.0, 0.52, 0.31), Vector3(0.28, 0.05, 0.03), 0.0)
	b.tier = 0
	# right arm + kit (static with the body)
	b.brush(dark)
	b.box(Vector3(0.235, 0.60, -0.10), Vector3(0.09, 0.09, 0.30), 0.0)
	b.brush(metal, Mat.METAL)
	match _s(a, "kit"):
		"hmg":
			b.box(Vector3(0.20, 0.64, -0.30), Vector3(0.07, 0.09, 0.78), 0.0)
			b.brush(dark)
			b.box(Vector3(0.10, 0.50, -0.16), Vector3(0.10, 0.16, 0.14), 0.0)
		"shield":
			b.brush(sec)
			b.box(Vector3(0.24, 0.60, -0.36), Vector3(0.46, 0.66, 0.05), 0.01)
			b.brush(base, Mat.PAINT, 1.0)
			b.box(Vector3(0.24, 0.80, -0.385), Vector3(0.26, 0.10, 0.02), 0.0)
		"launcher":
			b.cylinder(Vector3(0.20, 0.72, 0.25), Vector3(0.20, 0.72, -0.62), 0.065, 8, 0.01)
			b.brush(acc)
			b.cylinder(Vector3(0.20, 0.72, -0.62), Vector3(0.20, 0.72, -0.68), 0.075, 8, 0.0)
			b.brush(base, Mat.PAINT, 1.0)
			b.box(Vector3(0.20, 0.79, -0.05), Vector3(0.08, 0.02, 0.24), 0.0)
		"tripod":
			b.box(Vector3(0.20, 0.50, -0.34), Vector3(0.05, 0.07, 0.62), 0.0)
			for sx2: float in [-1.0, 1.0]:
				b.cylinder(Vector3(0.20, 0.48, -0.55), Vector3(0.20 + sx2 * 0.16, 0.0, -0.66), 0.014, 5, 0.0, false)
			b.cylinder(Vector3(0.20, 0.48, -0.55), Vector3(0.20, 0.0, -0.40), 0.014, 5, 0.0, false)
		"medic":
			b.brush(sec)
			b.box(Vector3(0.20, 0.55, -0.12), Vector3(0.14, 0.16, 0.16), 0.01)
			b.brush(acc)
			b.box(Vector3(0.20, 0.55, -0.205), Vector3(0.09, 0.03, 0.01), 0.0)
			b.box(Vector3(0.20, 0.55, -0.205), Vector3(0.03, 0.09, 0.01), 0.0)
		"radio":
			b.brush(dark)
			b.box(Vector3(0.0, 0.72, 0.27), Vector3(0.22, 0.28, 0.12), 0.01)
			b.cylinder(Vector3(0.08, 0.86, 0.28), Vector3(0.10, 1.35, 0.30), 0.008, 4, 0.0, false)
			b.box(Vector3(0.20, 0.60, -0.20), Vector3(0.05, 0.07, 0.34), 0.0)
		"scope":
			b.box(Vector3(0.20, 0.64, -0.34), Vector3(0.04, 0.06, 0.86), 0.0)
			b.brush(dark)
			b.cylinder(Vector3(0.20, 0.71, -0.20), Vector3(0.20, 0.71, -0.38), 0.03, 6, 0.0)
		"tool":
			b.brush(acc)
			b.box(Vector3(0.20, 0.42, -0.10), Vector3(0.14, 0.14, 0.24), 0.01)
			b.brush(metal, Mat.METAL)
			b.box(Vector3(0.20, 0.62, -0.28), Vector3(0.04, 0.05, 0.50), 0.0)
		"breach":
			b.box(Vector3(0.20, 0.62, -0.24), Vector3(0.06, 0.08, 0.46), 0.0)
			b.brush(acc)
			b.box(Vector3(0.20, 0.50, -0.14), Vector3(0.10, 0.12, 0.10), 0.0)
		"torch":
			b.box(Vector3(0.20, 0.62, -0.20), Vector3(0.06, 0.08, 0.36), 0.0)
			b.brush(_p(pal, "light"), Mat.EMISSIVE)
			b.box(Vector3(0.20, 0.62, -0.40), Vector3(0.05, 0.05, 0.05), 0.0)
		"hook":
			b.cylinder(Vector3(0.24, 0.10, -0.10), Vector3(0.24, 1.10, -0.10), 0.018, 5, 0.0, false)
			b.box(Vector3(0.24, 1.12, -0.16), Vector3(0.03, 0.03, 0.14), 0.0)
		_:
			b.box(Vector3(0.20, 0.64, -0.28), Vector3(0.05, 0.07, 0.70), 0.0)
			b.box(Vector3(0.20, 0.57, -0.15), Vector3(0.04, 0.10, 0.07), 0.0)
	b.set_part(Pt.ARM_A, Vector3(x0 - 0.235, 0.78, z0), ph, 0.0)
	b.brush(base)
	b.box(Vector3(-0.235, 0.62, 0.0), Vector3(0.09, 0.30, 0.10), 0.0)
	b.brush(SKIN)
	b.box(Vector3(-0.235, 0.45, 0.0), Vector3(0.08, 0.07, 0.09), 0.0)
	b.clear_part()
	b.pop()
	b.member(0, 0)


static func _squad(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> String:
	var n: int = clampi(_i(a, "n"), 1, 8)
	var kits: PackedStringArray = _s(a, "kit").split(",", false)
	if kits.is_empty():
		return "squad: empty kit list"
	var sp: float = _f(a, "spread")
	for i in n:
		var x: float = 0.0
		var z: float = 0.0
		match _s(a, "layout"):
			"line":
				x = (float(i) - float(n - 1) * 0.5) * sp * 0.9
			"wedge":
				x = (float(i) - float(n - 1) * 0.5) * sp * 0.8
				z = absf(float(i) - float(n - 1) * 0.5) * sp * 0.5
			_:
				if n > 1:
					x = cos(float(i) * TAU / float(n) + 0.6) * sp * (0.6 + 0.4 * _hash01(i))
					z = sin(float(i) * TAU / float(n) + 0.6) * sp * (0.6 + 0.4 * _hash01(i + 9))
		var sa: Dictionary = {"x": x, "z": z, "phase": (float(i) + 0.5) / float(n), "member": float(i), "count": float(n),
			"kit": kits[i % kits.size()], "helmet": _s(a, "helmet"), "pack": "small"}
		_soldier(b, sa, pal)
	return ""


# ---------------------------------------------------------------------------------------------- air
static func _fuselage(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> String:
	var l: float = _f(a, "len")
	var w: float = _f(a, "half_w")
	var h: float = _f(a, "h")
	var hl: float = l * 0.5
	var prof: PackedVector2Array
	match _s(a, "profile"):
		"heli":
			prof = PackedVector2Array([Vector2(-hl * 0.42, 0.85), Vector2(-hl * 0.42, 1.5), Vector2(-hl * 0.03, 1.9), Vector2(hl * 0.43, 1.45), Vector2(hl * 0.57, 1.1), Vector2(hl * 0.4, 0.7), Vector2(-hl * 0.11, 0.62)])
		"jet":
			prof = PackedVector2Array([Vector2(-hl, 0.8 * h), Vector2(-hl * 0.6, 1.15 * h), Vector2(hl * 0.3, 1.2 * h), Vector2(hl, 0.95 * h), Vector2(hl * 0.6, 0.6 * h), Vector2(-hl * 0.8, 0.6 * h)])
		"flying_wing":
			prof = PackedVector2Array([Vector2(-hl, 0.8 * h), Vector2(-hl * 0.3, 1.1 * h), Vector2(hl * 0.4, 1.0 * h), Vector2(hl, 0.85 * h), Vector2(hl * 0.3, 0.6 * h)])
		"pod":
			prof = PackedVector2Array([Vector2(-hl, 0.9 * h), Vector2(-hl * 0.5, 1.2 * h), Vector2(hl * 0.5, 1.2 * h), Vector2(hl, 0.9 * h), Vector2(hl * 0.5, 0.6 * h), Vector2(-hl * 0.5, 0.6 * h)])
		_:
			return "fuselage: unknown profile '%s'" % _s(a, "profile")
	b.brush(_p(pal, "base"))
	b.extrude(prof, -w, w, 0.05)
	b.brush(_p(pal, "dark"))
	b.extrude(PackedVector2Array([Vector2(-hl * 0.8, 0.62 * h), Vector2(-hl * 0.8, 0.9 * h), Vector2(hl * 0.6, 0.9 * h), Vector2(hl * 0.8, 0.66 * h), Vector2(hl * 0.7, 0.56 * h), Vector2(-hl * 0.6, 0.56 * h)]), -w * 0.75, w * 0.75, 0.03)
	b.brush(_p(pal, "glass"), Mat.GLASS)
	b.extrude(PackedVector2Array([Vector2(hl * 0.1, 1.5 * h), Vector2(hl * 0.6, 1.3 * h), Vector2(hl * 0.62, 1.0 * h), Vector2(hl * 0.3, 1.0 * h)]), -w * 0.7, w * 0.7, 0.02)
	_team_panel(b, pal, Vector3(0.0, 1.5 * h, hl * 0.3), Vector3(w * 0.9, 0.03, l * 0.3), _p(pal, "base"))
	return ""


static func _wing(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var span: float = _f(a, "span")
	var chord: float = _f(a, "chord")
	var sweep: float = _f(a, "sweep")
	var th: float = _f(a, "thick")
	var y: float = _f(a, "y")
	var z: float = _f(a, "z")
	var fold: float = _f(a, "fold")
	var m0: PackedInt32Array = b.mark()
	var kink: float = span * 0.5 * (0.6 if fold > 0.0 else 1.0)
	b.brush(_p(pal, "base"))
	b.prism(_wing_loop(0.0, z, y, chord, th), _wing_loop(kink, z + sweep * (kink / (span * 0.5)), y, chord * 0.7, th * 0.8), 0.015)
	if fold > 0.0:
		b.set_part(Pt.DEPLOY_Z, Vector3(kink, y, z + sweep * 0.6), fold, 0.0)
		b.brush(_p(pal, "base"))
		b.prism(_wing_loop(kink, z + sweep * 0.6, y, chord * 0.7, th * 0.8), _wing_loop(span * 0.5, z + sweep, y, chord * 0.45, th * 0.6), 0.012)
		b.clear_part()
	b.brush(_p(pal, "base"), Mat.PAINT, 1.0)
	b.box(Vector3(kink * 0.5, y + th * 0.5 + 0.005, z + sweep * 0.25), Vector3(kink * 0.5, 0.012, chord * 0.35), 0.0)
	b.mirror_x(m0)


static func _wing_loop(x: float, z: float, y: float, chord: float, th: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(x, y - th * 0.5, z - chord * 0.5), Vector3(x, y - th * 0.5, z + chord * 0.5), Vector3(x, y + th * 0.5, z + chord * 0.5), Vector3(x, y + th * 0.5, z - chord * 0.5)])


static func _rotor_main(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var hub: Vector3 = _v(a, "hub")
	var n: int = maxi(_i(a, "blades"), 2)
	var rad: float = _f(a, "radius")
	var ch: float = _f(a, "chord")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(hub - Vector3(0.0, 0.5, 0.0), hub - Vector3(0.0, 0.06, 0.0), 0.10, 10, 0.0)
	b.set_part(Pt.ROTOR, hub)
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(hub + Vector3(0.0, -0.06, 0.0), hub + Vector3(0.0, 0.10, 0.0), 0.22, 12, 0.02)
	for i in n:
		b.push(ViewMeshBuilder.xf(hub, Vector3(0.0, 360.0 * float(i) / float(n), 0.0)))
		b.brush(_p(pal, "dark"), Mat.METAL)
		b.box(Vector3(rad * 0.56, 0.0, 0.0), Vector3(rad, 0.035, ch), 0.0)
		b.brush(_p(pal, "acc"))
		b.box(Vector3(rad * 1.0 + 0.02, 0.0, 0.0), Vector3(0.34, 0.038, ch), 0.0)
		b.pop()


static func _rotor_tail(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var p: Vector3 = _v(a, "pos")
	b.set_part(Pt.TAIL_ROTOR, p)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.box(p, Vector3(0.02, 0.85, 0.09), 0.0)
	b.box(p, Vector3(0.02, 0.09, 0.85), 0.0)


static func _tilt_nacelle(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var p: Vector3 = _v(a, "pos")
	var r: float = _f(a, "r")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(p + Vector3(0.0, 0.0, 0.5), p + Vector3(0.0, 0.0, -0.5), r, 12, 0.02)
	b.set_part(Pt.ROTOR, p + Vector3(0.0, r + 0.1, -0.1))
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(p + Vector3(0.0, r + 0.05, -0.1), p + Vector3(0.0, r + 0.15, -0.1), 0.1, 8, 0.0)
	for i in 3:
		b.push(ViewMeshBuilder.xf(p + Vector3(0.0, r + 0.12, -0.1), Vector3(0.0, 120.0 * float(i), 0.0)))
		b.box(Vector3(0.6, 0.0, 0.0), Vector3(1.2, 0.03, 0.16), 0.0)
		b.pop()


static func _nozzle(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var p: Vector3 = _v(a, "pos")
	var r: float = _f(a, "r")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(p, p + Vector3(0.0, 0.0, 0.5), r, 12, 0.02)
	b.set_part(Pt.BLINK)
	b.brush(Color(1.0, 0.45, 0.10), Mat.EMISSIVE)
	b.cylinder(p + Vector3(0.0, 0.0, -0.01), p + Vector3(0.0, 0.0, -0.05), r * 0.75, 12, 0.0)


static func _gear(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var p: Vector3 = _v(a, "pos")
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(p, Vector3(p.x, 0.18, p.z), 0.035, 6, 0.0)
	b.wheel(Vector3(p.x, 0.16, p.z), 0.16, 0.12, _p(pal, "rubber"), _p(pal, "metal"), 0, 10, false)


static func _drone_body(b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = _v(a, "center")
	var r: float = _f(a, "r")
	var n: int = clampi(_i(a, "arms"), 2, 8)
	b.brush(_p(pal, "base"))
	b.tapered_box(c, Vector2(r * 1.6, r * 2.4), Vector2(r * 1.1, r * 1.8), r * 0.7, Vector2.ZERO, 0.03)
	b.brush(_p(pal, "base"), Mat.PAINT, 1.0)
	b.box(c + Vector3(0.0, r * 0.36, 0.0), Vector3(r * 0.6, 0.02, r * 0.9), 0.0)
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	b.box(c + Vector3(0.0, 0.0, -r * 1.2), Vector3(r * 0.4, 0.04, 0.04), 0.0)
	for i in n:
		var ang: float = TAU * (float(i) + 0.5) / float(n)
		var tip: Vector3 = c + Vector3(cos(ang) * r * 1.6, 0.05, sin(ang) * r * 1.6)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.cylinder(c, tip, 0.02, 5, 0.0, false)
		b.set_part(Pt.ROTOR, tip + Vector3(0.0, 0.05, 0.0))
		b.brush(_p(pal, "dark"), Mat.METAL)
		b.box(tip + Vector3(0.0, 0.05, 0.0), Vector3(r * 1.1, 0.01, 0.05), 0.0)
		b.clear_part()
