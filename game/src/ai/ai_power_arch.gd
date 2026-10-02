class_name AiPowerArch
extends RefCounted
## Archetype evaluators of the 48 support powers (ai.md 5.12.1 / 5.12.2). `evaluate(ctx, entry, budget)` returns true and fills
## `benefit` (credits-equivalent), `bx / by` (target, sub-cells), `bangle` and `target_eid` (own-structure powers) when the
## trigger of the entry holds; AiPowers compares the benefit with the price. The evaluators read one per-tick snapshot of my
## combat units (value, selector class, engaged flag) and of the fresh enemy items; nothing here writes anywhere.
##
## Definitions (spec): V(S) = sum(cost x hp / hp_max) of my units; engaged = damaged within 100 ticks, or an ATTACK / ATTACK_MOVE
## order with an armed enemy within 12 cells; fight_ref = 400 ticks; effect sizes are Q8 fractions (256 = 100 %).

const FIGHT_REF: int = 400
const ENGAGE_TICKS: int = 100
const ENGAGE_RANGE: int = 12 * Fp.CELL
const STATIONARY_TICKS: int = 40
const FRESH: int = 100
const DMG_Q8_DEFAULT: int = 150
const SEL_INF: int = 1
const SEL_VEH: int = 2
const SEL_AIR: int = 4
const SEL_SHIP: int = 8
const SEL_TANK: int = 16
const SEL_UNMANNED: int = 32
const SEL_ARTY: int = 64
const SEL_ALL: int = 127

const KIND_STRUCT: int = 1  ## e_kind value of a structure item
const KIND_UNIT_ITEM: int = 0
const REVEAL_MEMORY: int = 6000
const STALE_TICKS: int = 3600


## Static parameters of one power (built by AiPowers from its table, plus the resolved DefPower numbers).
class Entry extends RefCounted:
	var id: String = ""
	var pidx: int = -1
	var arch: int = AiTypes.PowerArch.REVEAL
	var min_level: int = 2
	var gap: int = 1800
	var ratio: int = 120  ## min benefit / cost in percent
	var sel: int = 0
	var eff: int = 26  ## Q8 effect size
	var dur: int = 300  ## ticks
	var radius: int = 6 * Fp.CELL
	var length: int = 0
	var cost: int = 0
	var engaged_min: int = 6
	var util: int = 0
	var emergency: bool = false
	var opt: PackedStringArray = PackedStringArray()
	var last_cast: int = AiTypes.NEVER
	var next_eval: int = 0
	var casts: int = 0
	var evals: int = 0
	var holds: int = 0
	var why_hist: Dictionary = {}  ## refusal reason -> count (debug)

	func has(flag: String) -> bool:
		return opt.has(flag)


# ---- result of the last evaluate() ----------------------------------------------------------------------------------
var benefit: int = 0
var bx: int = 0
var by: int = 0
var bangle: int = 0
var target_eid: int = 0
var why: String = ""  ## short reason of the last refusal (tests / debug)

# ---- snapshot of my combat units ------------------------------------------------------------------------------------
var snap_tick: int = -1
var un: int = 0
var u_row: PackedInt32Array = PackedInt32Array()
var u_eid: PackedInt32Array = PackedInt32Array()
var u_x: PackedInt32Array = PackedInt32Array()
var u_y: PackedInt32Array = PackedInt32Array()
var u_v: PackedInt32Array = PackedInt32Array()
var u_paid: PackedInt32Array = PackedInt32Array()  ## full paid cost (repair benefit)
var u_sel: PackedInt32Array = PackedInt32Array()
var u_eng: PackedByteArray = PackedByteArray()
var u_miss: PackedInt32Array = PackedInt32Array()  ## missing hp fraction q8
var u_move: PackedByteArray = PackedByteArray()
var u_flags: PackedInt32Array = PackedInt32Array()
# my structures
var sn: int = 0
var s_x: PackedInt32Array = PackedInt32Array()
var s_y: PackedInt32Array = PackedInt32Array()
var s_v: PackedInt32Array = PackedInt32Array()
var s_kind: PackedInt32Array = PackedInt32Array()
var s_flags: PackedInt32Array = PackedInt32Array()
var s_eid: PackedInt32Array = PackedInt32Array()
# fresh enemy items
var en: int = 0
var e_x: PackedInt32Array = PackedInt32Array()
var e_y: PackedInt32Array = PackedInt32Array()
var e_v: PackedInt32Array = PackedInt32Array()
var e_armed: PackedByteArray = PackedByteArray()
var e_stat: PackedByteArray = PackedByteArray()
var e_kind: PackedByteArray = PackedByteArray()
var e_arty: PackedByteArray = PackedByteArray()
var e_row: PackedInt32Array = PackedInt32Array()  ## row in kb.enemy_units (-1 for structures)

# group finder output
var g_v: int = 0
var g_n: int = 0
var g_x: int = 0
var g_y: int = 0

# memory of casts (guardrails)
var repair_zones: PackedInt32Array = PackedInt32Array()  ## x, y, until_tick
var reveal_hist: PackedInt32Array = PackedInt32Array()  ## x, y, tick
var trapped: PackedInt32Array = PackedInt32Array()  ## Aurora warning with my vehicles inside: x, y, n, impact_tick (or empty)
var _tmp: PackedInt32Array = PackedInt32Array()
var _ctx: AiContext = null


# ------------------------------------------------------------------------------------------------------- snapshot
func snapshot(ctx: AiContext, budget: AiBudget) -> void:
	if snap_tick == ctx.tick:
		return
	snap_tick = ctx.tick
	_ctx = ctx
	var t: AiEntityTable = ctx.kb.own
	budget.spend(2 + t.count / 6)
	for a: PackedInt32Array in [u_row, u_eid, u_x, u_y, u_v, u_paid, u_sel, u_miss, u_flags, s_x, s_y, s_v, s_kind, s_flags, s_eid,
			e_x, e_y, e_v, e_row]:
		a.resize(0)
	for b: PackedByteArray in [u_eng, u_move, e_armed, e_stat, e_kind, e_arty]:
		b.resize(0)
	un = 0
	sn = 0
	en = 0
	_snap_enemies(ctx)
	for r: int in t.count:
		var rm: int = t.role_mask[r]
		if t.kind[r] == AiTypes.KIND_STRUCTURE:
			if t.hp[r] <= 0 or (t.flags[r] & AiTypes.EF_UNDER_CONSTRUCTION) != 0:
				continue
			s_x.append(t.x[r])
			s_y.append(t.y[r])
			s_v.append(t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1))
			s_kind.append(ctx.res.kind_of_structure(t.def[r]))
			s_flags.append(t.flags[r])
			s_eid.append(t.eid[r])
			sn += 1
			continue
		if t.kind[r] != AiTypes.KIND_UNIT or t.hp[r] <= 0 or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		if (rm & (1 << AiTypes.R_COMBAT)) == 0:
			continue
		var prof: AiUnitProfile = ctx.unit_profile(t.def[r])
		if prof == null:
			continue
		var sel: int = 0
		match prof.move_class:
			AiTypes.MoveClass.FOOT:
				sel = SEL_INF
			AiTypes.MoveClass.WHEELED, AiTypes.MoveClass.TRACKED, AiTypes.MoveClass.AMPHIBIOUS:
				sel = SEL_VEH
			AiTypes.MoveClass.NAVAL, AiTypes.MoveClass.SUBMERGED:
				sel = SEL_SHIP
			AiTypes.MoveClass.AIR:
				sel = SEL_AIR
		if (rm & ((1 << AiTypes.R_TANK_MAIN) | (1 << AiTypes.R_HEAVY))) != 0 and sel == SEL_VEH:
			sel |= SEL_TANK
		if (rm & (1 << AiTypes.R_UNMANNED)) != 0:
			sel |= SEL_UNMANNED
		if (rm & (1 << AiTypes.R_ARTILLERY)) != 0:
			sel |= SEL_ARTY
		u_row.append(r)
		u_eid.append(t.eid[r])
		u_x.append(t.x[r])
		u_y.append(t.y[r])
		u_v.append(t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1))
		u_paid.append(t.paid[r])
		u_sel.append(sel)
		u_miss.append(256 - t.hp[r] * 256 / maxi(t.hp_max[r], 1))
		u_move.append(1 if (t.flags[r] & AiTypes.EF_MOVING) != 0 else 0)
		u_flags.append(t.flags[r])
		u_eng.append(0)
		un += 1
	budget.spend(1 + un / 8 + en / 16)
	# armed enemies bucketed in 12-cell blocks: "an armed enemy within 12 cells" looks at 3 x 3 buckets
	var buckets: Dictionary = {}
	for j: int in en:
		if e_armed[j] != 0:
			var key: int = (e_y[j] / ENGAGE_RANGE) * 4096 + e_x[j] / ENGAGE_RANGE
			if buckets.has(key):
				(buckets[key] as PackedInt32Array).append(j)
			else:
				buckets[key] = PackedInt32Array([j])
	for i: int in un:
		var r2: int = u_row[i]
		var dmg_age: int = ctx.tick - t.last_dmg[r2]
		if t.last_dmg[r2] > AiTypes.NEVER and dmg_age <= ENGAGE_TICKS:
			u_eng[i] = 1
			continue
		var ord: int = t.order[r2]
		if ord != AiTypes.OrderKind.ATTACK and ord != AiTypes.OrderKind.ATTACK_MOVE or buckets.is_empty():
			continue
		var bx0: int = u_x[i] / ENGAGE_RANGE
		var by0: int = u_y[i] / ENGAGE_RANGE
		var found: bool = false
		for dby: int in range(-1, 2):
			for dbx: int in range(-1, 2):
				var k: int = (by0 + dby) * 4096 + bx0 + dbx
				if not buckets.has(k):
					continue
				for j2: int in (buckets[k] as PackedInt32Array):
					var dx: int = e_x[j2] - u_x[i]
					var dy: int = e_y[j2] - u_y[i]
					if dx * dx + dy * dy <= ENGAGE_RANGE * ENGAGE_RANGE:
						found = true
						break
				if found:
					break
			if found:
				break
		if found:
			u_eng[i] = 1


func _snap_enemies(ctx: AiContext) -> void:
	var et: AiEntityTable = ctx.kb.enemy_units
	var v: AiWorldView = ctx.view
	for i: int in et.count:
		if ctx.tick - et.last_seen[i] > FRESH or (et.flags[i] & AiTypes.EF_DECOY) != 0 or not v.is_enemy(et.owner[i]) or et.hp[i] <= 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(et.owner[i], et.def[i])
		if p == null:
			continue
		e_x.append(et.x[i])
		e_y.append(et.y[i])
		e_v.append(et.paid[i] * et.hp[i] / maxi(et.hp_max[i], 1))
		e_armed.append(1 if p.is_combat() else 0)
		e_stat.append(1 if ctx.tick - et.last_moved[i] >= STATIONARY_TICKS else 0)
		e_kind.append(KIND_UNIT_ITEM)
		e_arty.append(1 if (p.role_mask & (1 << AiTypes.R_ARTILLERY)) != 0 else 0)
		e_row.append(i)
		en += 1
	var gt: AiGhostTable = ctx.kb.ghosts
	for j: int in gt.count:
		if gt.owner[j] < 0 or gt.eid[j] < 0 or ctx.tick - gt.last_seen[j] > FRESH or not v.is_enemy(gt.owner[j]):
			continue
		var sp: AiUnitProfile = ctx.struct_profile_of(gt.owner[j], gt.def[j])
		e_x.append(gt.x[j])
		e_y.append(gt.y[j])
		e_v.append(gt.value[j] * maxi(gt.hp_pct[j], 1) / 100)
		e_armed.append(1 if sp != null and sp.is_combat() else 0)
		e_stat.append(1)
		e_kind.append(KIND_STRUCT)
		e_arty.append(0)
		e_row.append(-1)
		en += 1


# ------------------------------------------------------------------------------------------------------- helpers
func own_value_in_circle(x: int, y: int, r: int, sel: int = SEL_ALL) -> int:
	var sum: int = 0
	var r2: int = r * r
	for i: int in un:
		if (u_sel[i] & sel) == 0:
			continue
		var dx: int = u_x[i] - x
		var dy: int = u_y[i] - y
		if dx * dx + dy * dy <= r2:
			sum += u_v[i]
	for k: int in sn:
		var dx2: int = s_x[k] - x
		var dy2: int = s_y[k] - y
		if sel == SEL_ALL and dx2 * dx2 + dy2 * dy2 <= r2:
			sum += s_v[k]
	return sum


## Best circle of radius r over my units of the selector (engaged ones only when eng_only): fills g_v / g_n / g_x / g_y (V-weighted
## centroid of the members). True when at least one member exists.
func best_group(r: int, sel: int, eng_only: bool, min_miss_q8: int = -1) -> bool:
	g_v = 0
	g_n = 0
	var r2: int = r * r
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in un:
		if (u_sel[i] & sel) != 0 and (not eng_only or u_eng[i] != 0) and u_miss[i] >= min_miss_q8:
			idx.append(i)
	if idx.is_empty():
		return false
	var step: int = maxi(1, idx.size() / 16)
	var best_v: int = 0
	var best_i: int = -1
	var a: int = 0
	while a < idx.size():
		var ci: int = idx[a]
		var sum: int = 0
		for j: int in idx:
			var dx: int = u_x[j] - u_x[ci]
			var dy: int = u_y[j] - u_y[ci]
			if dx * dx + dy * dy <= r2:
				sum += u_v[j]
		if sum > best_v:
			best_v = sum
			best_i = ci
		a += step
	if best_i < 0:
		best_i = idx[0]
	var cx: int = u_x[best_i]
	var cy: int = u_y[best_i]
	var mx: int = 0
	var my: int = 0
	var mw: int = 0
	for j2: int in idx:
		var dx2: int = u_x[j2] - cx
		var dy2: int = u_y[j2] - cy
		if dx2 * dx2 + dy2 * dy2 <= r2:
			mx += u_x[j2] * maxi(u_v[j2], 1)
			my += u_y[j2] * maxi(u_v[j2], 1)
			mw += maxi(u_v[j2], 1)
	if mw > 0:
		cx = mx / mw
		cy = my / mw
	g_x = cx
	g_y = cy
	for j3: int in idx:
		var dx3: int = u_x[j3] - cx
		var dy3: int = u_y[j3] - cy
		if dx3 * dx3 + dy3 * dy3 <= r2:
			g_v += u_v[j3]
			g_n += 1
	return g_n > 0


func armed_enemies_near(x: int, y: int, r: int) -> int:
	var n: int = 0
	var r2: int = r * r
	for j: int in en:
		if e_armed[j] == 0:
			continue
		var dx: int = e_x[j] - x
		var dy: int = e_y[j] - y
		if dx * dx + dy * dy <= r2:
			n += 1
	return n


func enemy_value_near(x: int, y: int, r: int, armed_only: bool = false) -> int:
	var s: int = 0
	var r2: int = r * r
	for j: int in en:
		if armed_only and e_armed[j] == 0:
			continue
		var dx: int = e_x[j] - x
		var dy: int = e_y[j] - y
		if dx * dx + dy * dy <= r2:
			s += e_v[j]
	return s


func _best(b: int, x: int, y: int, ang: int = 0) -> bool:
	if b <= benefit:
		return false
	benefit = b
	bx = x
	by = y
	bangle = ang
	return true


func _refuse(reason: String) -> bool:
	why = reason
	return false


func note_cast(e: Entry, x: int, y: int, tick: int) -> void:
	if e.arch == AiTypes.PowerArch.REPAIR_ZONE:
		repair_zones.append(x)
		repair_zones.append(y)
		repair_zones.append(tick + e.dur + 100)
		if repair_zones.size() > 24:
			repair_zones = repair_zones.slice(repair_zones.size() - 24)
	elif e.arch == AiTypes.PowerArch.REVEAL or e.arch == AiTypes.PowerArch.REVEAL_CORRIDOR:
		reveal_hist.append(x)
		reveal_hist.append(y)
		reveal_hist.append(tick)
		if reveal_hist.size() > 30:
			reveal_hist = reveal_hist.slice(reveal_hist.size() - 30)


func _recent_reveal(x: int, y: int, r: int, tick: int) -> bool:
	for i: int in reveal_hist.size() / 3:
		if tick - reveal_hist[3 * i + 2] >= REVEAL_MEMORY:
			continue
		var dx: int = reveal_hist[3 * i] - x
		var dy: int = reveal_hist[3 * i + 1] - y
		if dx * dx + dy * dy <= r * r:
			return true
	return false


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([repair_zones.size(), reveal_hist.size(), benefit, bx, by]))


# ------------------------------------------------------------------------------------------------------- dispatch
func evaluate(ctx: AiContext, e: Entry, budget: AiBudget) -> bool:
	benefit = 0
	bx = 0
	by = 0
	bangle = 0
	target_eid = 0
	why = ""
	snapshot(ctx, budget)
	e.evals += 1
	var ok: bool = false
	match e.arch:
		AiTypes.PowerArch.REVEAL:
			ok = _reveal(ctx, e)
		AiTypes.PowerArch.REVEAL_CORRIDOR:
			ok = _corridor(ctx, e)
		AiTypes.PowerArch.STRIKE:
			ok = _strike(ctx, e, false, budget)
		AiTypes.PowerArch.MARK:
			ok = _mark(ctx, e, budget)
		AiTypes.PowerArch.BUFF:
			ok = _buff(ctx, e)
		AiTypes.PowerArch.BUFF_MOVE:
			ok = _buff_move(ctx, e)
		AiTypes.PowerArch.PRODUCTION:
			ok = _production(ctx, e)
		AiTypes.PowerArch.REPAIR_ZONE:
			ok = _repair(ctx, e)
		AiTypes.PowerArch.SMOKE:
			ok = _smoke(ctx, e)
		AiTypes.PowerArch.DECOY:
			ok = _decoy(ctx, e)
		AiTypes.PowerArch.GUARD_STRUCT:
			ok = _guard(ctx, e)
		AiTypes.PowerArch.CAMO_HOLD:
			ok = _camo_hold(ctx, e)
		AiTypes.PowerArch.ANTI_EMP:
			ok = _anti_emp(ctx, e)
		AiTypes.PowerArch.TRANSPORT_BUFF:
			ok = _transport(ctx, e)
		AiTypes.PowerArch.ECON_BOOST:
			ok = _econ(ctx, e)
		AiTypes.PowerArch.FIELD_BOOST:
			ok = _field(ctx, e)
	if not ok or benefit <= 0:
		e.holds += 1
		e.why_hist[why] = int(e.why_hist.get(why, 0)) + 1
		return false
	return true


# ------------------------------------------------------------------------------------------------------- REVEAL
func _reveal(ctx: AiContext, e: Entry) -> bool:
	var kb: AiKnowledge = ctx.kb
	var v: AiWorldView = ctx.view
	var gt: AiGhostTable = kb.ghosts
	var cand_x: PackedInt32Array = PackedInt32Array()
	var cand_y: PackedInt32Array = PackedInt32Array()
	var cand_i: PackedInt32Array = PackedInt32Array()
	var camo: PackedInt32Array = PackedInt32Array()
	var camo_ok: bool = kb.camo_alert(camo) and ctx.tick - camo[2] <= 400 and e.has("detect")
	var only_new: bool = e.has("scout_new")
	# (1) stale or never scouted enemy bases
	if not e.has("detect_only"):
		for p: int in kb.enemy_pids:
			if not v.player_alive(p) or not v.is_enemy(p):
				continue
			var best: int = -1
			for j: int in gt.count:
				if gt.owner[j] == p and gt.kind[j] == AiTypes.StructKind.HQ and (best < 0 or gt.conf[j] > gt.conf[best]):
					best = j
			if best < 0:
				continue
			var info: int = 0
			if gt.eid[best] < 0:
				if ctx.tick > 240 * SimConfig.TPS:
					info = 100
			elif not only_new and ctx.tick - gt.last_seen[best] > STALE_TICKS:
				info = 100
			if info > 0:
				cand_x.append(gt.x[best])
				cand_y.append(gt.y[best])
				cand_i.append(info)
	# (2) camouflage alert (detecting powers)
	if camo_ok:
		cand_x.append(camo[0])
		cand_y.append(camo[1])
		cand_i.append(60)
	# (3) spotting for idle artillery
	if e.has("spot_arty"):
		var sp: PackedInt32Array = _spot_arty_target(ctx)
		if not sp.is_empty():
			cand_x.append(sp[0])
			cand_y.append(sp[1])
			cand_i.append(50 + 50)
	# (4) wrecks near salvagers
	if e.has("wrecks"):
		var wp: PackedInt32Array = _wreck_cluster(ctx, 1500, 25 * Fp.CELL)
		if not wp.is_empty():
			cand_x.append(wp[0])
			cand_y.append(wp[1])
			cand_i.append(30 + 70)
	if e.has("detect_only") and not camo_ok:
		return _refuse("no camo alert")
	var top: int = 0
	for k: int in cand_i.size():
		var info2: int = cand_i[k]
		if camo_ok and k < cand_i.size() and cand_i[k] != 60:
			var dxc: int = cand_x[k] - camo[0]
			var dyc: int = cand_y[k] - camo[1]
			if dxc * dxc + dyc * dyc <= e.radius * e.radius:
				info2 += 60
		if _recent_reveal(cand_x[k], cand_y[k], e.radius, ctx.tick):
			continue
		if info2 > top:
			top = info2
			# the summoned flyer enters from the `angle` side of the target: from my side, away from the enemy defenses
			var ang: int = Fp.angle_between(cand_x[k], cand_y[k], v.start_cell_x(v.me()) * Fp.CELL, v.start_cell_y(v.me()) * Fp.CELL)
			_best(info2 * e.cost / 60, cand_x[k], cand_y[k], ang)
	return benefit > 0 or _refuse("nothing to reveal")


## Centre of the enemy cluster an idle artillery piece of mine could hit if it saw it (known ghost, no vision, within range).
func _spot_arty_target(ctx: AiContext) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var t: AiEntityTable = ctx.kb.own
	var gt: AiGhostTable = ctx.kb.ghosts
	for i: int in un:
		if (u_sel[i] & SEL_ARTY) == 0 or t.order[u_row[i]] != AiTypes.OrderKind.IDLE and t.order[u_row[i]] != AiTypes.OrderKind.DEPLOYED:
			continue
		var prof: AiUnitProfile = ctx.unit_profile(t.def[u_row[i]])
		if prof == null or prof.range <= 0:
			continue
		for j: int in gt.count:
			if gt.owner[j] < 0 or not ctx.view.is_enemy(gt.owner[j]) or gt.value[j] < 500:
				continue
			var dx: int = gt.x[j] - u_x[i]
			var dy: int = gt.y[j] - u_y[i]
			if dx * dx + dy * dy > prof.range * prof.range:
				continue
			if ctx.view.cell_visible(gt.x[j] >> Fp.CELL_SHIFT, gt.y[j] >> Fp.CELL_SHIFT):
				continue
			out.append(gt.x[j])
			out.append(gt.y[j])
			return out
	return out


## Centroid of the wrecks within `r` of my salvagers when their paid value reaches `min_paid` (empty otherwise).
func _wreck_cluster(ctx: AiContext, min_paid: int, r: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var t: AiEntityTable = ctx.kb.own
	var info: PackedInt32Array = PackedInt32Array()
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in t.count:
		if t.kind[row] != AiTypes.KIND_UNIT or (t.role_mask[row] & (1 << AiTypes.R_SALVAGER)) == 0:
			continue
		ctx.view.wrecks_in_circle(t.x[row], t.y[row], r, ids)
		var paid: int = 0
		var sx: int = 0
		var sy: int = 0
		for id: int in ids:
			ctx.view.wreck_info(id, info)
			paid += info[2]
			sx += info[0]
			sy += info[1]
		if paid >= min_paid and not ids.is_empty():
			out.append(sx / ids.size())
			out.append(sy / ids.size())
			out.append(paid)
			out.append(ids.size())
			return out
	return out


func _corridor(ctx: AiContext, e: Entry) -> bool:
	var kb: AiKnowledge = ctx.kb
	if ctx.tick < 240 * SimConfig.TPS:
		return _refuse("too early")
	var p: int = kb.primary
	if p < 0:
		return _refuse("no primary enemy")
	var mx: int = (ctx.view.start_cell_x(ctx.view.me()) + ctx.view.start_cell_x(p)) * Fp.CELL / 2 + Fp.CELL / 2
	var my: int = (ctx.view.start_cell_y(ctx.view.me()) + ctx.view.start_cell_y(p)) * Fp.CELL / 2 + Fp.CELL / 2
	if _recent_reveal(mx, my, e.length / 2, ctx.tick):
		return _refuse("recent")
	var ang: int = Fp.angle_between(ctx.view.start_cell_x(ctx.view.me()), ctx.view.start_cell_y(ctx.view.me()), ctx.view.start_cell_x(p), ctx.view.start_cell_y(p))
	return _best(100 * e.cost / 60, mx, my, ang)


# ------------------------------------------------------------------------------------------------------- STRIKE / MARK
## Best circle of `e.radius` over the fresh enemy items: sum(w_stat x v x dmg) - 2 V(own). `only_arty`: MARK-STRIKE positions.
func _strike(ctx: AiContext, e: Entry, only_arty: bool, budget: AiBudget) -> bool:
	if en == 0:
		return _refuse("no targets")
	var r: int = e.radius
	var r2: int = r * r
	# candidate centres: the 8 most valuable eligible items
	var cands: PackedInt32Array = _top_items(8, only_arty)
	budget.spend(1 + cands.size() * en / 48)
	var best_b: int = 0
	var best_x: int = 0
	var best_y: int = 0
	var best_own: int = 0
	for i: int in cands:
		var cx: int = e_x[i]
		var cy: int = e_y[i]
		for pass_i: int in 2:
			var sum: int = 0
			var mx: int = 0
			var my: int = 0
			var mw: int = 0
			for j: int in en:
				if only_arty and e_arty[j] == 0:
					continue
				var dx: int = e_x[j] - cx
				var dy: int = e_y[j] - cy
				if dx * dx + dy * dy > r2:
					continue
				var w: int = 256 if (e_stat[j] != 0) else 64
				sum += w * e_v[j] / 256 * mini(256, DMG_Q8_DEFAULT) / 256
				mx += e_x[j] * maxi(e_v[j], 1)
				my += e_y[j] * maxi(e_v[j], 1)
				mw += maxi(e_v[j], 1)
			if pass_i == 0 and mw > 0:
				cx = mx / mw
				cy = my / mw
			elif pass_i == 1:
				var own: int = own_value_in_circle(cx, cy, r)
				var net: int = sum - 2 * own
				if net > best_b and own * 5 <= sum:
					best_b = net
					best_x = cx
					best_y = cy
					best_own = own
	if best_b <= 0:
		return _refuse("no worthwhile circle")
	if not ctx.view.cell_visible(best_x >> Fp.CELL_SHIFT, best_y >> Fp.CELL_SHIFT):
		return _refuse("not visible")
	if best_own * 5 > best_b:
		return _refuse("friendly fire")
	return _best(best_b, best_x, best_y)


## Indices of the `n` most valuable fresh enemy items (arty only when asked), best first.
func _top_items(n: int, only_arty: bool) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for j: int in en:
		if only_arty and e_arty[j] == 0:
			continue
		var pos: int = out.size()
		while pos > 0 and e_v[out[pos - 1]] < e_v[j]:
			pos -= 1
		if pos >= n:
			continue
		out.insert(pos, j)
		if out.size() > n:
			out.resize(n)
	return out


func _mark(ctx: AiContext, e: Entry, budget: AiBudget) -> bool:
	# enemy artillery that fired within 8 s
	var fired: PackedInt32Array = PackedInt32Array()
	var et: AiEntityTable = ctx.kb.enemy_units
	for j: int in en:
		if e_row[j] < 0 or e_arty[j] == 0:
			continue
		var lf: int = ctx.view.e_last_fire(et.eid[e_row[j]])
		if lf >= 0 and ctx.tick - lf <= 160:
			fired.append(j)
	if fired.size() < (2 if e.has("need2") else 1):
		return _refuse("no artillery fired")
	var sx: int = 0
	var sy: int = 0
	var sv: int = 0
	var stat_v: int = 0
	for j2: int in fired:
		sx += e_x[j2]
		sy += e_y[j2]
		sv += e_v[j2]
		if e_stat[j2] != 0:
			stat_v += e_v[j2]
	var cx: int = sx / fired.size()
	var cy: int = sy / fired.size()
	if e.has("strike"):
		if stat_v < 1500:
			return _refuse("value below 1500")
		var own: int = own_value_in_circle(cx, cy, e.radius)
		var b: int = stat_v * DMG_Q8_DEFAULT / 256 - 2 * own
		if own * 5 > stat_v * DMG_Q8_DEFAULT / 256:
			return _refuse("friendly fire")
		return _best(b, cx, cy)
	# Solution: my ground force within 14 cells of the marked artillery
	var eng_v: int = 0
	for i: int in un:
		if (u_sel[i] & (SEL_INF | SEL_VEH)) == 0 or u_eng[i] == 0:
			continue
		var dx: int = u_x[i] - cx
		var dy: int = u_y[i] - cy
		if dx * dx + dy * dy <= 14 * Fp.CELL * 14 * Fp.CELL:
			eng_v += u_v[i]
	budget.spend(1)
	return _best(eng_v * 15 / 100 * 12 / 20, cx, cy)


# ------------------------------------------------------------------------------------------------------- BUFF
func _buff(ctx: AiContext, e: Entry) -> bool:
	if not best_group(e.radius, e.sel, true):
		return _refuse("no engaged group")
	if g_n < e.engaged_min:
		return _refuse("group too small")
	if e.has("stationary"):
		var still: int = 0
		for i: int in un:
			if (u_sel[i] & e.sel) != 0 and u_move[i] == 0 and _in(u_x[i], u_y[i], g_x, g_y, e.radius):
				still += 1
		if still < e.engaged_min or armed_enemies_near(g_x, g_y, 18 * Fp.CELL) == 0:
			return _refuse("not stationary")
	if e.has("relay") and not _relay_near(ctx, g_x, g_y):
		return _refuse("no relay")
	if e.has("suppress"):
		var sup: int = 0
		for i2: int in un:
			if (u_flags[i2] & AiTypes.EF_SUPPRESSED) != 0 and _in(u_x[i2], u_y[i2], g_x, g_y, e.radius):
				sup += 1
		if sup < 2 and not _suppressive_near(ctx, g_x, g_y):
			return _refuse("no suppression")
	if e.has("finisher"):
		return _finisher(ctx, e)
	if e.has("no_pursuit"):
		if armed_enemies_near(g_x, g_y, 6 * Fp.CELL) > 0 and enemy_value_near(g_x, g_y, 14 * Fp.CELL, true) * 2 < g_v:
			return _refuse("pursuing")
	var scale: int = mini(256, e.dur * 256 / FIGHT_REF)
	return _best(g_v * e.eff / 256 * scale / 256, g_x, g_y)


func _in(ax: int, ay: int, bx_: int, by_: int, r: int) -> bool:
	var dx: int = ax - bx_
	var dy: int = ay - by_
	return dx * dx + dy * dy <= r * r


func _relay_near(ctx: AiContext, x: int, y: int) -> bool:
	for k: int in sn:
		if s_kind[k] == AiTypes.StructKind.RELAY and (s_flags[k] & AiTypes.EF_UNPOWERED) == 0 and _in(s_x[k], s_y[k], x, y, 10 * Fp.CELL):
			return true
	return false


func _suppressive_near(ctx: AiContext, x: int, y: int) -> bool:
	var gt: AiGhostTable = ctx.kb.ghosts
	for j: int in gt.count:
		if gt.owner[j] >= 0 and (gt.kind[j] == AiTypes.StructKind.WATCHTOWER or gt.kind[j] == AiTypes.StructKind.ADV_DEFENSE) \
				and _in(gt.x[j], gt.y[j], x, y, 14 * Fp.CELL):
			return true
	return false


## Finisher (Capacitor Discharge / Software Surge): the enemy in range dies inside the window and its remaining fire during the
## silence is small (never opens a fight).
func _finisher(ctx: AiContext, e: Entry) -> bool:
	var t: AiEntityTable = ctx.kb.own
	var my_dps: int = 0
	var my_hp: int = 0
	for i: int in un:
		if (u_sel[i] & e.sel) == 0 or not _in(u_x[i], u_y[i], g_x, g_y, e.radius):
			continue
		var p: AiUnitProfile = ctx.unit_profile(t.def[u_row[i]])
		my_dps += p.dps_avg_x100() / 100
		my_hp += t.hp[u_row[i]]
	var enemy_hp: int = 0
	var enemy_dps: int = 0
	var et: AiEntityTable = ctx.kb.enemy_units
	for j: int in en:
		if e_row[j] < 0 or not _in(e_x[j], e_y[j], g_x, g_y, 10 * Fp.CELL):
			continue
		var ep: AiUnitProfile = ctx.unit_profile_of(et.owner[e_row[j]], et.def[e_row[j]])
		enemy_hp += et.hp[e_row[j]]
		enemy_dps += ep.dps_avg_x100() / 100
	var win_s: int = maxi(e.dur / SimConfig.TPS, 1)
	if enemy_hp == 0 or enemy_hp * 100 > 120 * my_dps * win_s:
		return _refuse("enemy hp beyond the window")
	var silence_s: int = 4 if e.has("silence4") else 3
	if enemy_dps * silence_s * 100 > 25 * my_hp * (1 if silence_s == 4 else 1):
		return _refuse("enemy fire after the silence")
	return _best(e.util, g_x, g_y)


# ------------------------------------------------------------------------------------------------------- BUFF_MOVE
func _buff_move(ctx: AiContext, e: Entry) -> bool:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null:
		return _refuse("no brain")
	for o: AiOp in b.ops:
		if o.is_over() or (o.type != AiTypes.OpType.ATTACK and o.type != AiTypes.OpType.HARASS and o.type != AiTypes.OpType.LANDING):
			continue
		var advancing: bool = o.state == AiTypes.OpState.ADVANCING
		var retreating: bool = o.state == AiTypes.OpState.RETREATING
		if not ((e.has("adv") and advancing) or (e.has("ret") and retreating)):
			continue
		# eligible members of the op around its centroid
		var sx: int = 0
		var sy: int = 0
		var n: int = 0
		for i: int in un:
			if (u_sel[i] & e.sel) != 0 and o.ids.has(u_eid[i]):
				sx += u_x[i]
				sy += u_y[i]
				n += 1
		if n < e.engaged_min:
			continue
		var cx: int = sx / n
		var cy: int = sy / n
		var inside: int = 0
		for i2: int in un:
			if (u_sel[i2] & e.sel) != 0 and o.ids.has(u_eid[i2]) and _in(u_x[i2], u_y[i2], cx, cy, e.radius):
				inside += 1
		if inside < e.engaged_min:
			continue
		if advancing and e.has("adv"):
			if AiForce.cells(cx, cy, o.tx, o.ty) < 25 or ctx.tick - o.state_since > 240:
				continue
			if e.has("suppress") and not _suppressive_near(ctx, o.tx, o.ty):
				var sup: int = 0
				for i3: int in un:
					if (u_flags[i3] & AiTypes.EF_SUPPRESSED) != 0:
						sup += 1
				if sup < 2:
					continue
		if retreating and e.has("ret") and armed_enemies_near(cx, cy, 12 * Fp.CELL) == 0:
			continue
		return _best(e.util, cx, cy)
	return _refuse("no op fits")


# ------------------------------------------------------------------------------------------------------- PRODUCTION
func _production(ctx: AiContext, e: Entry) -> bool:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null:
		return _refuse("no brain")
	var eco: AiEconomy = b.eco()
	var v: AiWorldView = ctx.view
	if e.has("rearm"):
		return _rearm(ctx, e)
	if v.credits() < 1500 or v.power_shortage():
		return _refuse("credits or power")
	var rate: int = 0
	var lines: int = 0
	for k: int in eco.prod_eid.size():
		var kind: int = eco.prod_kind[k]
		if kind != AiTypes.StructKind.BARRACKS and kind != AiTypes.StructKind.FACTORY:
			continue
		if eco.prod_qlen[k] <= 0:
			continue
		v.queue_of(eco.prod_eid[k], _tmp)
		if _tmp.is_empty():
			continue
		lines += 1
		rate += v.unit_cost(_tmp[0]) * SimConfig.TPS / maxi(v.unit_ticks(_tmp[0]), 1)
	if lines < 3:
		return _refuse("fewer than 3 lines")
	var dur_s: int = e.dur / SimConfig.TPS
	return _best(rate * e.eff / 256 * dur_s, 0, 0)


## Rapid Turnaround: >= 4 aircraft waiting for ammo at one powered airfield.
func _rearm(ctx: AiContext, e: Entry) -> bool:
	var t: AiEntityTable = ctx.kb.own
	var best: int = 0
	var best_eid: int = 0
	var bpx: int = 0
	var bpy: int = 0
	for k: int in sn:
		if s_kind[k] != AiTypes.StructKind.AIRFIELD or (s_flags[k] & AiTypes.EF_UNPOWERED) != 0:
			continue
		var n: int = 0
		var val: int = 0
		for i: int in un:
			if (u_sel[i] & SEL_AIR) == 0 or not _in(u_x[i], u_y[i], s_x[k], s_y[k], 4 * Fp.CELL):
				continue
			if ctx.view.e_ammo(u_eid[i]) == 0 and t.order[u_row[i]] != AiTypes.OrderKind.MOVE:
				n += 1
				val += u_v[i]
		if n > best:
			best = n
			best_eid = s_eid[k]
			bpx = s_x[k]
			bpy = s_y[k]
	if best < 4:
		return _refuse("fewer than 4 rearming")
	var b: int = 0
	for i2: int in un:
		if (u_sel[i2] & SEL_AIR) != 0 and _in(u_x[i2], u_y[i2], bpx, bpy, 4 * Fp.CELL):
			b += u_v[i2]
	target_eid = best_eid
	return _best(b * e.eff / 256, bpx, bpy)


# ------------------------------------------------------------------------------------------------------- REPAIR_ZONE
func _repair(ctx: AiContext, e: Entry) -> bool:
	var min_miss: int = 38 if not e.has("miss30") else 77  # 15 % / 30 % of hp missing
	var min_n: int = 5 if e.has("miss30") else 3
	var eff_total: int = e.eff
	var r: int = e.radius
	var r2: int = r * r
	var step: int = maxi(1, un / 24)
	var best_b: int = 0
	var best_i: int = -1
	var i: int = 0
	while i < un:
		if (u_sel[i] & e.sel) == 0 or u_miss[i] < min_miss:
			i += step
			continue
		var b: int = 0
		var n: int = 0
		for j: int in un:
			if (u_sel[j] & e.sel) == 0 or u_miss[j] < min_miss:
				continue
			var dx: int = u_x[j] - u_x[i]
			var dy: int = u_y[j] - u_y[i]
			if dx * dx + dy * dy <= r2:
				b += u_paid[j] * mini(eff_total, u_miss[j]) / 256
				n += 1
		if n >= min_n and b > best_b:
			best_b = b
			best_i = i
		i += step
	if best_i < 0:
		return _refuse("no damaged group")
	# centre = centroid of the damaged eligible units within the circle
	var mx: int = 0
	var my: int = 0
	var mw: int = 0
	for j2: int in un:
		if (u_sel[j2] & e.sel) != 0 and u_miss[j2] >= min_miss and _in(u_x[j2], u_y[j2], u_x[best_i], u_y[best_i], r):
			mx += u_x[j2]
			my += u_y[j2]
			mw += 1
	var cx: int = mx / mw
	var cy: int = my / mw
	var quiet: int = 14 * Fp.CELL if e.has("miss30") else 12 * Fp.CELL
	if armed_enemies_near(cx, cy, quiet) > 0:
		return _refuse("enemy near")
	for z: int in repair_zones.size() / 3:
		if repair_zones[3 * z + 2] > ctx.tick and _in(repair_zones[3 * z], repair_zones[3 * z + 1], cx, cy, 10 * Fp.CELL):
			return _refuse("repair zone active")
	# structures count for Repair Swarm
	if e.has("structs"):
		for k: int in sn:
			if _in(s_x[k], s_y[k], cx, cy, r):
				best_b += s_v[k] * 30 / 256
	return _best(best_b, cx, cy)


# ------------------------------------------------------------------------------------------------------- SMOKE
func _smoke(ctx: AiContext, e: Entry) -> bool:
	if e.has("crossing"):
		return _refuse("no crossing op")
	if e.has("retreat"):
		var b: AiBrain = ctx.brain as AiBrain
		var retreating: bool = false
		if b != null:
			for o: AiOp in b.ops:
				if not o.is_over() and o.state == AiTypes.OpState.RETREATING:
					retreating = true
		if not retreating:
			return _refuse("not retreating")
	# my ground units that take fire from outside the circle
	var hit_sel: int = SEL_INF | SEL_VEH
	var t: AiEntityTable = ctx.kb.own
	var saved_eng: PackedByteArray = u_eng.duplicate()
	for i: int in un:
		var age: int = ctx.tick - t.last_dmg[u_row[i]]
		u_eng[i] = 1 if t.last_dmg[u_row[i]] > AiTypes.NEVER and age <= 60 else 0
	var found: bool = best_group(e.radius, hit_sel, true)
	u_eng = saved_eng
	if not found or g_n < 3:
		return _refuse("nobody under fire")
	var own_v: int = own_value_in_circle(g_x, g_y, e.radius, hit_sel)
	var enemy_v: int = enemy_value_near(g_x, g_y, e.radius, true)
	if enemy_v * 10 > own_v * 3:
		return _refuse("enemy inside the smoke")
	var arty_share: int = 0
	var tot: int = 0
	var art: int = 0
	for j: int in en:
		if _in(e_x[j], e_y[j], g_x, g_y, 20 * Fp.CELL):
			tot += e_v[j]
			if e_arty[j] != 0:
				art += e_v[j]
	if tot > 0:
		arty_share = art * 256 / tot
	var scale: int = mini(256, e.dur * 256 / FIGHT_REF)
	return _best(g_v * 77 / 256 * scale / 256 * (256 - arty_share) / 256, g_x, g_y)


# ------------------------------------------------------------------------------------------------------- DECOY
func _decoy(ctx: AiContext, e: Entry) -> bool:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null:
		return _refuse("no brain")
	var v: AiWorldView = ctx.view
	var home_x: int = v.start_cell_x(v.me()) * Fp.CELL + Fp.CELL / 2
	var home_y: int = v.start_cell_y(v.me()) * Fp.CELL + Fp.CELL / 2
	var px: int = 0
	var py: int = 0
	var have: bool = false
	if e.has("observed"):
		# False Front: an enemy scout or aircraft looks at my base
		var seen: bool = false
		var watch_mask: int = (1 << AiTypes.R_SCOUT_LIGHT) | (1 << AiTypes.R_FIGHTER) | (1 << AiTypes.R_BOMBER) | (1 << AiTypes.R_EW_AIR)
		for j: int in en:
			if e_kind[j] != KIND_UNIT_ITEM or not _in(e_x[j], e_y[j], home_x, home_y, 20 * Fp.CELL):
				continue
			if e_armed[j] == 0 or (e_row[j] >= 0 and (ctx.kb.enemy_units.role_mask[e_row[j]] & watch_mask) != 0):
				seen = true
		if not seen:
			return _refuse("nobody observes")
		var ex: PackedInt32Array = PackedInt32Array()
		AiPlacer.toward_enemy(ctx, home_x, home_y, ex)
		px = home_x + ex[0] * 16 * Fp.CELL / 1024
		py = home_y + ex[1] * 16 * Fp.CELL / 1024
		have = true
	else:
		# a real op launching now: place the decoy 25+ cells off its path
		for o: AiOp in b.ops:
			if o.is_over() or ctx.tick - o.created_tick > 200 or o.state < AiTypes.OpState.STAGING:
				continue
			if e.has("landing") and o.type != AiTypes.OpType.LANDING:
				continue
			if not e.has("landing") and o.type != AiTypes.OpType.ATTACK:
				continue
			var mx: int = (home_x + o.tx) / 2
			var my: int = (home_y + o.ty) / 2
			var dx: int = o.tx - home_x
			var dy: int = o.ty - home_y
			var len: int = maxi(Fp.dist(dx, dy), 1)
			var nx: int = -dy * 1024 / len
			var ny: int = dx * 1024 / len
			for side: int in [1, -1]:
				for off: int in [26, 32, 40]:
					var tx: int = mx + side * nx * off * Fp.CELL / 1024
					var ty: int = my + side * ny * off * Fp.CELL / 1024
					var cx: int = tx >> Fp.CELL_SHIFT
					var cy: int = ty >> Fp.CELL_SHIFT
					if cx < 2 or cy < 2 or cx >= v.map_w() - 2 or cy >= v.map_h() - 2 or not v.cell_explored(cx, cy):
						continue
					var ok: bool = v.passable(cx, cy, AiTypes.MoveClass.WHEELED) or (e.has("landing") and v.is_water(cx, cy))
					if ok and not have:
						px = tx
						py = ty
						have = true
	if not have:
		return _refuse("no decoy site")
	return _best(e.util, px, py)


# ------------------------------------------------------------------------------------------------------- GUARD_STRUCT
func _guard(ctx: AiContext, e: Entry) -> bool:
	# attacked defenses / production: the densest group of them with armed enemies within 14 cells
	var best: int = -1
	var best_v: int = 0
	for k: int in sn:
		if not AiForce.is_defense_kind(s_kind[k]) and s_kind[k] != AiTypes.StructKind.BARRACKS and s_kind[k] != AiTypes.StructKind.FACTORY:
			continue
		var v: int = 0
		var n: int = 0
		for k2: int in sn:
			if (AiForce.is_defense_kind(s_kind[k2]) or s_kind[k2] == AiTypes.StructKind.BARRACKS or s_kind[k2] == AiTypes.StructKind.FACTORY) \
					and _in(s_x[k2], s_y[k2], s_x[k], s_y[k], e.radius):
				v += s_v[k2]
				n += 1
		if armed_enemies_near(s_x[k], s_y[k], 14 * Fp.CELL) >= 6 and n >= (4 if e.has("min4") else 2) and v > best_v:
			best_v = v
			best = k
	if best < 0:
		return _refuse("base not under attack")
	var share: int = 256
	if e.has("explosive"):
		var tot: int = 0
		var expl: int = 0
		for j: int in en:
			if e_armed[j] != 0 and _in(e_x[j], e_y[j], s_x[best], s_y[best], 14 * Fp.CELL):
				tot += e_v[j]
				if e_arty[j] != 0 or e_kind[j] == KIND_UNIT_ITEM and e_row[j] >= 0 and (ctx.kb.enemy_units.role_mask[e_row[j]] & (1 << AiTypes.R_TANK_MAIN)) != 0:
					expl += e_v[j]
		share = expl * 256 / maxi(tot, 1)
		if share < 102:
			return _refuse("explosive share below 40 %")
	var scale: int = mini(256, e.dur * 256 / FIGHT_REF)
	return _best(best_v * e.eff / 256 * scale / 256 * share / 256, s_x[best], s_y[best])


# ------------------------------------------------------------------------------------------------------- CAMO_HOLD
func _camo_hold(ctx: AiContext, e: Entry) -> bool:
	# a stationary group of >= 6 that an enemy force reaches within 240 ticks, with no detector among the visible enemies
	var t: AiEntityTable = ctx.kb.own
	var best_i: int = -1
	var best_n: int = 0
	for i: int in un:
		if u_move[i] != 0 or t.order[u_row[i]] == AiTypes.OrderKind.ATTACK:
			continue
		var n: int = 0
		for j: int in un:
			if u_move[j] == 0 and _in(u_x[j], u_y[j], u_x[i], u_y[i], e.radius):
				n += 1
		if n > best_n:
			best_n = n
			best_i = i
	if best_n < 6:
		return _refuse("no stationary group")
	var gx: int = u_x[best_i]
	var gy: int = u_y[best_i]
	var et: AiEntityTable = ctx.kb.enemy_units
	var eta_ok: bool = false
	for j2: int in en:
		if e_armed[j2] == 0 or e_row[j2] < 0:
			continue
		var ep: AiUnitProfile = ctx.unit_profile_of(et.owner[e_row[j2]], et.def[e_row[j2]])
		if (ep.role_mask & (1 << AiTypes.R_DETECTOR)) != 0:
			return _refuse("a detector is visible")
		var d: int = Fp.dist(e_x[j2] - gx, e_y[j2] - gy)
		if ep.speed > 0 and d / ep.speed <= 240 and d > 6 * Fp.CELL:
			eta_ok = true
	if not eta_ok:
		return _refuse("nobody approaches")
	return _best(e.util, gx, gy)


# ------------------------------------------------------------------------------------------------------- ANTI_EMP
func _anti_emp(ctx: AiContext, e: Entry) -> bool:
	if trapped.size() < 4:
		return _refuse("no Aurora warning")
	if trapped[2] < 6:
		return _refuse("fewer than 6 vehicles trapped")
	var left: int = trapped[3] - ctx.tick
	if left > 30 + ctx.cmd.exec_lag_est or left < 4:
		return _refuse("not yet the moment")
	return _best(e.util, trapped[0], trapped[1])


# ------------------------------------------------------------------------------------------------------- TRANSPORT_BUFF
func _transport(ctx: AiContext, e: Entry) -> bool:
	var t: AiEntityTable = ctx.kb.own
	var mask: int = (1 << AiTypes.R_LANDING_TRANSPORT) | (1 << AiTypes.R_AMPH_TRANSPORT)
	var n: int = 0
	var sx: int = 0
	var sy: int = 0
	var cargo_v: int = 0
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or (t.role_mask[r] & mask) == 0 or (t.flags[r] & AiTypes.EF_MOVING) == 0:
			continue
		var c: int = ctx.view.e_cargo(t.eid[r])
		if c <= 0:
			continue
		n += 1
		sx += t.x[r]
		sy += t.y[r]
		cargo_v += t.paid[r] * c
	if n < 2:
		return _refuse("fewer than 2 loaded transports")
	if e.has("landing"):
		var cx: int = sx / n
		var cy: int = sy / n
		if armed_enemies_near(cx, cy, 14 * Fp.CELL) == 0:
			return _refuse("no enemy at the landing zone")
		return _best(cargo_v * 51 / 256 * 6 / 20 + 0, cx, cy)
	return _best(e.util, sx / n, sy / n)


# ------------------------------------------------------------------------------------------------------- ECON_BOOST
func _econ(ctx: AiContext, e: Entry) -> bool:
	var t: AiEntityTable = ctx.kb.own
	if e.has("salvage"):
		var wc: PackedInt32Array = _wreck_cluster(ctx, 900, 25 * Fp.CELL)
		if wc.is_empty() or wc[3] < 3:
			return _refuse("fewer than 3 wrecks")
		if armed_enemies_near(wc[0], wc[1], 16 * Fp.CELL) > 0:
			return _refuse("area not secure")
		return _best(wc[2] / 2, wc[0], wc[1])
	# fleeing collectors: >= 2 damaged collectors on the move
	var n: int = 0
	var sx: int = 0
	var sy: int = 0
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or (t.role_mask[r] & (1 << AiTypes.R_COLLECTOR)) == 0:
			continue
		if t.last_dmg[r] > AiTypes.NEVER and ctx.tick - t.last_dmg[r] <= 100 and (t.flags[r] & AiTypes.EF_MOVING) != 0:
			n += 1
			sx += t.x[r]
			sy += t.y[r]
	if n < 2:
		return _refuse("no collectors fleeing")
	return _best(e.util, sx / n, sy / n)


# ------------------------------------------------------------------------------------------------------- FIELD_BOOST
func _field(ctx: AiContext, e: Entry) -> bool:
	var t: AiEntityTable = ctx.kb.own
	var field_r: int = ctx.tune("powers.field_radius_cells", 8) * Fp.CELL
	var best_b: int = 0
	var bpx: int = 0
	var bpy: int = 0
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or (t.role_mask[r] & (1 << AiTypes.R_COMMAND_PROVIDER)) == 0 or t.hp[r] <= 0:
			continue
		var v_in: int = 0
		var v_out: int = 0
		var n_in: int = 0
		var n_out: int = 0
		for i: int in un:
			if (u_sel[i] & SEL_UNMANNED) == 0 or u_eng[i] == 0:
				continue
			var d2: int = (u_x[i] - t.x[r]) * (u_x[i] - t.x[r]) + (u_y[i] - t.y[r]) * (u_y[i] - t.y[r])
			if d2 <= field_r * field_r:
				v_in += u_v[i]
				n_in += 1
			elif d2 <= (field_r + 3 * Fp.CELL) * (field_r + 3 * Fp.CELL):
				v_out += u_v[i]
				n_out += 1
		var b: int = 0
		if e.has("reach"):
			if n_out >= 4:
				b = v_out * 26 / 256
		elif n_in >= 4:
			b = v_in * e.eff / 256 * 15 / 20  # spec: V(in field) x 26 >> 8 x 15 / 20
		if b > best_b:
			best_b = b
			bpx = t.x[r]
			bpy = t.y[r]
	if best_b <= 0:
		return _refuse("no engaged unmanned group at a provider")
	return _best(best_b, bpx, bpy)
