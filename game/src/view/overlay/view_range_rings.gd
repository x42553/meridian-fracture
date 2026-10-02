class_name ViewRangeRings
extends Node3D
## Weapon range rings (render spec 5.10): maximum and minimum range of the selected armed entities, in metres
## (`units * 3 / 1024`), read once per selection change through `ViewSimReader.weapon_ranges`. Dashed and ground following
## (line.gdshader); anti-air cyan, artillery orange, everything else white. At most 12 rings, one per distinct (range, colour)
## class of the selection, so a 30-tank column shows one ring, not thirty. `show_preview` draws the
## range of a defense that is about to be placed. Presentation only.

const CAP: int = 12
const LIFT_M: float = 0.18
const MOVE_EPS_M: float = 0.05
const MOVE_INTERVAL_S: float = 0.05  ## rings follow moving entities at 20 Hz
const COL_GROUND: Color = Color(0.96, 0.96, 0.9, 0.85)
const COL_AIR: Color = Color(0.35, 0.85, 1.0, 0.9)
const COL_ARTY: Color = Color(1.0, 0.62, 0.20, 0.9)
const COL_PREVIEW: Color = Color(1.0, 1.0, 1.0, 0.95)
const MIN_SEGMENTS: int = 48
const MAX_SEGMENTS: int = 160

var count: int = 0  ## rings drawn (max ring + min ring of one entity count separately)
var entities_shown: int = 0

var _v: ViewWorld = null
var _ribbon: ViewRibbon = null
var _rings: Array[Dictionary] = []  ## {id, r, rmin, col, cx, cz, pts, pts_min}
var _preview: Dictionary = {}
var _ground: Callable = Callable()
var _dirty: bool = true
var _cool: float = 0.0
var _ranges: PackedInt32Array = PackedInt32Array()
var _arch_air: PackedInt32Array = PackedInt32Array()
var _arch_arty: PackedInt32Array = PackedInt32Array()


func setup(v: ViewWorld) -> void:
	_v = v
	_ground = Callable(v, "ground_at")
	_ribbon = ViewRibbon.new()
	_ribbon.setup(self, 3.5, ViewLayers.PRIO_LINES)
	_ribbon.material.set_shader_parameter(&"outline_px", 1.3)
	_ribbon.material.set_shader_parameter(&"intensity", 1.05)
	if v.terrain != null:
		_ribbon.set_bounds(Rect2(Vector2.ZERO, v.terrain.world_size()))
	_arch_air = _arch_indices(["aa_missile", "flak"])
	_arch_arty = _arch_indices(["artillery_shell", "rocket_barrage", "mortar", "missile_artillery", "naval_bombard", "cruise_missile"])


static func _arch_indices(names: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for n: String in names:
		var i: int = DefEnums.WEAPON_ARCH_NAMES.find(n)
		if i >= 0:
			out.append(i)
	return out


## Max (and min) range rings of the armed entities among `ids` (selection change).
func show_for(ids: PackedInt32Array) -> void:
	_rings.clear()
	if _v == null or _v.sim == null:
		_dirty = true
		return
	var cands: Array[Dictionary] = []
	for id: int in ids:
		var ve: ViewEntity = _v.entity_view(id)
		var e: SimEntity = _v.sim.get_entity(id)
		if ve == null or e == null or ve.vs == ViewConsts.VS_HIDDEN or ve.sim_gone:
			continue
		var n: int = ViewSimReader.weapon_ranges(_v.sim, e, _ranges)
		var rmax: int = 0
		var rmin: int = 0
		for m: int in n:
			rmax = maxi(rmax, _ranges[m * 2])
			var mn: int = _ranges[m * 2 + 1]
			if mn > 0 and (rmin == 0 or mn < rmin):
				rmin = mn
		if rmax <= 0:
			continue
		cands.append({"id": id, "r": float(rmax) * ViewConsts.M_PER_UNIT, "rmin": float(rmin) * ViewConsts.M_PER_UNIT, "col": _color_of(ve.vdef)})
	_pick(cands)
	_dirty = true


func _color_of(vd: ViewDef) -> Color:
	var air: bool = false
	var arty: bool = false
	var any: bool = false
	for a: int in vd.warch:
		if a < 0:
			continue
		any = true
		if _arch_arty.has(a):
			arty = true
		elif _arch_air.has(a):
			air = true
	if not any:
		return COL_GROUND
	if arty:
		return COL_ARTY
	if air:
		var only_air: bool = true
		for a2: int in vd.warch:
			if a2 >= 0 and not _arch_air.has(a2):
				only_air = false
		if only_air:
			return COL_AIR
	return COL_GROUND


## One ring per distinct (range, colour) class, in id order, at most 12: a 30-tank column shows one tank's ring, a mixed army
## one ring per unit type. (Rings of identical units would only pile up.)
func _pick(cands: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	for c: Dictionary in cands:
		var key: int = int(roundf((c["r"] as float) * 2.0)) * 8 + (c["col"] as Color).to_argb32() % 7
		if _rings.size() < CAP and not seen.has(key):
			seen[key] = true
			_rings.append(c)


## A ring at `center` for a structure that is being placed (defenses); `range_m <= 0` removes it.
func show_preview(center: Vector3, range_m: float, min_range_m: float = 0.0, color: Color = COL_PREVIEW) -> void:
	if range_m <= 0.0:
		_preview = {}
	else:
		_preview = {"r": range_m, "rmin": min_range_m, "col": color, "cx": center.x, "cz": center.z, "pts": PackedVector3Array(), "pts_min": PackedVector3Array()}
		_build(_preview)
	_dirty = true


func hide_all() -> void:
	_rings.clear()
	_preview = {}
	_dirty = true


func has_rings() -> bool:
	return not _rings.is_empty() or not _preview.is_empty()


## Ring records (tests): {id, r, rmin, col}.
func rings() -> Array[Dictionary]:
	return _rings


func _process(delta: float) -> void:
	update(delta)


func update(dt: float) -> void:
	if _v == null or _ribbon == null:
		return
	_cool -= dt
	var moved: bool = false
	if _cool <= 0.0:
		for r: Dictionary in _rings:
			var ve: ViewEntity = _v.entity_view(r["id"] as int)
			if ve == null or ve.sim_gone:
				continue
			var d: float = absf(ve.wx - (r.get("cx", INF) as float)) + absf(ve.wz - (r.get("cz", INF) as float))
			if d > MOVE_EPS_M:
				r["cx"] = ve.wx
				r["cz"] = ve.wz
				_build(r)
				moved = true
		_cool = MOVE_INTERVAL_S
	if not _dirty and not moved:
		return
	if _dirty:
		for r2: Dictionary in _rings:
			if not r2.has("cx"):
				var ve2: ViewEntity = _v.entity_view(r2["id"] as int)
				if ve2 != null:
					r2["cx"] = ve2.wx
					r2["cz"] = ve2.wz
					_build(r2)
	_dirty = false
	_assemble()


func _build(r: Dictionary) -> void:
	var cx: float = r["cx"] as float
	var cz: float = r["cz"] as float
	var rad: float = r["r"] as float
	r["pts"] = ViewRibbon.circle_points(cx, cz, rad, _segments(rad), _ground, LIFT_M)
	var rmin: float = r["rmin"] as float
	if rmin > 0.0:
		r["pts_min"] = ViewRibbon.circle_points(cx, cz, rmin, _segments(rmin), _ground, LIFT_M)
	else:
		r["pts_min"] = PackedVector3Array()


static func _segments(radius_m: float) -> int:
	return clampi(int(radius_m * 3.0), MIN_SEGMENTS, MAX_SEGMENTS)


func _assemble() -> void:
	_ribbon.begin()
	count = 0
	entities_shown = 0
	var all: Array[Dictionary] = _rings.duplicate()
	if not _preview.is_empty():
		all.append(_preview)
	for r: Dictionary in all:
		var pts: PackedVector3Array = r.get("pts", PackedVector3Array()) as PackedVector3Array
		if pts.size() < 3:
			continue
		var col: Color = r["col"] as Color
		_ribbon.add_polyline(pts, col, ViewRibbon.STYLE_DASH, 0.85, true)
		count += 1
		entities_shown += 1
		var pm: PackedVector3Array = r.get("pts_min", PackedVector3Array()) as PackedVector3Array
		if pm.size() >= 3:
			_ribbon.add_polyline(pm, Color(col.r, col.g, col.b, col.a * 0.75), ViewRibbon.STYLE_DOTS, 0.7, true)
			count += 1
	_ribbon.commit()


func ribbon() -> ViewRibbon:
	return _ribbon
