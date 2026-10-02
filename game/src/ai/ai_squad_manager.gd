class_name AiSquadManager
extends RefCounted
## Unit -> squad assignment and claim / steal arbitration (ai.md 3.5b / 5.8.3). Every own combat unit that belongs to no squad
## is put into the RESERVE squad (id 0); ops create squads with `create` and take units with `claim` (units of the reserve first
## are NOT preferred - the nearest units win - but a claimer only steals from squads of a lower `prio`). `release` returns the
## units of a squad to the reserve. `refresh` keeps centroid / radius / value / hp fraction / slowest speed / role counts of every
## squad up to date. The manager is stepped by AiProduction (no slot of its own); it writes the `squad` column of kb.own.

const ASSIGN_PER_CALL: int = 96

var squads: Dictionary = {}  ## id -> AiSquad
var reserve: AiSquad = null
var next_id: int = 1
var claims: int = 0
var _ctx: AiContext = null
var _cursor: int = 0
var _last_step: int = -1


func setup(ctx: AiContext) -> void:
	_ctx = ctx
	reserve = AiSquad.new(0, AiTypes.SquadKind.RESERVE, -1)
	squads.clear()
	squads[0] = reserve


func create(kind: int, op_id: int = -1) -> AiSquad:
	var s: AiSquad = AiSquad.new(next_id, kind, op_id)
	next_id += 1
	squads[s.id] = s
	return s


func squad(id: int) -> AiSquad:
	return squads.get(id, null)


func squad_of(eid: int) -> int:
	var r: int = _ctx.kb.own.row(eid)
	return _ctx.kb.own.squad[r] if r >= 0 else -1


## True for a unit that may live in a squad (armed, not an economy / utility unit).
func eligible(row: int) -> bool:
	var t: AiEntityTable = _ctx.kb.own
	if t.kind[row] != AiTypes.KIND_UNIT or (t.flags[row] & AiTypes.EF_LOADED) != 0:
		return false
	var m: int = t.role_mask[row]
	var excluded: int = (1 << AiTypes.R_COLLECTOR) | (1 << AiTypes.R_MCV) | (1 << AiTypes.R_ENGINEER) | (1 << AiTypes.R_LANDING_TRANSPORT)
	return (m & (1 << AiTypes.R_COMBAT)) != 0 and (m & excluded) == 0


## Once per think: drops dead units, puts new combat units into the reserve, refreshes the squad statistics.
func step(ctx: AiContext, budget: AiBudget) -> void:
	if ctx.tick == _last_step or reserve == null:
		return
	_last_step = ctx.tick
	_ctx = ctx
	var t: AiEntityTable = ctx.kb.own
	# drop units that are gone
	for id: int in squads:
		var s: AiSquad = squads[id]
		if s.units.is_empty() or not budget.spend(1):
			continue
		var i: int = s.units.size() - 1
		while i >= 0:
			if not t.has(s.units[i]):
				s.units.remove_at(i)
			i -= 1
	# assign
	var n: int = mini(t.count, ASSIGN_PER_CALL)
	for _k: int in n:
		if t.count == 0 or not budget.spend(1):
			break
		if _cursor >= t.count:
			_cursor = 0
		var r: int = _cursor
		_cursor += 1
		if t.squad[r] < 0 and eligible(r):
			t.squad[r] = 0
			reserve.add(t.eid[r])
		elif t.squad[r] >= 0 and not squads.has(t.squad[r]):
			t.squad[r] = -1
	refresh(budget)


## Units of the squads that match `role_mask` (0 = any role bit) within `max_dist` of (near_x, near_y) (0 = anywhere), nearest
## first, from the reserve or from squads with prio < `prio`, are moved into `into`. Returns how many were added.
func claim(role_mask: int, count: int, near_x: int, near_y: int, max_dist: int, prio: int, into: AiSquad) -> int:
	var t: AiEntityTable = _ctx.kb.own
	var cand: PackedInt64Array = PackedInt64Array()
	var max2: int = max_dist * max_dist
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or t.squad[r] == into.id or t.squad[r] < 0:
			continue
		var owner_sq: AiSquad = squads.get(t.squad[r], null)
		if owner_sq == null or (owner_sq.id != 0 and owner_sq.prio >= prio):
			continue
		if role_mask != 0 and (t.role_mask[r] & role_mask) == 0:
			continue
		var dx: int = t.x[r] - near_x
		var dy: int = t.y[r] - near_y
		var d2: int = dx * dx + dy * dy
		if max_dist > 0 and d2 > max2:
			continue
		cand.append((mini(d2 / 1024, 0x3FFFFFFF) << 24) | (t.eid[r] & 0xFFFFFF))
	cand.sort()
	var added: int = 0
	for key: int in cand:
		if added >= count:
			break
		var eid: int = key & 0xFFFFFF
		var row: int = t.row(eid)
		if row < 0:
			continue
		var old: AiSquad = squads.get(t.squad[row], null)
		if old != null:
			old.remove(eid)
		t.squad[row] = into.id
		into.add(eid)
		added += 1
	claims += added
	return added


## Returns all units of a squad to the reserve (or frees them) and forgets the squad (the reserve itself stays).
func release(squad_id: int, to_reserve: bool = true) -> void:
	if squad_id == 0 or not squads.has(squad_id):
		return
	var s: AiSquad = squads[squad_id]
	var t: AiEntityTable = _ctx.kb.own
	for eid: int in s.units:
		var r: int = t.row(eid)
		if r < 0:
			continue
		if to_reserve:
			t.squad[r] = 0
			reserve.add(eid)
		else:
			t.squad[r] = -1
	squads.erase(squad_id)


func refresh(budget: AiBudget) -> void:
	var t: AiEntityTable = _ctx.kb.own
	for id: int in squads:
		var s: AiSquad = squads[id]
		s.role_counts.fill(0)
		if s.units.is_empty():
			s.value = 0
			s.radius = 0
			s.speed_min = 0
			continue
		if not budget.spend(1 + s.units.size() / 8):
			return
		var sx: int = 0
		var sy: int = 0
		var hp: int = 0
		var hpm: int = 0
		var val: int = 0
		var spd: int = 1 << 30
		var n: int = 0
		for eid: int in s.units:
			var r: int = t.row(eid)
			if r < 0:
				continue
			n += 1
			sx += t.x[r]
			sy += t.y[r]
			hp += t.hp[r]
			hpm += t.hp_max[r]
			val += t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1)
			var pr: AiUnitProfile = _ctx.unit_profile(t.def[r])
			if pr != null and pr.speed > 0:
				spd = mini(spd, pr.speed)
			var m: int = t.role_mask[r]
			for b: int in AiTypes.R_COMBAT:
				if (m & (1 << b)) != 0:
					s.role_counts[b] += 1
		if n == 0:
			continue
		s.cx = sx / n
		s.cy = sy / n
		var rad2: int = 0
		for eid2: int in s.units:
			var r2: int = t.row(eid2)
			if r2 >= 0:
				var dx: int = t.x[r2] - s.cx
				var dy: int = t.y[r2] - s.cy
				rad2 = maxi(rad2, dx * dx + dy * dy)
		s.radius = Fp.isqrt(rad2)
		s.value = val
		s.hp_frac_q8 = hp * 256 / maxi(hpm, 1)
		s.speed_min = 0 if spd == (1 << 30) else spd


func total_units() -> int:
	var n: int = 0
	for id: int in squads:
		n += (squads[id] as AiSquad).units.size()
	return n


func state_hash() -> int:
	var ids: PackedInt32Array = PackedInt32Array(squads.keys())
	ids.sort()
	var v: PackedInt32Array = PackedInt32Array([next_id, claims])
	for id: int in ids:
		v.append((squads[id] as AiSquad).state_hash())
	return AiRng.hash_ints(v)
