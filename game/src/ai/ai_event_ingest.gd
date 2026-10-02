class_name AiEventIngest
extends RefCounted
## Slot 0: change detection (ai.md 5.3.2). The thinker receives no event feed, so every AI-internal event record is DERIVED by
## diffing snapshots of the state read through AiWorldView: own spawn / loss / damage, unseen hits, enemy seen / gone, enemy
## artillery fire, power / income / research / construction polls, defeated players, superweapon warnings. Records are int
## arrays [code, a, b, c, d, e] (AiTypes.Ev). ALERT records pass through the human-reaction queue (ready after
## `diff.reaction_delay_ticks`, delivered at the first think at or after that tick); STATE records are delivered at once.
## Delivered records are appended to `kb.events` (cleared at the start of every ingest run); the tables of AiKnowledge are
## updated as a side effect. Work is cursor based and budgeted: an exhausted budget just resumes at the next think.

const UNIT_REFRESH: int = 10
const STRUCT_REFRESH: int = 40
const ENEMY_UNIT_DROP: int = 100
const UNSEEN_RADIUS: int = 10 * Fp.CELL
const ARTY_WINDOW: int = 160
const CAMO_WINDOW: int = 200
const CAMO_COUNT: int = 3
const CAMO_RADIUS: int = 6 * Fp.CELL

var _pending: Array[PackedInt32Array] = []  ## alert records [ready_tick, code, a, b, c, d, e]
var _row: PackedInt32Array = PackedInt32Array()
var _tmp: PackedInt32Array = PackedInt32Array()
var _sweep_ids: PackedInt32Array = PackedInt32Array()
var _sweep_pos: int = 0
var _sweep_active: bool = false
var _prev_sweep: Dictionary = {}  ## enemy id -> def, previous complete sweep
var _cur_sweep: Dictionary = {}
var _own_cursor: int = 0
var _unseen: PackedInt32Array = PackedInt32Array()  ## [x, y, tick] * n, recent unseen hits
var _arty_reported: Dictionary = {}
var _last_shortage: bool = false
var _last_research: int = -1
var _last_cstate: int = 0
var _alive_flags: PackedByteArray = PackedByteArray()
var _warn_seen: Dictionary = {}
var _income_tick: int = 0
var records_total: int = 0


## Silent priming at bootstrap: existing own entities become rows without events; player liveness is snapshotted.
func setup(ctx: AiContext) -> void:
	var v: AiWorldView = ctx.view
	for id: int in v.own_ids():
		_spawn(ctx, id, false)
	_alive_flags.resize(v.player_slots())
	for p: int in v.player_slots():
		_alive_flags[p] = 1 if v.player_alive(p) else 0
	_last_shortage = v.power_shortage()
	_last_research = v.research_active()
	var cs: PackedInt32Array = PackedInt32Array()
	v.construction_state(cs)
	_last_cstate = cs[0]
	_income_tick = ctx.tick


func step(ctx: AiContext, budget: AiBudget) -> void:
	var kb: AiKnowledge = ctx.kb
	kb.events.clear()
	kb.now = ctx.tick
	kb.route.tick_hint = ctx.tick
	_deliver(ctx.tick, kb)
	_own_membership(ctx, budget)
	_own_refresh(ctx, budget)
	_enemy_sweep(ctx, budget)
	_polls(ctx, budget)
	_deliver(ctx.tick, kb)


# ----------------------------------------------------------------------------------------------- emit
func _state(kb: AiKnowledge, code: int, a: int, b: int = 0, c: int = 0, d: int = 0, e: int = 0) -> void:
	kb.events.append(PackedInt32Array([code, a, b, c, d, e]))
	records_total += 1


func _alert(ctx: AiContext, code: int, a: int, b: int = 0, c: int = 0, d: int = 0, e: int = 0) -> void:
	_pending.append(PackedInt32Array([ctx.tick + ctx.diff.reaction_delay_ticks, code, a, b, c, d, e]))


func _deliver(tick: int, kb: AiKnowledge) -> void:
	var keep: Array[PackedInt32Array] = []
	for rec: PackedInt32Array in _pending:
		if rec[0] <= tick:
			kb.events.append(rec.slice(1))
			records_total += 1
		else:
			keep.append(rec)
	_pending = keep


func pending_alerts() -> int:
	return _pending.size()


# ---------------------------------------------------------------------------------------- own entities
func _spawn(ctx: AiContext, id: int, emit: bool) -> void:
	var v: AiWorldView = ctx.view
	if not v.read_row(id, _row):
		return
	var t: AiEntityTable = ctx.kb.own
	var r: int = t.upsert(id)
	_fill_own(ctx, t, r, _row)
	t.refreshed[r] = ctx.tick
	if emit:
		_state(ctx.kb, AiTypes.Ev.OWN_SPAWNED, id, t.def[r], t.x[r], t.y[r], t.paid[r])


func _fill_own(ctx: AiContext, t: AiEntityTable, r: int, row: PackedInt32Array) -> void:
	t.def[r] = row[AiTypes.ROW_DEF]
	t.owner[r] = row[AiTypes.ROW_OWNER]
	t.kind[r] = row[AiTypes.ROW_KIND]
	t.x[r] = row[AiTypes.ROW_X]
	t.y[r] = row[AiTypes.ROW_Y]
	t.hp[r] = row[AiTypes.ROW_HP]
	t.hp_max[r] = row[AiTypes.ROW_HP_MAX]
	t.flags[r] = row[AiTypes.ROW_FLAGS]
	t.order[r] = row[AiTypes.ROW_ORDER]
	t.paid[r] = row[AiTypes.ROW_PAID]
	var prof: AiUnitProfile = null
	if row[AiTypes.ROW_KIND] == AiTypes.KIND_UNIT:
		prof = ctx.unit_profile(row[AiTypes.ROW_DEF])
	elif row[AiTypes.ROW_KIND] == AiTypes.KIND_STRUCTURE:
		prof = ctx.struct_profile(row[AiTypes.ROW_DEF])
	t.role_mask[r] = prof.role_mask if prof != null else 0


func _own_membership(ctx: AiContext, budget: AiBudget) -> void:
	var v: AiWorldView = ctx.view
	var t: AiEntityTable = ctx.kb.own
	var ids: PackedInt32Array = v.own_ids()
	budget.spend(1 + ids.size() / 8)
	for id: int in ids:
		if not t.has(id):
			budget.spend(3)
			_spawn(ctx, id, true)
	if t.count > ids.size():
		for r: int in range(t.count - 1, -1, -1):
			var id2: int = t.eid[r]
			if not v.alive(id2):
				_state(ctx.kb, AiTypes.Ev.OWN_LOST, id2, t.def[r], t.x[r], t.y[r], t.paid[r])
				t.remove(id2)
				budget.spend(1)


func _own_refresh(ctx: AiContext, budget: AiBudget) -> void:
	var v: AiWorldView = ctx.view
	var t: AiEntityTable = ctx.kb.own
	if t.count == 0:
		return
	var steps: int = mini(t.count, (t.count * ctx.dt + UNIT_REFRESH - 1) / UNIT_REFRESH)
	for _i: int in steps:
		if _own_cursor >= t.count:
			_own_cursor = 0
		var r: int = _own_cursor
		_own_cursor += 1
		var age: int = ctx.tick - t.refreshed[r]
		if age < (STRUCT_REFRESH if t.kind[r] == AiTypes.KIND_STRUCTURE else UNIT_REFRESH):
			continue
		if not budget.spend(3):
			return
		if not v.read_row(t.eid[r], _row):
			continue  # gone: the membership pass reports the loss
		var old_hp: int = t.hp[r]
		_fill_own(ctx, t, r, _row)
		t.refreshed[r] = ctx.tick
		var dhp: int = old_hp - t.hp[r]
		if dhp > 0:
			t.last_dmg[r] = ctx.tick
			_alert(ctx, AiTypes.Ev.OWN_DAMAGED, t.eid[r], dhp, _row[AiTypes.ROW_SINCE_COMBAT])
			_on_damage(ctx, t, r, budget)


## Attributes a hit: an enemy nearby => hostile mark of its owner; nobody in sight => UNSEEN_HIT (camouflage alert logic).
func _on_damage(ctx: AiContext, t: AiEntityTable, r: int, budget: AiBudget) -> void:
	budget.spend(5)
	var n: int = ctx.view.enemies_in_circle(t.x[r], t.y[r], UNSEEN_RADIUS, _tmp)
	if n > 0:
		ctx.kb.note_hostile(ctx.view.e_owner(_tmp[0]), ctx.tick)
		return
	_alert(ctx, AiTypes.Ev.UNSEEN_HIT, t.x[r], t.y[r])
	_unseen.append(t.x[r])
	_unseen.append(t.y[r])
	_unseen.append(ctx.tick)
	# prune the window and look for >= CAMO_COUNT hits inside CAMO_RADIUS of this one
	var kept: PackedInt32Array = PackedInt32Array()
	var near: int = 0
	for i: int in _unseen.size() / 3:
		if ctx.tick - _unseen[3 * i + 2] > CAMO_WINDOW:
			continue
		kept.append_array(_unseen.slice(3 * i, 3 * i + 3))
		var dx: int = _unseen[3 * i] - t.x[r]
		var dy: int = _unseen[3 * i + 1] - t.y[r]
		if dx * dx + dy * dy <= CAMO_RADIUS * CAMO_RADIUS:
			near += 1
	_unseen = kept
	if near >= CAMO_COUNT and ctx.tick - ctx.kb.camo[2] > CAMO_WINDOW:
		ctx.kb.camo[0] = t.x[r]
		ctx.kb.camo[1] = t.y[r]
		ctx.kb.camo[2] = ctx.tick
		_alert(ctx, AiTypes.Ev.CAMO_ALERT, t.x[r], t.y[r])


# ----------------------------------------------------------------------------------------- enemy sweep
func _enemy_sweep(ctx: AiContext, budget: AiBudget) -> void:
	var v: AiWorldView = ctx.view
	var kb: AiKnowledge = ctx.kb
	if not _sweep_active:
		if not budget.spend(2):
			return
		v.visible_enemy_ids(_sweep_ids)
		_sweep_pos = 0
		_cur_sweep.clear()
		_sweep_active = true
	while _sweep_pos < _sweep_ids.size():
		if not budget.spend(3):
			return
		_sweep_one(ctx, _sweep_ids[_sweep_pos])
		_sweep_pos += 1
	_finish_sweep(ctx, budget)
	_sweep_active = false
	kb.sweep_tick = ctx.tick


func _sweep_one(ctx: AiContext, id: int) -> void:
	var v: AiWorldView = ctx.view
	var kb: AiKnowledge = ctx.kb
	if not v.read_row(id, _row):
		return
	var owner: int = _row[AiTypes.ROW_OWNER]
	var def: int = _row[AiTypes.ROW_DEF]
	var x: int = _row[AiTypes.ROW_X]
	var y: int = _row[AiTypes.ROW_Y]
	_cur_sweep[id] = def
	if owner < 0 or owner >= 8:
		return
	if _row[AiTypes.ROW_KIND] == AiTypes.KIND_UNIT:
		var prof: AiUnitProfile = ctx.unit_profile_of(owner, def)
		if prof == null:
			return
		var t: AiEntityTable = kb.enemy_units
		var fresh: bool = not t.has(id)
		var r: int = t.upsert(id)
		var moved: bool = fresh or absi(t.x[r] - x) >= Fp.CELL or absi(t.y[r] - y) >= Fp.CELL
		if moved:
			t.last_moved[r] = ctx.tick
		t.def[r] = def
		t.owner[r] = owner
		t.kind[r] = AiTypes.KIND_UNIT
		t.x[r] = x
		t.y[r] = y
		t.hp[r] = _row[AiTypes.ROW_HP]
		t.hp_max[r] = _row[AiTypes.ROW_HP_MAX]
		t.flags[r] = _row[AiTypes.ROW_FLAGS]
		t.paid[r] = prof.value
		t.role_mask[r] = prof.role_mask
		t.last_seen[r] = ctx.tick
		var decoy: bool = (t.flags[r] & AiTypes.EF_DECOY) != 0
		if fresh and not decoy:
			kb.profiles[owner].observe(prof.category, prof.value, ctx.tick)
		if (t.flags[r] & AiTypes.EF_CAMO) != 0:
			kb.profiles[owner].camo_seen = true
		if prof.power > 0 and not decoy:
			kb.threat.add_sighting(x, y, prof.power)
		if (prof.role_mask & (1 << AiTypes.R_ARTILLERY)) != 0:
			var lf: int = v.e_last_fire(id)
			if lf >= 0 and ctx.tick - lf <= ARTY_WINDOW and int(_arty_reported.get(id, -1)) != lf:
				_arty_reported[id] = lf
				kb.profiles[owner].arty_fired_recent = ctx.tick
				_alert(ctx, AiTypes.Ev.ENEMY_ARTY_FIRED, id, x, y)
	elif _row[AiTypes.ROW_KIND] == AiTypes.KIND_STRUCTURE:
		var sp: AiUnitProfile = ctx.struct_profile_of(owner, def)
		var kind: int = ctx.shared.resolver(v.roster_of(owner)).kind_of_structure(def)
		var g: AiGhostTable = kb.ghosts
		var pct: int = _row[AiTypes.ROW_HP] * 100 / maxi(_row[AiTypes.ROW_HP_MAX], 1)
		g.upsert(id, def, owner, x, y, ctx.tick, pct, _row[AiTypes.ROW_FLAGS], kind, sp.value if sp != null else 0)
		if kind == AiTypes.StructKind.HQ:
			g.replace_presumed(owner)
		if kind == AiTypes.StructKind.SUPERWEAPON and kb.profiles[owner].sw_known_tick < 0:
			kb.profiles[owner].sw_known_tick = ctx.tick
		if sp != null and sp.power > 0:
			kb.threat.add_sighting(x, y, sp.power)


func _finish_sweep(ctx: AiContext, budget: AiBudget) -> void:
	var v: AiWorldView = ctx.view
	var kb: AiKnowledge = ctx.kb
	kb.threat.commit(ctx.tick)
	budget.spend(1 + _cur_sweep.size() / 8)
	for id: int in _cur_sweep:
		if not _prev_sweep.has(id):
			var r: int = kb.enemy_units.row(id)
			var gx: int = kb.enemy_units.x[r] if r >= 0 else 0
			var gy: int = kb.enemy_units.y[r] if r >= 0 else 0
			if r < 0:
				var gr: int = kb.ghosts.row(id)
				gx = kb.ghosts.x[gr] if gr >= 0 else 0
				gy = kb.ghosts.y[gr] if gr >= 0 else 0
			_alert(ctx, AiTypes.Ev.ENEMY_SEEN, id, _cur_sweep[id], gx, gy)
	for id2: int in _prev_sweep:
		if _cur_sweep.has(id2):
			continue
		var r2: int = kb.enemy_units.row(id2)
		var gr2: int = kb.ghosts.row(id2)
		var px: int = -1
		var py: int = -1
		if r2 >= 0:
			px = kb.enemy_units.x[r2]
			py = kb.enemy_units.y[r2]
		elif gr2 >= 0:
			px = kb.ghosts.x[gr2]
			py = kb.ghosts.y[gr2]
		if px < 0:
			continue
		# absent while its last cell is visible => presumed dead / destroyed
		if v.cell_visible(px >> Fp.CELL_SHIFT, py >> Fp.CELL_SHIFT) and not v.alive(id2):
			_alert(ctx, AiTypes.Ev.ENEMY_GONE, id2, _prev_sweep[id2], px, py)
			if r2 >= 0:
				kb.enemy_units.remove(id2)
			if gr2 >= 0:
				kb.ghosts.remove(id2)
			_arty_reported.erase(id2)
	# unit rows unseen for ENEMY_UNIT_DROP ticks are forgotten
	var t: AiEntityTable = kb.enemy_units
	for r3: int in range(t.count - 1, -1, -1):
		if ctx.tick - t.last_seen[r3] > ENEMY_UNIT_DROP:
			t.remove(t.eid[r3])
	var swap: Dictionary = _prev_sweep
	_prev_sweep = _cur_sweep
	_cur_sweep = swap
	_cur_sweep.clear()


# ------------------------------------------------------------------------------------------------- polls
func _polls(ctx: AiContext, budget: AiBudget) -> void:
	var v: AiWorldView = ctx.view
	var kb: AiKnowledge = ctx.kb
	if not budget.spend(4):
		return
	var sh: bool = v.power_shortage()
	if sh != _last_shortage:
		_last_shortage = sh
		_state(kb, AiTypes.Ev.POWER_STATE, v.power_supply(), v.power_demand(), 1 if sh else 0)
	if ctx.tick - _income_tick >= 20:
		var before: int = kb.last_income_total
		kb.update_income(v.income_total(), ctx.tick)
		_income_tick = ctx.tick
		if kb.last_income_total != before:
			_state(kb, AiTypes.Ev.INCOME, kb.last_income_total - before, kb.income_per_min)
		kb.collectors_alive = _count_collectors(v)
	var ra: int = v.research_active()
	if _last_research >= 0 and ra != _last_research and v.research_done(_last_research):
		_state(kb, AiTypes.Ev.RESEARCH_DONE, _last_research)
	_last_research = ra
	var cs: PackedInt32Array = PackedInt32Array()
	v.construction_state(cs)
	if cs[0] == 2 and _last_cstate != 2:
		_state(kb, AiTypes.Ev.CONSTRUCTION_READY, cs[3])
	_last_cstate = cs[0]
	for p: int in mini(_alive_flags.size(), v.player_slots()):
		var alive_now: bool = v.player_alive(p)
		if _alive_flags[p] == 1 and not alive_now:
			_state(kb, AiTypes.Ev.PLAYER_DEFEATED, p)
		_alive_flags[p] = 1 if alive_now else 0
	var n: int = v.strategic_warnings(_tmp)
	for i: int in n / 7:
		var key: int = AiCommandBuilder.key2(_tmp[7 * i + 1], _tmp[7 * i + 5])
		if not _warn_seen.has(key):
			_warn_seen[key] = true
			_alert(ctx, AiTypes.Ev.SW_WARNING, _tmp[7 * i], _tmp[7 * i + 1], _tmp[7 * i + 2], _tmp[7 * i + 3], _tmp[7 * i + 4])


func _count_collectors(v: AiWorldView) -> int:
	v.collector_ids(_tmp)
	return _tmp.size()


func state_hash() -> int:
	return AiRng.mix32(records_total * 7 + _pending.size() * 3 + _prev_sweep.size())
