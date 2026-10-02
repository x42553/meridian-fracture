class_name AiPlacer
extends RefCounted
## Budgeted placement search (ai.md 3.5b / 5.4.5): `request(struct_def, site_kind, hint_x, hint_y)` returns a resumable AiJob whose
## result() is [cx, cy, rot] (origin cell of the footprint) or an empty array. Candidates are the cells around the centres
## (own HQs, or the hint for FIELD sites), pre-scored with integer geometry (distance to a target point that depends on the site
## kind, crowding, threat, map border), sorted best first and validated with AiWorldView.can_place - the same rules the sim
## applies to BUILD_PLACE - in that order. Passes relax the minimum gap to the neighbouring structures (2 -> 1 -> 0 cells) so
## a lane stays open for the exits of factories and the collector traffic of refineries, while a crowded base still gets a site.
## A cell that failed in the sim is blacklisted (`blacklist`) so the same cell is never retried for BL_TICKS.

enum Site { ANY = 0, BACK = 1, FRONT = 2, FIELD = 3, CHOKE = 4, RELAY = 5, RING = 6 }

const RADIUS: int = 9  ## search radius around a centre (cells); the HQ build radius is 8
const BL_TICKS: int = 1200
const MAX_VALIDATIONS: int = 260
const WU_PER_CELL_GEN: int = 6  ## cells generated per wu
const WU_PER_VALIDATE: int = 4

var _ctx: AiContext = null
var _black: Dictionary = {}  ## cell key -> until tick
var _dock_ok: int = -1
var jobs_made: int = 0
var blacklisted_total: int = 0


func setup(ctx: AiContext) -> void:
	_ctx = ctx


func request(struct_def: int, site_kind: int, hint_x: int = -1, hint_y: int = -1) -> AiJob:
	jobs_made += 1
	return PlaceJob.new(self, _ctx, struct_def, site_kind, hint_x, hint_y)


func blacklist(cx: int, cy: int, until_tick: int) -> void:
	_black[cx * 4096 + cy] = until_tick
	blacklisted_total += 1


func is_blacklisted(cx: int, cy: int, tick: int) -> bool:
	var k: int = cx * 4096 + cy
	if not _black.has(k):
		return false
	if int(_black[k]) <= tick:
		_black.erase(k)
		return false
	return true


## True when open water lies close to the first HQ (a Dock can possibly be placed); cached for the whole match.
func dock_placeable(ctx: AiContext) -> bool:
	if _dock_ok >= 0:
		return _dock_ok == 1
	var v: AiWorldView = ctx.view
	var hx: int = v.start_cell_x(v.me())
	var hy: int = v.start_cell_y(v.me())
	var n: int = 0
	for dy: int in range(-11, 12):
		for dx: int in range(-11, 12):
			if v.is_water(hx + dx, hy + dy):
				n += 1
	_dock_ok = 1 if n >= 12 else 0
	return _dock_ok == 1


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([jobs_made, blacklisted_total, _black.size()]))


## Unit vector (x1024) from a point towards the nearest known enemy start (map centre when none).
static func toward_enemy(ctx: AiContext, px: int, py: int, out: PackedInt32Array) -> void:
	out.resize(2)
	var tx: int = ctx.view.map_w() * Fp.CELL / 2
	var ty: int = ctx.view.map_h() * Fp.CELL / 2
	var best: int = 1 << 60
	var es: PackedInt32Array = ctx.kb.enemy_starts
	for i: int in es.size() / 2:
		var ex: int = es[2 * i] * Fp.CELL + Fp.CELL / 2
		var ey: int = es[2 * i + 1] * Fp.CELL + Fp.CELL / 2
		var d2: int = (ex - px) * (ex - px) + (ey - py) * (ey - py)
		if d2 < best:
			best = d2
			tx = ex
			ty = ey
	var dx: int = tx - px
	var dy: int = ty - py
	var dist: int = maxi(Fp.dist(dx, dy), 1)
	out[0] = dx * 1024 / dist
	out[1] = dy * 1024 / dist


class PlaceJob extends AiJob:
	var placer: AiPlacer = null
	var ctx: AiContext = null
	var struct_def: int = -1
	var site_kind: int = 0
	var hint_x: int = -1
	var hint_y: int = -1
	var _res: PackedInt32Array = PackedInt32Array()
	var _pass: int = 0
	var _stage: int = 0  ## 0 setup, 1 generate, 2 validate
	var _gaps: PackedInt32Array = PackedInt32Array()
	var _rects: PackedInt32Array = PackedInt32Array()  ## x0, y0, x1, y1 of own structures (cells)
	var _centres: PackedInt32Array = PackedInt32Array()  ## cell centres to search around
	var _hqs: PackedInt32Array = PackedInt32Array()  ## cell centres of my HQs (FIELD sites: candidates beyond the build radius are skipped)
	var _ci: int = 0
	var _oi: int = 0
	var _fw: int = 1
	var _fh: int = 1
	var _is_dock: bool = false
	var _tgt: PackedInt32Array = PackedInt32Array()  ## per centre: target point (cells x, y)
	var _cx: PackedInt32Array = PackedInt32Array()
	var _cy: PackedInt32Array = PackedInt32Array()
	var _rot: PackedInt32Array = PackedInt32Array()
	var _keys: PackedInt64Array = PackedInt64Array()
	var _vi: int = 0
	var _validated: int = 0
	var _dir: PackedInt32Array = PackedInt32Array([0, 0])

	func _init(p_placer: AiPlacer, p_ctx: AiContext, p_def: int, p_kind: int, p_hx: int, p_hy: int) -> void:
		placer = p_placer
		ctx = p_ctx
		struct_def = p_def
		site_kind = p_kind
		hint_x = p_hx
		hint_y = p_hy
		_res = PackedInt32Array()

	func result() -> Variant:
		return _res

	func step(budget: AiBudget) -> void:
		while not done:
			match _stage:
				0:
					if not _setup(budget):
						return
					_stage = 1
				1:
					if not _generate(budget):
						return
					_stage = 2
				2:
					if not _validate(budget):
						return

	func _setup(budget: AiBudget) -> bool:
		var v: AiWorldView = ctx.view
		var kb: AiKnowledge = ctx.kb
		var d: DefStructure = v.structure_def(struct_def)
		if d == null:
			done = true
			return true
		_fw = d.fp_w
		_fh = d.fp_h
		var kind: int = ctx.res.kind_of_structure(struct_def)
		_is_dock = kind == AiTypes.StructKind.DOCK
		var big: bool = kind == AiTypes.StructKind.BARRACKS or kind == AiTypes.StructKind.FACTORY or kind == AiTypes.StructKind.REFINERY \
			or kind == AiTypes.StructKind.AIRFIELD or kind == AiTypes.StructKind.DOCK or kind == AiTypes.StructKind.LAB
		_gaps = PackedInt32Array([2, 1, 0]) if big else PackedInt32Array([1, 0])
		var t: AiEntityTable = kb.own
		_rects.resize(0)
		_centres.resize(0)
		_hqs.resize(0)
		budget.spend(2 + t.count / 16)
		for r: int in t.count:
			if t.kind[r] != AiTypes.KIND_STRUCTURE:
				continue
			var sd: DefStructure = v.structure_def(t.def[r])
			if sd == null:
				continue
			var x0: int = (t.x[r] - sd.fp_w * (Fp.CELL / 2)) >> Fp.CELL_SHIFT
			var y0: int = (t.y[r] - sd.fp_h * (Fp.CELL / 2)) >> Fp.CELL_SHIFT
			_rects.append(x0)
			_rects.append(y0)
			_rects.append(x0 + sd.fp_w - 1)
			_rects.append(y0 + sd.fp_h - 1)
			if ctx.res.kind_of_structure(t.def[r]) == AiTypes.StructKind.HQ:
				_centres.append(t.x[r] >> Fp.CELL_SHIFT)
				_centres.append(t.y[r] >> Fp.CELL_SHIFT)
				if (t.flags[r] & AiTypes.EF_UNDER_CONSTRUCTION) == 0:
					_hqs.append(t.x[r] >> Fp.CELL_SHIFT)
					_hqs.append(t.y[r] >> Fp.CELL_SHIFT)
		if _centres.is_empty():
			_centres.append(v.start_cell_x(v.me()))
			_centres.append(v.start_cell_y(v.me()))
		# per-centre target point (cells)
		_tgt.resize(0)
		if site_kind == AiPlacer.Site.FIELD and hint_x >= 0:
			_tgt.append(hint_x >> Fp.CELL_SHIFT)
			_tgt.append(hint_y >> Fp.CELL_SHIFT)
			_centres = PackedInt32Array([hint_x >> Fp.CELL_SHIFT, hint_y >> Fp.CELL_SHIFT])
		else:
			for i: int in _centres.size() / 2:
				AiPlacer.toward_enemy(ctx, _centres[2 * i] * Fp.CELL, _centres[2 * i + 1] * Fp.CELL, _dir)
				var reach: int = 0
				match site_kind:
					AiPlacer.Site.BACK:
						reach = -4
					AiPlacer.Site.FRONT, AiPlacer.Site.CHOKE:
						reach = 6
					AiPlacer.Site.RING, AiPlacer.Site.RELAY:
						reach = 0
				_tgt.append(_centres[2 * i] + _dir[0] * reach / 1024)
				_tgt.append(_centres[2 * i + 1] + _dir[1] * reach / 1024)
		_begin_pass()
		return true

	func _begin_pass() -> void:
		_cx.resize(0)
		_cy.resize(0)
		_rot.resize(0)
		_keys.resize(0)
		_ci = 0
		_oi = 0
		_vi = 0
		_validated = 0

	func _generate(budget: AiBudget) -> bool:
		var v: AiWorldView = ctx.view
		var kb: AiKnowledge = ctx.kb
		var gap: int = _gaps[_pass]
		var side: int = 2 * AiPlacer.RADIUS + 1
		var total: int = side * side
		var tick: int = ctx.tick
		var mw: int = v.map_w()
		var mh: int = v.map_h()
		var n_centres: int = _centres.size() / 2
		while _ci < n_centres:
			var ccx: int = _centres[2 * _ci]
			var ccy: int = _centres[2 * _ci + 1]
			var tx: int = _tgt[2 * _ci]
			var ty: int = _tgt[2 * _ci + 1]
			while _oi < total:
				if _oi % AiPlacer.WU_PER_CELL_GEN == 0 and not budget.spend(1):
					return false
				var ox: int = _oi % side - AiPlacer.RADIUS
				var oy: int = _oi / side - AiPlacer.RADIUS
				_oi += 1
				var cx: int = ccx + ox
				var cy: int = ccy + oy
				if cx < 1 or cy < 1 or cx + _fw >= mw - 1 or cy + _fh >= mh - 1:
					continue
				if placer.is_blacklisted(cx, cy, tick):
					continue
				var mx: int = cx + _fw / 2
				var my: int = cy + _fh / 2
				if not _is_dock and not v.passable(mx, my, AiTypes.MoveClass.TRACKED):
					continue
				if not _gap_ok(cx, cy, gap):
					continue
				if site_kind == AiPlacer.Site.FIELD and not _hqs.is_empty() and not _in_reach(mx, my):
					continue  # AIT: outside the build radius of every HQ (the sim refuses it): do not spend a validation on it
				var score: int = _score(cx, cy, mx, my, tx, ty, ccx, ccy, kb)
				if _is_dock:
					var wat: int = _water_near(v, mx, my)
					if wat == 0:
						continue
					for r: int in 4:
						_push(cx, cy, r, score - wat * 4 + r)
				else:
					_push(cx, cy, 0, score)
			_ci += 1
			_oi = 0
		_keys.sort()
		return true

	func _push(cx: int, cy: int, rot: int, score: int) -> void:
		var idx: int = _cx.size()
		_cx.append(cx)
		_cy.append(cy)
		_rot.append(rot)
		_keys.append((maxi(score, 0) << 20) | idx)

	func _score(cx: int, cy: int, mx: int, my: int, tx: int, ty: int, ccx: int, ccy: int, kb: AiKnowledge) -> int:
		var s: int = 0
		var dx: int = mx - tx
		var dy: int = my - ty
		if site_kind == AiPlacer.Site.ANY or site_kind == AiPlacer.Site.RING or site_kind == AiPlacer.Site.RELAY:
			# a ring of 4..6 cells around the centre
			var rr: int = maxi(absi(mx - ccx), absi(my - ccy))
			s += absi(rr - 5) * 12
			s += (absi(dx) + absi(dy)) * 2
		else:
			s += (absi(dx) + absi(dy)) * 10
		# crowding: own structures within 2 cells
		var n: int = _rects.size() / 4
		for i: int in n:
			var x0: int = _rects[4 * i]
			var y0: int = _rects[4 * i + 1]
			var x1: int = _rects[4 * i + 2]
			var y1: int = _rects[4 * i + 3]
			if x0 - 3 > cx + _fw or x1 + 3 < cx or y0 - 3 > cy + _fh or y1 + 3 < cy:
				continue
			s += 5
		s += kb.threat_at(mx * Fp.CELL, my * Fp.CELL) / 16
		# AIT: do not build inside an active warning zone (Horizon no-build field, a strike footprint)
		var pb: AiBrain = ctx.brain as AiBrain
		if pb != null and not pb.powers.dispersal.avoid.is_empty():
			var ax: int = mx * Fp.CELL + Fp.CELL / 2
			var ay: int = my * Fp.CELL + Fp.CELL / 2
			if pb.powers.dispersal.avoided(ax, ay, AiDispersal.AV_NO_BUILD, ctx.tick) or pb.powers.dispersal.avoided(ax, ay, AiDispersal.AV_DANGER, ctx.tick):
				s += 4000
		var mw: int = ctx.view.map_w()
		var mh: int = ctx.view.map_h()
		if mini(mini(cx, cy), mini(mw - cx, mh - cy)) < 4:
			s += 40
		return s

	func _in_reach(mx: int, my: int) -> bool:
		for i: int in _hqs.size() / 2:
			var dx: int = mx - _hqs[2 * i]
			var dy: int = my - _hqs[2 * i + 1]
			if dx * dx + dy * dy <= 11 * 11:
				return true
		return false

	func _gap_ok(cx: int, cy: int, gap: int) -> bool:
		if gap <= 0:
			return true
		var ex: int = cx + _fw - 1
		var ey: int = cy + _fh - 1
		var n: int = _rects.size() / 4
		for i: int in n:
			var x0: int = _rects[4 * i]
			var y0: int = _rects[4 * i + 1]
			var x1: int = _rects[4 * i + 2]
			var y1: int = _rects[4 * i + 3]
			var gx: int = maxi(x0 - ex, cx - x1) - 1
			var gy: int = maxi(y0 - ey, cy - y1) - 1
			if maxi(gx, gy) < gap:
				return false
		return true

	func _water_near(v: AiWorldView, mx: int, my: int) -> int:
		var n: int = 0
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				if v.is_water(mx + dx, my + dy):
					n += 1
		return n

	func _validate(budget: AiBudget) -> bool:
		var v: AiWorldView = ctx.view
		while _vi < _keys.size() and _validated < AiPlacer.MAX_VALIDATIONS:
			if not budget.spend(AiPlacer.WU_PER_VALIDATE):
				return false
			var idx: int = int(_keys[_vi] & 0xFFFFF)
			_vi += 1
			_validated += 1
			if v.can_place(struct_def, _cx[idx], _cy[idx], _rot[idx]):
				_res = PackedInt32Array([_cx[idx], _cy[idx], _rot[idx]])
				done = true
				return true
		# pass exhausted: relax the gap once more, else give up (empty result)
		if _pass + 1 < _gaps.size():
			_pass += 1
			_begin_pass()
			_stage = 1
			return true
		_res = PackedInt32Array()
		done = true
		return true
